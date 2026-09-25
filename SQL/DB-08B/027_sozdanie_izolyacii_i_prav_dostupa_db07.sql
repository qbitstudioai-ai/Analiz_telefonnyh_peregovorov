-- DB-07
-- Shablon-contour capability roles, restricted runtime surfaces and negative
-- permission boundaries.
-- APPROVED WORKING CONTOUR. Depends on DB-01..DB-06; scope is limited to schema shablon_analiz_telefonnyh_peregovorov.
--
-- No LOGIN roles, passwords or credentials are created here.
-- A future secret-management step creates LOGIN identities out of band and
-- grants only the required NOLOGIN capability role.
--
-- Isolation model: one schema = one company+environment contour.
-- RLS is used as defense-in-depth for raw transcript/mapping tables; it is not
-- a substitute for separate schema/credentials between companies/environments.

begin;

do $guard$
declare
  v_missing text;
  v_role text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'shablon_analiz_telefonnyh_peregovorov'
  ) then
    raise exception 'DB-07 requires schema shablon_analiz_telefonnyh_peregovorov';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('calls'),
      ('operations'),
      ('raw_transcripts'),
      ('pseudonym_mappings'),
      ('knowledge_publications'),
      ('analysis_versions'),
      ('business_confirmations'),
      ('audit_events'),
      ('v_dashboard_zvonki'),
      ('v_runtime_knowledge_fragments')
  ) as required(required_relation)
  where to_regclass('shablon_analiz_telefonnyh_peregovorov.' || required.required_relation) is null;

  if v_missing is not null then
    raise exception 'DB-07 requires DB-01..DB-06. Missing: %', v_missing;
  end if;

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
    if exists (select 1 from pg_roles where rolname = v_role) then
      raise exception 'DB-07 refuses to run because role % already exists', v_role;
    end if;
  end loop;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
      and c.relname in (
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
  ) then
    raise exception 'DB-07 refuses to run because one or more DB-07 views already exist';
  end if;
end
$guard$;

create role shablon_analiz_telefonnyh_peregovorov_orchestrator
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role shablon_analiz_telefonnyh_peregovorov_core
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role shablon_analiz_telefonnyh_peregovorov_privacy
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role shablon_analiz_telefonnyh_peregovorov_knowledge_reader
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role shablon_analiz_telefonnyh_peregovorov_knowledge_admin
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role shablon_analiz_telefonnyh_peregovorov_dashboard
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role shablon_analiz_telefonnyh_peregovorov_admin_api
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role shablon_analiz_telefonnyh_peregovorov_monitor
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

-- PUBLIC must not acquire access just because a function/table has permissive
-- PostgreSQL defaults. Existing application capability roles are granted below.
revoke all on schema shablon_analiz_telefonnyh_peregovorov from public;
revoke all on all tables in schema shablon_analiz_telefonnyh_peregovorov from public;
revoke all on all sequences in schema shablon_analiz_telefonnyh_peregovorov from public;
revoke execute on all functions in schema shablon_analiz_telefonnyh_peregovorov from public;

alter default privileges in schema shablon_analiz_telefonnyh_peregovorov
  revoke all on tables from public;
alter default privileges in schema shablon_analiz_telefonnyh_peregovorov
  revoke all on sequences from public;
alter default privileges in schema shablon_analiz_telefonnyh_peregovorov
  revoke execute on functions from public;

grant usage on schema shablon_analiz_telefonnyh_peregovorov to
  shablon_analiz_telefonnyh_peregovorov_orchestrator,
  shablon_analiz_telefonnyh_peregovorov_core,
  shablon_analiz_telefonnyh_peregovorov_privacy,
  shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader,
  shablon_analiz_telefonnyh_peregovorov_knowledge_reader,
  shablon_analiz_telefonnyh_peregovorov_knowledge_admin,
  shablon_analiz_telefonnyh_peregovorov_dashboard,
  shablon_analiz_telefonnyh_peregovorov_admin_api,
  shablon_analiz_telefonnyh_peregovorov_monitor;

-- Runtime configuration surfaces: draft/invalid configuration is not visible
-- to the runtime roles.
create view shablon_analiz_telefonnyh_peregovorov.v_runtime_prompt_active
with (security_barrier = true) as
select
  p.prompt_version_id,
  p.family_ref,
  p.version_no,
  p.prompt_text,
  p.content_sha256,
  p.activated_at
