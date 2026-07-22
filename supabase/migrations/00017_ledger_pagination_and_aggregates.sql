-- ============================================================================
-- 00017: Server-side ledger paging + owner-scoped aggregates (Phase 7, D4).
--        Replaces "load the whole ledger, filter in Dart" with indexed,
--        cursor-paged queries and single-call summaries. Additive/forward-only.
-- ============================================================================

-- 1. Ordering index ----------------------------------------------------------
-- The ledger orders by *effective* date (when the money actually moved),
-- falling back to created_at, then by id to break ties. Paging compares the
-- same expression, so the index must match it exactly or every page scans.
CREATE INDEX IF NOT EXISTS idx_transactions_owner_effective
  ON transactions (user_id, (COALESCE(transacted_at, created_at)) DESC, id DESC)
  WHERE is_deleted = false;

-- Merchant/note search. pg_trgm may not be available on every plan, so this
-- stays a plain btree on lower(merchant) for prefix matches; the RPC uses
-- ILIKE and falls back to a scan only when a search term is supplied.
CREATE INDEX IF NOT EXISTS idx_transactions_owner_merchant_lower
  ON transactions (user_id, lower(merchant))
  WHERE is_deleted = false;

-- 2. get_transaction_page ----------------------------------------------------
-- Keyset (cursor) pagination: stable under inserts, never duplicates or skips
-- a row the way OFFSET does. The cursor is the last row's (effective_at, id);
-- the next page is everything strictly "less than" that pair in sort order.
--
-- Returns a versioned envelope so the Dart DTO can reject a shape it does not
-- understand instead of silently reading nulls.
CREATE OR REPLACE FUNCTION get_transaction_page(
  p_limit            int         DEFAULT 50,
  p_cursor_at        timestamptz DEFAULT NULL,
  p_cursor_id        uuid        DEFAULT NULL,
  p_account_id       uuid        DEFAULT NULL,
  p_label_id         uuid        DEFAULT NULL,
  p_type             text        DEFAULT NULL,
  p_search           text        DEFAULT NULL,
  p_from             date        DEFAULT NULL,
  p_to               date        DEFAULT NULL,
  p_unresolved       text        DEFAULT NULL   -- 'needs_primary' | 'unlabeled'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_limit int;
  v_rows  jsonb;
  v_count int;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  -- Bound the page size: a caller cannot ask for the whole ledger back.
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);

  IF p_unresolved IS NOT NULL
     AND p_unresolved NOT IN ('needs_primary', 'unlabeled') THEN
    RAISE EXCEPTION 'Unknown unresolved filter: %', p_unresolved;
  END IF;

  WITH filtered AS (
    SELECT
      t.id,
      COALESCE(t.transacted_at, t.created_at) AS effective_at,
      t.amount, t.type, t.direction, t.account_id, t.merchant, t.vpa, t.bank,
      t.note, t.usd_amount, t.transfer_group_id, t.source, t.primary_label_id,
      t.transacted_at, t.created_at, t.raw_sms, t.raw_sms_hash,
      t.linked_invoice_id
    FROM transactions t
    WHERE t.user_id = v_owner
      AND t.is_deleted = false
      AND (p_account_id IS NULL OR t.account_id = p_account_id)
      AND (p_type       IS NULL OR t.type = p_type)
      AND (p_from       IS NULL OR COALESCE(t.transacted_at, t.created_at) >= p_from::timestamptz)
      AND (p_to         IS NULL OR COALESCE(t.transacted_at, t.created_at) <  (p_to + 1)::timestamptz)
      AND (
        p_search IS NULL OR btrim(p_search) = ''
        OR t.merchant ILIKE '%' || btrim(p_search) || '%'
        OR t.note     ILIKE '%' || btrim(p_search) || '%'
        OR t.vpa      ILIKE '%' || btrim(p_search) || '%'
      )
      AND (
        p_label_id IS NULL
        OR EXISTS (
          SELECT 1 FROM transaction_labels tl
          WHERE tl.transaction_id = t.id AND tl.label_id = p_label_id
        )
      )
      -- Unresolved review states. 'needs_primary' is a labelled expense with
      -- no primary and more than one label; a single-label row resolves by
      -- fallback and is deliberately not queued (mirrors Transaction.primaryLabel).
      AND (
        p_unresolved IS NULL
        OR (
          p_unresolved = 'unlabeled'
          AND t.type = 'debit'
          AND NOT EXISTS (SELECT 1 FROM transaction_labels tl WHERE tl.transaction_id = t.id)
        )
        OR (
          p_unresolved = 'needs_primary'
          AND t.type = 'debit'
          AND t.primary_label_id IS NULL
          AND (SELECT count(*) FROM transaction_labels tl WHERE tl.transaction_id = t.id) > 1
        )
      )
      -- Keyset: strictly after the cursor in (effective_at DESC, id DESC).
      AND (
        p_cursor_at IS NULL OR p_cursor_id IS NULL
        OR (COALESCE(t.transacted_at, t.created_at), t.id) < (p_cursor_at, p_cursor_id)
      )
    ORDER BY COALESCE(t.transacted_at, t.created_at) DESC, t.id DESC
    LIMIT v_limit
  )
  SELECT
    COALESCE(jsonb_agg(row_json ORDER BY effective_at DESC, id DESC), '[]'::jsonb),
    count(*)
  INTO v_rows, v_count
  FROM (
    SELECT
      f.effective_at,
      f.id,
      to_jsonb(f) || jsonb_build_object(
        'labels',
        COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id', l.id, 'name', l.name, 'color', l.color,
                   'status', l.status,
                   'exclude_from_personal_spend', l.exclude_from_personal_spend))
          FROM transaction_labels tl
          JOIN labels l ON l.id = tl.label_id
          WHERE tl.transaction_id = f.id
        ), '[]'::jsonb)
      ) AS row_json
    FROM filtered f
  ) s;

  RETURN jsonb_build_object(
    'version', 1,
    'rows', v_rows,
    'has_more', v_count = v_limit,
    'next_cursor',
      CASE WHEN v_count = 0 THEN NULL ELSE jsonb_build_object(
        'at', (v_rows -> (v_count - 1) ->> 'effective_at'),
        'id', (v_rows -> (v_count - 1) ->> 'id')
      ) END
  );
