-- DB-04 verification
-- TEST/LOCAL ONLY.
-- Run after DB-01..DB-04 migrations.
-- The whole verification is rolled back and does not persist fixture rows.

begin;

do $verify$
declare
  v_missing text;
  v_count integer;
  v_definition text;
  v_labels text[];
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-04 verification failed: schema atp_test does not exist';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('analysis_versions'),
      ('analysis_knowledge_inputs'),
      ('analysis_claims'),
      ('criterion_scores'),
      ('stage_results'),
      ('analysis_observations'),
      ('ai_inferred_outcomes'),
      ('evidence_sets'),
      ('evidence_conversation_refs'),
      ('evidence_knowledge_refs'),
      ('evidence_absence_checks')
  ) as required(required_relation)
  where to_regclass('atp_test.' || required.required_relation) is null;

  if v_missing is not null then
    raise exception
      'DB-04 verification failed: missing relation(s): %',
      v_missing;
  end if;

  select count(*)
  into v_count
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'atp_test'
    and t.typname in (
      'analysis_state',
      'analysis_claim_type',
      'evidence_requirement',
      'evidence_type',
      'evidence_integrity',
      'evidence_coverage',
      'evidence_rule_kind',
      'observation_type',
      'absence_scope_kind'
    );

  if v_count <> 9 then
    raise exception
      'DB-04 verification failed: expected 9 DB-04 enum types, found %',
      v_count;
  end if;

  select array_agg(e.enumlabel order by e.enumsortorder)
  into v_labels
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  join pg_enum e on e.enumtypid = t.oid
  where n.nspname = 'atp_test'
    and t.typname = 'analysis_state';

  if v_labels is distinct from
     array['candidate','validated','current','superseded','invalidated']::text[]
  then
    raise exception
      'DB-04 verification failed: unexpected analysis_state labels: %',
      v_labels;
  end if;

  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname in (
      'guard_analysis_initial_state',
      'guard_analysis_child_mutation',
      'validate_criterion_score',
      'validate_stage_result',
      'validate_evidence_target_rule',
      'guard_evidence_set_mutation',
      'guard_evidence_ref_mutation',
      'validate_evidence_conversation_ref',
      'validate_evidence_knowledge_ref',
      'validate_evidence_absence_check',
      'calculate_analysis_overall_score',
      'validate_analysis_evidence_gate',
      'guard_analysis_version_update'
    );

  if v_count <> 13 then
    raise exception
      'DB-04 verification failed: expected 13 DB-04 functions, found %',
      v_count;
  end if;

  select count(*)
  into v_count
  from pg_trigger tg
  join pg_class c on c.oid = tg.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where not tg.tgisinternal
    and n.nspname = 'atp_test'
    and tg.tgname in (
      'trg_analysis_versions_guard_initial_state',
      'trg_analysis_knowledge_inputs_guard',
      'trg_analysis_claims_guard',
      'trg_criterion_scores_guard',
      'trg_stage_results_guard',
      'trg_analysis_observations_guard',
      'trg_ai_inferred_outcomes_guard',
      'trg_criterion_scores_validate',
      'trg_stage_results_validate',
      'trg_evidence_sets_validate_target_rule',
      'trg_evidence_sets_guard',
      'trg_evidence_conversation_refs_guard',
      'trg_evidence_knowledge_refs_guard',
      'trg_evidence_absence_checks_guard',
      'trg_evidence_conversation_refs_validate',
      'trg_evidence_knowledge_refs_validate',
      'trg_evidence_absence_checks_validate',
      'trg_analysis_versions_guard_update'
    );

  if v_count <> 18 then
    raise exception
      'DB-04 verification failed: expected 18 DB-04 triggers, found %',
      v_count;
  end if;

  -- DB-04 extends two DB-02 relations with exact composite ownership keys.
  if not exists (
    select 1
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname = 'privacy_packages'
      and con.conname = 'privacy_packages_package_role_call_unique'
      and con.contype = 'u'
  ) then
    raise exception
      'DB-04 verification failed: privacy package exact role/call unique key missing';
  end if;

  if not exists (
    select 1
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname = 'processing_quality'
      and con.conname = 'processing_quality_quality_inputs_call_unique'
      and con.contype = 'u'
  ) then
    raise exception
      'DB-04 verification failed: processing quality exact input unique key missing';
  end if;

  -- The analysis row is the immutable input manifest and must pin all major inputs.
  select count(*)
  into v_count
  from (
    values
      ('call_id'),
      ('analysis_operation_id'),
      ('raw_transcript_id'),
      ('role_assignment_version_id'),
      ('pseudonymized_transcript_id'),
      ('privacy_package_id'),
      ('processing_quality_id'),
      ('prompt_version_id'),
      ('methodology_version_id'),
      ('knowledge_publication_id'),
      ('model_provider'),
      ('model_name'),
      ('model_config_version'),
      ('analysis_contract_version'),
      ('core_version'),
      ('validator_version'),
      ('input_manifest_sha256'),
      ('llm_response_sha256')
  ) as required(column_name)
  where not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'atp_test'
      and c.table_name = 'analysis_versions'
      and c.column_name = required.column_name
  );

  if v_count <> 0 then
    raise exception
      'DB-04 verification failed: analysis input manifest is missing % required column(s)',
      v_count;
  end if;

  -- Critical composite FKs prove that evidence can only point to exact inputs.
  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conname = 'analysis_knowledge_inputs_product_scope';

  if v_definition is null
     or regexp_replace(lower(v_definition), '\s+', ' ', 'g')
        not like '%foreign key (knowledge_publication_id, fragment_id, product_code)%'
  then
    raise exception
      'DB-04 verification failed: analysis knowledge product-scope FK missing/wrong';
  end if;

  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conname = 'evidence_conversation_refs_package_segment_fk';

  if v_definition is null
     or regexp_replace(lower(v_definition), '\s+', ' ', 'g')
        not like '%foreign key (privacy_package_id, pseudonymized_segment_id)%'
  then
    raise exception
      'DB-04 verification failed: conversation evidence package-segment FK missing/wrong';
  end if;

  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conname = 'evidence_knowledge_refs_analysis_input_fk';

  if v_definition is null
     or regexp_replace(lower(v_definition), '\s+', ' ', 'g')
        not like '%foreign key (analysis_id, fragment_id)%'
  then
    raise exception
      'DB-04 verification failed: knowledge evidence analysis-input FK missing/wrong';
  end if;

  select pg_get_constraintdef(con.oid)
  into v_definition
  from pg_constraint con
  where con.conname = 'evidence_absence_checks_analysis_package_fk';

  if v_definition is null
     or regexp_replace(lower(v_definition), '\s+', ' ', 'g')
        not like '%foreign key (analysis_id, privacy_package_id)%'
  then
    raise exception
      'DB-04 verification failed: absence evidence exact privacy-package FK missing/wrong';
  end if;

  -- No generic free-form evidence target/reference column is allowed.
  select count(*)
  into v_count
  from information_schema.columns
  where table_schema = 'atp_test'
    and table_name in (
      'analysis_claims',
      'evidence_sets',
      'evidence_conversation_refs',
      'evidence_knowledge_refs',
      'evidence_absence_checks'
    )
    and column_name in (
      'target_ref',
      'source_ref',
      'segment_ref',
      'knowledge_ref'
    );

  if v_count <> 0 then
    raise exception
      'DB-04 verification failed: found % forbidden free-form evidence reference column(s)',
      v_count;
  end if;

  -- One current analysis per call/family is a physical invariant.
  select pg_get_expr(i.indpred, i.indrelid)
  into v_definition
  from pg_index i
  join pg_class idx on idx.oid = i.indexrelid
  join pg_class tbl on tbl.oid = i.indrelid
  join pg_namespace n on n.oid = tbl.relnamespace
  where n.nspname = 'atp_test'
    and idx.relname = 'uq_analysis_versions_one_current'
    and i.indisunique;

  if v_definition is null or v_definition not ilike '%current%' then
    raise exception
      'DB-04 verification failed: unique current-analysis partial index missing/wrong';
  end if;

  -- The update gate must actually execute the structural evidence validator.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname = 'guard_analysis_version_update';

  if v_definition is null
     or v_definition not ilike '%validate_analysis_evidence_gate%'
     or v_definition not ilike '%analysis must become validated before current%'
  then
    raise exception
      'DB-04 verification failed: validated/current evidence gate is not wired into analysis transition';
  end if;

  -- Regression: final state must never be inserted directly.
  begin
    insert into atp_test.analysis_versions (
      call_id,
      version_no,
      analysis_operation_id,
      raw_transcript_id,
      role_assignment_version_id,
      pseudonymized_transcript_id,
      privacy_package_id,
      processing_quality_id,
      prompt_version_id,
      methodology_version_id,
      knowledge_publication_id,
      model_provider,
      model_name,
      model_config_version,
      model_config,
      analysis_contract_version,
      core_version,
      validator_version,
      input_manifest_sha256,
      llm_response_sha256,
      reliability,
      core_validation_status,
      evidence_gate_status,
      analysis_state,
      validated_at,
      current_at
    )
    values (
      gen_random_uuid(),
      1,
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      'verify',
      'verify',
      'verify-v1',
      '{}'::jsonb,
      'contract-v1',
      'core-v1',
      'validator-v1',
      'verify-manifest',
      'verify-response',
      'reliable',
      'passed',
      'passed',
      'current',
      now(),
      now()
    );

    raise exception
      'DB-04 verification failed: direct current analysis INSERT was accepted';
  exception
    when raise_exception then
      if sqlerrm like 'DB-04 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Analysis must be inserted as candidate%' then
        raise;
      end if;
  end;

  -- Regression: even a candidate cannot pre-declare a passed evidence gate.
  begin
    insert into atp_test.analysis_versions (
      call_id,
      version_no,
      analysis_operation_id,
      raw_transcript_id,
      role_assignment_version_id,
      pseudonymized_transcript_id,
      privacy_package_id,
      processing_quality_id,
      prompt_version_id,
      methodology_version_id,
      knowledge_publication_id,
      model_provider,
      model_name,
      model_config_version,
      model_config,
      analysis_contract_version,
      core_version,
      validator_version,
      input_manifest_sha256,
      llm_response_sha256,
      reliability,
      core_validation_status,
      evidence_gate_status,
      analysis_state
    )
    values (
      gen_random_uuid(),
      1,
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      gen_random_uuid(),
      'verify',
      'verify',
      'verify-v1',
      '{}'::jsonb,
      'contract-v1',
      'core-v1',
      'validator-v1',
      'verify-manifest',
      'verify-response',
      'reliable',
      'passed',
      'passed',
      'candidate'
    );

    raise exception
      'DB-04 verification failed: candidate INSERT pre-declared passed evidence gate';
  exception
    when raise_exception then
      if sqlerrm like 'DB-04 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'New candidate analysis cannot pre-declare evidence gate%' then
        raise;
      end if;
  end;

  raise notice 'DB-04 verification passed';
end
$verify$;

rollback;
