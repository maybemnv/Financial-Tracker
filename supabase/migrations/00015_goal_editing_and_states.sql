-- ============================================================================
-- 00015: Goal editing, lifecycle states, and safe delete (Phase 6.2).
--        Every guard the UI offers is also enforced here, so a guard cannot be
--        bypassed by calling the API directly. Additive/forward-only.
-- ============================================================================

-- 1. Auto-complete in BOTH directions, on target or allocation change ---------
-- 00014 only promoted active -> completed. A negative correction (or a raised
-- target) must be able to demote completed -> active again, otherwise a
-- corrected goal stays falsely "completed" forever. Manual pause/archive is
-- never overridden.
CREATE OR REPLACE FUNCTION goals_autocomplete()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('active', 'completed') THEN
    IF NEW.allocated_amount >= NEW.target_amount THEN
      NEW.status := 'completed';
    ELSE
      NEW.status := 'active';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_goals_autocomplete ON goals;
CREATE TRIGGER trg_goals_autocomplete
  BEFORE UPDATE OF allocated_amount, target_amount ON goals
  FOR EACH ROW EXECUTE FUNCTION goals_autocomplete();

-- 2. Overfunding requires explicit confirmation -------------------------------
-- Replaces the 00014 signature (3 args) with a 4-arg form. Only a POSITIVE
-- contribution that pushes the total past the target needs confirmation; a
-- negative correction on an already-overfunded goal must never be blocked.
DROP FUNCTION IF EXISTS contribute_to_goal(uuid, numeric, text);

