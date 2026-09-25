-- DB-01 rollback
-- TEST/LOCAL ONLY.
-- This script is destructive for schema atp_test.
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
    where nspname = 'atp_test'
  ) then
    raise exception
      'DB-01 rollback refused: schema atp_test does not exist';
  end if;

  select count(*)
  into v_expected_count
  from pg_tables
  where schemaname = 'atp_test'
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
  where schemaname = 'atp_test'
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
      'DB-01 rollback refused: later/unknown tables exist in atp_test: %',
      v_extra_tables;
  end if;
end
$guard$;

drop schema atp_test cascade;

commit;
