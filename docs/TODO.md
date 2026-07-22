# TODO: Secure, Correct, Mobile-First Production Roadmap

This is the implementation checklist for `docs/enhancement.md` (requirements
and metric definitions in `docs/PRD.md`). Work through the phases in order
unless a task explicitly says it can run in parallel.

## Product boundaries

- [x] The product is single-owner. There is no registration, sharing, member, or
  organization workflow.
- [x] Existing finance data belongs to the owner and must be preserved during
  every migration.
- [x] AI may read, classify, summarize, forecast, and answer. It must never
  create, modify, delete, allocate, or move money without explicit user review
  and confirmation.
- [x] Financial records use soft deletion. Physical `DELETE` access remains
  disabled for client roles.
- [x] Balances are derived from opening balances and transactions; no mutable
  account balance column may be introduced.
- [x] Transfers use two linked entries, never change net worth, and the
  `transfer` type is reserved for moves between owner-held accounts.
- [x] Investments are asset movements, not personal spending.
- [x] Goal allocation is earmarking: it never changes an account balance or net
  worth.
- [x] Budgets, rollover logic, AI streaming, multi-owner access, transaction
  attachments, statement import/export, bank integrations, tax modules,
  gamification, ML anomaly detection, and investment return calculations are
  out of scope.
- [x] Maximum four primary Analytics charts. Google Pay screenshot import stays
  in the future backlog, outside every committed phase.
- [x] No new state-management system, chart library, backend server,
  microservice, or infrastructure beyond the planned Supabase Edge Function.

## Delivery order

0. Record the deployed baseline and known defects.
1. Establish a reliable test gate, backup, and migration safety.
2. Deploy owner authentication, ownership columns, RLS, and scoped RPCs.
3. Move Gemini access to an authenticated Edge Function and rotate the key.
4. Fix cash/account correctness and Family-support semantics.
5. Add primary labels, atomic transaction auditing, and the label lifecycle.
6. Redesign Goals with contribution history and full editing.
7. Replace full-ledger reads with pagination, snapshots, and aggregate RPCs.
8. Slim Briefing and build the four-chart Analytics tab.
9. Add upcoming obligations and the deterministic cash-flow forecast.
10. Add quick capture and merchant normalization.
11. Harden installed-PWA startup/resume (browser-agnostic) and complete
    production acceptance.

---

## Phase 0: Deployed baseline and known defects

### Completed foundation

- [x] Flutter web application with Riverpod, Supabase, `fl_chart`, `intl`, and
  browser-safe environment loading, deployed on Vercel.
- [x] Core models and CRUD providers for transactions, accounts, goals,
  invoices, recurring income, recurring expenses, labels, and chat sessions.
- [x] Existing schema migrations through `00005_transaction_labels.sql`.
- [x] Derived account balance (`fn_account_balance`, direction-based) and
  net-worth (`fn_net_worth`) functions.
- [x] Realtime transaction updates, soft deletion, transaction edit history,
  transfer pairing, investment entries, and duplicate prevention.
- [x] Monthly snapshot creation/backfill for prior-month totals.
- [x] Transaction ledger, add/edit form, account filtering, date grouping, and
  pull-to-refresh.
- [x] Briefing/dashboard KPIs, emergency-fund progress, savings rate, account
  balances, and label charts (to be slimmed in Phase 8).
- [x] Goals, invoice drawer, and Agent Desk (Gemini 2.5 Flash, 10 read-only
  tools) user interfaces.
- [x] Removed Android and Windows runners and native SMS listening; retained
  the pure Dart SMS parser for future paste/import workflows.
- [x] Removed the Supabase service-role key from browser configuration.

### Known defects carried into this roadmap (PRD §1)

- [~] D1 — cash expenses recorded against bank accounts (Phase 4). Form enforces
  an explicit visible account; `00011` adds `account_id NOT NULL`; review query
  authored. Historical reassignment is a live owner step.
- [x] D2 — `TRANSFER TO OTHER` label conflates family support with transfers
  (Phase 4). Identity-preserving rename → `FAMILY` + `exclude_from_personal_spend`.
- [x] D3 — multi-label expenses split evenly in reports (Phase 5). Even-split
  removed; full amount attributes to the primary label (Phase 4 groundwork;
  RPC-level enforcement in Phase 5).
- [ ] D4 — full-ledger loading and full reloads on Realtime events (Phase 7).
- [~] D5 — `anon_all` RLS and browser-side `GEMINI_API_KEY` (Phases 2–3). RLS
  replacement authored (`00006`–`00010`); Gemini Edge Function is Phase 3. The
  current Vercel build requirement for the Gemini key is an interim state, not
  the permanent fix.
- [ ] D6 — goal allocation without history or corrections (Phase 6).
- [x] D7 — `find.byDisplayValue` breaks the test gate (Phase 1). Fixed:
  replaced with an `EditableText` predicate finder + tall test surface.
- [ ] D8 — installed-PWA (mobile Brave shortcut) resume blank-screen on WebGL
  context loss (Brave now, Helium/Zen possible future browsers) (Phase 11).

---

## Phase 1: Migration safety and reliable gates

No ownership or policy migration starts until this phase is complete.

### Repair the validation baseline

- [x] Replace the unsupported `find.byDisplayValue` use in
  `test/features/transactions/add_transaction_screen_test.dart` with a
  supported finder or a widget-key assertion.
- [x] Run `flutter pub get`, `flutter analyze`, and `flutter test`; record any
  pre-existing failures before feature work. Result: analyze clean, all tests
  green (fixing D7 also surfaced/fixed a lazy-`ListView` off-screen finder).
- [x] Run a release `flutter build web` with the current required environment to
  prove the pre-migration client still builds. Result: `√ Built build\web`.
- [x] Add one smoke test that boots the app with mocked initialization and one
  model/provider test that proves the test harness can exercise async state.
  Added `test/smoke_test.dart` (boot-failure surface) and
  `test/providers/async_state_test.dart` (loading→data→error transitions).

### Inventory protected data and interfaces

