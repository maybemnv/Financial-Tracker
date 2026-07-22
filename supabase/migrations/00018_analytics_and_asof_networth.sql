-- ============================================================================
-- 00018: Analytics aggregates + as-of net worth (Phase 8). Additive/forward-only.
-- ============================================================================

-- 0. Shared effective-primary helpers ----------------------------------------
-- The "explicit primary_label_id, else the sole attached label" rule is the
-- single most repeated piece of logic in this schema (00016, 00017 briefing,
-- 00017 label usage, and every chart below). Defined once here so the four
-- surfaces cannot drift apart; mirrors Transaction.primaryLabel in Dart.
CREATE OR REPLACE FUNCTION app_effective_primary(
  p_transaction_id uuid,
  p_primary_label_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    p_primary_label_id,
    CASE WHEN (SELECT count(*) FROM transaction_labels tl
               WHERE tl.transaction_id = p_transaction_id) = 1
         THEN (SELECT tl.label_id FROM transaction_labels tl
               WHERE tl.transaction_id = p_transaction_id LIMIT 1)
    END
  );
$$;

-- True when the row's effective primary label is flagged Family Support.
CREATE OR REPLACE FUNCTION app_effective_excluded(
  p_transaction_id uuid,
  p_primary_label_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((
    SELECT l.exclude_from_personal_spend FROM labels l
    WHERE l.id = app_effective_primary(p_transaction_id, p_primary_label_id)
  ), false);
$$;

-- 1. As-of balances — fixes the snapshot leak (TODO 8.6) -----------------------
-- MonthlySnapshotJob stores last month's row by calling fn_net_worth(), which is
-- unbounded and evaluates at "now". Run it on the 5th and the previous month's
-- snapshot silently includes five days of the new month. Every net-worth history
-- point is therefore wrong by however late the job happened to run.
--
-- These take an explicit cut-off so a historical value means what it says.
CREATE OR REPLACE FUNCTION fn_account_balance_asof(
  p_account_id uuid,
  p_as_of      timestamptz
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE ob NUMERIC; od DATE; tx_total NUMERIC;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  SELECT opening_balance, opening_date INTO ob, od
  FROM accounts
  WHERE id = p_account_id AND user_id = auth.uid() AND is_deleted = false;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- An account opened after the cut-off did not exist yet: contribute nothing
  -- rather than back-dating its opening balance into earlier history.
  IF od IS NOT NULL AND od > p_as_of THEN RETURN 0; END IF;

  SELECT COALESCE(SUM(CASE WHEN direction = 'inflow' THEN amount ELSE -amount END), 0)
  INTO tx_total
  FROM transactions
  WHERE account_id = p_account_id
    AND user_id = auth.uid()
    AND is_deleted = false
    AND (od IS NULL OR COALESCE(transacted_at, created_at) >= od)
    AND COALESCE(transacted_at, created_at) <= p_as_of;

  RETURN COALESCE(ob, 0) + tx_total;
END;
$$;
REVOKE ALL ON FUNCTION fn_account_balance_asof(uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_account_balance_asof(uuid, timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION fn_net_worth_asof(p_as_of timestamptz)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE total NUMERIC;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  SELECT COALESCE(SUM(fn_account_balance_asof(id, p_as_of)), 0) INTO total
  FROM accounts WHERE is_deleted = false AND user_id = auth.uid();
  RETURN total;
END;
$$;
REVOKE ALL ON FUNCTION fn_net_worth_asof(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_net_worth_asof(timestamptz) TO authenticated;

-- 2. Quarantine the snapshots computed the wrong way --------------------------
-- Existing net_worth values cannot be distinguished from correct ones, and the
-- roadmap forbids charting fabricated history. Rather than silently "repair"
-- them with today's numbers, record how each value was produced; the chart then
-- plots only what it can stand behind and marks the rest unavailable.
ALTER TABLE monthly_snapshots
  ADD COLUMN IF NOT EXISTS net_worth_basis TEXT NOT NULL DEFAULT 'unbounded'
    CHECK (net_worth_basis IN ('unbounded', 'as_of_month_end')),
  ADD COLUMN IF NOT EXISTS calculated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS calc_version INT NOT NULL DEFAULT 1;

COMMENT ON COLUMN monthly_snapshots.net_worth_basis IS
  'unbounded = net_worth captured with fn_net_worth() at job run time and may '
  'include transactions after the period (pre-00018 behaviour; not chartable). '
  'as_of_month_end = captured with fn_net_worth_asof(month end).';

-- Recompute historical net worth correctly where the transaction data supports
-- it. This is a derivation from rows that already exist, not a fabrication.
--
-- Written without auth.uid()/fn_net_worth_asof on purpose: a migration runs in
-- the SQL Editor as `postgres` with no JWT, so auth.uid() is NULL and an
-- auth-scoped backfill would match zero rows and appear to succeed.
WITH bounds AS (
  SELECT s.id, s.user_id,
         (make_timestamptz(s.year, s.month, 1, 0, 0, 0)
            + interval '1 month' - interval '1 microsecond') AS month_end
  FROM monthly_snapshots s
  WHERE s.net_worth_basis = 'unbounded'
), computed AS (
  SELECT b.id,
         COALESCE(SUM(COALESCE(a.opening_balance, 0) + COALESCE(tx.total, 0)), 0) AS nw
  FROM bounds b
  JOIN accounts a
    ON a.user_id = b.user_id
   AND a.is_deleted = false
   -- An account opened after the cut-off did not exist yet.
   AND (a.opening_date IS NULL OR a.opening_date <= b.month_end)
  LEFT JOIN LATERAL (
    SELECT SUM(CASE WHEN t.direction = 'inflow' THEN t.amount ELSE -t.amount END) AS total
    FROM transactions t
    WHERE t.account_id = a.id
      AND t.is_deleted = false
      AND (a.opening_date IS NULL OR COALESCE(t.transacted_at, t.created_at) >= a.opening_date)
      AND COALESCE(t.transacted_at, t.created_at) <= b.month_end
  ) tx ON true
  GROUP BY b.id
)
UPDATE monthly_snapshots s
SET net_worth       = c.nw,
    net_worth_basis = 'as_of_month_end',
    calculated_at   = now(),
    calc_version    = 2
FROM computed c
WHERE c.id = s.id;

-- 3. get_analytics -----------------------------------------------------------
-- One typed bundle for the four approved charts. Attribution matches
-- finance_metrics.dart and get_briefing_summary: full amount to the effective
-- primary label, Family Support separated by exclude_from_personal_spend.
CREATE OR REPLACE FUNCTION get_analytics(
  p_months          int     DEFAULT 12,
  p_include_family  boolean DEFAULT false
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
  v_now   timestamptz := now();
  v_month_start timestamptz;
  v_prev_start  timestamptz;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  p_months := LEAST(GREATEST(COALESCE(p_months, 12), 1), 120);

  v_month_start := date_trunc('month', v_now);
  v_prev_start  := v_month_start - interval '1 month';
  v_start := v_month_start - make_interval(months => p_months - 1);

  RETURN jsonb_build_object(
    'version', 1,
    'months', p_months,
    'include_family', p_include_family,
    'generated_at', v_now,

    -- Chart 1: monthly income vs total outflow.
    'cash_flow', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'year', y, 'month', m, 'income', inc, 'outflow', outf,
               'family_support', fam, 'is_partial', (y = EXTRACT(YEAR FROM v_now)::int
                                                 AND m = EXTRACT(MONTH FROM v_now)::int))
             ORDER BY y, m)
      FROM (
        SELECT
          EXTRACT(YEAR  FROM COALESCE(t.transacted_at, t.created_at))::int AS y,
          EXTRACT(MONTH FROM COALESCE(t.transacted_at, t.created_at))::int AS m,
          COALESCE(sum(t.amount) FILTER (WHERE t.type NOT IN ('transfer','investment')
            AND COALESCE(t.direction, CASE WHEN t.type='credit' THEN 'inflow' ELSE 'outflow' END) = 'inflow'), 0) AS inc,
          COALESCE(sum(t.amount) FILTER (WHERE t.type NOT IN ('transfer','investment')
            AND COALESCE(t.direction, CASE WHEN t.type='credit' THEN 'inflow' ELSE 'outflow' END) = 'outflow'), 0) AS outf,
          COALESCE(sum(t.amount) FILTER (WHERE t.type NOT IN ('transfer','investment')
            AND COALESCE(t.direction, CASE WHEN t.type='credit' THEN 'inflow' ELSE 'outflow' END) = 'outflow'
            AND app_effective_excluded(t.id, t.primary_label_id)), 0) AS fam
        FROM transactions t
        WHERE t.user_id = v_owner AND t.is_deleted = false
          AND COALESCE(t.transacted_at, t.created_at) >= v_start
        GROUP BY y, m
      ) mo
    ), '[]'::jsonb),

    -- Chart 2: spend by effective primary label over the window.
    'by_label', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'label_id', label_id, 'name', name, 'amount', amount,
               'excluded', excluded, 'bucket', bucket)
             ORDER BY amount DESC)
      FROM (
        SELECT
          l.id AS label_id,
          COALESCE(l.name,
            CASE WHEN cnt = 0 THEN 'Unlabeled' ELSE 'Needs primary label' END) AS name,
          sum(t.amount) AS amount,
          COALESCE(l.exclude_from_personal_spend, false) AS excluded,
          CASE WHEN l.id IS NOT NULL THEN 'label'
               WHEN cnt = 0 THEN 'unlabeled'
               ELSE 'needs_primary' END AS bucket
        FROM (
          SELECT t2.*, app_effective_primary(t2.id, t2.primary_label_id) AS eff,
                 (SELECT count(*) FROM transaction_labels tl WHERE tl.transaction_id = t2.id) AS cnt
          FROM transactions t2
          WHERE t2.user_id = v_owner AND t2.is_deleted = false
            AND t2.type = 'debit'
            AND COALESCE(t2.transacted_at, t2.created_at) >= v_start
        ) t
        LEFT JOIN labels l ON l.id = t.eff
        WHERE p_include_family OR NOT COALESCE(l.exclude_from_personal_spend, false)
        GROUP BY l.id, l.name, l.exclude_from_personal_spend, cnt
      ) b
    ), '[]'::jsonb),

    -- Chart 3: daily cumulative personal spend, this month vs last.
    'daily_spend', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('day', d, 'current', cur, 'previous', prev) ORDER BY d)
      FROM (
        SELECT
          gs.d,
          (SELECT COALESCE(sum(t.amount), 0) FROM transactions t
           WHERE t.user_id = v_owner AND t.is_deleted = false AND t.type = 'debit'
             AND NOT app_effective_excluded(t.id, t.primary_label_id)
             AND COALESCE(t.transacted_at, t.created_at) >= v_month_start
             AND COALESCE(t.transacted_at, t.created_at) <  v_month_start + make_interval(days => gs.d)
             AND EXTRACT(DAY FROM v_now)::int >= gs.d) AS cur,
          (SELECT COALESCE(sum(t.amount), 0) FROM transactions t
           WHERE t.user_id = v_owner AND t.is_deleted = false AND t.type = 'debit'
             AND NOT app_effective_excluded(t.id, t.primary_label_id)
             AND COALESCE(t.transacted_at, t.created_at) >= v_prev_start
             AND COALESCE(t.transacted_at, t.created_at) <  v_prev_start + make_interval(days => gs.d)) AS prev
        FROM generate_series(1, 31) AS gs(d)
      ) dd
      WHERE d <= GREATEST(
        EXTRACT(DAY FROM (v_month_start + interval '1 month' - interval '1 day'))::int,
        EXTRACT(DAY FROM (v_prev_start  + interval '1 month' - interval '1 day'))::int)
    ), '[]'::jsonb),

    -- Chart 4: net worth history. Only snapshots computed as-of month end are
    -- chartable; anything still on the legacy basis is reported as unavailable
    -- rather than drawn as if it were real.
    'net_worth', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'year', s.year, 'month', s.month,
               'value', CASE WHEN s.net_worth_basis = 'as_of_month_end' THEN s.net_worth END,
               'available', s.net_worth_basis = 'as_of_month_end')
             ORDER BY s.year, s.month)
      FROM monthly_snapshots s
      WHERE s.user_id = v_owner
        AND make_timestamptz(s.year, s.month, 1, 0, 0, 0) >= v_start
    ), '[]'::jsonb),
    'net_worth_current', fn_net_worth(),

    -- Non-chart: top merchants over the window.
    'top_merchants', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('merchant', merchant, 'amount', amount, 'count', n)
             ORDER BY amount DESC)
      FROM (
        SELECT COALESCE(NULLIF(btrim(t.merchant), ''), 'Unknown') AS merchant,
               sum(t.amount) AS amount, count(*) AS n
        FROM transactions t
        WHERE t.user_id = v_owner AND t.is_deleted = false AND t.type = 'debit'
          AND COALESCE(t.transacted_at, t.created_at) >= v_start
        GROUP BY 1 ORDER BY 2 DESC LIMIT 10
      ) m
    ), '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION get_analytics(int, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_analytics(int, boolean) TO authenticated;
