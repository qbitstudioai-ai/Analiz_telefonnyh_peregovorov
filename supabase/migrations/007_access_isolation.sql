-- DB-07
-- Test-contour capability roles, least-privilege grants and safe read/write boundaries.
-- TEST/LOCAL ONLY. Depends on DB-01..DB-06.
--
-- Isolation decision:
--   one PostgreSQL schema = one company + one environment contour;
--   cross-company/environment isolation is therefore schema + credential based;
--   row-level tenant RLS is intentionally NOT added inside atp_test because
--   there is no tenant discriminator inside one contour. A USING(true) policy
--   would add no security and would create false confidence.
--
-- All roles created here are NOLOGIN capability roles. Real login credentials
-- are created/rotated outside GitHub and must be dedicated to one contour.

begin;

do $guard$
declare
  v_missing text;
  v_existing_roles text;
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
      ('v_dashboard_zvonki')
  ) as required(required_relation)
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname = required.required_relation
      and c.relkind in ('r', 'p', 'v', 'm')
  );

  if v_missing is not null then
    raise exception 'DB-07 requires DB-01..DB-06. Missing: %', v_missing;
  end if;

  select string_agg(rolname, ', ' order by rolname)
  into v_existing_roles
  from pg_roles
  where rolname in (
    'atp_test_orchestrator',
    'atp_test_privacy',
    'atp_test_core',
    'atp_test_knowledge_call_analysis',
    'atp_test_knowledge_admin',
    'atp_test_dashboard',
    'atp_test_correction_operator',
    'atp_test_monitoring'
  );

  if v_existing_roles is not null then
    raise exception
      'DB-07 refuses to run because test capability role(s) already exist: %',
      v_existing_roles;
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname in (
        'v_knowledge_call_analysis_runtime',
        'v_dashboard_safe_transcript_segments',
        'v_dashboard_evidence_conversation',
        'v_dashboard_evidence_knowledge',
        'v_monitoring_calls',
        'v_monitoring_operations'
      )
  ) then
    raise exception 'DB-07 refuses to run because one or more DB-07 views already exist';
  end if;
end
$guard$;

-- Capability roles only. No passwords/login attributes are stored in GitHub.
create role atp_test_orchestrator
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role atp_test_privacy
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role atp_test_core
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role atp_test_knowledge_call_analysis
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role atp_test_knowledge_admin
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role atp_test_dashboard
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role atp_test_correction_operator
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role atp_test_monitoring
  nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;

comment on role atp_test_orchestrator is
  'TEST capability: n8n/orchestration metadata, CRM/callback/outgoing delivery. One contour only.';
comment on role atp_test_privacy is
  'TEST capability: transcription/privacy service. Only runtime role allowed raw transcript and pseudonym reverse mapping.';
comment on role atp_test_core is
  'TEST capability: pseudonymized analysis/evidence processing. No raw transcript or reverse mapping.';
comment on role atp_test_knowledge_call_analysis is
  'TEST capability: read only published product-scoped call-analysis knowledge.';
comment on role atp_test_knowledge_admin is
  'TEST capability: controlled knowledge/config draft-validation-publication administration. No call conversation access.';
comment on role atp_test_dashboard is
  'TEST capability: read-only dashboard views/functions and safe pseudonymized evidence. No direct business-table write.';
comment on role atp_test_correction_operator is
  'TEST capability: controlled dashboard correction/dispute functions. No arbitrary table write.';
comment on role atp_test_monitoring is
  'TEST capability: minimized technical state/error monitoring. No transcript/content access.';

-- Remove accidental ambient access. Existing trigger functions continue to run
-- as triggers; ordinary roles cannot call helper/guard functions directly.
revoke all on schema atp_test from public;
revoke all on all tables in schema atp_test from public;
revoke all on all sequences in schema atp_test from public;
revoke all on all functions in schema atp_test from public;

-- Future objects created by the migration owner must not silently become
-- executable/readable to PUBLIC.
alter default privileges in schema atp_test
  revoke all on tables from public;
alter default privileges in schema atp_test
  revoke all on sequences from public;