- [x] List every owner-controlled table from all migrations, including
  transactions, transaction-label joins, labels, accounts, goals, invoices,
  category rules, recurring items, monthly snapshots, and chat sessions.
  (See `docs/phase1-inventory.md`.)
- [x] List every view, function, trigger, Realtime publication, storage bucket,
  and client query that can expose or mutate owner data.
  (See `docs/phase1-inventory.md`; no views or storage buckets exist.)
- [x] Record current unique constraints and foreign keys that need `user_id` in
  their key, especially snapshot month/year and case-insensitive label names.
  (See `docs/phase1-inventory.md` "Keys that must gain `user_id`".)
- [x] Identify all RPCs using `SECURITY DEFINER`; verify each has a fixed
  `search_path`, explicit authorization, least-privilege grants, and no caller-
  supplied owner UUID. (None exist yet — documented as a Phase 2+ requirement.)
- [ ] Capture baseline query counts and payload sizes for first ledger load,
  Briefing load, and Agent Desk context gathering. (Requires live project
  access — deferred to the ops runbook; load *shape* documented in inventory.)

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

> **Status (this branch):** migrations `00006`–`00010` and the Flutter auth gate
> are authored and pass `analyze`/tests. Items needing the live Supabase project
> (owner provisioning, applying migrations, deploy-time verification) are marked
> `[ ]` and covered by `docs/RUNBOOK.md`. `[x]` = code artifact complete.

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

- [x] Create the next additive migration for a private `app_owner` registry
  referencing `auth.users(id)` and constrained to one active owner. (`00006`)
- [ ] Insert the known owner UUID during the maintenance window; fail the
  migration if the owner UUID is absent or ambiguous. (Live step — RUNBOOK §2;
  `00007` backfill raises if the owner row is absent.)
- [x] Add a private owner-check helper based on `auth.uid()` with a fixed
  `search_path`; revoke direct execution or table access not needed by client
  roles. (`app_is_owner()`, SECURITY DEFINER, granted to `authenticated` only.)
- [x] Make all owner policies and privileged RPCs fail closed when no registry
  row exists. (RLS-enabled `app_owner` with no policies; `app_is_owner()`
  returns false ⇒ every owner policy denies.)
- [x] Add a database assertion that a second active owner cannot be inserted.
  (Partial unique index + `app_owner_single_guard` trigger.)

### 2.3 Add and backfill row ownership

- [x] Add nullable `user_id uuid` columns to every protected table before
  changing policies. (`00007`)
- [x] Backfill every existing row with the registered owner UUID in one reviewed
  transaction and compare table row counts before and after. (`00007` DO block +
  RUNBOOK §3 zero-null verification query.)
- [ ] Detect orphaned join rows and cross-table references before adding stricter
  keys; stop rather than silently deleting data. (Live check — RUNBOOK §3.)
- [x] Add indexes beginning with `user_id` for owner-filtered date, status,
  account, label, and soft-delete query paths. (`00007`)
- [x] Change ownership columns to `NOT NULL` only after zero null rows are
  verified. (`00008`, gated on the RUNBOOK verification query.)
- [x] Add composite owner-aware foreign keys where they prevent cross-owner
  references... (`00008` owner-scoped keys + `enforce_row_owner` trigger; full
  composite FKs revisited as label/goal schema lands in Phases 5–6.)
- [x] Update owner-specific uniqueness: snapshot `(user_id, year, month)`, label
  `(user_id, lower(name))`, SMS hash owner-scoped. (`00008`)
- [x] Ensure triggers copy or validate ownership rather than trusting arbitrary
  client-supplied `user_id` values. (`enforce_row_owner` stamps/immutable-checks.)

### 2.4 Replace open policies

- [x] Remove every `anon_all` policy in the same release that introduces the
  replacement policies. (`00009`)
- [x] Add owner-only `SELECT` policies requiring both `user_id = auth.uid()` and
  membership in `app_owner`. (`00009`)
- [x] Add owner-only `INSERT` policies with equivalent `WITH CHECK` expressions.
  (`00009`)
- [x] Add owner-only `UPDATE` policies with both `USING` and `WITH CHECK` so an
  update cannot transfer row ownership. (`00009`)
- [x] Keep physical `DELETE` revoked and expose only audited soft-delete updates
  or RPCs. (`00009` creates no DELETE policy + `REVOKE DELETE`.)
- [x] Apply equivalent ownership controls to storage objects if attachments or
  other user files already exist. (No storage buckets exist — no-op, per
  `docs/phase1-inventory.md`.)
- [ ] Recheck Realtime: authenticated changes are delivered to the owner while
  anonymous and non-owner subscribers receive no finance rows. (Live verify —
  RUNBOOK §3 + `rls_owner_scoping.sql`.)

### 2.5 Scope functions and aggregates

- [x] Update account-balance and net-worth functions to derive the owner from
  `auth.uid()` and never accept a trusted `user_id` from the browser. (`00010`)
- [~] Scope transaction, label, snapshot, recurring, goal, invoice, chat, and
  future analytics RPCs to the authenticated owner. (Balance/net-worth done in
  `00010`; the aggregate/save RPCs are authored in their own phases: Phase 5
  `save_transaction_with_labels`, Phase 6 `contribute_to_goal`, Phase 7
  `get_briefing_summary`/`get_analytics`.)
- [x] Reject anonymous, non-owner, and owner-registry-missing calls before any
  query executes. (`app_is_owner()` guard raises `42501` first.)
- [x] Restrict function grants to `authenticated`; revoke unintended `anon` and
  `public` execution. (`00010`)
- [x] Preserve soft-delete filtering and double-entry behavior inside all revised
  functions. (`00010` keeps `is_deleted=false` + `direction` legs.)

### 2.6 Implement the Flutter auth gate

- [x] Add typed auth state for initializing, signed out, callback processing,
  authenticated owner, authenticated non-owner, and recoverable error.
  (`OwnerAuthStatus` in `auth_controller.dart`.)
- [x] Restore Supabase's persisted browser session before constructing finance
  providers or subscribing to Realtime. (Gate blocks `AppShell`; providers are
  read lazily only inside it.)
