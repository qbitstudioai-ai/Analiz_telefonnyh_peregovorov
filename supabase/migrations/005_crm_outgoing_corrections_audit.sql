-- DB-05
-- CRM/human confirmations, callback links, outgoing delivery, disputes,
-- corrections and immutable audit trail.
-- TEST/LOCAL ONLY. Depends on DB-01..DB-04.
--
-- Key invariants:
--   AI outcome is never a CRM/human confirmation;
--   outgoing action exists before any delivery attempt;
--   confirmed delivery cannot be repeated;
--   outcome_unknown requires reconciliation before any retry;
--   corrections/disputes preserve original history;
--   audit is append-only.

begin;

do $guard$
declare
  v_missing text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-05 requires schema atp_test';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('calls'),
      ('managers'),
      ('operations'),
      ('operation_attempts'),
      ('role_assignment_versions'),
      ('raw_transcripts'),
      ('analysis_versions'),
      ('analysis_claims'),
      ('evidence_sets')
  ) as required(required_relation)
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname = required.required_relation
      and c.relkind in ('r', 'p')
  );

  if v_missing is not null then
    raise exception 'DB-05 requires DB-01..DB-04. Missing: %', v_missing;
  end if;

  if exists (
    select 1
    from pg_tables
    where schemaname = 'atp_test'
      and tablename in (
        'business_confirmations',
        'callback_links',
        'outgoing_actions',
        'delivery_attempts',
        'analysis_disputes',
        'corrections',
        'audit_events'
      )
  ) then
    raise exception
      'DB-05 refuses to run because one or more DB-05 tables already exist';
  end if;
end
$guard$;

-- Composite keys needed by exact DB-05 ownership FKs.
alter table atp_test.operation_attempts
  add constraint operation_attempts_attempt_operation_unique
  unique (attempt_id, operation_id);

alter table atp_test.role_assignment_versions
  add constraint role_assignment_versions_role_call_unique
  unique (role_assignment_version_id, call_id);

create type atp_test.business_confirmation_source as enum (
  'crm',
  'human'
);

create type atp_test.business_confirmation_event_kind as enum (
  'confirm',
  'correct',
  'cancel'
);

create type atp_test.callback_link_state as enum (
  'candidate',
  'confirmed',
  'rejected'
);

create type atp_test.outgoing_action_state as enum (
  'prepared',
  'cancelled'
);

create type atp_test.delivery_provider_status as enum (
  'not_confirmed',
  'accepted',
  'delivered',
  'rejected',
  'unknown'
);

create type atp_test.delivery_reconciliation_state as enum (
  'not_required',
  'pending',
  'confirmed_delivered',
  'confirmed_not_delivered',
  'unresolved'
);

create type atp_test.dispute_state as enum (
  'open',
  'under_review',
  'resolved',
  'rejected'
);

create type atp_test.correction_state as enum (
  'proposed',
  'applied',
  'rejected'
);

create type atp_test.correction_target_type as enum (
  'manager',
  'role_assignment',
  'transcript',
  'analysis',
  'business_confirmation',
  'callback_link',
  'outgoing_action'
);

create type atp_test.audit_result as enum (
  'success',
  'rejected',
  'unknown'
);

