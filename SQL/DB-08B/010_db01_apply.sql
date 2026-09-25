-- DB-01
-- Base ingest and reliability schema for the Analiz_telefonnyh_peregovorov template.
-- APPROVED WORKING CONTOUR. Run only in the approved Supabase project and only for schema shablon_analiz_telefonnyh_peregovorov.
-- Source requirements:
--   docs/DATA_DICTIONARY.md
--   docs/specs/INTEGRATION_CONTRACTS.md
--   docs/specs/RELIABILITY_AND_IDEMPOTENCY.md
--   docs/specs/CALL_LIFECYCLE.md
--   docs/specs/AUDIO_RETENTION.md
--   docs/specs/ACCESS_AND_ISOLATION.md
--
-- Physical implementation decision for the working template contour:
-- one PostgreSQL schema = one company+environment contour.
-- DB-01 uses the neutral template schema "shablon_analiz_telefonnyh_peregovorov".
-- DB-07 will implement/verify runtime roles and cross-contour isolation.
--
-- This migration stores only metadata for temporary audio. It never stores
-- permanent audio bytes/blobs.

begin;

create extension if not exists pgcrypto;

do $guard$
begin
  if exists (
    select 1
    from pg_namespace
    where nspname = 'shablon_analiz_telefonnyh_peregovorov'
  ) then
    raise exception
      'DB-01 refuses to run because schema shablon_analiz_telefonnyh_peregovorov already exists. Inspect schema shablon_analiz_telefonnyh_peregovorov instead of rerunning blindly.';
  end if;
end
$guard$;

create schema shablon_analiz_telefonnyh_peregovorov;

comment on schema shablon_analiz_telefonnyh_peregovorov is
  'Working template contour for Analiz_telefonnyh_peregovorov. Schema shablon_analiz_telefonnyh_peregovorov is isolated from unrelated schemas in the same Supabase project.';

create type shablon_analiz_telefonnyh_peregovorov.contract_decision as enum (
  'accepted',
  'duplicate',
  'rejected'
);

create type shablon_analiz_telefonnyh_peregovorov.operation_state as enum (
  'not_started',
  'in_progress_unconfirmed',
  'succeeded',
  'failed_retryable',
  'failed_requires_fix',
  'outcome_unknown'
);

create type shablon_analiz_telefonnyh_peregovorov.call_processing_state as enum (
  'registered',
  'excluded',
  'missed',
  'waiting_audio',
  'processing',
  'analysis_ready',
  'feedback_pending',
  'feedback_delivered',
  'delivery_unknown',
  'retry_wait',
  'technically_finished'
);

create type shablon_analiz_telefonnyh_peregovorov.call_classification as enum (
  'pending',
  'client',
  'excluded',
  'missed'
);

create type shablon_analiz_telefonnyh_peregovorov.call_occurrence_kind as enum (
  'unknown',
  'first',
  'repeat'
);

create type shablon_analiz_telefonnyh_peregovorov.call_direction as enum (
  'unknown',
  'inbound',
  'outbound'
);

create type shablon_analiz_telefonnyh_peregovorov.answer_status as enum (
  'unknown',
  'answered',
  'missed'
);

create type shablon_analiz_telefonnyh_peregovorov.filter_outcome as enum (
  'accepted',
  'excluded',
  'missed'
);

create type shablon_analiz_telefonnyh_peregovorov.transport_result as enum (
  'not_sent',
  'transport_succeeded',
  'transport_failed',
  'transport_unknown'
);

create type shablon_analiz_telefonnyh_peregovorov.audio_acquisition_state as enum (
  'requested',
  'downloading',
  'ready',
  'incomplete',
  'unavailable',
  'failed'
);

create type shablon_analiz_telefonnyh_peregovorov.audio_cleanup_state as enum (
  'not_due',
  'due',
  'deleting',
  'deleted',
  'delete_failed'
);

create function shablon_analiz_telefonnyh_peregovorov.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  new.updated_at = clock_timestamp();
  return new;
end
$function$;