- [x] Listen to auth state changes for initial session, token refresh, OAuth or
  magic-link callback, password recovery if enabled, and sign-out.
- [x] Build a focused sign-in screen with Google and email magic-link actions,
  callback progress, resend cooldown, and useful error messages.
  (`sign_in_screen.dart`.)
- [x] Verify owner status after authentication before showing any finance shell;
  present a fail-closed access-denied state to non-owners. (`app_is_owner` RPC +
  `_AccessDenied`.)
- [~] Refresh an expired session on resume and return to sign-in without losing a
  valid unsaved draft when refresh is temporarily offline. (`refreshOwner()`
  present; full resume/draft handling is Phase 11.)
- [x] Add sign-out to the app shell; cancel subscriptions, invalidate owner data,
  clear local drafts/filters, and return to the auth gate. (Masthead sign-out;
  gate rebuild disposes provider scope on sign-out.)
- [x] Prevent finance providers, Agent Desk, and deep links from loading before
  the owner gate succeeds. (All finance screens live under `AppShell`.)

### 2.7 Verify and deploy ownership

- [x] Add database tests proving anonymous and non-owner users cannot select,
  insert, update, soft-delete, subscribe to, or invoke privileged functions.
  (`supabase/tests/rls_owner_scoping.sql` — run against restored-data staging.)
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

> **Status (this branch):** the `agent` Edge Function and the rewired thin Dart
> client are authored; the release bundle is verified free of Gemini/service-role
> material. Deploy (`supabase functions deploy agent`), secret set, key rotation,
> and live JWT/error testing are maintenance-window steps (RUNBOOK §4).

### 3.1 Create the authenticated Edge Function

- [x] Add a Supabase Edge Function for Agent Desk requests and keep all Gemini
  HTTP traffic inside the function. (`supabase/functions/agent/index.ts`)
- [x] Require a valid Supabase bearer JWT and verify the caller against
  `app_owner` before accepting request content. (`app_is_owner` RPC check.)
- [x] Restrict CORS to local development, approved Vercel previews if required,
  and the production origin. (`ALLOWED_ORIGINS` env allowlist.)
- [x] Define a versioned request/response contract for conversation messages,
  tool activity, final answer, retryable errors, and request correlation ID.
- [x] Enforce request size, conversation length, tool-round, and execution-time
  limits; preserve the existing maximum of ten tool rounds. (`MAX_*` consts.)
- [x] Validate roles and content server-side rather than forwarding arbitrary
  Gemini payloads from the browser. (`sanitizeMessages`.)

### 3.2 Move context and tools server-side

- [x] Port Gemini model configuration, system safety rules, the ten tool
  definitions, retry/backoff, and response parsing from `llm_service.dart` to
  the Edge Function.
- [x] Resolve account balances, net worth, transactions, invoices, goals,
  recurring commitments, expected income, and snapshots using owner-scoped
  database calls under the caller's JWT. (Function client bound to the JWT.)
- [x] Keep all money-changing operations absent from the tool registry.
- [~] Update tool semantics to the canonical metrics: label breakdown uses
  primary-label attribution once Phase 5 lands (no even splitting), and
  cash-flow summaries report Income, Total Outflow, Personal Spend, and Family
  Support distinctly once Phase 4 lands. (Cashflow already reports Income/Total
  Outflow/Net Cash Surplus; label breakdown uses primary label when present —
  finalized as Phases 4–5 columns land + are backfilled.)
- [x] Treat model tool arguments as untrusted: validate types, filter bounds,
  dates, pagination limits, and enum values. (`boundedInt`, `decodeArgs`.)
- [x] Return privacy-safe tool progress metadata for a collapsible activity view;
  never return chain-of-thought or raw secrets. (`toolActivity[]`.)
- [x] Ensure failures expose a stable user message and correlation ID without SQL,
  JWT, key, stack-trace, or finance-value leakage.

### 3.3 Remove browser Gemini credentials

- [ ] Store `GEMINI_API_KEY` with `supabase secrets set`, not in repository,
  Flutter assets, Vercel variables, or generated `.env` files. (Live — RUNBOOK §4.)
- [x] Update Flutter Agent Desk code to call the Edge Function with the current
  authenticated session instead of Gemini directly. (`functions.invoke('agent')`.)
- [x] Remove `GEMINI_API_KEY` from `.env.example`, `pubspec.yaml` asset inputs,
  `vercel-build.sh`, `vercel.json`, documentation, and browser request code.
  (Also scrubbed the local `.env` of GEMINI + stray SUPABASE_SERVICE_KEY.)
- [x] Make the Vercel build require only the browser-safe Supabase URL and
  publishable/anon key.
- [x] Search source maps, `build/web`, logs, deployment settings, and Git history
  for exposed Gemini key material. (`build/web` verified clean after scrub.)
- [ ] Rotate the deployed Gemini key after the server-only path is live and revoke
  the old key. (Live — RUNBOOK §4.)

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

## Phase 4: Cash/account correctness and Family support

### 4.1 Enforce explicit account selection (D1)

- [x] Keep the account selector required and always visible in add and edit
  forms; never auto-submit a hidden or implied account. (Existing required
  dropdown with `Select an account` validator.)
- [ ] Pre-suggest the last-used account for convenience while keeping it
  visible and changeable before save. (Deferred convenience — not required for
  correctness; the account is already explicit and validated.)
- [~] Add form affordances that make Cash vs bank selection obvious at entry
  time on a 360-pixel layout. (Dropdown labels each account; account chips are
  a Phase 8/10 UX polish.)
- [x] **Enforce at the schema boundary, not just the form.** Make
  `transactions.account_id` `NOT NULL` in a migration. (`00011`, with a guard
  that fails if null-account rows remain.)
- [~] Verify quick paths added later (quick capture, review flows) route
  through the same explicit-account validation. (Quick capture is Phase 10;
  it will reuse `save_transaction_with_labels`.)

### 4.2 Review misassigned historical rows (no silent rewrites)

- [x] Write a review query listing candidate misassigned rows.
  (`supabase/reports/misassigned_cash_review.sql`.)