alter default privileges in schema atp_test
  revoke execute on functions from public;

grant usage on schema atp_test to
  atp_test_orchestrator,
  atp_test_privacy,
  atp_test_core,
  atp_test_knowledge_call_analysis,
  atp_test_knowledge_admin,
  atp_test_dashboard,
  atp_test_correction_operator,
  atp_test_monitoring;

-- ---------------------------------------------------------------------------
-- Safe read surfaces
-- ---------------------------------------------------------------------------

-- Product-scoped published knowledge. Product readers never receive SELECT on
-- base knowledge tables or the unrestricted internal runtime view.
create view atp_test.v_knowledge_call_analysis_runtime
with (security_barrier = true) as
select
  publication_id,
  publication_family_ref,
  publication_version_no,
  product_code,
  document_id,
  document_code,
  document_version_id,
  fragment_id,
  fragment_family_key,
  fragment_version_no,
  fragment_order,
  fragment_text,
  fragment_sha256,
  requires_embedding,
  embedding_id,
  embedding_provider,
  embedding_model,
  embedding_model_version,
  embedding_config_version,
  embedding_dimensions,
  vector_data
from atp_test.v_runtime_knowledge_fragments
where product_code = 'call_analysis';

comment on view atp_test.v_knowledge_call_analysis_runtime is
  'Published/current knowledge restricted to product_code=call_analysis. Direct base-knowledge access is not required.';

-- Dashboard transcript surface contains only segments that passed privacy gate
-- and were included in a real privacy package. No raw text/mapping is exposed.
create view atp_test.v_dashboard_safe_transcript_segments
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
from atp_test.privacy_packages pp
join atp_test.privacy_package_segments pps
  on pps.privacy_package_id = pp.privacy_package_id
 and pps.pseudonymized_transcript_id = pp.pseudonymized_transcript_id
 and pps.call_id = pp.call_id
join atp_test.pseudonymized_segments ps
  on ps.pseudonymized_segment_id = pps.pseudonymized_segment_id
 and ps.pseudonymized_transcript_id = pps.pseudonymized_transcript_id
 and ps.call_id = pps.call_id
where pp.privacy_status = 'passed'
  and pp.version_state <> 'invalidated';

create view atp_test.v_dashboard_evidence_conversation
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
from atp_test.evidence_conversation_refs ecr
join atp_test.v_dashboard_safe_transcript_segments s
  on s.privacy_package_id = ecr.privacy_package_id
 and s.pseudonymized_segment_id = ecr.pseudonymized_segment_id;

-- Historical used knowledge is visible only through exact analysis input refs,
-- not by granting the dashboard access to draft/unrelated knowledge tables.
create view atp_test.v_dashboard_evidence_knowledge
with (security_barrier = true) as
select
  ekr.analysis_id,
  ekr.evidence_id,
  ekr.knowledge_ref_id,
  ekr.fragment_id,
  ekr.ref_order,
  ekr.excerpt_snapshot,
  ekr.excerpt_sha256,
  aki.knowledge_publication_id,
  aki.input_order,
  kp.family_ref as publication_family_ref,
  kp.version_no as publication_version_no,
  kf.document_id,
  kd.stable_code as document_code,
  kf.document_version_id,
  kf.fragment_family_key,
  kf.fragment_version_no,
  kf.fragment_order,
  kf.fragment_text,
  kf.content_sha256 as fragment_sha256,
  kf.source_locator
from atp_test.evidence_knowledge_refs ekr
join atp_test.analysis_knowledge_inputs aki
  on aki.analysis_id = ekr.analysis_id
 and aki.fragment_id = ekr.fragment_id
join atp_test.knowledge_publications kp
  on kp.publication_id = aki.knowledge_publication_id
join atp_test.knowledge_fragments kf
  on kf.fragment_id = ekr.fragment_id
join atp_test.knowledge_documents kd
  on kd.document_id = kf.document_id;

-- Monitoring surfaces exclude transcript text, mappings, message bodies,
-- knowledge content and business-result payloads.
create view atp_test.v_monitoring_calls
with (security_barrier = true) as
select
  call_id,
  source_adapter_code,
  started_at,
  ended_at,
  duration_seconds,
  direction,
  answer_status,
  classification,
  processing_state,
  created_at,
  updated_at
