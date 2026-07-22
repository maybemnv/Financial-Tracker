-- ============================================================================
-- PREFLIGHT — read-only. Run this in the Supabase SQL Editor BEFORE part 2.
-- It changes nothing. Every row it returns must read OK before you proceed.
-- ============================================================================

-- 1. The one data condition that will stop part 2 -----------------------------
-- 00011 enforces `transactions.account_id NOT NULL` and refuses to guess an
-- account for orphan rows. Reassign them through the app's normal edit flow
-- (audited) before running part 2. `supabase/reports/misassigned_cash_review.sql`
-- lists the rows that likely sit on the wrong account.
SELECT
  CASE WHEN count(*) = 0
       THEN 'OK — every transaction has an account'
       ELSE 'BLOCKED — reassign these before part 2'
  END AS account_integrity,
  count(*) AS null_account_rows
FROM transactions;

-- The offending rows, if any:
SELECT id, created_at, amount, note
FROM transactions
WHERE account_id IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- 2. What part 2 will touch ---------------------------------------------------
SELECT 'accounts' AS table_name, count(*) AS rows FROM accounts
UNION ALL SELECT 'transactions',       count(*) FROM transactions
UNION ALL SELECT 'transaction_labels', count(*) FROM transaction_labels
UNION ALL SELECT 'labels',             count(*) FROM labels
UNION ALL SELECT 'invoices',           count(*) FROM invoices
UNION ALL SELECT 'goals',              count(*) FROM goals
UNION ALL SELECT 'recurring_expenses', count(*) FROM recurring_expenses
UNION ALL SELECT 'recurring_income',   count(*) FROM recurring_income
UNION ALL SELECT 'category_rules',     count(*) FROM category_rules
UNION ALL SELECT 'monthly_snapshots',  count(*) FROM monthly_snapshots
UNION ALL SELECT 'chat_sessions',      count(*) FROM chat_sessions
ORDER BY table_name;

-- 3. The label 00011 renames --------------------------------------------------
-- Expect to see TRANSFER TO OTHER (pre-migration) or FAMILY (post-migration),
-- never both — the rename preserves the row's identity and its joins.
SELECT id, name FROM labels
WHERE lower(name) IN ('transfer to other', 'family');
