-- ============================================================================
-- 00020: Merchant normalization (Phase 10.2). Additive/forward-only.
--
-- Normalization is applied at READ time only. The raw merchant/VPA stays on the
-- transaction untouched, so an alias can never rewrite the audit trail — it
-- only changes how rows roll up in analytics.
-- ============================================================================

CREATE TABLE IF NOT EXISTS merchant_aliases (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES auth.users(id),
  -- Case-insensitive substring matched against the raw merchant.
  match_pattern  TEXT NOT NULL,
  canonical_name TEXT NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, lower(match_pattern))
);

CREATE INDEX IF NOT EXISTS idx_merchant_aliases_owner
  ON merchant_aliases (user_id);

ALTER TABLE merchant_aliases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_select ON merchant_aliases;
CREATE POLICY owner_select ON merchant_aliases FOR SELECT TO authenticated
  USING (user_id = auth.uid() AND app_is_owner());
DROP POLICY IF EXISTS owner_insert ON merchant_aliases;
CREATE POLICY owner_insert ON merchant_aliases FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND app_is_owner());
DROP POLICY IF EXISTS owner_delete ON merchant_aliases;
CREATE POLICY owner_delete ON merchant_aliases FOR DELETE TO authenticated
  USING (user_id = auth.uid() AND app_is_owner());

REVOKE ALL ON merchant_aliases FROM anon;
GRANT SELECT, INSERT, DELETE ON merchant_aliases TO authenticated;

DROP TRIGGER IF EXISTS trg_enforce_owner ON merchant_aliases;
CREATE TRIGGER trg_enforce_owner BEFORE INSERT OR UPDATE ON merchant_aliases
  FOR EACH ROW EXECUTE FUNCTION enforce_row_owner();

-- Canonicalise a raw merchant against the owner's aliases. Longest pattern
-- wins, so a specific rule ("amazon pay") beats a general one ("amazon").
CREATE OR REPLACE FUNCTION app_canonical_merchant(p_owner uuid, p_raw text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT a.canonical_name FROM merchant_aliases a
     WHERE a.user_id = p_owner
       AND p_raw IS NOT NULL
       AND p_raw ILIKE '%' || a.match_pattern || '%'
     ORDER BY length(a.match_pattern) DESC
     LIMIT 1),
    NULLIF(btrim(p_raw), ''),
    'Unknown'
  );
$$;

-- Roll top-merchant analytics up by canonical name. get_analytics keeps its own
-- raw top_merchants for the pre-alias view; this is what the UI calls once
-- aliases exist so the same shop under several spellings totals as one.
CREATE OR REPLACE FUNCTION get_top_merchants(
  p_months int DEFAULT 12,
  p_limit  int DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_start timestamptz;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  p_months := LEAST(GREATEST(COALESCE(p_months, 12), 1), 120);
  p_limit  := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 50);
  v_start := date_trunc('month', now()) - make_interval(months => p_months - 1);

  RETURN jsonb_build_object(
    'version', 1,
    'merchants', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('merchant', merchant, 'amount', amount, 'count', n)
             ORDER BY amount DESC)
      FROM (
        SELECT app_canonical_merchant(v_owner, t.merchant) AS merchant,
               sum(t.amount) AS amount, count(*) AS n
        FROM transactions t
        WHERE t.user_id = v_owner AND t.is_deleted = false AND t.type = 'debit'
          AND COALESCE(t.transacted_at, t.created_at) >= v_start
        GROUP BY 1 ORDER BY 2 DESC LIMIT p_limit
      ) m
    ), '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION get_top_merchants(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_top_merchants(int, int) TO authenticated;
