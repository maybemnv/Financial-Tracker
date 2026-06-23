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
| `raw_sms` | `text` | `nullable` | Raw SMS text for audit trail. Used for deduplication. |
| `source` | `text` | `'manual'` | `sms` or `manual` |
| `note` | `text` | `nullable` | User memo |
| `usd_amount` | `numeric` | `nullable` | Original USD amount if this was a forex transaction |
| `linked_invoice_id` | `uuid FK` | `nullable` | References `invoices.id`. Connects a PayPal/bank receipt transaction to the invoice it pays. Null for non-freelance transactions. |
| `transfer_group_id` | `uuid` | `nullable` | Links the two rows in a transfer (out + in). Both rows share this value. Queryable — find all legs of a transfer by this ID. |
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
CREATE INDEX idx_transactions_raw_sms_hash ON transactions(digest(raw_sms, 'sha256')) WHERE raw_sms IS NOT NULL;
```

---

## Table: `accounts`

Financial accounts the user holds. Every transaction references one of these.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | `uuid PK` | `gen_random_uuid()` | |
| `name` | `text` | | Display name: `SBI`, `Kotak`, `PayPal`, `Cash`, `Nifty 50` |
| `type` | `text` | | `cash`, `bank`, `paypal`, `investment` |
| `balance` | `numeric` | `0` | Current balance (manually reconciled or computed) |
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
|---|---|---|---|---|
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
| `savings` | `numeric` | `0` | income - expenses |
| `savings_rate` | `numeric` | `0` | (savings / income) * 100 |
| `net_worth` | `numeric` | `0` | End-of-month net worth |
| `recorded_at` | `timestamptz` | `now()` | |

### Constraints

```sql
UNIQUE(month, year)
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

### `fn_current_balance()`

Returns total credits minus total debits across all transactions (excluding transfers and investments).

```sql
CREATE OR REPLACE FUNCTION fn_current_balance()
RETURNS NUMERIC AS $$
DECLARE
  total_credits NUMERIC;
  total_debits NUMERIC;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO total_credits
  FROM transactions WHERE type = 'credit' AND is_deleted = false;
  SELECT COALESCE(SUM(amount), 0) INTO total_debits
  FROM transactions WHERE type = 'debit' AND is_deleted = false;
  RETURN total_credits - total_debits;
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

Applied to: `transactions`, `category_rules`, `goals`, `invoices`

---

## Design Rules

These are enforced at the application layer (not in SQL constraints):

| Rule | Description |
|---|---|
| **Soft delete** | Nothing is ever `DELETE FROM`. Use `is_deleted = true` + `deleted_at`. |
| **Immutable history** | Every update appends to `edit_history` JSONB. Previous values are never overwritten silently. |
| **Double-entry transfers** | A transfer creates two rows in `transactions` — one `debit` from source account, one `credit` to destination account — linked by `transfer_group_id`. |
| **Investments are not expenses** | `type = 'investment'` decreases cash balance but does not count as spending in reports. Net worth is unchanged. |
| **AI never modifies data** | No agent function can `UPDATE`, `DELETE`, or `INSERT` transactions. Agent is read-only + categorization-only. |

---

## Flutter Model Mapping

| Dart Model | File | Table |
|---|---|---|
| `Transaction` | `lib/models/transaction.dart` | `transactions` |
| `CategoryRule` | `lib/models/category_rule.dart` | `category_rules` |
| `Goal` | `lib/models/goal.dart` | `goals` |
| `Invoice` | `lib/models/invoice.dart` | `invoices` |
| `Account` | _not yet created_ | `accounts` |
| `RecurringExpense` | _not yet created_ | `recurring_expenses` |
| `RecurringIncome` | _not yet created_ | `recurring_income` |
| `MonthlySnapshot` | _not yet created_ | `monthly_snapshots` |
| (attachments) | _backlog_ | Invoice PDFs, receipts, screenshots attached to transactions — not in schema yet. |
