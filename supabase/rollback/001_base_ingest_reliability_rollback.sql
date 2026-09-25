-- DB-01 rollback
-- APPROVED WORKING CONTOUR. Rollback is limited to schema shablon and requires an explicit safety check before execution.
-- This script is destructive for schema shablon.
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
    where nspname = 'shablon'
  ) then
    raise exception
      'DB-01 rollback refused: schema shablon does not exist';
  end if;

  select count(*)
  into v_expected_count
  from pg_tables
  where schemaname = 'shablon'
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
  where schemaname = 'shablon'
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
      'DB-01 rollback refused: later/unknown tables exist in shablon: %',
      v_extra_tables;
  end if;
end
$guard$;

drop table shablon.temporary_audio_artifacts;
drop table shablon.call_links;
drop table shablon.filter_decisions;
drop table shablon.operation_attempts;
drop table shablon.call_events;
drop table shablon.operations;
drop table shablon.calls;
drop table shablon.managers;

drop function shablon.set_updated_at();

drop type shablon.audio_cleanup_state;
drop type shablon.audio_acquisition_state;
drop type shablon.transport_result;
drop type shablon.filter_outcome;
drop type shablon.answer_status;
drop type shablon.call_direction;
drop type shablon.call_occurrence_kind;
drop type shablon.call_classification;
drop type shablon.call_processing_state;
drop type shablon.operation_state;
drop type shablon.contract_decision;

drop schema shablon restrict;

commit;
