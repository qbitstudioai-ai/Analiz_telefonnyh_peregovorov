-- DB-05 verification
-- APPROVED WORKING CONTOUR. Verification is limited to schema shablon.
-- Run after DB-01..DB-05 migrations.
-- The whole verification is rolled back and does not persist test rows.

begin;

do $verify$
declare
  v_missing text;
  v_count integer;
  v_definition text;
  v_labels text[];
  v_audit_id uuid;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'shablon'
  ) then
    raise exception 'DB-05 verification failed: schema shablon does not exist';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('business_confirmations'),
      ('callback_links'),
      ('outgoing_actions'),
      ('delivery_attempts'),
      ('analysis_disputes'),
      ('corrections'),
      ('audit_events')
  ) as required(required_relation)
  where to_regclass('shablon.' || required.required_relation) is null;

  if v_missing is not null then
    raise exception
      'DB-05 verification failed: missing relation(s): %',
      v_missing;
  end if;

  select count(*)
  into v_count
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'shablon'
    and t.typname in (
      'business_confirmation_source',
      'business_confirmation_event_kind',
      'callback_link_state',
      'outgoing_action_state',
      'delivery_provider_status',
      'delivery_reconciliation_state',
      'dispute_state',
      'correction_state',
      'correction_target_type',
      'audit_result'
    );

  if v_count <> 10 then
    raise exception
      'DB-05 verification failed: expected 10 DB-05 enum types, found %',
      v_count;
  end if;

  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'shablon'
    and p.proname in (
      'validate_business_confirmation_insert',
      'guard_business_confirmation_immutable',
      'guard_db05_history_delete',
      'validate_callback_link',
      'guard_callback_link_update',
      'validate_outgoing_action_insert',
      'guard_outgoing_action_update',
      'guard_delivery_attempt_insert',
      'guard_delivery_attempt_update',
      'guard_delivery_attempt_delete',
      'guard_analysis_dispute_initial_state',
      'guard_analysis_dispute_update',
      'guard_correction_initial_state',
      'guard_correction_update',
      'guard_audit_event_append_only'
    );

  if v_count <> 15 then
    raise exception
      'DB-05 verification failed: expected 15 DB-05 functions, found %',
      v_count;
  end if;

  select count(*)
  into v_count
  from pg_trigger tg
  join pg_class c on c.oid = tg.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where not tg.tgisinternal
    and n.nspname = 'shablon'
    and tg.tgname in (
      'trg_business_confirmations_validate_insert',
      'trg_business_confirmations_immutable',
      'trg_callback_links_validate',
      'trg_callback_links_guard_update',
      'trg_callback_links_guard_delete',
      'trg_outgoing_actions_validate_insert',
      'trg_outgoing_actions_guard_update',
      'trg_outgoing_actions_guard_delete',
      'trg_delivery_attempts_guard_insert',
      'trg_delivery_attempts_guard_update',
      'trg_delivery_attempts_guard_delete',
      'trg_analysis_disputes_guard_initial',
      'trg_analysis_disputes_guard_update',
      'trg_analysis_disputes_guard_delete',
      'trg_corrections_guard_initial',
      'trg_corrections_guard_update',
      'trg_corrections_guard_delete',
      'trg_audit_events_append_only'
    );

  if v_count <> 18 then
    raise exception
      'DB-05 verification failed: expected 18 DB-05 triggers, found %',
      v_count;
  end if;

  -- Upstream exact ownership keys added by DB-05.
  if not exists (
    select 1
    from pg_constraint con
    where con.conrelid = 'shablon.operation_attempts'::regclass
      and con.conname = 'operation_attempts_attempt_operation_unique'
      and con.contype = 'u'
  ) then
    raise exception
      'DB-05 verification failed: exact operation attempt key missing';
  end if;

  if not exists (
    select 1
    from pg_constraint con
    where con.conrelid = 'shablon.role_assignment_versions'::regclass
      and con.conname = 'role_assignment_versions_role_call_unique'
      and con.contype = 'u'
  ) then
    raise exception
      'DB-05 verification failed: exact role/call key missing';
  end if;

  -- CRM/human source facts must remain physically separate from AI output.
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'shablon'
      and table_name = 'business_confirmations'
      and column_name in ('analysis_id', 'ai_outcome_id', 'claim_id')
  ) then
    raise exception
      'DB-05 verification failed: trusted business confirmation is coupled to AI result';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'shablon'
      and table_name = 'ai_inferred_outcomes'
      and column_name = 'analysis_id'
  ) then
    raise exception
      'DB-05 verification failed: DB-04 AI outcome source is missing';
  end if;

  -- Outgoing action pins exact analysis + call and is created before attempts.
  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conrelid = 'shablon.outgoing_actions'::regclass
    and con.conname = 'outgoing_actions_analysis_same_call';

  if v_definition is null
     or regexp_replace(lower(v_definition), '\s+', ' ', 'g')
        not like '%foreign key (analysis_id, call_id)%'
  then
    raise exception
      'DB-05 verification failed: outgoing action exact analysis/call FK missing';
  end if;

  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conrelid = 'shablon.delivery_attempts'::regclass
    and con.conname = 'delivery_attempts_action_same_call';

  if v_definition is null
     or regexp_replace(lower(v_definition), '\s+', ' ', 'g')
        not like '%foreign key (outgoing_action_id, call_id)%'
  then
    raise exception
      'DB-05 verification failed: delivery attempt does not require persisted outgoing action';
  end if;

  -- Delivery attempt is tied to one exact operation attempt.
  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conrelid = 'shablon.delivery_attempts'::regclass
    and con.conname = 'delivery_attempts_attempt_same_operation';

  if v_definition is null
     or regexp_replace(lower(v_definition), '\s+', ' ', 'g')
        not like '%foreign key (attempt_id, operation_id)%'
  then
    raise exception
      'DB-05 verification failed: delivery attempt exact operation-attempt FK missing';
  end if;

  -- Delivery state semantics: retryability and success are explicit.
  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conrelid = 'shablon.delivery_attempts'::regclass
    and con.conname = 'delivery_attempts_retry_shape';

  if v_definition is null
     or lower(v_definition) not like '%failed_retryable%'
     or lower(v_definition) not like '%safe_retry_allowed%'
  then
    raise exception
      'DB-05 verification failed: delivery retryability CHECK missing/wrong';
  end if;

  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conrelid = 'shablon.delivery_attempts'::regclass
    and con.conname = 'delivery_attempts_succeeded_shape';

  if v_definition is null
     or lower(v_definition) not like '%provider_status%'
     or lower(v_definition) not like '%delivered%'
     or lower(v_definition) not like '%transport_succeeded%'
  then
    raise exception
      'DB-05 verification failed: succeeded delivery is not tied to confirmed delivery';
  end if;

  -- Callback candidate/final decision metadata must not be ambiguous.
  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conrelid = 'shablon.callback_links'::regclass
    and con.conname = 'callback_links_decision_metadata';

  if v_definition is null
     or lower(v_definition) not like '%candidate%'
     or lower(v_definition) not like '%confirmed%'
     or lower(v_definition) not like '%rejected%'
  then
    raise exception
      'DB-05 verification failed: callback decision metadata CHECK missing/wrong';
  end if;

  -- Audit rows always represent a completed result classification.
  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conrelid = 'shablon.audit_events'::regclass
    and con.conname = 'audit_events_result_time';

  if v_definition is null
     or lower(v_definition) not like '%result_at is not null%'
  then
    raise exception
      'DB-05 verification failed: audit result time is not required';
  end if;

  -- The send guard must block confirmed delivery and unresolved unknown outcome.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'shablon'
    and p.proname = 'guard_delivery_attempt_insert';

  if v_definition is null
     or v_definition not ilike '%Confirmed delivery forbids another attempt%'
     or v_definition not ilike '%outcome_unknown requires reconciliation before any retry%'
  then
    raise exception
      'DB-05 verification failed: delivery duplicate/unknown guard missing';
  end if;

  -- Reconciliation cannot silently mutate the original send facts.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'shablon'
    and p.proname = 'guard_delivery_attempt_update';

  if v_definition is null
     or v_definition not ilike '%Original delivery attempt facts are immutable%'
     or v_definition not ilike '%confirmed_not_delivered%'
     or v_definition not ilike '%confirmed_delivered%'
  then
    raise exception
      'DB-05 verification failed: delivery reconciliation guard missing';
  end if;

  -- Correction rows must have exactly one typed target.
  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conrelid = 'shablon.corrections'::regclass
    and con.conname = 'corrections_target_exactly_one';

  if v_definition is null
     or lower(v_definition) not like '%num_nonnulls%'
  then
    raise exception
      'DB-05 verification failed: correction exact-target constraint missing';
  end if;

  -- Regression: a dispute cannot be inserted already resolved.
  begin
    insert into shablon.analysis_disputes (
      call_id,
      analysis_id,
      author_ref,
      reason,
      dispute_state,
      resolution_reason,
      resolved_by_ref,
      resolved_at
    )
    values (
      gen_random_uuid(),
      gen_random_uuid(),
      'verify_actor',
      'verify dispute',
      'resolved',
      'pre-resolved',
      'verify_reviewer',
      now()
    );

    raise exception
      'DB-05 verification failed: dispute inserted directly as resolved';
  exception
    when raise_exception then
      if sqlerrm like 'DB-05 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Dispute must be inserted as open%' then
        raise;
      end if;
  end;

  -- Regression: a correction cannot be inserted directly as applied.
  begin
    insert into shablon.corrections (
      call_id,
      target_type,
      target_manager_id,
      before_ref,
      after_ref,
      actor_ref,
      reason,
      correction_state,
      apply_operation_id,
      applied_at
    )
    values (
      gen_random_uuid(),
      'manager',
      gen_random_uuid(),
      'old',
      'new',
      'verify_actor',
      'verify correction',
      'applied',
      gen_random_uuid(),
      now()
    );

    raise exception
      'DB-05 verification failed: correction inserted directly as applied';
  exception
    when raise_exception then
      if sqlerrm like 'DB-05 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Correction must be inserted as proposed%' then
        raise;
      end if;
  end;

  -- Regression: an outgoing action cannot be inserted cancelled/final.
  begin
    insert into shablon.outgoing_actions (
      call_id,
      analysis_id,
      logical_action_key,
      purpose_code,
      channel_ref,
      recipient_ref,
      message_version,
      message_body,
      message_sha256,
      creation_operation_id,
      action_state,
      cancel_reason,
      cancelled_at
    )
    values (
      gen_random_uuid(),
      gen_random_uuid(),
      'verify-db05-direct-cancelled',
      'manager_feedback',
      'verify_channel',
      'verify_recipient',
      'v1',
      'safe test message',
      'verify-message-hash',
      gen_random_uuid(),
      'cancelled',
      'pre-cancelled',
      now()
    );

    raise exception
      'DB-05 verification failed: outgoing action inserted directly cancelled';
  exception
    when raise_exception then
      if sqlerrm like 'DB-05 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Outgoing action must be inserted as prepared%' then
        raise;
      end if;
  end;

  -- Audit can be appended without a business FK and must then be immutable.
  insert into shablon.audit_events (
    actor_ref,
    actor_capability,
    action_type,
    target_type,
    target_ref,
    reason,
    result,
    source_channel,
    safe_details,
    result_at
  )
  values (
    'verify_actor',
    'verify_capability',
    'verify_action',
    'verify_target',
    'verify_ref',
    'DB-05 verification',
    'success',
    'verify',
    '{"verification":true}'::jsonb,
    now()
  )
  returning audit_event_id into v_audit_id;

  begin
    update shablon.audit_events
    set reason = 'attempted mutation'
    where audit_event_id = v_audit_id;

    raise exception
      'DB-05 verification failed: audit event was mutable';
  exception
    when raise_exception then
      if sqlerrm like 'DB-05 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Audit events are append-only%' then
        raise;
      end if;
  end;

  begin
    delete from shablon.audit_events
    where audit_event_id = v_audit_id;

    raise exception
      'DB-05 verification failed: audit event was deletable';
  exception
    when raise_exception then
      if sqlerrm like 'DB-05 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Audit events are append-only%' then
        raise;
      end if;
  end;

  raise notice 'DB-05 verification passed';
end
$verify$;

rollback;
