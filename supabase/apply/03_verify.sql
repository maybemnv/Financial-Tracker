-- ============================================================================
-- VERIFY — read-only. Run in the Supabase SQL Editor AFTER part 2.
-- Every row must read OK.
-- ============================================================================

-- 1. Exactly one active owner -------------------------------------------------
SELECT CASE WHEN count(*) = 1 THEN 'OK' ELSE 'FAIL' END AS single_owner,
       count(*) AS active_owners
FROM app_owner WHERE is_active;

-- 2. No unowned rows survived the backfill ------------------------------------
SELECT CASE WHEN sum(n) = 0 THEN 'OK — every row is owned' ELSE 'FAIL' END AS ownership,
       sum(n) AS unowned_rows
FROM (
  SELECT count(*) n FROM accounts           WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM transactions       WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM transaction_labels WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM labels             WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM invoices           WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM goals              WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM recurring_expenses WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM recurring_income   WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM category_rules     WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM monthly_snapshots  WHERE user_id IS NULL
  UNION ALL SELECT count(*) FROM chat_sessions      WHERE user_id IS NULL
) s;

-- 3. The permissive policy is gone everywhere ---------------------------------
SELECT CASE WHEN count(*) = 0 THEN 'OK — no anon_all policies left' ELSE 'FAIL' END AS rls,
       count(*) AS permissive_policies
FROM pg_policies
WHERE schemaname = 'public' AND policyname = 'anon_all';

-- 4. Every expected function exists -------------------------------------------
SELECT CASE WHEN count(*) = 12 THEN 'OK' ELSE 'FAIL — expected 12' END AS functions,
       count(*) AS found,
       string_agg(proname, ', ' ORDER BY proname) AS names
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND proname IN (
  'app_is_owner', 'save_transaction_with_labels', 'rename_label',
  'set_label_status', 'merge_labels', 'delete_label',
  'contribute_to_goal', 'reallocate_goal_funds', 'update_goal',
  'set_goal_status', 'delete_goal', 'assert_goal_allocation_drift'
);

-- 5. Goal allocation reconciles with its history ------------------------------
-- assert_goal_allocation_drift() returns one row per drifted goal. Empty = OK.
SELECT CASE WHEN count(*) = 0 THEN 'OK — no allocation drift' ELSE 'FAIL' END AS goal_drift,
       count(*) AS drifted_goals
FROM assert_goal_allocation_drift();

-- 6. Every goal with an allocation has an opening contribution ----------------
SELECT CASE WHEN count(*) = 0 THEN 'OK — history seeded' ELSE 'FAIL' END AS goal_history,
       count(*) AS goals_missing_history
FROM goals g
WHERE g.is_deleted = false AND g.allocated_amount <> 0
  AND NOT EXISTS (SELECT 1 FROM goal_contributions c WHERE c.goal_id = g.id);

-- 7. The Family-support invariant has exactly one excluded label --------------
SELECT CASE WHEN count(*) <= 1 THEN 'OK' ELSE 'FAIL — invariant broken' END AS family_flag,
       count(*) AS excluded_labels,
       string_agg(name, ', ') AS names
FROM labels WHERE exclude_from_personal_spend = true;

-- ----------------------------------------------------------------------------
-- Deeper behavioural checks (they write, then roll back) live in:
--   supabase/tests/rls_owner_scoping.sql   — anon/non-owner fail closed
--   supabase/tests/goal_allocation.sql     — allocation invariants
-- Run those with psql, not the SQL Editor: they need \set and role switching.
-- ----------------------------------------------------------------------------