-- Logical entity: menedzhery.
create table shablon_analiz_telefonnyh_peregovorov.managers (
  manager_id uuid primary key default gen_random_uuid(),
  source_code text not null,
  external_scope_ref text not null,
  external_manager_id text not null,
  full_name text,
  department_ref text,
  active_from timestamptz not null default now(),
  active_to timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint managers_source_code_not_blank
    check (btrim(source_code) <> ''),
  constraint managers_external_scope_not_blank
    check (btrim(external_scope_ref) <> ''),
  constraint managers_external_id_not_blank
    check (btrim(external_manager_id) <> ''),
  constraint managers_active_period_valid
    check (active_to is null or active_to >= active_from),
  constraint managers_active_flag_period_consistent
    check (is_active or active_to is not null)
);

comment on table shablon_analiz_telefonnyh_peregovorov.managers is
  'Trusted manager entity for the shablon_analiz_telefonnyh_peregovorov contour. Local protected data only; LLM never assigns manager_id.';

create unique index uq_managers_active_external_binding
  on shablon_analiz_telefonnyh_peregovorov.managers (source_code, external_scope_ref, external_manager_id)
  where active_to is null;

create trigger trg_managers_set_updated_at
before update on shablon_analiz_telefonnyh_peregovorov.managers
for each row execute function shablon_analiz_telefonnyh_peregovorov.set_updated_at();

-- Logical entity: zvonki.
create table shablon_analiz_telefonnyh_peregovorov.calls (
  call_id uuid primary key default gen_random_uuid(),
  source_adapter_code text not null,
  connection_ref text not null,
  call_identity_key text not null,
  external_call_id text,
  manager_id uuid references shablon_analiz_telefonnyh_peregovorov.managers(manager_id) on delete restrict,
  contact_ref text,
  lead_ref text,
  deal_ref text,
  started_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer,
  direction shablon_analiz_telefonnyh_peregovorov.call_direction not null default 'unknown',
  answer_status shablon_analiz_telefonnyh_peregovorov.answer_status not null default 'unknown',
  occurrence_kind shablon_analiz_telefonnyh_peregovorov.call_occurrence_kind not null default 'unknown',
  classification shablon_analiz_telefonnyh_peregovorov.call_classification not null default 'pending',
  processing_state shablon_analiz_telefonnyh_peregovorov.call_processing_state not null default 'registered',
  current_filter_decision_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint calls_source_adapter_not_blank
    check (btrim(source_adapter_code) <> ''),
  constraint calls_connection_ref_not_blank
    check (btrim(connection_ref) <> ''),
  constraint calls_identity_key_not_blank
    check (btrim(call_identity_key) <> ''),
  constraint calls_duration_nonnegative
    check (duration_seconds is null or duration_seconds >= 0),
  constraint calls_time_order_valid
    check (ended_at is null or started_at is null or ended_at >= started_at)
);

comment on table shablon_analiz_telefonnyh_peregovorov.calls is
  'One logical call/attempt of communication, not one webhook. call_identity_key is a server-derived stable identity inside source_adapter_code + connection_ref.';

create unique index uq_calls_source_identity
  on shablon_analiz_telefonnyh_peregovorov.calls (source_adapter_code, connection_ref, call_identity_key);

create index ix_calls_manager_started_at
  on shablon_analiz_telefonnyh_peregovorov.calls (manager_id, started_at desc);

create index ix_calls_processing_state
  on shablon_analiz_telefonnyh_peregovorov.calls (processing_state, created_at);

create trigger trg_calls_set_updated_at
before update on shablon_analiz_telefonnyh_peregovorov.calls
for each row execute function shablon_analiz_telefonnyh_peregovorov.set_updated_at();

