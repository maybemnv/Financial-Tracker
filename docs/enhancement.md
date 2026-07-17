# Mobile, Security, Performance, and Analytics Enhancement Plan

## Summary

Deliver these improvements in order:

1. Secure the database and AI integration.
2. Fix Android Brave shortcut resume reliability.
3. Make transaction labels auditable and reporting-safe.
4. Replace full-ledger loading with paginated and aggregated queries.
5. Add a separate, mobile-first Analytics tab.

The app remains a single-owner product. Preserve all existing data and assign it to the authenticated owner. No budget feature is included.

## 1. Single-owner authentication and RLS

- Provision one Supabase owner account supporting Google and email magic-link login, configure production callback URLs, then disable public sign-up.
- Add an auth gate that restores persistent sessions, handles OAuth and magic-link callbacks, refreshes expired sessions, and provides sign-out.
- Add `user_id` ownership to all finance, label, snapshot, recurring, rule, goal, invoice, and chat data. Backfill every existing row with the owner UUID before making ownership non-null.
- Replace every `anon_all` policy with owner-only `SELECT`, `INSERT`, `UPDATE`, and soft-delete policies using `auth.uid()` plus a protected owner registry/helper.
- Scope balance, net-worth, analytics, transaction, label, and agent RPCs to the authenticated owner. Anonymous and non-owner requests must fail closed.
- Update unique constraints to include `user_id` where appropriate, including monthly snapshots and label names.
- Follow Supabase's documented [`auth.uid()` RLS model](https://supabase.com/docs/guides/database/postgres/row-level-security) and [persistent Flutter authentication flow](https://supabase.com/docs/guides/getting-started/tutorials/with-flutter).

## 2. Secure Agent Desk

- Keep Agent Desk, but replace direct browser-to-Gemini calls with an authenticated Supabase Edge Function.
- Store `GEMINI_API_KEY` only as a server-side function secret; validate the Supabase JWT and owner status on every request.
- Remove `GEMINI_API_KEY` from `.env`, Flutter assets, Vercel build output, and browser request code.
- Rotate the currently deployed Gemini key because it may already have been exposed in the web bundle.
- Keep the Supabase publishable key in the client; security comes from authenticated RLS, not hiding that key.

## 3. Android Brave shortcut recovery

