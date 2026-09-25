-- DB-03 verification
-- TEST/LOCAL ONLY.
-- Run after migrations 001, 002 and 003.
-- All synthetic verification data is rolled back.

begin;

do $verify$
declare
  v_table_count integer;
  v_prompt_id uuid;
  v_methodology_id uuid;
  v_filter_ref text;
  v_call_id uuid;
  v_filter_operation_id uuid;
  v_document_id uuid;
  v_document_version_id uuid;
  v_fragment_id uuid;
  v_embedding_id uuid;
  v_publication_id uuid;
  v_bad_publication_id uuid;
  v_bad_embedding_id uuid;
  v_view_rows integer;
  v_count integer;
begin
  select count(*)
  into v_table_count
  from pg_tables
  where schemaname = 'atp_test'
    and tablename in (
      'prompt_versions',
      'methodology_versions',
      'methodology_criteria',
      'methodology_stages',
      'filter_rule_versions',
      'knowledge_documents',
      'knowledge_document_versions',
      'knowledge_fragments',
      'knowledge_embeddings',
      'knowledge_publications',
      'knowledge_publication_documents',
      'knowledge_publication_fragments',
      'knowledge_publication_fragment_products'
    );

  if v_table_count <> 13 then
    raise exception
      'DB-03 verification failed: expected 13 DB-03 tables, found %',
      v_table_count;
  end if;

  if not exists (
    select 1
    from pg_views
    where schemaname = 'atp_test'
      and viewname = 'v_runtime_knowledge_fragments'
  ) then
    raise exception
      'DB-03 verification failed: runtime knowledge source view is missing';
  end if;

  -- Business config versions must start as draft.
  begin
    insert into atp_test.prompt_versions (
      family_ref,
      version_no,
      prompt_text,
      content_sha256,
      config_state,
      validation_status,
      activated_at,
      actor_ref
    )
    values (
      'verify_prompt_family_direct_active',
      1,
      'invalid direct active prompt',
      'verify-prompt-direct-active-hash',
      'active',
      'passed',
      now(),
      'verify_actor'
    );

    raise exception
      'DB-03 verification failed: prompt inserted directly as active';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  insert into atp_test.prompt_versions (
    family_ref,
    version_no,
    prompt_text,
    content_sha256,
    actor_ref
  )
  values (
    'verify_prompt_family',
    1,
    'Оцени разговор по проверяемым критериям.',
    'verify-prompt-hash-v1',
    'verify_actor'
  )
  returning prompt_version_id into v_prompt_id;

  update atp_test.prompt_versions
  set
    validation_status = 'passed',
    config_state = 'active',
    activated_at = now()
  where prompt_version_id = v_prompt_id;

  begin
    update atp_test.prompt_versions
    set prompt_text = 'Попытка переписать active prompt'
    where prompt_version_id = v_prompt_id;

    raise exception
      'DB-03 verification failed: active prompt semantic content was mutable';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  begin
    update atp_test.prompt_versions
    set config_state = 'draft'
    where prompt_version_id = v_prompt_id;

    raise exception
      'DB-03 verification failed: active prompt returned to draft';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  -- Methodology children are editable in draft and frozen after leaving draft.
  insert into atp_test.methodology_versions (
    family_ref,
    version_no,
    title,
    scoring_config,
    result_rules,
    content_sha256,
    actor_ref
  )
  values (
    'verify_methodology_family',
    1,
    'Verification methodology',
    '{"scale":"1-10"}'::jsonb,
    '{"result":"separate_from_crm"}'::jsonb,
    'verify-methodology-hash-v1',
    'verify_actor'
  )
  returning methodology_version_id into v_methodology_id;

  insert into atp_test.methodology_criteria (
    methodology_version_id,
    criterion_code,
    display_name,
    sort_order,
    weight,
    scale_min,
    scale_max,
    applicability_rule,
    required
  )
  values (
    v_methodology_id,
    'greeting',
    'Приветствие',
    0,
    1,
    1,
    10,
    '{}'::jsonb,
    true
  );

  insert into atp_test.methodology_stages (
    methodology_version_id,
    stage_code,
    display_name,
    sort_order,
    applicability_rule,
    required
  )
  values (
    v_methodology_id,
    'opening',
    'Начало разговора',
    0,
    '{}'::jsonb,
    true
  );

  update atp_test.methodology_versions
  set
    validation_status = 'passed',
    config_state = 'ready'
  where methodology_version_id = v_methodology_id;

  begin
    update atp_test.methodology_criteria
    set weight = 2
    where methodology_version_id = v_methodology_id
      and criterion_code = 'greeting';

    raise exception
      'DB-03 verification failed: methodology child changed after parent left draft';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  update atp_test.methodology_versions
  set
    config_state = 'active',
    activated_at = now()
  where methodology_version_id = v_methodology_id;

  -- Filter rule version is now a real FK target for filter decisions.
  insert into atp_test.filter_rule_versions (
    family_ref,
    version_no,
    rules_json,
    content_sha256,
    actor_ref
  )
  values (
    'verify_filter_family',
    1,
    '{"client_calls_only":true}'::jsonb,
    'verify-filter-hash-v1',
    'verify_actor'
  )
  returning filter_rule_version_ref into v_filter_ref;

  update atp_test.filter_rule_versions
  set
    validation_status = 'passed',
    config_state = 'active',
    activated_at = now()
  where filter_rule_version_ref = v_filter_ref;

  insert into atp_test.calls (
    source_adapter_code,
    connection_ref,
    call_identity_key,
    direction,
    answer_status,
    classification,
    processing_state
  )
  values (
    'verify_db03_source',
    'verify_db03_connection',
    'verify-db03-call-001',
    'inbound',
    'answered',
    'client',
    'registered'
  )
  returning call_id into v_call_id;

  insert into atp_test.operations (
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
    'filter_call',
    'verify-db03-filter-op',
    'contract-v1',
    'verify-db03-filter-correlation',
    '{}'::jsonb,
    'accepted',
    'succeeded',
    'verify-db03-filter-result',
    now()
  )
  returning operation_id into v_filter_operation_id;

  insert into atp_test.filter_decisions (
    call_id,
    outcome,
    filter_rules_version_ref,
    input_facts,
    operation_id
  )
  values (
    v_call_id,
    'accepted',
    v_filter_ref,
    '{"verification":true}'::jsonb,
    v_filter_operation_id
  );

  begin
    insert into atp_test.filter_decisions (
      call_id,
      outcome,
      filter_rules_version_ref,
      input_facts,
      operation_id
    )
    values (
      v_call_id,
      'accepted',
      'missing-filter-version',
      '{}'::jsonb,
      v_filter_operation_id
    );

    raise exception
      'DB-03 verification failed: filter decision accepted unknown filter version';
  exception
    when foreign_key_violation then
      null;
  end;

  -- One canonical document, one exact document version and one fragment.
  insert into atp_test.knowledge_documents (
    stable_code,
    title,
    source_type,
    source_ref
  )
  values (
    'verify_product_terms',
    'Условия продукта — проверка',
    'internal_document',
    'verify-source-ref'
  )
  returning document_id into v_document_id;

  insert into atp_test.knowledge_document_versions (
    document_id,
    version_no,
    source_version_ref,
    content,
    content_sha256,
    metadata,
    external_embedding_allowed,
    editorial_state,
    validation_status,
    version_state,
    actor_ref,
    change_reason
  )
  values (
    v_document_id,
    1,
    'verify-doc-source-v1',
    'Гарантия тестового продукта — 12 месяцев.',
    'verify-document-hash-v1',
    '{"verification":true}'::jsonb,
    false,
    'draft',
    'pending',
    'candidate',
    'verify_editor',
    'initial verification version'
  )
  returning document_version_id into v_document_version_id;

  update atp_test.knowledge_document_versions
  set
    validation_status = 'passed',
    editorial_state = 'ready',
    version_state = 'current'
  where document_version_id = v_document_version_id;

  insert into atp_test.knowledge_fragments (
    document_id,
    document_version_id,
    fragment_family_key,
    fragment_version_no,
    fragment_order,
    chunking_config_version,
    normalization_config_version,
    fragment_text,
    content_sha256,
    source_locator,
    validation_status,
    version_state
  )
  values (
    v_document_id,
    v_document_version_id,
    'warranty',
    1,
    0,
    'verify-chunking-v1',
    'verify-normalization-v1',
    'Гарантия тестового продукта — 12 месяцев.',
    'verify-fragment-hash-v1',
    '{"section":"warranty"}'::jsonb,
    'passed',
    'current'
  )
  returning fragment_id into v_fragment_id;

  insert into atp_test.knowledge_embeddings (
    fragment_id,
    version_no,
    provider,
    model_name,
    model_version,
    config_version,
    config,
    dimensions,
    vector_data,
    input_sha256,
    embedding_state,
    validation_status,
    version_state,
    external_api,
    actor_ref,
    calculated_at
  )
  values (
    v_fragment_id,
    1,
    'verify_local',
    'verify_embedding',
    'test-build',
    'verify-embedding-config-v1',
    '{"verification":true}'::jsonb,
    3,
    array[0.1, 0.2, 0.3]::real[],
    'verify-fragment-hash-v1',
    'ready',
    'passed',
    'current',
    false,
    'verify_embedding_worker',
    now()
  )
  returning embedding_id into v_embedding_id;

  -- Draft publication does not appear in runtime.
  insert into atp_test.knowledge_publications (
    family_ref,
    version_no,
    publication_state,
    validation_status,
    manifest_sha256,
    actor_ref,
    validation_ref,
    change_reason
  )
  values (
    'verify_knowledge_family',
    1,
    'draft',
    'pending',
    'verify-publication-manifest-v1',
    'verify_publisher',
    'verify-validation-v1',
    'initial verification publication'
  )
  returning publication_id into v_publication_id;

  insert into atp_test.knowledge_publication_documents (
    publication_id,
    document_version_id,
    document_id,
    document_order
  )
  values (
    v_publication_id,
    v_document_version_id,
    v_document_id,
    0
  );

  insert into atp_test.knowledge_publication_fragments (
    publication_id,
    fragment_id,
    document_version_id,
    document_id,
    embedding_id,
    requires_embedding,
    fragment_order
  )
  values (
    v_publication_id,
    v_fragment_id,
    v_document_version_id,
    v_document_id,
    v_embedding_id,
    true,
    0
  );

  insert into atp_test.knowledge_publication_fragment_products (
    publication_id,
    fragment_id,
    product_code
  )
  values
    (v_publication_id, v_fragment_id, 'call_analysis'),
    (v_publication_id, v_fragment_id, 'initial_contact_bot');

  select count(*)
  into v_view_rows
  from atp_test.v_runtime_knowledge_fragments
  where publication_id = v_publication_id;

  if v_view_rows <> 0 then
    raise exception
      'DB-03 verification failed: draft publication leaked into runtime view';
  end if;

  update atp_test.knowledge_publications
  set
    validation_status = 'passed',
    publication_state = 'published',
    published_at = now(),
    is_current = true
  where publication_id = v_publication_id;

  select count(*)
  into v_view_rows
  from atp_test.v_runtime_knowledge_fragments
  where publication_id = v_publication_id
    and fragment_id = v_fragment_id;

  if v_view_rows <> 2 then
    raise exception
      'DB-03 verification failed: expected one exact fragment for two product scopes, runtime rows=%',
      v_view_rows;
  end if;

  if not exists (
    select 1
    from atp_test.v_runtime_knowledge_fragments
    where publication_id = v_publication_id
      and product_code = 'call_analysis'
      and document_version_id = v_document_version_id
      and fragment_id = v_fragment_id
      and embedding_id = v_embedding_id
  ) then
    raise exception
      'DB-03 verification failed: exact publication/document/fragment/embedding provenance missing';
  end if;

  -- Published membership is immutable.
  begin
    insert into atp_test.knowledge_publication_fragment_products (
      publication_id,
      fragment_id,
      product_code
    )
    values (
      v_publication_id,
      v_fragment_id,
      'unauthorized_late_product'
    );

    raise exception
      'DB-03 verification failed: published membership was mutable';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  -- Published document semantics are immutable.
  begin
    update atp_test.knowledge_document_versions
    set content = 'Попытка изменить опубликованный документ'
    where document_version_id = v_document_version_id;

    raise exception
      'DB-03 verification failed: published document content was mutable';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  -- Publication itself cannot be reopened for editing.
  begin
    update atp_test.knowledge_publications
    set publication_state = 'ready'
    where publication_id = v_publication_id;

    raise exception
      'DB-03 verification failed: published publication returned to ready';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  -- A fragment without product scope cannot be published.
  insert into atp_test.knowledge_publications (
    family_ref,
    version_no,
    publication_state,
    validation_status,
    manifest_sha256,
    actor_ref
  )
  values (
    'verify_missing_scope_family',
    1,
    'draft',
    'pending',
    'verify-missing-scope-manifest',
    'verify_publisher'
  )
  returning publication_id into v_bad_publication_id;

  insert into atp_test.knowledge_publication_documents (
    publication_id,
    document_version_id,
    document_id,
    document_order
  )
  values (
    v_bad_publication_id,
    v_document_version_id,
    v_document_id,
    0
  );

  insert into atp_test.knowledge_publication_fragments (
    publication_id,
    fragment_id,
    document_version_id,
    document_id,
    embedding_id,
    requires_embedding,
    fragment_order
  )
  values (
    v_bad_publication_id,
    v_fragment_id,
    v_document_version_id,
    v_document_id,
    v_embedding_id,
    true,
    0
  );

  begin
    update atp_test.knowledge_publications
    set
      validation_status = 'passed',
      publication_state = 'published',
      published_at = now(),
      is_current = true
    where publication_id = v_bad_publication_id;

    raise exception
      'DB-03 verification failed: publication without product scope was activated';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  -- External embedding cannot be published when the exact document version
  -- does not allow external embedding.
  insert into atp_test.knowledge_embeddings (
    fragment_id,
    version_no,
    provider,
    model_name,
    model_version,
    config_version,
    config,
    dimensions,
    vector_data,
    input_sha256,
    embedding_state,
    validation_status,
    version_state,
    external_api,
    actor_ref,
    calculated_at
  )
  values (
    v_fragment_id,
    1,
    'verify_external_provider',
    'verify_external_embedding',
    'test-build',
    'verify-external-config-v1',
    '{}'::jsonb,
    3,
    array[0.2, 0.3, 0.4]::real[],
    'verify-fragment-hash-v1',
    'ready',
    'passed',
    'candidate',
    true,
    'verify_embedding_worker',
    now()
  )
  returning embedding_id into v_bad_embedding_id;

  insert into atp_test.knowledge_publications (
    family_ref,
    version_no,
    publication_state,
    validation_status,
    manifest_sha256,
    actor_ref
  )
  values (
    'verify_external_policy_family',
    1,
    'draft',
    'pending',
    'verify-external-policy-manifest',
    'verify_publisher'
  )
  returning publication_id into v_bad_publication_id;

  insert into atp_test.knowledge_publication_documents (
    publication_id,
    document_version_id,
    document_id,
    document_order
  )
  values (
    v_bad_publication_id,
    v_document_version_id,
    v_document_id,
    0
  );

  insert into atp_test.knowledge_publication_fragments (
    publication_id,
    fragment_id,
    document_version_id,
    document_id,
    embedding_id,
    requires_embedding,
    fragment_order
  )
  values (
    v_bad_publication_id,
    v_fragment_id,
    v_document_version_id,
    v_document_id,
    v_bad_embedding_id,
    true,
    0
  );

  insert into atp_test.knowledge_publication_fragment_products (
    publication_id,
    fragment_id,
    product_code
  )
  values (
    v_bad_publication_id,
    v_fragment_id,
    'call_analysis'
  );

  begin
    update atp_test.knowledge_publications
    set
      validation_status = 'passed',
      publication_state = 'published',
      published_at = now(),
      is_current = true
    where publication_id = v_bad_publication_id;

    raise exception
      'DB-03 verification failed: forbidden external embedding was published';
  exception
    when raise_exception then
      if sqlerrm like 'DB-03 verification failed:%' then
        raise;
      end if;
  end;

  -- Exact embedding input provenance must match exact fragment content hash.
  update atp_test.knowledge_document_versions
  set external_embedding_allowed = true,
      embedding_policy_ref = 'verify-policy-ref'
  where document_version_id = v_document_version_id;
  -- The update above must be rejected because the published document is immutable.
  -- If control reaches here, immutability is broken.
  raise exception
    'DB-03 verification failed: published document embedding policy was mutable';
exception
  when raise_exception then
    if sqlerrm = 'Knowledge document version is semantically immutable; create a new version' then
      null;
    elsif sqlerrm like 'DB-03 verification failed:%' then
      raise;
    else
      raise;
    end if;
end
$verify$;

rollback;
