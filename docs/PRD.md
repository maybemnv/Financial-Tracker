# PRD: Personal Finance Tracker (v2)

Single-owner personal finance system. Flutter Web app deployed on Vercel, backed
by Supabase (Postgres + Realtime), state managed with Riverpod, charts with
`fl_chart`, and a Gemini-powered read-only finance agent.

> **Document status.** This v2 PRD supersedes the original day-0 build plan
> (Android + Windows + SMS capture + Claude agent). That plan shipped its MVP and
> is preserved in git history. Claims that no longer match the deployed product —
> native platforms, SMS auto-capture, Claude API, budget envelopes, "no auth
> forever" — are removed here, not carried forward.

---

## 1. Current product (verified against code)

What exists and works in production today:

- **Ledger** — manual entry of debits, credits, double-entry transfers, and
  investment moves; every row belongs to an account; soft delete; immutable
  `edit_history`; user-set `transacted_at` with `created_at` fallback;
  edit screen for debit/credit rows with pre-filled form.
- **Accounts** — Cash, bank (Kotak/PSB), PayPal, investment accounts. Balances
  are derived by `fn_account_balance()` from `opening_balance` + transaction
  legs; net worth by `fn_net_worth()`. No stored balance column.
- **Labels** — GitHub-style many-to-many labels with user-chosen colors
  (create only; no rename/archive/merge/delete yet).
- **Briefing (dashboard)** — month selector, hero summary, metric grid, account
  balances, six-month trend line chart, daily bar chart, label pie chart, goal
  trackers, action items — all computed client-side from the full ledger.
- **Goals** — create goal, allocate positive amounts, soft delete. Emergency
  Fund pinned by `type`, funded % progress bars.
- **Invoices** — freelance invoice drawer with USD/PayPal/bank receipt tracking.
- **Agent Desk** — Gemini 2.5 Flash with 10 read-only tools querying Supabase;
  chat history persisted in `chat_sessions`.
- **Recurring items** — `recurring_expenses` and `recurring_income` tables used
  as agent context (no UI surfacing yet).
- **Monthly snapshots** — previous-month aggregate written client-side on first
  open of a new month.

