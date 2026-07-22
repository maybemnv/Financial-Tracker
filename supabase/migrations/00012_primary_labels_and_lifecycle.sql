-- ============================================================================
-- 00012: Primary-label schema, label lifecycle columns, legacy backfill
--        (Phase 5.1, 5.2, 5.7). Additive/forward-only.
-- ============================================================================

-- 1. Primary label on transactions ------------------------------------------
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS primary_label_id UUID REFERENCES labels(id);

-- Index the unresolved-review + analytics query paths (owner-first).
CREATE INDEX IF NOT EXISTS idx_transactions_owner_primary_label
  ON transactions (user_id, primary_label_id) WHERE is_deleted = false;

-- 2. Label lifecycle columns -------------------------------------------------
ALTER TABLE labels
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'archived', 'merged', 'deleted')),
  ADD COLUMN IF NOT EXISTS merged_into_id UUID REFERENCES labels(id),
  ADD COLUMN IF NOT EXISTS updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS merged_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_at  TIMESTAMPTZ;

-- Case-insensitive uniqueness only among *assignable* (active) labels, so a
-- rename can reuse a freed name after archive/merge.
DROP INDEX IF EXISTS uq_labels_owner_name_lower;
CREATE UNIQUE INDEX IF NOT EXISTS uq_labels_owner_active_name_lower
  ON labels (user_id, lower(name)) WHERE status = 'active';

DROP TRIGGER IF EXISTS set_labels_updated_at ON labels;
CREATE TRIGGER set_labels_updated_at
  BEFORE UPDATE ON labels
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 3. Label audit log ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS label_audit (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id),
  label_id   UUID NOT NULL REFERENCES labels(id),
  action     TEXT NOT NULL CHECK (action IN
               ('create','rename','archive','restore','merge','delete','exclude_flag')),
  old_value  JSONB,
  new_value  JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_label_audit_owner_label
  ON label_audit (user_id, label_id, created_at DESC);

ALTER TABLE label_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS owner_select ON label_audit;
CREATE POLICY owner_select ON label_audit FOR SELECT TO authenticated
  USING (user_id = auth.uid() AND app_is_owner());
-- No client INSERT/UPDATE/DELETE: audit rows are written only by SECURITY
-- DEFINER RPCs. Ownership stamped by enforce_row_owner.
REVOKE ALL ON label_audit FROM anon, authenticated;
GRANT SELECT ON label_audit TO authenticated;

DROP TRIGGER IF EXISTS trg_enforce_owner ON label_audit;
CREATE TRIGGER trg_enforce_owner BEFORE INSERT OR UPDATE ON label_audit
  FOR EACH ROW EXECUTE FUNCTION enforce_row_owner();

-- 4. Backfill legacy primary labels + active status --------------------------
-- Single-label non-deleted expenses get that label as primary. Zero-label and
-- multi-label expenses are intentionally left NULL (Unlabeled / Needs primary).
DO $$
DECLARE resolved int; ambiguous int; unlabeled int;
BEGIN
  UPDATE transactions t
  SET primary_label_id = tl.label_id
  FROM (
    SELECT transaction_id, MIN(label_id) AS label_id, COUNT(*) AS n
    FROM transaction_labels
    GROUP BY transaction_id
    HAVING COUNT(*) = 1
  ) tl
  WHERE t.id = tl.transaction_id
    AND t.is_deleted = false
    AND t.type = 'debit'
    AND t.primary_label_id IS NULL;

  GET DIAGNOSTICS resolved = ROW_COUNT;

  SELECT count(*) INTO ambiguous FROM transactions t
  WHERE t.is_deleted = false AND t.type = 'debit' AND t.primary_label_id IS NULL
    AND (SELECT count(*) FROM transaction_labels x WHERE x.transaction_id = t.id) > 1;

  SELECT count(*) INTO unlabeled FROM transactions t
  WHERE t.is_deleted = false AND t.type = 'debit' AND t.primary_label_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM transaction_labels x WHERE x.transaction_id = t.id);

  RAISE NOTICE 'primary backfill: resolved=% ambiguous(needs primary)=% unlabeled=%',
    resolved, ambiguous, unlabeled;
END $$;

-- All existing labels are already active (column default); seed one audit row.
INSERT INTO label_audit (user_id, label_id, action, new_value)
SELECT user_id, id, 'create', jsonb_build_object('name', name, 'color', color)
FROM labels
WHERE NOT EXISTS (
  SELECT 1 FROM label_audit a WHERE a.label_id = labels.id AND a.action = 'create'
);