from atp_test.calls;

create view atp_test.v_monitoring_operations
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
  count(oa.attempt_id)::bigint as attempt_count,
  max(oa.requested_at) as latest_attempt_at,
  bool_or(oa.attempt_state = 'outcome_unknown') as has_unknown_attempt,
  bool_or(oa.attempt_state = 'failed_retryable') as has_retryable_attempt,
  bool_or(oa.attempt_state = 'failed_requires_fix') as has_requires_fix_attempt
from atp_test.operations o
left join atp_test.operation_attempts oa
  on oa.operation_id = o.operation_id
group by
  o.operation_id,
  o.call_id,
  o.operation_type,
  o.decision,
  o.operation_state,
  o.error_class,
  o.error_code,
  o.requested_at,
  o.completed_at;

-- ---------------------------------------------------------------------------
-- Controlled dashboard-admin write functions
-- ---------------------------------------------------------------------------

create function atp_test.dashboard_open_analysis_dispute(
  p_call_id uuid,
  p_analysis_id uuid,
  p_claim_id uuid default null,
  p_evidence_id uuid default null,
  p_actor_ref text default null,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, atp_test
as $function$
declare
  v_dispute_id uuid;
begin
  if p_actor_ref is null or btrim(p_actor_ref) = '' then
    raise exception 'actor_ref is required';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'reason is required';
  end if;

  if not exists (
    select 1
    from atp_test.analysis_versions a
    where a.analysis_id = p_analysis_id
      and a.call_id = p_call_id
  ) then
    raise exception 'analysis does not belong to call';
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
    after_ref,
    reason,
    result,
    source_channel,
    safe_details,
    result_at
  )
  values (
    p_actor_ref,
    'dispute_analysis',
    'open_analysis_dispute',
    'analysis_dispute',
    v_dispute_id::text,
    p_analysis_id::text,
    p_reason,
    'success',
    'dashboard_api',
    jsonb_build_object(
      'call_id', p_call_id,
      'claim_id', p_claim_id,
      'evidence_id', p_evidence_id
    ),
    clock_timestamp()
  );

  return v_dispute_id;
end
$function$;