from shablon_analiz_telefonnyh_peregovorov.prompt_versions p
where p.config_state = 'active'
  and p.validation_status = 'passed';

create view shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_active
with (security_barrier = true) as
select
  m.methodology_version_id,
  m.family_ref,
  m.version_no,
  m.title,
  m.scoring_config,
  m.result_rules,
  m.content_sha256,
  m.activated_at
from shablon_analiz_telefonnyh_peregovorov.methodology_versions m
where m.config_state = 'active'
  and m.validation_status = 'passed';

create view shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_criteria_active
with (security_barrier = true) as
select
  m.methodology_version_id,
  m.family_ref,
  m.version_no,
  c.criterion_code,
  c.display_name,
  c.weight,
  c.applicability_rule,
  c.sort_order
from shablon_analiz_telefonnyh_peregovorov.methodology_versions m
join shablon_analiz_telefonnyh_peregovorov.methodology_criteria c
  on c.methodology_version_id = m.methodology_version_id
where m.config_state = 'active'
  and m.validation_status = 'passed';

create view shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_stages_active
with (security_barrier = true) as
select
  m.methodology_version_id,
  m.family_ref,
  m.version_no,
  s.stage_code,
  s.display_name,
  s.required,
  s.applicability_rule,
  s.sort_order
from shablon_analiz_telefonnyh_peregovorov.methodology_versions m
join shablon_analiz_telefonnyh_peregovorov.methodology_stages s
  on s.methodology_version_id = m.methodology_version_id
where m.config_state = 'active'
  and m.validation_status = 'passed';

create view shablon_analiz_telefonnyh_peregovorov.v_runtime_filter_rules_active
with (security_barrier = true) as
select
  f.filter_rule_version_ref,
  f.family_ref,
  f.version_no,
  f.rules_json,
  f.content_sha256,
  f.activated_at
from shablon_analiz_telefonnyh_peregovorov.filter_rule_versions f
where f.config_state = 'active'
  and f.validation_status = 'passed';

-- Product reader is physically fixed to call_analysis and never gets SELECT on
-- the raw all-products runtime knowledge view or draft knowledge tables.
create view shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_call_analysis
with (security_barrier = true) as
select
  k.publication_id,
  k.publication_family_ref,
  k.publication_version_no,
  k.product_code,
  k.document_id,
  k.document_code,
  k.document_version_id,
  k.fragment_id,
  k.fragment_family_key,
  k.fragment_version_no,
  k.fragment_order,
  k.fragment_text,
  k.fragment_sha256,
  k.requires_embedding,
  k.embedding_id,
  k.embedding_provider,
  k.embedding_model,
  k.embedding_model_version,
  k.embedding_config_version,
  k.embedding_dimensions,
  k.vector_data
from shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_fragments k
where k.product_code = 'call_analysis';

-- Dashboard-safe exact analysis provenance; raw model payload/config and raw
-- transcript text are intentionally not exposed.
create view shablon_analiz_telefonnyh_peregovorov.v_dashboard_analysis_provenance
with (security_barrier = true) as
select
  a.analysis_id,
  a.call_id,
  a.version_no,
  a.raw_transcript_id,
  a.role_assignment_version_id,
  a.pseudonymized_transcript_id,
  a.privacy_package_id,
  a.processing_quality_id,
  a.prompt_version_id,
  a.methodology_version_id,
  a.knowledge_publication_id,
  a.model_provider,
  a.model_name,
  a.model_config_version,
  a.analysis_contract_version,
  a.core_version,
  a.validator_version,
  a.input_manifest_sha256,
  a.llm_response_sha256,
  a.overall_score,
  a.reliability,
  a.evidence_gate_status,
  a.analysis_state,
  a.created_at,
  a.validated_at,
  a.current_at
from shablon_analiz_telefonnyh_peregovorov.analysis_versions a;

-- Dashboard transcript surface is restricted to segments in a privacy-passed
-- package. Raw text, raw segment text and reverse mapping are never exposed.
create view shablon_analiz_telefonnyh_peregovorov.v_dashboard_safe_transcript_segments
with (security_barrier = true) as
select
  pp.call_id,
  pp.privacy_package_id,
  pp.pseudonymized_transcript_id,
  pp.version_no as privacy_package_version_no,
  pp.version_state as privacy_package_version_state,
  pps.package_order,
  ps.pseudonymized_segment_id,
  ps.segment_key,
  ps.segment_order,
  ps.start_ms,
  ps.end_ms,
  ps.speaker_label,
  ps.business_role,
  ps.pseudonymized_text,
  ps.content_sha256 as pseudonymized_segment_sha256,
  ps.text_deleted_at
