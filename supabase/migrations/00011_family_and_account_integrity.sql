-- ============================================================================
-- 00011: Account integrity + Family-support semantics (Phase 4, fixes D1/D2)
--
-- Additive/forward-only. Enforces an explicit account at the schema boundary,
-- renames the misleading TRANSFER TO OTHER label to FAMILY without losing its
-- identity, and adds the single reporting flag that separates Family Support
-- from Personal Spend.
-- ============================================================================

-- 1. D1 — every transaction must sit on an explicitly chosen account ----------
-- Audit first: any null-account rows must be reassigned via the normal edit
-- flow before this runs (see RUNBOOK / review query below). The DO block fails
-- loudly rather than guessing an account.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM transactions WHERE account_id IS NULL;
  IF n > 0 THEN
    RAISE EXCEPTION
      '% transactions have a null account_id. Reassign them (audited edit) before enforcing NOT NULL.', n;
  END IF;
END $$;

ALTER TABLE transactions ALTER COLUMN account_id SET NOT NULL;

-- 2. D2 — identity-preserving rename TRANSFER TO OTHER -> FAMILY --------------
-- Same row, same id; all transaction_labels joins untouched. Never
-- delete-and-recreate. Idempotent: only renames if the old name still exists.
UPDATE labels
SET name = 'FAMILY'
WHERE lower(name) = lower('TRANSFER TO OTHER');

-- 3. Reporting exclusion flag (the smallest possible mechanism) --------------
ALTER TABLE labels
  ADD COLUMN IF NOT EXISTS exclude_from_personal_spend BOOLEAN NOT NULL DEFAULT false;

UPDATE labels
SET exclude_from_personal_spend = true
WHERE lower(name) = lower('FAMILY');

-- Guard: keep the invariant Total Outflow = Personal Spend + Family Support by
-- restricting the exclusion flag to a single label (FAMILY today). A second
-- excluded label would silently break reconciliation. If a future need arises,
-- redefine Family Support to include every excluded label instead of lifting
-- this guard blindly.
CREATE OR REPLACE FUNCTION labels_single_exclusion_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.exclude_from_personal_spend AND EXISTS (
    SELECT 1 FROM labels
    WHERE exclude_from_personal_spend
      AND user_id = NEW.user_id
      AND id <> NEW.id
  ) THEN
    RAISE EXCEPTION
      'Only one label may be excluded from Personal Spend (Family Support). '
      'Excluding another would break Total Outflow = Personal Spend + Family Support.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_labels_single_exclusion ON labels;
CREATE TRIGGER trg_labels_single_exclusion
  BEFORE INSERT OR UPDATE OF exclude_from_personal_spend ON labels
  FOR EACH ROW EXECUTE FUNCTION labels_single_exclusion_guard();
