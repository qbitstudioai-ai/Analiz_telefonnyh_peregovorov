-- DB-07 verification
-- APPROVED WORKING CONTOUR. Verification is limited to schema shablon_analiz_telefonnyh_peregovorov.
-- Run after DB-01..DB-07 migrations.
-- Verifies capability roles, grants, RLS/policies and restricted surfaces.
-- The whole verification is rolled back.

begin;

create schema atp_verify_other;
revoke all on schema atp_verify_other from public;
create table atp_verify_other.sentinel (
  sentinel_id integer primary key
);

create schema atp_verify_prod;
revoke all on schema atp_verify_prod from public;
create table atp_verify_prod.sentinel (
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
    select 1 from pg_namespace where nspname = 'shablon_analiz_telefonnyh_peregovorov'
  ) then
    raise exception 'DB-07 verification failed: schema shablon_analiz_telefonnyh_peregovorov does not exist';
  end if;

  -- Every DB-07 role is a NOLOGIN, non-admin, non-bypass capability role.
  foreach v_role in array array[
    'shablon_analiz_telefonnyh_peregovorov_orchestrator',
    'shablon_analiz_telefonnyh_peregovorov_core',
    'shablon_analiz_telefonnyh_peregovorov_privacy',
    'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
    'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
    'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
    'shablon_analiz_telefonnyh_peregovorov_dashboard',
    'shablon_analiz_telefonnyh_peregovorov_admin_api',
    'shablon_analiz_telefonnyh_peregovorov_monitor'
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

    if not has_schema_privilege(v_role, 'shablon_analiz_telefonnyh_peregovorov', 'USAGE') then
      raise exception
        'DB-07 verification failed: role % lacks allowed shablon_analiz_telefonnyh_peregovorov USAGE',
        v_role;
    end if;

    if has_schema_privilege(v_role, 'shablon_analiz_telefonnyh_peregovorov', 'CREATE') then
      raise exception
        'DB-07 verification failed: role % can CREATE in shablon_analiz_telefonnyh_peregovorov',
        v_role;
    end if;

    if has_schema_privilege(v_role, 'atp_verify_other', 'USAGE')
       or has_schema_privilege(v_role, 'atp_verify_other', 'CREATE')
       or has_table_privilege(v_role, 'atp_verify_other.sentinel', 'SELECT')
       or has_table_privilege(v_role, 'atp_verify_other.sentinel', 'INSERT')
       or has_schema_privilege(v_role, 'atp_verify_prod', 'USAGE')
       or has_schema_privilege(v_role, 'atp_verify_prod', 'CREATE')
       or has_table_privilege(v_role, 'atp_verify_prod.sentinel', 'SELECT')
       or has_table_privilege(v_role, 'atp_verify_prod.sentinel', 'INSERT')
    then
      raise exception
        'DB-07 verification failed: role % escaped into another schema',
        v_role;
    end if;
  end loop;

  -- PostgreSQL 17 automatically grants a role created by a non-superuser
  -- CREATEROLE user back to that creator WITH ADMIN TRUE, SET FALSE,
  -- INHERIT FALSE. This administrative creator membership is safe for the
  -- runtime boundary: it does not inherit capability privileges and cannot
  -- SET ROLE into the capability. Any other membership is rejected.
  select count(*)
  into v_count
  from pg_auth_members m
  join pg_roles parent on parent.oid = m.roleid
  where parent.rolname in (
    'shablon_analiz_telefonnyh_peregovorov_orchestrator',
    'shablon_analiz_telefonnyh_peregovorov_core',
    'shablon_analiz_telefonnyh_peregovorov_privacy',
    'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
    'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
    'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
    'shablon_analiz_telefonnyh_peregovorov_dashboard',
    'shablon_analiz_telefonnyh_peregovorov_admin_api',
    'shablon_analiz_telefonnyh_peregovorov_monitor'
  );

  if v_count not in (0, 9) then
    raise exception
      'DB-07 verification failed: expected 0 memberships or 9 safe creator-admin memberships, found %',
      v_count;
  end if;

  if v_count = 9 then
    select string_agg(
      parent.rolname || ' -> ' || member.rolname,
      ', ' order by parent.rolname, member.rolname
    )
    into v_bad
    from pg_auth_members m
    join pg_roles parent on parent.oid = m.roleid
    join pg_roles member on member.oid = m.member
    where parent.rolname in (
      'shablon_analiz_telefonnyh_peregovorov_orchestrator',
      'shablon_analiz_telefonnyh_peregovorov_core',
      'shablon_analiz_telefonnyh_peregovorov_privacy',
      'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
      'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
      'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
      'shablon_analiz_telefonnyh_peregovorov_dashboard',
      'shablon_analiz_telefonnyh_peregovorov_admin_api',
      'shablon_analiz_telefonnyh_peregovorov_monitor'
    )
      and (
        member.rolname <> current_user
        or not m.admin_option
        or m.inherit_option
        or m.set_option
      );

    if v_bad is not null then
      raise exception
        'DB-07 verification failed: unsafe capability-role membership(s): %',
        v_bad;
    end if;

    select count(distinct parent.rolname)
    into v_count
    from pg_auth_members m
    join pg_roles parent on parent.oid = m.roleid
    join pg_roles member on member.oid = m.member
    where parent.rolname in (
      'shablon_analiz_telefonnyh_peregovorov_orchestrator',
      'shablon_analiz_telefonnyh_peregovorov_core',
      'shablon_analiz_telefonnyh_peregovorov_privacy',
      'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
      'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
      'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
      'shablon_analiz_telefonnyh_peregovorov_dashboard',
      'shablon_analiz_telefonnyh_peregovorov_admin_api',
      'shablon_analiz_telefonnyh_peregovorov_monitor'
    )
      and member.rolname = current_user
      and m.admin_option
      and not m.inherit_option
      and not m.set_option;

    if v_count <> 9 then
      raise exception
        'DB-07 verification failed: creator-admin memberships do not cover all 9 capability roles';
    end if;
  end if;

  -- PUBLIC must not have ambient relation access.
  select count(*)
  into v_count
  from pg_class c_rel
  join pg_namespace n on n.oid = c_rel.relnamespace
  cross join lateral aclexplode(
    coalesce(c_rel.relacl, acldefault('r', c_rel.relowner))
  ) acl
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and c_rel.relkind in ('r', 'p', 'v', 'm')
    and acl.grantee = 0;

  if v_count <> 0 then
    raise exception
      'DB-07 verification failed: PUBLIC relation privileges remain in shablon_analiz_telefonnyh_peregovorov';
  end if;

  -- PUBLIC EXECUTE is removed from every function, not only admin functions.
  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(
    coalesce(p.proacl, acldefault('f', p.proowner))
  ) acl
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and acl.grantee = 0
    and acl.privilege_type = 'EXECUTE';

  if v_count <> 0 then
    raise exception
      'DB-07 verification failed: PUBLIC EXECUTE remains on % shablon_analiz_telefonnyh_peregovorov function(s)',
      v_count;
  end if;

  -- New functions created by the migration owner must not regain PUBLIC EXECUTE.
  select count(*)
  into v_count
  from pg_default_acl d
  join pg_namespace n on n.oid = d.defaclnamespace
  cross join lateral aclexplode(d.defaclacl) acl
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and d.defaclrole = (
      select oid from pg_roles where rolname = current_user
    )
    and d.defaclobjtype = 'f'
    and acl.grantee = 0
    and acl.privilege_type = 'EXECUTE';

  if v_count <> 0 then
    raise exception
      'DB-07 verification failed: future shablon_analiz_telefonnyh_peregovorov functions still default to PUBLIC EXECUTE';
  end if;

  -- Business schema is not a password/token/secret/credential store.
  select string_agg(
    table_name || '.' || column_name,
    ', ' order by table_name, column_name
  )
  into v_bad
  from information_schema.columns
  where table_schema = 'shablon_analiz_telefonnyh_peregovorov'
    and (
      column_name ilike '%password%'
      or column_name ilike '%token%'
      or column_name ilike '%secret%'
      or column_name ilike '%credential%'
    );

  if v_bad is not null then
    raise exception
      'DB-07 verification failed: secret-like business column(s): %',
      v_bad;
  end if;

  -- No capability role receives DELETE/TRUNCATE on any shablon_analiz_telefonnyh_peregovorov relation.
  select string_agg(role_name || ':' || relname, ', ' order by role_name, relname)
  into v_bad
  from (
    select
      role_name,
      c_rel.relname
    from unnest(array[
      'shablon_analiz_telefonnyh_peregovorov_orchestrator',
      'shablon_analiz_telefonnyh_peregovorov_core',
      'shablon_analiz_telefonnyh_peregovorov_privacy',
      'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
      'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
      'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
      'shablon_analiz_telefonnyh_peregovorov_dashboard',
      'shablon_analiz_telefonnyh_peregovorov_admin_api',
      'shablon_analiz_telefonnyh_peregovorov_monitor'
    ]) role_name
    cross join pg_class c_rel
    join pg_namespace n on n.oid = c_rel.relnamespace
    where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
      and c_rel.relkind in ('r', 'p', 'v', 'm')
      and (
        has_table_privilege(role_name, c_rel.oid, 'DELETE')
        or has_table_privilege(role_name, c_rel.oid, 'TRUNCATE')
      )
  ) forbidden;

  if v_bad is not null then
    raise exception
      'DB-07 verification failed: destructive privilege(s): %',
      v_bad;
  end if;

  -- All DB-07 safe/runtime views must keep security_barrier=true.
  select string_agg(c_rel.relname, ', ' order by c_rel.relname)
  into v_bad
  from pg_class c_rel
  join pg_namespace n on n.oid = c_rel.relnamespace
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and c_rel.relname in (
      'v_runtime_prompt_active',
      'v_runtime_methodology_active',
      'v_runtime_methodology_criteria_active',
      'v_runtime_methodology_stages_active',
      'v_runtime_filter_rules_active',
      'v_runtime_knowledge_call_analysis',
      'v_dashboard_analysis_provenance',
      'v_dashboard_safe_transcript_segments',
      'v_dashboard_evidence_conversation',
      'v_dashboard_evidence_absence',
      'v_dashboard_knowledge_evidence',
      'v_dashboard_corrections_safe',
      'v_dashboard_disputes_safe',
      'v_dashboard_feedback_safe',
      'v_admin_audit_safe',
      'v_monitor_operations',
      'v_monitor_audio_cleanup',
      'v_monitor_delivery'
    )
    and not (
      coalesce(c_rel.reloptions, '{}'::text[])
      @> array['security_barrier=true']::text[]
    );

  if v_bad is not null then
    raise exception
      'DB-07 verification failed: view(s) lost security_barrier: %',
      v_bad;
  end if;

  -- RLS defense-in-depth is enabled on the three sensitive raw/mapping tables.
  select count(*)
  into v_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
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
  where p.schemaname = 'shablon_analiz_telefonnyh_peregovorov'
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
  if not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.calls', 'SELECT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.calls', 'INSERT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.calls', 'UPDATE')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.outgoing_actions', 'INSERT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.delivery_attempts', 'UPDATE')
  then
    raise exception
      'DB-07 verification failed: orchestrator positive control missing';
  end if;

  -- Negative: orchestrator cannot read raw/mapping or administer knowledge.
  if has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.raw_transcripts', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.transcript_segments', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.knowledge_documents', 'INSERT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.knowledge_publications', 'UPDATE')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.audit_events', 'UPDATE')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_orchestrator', 'shablon_analiz_telefonnyh_peregovorov.audit_events', 'DELETE')
  then
    raise exception
      'DB-07 verification failed: orchestrator has forbidden raw/knowledge/audit privilege';
  end if;

  -- CORE positive control.
  if not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_core', 'shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_call_analysis', 'SELECT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_core', 'shablon_analiz_telefonnyh_peregovorov.analysis_versions', 'INSERT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_core', 'shablon_analiz_telefonnyh_peregovorov.analysis_versions', 'UPDATE')
     or not has_function_privilege(
       'shablon_analiz_telefonnyh_peregovorov_core',
       'shablon_analiz_telefonnyh_peregovorov.calculate_analysis_overall_score(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shablon_analiz_telefonnyh_peregovorov_core',
       'shablon_analiz_telefonnyh_peregovorov.validate_analysis_evidence_gate(uuid)',
       'EXECUTE'
     )
  then
    raise exception
      'DB-07 verification failed: CORE positive control missing';
  end if;

  -- CORE cannot bypass privacy or publish/edit knowledge.
  if has_table_privilege('shablon_analiz_telefonnyh_peregovorov_core', 'shablon_analiz_telefonnyh_peregovorov.raw_transcripts', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_core', 'shablon_analiz_telefonnyh_peregovorov.transcript_segments', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_core', 'shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_core', 'shablon_analiz_telefonnyh_peregovorov.knowledge_documents', 'UPDATE')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_core', 'shablon_analiz_telefonnyh_peregovorov.knowledge_publications', 'UPDATE')
  then
    raise exception
      'DB-07 verification failed: CORE has forbidden raw/mapping/knowledge-write privilege';
  end if;

  -- Privacy positive control and separation from dashboard/admin knowledge.
  if not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_privacy', 'shablon_analiz_telefonnyh_peregovorov.raw_transcripts', 'SELECT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_privacy', 'shablon_analiz_telefonnyh_peregovorov.raw_transcripts', 'INSERT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_privacy', 'shablon_analiz_telefonnyh_peregovorov.raw_transcripts', 'UPDATE')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_privacy', 'shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings', 'SELECT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_privacy', 'shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings', 'INSERT')
  then
    raise exception
      'DB-07 verification failed: privacy positive control missing';
  end if;

  if has_table_privilege('shablon_analiz_telefonnyh_peregovorov_privacy', 'shablon_analiz_telefonnyh_peregovorov.v_dashboard_zvonki', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_privacy', 'shablon_analiz_telefonnyh_peregovorov.knowledge_publications', 'UPDATE')
  then
    raise exception
      'DB-07 verification failed: privacy role has unrelated dashboard/knowledge-admin access';
  end if;

  -- Optional raw reader sees raw text but never mapping.
  if not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
       'shablon_analiz_telefonnyh_peregovorov.raw_transcripts',
       'SELECT'
     )
     or not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
       'shablon_analiz_telefonnyh_peregovorov.transcript_segments',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: raw-reader positive control missing';
  end if;

  if has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
       'shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
       'shablon_analiz_telefonnyh_peregovorov.raw_transcripts',
       'UPDATE'
     )
  then
    raise exception
      'DB-07 verification failed: raw-reader can access mapping or mutate raw data';
  end if;

  -- Knowledge reader: one published call_analysis surface only.
  if not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
       'shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_call_analysis',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: knowledge-reader positive control missing';
  end if;

  if has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
       'shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_fragments',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
       'shablon_analiz_telefonnyh_peregovorov.knowledge_documents',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
       'shablon_analiz_telefonnyh_peregovorov.knowledge_document_versions',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
       'shablon_analiz_telefonnyh_peregovorov.knowledge_fragments',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
       'shablon_analiz_telefonnyh_peregovorov.knowledge_embeddings',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
       'shablon_analiz_telefonnyh_peregovorov.knowledge_publications',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
       'shablon_analiz_telefonnyh_peregovorov.knowledge_publications',
       'UPDATE'
     )
  then
    raise exception
      'DB-07 verification failed: knowledge reader can see raw/draft knowledge or write';
  end if;

  select pg_get_viewdef(
    'shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_call_analysis'::regclass,
    true
  )
  into v_definition;

  if v_definition not ilike '%call_analysis%'
     or v_definition not ilike '%v_runtime_knowledge_fragments%'
  then
    raise exception
      'DB-07 verification failed: product-scoped knowledge view definition is wrong';
  end if;

  -- Knowledge administration is separated from runtime reader and call data.
  if not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
       'shablon_analiz_telefonnyh_peregovorov.knowledge_document_versions',
       'UPDATE'
     )
     or not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
       'shablon_analiz_telefonnyh_peregovorov.knowledge_publications',
       'INSERT'
     )
     or not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
       'shablon_analiz_telefonnyh_peregovorov.v_admin_audit_safe',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: knowledge-admin positive control missing';
  end if;

  if has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
       'shablon_analiz_telefonnyh_peregovorov.calls',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
       'shablon_analiz_telefonnyh_peregovorov.raw_transcripts',
       'SELECT'
     )
     or has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
       'shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings',
       'SELECT'
     )
  then
    raise exception
      'DB-07 verification failed: knowledge admin can read call/privacy data';
  end if;

  -- Active configuration surfaces cannot reveal drafts/unvalidated rows.
  select pg_get_viewdef('shablon_analiz_telefonnyh_peregovorov.v_runtime_prompt_active'::regclass, true)
  into v_definition;
  if v_definition not ilike '%config_state = ''active''%'
     or v_definition not ilike '%validation_status = ''passed''%'
  then
    raise exception
      'DB-07 verification failed: prompt runtime surface is not active+passed only';
  end if;

  select pg_get_viewdef('shablon_analiz_telefonnyh_peregovorov.v_runtime_filter_rules_active'::regclass, true)
  into v_definition;
  if v_definition not ilike '%config_state = ''active''%'
     or v_definition not ilike '%validation_status = ''passed''%'
  then
    raise exception
      'DB-07 verification failed: filter runtime surface is not active+passed only';
  end if;

  -- Dashboard positive controls.
  if not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.v_dashboard_zvonki', 'SELECT')
     or not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_dashboard',
       'shablon_analiz_telefonnyh_peregovorov.v_dashboard_safe_transcript_segments',
       'SELECT'
     )
     or not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_dashboard',
       'shablon_analiz_telefonnyh_peregovorov.v_dashboard_evidence_conversation',
       'SELECT'
     )
     or not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_dashboard',
       'shablon_analiz_telefonnyh_peregovorov.v_dashboard_evidence_absence',
       'SELECT'
     )
     or not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_dashboard',
       'shablon_analiz_telefonnyh_peregovorov.v_dashboard_knowledge_evidence',
       'SELECT'
     )
     or not has_function_privilege(
       'shablon_analiz_telefonnyh_peregovorov_dashboard',
       'shablon_analiz_telefonnyh_peregovorov.dashboard_overview(timestamptz,timestamptz,jsonb,timestamptz,interval,text[],text[])',
       'EXECUTE'
     )
  then
    raise exception
      'DB-07 verification failed: dashboard positive control missing';
  end if;

  -- Dashboard cannot read raw/mapping or mutate primary business/history rows.
  if has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.raw_transcripts', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.transcript_segments', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.calls', 'INSERT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.analysis_versions', 'UPDATE')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.business_confirmations', 'UPDATE')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.audit_events', 'INSERT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.evidence_conversation_refs', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_dashboard', 'shablon_analiz_telefonnyh_peregovorov.evidence_absence_checks', 'SELECT')
  then
    raise exception
      'DB-07 verification failed: dashboard has forbidden raw/direct-write privilege';
  end if;

  select pg_get_viewdef(
    'shablon_analiz_telefonnyh_peregovorov.v_dashboard_safe_transcript_segments'::regclass,
    true
  )
  into v_definition;

  if v_definition not ilike '%privacy_status%passed%'
  then
    raise exception
      'DB-07 verification failed: dashboard safe transcript is not privacy-passed only';
  end if;

  -- Admin API uses controlled functions, not direct business-table write.
  if not has_table_privilege(
       'shablon_analiz_telefonnyh_peregovorov_admin_api',
       'shablon_analiz_telefonnyh_peregovorov.v_admin_audit_safe',
       'SELECT'
     )
     or not has_function_privilege(
       'shablon_analiz_telefonnyh_peregovorov_admin_api',
       'shablon_analiz_telefonnyh_peregovorov.admin_submit_analysis_dispute(uuid,uuid,uuid,uuid,text,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shablon_analiz_telefonnyh_peregovorov_admin_api',
       'shablon_analiz_telefonnyh_peregovorov.admin_propose_correction(uuid,shablon_analiz_telefonnyh_peregovorov.correction_target_type,uuid,text,text,jsonb,jsonb,text,text,uuid)',
       'EXECUTE'
     )
  then
    raise exception
      'DB-07 verification failed: admin API positive control missing';
  end if;

  if has_table_privilege('shablon_analiz_telefonnyh_peregovorov_admin_api', 'shablon_analiz_telefonnyh_peregovorov.analysis_disputes', 'INSERT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_admin_api', 'shablon_analiz_telefonnyh_peregovorov.corrections', 'INSERT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_admin_api', 'shablon_analiz_telefonnyh_peregovorov.audit_events', 'INSERT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_admin_api', 'shablon_analiz_telefonnyh_peregovorov.raw_transcripts', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_admin_api', 'shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings', 'SELECT')
  then
    raise exception
      'DB-07 verification failed: admin API bypasses controlled functions/privacy';
  end if;

  -- Security definer functions must use a fixed search_path.
  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and p.proname in (
      'admin_submit_analysis_dispute',
      'admin_propose_correction'
    )
    and p.prosecdef
    and exists (
      select 1
      from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
      where cfg = 'search_path=pg_catalog, shablon_analiz_telefonnyh_peregovorov'
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
    where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
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
    where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
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
  if not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_monitor', 'shablon_analiz_telefonnyh_peregovorov.v_monitor_operations', 'SELECT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_monitor', 'shablon_analiz_telefonnyh_peregovorov.v_monitor_audio_cleanup', 'SELECT')
     or not has_table_privilege('shablon_analiz_telefonnyh_peregovorov_monitor', 'shablon_analiz_telefonnyh_peregovorov.v_monitor_delivery', 'SELECT')
  then
    raise exception
      'DB-07 verification failed: monitor positive control missing';
  end if;

  if has_table_privilege('shablon_analiz_telefonnyh_peregovorov_monitor', 'shablon_analiz_telefonnyh_peregovorov.raw_transcripts', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_monitor', 'shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_monitor', 'shablon_analiz_telefonnyh_peregovorov.knowledge_documents', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_monitor', 'shablon_analiz_telefonnyh_peregovorov.v_dashboard_zvonki', 'SELECT')
     or has_table_privilege('shablon_analiz_telefonnyh_peregovorov_monitor', 'shablon_analiz_telefonnyh_peregovorov.outgoing_actions', 'SELECT')
  then
    raise exception
      'DB-07 verification failed: monitor has conversation/business content access';
  end if;

  -- No ordinary capability role can DELETE immutable/business history.
  select string_agg(role_list.role_name, ', ')
  into v_bad
  from unnest(array[
    'shablon_analiz_telefonnyh_peregovorov_orchestrator',
    'shablon_analiz_telefonnyh_peregovorov_core',
    'shablon_analiz_telefonnyh_peregovorov_privacy',
    'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
    'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
    'shablon_analiz_telefonnyh_peregovorov_knowledge_admin',
    'shablon_analiz_telefonnyh_peregovorov_dashboard',
    'shablon_analiz_telefonnyh_peregovorov_admin_api',
    'shablon_analiz_telefonnyh_peregovorov_monitor'
  ]) as role_list(role_name)
  where has_table_privilege(role_list.role_name, 'shablon_analiz_telefonnyh_peregovorov.analysis_versions', 'DELETE')
     or has_table_privilege(role_list.role_name, 'shablon_analiz_telefonnyh_peregovorov.business_confirmations', 'DELETE')
     or has_table_privilege(role_list.role_name, 'shablon_analiz_telefonnyh_peregovorov.delivery_attempts', 'DELETE')
     or has_table_privilege(role_list.role_name, 'shablon_analiz_telefonnyh_peregovorov.audit_events', 'DELETE');

  if v_bad is not null then
    raise exception
      'DB-07 verification failed: role(s) have forbidden DELETE: %',
      v_bad;
  end if;

  -- If a production-like schema happens to exist, shablon_analiz_telefonnyh_peregovorov roles must not see it.
  if exists (
    select 1 from pg_namespace where nspname = 'atp_prod'
  ) then
    select string_agg(role_list.role_name, ', ')
    into v_bad
    from unnest(array[
      'shablon_analiz_telefonnyh_peregovorov_orchestrator',
      'shablon_analiz_telefonnyh_peregovorov_core',
      'shablon_analiz_telefonnyh_peregovorov_privacy',
      'shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader',
      'shablon_analiz_telefonnyh_peregovorov_knowledge_reader',
      'shablon_analiz_telefonnyh_peregovorov_dashboard',
      'shablon_analiz_telefonnyh_peregovorov_admin_api',
      'shablon_analiz_telefonnyh_peregovorov_monitor'
    ]) as role_list(role_name)
    where has_schema_privilege(role_list.role_name, 'atp_prod', 'USAGE')
       or has_schema_privilege(role_list.role_name, 'atp_prod', 'CREATE');

    if v_bad is not null then
      raise exception
        'DB-07 verification failed: shablon_analiz_telefonnyh_peregovorov role(s) have atp_prod access: %',
        v_bad;
    end if;
  end if;

  raise notice 'DB-07 verification passed';
end
$verify$;

rollback;
