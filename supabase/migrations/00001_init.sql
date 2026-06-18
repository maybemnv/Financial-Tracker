-- Transactions table
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  amount NUMERIC NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('debit', 'credit')),
  vpa TEXT,
  merchant TEXT,
  bank TEXT,
  category TEXT,
  tags TEXT[] DEFAULT '{}',
  raw_sms TEXT,
  source TEXT DEFAULT 'manual',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON transactions FOR ALL USING (true);

-- Category rules table
CREATE TABLE category_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_pattern TEXT NOT NULL,
  category TEXT NOT NULL,
  tags TEXT[] DEFAULT '{}',
  priority INT DEFAULT 0
);

ALTER TABLE category_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON category_rules FOR ALL USING (true);

-- Goals table
CREATE TABLE goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  target_amount NUMERIC NOT NULL,
  allocated_amount NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON goals FOR ALL USING (true);

-- Invoices table
CREATE TABLE invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client TEXT NOT NULL,
  description TEXT,
  invoiced_usd NUMERIC NOT NULL,
  received_paypal NUMERIC DEFAULT 0,
  received_bank NUMERIC DEFAULT 0,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'partial')),
  invoice_date DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON invoices FOR ALL USING (true);

-- Auto-update updated_at on row changes
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

-- Enable Realtime for transactions
ALTER PUBLICATION supabase_realtime ADD TABLE transactions;

-- Helper function: current balance (credits - debits)
CREATE OR REPLACE FUNCTION fn_current_balance()
RETURNS NUMERIC AS $$
DECLARE
  total_credits NUMERIC;
  total_debits NUMERIC;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO total_credits FROM transactions WHERE type = 'credit';
  SELECT COALESCE(SUM(amount), 0) INTO total_debits FROM transactions WHERE type = 'debit';
  RETURN total_credits - total_debits;
END;
$$ LANGUAGE plpgsql;
