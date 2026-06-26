-- ============================================================================
-- 00002: Clear all data + add transacted_at to transactions
--
-- Run this in the Supabase SQL editor (Dashboard → SQL Editor → New query).
-- It:
--   1. Wipes all rows from every table (fresh start).
--   2. Re-seeds the four default accounts (SBI, Kotak, PayPal, Cash).
--   3. Adds transacted_at TIMESTAMPTZ to transactions — the date/time the
--      money actually moved, set explicitly by the user when adding a
--      transaction. Falls back to created_at for display/balance calc if NULL.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Clear all tables. Order matters: child tables first (FK constraints).
-- ----------------------------------------------------------------------------
TRUNCATE TABLE
  monthly_snapshots,
  recurring_income,
  recurring_expenses,
  category_rules,
  goals,
  transactions,
  invoices,
  accounts
RESTART IDENTITY CASCADE;

-- ----------------------------------------------------------------------------
-- 2. Re-seed default accounts so the account selector is usable immediately.
-- ----------------------------------------------------------------------------
INSERT INTO accounts (name, type, opening_balance, opening_date) VALUES
  ('SBI',    'bank',   0, CURRENT_DATE),
  ('Kotak',  'bank',   0, CURRENT_DATE),
  ('PayPal', 'paypal', 0, CURRENT_DATE),
  ('Cash',   'cash',   0, CURRENT_DATE);

-- ----------------------------------------------------------------------------
-- 3. Add transacted_at column (nullable — SMS-parsed rows won't have it;
--    fn_account_balance falls back to created_at via COALESCE).
-- ----------------------------------------------------------------------------
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS transacted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_transactions_transacted_at
  ON transactions(transacted_at DESC NULLS LAST);

-- ----------------------------------------------------------------------------
-- 4. Update fn_account_balance to respect transacted_at when filtering by
--    opening_date, so backdated entries still count correctly.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_account_balance(p_account_id uuid)
RETURNS NUMERIC AS $$
DECLARE
  ob       NUMERIC;
  od       DATE;
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
