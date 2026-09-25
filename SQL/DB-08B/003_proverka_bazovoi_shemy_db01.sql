-- DB-01 verification
-- APPROVED WORKING CONTOUR. Verification is limited to schema shablon_analiz_telefonnyh_peregovorov.
-- Run only after supabase/migrations/001_base_ingest_reliability.sql.
-- All synthetic data created below is rolled back.

begin;

do $verify$
declare
  v_table_count integer;
  v_bytea_count integer;
  v_manager_id uuid;
  v_call_id uuid;
  v_other_call_id uuid;
  v_canonical_event_id uuid;
  v_filter_operation_id uuid;
  v_filter_attempt_id uuid;
  v_filter_decision_id uuid;
  v_audio_operation_id uuid;
  v_audio_attempt_id uuid;
  v_count integer;
begin
  if not exists (
    select 1
    from pg_namespace
    where nspname = 'shablon_analiz_telefonnyh_peregovorov'
  ) then
    raise exception 'DB-01 verification failed: schema shablon_analiz_telefonnyh_peregovorov does not exist';
  end if;

  select count(*)
  into v_table_count
  from pg_tables
  where schemaname = 'shablon_analiz_telefonnyh_peregovorov'
    and tablename in (
      'managers',
      'calls',
      'call_events',
      'operations',
      'operation_attempts',
      'filter_decisions',
      'call_links',
      'temporary_audio_artifacts'
    );

  if v_table_count <> 8 then
    raise exception
      'DB-01 verification failed: expected 8 DB-01 tables, found %',
      v_table_count;
  end if;

  select count(*)
  into v_bytea_count
  from information_schema.columns
  where table_schema = 'shablon_analiz_telefonnyh_peregovorov'
    and data_type = 'bytea';

  if v_bytea_count <> 0 then
    raise exception
      'DB-01 verification failed: permanent bytea columns are forbidden in DB-01, found %',
      v_bytea_count;
  end if;

  insert into shablon_analiz_telefonnyh_peregovorov.managers (
    source_code,
    external_scope_ref,
    external_manager_id,
    full_name,
    department_ref
  )
  values (
    'verify_crm',
    'verify_account',
    'manager_001',
    'Тестовый Менеджер',
    'sales_test'
  )
  returning manager_id into v_manager_id;

  insert into shablon_analiz_telefonnyh_peregovorov.calls (
    source_adapter_code,
    connection_ref,
    call_identity_key,
    external_call_id,
    manager_id,
    started_at,
    ended_at,
    duration_seconds,
    direction,
    answer_status,
    occurrence_kind,
    classification,
    processing_state
  )
  values (
    'verify_source',
    'verify_connection',
    'call-key-001',
    'external-call-001',
    v_manager_id,
    now() - interval '5 minutes',
    now(),
    300,
    'inbound',
    'answered',
    'first',
    'client',
    'registered'
  )
  returning call_id into v_call_id;

  insert into shablon_analiz_telefonnyh_peregovorov.call_events (
    adapter_code,
    connection_ref,
    event_identity_key,
    external_event_id,
    external_call_id,
    event_type,
    source_event_at,
    direction,
    answer_status,
    audio_available,
    decision,
    call_id,
    safe_metadata
  )
  values (
    'verify_source',
    'verify_connection',
    'event-key-001',
    'external-event-001',
    'external-call-001',
    'call_finished',
    now(),
    'inbound',
    'answered',
    true,
    'accepted',
    v_call_id,
    '{"verification": true}'::jsonb
  )
  returning event_id into v_canonical_event_id;

  -- A duplicate receipt is preserved as a separate receipt record but points
  -- to the canonical event and may not create another logical call.
  insert into shablon_analiz_telefonnyh_peregovorov.call_events (
    adapter_code,
    connection_ref,
    event_identity_key,
    external_event_id,
    external_call_id,
    event_type,
    source_event_at,
    direction,
    answer_status,
    audio_available,
    decision,
    call_id,
    duplicate_of_event_id,
    safe_metadata
  )
  values (
    'verify_source',
    'verify_connection',
    'event-key-001',
    'external-event-001',
    'external-call-001',
    'call_finished',
    now(),
    'inbound',
    'answered',
    true,
    'duplicate',
    v_call_id,
    v_canonical_event_id,
    '{"verification": true, "duplicate_receipt": true}'::jsonb
  );

  select count(*)
  into v_count
  from shablon_analiz_telefonnyh_peregovorov.calls
  where source_adapter_code = 'verify_source'
    and connection_ref = 'verify_connection'
    and call_identity_key = 'call-key-001';

  if v_count <> 1 then
    raise exception
      'DB-01 verification failed: duplicate event changed logical call count, found %',
      v_count;
  end if;

  begin
    insert into shablon_analiz_telefonnyh_peregovorov.call_events (
      adapter_code,
      connection_ref,
      event_identity_key,
      event_type,
      decision,
      call_id
    )
    values (
      'verify_source',
      'verify_connection',
      'event-key-001',
      'call_finished',
      'accepted',
      v_call_id
    );

    raise exception
      'DB-01 verification failed: second non-duplicate event identity was accepted';
  exception
    when unique_violation then
      null;
  end;

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
    scope_ref,
    call_id,
    operation_type,
    idempotency_key,
    contract_version,
    correlation_id,
    input_refs,
    decision,
    operation_state,
    result_ref,
    completed_at
  )
  values (
    'shablon_analiz_telefonnyh_peregovorov',
    v_call_id,
    'filter_call',
    'filter-call-key-001',
    'contract-v1',
    'corr-filter-001',
    jsonb_build_object('call_id', v_call_id),
    'accepted',
    'succeeded',
    'filter-result-001',
    now()
  )
  returning operation_id into v_filter_operation_id;

  insert into shablon_analiz_telefonnyh_peregovorov.operation_attempts (
    operation_id,
    attempt_no,
    attempt_state,
    transport_result,
    decision,
    safe_context,
    requested_at,
    completed_at
  )
  values (
    v_filter_operation_id,
    1,
    'succeeded',
    'not_sent',
    'accepted',
    '{"verification": true}'::jsonb,
    now() - interval '1 second',
    now()
  )
  returning attempt_id into v_filter_attempt_id;

  insert into shablon_analiz_telefonnyh_peregovorov.filter_decisions (
    call_id,
    outcome,
    reason_code,
    filter_rules_version_ref,
    input_facts,
    operation_id
  )
  values (
    v_call_id,
    'accepted',
    null,
    'verify-filter-rules-v1',
    '{"client_call": true}'::jsonb,
    v_filter_operation_id
  )
  returning filter_decision_id into v_filter_decision_id;

  update shablon_analiz_telefonnyh_peregovorov.calls
  set
    current_filter_decision_id = v_filter_decision_id,
    processing_state = 'waiting_audio'
  where call_id = v_call_id;

  insert into shablon_analiz_telefonnyh_peregovorov.calls (
    source_adapter_code,
    connection_ref,
    call_identity_key,
    direction,
    answer_status,
    classification,
    processing_state
  )
  values (
    'verify_source',
    'verify_connection',
    'call-key-002',
    'outbound',
    'answered',
    'client',
    'registered'
  )
  returning call_id into v_other_call_id;

  -- A filter operation from one call must not be attachable to another call.
  begin
    insert into shablon_analiz_telefonnyh_peregovorov.filter_decisions (
      call_id,
      outcome,
      filter_rules_version_ref,
      input_facts,
      operation_id
    )
    values (
      v_other_call_id,
      'accepted',
      'verify-filter-rules-v1',
      '{}'::jsonb,
      v_filter_operation_id
    );

    raise exception
      'DB-01 verification failed: filter decision accepted an operation owned by another call';
  exception
    when foreign_key_violation then
      null;
  end;

  -- A call must not point to another call's current filter decision.
  begin
    update shablon_analiz_telefonnyh_peregovorov.calls
    set current_filter_decision_id = v_filter_decision_id
    where call_id = v_other_call_id;

    raise exception
      'DB-01 verification failed: call accepted another call''s current filter decision';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into shablon_analiz_telefonnyh_peregovorov.operations (
      scope_ref,
      call_id,
      operation_type,
      idempotency_key,
      contract_version,
      correlation_id,
      input_refs,
      decision
    )
    values (
      'shablon_analiz_telefonnyh_peregovorov',
      v_call_id,
      'filter_call',
      'filter-call-key-001',
      'contract-v1',
      'corr-filter-duplicate',
      '{}'::jsonb,
      'accepted'
    );

    raise exception
      'DB-01 verification failed: duplicate logical operation was accepted';
  exception
    when unique_violation then
      null;
  end;

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
    scope_ref,
    call_id,
    operation_type,
    idempotency_key,
    contract_version,
    correlation_id,
    input_refs,
    decision,
    operation_state,
    result_ref,
    completed_at
  )
  values (
    'shablon_analiz_telefonnyh_peregovorov',
    v_call_id,
    'get_audio',
    'audio-call-key-001',
    'contract-v1',
    'corr-audio-001',
    jsonb_build_object('call_id', v_call_id),
    'accepted',
    'succeeded',
    'audio-artifact-001',
    now()
  )
  returning operation_id into v_audio_operation_id;

  insert into shablon_analiz_telefonnyh_peregovorov.operation_attempts (
    operation_id,
    attempt_no,
    attempt_state,
    transport_result,
    decision,
    external_request_ref,
    safe_context,
    requested_at,
    completed_at
  )
  values (
    v_audio_operation_id,
    1,
    'succeeded',
    'transport_succeeded',
    'accepted',
    'verify-external-audio-request-001',
    '{"verification": true}'::jsonb,
    now() - interval '1 second',
    now()
  )
  returning attempt_id into v_audio_attempt_id;

  insert into shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts (
    call_id,
    acquisition_operation_id,
    artifact_identity_key,
    local_artifact_ref,
    source_ref,
    acquisition_state,
    size_bytes,
    duration_ms,
    integrity_algorithm,
    integrity_digest,
    delete_after,
    cleanup_state
  )
  values (
    v_call_id,
    v_audio_operation_id,
    'artifact-key-001',
    'local://atp-test/verify/audio-001',
    'verify_source:external-call-001',
    'ready',
    1024,
    300000,
    'sha256',
    'verification-digest-not-real-audio',
    now() + interval '1 hour',
    'not_due'
  );

  insert into shablon_analiz_telefonnyh_peregovorov.call_links (
    current_call_id,
    external_entity_type,
    external_entity_ref,
    relation_type,
    relation_identity_key,
    is_confirmed,
    basis_type,
    basis_ref,
    source_code
  )
  values (
    v_call_id,
    'crm_deal',
    'verify-deal-001',
    'belongs_to_deal',
    'deal-link-key-001',
    true,
    'trusted_crm_id',
    'verify-deal-001',
    'verify_crm'
  );

  begin
    insert into shablon_analiz_telefonnyh_peregovorov.calls (
      source_adapter_code,
      connection_ref,
      call_identity_key,
      duration_seconds
    )
    values (
      'verify_source',
      'verify_connection',
      'invalid-negative-duration',
      -1
    );

    raise exception
      'DB-01 verification failed: negative call duration was accepted';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into shablon_analiz_telefonnyh_peregovorov.call_events (
      adapter_code,
      connection_ref,
      event_identity_key,
      event_type,
      decision
    )
    values (
      'verify_source',
      'verify_connection',
      'rejected-without-code',
      'invalid_event',
      'rejected'
    );

    raise exception
      'DB-01 verification failed: rejected event without rejection_code was accepted';
  exception
    when check_violation then
      null;
  end;

  select count(*)
  into v_count
  from shablon_analiz_telefonnyh_peregovorov.call_events
  where adapter_code = 'verify_source'
    and connection_ref = 'verify_connection'
    and event_identity_key = 'event-key-001';

  if v_count <> 2 then
    raise exception
      'DB-01 verification failed: expected canonical + duplicate receipt, found %',
      v_count;
  end if;

  if not exists (
    select 1
    from shablon_analiz_telefonnyh_peregovorov.calls
    where call_id = v_call_id
      and current_filter_decision_id = v_filter_decision_id
      and processing_state = 'waiting_audio'
  ) then
    raise exception
      'DB-01 verification failed: call did not retain current filter decision/state';
  end if;

  if not exists (
    select 1
    from shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts
    where call_id = v_call_id
      and acquisition_operation_id = v_audio_operation_id
      and acquisition_state = 'ready'
      and cleanup_state = 'not_due'
  ) then
    raise exception
      'DB-01 verification failed: temporary audio metadata not linked to acquisition operation';
  end if;

  raise notice
    'DB-01 verification PASS inside transaction: tables, constraints, event deduplication, operation idempotency and temporary-audio metadata are consistent.';
end
$verify$;

rollback;