from shablon_analiz_telefonnyh_peregovorov.privacy_packages pp
join shablon_analiz_telefonnyh_peregovorov.privacy_package_segments pps
  on pps.privacy_package_id = pp.privacy_package_id
 and pps.pseudonymized_transcript_id = pp.pseudonymized_transcript_id
 and pps.call_id = pp.call_id
join shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments ps
  on ps.pseudonymized_segment_id = pps.pseudonymized_segment_id
 and ps.pseudonymized_transcript_id = pps.pseudonymized_transcript_id
 and ps.call_id = pps.call_id
where pp.privacy_status = 'passed'
  and pp.version_state <> 'invalidated';

create view shablon_analiz_telefonnyh_peregovorov.v_dashboard_evidence_conversation
with (security_barrier = true) as
select
  ecr.analysis_id,
  ecr.evidence_id,
  ecr.conversation_ref_id,
  ecr.privacy_package_id,
  ecr.pseudonymized_segment_id,
  ecr.ref_order,
  ecr.start_ms,
  ecr.end_ms,
  ecr.business_role,
  ecr.quote_snapshot,
  ecr.quote_sha256,
  s.call_id,
  s.segment_key,
  s.segment_order,
  s.pseudonymized_text,
  s.pseudonymized_segment_sha256
from shablon_analiz_telefonnyh_peregovorov.evidence_conversation_refs ecr
join shablon_analiz_telefonnyh_peregovorov.v_dashboard_safe_transcript_segments s
  on s.privacy_package_id = ecr.privacy_package_id
 and s.pseudonymized_segment_id = ecr.pseudonymized_segment_id;

create view shablon_analiz_telefonnyh_peregovorov.v_dashboard_evidence_absence
with (security_barrier = true) as
select
  eac.analysis_id,
  a.call_id,
  eac.evidence_id,
  eac.privacy_package_id,
  eac.methodology_version_id,
  eac.processing_quality_id,
  eac.scope_kind,
  eac.stage_code,
  eac.start_ms,
  eac.end_ms,
  eac.coverage_sufficient,
  eac.result_absent,
  eac.checked_rule_code,
  eac.notes
from shablon_analiz_telefonnyh_peregovorov.evidence_absence_checks eac
join shablon_analiz_telefonnyh_peregovorov.analysis_versions a
  on a.analysis_id = eac.analysis_id
join shablon_analiz_telefonnyh_peregovorov.privacy_packages pp
  on pp.privacy_package_id = eac.privacy_package_id
where pp.privacy_status = 'passed';

-- Knowledge text visible to dashboard only when it was an exact input/evidence
-- of a concrete analysis.
create view shablon_analiz_telefonnyh_peregovorov.v_dashboard_knowledge_evidence
with (security_barrier = true) as
select
  ek.knowledge_ref_id,
  ek.evidence_id,
  ek.analysis_id,
  ai.knowledge_publication_id,
  ai.fragment_id,
  f.document_version_id,
  dv.document_id,
  d.stable_code as document_code,
  dv.version_no as document_version_no,
  f.fragment_family_key,
  f.fragment_version_no,
  f.fragment_order,
  f.fragment_text,
  ek.excerpt_snapshot
from shablon_analiz_telefonnyh_peregovorov.evidence_knowledge_refs ek
join shablon_analiz_telefonnyh_peregovorov.analysis_knowledge_inputs ai
  on ai.analysis_id = ek.analysis_id
 and ai.fragment_id = ek.fragment_id
join shablon_analiz_telefonnyh_peregovorov.knowledge_fragments f
  on f.fragment_id = ai.fragment_id
join shablon_analiz_telefonnyh_peregovorov.knowledge_document_versions dv
  on dv.document_version_id = f.document_version_id
join shablon_analiz_telefonnyh_peregovorov.knowledge_documents d
  on d.document_id = dv.document_id;