-- Trusted source facts. Corrections/cancellations are new immutable source events,
-- not updates of an AI outcome or old CRM row.
create table atp_test.business_confirmations (
  confirmation_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  fact_family_ref text not null,
  event_no integer not null,
  supersedes_confirmation_id uuid,
  event_kind atp_test.business_confirmation_event_kind not null,
  fact_type text not null,
  source_kind atp_test.business_confirmation_source not null,
  source_system_code text not null,
  source_event_key text not null,
  external_fact_id text,
  client_ref text,
  deal_ref text,
  fact_value jsonb not null default '{}'::jsonb,
  fact_status text not null,
  fact_occurred_at timestamptz,
  received_at timestamptz not null default now(),
  human_actor_ref text,
  created_by_operation_id uuid not null,
  change_reason text,
  created_at timestamptz not null default now(),

  constraint business_confirmations_family_not_blank
    check (btrim(fact_family_ref) <> ''),
  constraint business_confirmations_event_positive
    check (event_no > 0),
  constraint business_confirmations_chain_shape
    check (
      (event_no = 1 and supersedes_confirmation_id is null and event_kind = 'confirm')
      or
      (event_no > 1 and supersedes_confirmation_id is not null and event_kind in ('correct', 'cancel'))
    ),
  constraint business_confirmations_type_not_blank
    check (btrim(fact_type) <> ''),
  constraint business_confirmations_source_system_not_blank
    check (btrim(source_system_code) <> ''),
  constraint business_confirmations_source_event_not_blank
    check (btrim(source_event_key) <> ''),
  constraint business_confirmations_value_object
    check (jsonb_typeof(fact_value) = 'object'),
  constraint business_confirmations_status_not_blank
    check (btrim(fact_status) <> ''),
  constraint business_confirmations_human_actor
    check (
      source_kind <> 'human'
      or (human_actor_ref is not null and btrim(human_actor_ref) <> '')
    ),
  constraint business_confirmations_correction_reason
    check (
      event_kind = 'confirm'
      or (change_reason is not null and btrim(change_reason) <> '')
    ),
  constraint business_confirmations_id_call_unique
    unique (confirmation_id, call_id),
  constraint business_confirmations_id_family_unique
    unique (confirmation_id, fact_family_ref),
  constraint business_confirmations_family_event_unique
    unique (fact_family_ref, event_no),
  constraint business_confirmations_source_event_unique
    unique (source_kind, source_system_code, source_event_key),
  constraint business_confirmations_call_fk
    foreign key (call_id)
    references atp_test.calls(call_id)
    on delete restrict,
  constraint business_confirmations_operation_same_call
    foreign key (created_by_operation_id, call_id)
    references atp_test.operations(operation_id, call_id)
    on delete restrict,
  constraint business_confirmations_predecessor_same_family
    foreign key (supersedes_confirmation_id, fact_family_ref)
    references atp_test.business_confirmations(confirmation_id, fact_family_ref)
    on delete restrict
);

comment on table atp_test.business_confirmations is
  'Immutable trusted CRM/human source events. They never overwrite AI inferred outcomes.';

create function atp_test.validate_business_confirmation_insert()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_predecessor_event_no integer;
  v_predecessor_call_id uuid;
  v_predecessor_fact_type text;
begin
  if new.event_no = 1 then
    return new;
  end if;

  select event_no, call_id, fact_type
  into v_predecessor_event_no, v_predecessor_call_id, v_predecessor_fact_type
  from atp_test.business_confirmations
  where confirmation_id = new.supersedes_confirmation_id
    and fact_family_ref = new.fact_family_ref;

  if not found then
    raise exception 'Business confirmation predecessor does not exist in same family';
  end if;

  if new.event_no <> v_predecessor_event_no + 1 then
    raise exception 'Business confirmation event_no must follow predecessor exactly';
  end if;

  if new.call_id is distinct from v_predecessor_call_id
     or new.fact_type is distinct from v_predecessor_fact_type
  then
    raise exception 'Business confirmation correction/cancel cannot change call/fact type';
  end if;

  if exists (
    select 1
    from atp_test.business_confirmations x
    where x.supersedes_confirmation_id = new.supersedes_confirmation_id
  ) then
    raise exception 'Business confirmation predecessor already has a successor';
  end if;

  return new;
end
$function$;

create function atp_test.guard_business_confirmation_immutable()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  raise exception
    'Business confirmation events are immutable; append a correction/cancel event';
end
$function$;

create trigger trg_business_confirmations_validate_insert
before insert on atp_test.business_confirmations
for each row execute function atp_test.validate_business_confirmation_insert();

create trigger trg_business_confirmations_immutable
before update or delete on atp_test.business_confirmations
for each row execute function atp_test.guard_business_confirmation_immutable();

-- Shared delete guard for history rows that may have no child FK yet.
create function atp_test.guard_db05_history_delete()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  raise exception '% history row cannot be deleted', tg_table_name;
end
$function$;

