-- DB-02 rollback
-- APPROVED WORKING CONTOUR. Rollback is limited to schema shablon_analiz_telefonnyh_peregovorov and requires an explicit safety check before execution.
-- Destructive for DB-02 objects inside shablon_analiz_telefonnyh_peregovorov.
-- Refuses to run when later/unknown relational objects exist.

begin;

do $guard$
declare
  v_missing text;
  v_extra_relations text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'shablon_analiz_telefonnyh_peregovorov'
  ) then
    raise exception 'DB-02 rollback refused: schema shablon_analiz_telefonnyh_peregovorov does not exist';
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
    where schemaname = 'shablon_analiz_telefonnyh_peregovorov'
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
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
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
      'DB-02 rollback refused: later/unknown relations exist in shablon_analiz_telefonnyh_peregovorov: %',
      v_extra_relations;
  end if;
end
$guard$;

drop table shablon_analiz_telefonnyh_peregovorov.speech_metrics;
drop table shablon_analiz_telefonnyh_peregovorov.processing_quality;
drop table shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings;
drop table shablon_analiz_telefonnyh_peregovorov.privacy_package_segments;
drop table shablon_analiz_telefonnyh_peregovorov.privacy_packages;
drop table shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments;
drop table shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts;
drop table shablon_analiz_telefonnyh_peregovorov.role_assignments;
drop table shablon_analiz_telefonnyh_peregovorov.role_assignment_versions;
drop table shablon_analiz_telefonnyh_peregovorov.transcript_segments;
drop table shablon_analiz_telefonnyh_peregovorov.raw_transcripts;

alter table shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts
  drop constraint temporary_audio_artifact_call_unique;

drop type shablon_analiz_telefonnyh_peregovorov.metric_reliability;
drop type shablon_analiz_telefonnyh_peregovorov.processing_reliability;
drop type shablon_analiz_telefonnyh_peregovorov.privacy_status;
drop type shablon_analiz_telefonnyh_peregovorov.role_confidence_status;
drop type shablon_analiz_telefonnyh_peregovorov.business_role;
drop type shablon_analiz_telefonnyh_peregovorov.validation_status;
drop type shablon_analiz_telefonnyh_peregovorov.artifact_version_state;

commit;
