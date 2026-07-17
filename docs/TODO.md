# TODO: Secure Mobile-First Production Roadmap

This is the implementation checklist for `docs/enhancement.md`. Work through the
phases in order unless a task explicitly says it can run in parallel.

## Product boundaries

- [x] The product is single-owner. There is no registration, sharing, member, or
  organization workflow.
- [x] Existing finance data belongs to the owner and must be preserved during
  every migration.
- [x] AI may read, categorize, summarize, and answer. It must never modify money
  or bypass explicit user confirmation.
- [x] Financial records use soft deletion. Physical `DELETE` access remains
  disabled for client roles.
- [x] Balances are derived from opening balances and transactions; no mutable
  account balance column may be introduced.
- [x] Transfers use two linked entries. Investments move value between accounts
  and are not expenses.
- [x] Budgets, rollover logic, AI streaming, multi-owner access, transaction
  attachments, and investment return calculations are out of scope.

## Delivery order

1. Establish a reliable test gate, backup, and owner account.
2. Deploy owner authentication, ownership columns, RLS, and scoped RPCs.
3. Move Gemini access to an authenticated Edge Function and rotate the key.
4. Harden Android Brave shortcut startup and resume behavior.
5. Add primary labels and atomic transaction auditing.
6. Add the label lifecycle and migration tools.
7. Replace full-ledger reads with pagination, snapshots, and aggregate RPCs.
8. Add the separate mobile-first Analytics tab.
9. Complete production acceptance and the seven-day finance check.

---

## Phase 0: Completed foundation

### Application and data layer

- [x] Flutter web application with Riverpod, Supabase, `fl_chart`, `intl`, and
  browser-safe environment loading.
- [x] Core models and CRUD providers for transactions, accounts, goals,
  invoices, recurring income, recurring expenses, labels, and chat sessions.
- [x] Existing schema migrations through `00005_transaction_labels.sql`.
- [x] Derived account balance and net-worth functions.
- [x] Realtime transaction updates, soft deletion, transaction edit history,
  transfer pairing, investment entries, and duplicate prevention.
- [x] Monthly snapshot creation/backfill for prior-month totals.
- [x] Transaction ledger, add/edit form, account filtering, date grouping, and
  pull-to-refresh.
- [x] Briefing/dashboard KPIs, emergency-fund progress, savings rate, account
  balances, and category chart.
- [x] Goals, invoice drawer, and Agent Desk user interfaces.

### Web-only deployment baseline

- [x] Removed Android and Windows runners and native SMS listening.
- [x] Retained the pure Dart SMS parser for future paste/import workflows.
- [x] Removed the Supabase service-role key from browser configuration.
- [x] Added Vercel web build configuration and release output in `build/web`.
- [x] Documented the Flutter Web -> Supabase -> Gemini architecture currently in
  production.
- [ ] Supersede the current browser `GEMINI_API_KEY` build requirement in Phase
  3. Do not treat adding the Gemini key to Vercel as the permanent fix.

---

## Phase 1: Migration safety and reliable gates

No ownership or policy migration starts until this phase is complete.

### Repair the validation baseline

- [ ] Replace the unsupported `find.byDisplayValue` use in the existing widget
  test with a supported finder or a widget-key assertion.
- [ ] Run `flutter pub get`, `flutter analyze`, and `flutter test`; record any
  pre-existing failures before feature work.
- [ ] Run a release `flutter build web` with the current required environment to
  prove the pre-migration client still builds.
- [ ] Add one smoke test that boots the app with mocked initialization and one
  model/provider test that proves the test harness can exercise async state.

### Inventory protected data and interfaces

- [ ] List every owner-controlled table from all migrations, including
  transactions, transaction-label joins, labels, accounts, goals, invoices,
  category rules, recurring items, monthly snapshots, and chat sessions.
- [ ] List every view, function, trigger, Realtime publication, storage bucket,
  and client query that can expose or mutate owner data.
- [ ] Record current unique constraints and foreign keys that need `user_id` in
  their key, especially snapshot month/year and case-insensitive label names.
- [ ] Identify all RPCs using `SECURITY DEFINER`; verify each has a fixed
  `search_path`, explicit authorization, least-privilege grants, and no caller-
  supplied owner UUID.
- [ ] Capture baseline query counts and payload sizes for first ledger load,
  Briefing load, and Agent Desk context gathering.

### Backup and rollback preparation

- [ ] Export the production schema and all rows immediately before migration.
- [ ] Restore the export into a disposable Supabase project and verify row counts
  and representative transaction, label, invoice, goal, and snapshot records.
- [ ] Record the production owner UUID, project reference, callback URLs, and
  maintenance-window procedure outside source control.
- [ ] Prepare forward-only corrective migrations. Do not plan a destructive
  rollback that removes populated ownership or primary-label columns.
- [ ] Define row-count and ownership verification SQL to run before and after
  each production migration.

### Phase 1 exit criteria

- [ ] Static analysis, tests, and the release web build pass.
- [ ] A tested backup exists and can be restored.
- [ ] Every protected table and callable database interface has an owner-scoping
  migration task in Phase 2.