-- Missed-call -> callback relation based only on trusted source/CRM facts.
create table atp_test.callback_links (
  callback_link_id uuid primary key default gen_random_uuid(),
  missed_call_id uuid not null references atp_test.calls(call_id) on delete restrict,
  callback_call_id uuid not null references atp_test.calls(call_id) on delete restrict,
  manager_id uuid references atp_test.managers(manager_id) on delete restrict,
  basis_kind text not null,
  basis_refs jsonb not null default '{}'::jsonb,
  rules_version_ref text not null,
  window_config jsonb not null default '{}'::jsonb,
  delay_seconds integer,
  link_state atp_test.callback_link_state not null default 'candidate',
  decision_reason text,
  decision_operation_id uuid not null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),

  constraint callback_links_distinct_calls
    check (missed_call_id <> callback_call_id),
  constraint callback_links_basis_not_blank
    check (btrim(basis_kind) <> ''),
  constraint callback_links_basis_object
    check (jsonb_typeof(basis_refs) = 'object'),
  constraint callback_links_rules_not_blank
    check (btrim(rules_version_ref) <> ''),
  constraint callback_links_window_object
    check (jsonb_typeof(window_config) = 'object'),
  constraint callback_links_delay_nonnegative
    check (delay_seconds is null or delay_seconds >= 0),
  constraint callback_links_decision_metadata
    check (
      (
        link_state = 'candidate'
        and decision_reason is null
        and decided_at is null
      )
      or
      (
        link_state in ('confirmed', 'rejected')
        and decision_reason is not null
        and btrim(decision_reason) <> ''
        and decided_at is not null
      )
    ),
  constraint callback_links_pair_unique
    unique (missed_call_id, callback_call_id),
  constraint callback_links_id_callback_unique
    unique (callback_link_id, callback_call_id),
  constraint callback_links_operation_same_callback
    foreign key (decision_operation_id, callback_call_id)
    references atp_test.operations(operation_id, call_id)
    on delete restrict
);

create function atp_test.validate_callback_link()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_missed_answer atp_test.answer_status;
  v_missed_class atp_test.call_classification;
  v_callback_direction atp_test.call_direction;
  v_missed_started timestamptz;
  v_callback_started timestamptz;
begin
  select answer_status, classification, started_at
  into v_missed_answer, v_missed_class, v_missed_started
  from atp_test.calls
  where call_id = new.missed_call_id;

  select direction, started_at
  into v_callback_direction, v_callback_started
  from atp_test.calls
  where call_id = new.callback_call_id;

  if v_missed_answer is distinct from 'missed'
     and v_missed_class is distinct from 'missed'
  then
    raise exception 'Callback link source is not a missed call';
  end if;

  if v_callback_direction is distinct from 'outbound' then
    raise exception 'Callback link target must be an outbound call';
  end if;

  if new.link_state = 'confirmed'
     and new.basis_refs = '{}'::jsonb
  then
    raise exception 'Confirmed callback link requires trusted basis refs';
  end if;

  if v_missed_started is not null
     and v_callback_started is not null
     and v_callback_started < v_missed_started
  then
    raise exception 'Callback call cannot precede missed call';
  end if;

  return new;
end
$function$;

create function atp_test.guard_callback_link_update()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_old_semantic jsonb;
  v_new_semantic jsonb;
begin
  if old.link_state <> 'candidate' then
    raise exception 'Final callback decision is immutable';
  end if;

  if new.link_state not in ('candidate', 'confirmed', 'rejected') then
    raise exception 'Invalid callback link state transition';
  end if;

  v_old_semantic := to_jsonb(old)
    - 'link_state'
    - 'decision_reason'
    - 'decided_at';
  v_new_semantic := to_jsonb(new)
    - 'link_state'
    - 'decision_reason'
    - 'decided_at';

  if v_old_semantic is distinct from v_new_semantic then
    raise exception 'Callback link identity/basis is immutable';
  end if;

  return new;
end
$function$;

create trigger trg_callback_links_validate
before insert or update on atp_test.callback_links
for each row execute function atp_test.validate_callback_link();

create trigger trg_callback_links_guard_update
before update on atp_test.callback_links
for each row execute function atp_test.guard_callback_link_update();

create trigger trg_callback_links_guard_delete
before delete on atp_test.callback_links
for each row execute function atp_test.guard_db05_history_delete();