Known defects (fixed by this PRD's roadmap):

| # | Defect | Consequence |
|---|---|---|
| D1 | Cash expenses recorded against a bank account (data-level; the form never enforced deliberate account choice historically) | Bank balances understate, Cash overstates; account-filtered reports wrong |
| D2 | The label "TRANSFER TO OTHER" holds money sent to family but reads as an internal transfer | Family support is invisible in reporting and conflated with account transfers |
| D3 | Multi-label expenses are split evenly across labels (`DashboardAnalytics`, `get_label_breakdown`) | Category totals do not reconcile; per-label numbers are fabricated fractions |
| D4 | Full-ledger `SELECT` with no pagination; full reload on every Realtime event | Slow loads that get worse every month |
| D5 | `anon_all` RLS on every table; Gemini key shipped in the browser bundle | Anyone with the URL + anon key can read/write all finance data |
| D6 | Goal allocation is an unaudited read-then-write on `allocated_amount` | No history, no corrections, race-prone |
| D7 | Widget test uses `find.byDisplayValue`, breaking the test gate | `flutter test` cannot act as a release gate |
| D8 | Installed PWA resume (mobile Brave shortcut) can blank-screen when the browser suspends it and the WebGL context is lost | App unusable after a switch until manual reload |

---

## 2. Tech stack (locked)

| Layer | Choice | Status |
|---|---|---|
| Frontend | Flutter Web (single codebase, mobile-first) | Locked |
| Deployment | Vercel (`vercel-build.sh` → `build/web`) | Locked |
| Backend/DB | Supabase — Postgres, Realtime, RPCs; **planned:** Auth + one Edge Function | Locked |
| State | Riverpod (StateNotifier) | Locked — no second state system |
| Charts | `fl_chart` | Locked — no second chart library |
| AI | Gemini 2.5 Flash (currently browser-side; moving server-side behind a Supabase Edge Function) | Locked |
| Design | Brutal Newsprint Workbench (`docs/design.md`) | Locked |

No new backend server, microservice, event-sourcing system, or generalized
analytics framework. The only new infrastructure permitted is the already
planned Supabase Edge Function.

---

## 3. Hard product boundaries (locked)

- **Single owner only.** No organization, member, sharing, household, or
  multi-user model. Authentication exists to protect one person's data, not to
  add users.
- **No budgets.** No envelopes, rollover budgets, or budget alerts. Anomaly
  awareness comes from the user's own baseline, not targets.
- **AI reads, never moves money.** AI may read, classify, summarize, forecast,
  and answer. It must never create, modify, delete, allocate, or move money
  without explicit user review and confirmation.
- **Soft delete everywhere.** Financial records are never physically deleted.
- **Balances are derived.** `opening_balance` + transactions. No mutable
  balance column, ever.
- **Transfers are two linked legs** (`transfer_group_id`) and do not change net
  worth. The `transfer` type is reserved **exclusively** for money moving
  between accounts the owner holds.
- **Investments are asset movements**, not personal spending.
- **All existing production data is preserved** through every migration.
- **Web-only, mobile-first UI**, preserving the Brutal Newsprint Workbench
  design system. No native Android or Windows app is in scope. The product is
  used via **Brave browser** on desktop and as a **Brave Add to Home Screen**
  shortcut (installed PWA) on mobile. Helium/Zen are possible future browsers.
  All recovery/resume logic must stay browser-agnostic — never hardcoded to one
  engine or OS.
- **Navigation stays at five primary destinations.** Analytics becomes a tab;
  invoice access moves to an app-bar/drawer action. No further tabs unless the
  Analytics tab genuinely cannot contain a feature.

---

## 4. Canonical financial metrics

These definitions are the single source of truth. The database RPCs, Briefing,
Analytics, exports, and Agent Desk answers must all use them identically.

| # | Metric | Definition |
|---|---|---|
| 1 | **Income** | External inflows classified as earned or received money: `credit` rows (including PayPal payouts/deposits). Excludes transfer and investment inflow legs. |
| 2 | **Total Outflow** | All external `debit` outflows — Personal Spend **plus** Family Support. Excludes transfer and investment legs. |
| 3 | **Personal Spend** | Debit outflows whose primary label is **not** flagged `exclude_from_personal_spend`. Unlabeled and `Needs primary label` expenses count as Personal Spend (visible in their own buckets) until classified. |
| 4 | **Family Support** | Debit outflows whose primary label is `FAMILY` (a label with `exclude_from_personal_spend = true`). Reduces the paying account and net worth; counted in Total Outflow; **never** in Personal Spend. |
| 5 | **Internal Transfer** | Two linked legs between owned accounts. Excluded from income, all spending metrics, and net-worth change. |
| 6 | **Investment Contribution** | `investment` outflow leg from a liquid account into an owned investment account. Excluded from spending and net-worth change. |
| 7 | **Net Cash Surplus** | `Income − Total Outflow`. The default "savings" number everywhere a single figure is shown. |
| 8 | **Personal Savings After Own Spend** | `Income − Personal Spend`. Shown alongside Net Cash Surplus for context only — it is **not** retained money, because Family Support has also left the accounts. UI copy must not present it as money kept. |
| 9 | **Savings Rate** | `Net Cash Surplus / Income × 100` (0 when income is 0). |

Reconciliation invariant: for any filter window,
`Total Outflow = Personal Spend + Family Support`, and the sum of primary-label
buckets (including `Unlabeled` and `Needs primary label`) equals Total Outflow
when excluded labels are shown, or Personal Spend when they are hidden.

---

## 5. Accounting correctness requirements

### 5.1 Account integrity (fixes D1)

Invariant set:

- Every transaction belongs to an explicitly selected account. A cash expense
  uses the Cash account ID; a Kotak expense uses the Kotak account ID; a PayPal
  expense uses the PayPal account ID.
- The application must **never** silently substitute a default bank account for
  Cash. The selected account is always visible in the add and edit forms. The
  last-used account may be pre-suggested for convenience, but it stays visible
  and changeable before save.
- A transaction changes the derived balance of exactly one account (its own);
  transfer/investment pairs change exactly the two accounts on their legs.
- Cash spending reduces Cash and net worth. Bank spending reduces only the
  selected bank account and net worth.
- Editing a transaction's account reverses the effect on the old account and
  applies it to the new one — this falls out of derived balances automatically
  and must be covered by tests, not reimplemented.
- **Existing potentially misassigned cash transactions are never silently
  guessed or rewritten.** A focused review step lists candidate rows (manual
  outflows against bank accounts in the affected period); the owner reassigns
  each through the normal audited edit flow.

Acceptance tests:

1. Cash debit reduces Cash, not Kotak.
2. Kotak debit reduces Kotak, not Cash.
3. Editing a debit from Cash → Kotak moves the derived effect completely.
4. Internal transfer changes both linked accounts and leaves net worth unchanged.
5. Account-filtered ledger totals and analytics totals reconcile with
   `fn_account_balance` for every account.

### 5.2 Family support semantics (fixes D2)

- Rename the production label `TRANSFER TO OTHER` → `FAMILY` via an
  identity-preserving `UPDATE labels SET name = 'FAMILY'` (same row, same `id`,
  all `transaction_labels` joins untouched). Never delete-and-recreate.
- Family payments are **normal debit outflows** from the selected Cash or bank
  account: they reduce that account, reduce net worth, and count toward Total
  Outflow. They must **not** use the `transfer` type.
- They are excluded from Personal Spend and reported separately as **Family
  Support** in Briefing, Analytics, and Agent Desk answers.
- Reporting mechanism (smallest possible): one flag on labels —
  `labels.exclude_from_personal_spend boolean NOT NULL DEFAULT false` — read
  through the primary-label system. No category taxonomy, no policy engine.

Acceptance tests:

1. A `FAMILY`-labeled debit reduces the paying account and net worth.
2. It appears in Total Outflow and Family Support, never in Personal Spend.
3. `Total Outflow = Personal Spend + Family Support` for any period.
4. The renamed label keeps its ID and all historical transaction joins.
5. Agent Desk distinguishes "spent on myself" from "sent to family."

---

## 6. Goals redesign (fixes D6)

**Accounting rule:** goal allocation is **earmarking, not money movement**.
Allocating ₹5,000 to a goal changes no account balance and no net worth; it
assigns part of already-existing money to a purpose. UI copy must reflect this.

Required capabilities (useful, not bloated):

- Create a goal; edit name; edit target amount; optional target date; edit type
  where valid.
- Add funds; remove/correct an allocation (negative adjustment); reallocate
  earmarked funds from one goal to another (one negative + one positive entry).
- Status: `active`, `paused`, `completed`, `archived`; restore from archive;
  auto-show completed when funded ≥ target; soft-delete only when safe (no
  contribution history), otherwise archive.
- Pin Emergency Fund above custom goals (by `type`, as today).
- Show saved, target, remaining, % funded, and latest allocation.
- Guards: allocated total can never go negative; warn before reducing target
  below the allocated amount; overfunding only after explicit confirmation.
- Compact goal-detail view with edit actions and allocation history.
- Agent Desk context can explain goal progress and affordability but cannot
  modify allocations.

Data model (adopted — it materially improves correctness over mutating
`allocated_amount` directly, which currently loses history and races):

- `goal_contributions`: `id`, `goal_id`, `amount` (positive or negative),
  `note`, `created_at`, `user_id` (after ownership migration). Corrections are
  new negative rows, not edits.
- The allocated total is **derived from contributions** (or maintained by one
  transactional RPC that inserts the contribution and updates the total
  atomically — either way, stored total and history must never drift).
- `goals` gains `status`, `target_date` (nullable), `updated_at`.

Estimated completion appears only when enough real contribution history exists
(≥ 3 contributions across ≥ 2 distinct months); never fabricated from one
allocation.

Non-goals: multiple goal tables, recurring-goal rules, automatic transfers,
generic ledger/event-sourcing framework.

---

## 7. Briefing tab (lightweight — no large charts)

Briefing shows numbers, not visualizations:

- Income, Total Outflow, Personal Spend, Family Support, Net Cash Surplus (all
  for the selected month)
- Current Net Worth
- Account balances
- Upcoming obligations (from recurring items)
- Latest transaction timestamp
- One concise financial status message

The current Briefing line/bar/pie charts move to (or are replaced by) the
Analytics tab. Stat values render as compact metric strips/cards in the
existing newsprint style.

---

## 8. Analytics tab — restrained chart specification

**Hard cap: exactly four primary charts.** Every chart answers a
decision-relevant question and drills into the filtered ledger. Do not add a
chart merely because data exists.

Default range 12 months; selectors 1M, 3M, 6M, 12M, YTD, All where meaningful.

| # | Chart | Form | Spec |
|---|---|---|---|
| 1 | **Monthly Cash Flow** | Grouped vertical bars | Income vs Total Outflow by month. Tap a bar → ledger filtered to that month + direction. Personal Spend and Family Support appear as supporting KPI values or a toggle — never additional permanent bar series. |
| 2 | **Spending by Primary Label** | Sorted **horizontal** bars (replaces the pie) | Default data: Personal Spend only. Visible toggle to include excluded outflows (Family). Top 7 labels + `Other`. Label names and exact ₹ readable on mobile. Tap a label → filtered ledger. Contextual labels never double-count. |
| 3 | **Daily Cumulative Personal Spend** | Two lines | Current month vs previous month aligned by day number. Partial current month clearly handled (line stops at today). No artificial budget/target line. Tap a point → that day's ledger. |
| 4 | **Net Worth History** | Line | Real monthly snapshots + current derived value only — never fabricated historical per-account balances. Current value clearly marked. Tap a point → that month's snapshot detail. |

Non-chart analytical components:

- Current account balances — cards or compact table, not a chart.
- Top merchants — ranked list with values, not a chart.
- Goal progress — progress bars and cards, not pie charts.
- Recurring obligations — ordered list by due date.
- Family Support — separate KPI with ledger drill-down.
- Optional tiny goal-contribution sparkline only where real history exists.

Chart rules (all four charts):

- `fl_chart` only; Brutal Newsprint visual language — square corners, strong
  rules, warm paper background, readable labels.
- No gradients, glow, 3D, gauges, or decorative charts. One value axis per
  chart — never dual-axis.
- Always show currency values and clear axis units; tooltips with full values.
- Accessible text summary and tabular alternative for every chart; empty
  states; render only the active analytics section.

---

## 9. Security, performance, reliability (summary)

Fully specified in `docs/enhancement.md`; the requirements are:

- **Auth + RLS:** one Supabase owner account (Google + magic link), `user_id`
  ownership on all tables, owner-only policies replacing `anon_all`,
  fail-closed RPCs. (D5)
- **Server-side AI:** Gemini behind an authenticated Supabase Edge Function;
  key removed from the bundle and rotated. (D5)
- **Primary labels + audit:** exactly one primary label per new/edited expense;
  one transactional RPC per edit; one audit entry per logical change. (D3)
- **Performance:** cursor pagination (50/page), server-side filtering,
  aggregate RPCs, snapshot/live-month split, lazy tabs. (D4)
- **Installed-PWA resume resilience:** bootstrap surface (no blank screen),
  browser-agnostic JS/Dart lifecycle handshake with bounded WebGL-context-loss
  recovery, session/realtime refresh on resume, and draft persistence. (D8)

Performance targets: warm launch interactive < 3 s on a mid-range mobile PWA;
cold 4G < 6 s; Briefing aggregate p95 < 500 ms; ledger first paint downloads
one page.

---

## 10. Roadmap (dependency-ordered)

| Phase | Scope | Priority | Status (this branch) |
|---|---|---|---|
| 0 | Current deployed baseline + known defects (D1–D8) recorded | — | done |
| 1 | Test gate repair, backup, migration safety | Must | done |
| 2 | Owner authentication, ownership backfill, RLS, scoped RPCs | Must | done |
| 3 | Secure Gemini Edge Function + key rotation | Must | done |
| 4 | Cash/account correctness + Family-support semantics | Must | done |
| 5 | Primary-label auditing + label lifecycle | Must | done |
| 6 | Goals redesign | Must | done |
| 7 | Pagination, aggregate RPCs, snapshots, performance | Must | done |
| 8 | Briefing slim-down + four-chart Analytics tab | Must | done |
| 9 | Upcoming obligations + deterministic cash-flow forecast | Should | done |
| 10 | Quick capture + merchant normalization | Should | done |
| 11 | Installed-PWA resume resilience (browser-agnostic) + production acceptance | Must | code complete; 11.6/11.9 acceptance are on-device owner steps |
| — | Monthly digest, automated backup | Later | not started |
| — | Google Pay screenshot import | Future backlog | not started |

**Defects:** D1 (code done; historical reassignment is a live owner step),
D2/D3/D5/D6/D7 done, D4 fixed in Phase 7, D8 addressed in Phase 11 (bounded
WebGL-loss recovery) pending on-device confirmation.

The detailed checklist is `docs/TODO.md`.

---

## 11. Feature additions

Each feature states: user problem, minimal data-model change, reused
capability, non-goals, acceptance, and priority.

### 11.1 Upcoming obligations (Phase 9 — Should)

- **Problem:** recurring data exists but nothing answers "what's about to hit?"
- **Data model:** none new. Reuses `recurring_expenses` + `recurring_income`
  (optional additive columns only if needed: e.g. `account_id`, `is_paused`).
- **Shows:** name, expected amount, expected date, account if known, days
  remaining, status (upcoming / expected today / overdue / confirmed).
- **Non-goals:** no separate subscriptions system — a subscription is a
  filtered recurring expense with optional metadata; no reminders/notification
  infrastructure.
- **Acceptance:** obligations list matches recurring rows; statuses correct
  around due-date boundaries; confirmed items link to the matching transaction.

### 11.2 Deterministic cash-flow forecast (Phase 9 — Should)

- **Problem:** "how much is actually safe to spend before the next inflow?"
- **Inputs:** current liquid balances, known recurring inflows/outflows, recent
  average Personal Spend, explicit upcoming obligations.
- **Output:** 30-day projected liquid balance, obligations due before next
  expected inflow, estimated available amount until next inflow, and the
  assumptions used — presented as an estimate, never authoritative.
- **Data model:** none. Pure computation over existing data.
- **Non-goals:** no ML; investment-account value is not spendable cash;
  earmarked goal allocations are **not** treated as money that left an account
  (they are context, shown as "earmarked" alongside the projection).
- **Acceptance:** projection reproducible by hand from its stated inputs;
  excludes investment balances; states assumptions.

### 11.3 Quick capture (Phase 10 — Should)

- **Problem:** entry friction is the biggest threat to data completeness.
- **Behavior:** one-field input — `250 biryani cash`, `500 sent to mummy kotak`
  — parsed into a reviewable draft (amount, direction/type, account, merchant/
  note, primary label, date/time). **User confirms before saving**; saving goes
  through the same audited write path as the full form.
- **Parsing:** deterministic rules first (amount token, account-name match,
  label keyword match — reusing the retained Dart parser machinery and label
  data); Gemini only as fallback, and its output is still just a draft.
- **Data model:** none.
- **Non-goals:** no auto-save, no SMS integration, no NLP framework.
- **Acceptance:** the two example utterances parse correctly; ambiguous input
  degrades to a partially-filled draft, never a wrong silent save.

### 11.4 Merchant normalization (Phase 10 — Should)

- **Problem:** `SWIGGY*ORDER8837`-style variants fragment merchant analytics.
- **Data model:** one minimal table `merchant_aliases` (`id`, `match_pattern`,
  `canonical_name`, `user_id`, `created_at`). Raw merchant/VPA values are
  preserved on the transaction for audit; normalization applies at read time.
- **Reuses:** the ranked top-merchants list and ledger filters.
- **Non-goals:** no merchant intelligence system, no enrichment APIs.
- **Acceptance:** aliased variants roll up to one display merchant in
  analytics; raw value still visible on the transaction detail.

### 11.5 Monthly digest (Later)

Concise month-in-review generated from the **same aggregate RPCs** as the UI:
income, Total Outflow, Personal Spend, Family Support, savings change, largest
labels/merchants, goal progress, significant recurring charges. No separate
analytics pipeline. Rejected if it ever computes numbers the UI cannot
reconcile.

### 11.6 Automated backup (Later — operational, not a screen)

Recurring Supabase export (schema + rows) scheduled after the security
migration. Documented as an ops runbook task; no product UI.

---

## 12. Future backlog: Google Pay screenshot import

**Deferred. Not part of any committed phase. No implementation now.**

Intended future workflow (reviewed import, nothing automatic):

1. User uploads one or more Google Pay transaction-history screenshots.
2. OCR or a vision model extracts candidate transactions.
3. A review table presents candidates; the user edits or rejects rows.
4. Dedupe compares date, amount, direction, merchant/VPA, and nearby existing
   entries.
5. **Only explicitly confirmed rows are imported**, through the standard
   audited write path.
6. Screenshot retention only if a privacy/storage design is intentionally
   approved later.

Constraints: no automatic insertion; no Google Pay credentials or scraping; no
bank-statement parser as a prerequisite; no attachment tables added in the
current phase to "prepare" for this.

Likely minimal interfaces when picked up: an import-review screen, a candidate
DTO (date, amount, direction, merchant, VPA, confidence), and reuse of the
existing dedupe hash/window checks. Acceptance: zero rows created without
explicit confirmation; dedupe prevents double-import of an existing ledger row.

---

## 13. Explicitly out of scope / rejected

| Item | Status |
|---|---|
| Bank-statement CSV/PDF import; statement export | Out of scope now |
| Direct bank / Account Aggregator integrations | Rejected |
| Google Pay OCR implementation | Deferred (see §12) |
| Shared wallets, household/multi-user anything | Rejected (boundary) |
| Budgets, envelopes, rollover, budget alerts | Rejected (boundary) |
| Tax-management modules | Rejected |
| Gamification | Rejected |
| ML-based anomaly detection | Rejected (deterministic baselines only) |
| Investment holdings, market prices, return calculations | Out of scope — contributions/allocation only |
| Separate subscription data model | Rejected — recurring expenses cover it |
| Event-sourcing system | Rejected |
| New infrastructure beyond the planned Edge Function | Rejected |
| AI streaming, transaction attachments | Out of scope now |

---

## 14. Overengineering guardrails

Reject or defer anything that:

- Requires a new service when Supabase already supports it.
- Requires a new table without a clear correctness reason.
- Adds a separate screen where a section or filter suffices.
- Duplicates existing analytics.
- Adds AI where deterministic rules are sufficient.
- Requires historical data that does not exist (never fabricate).
- Produces numbers that cannot be reconciled to ledger totals.
- Adds more than the four approved primary charts.
- Expands the product into accounting software for multiple people.

Every future proposal must state: user problem, minimal data-model change,
reused capability, non-goals, acceptance criteria, and Must/Should/Later/
Rejected.