create view shablon_analiz_telefonnyh_peregovorov.v_dashboard_corrections_safe
with (security_barrier = true) as
select
  correction_id,
  call_id,
  target_type,
  target_manager_id,
  target_role_assignment_version_id,
  target_transcript_id,
  target_analysis_id,
  target_business_confirmation_id,
  target_callback_link_id,
  target_outgoing_action_id,
  before_ref,
  after_ref,
  actor_ref,
  reason,
  correction_state,
  source_dispute_id,
  apply_operation_id,
  applied_at,
  created_at
from shablon_analiz_telefonnyh_peregovorov.corrections;

create view shablon_analiz_telefonnyh_peregovorov.v_dashboard_disputes_safe
with (security_barrier = true) as
select
  dispute_id,
  call_id,
  analysis_id,
  claim_id,
  evidence_id,
  author_ref,
  reason,
  dispute_state,
  resolution_reason,
  resolved_by_ref,
  opened_at,
  resolved_at,
  created_at
from shablon_analiz_telefonnyh_peregovorov.analysis_disputes;

create view shablon_analiz_telefonnyh_peregovorov.v_dashboard_feedback_safe
with (security_barrier = true) as
select
  oa.outgoing_action_id,
  oa.call_id,
  oa.analysis_id,
  oa.purpose_code,
  oa.message_version,
  oa.message_body,
  oa.message_sha256,
  oa.action_state,
  d.delivery_state,
  d.provider_status,
  d.outcome_state,
  d.reconciliation_state,
  d.delivered_at,
  oa.created_at
from shablon_analiz_telefonnyh_peregovorov.outgoing_actions oa
left join shablon_analiz_telefonnyh_peregovorov.v_dashboard_delivery_current d
  on d.outgoing_action_id = oa.outgoing_action_id;

create view shablon_analiz_telefonnyh_peregovorov.v_admin_audit_safe
with (security_barrier = true) as
select
  audit_event_id,
  scope_ref,
  environment_ref,
  actor_ref,
  actor_capability,
  action_type,
  target_type,
  target_ref,
  before_ref,
  after_ref,
  reason,
  operation_id,
  result,
  error_code,
  source_channel,
  requested_at,
  result_at,
  created_at
from shablon_analiz_telefonnyh_peregovorov.audit_events;

-- Monitoring views deliberately omit transcript/message content, external
-- recipient data, local file path and operation input payload.
create view shablon_analiz_telefonnyh_peregovorov.v_monitor_operations
with (security_barrier = true) as
select
  o.operation_id,
  o.call_id,
  o.operation_type,
  o.decision,
  o.operation_state,
  o.error_class,
  o.error_code,
  o.requested_at,
  o.completed_at,
  o.updated_at,
  count(a.attempt_id)::bigint as attempt_count,
  max(a.requested_at) as last_attempt_at
from shablon_analiz_telefonnyh_peregovorov.operations o
left join shablon_analiz_telefonnyh_peregovorov.operation_attempts a
  on a.operation_id = o.operation_id
group by
  o.operation_id,
  o.call_id,
  o.operation_type,
  o.decision,
  o.operation_state,
  o.error_class,
  o.error_code,
  o.requested_at,
  o.completed_at,
  o.updated_at;

create view shablon_analiz_telefonnyh_peregovorov.v_monitor_audio_cleanup
with (security_barrier = true) as
select
  audio_artifact_id,
  call_id,
  acquisition_state,
  size_bytes,
  duration_ms,
  created_at,
  delete_after,
  deleted_at,
  deletion_confirmed_at,
  cleanup_state,
  cleanup_error_code
from shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts;

create view shablon_analiz_telefonnyh_peregovorov.v_monitor_delivery
with (security_barrier = true) as
select
  outgoing_action_id,
  call_id,
  analysis_id,
  purpose_code,
  delivery_state,
  provider_status,
  outcome_state,
  reconciliation_state,
  delivered_at,
  error_class,
  error_code,
  action_created_at
from shablon_analiz_telefonnyh_peregovorov.v_dashboard_delivery_current;

-- Sensitive content gets defense-in-depth row policies. Because shablon_analiz_telefonnyh_peregovorov is one
-- contour, these policies are role gates, not tenant predicates.
alter table shablon_analiz_telefonnyh_peregovorov.raw_transcripts enable row level security;
alter table shablon_analiz_telefonnyh_peregovorov.transcript_segments enable row level security;
alter table shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings enable row level security;