---

## Phase 2: Single-owner authentication and RLS

### 2.1 Provision the owner identity

- [ ] Create the one production Supabase Auth owner account and retain its UUID
  for the controlled data backfill.
- [ ] Enable Google OAuth and email magic-link login for that account.
- [ ] Configure localhost, Vercel preview, and production callback/redirect URLs;
  reject redirects outside the allowlist.
- [ ] Disable public sign-up after the owner identity is proven usable.
- [ ] Confirm a non-owner test account can authenticate only in staging and is
  rejected by application ownership checks.

### 2.2 Add the protected owner registry

- [ ] Create the next additive migration for a private `app_owner` registry
  referencing `auth.users(id)` and constrained to one active owner.
- [ ] Insert the known owner UUID during the maintenance window; fail the
  migration if the owner UUID is absent or ambiguous.
- [ ] Add a private owner-check helper based on `auth.uid()` with a fixed
  `search_path`; revoke direct execution or table access not needed by client
  roles.
- [ ] Make all owner policies and privileged RPCs fail closed when no registry
  row exists.
- [ ] Add a database assertion that a second active owner cannot be inserted.

### 2.3 Add and backfill row ownership

- [ ] Add nullable `user_id uuid` columns to every protected table before
  changing policies.
- [ ] Backfill every existing row with the registered owner UUID in one reviewed
  transaction and compare table row counts before and after.
- [ ] Detect orphaned join rows and cross-table references before adding stricter
  keys; stop rather than silently deleting data.
- [ ] Add indexes beginning with `user_id` for owner-filtered date, status,
  account, label, and soft-delete query paths.
- [ ] Change ownership columns to `NOT NULL` only after zero null rows are
  verified.
- [ ] Add composite owner-aware foreign keys where they prevent cross-owner
  references, including transaction-label, primary-label, transfer, account,
  invoice, recurring, rule, and merge relationships.
- [ ] Update owner-specific uniqueness: snapshot `(user_id, year, month)`, label
  `(user_id, lower(name))` where applicable, SMS hash, and any other natural
  keys currently global.
- [ ] Ensure triggers copy or validate ownership rather than trusting arbitrary
  client-supplied `user_id` values.

### 2.4 Replace open policies

- [ ] Remove every `anon_all` policy in the same release that introduces the
  replacement policies.
- [ ] Add owner-only `SELECT` policies requiring both `user_id = auth.uid()` and
  membership in `app_owner`.
- [ ] Add owner-only `INSERT` policies with equivalent `WITH CHECK` expressions.
- [ ] Add owner-only `UPDATE` policies with both `USING` and `WITH CHECK` so an
  update cannot transfer row ownership.
- [ ] Keep physical `DELETE` revoked and expose only audited soft-delete updates
  or RPCs.
- [ ] Apply equivalent ownership controls to storage objects if attachments or
  other user files already exist.
- [ ] Recheck Realtime: authenticated changes are delivered to the owner while
  anonymous and non-owner subscribers receive no finance rows.

### 2.5 Scope functions and aggregates

- [ ] Update account-balance and net-worth functions to derive the owner from
  `auth.uid()` and never accept a trusted `user_id` from the browser.
- [ ] Scope transaction, label, snapshot, recurring, goal, invoice, chat, and
  future analytics RPCs to the authenticated owner.
- [ ] Reject anonymous, non-owner, and owner-registry-missing calls before any
  query executes.
- [ ] Restrict function grants to `authenticated`; revoke unintended `anon` and
  `public` execution.
- [ ] Preserve soft-delete filtering and double-entry behavior inside all revised
  functions.

### 2.6 Implement the Flutter auth gate

- [ ] Add typed auth state for initializing, signed out, callback processing,
  authenticated owner, authenticated non-owner, and recoverable error.
- [ ] Restore Supabase's persisted browser session before constructing finance
  providers or subscribing to Realtime.
- [ ] Listen to auth state changes for initial session, token refresh, OAuth or
  magic-link callback, password recovery if enabled, and sign-out.
- [ ] Build a focused sign-in screen with Google and email magic-link actions,
  callback progress, resend cooldown, and useful error messages.
- [ ] Verify owner status after authentication before showing any finance shell;
  present a fail-closed access-denied state to non-owners.
- [ ] Refresh an expired session on resume and return to sign-in without losing a
  valid unsaved draft when refresh is temporarily offline.
- [ ] Add sign-out to the app shell; cancel subscriptions, invalidate owner data,
  clear local drafts/filters, and return to the auth gate.
- [ ] Prevent finance providers, Agent Desk, and deep links from loading before
  the owner gate succeeds.

### 2.7 Verify and deploy ownership

- [ ] Add database tests proving anonymous and non-owner users cannot select,
  insert, update, soft-delete, subscribe to, or invoke privileged functions.
- [ ] Prove the owner can complete supported CRUD, transfer, allocation, invoice,
  label, snapshot, and balance operations.