create function atp_test.dashboard_propose_correction(
  p_call_id uuid,
  p_target_type text,
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
  if p_actor_ref is null or btrim(p_actor_ref) = '' then
    raise exception 'actor_ref is required';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'reason is required';
  end if;
  if p_target_id is null then
    raise exception 'target_id is required';
  end if;

  case p_target_type
    when 'manager' then
      if not exists (
        select 1
        from atp_test.calls c
        where c.call_id = p_call_id
          and c.manager_id = p_target_id
      ) then
        raise exception 'manager target is not the current manager of call';
      end if;

      insert into atp_test.corrections (
        call_id, target_type, target_manager_id,
        before_ref, after_ref, before_value, after_value,
        actor_ref, reason, source_dispute_id
      )
      values (
        p_call_id, 'manager', p_target_id,
        p_before_ref, p_after_ref, p_before_value, p_after_value,
        p_actor_ref, p_reason, p_source_dispute_id
      )
      returning correction_id into v_correction_id;

    when 'role_assignment' then
      insert into atp_test.corrections (
        call_id, target_type, target_role_assignment_version_id,
        before_ref, after_ref, before_value, after_value,
        actor_ref, reason, source_dispute_id
      )
      values (
        p_call_id, 'role_assignment', p_target_id,
        p_before_ref, p_after_ref, p_before_value, p_after_value,
        p_actor_ref, p_reason, p_source_dispute_id
      )
      returning correction_id into v_correction_id;

    when 'transcript' then
      insert into atp_test.corrections (
        call_id, target_type, target_transcript_id,
        before_ref, after_ref, before_value, after_value,
        actor_ref, reason, source_dispute_id
      )
      values (
        p_call_id, 'transcript', p_target_id,
        p_before_ref, p_after_ref, p_before_value, p_after_value,
        p_actor_ref, p_reason, p_source_dispute_id
      )
      returning correction_id into v_correction_id;

    when 'analysis' then
      insert into atp_test.corrections (
        call_id, target_type, target_analysis_id,
        before_ref, after_ref, before_value, after_value,
        actor_ref, reason, source_dispute_id
      )
      values (
        p_call_id, 'analysis', p_target_id,
        p_before_ref, p_after_ref, p_before_value, p_after_value,
        p_actor_ref, p_reason, p_source_dispute_id
      )
      returning correction_id into v_correction_id;

    when 'business_confirmation' then
      insert into atp_test.corrections (
        call_id, target_type, target_business_confirmation_id,
        before_ref, after_ref, before_value, after_value,
        actor_ref, reason, source_dispute_id
      )
      values (
        p_call_id, 'business_confirmation', p_target_id,
        p_before_ref, p_after_ref, p_before_value, p_after_value,
        p_actor_ref, p_reason, p_source_dispute_id
      )
      returning correction_id into v_correction_id;

    when 'callback_link' then
      insert into atp_test.corrections (
        call_id, target_type, target_callback_link_id,
        before_ref, after_ref, before_value, after_value,
        actor_ref, reason, source_dispute_id
      )
      values (
        p_call_id, 'callback_link', p_target_id,
        p_before_ref, p_after_ref, p_before_value, p_after_value,
        p_actor_ref, p_reason, p_source_dispute_id
      )
      returning correction_id into v_correction_id;

    when 'outgoing_action' then
      insert into atp_test.corrections (
        call_id, target_type, target_outgoing_action_id,
        before_ref, after_ref, before_value, after_value,
        actor_ref, reason, source_dispute_id
      )
      values (
        p_call_id, 'outgoing_action', p_target_id,
        p_before_ref, p_after_ref, p_before_value, p_after_value,
        p_actor_ref, p_reason, p_source_dispute_id
      )
      returning correction_id into v_correction_id;

    else
      raise exception 'unsupported correction target_type: %', p_target_type;
  end case;

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
    'propose_correction',
    p_target_type,
    p_target_id::text,
    p_before_ref,
    p_after_ref,
    p_reason,
    'success',
    'dashboard_api',
    jsonb_build_object(
      'call_id', p_call_id,
      'correction_id', v_correction_id,
      'source_dispute_id', p_source_dispute_id
    ),
    clock_timestamp()
  );

  return v_correction_id;
end
$function$;

create function atp_test.dashboard_resolve_analysis_dispute(
  p_dispute_id uuid,
  p_resolution_state text,
  p_actor_ref text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, atp_test
as $function$
declare
  v_call_id uuid;
  v_analysis_id uuid;
  v_old_state atp_test.dispute_state;
  v_new_state atp_test.dispute_state;
begin
  if p_actor_ref is null or btrim(p_actor_ref) = ''
     or p_reason is null or btrim(p_reason) = ''
  then
    raise exception 'actor_ref and reason are required';
  end if;

  if p_resolution_state not in ('resolved', 'rejected') then
    raise exception 'resolution state must be resolved or rejected';
  end if;

  v_new_state := p_resolution_state::atp_test.dispute_state;

  select call_id, analysis_id, dispute_state
  into v_call_id, v_analysis_id, v_old_state
  from atp_test.analysis_disputes
  where dispute_id = p_dispute_id
  for update;

  if not found then
    raise exception 'dispute not found';
  end if;

  update atp_test.analysis_disputes
  set
    dispute_state = v_new_state,
    resolution_reason = p_reason,
    resolved_by_ref = p_actor_ref,
    resolved_at = clock_timestamp()
  where dispute_id = p_dispute_id;

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
    'resolve_dispute',
    'resolve_analysis_dispute',
    'analysis_dispute',
    p_dispute_id::text,
    v_old_state::text,
    v_new_state::text,
    p_reason,
    'success',
    'dashboard_api',
    jsonb_build_object(
      'call_id', v_call_id,
      'analysis_id', v_analysis_id
    ),
    clock_timestamp()
  );
end
$function$;

