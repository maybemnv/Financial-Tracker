-- ============================================================================
-- 00014: Goals redesign — contribution history + atomic allocation (Phase 6,
--        fixes D6). Allocation is EARMARKING: it never touches an account
--        balance or net worth. Additive/forward-only.
-- ============================================================================

-- 1. Goal lifecycle columns --------------------------------------------------
ALTER TABLE goals
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'paused', 'completed', 'archived')),
  ADD COLUMN IF NOT EXISTS target_date DATE,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE TRIGGER set_goals_updated_at
  BEFORE UPDATE ON goals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 2. Contribution history (corrections are new negative rows, never edits) ----
CREATE TABLE IF NOT EXISTS goal_contributions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id    UUID NOT NULL REFERENCES goals(id),
  user_id    UUID NOT NULL REFERENCES auth.users(id),
  amount     NUMERIC NOT NULL,     -- positive or negative
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_goal_contributions_owner_goal
  ON goal_contributions (user_id, goal_id, created_at DESC);

ALTER TABLE goal_contributions ENABLE ROW LEVEL SECURITY;
CREATE POLICY owner_select ON goal_contributions FOR SELECT TO authenticated
  USING (user_id = auth.uid() AND app_is_owner());
-- Writes only via the transactional RPCs below.
REVOKE ALL ON goal_contributions FROM anon, authenticated;
GRANT SELECT ON goal_contributions TO authenticated;

DROP TRIGGER IF EXISTS trg_enforce_owner ON goal_contributions;
CREATE TRIGGER trg_enforce_owner BEFORE INSERT OR UPDATE ON goal_contributions
  FOR EACH ROW EXECUTE FUNCTION enforce_row_owner();

-- 3. Seed one opening contribution per goal so history reconciles day one -----
INSERT INTO goal_contributions (goal_id, user_id, amount, note)
SELECT g.id, g.user_id, g.allocated_amount, 'opening allocation'
FROM goals g
WHERE g.allocated_amount <> 0
  AND NOT EXISTS (SELECT 1 FROM goal_contributions c WHERE c.goal_id = g.id);

-- 4. Auto-complete when funded; sync status on allocation change --------------
CREATE OR REPLACE FUNCTION goals_autocomplete()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.allocated_amount >= NEW.target_amount AND NEW.status = 'active' THEN
    NEW.status := 'completed';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_goals_autocomplete ON goals;
CREATE TRIGGER trg_goals_autocomplete
  BEFORE UPDATE OF allocated_amount ON goals
  FOR EACH ROW EXECUTE FUNCTION goals_autocomplete();

-- 5. contribute_to_goal: insert contribution + update total atomically --------
-- Rejects any contribution that would drive the allocated total negative.
CREATE OR REPLACE FUNCTION contribute_to_goal(
  p_goal_id uuid, p_amount numeric, p_note text DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_new numeric;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;
  IF p_amount = 0 THEN RAISE EXCEPTION 'Contribution cannot be zero.'; END IF;

  SELECT allocated_amount + p_amount INTO v_new FROM goals
  WHERE id = p_goal_id AND user_id = v_owner AND is_deleted = false FOR UPDATE;
  IF v_new IS NULL THEN RAISE EXCEPTION 'Goal not found.'; END IF;
  IF v_new < 0 THEN RAISE EXCEPTION 'Allocation cannot go negative.'; END IF;

  INSERT INTO goal_contributions (goal_id, user_id, amount, note)
  VALUES (p_goal_id, v_owner, p_amount, p_note);
  UPDATE goals SET allocated_amount = v_new WHERE id = p_goal_id;
  RETURN v_new;
END;
$$;
REVOKE ALL ON FUNCTION contribute_to_goal(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION contribute_to_goal(uuid, numeric, text) TO authenticated;

-- 6. reallocate_goal_funds: one negative + one positive, atomic ---------------
CREATE OR REPLACE FUNCTION reallocate_goal_funds(
  p_from uuid, p_to uuid, p_amount numeric, p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_from_new numeric;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;
  IF p_amount <= 0 THEN RAISE EXCEPTION 'Reallocation amount must be positive.'; END IF;
  IF p_from = p_to THEN RAISE EXCEPTION 'Source and target must differ.'; END IF;

  -- Lock both goals deterministically.
  PERFORM 1 FROM goals WHERE id = LEAST(p_from, p_to) AND user_id = v_owner FOR UPDATE;
  PERFORM 1 FROM goals WHERE id = GREATEST(p_from, p_to) AND user_id = v_owner FOR UPDATE;

  SELECT allocated_amount - p_amount INTO v_from_new FROM goals
  WHERE id = p_from AND user_id = v_owner AND is_deleted = false;
  IF v_from_new IS NULL THEN RAISE EXCEPTION 'Source goal not found.'; END IF;
  IF v_from_new < 0 THEN RAISE EXCEPTION 'Source goal has insufficient earmarked funds.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM goals WHERE id = p_to AND user_id = v_owner AND is_deleted = false) THEN
    RAISE EXCEPTION 'Target goal not found.';
  END IF;

  INSERT INTO goal_contributions (goal_id, user_id, amount, note)
  VALUES (p_from, v_owner, -p_amount, COALESCE(p_note, 'reallocation out')),
         (p_to,   v_owner,  p_amount, COALESCE(p_note, 'reallocation in'));
  UPDATE goals SET allocated_amount = allocated_amount - p_amount WHERE id = p_from;
  UPDATE goals SET allocated_amount = allocated_amount + p_amount WHERE id = p_to;
END;
$$;
REVOKE ALL ON FUNCTION reallocate_goal_funds(uuid, uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reallocate_goal_funds(uuid, uuid, numeric, text) TO authenticated;

-- 7. Drift assertion helper: stored total must equal sum of contributions -----
-- Run in CI/staging: SELECT * FROM assert_goal_allocation_drift(); (empty = ok)
CREATE OR REPLACE FUNCTION assert_goal_allocation_drift()
RETURNS TABLE (goal_id uuid, stored numeric, derived numeric)
LANGUAGE sql
STABLE
AS $$
  SELECT g.id, g.allocated_amount,
         COALESCE((SELECT sum(amount) FROM goal_contributions c WHERE c.goal_id = g.id), 0)
  FROM goals g
  WHERE g.is_deleted = false
    AND g.allocated_amount <>
        COALESCE((SELECT sum(amount) FROM goal_contributions c WHERE c.goal_id = g.id), 0);
$$;