- [ ] Prove cross-owner foreign-key relationships and ownership-changing updates
  fail.
- [ ] Verify all pre-migration rows remain present and belong to the owner.
- [ ] Deploy the auth-capable client and owner migration in a short maintenance
  window; do not leave the open-policy client deployed against owner-only RLS.

### Phase 2 exit criteria

- [ ] Production has no `anon_all` policy or anonymously executable finance RPC.
- [ ] The owner can sign in after browser restart and sign out cleanly.
- [ ] Anonymous and non-owner requests fail closed without leaking row existence.

---

## Phase 3: Secure Agent Desk

### 3.1 Create the authenticated Edge Function

- [ ] Add a Supabase Edge Function for Agent Desk requests and keep all Gemini
  HTTP traffic inside the function.
- [ ] Require a valid Supabase bearer JWT and verify the caller against
  `app_owner` before accepting request content.
- [ ] Restrict CORS to local development, approved Vercel previews if required,
  and the production origin.
- [ ] Define a versioned request/response contract for conversation messages,
  tool activity, final answer, retryable errors, and request correlation ID.
- [ ] Enforce request size, conversation length, tool-round, and execution-time
  limits; preserve the existing maximum of ten tool rounds unless measured data
  justifies lowering it.
- [ ] Validate roles and content server-side rather than forwarding arbitrary
  Gemini payloads from the browser.

### 3.2 Move context and tools server-side

- [ ] Port Gemini model configuration, system safety rules, tool definitions,
  retry/backoff, and response parsing from Flutter to the Edge Function.
- [ ] Resolve account balances, net worth, transactions, invoices, goals,
  recurring commitments, expected income, and snapshots using owner-scoped
  database calls under the caller's JWT.
- [ ] Keep all money-changing operations absent from the tool registry.
- [ ] Treat model tool arguments as untrusted: validate types, filter bounds,
  dates, pagination limits, and enum values before database execution.
- [ ] Return privacy-safe tool progress metadata for a collapsible activity view;
  never return chain-of-thought or raw secrets.
- [ ] Ensure failures expose a stable user message and correlation ID without SQL,
  JWT, key, stack-trace, or finance-value leakage.

### 3.3 Remove browser Gemini credentials

- [ ] Store `GEMINI_API_KEY` with `supabase secrets set`, not in repository,
  Flutter assets, Vercel variables, or generated `.env` files.
- [ ] Update Flutter Agent Desk code to call the Edge Function with the current
  authenticated session instead of Gemini directly.
- [ ] Remove `GEMINI_API_KEY` from `.env.example`, `pubspec.yaml` asset inputs,
  `vercel-build.sh`, `vercel.json`, documentation, and browser request code.
- [ ] Make the Vercel build require only the browser-safe Supabase URL and
  publishable/anon key.
- [ ] Search source maps, `build/web`, logs, deployment settings, and Git history
  for exposed Gemini key material.
- [ ] Rotate the deployed Gemini key after the server-only path is live and revoke
  the old key.

### 3.4 Test the secure Agent Desk

- [ ] Test missing, malformed, expired, non-owner, and valid owner JWTs.
- [ ] Test malformed model output, invalid tool arguments, Gemini rate limits,
  timeout, retry exhaustion, and database outage behavior.
- [ ] Verify data from one synthetic user cannot enter another caller's prompt or
  answer.
- [ ] Verify "Can I afford X?" still cites owner-scoped balances and committed
  spend without changing any row.
- [ ] Add a collapsible tool-activity UI with accessible labels and no hidden
  chain-of-thought display.

### Phase 3 exit criteria

- [ ] No Gemini credential or direct Gemini request exists in the web bundle.
- [ ] Only the authenticated owner can invoke Agent Desk successfully.
- [ ] Key rotation is complete and the former browser-exposed key is revoked.

---

## Phase 4: Android Brave shortcut reliability

### 4.1 Build a visible web startup surface

- [ ] Add `web/flutter_bootstrap.js` using Flutter's supported loader hooks and
  release-aware service-worker initialization.
- [ ] Show lightweight HTML states for loading Flutter, initialization failure,
  recovery in progress, and manual recovery before the Dart app is available.
- [ ] Include a retry button and privacy-safe diagnostic code in terminal error
  states; never leave a blank page.
- [ ] Remove the unused Corbado/passkey script and any other blocking third-party
  startup dependency from `web/index.html`.
- [ ] Keep Flutter's default renderer; add a documented diagnostic query
  parameter for renderer comparison rather than forcing a renderer globally.

### 4.2 Correct install metadata

- [ ] Set the production application name, short name, description, background
  color, theme color, display mode, and orientation behavior.
- [ ] Set stable root values for manifest `id`, `start_url`, and `scope`, including
  behavior when a release cache-buster query is present.
- [ ] Generate and reference standard and maskable icons at required PWA sizes;
  verify safe-zone rendering on Android.
- [ ] Check favicon, Apple/mobile metadata where relevant, and installed shortcut
  naming against the production brand.