create policy raw_transcripts_privacy_all
on shablon_analiz_telefonnyh_peregovorov.raw_transcripts
for all
to shablon_analiz_telefonnyh_peregovorov_privacy
using (true)
with check (true);

create policy raw_transcripts_reader_select
on shablon_analiz_telefonnyh_peregovorov.raw_transcripts
for select
to shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader
using (true);

create policy transcript_segments_privacy_all
on shablon_analiz_telefonnyh_peregovorov.transcript_segments
for all
to shablon_analiz_telefonnyh_peregovorov_privacy
using (true)
with check (true);

create policy transcript_segments_reader_select
on shablon_analiz_telefonnyh_peregovorov.transcript_segments
for select
to shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader
using (true);

create policy pseudonym_mappings_privacy_all
on shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings
for all
to shablon_analiz_telefonnyh_peregovorov_privacy
using (true)
with check (true);

-- Orchestrator: operational state + safe pipeline outputs, no raw/mapping and
-- no direct knowledge/config administration.
grant select, insert, update on
  shablon_analiz_telefonnyh_peregovorov.managers,
  shablon_analiz_telefonnyh_peregovorov.calls,
  shablon_analiz_telefonnyh_peregovorov.call_events,
  shablon_analiz_telefonnyh_peregovorov.operations,
  shablon_analiz_telefonnyh_peregovorov.operation_attempts,
  shablon_analiz_telefonnyh_peregovorov.filter_decisions,
  shablon_analiz_telefonnyh_peregovorov.call_links,
  shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts
to shablon_analiz_telefonnyh_peregovorov_orchestrator;

grant select on
  shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts,
  shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments,
  shablon_analiz_telefonnyh_peregovorov.privacy_packages,
  shablon_analiz_telefonnyh_peregovorov.privacy_package_segments,
  shablon_analiz_telefonnyh_peregovorov.processing_quality,
  shablon_analiz_telefonnyh_peregovorov.speech_metrics,
  shablon_analiz_telefonnyh_peregovorov.analysis_versions,
  shablon_analiz_telefonnyh_peregovorov.analysis_knowledge_inputs,
  shablon_analiz_telefonnyh_peregovorov.analysis_claims,
  shablon_analiz_telefonnyh_peregovorov.criterion_scores,
  shablon_analiz_telefonnyh_peregovorov.stage_results,
  shablon_analiz_telefonnyh_peregovorov.analysis_observations,
  shablon_analiz_telefonnyh_peregovorov.ai_inferred_outcomes,
  shablon_analiz_telefonnyh_peregovorov.evidence_sets,
  shablon_analiz_telefonnyh_peregovorov.evidence_conversation_refs,
  shablon_analiz_telefonnyh_peregovorov.evidence_knowledge_refs,
  shablon_analiz_telefonnyh_peregovorov.evidence_absence_checks,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_filter_rules_active
to shablon_analiz_telefonnyh_peregovorov_orchestrator;

grant select, insert on
  shablon_analiz_telefonnyh_peregovorov.business_confirmations
to shablon_analiz_telefonnyh_peregovorov_orchestrator;

grant select, insert, update on
  shablon_analiz_telefonnyh_peregovorov.callback_links,
  shablon_analiz_telefonnyh_peregovorov.outgoing_actions,
  shablon_analiz_telefonnyh_peregovorov.delivery_attempts
to shablon_analiz_telefonnyh_peregovorov_orchestrator;

grant insert on shablon_analiz_telefonnyh_peregovorov.audit_events to shablon_analiz_telefonnyh_peregovorov_orchestrator;

-- CORE: safe privacy package + active config/knowledge + analysis/evidence.
grant select on
  shablon_analiz_telefonnyh_peregovorov.calls,
  shablon_analiz_telefonnyh_peregovorov.managers,
  shablon_analiz_telefonnyh_peregovorov.operations,
  shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts,
  shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments,
  shablon_analiz_telefonnyh_peregovorov.privacy_packages,
  shablon_analiz_telefonnyh_peregovorov.privacy_package_segments,
  shablon_analiz_telefonnyh_peregovorov.processing_quality,
  shablon_analiz_telefonnyh_peregovorov.speech_metrics,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_prompt_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_criteria_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_stages_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_call_analysis
