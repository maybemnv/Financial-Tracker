-- ============================================================================
-- 00010: Scope balance/net-worth functions to the authenticated owner (2.5)
--
-- Derives the owner from auth.uid(); never accepts a trusted user_id. Fixed
-- search_path, execute granted to authenticated only. SECURITY INVOKER so the
-- owner-only RLS from 00009 also applies to the internal reads (defence in
-- depth alongside the explicit app_is_owner() guard).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_account_balance(p_account_id uuid)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  ob       NUMERIC;
  od       DATE;
  tx_total NUMERIC;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  SELECT opening_balance, opening_date INTO ob, od
  FROM accounts
  WHERE id = p_account_id AND user_id = auth.uid() AND is_deleted = false;

  IF NOT FOUND THEN
    RETURN 0;  -- not owned / not found: reveal nothing
  END IF;

  SELECT COALESCE(SUM(CASE WHEN direction = 'inflow' THEN amount ELSE -amount END), 0)
  INTO tx_total
  FROM transactions
  WHERE account_id = p_account_id
    AND user_id = auth.uid()
    AND is_deleted = false
    AND (od IS NULL OR COALESCE(transacted_at, created_at) >= od);

  RETURN COALESCE(ob, 0) + tx_total;
END;
$$;

CREATE OR REPLACE FUNCTION fn_net_worth()
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  total NUMERIC;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(fn_account_balance(id)), 0) INTO total
  FROM accounts
  WHERE is_deleted = false AND user_id = auth.uid();

  RETURN total;
END;
$$;

REVOKE ALL ON FUNCTION fn_account_balance(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_net_worth()          FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_account_balance(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_net_worth()          TO authenticated;
