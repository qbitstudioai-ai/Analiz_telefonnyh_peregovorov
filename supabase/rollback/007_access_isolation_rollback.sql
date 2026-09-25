-- DB-07 rollback
-- TEST/LOCAL ONLY.
-- Removes only DB-07 roles/views/functions and restores the pre-DB-07
-- PostgreSQL default PUBLIC function EXECUTE behavior.
--
-- Refuses to run if capability roles have already been attached to real login
-- identities. Detach/revoke those memberships explicitly first.

begin;

do $guard$
declare
  v_missing_roles text;
  v_memberships text;
  v_missing_views text;
  v_extra_relations text;
begin
  select string_agg(required_role, ', ' order by required_role)
  into v_missing_roles
  from (
    values
      ('atp_test_orchestrator'),
      ('atp_test_privacy'),
      ('atp_test_core'),
      ('atp_test_knowledge_call_analysis'),
      ('atp_test_knowledge_admin'),
      ('atp_test_dashboard'),
      ('atp_test_correction_operator'),
      ('atp_test_monitoring')
  ) as required(required_role)
  where not exists (
    select 1 from pg_roles r where r.rolname = required.required_role
  );

  if v_missing_roles is not null then
    raise exception
      'DB-07 rollback refused: missing DB-07 role(s): %',
      v_missing_roles;
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
    'atp_test_privacy',
    'atp_test_core',
    'atp_test_knowledge_call_analysis',
    'atp_test_knowledge_admin',
    'atp_test_dashboard',
    'atp_test_correction_operator',
    'atp_test_monitoring'
  );

  if v_memberships is not null then
    raise exception
      'DB-07 rollback refused: detach capability-role memberships first: %',
      v_memberships;
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing_views
  from (
    values
      ('v_knowledge_call_analysis_runtime'),
      ('v_dashboard_safe_transcript_segments'),
      ('v_dashboard_evidence_conversation'),
      ('v_dashboard_evidence_knowledge'),
      ('v_monitoring_calls'),
      ('v_monitoring_operations')
  ) as required(required_relation)
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname = required.required_relation
      and c.relkind = 'v'
  );

  if v_missing_views is not null then
    raise exception
      'DB-07 rollback refused: missing DB-07 view(s): %',
      v_missing_views;
  end if;

  select string_agg(c.relname::text, ', ' order by c.relname::text)
  into v_extra_relations
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'atp_test'
    and c.relkind in ('r', 'p', 'v', 'm')
    and c.relname not in (
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
      'v_knowledge_call_analysis_runtime',
      'v_dashboard_safe_transcript_segments',
      'v_dashboard_evidence_conversation',
      'v_dashboard_evidence_knowledge',
      'v_monitoring_calls',
      'v_monitoring_operations'
    );

  if v_extra_relations is not null then
    raise exception
      'DB-07 rollback refused: later/unknown relations exist in atp_test: %',
      v_extra_relations;
  end if;
end
$guard$;

-- Remove all explicit object grants before dropping global roles.
revoke all privileges on all tables in schema atp_test from
  atp_test_orchestrator,
  atp_test_privacy,
  atp_test_core,
  atp_test_knowledge_call_analysis,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_correction_operator,
  atp_test_monitoring;

revoke all privileges on all sequences in schema atp_test from
  atp_test_orchestrator,
  atp_test_privacy,
  atp_test_core,
  atp_test_knowledge_call_analysis,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_correction_operator,
  atp_test_monitoring;

revoke all privileges on all functions in schema atp_test from
  atp_test_orchestrator,
  atp_test_privacy,
  atp_test_core,
  atp_test_knowledge_call_analysis,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_correction_operator,
  atp_test_monitoring;

revoke all privileges on schema atp_test from
  atp_test_orchestrator,
  atp_test_privacy,
  atp_test_core,
  atp_test_knowledge_call_analysis,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_correction_operator,
  atp_test_monitoring;

drop function atp_test.dashboard_finalize_correction(
  uuid, text, uuid, text, text
);
drop function atp_test.dashboard_resolve_analysis_dispute(
  uuid, text, text, text
);
drop function atp_test.dashboard_propose_correction(
  uuid, text, uuid, text, text, jsonb, jsonb, text, text, uuid
);
drop function atp_test.dashboard_open_analysis_dispute(
  uuid, uuid, uuid, uuid, text, text
);

drop view atp_test.v_monitoring_operations;
drop view atp_test.v_monitoring_calls;
drop view atp_test.v_dashboard_evidence_knowledge;
drop view atp_test.v_dashboard_evidence_conversation;
drop view atp_test.v_dashboard_safe_transcript_segments;
drop view atp_test.v_knowledge_call_analysis_runtime;

-- Restore pre-DB-07 function-execution defaults for a true rollback to DB-06.
grant execute on all functions in schema atp_test to public;
alter default privileges in schema atp_test
  grant execute on functions to public;

drop role atp_test_monitoring;
drop role atp_test_correction_operator;
drop role atp_test_dashboard;
drop role atp_test_knowledge_admin;
drop role atp_test_knowledge_call_analysis;
drop role atp_test_core;
drop role atp_test_privacy;
drop role atp_test_orchestrator;

commit;
