-- DB-07 verification
-- TEST/LOCAL ONLY.
-- Run after DB-01..DB-07 migrations.
-- Verifies role attributes, positive/negative privilege matrix and
-- cross-schema denial. The whole verification is rolled back.

begin;

-- Probe contours exist only inside this verification transaction.
create schema atp_test_isolation_probe;
create table atp_test_isolation_probe.private_probe (
  probe_id integer primary key,
  probe_value text not null
);
insert into atp_test_isolation_probe.private_probe values (1, 'other-test-contour');

create schema atp_prod_probe;
create table atp_prod_probe.private_probe (
  probe_id integer primary key,
  probe_value text not null
);
insert into atp_prod_probe.private_probe values (1, 'production-probe');

do $verify$
declare
  v_missing text;
  v_bad text;
  v_count integer;
  v_public_exec_count integer;
  v_public_table_count integer;
  v_role text;
  v_roles text[] := array[
    'atp_test_orchestrator',
    'atp_test_privacy',
    'atp_test_core',
    'atp_test_knowledge_call_analysis',
    'atp_test_knowledge_admin',
    'atp_test_dashboard',
    'atp_test_correction_operator',
    'atp_test_monitoring'
  ];
begin
  select string_agg(required_role, ', ' order by required_role)
  into v_missing
  from unnest(v_roles) required_role
  where not exists (
    select 1 from pg_roles r where r.rolname = required_role
  );

  if v_missing is not null then
    raise exception
      'DB-07 verification failed: missing capability role(s): %',
      v_missing;
  end if;

  -- Every capability role is deliberately non-login/non-admin.
  select string_agg(r.rolname, ', ' order by r.rolname)
  into v_bad
  from pg_roles r
  where r.rolname = any(v_roles)
    and (
      r.rolcanlogin
      or r.rolsuper
      or r.rolcreatedb
      or r.rolcreaterole
      or r.rolreplication
      or r.rolbypassrls
    );

  if v_bad is not null then
    raise exception
      'DB-07 verification failed: broad/login privilege on role(s): %',
      v_bad;
  end if;

  -- No real login identity has been attached yet. DB-08 will do that outside
  -- GitHub only after credentials are created for the concrete test contour.
  select count(*)
  into v_count
  from pg_auth_members m
  join pg_roles r on r.oid = m.roleid
  where r.rolname = any(v_roles);

  if v_count <> 0 then
    raise exception
      'DB-07 verification failed: capability roles unexpectedly have % member(s)',
      v_count;
  end if;

  -- All roles use only their own contour schema and none can CREATE in it.
  foreach v_role in array v_roles loop
    if not has_schema_privilege(v_role, 'atp_test', 'USAGE') then
      raise exception
        'DB-07 verification failed: % lacks positive-control USAGE on atp_test',
        v_role;
    end if;

    if has_schema_privilege(v_role, 'atp_test', 'CREATE') then
      raise exception
        'DB-07 verification failed: % can CREATE in atp_test',
        v_role;
    end if;

    if has_schema_privilege(v_role, 'atp_test_isolation_probe', 'USAGE')
       or has_table_privilege(
         v_role,
         'atp_test_isolation_probe.private_probe',
         'SELECT'
       )
    then
      raise exception
        'DB-07 verification failed: % can access another test contour probe',
        v_role;
    end if;

    if has_schema_privilege(v_role, 'atp_prod_probe', 'USAGE')
       or has_table_privilege(
         v_role,
         'atp_prod_probe.private_probe',
         'SELECT'
       )
    then
      raise exception
        'DB-07 verification failed: % can access production probe',
        v_role;
    end if;
  end loop;

  -- PUBLIC must not be a hidden access path to atp_test tables/views.
  select count(*)
  into v_public_table_count
  from information_schema.table_privileges tp
  where tp.table_schema = 'atp_test'
    and tp.grantee = 'PUBLIC';

  if v_public_table_count <> 0 then
    raise exception
      'DB-07 verification failed: PUBLIC still has % table/view privilege(s)',
      v_public_table_count;
  end if;

  -- PostgreSQL gives PUBLIC EXECUTE on functions by default; DB-07 must revoke
  -- it from every atp_test function, including older DB-01..DB-06 helpers.
  select count(*)
  into v_public_exec_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(
    coalesce(p.proacl, acldefault('f', p.proowner))
  ) acl
  where n.nspname = 'atp_test'
    and acl.grantee = 0
    and acl.privilege_type = 'EXECUTE';

  if v_public_exec_count <> 0 then
    raise exception
      'DB-07 verification failed: PUBLIC EXECUTE remains on % atp_test function(s)',
      v_public_exec_count;
  end if;

  -- Orchestrator positive controls.
  if not has_table_privilege(
    'atp_test_orchestrator', 'atp_test.calls', 'INSERT'
  )
     or not has_table_privilege(
       'atp_test_orchestrator', 'atp_test.operations', 'UPDATE'
     )
     or not has_table_privilege(
       'atp_test_orchestrator', 'atp_test.outgoing_actions', 'INSERT'
     )
  then
    raise exception
      'DB-07 verification failed: orchestrator allowed-write controls are incomplete';
  end if;

  if has_table_privilege(
       'atp_test_orchestrator', 'atp_test.raw_transcripts', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_orchestrator', 'atp_test.pseudonym_mappings', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_orchestrator', 'atp_test.knowledge_documents', 'UPDATE'
     )
  then
    raise exception
      'DB-07 verification failed: orchestrator reached raw/mapping/knowledge-admin data';
  end if;

  -- Privacy is the explicit positive control for raw/mapping access.
  if not has_table_privilege(
       'atp_test_privacy', 'atp_test.raw_transcripts', 'SELECT'
     )
     or not has_table_privilege(
       'atp_test_privacy', 'atp_test.raw_transcripts', 'INSERT'
     )
     or not has_table_privilege(
       'atp_test_privacy', 'atp_test.pseudonym_mappings', 'SELECT'
     )
     or not has_table_privilege(
       'atp_test_privacy', 'atp_test.pseudonym_mappings', 'UPDATE'
     )
  then
    raise exception
      'DB-07 verification failed: privacy raw/mapping positive controls missing';
  end if;

  if has_table_privilege(
       'atp_test_privacy', 'atp_test.knowledge_documents', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_privacy', 'atp_test.v_dashboard_zvonki', 'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: privacy role has unrelated knowledge/dashboard access';
  end if;

  -- CORE can read safe pseudonymized data and write analysis, but not raw/mapping.
  if not has_table_privilege(
       'atp_test_core', 'atp_test.pseudonymized_segments', 'SELECT'
     )
     or not has_table_privilege(
       'atp_test_core', 'atp_test.analysis_versions', 'INSERT'
     )
     or not has_table_privilege(
       'atp_test_core', 'atp_test.evidence_sets', 'UPDATE'
     )
     or not has_table_privilege(
       'atp_test_core',
       'atp_test.v_knowledge_call_analysis_runtime',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: CORE positive controls missing';
  end if;

  if has_table_privilege(
       'atp_test_core', 'atp_test.raw_transcripts', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_core', 'atp_test.transcript_segments', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_core', 'atp_test.pseudonym_mappings', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_core', 'atp_test.knowledge_document_versions', 'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: CORE escaped privacy/product-scoped knowledge boundary';
  end if;

  -- Product knowledge reader sees exactly the product-safe view, not drafts/base tables.
  if not has_table_privilege(
       'atp_test_knowledge_call_analysis',
       'atp_test.v_knowledge_call_analysis_runtime',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: product knowledge reader cannot read safe published view';
  end if;

  if has_table_privilege(
       'atp_test_knowledge_call_analysis',
       'atp_test.knowledge_documents',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_call_analysis',
       'atp_test.knowledge_document_versions',
       'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_call_analysis',
       'atp_test.knowledge_publications',
       'UPDATE'
     )
  then
    raise exception
      'DB-07 verification failed: product knowledge reader can read drafts/base or publish';
  end if;

  -- Knowledge admin has explicit config/knowledge write but no conversation data.
  if not has_table_privilege(
       'atp_test_knowledge_admin',
       'atp_test.knowledge_document_versions',
       'UPDATE'
     )
     or not has_table_privilege(
       'atp_test_knowledge_admin',
       'atp_test.knowledge_publications',
       'INSERT'
     )
  then
    raise exception
      'DB-07 verification failed: knowledge-admin positive controls missing';
  end if;

  if has_table_privilege(
       'atp_test_knowledge_admin', 'atp_test.calls', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_admin', 'atp_test.raw_transcripts', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_knowledge_admin', 'atp_test.pseudonym_mappings', 'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: knowledge admin can read conversation/privacy data';
  end if;

  -- Dashboard can read only prepared analytics/safe evidence.
  if not has_table_privilege(
       'atp_test_dashboard', 'atp_test.v_dashboard_zvonki', 'SELECT'
     )
     or not has_table_privilege(
       'atp_test_dashboard',
       'atp_test.v_dashboard_safe_transcript_segments',
       'SELECT'
     )
     or not has_table_privilege(
       'atp_test_dashboard',
       'atp_test.v_dashboard_evidence_knowledge',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: dashboard positive read controls missing';
  end if;

  if has_table_privilege(
       'atp_test_dashboard', 'atp_test.calls', 'UPDATE'
     )
     or has_table_privilege(
       'atp_test_dashboard', 'atp_test.raw_transcripts', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_dashboard', 'atp_test.pseudonym_mappings', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_dashboard', 'atp_test.knowledge_fragments', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_dashboard', 'atp_test.corrections', 'INSERT'
     )
  then
    raise exception
      'DB-07 verification failed: dashboard gained direct write/raw/mapping/base-knowledge access';
  end if;

  -- Correction operator reviews safe history but cannot direct-write it.
  if not has_table_privilege(
       'atp_test_correction_operator',
       'atp_test.corrections',
       'SELECT'
     )
     or not has_table_privilege(
       'atp_test_correction_operator',
       'atp_test.audit_events',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: correction operator positive read controls missing';
  end if;

  if has_table_privilege(
       'atp_test_correction_operator',
       'atp_test.corrections',
       'UPDATE'
     )
     or has_table_privilege(
       'atp_test_correction_operator',
       'atp_test.analysis_disputes',
       'INSERT'
     )
     or has_table_privilege(
       'atp_test_correction_operator',
       'atp_test.raw_transcripts',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: correction operator can bypass controlled functions';
  end if;

  -- Monitoring can see only minimized technical surfaces.
  if not has_table_privilege(
       'atp_test_monitoring', 'atp_test.v_monitoring_calls', 'SELECT'
     )
     or not has_table_privilege(
       'atp_test_monitoring',
       'atp_test.v_monitoring_operations',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: monitoring positive controls missing';
  end if;

  if has_table_privilege(
       'atp_test_monitoring', 'atp_test.raw_transcripts', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_monitoring', 'atp_test.pseudonymized_segments', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_monitoring', 'atp_test.knowledge_fragments', 'SELECT'
     )
     or has_table_privilege(
       'atp_test_monitoring', 'atp_test.v_dashboard_zvonki', 'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: monitoring can read business/content surfaces';
  end if;

  -- Dashboard metric execution is allowed only where explicitly granted.
  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname in (
      'dashboard_filter_call_ids',
      'dashboard_overview',
      'dashboard_manager_metrics',
      'dashboard_criterion_metrics',
      'dashboard_stage_metrics',
      'dashboard_observation_metrics',
      'dashboard_result_metrics'
    )
    and has_function_privilege('atp_test_dashboard', p.oid, 'EXECUTE');

  if v_count <> 7 then
    raise exception
      'DB-07 verification failed: dashboard can execute only % of 7 metric functions',
      v_count;
  end if;

  -- Controlled write functions: correction operator yes; ordinary dashboard no.
  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname in (
      'dashboard_open_analysis_dispute',
      'dashboard_propose_correction',
      'dashboard_resolve_analysis_dispute',
      'dashboard_finalize_correction'
    )
    and p.prosecdef
    and has_function_privilege(
      'atp_test_correction_operator',
      p.oid,
      'EXECUTE'
    )
    and not has_function_privilege(
      'atp_test_dashboard',
      p.oid,
      'EXECUTE'
    );

  if v_count <> 4 then
    raise exception
      'DB-07 verification failed: controlled write-function boundary expected 4, found %',
      v_count;
  end if;

  -- SECURITY DEFINER functions must have a pinned search_path.
  select string_agg(p.proname, ', ' order by p.proname)
  into v_bad
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname in (
      'dashboard_open_analysis_dispute',
      'dashboard_propose_correction',
      'dashboard_resolve_analysis_dispute',
      'dashboard_finalize_correction'
    )
    and (
      not p.prosecdef
      or p.proconfig is null
      or not exists (
        select 1
        from unnest(p.proconfig) cfg
        where cfg like 'search_path=%pg_catalog%atp_test%'
      )
    );

  if v_bad is not null then
    raise exception
      'DB-07 verification failed: unsafe SECURITY DEFINER function(s): %',
      v_bad;
  end if;

  -- Safe knowledge view must be physically product-scoped.
  if pg_get_viewdef(
       'atp_test.v_knowledge_call_analysis_runtime'::regclass,
       true
     ) not ilike '%product_code%call_analysis%'
  then
    raise exception
      'DB-07 verification failed: call-analysis knowledge view is not product-scoped';
  end if;

  -- Safe dashboard transcript must only expose passed privacy packages.
  if pg_get_viewdef(
       'atp_test.v_dashboard_safe_transcript_segments'::regclass,
       true
     ) not ilike '%privacy_status%passed%'
  then
    raise exception
      'DB-07 verification failed: dashboard safe transcript is not privacy-gated';
  end if;

  raise notice 'DB-07 verification passed';
end
$verify$;

rollback;