-- Outgoing message/action is persisted before any external send.
create table atp_test.outgoing_actions (
  outgoing_action_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  analysis_id uuid not null,
  logical_action_key text not null,
  purpose_code text not null,
  channel_ref text not null,
  recipient_ref text not null,
  message_version text not null,
  message_body text not null,
  message_sha256 text not null,
  creation_operation_id uuid not null,
  action_state atp_test.outgoing_action_state not null default 'prepared',
  cancel_reason text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),

  constraint outgoing_actions_key_not_blank
    check (btrim(logical_action_key) <> ''),
  constraint outgoing_actions_purpose_not_blank
    check (btrim(purpose_code) <> ''),
  constraint outgoing_actions_channel_not_blank
    check (btrim(channel_ref) <> ''),
  constraint outgoing_actions_recipient_not_blank
    check (btrim(recipient_ref) <> ''),
  constraint outgoing_actions_message_version_not_blank
    check (btrim(message_version) <> ''),
  constraint outgoing_actions_message_not_blank
    check (btrim(message_body) <> ''),
  constraint outgoing_actions_hash_not_blank
    check (btrim(message_sha256) <> ''),
  constraint outgoing_actions_cancel_metadata
    check (
      action_state <> 'cancelled'
      or (
        cancel_reason is not null
        and btrim(cancel_reason) <> ''
        and cancelled_at is not null
      )
    ),
  constraint outgoing_actions_logical_key_unique
    unique (logical_action_key),
  constraint outgoing_actions_id_call_unique
    unique (outgoing_action_id, call_id),
  constraint outgoing_actions_analysis_same_call
    foreign key (analysis_id, call_id)
    references atp_test.analysis_versions(analysis_id, call_id)
    on delete restrict,
  constraint outgoing_actions_operation_same_call
    foreign key (creation_operation_id, call_id)
    references atp_test.operations(operation_id, call_id)
    on delete restrict
);

create function atp_test.validate_outgoing_action_insert()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_analysis_state atp_test.analysis_state;
  v_operation_state atp_test.operation_state;
begin
  if new.action_state <> 'prepared' then
    raise exception 'Outgoing action must be inserted as prepared';
  end if;

  select analysis_state
  into v_analysis_state
  from atp_test.analysis_versions
  where analysis_id = new.analysis_id
    and call_id = new.call_id;

  if v_analysis_state not in ('validated', 'current') then
    raise exception
      'Outgoing action requires a validated/current analysis';
  end if;

  select operation_state
  into v_operation_state
  from atp_test.operations
  where operation_id = new.creation_operation_id
    and call_id = new.call_id;

  if v_operation_state is distinct from 'succeeded' then
    raise exception 'Outgoing action creation operation must be succeeded';
  end if;

  return new;
end
$function$;

create function atp_test.guard_outgoing_action_update()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_old_semantic jsonb;
  v_new_semantic jsonb;
begin
  if old.action_state = 'cancelled' then
    raise exception 'Cancelled outgoing action is immutable';
  end if;

  v_old_semantic := to_jsonb(old)
    - 'action_state'
    - 'cancel_reason'
    - 'cancelled_at';
  v_new_semantic := to_jsonb(new)
    - 'action_state'
    - 'cancel_reason'
    - 'cancelled_at';

  if v_old_semantic is distinct from v_new_semantic then
    raise exception 'Outgoing action content/address/analysis is immutable';
  end if;

  if new.action_state not in ('prepared', 'cancelled') then
    raise exception 'Invalid outgoing action state transition';
  end if;

  return new;
end
$function$;

create trigger trg_outgoing_actions_validate_insert
before insert on atp_test.outgoing_actions
for each row execute function atp_test.validate_outgoing_action_insert();

create trigger trg_outgoing_actions_guard_update
before update on atp_test.outgoing_actions
for each row execute function atp_test.guard_outgoing_action_update();

create trigger trg_outgoing_actions_guard_delete
before delete on atp_test.outgoing_actions
for each row execute function atp_test.guard_db05_history_delete();

