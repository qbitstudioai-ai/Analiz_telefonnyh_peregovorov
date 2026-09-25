-- DB-07 verification
-- TEST/LOCAL ONLY.
-- Run after DB-01..DB-07 migrations.
-- Verifies capability roles, grants, RLS/policies and restricted surfaces.
-- The whole verification is rolled back.

begin;

create schema atp_verify_other;
revoke all on schema atp_verify_other from public;
create table atp_verify_other.sentinel (
  sentinel_id integer primary key
);

do $verify$
declare
  v_role text;
  v_count integer;
  v_definition text;
  v_bad text;
  v_acl_public_execute boolean;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-07 verification failed: schema atp_test does not exist';
  end if;

  -- Every DB-07 role is a NOLOGIN, non-admin, non-bypass capability role.
  foreach v_role in array array[
    'atp_test_orchestrator',
    'atp_test_core',
    'atp_test_privacy',
    'atp_test_raw_transcript_reader',
    'atp_test_knowledge_reader',
    'atp_test_dashboard',
    'atp_test_admin_api',
    'atp_test_monitor'
  ]
  loop
    if not exists (
      select 1
      from pg_roles r
      where r.rolname = v_role
        and not r.rolcanlogin
        and not r.rolsuper
        and not r.rolcreatedb
        and not r.rolcreaterole
        and not r.rolinherit
        and not r.rolreplication
        and not r.rolbypassrls
    ) then
      raise exception
        'DB-07 verification failed: role % missing or has unsafe attributes',
        v_role;
    end if;

    if not has_schema_privilege(v_role, 'atp_test', 'USAGE') then
      raise exception
        'DB-07 verification failed: role % lacks allowed atp_test USAGE',
        v_role;
    end if;

    if has_schema_privilege(v_role, 'atp_test', 'CREATE') then
      raise exception
        'DB-07 verification failed: role % can CREATE in atp_test',
        v_role;
    end if;

    if has_schema_privilege(v_role, 'atp_verify_other', 'USAGE')
       or has_schema_privilege(v_role, 'atp_verify_other', 'CREATE')
       or has_table_privilege(v_role, 'atp_verify_other.sentinel', 'SELECT')
       or has_table_privilege(v_role, 'atp_verify_other.sentinel', 'INSERT')
    then
      raise exception
        'DB-07 verification failed: role % escaped into another schema',
        v_role;
    end if;
  end loop;

  -- RLS defense-in-depth is enabled on the three sensitive raw/mapping tables.
  select count(*)
  into v_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'atp_test'
    and c.relname in (
      'raw_transcripts',
      'transcript_segments',
      'pseudonym_mappings'
    )
    and c.relrowsecurity;

  if v_count <> 3 then
    raise exception
      'DB-07 verification failed: expected RLS on 3 sensitive tables, found %',
      v_count;
  end if;

  select count(*)
  into v_count
  from pg_policies p
  where p.schemaname = 'atp_test'
    and p.policyname in (
      'raw_transcripts_privacy_all',
      'raw_transcripts_reader_select',
      'transcript_segments_privacy_all',
      'transcript_segments_reader_select',
      'pseudonym_mappings_privacy_all'
    );

  if v_count <> 5 then
    raise exception
      'DB-07 verification failed: expected 5 DB-07 policies, found %',
      v_count;
  end if;

  -- Positive control: orchestrator can operate pipeline/business-delivery state.
  if not has_table_privilege('atp_test_orchestrator', 'atp_test.calls', 'SELECT')
     or not has_table_privilege('atp_test_orchestrator', 'atp_test.calls', 'INSERT')
     or not has_table_privilege('atp_test_orchestrator', 'atp_test.calls', 'UPDATE')
     or not has_table_privilege('atp_test_orchestrator', 'atp_test.outgoing_actions', 'INSERT')
     or not has_table_privilege('atp_test_orchestrator', 'atp_test.delivery_attempts', 'UPDATE')
  then
    raise exception
      'DB-07 verification failed: orchestrator positive control missing';
  end if;

  -- Negative: orchestrator cannot read raw/mapping or administer knowledge.
  if has_table_privilege('atp_test_orchestrator', 'atp_test.raw_transcripts', 'SELECT')
     or has_table_privilege('atp_test_orchestrator', 'atp_test.transcript_segments', 'SELECT')
     or has_table_privilege('atp_test_orchestrator', 'atp_test.pseudonym_mappings', 'SELECT')
     or has_table_privilege('atp_test_orchestrator', 'atp_test.knowledge_documents', 'INSERT')
     or has_table_privilege('atp_test_orchestrator', 'atp_test.knowledge_publications', 'UPDATE')
     or has_table_privilege('atp_test_orchestrator', 'atp_test.audit_events', 'UPDATE')
     or has_table_privilege('atp_test_orchestrator', 'atp_test.audit_events', 'DELETE')
  then
    raise exception
      'DB-07 verification failed: orchestrator has forbidden raw/knowledge/audit privilege';
  end if;

  -- CORE positive control.
  if not has_table_privilege('atp_test_core', 'atp_test.v_runtime_knowledge_call_analysis', 'SELECT')
     or not has_table_privilege('atp_test_core', 'atp_test.analysis_versions', 'INSERT')
     or not has_table_privilege('atp_test_core', 'atp_test.analysis_versions', 'UPDATE')
     or not has_function_privilege(
       'atp_test_core',
       'atp_test.calculate_analysis_overall_score(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'atp_test_core',
       'atp_test.validate_analysis_evidence_gate(uuid)',
       'EXECUTE'
     )
  then
    raise exception
      'DB-07 verification failed: CORE positive control missing';
  end if;

  -- CORE cannot bypass privacy or publish/edit knowledge.
  if has_table_privilege('atp_test_core', 'atp_test.raw_transcripts', 'SELECT')
     or has_table_privilege('atp_test_core', 'atp_test.transcript_segments', 'SELECT')
     or has_table_privilege('atp_test_core', 'atp_test.pseudonym_mappings', 'SELECT')
     or has_table_privilege('atp_test_core', 'atp_test.knowledge_documents', 'UPDATE')
     or has_table_privilege('atp_test_core', 'atp_test.knowledge_publications', 'UPDATE')
  then
    raise exception
      'DB-07 verification failed: CORE has forbidden raw/mapping/knowledge-write privilege';
  end if;

  -- Privacy positive control and separation from dashboard/admin knowledge.
  if not has_table_privilege('atp_test_privacy', 'atp_test.raw_transcripts', 'SELECT')
     or not has_table_privilege('atp_test_privacy', 'atp_test.raw_transcripts', 'INSERT')
     or not has_table_privilege('atp_test_privacy', 'atp_test.raw_transcripts', 'UPDATE')
     or not has_table_privilege('atp_test_privacy', 'atp_test.pseudonym_mappings', 'SELECT')
     or not has_table_privilege('atp_test_privacy', 'atp_test.pseudonym_mappings', 'INSERT')
  then
    raise exception
      'DB-07 verification failed: privacy positive control missing';
  end if;

  if has_table_privilege('atp_test_privacy', 'atp_test.v_dashboard_zvonki', 'SELECT')
     or has_table_privilege('atp_test_privacy', 'atp_test.knowledge_publications', 'UPDATE')
  then
    raise exception
      'DB-07 verification failed: privacy role has unrelated dashboard/knowledge-admin access';
  end if;

  -- Optional raw reader sees raw text but never mapping.
  if not has_table_privilege(
       'atp_test_raw_transcript_reader',
       'atp_test.raw_transcripts',
       'SELECT'
     )
     or not has_table_privilege(
       'atp_test_raw_transcript_reader',
       'atp_test.transcript_segments',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: raw-reader positive control missing';
  end if;

  if has_table_privilege(
       'atp_test_raw_transcript_reader',
       'atp_test.pseudonym_mappings',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_raw_transcript_reader',
       'atp_test.raw_transcripts',
       'UPDATE'
     )
  then
    raise exception
      'DB-07 verification failed: raw-reader can access mapping or mutate raw data';
  end if;

  -- Knowledge reader: one published call_analysis surface only.
  if not has_table_privilege(
       'atp_test_knowledge_reader',
       'atp_test.v_runtime_knowledge_call_analysis',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: knowledge-reader positive control missing';
  end if;

  if has_table_privilege(
       'atp_test_knowledge_reader',
       'atp_test.v_runtime_knowledge_fragments',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_reader',
       'atp_test.knowledge_documents',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_reader',
       'atp_test.knowledge_document_versions',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_reader',
       'atp_test.knowledge_fragments',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_reader',
       'atp_test.knowledge_embeddings',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_reader',
       'atp_test.knowledge_publications',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_reader',
       'atp_test.knowledge_publications',
       'UPDATE'
     )
  then
    raise exception
      'DB-07 verification failed: knowledge reader can see raw/draft knowledge or write';
  end if;

  select pg_get_viewdef(
    'atp_test.v_runtime_knowledge_call_analysis'::regclass,
    true
  )
  into v_definition;

  if v_definition not ilike '%call_analysis%'
     or v_definition not ilike '%v_runtime_knowledge_fragments%'
  then
    raise exception
      'DB-07 verification failed: product-scoped knowledge view definition is wrong';
  end if;

  -- Active configuration surfaces cannot reveal drafts/unvalidated rows.
  select pg_get_viewdef('atp_test.v_runtime_prompt_active'::regclass, true)
  into v_definition;
  if v_definition not ilike '%config_state = ''active''%'
     or v_definition not ilike '%validation_status = ''passed''%'
  then
    raise exception
      'DB-07 verification failed: prompt runtime surface is not active+passed only';
  end if;

  select pg_get_viewdef('atp_test.v_runtime_filter_rules_active'::regclass, true)
  into v_definition;
  if v_definition not ilike '%config_state = ''active''%'
     or v_definition not ilike '%validation_status = ''passed''%'
  then
    raise exception
      'DB-07 verification failed: filter runtime surface is not active+passed only';
  end if;

  -- Dashboard positive controls.
  if not has_table_privilege('atp_test_dashboard', 'atp_test.v_dashboard_zvonki', 'SELECT')
     or not has_table_privilege(
       'atp_test_dashboard',
       'atp_test.v_dashboard_knowledge_evidence',
       'SELECT'
     )
     or not has_function_privilege(
       'atp_test_dashboard',
       'atp_test.dashboard_overview(timestamptz,timestamptz,jsonb,timestamptz,interval,text[],text[])',
       'EXECUTE'
     )
  then
    raise exception
      'DB-07 verification failed: dashboard positive control missing';
  end if;

  -- Dashboard cannot read raw/mapping or mutate primary business/history rows.
  if has_table_privilege('atp_test_dashboard', 'atp_test.raw_transcripts', 'SELECT')
     or has_table_privilege('atp_test_dashboard', 'atp_test.transcript_segments', 'SELECT')
     or has_table_privilege('atp_test_dashboard', 'atp_test.pseudonym_mappings', 'SELECT')
     or has_table_privilege('atp_test_dashboard', 'atp_test.calls', 'INSERT')
     or has_table_privilege('atp_test_dashboard', 'atp_test.analysis_versions', 'UPDATE')
     or has_table_privilege('atp_test_dashboard', 'atp_test.business_confirmations', 'UPDATE')
     or has_table_privilege('atp_test_dashboard', 'atp_test.audit_events', 'INSERT')
  then
    raise exception
      'DB-07 verification failed: dashboard has forbidden raw/direct-write privilege';
  end if;

  -- Admin API uses controlled functions, not direct business-table write.
  if not has_table_privilege(
       'atp_test_admin_api',
       'atp_test.v_admin_audit_safe',
       'SELECT'
     )
     or not has_function_privilege(
       'atp_test_admin_api',
       'atp_test.admin_submit_analysis_dispute(uuid,uuid,uuid,uuid,text,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'atp_test_admin_api',
       'atp_test.admin_propose_correction(uuid,atp_test.correction_target_type,uuid,text,text,jsonb,jsonb,text,text,uuid)',
       'EXECUTE'
     )
  then
    raise exception
      'DB-07 verification failed: admin API positive control missing';
  end if;

  if has_table_privilege('atp_test_admin_api', 'atp_test.analysis_disputes', 'INSERT')
     or has_table_privilege('atp_test_admin_api', 'atp_test.corrections', 'INSERT')
     or has_table_privilege('atp_test_admin_api', 'atp_test.audit_events', 'INSERT')
     or has_table_privilege('atp_test_admin_api', 'atp_test.raw_transcripts', 'SELECT')
     or has_table_privilege('atp_test_admin_api', 'atp_test.pseudonym_mappings', 'SELECT')
  then
    raise exception
      'DB-07 verification failed: admin API bypasses controlled functions/privacy';
  end if;

  -- Security definer functions must use a fixed search_path.
  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname in (
      'admin_submit_analysis_dispute',
      'admin_propose_correction'
    )
    and p.prosecdef
    and exists (
      select 1
      from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
      where cfg = 'search_path=pg_catalog, atp_test'
    );

  if v_count <> 2 then
    raise exception
      'DB-07 verification failed: SECURITY DEFINER functions lack fixed search_path';
  end if;

  -- PUBLIC must not execute either privileged admin function.
  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where n.nspname = 'atp_test'
      and p.proname = 'admin_submit_analysis_dispute'
      and a.grantee = 0
      and a.privilege_type = 'EXECUTE'
  )
  into v_acl_public_execute;

  if v_acl_public_execute then
    raise exception
      'DB-07 verification failed: PUBLIC can execute admin_submit_analysis_dispute';
  end if;

  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where n.nspname = 'atp_test'
      and p.proname = 'admin_propose_correction'
      and a.grantee = 0
      and a.privilege_type = 'EXECUTE'
  )
  into v_acl_public_execute;

  if v_acl_public_execute then
    raise exception
      'DB-07 verification failed: PUBLIC can execute admin_propose_correction';
  end if;

  -- Monitor can see minimized health, not conversation/business content.
  if not has_table_privilege('atp_test_monitor', 'atp_test.v_monitor_operations', 'SELECT')
     or not has_table_privilege('atp_test_monitor', 'atp_test.v_monitor_audio_cleanup', 'SELECT')
     or not has_table_privilege('atp_test_monitor', 'atp_test.v_monitor_delivery', 'SELECT')
  then
    raise exception
      'DB-07 verification failed: monitor positive control missing';
  end if;

  if has_table_privilege('atp_test_monitor', 'atp_test.raw_transcripts', 'SELECT')
     or has_table_privilege('atp_test_monitor', 'atp_test.pseudonymized_transcripts', 'SELECT')
     or has_table_privilege('atp_test_monitor', 'atp_test.knowledge_documents', 'SELECT')
     or has_table_privilege('atp_test_monitor', 'atp_test.v_dashboard_zvonki', 'SELECT')
     or has_table_privilege('atp_test_monitor', 'atp_test.outgoing_actions', 'SELECT')
  then
    raise exception
      'DB-07 verification failed: monitor has conversation/business content access';
  end if;

  -- No ordinary capability role can DELETE immutable/business history.
  select string_agg(v_role, ', ')
  into v_bad
  from unnest(array[
    'atp_test_orchestrator',
    'atp_test_core',
    'atp_test_privacy',
    'atp_test_raw_transcript_reader',
    'atp_test_knowledge_reader',
    'atp_test_dashboard',
    'atp_test_admin_api',
    'atp_test_monitor'
  ]) as role_list(v_role)
  where has_table_privilege(v_role, 'atp_test.analysis_versions', 'DELETE')
     or has_table_privilege(v_role, 'atp_test.business_confirmations', 'DELETE')
     or has_table_privilege(v_role, 'atp_test.delivery_attempts', 'DELETE')
     or has_table_privilege(v_role, 'atp_test.audit_events', 'DELETE');

  if v_bad is not null then
    raise exception
      'DB-07 verification failed: role(s) have forbidden DELETE: %',
      v_bad;
  end if;

  -- If a production-like schema happens to exist, test roles must not see it.
  if exists (
    select 1 from pg_namespace where nspname = 'atp_prod'
  ) then
    select string_agg(v_role, ', ')
    into v_bad
    from unnest(array[
      'atp_test_orchestrator',
      'atp_test_core',
      'atp_test_privacy',
      'atp_test_raw_transcript_reader',
      'atp_test_knowledge_reader',
      'atp_test_dashboard',
      'atp_test_admin_api',
      'atp_test_monitor'
    ]) as role_list(v_role)
    where has_schema_privilege(v_role, 'atp_prod', 'USAGE')
       or has_schema_privilege(v_role, 'atp_prod', 'CREATE');

    if v_bad is not null then
      raise exception
        'DB-07 verification failed: test role(s) have atp_prod access: %',
        v_bad;
    end if;
  end if;

  raise notice 'DB-07 verification passed';
end
$verify$;

rollback;
