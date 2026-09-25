-- DB-02
-- Versioned transcription, roles, privacy, quality and speech metrics.
-- APPROVED WORKING CONTOUR. Depends on DB-01; scope is limited to schema shablon_analiz_telefonnyh_peregovorov.
--
-- Privacy model:
--   raw transcript != pseudonymized transcript != reverse pseudonym mapping.
-- A privacy package references only safe pseudonymized artifacts and exact
-- role/version metadata. It has no FK to raw text or pseudonym mappings.

begin;

do $guard$
declare
  v_missing text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'shablon_analiz_telefonnyh_peregovorov'
  ) then
    raise exception 'DB-02 requires DB-01 schema shablon_analiz_telefonnyh_peregovorov';
  end if;

  select string_agg(required_table, ', ' order by required_table)
  into v_missing
  from (
    values
      ('calls'),
      ('managers'),
      ('operations'),
      ('temporary_audio_artifacts')
  ) as required(required_table)
  where not exists (
    select 1
    from pg_tables
    where schemaname = 'shablon_analiz_telefonnyh_peregovorov'
      and tablename = required.required_table
  );

  if v_missing is not null then
    raise exception 'DB-02 requires DB-01 tables. Missing: %', v_missing;
  end if;

  if exists (
    select 1
    from pg_tables
    where schemaname = 'shablon_analiz_telefonnyh_peregovorov'
      and tablename in (
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
      )
  ) then
    raise exception
      'DB-02 refuses to run because one or more DB-02 tables already exist. Inspect schema shablon_analiz_telefonnyh_peregovorov instead of rerunning blindly.';
  end if;
end
$guard$;

-- Needed for call-owned FK from transcript to temporary audio metadata.
alter table shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts
  add constraint temporary_audio_artifact_call_unique
  unique (audio_artifact_id, call_id);

create type shablon_analiz_telefonnyh_peregovorov.artifact_version_state as enum (
  'candidate',
  'current',
  'superseded',
  'invalidated'
);

create type shablon_analiz_telefonnyh_peregovorov.validation_status as enum (
  'pending',
  'passed',
  'failed'
);

create type shablon_analiz_telefonnyh_peregovorov.business_role as enum (
  'manager',
  'client',
  'other',
  'unknown'
);

create type shablon_analiz_telefonnyh_peregovorov.role_confidence_status as enum (
  'confirmed',
  'assumed',
  'undetermined'
);

create type shablon_analiz_telefonnyh_peregovorov.privacy_status as enum (
  'pending',
  'passed',
  'blocked'
);

create type shablon_analiz_telefonnyh_peregovorov.processing_reliability as enum (
  'reliable',
  'preliminary',
  'technically_incomplete'
);

create type shablon_analiz_telefonnyh_peregovorov.metric_reliability as enum (
  'reliable',
  'preliminary',
  'unavailable'
);