- [ ] Surface the review list to the owner; the owner reassigns each row
  through the normal audited edit flow. (Live owner step.)
- [x] Do not bulk-update account IDs; every correction is an individual audited
  edit. (Report is read-only by design; no bulk UPDATE authored.)
- [ ] Re-run account reconciliation after review. (Live — reconcile query in
  the report footer + RUNBOOK.)

### 4.3 Rename `TRANSFER TO OTHER` to `FAMILY` (D2)

- [x] Rename via an identity-preserving `UPDATE labels SET name = 'FAMILY'`.
  (`00011` — same row/id, joins untouched, idempotent.)
- [ ] Record the rename in the label audit log once Phase 5 auditing exists
  (backfill one audit entry). (Wired when Phase 5 label audit lands.)
- [ ] Review legacy rows recorded with the `transfer` type. (Live owner review.)

### 4.4 Add the reporting exclusion flag

- [x] Migration: `labels.exclude_from_personal_spend boolean NOT NULL DEFAULT
  false`; set `true` for `FAMILY`. (`00011`)
- [x] **Restrict the toggle to the `FAMILY` label only.** (`00011`
  `labels_single_exclusion_guard` trigger — at most one excluded label per
  owner, so the reconciliation invariant cannot break.)
- [~] Extend the label model/provider with the flag; expose it in label
  management UI. (Model + provider carry the flag; the management UI toggle is
  built with the Phase 5.11 label-management screen.)
- [x] Implement the canonical metrics (PRD §4) in shared computation code.
  (`lib/core/finance_metrics.dart` — the single source of truth, fully tested.)
- [x] Update Briefing and existing dashboard analytics to report Family Support
  separately and exclude it from Personal Spend. (Briefing metric grid +
  `DashboardAnalytics`; Agent cashflow tool already reports canonical figures.)
- [x] Ensure UI copy never presents Personal Savings After Own Spend as
  retained money. (`FinanceMetrics` doc + Briefing shows Net Cash Surplus as
  the savings figure, not after-own-spend.)

### 4.5 Phase 4 tests

- [~] Cash debit reduces Cash but not Kotak; Kotak debit reduces Kotak but not
  Cash. (`fn_account_balance` derives per-account from `direction` legs;
  covered by `test/core/account_balance_rpc_test.dart` shape + live reconcile.)
- [~] Editing a debit's account from Cash to Kotak moves the derived effect
  correctly. (Falls out of derived balances; live-reconcile after edit.)
- [~] Internal transfers affect both linked accounts and leave net worth
  unchanged. (Derived-balance behavior; live-verify.)
- [x] `FAMILY`-labeled debit counts in Total Outflow and Family Support, and
  never in Personal Spend. (`test/core/finance_metrics_test.dart`.)
- [x] `Total Outflow = Personal Spend + Family Support` for any period.
  (`finance_metrics_test.dart` invariant test.)
- [x] The renamed label keeps its ID and all historical joins. (`00011`
  in-place `UPDATE`; no delete/recreate.)
- [~] Account-filtered ledger and analytics totals reconcile. (Analytics use
  the shared classifier; account-balance reconcile is a live check.)

### Phase 4 exit criteria

- [x] No path can save a transaction without an explicit, visible account,
  enforced at both the form and database level. (Form validator + `00011`
  `account_id NOT NULL`.)
- [ ] Reviewed historical rows reconcile with real account balances. (Live
  owner review — report authored.)
- [x] Family Support is a first-class reported metric, distinct from both
  Personal Spend and internal transfers. (`FinanceMetrics` + Briefing.)

---

## Phase 5: Primary labels, unified auditing, and label lifecycle

> **Status (this branch):** the schema (`00012`) and the full owner-scoped RPC
> layer (`00013`: `save_transaction_with_labels`, `rename_label`,
> `set_label_status`, `merge_labels`, `delete_label`) are authored, each writing
> exactly one audit entry. The model carries `primary_label_id` +
> `PrimaryLabelStatus`, and reports are already double-count-safe (Phase 4). The
> transaction-form primary picker, review queue, and label-management screen
> (5.5, 5.11) plus wiring writes through the RPC remain UI work.

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
- [ ] Extend `TransactionLabel` with lifecycle, merge, and
  `excludeFromPersonalSpend` fields; do not infer primary from list order.
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
- [ ] Include selected labels and primary state in the local form draft once
  Phase 11 draft persistence lands.
- [ ] Display primary status in ledger rows and detail/edit views without making
  contextual labels look like additional spend categories.
- [ ] Add a review queue for unresolved multi-label expenses with owner-scoped
  pagination and a focused assign-primary action.
- [ ] Provide separate filters for `Unlabeled` and `Needs primary label`.

### 5.6 Make reports double-count safe (D3)

- [ ] Update all reporting surfaces, exports, and Agent Desk context to
  attribute each expense's full amount exactly once to its primary label —
  removing the even-split logic in `DashboardAnalytics` and the
  `get_label_breakdown` tool.
- [ ] Bucket zero-label expenses as `Unlabeled` and ambiguous legacy expenses as
  `Needs primary label` until reviewed.
- [ ] Keep contextual labels available for ledger search and analysis filters,
  but never split or duplicate monetary totals across them.
- [ ] Add invariants comparing total expense amount with the sum of primary,
  unlabeled, and unresolved buckets for the same filter set.

### 5.7 Add lifecycle schema and audit records

- [ ] Add label state constrained to `active`, `archived`, `merged`, or `deleted`.
- [ ] Add same-owner `merged_into_id`, `updated_at`, `archived_at`, `merged_at`,
  `deleted_at`, and actor metadata where required.
- [ ] Prevent self-merges, merge cycles, merged-target chains, and references to a
  deleted target.
- [ ] Add owner-scoped, case-insensitive uniqueness for assignable label names.
- [ ] Create immutable label audit records for create, rename, archive, merge,
  restore if supported, soft delete, and `exclude_from_personal_spend` changes.
- [ ] Backfill all existing labels as active without changing IDs or joins.

### 5.8 Implement rename and archive

- [ ] Add an owner-scoped rename RPC that trims/normalizes input, detects names
  case-insensitively, preserves label identity, and records old/new names.
