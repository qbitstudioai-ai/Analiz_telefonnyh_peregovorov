-- DB-02 rollback
-- TEST/LOCAL ONLY.
-- Destructive for DB-02 objects inside atp_test.
-- Refuses to run when later/unknown relational objects exist.

begin;

do $guard$
declare
  v_missing text;
  v_extra_relations text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-02 rollback refused: schema atp_test does not exist';
  end if;

  select string_agg(required_table, ', ' order by required_table)
  into v_missing
  from (
    values
      ('raw_transcripts'),
      ('transcript_segments'),
      ('role_assignment_versions'),
      ('role_assignments'),
      ('pseudonymized_transcripts'),
      ('pseudonymized_segments'),
      ('privacy_packages'),
      ('privacy_package_segments'),
      ('pseudonym_mappings'),
      ('processing_quality'),
      ('speech_metrics')
  ) as required(required_table)
  where not exists (
    select 1
    from pg_tables
    where schemaname = 'atp_test'
      and tablename = required.required_table
  );

  if v_missing is not null then
    raise exception
      'DB-02 rollback refused: missing DB-02 tables: %',
      v_missing;
  end if;

  select string_agg(c.relname::text, ', ' order by c.relname::text)
  into v_extra_relations
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'atp_test'
    and c.relkind in ('r', 'p', 'v', 'm')
    and c.relname not in (
      -- DB-01
      'managers',
      'calls',
      'call_events',
      'operations',
      'operation_attempts',
      'filter_decisions',
      'call_links',
      'temporary_audio_artifacts',
      -- DB-02
      'raw_transcripts',
      'transcript_segments',
      'role_assignment_versions',
      'role_assignments',
      'pseudonymized_transcripts',
      'pseudonymized_segments',
      'privacy_packages',
      'privacy_package_segments',
      'pseudonym_mappings',
      'processing_quality',
      'speech_metrics'
    );

  if v_extra_relations is not null then
    raise exception
      'DB-02 rollback refused: later/unknown relations exist in atp_test: %',
      v_extra_relations;
  end if;
end
$guard$;

drop table atp_test.speech_metrics;
drop table atp_test.processing_quality;
drop table atp_test.pseudonym_mappings;
drop table atp_test.privacy_package_segments;
drop table atp_test.privacy_packages;
drop table atp_test.pseudonymized_segments;
drop table atp_test.pseudonymized_transcripts;
drop table atp_test.role_assignments;
drop table atp_test.role_assignment_versions;
drop table atp_test.transcript_segments;
drop table atp_test.raw_transcripts;

alter table atp_test.temporary_audio_artifacts
  drop constraint temporary_audio_artifact_call_unique;

drop type atp_test.metric_reliability;
drop type atp_test.processing_reliability;
drop type atp_test.privacy_status;
drop type atp_test.role_confidence_status;
drop type atp_test.business_role;
drop type atp_test.validation_status;
drop type atp_test.artifact_version_state;

commit;
