-- DB-06
-- Canonical dashboard metric rows and server-side metric functions.
-- TEST/LOCAL ONLY. Depends on DB-01..DB-05.
--
-- Views keep drill-down call_id/provenance. Metric functions use one shared
-- filter contract so cards/tables/exports cannot silently use another sample.

begin;

do $guard$
declare
  v_missing text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-06 requires schema atp_test';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('calls'),
      ('managers'),
      ('filter_decisions'),
      ('processing_quality'),
      ('speech_metrics'),
      ('analysis_versions'),
      ('criterion_scores'),
      ('stage_results'),
      ('analysis_observations'),
      ('ai_inferred_outcomes'),
      ('evidence_sets'),
      ('business_confirmations'),
      ('callback_links'),
      ('outgoing_actions'),
      ('delivery_attempts')
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
    raise exception 'DB-06 requires DB-01..DB-05. Missing: %', v_missing;
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname in (
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
        'v_dashboard_kachestvo'
      )
  ) then
    raise exception 'DB-06 refuses to run because one or more DB-06 views already exist';
  end if;
end
$guard$;

-- Latest trusted event in each business-fact family. A cancelled family is
-- absent from current facts but remains in immutable history.
create view atp_test.v_dashboard_business_confirmations_current as
with ranked as (
  select
    bc.*,
    row_number() over (
      partition by bc.fact_family_ref
      order by bc.event_no desc, bc.created_at desc, bc.confirmation_id
    ) as rn
  from atp_test.business_confirmations bc
)
select
  confirmation_id,
  call_id,
  fact_family_ref,
  event_no,
  event_kind,
  fact_type,
  source_kind,
  source_system_code,
  source_event_key,
  external_fact_id,
  client_ref,
  deal_ref,
  fact_value,
  fact_status,
  fact_occurred_at,
  received_at,
  human_actor_ref,
  created_by_operation_id,
  created_at
from ranked
where rn = 1
  and event_kind <> 'cancel';

comment on view atp_test.v_dashboard_business_confirmations_current is
  'Current trusted CRM/human facts. Cancelled families disappear from current metrics but remain in source history.';

-- One current delivery state per outgoing action.
create view atp_test.v_dashboard_delivery_current as
with latest_attempt as (
  select
    d.*,
    row_number() over (
      partition by d.outgoing_action_id
      order by d.requested_at desc, d.created_at desc, d.delivery_attempt_id
    ) as rn
  from atp_test.delivery_attempts d
)
select
  oa.outgoing_action_id,
  oa.call_id,
  oa.analysis_id,
  oa.purpose_code,
  oa.channel_ref,
  oa.recipient_ref,
  oa.message_version,
  oa.action_state,
  oa.created_at as action_created_at,
  la.delivery_attempt_id,
  la.operation_id as delivery_operation_id,
  la.attempt_id,
  la.provider_request_id,
  la.transport_result,
  la.provider_status,
  la.outcome_state,
  la.safe_retry_allowed,
  la.delivered_at,
  la.error_class,
  la.error_code,
  la.reconciliation_state,
  la.reconciliation_operation_id,
  la.reconciled_at,
  case
    when oa.action_state = 'cancelled' then 'cancelled'
    when la.delivery_attempt_id is null then 'pending'
    when la.reconciliation_state = 'confirmed_delivered' then 'delivered'
    when la.provider_status = 'delivered' and la.outcome_state = 'succeeded' then 'delivered'
    when la.outcome_state = 'outcome_unknown'
         and la.reconciliation_state in ('pending', 'unresolved') then 'unknown'
    when la.outcome_state = 'outcome_unknown'
         and la.reconciliation_state = 'confirmed_not_delivered' then 'not_delivered'
    when la.outcome_state = 'failed_retryable' then 'failed_retryable'
    when la.outcome_state = 'failed_requires_fix' then 'failed_requires_fix'
    else 'pending'
  end as delivery_state
from atp_test.outgoing_actions oa
left join latest_attempt la
  on la.outgoing_action_id = oa.outgoing_action_id
 and la.rn = 1;

-- Current processing quality for calls that have not yet reached current analysis.
create view atp_test.v_dashboard_processing_quality_current as
with ranked as (
  select
    q.*,
    row_number() over (
      partition by q.call_id
      order by q.version_no desc, q.created_at desc, q.quality_id
    ) as rn
  from atp_test.processing_quality q
  where q.version_state = 'current'
)
select
  quality_id,
  call_id,
  version_no,
  raw_transcript_id,
  role_assignment_version_id,
  audio_quality,
  transcription_metrics,
  role_metrics,
  overall_reliability,
  warning_codes,
  created_at
