-- ============================================================================
-- 00009: Replace every open anon_all policy with owner-only RLS (Phase 2.4)
--
-- Removes the D5 hole. After this migration, only the authenticated owner can
-- read or write finance rows, and only their own. Physical DELETE stays revoked
-- (no DELETE policy is created, so RLS denies it) — deletion is soft-delete via
-- UPDATE only. Deploy the auth-capable client in the SAME window (never leave an
-- anon client pointed at owner-only RLS).
-- ============================================================================

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'accounts','transactions','transaction_labels','labels','invoices','goals',
    'recurring_expenses','recurring_income','category_rules','monthly_snapshots',
    'chat_sessions'
  ] LOOP
    -- Drop the permissive policy.
    EXECUTE format('DROP POLICY IF EXISTS "anon_all" ON %I', t);

    -- Drop our own policies first so this migration is safely re-runnable.
    EXECUTE format('DROP POLICY IF EXISTS owner_select ON %I', t);
    EXECUTE format('DROP POLICY IF EXISTS owner_insert ON %I', t);
    EXECUTE format('DROP POLICY IF EXISTS owner_update ON %I', t);

    -- Owner-only SELECT.
    EXECUTE format($p$
      CREATE POLICY owner_select ON %I FOR SELECT TO authenticated
        USING (user_id = auth.uid() AND app_is_owner())
    $p$, t);

    -- Owner-only INSERT.
    EXECUTE format($p$
      CREATE POLICY owner_insert ON %I FOR INSERT TO authenticated
        WITH CHECK (user_id = auth.uid() AND app_is_owner())
    $p$, t);

    -- Owner-only UPDATE; USING + WITH CHECK both scoped so an update can never
    -- transfer ownership or escape the owner's rows.
    EXECUTE format($p$
      CREATE POLICY owner_update ON %I FOR UPDATE TO authenticated
        USING (user_id = auth.uid() AND app_is_owner())
        WITH CHECK (user_id = auth.uid() AND app_is_owner())
    $p$, t);

    -- No DELETE policy: physical delete stays denied for client roles.
  END LOOP;
END $$;

-- Least privilege at the grant layer too (RLS is the primary control).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'accounts','transactions','transaction_labels','labels','invoices','goals',
    'recurring_expenses','recurring_income','category_rules','monthly_snapshots',
    'chat_sessions'
  ] LOOP
    EXECUTE format('REVOKE ALL ON %I FROM anon', t);
    EXECUTE format('REVOKE DELETE ON %I FROM authenticated', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON %I TO authenticated', t);
  END LOOP;
END $$;