- [ ] Decide and test case-only rename behavior explicitly.
- [ ] Add archive RPC behavior that hides the label from new assignments and
  rules while retaining historical joins, primary references, colors, flags,
  and reports.
- [ ] Keep archived labels visible on historical transactions and offer an
  archived filter in label management.
- [ ] Prevent archived or merged labels from being assigned by transaction save
  RPCs.

### 5.9 Implement atomic merge

- [ ] Add an owner-scoped merge RPC accepting one source and one active target.
- [ ] Lock both labels and all affected primary/join references in a deterministic
  order.
- [ ] Move contextual joins to the target, resolve source/target duplicate joins,
  and migrate every source primary reference to the target.
- [ ] Surface a confirmation when source and target differ on
  `exclude_from_personal_spend`; the target keeps its own flag.
- [ ] Update category rules and recurring-item references where labels are stored
  by ID; add an explicit migration plan if any still use label names.
- [ ] Append affected transaction audit entries containing old/new contextual and
  primary label states.
- [ ] Record a label merge event with source, target, actor, timestamp, and
  affected counts, then mark the source `merged` with `merged_into_id`.
- [ ] Roll back all relationship, audit, and lifecycle changes on any failure.
- [ ] Prove the merge is idempotent or returns a stable already-merged result on
  accidental retry.

### 5.10 Guard label deletion

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

### 5.11 Build label management UI

- [ ] Add active and archived label views with usage counts and primary-usage
  counts.
- [ ] Add rename, archive, merge, and eligible-delete dialogs with clear impact
  summaries and confirmation.
- [ ] Exclude invalid merge targets and preserve form state on recoverable RPC
  errors.
- [ ] Refresh visible labels and patch affected transactions after lifecycle RPCs
  without reloading the full ledger.
- [ ] Provide accessible status text and controls at 360-pixel width.

### Phase 5 exit criteria

- [ ] Every new or edited expense has exactly one valid primary label.
- [ ] Legacy ambiguity is visible and no existing label relationship is lost.
- [ ] One logical edit creates one complete audit entry or changes nothing.
- [ ] Category reports reconcile exactly to filtered spending totals.
- [ ] Rename conflicts are case-insensitive and identity-preserving; archived
  history remains reportable; merge moves references without duplicates;
  referenced labels cannot be deleted.

---

## Phase 6: Goals redesign

### 6.1 Schema and contribution history

- [ ] Migration: add `goals.status` (`active` / `paused` / `completed` /
  `archived`, default `active`), nullable `goals.target_date`, and
  `goals.updated_at`.
- [ ] Migration: create `goal_contributions` (`id`, `goal_id`, `amount`
  positive or negative, `note`, `created_at`, `user_id`). Corrections are new
  negative rows, never edits of old rows.
- [ ] Backfill: one seed contribution per goal equal to its current
  `allocated_amount` (note: "opening allocation"), so history and totals
  reconcile from day one.
- [ ] Add one transactional RPC (`contribute_to_goal` or equivalent) that
  inserts the contribution and updates/derives the allocated total atomically;
  reject any contribution that would make the total negative.
- [ ] Reallocation between goals runs as one transaction: negative entry on the
  source, positive entry on the target, both audited.
- [ ] Add a drift assertion: stored `allocated_amount` (if retained) always
  equals the sum of non-deleted contributions.

### 6.2 Goal editing and states

- [ ] Edit goal name, target amount, optional target date, and type where valid
  through audited updates.
- [ ] Warn before reducing the target below the currently allocated amount.
- [ ] Allow overfunding only after explicit confirmation.
- [ ] Auto-mark `completed` when the funded amount reaches the target; allow
  manual pause/archive/restore transitions.
- [ ] Soft-delete only a goal with no contribution history; otherwise offer
  Archive.
- [ ] Keep the Emergency Fund pinned above custom goals by `type`.

### 6.3 Goal UI

- [ ] Compact goal-detail view: saved, target, remaining, % funded, latest
  allocation, edit actions, and allocation history list.
- [ ] Add-funds, correct/remove-allocation, and reallocate dialogs with clear
  confirmation copy ("earmarks existing money; no account balance changes").
- [ ] Status controls (pause, complete, archive, restore) with the newsprint
  design language at 360-pixel width.
- [ ] Show estimated completion only when ≥ 3 contributions across ≥ 2 distinct
  months exist; otherwise show "not enough history".

### 6.4 Agent context

- [ ] Update Agent Desk goal tools/context to include status, target date,
  contribution pace, and the earmarking rule; the agent explains progress and
  affordability but has no allocation-modifying tool.

### 6.5 Phase 6 tests

- [ ] Contribution history always reconciles with the allocated total.
- [ ] Negative adjustments cannot make a total negative.
- [ ] Reallocation is atomic and conserves the combined earmarked total.
- [ ] Allocation changes no account balance and no net worth.
- [ ] Completion, archive, restore, and safe-delete rules behave as specified.
- [ ] Estimate gating: no estimate from a single allocation.

### Phase 6 exit criteria

- [ ] Every allocation change is a recorded contribution row.
- [ ] Goals are fully editable within the stated guards.
- [ ] Earmarking never touches account balances.

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

- [ ] Replace the full-table query with first-page, next-page, refresh, filter-
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

- [ ] Implement `get_briefing_summary(month)` returning the canonical metrics
  (Income, Total Outflow, Personal Spend, Family Support, Net Cash Surplus,
  savings rate), account balances, unresolved-label counts, and compact
  summaries.
- [ ] Implement `get_account_balances()` as one batch call rather than one RPC per
  account.
- [ ] Implement typed `get_analytics(period, filters)` output covering exactly
  the four approved charts plus the non-chart lists, or narrowly split RPCs if
  payload measurement shows one bundle is too large.
- [ ] Derive owner from `auth.uid()`, validate date/filter limits, exclude soft-
  deleted rows, and apply primary-label attribution and the
  `exclude_from_personal_spend` flag consistently.
- [ ] Version the returned JSON shape and map it to typed Dart DTOs rather than
  passing dynamic maps into widgets.