from ranked
where rn = 1;

create view atp_test.v_dashboard_speech_metrics_current as
with ranked as (
  select
    sm.*,
    row_number() over (
      partition by sm.call_id
      order by sm.version_no desc, sm.created_at desc, sm.speech_metrics_id
    ) as rn
  from atp_test.speech_metrics sm
  where sm.version_state = 'current'
)
select
  speech_metrics_id,
  call_id,
  raw_transcript_id,
  role_assignment_version_id,
  quality_id,
  metrics_rules_version_ref,
  manager_talk_ratio,
  client_talk_ratio,
  total_pause_ms,
  interruption_count,
  manager_speech_rate_wpm,
  client_speech_rate_wpm,
  call_duration_ms,
  reliability,
  warning_codes,
  created_at
from ranked
where rn = 1;

-- One canonical row per logical call. Duplicate webhook rows never appear here
-- because they live in call_events, not calls.
create view atp_test.v_dashboard_zvonki as
with ai as (
  select
    a.analysis_id,
    array_agg(distinct a.outcome_type order by a.outcome_type) as ai_outcome_types,
    jsonb_agg(
      jsonb_build_object(
        'ai_outcome_id', a.ai_outcome_id,
        'outcome_type', a.outcome_type,
        'target_action', a.target_action,
        'confidence', a.confidence,
        'expected_next_contact_at', a.expected_next_contact_at,
        'outcome_status', a.outcome_status
      )
      order by a.outcome_type, a.ai_outcome_id
    ) as ai_outcomes
  from atp_test.ai_inferred_outcomes a
  group by a.analysis_id
),
disputes as (
  select
    d.analysis_id,
    true as has_open_dispute
  from atp_test.analysis_disputes d
  where d.dispute_state in ('open', 'under_review')
  group by d.analysis_id
),
crm as (
  select
    bc.call_id,
    array_agg(distinct bc.fact_type order by bc.fact_type) as crm_fact_types,
    jsonb_agg(
      jsonb_build_object(
        'confirmation_id', bc.confirmation_id,
        'fact_family_ref', bc.fact_family_ref,
        'fact_type', bc.fact_type,
        'source_kind', bc.source_kind,
        'fact_status', bc.fact_status,
        'fact_occurred_at', bc.fact_occurred_at
      )
      order by bc.fact_type, bc.confirmation_id
    ) as crm_facts
  from atp_test.v_dashboard_business_confirmations_current bc
  group by bc.call_id
),
callbacks as (
  select
    cl.missed_call_id as call_id,
    count(*) filter (where cl.link_state = 'confirmed') as confirmed_callback_count,
    min(cl.delay_seconds) filter (where cl.link_state = 'confirmed') as first_callback_delay_seconds,
    array_agg(cl.callback_call_id order by cl.delay_seconds nulls last, cl.callback_call_id)
      filter (where cl.link_state = 'confirmed') as confirmed_callback_call_ids
  from atp_test.callback_links cl
  group by cl.missed_call_id
),
delivery as (
  select distinct on (d.call_id)
    d.call_id,
    d.outgoing_action_id,
    d.delivery_state,
    d.provider_status,
    d.outcome_state,
    d.reconciliation_state,
    d.delivered_at,
    d.action_created_at
  from atp_test.v_dashboard_delivery_current d
  order by d.call_id, d.action_created_at desc, d.outgoing_action_id desc
)
select
  c.call_id,
  c.source_adapter_code,
  c.connection_ref,
  c.manager_id,
  m.full_name as manager_name,
  m.department_ref,
  c.started_at,
  c.ended_at,
  c.duration_seconds,
  c.direction,
  c.answer_status,
  c.occurrence_kind,
  c.classification,
  c.processing_state,
  fd.filter_decision_id,
  fd.outcome as filter_outcome,
  fd.reason_code as filter_reason_code,
  av.analysis_id as current_analysis_id,
  av.raw_transcript_id as analysis_raw_transcript_id,
  av.role_assignment_version_id as analysis_role_assignment_version_id,
  av.pseudonymized_transcript_id as analysis_pseudonymized_transcript_id,
  av.privacy_package_id as analysis_privacy_package_id,
  av.overall_score,
  av.reliability as analysis_reliability,
  coalesce(disputes.has_open_dispute, false) as has_open_dispute,
  av.methodology_version_id,
  av.prompt_version_id,
  av.knowledge_publication_id,
  av.processing_quality_id,
  coalesce(ai.ai_outcome_types, '{}'::text[]) as ai_outcome_types,
  coalesce(ai.ai_outcomes, '[]'::jsonb) as ai_outcomes,
  coalesce(crm.crm_fact_types, '{}'::text[]) as crm_fact_types,
  coalesce(crm.crm_facts, '[]'::jsonb) as crm_facts,
  coalesce(callbacks.confirmed_callback_count, 0)::bigint as confirmed_callback_count,
  callbacks.first_callback_delay_seconds,
  coalesce(callbacks.confirmed_callback_call_ids, '{}'::uuid[]) as confirmed_callback_call_ids,
  delivery.outgoing_action_id as latest_outgoing_action_id,
  delivery.delivery_state as latest_delivery_state,
  delivery.provider_status as latest_provider_status,
  delivery.outcome_state as latest_delivery_outcome_state,
  delivery.reconciliation_state as latest_delivery_reconciliation_state,
  delivery.delivered_at as latest_delivered_at,
  case
    when c.classification = 'excluded'
      or fd.outcome = 'excluded'
      then 'excluded'
    when c.classification = 'missed'
      or c.answer_status = 'missed'
      or fd.outcome = 'missed'
      then 'missed_client'
    when c.classification = 'client'
      and av.analysis_id is not null
      and not coalesce(disputes.has_open_dispute, false)
      then 'evaluated_client'
    else 'pending_or_technical'
  end as terminal_metric_category,
  case
    when c.classification = 'client'
     and av.analysis_id is not null
     and av.reliability = 'reliable'
     and not coalesce(disputes.has_open_dispute, false)
    then av.overall_score
    else null
  end as official_score
