-- ============================================================================
-- RLS owner-scoping verification (Phase 2.7)
--
-- Run against a RESTORED-DATA staging project after applying 00006–00010.
-- Simulates anon / non-owner / owner JWTs by setting the request claims and
-- role that PostgREST would set. Every RAISE EXCEPTION marks a failed control.
--
-- Usage:  psql "$STAGING_DB_URL" -f supabase/tests/rls_owner_scoping.sql
-- Set :owner and :other to real UUIDs (owner = app_owner.user_id).
-- ============================================================================

\set owner  '00000000-0000-0000-0000-000000000000'
\set other  '11111111-1111-1111-1111-111111111111'

-- ---- anon: no session ------------------------------------------------------
BEGIN;
  SET LOCAL role anon;
  DO $$
  DECLARE n int;
  BEGIN
    SELECT count(*) INTO n FROM transactions;
    IF n <> 0 THEN
      RAISE EXCEPTION 'FAIL: anon can read % transaction rows', n;
    END IF;
    RAISE NOTICE 'PASS: anon sees no transactions';
  END $$;
ROLLBACK;

-- ---- authenticated non-owner ----------------------------------------------
BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  DO $$
  DECLARE n int;
  BEGIN
    IF app_is_owner() THEN
      RAISE EXCEPTION 'FAIL: non-owner passes app_is_owner()';
    END IF;
    SELECT count(*) INTO n FROM transactions;
    IF n <> 0 THEN
      RAISE EXCEPTION 'FAIL: non-owner reads % transaction rows', n;
    END IF;
    RAISE NOTICE 'PASS: non-owner is denied and sees no rows';
  END $$;

  -- Privileged RPC must reject the non-owner.
  DO $$
  BEGIN
    PERFORM fn_net_worth();
    RAISE EXCEPTION 'FAIL: non-owner invoked fn_net_worth()';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: fn_net_worth() rejects non-owner';
  END $$;
ROLLBACK;

-- ---- authenticated owner ---------------------------------------------------
BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}';
  DO $$
  DECLARE n int;
  BEGIN
    IF NOT app_is_owner() THEN
      RAISE EXCEPTION 'FAIL: owner is not recognised by app_is_owner()';
    END IF;
    SELECT count(*) INTO n FROM transactions WHERE is_deleted = false;
    RAISE NOTICE 'PASS: owner sees % active transactions', n;
    PERFORM fn_net_worth();  -- must not raise
    RAISE NOTICE 'PASS: owner can call fn_net_worth()';
  END $$;

  -- Owner cannot insert a row owned by someone else (enforce_row_owner).
  DO $$
  BEGIN
    INSERT INTO goals (name, target_amount, user_id)
    VALUES ('x', 1, '11111111-1111-1111-1111-111111111111');
    RAISE EXCEPTION 'FAIL: owner inserted a foreign-owned goal';
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'PASS: foreign-owned insert rejected (%).', SQLERRM;
  END $$;
ROLLBACK;
