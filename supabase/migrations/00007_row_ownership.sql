-- ============================================================================
-- 00007: Add nullable user_id to every protected table and backfill (Phase 2.3)
--
-- Additive and forward-only. Columns start NULLABLE so existing rows are not
-- rejected; the backfill assigns them all to the registered owner; NOT NULL and
-- owner-aware keys land in 00008 only after zero-null verification.
--
-- PREREQUISITE: 00006 applied AND an active row exists in app_owner. The
-- backfill DO block raises if not.
-- ============================================================================

-- 1. Add nullable ownership columns -----------------------------------------
ALTER TABLE accounts            ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE transactions        ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE transaction_labels  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE labels              ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE invoices            ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE goals               ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE recurring_expenses  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE recurring_income    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE category_rules      ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE monthly_snapshots   ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE chat_sessions       ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

-- 2. Backfill all existing rows to the single registered owner --------------
DO $$
DECLARE
  owner uuid;
BEGIN
  SELECT user_id INTO owner FROM app_owner WHERE is_active LIMIT 1;
  IF owner IS NULL THEN
    RAISE EXCEPTION
      'No active owner in app_owner. Insert the owner UUID (00006) before backfilling ownership.';
  END IF;

  UPDATE accounts           SET user_id = owner WHERE user_id IS NULL;
  UPDATE transactions       SET user_id = owner WHERE user_id IS NULL;
  UPDATE transaction_labels SET user_id = owner WHERE user_id IS NULL;
  UPDATE labels             SET user_id = owner WHERE user_id IS NULL;
  UPDATE invoices           SET user_id = owner WHERE user_id IS NULL;
  UPDATE goals              SET user_id = owner WHERE user_id IS NULL;
  UPDATE recurring_expenses SET user_id = owner WHERE user_id IS NULL;
  UPDATE recurring_income   SET user_id = owner WHERE user_id IS NULL;
  UPDATE category_rules     SET user_id = owner WHERE user_id IS NULL;
  UPDATE monthly_snapshots  SET user_id = owner WHERE user_id IS NULL;
  UPDATE chat_sessions      SET user_id = owner WHERE user_id IS NULL;
END $$;

-- 3. Owner-first indexes for the hot owner-scoped query paths ----------------
CREATE INDEX IF NOT EXISTS idx_transactions_user_txn_at
  ON transactions (user_id, COALESCE(transacted_at, created_at) DESC, id DESC)
  WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_transactions_user_account
  ON transactions (user_id, account_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_accounts_user           ON accounts (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_labels_user             ON labels (user_id);
CREATE INDEX IF NOT EXISTS idx_transaction_labels_user ON transaction_labels (user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_user           ON invoices (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_goals_user              ON goals (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_recurring_expenses_user ON recurring_expenses (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_recurring_income_user   ON recurring_income (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_monthly_snapshots_user  ON monthly_snapshots (user_id);
CREATE INDEX IF NOT EXISTS idx_chat_sessions_user      ON chat_sessions (user_id);

-- Verification (run manually; every count must be 0):
--   SELECT 'transactions' t, count(*) FROM transactions WHERE user_id IS NULL
--   UNION ALL SELECT 'accounts', count(*) FROM accounts WHERE user_id IS NULL
--   -- ... repeat per table ...
