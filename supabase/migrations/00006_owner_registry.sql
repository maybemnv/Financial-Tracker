-- ============================================================================
-- 00006: Single-owner registry + owner-check helper (Phase 2.2)
--
-- Establishes the one protected owner identity that every later RLS policy and
-- privileged RPC checks against. Additive and forward-only. Fails closed: until
-- a row exists in app_owner, app_is_owner() returns false and every owner-only
-- policy denies access.
--
-- APPLY ORDER: the owner must first create their Supabase Auth account (Google
-- or magic link) so auth.users has their row, then run the INSERT at the bottom
-- with that UUID during the maintenance window. See docs/RUNBOOK.md.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- app_owner: private registry. Constrained to at most one *active* owner.
-- Not exposed to client roles; only the SECURITY DEFINER helper reads it.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_owner (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- At most one active owner ever (partial unique on a constant expression).
CREATE UNIQUE INDEX IF NOT EXISTS uq_app_owner_single_active
  ON app_owner ((true)) WHERE is_active;

ALTER TABLE app_owner ENABLE ROW LEVEL SECURITY;
-- No policies: RLS-enabled with zero policies denies all client access. The
-- helper below is SECURITY DEFINER and bypasses RLS to read it.
REVOKE ALL ON app_owner FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- app_is_owner(): true only when the caller's JWT belongs to the active owner.
-- Fixed search_path, SECURITY DEFINER so it can read the private registry.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_is_owner()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM app_owner
    WHERE user_id = auth.uid() AND is_active
  );
$$;

REVOKE ALL ON FUNCTION app_is_owner() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_is_owner() TO authenticated;

-- ----------------------------------------------------------------------------
-- Guard: a second active owner cannot be inserted. The partial unique index
-- above already enforces this; this trigger yields a clearer error message.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_owner_single_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_active AND EXISTS (
    SELECT 1 FROM app_owner
    WHERE is_active AND user_id <> NEW.user_id
  ) THEN
    RAISE EXCEPTION 'app_owner already has an active owner; this product is single-owner.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_owner_single_guard ON app_owner;
CREATE TRIGGER trg_app_owner_single_guard
  BEFORE INSERT OR UPDATE ON app_owner
  FOR EACH ROW EXECUTE FUNCTION app_owner_single_guard();

-- ----------------------------------------------------------------------------
-- OWNER PROVISIONING — run manually during the maintenance window.
-- Replace the UUID with the owner's auth.users id. Fails if the UUID is absent
-- from auth.users (FK) or if an active owner already exists (trigger).
-- ----------------------------------------------------------------------------
-- INSERT INTO app_owner (user_id, note)
-- VALUES ('00000000-0000-0000-0000-000000000000', 'production owner');