- [ ] Add SQL tests reconciling aggregate output against known fixture rows and
  the invariant `Total Outflow = Personal Spend + Family Support`.

### 7.5 Complete snapshot strategy

- [ ] Use live transaction rows for the current partial month.
- [ ] Use immutable monthly snapshots for completed historical months and define
  a controlled rebuild path when old transactions are corrected (including the
  Phase 4 account reassignments).
- [ ] Extend snapshot content (additively) so historical months can report the
  canonical metrics without recomputation where derivable; never fabricate
  values for months that predate the data.
- [ ] Add owner-scoped monthly account-balance snapshots recorded at month end or
  first open of the next month.
- [ ] Store source period, calculated timestamp, and schema/calculation version so
  stale snapshots can be identified.
- [ ] Update trend queries to combine historical snapshots with the live current
  month without overlap or gaps.

### 7.6 Reduce rendering and startup work

- [ ] Lazily construct and fetch each app tab; an unvisited tab must not issue
  provider reads or build charts.
- [ ] Render only the active Analytics section and defer below-the-fold chart work
  until needed.
- [ ] Cache/memoize pure analytics transformations by immutable typed inputs and
  rebuild only when source data or filters change.
- [ ] Constrain ledger, form, and chart widths for desktop while preserving a
  readable 360-390 pixel mobile layout.

### 7.7 Measure performance

- [ ] Add privacy-safe timing around app interactive state, first ledger page,
  Briefing RPC, analytics RPC, and chart-ready state.
- [ ] Test with a representative large personal ledger rather than the small
  development dataset.
- [ ] Achieve warm installed-PWA interaction within three seconds and cold
  4G interaction within six seconds on a mid-range mobile device.
- [ ] Achieve Briefing aggregate p95 below 500 ms under the expected dataset.
- [ ] Prove first ledger paint downloads only one page, not full history.

### Phase 7 exit criteria

- [ ] Ledger memory and initial payload are bounded by a 50-row page.
- [ ] Filters/search execute server-side and paginate deterministically.
- [ ] Briefing and charts no longer recalculate the full ledger.
- [ ] Unvisited tabs and inactive analytics sections perform no data fetches.

---

## Phase 8: Briefing slim-down and four-chart Analytics tab

### 8.1 Slim the Briefing tab

- [ ] Reduce Briefing to: Income, Total Outflow, Personal Spend, Family
  Support, Net Cash Surplus, current Net Worth, account balances, upcoming
  obligations (placeholder until Phase 9 provides data), latest transaction
  timestamp, and one concise status message.
- [ ] Remove the monthly trend line chart, daily bar chart, and label pie chart
  from Briefing (their replacements live in Analytics).
- [ ] Render Briefing from `get_briefing_summary`, not client-side full-ledger
  computation.
- [ ] Keep metric strips/cards in the existing newsprint style; no large charts
  on Briefing.

### 8.2 Navigation and typed interfaces

- [ ] Add Analytics as a first-class destination separate from Briefing.
- [ ] Keep five primary mobile destinations by moving invoice access to an
  app-bar/drawer action; do not squeeze six bottom-nav items.
- [ ] Add `AnalyticsPeriod` for 1M, 3M, 6M, 12M, YTD, and All with 12M default.
- [ ] Add typed `AnalyticsQuery`, `AnalyticsFilters`, `AnalyticsBundle`, and
  chart-point DTOs; define currency, timezone boundaries, missing periods, and
  percentage precision in one place.
- [ ] Persist active period, section, and filters locally for 24 hours using the
  Phase 11 draft format (a minimal local store until then).
- [ ] Define ledger drill-down routes carrying date, primary label, contextual
  label, merchant, account, and unresolved filters, with a clear way back to
  the same chart state.

### 8.3 Chart 1 — Monthly Cash Flow

- [ ] Grouped vertical bars: Income vs Total Outflow per month for the selected
  period.
- [ ] Personal Spend and Family Support as supporting KPI values or a toggle —
  never additional permanent bar series.
- [ ] Bar tap opens the ledger filtered to that month and direction.
- [ ] Partial current month clearly identified.

### 8.4 Chart 2 — Spending by Primary Label

- [ ] Sorted horizontal bar chart replacing the pie; label names and exact ₹
  values readable on mobile.
- [ ] Default data: Personal Spend only; visible toggle to include excluded
  outflows (Family).
- [ ] Top seven labels plus `Other`; `Unlabeled` and `Needs primary label`
  shown distinctly with links to the review queue.
- [ ] Label tap opens the filtered ledger; contextual labels never double-count.

### 8.5 Chart 3 — Daily Cumulative Personal Spend

- [ ] Two lines: current month and previous month aligned by day number.
- [ ] No artificial budget or target line; partial current month stops at
  today.
- [ ] Point tap opens that day's ledger entries.

### 8.6 Chart 4 — Net Worth History

- [ ] Line from completed monthly snapshots plus the current live derived
  value; current value clearly marked.
- [ ] **Snapshots must capture net worth as of month-end, not at current
  time.** The existing `MonthlySnapshotJob` calls `fn_net_worth()` which is
  unbounded, so post-month transactions leak into the prior month's snapshot.
  Add an as-of-timestamp parameter to `fn_net_worth()` or compute the snapshot
  value from transactions with `transacted_at <= last day of month`.
- [ ] Repair/invalidate existing `net_worth` snapshot values before treating
  them as historical chart data.
- [ ] Never fabricate or interpolate historical values that data cannot
  support; mark unavailable periods.
- [ ] Point tap shows the relevant month and available account snapshot data.

### 8.7 Non-chart components

- [ ] Account balances as cards or a compact table.
- [ ] Top merchants as a ranked list with values (normalized names once Phase
  10 lands).
- [ ] Goal progress as progress bars and cards; optional tiny contribution
  sparkline only where real history exists.
- [ ] Recurring obligations list (activated by Phase 9).
- [ ] Family Support KPI with ledger drill-down.

### 8.8 Chart usability and accessibility