-- Logical entity: sobytia_zvonkov.
-- Duplicate receipts are allowed only with decision=duplicate and must point
-- to the canonical earlier event. A non-duplicate external event identity is
-- unique inside adapter + connection.
create table shablon_analiz_telefonnyh_peregovorov.call_events (
  event_id uuid primary key default gen_random_uuid(),
  adapter_code text not null,
  connection_ref text not null,
  event_identity_key text not null,
  external_event_id text,
  external_call_id text,
  event_type text not null,
  source_event_at timestamptz,
  received_at timestamptz not null default now(),
  direction shablon_analiz_telefonnyh_peregovorov.call_direction not null default 'unknown',
  answer_status shablon_analiz_telefonnyh_peregovorov.answer_status not null default 'unknown',
  participant_ref text,
  extension_ref text,
  crm_contact_ref text,
  crm_lead_ref text,
  crm_deal_ref text,
  audio_available boolean,
  decision shablon_analiz_telefonnyh_peregovorov.contract_decision not null,
  call_id uuid references shablon_analiz_telefonnyh_peregovorov.calls(call_id) on delete restrict,
  duplicate_of_event_id uuid references shablon_analiz_telefonnyh_peregovorov.call_events(event_id) on delete restrict,
  rejection_code text,
  safe_metadata jsonb not null default '{}'::jsonb,

  constraint call_events_adapter_not_blank
    check (btrim(adapter_code) <> ''),
  constraint call_events_connection_ref_not_blank
    check (btrim(connection_ref) <> ''),
  constraint call_events_identity_key_not_blank
    check (btrim(event_identity_key) <> ''),
  constraint call_events_event_type_not_blank
    check (btrim(event_type) <> ''),
  constraint call_events_safe_metadata_object
    check (jsonb_typeof(safe_metadata) = 'object'),
  constraint call_events_duplicate_link_valid
    check (
      (decision = 'duplicate' and duplicate_of_event_id is not null)
      or
      (decision <> 'duplicate' and duplicate_of_event_id is null)
    ),
  constraint call_events_resolved_call_ref
    check (
      decision = 'rejected'
      or call_id is not null
    ),
  constraint call_events_rejected_code_present
    check (
      decision <> 'rejected'
      or (rejection_code is not null and btrim(rejection_code) <> '')
    )
);

comment on table shablon_analiz_telefonnyh_peregovorov.call_events is
  'One received source signal. Raw provider payload is intentionally not stored here; only normalized trusted refs and safe metadata.';

create unique index uq_call_events_non_duplicate_identity
  on shablon_analiz_telefonnyh_peregovorov.call_events (adapter_code, connection_ref, event_identity_key)
  where decision <> 'duplicate';

create index ix_call_events_call_received
  on shablon_analiz_telefonnyh_peregovorov.call_events (call_id, received_at);

create index ix_call_events_external_call
  on shablon_analiz_telefonnyh_peregovorov.call_events (adapter_code, connection_ref, external_call_id)
  where external_call_id is not null;

-- Logical entity: operacii.
create table shablon_analiz_telefonnyh_peregovorov.operations (
  operation_id uuid primary key default gen_random_uuid(),
  scope_ref text not null default 'shablon_analiz_telefonnyh_peregovorov',
  call_id uuid not null references shablon_analiz_telefonnyh_peregovorov.calls(call_id) on delete restrict,
  operation_type text not null,
  idempotency_key text not null,
  contract_version text not null,
  correlation_id text not null,
  input_refs jsonb not null default '{}'::jsonb,
  decision shablon_analiz_telefonnyh_peregovorov.contract_decision not null,
  operation_state shablon_analiz_telefonnyh_peregovorov.operation_state not null default 'not_started',
  result_ref text,
  external_request_ref text,
  error_class text,
  error_code text,
  supersedes_operation_id uuid references shablon_analiz_telefonnyh_peregovorov.operations(operation_id) on delete restrict,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint operations_scope_is_test
    check (scope_ref = 'shablon_analiz_telefonnyh_peregovorov'),
  constraint operations_type_not_blank
    check (btrim(operation_type) <> ''),
  constraint operations_idempotency_key_not_blank
    check (btrim(idempotency_key) <> ''),
  constraint operations_contract_version_not_blank
    check (btrim(contract_version) <> ''),
  constraint operations_correlation_id_not_blank
    check (btrim(correlation_id) <> ''),
  constraint operations_input_refs_object
    check (jsonb_typeof(input_refs) = 'object'),
  constraint operations_completed_after_requested
    check (completed_at is null or completed_at >= requested_at),
  constraint operations_rejected_not_started
    check (
      decision <> 'rejected'
      or operation_state in ('not_started', 'failed_requires_fix')
    ),
  constraint operations_no_self_supersede
    check (supersedes_operation_id is null or supersedes_operation_id <> operation_id),
  constraint operations_operation_call_unique
    unique (operation_id, call_id)
);

comment on table shablon_analiz_telefonnyh_peregovorov.operations is
  'One idempotent logical operation. Safe retries create operation_attempts, not a second equivalent operation.';

create unique index uq_operations_call_type_idempotency
  on shablon_analiz_telefonnyh_peregovorov.operations (call_id, operation_type, idempotency_key);