from atp_test.calls c
left join atp_test.managers m
  on m.manager_id = c.manager_id
left join atp_test.filter_decisions fd
  on fd.filter_decision_id = c.current_filter_decision_id
left join atp_test.analysis_versions av
  on av.call_id = c.call_id
 and av.analysis_state = 'current'
left join ai
  on ai.analysis_id = av.analysis_id
left join disputes
  on disputes.analysis_id = av.analysis_id
left join crm
  on crm.call_id = c.call_id
left join callbacks
  on callbacks.call_id = c.call_id
left join delivery
  on delivery.call_id = c.call_id;

comment on view atp_test.v_dashboard_zvonki is
  'One row per logical call with current analysis and separate AI/CRM/delivery facts. Source for dashboard drill-down and global filtering.';

-- One row per call with mutually-exclusive activity flags.
create view atp_test.v_dashboard_obshchaya_kartina as
select
  z.*,
  (z.terminal_metric_category = 'evaluated_client') as is_evaluated_client,
  (z.terminal_metric_category = 'excluded') as is_excluded,
  (z.terminal_metric_category = 'missed_client') as is_missed_client,
  (z.terminal_metric_category = 'pending_or_technical') as is_pending_or_technical,
  (
    z.terminal_metric_category = 'evaluated_client'
    and z.analysis_reliability = 'reliable'
  ) as is_reliable_analysis,
  (
    z.terminal_metric_category = 'evaluated_client'
    and z.analysis_reliability = 'preliminary'
  ) as is_preliminary_analysis,
  (
    z.terminal_metric_category = 'evaluated_client'
    and z.analysis_reliability = 'technically_incomplete'
  ) as is_technically_incomplete_analysis,
  (
    z.classification = 'client'
    and z.occurrence_kind = 'first'
  ) as is_first_client_call,
  (
    z.classification = 'client'
    and z.occurrence_kind = 'repeat'
  ) as is_repeat_client_call,
  (z.confirmed_callback_count > 0) as has_confirmed_callback
from atp_test.v_dashboard_zvonki z;

-- Manager metric rows deliberately remain one-row-per-call; period/result filters
-- are applied before aggregation by dashboard_manager_metrics().
create view atp_test.v_dashboard_menedzhery as
select
  o.manager_id,
  o.manager_name,
  o.department_ref,
  o.call_id,
  o.started_at,
  o.source_adapter_code,
  o.direction,
  o.occurrence_kind,
  o.classification,
  o.terminal_metric_category,
  o.analysis_reliability,
  o.has_open_dispute,
  o.official_score,
  o.ai_outcome_types,
  o.crm_fact_types,
  o.is_evaluated_client,
  o.is_reliable_analysis,
  o.is_preliminary_analysis,
  o.is_technically_incomplete_analysis,
  o.is_missed_client,
  o.has_confirmed_callback,
  o.first_callback_delay_seconds
from atp_test.v_dashboard_obshchaya_kartina o
where o.manager_id is not null;