to shablon_analiz_telefonnyh_peregovorov_core;

grant select, insert, update on
  shablon_analiz_telefonnyh_peregovorov.analysis_versions,
  shablon_analiz_telefonnyh_peregovorov.analysis_knowledge_inputs,
  shablon_analiz_telefonnyh_peregovorov.analysis_claims,
  shablon_analiz_telefonnyh_peregovorov.criterion_scores,
  shablon_analiz_telefonnyh_peregovorov.stage_results,
  shablon_analiz_telefonnyh_peregovorov.analysis_observations,
  shablon_analiz_telefonnyh_peregovorov.ai_inferred_outcomes,
  shablon_analiz_telefonnyh_peregovorov.evidence_sets,
  shablon_analiz_telefonnyh_peregovorov.evidence_conversation_refs,
  shablon_analiz_telefonnyh_peregovorov.evidence_knowledge_refs,
  shablon_analiz_telefonnyh_peregovorov.evidence_absence_checks
to shablon_analiz_telefonnyh_peregovorov_core;

-- Two ordinary functions are called from the analysis transition/evidence gate.
grant execute on function
  shablon_analiz_telefonnyh_peregovorov.calculate_analysis_overall_score(uuid),
  shablon_analiz_telefonnyh_peregovorov.validate_analysis_evidence_gate(uuid)
to shablon_analiz_telefonnyh_peregovorov_core;

-- Privacy/local processing: raw text/mapping is intentionally isolated here.
grant select on
  shablon_analiz_telefonnyh_peregovorov.calls,
  shablon_analiz_telefonnyh_peregovorov.managers,
  shablon_analiz_telefonnyh_peregovorov.operations,
  shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts
to shablon_analiz_telefonnyh_peregovorov_privacy;

grant select, insert, update on
  shablon_analiz_telefonnyh_peregovorov.raw_transcripts,
  shablon_analiz_telefonnyh_peregovorov.transcript_segments,
  shablon_analiz_telefonnyh_peregovorov.role_assignment_versions,
  shablon_analiz_telefonnyh_peregovorov.role_assignments,
  shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts,
  shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments,
  shablon_analiz_telefonnyh_peregovorov.privacy_packages,
  shablon_analiz_telefonnyh_peregovorov.privacy_package_segments,
  shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings,
  shablon_analiz_telefonnyh_peregovorov.processing_quality,
  shablon_analiz_telefonnyh_peregovorov.speech_metrics
to shablon_analiz_telefonnyh_peregovorov_privacy;

-- Optional separately-authorized raw transcript read capability: raw transcript
-- but still no pseudonym mapping.
grant select on
  shablon_analiz_telefonnyh_peregovorov.raw_transcripts,
  shablon_analiz_telefonnyh_peregovorov.transcript_segments
to shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader;

-- Product knowledge reader sees exactly one published product scope.
grant select on shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_call_analysis
to shablon_analiz_telefonnyh_peregovorov_knowledge_reader;

-- Knowledge/config administration is a separate privileged capability and is
-- never used as a normal runtime reader.
grant select, insert, update on
  shablon_analiz_telefonnyh_peregovorov.prompt_versions,
  shablon_analiz_telefonnyh_peregovorov.methodology_versions,
  shablon_analiz_telefonnyh_peregovorov.methodology_criteria,
  shablon_analiz_telefonnyh_peregovorov.methodology_stages,
  shablon_analiz_telefonnyh_peregovorov.filter_rule_versions,
  shablon_analiz_telefonnyh_peregovorov.knowledge_documents,
  shablon_analiz_telefonnyh_peregovorov.knowledge_document_versions,
  shablon_analiz_telefonnyh_peregovorov.knowledge_fragments,
  shablon_analiz_telefonnyh_peregovorov.knowledge_embeddings,
  shablon_analiz_telefonnyh_peregovorov.knowledge_publications,
  shablon_analiz_telefonnyh_peregovorov.knowledge_publication_documents,
  shablon_analiz_telefonnyh_peregovorov.knowledge_publication_fragments,
  shablon_analiz_telefonnyh_peregovorov.knowledge_publication_fragment_products
to shablon_analiz_telefonnyh_peregovorov_knowledge_admin;