- [ ] Validate the manifest and service worker in browser application tooling.

### 4.3 Implement the JavaScript/Dart lifecycle handshake

- [ ] Define versioned browser events for Dart-ready, resume-request, and
  post-frame resume acknowledgement.
- [ ] Emit Dart-ready only after initialization and the first usable frame.
- [ ] Listen in JavaScript for `visibilitychange`, `pageshow`, and WebGL context
  loss; ignore duplicate signals for the same resume attempt.
- [ ] On foregrounding, request a Dart acknowledgement tied to a unique attempt
  ID and wait up to three seconds for a rendered post-frame response.
- [ ] If the response is missing, reload once with release and attempt cache-
  busters so a stale service worker cannot serve the same broken shell.
- [ ] Persist a short-lived recovery marker so a second failure stops the reload
  loop and displays the HTML recovery message and reload button.
- [ ] Clear recovery markers after a healthy acknowledged frame.
- [ ] Record privacy-safe startup, resume, context-loss, reload, and recovery
  timings without recording financial values or message content.

### 4.4 Recover application state without reload

- [ ] On healthy resume, refresh the auth session before owner-scoped requests.
- [ ] Detect closed, errored, or stale Realtime channels and recreate only those
  subscriptions instead of duplicating listeners.
- [ ] Revalidate only providers visible in the active tab; debounce duplicate
  lifecycle notifications.
- [ ] Add an offline/stale indicator that distinguishes no network, expired auth,
  Supabase failure, and locally cached display data.
- [ ] Preserve the last usable read state while showing retry controls; do not
  imply stale balances are current.

### 4.5 Persist short-lived UI drafts

- [ ] Define versioned local draft DTOs for transaction form fields, selected
  labels and primary label, active app tab, active analytics subview, date range,
  and analytics filters.
- [ ] Store drafts with owner ID, schema version, saved timestamp, and 24-hour
  expiry; reject malformed, expired, or wrong-owner records.
- [ ] Debounce writes and avoid persisting auth tokens or unnecessary financial
  context beyond the explicitly entered draft.
- [ ] Restore form drafts only after authentication and present a clear resumed-
  draft state.
- [ ] Clear the relevant draft after successful save, explicit cancel, expiry,
  incompatible schema migration, or sign-out.

### 4.6 Brave acceptance

- [ ] Test a production release installed as a shortcut from Android Brave on a
  mid-range device.
- [ ] Complete ten rapid app switches and 5-minute and 30-minute suspensions.
- [ ] Repeat while online, temporarily offline, and with an expired session.
- [ ] Trigger or simulate WebGL context loss and verify one bounded recovery
  attempt followed by the manual recovery screen if needed.
- [ ] Verify healthy resume within two seconds, watchdog recovery within six
  seconds, no reload loop, and no lost transaction draft.
- [ ] Clear obsolete service-worker caches during rollout and prove the installed
  shortcut receives the new release.

### Phase 4 exit criteria

- [ ] No tested startup or resume path produces an indefinite blank screen.
- [ ] Healthy resumes refresh auth/data without reloading the app.
- [ ] Failed resumes recover once automatically and then fail visibly and safely.

---

## Phase 5: Primary labels and unified transaction auditing

### 5.1 Add primary-label schema

- [ ] Add nullable `transactions.primary_label_id` through an additive migration.
- [ ] Tie the primary label to the same owner as the transaction and add indexes
  for unresolved-review and analytics queries.
- [ ] Add database validation that a non-null primary label is also attached in
  the transaction-label join table.
- [ ] Define expense applicability from canonical transaction direction/type so
  credits, transfers, and investments are not accidentally treated as spending.
- [ ] Do not immediately make legacy primary labels non-null; preserve ambiguous
  data for explicit review.

### 5.2 Classify and backfill legacy transactions

- [ ] For each non-deleted legacy expense with exactly one attached label, assign
  that label as primary.
- [ ] Leave zero-label expenses without a primary and report them as `Unlabeled`.
- [ ] Leave multi-label expenses without a primary and report them as
  `Needs primary label`.
- [ ] Keep all contextual joins unchanged during backfill; verify join and
  transaction counts before and after.
- [ ] Produce a review report with resolved, unlabeled, ambiguous, skipped
  non-expense, and invalid-reference counts.

### 5.3 Add explicit model state

- [ ] Extend `Transaction` serialization and `copyWith` with `primaryLabelId`.
- [ ] Add a typed derived primary-label status: `notRequired`, `resolved`,
  `unlabeled`, and `needsPrimaryLabel`.
- [ ] Extend `TransactionLabel` only with fields needed to render identity,
  lifecycle, and merge state; do not infer primary from list order.
- [ ] Add tests for old payloads, null primary IDs, missing joined labels, and all
  four derived statuses.

### 5.4 Replace split writes with one transaction RPC

- [ ] Add an owner-scoped `save_transaction_with_labels` RPC supporting the
  required create/edit fields, attached label IDs, and primary label ID.
- [ ] Lock the existing transaction and attached labels before an edit so the
  audit compares one consistent old state.