create view atp_test.v_dashboard_kriterii as
select
  z.call_id,
  z.started_at,
  z.manager_id,
  z.department_ref,
  z.source_adapter_code,
  z.direction,
  z.occurrence_kind,
  z.classification,
  z.current_analysis_id as analysis_id,
  z.analysis_reliability,
  z.has_open_dispute,
  cs.criterion_score_id,
  cs.criterion_code,
  cs.applicable,
  cs.score,
  cs.weight,
  cs.rationale,
  es.evidence_id
from atp_test.v_dashboard_zvonki z
join atp_test.criterion_scores cs
  on cs.analysis_id = z.current_analysis_id
left join atp_test.evidence_sets es
  on es.claim_id = cs.criterion_score_id
 and es.analysis_id = cs.analysis_id;

create view atp_test.v_dashboard_etapy as
with stage_rows as (
  select
    z.call_id,
    z.started_at,
    z.manager_id,
    z.department_ref,
    z.source_adapter_code,
    z.direction,
    z.occurrence_kind,
    z.classification,
    z.current_analysis_id as analysis_id,
    z.analysis_reliability,
    z.has_open_dispute,
    sr.stage_result_id,
    sr.stage_code,
    sr.applicable,
    sr.reached,
    sr.sort_order,
    sr.required,
    sr.explanation,
    es.evidence_id,
    max(sr.sort_order) filter (
      where sr.applicable and sr.reached
    ) over (partition by sr.analysis_id) as last_reached_sort_order
  from atp_test.v_dashboard_zvonki z
  join atp_test.stage_results sr
    on sr.analysis_id = z.current_analysis_id
  left join atp_test.evidence_sets es
    on es.claim_id = sr.stage_result_id
   and es.analysis_id = sr.analysis_id
)
select
  *,
  (
    applicable
    and reached
    and sort_order = last_reached_sort_order
  ) as is_last_reached_stage
from stage_rows;

create view atp_test.v_dashboard_oshibki as
select
  z.call_id,
  z.started_at,
  z.manager_id,
  z.department_ref,
  z.source_adapter_code,
  z.direction,
  z.occurrence_kind,
  z.classification,
  z.current_analysis_id as analysis_id,
  z.analysis_reliability,
  z.has_open_dispute,
  ao.observation_id,
  ao.observation_code,
  ao.observation_type,
  ao.applicable,
  ao.severity,
  ao.explanation,
  ao.criterion_code,
  ao.stage_code,
  es.evidence_id
from atp_test.v_dashboard_zvonki z
join atp_test.analysis_observations ao
  on ao.analysis_id = z.current_analysis_id
left join atp_test.evidence_sets es
  on es.claim_id = ao.observation_id
 and es.analysis_id = ao.analysis_id;

-- AI and CRM/human results share a reporting shape but remain explicitly
-- distinguished by result_source and never overwrite each other.
create view atp_test.v_dashboard_rezultaty as
select
  z.call_id,
  z.started_at,
  z.manager_id,
  z.department_ref,
  z.current_analysis_id as analysis_id,
  'ai'::text as result_source,
  aio.ai_outcome_id as result_ref,
  aio.outcome_type as result_code,
  aio.outcome_status as result_status,
  aio.confidence,
  aio.expected_next_contact_at as result_time,
  es.evidence_id,
  null::text as trusted_source_system,
  (not z.has_open_dispute) as aggregate_eligible
from atp_test.v_dashboard_zvonki z
join atp_test.ai_inferred_outcomes aio
  on aio.analysis_id = z.current_analysis_id
left join atp_test.evidence_sets es
  on es.claim_id = aio.ai_outcome_id
 and es.analysis_id = aio.analysis_id

union all

select
  z.call_id,
  z.started_at,
  z.manager_id,
  z.department_ref,
  null::uuid as analysis_id,
  bc.source_kind::text as result_source,
  bc.confirmation_id as result_ref,
  bc.fact_type as result_code,
  bc.fact_status as result_status,
  null::numeric as confidence,
  bc.fact_occurred_at as result_time,
  null::uuid as evidence_id,
  bc.source_system_code as trusted_source_system,
  true as aggregate_eligible
from atp_test.v_dashboard_zvonki z
join atp_test.v_dashboard_business_confirmations_current bc
  on bc.call_id = z.call_id;