create index ix_operations_call_state
  on shablon_analiz_telefonnyh_peregovorov.operations (call_id, operation_state, requested_at);

create index ix_operations_state_requested
  on shablon_analiz_telefonnyh_peregovorov.operations (operation_state, requested_at);

create trigger trg_operations_set_updated_at
before update on shablon_analiz_telefonnyh_peregovorov.operations
for each row execute function shablon_analiz_telefonnyh_peregovorov.set_updated_at();

-- Logical entity: popytki_operaciy.
create table shablon_analiz_telefonnyh_peregovorov.operation_attempts (
  attempt_id uuid primary key default gen_random_uuid(),
  operation_id uuid not null references shablon_analiz_telefonnyh_peregovorov.operations(operation_id) on delete restrict,
  attempt_no integer not null,
  attempt_state shablon_analiz_telefonnyh_peregovorov.operation_state not null,
  external_request_ref text,
  transport_result shablon_analiz_telefonnyh_peregovorov.transport_result not null default 'not_sent',
  decision shablon_analiz_telefonnyh_peregovorov.contract_decision not null,
  error_class text,
  error_code text,
  safe_context jsonb not null default '{}'::jsonb,
  retry_reason text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,

  constraint operation_attempts_number_positive
    check (attempt_no > 0),
  constraint operation_attempts_safe_context_object
    check (jsonb_typeof(safe_context) = 'object'),
  constraint operation_attempts_completed_after_requested
    check (completed_at is null or completed_at >= requested_at),
  constraint operation_attempts_rejected_not_started
    check (
      decision <> 'rejected'
      or attempt_state in ('not_started', 'failed_requires_fix')
    )
);

comment on table shablon_analiz_telefonnyh_peregovorov.operation_attempts is
  'One concrete execution attempt of an operation. Attempt errors are primary technical facts for monitoring.';

create unique index uq_operation_attempts_number
  on shablon_analiz_telefonnyh_peregovorov.operation_attempts (operation_id, attempt_no);

create index ix_operation_attempts_operation_time
  on shablon_analiz_telefonnyh_peregovorov.operation_attempts (operation_id, requested_at);

create index ix_operation_attempts_state
  on shablon_analiz_telefonnyh_peregovorov.operation_attempts (attempt_state, requested_at);