END;
$$;
REVOKE ALL ON FUNCTION get_transaction_page(int, timestamptz, uuid, uuid, uuid, text, text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_transaction_page(int, timestamptz, uuid, uuid, uuid, text, text, date, date, text) TO authenticated;

-- 3. get_account_balances ----------------------------------------------------
-- One call instead of one fn_account_balance() round-trip per account.
CREATE OR REPLACE FUNCTION get_account_balances()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid();
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'version', 1,
    'accounts', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', a.id, 'name', a.name, 'type', a.type,
               'balance', fn_account_balance(a.id))
             ORDER BY a.name)
      FROM accounts a
      WHERE a.user_id = v_owner AND a.is_deleted = false
    ), '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION get_account_balances() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_account_balances() TO authenticated;

-- 3b. get_label_usage --------------------------------------------------------
-- Once the ledger is paged, usage counts can no longer be derived in Dart from
-- loaded rows — a page is not the ledger. The label management screen's impact
-- summaries must count the whole history or they understate what an action
-- affects, so they come from here.
--
-- primary_count / attributed_amount use the same effective-primary fallback as
-- everywhere else: explicit primary_label_id, else the sole attached label.
CREATE OR REPLACE FUNCTION get_label_usage()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid();
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'version', 1,
    'labels', COALESCE((
      WITH effective AS (
        SELECT
          t.id, t.amount, t.type,
          COALESCE(
            t.primary_label_id,
            CASE WHEN (SELECT count(*) FROM transaction_labels tl
                       WHERE tl.transaction_id = t.id) = 1
                 THEN (SELECT tl.label_id FROM transaction_labels tl
                       WHERE tl.transaction_id = t.id LIMIT 1)
            END
          ) AS primary_id
        FROM transactions t
        WHERE t.user_id = v_owner AND t.is_deleted = false
      )
      SELECT jsonb_agg(jsonb_build_object(
               'label_id', l.id,
               'attached_count', (
                 SELECT count(*) FROM transaction_labels tl
                 JOIN transactions t2 ON t2.id = tl.transaction_id
                 WHERE tl.label_id = l.id AND t2.is_deleted = false
                   AND t2.user_id = v_owner),
               'primary_count', (
                 SELECT count(*) FROM effective e
                 WHERE e.primary_id = l.id AND e.type = 'debit'),
               'attributed_amount', COALESCE((
                 SELECT sum(e.amount) FROM effective e
                 WHERE e.primary_id = l.id AND e.type = 'debit'), 0)))
      FROM labels l
      WHERE l.user_id = v_owner
    ), '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION get_label_usage() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_label_usage() TO authenticated;

-- 4. get_briefing_summary ----------------------------------------------------
-- The canonical PRD §4 metrics for one month, computed once server-side so
-- Briefing never walks the ledger. Attribution rules match
-- lib/core/finance_metrics.dart exactly:
--   income        = non-transfer, non-investment inflow
--   total_outflow = non-transfer, non-investment outflow
--   family_support= outflow whose PRIMARY label is exclude_from_personal_spend
--   personal_spend= total_outflow - family_support   (invariant by construction)
-- A single attached label acts as primary when primary_label_id is null, the
-- same fallback the Dart model applies.
CREATE OR REPLACE FUNCTION get_briefing_summary(
  p_month int DEFAULT NULL,
  p_year  int DEFAULT NULL
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
  v_end   timestamptz;
  v_income numeric := 0;
  v_outflow numeric := 0;
  v_family numeric := 0;
  v_invest numeric := 0;
  v_needs_primary int := 0;
  v_unlabeled int := 0;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  p_year  := COALESCE(p_year,  EXTRACT(YEAR  FROM now())::int);
  p_month := COALESCE(p_month, EXTRACT(MONTH FROM now())::int);
  IF p_month < 1 OR p_month > 12 THEN RAISE EXCEPTION 'Month out of range: %', p_month; END IF;
  IF p_year < 1970 OR p_year > 2100 THEN RAISE EXCEPTION 'Year out of range: %', p_year; END IF;

  v_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0);
  v_end   := v_start + interval '1 month';

  WITH scoped AS (
    SELECT
      t.amount, t.type, t.direction,
      -- Effective primary: explicit, else the sole attached label. The count
      -- guard is separate from the fetch because `HAVING count(*) = 1` with a
      -- bare column is not a legal aggregate query.
      COALESCE(
        t.primary_label_id,
        CASE WHEN (SELECT count(*) FROM transaction_labels tl
                   WHERE tl.transaction_id = t.id) = 1
             THEN (SELECT tl.label_id FROM transaction_labels tl
                   WHERE tl.transaction_id = t.id LIMIT 1)
        END
      ) AS effective_primary
    FROM transactions t
    WHERE t.user_id = v_owner
      AND t.is_deleted = false
      AND COALESCE(t.transacted_at, t.created_at) >= v_start
      AND COALESCE(t.transacted_at, t.created_at) <  v_end
  ), classified AS (
    SELECT
      s.amount,
      s.type,
      COALESCE(s.direction, CASE WHEN s.type = 'credit' THEN 'inflow' ELSE 'outflow' END) AS dir,
      COALESCE((SELECT l.exclude_from_personal_spend FROM labels l WHERE l.id = s.effective_primary), false) AS excluded
    FROM scoped s
  )
  SELECT
    COALESCE(sum(amount) FILTER (WHERE type NOT IN ('transfer','investment') AND dir = 'inflow'), 0),
    COALESCE(sum(amount) FILTER (WHERE type NOT IN ('transfer','investment') AND dir = 'outflow'), 0),
    COALESCE(sum(amount) FILTER (WHERE type NOT IN ('transfer','investment') AND dir = 'outflow' AND excluded), 0),
    COALESCE(sum(amount) FILTER (WHERE type = 'investment' AND dir = 'outflow'), 0)
  INTO v_income, v_outflow, v_family, v_invest
  FROM classified;

  -- Review backlog, owner-scoped and not month-bound: it is a standing task.
  SELECT
    count(*) FILTER (
      WHERE t.type = 'debit' AND t.primary_label_id IS NULL
        AND (SELECT count(*) FROM transaction_labels tl WHERE tl.transaction_id = t.id) > 1),
    count(*) FILTER (
      WHERE t.type = 'debit'
        AND NOT EXISTS (SELECT 1 FROM transaction_labels tl WHERE tl.transaction_id = t.id))
  INTO v_needs_primary, v_unlabeled
  FROM transactions t
  WHERE t.user_id = v_owner AND t.is_deleted = false;

  RETURN jsonb_build_object(
    'version', 1,
    'month', p_month,
    'year', p_year,
    'income', v_income,
    'total_outflow', v_outflow,
    'family_support', v_family,
    'personal_spend', v_outflow - v_family,
    'net_cash_surplus', v_income - v_outflow,
    'investments', v_invest,
    'savings_rate', CASE WHEN v_income = 0 THEN 0
                         ELSE ((v_income - v_outflow) / v_income) * 100 END,
    'needs_primary_count', v_needs_primary,
    'unlabeled_count', v_unlabeled
  );
END;
$$;
REVOKE ALL ON FUNCTION get_briefing_summary(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_briefing_summary(int, int) TO authenticated;
