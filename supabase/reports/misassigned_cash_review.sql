-- ============================================================================
-- D1 review report (Phase 4.2) — candidate misassigned cash transactions.
--
-- Lists manual debit OUTFLOWS booked against BANK accounts (the pattern where a
-- cash expense was historically recorded on a bank account). NOTHING is
-- rewritten: the owner reviews each row and reassigns it through the normal
-- audited edit flow. Do NOT bulk-update account_id.
--
-- Optionally narrow with note/merchant hints in the WHERE clause.
-- ============================================================================
SELECT
  t.id,
  COALESCE(t.transacted_at, t.created_at) AS occurred_at,
  t.amount,
  a.name  AS booked_account,
  a.type  AS booked_account_type,
  t.merchant,
  t.vpa,
  t.note
FROM transactions t
JOIN accounts a ON a.id = t.account_id
WHERE t.is_deleted = false
  AND t.type = 'debit'
  AND t.direction = 'outflow'
  AND t.source = 'manual'
  AND a.type = 'bank'
  -- AND (t.merchant ILIKE '%cash%' OR t.note ILIKE '%cash%')  -- optional hint
ORDER BY occurred_at DESC;

-- After reassignment, reconcile every account against fn_account_balance:
--   SELECT a.name, fn_account_balance(a.id) AS derived_balance
--   FROM accounts a WHERE a.is_deleted = false ORDER BY a.name;