-- Logical entity: resheniya_filtra.
create table shablon_analiz_telefonnyh_peregovorov.filter_decisions (
  filter_decision_id uuid primary key default gen_random_uuid(),
  call_id uuid not null references shablon_analiz_telefonnyh_peregovorov.calls(call_id) on delete restrict,
  outcome shablon_analiz_telefonnyh_peregovorov.filter_outcome not null,
  reason_code text,
  filter_rules_version_ref text not null,
  input_facts jsonb not null default '{}'::jsonb,
  operation_id uuid not null,
  decided_at timestamptz not null default now(),

  constraint filter_decisions_rule_ref_not_blank
    check (btrim(filter_rules_version_ref) <> ''),
  constraint filter_decisions_input_facts_object
    check (jsonb_typeof(input_facts) = 'object'),
  constraint filter_decisions_reason_for_nonaccepted
    check (
      outcome = 'accepted'
      or (reason_code is not null and btrim(reason_code) <> '')
    ),
  constraint filter_decisions_decision_call_unique
    unique (filter_decision_id, call_id),
  constraint fk_filter_decisions_operation_call
    foreign key (operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.filter_decisions is
  'Versioned filter decision. Filtering never deletes the registered logical call.';

create unique index uq_filter_decisions_operation
  on shablon_analiz_telefonnyh_peregovorov.filter_decisions (operation_id);

create index ix_filter_decisions_call_time
  on shablon_analiz_telefonnyh_peregovorov.filter_decisions (call_id, decided_at desc);

alter table shablon_analiz_telefonnyh_peregovorov.calls
  add constraint fk_calls_current_filter_decision
  foreign key (current_filter_decision_id, call_id)
  references shablon_analiz_telefonnyh_peregovorov.filter_decisions(filter_decision_id, call_id)
  on delete restrict;

-- Logical entity: svyazi_zvonkov.
create table shablon_analiz_telefonnyh_peregovorov.call_links (
  call_link_id uuid primary key default gen_random_uuid(),
  current_call_id uuid not null references shablon_analiz_telefonnyh_peregovorov.calls(call_id) on delete restrict,
  previous_call_id uuid references shablon_analiz_telefonnyh_peregovorov.calls(call_id) on delete restrict,
  external_entity_type text,
  external_entity_ref text,
  relation_type text not null,
  relation_identity_key text not null,
  is_confirmed boolean not null default false,
  basis_type text not null,
  basis_ref text,
  source_code text not null,
  created_at timestamptz not null default now(),

  constraint call_links_relation_type_not_blank
    check (btrim(relation_type) <> ''),
  constraint call_links_identity_key_not_blank
    check (btrim(relation_identity_key) <> ''),
  constraint call_links_basis_type_not_blank
    check (btrim(basis_type) <> ''),
  constraint call_links_source_code_not_blank
    check (btrim(source_code) <> ''),
  constraint call_links_has_target
    check (
      previous_call_id is not null
      or (
        external_entity_type is not null
        and btrim(external_entity_type) <> ''
        and external_entity_ref is not null
        and btrim(external_entity_ref) <> ''
      )
    ),
  constraint call_links_not_self
    check (previous_call_id is null or previous_call_id <> current_call_id)
);

comment on table shablon_analiz_telefonnyh_peregovorov.call_links is
  'Trusted relation between calls or between a call and a trusted external CRM/contact/deal entity. LLM guess is not sufficient evidence.';

create unique index uq_call_links_identity
  on shablon_analiz_telefonnyh_peregovorov.call_links (current_call_id, relation_identity_key);

create index ix_call_links_previous_call
  on shablon_analiz_telefonnyh_peregovorov.call_links (previous_call_id)
  where previous_call_id is not null;

-- Logical entity: vremennye_audio_artefakty.
create table shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts (
  audio_artifact_id uuid primary key default gen_random_uuid(),
  call_id uuid not null references shablon_analiz_telefonnyh_peregovorov.calls(call_id) on delete restrict,
  acquisition_operation_id uuid not null,
  artifact_identity_key text not null,
  local_artifact_ref text not null,
  source_ref text not null,
  acquisition_state shablon_analiz_telefonnyh_peregovorov.audio_acquisition_state not null,
  size_bytes bigint,
  duration_ms bigint,
  integrity_algorithm text,
  integrity_digest text,
  created_at timestamptz not null default now(),
  delete_after timestamptz not null,
  deleted_at timestamptz,
  deletion_confirmed_at timestamptz,
  cleanup_state shablon_analiz_telefonnyh_peregovorov.audio_cleanup_state not null default 'not_due',
  cleanup_error_code text,

  constraint temporary_audio_identity_not_blank
    check (btrim(artifact_identity_key) <> ''),
  constraint temporary_audio_local_ref_not_blank
    check (btrim(local_artifact_ref) <> ''),
  constraint temporary_audio_source_ref_not_blank
    check (btrim(source_ref) <> ''),
  constraint temporary_audio_size_nonnegative
    check (size_bytes is null or size_bytes >= 0),
  constraint temporary_audio_duration_nonnegative
    check (duration_ms is null or duration_ms >= 0),
  constraint temporary_audio_delete_after_created
    check (delete_after > created_at),
  constraint temporary_audio_deleted_state_consistent
    check (
      cleanup_state <> 'deleted'
      or deleted_at is not null
    ),
  constraint temporary_audio_confirmation_consistent
    check (
      deletion_confirmed_at is null
      or (
        deleted_at is not null
        and cleanup_state = 'deleted'
        and deletion_confirmed_at >= deleted_at
      )
    ),
  constraint temporary_audio_delete_error_consistent
    check (
      cleanup_state <> 'delete_failed'
      or (cleanup_error_code is not null and btrim(cleanup_error_code) <> '')
    ),
  constraint fk_temporary_audio_operation_call
    foreign key (acquisition_operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts is
  'Metadata for temporary local audio only. No audio bytea/blob is stored in Supabase. local_artifact_ref must be server-generated and must not contain secrets.';

create unique index uq_temporary_audio_identity
  on shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts (call_id, artifact_identity_key);

create index ix_temporary_audio_cleanup_due
  on shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts (cleanup_state, delete_after);

create index ix_temporary_audio_call
  on shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts (call_id, created_at);

commit;
