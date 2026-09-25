-- DB-07 rollback
-- TEST/LOCAL ONLY.
-- Removes DB-07 capability roles, views, policies and admin functions.
-- Leaves DB-01..DB-06 objects intact.

begin;

do $guard$
declare
  v_missing_roles text;
  v_missing_views text;
  v_missing_policies text;
  v_memberships text;
  v_extra_relations text;
begin
  select string_agg(required_role, ', ' order by required_role)
  into v_missing_roles
  from (
    values
      ('atp_test_orchestrator'),
      ('atp_test_core'),
      ('atp_test_privacy'),
      ('atp_test_raw_transcript_reader'),
      ('atp_test_knowledge_reader'),
      ('atp_test_knowledge_admin'),
      ('atp_test_dashboard'),
      ('atp_test_admin_api'),
      ('atp_test_monitor')
  ) as required(required_role)
  where not exists (
    select 1 from pg_roles r where r.rolname = required.required_role
  );

  if v_missing_roles is not null then
    raise exception
      'DB-07 rollback refused: missing DB-07 role(s): %',
      v_missing_roles;
  end if;

  select string_agg(required_view, ', ' order by required_view)
  into v_missing_views
  from (
    values
      ('v_runtime_prompt_active'),
      ('v_runtime_methodology_active'),
      ('v_runtime_methodology_criteria_active'),
      ('v_runtime_methodology_stages_active'),
      ('v_runtime_filter_rules_active'),
      ('v_runtime_knowledge_call_analysis'),
      ('v_dashboard_analysis_provenance'),
      ('v_dashboard_safe_transcript_segments'),
      ('v_dashboard_evidence_conversation'),
      ('v_dashboard_evidence_absence'),
      ('v_dashboard_knowledge_evidence'),
      ('v_dashboard_corrections_safe'),
      ('v_dashboard_disputes_safe'),
      ('v_dashboard_feedback_safe'),
      ('v_admin_audit_safe'),
      ('v_monitor_operations'),
      ('v_monitor_audio_cleanup'),
      ('v_monitor_delivery')
  ) as required(required_view)
  where to_regclass('atp_test.' || required.required_view) is null;

  if v_missing_views is not null then
    raise exception
      'DB-07 rollback refused: missing DB-07 view(s): %',
      v_missing_views;
  end if;

  select string_agg(required_policy, ', ' order by required_policy)
  into v_missing_policies
  from (
    values
      ('raw_transcripts_privacy_all'),
      ('raw_transcripts_reader_select'),
      ('transcript_segments_privacy_all'),
      ('transcript_segments_reader_select'),
      ('pseudonym_mappings_privacy_all')
  ) as required(required_policy)
  where not exists (
    select 1
    from pg_policies p
    where p.schemaname = 'atp_test'
      and p.policyname = required.required_policy
  );

  if v_missing_policies is not null then
    raise exception
      'DB-07 rollback refused: missing DB-07 policy/policies: %',
      v_missing_policies;
  end if;

  select string_agg(
    parent.rolname || ' -> ' || member.rolname,
    ', ' order by parent.rolname, member.rolname
  )
  into v_memberships
  from pg_auth_members m
  join pg_roles parent on parent.oid = m.roleid
  join pg_roles member on member.oid = m.member
  where parent.rolname in (
    'atp_test_orchestrator',
    'atp_test_core',
    'atp_test_privacy',
    'atp_test_raw_transcript_reader',
    'atp_test_knowledge_reader',
    'atp_test_knowledge_admin',
    'atp_test_dashboard',
    'atp_test_admin_api',
    'atp_test_monitor'
  );

  if v_memberships is not null then
    raise exception
      'DB-07 rollback refused: detach capability-role memberships first: %',
      v_memberships;
  end if;

  select string_agg(c_rel.relname::text, ', ' order by c_rel.relname::text)
  into v_extra_relations
  from pg_class c_rel
  join pg_namespace n on n.oid = c_rel.relnamespace
  where n.nspname = 'atp_test'
    and c_rel.relkind in ('r', 'p', 'v', 'm')
    and c_rel.relname not in (
      -- DB-01
      'managers','calls','call_events','operations','operation_attempts',
      'filter_decisions','call_links','temporary_audio_artifacts',
      -- DB-02
      'raw_transcripts','transcript_segments','role_assignment_versions',
      'role_assignments','pseudonymized_transcripts','pseudonymized_segments',
      'privacy_packages','privacy_package_segments','pseudonym_mappings',
      'processing_quality','speech_metrics',
      -- DB-03
      'prompt_versions','methodology_versions','methodology_criteria',
      'methodology_stages','filter_rule_versions','knowledge_documents',
      'knowledge_document_versions','knowledge_fragments','knowledge_embeddings',
      'knowledge_publications','knowledge_publication_documents',
      'knowledge_publication_fragments',
      'knowledge_publication_fragment_products','v_runtime_knowledge_fragments',
      -- DB-04
      'analysis_versions','analysis_knowledge_inputs','analysis_claims',
      'criterion_scores','stage_results','analysis_observations',
      'ai_inferred_outcomes','evidence_sets','evidence_conversation_refs',
      'evidence_knowledge_refs','evidence_absence_checks',
      -- DB-05
      'business_confirmations','callback_links','outgoing_actions',
      'delivery_attempts','analysis_disputes','corrections','audit_events',
      -- DB-06
      'v_dashboard_business_confirmations_current',
      'v_dashboard_delivery_current',
      'v_dashboard_processing_quality_current',
      'v_dashboard_speech_metrics_current',
      'v_dashboard_zvonki',
      'v_dashboard_obshchaya_kartina',
      'v_dashboard_menedzhery',
      'v_dashboard_kriterii',
      'v_dashboard_etapy',
      'v_dashboard_oshibki',
      'v_dashboard_rezultaty',
      'v_dashboard_kachestvo',
      -- DB-07
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
    );

  if v_extra_relations is not null then
    raise exception
      'DB-07 rollback refused: later/unknown relations exist in atp_test: %',
      v_extra_relations;
  end if;

  if to_regprocedure(
       'atp_test.admin_submit_analysis_dispute(uuid,uuid,uuid,uuid,text,text)'
     ) is null
     or to_regprocedure(
       'atp_test.admin_propose_correction(uuid,atp_test.correction_target_type,uuid,text,text,jsonb,jsonb,text,text,uuid)'
     ) is null
  then
    raise exception
      'DB-07 rollback refused: DB-07 admin function(s) missing';
  end if;
