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
