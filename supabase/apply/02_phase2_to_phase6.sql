-- ============================================================================
-- PART 2 of 2 — Phases 2-6.  Paste into the Supabase SQL Editor and Run.
--
-- Contains migrations 00007 - 00015 in order:
--   00007 row ownership (adds + backfills user_id)
--   00008 owner constraints (NOT NULL, owner-scoped keys, ownership triggers)
--   00009 owner-only RLS  <-- the anon client STOPS WORKING after this
--   00010 owner-scoped balance / net-worth functions
--   00011 account_id NOT NULL, TRANSFER TO OTHER -> FAMILY, exclusion flag
--   00012 primary labels + label lifecycle + label_audit
--   00013 transaction/label RPCs
--   00014 goal contribution history + atomic allocation
--   00015 goal editing, lifecycle states, safe delete
--   00016 save_transaction_with_labels corrections (unlabeled expenses, SMS)
--
-- READ BEFORE RUNNING:
--
-- * BACK UP FIRST (docs/RUNBOOK.md §1). These migrations are forward-only;
--   there is no scripted rollback.
--
-- * 00009 replaces the permissive anon policies with owner-only RLS. The
--   currently deployed anon Flutter client will stop reading data the moment
--   this commits. Deploy the auth-capable client from this branch in the SAME
--   maintenance window.
--
-- * Run part 1 and the INSERT INTO app_owner first. This script refuses to
--   start without an active owner row.
--
-- * The Supabase SQL Editor runs this as one transaction, so a failure rolls
--   the whole thing back and leaves your database untouched. Two checks can
--   stop it deliberately: a missing owner row, and transactions with a null
--   account_id (00011 will not guess an account). Run 00_preflight.sql first
--   to see the second one coming.
--
-- * Safe to re-run: every statement is guarded, so re-running is a no-op on
--   parts already applied.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.app_owner') IS NULL THEN
    RAISE EXCEPTION 'app_owner does not exist. Run 01_owner_registry.sql first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app_owner WHERE is_active) THEN
    RAISE EXCEPTION
      'No active owner row. Run the INSERT INTO app_owner from part 1 first.';
  END IF;
END $$;


-- ####################################################################
-- BEGIN 00007_row_ownership.sql
-- ####################################################################

-- ============================================================================
-- 00007: Add nullable user_id to every protected table and backfill (Phase 2.3)
--
-- Additive and forward-only. Columns start NULLABLE so existing rows are not
-- rejected; the backfill assigns them all to the registered owner; NOT NULL and
-- owner-aware keys land in 00008 only after zero-null verification.
--
-- PREREQUISITE: 00006 applied AND an active row exists in app_owner. The
-- backfill DO block raises if not.
-- ============================================================================

-- 1. Add nullable ownership columns -----------------------------------------
ALTER TABLE accounts            ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE transactions        ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE transaction_labels  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE labels              ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE invoices            ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE goals               ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE recurring_expenses  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE recurring_income    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE category_rules      ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE monthly_snapshots   ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE chat_sessions       ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

-- 2. Backfill all existing rows to the single registered owner --------------
DO $$
DECLARE
  owner uuid;
BEGIN
  SELECT user_id INTO owner FROM app_owner WHERE is_active LIMIT 1;
  IF owner IS NULL THEN
    RAISE EXCEPTION
      'No active owner in app_owner. Insert the owner UUID (00006) before backfilling ownership.';
  END IF;

  UPDATE accounts           SET user_id = owner WHERE user_id IS NULL;
  UPDATE transactions       SET user_id = owner WHERE user_id IS NULL;
  UPDATE transaction_labels SET user_id = owner WHERE user_id IS NULL;
  UPDATE labels             SET user_id = owner WHERE user_id IS NULL;
  UPDATE invoices           SET user_id = owner WHERE user_id IS NULL;
  UPDATE goals              SET user_id = owner WHERE user_id IS NULL;
  UPDATE recurring_expenses SET user_id = owner WHERE user_id IS NULL;
  UPDATE recurring_income   SET user_id = owner WHERE user_id IS NULL;
  UPDATE category_rules     SET user_id = owner WHERE user_id IS NULL;
  UPDATE monthly_snapshots  SET user_id = owner WHERE user_id IS NULL;
  UPDATE chat_sessions      SET user_id = owner WHERE user_id IS NULL;
