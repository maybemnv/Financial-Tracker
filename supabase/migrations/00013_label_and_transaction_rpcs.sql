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
