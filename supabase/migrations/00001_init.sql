-- ============================================================================
-- Finance Tracker — initial schema (locked design, DATABASE.md)
-- Applied to an empty project. Idempotent-ish: safe to re-run on a fresh DB.
-- ============================================================================

-- Required for gen_random_uuid() and digest() helpers
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ----------------------------------------------------------------------------
-- accounts: where money lives. Balance is DERIVED (fn_account_balance), never
-- stored, so there is no `balance` column to drift.
-- ----------------------------------------------------------------------------
CREATE TABLE accounts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('cash', 'bank', 'paypal', 'investment')),
  opening_balance NUMERIC NOT NULL DEFAULT 0,
  opening_date    DATE,
  is_deleted      BOOLEAN NOT NULL DEFAULT false,
  deleted_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON accounts FOR ALL USING (true);

-- ----------------------------------------------------------------------------
-- invoices: freelance invoices with 3-column payout breakdown + derived FX.
-- paypal_fee / fx_loss / fx_rate are derived from received amounts (display).
-- ----------------------------------------------------------------------------
CREATE TABLE invoices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client          TEXT NOT NULL,
  description     TEXT,
  invoiced_usd    NUMERIC NOT NULL,
  received_paypal NUMERIC NOT NULL DEFAULT 0,
  received_bank   NUMERIC NOT NULL DEFAULT 0,
  paypal_fee      NUMERIC,
  fx_loss         NUMERIC,
  fx_rate         NUMERIC,
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'partial')),
  invoice_date    DATE,
  is_deleted      BOOLEAN NOT NULL DEFAULT false,
  deleted_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON invoices FOR ALL USING (true);

-- ----------------------------------------------------------------------------
-- transactions: the core ledger. Every financial event — debits, credits,
-- transfers (two linked rows), and investments.
-- ----------------------------------------------------------------------------
CREATE TABLE transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id        UUID REFERENCES accounts(id),
  amount            NUMERIC NOT NULL CHECK (amount > 0),
  type              TEXT NOT NULL CHECK (type IN ('debit', 'credit', 'transfer', 'investment')),
  vpa               TEXT,
  merchant          TEXT,
  bank              TEXT,
  category          TEXT,
  tags              TEXT[] NOT NULL DEFAULT '{}',
  raw_sms           TEXT,
  raw_sms_hash      TEXT,
  source            TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('sms', 'manual')),
  note              TEXT,
  usd_amount        NUMERIC,
  linked_invoice_id UUID REFERENCES invoices(id),
  transfer_group_id UUID,
  is_deleted        BOOLEAN NOT NULL DEFAULT false,
  deleted_at        TIMESTAMPTZ,
  edit_history      JSONB NOT NULL DEFAULT '[]',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON transactions FOR ALL USING (true);

CREATE INDEX idx_transactions_account_id  ON transactions(account_id);
CREATE INDEX idx_transactions_type        ON transactions(type);
CREATE INDEX idx_transactions_created_at  ON transactions(created_at DESC);
CREATE INDEX idx_transactions_category    ON transactions(category);
CREATE INDEX idx_transactions_active      ON transactions(is_deleted) WHERE is_deleted = false;
CREATE INDEX idx_transactions_sms_hash    ON transactions(raw_sms_hash) WHERE raw_sms_hash IS NOT NULL;

-- ----------------------------------------------------------------------------
-- category_rules: rule engine for auto-categorization (priority order).
-- ----------------------------------------------------------------------------
CREATE TABLE category_rules (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_pattern TEXT NOT NULL,
  category      TEXT NOT NULL,
  tags          TEXT[] NOT NULL DEFAULT '{}',
  priority      INT NOT NULL DEFAULT 0
);

ALTER TABLE category_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON category_rules FOR ALL USING (true);

CREATE INDEX idx_category_rules_priority ON category_rules(priority);