-- Logical entity: ishodnye_transkripcii.
create table shablon_analiz_telefonnyh_peregovorov.raw_transcripts (
  transcript_id uuid primary key default gen_random_uuid(),
  call_id uuid not null references shablon_analiz_telefonnyh_peregovorov.calls(call_id) on delete restrict,
  version_no integer not null,
  predecessor_transcript_id uuid,
  audio_artifact_id uuid,
  created_by_operation_id uuid not null,
  engine_provider text not null,
  engine_model text not null,
  engine_version text,
  engine_config_version text not null,
  engine_config jsonb not null default '{}'::jsonb,
  raw_text text,
  content_sha256 text not null,
  validation_status shablon_analiz_telefonnyh_peregovorov.validation_status not null default 'pending',
  version_state shablon_analiz_telefonnyh_peregovorov.artifact_version_state not null default 'candidate',
  invalidation_reason text,
  change_reason text,
  retention_policy_ref text not null,
  retain_until timestamptz,
  content_deleted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint raw_transcripts_version_positive
    check (version_no > 0),
  constraint raw_transcripts_engine_provider_not_blank
    check (btrim(engine_provider) <> ''),
  constraint raw_transcripts_engine_model_not_blank
    check (btrim(engine_model) <> ''),
  constraint raw_transcripts_engine_config_version_not_blank
    check (btrim(engine_config_version) <> ''),
  constraint raw_transcripts_engine_config_object
    check (jsonb_typeof(engine_config) = 'object'),
  constraint raw_transcripts_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint raw_transcripts_retention_ref_not_blank
    check (btrim(retention_policy_ref) <> ''),
  constraint raw_transcripts_deleted_content_consistent
    check (
      (raw_text is not null and content_deleted_at is null)
      or
      (raw_text is null and content_deleted_at is not null)
    ),
  constraint raw_transcripts_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint raw_transcripts_transcript_call_unique
    unique (transcript_id, call_id),
  constraint raw_transcripts_predecessor_same_call
    foreign key (predecessor_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.raw_transcripts(transcript_id, call_id)
    on delete restrict,
  constraint raw_transcripts_operation_same_call
    foreign key (created_by_operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict,
  constraint raw_transcripts_audio_same_call
    foreign key (audio_artifact_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts(audio_artifact_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.raw_transcripts is
  'Protected raw transcript version. Never sent to an external analytical LLM. call_id is the version family.';

create unique index uq_raw_transcripts_call_version
  on shablon_analiz_telefonnyh_peregovorov.raw_transcripts (call_id, version_no);

create unique index uq_raw_transcripts_one_current
  on shablon_analiz_telefonnyh_peregovorov.raw_transcripts (call_id)
  where version_state = 'current';

create index ix_raw_transcripts_call_created
  on shablon_analiz_telefonnyh_peregovorov.raw_transcripts (call_id, created_at desc);

-- Logical entity: segmenty_transkripcii.
create table shablon_analiz_telefonnyh_peregovorov.transcript_segments (
  segment_id uuid primary key default gen_random_uuid(),
  transcript_id uuid not null,
  call_id uuid not null,
  segment_key text not null,
  segment_order integer not null,
  start_ms bigint not null,
  end_ms bigint not null,
  technical_speaker text not null,
  raw_text text,
  content_sha256 text not null,
  engine_confidence numeric,
  technical_quality jsonb not null default '{}'::jsonb,
  text_deleted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint transcript_segments_key_not_blank
    check (btrim(segment_key) <> ''),
  constraint transcript_segments_order_nonnegative
    check (segment_order >= 0),
  constraint transcript_segments_time_valid
    check (start_ms >= 0 and end_ms >= start_ms),
  constraint transcript_segments_speaker_not_blank
    check (btrim(technical_speaker) <> ''),
  constraint transcript_segments_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint transcript_segments_quality_object
    check (jsonb_typeof(technical_quality) = 'object'),
  constraint transcript_segments_deleted_text_consistent
    check (
      (raw_text is not null and text_deleted_at is null)
      or
      (raw_text is null and text_deleted_at is not null)
    ),
  constraint transcript_segments_segment_transcript_call_unique
    unique (segment_id, transcript_id, call_id),
  constraint transcript_segments_transcript_same_call
    foreign key (transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.raw_transcripts(transcript_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.transcript_segments is
  'Raw transcript segment with exact timestamp and technical speaker. Business role is stored separately.';

create unique index uq_transcript_segments_key
  on shablon_analiz_telefonnyh_peregovorov.transcript_segments (transcript_id, segment_key);

create unique index uq_transcript_segments_order
  on shablon_analiz_telefonnyh_peregovorov.transcript_segments (transcript_id, segment_order);

create index ix_transcript_segments_transcript_time
  on shablon_analiz_telefonnyh_peregovorov.transcript_segments (transcript_id, start_ms);

-- Logical version entity for naznacheniya_rolej.
create table shablon_analiz_telefonnyh_peregovorov.role_assignment_versions (
  role_assignment_version_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  transcript_id uuid not null,
  version_no integer not null,
  predecessor_role_version_id uuid,
  rules_version_ref text not null,
  created_by_operation_id uuid not null,
  version_state shablon_analiz_telefonnyh_peregovorov.artifact_version_state not null default 'candidate',
  invalidation_reason text,
  change_reason text,
  created_at timestamptz not null default now(),

  constraint role_assignment_versions_version_positive
    check (version_no > 0),
  constraint role_assignment_versions_rules_ref_not_blank
    check (btrim(rules_version_ref) <> ''),
  constraint role_assignment_versions_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint role_assignment_versions_version_transcript_call_unique
    unique (role_assignment_version_id, transcript_id, call_id),
  constraint role_assignment_versions_transcript_same_call
    foreign key (transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.raw_transcripts(transcript_id, call_id)
    on delete restrict,
  constraint role_assignment_versions_operation_same_call
    foreign key (created_by_operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.role_assignment_versions is
  'Immutable-by-version role-assignment family for one exact raw transcript version.';

create unique index uq_role_assignment_versions_transcript_version
  on shablon_analiz_telefonnyh_peregovorov.role_assignment_versions (transcript_id, version_no);

create unique index uq_role_assignment_versions_one_current
  on shablon_analiz_telefonnyh_peregovorov.role_assignment_versions (transcript_id)
  where version_state = 'current';

-- Add same-transcript predecessor constraint after unique key exists.
alter table shablon_analiz_telefonnyh_peregovorov.role_assignment_versions
  add constraint fk_role_assignment_versions_predecessor
  foreign key (
    predecessor_role_version_id,
    transcript_id,
    call_id
  )
  references shablon_analiz_telefonnyh_peregovorov.role_assignment_versions(
    role_assignment_version_id,
    transcript_id,
    call_id
  )
  on delete restrict;

-- One technical speaker -> one business-role result inside a role version.
create table shablon_analiz_telefonnyh_peregovorov.role_assignments (
  role_assignment_id uuid primary key default gen_random_uuid(),
  role_assignment_version_id uuid not null references shablon_analiz_telefonnyh_peregovorov.role_assignment_versions(role_assignment_version_id) on delete restrict,
  technical_speaker text not null,
  business_role shablon_analiz_telefonnyh_peregovorov.business_role not null,
  confidence_status shablon_analiz_telefonnyh_peregovorov.role_confidence_status not null,
  manager_id uuid references shablon_analiz_telefonnyh_peregovorov.managers(manager_id) on delete restrict,
  evidence_types text[] not null default '{}'::text[],
  basis_refs jsonb not null default '{}'::jsonb,
  source_conflict boolean not null default false,
  is_manual_correction boolean not null default false,
  correction_actor_ref text,
  correction_reason text,
  created_at timestamptz not null default now(),

  constraint role_assignments_speaker_not_blank
    check (btrim(technical_speaker) <> ''),
  constraint role_assignments_basis_refs_object
    check (jsonb_typeof(basis_refs) = 'object'),
  constraint role_assignments_evidence_for_resolved
    check (
      confidence_status = 'undetermined'
      or cardinality(evidence_types) > 0
    ),
  constraint role_assignments_manual_correction_reason
    check (
      not is_manual_correction
      or (
        correction_actor_ref is not null
        and btrim(correction_actor_ref) <> ''
        and correction_reason is not null
        and btrim(correction_reason) <> ''
      )
    ),
  constraint role_assignments_unknown_consistent
    check (
      confidence_status <> 'undetermined'
      or business_role in ('unknown', 'other')
    ),
  constraint role_assignments_assignment_version_speaker_unique
    unique (role_assignment_version_id, technical_speaker)
);

comment on table shablon_analiz_telefonnyh_peregovorov.role_assignments is
  'Technical speaker to business-role mapping. Manager identity is optional and comes only from trusted data.';

-- Logical entity: psevdonimizirovannye_transkripcii.
create table shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts (
  pseudonymized_transcript_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  raw_transcript_id uuid not null,
  role_assignment_version_id uuid not null,
  version_no integer not null,
  predecessor_pseudonymized_id uuid,
  pseudonymization_rules_version text not null,
  created_by_operation_id uuid not null,
  pseudonymized_text text,
  content_sha256 text not null,
  privacy_status shablon_analiz_telefonnyh_peregovorov.privacy_status not null default 'pending',
  privacy_issue_codes text[] not null default '{}'::text[],
  version_state shablon_analiz_telefonnyh_peregovorov.artifact_version_state not null default 'candidate',
  invalidation_reason text,
  change_reason text,
  retention_policy_ref text not null,
  retain_until timestamptz,
  content_deleted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint pseudonymized_transcripts_version_positive
    check (version_no > 0),
  constraint pseudonymized_transcripts_rules_not_blank
    check (btrim(pseudonymization_rules_version) <> ''),
  constraint pseudonymized_transcripts_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint pseudonymized_transcripts_retention_ref_not_blank
    check (btrim(retention_policy_ref) <> ''),
  constraint pseudonymized_transcripts_deleted_content_consistent
    check (
      (pseudonymized_text is not null and content_deleted_at is null)
      or
      (pseudonymized_text is null and content_deleted_at is not null)
    ),
  constraint pseudonymized_transcripts_blocked_has_issue
    check (
      privacy_status <> 'blocked'
      or cardinality(privacy_issue_codes) > 0
    ),
  constraint pseudonymized_transcripts_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint pseudonymized_transcripts_pseudo_raw_call_unique
    unique (pseudonymized_transcript_id, raw_transcript_id, call_id),
  constraint pseudonymized_transcripts_pseudo_role_call_unique
    unique (pseudonymized_transcript_id, role_assignment_version_id, call_id),
  constraint pseudonymized_transcripts_raw_same_call
    foreign key (raw_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.raw_transcripts(transcript_id, call_id)
    on delete restrict,
  constraint pseudonymized_transcripts_role_matches_raw
    foreign key (role_assignment_version_id, raw_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.role_assignment_versions(role_assignment_version_id, transcript_id, call_id)
    on delete restrict,
  constraint pseudonymized_transcripts_operation_same_call
    foreign key (created_by_operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts is
  'Pseudonymized version physically separated from raw transcript and reverse mapping. It never contains the reverse mapping table.';

create unique index uq_pseudonymized_transcripts_call_version
  on shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts (call_id, version_no);

create unique index uq_pseudonymized_transcripts_one_current
  on shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts (call_id)
  where version_state = 'current';

-- Unique target for same-call predecessor FK.
alter table shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts
  add constraint pseudonymized_transcripts_pseudo_call_unique
  unique (pseudonymized_transcript_id, call_id);

alter table shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts
  add constraint fk_pseudonymized_transcripts_predecessor
  foreign key (predecessor_pseudonymized_id, call_id)
  references shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts(pseudonymized_transcript_id, call_id)
  on delete restrict;

-- Safe segment copy for external/package use.
create table shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments (
  pseudonymized_segment_id uuid primary key default gen_random_uuid(),
  pseudonymized_transcript_id uuid not null,
  raw_transcript_id uuid not null,
  call_id uuid not null,
  source_segment_id uuid not null,
  segment_key text not null,
  segment_order integer not null,
  start_ms bigint not null,
  end_ms bigint not null,
  speaker_label text not null,
  business_role shablon_analiz_telefonnyh_peregovorov.business_role not null,
  pseudonymized_text text,
  content_sha256 text not null,
  text_deleted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint pseudonymized_segments_key_not_blank
    check (btrim(segment_key) <> ''),
  constraint pseudonymized_segments_order_nonnegative
    check (segment_order >= 0),
  constraint pseudonymized_segments_time_valid
    check (start_ms >= 0 and end_ms >= start_ms),
  constraint pseudonymized_segments_speaker_label_not_blank
    check (btrim(speaker_label) <> ''),
  constraint pseudonymized_segments_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint pseudonymized_segments_deleted_text_consistent
    check (
      (pseudonymized_text is not null and text_deleted_at is null)
      or
      (pseudonymized_text is null and text_deleted_at is not null)
    ),
  constraint pseudonymized_segments_segment_pseudo_call_unique
    unique (pseudonymized_segment_id, pseudonymized_transcript_id, call_id),
  constraint pseudonymized_segments_parent_same_raw_call
    foreign key (pseudonymized_transcript_id, raw_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts(pseudonymized_transcript_id, raw_transcript_id, call_id)
    on delete restrict,
  constraint pseudonymized_segments_source_same_raw_call
    foreign key (source_segment_id, raw_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.transcript_segments(segment_id, transcript_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments is
  'Safe pseudonymized segment with timestamp and business role. Exact source segment remains local and protected.';

create unique index uq_pseudonymized_segments_key
  on shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments (pseudonymized_transcript_id, segment_key);

create unique index uq_pseudonymized_segments_order
  on shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments (pseudonymized_transcript_id, segment_order);

-- Logical entity: privacy_pakety.
create table shablon_analiz_telefonnyh_peregovorov.privacy_packages (
  privacy_package_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  pseudonymized_transcript_id uuid not null,
  role_assignment_version_id uuid not null,
  version_no integer not null,
  predecessor_privacy_package_id uuid,
  history_context_ref text,
  privacy_status shablon_analiz_telefonnyh_peregovorov.privacy_status not null,
  issue_codes text[] not null default '{}'::text[],
  checker_version text not null,
  preparation_operation_id uuid not null,
  llm_operation_id uuid,
  package_sha256 text not null,
  retention_policy_ref text not null,
  retain_until timestamptz,
  version_state shablon_analiz_telefonnyh_peregovorov.artifact_version_state not null default 'candidate',
  invalidation_reason text,
  change_reason text,
  checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  constraint privacy_packages_version_positive
    check (version_no > 0),
  constraint privacy_packages_checker_not_blank
    check (btrim(checker_version) <> ''),
  constraint privacy_packages_hash_not_blank
    check (btrim(package_sha256) <> ''),
  constraint privacy_packages_retention_ref_not_blank
    check (btrim(retention_policy_ref) <> ''),
  constraint privacy_packages_blocked_has_issue
    check (
      privacy_status <> 'blocked'
      or cardinality(issue_codes) > 0
    ),
  constraint privacy_packages_blocked_has_no_llm_operation
    check (
      privacy_status <> 'blocked'
      or llm_operation_id is null
    ),
  constraint privacy_packages_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint privacy_packages_package_pseudo_call_unique
    unique (privacy_package_id, pseudonymized_transcript_id, call_id),
  constraint privacy_packages_package_call_unique
    unique (privacy_package_id, call_id),
  constraint privacy_packages_pseudonymized_role_same_call
    foreign key (pseudonymized_transcript_id, role_assignment_version_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts(pseudonymized_transcript_id, role_assignment_version_id, call_id)
    on delete restrict,
  constraint privacy_packages_preparation_operation_same_call
    foreign key (preparation_operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict,
  constraint privacy_packages_llm_operation_same_call
    foreign key (llm_operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.privacy_packages is
  'Exact privacy-gate result for an external package. This table has no raw-transcript or pseudonym-mapping FK.';

create unique index uq_privacy_packages_call_version
  on shablon_analiz_telefonnyh_peregovorov.privacy_packages (call_id, version_no);

create unique index uq_privacy_packages_one_current
  on shablon_analiz_telefonnyh_peregovorov.privacy_packages (call_id)
  where version_state = 'current';

alter table shablon_analiz_telefonnyh_peregovorov.privacy_packages
  add constraint fk_privacy_packages_predecessor
  foreign key (predecessor_privacy_package_id, call_id)
  references shablon_analiz_telefonnyh_peregovorov.privacy_packages(privacy_package_id, call_id)
  on delete restrict;

-- Exact safe segment set authorized by a privacy package.
create table shablon_analiz_telefonnyh_peregovorov.privacy_package_segments (
  privacy_package_id uuid not null,
  pseudonymized_transcript_id uuid not null,
  call_id uuid not null,
  pseudonymized_segment_id uuid not null,
  package_order integer not null,
  created_at timestamptz not null default now(),

  constraint privacy_package_segments_order_nonnegative
    check (package_order >= 0),
  constraint privacy_package_segments_pk
    primary key (privacy_package_id, pseudonymized_segment_id),
  constraint privacy_package_segments_package_same_pseudo_call
    foreign key (privacy_package_id, pseudonymized_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.privacy_packages(privacy_package_id, pseudonymized_transcript_id, call_id)
    on delete restrict,
  constraint privacy_package_segments_segment_same_pseudo_call
    foreign key (pseudonymized_segment_id, pseudonymized_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments(pseudonymized_segment_id, pseudonymized_transcript_id, call_id)
    on delete restrict,
  constraint privacy_package_segments_order_unique
    unique (privacy_package_id, package_order)
);

comment on table shablon_analiz_telefonnyh_peregovorov.privacy_package_segments is
  'Exact pseudonymized segment set authorized for one privacy package; never points to raw segments directly.';

-- Logical entity: sootvetstviya_psevdonimov.
create table shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings (
  pseudonym_mapping_id uuid primary key default gen_random_uuid(),
  pseudonymized_transcript_id uuid not null references shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts(pseudonymized_transcript_id) on delete restrict,
  pseudonym_scope_ref text not null,
  pseudonym text not null,
  protected_value text,
  protected_local_ref text,
  purpose_code text not null,
  retention_policy_ref text not null,
  retain_until timestamptz,
  value_deleted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint pseudonym_mappings_scope_not_blank
    check (btrim(pseudonym_scope_ref) <> ''),
  constraint pseudonym_mappings_pseudonym_not_blank
    check (btrim(pseudonym) <> ''),
  constraint pseudonym_mappings_target_or_deleted
    check (
      (
        value_deleted_at is null
        and (
          (protected_value is not null and btrim(protected_value) <> '')
          or
          (protected_local_ref is not null and btrim(protected_local_ref) <> '')
        )
      )
      or
      (
        value_deleted_at is not null
        and protected_value is null
        and protected_local_ref is null
      )
    ),
  constraint pseudonym_mappings_purpose_not_blank
    check (btrim(purpose_code) <> ''),
  constraint pseudonym_mappings_retention_ref_not_blank
    check (btrim(retention_policy_ref) <> ''),
  constraint pseudonym_mappings_deleted_time_valid
    check (value_deleted_at is null or value_deleted_at >= created_at)
);

comment on table shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings is
  'Highly protected local reverse pseudonym mapping. Must never be available to external LLM/embedding API/ordinary browser/logs.';

create unique index uq_pseudonym_mappings_pseudonym
  on shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings (pseudonymized_transcript_id, pseudonym_scope_ref, pseudonym);

-- Logical entity: kachestvo_obrabotki.
create table shablon_analiz_telefonnyh_peregovorov.processing_quality (
  quality_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  version_no integer not null,
  raw_transcript_id uuid not null,
  role_assignment_version_id uuid not null,
  audio_artifact_id uuid,
  quality_rules_version_ref text not null,
  audio_quality jsonb not null default '{}'::jsonb,
  transcription_metrics jsonb not null default '{}'::jsonb,
  role_metrics jsonb not null default '{}'::jsonb,
  overall_reliability shablon_analiz_telefonnyh_peregovorov.processing_reliability not null,
  warning_codes text[] not null default '{}'::text[],
  created_by_operation_id uuid not null,
  version_state shablon_analiz_telefonnyh_peregovorov.artifact_version_state not null default 'candidate',
  invalidation_reason text,
  created_at timestamptz not null default now(),

  constraint processing_quality_version_positive
    check (version_no > 0),
  constraint processing_quality_rules_ref_not_blank
    check (btrim(quality_rules_version_ref) <> ''),
  constraint processing_quality_audio_quality_object
    check (jsonb_typeof(audio_quality) = 'object'),
  constraint processing_quality_transcription_metrics_object
    check (jsonb_typeof(transcription_metrics) = 'object'),
  constraint processing_quality_role_metrics_object
    check (jsonb_typeof(role_metrics) = 'object'),
  constraint processing_quality_preliminary_has_warning
    check (
      overall_reliability = 'reliable'
      or cardinality(warning_codes) > 0
    ),
  constraint processing_quality_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint processing_quality_quality_call_unique
    unique (quality_id, call_id),
  constraint processing_quality_raw_same_call
    foreign key (raw_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.raw_transcripts(transcript_id, call_id)
    on delete restrict,
  constraint processing_quality_role_matches_raw
    foreign key (role_assignment_version_id, raw_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.role_assignment_versions(role_assignment_version_id, transcript_id, call_id)
    on delete restrict,
  constraint processing_quality_audio_same_call
    foreign key (audio_artifact_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.temporary_audio_artifacts(audio_artifact_id, call_id)
    on delete restrict,
  constraint processing_quality_operation_same_call
    foreign key (created_by_operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.processing_quality is
  'Technical processing quality, separate from manager performance score.';

create unique index uq_processing_quality_call_version
  on shablon_analiz_telefonnyh_peregovorov.processing_quality (call_id, version_no);

create unique index uq_processing_quality_one_current
  on shablon_analiz_telefonnyh_peregovorov.processing_quality (call_id)
  where version_state = 'current';

-- Logical entity: metriky_rechi.
create table shablon_analiz_telefonnyh_peregovorov.speech_metrics (
  speech_metrics_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  version_no integer not null,
  raw_transcript_id uuid not null,
  role_assignment_version_id uuid not null,
  quality_id uuid,
  metrics_rules_version_ref text not null,
  manager_talk_ratio numeric(8,7),
  client_talk_ratio numeric(8,7),
  total_pause_ms bigint,
  interruption_count integer,
  manager_speech_rate_wpm numeric,
  client_speech_rate_wpm numeric,
  call_duration_ms bigint,
  reliability shablon_analiz_telefonnyh_peregovorov.metric_reliability not null,
  warning_codes text[] not null default '{}'::text[],
  created_by_operation_id uuid not null,
  version_state shablon_analiz_telefonnyh_peregovorov.artifact_version_state not null default 'candidate',
  invalidation_reason text,
  created_at timestamptz not null default now(),

  constraint speech_metrics_version_positive
    check (version_no > 0),
  constraint speech_metrics_rules_ref_not_blank
    check (btrim(metrics_rules_version_ref) <> ''),
  constraint speech_metrics_manager_ratio
    check (manager_talk_ratio is null or (manager_talk_ratio >= 0 and manager_talk_ratio <= 1)),
  constraint speech_metrics_client_ratio
    check (client_talk_ratio is null or (client_talk_ratio >= 0 and client_talk_ratio <= 1)),
  constraint speech_metrics_pause_nonnegative
    check (total_pause_ms is null or total_pause_ms >= 0),
  constraint speech_metrics_interruptions_nonnegative
    check (interruption_count is null or interruption_count >= 0),
  constraint speech_metrics_manager_rate_nonnegative
    check (manager_speech_rate_wpm is null or manager_speech_rate_wpm >= 0),
  constraint speech_metrics_client_rate_nonnegative
    check (client_speech_rate_wpm is null or client_speech_rate_wpm >= 0),
  constraint speech_metrics_duration_nonnegative
    check (call_duration_ms is null or call_duration_ms >= 0),
  constraint speech_metrics_unreliable_warning
    check (
      reliability = 'reliable'
      or cardinality(warning_codes) > 0
    ),
  constraint speech_metrics_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint speech_metrics_raw_same_call
    foreign key (raw_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.raw_transcripts(transcript_id, call_id)
    on delete restrict,
  constraint speech_metrics_role_matches_raw
    foreign key (role_assignment_version_id, raw_transcript_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.role_assignment_versions(role_assignment_version_id, transcript_id, call_id)
    on delete restrict,
  constraint speech_metrics_quality_same_call
    foreign key (quality_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.processing_quality(quality_id, call_id)
    on delete restrict,
  constraint speech_metrics_operation_same_call
    foreign key (created_by_operation_id, call_id)
    references shablon_analiz_telefonnyh_peregovorov.operations(operation_id, call_id)
    on delete restrict
);

comment on table shablon_analiz_telefonnyh_peregovorov.speech_metrics is
  'Derived speech parameters. They do not automatically change manager score.';

create unique index uq_speech_metrics_call_version
  on shablon_analiz_telefonnyh_peregovorov.speech_metrics (call_id, version_no);

create unique index uq_speech_metrics_one_current
  on shablon_analiz_telefonnyh_peregovorov.speech_metrics (call_id)
  where version_state = 'current';

create index ix_pseudonymized_segments_parent_time
  on shablon_analiz_telefonnyh_peregovorov.pseudonymized_segments (pseudonymized_transcript_id, start_ms);

create index ix_privacy_packages_call_status
  on shablon_analiz_telefonnyh_peregovorov.privacy_packages (call_id, privacy_status, created_at desc);

create index ix_pseudonym_mappings_retention
  on shablon_analiz_telefonnyh_peregovorov.pseudonym_mappings (retain_until)
  where retain_until is not null and value_deleted_at is null;

create index ix_raw_transcripts_retention
  on shablon_analiz_telefonnyh_peregovorov.raw_transcripts (retain_until)
  where retain_until is not null and content_deleted_at is null;

create index ix_pseudonymized_transcripts_retention
  on shablon_analiz_telefonnyh_peregovorov.pseudonymized_transcripts (retain_until)
  where retain_until is not null and content_deleted_at is null;

commit;