END $$;

-- 3. Owner-first indexes for the hot owner-scoped query paths ----------------
CREATE INDEX IF NOT EXISTS idx_transactions_user_txn_at
  ON transactions (user_id, COALESCE(transacted_at, created_at) DESC, id DESC)
  WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_transactions_user_account
  ON transactions (user_id, account_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_accounts_user           ON accounts (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_labels_user             ON labels (user_id);
CREATE INDEX IF NOT EXISTS idx_transaction_labels_user ON transaction_labels (user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_user           ON invoices (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_goals_user              ON goals (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_recurring_expenses_user ON recurring_expenses (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_recurring_income_user   ON recurring_income (user_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_monthly_snapshots_user  ON monthly_snapshots (user_id);
CREATE INDEX IF NOT EXISTS idx_chat_sessions_user      ON chat_sessions (user_id);

-- Verification (run manually; every count must be 0):
--   SELECT 'transactions' t, count(*) FROM transactions WHERE user_id IS NULL
--   UNION ALL SELECT 'accounts', count(*) FROM accounts WHERE user_id IS NULL
--   -- ... repeat per table ...


-- ####################################################################
-- BEGIN 00008_owner_constraints.sql
-- ####################################################################

-- ============================================================================
-- 00008: Enforce ownership integrity (Phase 2.3 continued)
--
-- Runs only after 00007's backfill leaves zero null user_id rows. Adds NOT
-- NULL, owner-scoped uniqueness, and triggers that stamp/validate ownership so
-- a client can never write a row owned by someone else.
-- ============================================================================

-- 1. NOT NULL now that every row is owned -----------------------------------
ALTER TABLE accounts           ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE transactions       ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE transaction_labels ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE labels             ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE invoices           ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE goals              ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE recurring_expenses ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE recurring_income   ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE category_rules     ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE monthly_snapshots  ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE chat_sessions      ALTER COLUMN user_id SET NOT NULL;

-- 2. Owner-scope the natural keys that were global ---------------------------
-- Snapshots: one per (owner, year, month), not globally one per (year, month).
ALTER TABLE monthly_snapshots DROP CONSTRAINT IF EXISTS monthly_snapshots_month_year_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_monthly_snapshots_owner_period
  ON monthly_snapshots (user_id, year, month);

-- Labels: case-insensitive unique per owner, not globally.
DROP INDEX IF EXISTS idx_labels_name_lower;
CREATE UNIQUE INDEX IF NOT EXISTS uq_labels_owner_name_lower
  ON labels (user_id, lower(name));

-- SMS dedupe hash: owner-scoped lookup (kept non-unique — legacy rows may
-- share a hash; hard uniqueness needs a separate dedup pass first).
DROP INDEX IF EXISTS idx_transactions_sms_hash;
CREATE INDEX IF NOT EXISTS idx_transactions_owner_sms_hash
  ON transactions (user_id, raw_sms_hash) WHERE raw_sms_hash IS NOT NULL;

-- 3. Stamp/validate ownership from the JWT, never trust client user_id -------
CREATE OR REPLACE FUNCTION enforce_row_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Stamp the caller if the client omitted it; reject a foreign owner.
    IF NEW.user_id IS NULL THEN
      NEW.user_id := auth.uid();
    ELSIF NEW.user_id <> auth.uid() THEN
      RAISE EXCEPTION 'Cannot create a row owned by another user.';
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Ownership is immutable via normal writes.
    IF NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'Cannot change row ownership.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'accounts','transactions','transaction_labels','labels','invoices','goals',
    'recurring_expenses','recurring_income','category_rules','monthly_snapshots',
    'chat_sessions'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_enforce_owner ON %I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_enforce_owner BEFORE INSERT OR UPDATE ON %I
         FOR EACH ROW EXECUTE FUNCTION enforce_row_owner()', t);
  END LOOP;
END $$;


-- ####################################################################
-- BEGIN 00009_owner_policies.sql
-- ####################################################################

-- ============================================================================
-- 00009: Replace every open anon_all policy with owner-only RLS (Phase 2.4)
--
-- Removes the D5 hole. After this migration, only the authenticated owner can
-- read or write finance rows, and only their own. Physical DELETE stays revoked
-- (no DELETE policy is created, so RLS denies it) — deletion is soft-delete via
-- UPDATE only. Deploy the auth-capable client in the SAME window (never leave an
-- anon client pointed at owner-only RLS).
-- ============================================================================

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'accounts','transactions','transaction_labels','labels','invoices','goals',
    'recurring_expenses','recurring_income','category_rules','monthly_snapshots',
    'chat_sessions'
  ] LOOP
    -- Drop the permissive policy.
    EXECUTE format('DROP POLICY IF EXISTS "anon_all" ON %I', t);

    -- Drop our own policies first so this migration is safely re-runnable.
    EXECUTE format('DROP POLICY IF EXISTS owner_select ON %I', t);
    EXECUTE format('DROP POLICY IF EXISTS owner_insert ON %I', t);
    EXECUTE format('DROP POLICY IF EXISTS owner_update ON %I', t);

    -- Owner-only SELECT.
    EXECUTE format($p$
      CREATE POLICY owner_select ON %I FOR SELECT TO authenticated
        USING (user_id = auth.uid() AND app_is_owner())
    $p$, t);

    -- Owner-only INSERT.
    EXECUTE format($p$
      CREATE POLICY owner_insert ON %I FOR INSERT TO authenticated
        WITH CHECK (user_id = auth.uid() AND app_is_owner())
    $p$, t);

    -- Owner-only UPDATE; USING + WITH CHECK both scoped so an update can never
    -- transfer ownership or escape the owner's rows.
    EXECUTE format($p$
      CREATE POLICY owner_update ON %I FOR UPDATE TO authenticated
        USING (user_id = auth.uid() AND app_is_owner())
        WITH CHECK (user_id = auth.uid() AND app_is_owner())
    $p$, t);

    -- No DELETE policy: physical delete stays denied for client roles.
  END LOOP;
END $$;

-- Least privilege at the grant layer too (RLS is the primary control).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'accounts','transactions','transaction_labels','labels','invoices','goals',
    'recurring_expenses','recurring_income','category_rules','monthly_snapshots',
    'chat_sessions'
  ] LOOP
    EXECUTE format('REVOKE ALL ON %I FROM anon', t);
    EXECUTE format('REVOKE DELETE ON %I FROM authenticated', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON %I TO authenticated', t);
  END LOOP;
END $$;


-- ####################################################################
-- BEGIN 00010_scope_functions.sql
-- ####################################################################

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


-- ####################################################################
-- BEGIN 00011_family_and_account_integrity.sql
-- ####################################################################

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


-- ####################################################################
-- BEGIN 00012_primary_labels_and_lifecycle.sql
-- ####################################################################

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


-- ####################################################################
-- BEGIN 00013_label_and_transaction_rpcs.sql
-- ####################################################################

-- ============================================================================
-- 00013: Owner-scoped transactional RPCs (Phase 5.4, 5.8, 5.9, 5.10)
--
-- One audited write path per logical change. All SECURITY DEFINER with a fixed
-- search_path, owner-guarded via app_is_owner(), granted to authenticated only.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- save_transaction_with_labels: create/edit a transaction, replace its label
-- set, set its primary label, and append exactly one edit_history audit entry —
-- all in one transaction. Requires exactly one primary label for expenses.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION save_transaction_with_labels(
  p_id             uuid,        -- null to create
  p_fields         jsonb,       -- account_id, amount, type, direction, merchant, vpa, bank, note, transacted_at, ...
  p_label_ids      uuid[],      -- contextual labels to attach (may be empty)
  p_primary_label  uuid         -- required for expenses; must be in p_label_ids
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner   uuid := auth.uid();
  v_id      uuid := p_id;
  v_type    text := p_fields->>'type';
  v_is_expense boolean;
  v_old     jsonb;
  v_bad     int;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  v_is_expense := (v_type = 'debit');

  -- Every attached label must be owner-owned and assignable (active).
  SELECT count(*) INTO v_bad
  FROM unnest(p_label_ids) AS lid
  WHERE NOT EXISTS (
    SELECT 1 FROM labels l
    WHERE l.id = lid AND l.user_id = v_owner AND l.status = 'active'
  );
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'One or more labels are invalid, archived, or not yours.';
  END IF;

  -- Expenses require exactly one primary, and it must be attached.
  IF v_is_expense THEN
    IF p_primary_label IS NULL THEN
      RAISE EXCEPTION 'An expense requires exactly one primary label.';
    END IF;
    IF NOT (p_primary_label = ANY (p_label_ids)) THEN
      RAISE EXCEPTION 'The primary label must also be attached to the transaction.';
    END IF;
  ELSIF p_primary_label IS NOT NULL AND NOT (p_primary_label = ANY (p_label_ids)) THEN
    RAISE EXCEPTION 'The primary label must also be attached to the transaction.';
  END IF;

  IF v_id IS NULL THEN
    ----------------------------------------------------------------- create
    INSERT INTO transactions (
      user_id, account_id, amount, type, direction, vpa, merchant, bank,
      note, usd_amount, linked_invoice_id, transfer_group_id, source,
      transacted_at, primary_label_id
    )
    VALUES (
      v_owner,
      (p_fields->>'account_id')::uuid,
      (p_fields->>'amount')::numeric,
      v_type,
      p_fields->>'direction',
      p_fields->>'vpa',
      p_fields->>'merchant',
      p_fields->>'bank',
      p_fields->>'note',
      (p_fields->>'usd_amount')::numeric,
      (p_fields->>'linked_invoice_id')::uuid,
      (p_fields->>'transfer_group_id')::uuid,
      COALESCE(p_fields->>'source', 'manual'),
      (p_fields->>'transacted_at')::timestamptz,
      p_primary_label
    )
    RETURNING id INTO v_id;
  ELSE
    ------------------------------------------------------------------- edit
    -- Lock the row and capture the old state for the audit.
    SELECT to_jsonb(t) INTO v_old
    FROM transactions t
    WHERE t.id = v_id AND t.user_id = v_owner AND t.is_deleted = false
    FOR UPDATE;
    IF v_old IS NULL THEN
      RAISE EXCEPTION 'Transaction not found or not editable.';
    END IF;

    UPDATE transactions SET
      account_id       = (p_fields->>'account_id')::uuid,
      amount           = (p_fields->>'amount')::numeric,
      type             = v_type,
      direction        = p_fields->>'direction',
      vpa              = p_fields->>'vpa',
      merchant         = p_fields->>'merchant',
      bank             = p_fields->>'bank',
      note             = p_fields->>'note',
      transacted_at    = (p_fields->>'transacted_at')::timestamptz,
      primary_label_id = p_primary_label,
      edit_history     = edit_history || jsonb_build_array(jsonb_build_object(
                           'old', v_old,
                           'edited_at', now()
                         ))
    WHERE id = v_id AND user_id = v_owner;
  END IF;

  -- Replace the contextual label set.
  DELETE FROM transaction_labels WHERE transaction_id = v_id;
  INSERT INTO transaction_labels (transaction_id, label_id, user_id)
  SELECT v_id, lid, v_owner FROM unnest(p_label_ids) AS lid
  ON CONFLICT DO NOTHING;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION save_transaction_with_labels(uuid, jsonb, uuid[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION save_transaction_with_labels(uuid, jsonb, uuid[], uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- rename_label: identity-preserving, case-insensitive conflict detection.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rename_label(p_id uuid, p_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_old text;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;
  p_name := btrim(p_name);
  IF p_name = '' THEN RAISE EXCEPTION 'Label name cannot be empty.'; END IF;

  SELECT name INTO v_old FROM labels
  WHERE id = p_id AND user_id = v_owner AND status = 'active' FOR UPDATE;
  IF v_old IS NULL THEN RAISE EXCEPTION 'Label not found or not editable.'; END IF;

  -- Case-only rename is allowed (same row); a different active label with the
  -- same lower(name) is a conflict.
  IF EXISTS (
    SELECT 1 FROM labels
    WHERE user_id = v_owner AND status = 'active'
      AND id <> p_id AND lower(name) = lower(p_name)
  ) THEN
    RAISE EXCEPTION 'Another label already uses that name.';
  END IF;

  UPDATE labels SET name = p_name WHERE id = p_id;
  INSERT INTO label_audit (user_id, label_id, action, old_value, new_value)
  VALUES (v_owner, p_id, 'rename',
          jsonb_build_object('name', v_old), jsonb_build_object('name', p_name));
END;
$$;
REVOKE ALL ON FUNCTION rename_label(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rename_label(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_label_status: archive / restore, with audit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_label_status(p_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_old text;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;
  IF p_status NOT IN ('active', 'archived') THEN
    RAISE EXCEPTION 'Only active/archived transitions are allowed here.';
  END IF;

  SELECT status INTO v_old FROM labels
  WHERE id = p_id AND user_id = v_owner FOR UPDATE;
  IF v_old IS NULL THEN RAISE EXCEPTION 'Label not found.'; END IF;
  IF v_old = 'merged' OR v_old = 'deleted' THEN
    RAISE EXCEPTION 'A % label cannot change status.', v_old;
  END IF;

  UPDATE labels SET
    status = p_status,
    archived_at = CASE WHEN p_status = 'archived' THEN now() ELSE NULL END
  WHERE id = p_id;

  INSERT INTO label_audit (user_id, label_id, action, old_value, new_value)
  VALUES (v_owner, p_id,
          CASE WHEN p_status = 'archived' THEN 'archive' ELSE 'restore' END,
          jsonb_build_object('status', v_old), jsonb_build_object('status', p_status));
END;
$$;
REVOKE ALL ON FUNCTION set_label_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_label_status(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- merge_labels: move all references source -> target, mark source merged.
-- Idempotent: a re-run on an already-merged source returns quietly.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION merge_labels(p_source uuid, p_target uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_src_status text; v_moved int;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;
  IF p_source = p_target THEN RAISE EXCEPTION 'Cannot merge a label into itself.'; END IF;

  -- Lock both in a deterministic order to avoid deadlocks.
  PERFORM 1 FROM labels WHERE id = LEAST(p_source, p_target) AND user_id = v_owner FOR UPDATE;
  PERFORM 1 FROM labels WHERE id = GREATEST(p_source, p_target) AND user_id = v_owner FOR UPDATE;

  SELECT status INTO v_src_status FROM labels WHERE id = p_source AND user_id = v_owner;
  IF v_src_status IS NULL THEN RAISE EXCEPTION 'Source label not found.'; END IF;
  IF v_src_status = 'merged' THEN RETURN; END IF;  -- idempotent

  IF NOT EXISTS (SELECT 1 FROM labels WHERE id = p_target AND user_id = v_owner AND status = 'active') THEN
    RAISE EXCEPTION 'Target label must be an active owned label.';
  END IF;

  -- Move contextual joins, resolving duplicates.
  UPDATE transaction_labels tl SET label_id = p_target
  WHERE tl.label_id = p_source
    AND NOT EXISTS (SELECT 1 FROM transaction_labels d
                    WHERE d.transaction_id = tl.transaction_id AND d.label_id = p_target);
  DELETE FROM transaction_labels WHERE label_id = p_source;

  -- Migrate primary references.
  UPDATE transactions SET primary_label_id = p_target
  WHERE primary_label_id = p_source AND user_id = v_owner;
  GET DIAGNOSTICS v_moved = ROW_COUNT;

  UPDATE labels SET status = 'merged', merged_into_id = p_target, merged_at = now()
  WHERE id = p_source;

  INSERT INTO label_audit (user_id, label_id, action, old_value, new_value)
  VALUES (v_owner, p_source, 'merge',
          jsonb_build_object('status', v_src_status),
          jsonb_build_object('merged_into', p_target, 'primary_moved', v_moved));
END;
$$;
REVOKE ALL ON FUNCTION merge_labels(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION merge_labels(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- delete_label: soft-delete only when unreferenced; otherwise raise so the UI
-- offers Archive/Merge instead. Never a physical DELETE.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION delete_label(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid := auth.uid(); v_refs int;
BEGIN
  IF NOT app_is_owner() THEN RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501'; END IF;

  PERFORM 1 FROM labels WHERE id = p_id AND user_id = v_owner FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Label not found.'; END IF;

  SELECT
    (SELECT count(*) FROM transaction_labels WHERE label_id = p_id)
    + (SELECT count(*) FROM transactions WHERE primary_label_id = p_id)
    + (SELECT count(*) FROM labels WHERE merged_into_id = p_id)
  INTO v_refs;

  IF v_refs > 0 THEN
    RAISE EXCEPTION 'Label is referenced by % rows; archive or merge instead.', v_refs;
  END IF;

  UPDATE labels SET status = 'deleted', deleted_at = now() WHERE id = p_id;
  INSERT INTO label_audit (user_id, label_id, action, new_value)
  VALUES (v_owner, p_id, 'delete', jsonb_build_object('status', 'deleted'));
END;
$$;
REVOKE ALL ON FUNCTION delete_label(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_label(uuid) TO authenticated;


-- ####################################################################
-- BEGIN 00014_goal_contributions.sql
-- ####################################################################

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

DROP TRIGGER IF EXISTS set_goals_updated_at ON goals;
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
DROP POLICY IF EXISTS owner_select ON goal_contributions;
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


-- ####################################################################
-- BEGIN 00015_goal_editing_and_states.sql
-- ####################################################################

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


-- ####################################################################
-- BEGIN 00016_save_transaction_fixes.sql
-- ####################################################################

-- ============================================================================
-- 00016: Corrections to save_transaction_with_labels (Phase 5.4).
--        Found while routing the Flutter write path through the RPC.
--        Additive/forward-only; replaces the 00013 body, same signature.
-- ============================================================================
--
-- Two defects in the 00013 version blocked it from becoming the only write path:
--
-- 1. It rejected EVERY expense without a primary label, including expenses with
--    no labels at all. But `Unlabeled` is a modelled, expected state
--    (PrimaryLabelStatus.unlabeled, TODO 5.6 "bucket zero-label expenses as
--    Unlabeled"), and Phase 10 quick capture depends on being able to save an
--    expense before it is classified. The rule is really "an expense that HAS
--    labels must name exactly one of them primary" — attaching none is fine,
--    attaching some without choosing is not.
--
-- 2. Its INSERT column list omitted raw_sms and raw_sms_hash, so every
--    SMS-sourced row created through the RPC lost its provenance and its dedup
--    hash — silently re-importing the same message would then be possible.
-- ============================================================================

CREATE OR REPLACE FUNCTION save_transaction_with_labels(
  p_id             uuid,        -- null to create
  p_fields         jsonb,       -- account_id, amount, type, direction, merchant, vpa, bank, note, transacted_at, ...
  p_label_ids      uuid[],      -- contextual labels to attach (may be empty)
  p_primary_label  uuid         -- required when an expense has labels; must be in p_label_ids
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner      uuid := auth.uid();
  v_id         uuid := p_id;
  v_type       text := p_fields->>'type';
  v_is_expense boolean;
  v_has_labels boolean;
  v_old        jsonb;
  v_bad        int;
BEGIN
  IF NOT app_is_owner() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  v_is_expense := (v_type = 'debit');
  v_has_labels := COALESCE(array_length(p_label_ids, 1), 0) > 0;

  -- Every attached label must be owner-owned and assignable (active).
  SELECT count(*) INTO v_bad
  FROM unnest(p_label_ids) AS lid
  WHERE NOT EXISTS (
    SELECT 1 FROM labels l
    WHERE l.id = lid AND l.user_id = v_owner AND l.status = 'active'
  );
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'One or more labels are invalid, archived, or not yours.';
  END IF;

  -- A labelled expense must name exactly one attached label as primary. An
  -- expense with no labels is allowed and reports as Unlabeled.
  IF v_is_expense AND v_has_labels AND p_primary_label IS NULL THEN
    RAISE EXCEPTION
      'This expense has labels but no primary label. Choose which one it counts under.';
  END IF;
  IF NOT v_has_labels AND p_primary_label IS NOT NULL THEN
    RAISE EXCEPTION 'A primary label must also be attached to the transaction.';
  END IF;
  IF p_primary_label IS NOT NULL AND NOT (p_primary_label = ANY (p_label_ids)) THEN
    RAISE EXCEPTION 'The primary label must also be attached to the transaction.';
  END IF;

  IF v_id IS NULL THEN
    ----------------------------------------------------------------- create
    INSERT INTO transactions (
      user_id, account_id, amount, type, direction, vpa, merchant, bank,
      note, usd_amount, linked_invoice_id, transfer_group_id, source,
      transacted_at, primary_label_id, raw_sms, raw_sms_hash
    )
    VALUES (
      v_owner,
      (p_fields->>'account_id')::uuid,
      (p_fields->>'amount')::numeric,
      v_type,
      p_fields->>'direction',
      p_fields->>'vpa',
      p_fields->>'merchant',
      p_fields->>'bank',
      p_fields->>'note',
      (p_fields->>'usd_amount')::numeric,
      (p_fields->>'linked_invoice_id')::uuid,
      (p_fields->>'transfer_group_id')::uuid,
      COALESCE(p_fields->>'source', 'manual'),
      (p_fields->>'transacted_at')::timestamptz,
      p_primary_label,
      p_fields->>'raw_sms',
      p_fields->>'raw_sms_hash'
    )
    RETURNING id INTO v_id;
  ELSE
    ------------------------------------------------------------------- edit
    -- Lock the row and capture the old state for the audit.
    SELECT to_jsonb(t) INTO v_old
    FROM transactions t
    WHERE t.id = v_id AND t.user_id = v_owner AND t.is_deleted = false
    FOR UPDATE;
    IF v_old IS NULL THEN
      RAISE EXCEPTION 'Transaction not found or not editable.';
    END IF;

    UPDATE transactions SET
      account_id       = (p_fields->>'account_id')::uuid,
      amount           = (p_fields->>'amount')::numeric,
      type             = v_type,
      direction        = p_fields->>'direction',
      vpa              = p_fields->>'vpa',
      merchant         = p_fields->>'merchant',
      bank             = p_fields->>'bank',
      note             = p_fields->>'note',
      transacted_at    = (p_fields->>'transacted_at')::timestamptz,
      primary_label_id = p_primary_label,
      edit_history     = edit_history || jsonb_build_array(jsonb_build_object(
                           'old', v_old,
                           'edited_at', now()
                         ))
    WHERE id = v_id AND user_id = v_owner;
  END IF;

  -- Replace the contextual label set.
  DELETE FROM transaction_labels WHERE transaction_id = v_id;
  INSERT INTO transaction_labels (transaction_id, label_id, user_id)
  SELECT v_id, lid, v_owner FROM unnest(p_label_ids) AS lid
  ON CONFLICT DO NOTHING;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION save_transaction_with_labels(uuid, jsonb, uuid[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION save_transaction_with_labels(uuid, jsonb, uuid[], uuid) TO authenticated;
