-- DB-01 rollback
-- APPROVED WORKING CONTOUR. Rollback is limited to schema shablon_analiz_telefonnyh_peregovorov and requires an explicit safety check before execution.
-- This script is destructive for schema shablon_analiz_telefonnyh_peregovorov.
-- It intentionally refuses to run if DB-01 is not the only migration present
-- in the schema. It does not remove pgcrypto because that extension may be
-- shared by other schemas/components.

begin;

do $guard$
declare
  v_expected_count integer;
  v_extra_tables text;
begin
  if not exists (
    select 1
    from pg_namespace
    where nspname = 'shablon_analiz_telefonnyh_peregovorov'
  ) then
    raise exception
      'DB-01 rollback refused: schema shablon_analiz_telefonnyh_peregovorov does not exist';
  end if;

  select count(*)
  into v_expected_count
  from pg_tables
  where schemaname = 'shablon_analiz_telefonnyh_peregovorov'
    and tablename in (
      'managers',
      'calls',
      'call_events',
      'operations',
      'operation_attempts',
      'filter_decisions',
      'call_links',
      'temporary_audio_artifacts'
    );

  if v_expected_count <> 8 then
    raise exception
      'DB-01 rollback refused: expected all 8 DB-01 tables, found %. Inspect the schema manually.',
      v_expected_count;
  end if;

  select string_agg(tablename::text, ', ' order by tablename::text)
  into v_extra_tables
  from pg_tables
  where schemaname = 'shablon_analiz_telefonnyh_peregovorov'
    and tablename not in (
      'managers',
      'calls',
      'call_events',
      'operations',
      'operation_attempts',
      'filter_decisions',
      'call_links',
      'temporary_audio_artifacts'
    );

  if v_extra_tables is not null then
    raise exception
      'DB-01 rollback refused: later/unknown tables exist in shablon_analiz_telefonnyh_peregovorov: %',
      v_extra_tables;
  end if;
end
$guard$;

drop table shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts;
drop table shablon_analiz_telefonnyh_peregovorov.call_links;
drop table shablon_analiz_telefonnyh_peregovorov.filter_decisions;
drop table shablon_analiz_telefonnyh_peregovorov.operation_attempts;
drop table shablon_analiz_telefonnyh_peregovorov.call_events;
drop table shablon_analiz_telefonnyh_peregovorov.operations;
drop table shablon_analiz_telefonnyh_peregovorov.calls;
drop table shablon_analiz_telefonnyh_peregovorov.managers;

drop function shablon_analiz_telefonnyh_peregovorov.set_updated_at();

drop type shablon_analiz_telefonnyh_peregovorov.audio_cleanup_state;
drop type shablon_analiz_telefonnyh_peregovorov.audio_acquisition_state;
drop type shablon_analiz_telefonnyh_peregovorov.transport_result;
drop type shablon_analiz_telefonnyh_peregovorov.filter_outcome;
drop type shablon_analiz_telefonnyh_peregovorov.answer_status;
drop type shablon_analiz_telefonnyh_peregovorov.call_direction;
drop type shablon_analiz_telefonnyh_peregovorov.call_occurrence_kind;
drop type shablon_analiz_telefonnyh_peregovorov.call_classification;
drop type shablon_analiz_telefonnyh_peregovorov.call_processing_state;
drop type shablon_analiz_telefonnyh_peregovorov.operation_state;
drop type shablon_analiz_telefonnyh_peregovorov.contract_decision;

drop schema shablon_analiz_telefonnyh_peregovorov restrict;

commit;
