-- ============================================================================
-- REGISTER THE OWNER — run in the Supabase SQL Editor after 01_owner_registry.
--
-- Edit the ONE line marked below to your sign-in email, then Run.
-- Resolves your auth.users UUID for you, so there is no UUID to hand-copy and
-- no chance of registering the wrong account.
--
-- Safe to re-run: if you are already the owner it reports and does nothing.
-- ============================================================================

DO $$
DECLARE
  -- ▼▼▼ EDIT THIS ▼▼▼
  v_email   text := 'you@example.com';
  -- ▲▲▲ EDIT THIS ▲▲▲
  v_uid     uuid;
  v_matches int;
  v_current uuid;
BEGIN
  v_email := lower(btrim(v_email));

  SELECT count(*) INTO v_matches FROM auth.users WHERE lower(email) = v_email;

  IF v_matches = 0 THEN
    RAISE EXCEPTION
      'No auth.users row for "%". Sign in once with the magic link first, then re-run. (Users present: %)',
      v_email,
      COALESCE((SELECT string_agg(email, ', ') FROM auth.users), 'none');
  END IF;

  IF v_matches > 1 THEN
    RAISE EXCEPTION
      '% accounts share the email "%". Resolve manually — registering the wrong one assigns your whole history to it.',
      v_matches, v_email;
  END IF;

  SELECT id INTO v_uid FROM auth.users WHERE lower(email) = v_email;
  SELECT user_id INTO v_current FROM app_owner WHERE is_active;

  IF v_current = v_uid THEN
    RAISE NOTICE 'Already registered: % (%). Nothing to do.', v_email, v_uid;
    RETURN;
  END IF;

  IF v_current IS NOT NULL THEN
    RAISE EXCEPTION
      'A different owner (%) is already active. This product is single-owner. To replace them, first run:  UPDATE app_owner SET is_active = false;',
      v_current;
  END IF;

  INSERT INTO app_owner (user_id, note) VALUES (v_uid, 'production owner');
  RAISE NOTICE 'Registered % as the owner (%).', v_email, v_uid;
END $$;

-- Confirm: exactly one row, is_active true, and the email you expect.
SELECT o.user_id, u.email, o.note, o.is_active, o.created_at
FROM app_owner o
JOIN auth.users u ON u.id = o.user_id
WHERE o.is_active;
