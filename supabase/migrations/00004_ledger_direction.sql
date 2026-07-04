-- ============================================================================
-- 00004: Add explicit ledger direction for account-balancing correctness.
--
-- Transfers and investments are semantic transaction types, but the balance RPC
-- also needs to know whether each row adds to or subtracts from an account.
-- `direction` captures that as `inflow` or `outflow`.
-- ============================================================================

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS direction TEXT
  CHECK (direction IN ('inflow', 'outflow'));

UPDATE transactions
SET direction = CASE
  WHEN type = 'credit' THEN 'inflow'
  WHEN type = 'debit' THEN 'outflow'
  ELSE direction
END
WHERE direction IS NULL
  AND type IN ('credit', 'debit');

WITH ranked_moves AS (
  SELECT
    id,
    CASE
      WHEN ROW_NUMBER() OVER (
        PARTITION BY transfer_group_id
        ORDER BY created_at, id
      ) = 1 THEN 'outflow'
      ELSE 'inflow'
    END AS derived_direction
  FROM transactions
  WHERE direction IS NULL
    AND transfer_group_id IS NOT NULL
    AND type IN ('transfer', 'investment')
)
UPDATE transactions t
SET direction = ranked_moves.derived_direction
FROM ranked_moves
WHERE t.id = ranked_moves.id;

UPDATE transactions
SET direction = 'outflow'
WHERE direction IS NULL
  AND type IN ('transfer', 'investment');

ALTER TABLE transactions
  ALTER COLUMN direction SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transactions_direction
  ON transactions(direction);

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