-- One physical send attempt. outcome_unknown is intentionally not retryable
-- until reconciliation proves that the external side effect did not happen.
create table atp_test.delivery_attempts (
  delivery_attempt_id uuid primary key default gen_random_uuid(),
  outgoing_action_id uuid not null,
  call_id uuid not null,
  operation_id uuid not null,
  attempt_id uuid not null,
  provider_request_id text,
  transport_result atp_test.transport_result not null,
  provider_status atp_test.delivery_provider_status not null,
  outcome_state atp_test.operation_state not null,
  safe_retry_allowed boolean not null default false,
  delivered_at timestamptz,
  error_class text,
  error_code text,
  reconciliation_state atp_test.delivery_reconciliation_state not null default 'not_required',
  reconciliation_operation_id uuid,
  reconciled_at timestamptz,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),

  constraint delivery_attempts_final_outcome
    check (
      outcome_state in (
        'succeeded',
        'failed_retryable',
        'failed_requires_fix',
        'outcome_unknown'
      )
    ),
  constraint delivery_attempts_completed_after_requested
    check (completed_at is null or completed_at >= requested_at),
  constraint delivery_attempts_delivered_shape
    check (
      provider_status <> 'delivered'
      or (
        outcome_state = 'succeeded'
        and transport_result = 'transport_succeeded'
        and delivered_at is not null
        and not safe_retry_allowed
      )
    ),
  constraint delivery_attempts_retry_shape
    check (
      (outcome_state = 'failed_retryable' and safe_retry_allowed)
      or
      (outcome_state <> 'failed_retryable' and not safe_retry_allowed)
    ),
  constraint delivery_attempts_succeeded_shape
    check (
      outcome_state <> 'succeeded'
      or (
        provider_status = 'delivered'
        and transport_result = 'transport_succeeded'
        and delivered_at is not null
      )
    ),
  constraint delivery_attempts_unknown_shape
    check (
      outcome_state <> 'outcome_unknown'
      or (
        provider_status in ('not_confirmed', 'unknown', 'accepted')
        and not safe_retry_allowed
        and reconciliation_state = 'pending'
      )
    ),
  constraint delivery_attempts_nonunknown_reconciliation
    check (
      outcome_state = 'outcome_unknown'
      or reconciliation_state = 'not_required'
    ),
  constraint delivery_attempts_reconciliation_metadata
    check (
      reconciliation_state in ('not_required', 'pending')
      or (
        reconciliation_operation_id is not null
        and reconciled_at is not null
      )
    ),
  constraint delivery_attempts_action_attempt_unique
    unique (outgoing_action_id, attempt_id),
  constraint delivery_attempts_action_same_call
    foreign key (outgoing_action_id, call_id)
    references atp_test.outgoing_actions(outgoing_action_id, call_id)
    on delete restrict,
  constraint delivery_attempts_operation_same_call
    foreign key (operation_id, call_id)
    references atp_test.operations(operation_id, call_id)
    on delete restrict,
  constraint delivery_attempts_attempt_same_operation
    foreign key (attempt_id, operation_id)
    references atp_test.operation_attempts(attempt_id, operation_id)
    on delete restrict,
  constraint delivery_attempts_reconciliation_operation_same_call
    foreign key (reconciliation_operation_id, call_id)
    references atp_test.operations(operation_id, call_id)
    on delete restrict
);

create index ix_delivery_attempts_action_created
  on atp_test.delivery_attempts (outgoing_action_id, created_at);

create function atp_test.guard_delivery_attempt_insert()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_action_state atp_test.outgoing_action_state;
  v_attempt_state atp_test.operation_state;
  v_attempt_transport atp_test.transport_result;
begin
  select action_state
  into v_action_state
  from atp_test.outgoing_actions
  where outgoing_action_id = new.outgoing_action_id
    and call_id = new.call_id;

  if v_action_state is distinct from 'prepared' then
    raise exception 'Cannot deliver a non-prepared/cancelled outgoing action';
  end if;

  if exists (
    select 1
    from atp_test.delivery_attempts d
    where d.outgoing_action_id = new.outgoing_action_id
      and (
        d.provider_status = 'delivered'
        or d.reconciliation_state = 'confirmed_delivered'
      )
  ) then
    raise exception 'Confirmed delivery forbids another attempt';
  end if;

  if exists (
    select 1
    from atp_test.delivery_attempts d
    where d.outgoing_action_id = new.outgoing_action_id
      and d.outcome_state = 'outcome_unknown'
      and d.reconciliation_state in ('pending', 'unresolved')
  ) then
    raise exception
      'outcome_unknown requires reconciliation before any retry';
  end if;

  select attempt_state, transport_result
  into v_attempt_state, v_attempt_transport
  from atp_test.operation_attempts
  where attempt_id = new.attempt_id
    and operation_id = new.operation_id;

  if v_attempt_state is distinct from new.outcome_state
     or v_attempt_transport is distinct from new.transport_result
  then
    raise exception
      'Delivery attempt outcome/transport must match exact operation attempt';
  end if;

  return new;
end
$function$;

