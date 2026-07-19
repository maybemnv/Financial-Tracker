# Enhancement Plan: Correctness, Security, Performance, and Analytics

## Summary

Deliver these improvements in dependency order:

1. Repair the test gate, back up production data, and prepare migration safety.
2. Secure the database (single-owner auth + RLS) and the AI integration.
3. Fix cash/account assignment correctness and Family-support semantics.
4. Make transaction labels auditable and reporting-safe (primary labels +
   lifecycle).
5. Redesign Goals into an editable, history-backed earmarking system.
6. Replace full-ledger loading with paginated and aggregated queries.
7. Slim the Briefing tab and add a separate, mobile-first Analytics tab with a
   hard four-chart cap.
8. Add upcoming obligations, a deterministic cash-flow forecast, quick capture,
   and merchant normalization.
9. Fix installed-PWA resume reliability (browser-agnostic) and complete
   production acceptance.

The app remains a single-owner product. Preserve all existing data and assign
it to the authenticated owner. No budget feature is included. Canonical metric
definitions live in `docs/PRD.md` §4 and are binding on every section below.

## 1. Single-owner authentication and RLS

- Provision one Supabase owner account supporting Google and email magic-link login, configure production callback URLs, then disable public sign-up.
- Add an auth gate that restores persistent sessions, handles OAuth and magic-link callbacks, refreshes expired sessions, and provides sign-out.
- Add `user_id` ownership to all finance, label, snapshot, recurring, rule, goal, invoice, and chat data. Backfill every existing row with the owner UUID before making ownership non-null.
- Replace every `anon_all` policy with owner-only `SELECT`, `INSERT`, `UPDATE`, and soft-delete policies using `auth.uid()` plus a protected owner registry/helper.
- Scope balance, net-worth, analytics, transaction, label, goal, and agent RPCs to the authenticated owner. Anonymous and non-owner requests must fail closed.
- Update unique constraints to include `user_id` where appropriate, including monthly snapshots and label names.
- Follow Supabase's documented [`auth.uid()` RLS model](https://supabase.com/docs/guides/database/postgres/row-level-security) and [persistent Flutter authentication flow](https://supabase.com/docs/guides/getting-started/tutorials/with-flutter).

## 2. Secure Agent Desk

- Keep Agent Desk, but replace direct browser-to-Gemini calls with an authenticated Supabase Edge Function.
- Store `GEMINI_API_KEY` only as a server-side function secret; validate the Supabase JWT and owner status on every request.
- Remove `GEMINI_API_KEY` from `.env`, Flutter assets, Vercel build output, and browser request code.
- Rotate the currently deployed Gemini key because it may already have been exposed in the web bundle.
- Keep the Supabase publishable key in the client; security comes from authenticated RLS, not hiding that key.
- Update the agent system rules so answers use the canonical metrics: Personal Spend vs Family Support vs Total Outflow, and goal allocations as earmarks.

## 3. Cash/account correctness (Defect D1)

The deployed product allowed cash expenses to sit against a bank account, so
the bank ending balance understates and Cash overstates.

Invariants (also in PRD §5.1):

- Every transaction belongs to an explicitly selected account: Cash expenses
  use the Cash account ID, Kotak expenses the Kotak ID, PayPal expenses the
  PayPal ID.
- The application never silently substitutes the default bank account for
  Cash. The account field is always visible in add/edit forms; the last-used
  account may be pre-suggested but stays visible and changeable.
- Balances change only for the account a transaction references. Editing a
  transaction's account reverses the old effect and applies the new one via
  derived balances.
- Existing potentially misassigned rows are **not** guessed or bulk-rewritten.
  Provide a focused review step: list manual bank-account outflows in the
  affected window; the owner reassigns each via the normal audited edit flow.

Acceptance tests:

- Cash debit reduces Cash but not Kotak.
- Kotak debit reduces Kotak but not Cash.
- Editing Cash → Kotak moves the derived effect correctly.
- Internal transfers affect both linked accounts but not net worth.
- All account-filtered ledger and analytics totals reconcile.

## 4. Family-support semantics (Defect D2)

The production label `TRANSFER TO OTHER` represents money sent to the owner's
mother. It is **not** an internal transfer.

