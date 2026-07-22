-- ============================================================================
-- Goal allocation, editing, and lifecycle verification (Phase 6.5)
--
-- Run against a staging project after applying 00014–00015. Everything happens
-- inside one transaction that is ROLLED BACK, so no test data survives.
-- Every RAISE EXCEPTION marks a failed control.
--
-- Usage:  psql "$STAGING_DB_URL" -f supabase/tests/goal_allocation.sql
-- Set :owner to the real owner UUID (app_owner.user_id).
-- ============================================================================

\set owner '00000000-0000-0000-0000-000000000000'

BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}';

  DO $$
  DECLARE
    v_owner   uuid := auth.uid();
    v_a       uuid;
    v_b       uuid;
    v_total   numeric;
    v_derived numeric;
    v_status  text;
    v_worth   numeric;
    v_worth2  numeric;
    n         int;
  BEGIN
    IF NOT app_is_owner() THEN
      RAISE EXCEPTION 'FAIL: test must run as the owner';
    END IF;

    v_worth := fn_net_worth();

    INSERT INTO goals (name, target_amount, allocated_amount, user_id)
    VALUES ('T-A', 10000, 0, v_owner) RETURNING id INTO v_a;
    INSERT INTO goals (name, target_amount, allocated_amount, user_id)
    VALUES ('T-B', 10000, 0, v_owner) RETURNING id INTO v_b;

    -- ---- contribute writes history and total in one step --------------------
    PERFORM contribute_to_goal(v_a, 4000, 'test deposit');
    SELECT allocated_amount INTO v_total FROM goals WHERE id = v_a;
    SELECT sum(amount) INTO v_derived FROM goal_contributions WHERE goal_id = v_a;
    IF v_total <> 4000 OR v_derived <> 4000 THEN
      RAISE EXCEPTION 'FAIL: contribute total %/derived % <> 4000', v_total, v_derived;
    END IF;
    RAISE NOTICE 'PASS: contribution recorded and reconciles';

    -- ---- a negative row cannot drive the total below zero --------------------
    BEGIN
      PERFORM contribute_to_goal(v_a, -5000, 'too much');
      RAISE EXCEPTION 'FAIL: allocation was allowed to go negative';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: negative total rejected (%)', SQLERRM;
    END;

    -- ---- corrections are new rows, never edits -------------------------------
    PERFORM contribute_to_goal(v_a, -1500, 'correction');
    SELECT count(*) INTO n FROM goal_contributions WHERE goal_id = v_a;
    SELECT allocated_amount INTO v_total FROM goals WHERE id = v_a;
    IF n <> 2 OR v_total <> 2500 THEN
      RAISE EXCEPTION 'FAIL: correction produced % rows, total %', n, v_total;
    END IF;
    RAISE NOTICE 'PASS: correction appended a negative row';

    -- ---- overfunding needs explicit confirmation -----------------------------
    BEGIN
      PERFORM contribute_to_goal(v_a, 20000, 'overfund');
      RAISE EXCEPTION 'FAIL: silent overfunding allowed';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: unconfirmed overfunding rejected (%)', SQLERRM;
    END;
    PERFORM contribute_to_goal(v_a, 20000, 'overfund', true);
    SELECT status INTO v_status FROM goals WHERE id = v_a;
    IF v_status <> 'completed' THEN
      RAISE EXCEPTION 'FAIL: funded goal has status %', v_status;
    END IF;
    RAISE NOTICE 'PASS: confirmed overfunding allowed and auto-completed';

    -- ---- auto-complete reverses when funding drops back below target ---------
    PERFORM contribute_to_goal(v_a, -20000, 'undo overfund');
    SELECT status, allocated_amount INTO v_status, v_total FROM goals WHERE id = v_a;
    IF v_status <> 'active' THEN
      RAISE EXCEPTION 'FAIL: corrected goal stayed % at %', v_status, v_total;
    END IF;
    RAISE NOTICE 'PASS: completion reverts after a correction';

    -- ---- reallocation conserves the combined earmarked total -----------------
    SELECT sum(allocated_amount) INTO v_total FROM goals WHERE id IN (v_a, v_b);
    PERFORM reallocate_goal_funds(v_a, v_b, 1000, 'test move');
    SELECT sum(allocated_amount) INTO v_derived FROM goals WHERE id IN (v_a, v_b);
    IF v_total <> v_derived THEN
      RAISE EXCEPTION 'FAIL: reallocation changed the total % -> %', v_total, v_derived;
    END IF;
    SELECT count(*) INTO n FROM goal_contributions
    WHERE note = 'test move' AND goal_id IN (v_a, v_b);
    IF n <> 2 THEN
      RAISE EXCEPTION 'FAIL: reallocation wrote % audit rows, expected 2', n;
    END IF;
    RAISE NOTICE 'PASS: reallocation is conserving and doubly audited';

    BEGIN
      PERFORM reallocate_goal_funds(v_a, v_b, 999999, 'too much');
      RAISE EXCEPTION 'FAIL: reallocated more than the source holds';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: over-drawing the source rejected (%)', SQLERRM;
    END;

    -- ---- no drift between stored totals and history --------------------------
    SELECT count(*) INTO n FROM assert_goal_allocation_drift();
    IF n <> 0 THEN
      RAISE EXCEPTION 'FAIL: % goals drifted from their contribution history', n;
    END IF;
    RAISE NOTICE 'PASS: no allocation drift';

    -- ---- earmarking never moves money ---------------------------------------
    v_worth2 := fn_net_worth();
    IF v_worth2 <> v_worth THEN
      RAISE EXCEPTION 'FAIL: allocation changed net worth % -> %', v_worth, v_worth2;
    END IF;
    RAISE NOTICE 'PASS: net worth unchanged by allocation';

    -- ---- editing guards ------------------------------------------------------
    BEGIN
      PERFORM update_goal(v_a, 'T-A', 10, NULL, NULL);
      RAISE EXCEPTION 'FAIL: target silently dropped below the earmarked amount';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: target-below-allocated rejected (%)', SQLERRM;
    END;
    PERFORM update_goal(v_a, 'T-A renamed', 12000, DATE '2027-01-01', 'custom');
    RAISE NOTICE 'PASS: audited edit applied';

    -- ---- status transitions --------------------------------------------------
    BEGIN
      PERFORM set_goal_status(v_a, 'completed');
      RAISE EXCEPTION 'FAIL: completed was set by hand';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: manual completion rejected (%)', SQLERRM;
    END;
    PERFORM set_goal_status(v_a, 'paused');
    PERFORM set_goal_status(v_a, 'archived');
    PERFORM set_goal_status(v_a, 'active');
    SELECT status INTO v_status FROM goals WHERE id = v_a;
    IF v_status <> 'active' THEN
      RAISE EXCEPTION 'FAIL: restore left status %', v_status;
    END IF;
    RAISE NOTICE 'PASS: pause / archive / restore behave';

    -- ---- delete only without history ----------------------------------------
    BEGIN
      PERFORM delete_goal(v_a);
      RAISE EXCEPTION 'FAIL: deleted a goal that has history';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: delete refused, archive offered (%)', SQLERRM;
    END;

    INSERT INTO goals (name, target_amount, allocated_amount, user_id)
    VALUES ('T-C', 500, 0, v_owner) RETURNING id INTO v_b;
    PERFORM delete_goal(v_b);
    SELECT count(*) INTO n FROM goals WHERE id = v_b AND is_deleted = true;
    IF n <> 1 THEN
      RAISE EXCEPTION 'FAIL: history-free goal was not soft-deleted';
    END IF;
    RAISE NOTICE 'PASS: history-free goal soft-deleted';

    RAISE NOTICE 'ALL GOAL ALLOCATION CONTROLS PASSED';
  END $$;
ROLLBACK;