CREATE OR REPLACE FUNCTION contribute_to_goal(
  p_goal_id uuid,
  p_amount numeric,
  p_note text DEFAULT NULL,
  p_allow_overfunding boolean DEFAULT false
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_new numeric; v_target numeric;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;
  IF p_amount = 0 THEN RAISE EXCEPTION 'Contribution cannot be zero.'; END IF;

  SELECT allocated_amount + p_amount, target_amount INTO v_new, v_target FROM goals
  WHERE id = p_goal_id AND user_id = v_owner AND is_deleted = false FOR UPDATE;
  IF v_new IS NULL THEN RAISE EXCEPTION 'Goal not found.'; END IF;
  IF v_new < 0 THEN RAISE EXCEPTION 'Allocation cannot go negative.'; END IF;
  IF p_amount > 0 AND v_new > v_target AND NOT p_allow_overfunding THEN
    RAISE EXCEPTION 'Contribution would overfund this goal. Confirm to proceed.';
  END IF;

  INSERT INTO goal_contributions (goal_id, user_id, amount, note)
  VALUES (p_goal_id, v_owner, p_amount, p_note);
  UPDATE goals SET allocated_amount = v_new WHERE id = p_goal_id;
  RETURN v_new;
END;
$$;
REVOKE ALL ON FUNCTION contribute_to_goal(uuid, numeric, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION contribute_to_goal(uuid, numeric, text, boolean) TO authenticated;

-- Same confirmation rule on the receiving side of a reallocation.
DROP FUNCTION IF EXISTS reallocate_goal_funds(uuid, uuid, numeric, text);

CREATE OR REPLACE FUNCTION reallocate_goal_funds(
  p_from uuid,
  p_to uuid,
  p_amount numeric,
  p_note text DEFAULT NULL,
  p_allow_overfunding boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_from_new numeric; v_to_new numeric; v_to_target numeric;
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

  SELECT allocated_amount + p_amount, target_amount INTO v_to_new, v_to_target FROM goals
  WHERE id = p_to AND user_id = v_owner AND is_deleted = false;
  IF v_to_new IS NULL THEN RAISE EXCEPTION 'Target goal not found.'; END IF;
  IF v_to_new > v_to_target AND NOT p_allow_overfunding THEN
    RAISE EXCEPTION 'Reallocation would overfund the target goal. Confirm to proceed.';
  END IF;

  INSERT INTO goal_contributions (goal_id, user_id, amount, note)
  VALUES (p_from, v_owner, -p_amount, COALESCE(p_note, 'reallocation out')),
         (p_to,   v_owner,  p_amount, COALESCE(p_note, 'reallocation in'));
  UPDATE goals SET allocated_amount = allocated_amount - p_amount WHERE id = p_from;
  UPDATE goals SET allocated_amount = allocated_amount + p_amount WHERE id = p_to;
END;
$$;
REVOKE ALL ON FUNCTION reallocate_goal_funds(uuid, uuid, numeric, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reallocate_goal_funds(uuid, uuid, numeric, text, boolean) TO authenticated;

-- 3. update_goal: audited edit of name / target / date / type -----------------
-- Reducing the target below the amount already earmarked needs confirmation:
-- it is legal (the goal simply becomes overfunded) but never silent.
CREATE OR REPLACE FUNCTION update_goal(
  p_goal_id uuid,
  p_name text,
  p_target_amount numeric,
  p_target_date date DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_allow_target_below_allocated boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_allocated numeric; v_type text;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;
  IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'Goal name is required.'; END IF;
  IF p_target_amount IS NULL OR p_target_amount <= 0 THEN
    RAISE EXCEPTION 'Target amount must be positive.';
  END IF;

  SELECT allocated_amount, type INTO v_allocated, v_type FROM goals
  WHERE id = p_goal_id AND user_id = v_owner AND is_deleted = false FOR UPDATE;
  IF v_allocated IS NULL THEN RAISE EXCEPTION 'Goal not found.'; END IF;

  IF p_target_amount < v_allocated AND NOT p_allow_target_below_allocated THEN
    RAISE EXCEPTION 'Target is below the amount already earmarked. Confirm to proceed.';
  END IF;

  v_type := COALESCE(p_type, v_type);
  IF v_type NOT IN ('custom', 'emergency_fund') THEN
    RAISE EXCEPTION 'Unknown goal type: %', v_type;
  END IF;

  UPDATE goals
  SET name = btrim(p_name),
      target_amount = p_target_amount,
      target_date = p_target_date,
      type = v_type
  WHERE id = p_goal_id;
END;
$$;
REVOKE ALL ON FUNCTION update_goal(uuid, text, numeric, date, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_goal(uuid, text, numeric, date, text, boolean) TO authenticated;

-- 4. set_goal_status: manual pause / archive / restore ------------------------
-- 'completed' is owned by the trigger above and is never set by hand, so a
-- goal can never claim to be complete while underfunded.
CREATE OR REPLACE FUNCTION set_goal_status(p_goal_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_current text;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;
  IF p_status NOT IN ('active', 'paused', 'archived') THEN
    RAISE EXCEPTION 'Status % cannot be set manually.', p_status;
  END IF;

  SELECT status INTO v_current FROM goals
  WHERE id = p_goal_id AND user_id = v_owner AND is_deleted = false FOR UPDATE;
  IF v_current IS NULL THEN RAISE EXCEPTION 'Goal not found.'; END IF;
  IF v_current = p_status THEN RETURN; END IF;

  -- Naming allocated_amount in SET re-fires the autocomplete trigger, so
  -- restoring to active re-derives completion from the current funding level.
  UPDATE goals SET status = p_status, allocated_amount = allocated_amount
  WHERE id = p_goal_id;
END;
$$;
REVOKE ALL ON FUNCTION set_goal_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_goal_status(uuid, text) TO authenticated;

-- 5. delete_goal: soft delete only when there is no history -------------------
-- A goal with contributions carries an audit trail that must survive; the UI
-- offers Archive instead. Never a physical DELETE.
CREATE OR REPLACE FUNCTION delete_goal(p_goal_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_exists boolean;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;

  SELECT true INTO v_exists FROM goals
  WHERE id = p_goal_id AND user_id = v_owner AND is_deleted = false FOR UPDATE;
  IF v_exists IS NULL THEN RAISE EXCEPTION 'Goal not found.'; END IF;

  IF EXISTS (SELECT 1 FROM goal_contributions WHERE goal_id = p_goal_id) THEN
    RAISE EXCEPTION 'This goal has allocation history. Archive it instead.';
  END IF;

  UPDATE goals SET is_deleted = true, deleted_at = now() WHERE id = p_goal_id;
END;
$$;
REVOKE ALL ON FUNCTION delete_goal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_goal(uuid) TO authenticated;