end
$guard$;

-- Remove role references from RLS policies before dropping roles.
drop policy raw_transcripts_privacy_all
  on atp_test.raw_transcripts;
drop policy raw_transcripts_reader_select
  on atp_test.raw_transcripts;
drop policy transcript_segments_privacy_all
  on atp_test.transcript_segments;
drop policy transcript_segments_reader_select
  on atp_test.transcript_segments;
drop policy pseudonym_mappings_privacy_all
  on atp_test.pseudonym_mappings;

alter table atp_test.raw_transcripts disable row level security;
alter table atp_test.transcript_segments disable row level security;
alter table atp_test.pseudonym_mappings disable row level security;

drop function atp_test.admin_propose_correction(
  uuid, atp_test.correction_target_type, uuid, text, text, jsonb, jsonb, text, text, uuid
);
drop function atp_test.admin_submit_analysis_dispute(
  uuid, uuid, uuid, uuid, text, text
);

drop view atp_test.v_monitor_delivery;
drop view atp_test.v_monitor_audio_cleanup;
drop view atp_test.v_monitor_operations;
drop view atp_test.v_admin_audit_safe;
drop view atp_test.v_dashboard_feedback_safe;
drop view atp_test.v_dashboard_disputes_safe;
drop view atp_test.v_dashboard_corrections_safe;
drop view atp_test.v_dashboard_knowledge_evidence;
drop view atp_test.v_dashboard_evidence_absence;
drop view atp_test.v_dashboard_evidence_conversation;
drop view atp_test.v_dashboard_safe_transcript_segments;
drop view atp_test.v_dashboard_analysis_provenance;
drop view atp_test.v_runtime_knowledge_call_analysis;
drop view atp_test.v_runtime_filter_rules_active;
drop view atp_test.v_runtime_methodology_stages_active;
drop view atp_test.v_runtime_methodology_criteria_active;
drop view atp_test.v_runtime_methodology_active;
drop view atp_test.v_runtime_prompt_active;

-- Remove all grants made to the capability roles.
revoke all privileges on all tables in schema atp_test from
  atp_test_orchestrator,
  atp_test_core,
  atp_test_privacy,
  atp_test_raw_transcript_reader,
  atp_test_knowledge_reader,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_admin_api,
  atp_test_monitor;

revoke all privileges on all sequences in schema atp_test from
  atp_test_orchestrator,
  atp_test_core,
  atp_test_privacy,
  atp_test_raw_transcript_reader,
  atp_test_knowledge_reader,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_admin_api,
  atp_test_monitor;

revoke all privileges on all functions in schema atp_test from
  atp_test_orchestrator,
  atp_test_core,
  atp_test_privacy,
  atp_test_raw_transcript_reader,
  atp_test_knowledge_reader,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_admin_api,
  atp_test_monitor;

revoke all privileges on schema atp_test from
  atp_test_orchestrator,
  atp_test_core,
  atp_test_privacy,
  atp_test_raw_transcript_reader,
  atp_test_knowledge_reader,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_admin_api,
  atp_test_monitor;

-- DB-01..DB-06 functions existed before DB-07 and PostgreSQL default grants
-- EXECUTE to PUBLIC. Restore that pre-DB-07 state after dropping DB-07 funcs.
grant execute on all functions in schema atp_test to public;
alter default privileges in schema atp_test
  grant execute on functions to public;

drop role atp_test_monitor;
drop role atp_test_admin_api;
drop role atp_test_dashboard;
drop role atp_test_knowledge_admin;
drop role atp_test_knowledge_reader;
drop role atp_test_raw_transcript_reader;
drop role atp_test_privacy;
drop role atp_test_core;
drop role atp_test_orchestrator;

commit;
