-- ============================================================================
-- 00019: Upcoming obligations (Phase 9.1). Additive/forward-only.
--
-- No new subscriptions system: a subscription is a recurring expense with
-- optional metadata, so everything here hangs off the tables that already
-- exist.
-- ============================================================================

-- 1. Additive columns --------------------------------------------------------
ALTER TABLE recurring_expenses
  ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES accounts(id),
  ADD COLUMN IF NOT EXISTS is_paused BOOLEAN NOT NULL DEFAULT false,
  -- The ledger row that settled the current cycle. Set on confirmation so a
  -- confirmed obligation can never be counted again by the forecast.
  ADD COLUMN IF NOT EXISTS confirmed_transaction_id UUID REFERENCES transactions(id),
  ADD COLUMN IF NOT EXISTS confirmed_for DATE;

ALTER TABLE recurring_income
  ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES accounts(id),
  ADD COLUMN IF NOT EXISTS is_paused BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS confirmed_transaction_id UUID REFERENCES transactions(id),
  ADD COLUMN IF NOT EXISTS confirmed_for DATE;

-- 2. Cycle advance helper ----------------------------------------------------
-- One definition of "next cycle" for both tables and for the Dart projection,
-- so a forecast and a confirmation can never disagree about when something is
-- next due.
CREATE OR REPLACE FUNCTION app_advance_due(p_from date, p_frequency text)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(p_frequency)
    WHEN 'weekly'  THEN p_from + interval '1 week'
    WHEN 'yearly'  THEN p_from + interval '1 year'
    WHEN 'monthly' THEN p_from + interval '1 month'
    ELSE p_from + interval '1 month'
  END::date;
$$;

-- 3. confirm_obligation ------------------------------------------------------
-- Links the ledger transaction that settled this cycle and advances the due
-- date in one transaction. Without the link, a confirmed obligation would keep
-- appearing in the forecast alongside the very transaction that paid it —
-- double-counting the same money.
CREATE OR REPLACE FUNCTION confirm_obligation(
  p_kind           text,   -- 'expense' | 'income'
  p_id             uuid,
  p_transaction_id uuid
)
RETURNS date
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_freq  text;
  v_due   date;
  v_next  date;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  IF p_kind NOT IN ('expense', 'income') THEN
    RAISE EXCEPTION 'Unknown obligation kind: %', p_kind;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM transactions
    WHERE id = p_transaction_id AND user_id = v_owner AND is_deleted = false
  ) THEN
    RAISE EXCEPTION 'That transaction does not exist.';
  END IF;

  IF p_kind = 'expense' THEN
    SELECT frequency, next_due INTO v_freq, v_due FROM recurring_expenses
    WHERE id = p_id AND user_id = v_owner AND is_deleted = false FOR UPDATE;
    IF v_freq IS NULL THEN RAISE EXCEPTION 'Obligation not found.'; END IF;

    v_next := app_advance_due(COALESCE(v_due, CURRENT_DATE), v_freq);
    UPDATE recurring_expenses
    SET confirmed_transaction_id = p_transaction_id,
        confirmed_for = v_due,
        next_due = v_next
    WHERE id = p_id;
  ELSE
    SELECT frequency, next_expected INTO v_freq, v_due FROM recurring_income
    WHERE id = p_id AND user_id = v_owner AND is_deleted = false FOR UPDATE;
    IF v_freq IS NULL THEN RAISE EXCEPTION 'Obligation not found.'; END IF;

    v_next := app_advance_due(COALESCE(v_due, CURRENT_DATE), v_freq);
    UPDATE recurring_income
    SET confirmed_transaction_id = p_transaction_id,
        confirmed_for = v_due,
        next_expected = v_next
    WHERE id = p_id;
  END IF;

  RETURN v_next;
END;
$$;
REVOKE ALL ON FUNCTION confirm_obligation(text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION confirm_obligation(text, uuid, uuid) TO authenticated;

-- 4. Forecast inputs ---------------------------------------------------------
-- The projection itself is computed in Dart so it stays reproducible by hand
-- from stated inputs (TODO 9.2). This returns only the measured inputs it
-- needs, none of them estimated here.
CREATE OR REPLACE FUNCTION get_forecast_inputs(p_lookback_days int DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_days  int;
  v_since timestamptz;
  v_spend numeric;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  v_days := LEAST(GREATEST(COALESCE(p_lookback_days, 90), 7), 365);
  v_since := now() - make_interval(days => v_days);

  -- Personal Spend only: Family Support is real money leaving, but it is
  -- driven by obligation rather than habit, so averaging it into a daily
  -- spending rate would overstate discretionary burn.
  SELECT COALESCE(sum(t.amount), 0) INTO v_spend
  FROM transactions t
  WHERE t.user_id = v_owner AND t.is_deleted = false
    AND t.type = 'debit'
    AND NOT app_effective_excluded(t.id, t.primary_label_id)
    AND COALESCE(t.transacted_at, t.created_at) >= v_since;

  RETURN jsonb_build_object(
    'version', 1,
    'lookback_days', v_days,
    'personal_spend_total', v_spend,
    'personal_spend_per_day', v_spend / v_days,
    -- Liquid only. Investment accounts hold value, not spendable cash, and
    -- counting them would report money the owner cannot actually spend.
    'liquid_balance', COALESCE((
      SELECT sum(fn_account_balance(a.id))
      FROM accounts a
      WHERE a.user_id = v_owner AND a.is_deleted = false
        AND a.type <> 'investment'
    ), 0),
    'investment_balance', COALESCE((
      SELECT sum(fn_account_balance(a.id))
      FROM accounts a
      WHERE a.user_id = v_owner AND a.is_deleted = false
        AND a.type = 'investment'
    ), 0),
    -- Context only: earmarked money has NOT left the accounts, so the forecast
    -- shows it beside the balance and never subtracts it.
    'earmarked_total', COALESCE((
      SELECT sum(g.allocated_amount) FROM goals g
      WHERE g.user_id = v_owner AND g.is_deleted = false AND g.status <> 'archived'
    ), 0)
  );
END;
$$;
REVOKE ALL ON FUNCTION get_forecast_inputs(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_forecast_inputs(int) TO authenticated;
