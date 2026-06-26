# Database Schema

Postgres database hosted on Supabase. All tables use UUID primary keys with `gen_random_uuid()`. Timestamps use `timestamptz` with `now()` defaults.

---

## Table: `transactions`

Core ledger. Every financial event lives here — debits, credits, transfers, and investments.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `account_id` | `uuid FK` | | References `accounts.id`. Every transaction belongs to an account. |
| `amount` | `numeric` | | Always positive. Direction determined by `type`. |
| `type` | `text` | | `debit`, `credit`, `transfer`, or `investment` |
| `vpa` | `text` | `nullable` | UPI VPA (e.g. `user@paytm`, `user@oksbi`) |
| `merchant` | `text` | `nullable` | Merchant name extracted from SMS or manual entry |
| `bank` | `text` | `nullable` | Bank name from SMS |
| `category` | `text` | `nullable` | One of: Food, Travel, Shopping, Work, Family, Health, Subscriptions, Other, or null until categorized |
| `tags` | `text[]` | `'{}'` | Cross-cutting labels. `career_investment` is a reserved tag — excluded from discretionary spending reports. |
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

### Type semantics

| Type | Effect on source account | Effect on destination | Net worth impact |
|---|---|---|---|
| `debit` | Balance decreases | — | Decreases |
| `credit` | Balance increases | — | Increases |
| `transfer` | Balance decreases | Balance increases (linked row) | None |
| `investment` | Balance decreases | Investment account increases | None |

### Indexes

```sql
CREATE INDEX idx_transactions_account_id ON transactions(account_id);
CREATE INDEX idx_transactions_type ON transactions(type);
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
CREATE INDEX idx_transactions_category ON transactions(category);
CREATE INDEX idx_transactions_is_deleted ON transactions(is_deleted) WHERE is_deleted = false;
CREATE INDEX idx_transactions_raw_sms_hash ON transactions(raw_sms_hash) WHERE raw_sms_hash IS NOT NULL;
CREATE INDEX idx_transactions_transacted_at ON transactions(transacted_at DESC NULLS LAST);
```

---

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

Rule engine for auto-categorization. When a transaction comes in (via SMS), the first matching rule by priority assigns the category and tags.

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
| `received_bank` | `numeric` | `0` | Amount received via bank transfer (USD) |
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

Applied to: `transactions`, `invoices`

### `fn_account_balance(p_account_id uuid)`

Returns the derived current balance for an account: `opening_balance + SUM(credits) - SUM(debits)` for transactions after `opening_date`. Uses `COALESCE(transacted_at, created_at)` for the date filter so backdated entries count correctly. Excludes transfers and investments, ignores soft-deleted rows.

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

  SELECT COALESCE(SUM(CASE WHEN type = 'credit' THEN amount ELSE -amount END), 0)
  INTO tx_total
  FROM transactions
  WHERE account_id = p_account_id
    AND type IN ('debit', 'credit')
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

Additional tables can be added as needed:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE accounts;
ALTER PUBLICATION supabase_realtime ADD TABLE goals;
ALTER PUBLICATION supabase_realtime ADD TABLE invoices;
```

---

## Row Level Security

All tables use open RLS for the single anon key (v1 design — no auth):

```sql
ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON <table> FOR ALL USING (true);
```

Applied to: `transactions`, `category_rules`, `goals`, `invoices`, `accounts`, `recurring_expenses`, `recurring_income`, `monthly_snapshots`

---

## Design Rules

These are enforced at the application layer (not in SQL constraints):

| Rule | Description |
|---|---|
| **Soft delete** | Nothing is ever `DELETE FROM`. Use `is_deleted = true` + `deleted_at`. |
| **Immutable history** | Every update appends to `edit_history` JSONB. Previous values are never overwritten silently. |
| **Double-entry transfers** | A transfer creates two rows in `transactions` — one `debit` from source account, one `credit` to destination account — linked by `transfer_group_id`. |
| **Investments are not expenses** | `type = 'investment'` decreases cash balance but does not count as spending in reports. Net worth is unchanged. |
| **Balances are derived, not stored** | `accounts` has `opening_balance` + `opening_date`. Current balance is computed by `fn_account_balance()` as `opening + SUM(credits) - SUM(debits)` on transactions after the opening date. No `balance` column to drift out of sync. |
| **AI never modifies data** | No agent function can `UPDATE`, `DELETE`, or `INSERT` transactions. Agent is read-only + categorization-only. |

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
| (attachments) | _backlog_ | Invoice PDFs, receipts, screenshots attached to transactions — not in schema yet. |
