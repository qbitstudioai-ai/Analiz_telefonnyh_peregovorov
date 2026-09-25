-- DB-02 verification
-- APPROVED WORKING CONTOUR. Verification is limited to schema shablon_analiz_telefonnyh_peregovorov.
-- Run after migrations 001 and 002.
-- Synthetic data is rolled back at the end.

begin;

do $verify$
declare
  v_table_count integer;
  v_forbidden_fk_count integer;
  v_forbidden_column_count integer;
  v_manager_id uuid;
  v_call_id uuid;
  v_other_call_id uuid;
  v_audio_operation_id uuid;
  v_audio_artifact_id uuid;
  v_transcribe_operation_id uuid;
  v_raw_transcript_id uuid;
  v_segment_manager_id uuid;
  v_segment_client_id uuid;
  v_roles_operation_id uuid;
  v_role_version_id uuid;
  v_privacy_operation_id uuid;
  v_pseudo_transcript_id uuid;
  v_pseudo_segment_manager_id uuid;
  v_pseudo_segment_client_id uuid;
  v_mapping_id uuid;
  v_package_id uuid;
  v_llm_operation_id uuid;
  v_quality_operation_id uuid;
  v_quality_id uuid;
  v_speech_operation_id uuid;
  v_count integer;
begin
  select count(*)
  into v_table_count
  from pg_tables
  where schemaname = 'shablon_analiz_telefonnyh_peregovorov'
    and tablename in (
      'raw_transcripts',
      'transcript_segments',
      'role_assignment_versions',
      'role_assignments',
      'pseudonymized_transcripts',
      'pseudonymized_segments',
      'privacy_packages',
      'privacy_package_segments',
      'pseudonym_mappings',
      'processing_quality',
      'speech_metrics'
    );

  if v_table_count <> 11 then
    raise exception
      'DB-02 verification failed: expected 11 DB-02 tables, found %',
      v_table_count;
  end if;

  -- Privacy packages may point only to safe pseudonymized artifacts,
  -- role/version metadata and operations. Direct raw/mapping FKs are forbidden.
  select count(*)
  into v_forbidden_fk_count
  from pg_constraint con
  join pg_class child on child.oid = con.conrelid
  join pg_namespace child_ns on child_ns.oid = child.relnamespace
  join pg_class parent on parent.oid = con.confrelid
  join pg_namespace parent_ns on parent_ns.oid = parent.relnamespace
  where con.contype = 'f'
    and child_ns.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and child.relname in ('privacy_packages', 'privacy_package_segments')
    and parent_ns.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and parent.relname in ('raw_transcripts', 'transcript_segments', 'pseudonym_mappings');

  if v_forbidden_fk_count <> 0 then
    raise exception
      'DB-02 verification failed: privacy package has % forbidden raw/mapping FK(s)',
      v_forbidden_fk_count;
  end if;

  select count(*)
  into v_forbidden_column_count
  from information_schema.columns
  where table_schema = 'shablon_analiz_telefonnyh_peregovorov'
    and table_name in ('privacy_packages', 'privacy_package_segments')
    and (
      column_name ilike '%raw_text%'
      or column_name ilike '%protected_value%'
      or column_name ilike '%mapping%'
    );

  if v_forbidden_column_count <> 0 then
    raise exception
      'DB-02 verification failed: privacy package contains % forbidden raw/mapping column(s)',
      v_forbidden_column_count;
  end if;

  insert into shablon_analiz_telefonnyh_peregovorov.managers (
    source_code,
    external_scope_ref,
    external_manager_id,
    full_name
  )
  values (
    'verify_crm_db02',
    'verify_account_db02',
    'manager_db02',
    'Тестовый Менеджер DB-02'
  )
  returning manager_id into v_manager_id;

  insert into shablon_analiz_telefonnyh_peregovorov.calls (
    source_adapter_code,
    connection_ref,
    call_identity_key,
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
    'verify_source_db02',
    'verify_connection_db02',
    'call-db02-001',
    v_manager_id,
    now() - interval '3 minutes',
    now(),
    180,
    'inbound',
    'answered',
    'first',
    'client',
    'processing'
  )
  returning call_id into v_call_id;

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
    'verify_source_db02',
    'verify_connection_db02',
    'call-db02-002',
    'outbound',
    'answered',
    'client',
    'processing'
  )
  returning call_id into v_other_call_id;

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
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
    v_call_id,
    'get_audio',
    'db02-audio-001',
    'contract-v1',
    'db02-corr-audio-001',
    '{}'::jsonb,
    'accepted',
    'succeeded',
    'db02-audio-result-001',
    now()
  )
  returning operation_id into v_audio_operation_id;

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
    'db02-artifact-001',
    'local://atp-test/db02/audio-001',
    'verify_source_db02:call-db02-001',
    'ready',
    2048,
    180000,
    'sha256',
    'db02-verification-audio-digest',
    now() + interval '1 hour',
    'not_due'
  )
  returning audio_artifact_id into v_audio_artifact_id;

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
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
    v_call_id,
    'transcribe',
    'db02-transcribe-001',
    'contract-v1',
    'db02-corr-transcribe-001',
    jsonb_build_object('audio_artifact_id', v_audio_artifact_id),
    'accepted',
    'succeeded',
    'db02-transcript-result-001',
    now()
  )
  returning operation_id into v_transcribe_operation_id;

  insert into shablon_analiz_telefonnyh_peregovorov.raw_transcripts (
    call_id,
    version_no,
    audio_artifact_id,
    created_by_operation_id,
    engine_provider,
    engine_model,
    engine_version,
    engine_config_version,
    engine_config,
    raw_text,
    content_sha256,
    validation_status,
    version_state,
    retention_policy_ref,
    retain_until
  )
  values (
    v_call_id,
    1,
    v_audio_artifact_id,
    v_transcribe_operation_id,
    'verify_local',
    'verify_asr',
    'build-test',
    'config-test-v1',
    '{"language":"ru","verification":true}'::jsonb,
    'Менеджер: Добрый день. Клиент: Здравствуйте, меня зовут Иван.',
    'db02-raw-transcript-digest',
    'passed',
    'current',
    'verify-raw-retention',
    now() + interval '1 day'
  )
  returning transcript_id into v_raw_transcript_id;

  insert into shablon_analiz_telefonnyh_peregovorov.transcript_segments (
    transcript_id,
    call_id,
    segment_key,
    segment_order,
    start_ms,
    end_ms,
    technical_speaker,
    raw_text,
    content_sha256,
    engine_confidence,
    technical_quality
  )
  values
  (
    v_raw_transcript_id,
    v_call_id,
    'seg-001',
    0,
    0,
    2500,
    'SPEAKER_00',
    'Добрый день.',
    'db02-seg-manager-digest',
    0.95,
    '{"verification":true}'::jsonb
  )
  returning segment_id into v_segment_manager_id;

  insert into shablon_analiz_telefonnyh_peregovorov.transcript_segments (
    transcript_id,
    call_id,
    segment_key,
    segment_order,
    start_ms,
    end_ms,
    technical_speaker,
    raw_text,
    content_sha256,
    engine_confidence,
    technical_quality
  )
  values
  (
    v_raw_transcript_id,
    v_call_id,
    'seg-002',
    1,
    2600,
    6000,
    'SPEAKER_01',
    'Здравствуйте, меня зовут Иван.',
    'db02-seg-client-digest',
    0.90,
    '{"verification":true}'::jsonb
  )
  returning segment_id into v_segment_client_id;

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
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
    v_call_id,
    'assign_roles',
    'db02-roles-001',
    'contract-v1',
    'db02-corr-roles-001',
    jsonb_build_object('transcript_id', v_raw_transcript_id),
    'accepted',
    'succeeded',
    'db02-role-version-001',
    now()
  )
  returning operation_id into v_roles_operation_id;

  insert into shablon_analiz_telefonnyh_peregovorov.role_assignment_versions (
    call_id,
    transcript_id,
    version_no,
    rules_version_ref,
    created_by_operation_id,
    version_state
  )
  values (
    v_call_id,
    v_raw_transcript_id,
    1,
    'verify-role-rules-v1',
    v_roles_operation_id,
    'current'
  )
  returning role_assignment_version_id into v_role_version_id;

  insert into shablon_analiz_telefonnyh_peregovorov.role_assignments (
    role_assignment_version_id,
    technical_speaker,
    business_role,
    confidence_status,
    manager_id,
    evidence_types,
    basis_refs,
    source_conflict
  )
  values
  (
    v_role_version_id,
    'SPEAKER_00',
    'manager',
    'confirmed',
    v_manager_id,
    array['trusted_extension'],
    '{"extension":"verify-extension"}'::jsonb,
    false
  ),
  (
    v_role_version_id,
    'SPEAKER_01',
    'client',
    'assumed',
    null,
    array['confirmed_other_side'],
    '{"rule":"two_party_client_call"}'::jsonb,
    false
  );

  begin
    insert into shablon_analiz_telefonnyh_peregovorov.role_assignments (
      role_assignment_version_id,
      technical_speaker,
      business_role,
      confidence_status
    )
    values (
      v_role_version_id,
      'SPEAKER_BAD',
      'manager',
      'undetermined'
    );

    raise exception
      'DB-02 verification failed: undetermined speaker was allowed to become manager';
  exception
    when check_violation then
      null;
  end;

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
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
    v_call_id,
    'prepare_privacy',
    'db02-privacy-001',
    'contract-v1',
    'db02-corr-privacy-001',
    jsonb_build_object(
      'raw_transcript_id', v_raw_transcript_id,
      'role_assignment_version_id', v_role_version_id
    ),
    'accepted',
    'succeeded',
    'db02-pseudonymized-001',
    now()
  )
  returning operation_id into v_privacy_operation_id;

  insert into shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts (
    call_id,
    raw_transcript_id,
    role_assignment_version_id,
    version_no,
    pseudonymization_rules_version,
    created_by_operation_id,
    pseudonymized_text,
    content_sha256,
    privacy_status,
    version_state,
    retention_policy_ref,
    retain_until
  )
  values (
    v_call_id,
    v_raw_transcript_id,
    v_role_version_id,
    1,
    'verify-privacy-rules-v1',
    v_privacy_operation_id,
    'МЕНЕДЖЕР: Добрый день. КЛИЕНТ: Здравствуйте, меня зовут PERSON_01.',
    'db02-pseudonymized-digest',
    'passed',
    'current',
    'verify-pseudonymized-retention',
    now() + interval '7 days'
  )
  returning pseudonymized_transcript_id into v_pseudo_transcript_id;

  insert into shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments (
    pseudonymized_transcript_id,
    raw_transcript_id,
    call_id,
    source_segment_id,
    segment_key,
    segment_order,
    start_ms,
    end_ms,
    speaker_label,
    business_role,
    pseudonymized_text,
    content_sha256
  )
  values
  (
    v_pseudo_transcript_id,
    v_raw_transcript_id,
    v_call_id,
    v_segment_manager_id,
    'safe-seg-001',
    0,
    0,
    2500,
    'MANAGER_01',
    'manager',
    'Добрый день.',
    'db02-safe-manager-digest'
  )
  returning pseudonymized_segment_id into v_pseudo_segment_manager_id;

  insert into shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments (
    pseudonymized_transcript_id,
    raw_transcript_id,
    call_id,
    source_segment_id,
    segment_key,
    segment_order,
    start_ms,
    end_ms,
    speaker_label,
    business_role,
    pseudonymized_text,
    content_sha256
  )
  values
  (
    v_pseudo_transcript_id,
    v_raw_transcript_id,
    v_call_id,
    v_segment_client_id,
    'safe-seg-002',
    1,
    2600,
    6000,
    'CLIENT_01',
    'client',
    'Здравствуйте, меня зовут PERSON_01.',
    'db02-safe-client-digest'
  )
  returning pseudonymized_segment_id into v_pseudo_segment_client_id;

  insert into shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings (
    pseudonymized_transcript_id,
    pseudonym_scope_ref,
    pseudonym,
    protected_value,
    purpose_code,
    retention_policy_ref,
    retain_until
  )
  values (
    v_pseudo_transcript_id,
    'call-db02-001',
    'PERSON_01',
    'Иван',
    'analysis_reidentification_if_authorized',
    'verify-mapping-retention',
    now() + interval '1 day'
  )
  returning pseudonym_mapping_id into v_mapping_id;

  v_package_id := gen_random_uuid();

  insert into shablon_analiz_telefonnyh_peregovorov.privacy_packages (
    privacy_package_id,
    call_id,
    pseudonymized_transcript_id,
    role_assignment_version_id,
    version_no,
    privacy_status,
    checker_version,
    preparation_operation_id,
    package_sha256,
    retention_policy_ref,
    retain_until,
    version_state
  )
  values (
    v_package_id,
    v_call_id,
    v_pseudo_transcript_id,
    v_role_version_id,
    1,
    'passed',
    'verify-privacy-checker-v1',
    v_privacy_operation_id,
    'db02-package-digest',
    'verify-package-retention',
    now() + interval '7 days',
    'current'
  );

  insert into shablon_analiz_telefonnyh_peregovorov.privacy_package_segments (
    privacy_package_id,
    pseudonymized_transcript_id,
    call_id,
    pseudonymized_segment_id,
    package_order
  )
  values
  (
    v_package_id,
    v_pseudo_transcript_id,
    v_call_id,
    v_pseudo_segment_manager_id,
    0
  ),
  (
    v_package_id,
    v_pseudo_transcript_id,
    v_call_id,
    v_pseudo_segment_client_id,
    1
  );

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
    call_id,
    operation_type,
    idempotency_key,
    contract_version,
    correlation_id,
    input_refs,
    decision,
    operation_state
  )
  values (
    v_call_id,
    'analyze_llm',
    'db02-llm-001',
    'contract-v1',
    'db02-corr-llm-001',
    jsonb_build_object('privacy_package_id', v_package_id),
    'accepted',
    'not_started'
  )
  returning operation_id into v_llm_operation_id;

  update shablon_analiz_telefonnyh_peregovorov.privacy_packages
  set llm_operation_id = v_llm_operation_id
  where privacy_package_id = v_package_id;

  -- blocked package must never point to an LLM operation.
  begin
    insert into shablon_analiz_telefonnyh_peregovorov.privacy_packages (
      call_id,
      pseudonymized_transcript_id,
      role_assignment_version_id,
      version_no,
      privacy_status,
      issue_codes,
      checker_version,
      preparation_operation_id,
      llm_operation_id,
      package_sha256,
      retention_policy_ref,
      version_state
    )
    values (
      v_call_id,
      v_pseudo_transcript_id,
      v_role_version_id,
      2,
      'blocked',
      array['pii_detected'],
      'verify-privacy-checker-v1',
      v_privacy_operation_id,
      v_llm_operation_id,
      'db02-blocked-package-digest',
      'verify-package-retention',
      'candidate'
    );

    raise exception
      'DB-02 verification failed: blocked package accepted an LLM operation';
  exception
    when check_violation then
      null;
  end;

  -- Deleted reverse mapping must not keep either the protected value or
  -- a protected local reference.
  begin
    insert into shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings (
      pseudonymized_transcript_id,
      pseudonym_scope_ref,
      pseudonym,
      protected_value,
      purpose_code,
      retention_policy_ref,
      value_deleted_at
    )
    values (
      v_pseudo_transcript_id,
      'call-db02-001',
      'PERSON_BAD',
      'Should not survive retention',
      'verification',
      'verify-mapping-retention',
      now()
    );

    raise exception
      'DB-02 verification failed: deleted mapping retained protected target';
  exception
    when check_violation then
      null;
  end;

  -- Operation/call ownership must prevent cross-call transcript creation.
  begin
    insert into shablon_analiz_telefonnyh_peregovorov.raw_transcripts (
      call_id,
      version_no,
      created_by_operation_id,
      engine_provider,
      engine_model,
      engine_config_version,
      raw_text,
      content_sha256,
      retention_policy_ref
    )
    values (
      v_other_call_id,
      1,
      v_transcribe_operation_id,
      'verify_local',
      'verify_asr',
      'config-test-v1',
      'wrong call',
      'wrong-call-digest',
      'verify-raw-retention'
    );

    raise exception
      'DB-02 verification failed: transcript accepted operation owned by another call';
  exception
    when foreign_key_violation then
      null;
  end;

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
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
    v_call_id,
    'assess_processing_quality',
    'db02-quality-001',
    'contract-v1',
    'db02-corr-quality-001',
    jsonb_build_object(
      'raw_transcript_id', v_raw_transcript_id,
      'role_assignment_version_id', v_role_version_id
    ),
    'accepted',
    'succeeded',
    'db02-quality-result-001',
    now()
  )
  returning operation_id into v_quality_operation_id;

  insert into shablon_analiz_telefonnyh_peregovorov.processing_quality (
    call_id,
    version_no,
    raw_transcript_id,
    role_assignment_version_id,
    audio_artifact_id,
    quality_rules_version_ref,
    audio_quality,
    transcription_metrics,
    role_metrics,
    overall_reliability,
    created_by_operation_id,
    version_state
  )
  values (
    v_call_id,
    1,
    v_raw_transcript_id,
    v_role_version_id,
    v_audio_artifact_id,
    'verify-quality-rules-v1',
    '{"decoded":true}'::jsonb,
    '{"verification":"ok"}'::jsonb,
    '{"roles":"confirmed_or_assumed"}'::jsonb,
    'reliable',
    v_quality_operation_id,
    'current'
  )
  returning quality_id into v_quality_id;

  insert into shablon_analiz_telefonnyh_peregovorov.operations (
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
    v_call_id,
    'calculate_speech_metrics',
    'db02-speech-001',
    'contract-v1',
    'db02-corr-speech-001',
    jsonb_build_object(
      'raw_transcript_id', v_raw_transcript_id,
      'role_assignment_version_id', v_role_version_id,
      'quality_id', v_quality_id
    ),
    'accepted',
    'succeeded',
    'db02-speech-result-001',
    now()
  )
  returning operation_id into v_speech_operation_id;

  insert into shablon_analiz_telefonnyh_peregovorov.speech_metrics (
    call_id,
    version_no,
    raw_transcript_id,
    role_assignment_version_id,
    quality_id,
    metrics_rules_version_ref,
    manager_talk_ratio,
    client_talk_ratio,
    total_pause_ms,
    interruption_count,
    manager_speech_rate_wpm,
    client_speech_rate_wpm,
    call_duration_ms,
    reliability,
    created_by_operation_id,
    version_state
  )
  values (
    v_call_id,
    1,
    v_raw_transcript_id,
    v_role_version_id,
    v_quality_id,
    'verify-speech-rules-v1',
    0.45,
    0.55,
    1200,
    1,
    135,
    120,
    180000,
    'reliable',
    v_speech_operation_id,
    'current'
  );

  select count(*)
  into v_count
  from shablon_analiz_telefonnyh_peregovorov.privacy_package_segments
  where privacy_package_id = v_package_id;

  if v_count <> 2 then
    raise exception
      'DB-02 verification failed: exact package segment set expected 2, found %',
      v_count;
  end if;

  if not exists (
    select 1
    from shablon_analiz_telefonnyh_peregovorov.privacy_packages
    where privacy_package_id = v_package_id
      and privacy_status = 'passed'
      and llm_operation_id = v_llm_operation_id
  ) then
    raise exception
      'DB-02 verification failed: passed package did not retain LLM operation provenance';
  end if;

  if not exists (
    select 1
    from shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings
    where pseudonym_mapping_id = v_mapping_id
      and pseudonym = 'PERSON_01'
      and protected_value = 'Иван'
  ) then
    raise exception
      'DB-02 verification failed: protected mapping was not stored separately';
  end if;

  raise notice
    'DB-02 verification PASS inside transaction: raw/pseudonym/mapping separation, exact safe package segments, version ownership, role constraints, quality and speech metrics are consistent.';
end
$verify$;

rollback;
