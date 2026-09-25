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
  atp_test_dashboard,
  atp_test_admin_api,
  atp_test_monitor;

revoke all privileges on all functions in schema atp_test from
  atp_test_orchestrator,
  atp_test_core,
  atp_test_privacy,
  atp_test_raw_transcript_reader,
  atp_test_knowledge_reader,
  atp_test_dashboard,
  atp_test_admin_api,
  atp_test_monitor;

revoke all privileges on schema atp_test from
  atp_test_orchestrator,
  atp_test_core,
  atp_test_privacy,
  atp_test_raw_transcript_reader,
  atp_test_knowledge_reader,
  atp_test_dashboard,
  atp_test_admin_api,
  atp_test_monitor;

-- DB-01..DB-06 functions existed before DB-07 and PostgreSQL default grants
-- EXECUTE to PUBLIC. Restore that pre-DB-07 state after dropping DB-07 funcs.
grant execute on all functions in schema atp_test to public;

drop role atp_test_monitor;
drop role atp_test_admin_api;
drop role atp_test_dashboard;
drop role atp_test_knowledge_reader;
drop role atp_test_raw_transcript_reader;
drop role atp_test_privacy;
drop role atp_test_core;
drop role atp_test_orchestrator;

commit;