create view atp_test.v_dashboard_kachestvo as
select
  z.call_id,
  z.started_at,
  z.manager_id,
  z.department_ref,
  z.source_adapter_code,
  z.direction,
  z.classification,
  z.processing_state,
  z.current_analysis_id as analysis_id,
  z.analysis_reliability,
  coalesce(z.processing_quality_id, qc.quality_id) as quality_id,
  coalesce(q_exact.overall_reliability, qc.overall_reliability) as processing_reliability,
  coalesce(q_exact.warning_codes, qc.warning_codes, '{}'::text[]) as processing_warning_codes,
  coalesce(q_exact.audio_quality, qc.audio_quality, '{}'::jsonb) as audio_quality,
  coalesce(q_exact.transcription_metrics, qc.transcription_metrics, '{}'::jsonb) as transcription_metrics,
  coalesce(q_exact.role_metrics, qc.role_metrics, '{}'::jsonb) as role_metrics,
  sm.speech_metrics_id,
  sm.reliability as speech_metrics_reliability,
  sm.warning_codes as speech_warning_codes,
  case
    when sm.reliability = 'reliable' then sm.manager_talk_ratio
    else null
  end as manager_talk_ratio,
  case
    when sm.reliability = 'reliable' then sm.client_talk_ratio
    else null
  end as client_talk_ratio,
  case
    when sm.reliability = 'reliable' then sm.total_pause_ms
    else null
  end as total_pause_ms,
  case
    when sm.reliability = 'reliable' then sm.interruption_count
    else null
  end as interruption_count,
  case
    when sm.reliability = 'reliable' then sm.manager_speech_rate_wpm
    else null
  end as manager_speech_rate_wpm,
  case
    when sm.reliability = 'reliable' then sm.call_duration_ms
    else null
  end as metric_call_duration_ms
from atp_test.v_dashboard_zvonki z
left join atp_test.processing_quality q_exact
  on q_exact.quality_id = z.processing_quality_id
left join atp_test.v_dashboard_processing_quality_current qc
  on qc.call_id = z.call_id
left join atp_test.v_dashboard_speech_metrics_current sm
  on sm.call_id = z.call_id
 and (
   z.current_analysis_id is null
   or (
     sm.raw_transcript_id = z.analysis_raw_transcript_id
     and sm.role_assignment_version_id = z.analysis_role_assignment_version_id
   )
 );

-- Shared global filter contract. p_start is inclusive, p_end is exclusive.
-- The dashboard server is responsible for converting a company's local period
-- into timestamptz boundaries before calling this function.
create function atp_test.dashboard_filter_call_ids(
  p_start timestamptz,
  p_end timestamptz,
  p_filters jsonb default '{}'::jsonb
)
returns table(call_id uuid)
language plpgsql
stable
set search_path = pg_catalog, atp_test
as $function$
begin
  if p_start is null or p_end is null or p_end <= p_start then
    raise exception 'Dashboard period must have non-null start < end';
  end if;

  if p_filters is null or jsonb_typeof(p_filters) <> 'object' then
    raise exception 'Dashboard filters must be a JSON object';
  end if;

  return query
  select z.call_id
  from atp_test.v_dashboard_zvonki z
  where z.started_at >= p_start
    and z.started_at < p_end
    and (
      not (p_filters ? 'manager_id')
      or z.manager_id = nullif(p_filters ->> 'manager_id', '')::uuid
    )
    and (
      not (p_filters ? 'department_ref')
      or z.department_ref = p_filters ->> 'department_ref'
    )
    and (
      not (p_filters ? 'source_adapter_code')
      or z.source_adapter_code = p_filters ->> 'source_adapter_code'
    )
    and (
      not (p_filters ? 'direction')
      or z.direction::text = p_filters ->> 'direction'
    )
    and (
      not (p_filters ? 'occurrence_kind')
      or z.occurrence_kind::text = p_filters ->> 'occurrence_kind'
    )
    and (
      not (p_filters ? 'reliability')
      or z.analysis_reliability::text = p_filters ->> 'reliability'
    )
    and (
      not (p_filters ? 'classification')
      or z.classification::text = p_filters ->> 'classification'
    )
    and (
      not (p_filters ? 'terminal_metric_category')
      or z.terminal_metric_category = p_filters ->> 'terminal_metric_category'
    )
    and (
      not (p_filters ? 'ai_outcome_type')
      or (p_filters ->> 'ai_outcome_type') = any(z.ai_outcome_types)
    )
    and (
      not (p_filters ? 'crm_fact_type')
      or (p_filters ->> 'crm_fact_type') = any(z.crm_fact_types)
    );
end
$function$;