create function atp_test.guard_delivery_attempt_update()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_old_semantic jsonb;
  v_new_semantic jsonb;
  v_recon_state atp_test.operation_state;
begin
  if old.outcome_state <> 'outcome_unknown' then
    raise exception 'Only outcome_unknown delivery may be reconciled';
  end if;

  v_old_semantic := to_jsonb(old)
    - 'reconciliation_state'
    - 'reconciliation_operation_id'
    - 'reconciled_at';
  v_new_semantic := to_jsonb(new)
    - 'reconciliation_state'
    - 'reconciliation_operation_id'
    - 'reconciled_at';

  if v_old_semantic is distinct from v_new_semantic then
    raise exception 'Original delivery attempt facts are immutable';
  end if;

  if old.reconciliation_state <> 'pending'
     or new.reconciliation_state not in (
       'confirmed_delivered',
       'confirmed_not_delivered',
       'unresolved'
     )
  then
    raise exception 'Invalid delivery reconciliation transition';
  end if;

  if new.reconciliation_operation_id is null
     or new.reconciled_at is null
  then
    raise exception 'Reconciliation result requires operation and time';
  end if;

  select operation_state
  into v_recon_state
  from atp_test.operations
  where operation_id = new.reconciliation_operation_id
    and call_id = new.call_id;

  if v_recon_state is distinct from 'succeeded' then
    raise exception 'Reconciliation operation must be succeeded';
  end if;

  return new;
end
$function$;

create function atp_test.guard_delivery_attempt_delete()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  raise exception 'Delivery attempts are immutable history and cannot be deleted';
end
$function$;

create trigger trg_delivery_attempts_guard_insert
before insert on atp_test.delivery_attempts
for each row execute function atp_test.guard_delivery_attempt_insert();

create trigger trg_delivery_attempts_guard_update
before update on atp_test.delivery_attempts
for each row execute function atp_test.guard_delivery_attempt_update();

create trigger trg_delivery_attempts_guard_delete
before delete on atp_test.delivery_attempts
for each row execute function atp_test.guard_delivery_attempt_delete();

-- A dispute is a request for review, not a direct score edit.
create table atp_test.analysis_disputes (
  dispute_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  analysis_id uuid not null,
  claim_id uuid,
  evidence_id uuid,
  author_ref text not null,
  reason text not null,
  dispute_state atp_test.dispute_state not null default 'open',
  resolution_reason text,
  resolved_by_ref text,
  opened_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),

  constraint analysis_disputes_author_not_blank
    check (btrim(author_ref) <> ''),
  constraint analysis_disputes_reason_not_blank
    check (btrim(reason) <> ''),
  constraint analysis_disputes_resolution_metadata
    check (
      dispute_state in ('open', 'under_review')
      or (
        resolution_reason is not null
        and btrim(resolution_reason) <> ''
        and resolved_by_ref is not null
        and btrim(resolved_by_ref) <> ''
        and resolved_at is not null
      )
    ),
  constraint analysis_disputes_id_call_unique
    unique (dispute_id, call_id),
  constraint analysis_disputes_analysis_same_call
    foreign key (analysis_id, call_id)
    references atp_test.analysis_versions(analysis_id, call_id)
    on delete restrict,
  constraint analysis_disputes_claim_same_analysis
    foreign key (claim_id, analysis_id)
    references atp_test.analysis_claims(claim_id, analysis_id)
    on delete restrict,
  constraint analysis_disputes_evidence_same_analysis
    foreign key (evidence_id, analysis_id)
    references atp_test.evidence_sets(evidence_id, analysis_id)
    on delete restrict
);

create function atp_test.guard_analysis_dispute_initial_state()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  if new.dispute_state <> 'open'
     or new.resolution_reason is not null
     or new.resolved_by_ref is not null
     or new.resolved_at is not null
  then
    raise exception 'Dispute must be inserted as open';
  end if;
  return new;
end
$function$;

create function atp_test.guard_analysis_dispute_update()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_old_semantic jsonb;
  v_new_semantic jsonb;
