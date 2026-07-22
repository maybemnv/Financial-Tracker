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
-- Uses to_regclass to skip tables not yet created (e.g. chat_sessions from 00003
-- if that migration is pending). Part 2 (00007) will CREATE IF NOT EXISTS any
-- missing columns, so an empty result here is fine.
SELECT table_name, rows FROM (
  SELECT 'accounts' AS table_name, (SELECT count(*) FROM accounts) AS rows
  WHERE to_regclass('accounts') IS NOT NULL
  UNION ALL
  SELECT 'transactions', (SELECT count(*) FROM transactions)
  WHERE to_regclass('transactions') IS NOT NULL
  UNION ALL
  SELECT 'transaction_labels', (SELECT count(*) FROM transaction_labels)
  WHERE to_regclass('transaction_labels') IS NOT NULL
  UNION ALL
  SELECT 'labels', (SELECT count(*) FROM labels)
  WHERE to_regclass('labels') IS NOT NULL
  UNION ALL
  SELECT 'invoices', (SELECT count(*) FROM invoices)
  WHERE to_regclass('invoices') IS NOT NULL
  UNION ALL
  SELECT 'goals', (SELECT count(*) FROM goals)
  WHERE to_regclass('goals') IS NOT NULL
  UNION ALL
  SELECT 'recurring_expenses', (SELECT count(*) FROM recurring_expenses)
  WHERE to_regclass('recurring_expenses') IS NOT NULL
  UNION ALL
  SELECT 'recurring_income', (SELECT count(*) FROM recurring_income)
  WHERE to_regclass('recurring_income') IS NOT NULL
  UNION ALL
  SELECT 'category_rules', (SELECT count(*) FROM category_rules)
  WHERE to_regclass('category_rules') IS NOT NULL
  UNION ALL
  SELECT 'monthly_snapshots', (SELECT count(*) FROM monthly_snapshots)
  WHERE to_regclass('monthly_snapshots') IS NOT NULL
  UNION ALL
  SELECT 'chat_sessions', (SELECT count(*) FROM chat_sessions)
  WHERE to_regclass('chat_sessions') IS NOT NULL
) s
ORDER BY table_name;

-- 3. The label 00011 renames --------------------------------------------------
-- Expect to see TRANSFER TO OTHER (pre-migration) or FAMILY (post-migration),
-- never both — the rename preserves the row's identity and its joins.
SELECT id, name FROM labels
WHERE lower(name) IN ('transfer to other', 'family')
  AND to_regclass('labels') IS NOT NULL;