grant select on
  shablon_analiz_telefonnyh_peregovorov.v_runtime_prompt_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_criteria_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_methodology_stages_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_filter_rules_active,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_fragments,
  shablon_analiz_telefonnyh_peregovorov.v_runtime_knowledge_call_analysis,
  shablon_analiz_telefonnyh_peregovorov.v_admin_audit_safe
to shablon_analiz_telefonnyh_peregovorov_knowledge_admin;

grant insert on shablon_analiz_telefonnyh_peregovorov.audit_events
to shablon_analiz_telefonnyh_peregovorov_knowledge_admin;

-- Dashboard server surfaces. It can read pseudonymized conversation/evidence,
-- never raw transcript or mapping.
grant select on
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_business_confirmations_current,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_delivery_current,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_processing_quality_current,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_speech_metrics_current,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_zvonki,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_obshchaya_kartina,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_menedzhery,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_kriterii,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_etapy,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_oshibki,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_rezultaty,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_kachestvo,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_analysis_provenance,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_safe_transcript_segments,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_evidence_conversation,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_evidence_absence,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_knowledge_evidence,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_corrections_safe,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_disputes_safe,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_feedback_safe
to shablon_analiz_telefonnyh_peregovorov_dashboard;

grant execute on function
  shablon_analiz_telefonnyh_peregovorov.dashboard_filter_call_ids(timestamptz, timestamptz, jsonb),
  shablon_analiz_telefonnyh_peregovorov.dashboard_overview(
    timestamptz, timestamptz, jsonb, timestamptz, interval, text[], text[]
  ),
  shablon_analiz_telefonnyh_peregovorov.dashboard_manager_metrics(
    timestamptz, timestamptz, jsonb, text[], text[]
  ),
  shablon_analiz_telefonnyh_peregovorov.dashboard_criterion_metrics(timestamptz, timestamptz, jsonb),
  shablon_analiz_telefonnyh_peregovorov.dashboard_stage_metrics(timestamptz, timestamptz, jsonb),
  shablon_analiz_telefonnyh_peregovorov.dashboard_observation_metrics(timestamptz, timestamptz, jsonb),
  shablon_analiz_telefonnyh_peregovorov.dashboard_result_metrics(timestamptz, timestamptz, jsonb)
to shablon_analiz_telefonnyh_peregovorov_dashboard;