- [ ] Validate owner, editability, soft-delete state, account relationships,
  label lifecycle, duplicate label IDs, and primary membership.
- [ ] Require exactly one primary label for every newly created or edited expense;
  allow contextual labels without a spending primary for other transaction types.
- [ ] Update transaction fields, replace label relationships, and set primary
  status in one database transaction.
- [ ] Append exactly one immutable audit record containing old/new transaction
  fields plus old/new label IDs, names, colors, and primary flags.
- [ ] Use database timestamps and actor identity for the audit; do not trust
  caller-provided audit JSON.
- [ ] Roll back field, join, primary, and audit changes together if any validation
  or write fails.
- [ ] Restrict direct client updates that could bypass unified auditing; route
  supported transaction edits through the RPC.
- [ ] Update providers to refresh or patch local state only after the RPC commits.

### 5.5 Update transaction UI and review workflow

- [ ] Make primary selection explicit in add/edit forms while retaining optional
  contextual multi-label selection.
- [ ] Prevent save with zero or multiple primary choices when the entry is an
  expense; clear the spending-primary requirement when type changes to a credit,
  transfer, or investment.
- [ ] Keep selected labels and primary state in the 24-hour form draft.
- [ ] Display primary status in ledger rows and detail/edit views without making
  contextual labels look like additional spend categories.
- [ ] Add a review queue for unresolved multi-label expenses with owner-scoped
  pagination and a focused assign-primary action.
- [ ] Provide separate filters for `Unlabeled` and `Needs primary label`.

### 5.6 Make reports double-count safe

- [ ] Update category pies, trends, briefing data, exports, and Agent Desk context
  to attribute each expense's full amount exactly once to its primary label.
- [ ] Bucket zero-label expenses as `Unlabeled` and ambiguous legacy expenses as
  `Needs primary label` until reviewed.
- [ ] Keep contextual labels available for ledger search and analysis filters,
  but never split or duplicate monetary totals across them.
- [ ] Add invariants comparing total expense amount with the sum of primary,
  unlabeled, and unresolved buckets for the same filter set.

### Phase 5 exit criteria

- [ ] Every new or edited expense has exactly one valid primary label.
- [ ] Legacy ambiguity is visible and no existing label relationship is lost.
- [ ] One logical edit creates one complete audit entry or changes nothing.
- [ ] Category reports reconcile exactly to filtered spending totals.

---

## Phase 6: Label lifecycle management

### 6.1 Add lifecycle schema and audit records

- [ ] Add label state constrained to `active`, `archived`, `merged`, or `deleted`.
- [ ] Add same-owner `merged_into_id`, `updated_at`, `archived_at`, `merged_at`,
  `deleted_at`, and actor metadata where required.
- [ ] Prevent self-merges, merge cycles, merged-target chains, and references to a
  deleted target.
- [ ] Add owner-scoped, case-insensitive uniqueness for assignable label names.
- [ ] Create immutable label audit records for create, rename, archive, merge,
  restore if supported, and soft delete.
- [ ] Backfill all existing labels as active without changing IDs or joins.

### 6.2 Implement rename and archive

- [ ] Add an owner-scoped rename RPC that trims/normalizes input, detects names
  case-insensitively, preserves label identity, and records old/new names.
- [ ] Decide and test case-only rename behavior explicitly.
- [ ] Add archive RPC behavior that hides the label from new assignments and
  rules while retaining historical joins, primary references, colors, and
  reports.
- [ ] Keep archived labels visible on historical transactions and offer an
  archived filter in label management.
- [ ] Prevent archived or merged labels from being assigned by transaction save
  RPCs.

### 6.3 Implement atomic merge

- [ ] Add an owner-scoped merge RPC accepting one source and one active target.
- [ ] Lock both labels and all affected primary/join references in a deterministic
  order.
- [ ] Move contextual joins to the target, resolve source/target duplicate joins,
  and migrate every source primary reference to the target.
- [ ] Update category rules and recurring-item references where labels are stored
  by ID; add an explicit migration plan if any still use label names.
- [ ] Append affected transaction audit entries containing old/new contextual and
  primary label states.
- [ ] Record a label merge event with source, target, actor, timestamp, and
  affected counts, then mark the source `merged` with `merged_into_id`.
- [ ] Roll back all relationship, audit, and lifecycle changes on any failure.
- [ ] Prove the merge is idempotent or returns a stable already-merged result on
  accidental retry.

### 6.4 Guard label deletion

- [ ] Add a reference-check function covering contextual transaction joins,
  primary labels, category rules, recurring items, merge targets, and any other
  owner data discovered in Phase 1.
- [ ] Permit delete only when the active/archived label has zero references.
- [ ] Implement delete as a soft-delete state transition with audit metadata;
  never physically remove the row.
- [ ] For referenced labels, return affected counts and expose Archive and Merge
  actions instead of Delete.
- [ ] Exclude soft-deleted labels from assignment, default management lists, and
  aggregate category output.

### 6.5 Build label management UI