begin
  if old.dispute_state in ('resolved', 'rejected') then
    raise exception 'Resolved/rejected dispute is immutable';
  end if;

  v_old_semantic := to_jsonb(old)
    - 'dispute_state'
    - 'resolution_reason'
    - 'resolved_by_ref'
    - 'resolved_at';
  v_new_semantic := to_jsonb(new)
    - 'dispute_state'
    - 'resolution_reason'
    - 'resolved_by_ref'
    - 'resolved_at';

  if v_old_semantic is distinct from v_new_semantic then
    raise exception 'Dispute target/author/reason are immutable';
  end if;

  if old.dispute_state = 'open'
     and new.dispute_state not in ('open', 'under_review', 'resolved', 'rejected')
  then
    raise exception 'Invalid dispute transition';
  end if;

  if old.dispute_state = 'under_review'
     and new.dispute_state not in ('under_review', 'resolved', 'rejected')
  then
    raise exception 'Invalid dispute transition';
  end if;

  return new;
end
$function$;

create trigger trg_analysis_disputes_guard_initial
before insert on atp_test.analysis_disputes
for each row execute function atp_test.guard_analysis_dispute_initial_state();

create trigger trg_analysis_disputes_guard_update
before update on atp_test.analysis_disputes
for each row execute function atp_test.guard_analysis_dispute_update();

create trigger trg_analysis_disputes_guard_delete
before delete on atp_test.analysis_disputes
for each row execute function atp_test.guard_db05_history_delete();

-- Typed correction record. It records a controlled correction but never
-- rewrites the original source/analysis row itself.
create table atp_test.corrections (
  correction_id uuid primary key default gen_random_uuid(),
  call_id uuid not null references atp_test.calls(call_id) on delete restrict,
  target_type atp_test.correction_target_type not null,
  target_manager_id uuid references atp_test.managers(manager_id) on delete restrict,
  target_role_assignment_version_id uuid,
  target_transcript_id uuid,
  target_analysis_id uuid,
  target_business_confirmation_id uuid,
  target_callback_link_id uuid,
  target_outgoing_action_id uuid,
  before_ref text,
  after_ref text,
  before_value jsonb,
  after_value jsonb,
  actor_ref text not null,
  reason text not null,
  correction_state atp_test.correction_state not null default 'proposed',
  source_dispute_id uuid,
  apply_operation_id uuid,
  applied_at timestamptz,
  created_at timestamptz not null default now(),

  constraint corrections_target_exactly_one
    check (
      num_nonnulls(
        target_manager_id,
        target_role_assignment_version_id,
        target_transcript_id,
        target_analysis_id,
        target_business_confirmation_id,
        target_callback_link_id,
        target_outgoing_action_id
      ) = 1
    ),
  constraint corrections_target_shape
    check (
      (target_type = 'manager' and target_manager_id is not null)
      or
      (target_type = 'role_assignment' and target_role_assignment_version_id is not null)
      or
      (target_type = 'transcript' and target_transcript_id is not null)
      or
      (target_type = 'analysis' and target_analysis_id is not null)
      or
      (target_type = 'business_confirmation' and target_business_confirmation_id is not null)
      or
      (target_type = 'callback_link' and target_callback_link_id is not null)
      or
      (target_type = 'outgoing_action' and target_outgoing_action_id is not null)
    ),
  constraint corrections_before_value_object
    check (before_value is null or jsonb_typeof(before_value) = 'object'),
  constraint corrections_after_value_object
    check (after_value is null or jsonb_typeof(after_value) = 'object'),
  constraint corrections_actor_not_blank
    check (btrim(actor_ref) <> ''),
  constraint corrections_reason_not_blank
    check (btrim(reason) <> ''),
  constraint corrections_applied_metadata
    check (
      correction_state <> 'applied'
      or (apply_operation_id is not null and applied_at is not null)
    ),
  constraint corrections_role_same_call
    foreign key (target_role_assignment_version_id, call_id)
    references atp_test.role_assignment_versions(role_assignment_version_id, call_id)
    on delete restrict,
  constraint corrections_transcript_same_call
    foreign key (target_transcript_id, call_id)
    references atp_test.raw_transcripts(transcript_id, call_id)
    on delete restrict,
  constraint corrections_analysis_same_call
    foreign key (target_analysis_id, call_id)
    references atp_test.analysis_versions(analysis_id, call_id)
    on delete restrict,
  constraint corrections_confirmation_same_call
    foreign key (target_business_confirmation_id, call_id)
    references atp_test.business_confirmations(confirmation_id, call_id)
    on delete restrict,
  constraint corrections_callback_same_call
    foreign key (target_callback_link_id, call_id)
    references atp_test.callback_links(callback_link_id, callback_call_id)
    on delete restrict,
  constraint corrections_outgoing_same_call
    foreign key (target_outgoing_action_id, call_id)
    references atp_test.outgoing_actions(outgoing_action_id, call_id)
    on delete restrict,
  constraint corrections_dispute_same_call
    foreign key (source_dispute_id, call_id)
    references atp_test.analysis_disputes(dispute_id, call_id)
    on delete restrict,
  constraint corrections_operation_same_call
    foreign key (apply_operation_id, call_id)
    references atp_test.operations(operation_id, call_id)
    on delete restrict
);