create function atp_test.dashboard_overview(
  p_start timestamptz,
  p_end timestamptz,
  p_filters jsonb default '{}'::jsonb,
  p_as_of timestamptz default now(),
  p_callback_window interval default null,
  p_target_ai_outcome_codes text[] default null,
  p_target_crm_fact_types text[] default null
)
returns table(
  all_calls bigint,
  evaluated_client_calls bigint,
  excluded_calls bigint,
  missed_client_calls bigint,
  pending_or_technical_calls bigint,
  first_client_calls bigint,
  repeat_client_calls bigint,
  reliable_analyses bigint,
  preliminary_analyses bigint,
  technically_incomplete_analyses bigint,
  official_average_score numeric,
  target_ai_calls bigint,
  ai_conversion_pct numeric,
  confirmed_crm_calls bigint,
  confirmed_callbacks bigint,
  callback_rate_pct numeric,
  without_callback_after_window bigint,
  average_callback_seconds numeric
)
language plpgsql
stable
set search_path = pg_catalog, atp_test
as $function$
begin
  if p_as_of is null then
    raise exception 'Dashboard as-of time cannot be null';
  end if;

  if p_callback_window is not null and p_callback_window < interval '0 seconds' then
    raise exception 'Callback window cannot be negative';
  end if;

  return query
  with filtered as (
    select o.*
    from atp_test.v_dashboard_obshchaya_kartina o
    join atp_test.dashboard_filter_call_ids(p_start, p_end, p_filters) f
      on f.call_id = o.call_id
  ),
  agg as (
    select
      count(*)::bigint as all_calls,
      count(*) filter (where is_evaluated_client)::bigint as evaluated_client_calls,
      count(*) filter (where is_excluded)::bigint as excluded_calls,
      count(*) filter (where is_missed_client)::bigint as missed_client_calls,
      count(*) filter (where is_pending_or_technical)::bigint as pending_or_technical_calls,
      count(*) filter (where is_first_client_call)::bigint as first_client_calls,
      count(*) filter (where is_repeat_client_call)::bigint as repeat_client_calls,
      count(*) filter (where is_reliable_analysis)::bigint as reliable_analyses,
      count(*) filter (where is_preliminary_analysis)::bigint as preliminary_analyses,
      count(*) filter (where is_technically_incomplete_analysis)::bigint as technically_incomplete_analyses,
      avg(official_score) filter (where is_reliable_analysis) as official_average_score,
      count(*) filter (
        where p_target_ai_outcome_codes is not null
          and is_evaluated_client
          and ai_outcome_types && p_target_ai_outcome_codes
      )::bigint as target_ai_calls_raw,
      count(*) filter (
        where p_target_crm_fact_types is not null
          and crm_fact_types && p_target_crm_fact_types
      )::bigint as confirmed_crm_calls_raw,
      count(*) filter (
        where is_missed_client and has_confirmed_callback
      )::bigint as confirmed_callbacks,
      count(*) filter (
        where is_missed_client
          and not has_confirmed_callback
          and p_callback_window is not null
          and started_at + p_callback_window <= p_as_of
      )::bigint as without_callback_after_window,
      avg(first_callback_delay_seconds) filter (
        where is_missed_client and has_confirmed_callback
      ) as average_callback_seconds
    from filtered
  )
  select
    a.all_calls,
    a.evaluated_client_calls,
    a.excluded_calls,
    a.missed_client_calls,
    a.pending_or_technical_calls,
    a.first_client_calls,
    a.repeat_client_calls,
    a.reliable_analyses,
    a.preliminary_analyses,
    a.technically_incomplete_analyses,
    a.official_average_score,
    case
      when p_target_ai_outcome_codes is null then null
      else a.target_ai_calls_raw
    end as target_ai_calls,
    case
      when p_target_ai_outcome_codes is null then null
      else round(
        100.0 * a.target_ai_calls_raw
        / nullif(a.evaluated_client_calls, 0),
        2
      )
    end as ai_conversion_pct,
    case
      when p_target_crm_fact_types is null then null
      else a.confirmed_crm_calls_raw
    end as confirmed_crm_calls,
    a.confirmed_callbacks,
    round(
      100.0 * a.confirmed_callbacks
      / nullif(a.missed_client_calls, 0),
      2
    ) as callback_rate_pct,
    case
      when p_callback_window is null then null
      else a.without_callback_after_window
    end as without_callback_after_window,
    a.average_callback_seconds
  from agg a;
end
$function$;