- [ ] `fl_chart` only; square corners, strong rules, warm paper background,
  readable labels; no gradients, glow, 3D, gauges, or decorative charts; one
  value axis per chart.
- [ ] Render only the selected analytics section; avoid constructing hidden
  charts.
- [ ] Touch-friendly hit targets, tooltips with full currency/date values,
  legends, and selected-point feedback.
- [ ] Accessible text summary and tabular alternative for every chart.
- [ ] Empty and single-point series without exceptions or misleading lines.
- [ ] Test text scaling, keyboard focus on web, color contrast,
  color-independent distinctions, and a 360-pixel viewport.

### 8.9 Analytics correctness tests

- [ ] Verify the four charts against fixtures across all period selectors and
  timezone/month boundaries.
- [ ] Verify historical snapshots and live current-month rows neither overlap
  nor omit a period.
- [ ] Verify primary/context labels cannot double-count expense totals and the
  Family toggle changes only what it claims.
- [ ] Verify top-seven plus `Other` equals the ungrouped total.
- [ ] Verify chart drill-down filters reconcile to the selected value.
- [ ] Golden/widget coverage for each chart and the Briefing in empty,
  populated, error, and 360-pixel layouts.

### Phase 8 exit criteria

- [ ] Briefing is numbers-only and served by one aggregate call.
- [ ] Analytics contains exactly four primary charts, each with a typed data
  source, accessible alternative, and reconciling drill-down.
- [ ] Current and historical calculations use the correct live/snapshot
  boundary.

---

## Phase 9: Upcoming obligations and cash-flow forecast

### 9.1 Upcoming obligations

- [ ] Derive the obligations list from existing `recurring_expenses` and
  `recurring_income` rows; add only additive columns if genuinely needed
  (e.g. `account_id`, `is_paused`).
- [ ] Show name, expected amount, expected date, account if known, days
  remaining, and status: upcoming, expected today, overdue, or confirmed.
- [ ] Mark an obligation confirmed by linking the matching ledger transaction;
  advance `next_due`/`next_expected` on confirmation.
- [ ] Surface the list in Analytics (ordered by due date) and the compact
  version on Briefing.
- [ ] Do not build a separate subscriptions system; a subscription is a
  filtered recurring expense with optional metadata.

### 9.2 Deterministic cash-flow forecast

- [ ] Compute a 30-day projection from: current liquid balances, known
  recurring inflows/outflows, recent average Personal Spend, and explicit
  upcoming obligations.
- [ ] Output projected liquid balance, obligations due before the next expected
  inflow, estimated available amount until then, and the assumptions used.
- [ ] Present as an estimate, never authoritative; no ML.
- [ ] Exclude investment-account value from spendable cash.
- [ ] Show earmarked goal totals as context; never subtract them as departed
  money.

### 9.3 Phase 9 tests

- [ ] Obligation statuses correct across due-date boundaries and confirmations.
- [ ] Forecast reproducible by hand from its stated inputs.
- [ ] Forecast excludes investment balances and does not double-count confirmed
  obligations.

### Phase 9 exit criteria

- [ ] "What's about to hit and what's safe to spend" is answerable from
  Briefing/Analytics without manual arithmetic.

---

## Phase 10: Quick capture and merchant normalization

### 10.1 Quick capture

- [ ] Add a one-field capture input parsing utterances like `250 biryani cash`
  and `500 sent to mummy kotak` into a reviewable draft: amount,
  direction/type, account, merchant/note, primary label, date/time.
- [ ] Deterministic parsing first: amount token, account-name match against the
  owner's accounts, label keyword match, direction keywords. Use Gemini (via
  the Phase 3 Edge Function) only as fallback, still producing only a draft.
- [ ] Always show the parsed draft for confirmation; the confirmed save goes
  through `save_transaction_with_labels` with explicit account and primary
  label validation.
- [ ] Ambiguous input degrades to a partially-filled draft, never a wrong
  silent save.
- [ ] Tests: both example utterances, ambiguous amounts, unknown accounts, and
  fallback behavior.

### 10.2 Merchant normalization

- [ ] Migration: minimal `merchant_aliases` table (`id`, `match_pattern`,
  `canonical_name`, `user_id`, `created_at`).
- [ ] Apply normalization at read time in top-merchant analytics and merchant
  filters; preserve raw merchant/VPA on the transaction for audit.
- [ ] Simple management UI (list/add/remove aliases) as a section, not a new
  screen/tab.
- [ ] Tests: aliased variants roll up to one merchant; raw value remains
  visible on transaction detail; no alias affects amounts.

### Phase 10 exit criteria

- [ ] Capturing a routine cash expense takes one field and one confirmation.
- [ ] Top-merchant analytics show canonical names without losing audit data.

---

## Phase 11: Installed-PWA resume resilience, release, and production acceptance

> Browser-agnostic. The owner uses **Brave** on desktop and accesses the app
> via **Brave → Add to Home Screen** (installed PWA) on mobile. Helium
> (Chromium) or Zen (Firefox-based) are possible future browsers. No recovery
> logic may be hardcoded to one browser engine or to Android. There is no
> native app.

### 11.1 Build a visible web startup surface

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

### 11.2 Correct install metadata

- [ ] Set the production application name, short name, description, background
  color, theme color, display mode, and orientation behavior.
- [ ] Set stable root values for manifest `id`, `start_url`, and `scope`, including
  behavior when a release cache-buster query is present.
- [ ] Generate and reference standard and maskable icons at required PWA sizes;
  verify safe-zone rendering on Android.
- [ ] Check favicon, Apple/mobile metadata where relevant, and installed shortcut
  naming against the production brand.
- [ ] Validate the manifest and service worker in browser application tooling.

### 11.3 Implement the JavaScript/Dart lifecycle handshake

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

### 11.4 Recover application state without reload

- [ ] On healthy resume, refresh the auth session before owner-scoped requests.
- [ ] Detect closed, errored, or stale Realtime channels and recreate only those
  subscriptions instead of duplicating listeners.
- [ ] Revalidate only providers visible in the active tab; debounce duplicate
  lifecycle notifications.