create function atp_test.dashboard_finalize_correction(
  p_correction_id uuid,
  p_final_state text,
  p_apply_operation_id uuid,
  p_actor_ref text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, atp_test
as $function$
declare
  v_call_id uuid;
  v_target_type atp_test.correction_target_type;
  v_old_state atp_test.correction_state;
  v_new_state atp_test.correction_state;
begin
  if p_actor_ref is null or btrim(p_actor_ref) = ''
     or p_reason is null or btrim(p_reason) = ''
  then
    raise exception 'actor_ref and reason are required';
  end if;

  if p_final_state not in ('applied', 'rejected') then
    raise exception 'final correction state must be applied or rejected';
  end if;

  if p_final_state = 'applied' and p_apply_operation_id is null then
    raise exception 'applied correction requires apply operation';
  end if;

  if p_final_state = 'rejected' and p_apply_operation_id is not null then
    raise exception 'rejected correction must not claim apply operation';
  end if;

  v_new_state := p_final_state::atp_test.correction_state;

  select call_id, target_type, correction_state
  into v_call_id, v_target_type, v_old_state
  from atp_test.corrections
  where correction_id = p_correction_id
  for update;

  if not found then
    raise exception 'correction not found';
  end if;

  update atp_test.corrections
  set
    correction_state = v_new_state,
    apply_operation_id = case
      when v_new_state = 'applied' then p_apply_operation_id
      else null
    end,
    applied_at = case
      when v_new_state = 'applied' then clock_timestamp()
      else null
    end
  where correction_id = p_correction_id;

  insert into atp_test.audit_events (
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
    source_channel,
    safe_details,
    result_at
  )
  values (
    p_actor_ref,
    'finalize_correction',
    'finalize_correction',
    v_target_type::text,
    p_correction_id::text,
    v_old_state::text,
    v_new_state::text,
    p_reason,
    p_apply_operation_id,
    'success',
    'dashboard_api',
    jsonb_build_object('call_id', v_call_id),
    clock_timestamp()
  );
end
$function$;

-- DB-07 functions are not callable through ambient PUBLIC EXECUTE even if a
-- database restores broader defaults later.
revoke all on function atp_test.dashboard_open_analysis_dispute(
  uuid, uuid, uuid, uuid, text, text
) from public;
revoke all on function atp_test.dashboard_propose_correction(
  uuid, text, uuid, text, text, jsonb, jsonb, text, text, uuid
) from public;
revoke all on function atp_test.dashboard_resolve_analysis_dispute(
  uuid, text, text, text
) from public;
revoke all on function atp_test.dashboard_finalize_correction(
  uuid, text, uuid, text, text
) from public;

-- ---------------------------------------------------------------------------
-- Role grants
-- ---------------------------------------------------------------------------

-- n8n/orchestration: event/operation state, CRM confirmations, callback and
-- outgoing/delivery. No conversation text, reverse mapping or knowledge edit.
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
  atp_test.privacy_packages,
  atp_test.processing_quality,
  atp_test.analysis_versions
to atp_test_orchestrator;

grant select, insert on
  atp_test.business_confirmations
to atp_test_orchestrator;

grant select, insert, update on
  atp_test.callback_links,
  atp_test.outgoing_actions,
  atp_test.delivery_attempts
to atp_test_orchestrator;

-- Privacy/transcription: the ONLY ordinary runtime capability with raw
-- transcript and reverse-mapping access.
grant select on
  atp_test.managers,
  atp_test.calls,
  atp_test.temporary_audio_artifacts
to atp_test_privacy;

grant select, insert, update on
  atp_test.operations,
  atp_test.operation_attempts,
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

-- CORE analysis: safe/pseudonymized inputs + exact published knowledge +
-- analysis/evidence writes. No raw transcript or mapping.
grant select on
  atp_test.calls,
  atp_test.managers,
  atp_test.pseudonymized_transcripts,
  atp_test.pseudonymized_segments,
  atp_test.privacy_packages,
  atp_test.privacy_package_segments,
  atp_test.processing_quality,
  atp_test.speech_metrics,
  atp_test.prompt_versions,
  atp_test.methodology_versions,
  atp_test.methodology_criteria,
  atp_test.methodology_stages,
  atp_test.v_knowledge_call_analysis_runtime
to atp_test_core;

grant select, insert, update on
  atp_test.operations,
  atp_test.operation_attempts,
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

-- Product knowledge reader: only one product-scoped published view.
grant select on atp_test.v_knowledge_call_analysis_runtime
to atp_test_knowledge_call_analysis;

-- Knowledge/config admin: separate privileged capability, never used for
-- ordinary analysis. No access to conversation/raw/dashboard tables.
grant select, insert, update on
  atp_test.prompt_versions,
  atp_test.methodology_versions,
  atp_test.methodology_criteria,
  atp_test.methodology_stages,
  atp_test.filter_rule_versions,
  atp_test.knowledge_documents,
  atp_test.knowledge_document_versions,
  atp_test.knowledge_fragments,
  atp_test.knowledge_embeddings,
  atp_test.knowledge_publications,
  atp_test.knowledge_publication_documents,
  atp_test.knowledge_publication_fragments,
  atp_test.knowledge_publication_fragment_products
to atp_test_knowledge_admin;

grant select on
  atp_test.v_runtime_knowledge_fragments,
  atp_test.v_knowledge_call_analysis_runtime,
  atp_test.audit_events
to atp_test_knowledge_admin;

grant insert on atp_test.audit_events
to atp_test_knowledge_admin;

-- Dashboard is read-only at the table level.
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
  atp_test.v_dashboard_safe_transcript_segments,
  atp_test.v_dashboard_evidence_conversation,
  atp_test.v_dashboard_evidence_knowledge
to atp_test_dashboard;

grant execute on function atp_test.dashboard_filter_call_ids(
  timestamptz, timestamptz, jsonb
) to atp_test_dashboard;
grant execute on function atp_test.dashboard_overview(
  timestamptz, timestamptz, jsonb, timestamptz, interval, text[], text[]
) to atp_test_dashboard;
grant execute on function atp_test.dashboard_manager_metrics(
  timestamptz, timestamptz, jsonb, text[], text[]
) to atp_test_dashboard;
grant execute on function atp_test.dashboard_criterion_metrics(
  timestamptz, timestamptz, jsonb
) to atp_test_dashboard;
grant execute on function atp_test.dashboard_stage_metrics(
  timestamptz, timestamptz, jsonb
) to atp_test_dashboard;
grant execute on function atp_test.dashboard_observation_metrics(
  timestamptz, timestamptz, jsonb
) to atp_test_dashboard;
grant execute on function atp_test.dashboard_result_metrics(
  timestamptz, timestamptz, jsonb
) to atp_test_dashboard;

-- Controlled admin/correction capability can review safe dashboard evidence and
-- history, but cannot directly mutate tables.
grant select on
  atp_test.v_dashboard_zvonki,
  atp_test.v_dashboard_kriterii,
  atp_test.v_dashboard_etapy,
  atp_test.v_dashboard_oshibki,
  atp_test.v_dashboard_rezultaty,
  atp_test.v_dashboard_safe_transcript_segments,
  atp_test.v_dashboard_evidence_conversation,
  atp_test.v_dashboard_evidence_knowledge,
  atp_test.analysis_disputes,
  atp_test.corrections,
  atp_test.audit_events
to atp_test_correction_operator;

grant execute on function atp_test.dashboard_open_analysis_dispute(
  uuid, uuid, uuid, uuid, text, text
) to atp_test_correction_operator;
grant execute on function atp_test.dashboard_propose_correction(
  uuid, text, uuid, text, text, jsonb, jsonb, text, text, uuid
) to atp_test_correction_operator;
grant execute on function atp_test.dashboard_resolve_analysis_dispute(
  uuid, text, text, text
) to atp_test_correction_operator;
grant execute on function atp_test.dashboard_finalize_correction(
  uuid, text, uuid, text, text
) to atp_test_correction_operator;

-- Monitoring sees only minimized technical views.
grant select on
  atp_test.v_monitoring_calls,
  atp_test.v_monitoring_operations
to atp_test_monitoring;

commit;