- [ ] Add active and archived label views with usage counts and primary-usage
  counts.
- [ ] Add rename, archive, merge, and eligible-delete dialogs with clear impact
  summaries and confirmation.
- [ ] Exclude invalid merge targets and preserve form state on recoverable RPC
  errors.
- [ ] Refresh visible labels and patch affected transactions after lifecycle RPCs
  without reloading the full ledger.
- [ ] Provide accessible status text and controls at 360-pixel width.

### Phase 6 exit criteria

- [ ] Rename conflicts are case-insensitive and identity-preserving.
- [ ] Archived history remains reportable but cannot be newly assigned.
- [ ] Merge moves primary/context references without duplicates or partial state.
- [ ] Referenced labels cannot be deleted; unused deletes are soft and audited.

---

## Phase 7: Data and rendering performance

### 7.1 Define server-side ledger queries

- [ ] Add a typed `LedgerQuery` containing date range, direction/type, account,
  primary label, contextual label, merchant text, unresolved state, and sort.
- [ ] Implement an owner-scoped transaction-page query/RPC returning 50 rows and
  a stable cursor based on effective transaction timestamp plus transaction ID.
- [ ] Define null/equal-timestamp ordering explicitly so rows are never duplicated
  or skipped between pages.
- [ ] Push search and filters into indexed Supabase queries; stop filtering an
  ever-growing full ledger in memory.
- [ ] Return only fields and joined label/account data required by ledger rows;
  fetch heavier detail on demand.
- [ ] Add indexes validated with representative `EXPLAIN (ANALYZE, BUFFERS)` plans
  for common owner-scoped filters.

### 7.2 Replace the transaction provider

- [ ] Replace the 200-row full query with first-page, next-page, refresh, filter-
  change, empty, and error states.
- [ ] Reset cursor and loaded pages atomically when filters or owner session
  change.
- [ ] Trigger next-page loading near scroll end, prevent concurrent duplicates,
  and stop at the server's end-of-list signal.
- [ ] Preserve visible rows during transient next-page failures and offer a
  localized retry.
- [ ] Ensure edits that change date or active filters move/remove the row rather
  than leaving the page incorrectly sorted.
- [ ] Add pagination tests with equal timestamps, deleted rows, filter changes,
  inserts between pages, and an exact page-size boundary.

### 7.3 Patch Realtime changes efficiently

- [ ] Parse owner-visible insert/update events into row-level additions,
  replacements, moves, or removals when they intersect the current filter.
- [ ] Handle label-join changes through targeted transaction invalidation because
  the base row event alone may not contain current labels.
- [ ] Debounce bursts and invalidate only the affected first page, aggregate, or
  detail query when deterministic patching is unsafe.
- [ ] Reconnect one channel per owner/session after resume and dispose all
  channels on sign-out.
- [ ] Remove full-ledger reloads from normal Realtime event handling.

### 7.4 Add owner-scoped aggregate RPCs

- [ ] Implement `get_briefing_summary(month)` for income, spending, savings,
  investment contributions, savings rate, unresolved-label count, and compact
  summaries.
- [ ] Implement `get_account_balances()` as one batch call rather than one RPC per
  account.
- [ ] Implement typed `get_analytics(period, filters)` output or narrowly split
  RPCs if payload measurement shows one bundle is too large.
- [ ] Derive owner from `auth.uid()`, validate date/filter limits, exclude soft-
  deleted rows, and apply primary-label attribution consistently.
- [ ] Version the returned JSON shape and map it to typed Dart DTOs rather than
  passing dynamic maps into widgets.
- [ ] Add SQL tests reconciling aggregate output against known fixture rows.

### 7.5 Complete snapshot strategy

- [ ] Use live transaction rows for the current partial month.
- [ ] Use immutable monthly snapshots for completed historical months and define
  a controlled rebuild path when old transactions are corrected.
- [ ] Add owner-scoped monthly account-balance snapshots recorded at month end or
  first open of the next month.
- [ ] Store source period, calculated timestamp, and schema/calculation version so
  stale snapshots can be identified.
- [ ] Seed only balances that can be derived reliably from opening dates and
  transactions; display unavailable history instead of fabricating values.
- [ ] Update trend queries to combine historical snapshots with the live current
  month without overlap or gaps.

### 7.6 Reduce rendering and startup work

- [ ] Lazily construct and fetch each app tab; an unvisited tab must not issue
  provider reads or build charts.
- [ ] Render only the active Analytics subview and defer below-the-fold chart work
  until needed.
- [ ] Keep Briefing limited to essential KPIs, account balances, and small
  summaries; move detailed charting to Analytics.
- [ ] Cache/memoize pure analytics transformations by immutable typed inputs and
  rebuild only when source data or filters change.
- [ ] Constrain ledger, form, and chart widths for desktop while preserving a
  readable 360-390 pixel mobile layout.
- [ ] Reassess navigation at wide breakpoints without changing the mobile-first
  information architecture.

### 7.7 Measure performance

