# Database Schema

Postgres database hosted on Supabase. All tables use UUID primary keys with `gen_random_uuid()`. Timestamps use `timestamptz` with `now()` defaults.

This file documents the **current deployed schema** (migrations `00001`–`00005`) plus a [Planned schema changes](#planned-schema-changes) section for the approved roadmap (`docs/enhancement.md`, `docs/TODO.md`). Canonical financial-metric definitions live in `docs/PRD.md` §4 and bind every aggregate built on this schema.

---

## Table: `transactions`

Core ledger. Every financial event lives here — debits, credits, transfers, and investments.

| Column | Type | Default | Notes |
|---|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `account_id` | `uuid FK` | | References `accounts.id`. Every transaction belongs to an account. |
| `amount` | `numeric` | | Always positive. Direction determined by `direction` column. |
| `type` | `text` | | `debit`, `credit`, `transfer`, or `investment` |
| `direction` | `text` | | `inflow` or `outflow`. Explicit ledger direction — the RPC uses this directly instead of inferring from `type`. Required (non-null) after migration 00004. |
| `vpa` | `text` | `nullable` | UPI VPA (e.g. `user@paytm`, `user@oksbi`) |
| `merchant` | `text` | `nullable` | Merchant name extracted from SMS or manual entry |
| `bank` | `text` | `nullable` | Bank name from SMS |
| `raw_sms` | `text` | `nullable` | Raw SMS text for audit trail. |
| `raw_sms_hash` | `text` | `nullable` | `digest(raw_sms, 'sha256')` — used for duplicate detection instead of comparing full SMS text. |
| `source` | `text` | `'manual'` | `sms` or `manual` |
| `note` | `text` | `nullable` | User memo |
| `usd_amount` | `numeric` | `nullable` | Original USD amount if this was a forex transaction |
| `linked_invoice_id` | `uuid FK` | `nullable` | References `invoices.id`. Connects a PayPal/bank receipt transaction to the invoice it pays. Null for non-freelance transactions. |
| `transfer_group_id` | `uuid` | `nullable` | Links the two rows in a transfer (out + in). Both rows share this value. Queryable — find all legs of a transfer by this ID. |
| `transacted_at` | `timestamptz` | `nullable` | When the money actually moved. User-set via date/time picker in the add form. Falls back to `created_at` for display/balance calculation if null. |
| `is_deleted` | `boolean` | `false` | Soft delete flag |
| `deleted_at` | `timestamptz` | `nullable` | When soft-deleted |
| `edit_history` | `jsonb` | `'[]'` | Immutable audit trail: `[{"old": {...}, "new": {...}, "edited_at": "..."}]` |
| `created_at` | `timestamptz` | `now()` | |
| `updated_at` | `timestamptz` | `now()` | Auto-updated by trigger |

### Constraints

```sql
CHECK (type IN ('debit', 'credit', 'transfer', 'investment'))
CHECK (amount > 0)
CHECK (source IN ('sms', 'manual'))
```

### Type + Direction semantics

`type` captures the semantic kind for reporting; `direction` captures whether the row adds to or subtracts from the account balance. The `fn_account_balance` RPC uses `direction` directly (not `type`), so `credit` rows always have `direction = 'inflow'` and `debit` rows always have `direction = 'outflow'`. Transfers and investments use explicit inflow/outflow per leg.

| Type | `direction` (source leg) | `direction` (destination leg) | Net worth impact |
|---|---|---|---|
| `debit` | `outflow` | — | Decreases |
| `credit` | `inflow` | — | Increases |
| `transfer` | `outflow` | `inflow` | None |
| `investment` | `outflow` | `inflow` | None |

### Indexes

```sql
CREATE INDEX idx_transactions_account_id ON transactions(account_id);
CREATE INDEX idx_transactions_type ON transactions(type);
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
CREATE INDEX idx_transactions_is_deleted ON transactions(is_deleted) WHERE is_deleted = false;
CREATE INDEX idx_transactions_raw_sms_hash ON transactions(raw_sms_hash) WHERE raw_sms_hash IS NOT NULL;
CREATE INDEX idx_transactions_transacted_at ON transactions(transacted_at DESC NULLS LAST);
```

---

## Table: `labels`

Reusable GitHub-style labels. Each has a user-selected color and can be attached to any number of transactions.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `name` | `text` | | Case-insensitive unique name, e.g. `Food`, `Drinks`, `FAMILY` |
| `color` | `text` | | Six-digit hex color, e.g. `#1D76DB` |
| `created_at` | `timestamptz` | `now()` | |

> **Family Support.** The production label previously named `TRANSFER TO OTHER` represents money sent to family. It is renamed to `FAMILY` via an identity-preserving `UPDATE` (same row/ID, all joins retained — never delete-and-recreate). Family payments are normal debit outflows, **not** `transfer`-type rows. Planned: `exclude_from_personal_spend boolean NOT NULL DEFAULT false` (true for `FAMILY`) drives the Personal Spend vs Family Support split through the primary-label system. See [Planned schema changes](#planned-schema-changes).

## Table: `transaction_labels`

Many-to-many join table between transactions and labels. It replaces the retired `transactions.category` and `transactions.tags` fields.

| Column | Type | Notes |
|---|---|---|
| `transaction_id` | `uuid FK` | References `transactions.id` |
| `label_id` | `uuid FK` | References `labels.id` |
| `created_at` | `timestamptz` | Association creation time |

The composite primary key prevents the same label being assigned twice to one transaction.

## Table: `accounts`

Financial accounts the user holds. Every transaction references one of these.

| Column | Type | Default | Notes |
| --- | --- | --- | --- |
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `name` | `text` | | Display name: `SBI`, `Kotak`, `PayPal`, `Cash`, `Nifty 50` |
| `type` | `text` | | `cash`, `bank`, `paypal`, `investment` |
| `opening_balance` | `numeric` | `0` | Balance on `opening_date`. Source of truth is transactions — `balance` is intentionally absent to avoid drift between derived and stored values. |
| `opening_date` | `date` | | Date the opening balance was set. Transactions before this date are excluded from derived balance. |
| `is_deleted` | `boolean` | `false` | Soft delete |
| `deleted_at` | `timestamptz` | `nullable` | |
| `created_at` | `timestamptz` | `now()` | |

### Constraints

```sql
CHECK (type IN ('cash', 'bank', 'paypal', 'investment'))
```

---

## Table: `category_rules`

Rule engine for auto-categorization. **Currently dormant:** the table and Dart model exist, but no client code queries it since categories/tags were replaced by labels (migration `00005`). Retained for the quick-capture deterministic parser (Phase 10); columns will migrate from category/tags to label references when that phase lands.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `match_pattern` | `text` | | Substring match against `vpa` or `merchant` (case-insensitive) |
| `category` | `text` | | The category to assign |
| `tags` | `text[]` | `'{}'` | Tags to append |
| `priority` | `int` | `0` | Lower value = checked first |

### Indexes

```sql
CREATE INDEX idx_category_rules_priority ON category_rules(priority);
```

---

## Table: `goals`

Savings goals with manual allocation tracking.

> **Allocation is earmarking, not money movement.** Allocating to a goal changes no account balance and no net worth — it assigns existing money to a purpose. Today `allocated_amount` is mutated directly by the client (read-then-write, no history — defect D6); the Goals redesign replaces this with a `goal_contributions` history table and one transactional RPC. See [Planned schema changes](#planned-schema-changes).

| Column | Type | Default | Notes |
| --- | --- | --- | --- |
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `name` | `text` | | Goal name, e.g. `Emergency Fund`, `Phone`, `Keyboard` |
| `type` | `text` | `'custom'` | `emergency_fund`, `custom`. Agent and dashboard use this, not the name — renaming "Emergency Fund" to "Oh Shit Fund" won't break anything. |
| `target_amount` | `numeric` | | Target in INR |
| `allocated_amount` | `numeric` | `0` | Running total allocated so far |
| `is_deleted` | `boolean` | `false` | Soft delete |
| `deleted_at` | `timestamptz` | `nullable` | |
| `created_at` | `timestamptz` | `now()` | |

### Computed (client-side)

```dart
fundedPercent = (allocatedAmount / targetAmount) * 100
```

### Indexes

```sql
CREATE INDEX idx_goals_is_deleted ON goals(is_deleted) WHERE is_deleted = false;
```

---

## Table: `invoices`

Freelance invoice tracking with 3-column payout breakdown.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `client` | `text` | | Client name |
| `description` | `text` | `nullable` | Invoice line item or project description |
| `invoiced_usd` | `numeric` | | Amount invoiced in USD |
| `received_paypal` | `numeric` | `0` | Amount received via PayPal (USD) |
| `received_bank` | `numeric` | `0` | Amount received via bank transfer (INR) |
| `paypal_fee` | `numeric` | `nullable` | PayPal fee deducted (USD) |
| `fx_loss` | `numeric` | `nullable` | Loss due to FX conversion (INR) |
| `fx_rate` | `numeric` | `nullable` | Effective INR/USD rate at time of receipt |
| `status` | `text` | `'pending'` | `pending`, `partial`, `paid` |
| `invoice_date` | `date` | | |
| `is_deleted` | `boolean` | `false` | Soft delete |
| `deleted_at` | `timestamptz` | `nullable` | |
| `created_at` | `timestamptz` | `now()` | |
| `updated_at` | `timestamptz` | `now()` | Auto-updated by trigger |

### Constraints

```sql
CHECK (status IN ('pending', 'paid', 'partial'))
```

### Computed (client-side)

```dart
totalReceived = receivedPaypal + receivedBank
outstanding  = invoicedUsd - totalReceived
computedStatus = totalReceived >= invoicedUsd ? 'paid'
               : totalReceived > 0          ? 'partial'
               :                              'pending'
```

---

## Table: `recurring_expenses`

Known recurring outflows. Used by the agent to compute "committed money" — what's already spoken for before the month begins.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `name` | `text` | | e.g. `Spotify`, `SBI SIP`, `Netflix` |
| `amount` | `numeric` | | Per-cycle amount (INR) |
| `frequency` | `text` | | `monthly`, `weekly`, `yearly` |
| `category` | `text` | | e.g. `Subscriptions`, `Investments` |
| `next_due` | `date` | `nullable` | Next expected date |
| `is_deleted` | `boolean` | `false` | Soft delete |
| `deleted_at` | `timestamptz` | `nullable` | |
| `created_at` | `timestamptz` | `now()` | |

---

## Table: `recurring_income`

Expected recurring inflows. Enables agent questions like "How much income should I expect in July?"

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `name` | `text` | | e.g. `Salary`, `Freelance retainer`, `Rent` |
| `amount` | `numeric` | | Per-cycle amount (INR) |
| `frequency` | `text` | | `monthly`, `weekly`, `yearly` |
| `source` | `text` | | e.g. `Employer`, `Client`, `Tenant` |
| `next_expected` | `date` | `nullable` | Next expected date |
| `is_deleted` | `boolean` | `false` | Soft delete |
| `deleted_at` | `timestamptz` | `nullable` | |
| `created_at` | `timestamptz` | `now()` | |

---

## Table: `monthly_snapshots`

Pre-computed monthly aggregates. Avoids recalculating from raw transactions every time a chart loads. One row written per month on first open of the next month.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `month` | `int` | | 1–12 |
| `year` | `int` | | e.g. 2026 |
| `income` | `numeric` | `0` | Total credits this month |
| `expenses` | `numeric` | `0` | Total debits this month |
| `investments` | `numeric` | `0` | Total investments this month |
| `savings` | `numeric` | `0` | income - expenses. Computed client-side in the Flutter model, stored here for query convenience. Not independently updated — if income or expenses change, savings must be recomputed. |
| `savings_rate` | `numeric` | `0` | (savings / income) * 100. Also computed client-side. See savings note. |
| `net_worth` | `numeric` | `0` | End-of-month net worth |
| `recorded_at` | `timestamptz` | `now()` | |

### Constraints

```sql
UNIQUE(month, year)
-- No is_deleted / deleted_at: append-only by design. Rows are never modified after insertion.
```

### Indexes

```sql
CREATE INDEX idx_monthly_snapshots_year_month ON monthly_snapshots(year DESC, month DESC);
```

---

## Table: `chat_sessions`

Persists the Agent Desk (Gemini) message history so context survives app restarts. Currently global with **no `user_id`** (pre-auth design); gains ownership in the Phase 2 migration. The client keeps one rolling session: it loads the most recently updated row on launch and rewrites it after each completed turn.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `messages` | `jsonb` | `'[]'` | OpenAI-compatible message array (Gemini endpoint), including tool-call turns needed for context continuity. |
| `created_at` | `timestamptz` | `now()` | |
| `updated_at` | `timestamptz` | `now()` | Auto-updated by trigger |

### Indexes

```sql
CREATE INDEX idx_chat_sessions_updated ON chat_sessions(updated_at DESC);
```

---

## Helper Functions

### `update_updated_at()`

Trigger function that auto-updates `updated_at` on row changes.

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

Applied to: `transactions`, `invoices`, `chat_sessions`

### `fn_account_balance(p_account_id uuid)`

Returns the derived current balance for an account: `opening_balance + SUM(inflows) - SUM(outflows)` for transactions after `opening_date`. Uses the `direction` column directly (not `type`), so transfer and investment legs with explicit direction are correctly included. Uses `COALESCE(transacted_at, created_at)` for the date filter so backdated entries count correctly. Ignores soft-deleted rows.

```sql
CREATE OR REPLACE FUNCTION fn_account_balance(p_account_id uuid)
RETURNS NUMERIC AS $$
DECLARE
  ob NUMERIC;
  od DATE;
  tx_total NUMERIC;
BEGIN
  SELECT opening_balance, opening_date INTO ob, od
  FROM accounts WHERE id = p_account_id;

  SELECT COALESCE(
    SUM(CASE WHEN direction = 'inflow' THEN amount ELSE -amount END),
    0
  )
  INTO tx_total
  FROM transactions
  WHERE account_id = p_account_id
    AND is_deleted = false
    AND (od IS NULL OR COALESCE(transacted_at, created_at) >= od);

  RETURN COALESCE(ob, 0) + tx_total;
END;
$$ LANGUAGE plpgsql;
```

### `fn_net_worth()`

Returns sum of all account balances (opening + transaction deltas) for cash/bank/paypal accounts minus investment accounts. Uses `fn_account_balance` per account.

```sql
CREATE OR REPLACE FUNCTION fn_net_worth()
RETURNS NUMERIC AS $$
DECLARE
  total NUMERIC;
BEGIN
  SELECT COALESCE(SUM(fn_account_balance(id)), 0) INTO total
  FROM accounts
  WHERE is_deleted = false;
  RETURN total;
END;
$$ LANGUAGE plpgsql;
```

---

## Realtime

| Table | Publication | Enabled |
|---|---|---|
| `transactions` | `supabase_realtime` | Yes |
| `labels` | `supabase_realtime` | Yes (migration `00005`) |
| `transaction_labels` | `supabase_realtime` | Yes (migration `00005`) |

The client also opens channels on `accounts`, `goals`, and `invoices`; add them to the publication as needed:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE accounts;
ALTER PUBLICATION supabase_realtime ADD TABLE goals;
ALTER PUBLICATION supabase_realtime ADD TABLE invoices;
```

---

## Row Level Security

**Current state (defect D5 — being replaced, not an accepted production design):** all tables use open RLS for the single anon key:

```sql
ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON <table> FOR ALL USING (true);
```

Applied to: `transactions`, `labels`, `transaction_labels`, `category_rules`, `goals`, `invoices`, `accounts`, `recurring_expenses`, `recurring_income`, `monthly_snapshots`, `chat_sessions`

**Planned (Phase 2, `docs/TODO.md`):** every `anon_all` policy is replaced by owner-only `SELECT`/`INSERT`/`UPDATE`/soft-delete policies requiring `user_id = auth.uid()` plus membership in a private `app_owner` registry; physical `DELETE` stays revoked; policies fail closed when owner configuration is missing.

---

## Design Rules

These are enforced at the application layer (not in SQL constraints):

| Rule | Description |
|---|---|
| **Soft delete** | Nothing is ever `DELETE FROM`. Use `is_deleted = true` + `deleted_at`. |
| **Immutable history** | Every update appends to `edit_history` JSONB. Previous values are never overwritten silently. |
| **Explicit ledger direction** | Every row has a `direction` column (`inflow`/`outflow`) independent of `type`. The RPC uses `direction` directly so transfer/investment legs are balanced correctly. The model's `isInflow`/`isOutflow` helpers fall back to `type` when `direction` is null for backward compatibility. |
| **Double-entry transfers** | A transfer creates two rows in `transactions` — one with `direction = outflow` from source account, one with `direction = inflow` to destination account — linked by `transfer_group_id`. |
| **Investments are not expenses** | `type = 'investment'` with `direction = outflow` decreases cash balance but does not count as spending in reports. Net worth is unchanged. |
| **Balances are derived, not stored** | `accounts` has `opening_balance` + `opening_date`. Current balance is computed by `fn_account_balance()` as `opening + SUM(inflows) - SUM(outflows)` on transactions after the opening date. No `balance` column to drift out of sync. |
| **Explicit account integrity** | Every transaction belongs to an explicitly selected account (Cash expense → Cash ID, Kotak expense → Kotak ID). The client must never silently substitute a default bank account. A transaction moves the derived balance of exactly its own account; editing the account reverses/reapplies via derivation. Historical misassigned rows are corrected only through individually audited edits, never bulk guesses. |
| **Family Support is spending, not transfer** | `FAMILY`-labeled debits are external outflows: they reduce the paying account, reduce net worth, count in Total Outflow, are excluded from Personal Spend, and never use the `transfer` type. `transfer` is reserved for owner-account moves. |
| **Goal allocation is earmarking** | Goal allocations/contributions never write to `transactions` and never change an account balance or net worth. |
| **AI never modifies data** | No agent function can `UPDATE`, `DELETE`, or `INSERT` transactions, goals, or allocations. Agent is read/classify/summarize/forecast/answer only; any write requires explicit user review and confirmation in the UI. |

---

## Planned schema changes

Approved by `docs/enhancement.md` / `docs/TODO.md`. All additive; all preserve
existing data. Nothing here exists in migrations yet.

| Phase | Change | Justification (correctness reason) |
|---|---|---|
| 2 | `user_id uuid` on every protected table + private `app_owner` registry; owner-aware unique keys (`(user_id, year, month)` snapshots, `(user_id, lower(name))` labels) | Required for owner-only RLS; without it every row is world-readable via the anon key (D5) |
| 5 | `transactions.primary_label_id uuid` (nullable) | Single-attribution spending reports; removes even-split double-counting (D3) |
| 5 | Label lifecycle: `state` (`active`/`archived`/`merged`/`deleted`), `merged_into_id`, timestamps; immutable label audit records | Rename/archive/merge/delete without losing history or joins |
| 4 | `labels.exclude_from_personal_spend boolean NOT NULL DEFAULT false` | Smallest mechanism separating Personal Spend from Family Support (D2); one flag, no taxonomy |
| 6 | `goal_contributions` (`id`, `goal_id`, `amount` ±, `note`, `created_at`, `user_id`); `goals.status`, `goals.target_date`, `goals.updated_at` | Allocation history, corrections, reallocation, pace — direct `allocated_amount` mutation loses history and races (D6). Total derived from (or transactionally consistent with) contributions |
| 7 | Owner-scoped monthly `account_balance_snapshots`; snapshot metadata (source period, calc version) | Per-account net-worth history without fabricating values; identifies stale snapshots |
| 7 | Aggregate RPCs: `get_briefing_summary(month)`, `get_analytics(period, filters)`, `get_account_balances()` | Stops full-ledger recalculation per render (D4); one definition of the canonical metrics |
| 5 | `save_transaction_with_labels` transactional RPC | Atomic field+label+primary writes with exactly one audit entry |
| 10 | `merchant_aliases` (`id`, `match_pattern`, `canonical_name`, `user_id`, `created_at`) | Merchant-variant rollup at read time; raw values preserved for audit |

Explicitly **not** planned: budgets tables, subscription tables (recurring
expenses cover it), attachment tables (would only serve the deferred Google
Pay import), holdings/market-price tables, event-sourcing tables.

---

## Flutter Model Mapping

| Dart Model | File | Table |
|---|---|---|
| `Transaction` | `lib/models/transaction.dart` | `transactions` |
| `CategoryRule` | `lib/models/category_rule.dart` | `category_rules` |
| `Goal` | `lib/models/goal.dart` | `goals` |
| `Invoice` | `lib/models/invoice.dart` | `invoices` |
| `Account` | `lib/models/account.dart` | `accounts` |
| `RecurringExpense` | `lib/models/recurring_expense.dart` | `recurring_expenses` |
| `RecurringIncome` | `lib/models/recurring_income.dart` | `recurring_income` |
| `MonthlySnapshot` | `lib/models/monthly_snapshot.dart` | `monthly_snapshots` |
| `TransactionLabel` | `lib/models/transaction_label.dart` | `labels` (+ `transaction_labels` join) |
| (attachments) | _future backlog_ | Deliberately absent. Would only serve the deferred Google Pay screenshot import; not added in the current phases. |

---

## Schema additions by migration (Phases 2–11)

All migrations are additive and forward-only. Ownership and RLS are the primary
access control; every privileged function re-checks `app_is_owner()`.

| # | Adds | Key invariant |
|---|---|---|
| `00006` | `app_owner`, `app_is_owner()` | At most one active owner (partial unique index). Fails closed until seeded. |
| `00007–00008` | `user_id` on every table + backfill + NOT NULL, owner-scoped composite keys | No unowned rows; label name and snapshot period unique **per owner**. |
| `00009` | Owner-only RLS replacing `anon_all`; DELETE revoked from client roles | No physical delete path for `authenticated`. |
| `00010` | `fn_account_balance` / `fn_net_worth` owner-scoped | Balances are derived, never stored. |
| `00011` | `account_id NOT NULL`; `TRANSFER TO OTHER → FAMILY` rename; `exclude_from_personal_spend` | Exactly one label may be excluded (single-exclusion trigger). |
| `00012` | `transactions.primary_label_id`; label lifecycle (`status`, `merged_into_id`, timestamps); `label_audit` | Active-name uniqueness only among assignable labels. |
| `00013`/`00016` | Transaction + label RPCs | One audit entry per logical change; labelled expense needs a primary. |
| `00014`/`00015` | `goals.status`/`target_date`; `goal_contributions`; goal RPCs | Stored allocation = sum of contributions (`assert_goal_allocation_drift`). Never touches account balances. |
| `00017` | Paging + aggregate RPCs; effective-date and merchant indexes | A page is not the ledger — aggregates are whole-ledger. |
| `00018` | `fn_net_worth_asof`; `monthly_snapshots.net_worth_basis`/`calculated_at`/`calc_version`; `app_effective_primary`/`app_effective_excluded`; `get_analytics` | Only `as_of_month_end` snapshots are chartable; legacy values are marked, not fabricated. |
| `00019` | `account_id`/`is_paused`/`confirmed_*` on recurring tables; `confirm_obligation`; `get_forecast_inputs` | A confirmed obligation links its ledger row, so the forecast never double-counts. |
| `00020` | `merchant_aliases`; `app_canonical_merchant`; `get_top_merchants` | Read-time only; raw merchant on each row is never rewritten. |

The effective-primary rule (explicit `primary_label_id`, else the sole attached
label) is defined once in `app_effective_primary` and mirrored by
`Transaction.primaryLabel` in Dart, so attribution cannot drift between the
briefing, analytics, label-usage, and forecast surfaces.