create function atp_test.dashboard_manager_metrics(
  p_start timestamptz,
  p_end timestamptz,
  p_filters jsonb default '{}'::jsonb,
  p_target_ai_outcome_codes text[] default null,
  p_target_crm_fact_types text[] default null
)
returns table(
  manager_id uuid,
  manager_name text,
  department_ref text,
  evaluated_client_calls bigint,
  reliable_analyses bigint,
  preliminary_analyses bigint,
  technically_incomplete_analyses bigint,
  official_average_score numeric,
  target_ai_calls bigint,
  confirmed_crm_calls bigint,
  missed_client_calls bigint,
  confirmed_callbacks bigint,
  average_callback_seconds numeric
)
language sql
stable
set search_path = pg_catalog, atp_test
as $function$
  with filtered as (
    select m.*
    from atp_test.v_dashboard_menedzhery m
    join atp_test.dashboard_filter_call_ids(p_start, p_end, p_filters) f
      on f.call_id = m.call_id
  )
  select
    f.manager_id,
    max(f.manager_name) as manager_name,
    max(f.department_ref) as department_ref,
    count(*) filter (where f.is_evaluated_client)::bigint,
    count(*) filter (where f.is_reliable_analysis)::bigint,
    count(*) filter (where f.is_preliminary_analysis)::bigint,
    count(*) filter (where f.is_technically_incomplete_analysis)::bigint,
    avg(f.official_score) filter (where f.is_reliable_analysis),
    case
      when p_target_ai_outcome_codes is null then null
      else count(*) filter (
        where f.is_evaluated_client
          and f.ai_outcome_types && p_target_ai_outcome_codes
      )::bigint
    end,
    case
      when p_target_crm_fact_types is null then null
      else count(*) filter (
        where f.crm_fact_types && p_target_crm_fact_types
      )::bigint
    end,
    count(*) filter (where f.is_missed_client)::bigint,
    count(*) filter (
      where f.is_missed_client and f.has_confirmed_callback
    )::bigint,
    avg(f.first_callback_delay_seconds) filter (
      where f.is_missed_client and f.has_confirmed_callback
    )
  from filtered f
  group by f.manager_id
$function$;

create function atp_test.dashboard_criterion_metrics(
  p_start timestamptz,
  p_end timestamptz,
  p_filters jsonb default '{}'::jsonb
)
returns table(
  criterion_code text,
  applicable_calls bigint,
  average_score numeric,
  call_ids uuid[]
)
language sql
stable
set search_path = pg_catalog, atp_test
as $function$
  select
    k.criterion_code,
    count(distinct k.call_id)::bigint as applicable_calls,
    avg(k.score) as average_score,
    array_agg(distinct k.call_id order by k.call_id) as call_ids
  from atp_test.v_dashboard_kriterii k
  join atp_test.dashboard_filter_call_ids(p_start, p_end, p_filters) f
    on f.call_id = k.call_id
  where k.analysis_reliability = 'reliable'
    and not k.has_open_dispute
    and k.applicable
  group by k.criterion_code
$function$;

create function atp_test.dashboard_stage_metrics(
  p_start timestamptz,
  p_end timestamptz,
  p_filters jsonb default '{}'::jsonb
)
returns table(
  stage_code text,
  applicable_calls bigint,
  reached_calls bigint,
  reached_pct numeric,
  missed_required_calls bigint,
  reached_call_ids uuid[],
  missed_required_call_ids uuid[]
)
language sql
stable
set search_path = pg_catalog, atp_test
as $function$
  select
    e.stage_code,
    count(distinct e.call_id) filter (where e.applicable)::bigint as applicable_calls,
    count(distinct e.call_id) filter (where e.applicable and e.reached)::bigint as reached_calls,
    round(
      100.0 * count(distinct e.call_id) filter (where e.applicable and e.reached)
      / nullif(count(distinct e.call_id) filter (where e.applicable), 0),
      2
    ) as reached_pct,
    count(distinct e.call_id) filter (
      where e.applicable and e.required and not e.reached
    )::bigint as missed_required_calls,
    array_agg(distinct e.call_id order by e.call_id) filter (
      where e.applicable and e.reached
    ) as reached_call_ids,
    array_agg(distinct e.call_id order by e.call_id) filter (
      where e.applicable and e.required and not e.reached
    ) as missed_required_call_ids
  from atp_test.v_dashboard_etapy e
  join atp_test.dashboard_filter_call_ids(p_start, p_end, p_filters) f
    on f.call_id = e.call_id
  where e.analysis_reliability = 'reliable'
    and not e.has_open_dispute
  group by e.stage_code
$function$;