- [ ] Add privacy-safe timing around app interactive state, first ledger page,
  Briefing RPC, analytics RPC, and chart-ready state.
- [ ] Test with a representative large personal ledger rather than the small
  development dataset.
- [ ] Achieve warm installed-shortcut interaction within three seconds and cold
  4G interaction within six seconds on the chosen mid-range Android device.
- [ ] Achieve Briefing aggregate p95 below 500 ms under the expected dataset.
- [ ] Prove first ledger paint downloads only one page, not full history.

### Phase 7 exit criteria

- [ ] Ledger memory and initial payload are bounded by a 50-row page.
- [ ] Filters/search execute server-side and paginate deterministically.
- [ ] Briefing and charts no longer recalculate the full ledger.
- [ ] Unvisited tabs and inactive analytics subviews perform no data fetches.

---

## Phase 8: Separate mobile-first Analytics tab

### 8.1 Add typed analytics interfaces

- [ ] Add `AnalyticsPeriod` for 1M, 3M, 6M, 12M, YTD, and All with 12M as the
  default.
- [ ] Add typed `AnalyticsQuery`, `AnalyticsFilters`, `AnalyticsBundle`, summary,
  series, category, merchant, account, goal, and chart-point DTOs.
- [ ] Define currency minor/decimal-unit handling, timezone boundaries, missing
  periods, and percentage precision in one place.
- [ ] Persist active period, subview, and filters locally for 24 hours using the
  Phase 4 state format.
- [ ] Add Riverpod provider families keyed by immutable query/filter values.

### 8.2 Integrate navigation and drill-down

- [ ] Add Analytics as a first-class destination separate from Briefing.
- [ ] Keep no more than five primary mobile destinations by moving invoice access
  to an app-bar/drawer action if required; do not squeeze six bottom-nav items.
- [ ] Preserve active tab on healthy resume and deep-link into a requested
  analytics subview.
- [ ] Define ledger drill-down routes carrying date, primary label, contextual
  label, merchant, account, and unresolved filters.
- [ ] Make chart taps open a server-filtered ledger and provide a clear way back
  to the same chart/filter state.

### 8.3 Overview analytics

- [ ] Show income, spending, savings, investment contributions, and savings rate
  for the selected period.
- [ ] Add monthly cash-flow and savings-rate trends with current partial-month
  treatment clearly identified.
- [ ] Reconcile period cards and monthly series to the same aggregate result.
- [ ] Add empty, partial-history, loading, stale, and error states.

### 8.4 Spending analytics

- [ ] Add a primary-label donut that counts each expense once and combines ranks
  after the top seven into `Other`.
- [ ] Add monthly primary-label trend, top merchants, and daily cumulative
  spending views.
- [ ] Show `Unlabeled` and `Needs primary label` separately with a link to the
  relevant ledger/review queue.
- [ ] Keep contextual labels as optional filters without using them as additive
  category totals.
- [ ] Let category, merchant, and date interactions drill into matching ledger
  filters.

### 8.5 Net-worth analytics

- [ ] Add a historical net-worth line from completed snapshots plus the current
  live value.
- [ ] Add current account allocation using batch account balances.
- [ ] Add per-account trends only from reliable account-balance snapshots and
  visually mark unavailable periods.
- [ ] Drill current allocation into account-filtered ledger results where useful.
- [ ] Never interpolate or claim historical account values not supported by data.

### 8.6 Goal analytics

- [ ] Show goal progress, remaining amount, and contribution pace for the selected
  period.
- [ ] Estimate completion from a documented recent-savings/contribution window;
  return unavailable when pace is zero, negative, or insufficient.
- [ ] Distinguish the emergency fund while keeping calculations generic by goal
  type rather than name.
- [ ] Explain estimate assumptions in accessible help text and avoid presenting a
  forecast as guaranteed.

### 8.7 Investment analytics

- [ ] Show investment contribution totals and monthly contribution trend.
- [ ] Show current allocation across investment accounts using derived balances.
- [ ] Exclude transfers between investment accounts from contribution totals.
- [ ] State explicitly that the view reports contributions/allocation, not market
  value, gains, returns, or portfolio performance.

### 8.8 Chart usability and accessibility

- [ ] Render only the selected analytics subview and avoid constructing hidden
  charts.
- [ ] Prefer stacked vertical mobile sections; use horizontal scrolling only for
  time axes that remain unreadable otherwise.
- [ ] Add touch-friendly hit targets, tooltips with full currency/date values,
  legends, and selected-point feedback.
- [ ] Provide an accessible text summary and tabular alternative for every chart.
- [ ] Support empty and single-point series without exceptions or misleading
  lines.
- [ ] Test text scaling, keyboard focus on web, color contrast, color-independent
  distinctions, and a 360-pixel viewport.

### 8.9 Analytics correctness tests

- [ ] Verify income, spending, saving, investment, and net-worth fixtures across
  all period selectors and timezone/month boundaries.
- [ ] Verify historical snapshots and live current-month rows neither overlap nor
  omit a period.
