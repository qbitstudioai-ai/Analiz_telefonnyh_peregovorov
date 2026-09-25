-- DB-06 verification
-- TEST/LOCAL ONLY.
-- Run after DB-01..DB-06 migrations.
-- Catalog/formula checks plus negative calls; transaction is rolled back.

begin;

do $verify$
declare
  v_missing text;
  v_count integer;
  v_definition text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-06 verification failed: schema atp_test does not exist';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('v_dashboard_business_confirmations_current'),
      ('v_dashboard_delivery_current'),
      ('v_dashboard_processing_quality_current'),
      ('v_dashboard_speech_metrics_current'),
      ('v_dashboard_zvonki'),
      ('v_dashboard_obshchaya_kartina'),
      ('v_dashboard_menedzhery'),
      ('v_dashboard_kriterii'),
      ('v_dashboard_etapy'),
      ('v_dashboard_oshibki'),
      ('v_dashboard_rezultaty'),
      ('v_dashboard_kachestvo')
  ) as required(required_relation)
  where to_regclass('atp_test.' || required.required_relation) is null;

  if v_missing is not null then
    raise exception
      'DB-06 verification failed: missing view(s): %',
      v_missing;
  end if;

  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname in (
      'dashboard_filter_call_ids',
      'dashboard_overview',
      'dashboard_manager_metrics',
      'dashboard_criterion_metrics',
      'dashboard_stage_metrics',
      'dashboard_observation_metrics',
      'dashboard_result_metrics'
    );

  if v_count <> 7 then
    raise exception
      'DB-06 verification failed: expected 7 dashboard functions, found %',
      v_count;
  end if;

  -- Call list must originate from calls, not call_events: one logical call row.
  select pg_get_viewdef('atp_test.v_dashboard_zvonki'::regclass, true)
  into v_definition;

  if v_definition not ilike '%from atp_test.calls%'
     or v_definition ilike '%from atp_test.call_events%'
  then
    raise exception
      'DB-06 verification failed: call dashboard is not based on logical calls';
  end if;

  -- The four terminal categories are explicit and a disputed analysis cannot
  -- become evaluated/official while the dispute remains open.
  if v_definition not ilike '%evaluated_client%'
     or v_definition not ilike '%excluded%'
     or v_definition not ilike '%missed_client%'
     or v_definition not ilike '%pending_or_technical%'
     or v_definition not ilike '%has_open_dispute%'
     or v_definition not ilike '%reliable%'
  then
    raise exception
      'DB-06 verification failed: canonical call categories/official score logic missing';
  end if;

  -- AI result and trusted CRM/human fact must be distinguishable.
  select pg_get_viewdef('atp_test.v_dashboard_rezultaty'::regclass, true)
  into v_definition;

  if v_definition not ilike '%''ai''%'
     or v_definition not ilike '%v_dashboard_business_confirmations_current%'
     or v_definition not ilike '%aggregate_eligible%'
  then
    raise exception
      'DB-06 verification failed: AI/CRM result sources are mixed or dispute gate missing';
  end if;

  -- Current CRM facts must exclude cancellation but preserve source history.
  select pg_get_viewdef(
    'atp_test.v_dashboard_business_confirmations_current'::regclass,
    true
  )
  into v_definition;

  if v_definition not ilike '%event_kind%'
     or v_definition not ilike '%cancel%'
     or v_definition not ilike '%row_number%'
  then
    raise exception
      'DB-06 verification failed: current CRM event-chain selection missing';
  end if;

  -- Quality view may expose speech values only when speech metric reliability
  -- is reliable.
  select pg_get_viewdef('atp_test.v_dashboard_kachestvo'::regclass, true)
  into v_definition;

  if v_definition not ilike '%speech_metrics_reliability%'
     or v_definition not ilike '%reliable%'
     or v_definition not ilike '%manager_talk_ratio%'
  then
    raise exception
      'DB-06 verification failed: speech metric quality gate missing';
  end if;

  -- Shared filter function owns the [start, end) period and global filters.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname = 'dashboard_filter_call_ids';

  if v_definition not ilike '%started_at >= p_start%'
     or v_definition not ilike '%started_at < p_end%'
     or v_definition not ilike '%manager_id%'
     or v_definition not ilike '%department_ref%'
     or v_definition not ilike '%source_adapter_code%'
     or v_definition not ilike '%direction%'
     or v_definition not ilike '%occurrence_kind%'
     or v_definition not ilike '%reliability%'
     or v_definition not ilike '%classification%'
     or v_definition not ilike '%ai_outcome_type%'
     or v_definition not ilike '%crm_fact_type%'
  then
    raise exception
      'DB-06 verification failed: shared global filter contract incomplete';
  end if;

  -- Official overview average must use official_score/reliable rows and the
  -- activity decomposition must expose exactly the four mutually-exclusive flags.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname = 'dashboard_overview';

  if v_definition not ilike '%avg(official_score)%'
     or v_definition not ilike '%is_reliable_analysis%'
     or v_definition not ilike '%is_evaluated_client%'
     or v_definition not ilike '%is_excluded%'
     or v_definition not ilike '%is_missed_client%'
     or v_definition not ilike '%is_pending_or_technical%'
     or v_definition not ilike '%p_callback_window%'
  then
    raise exception
      'DB-06 verification failed: overview formulas incomplete';
  end if;

  -- Criterion average excludes N/A and disputed/preliminary analyses.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname = 'dashboard_criterion_metrics';

  if v_definition not ilike '%k.applicable%'
     or v_definition not ilike '%analysis_reliability = ''reliable''%'
     or v_definition not ilike '%not k.has_open_dispute%'
  then
    raise exception
      'DB-06 verification failed: criterion metric N/A/reliability/dispute gate missing';
  end if;

  -- Stage denominator is applicable calls, not all calls.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname = 'dashboard_stage_metrics';

  if v_definition not ilike '%where e.applicable%'
     or v_definition not ilike '%e.required and not e.reached%'
     or v_definition not ilike '%analysis_reliability = ''reliable''%'
  then
    raise exception
      'DB-06 verification failed: stage applicability/reliability formula missing';
  end if;

  -- Observation share must derive its denominator from applicable criterion/
  -- stage context rather than making row existence itself the denominator.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname = 'dashboard_observation_metrics';

  if v_definition not ilike '%criterion_scores%'
     or v_definition not ilike '%stage_results%'
     or v_definition not ilike '%applicable_calls%'
     or v_definition not ilike '%not o.has_open_dispute%'
  then
    raise exception
      'DB-06 verification failed: observation denominator formula missing';
  end if;

  -- Aggregate result metrics retain explicit source kind and drill-down call IDs.
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atp_test'
    and p.proname = 'dashboard_result_metrics';

  if v_definition not ilike '%result_source%'
     or v_definition not ilike '%array_agg%'
     or v_definition not ilike '%aggregate_eligible%'
  then
    raise exception
      'DB-06 verification failed: result source/drill-down/dispute formula missing';
  end if;

  -- Negative execution checks do not need fixture data.
  begin
    perform *
    from atp_test.dashboard_filter_call_ids(
      now(),
      now() - interval '1 minute',
      '{}'::jsonb
    );

    raise exception
      'DB-06 verification failed: invalid period was accepted';
  exception
    when raise_exception then
      if sqlerrm like 'DB-06 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Dashboard period must have non-null start < end%' then
        raise;
      end if;
  end;

  begin
    perform *
    from atp_test.dashboard_filter_call_ids(
      now() - interval '1 hour',
      now(),
      '[]'::jsonb
    );

    raise exception
      'DB-06 verification failed: non-object filters were accepted';
  exception
    when raise_exception then
      if sqlerrm like 'DB-06 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Dashboard filters must be a JSON object%' then
        raise;
      end if;
  end;

  begin
    perform *
    from atp_test.dashboard_overview(
      now() - interval '1 hour',
      now(),
      '{}'::jsonb,
      now(),
      interval '-1 second',
      null,
      null
    );

    raise exception
      'DB-06 verification failed: negative callback window was accepted';
  exception
    when raise_exception then
      if sqlerrm like 'DB-06 verification failed:%' then
        raise;
      end if;
      if sqlerrm not like 'Callback window cannot be negative%' then
        raise;
      end if;
  end;

  raise notice 'DB-06 verification passed';
end
$verify$;

rollback;