-- Observation denominator is derived from its explicit criterion/stage context.
-- With no context the observation is treated as analysis-wide and denominator is
-- all filtered reliable analyses. No absent observation is fabricated.
create function atp_test.dashboard_observation_metrics(
  p_start timestamptz,
  p_end timestamptz,
  p_filters jsonb default '{}'::jsonb
)
returns table(
  observation_code text,
  observation_type atp_test.observation_type,
  criterion_code text,
  stage_code text,
  observed_calls bigint,
  applicable_calls bigint,
  observation_pct numeric,
  managers_with_observation bigint,
  observed_call_ids uuid[]
)
language sql
stable
set search_path = pg_catalog, atp_test
as $function$
  with filtered_calls as (
    select f.call_id
    from atp_test.dashboard_filter_call_ids(p_start, p_end, p_filters) f
  ),
  filtered_reliable as (
    select z.call_id, z.current_analysis_id as analysis_id
    from atp_test.v_dashboard_zvonki z
    join filtered_calls f on f.call_id = z.call_id
    where z.analysis_reliability = 'reliable'
      and not z.has_open_dispute
      and z.current_analysis_id is not null
  ),
  contexts as (
    select distinct
      o.observation_code,
      o.observation_type,
      o.criterion_code,
      o.stage_code
    from atp_test.v_dashboard_oshibki o
    join filtered_calls f on f.call_id = o.call_id
    where o.analysis_reliability = 'reliable'
      and not o.has_open_dispute
      and o.applicable
  ),
  observed as (
    select
      o.observation_code,
      o.observation_type,
      o.criterion_code,
      o.stage_code,
      count(distinct o.call_id)::bigint as observed_calls,
      count(distinct o.manager_id)::bigint as managers_with_observation,
      array_agg(distinct o.call_id order by o.call_id) as observed_call_ids
    from atp_test.v_dashboard_oshibki o
    join filtered_calls f on f.call_id = o.call_id
    where o.analysis_reliability = 'reliable'
      and not o.has_open_dispute
      and o.applicable
    group by
      o.observation_code,
      o.observation_type,
      o.criterion_code,
      o.stage_code
  )
  select
    c.observation_code,
    c.observation_type,
    c.criterion_code,
    c.stage_code,
    coalesce(o.observed_calls, 0)::bigint as observed_calls,
    (
      select count(distinct fr.call_id)::bigint
      from filtered_reliable fr
      where (
        c.criterion_code is null
        or exists (
          select 1
          from atp_test.criterion_scores cs
          where cs.analysis_id = fr.analysis_id
            and cs.criterion_code = c.criterion_code
            and cs.applicable
        )
      )
      and (
        c.stage_code is null
        or exists (
          select 1
          from atp_test.stage_results sr
          where sr.analysis_id = fr.analysis_id
            and sr.stage_code = c.stage_code
            and sr.applicable
        )
      )
    ) as applicable_calls,
    round(
      100.0 * coalesce(o.observed_calls, 0)
      / nullif(
        (
          select count(distinct fr.call_id)
          from filtered_reliable fr
          where (
            c.criterion_code is null
            or exists (
              select 1
              from atp_test.criterion_scores cs
              where cs.analysis_id = fr.analysis_id
                and cs.criterion_code = c.criterion_code
                and cs.applicable
            )
          )
          and (
            c.stage_code is null
            or exists (
              select 1
              from atp_test.stage_results sr
              where sr.analysis_id = fr.analysis_id
                and sr.stage_code = c.stage_code
                and sr.applicable
            )
          )
        ),
        0
      ),
      2
    ) as observation_pct,
    coalesce(o.managers_with_observation, 0)::bigint,
    o.observed_call_ids
  from contexts c
  left join observed o
    on o.observation_code = c.observation_code
   and o.observation_type = c.observation_type
   and o.criterion_code is not distinct from c.criterion_code
   and o.stage_code is not distinct from c.stage_code
$function$;

create function atp_test.dashboard_result_metrics(
  p_start timestamptz,
  p_end timestamptz,
  p_filters jsonb default '{}'::jsonb
)
returns table(
  result_source text,
  result_code text,
  unique_calls bigint,
  call_ids uuid[]
)
language sql
stable
set search_path = pg_catalog, atp_test
as $function$
  select
    r.result_source,
    r.result_code,
    count(distinct r.call_id)::bigint as unique_calls,
    array_agg(distinct r.call_id order by r.call_id) as call_ids
  from atp_test.v_dashboard_rezultaty r
  join atp_test.dashboard_filter_call_ids(p_start, p_end, p_filters) f
    on f.call_id = r.call_id
  where r.aggregate_eligible
  group by r.result_source, r.result_code
$function$;

commit;