- Add a custom `flutter_bootstrap.js` using [Flutter's supported loader hooks](https://docs.flutter.dev/platform-integration/web/initialization), with a visible HTML loading/error surface and release-aware service-worker initialization.
- Remove the unused external Corbado/passkey script from `index.html`.
- Correct PWA metadata: production name, description, colors, `id`, root `start_url`, root `scope`, and maskable icons.
- Implement a JavaScript/Dart lifecycle handshake:
  - Dart emits ready and post-frame resume acknowledgements.
  - JavaScript listens to `visibilitychange`, `pageshow`, and WebGL context-loss events.
  - After returning from an app switch, wait three seconds for a rendered-frame acknowledgement.
  - If no acknowledgement arrives, reload once with a release cache-buster.
  - If recovery fails again, stop the loop and show an HTML recovery message and reload button.
- Persist transaction-form drafts, selected labels, active tab, and analytics filters locally with a 24-hour TTL. Clear them on successful save, cancel, or sign-out.
- On a healthy resume, refresh the auth session, reconnect stale realtime channels, and revalidate visible data without reloading the application.
- Keep Flutter's default renderer initially; add a diagnostic renderer query parameter rather than forcing a heavier renderer globally.

## 4. Primary labels and unified auditing

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
- Reporting pies and category trends count the full amount once under the primary label. Context labels remain usable for search and analysis filters but never duplicate or split spending.

## 5. Label lifecycle

- Add label lifecycle state: `active`, `archived`, `merged`, or `deleted`, plus `merged_into_id` and update timestamps.
- Rename labels case-insensitively while preserving identity and recording a label audit event.
- Archive labels by hiding them from new assignments while preserving historical reporting.
- Merge labels through one RPC that moves contextual relationships and primary references, resolves duplicate joins, records affected transaction history, and marks the source as merged.
- Permit delete only for an unused label with no transaction, primary-label, rule, recurring-item, or merge references. Implement it as a soft delete.
- For referenced labels, present Archive and Merge instead of Delete.

## 6. Data and rendering performance

- Replace the transaction provider's full-table query with cursor pagination in pages of 50, using effective transaction date plus ID as a stable cursor.
- Move ledger filtering and searching to Supabase instead of filtering an ever-growing in-memory list.
- Replace full reloads on every realtime event with row-level patching or debounced targeted invalidation.
- Add owner-scoped aggregate RPCs:
  - `get_briefing_summary(month)`
  - `get_analytics(period, filters)`
  - `get_account_balances()`
- Use live rows for the current month and snapshots for completed historical months. Never recalculate the entire ledger merely to render a chart.
- Add monthly account-balance snapshots for future per-account history. Do not fabricate historical account values that cannot be derived reliably.
- Lazily initialize app tabs and chart sections. An unvisited tab must not fetch data or construct charts.
- Keep the Briefing tab lightweight: essential KPIs, account balances, and small summaries. Move detailed visualizations to Analytics.
- Memoize pure analytics transformations and rebuild only when their input dataset or filters change.

## 7. Separate Analytics tab

Provide mobile-friendly subviews with a default 12-month range and 1M, 3M, 6M, 12M, YTD, and All selectors:

- **Overview:** income, spending, savings, investment contributions, savings-rate trend, and monthly cash-flow chart.
- **Spending:** primary-label donut, monthly category trend, top merchants, daily cumulative spending, and unresolved-label indicator.
- **Net Worth:** historical net-worth line, current account allocation, and per-account trends from available snapshots.
- **Goals:** progress, remaining amount, contribution pace, and estimated completion based on recent savings.
- **Investments:** contribution trend and investment-account allocation only. Do not claim portfolio returns without holdings and market-value data.

Chart behavior:

- Aggregate small categories into `Other` after the top seven.
- Tapping a chart segment or point opens the ledger with matching date, primary label, merchant, or account filters.
- Provide tooltips, currency values, accessible summaries, empty states, and a tabular alternative.
- Prefer readable vertical/mobile layouts over squeezing charts; use horizontal scrolling only where the time axis requires it.
- Render only the active analytics subview.

## Interfaces and data model

- Extend `Transaction` with `primaryLabelId` and explicit unresolved-primary status.
- Extend `TransactionLabel` with lifecycle and merge metadata.
- Add typed `AnalyticsQuery`, `AnalyticsBundle`, and chart-point DTOs rather than passing loosely structured maps through widgets.
- Add owner-scoped tables or fields for `app_owner`, label audit records, and account-balance snapshots.
- Add transactional RPCs for transaction edits, label merge, label archive/delete, briefing aggregates, analytics aggregates, and batch account balances.
- Update architecture, database, API, PRD, TODO, environment, deployment, and security documentation alongside the implementation.

## Test and acceptance plan

- First fix the existing test compilation failure caused by the unsupported `find.byDisplayValue` finder so validation can become a reliable gate.
- Database tests:
  - Anonymous and non-owner users cannot read or mutate any row or call privileged RPCs.
  - The owner can perform supported CRUD operations.
  - Existing rows are preserved and assigned to the owner.
  - Cross-owner foreign-key relationships are rejected.
- Transaction tests:
  - Field and label changes create one complete old/new audit entry.
  - Failed label writes roll back transaction changes.
  - Each expense is counted once under its primary label.
  - Ambiguous legacy rows appear under `Needs primary label`.
- Label tests cover case-insensitive rename conflicts, archive visibility, merge deduplication, primary-label migration, and delete safeguards.
- Analytics tests verify cash-flow totals, snapshot/live-month boundaries, drill-down filters, `Other` aggregation, goal estimates, and no double-counting from context labels.
- Widget tests cover authentication states, primary-label selection, review queue, responsive charts, accessible summaries, and 360-pixel-wide layouts.
- Brave shortcut acceptance:
  - Test a production release installed from Android Brave.
  - Perform at least ten rapid app switches plus 5-minute and 30-minute suspensions.
  - Test online, temporarily offline, and expired-session recovery.
  - No blank screen; healthy resume within two seconds, watchdog recovery within six seconds, and no lost transaction draft.
- Performance targets on a mid-range Android device:
  - Warm installed-shortcut launch interactive within three seconds.
  - Cold 4G launch interactive within six seconds.
  - Briefing aggregate request p95 below 500 ms under the expected personal dataset.
  - Ledger first page displayed without downloading the full history.
- Required gates: `flutter analyze`, `flutter test`, release web build, PWA install test, and manual Supabase RLS verification.

## Rollout and assumptions

- Back up/export Supabase data before migration.
- Create the owner account and secure AI function first; then deploy the auth-capable client and owner-scoped migration during a short maintenance window.
- Policies fail closed if owner configuration is missing.
- Clear obsolete service-worker caches after the first secure release and verify the installed Brave shortcut receives the new version.
- Record privacy-safe lifecycle, initialization, recovery, and query timings without storing finance values in diagnostics.
- The app has exactly one owner; no member management, sharing, registration flow, or organization model is included.
- All current data belongs to that owner and must be preserved.
- Budgets and rollover logic are explicitly out of scope.
- Existing soft-delete and derived-balance safety rules remain mandatory.