-- Controlled admin operations. These functions create proposals/requests and
-- their audit records; they do not apply a correction or edit an analysis.
create function shablon_analiz_telefonnyh_peregovorov.admin_submit_analysis_dispute(
  p_call_id uuid,
  p_analysis_id uuid,
  p_claim_id uuid,
  p_evidence_id uuid,
  p_actor_ref text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, shablon_analiz_telefonnyh_peregovorov
as $function$
declare
  v_dispute_id uuid;
begin
  if p_actor_ref is null or btrim(p_actor_ref) = ''
     or p_reason is null or btrim(p_reason) = ''
  then
    raise exception 'Dispute actor/reason must be provided';
  end if;

  insert into shablon_analiz_telefonnyh_peregovorov.analysis_disputes (
    call_id,
    analysis_id,
    claim_id,
    evidence_id,
    author_ref,
    reason
  )
  values (
    p_call_id,
    p_analysis_id,
    p_claim_id,
    p_evidence_id,
    p_actor_ref,
    p_reason
  )
  returning dispute_id into v_dispute_id;

  insert into shablon_analiz_telefonnyh_peregovorov.audit_events (
    actor_ref,
    actor_capability,
    action_type,
    target_type,
    target_ref,
    reason,
    result,
    source_channel,
    safe_details,
    result_at
  )
  values (
    p_actor_ref,
    'dispute_analysis',
    'analysis_dispute.create',
    'analysis',
    p_analysis_id::text,
    p_reason,
    'success',
    'admin_api',
    jsonb_build_object(
      'dispute_id', v_dispute_id,
      'db_session_user', session_user
    ),
    clock_timestamp()
  );

  return v_dispute_id;
end
$function$;

create function shablon_analiz_telefonnyh_peregovorov.admin_propose_correction(
  p_call_id uuid,
  p_target_type shablon_analiz_telefonnyh_peregovorov.correction_target_type,
  p_target_id uuid,
  p_before_ref text,
  p_after_ref text,
  p_before_value jsonb,
  p_after_value jsonb,
  p_actor_ref text,
  p_reason text,
  p_source_dispute_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, shablon_analiz_telefonnyh_peregovorov
as $function$
declare
  v_correction_id uuid;
begin
  if p_target_id is null then
    raise exception 'Correction target ID must be provided';
  end if;

  if p_actor_ref is null or btrim(p_actor_ref) = ''
     or p_reason is null or btrim(p_reason) = ''
  then
    raise exception 'Correction actor/reason must be provided';
  end if;

  insert into shablon_analiz_telefonnyh_peregovorov.corrections (
    call_id,
    target_type,
    target_manager_id,
    target_role_assignment_version_id,
    target_transcript_id,
    target_analysis_id,
    target_business_confirmation_id,
    target_callback_link_id,
    target_outgoing_action_id,
    before_ref,
    after_ref,
    before_value,
    after_value,
    actor_ref,
    reason,
    source_dispute_id
  )
  values (
    p_call_id,
    p_target_type,
    case when p_target_type = 'manager' then p_target_id end,
    case when p_target_type = 'role_assignment' then p_target_id end,
    case when p_target_type = 'transcript' then p_target_id end,
    case when p_target_type = 'analysis' then p_target_id end,
    case when p_target_type = 'business_confirmation' then p_target_id end,
    case when p_target_type = 'callback_link' then p_target_id end,
    case when p_target_type = 'outgoing_action' then p_target_id end,
    p_before_ref,
    p_after_ref,
    p_before_value,
    p_after_value,
    p_actor_ref,
    p_reason,
    p_source_dispute_id
  )
  returning correction_id into v_correction_id;

  insert into shablon_analiz_telefonnyh_peregovorov.audit_events (
    actor_ref,
    actor_capability,
    action_type,
    target_type,
    target_ref,
    before_ref,
    after_ref,
    reason,
    result,
    source_channel,
    safe_details,
    result_at
  )
  values (
    p_actor_ref,
    'propose_correction',
    'correction.propose',
    p_target_type::text,
    p_target_id::text,
    p_before_ref,
    p_after_ref,
    p_reason,
    'success',
    'admin_api',
    jsonb_build_object(
      'correction_id', v_correction_id,
      'db_session_user', session_user
    ),
    clock_timestamp()
  );

  return v_correction_id;
end
$function$;

-- Admin API receives the same safe read surfaces as dashboard plus safe audit.
grant select on
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_business_confirmations_current,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_delivery_current,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_zvonki,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_obshchaya_kartina,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_kriterii,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_etapy,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_oshibki,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_rezultaty,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_kachestvo,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_analysis_provenance,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_safe_transcript_segments,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_evidence_conversation,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_evidence_absence,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_knowledge_evidence,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_corrections_safe,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_disputes_safe,
  shablon_analiz_telefonnyh_peregovorov.v_dashboard_feedback_safe,
  shablon_analiz_telefonnyh_peregovorov.v_admin_audit_safe
to shablon_analiz_telefonnyh_peregovorov_admin_api;

grant execute on function
  shablon_analiz_telefonnyh_peregovorov.admin_submit_analysis_dispute(uuid, uuid, uuid, uuid, text, text),
  shablon_analiz_telefonnyh_peregovorov.admin_propose_correction(
    uuid, shablon_analiz_telefonnyh_peregovorov.correction_target_type, uuid, text, text, jsonb, jsonb, text, text, uuid
  )
to shablon_analiz_telefonnyh_peregovorov_admin_api;

-- Monitoring receives content-minimized technical surfaces only.
grant select on
  shablon_analiz_telefonnyh_peregovorov.v_monitor_operations,
  shablon_analiz_telefonnyh_peregovorov.v_monitor_audio_cleanup,
  shablon_analiz_telefonnyh_peregovorov.v_monitor_delivery
to shablon_analiz_telefonnyh_peregovorov_monitor;

-- Explicitly keep sensitive/security-definer functions away from PUBLIC.
revoke execute on function
  shablon_analiz_telefonnyh_peregovorov.admin_submit_analysis_dispute(uuid, uuid, uuid, uuid, text, text),
  shablon_analiz_telefonnyh_peregovorov.admin_propose_correction(
    uuid, shablon_analiz_telefonnyh_peregovorov.correction_target_type, uuid, text, text, jsonb, jsonb, text, text, uuid
  )
from public;

commit;