-- ----------------------------------------------------------------------------
-- goals: savings goals. type drives dashboard/agent behaviour (not the name).
-- ----------------------------------------------------------------------------
CREATE TABLE goals (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name             TEXT NOT NULL,
  type             TEXT NOT NULL DEFAULT 'custom' CHECK (type IN ('emergency_fund', 'custom')),
  target_amount    NUMERIC NOT NULL,
  allocated_amount NUMERIC NOT NULL DEFAULT 0,
  is_deleted       BOOLEAN NOT NULL DEFAULT false,
  deleted_at       TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON goals FOR ALL USING (true);

CREATE INDEX idx_goals_active ON goals(is_deleted) WHERE is_deleted = false;

-- ----------------------------------------------------------------------------
-- recurring_expenses: known outflows — drives agent "committed money" answers.
-- ----------------------------------------------------------------------------
CREATE TABLE recurring_expenses (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  amount     NUMERIC NOT NULL,
  frequency  TEXT NOT NULL CHECK (frequency IN ('monthly', 'weekly', 'yearly')),
  category   TEXT,
  next_due   DATE,
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE recurring_expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON recurring_expenses FOR ALL USING (true);

-- ----------------------------------------------------------------------------
-- recurring_income: expected inflows — drives "Expected July Income".
-- ----------------------------------------------------------------------------
CREATE TABLE recurring_income (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  amount       NUMERIC NOT NULL,
  frequency    TEXT NOT NULL CHECK (frequency IN ('monthly', 'weekly', 'yearly')),
  source       TEXT,
  next_expected DATE,
  is_deleted   BOOLEAN NOT NULL DEFAULT false,
  deleted_at   TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE recurring_income ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON recurring_income FOR ALL USING (true);

-- ----------------------------------------------------------------------------
-- monthly_snapshots: append-only pre-computed monthly aggregates.
-- Cheaper than recalculating forever. UNIQUE(month, year) prevents dupes.
-- ----------------------------------------------------------------------------
CREATE TABLE monthly_snapshots (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  month        INT NOT NULL CHECK (month BETWEEN 1 AND 12),
  year         INT NOT NULL,
  income       NUMERIC NOT NULL DEFAULT 0,
  expenses     NUMERIC NOT NULL DEFAULT 0,
  investments  NUMERIC NOT NULL DEFAULT 0,
  savings      NUMERIC NOT NULL DEFAULT 0,
  savings_rate NUMERIC NOT NULL DEFAULT 0,
  net_worth    NUMERIC NOT NULL DEFAULT 0,
  recorded_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (month, year)
);

ALTER TABLE monthly_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON monthly_snapshots FOR ALL USING (true);

CREATE INDEX idx_monthly_snapshots_year_month ON monthly_snapshots(year DESC, month DESC);

-- ============================================================================
-- Functions
-- ============================================================================

-- Auto-update updated_at on row changes (transactions, invoices)
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_transactions_updated_at
  BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER set_invoices_updated_at
  BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Derived balance for one account:
--   opening_balance + SUM(credits) - SUM(debits)
-- for transactions after opening_date, excluding transfers/investments and
-- soft-deleted rows. Transfers/investments move money between accounts, so they
-- net to zero across net worth and must not double-count per account.
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
    AND (od IS NULL OR created_at >= od);

  RETURN COALESCE(ob, 0) + tx_total;
END;
$$ LANGUAGE plpgsql;

-- Net worth: SUM of every (non-deleted) account's derived balance.
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

-- ============================================================================
-- Realtime — enable push on the tables the UI subscribes to
-- ============================================================================
ALTER PUBLICATION supabase_realtime ADD TABLE transactions;
ALTER PUBLICATION supabase_realtime ADD TABLE goals;
ALTER PUBLICATION supabase_realtime ADD TABLE invoices;
ALTER PUBLICATION supabase_realtime ADD TABLE accounts;

-- ============================================================================
-- Seed: default accounts so the app is usable immediately. Account CRUD UI is
-- deferred (not a Phase 1 task); the account selector needs rows to work.
-- ============================================================================
INSERT INTO accounts (name, type, opening_balance, opening_date) VALUES
  ('SBI',    'bank',        0, CURRENT_DATE),
  ('Kotak',  'bank',        0, CURRENT_DATE),
  ('PayPal', 'paypal',      0, CURRENT_DATE),
  ('Cash',   'cash',        0, CURRENT_DATE);