- Rename the label to `FAMILY` with an identity-preserving `UPDATE` (same row
  and ID, all joins retained). Never delete-and-recreate. Record a label audit
  event once label auditing (§6) exists.
- These transactions are normal debit outflows from the selected Cash or bank
  account: they reduce that account's balance and net worth and count toward
  Total Outflow.
- They are excluded from Personal Spend and reported separately as **Family
  Support** in Briefing, Analytics, and Agent Desk.
- They must not use the `transfer` type. `transfer` is reserved exclusively
  for movements between owner-held accounts. Add a review step for any legacy
  transfer-typed rows that were actually family payments.
- Reporting mechanism (smallest possible): add
  `labels.exclude_from_personal_spend boolean NOT NULL DEFAULT false`, read
  through the primary-label system. No taxonomy, no policy engine.

## 5. Installed-PWA startup and resume resilience

**Scope note.** The product is a mobile-first **web app / installed PWA**
(add-to-home-screen via Brave), not a native Android or Windows app. On
desktop the owner uses **Brave** directly; on mobile the app is accessed
via **Brave → Add to Home Screen** (installed PWA). Helium (Chromium) and Zen
(Firefox-based) are likely future targets, so all recovery logic must be
**browser-agnostic** — never hardcoded to one engine or to Android specifically.
Because the app runs as an installed PWA on mobile, resume reliability is
core, not optional: a suspended PWA that loses its WebGL/canvas context must
recover without a blank screen.

Startup and install metadata:

- Add a custom `flutter_bootstrap.js` using [Flutter's supported loader hooks](https://docs.flutter.dev/platform-integration/web/initialization), with a visible HTML loading/error surface so a failed boot never shows a blank page, plus release-aware service-worker initialization.
- Remove the unused external Corbado/passkey script from `index.html`.
- Correct PWA metadata: production name, description, colors, `id`, root `start_url`, root `scope`, and maskable icons — it is an installed PWA, so the manifest matters.

Resume recovery (browser-agnostic):

- Implement a JavaScript/Dart lifecycle handshake:
  - Dart emits ready and post-frame resume acknowledgements.
  - JavaScript listens to `visibilitychange`, `pageshow`, and WebGL context-loss events.
  - After returning from a suspension, wait three seconds for a rendered-frame acknowledgement.
  - If no acknowledgement arrives, reload once with a release cache-buster.
  - If recovery fails again, stop the loop and show an HTML recovery message and reload button.
- On a healthy resume, refresh the auth session, reconnect stale realtime channels, and revalidate visible data without reloading the application.
- Persist transaction-form drafts, selected labels, active tab, and analytics filters locally with a 24-hour TTL. Clear them on successful save, cancel, or sign-out.
- Keep Flutter's default renderer initially; add a diagnostic renderer query parameter rather than forcing a heavier renderer globally.

## 6. Primary labels and unified auditing (Defect D3)

- Add nullable `transactions.primary_label_id`.
- For new or edited debit/outflow expenses, require exactly one primary label. Credits, transfers, and investments may have contextual labels without a spending primary.
- Preserve all existing label relationships:
  - One-label expenses automatically receive that label as primary.
  - Unlabeled expenses report as `Unlabeled`.
  - Multi-label expenses remain unresolved and report as `Needs primary label` until reviewed.
- Add a review queue filtered to unresolved multi-label expenses.
- Replace the current separate transaction-update and label-replacement calls with one transactional RPC that:
  - Locks and reads the existing transaction and labels.
  - Validates the primary label is among the attached labels.
  - Updates transaction fields and label relationships atomically.
  - Appends one audit entry containing old/new fields, label IDs, names, colors, and primary status.
  - Rolls back everything if any step fails.
- Reporting counts the full amount once under the primary label. Context labels remain usable for search and analysis filters but never duplicate or split spending. This removes the current even-split behavior in `DashboardAnalytics` and the `get_label_breakdown` agent tool.

## 7. Label lifecycle

- Add label lifecycle state: `active`, `archived`, `merged`, or `deleted`, plus `merged_into_id` and update timestamps.
- Rename labels case-insensitively while preserving identity and recording a label audit event.
- Archive labels by hiding them from new assignments while preserving historical reporting.
- Merge labels through one RPC that moves contextual relationships and primary references, resolves duplicate joins, records affected transaction history, and marks the source as merged.
- Permit delete only for an unused label with no transaction, primary-label, rule, recurring-item, or merge references. Implement it as a soft delete.
- For referenced labels, present Archive and Merge instead of Delete.
- The `exclude_from_personal_spend` flag survives rename and archive; a merge target keeps its own flag (surface a confirmation when source and target flags differ).

## 8. Goals redesign (Defect D6)

Goal allocation is **earmarking, not money movement**: it changes no account
balance and no net worth.

- Capabilities: create; edit name/target/optional target date/type where
  valid; add funds; remove or correct an allocation; reallocate between goals;
  status `active` / `paused` / `completed` / `archived` with restore;
  soft-delete only when safe (no history), otherwise archive; Emergency Fund
  pinned by type; auto-completed state at target; compact detail view with
  edit actions and allocation history.
- Guards: allocated total never negative; warn before reducing target below
  allocated; overfunding needs explicit confirmation.
- Data model: one `goal_contributions` table (`id`, `goal_id`, `amount`
  positive or negative, `note`, `created_at`, `user_id`). Adopted because the
  current direct mutation of `allocated_amount` loses history and races.
  Derive the allocated total from contributions, or maintain it through one
  transactional RPC — stored total and history must never drift. `goals` gains
  `status`, `target_date`, `updated_at`.
- Estimated completion only with sufficient real history (≥ 3 contributions in
  ≥ 2 distinct months); otherwise show "not enough history".
- Agent Desk can explain goal progress and affordability; it cannot modify
  allocations.
- Non-goals: multiple goal tables, recurring-goal rules, automatic bank
  transfers, event-sourcing.

## 9. Data and rendering performance

- Replace the transaction provider's full-table query with cursor pagination in pages of 50, using effective transaction date plus ID as a stable cursor.
- Move ledger filtering and searching to Supabase instead of filtering an ever-growing in-memory list.
- Replace full reloads on every realtime event with row-level patching or debounced targeted invalidation.
- Add owner-scoped aggregate RPCs:
  - `get_briefing_summary(month)` — returns the canonical metrics (Income, Total Outflow, Personal Spend, Family Support, Net Cash Surplus, savings rate) plus account balances and unresolved-label counts.
  - `get_analytics(period, filters)` — typed bundle for the four Analytics charts.
  - `get_account_balances()` — one batch call.
- Use live rows for the current month and snapshots for completed historical months. Never recalculate the entire ledger merely to render a chart.
- Add monthly account-balance snapshots for future per-account history. Do not fabricate historical account values that cannot be derived reliably.
- Lazily initialize app tabs and chart sections. An unvisited tab must not fetch data or construct charts.
- Memoize pure analytics transformations and rebuild only when their input dataset or filters change.

## 10. Briefing and Analytics

### Briefing tab (lightweight)

Numbers only, no large charts: Income, Total Outflow, Personal Spend, Family
Support, Net Cash Surplus, current Net Worth, account balances, upcoming
obligations, latest transaction timestamp, one concise status message. The
existing Briefing line/bar/pie charts are removed or relocated to Analytics.

### Analytics tab — hard four-chart cap

Mobile-friendly, default 12-month range, selectors 1M / 3M / 6M / 12M / YTD /
All where meaningful. Render only the active section.

1. **Monthly Cash Flow** — grouped vertical bars, Income vs Total Outflow by
   month. Bar tap opens the ledger filtered to that month and direction.
   Personal Spend and Family Support appear as supporting KPIs or a toggle,
   not extra permanent bar series.
2. **Spending by Primary Label** — sorted horizontal bars (replacing the pie)
   so label names and exact ₹ values are readable on mobile. Default data:
   Personal Spend only; visible toggle to include excluded outflows (Family).
   Top seven labels + `Other`. Label tap opens the filtered ledger. Contextual
   labels never double-count.
3. **Daily Cumulative Personal Spend** — two lines: current month and previous
   month aligned by day number. No artificial budget/target line. Partial
   months clearly handled. Point tap opens that day's ledger.
4. **Net Worth History** — line from real snapshots plus the current derived
   value; never fabricated per-account history. Current value marked. Point
   tap shows that month and available snapshot data.

Non-chart components: account balances (cards/table), top merchants (ranked
list), goal progress (bars/cards), recurring obligations (ordered list),
Family Support KPI with drill-down, optional goal-contribution sparkline where
real history exists.

Chart rules: existing `fl_chart` only; editorial/brutalist visual language —
square corners, strong rules, warm paper background, readable labels; no
gradients, glow, 3D, gauges, or decorative charts; one value axis per chart;
currency values and clear units always; accessible summaries, tabular
alternative, and empty states; every chart supports ledger drill-down; do not
add a chart merely because data exists.

## 11. Daily-usefulness features

### Upcoming obligations

Reuse `recurring_expenses` and `recurring_income` — no separate subscriptions
system. Show name, expected amount, expected date, account if known, days
remaining, and status (upcoming / expected today / overdue / confirmed).

### Deterministic cash-flow forecast

30-day projection from current liquid balances, known recurring inflows and
outflows, recent average Personal Spend, and explicit upcoming obligations.
Output: projected liquid balance, obligations due before the next expected
inflow, estimated available amount until then, and the assumptions used. Not
an authoritative prediction; no ML; investment balances are not spendable;
earmarked goal allocations are context, not departed money.

### Quick capture

One-field input (`250 biryani cash`, `500 sent to mummy kotak`) parsed into a
reviewable draft: amount, direction/type, account, merchant/note, primary
label, date/time. The user must confirm before saving; the save goes through
the standard audited write path. Deterministic parsing and existing rules
first; Gemini only as fallback and still only producing a draft.

### Merchant normalization

Minimal `merchant_aliases` table (`match_pattern`, `canonical_name`) mapping
payment-string variants to one display merchant at read time. Raw values are
preserved for audit. Improves top-merchant analytics and filtering; no
merchant-intelligence system.

## 12. Later improvements

- **Monthly digest** — concise month-in-review (Income, Total Outflow,
  Personal Spend, Family Support, savings change, largest labels/merchants,
  goal progress, significant recurring charges) generated from the same
  aggregate RPCs and definitions as the UI. No separate analytics pipeline.
- **Automated backup** — recurring Supabase backup/export documented as an
  operational runbook task after the security migration. Not a product screen.

## 13. Future backlog: Google Pay screenshot import (deferred)

Reviewed-import workflow only; outside all committed phases; no OCR
implementation now; no attachment tables added in the current phase. Full
constraints and workflow in `docs/PRD.md` §12.

## Interfaces and data model

- Extend `Transaction` with `primaryLabelId` and explicit unresolved-primary status.
- Extend `TransactionLabel` with lifecycle, merge metadata, and `excludeFromPersonalSpend`.
- Extend `Goal` with `status`, `targetDate`; add a `GoalContribution` model.
- Add typed `AnalyticsQuery`, `AnalyticsBundle`, and chart-point DTOs rather than passing loosely structured maps through widgets.
- Add owner-scoped tables or fields for `app_owner`, label audit records, `goal_contributions`, `merchant_aliases`, and account-balance snapshots.
- Add transactional RPCs for transaction edits, goal contributions, label merge, label archive/delete, briefing aggregates, analytics aggregates, and batch account balances.
- Update architecture, database, API, PRD, TODO, environment, deployment, and security documentation alongside the implementation.

## Test and acceptance plan

- First fix the existing test compilation failure caused by the unsupported `find.byDisplayValue` finder so validation can become a reliable gate.
- Database tests:
  - Anonymous and non-owner users cannot read or mutate any row or call privileged RPCs.
  - The owner can perform supported CRUD operations.
  - Existing rows are preserved and assigned to the owner.
  - Cross-owner foreign-key relationships are rejected.
- Accounting tests (PRD §5): cash/bank isolation, account-edit reversal, transfer neutrality, account-filtered reconciliation.
- Family-support tests: outflow + net-worth reduction, exclusion from Personal Spend, `Total Outflow = Personal Spend + Family Support`, identity-preserving rename.
- Transaction tests:
  - Field and label changes create one complete old/new audit entry.
  - Failed label writes roll back transaction changes.
  - Each expense is counted once under its primary label.
  - Ambiguous legacy rows appear under `Needs primary label`.
- Label tests cover case-insensitive rename conflicts, archive visibility, merge deduplication, primary-label migration, delete safeguards, and flag survival across rename/archive/merge.
- Goal tests: contribution history reconciles with allocated totals; negative adjustments cannot drive totals negative; reallocation is atomic; completion state and estimate gating behave; allocation changes no account balance.
- Analytics tests verify cash-flow totals, snapshot/live-month boundaries, drill-down filters, `Other` aggregation, partial-month cumulative lines, and no double-counting from context labels.
- Widget tests cover authentication states, account selection visibility, primary-label selection, review queue, responsive charts, accessible summaries, and 360-pixel-wide layouts.
- Installed-PWA resume acceptance (test on mobile via Brave → Add to Home Screen first, since it is the primary access mode; re-verify in any additional browser adopted, e.g. Helium or Zen):
  - Install as a home-screen PWA via Brave; perform at least ten rapid app switches plus 5-minute and 30-minute suspensions.
  - Test online, temporarily offline, and expired-session recovery.
  - Trigger or simulate WebGL context loss; verify one bounded recovery attempt followed by the manual recovery screen if needed.
  - No blank screen; healthy resume within two seconds, watchdog recovery within six seconds, no reload loop, and no lost transaction draft.
- Performance targets:
  - Warm launch interactive within three seconds on a mid-range mobile PWA.
  - Cold 4G launch interactive within six seconds.
  - Briefing aggregate request p95 below 500 ms under the expected personal dataset.
  - Ledger first page displayed without downloading the full history.
- Required gates: `flutter analyze`, `flutter test`, release web build, PWA install test, and manual Supabase RLS verification.

## Rollout order

| Phase | Scope |
|---|---|
| 0 | Current deployed baseline and known defects (D1–D8, PRD §1) |
| 1 | Tests, backup, and migration safety |
| 2 | Owner authentication, ownership, RLS, and scoped RPCs |
| 3 | Secure Gemini Edge Function and key rotation |
| 4 | Cash/account correctness and Family-support semantics |
| 5 | Primary-label auditing and label lifecycle |
| 6 | Goals redesign |
| 7 | Pagination, aggregate RPCs, and performance |
| 8 | Briefing slim-down and the four-chart Analytics redesign |
| 9 | Recurring obligations and deterministic cash-flow forecast |
| 10 | Quick capture and merchant normalization |
| 11 | Installed-PWA resume resilience and production acceptance |

Ordering notes:

- Phases 4–6 run after security (2–3) so corrective edits are made once, under
  owner-scoped audited RPCs, not twice.
- The installed-PWA resume-resilience work (§5) moved from early in the old plan
  to Phase 11: nothing in phases 4–10 depends on it, and the acceptance pass at
  the end must retest resume behavior anyway. Its draft-persistence tasks are
  referenced by earlier UI work but only become acceptance-blocking in 11.
- No native Android/Windows app is in scope; the app is used via Brave browser
  on desktop and as a Brave home-screen PWA on mobile. Recovery logic stays
  browser-agnostic. Google Pay screenshot import stays outside all committed
  phases.

## Rollout and assumptions

- Back up/export Supabase data before migration.
- Create the owner account and secure AI function first; then deploy the auth-capable client and owner-scoped migration during a short maintenance window.
- Policies fail closed if owner configuration is missing.
- Clear obsolete service-worker caches after the first secure release and verify the installed PWA receives the new version.
- Record privacy-safe lifecycle, initialization, recovery, and query timings without storing finance values in diagnostics.
- The app has exactly one owner; no member management, sharing, registration flow, or organization model is included.
- All current data belongs to that owner and must be preserved.
- Budgets and rollover logic are explicitly out of scope.
- Existing soft-delete and derived-balance safety rules remain mandatory.
- No new state-management system, chart library, backend server, microservice, or generalized analytics framework.