- [ ] Add an offline/stale indicator that distinguishes no network, expired auth,
  Supabase failure, and locally cached display data.
- [ ] Preserve the last usable read state while showing retry controls; do not
  imply stale balances are current.

### 11.5 Persist short-lived UI drafts

- [ ] Define versioned local draft DTOs for transaction form fields, selected
  labels and primary label, quick-capture text, active app tab, active
  analytics section, date range, and analytics filters.
- [ ] Store drafts with owner ID, schema version, saved timestamp, and 24-hour
  expiry; reject malformed, expired, or wrong-owner records.
- [ ] Debounce writes and avoid persisting auth tokens or unnecessary financial
  context beyond the explicitly entered draft.
- [ ] Restore form drafts only after authentication and present a clear resumed-
  draft state.
- [ ] Clear the relevant draft after successful save, explicit cancel, expiry,
  incompatible schema migration, or sign-out.

### 11.6 Installed-PWA resume acceptance

- [ ] Test a production release installed via Brave → Add to Home Screen
  (mobile PWA) on a mid-range device; re-verify in any additional browser
  adopted (e.g. Helium, Zen).
- [ ] Complete ten rapid app switches and 5-minute and 30-minute suspensions.
- [ ] Repeat while online, temporarily offline, and with an expired session.
- [ ] Trigger or simulate WebGL context loss and verify one bounded recovery
  attempt followed by the manual recovery screen if needed.
- [ ] Verify healthy resume within two seconds, watchdog recovery within six
  seconds, no reload loop, and no lost transaction draft.
- [ ] Clear obsolete service-worker caches during rollout and prove the installed
  PWA receives the new release.

### 11.7 Documentation with implementation

- [ ] Update `docs/ARCHITECTURE.md` for auth gate, owner-scoped RLS, Edge Function,
  lifecycle recovery, pagination, aggregate RPCs, and lazy Analytics.
- [ ] Update `docs/DATABASE.md` with ownership columns, composite keys, policies,
  primary labels, lifecycle states, the exclusion flag, goal contributions,
  audits, snapshots, aliases, and migration/backfill invariants.
- [ ] Update `docs/API.md` with authenticated RPC and Edge Function contracts,
  request limits, typed responses, and error codes.
- [ ] Update `docs/PRD.md` completion status per phase.
- [ ] Update `README.md`, `.env.example`, and deployment instructions so Gemini is
  a Supabase function secret and only browser-safe Supabase values reach Vercel.
- [ ] Add an operations runbook for owner provisioning, key rotation, recurring
  backups (the "automated backup" Later item), migration verification, cache
  recovery, snapshot rebuilds, and incident checks.

### 11.8 Automated release gates

- [ ] `flutter pub get` succeeds from a clean checkout.
- [ ] `flutter analyze` reports zero issues.
- [ ] `flutter test` passes all unit, provider, model, and widget tests.
- [ ] Database tests pass against a clean migration and a restored-data fixture.
- [ ] Release `flutter build web` succeeds without `GEMINI_API_KEY` in the build
  environment.
- [ ] Search `build/web` and source maps for service-role and Gemini secrets.
- [ ] Locally serve `build/web` and verify startup, auth callback, refresh, direct
  route, and service-worker update behavior.

### 11.9 Manual security and finance verification

- [ ] Manually exercise owner, anonymous, expired, and non-owner requests through
  the REST API, Realtime, RPCs, and Edge Function.
- [ ] Verify production has no open finance policy, no public privileged function,
  and no physical delete path for client roles.
- [ ] Verify add/edit/soft-delete transactions, transfers, investments, labels,
  goals, contributions, recurring items, snapshots, invoices, quick capture,
  and Agent Desk.
- [ ] Verify balances, Briefing, Analytics, and Agent Desk agree for the same
  known dataset using the canonical metric definitions.
- [ ] Verify no keys, finance values, prompts, or tokens appear in browser errors,
  function errors, crash reports, or lifecycle diagnostics.

### 11.10 Production rollout

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

### 11.11 Seven-day production check

- [ ] Capture every transaction for seven days (quick capture and full form).
- [ ] Review and resolve every `Needs primary label` item generated during the
  period.
- [ ] On day seven, ask Agent Desk: "How much did I earn this week?"
- [ ] On day seven, ask Agent Desk: "What was my Personal Spend vs Family
  Support this week?"
- [ ] On day seven, ask Agent Desk: "Am I closer to funding my Emergency Fund?"
- [ ] Compare all three answers with the raw ledger, aggregate RPC output, and
  Analytics views; all must reconcile.
- [ ] Record any mismatch as a blocking defect rather than adjusting data to fit
  the answer.

### Production-ready definition

- [ ] Existing data is preserved and owner-scoped.
- [ ] Anonymous and non-owner access fails closed.
- [ ] Gemini credentials are server-only.
- [ ] Every transaction sits on its explicitly chosen account; Cash, bank, and
  PayPal balances reconcile.
- [ ] Family Support is reported separately, never inside Personal Spend, never
  as a transfer.
- [ ] Expenses are counted once through primary labels and edits are atomically
  audited.
- [ ] Goal earmarks have full history and never touch account balances.
- [ ] Ledger and charts do not require downloading or recalculating full history.
- [ ] Briefing is numbers-only; Analytics has exactly four reconciling charts.
- [ ] Installed-PWA startup/resume (Brave and any adopted browser) has no
  blank-screen failure in acceptance testing and preserves drafts.
- [ ] All automated gates, manual checks, performance targets, and the seven-day
  production check pass.

---

## Future backlog (outside all committed phases)

### Google Pay screenshot import (deferred)

Reviewed-import only — see `docs/PRD.md` §12 for the workflow and constraints.
Not scheduled; no OCR implementation, no attachment tables, and no preparatory
schema work in the current phases. Acceptance when picked up: zero rows
created without explicit confirmation; dedupe prevents double-import.

### Monthly digest (Later)

Month-in-review generated from the same aggregate RPCs and canonical metrics
as the UI. No separate analytics pipeline.

### Automated recurring backup (Later — operational)

Scheduled Supabase export documented in the runbook (11.7); not a product
screen.