- [ ] Verify primary/context labels cannot double-count expense totals.
- [ ] Verify top-seven plus `Other` equals the ungrouped category total.
- [ ] Verify chart drill-down filters reconcile to the selected value.
- [ ] Verify goal estimates and unavailable states for positive, zero, negative,
  and sparse contribution histories.
- [ ] Add golden/widget coverage for Overview, Spending, Net Worth, Goals, and
  Investments in empty, populated, error, and 360-pixel layouts.

### Phase 8 exit criteria

- [ ] Analytics is separate from the lightweight Briefing tab.
- [ ] Every visualization has a typed data source, accessible alternative, and
  reconciling drill-down.
- [ ] Current and historical calculations use the correct live/snapshot boundary.
- [ ] Investment views make no unsupported return claims.

---

## Phase 9: Documentation, release, and production acceptance

### 9.1 Update documentation with implementation

- [ ] Update `docs/ARCHITECTURE.md` for auth gate, owner-scoped RLS, Edge Function,
  lifecycle recovery, pagination, aggregate RPCs, and lazy Analytics.
- [ ] Update `docs/DATABASE.md` with ownership columns, composite keys, policies,
  primary labels, lifecycle states, audits, snapshots, and migration/backfill
  invariants.
- [ ] Update `docs/API.md` with authenticated RPC and Edge Function contracts,
  request limits, typed responses, and error codes.
- [ ] Update `docs/PRD.md` with single-owner authentication, primary-label rules,
  Analytics behavior, Brave recovery, and explicit exclusions.
- [ ] Update `README.md`, `.env.example`, and deployment instructions so Gemini is
  a Supabase function secret and only browser-safe Supabase values reach Vercel.
- [ ] Add an operations runbook for owner provisioning, key rotation, backups,
  migration verification, cache recovery, snapshot rebuilds, and incident checks.

### 9.2 Automated release gates

- [ ] `flutter pub get` succeeds from a clean checkout.
- [ ] `flutter analyze` reports zero issues.
- [ ] `flutter test` passes all unit, provider, model, and widget tests.
- [ ] Database tests pass against a clean migration and a restored-data fixture.
- [ ] Release `flutter build web` succeeds without `GEMINI_API_KEY` in the build
  environment.
- [ ] Search `build/web` and source maps for service-role and Gemini secrets.
- [ ] Locally serve `build/web` and verify startup, auth callback, refresh, direct
  route, and service-worker update behavior.

### 9.3 Manual security and finance verification

- [ ] Manually exercise owner, anonymous, expired, and non-owner requests through
  the REST API, Realtime, RPCs, and Edge Function.
- [ ] Verify production has no open finance policy, no public privileged function,
  and no physical delete path for client roles.
- [ ] Verify add/edit/soft-delete transactions, transfers, investments, labels,
  goals, allocations, recurring items, snapshots, invoices, and Agent Desk.
- [ ] Verify balances, Briefing, category totals, Analytics, and Agent Desk agree
  for the same known dataset.
- [ ] Verify no keys, finance values, prompts, or tokens appear in browser errors,
  function errors, crash reports, or lifecycle diagnostics.

### 9.4 Production rollout

- [ ] Deploy migrations and Edge Function in the documented maintenance-window
  order with row-count and ownership checks after each step.
- [ ] Deploy the matching Flutter client immediately after owner-only policies are
  active.
- [ ] Rotate Gemini credentials, remove obsolete Vercel variables, and invalidate
  stale web/service-worker caches.
- [ ] Verify Vercel serves `build/web`, direct routes resolve to the app shell, and
  the production owner can complete login callbacks.
- [ ] Monitor auth failures, Edge Function status, recovery attempts, aggregate
  latency, and client initialization without collecting finance content.
- [ ] Keep the verified database backup until the secure release and snapshot
  rebuild behavior have been stable for at least seven days.

### 9.5 Seven-day production check

- [ ] Capture every transaction manually for seven days.
- [ ] Review and resolve every `Needs primary label` item generated during the
  period.
- [ ] On day seven, ask Agent Desk: "How much did I earn this week?"
- [ ] On day seven, ask Agent Desk: "What primary label did I overspend in?"
- [ ] On day seven, ask Agent Desk: "Am I closer to funding my Emergency Fund?"
- [ ] Compare all three answers with the raw ledger, aggregate RPC output, and
  Analytics views; all must reconcile.
- [ ] Record any mismatch as a blocking defect rather than adjusting data to fit
  the answer.

### Production-ready definition

- [ ] Existing data is preserved and owner-scoped.
- [ ] Anonymous and non-owner access fails closed.
- [ ] Gemini credentials are server-only.
- [ ] Installed Brave startup/resume has no blank-screen failure in acceptance
  testing and preserves drafts.
- [ ] Expenses are counted once through primary labels and edits are atomically
  audited.
- [ ] Ledger and charts do not require downloading or recalculating full history.
- [ ] Analytics is correct, accessible, mobile-readable, and drill-down capable.
- [ ] All automated gates, manual checks, performance targets, and the seven-day
  production check pass.