create function atp_test.guard_correction_initial_state()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  if new.correction_state <> 'proposed'
     or new.apply_operation_id is not null
     or new.applied_at is not null
  then
    raise exception
      'Correction must be inserted as proposed; apply/reject is a separate operation';
  end if;
  return new;
end
$function$;

create function atp_test.guard_correction_update()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_old_semantic jsonb;
  v_new_semantic jsonb;
  v_apply_state atp_test.operation_state;
begin
  if old.correction_state <> 'proposed' then
    raise exception 'Applied/rejected correction is immutable';
  end if;

  v_old_semantic := to_jsonb(old)
    - 'correction_state'
    - 'apply_operation_id'
    - 'applied_at';
  v_new_semantic := to_jsonb(new)
    - 'correction_state'
    - 'apply_operation_id'
    - 'applied_at';

  if v_old_semantic is distinct from v_new_semantic then
    raise exception 'Correction target/before/after/actor/reason are immutable';
  end if;

  if new.correction_state not in ('proposed', 'applied', 'rejected') then
    raise exception 'Invalid correction transition';
  end if;

  if new.correction_state = 'applied' then
    select operation_state
    into v_apply_state
    from atp_test.operations
    where operation_id = new.apply_operation_id
      and call_id = new.call_id;

    if v_apply_state is distinct from 'succeeded' then
      raise exception 'Applied correction requires succeeded apply operation';
    end if;
  end if;

  return new;
end
$function$;

create trigger trg_corrections_guard_initial
before insert on atp_test.corrections
for each row execute function atp_test.guard_correction_initial_state();

create trigger trg_corrections_guard_update
before update on atp_test.corrections
for each row execute function atp_test.guard_correction_update();

create trigger trg_corrections_guard_delete
before delete on atp_test.corrections
for each row execute function atp_test.guard_db05_history_delete();

-- Generic administrative audit metadata. This is intentionally append-only.
create table atp_test.audit_events (
  audit_event_id uuid primary key default gen_random_uuid(),
  scope_ref text not null default 'atp_test',
  environment_ref text not null default 'test',
  actor_ref text not null,
  actor_capability text not null,
  action_type text not null,
  target_type text not null,
  target_ref text not null,
  before_ref text,
  after_ref text,
  reason text,
  operation_id uuid references atp_test.operations(operation_id) on delete restrict,
  result atp_test.audit_result not null,
  error_code text,
  source_channel text not null default 'backend',
  safe_details jsonb not null default '{}'::jsonb,
  requested_at timestamptz not null default now(),
  result_at timestamptz,
  created_at timestamptz not null default now(),

  constraint audit_events_scope_is_test
    check (scope_ref = 'atp_test'),
  constraint audit_events_environment_is_test
    check (environment_ref = 'test'),
  constraint audit_events_actor_not_blank
    check (btrim(actor_ref) <> ''),
  constraint audit_events_capability_not_blank
    check (btrim(actor_capability) <> ''),
  constraint audit_events_action_not_blank
    check (btrim(action_type) <> ''),
  constraint audit_events_target_type_not_blank
    check (btrim(target_type) <> ''),
  constraint audit_events_target_ref_not_blank
    check (btrim(target_ref) <> ''),
  constraint audit_events_source_channel_not_blank
    check (btrim(source_channel) <> ''),
  constraint audit_events_safe_details_object
    check (jsonb_typeof(safe_details) = 'object'),
  constraint audit_events_result_time
    check (result_at is not null and result_at >= requested_at)
);

create function atp_test.guard_audit_event_append_only()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  raise exception 'Audit events are append-only';
end
$function$;

create trigger trg_audit_events_append_only
before update or delete on atp_test.audit_events
for each row execute function atp_test.guard_audit_event_append_only();

commit;
