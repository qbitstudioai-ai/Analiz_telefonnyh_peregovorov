-- DB-07
-- Test-contour capability roles, restricted runtime surfaces and negative
-- permission boundaries.
-- TEST/LOCAL ONLY. Depends on DB-01..DB-06.
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
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-07 requires schema atp_test';
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
  where to_regclass('atp_test.' || required.required_relation) is null;

  if v_missing is not null then
    raise exception 'DB-07 requires DB-01..DB-06. Missing: %', v_missing;
  end if;

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
    if exists (select 1 from pg_roles where rolname = v_role) then
      raise exception 'DB-07 refuses to run because role % already exists', v_role;
    end if;
  end loop;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname in (
        'v_runtime_prompt_active',
        'v_runtime_methodology_active',
        'v_runtime_methodology_criteria_active',
        'v_runtime_methodology_stages_active',
        'v_runtime_filter_rules_active',
        'v_runtime_knowledge_call_analysis',
        'v_dashboard_analysis_provenance',
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

create role atp_test_orchestrator
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role atp_test_core
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role atp_test_privacy
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role atp_test_raw_transcript_reader
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role atp_test_knowledge_reader
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role atp_test_dashboard
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role atp_test_admin_api
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

create role atp_test_monitor
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;

-- PUBLIC must not acquire access just because a function/table has permissive
-- PostgreSQL defaults. Existing application capability roles are granted below.
revoke all on schema atp_test from public;
revoke all on all tables in schema atp_test from public;
revoke execute on all functions in schema atp_test from public;

grant usage on schema atp_test to
  atp_test_orchestrator,
  atp_test_core,
  atp_test_privacy,
  atp_test_raw_transcript_reader,
  atp_test_knowledge_reader,
  atp_test_dashboard,
  atp_test_admin_api,
  atp_test_monitor;

-- Runtime configuration surfaces: draft/invalid configuration is not visible
-- to the runtime roles.
create view atp_test.v_runtime_prompt_active
with (security_barrier = true) as
select
  p.prompt_version_id,
  p.family_ref,
  p.version_no,
  p.prompt_text,
  p.content_sha256,
  p.activated_at
from atp_test.prompt_versions p
where p.config_state = 'active'
  and p.validation_status = 'passed';

create view atp_test.v_runtime_methodology_active
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
from atp_test.methodology_versions m
where m.config_state = 'active'
  and m.validation_status = 'passed';

create view atp_test.v_runtime_methodology_criteria_active
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
from atp_test.methodology_versions m
join atp_test.methodology_criteria c
  on c.methodology_version_id = m.methodology_version_id
where m.config_state = 'active'
  and m.validation_status = 'passed';

create view atp_test.v_runtime_methodology_stages_active
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
from atp_test.methodology_versions m
join atp_test.methodology_stages s
  on s.methodology_version_id = m.methodology_version_id
where m.config_state = 'active'
  and m.validation_status = 'passed';

create view atp_test.v_runtime_filter_rules_active
with (security_barrier = true) as
select
  f.filter_rule_version_ref,
  f.family_ref,
  f.version_no,
  f.rules_json,
  f.content_sha256,
  f.activated_at
from atp_test.filter_rule_versions f
where f.config_state = 'active'
  and f.validation_status = 'passed';

-- Product reader is physically fixed to call_analysis and never gets SELECT on
-- the raw all-products runtime knowledge view or draft knowledge tables.
create view atp_test.v_runtime_knowledge_call_analysis
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
from atp_test.v_runtime_knowledge_fragments k
where k.product_code = 'call_analysis';

-- Dashboard-safe exact analysis provenance; raw model payload/config and raw
-- transcript text are intentionally not exposed.
create view atp_test.v_dashboard_analysis_provenance
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
from atp_test.analysis_versions a;

-- Knowledge text visible to dashboard only when it was an exact input/evidence
-- of a concrete analysis.
create view atp_test.v_dashboard_knowledge_evidence
with (security_barrier = true) as
select
  ek.evidence_knowledge_ref_id,
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
from atp_test.evidence_knowledge_refs ek
join atp_test.analysis_knowledge_inputs ai
  on ai.analysis_id = ek.analysis_id
 and ai.fragment_id = ek.fragment_id
join atp_test.knowledge_fragments f
  on f.fragment_id = ai.fragment_id
join atp_test.knowledge_document_versions dv
  on dv.document_version_id = f.document_version_id
join atp_test.knowledge_documents d
  on d.document_id = dv.document_id;

create view atp_test.v_dashboard_corrections_safe
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
from atp_test.corrections;

create view atp_test.v_dashboard_disputes_safe
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
from atp_test.analysis_disputes;

create view atp_test.v_dashboard_feedback_safe
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
from atp_test.outgoing_actions oa
left join atp_test.v_dashboard_delivery_current d
  on d.outgoing_action_id = oa.outgoing_action_id;

create view atp_test.v_admin_audit_safe
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
from atp_test.audit_events;

-- Monitoring views deliberately omit transcript/message content, external
-- recipient data, local file path and operation input payload.
create view atp_test.v_monitor_operations
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
from atp_test.operations o
left join atp_test.operation_attempts a
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

create view atp_test.v_monitor_audio_cleanup
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
from atp_test.temporary_audio_artifacts;

create view atp_test.v_monitor_delivery
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
from atp_test.v_dashboard_delivery_current;

-- Sensitive content gets defense-in-depth row policies. Because atp_test is one
-- contour, these policies are role gates, not tenant predicates.
alter table atp_test.raw_transcripts enable row level security;
alter table atp_test.transcript_segments enable row level security;
alter table atp_test.pseudonym_mappings enable row level security;

create policy raw_transcripts_privacy_all
on atp_test.raw_transcripts
for all
to atp_test_privacy
using (true)
with check (true);

create policy raw_transcripts_reader_select
on atp_test.raw_transcripts
for select
to atp_test_raw_transcript_reader
using (true);

create policy transcript_segments_privacy_all
on atp_test.transcript_segments
for all
to atp_test_privacy
using (true)
with check (true);

create policy transcript_segments_reader_select
on atp_test.transcript_segments
for select
to atp_test_raw_transcript_reader
using (true);

create policy pseudonym_mappings_privacy_all
on atp_test.pseudonym_mappings
for all
to atp_test_privacy
using (true)
with check (true);

-- Orchestrator: operational state + safe pipeline outputs, no raw/mapping and
-- no direct knowledge/config administration.
grant select, insert, update on
  atp_test.managers,
  atp_test.calls,
  atp_test.call_events,
  atp_test.operations,
  atp_test.operation_attempts,
  atp_test.filter_decisions,
  atp_test.call_links,
  atp_test.temporary_audio_artifacts
to atp_test_orchestrator;

grant select on
  atp_test.pseudonymized_transcripts,
  atp_test.pseudonymized_segments,
  atp_test.privacy_packages,
  atp_test.privacy_package_segments,
  atp_test.processing_quality,
  atp_test.speech_metrics,
  atp_test.analysis_versions,
  atp_test.analysis_knowledge_inputs,
  atp_test.analysis_claims,
  atp_test.criterion_scores,
  atp_test.stage_results,
  atp_test.analysis_observations,
  atp_test.ai_inferred_outcomes,
  atp_test.evidence_sets,
  atp_test.evidence_conversation_refs,
  atp_test.evidence_knowledge_refs,
  atp_test.evidence_absence_checks,
  atp_test.v_runtime_filter_rules_active
to atp_test_orchestrator;

grant select, insert on
  atp_test.business_confirmations
to atp_test_orchestrator;

grant select, insert, update on
  atp_test.callback_links,
  atp_test.outgoing_actions,
  atp_test.delivery_attempts
to atp_test_orchestrator;

grant insert on atp_test.audit_events to atp_test_orchestrator;

-- CORE: safe privacy package + active config/knowledge + analysis/evidence.
grant select on
  atp_test.calls,
  atp_test.managers,
  atp_test.operations,
  atp_test.pseudonymized_transcripts,
  atp_test.pseudonymized_segments,
  atp_test.privacy_packages,
  atp_test.privacy_package_segments,
  atp_test.processing_quality,
  atp_test.speech_metrics,
  atp_test.v_runtime_prompt_active,
  atp_test.v_runtime_methodology_active,
  atp_test.v_runtime_methodology_criteria_active,
  atp_test.v_runtime_methodology_stages_active,
  atp_test.v_runtime_knowledge_call_analysis
to atp_test_core;

grant select, insert, update on
  atp_test.analysis_versions,
  atp_test.analysis_knowledge_inputs,
  atp_test.analysis_claims,
  atp_test.criterion_scores,
  atp_test.stage_results,
  atp_test.analysis_observations,
  atp_test.ai_inferred_outcomes,
  atp_test.evidence_sets,
  atp_test.evidence_conversation_refs,
  atp_test.evidence_knowledge_refs,
  atp_test.evidence_absence_checks
to atp_test_core;

-- Two ordinary functions are called from the analysis transition/evidence gate.
grant execute on function
  atp_test.calculate_analysis_overall_score(uuid),
  atp_test.validate_analysis_evidence_gate(uuid)
to atp_test_core;

-- Privacy/local processing: raw text/mapping is intentionally isolated here.
grant select on
  atp_test.calls,
  atp_test.managers,
  atp_test.operations,
  atp_test.temporary_audio_artifacts
to atp_test_privacy;

grant select, insert, update on
  atp_test.raw_transcripts,
  atp_test.transcript_segments,
  atp_test.role_assignment_versions,
  atp_test.role_assignments,
  atp_test.pseudonymized_transcripts,
  atp_test.pseudonymized_segments,
  atp_test.privacy_packages,
  atp_test.privacy_package_segments,
  atp_test.pseudonym_mappings,
  atp_test.processing_quality,
  atp_test.speech_metrics
to atp_test_privacy;

-- Optional separately-authorized raw transcript read capability: raw transcript
-- but still no pseudonym mapping.
grant select on
  atp_test.raw_transcripts,
  atp_test.transcript_segments
to atp_test_raw_transcript_reader;

-- Product knowledge reader sees exactly one published product scope.
grant select on atp_test.v_runtime_knowledge_call_analysis
to atp_test_knowledge_reader;

-- Dashboard server surfaces. It can read pseudonymized conversation/evidence,
-- never raw transcript or mapping.
grant select on
  atp_test.v_dashboard_business_confirmations_current,
  atp_test.v_dashboard_delivery_current,
  atp_test.v_dashboard_processing_quality_current,
  atp_test.v_dashboard_speech_metrics_current,
  atp_test.v_dashboard_zvonki,
  atp_test.v_dashboard_obshchaya_kartina,
  atp_test.v_dashboard_menedzhery,
  atp_test.v_dashboard_kriterii,
  atp_test.v_dashboard_etapy,
  atp_test.v_dashboard_oshibki,
  atp_test.v_dashboard_rezultaty,
  atp_test.v_dashboard_kachestvo,
  atp_test.v_dashboard_analysis_provenance,
  atp_test.v_dashboard_knowledge_evidence,
  atp_test.v_dashboard_corrections_safe,
  atp_test.v_dashboard_disputes_safe,
  atp_test.v_dashboard_feedback_safe,
  atp_test.pseudonymized_transcripts,
  atp_test.pseudonymized_segments,
  atp_test.privacy_packages,
  atp_test.privacy_package_segments,
  atp_test.evidence_sets,
  atp_test.evidence_conversation_refs,
  atp_test.evidence_knowledge_refs,
  atp_test.evidence_absence_checks
to atp_test_dashboard;

grant execute on function
  atp_test.dashboard_filter_call_ids(timestamptz, timestamptz, jsonb),
  atp_test.dashboard_overview(
    timestamptz, timestamptz, jsonb, timestamptz, interval, text[], text[]
  ),
  atp_test.dashboard_manager_metrics(
    timestamptz, timestamptz, jsonb, text[], text[]
  ),
  atp_test.dashboard_criterion_metrics(timestamptz, timestamptz, jsonb),
  atp_test.dashboard_stage_metrics(timestamptz, timestamptz, jsonb),
  atp_test.dashboard_observation_metrics(timestamptz, timestamptz, jsonb),
  atp_test.dashboard_result_metrics(timestamptz, timestamptz, jsonb)
to atp_test_dashboard;

-- Controlled admin operations. These functions create proposals/requests and
-- their audit records; they do not apply a correction or edit an analysis.
create function atp_test.admin_submit_analysis_dispute(
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
set search_path = pg_catalog, atp_test
as $function$
declare
  v_dispute_id uuid;
begin
  if p_actor_ref is null or btrim(p_actor_ref) = ''
     or p_reason is null or btrim(p_reason) = ''
  then
    raise exception 'Dispute actor/reason must be provided';
  end if;

  insert into atp_test.analysis_disputes (
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

  insert into atp_test.audit_events (
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

create function atp_test.admin_propose_correction(
  p_call_id uuid,
  p_target_type atp_test.correction_target_type,
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
set search_path = pg_catalog, atp_test
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

  insert into atp_test.corrections (
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

  insert into atp_test.audit_events (
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
  atp_test.v_dashboard_business_confirmations_current,
  atp_test.v_dashboard_delivery_current,
  atp_test.v_dashboard_zvonki,
  atp_test.v_dashboard_obshchaya_kartina,
  atp_test.v_dashboard_kriterii,
  atp_test.v_dashboard_etapy,
  atp_test.v_dashboard_oshibki,
  atp_test.v_dashboard_rezultaty,
  atp_test.v_dashboard_kachestvo,
  atp_test.v_dashboard_analysis_provenance,
  atp_test.v_dashboard_knowledge_evidence,
  atp_test.v_dashboard_corrections_safe,
  atp_test.v_dashboard_disputes_safe,
  atp_test.v_dashboard_feedback_safe,
  atp_test.v_admin_audit_safe
to atp_test_admin_api;

grant execute on function
  atp_test.admin_submit_analysis_dispute(uuid, uuid, uuid, uuid, text, text),
  atp_test.admin_propose_correction(
    uuid, atp_test.correction_target_type, uuid, text, text, jsonb, jsonb, text, text, uuid
  )
to atp_test_admin_api;

-- Monitoring receives content-minimized technical surfaces only.
grant select on
  atp_test.v_monitor_operations,
  atp_test.v_monitor_audio_cleanup,
  atp_test.v_monitor_delivery
to atp_test_monitor;

-- Explicitly keep sensitive/security-definer functions away from PUBLIC.
revoke execute on function
  atp_test.admin_submit_analysis_dispute(uuid, uuid, uuid, uuid, text, text),
  atp_test.admin_propose_correction(
    uuid, atp_test.correction_target_type, uuid, text, text, jsonb, jsonb, text, text, uuid
  )
from public;

commit;
