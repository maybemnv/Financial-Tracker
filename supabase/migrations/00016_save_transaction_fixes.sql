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
