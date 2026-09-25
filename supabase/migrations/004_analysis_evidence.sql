-- DB-04
-- Immutable analysis versions, structured claims and evidence.
-- APPROVED WORKING CONTOUR. Depends on DB-01, DB-02 and DB-03; scope is limited to schema shablon.
--
-- Core invariant:
-- evidence never points to a free-form model-generated source ID.
-- Conversation refs must belong to the exact pinned privacy package.
-- Knowledge refs must belong to the exact pinned analysis knowledge input.

begin;

do $guard$
declare
  v_missing text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'shablon'
  ) then
    raise exception 'DB-04 requires schema shablon';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('operations'),
      ('raw_transcripts'),
      ('role_assignment_versions'),
      ('pseudonymized_transcripts'),
      ('privacy_packages'),
      ('privacy_package_segments'),
      ('processing_quality'),
      ('prompt_versions'),
      ('methodology_versions'),
      ('methodology_criteria'),
      ('methodology_stages'),
      ('knowledge_publications'),
      ('knowledge_publication_fragments'),
      ('knowledge_publication_fragment_products')
  ) as required(required_relation)
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'shablon'
      and c.relname = required.required_relation
      and c.relkind in ('r', 'p', 'v', 'm')
  );

  if v_missing is not null then
    raise exception 'DB-04 requires DB-01..DB-03. Missing: %', v_missing;
  end if;

  if exists (
    select 1
    from pg_tables
    where schemaname = 'shablon'
      and tablename in (
        'analysis_versions',
        'analysis_knowledge_inputs',
        'analysis_claims',
        'criterion_scores',
        'stage_results',
        'analysis_observations',
        'ai_inferred_outcomes',
        'evidence_sets',
        'evidence_conversation_refs',
        'evidence_knowledge_refs',
        'evidence_absence_checks'
      )
  ) then
    raise exception
      'DB-04 refuses to run because one or more DB-04 tables already exist';
  end if;
end
$guard$;

-- Extra composite keys needed to prove exact pinned upstream ownership.
alter table shablon.privacy_packages
  add constraint privacy_packages_package_role_call_unique
  unique (privacy_package_id, role_assignment_version_id, call_id);

alter table shablon.processing_quality
  add constraint processing_quality_quality_inputs_call_unique
  unique (
    quality_id,
    raw_transcript_id,
    role_assignment_version_id,
    call_id
  );

create type shablon.analysis_state as enum (
  'candidate',
  'validated',
  'current',
  'superseded',
  'invalidated'
);

create type shablon.analysis_claim_type as enum (
  'criterion_score',
  'stage_result',
  'observation',
  'ai_outcome'
);

create type shablon.evidence_requirement as enum (
  'none',
  'presence',
  'absence_check',
  'knowledge',
  'composite'
);

create type shablon.evidence_type as enum (
  'presence',
  'absence_check',
  'knowledge',
  'composite'
);

create type shablon.evidence_integrity as enum (
  'pending',
  'verified',
  'invalid',
  'unavailable_by_retention'
);

create type shablon.evidence_coverage as enum (
  'pending',
  'complete',
  'partial',
  'not_applicable'
);

create type shablon.evidence_rule_kind as enum (
  'criterion',
  'stage',
  'analysis'
);

create type shablon.observation_type as enum (
  'error',
  'strength',
  'warning'
);

create type shablon.absence_scope_kind as enum (
  'whole_conversation',
  'stage',
  'interval'
);

-- One immutable analysis version.
create table shablon.analysis_versions (
  analysis_id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  family_ref text not null default 'call_quality',
  version_no integer not null,
  predecessor_analysis_id uuid,
  analysis_operation_id uuid not null,
  raw_transcript_id uuid not null,
  role_assignment_version_id uuid not null,
  pseudonymized_transcript_id uuid not null,
  privacy_package_id uuid not null,
  processing_quality_id uuid not null,
  prompt_version_id uuid not null references shablon.prompt_versions(prompt_version_id) on delete restrict,
  methodology_version_id uuid not null references shablon.methodology_versions(methodology_version_id) on delete restrict,
  knowledge_publication_id uuid not null references shablon.knowledge_publications(publication_id) on delete restrict,
  history_context_ref text,
  model_provider text not null,
  model_name text not null,
  model_version text,
  model_config_version text not null,
  model_config jsonb not null default '{}'::jsonb,
  analysis_contract_version text not null,
  core_version text not null,
  validator_version text not null,
  input_manifest_sha256 text not null,
  llm_response_sha256 text not null,
  overall_score numeric,
  reliability shablon.processing_reliability not null,
  core_validation_status shablon.validation_status not null default 'pending',
  evidence_gate_status shablon.validation_status not null default 'pending',
  analysis_state shablon.analysis_state not null default 'candidate',
  invalidation_reason text,
  completed_at timestamptz not null default now(),
  validated_at timestamptz,
  current_at timestamptz,
  created_at timestamptz not null default now(),

  constraint analysis_versions_family_not_blank
    check (btrim(family_ref) <> ''),
  constraint analysis_versions_version_positive
    check (version_no > 0),
  constraint analysis_versions_model_provider_not_blank
    check (btrim(model_provider) <> ''),
  constraint analysis_versions_model_name_not_blank
    check (btrim(model_name) <> ''),
  constraint analysis_versions_model_config_version_not_blank
    check (btrim(model_config_version) <> ''),
  constraint analysis_versions_model_config_object
    check (jsonb_typeof(model_config) = 'object'),
  constraint analysis_versions_contract_not_blank
    check (btrim(analysis_contract_version) <> ''),
  constraint analysis_versions_core_version_not_blank
    check (btrim(core_version) <> ''),
  constraint analysis_versions_validator_version_not_blank
    check (btrim(validator_version) <> ''),
  constraint analysis_versions_manifest_hash_not_blank
    check (btrim(input_manifest_sha256) <> ''),
  constraint analysis_versions_response_hash_not_blank
    check (btrim(llm_response_sha256) <> ''),
  constraint analysis_versions_overall_score_range
    check (overall_score is null or (overall_score >= 1 and overall_score <= 10)),
  constraint analysis_versions_validated_time
    check (
      analysis_state not in ('validated', 'current', 'superseded')
      or validated_at is not null
    ),
  constraint analysis_versions_current_time
    check (
      analysis_state <> 'current'
      or current_at is not null
    ),
  constraint analysis_versions_invalidated_reason
    check (
      analysis_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint analysis_versions_analysis_call_unique
    unique (analysis_id, call_id),
  constraint analysis_versions_analysis_methodology_unique
    unique (analysis_id, methodology_version_id),
  constraint analysis_versions_analysis_privacy_unique
    unique (
      analysis_id,
      privacy_package_id,
      pseudonymized_transcript_id,
      call_id
    ),
  constraint analysis_versions_analysis_quality_unique
    unique (analysis_id, processing_quality_id),
  constraint analysis_versions_analysis_publication_unique
    unique (analysis_id, knowledge_publication_id),
  constraint analysis_versions_id_call_family_unique
    unique (analysis_id, call_id, family_ref),
  constraint analysis_versions_predecessor_same_family
    foreign key (predecessor_analysis_id, call_id, family_ref)
    references shablon.analysis_versions(analysis_id, call_id, family_ref)
    on delete restrict,
  constraint analysis_versions_operation_same_call
    foreign key (analysis_operation_id, call_id)
    references shablon.operations(operation_id, call_id)
    on delete restrict,
  constraint analysis_versions_pseudo_matches_raw
    foreign key (
      pseudonymized_transcript_id,
      raw_transcript_id,
      call_id
    )
    references shablon.pseudonymized_transcripts(
      pseudonymized_transcript_id,
      raw_transcript_id,
      call_id
    )
    on delete restrict,
  constraint analysis_versions_pseudo_matches_roles
    foreign key (
      pseudonymized_transcript_id,
      role_assignment_version_id,
      call_id
    )
    references shablon.pseudonymized_transcripts(
      pseudonymized_transcript_id,
      role_assignment_version_id,
      call_id
    )
    on delete restrict,
  constraint analysis_versions_privacy_matches_pseudo
    foreign key (
      privacy_package_id,
      pseudonymized_transcript_id,
      call_id
    )
    references shablon.privacy_packages(
      privacy_package_id,
      pseudonymized_transcript_id,
      call_id
    )
    on delete restrict,
  constraint analysis_versions_privacy_matches_roles
    foreign key (
      privacy_package_id,
      role_assignment_version_id,
      call_id
    )
    references shablon.privacy_packages(
      privacy_package_id,
      role_assignment_version_id,
      call_id
    )
    on delete restrict,
  constraint analysis_versions_quality_matches_inputs
    foreign key (
      processing_quality_id,
      raw_transcript_id,
      role_assignment_version_id,
      call_id
    )
    references shablon.processing_quality(
      quality_id,
      raw_transcript_id,
      role_assignment_version_id,
      call_id
    )
    on delete restrict
);

comment on table shablon.analysis_versions is
  'Immutable analysis version with exact pinned input manifest. LLM output is not current until CORE and evidence gates pass.';

create unique index uq_analysis_versions_family_version
  on shablon.analysis_versions (call_id, family_ref, version_no);

create unique index uq_analysis_versions_one_current
  on shablon.analysis_versions (call_id, family_ref)
  where analysis_state = 'current';

create index ix_analysis_versions_call_created
  on shablon.analysis_versions (call_id, created_at desc);

-- Every analysis must enter the lifecycle as a candidate. Without this
-- insert guard a caller could bypass the candidate -> validated/current
-- update gate by inserting a final state directly.
create function shablon.guard_analysis_initial_state()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  if new.analysis_state <> 'candidate' then
    raise exception
      'Analysis must be inserted as candidate; validation/current is a separate gated transition';
  end if;

  if new.evidence_gate_status <> 'pending'
     or new.validated_at is not null
     or new.current_at is not null
  then
    raise exception
      'New candidate analysis cannot pre-declare evidence gate/validated/current state';
  end if;

  return new;
end
$function$;

create trigger trg_analysis_versions_guard_initial_state
before insert on shablon.analysis_versions
for each row execute function shablon.guard_analysis_initial_state();

-- Exact RAG fragments actually available to this analysis, not the whole publication.
create table shablon.analysis_knowledge_inputs (
  analysis_id uuid not null,
  knowledge_publication_id uuid not null,
  fragment_id uuid not null,
  product_code text not null default 'call_analysis',
  context_order integer not null,
  created_at timestamptz not null default now(),

  constraint analysis_knowledge_inputs_pk
    primary key (analysis_id, fragment_id),
  constraint analysis_knowledge_inputs_product
    check (product_code = 'call_analysis'),
  constraint analysis_knowledge_inputs_order_nonnegative
    check (context_order >= 0),
  constraint analysis_knowledge_inputs_order_unique
    unique (analysis_id, context_order),
  constraint analysis_knowledge_inputs_analysis_publication
    foreign key (analysis_id, knowledge_publication_id)
    references shablon.analysis_versions(analysis_id, knowledge_publication_id)
    on delete restrict,
  constraint analysis_knowledge_inputs_publication_fragment
    foreign key (knowledge_publication_id, fragment_id)
    references shablon.knowledge_publication_fragments(publication_id, fragment_id)
    on delete restrict,
  constraint analysis_knowledge_inputs_product_scope
    foreign key (knowledge_publication_id, fragment_id, product_code)
    references shablon.knowledge_publication_fragment_products(
      publication_id,
      fragment_id,
      product_code
    )
    on delete restrict
);

comment on table shablon.analysis_knowledge_inputs is
  'Exact knowledge fragments actually supplied to one analysis. Evidence may reference only this set.';

-- Stable typed target base for all evidence-bearing analysis outputs.
create table shablon.analysis_claims (
  claim_id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references shablon.analysis_versions(analysis_id) on delete restrict,
  claim_type shablon.analysis_claim_type not null,
  claim_key text not null,
  evidence_requirement shablon.evidence_requirement not null,
  created_at timestamptz not null default now(),

  constraint analysis_claims_key_not_blank
    check (btrim(claim_key) <> ''),
  constraint analysis_claims_claim_analysis_type_unique
    unique (claim_id, analysis_id, claim_type),
  constraint analysis_claims_analysis_key_unique
    unique (analysis_id, claim_key)
);

comment on table shablon.analysis_claims is
  'Typed stable evidence target inside one immutable analysis version. No free-form target_ref is accepted.';

-- Criterion score target.
create table shablon.criterion_scores (
  criterion_score_id uuid primary key,
  analysis_id uuid not null,
  claim_type shablon.analysis_claim_type not null default 'criterion_score',
  methodology_version_id uuid not null,
  criterion_code text not null,
  applicable boolean not null,
  score numeric,
  weight numeric not null,
  rationale text,
  created_at timestamptz not null default now(),

  constraint criterion_scores_claim_type
    check (claim_type = 'criterion_score'),
  constraint criterion_scores_applicability
    check (
      (applicable and score is not null)
      or
      (not applicable and score is null)
    ),
  constraint criterion_scores_score_range
    check (score is null or (score >= 1 and score <= 10)),
  constraint criterion_scores_weight_nonnegative
    check (weight >= 0),
  constraint criterion_scores_claim_fk
    foreign key (criterion_score_id, analysis_id, claim_type)
    references shablon.analysis_claims(claim_id, analysis_id, claim_type)
    on delete restrict,
  constraint criterion_scores_analysis_methodology
    foreign key (analysis_id, methodology_version_id)
    references shablon.analysis_versions(analysis_id, methodology_version_id)
    on delete restrict,
  constraint criterion_scores_methodology_criterion
    foreign key (methodology_version_id, criterion_code)
    references shablon.methodology_criteria(methodology_version_id, criterion_code)
    on delete restrict,
  constraint criterion_scores_analysis_criterion_unique
    unique (analysis_id, criterion_code)
);

-- Stage target.
create table shablon.stage_results (
  stage_result_id uuid primary key,
  analysis_id uuid not null,
  claim_type shablon.analysis_claim_type not null default 'stage_result',
  methodology_version_id uuid not null,
  stage_code text not null,
  applicable boolean not null,
  reached boolean,
  sort_order integer not null,
  required boolean not null,
  explanation text,
  created_at timestamptz not null default now(),

  constraint stage_results_claim_type
    check (claim_type = 'stage_result'),
  constraint stage_results_applicability
    check (
      (applicable and reached is not null)
      or
      (not applicable and reached is null)
    ),
  constraint stage_results_order_nonnegative
    check (sort_order >= 0),
  constraint stage_results_claim_fk
    foreign key (stage_result_id, analysis_id, claim_type)
    references shablon.analysis_claims(claim_id, analysis_id, claim_type)
    on delete restrict,
  constraint stage_results_analysis_methodology
    foreign key (analysis_id, methodology_version_id)
    references shablon.analysis_versions(analysis_id, methodology_version_id)
    on delete restrict,
  constraint stage_results_methodology_stage
    foreign key (methodology_version_id, stage_code)
    references shablon.methodology_stages(methodology_version_id, stage_code)
    on delete restrict,
  constraint stage_results_analysis_stage_unique
    unique (analysis_id, stage_code)
);

-- Observation target.
create table shablon.analysis_observations (
  observation_id uuid primary key,
  analysis_id uuid not null,
  claim_type shablon.analysis_claim_type not null default 'observation',
  methodology_version_id uuid not null,
  observation_code text not null,
  observation_type shablon.observation_type not null,
  applicable boolean not null default true,
  severity text,
  explanation text not null,
  criterion_code text,
  stage_code text,
  created_at timestamptz not null default now(),

  constraint analysis_observations_claim_type
    check (claim_type = 'observation'),
  constraint analysis_observations_code_not_blank
    check (btrim(observation_code) <> ''),
  constraint analysis_observations_explanation_not_blank
    check (btrim(explanation) <> ''),
  constraint analysis_observations_claim_fk
    foreign key (observation_id, analysis_id, claim_type)
    references shablon.analysis_claims(claim_id, analysis_id, claim_type)
    on delete restrict,
  constraint analysis_observations_analysis_methodology
    foreign key (analysis_id, methodology_version_id)
    references shablon.analysis_versions(analysis_id, methodology_version_id)
    on delete restrict,
  constraint analysis_observations_criterion_fk
    foreign key (methodology_version_id, criterion_code)
    references shablon.methodology_criteria(methodology_version_id, criterion_code)
    on delete restrict,
  constraint analysis_observations_stage_fk
    foreign key (methodology_version_id, stage_code)
    references shablon.methodology_stages(methodology_version_id, stage_code)
    on delete restrict,
  constraint analysis_observations_analysis_code_unique
    unique (analysis_id, observation_code)
);

-- AI-inferred conversation outcome. It is not a CRM-confirmed fact.
create table shablon.ai_inferred_outcomes (
  ai_outcome_id uuid primary key,
  analysis_id uuid not null,
  claim_type shablon.analysis_claim_type not null default 'ai_outcome',
  outcome_type text not null,
  target_action text,
  confidence numeric,
  expected_next_contact_at timestamptz,
  outcome_status text not null default 'inferred',
  explanation text,
  created_at timestamptz not null default now(),

  constraint ai_inferred_outcomes_claim_type
    check (claim_type = 'ai_outcome'),
  constraint ai_inferred_outcomes_type_not_blank
    check (btrim(outcome_type) <> ''),
  constraint ai_inferred_outcomes_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),
  constraint ai_inferred_outcomes_status_not_blank
    check (btrim(outcome_status) <> ''),
  constraint ai_inferred_outcomes_claim_fk
    foreign key (ai_outcome_id, analysis_id, claim_type)
    references shablon.analysis_claims(claim_id, analysis_id, claim_type)
    on delete restrict,
  constraint ai_inferred_outcomes_analysis_type_unique
    unique (analysis_id, outcome_type)
);

-- One normalized evidence set for one typed claim.
create table shablon.evidence_sets (
  evidence_id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null,
  call_id uuid not null,
  claim_id uuid not null,
  evidence_type shablon.evidence_type not null,
  methodology_version_id uuid not null,
  rule_kind shablon.evidence_rule_kind not null,
  criterion_code text,
  stage_code text,
  analysis_rule_code text,
  processing_quality_id uuid not null,
  reference_integrity shablon.evidence_integrity not null default 'pending',
  coverage_status shablon.evidence_coverage not null default 'pending',
  safe_explanation text,
  verification_error_code text,
  verified_by_operation_id uuid,
  verified_at timestamptz,
  created_at timestamptz not null default now(),

  constraint evidence_sets_rule_shape
    check (
      (
        rule_kind = 'criterion'
        and criterion_code is not null
        and btrim(criterion_code) <> ''
        and stage_code is null
        and analysis_rule_code is null
      )
      or
      (
        rule_kind = 'stage'
        and stage_code is not null
        and btrim(stage_code) <> ''
        and criterion_code is null
        and analysis_rule_code is null
      )
      or
      (
        rule_kind = 'analysis'
        and analysis_rule_code is not null
        and btrim(analysis_rule_code) <> ''
        and criterion_code is null
        and stage_code is null
      )
    ),
  constraint evidence_sets_verification_metadata
    check (
      (
        reference_integrity = 'pending'
        and verified_by_operation_id is null
        and verified_at is null
      )
      or
      (
        reference_integrity <> 'pending'
        and verified_by_operation_id is not null
        and verified_at is not null
      )
    ),
  constraint evidence_sets_pending_coverage
    check (
      reference_integrity <> 'pending'
      or coverage_status = 'pending'
    ),
  constraint evidence_sets_evidence_analysis_unique
    unique (evidence_id, analysis_id),
  constraint evidence_sets_claim_fk
    foreign key (claim_id, analysis_id)
    references shablon.analysis_claims(claim_id, analysis_id)
    on delete restrict,
  constraint evidence_sets_analysis_call_fk
    foreign key (analysis_id, call_id)
    references shablon.analysis_versions(analysis_id, call_id)
    on delete restrict,
  constraint evidence_sets_analysis_methodology_fk
    foreign key (analysis_id, methodology_version_id)
    references shablon.analysis_versions(analysis_id, methodology_version_id)
    on delete restrict,
  constraint evidence_sets_quality_fk
    foreign key (analysis_id, processing_quality_id)
    references shablon.analysis_versions(analysis_id, processing_quality_id)
    on delete restrict,
  constraint evidence_sets_criterion_fk
    foreign key (methodology_version_id, criterion_code)
    references shablon.methodology_criteria(methodology_version_id, criterion_code)
    on delete restrict,
  constraint evidence_sets_stage_fk
    foreign key (methodology_version_id, stage_code)
    references shablon.methodology_stages(methodology_version_id, stage_code)
    on delete restrict,
  constraint evidence_sets_verifier_same_call
    foreign key (verified_by_operation_id, call_id)
    references shablon.operations(operation_id, call_id)
    on delete restrict
);

comment on table shablon.evidence_sets is
  'Verified evidence set for one typed claim. reference_integrity verifies source refs, not semantic truth of the model conclusion.';

create index ix_evidence_sets_claim
  on shablon.evidence_sets (claim_id, created_at);

-- Conversation refs: only exact safe segments that were in the pinned privacy package.
create table shablon.evidence_conversation_refs (
  conversation_ref_id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null,
  analysis_id uuid not null,
  privacy_package_id uuid not null,
  pseudonymized_segment_id uuid not null,
  ref_order integer not null,
  start_ms bigint not null,
  end_ms bigint not null,
  business_role shablon.business_role not null,
  quote_snapshot text,
  quote_sha256 text,
  created_at timestamptz not null default now(),

  constraint evidence_conversation_refs_order_nonnegative
    check (ref_order >= 0),
  constraint evidence_conversation_refs_time_valid
    check (start_ms >= 0 and end_ms >= start_ms),
  constraint evidence_conversation_refs_quote_hash
    check (
      quote_snapshot is null
      or (quote_sha256 is not null and btrim(quote_sha256) <> '')
    ),
  constraint evidence_conversation_refs_evidence_fk
    foreign key (evidence_id, analysis_id)
    references shablon.evidence_sets(evidence_id, analysis_id)
    on delete restrict,
  constraint evidence_conversation_refs_analysis_package_fk
    foreign key (analysis_id, privacy_package_id)
    references shablon.analysis_versions(analysis_id, privacy_package_id)
    on delete restrict,
  constraint evidence_conversation_refs_package_segment_fk
    foreign key (privacy_package_id, pseudonymized_segment_id)
    references shablon.privacy_package_segments(
      privacy_package_id,
      pseudonymized_segment_id
    )
    on delete restrict,
  constraint evidence_conversation_refs_order_unique
    unique (evidence_id, ref_order),
  constraint evidence_conversation_refs_segment_unique
    unique (evidence_id, pseudonymized_segment_id)
);

-- Knowledge refs: only exact fragments actually included in this analysis.
create table shablon.evidence_knowledge_refs (
  knowledge_ref_id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null,
  analysis_id uuid not null,
  fragment_id uuid not null,
  ref_order integer not null,
  excerpt_snapshot text,
  excerpt_sha256 text,
  created_at timestamptz not null default now(),

  constraint evidence_knowledge_refs_order_nonnegative
    check (ref_order >= 0),
  constraint evidence_knowledge_refs_excerpt_hash
    check (
      excerpt_snapshot is null
      or (excerpt_sha256 is not null and btrim(excerpt_sha256) <> '')
    ),
  constraint evidence_knowledge_refs_evidence_fk
    foreign key (evidence_id, analysis_id)
    references shablon.evidence_sets(evidence_id, analysis_id)
    on delete restrict,
  constraint evidence_knowledge_refs_analysis_input_fk
    foreign key (analysis_id, fragment_id)
    references shablon.analysis_knowledge_inputs(analysis_id, fragment_id)
    on delete restrict,
  constraint evidence_knowledge_refs_order_unique
    unique (evidence_id, ref_order),
  constraint evidence_knowledge_refs_fragment_unique
    unique (evidence_id, fragment_id)
);

-- Absence evidence has a real scope; it never invents a quote for missing speech.
create table shablon.evidence_absence_checks (
  evidence_id uuid primary key,
  analysis_id uuid not null,
  privacy_package_id uuid not null,
  methodology_version_id uuid not null,
  processing_quality_id uuid not null,
  scope_kind shablon.absence_scope_kind not null,
  stage_code text,
  start_ms bigint,
  end_ms bigint,
  coverage_sufficient boolean not null,
  result_absent boolean not null,
  checked_rule_code text not null,
  notes text,
  created_at timestamptz not null default now(),

  constraint evidence_absence_checks_rule_not_blank
    check (btrim(checked_rule_code) <> ''),
  constraint evidence_absence_checks_scope_shape
    check (
      (
        scope_kind = 'whole_conversation'
        and stage_code is null
        and start_ms is null
        and end_ms is null
      )
      or
      (
        scope_kind = 'stage'
        and stage_code is not null
        and btrim(stage_code) <> ''
      )
      or
      (
        scope_kind = 'interval'
        and stage_code is null
        and start_ms is not null
        and end_ms is not null
        and start_ms >= 0
        and end_ms >= start_ms
      )
    ),
  constraint evidence_absence_checks_evidence_fk
    foreign key (evidence_id, analysis_id)
    references shablon.evidence_sets(evidence_id, analysis_id)
    on delete restrict,
  constraint evidence_absence_checks_analysis_package_fk
    foreign key (analysis_id, privacy_package_id)
    references shablon.analysis_versions(analysis_id, privacy_package_id)
    on delete restrict,
  constraint evidence_absence_checks_analysis_methodology_fk
    foreign key (analysis_id, methodology_version_id)
    references shablon.analysis_versions(analysis_id, methodology_version_id)
    on delete restrict,
  constraint evidence_absence_checks_analysis_quality_fk
    foreign key (analysis_id, processing_quality_id)
    references shablon.analysis_versions(analysis_id, processing_quality_id)
    on delete restrict,
  constraint evidence_absence_checks_stage_fk
    foreign key (methodology_version_id, stage_code)
    references shablon.methodology_stages(methodology_version_id, stage_code)
    on delete restrict
);

-- Composite FK target needed by conversation/absence refs.
alter table shablon.analysis_versions
  add constraint analysis_versions_analysis_package_unique
  unique (analysis_id, privacy_package_id);

-- Child mutation is allowed only while analysis remains candidate.
create function shablon.guard_analysis_child_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_analysis_id uuid;
  v_state shablon.analysis_state;
begin
  if tg_op = 'DELETE' then
    v_analysis_id := old.analysis_id;
  else
    v_analysis_id := new.analysis_id;
  end if;

  select analysis_state
  into v_state
  from shablon.analysis_versions
  where analysis_id = v_analysis_id;

  if v_state is distinct from 'candidate' then
    raise exception
      'Analysis child rows are immutable when analysis state is %',
      v_state;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end
$function$;

create trigger trg_analysis_knowledge_inputs_guard
before insert or update or delete on shablon.analysis_knowledge_inputs
for each row execute function shablon.guard_analysis_child_mutation();

create trigger trg_analysis_claims_guard
before insert or update or delete on shablon.analysis_claims
for each row execute function shablon.guard_analysis_child_mutation();

create trigger trg_criterion_scores_guard
before insert or update or delete on shablon.criterion_scores
for each row execute function shablon.guard_analysis_child_mutation();

create trigger trg_stage_results_guard
before insert or update or delete on shablon.stage_results
for each row execute function shablon.guard_analysis_child_mutation();

create trigger trg_analysis_observations_guard
before insert or update or delete on shablon.analysis_observations
for each row execute function shablon.guard_analysis_child_mutation();

create trigger trg_ai_inferred_outcomes_guard
before insert or update or delete on shablon.ai_inferred_outcomes
for each row execute function shablon.guard_analysis_child_mutation();

-- Criterion score must reproduce the pinned methodology criterion.
create function shablon.validate_criterion_score()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_scale_min numeric;
  v_scale_max numeric;
  v_weight numeric;
begin
  select scale_min, scale_max, weight
  into v_scale_min, v_scale_max, v_weight
  from shablon.methodology_criteria
  where methodology_version_id = new.methodology_version_id
    and criterion_code = new.criterion_code;

  if not found then
    raise exception 'Unknown methodology criterion';
  end if;

  if new.weight is distinct from v_weight then
    raise exception
      'Criterion score weight does not match pinned methodology';
  end if;

  if new.applicable
     and (
       new.score is null
       or new.score < v_scale_min
       or new.score > v_scale_max
     )
  then
    raise exception
      'Criterion score is outside pinned methodology scale';
  end if;

  return new;
end
$function$;

create trigger trg_criterion_scores_validate
before insert or update on shablon.criterion_scores
for each row execute function shablon.validate_criterion_score();

-- Stage flags/order must reproduce the pinned methodology stage.
create function shablon.validate_stage_result()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_sort_order integer;
  v_required boolean;
begin
  select sort_order, required
  into v_sort_order, v_required
  from shablon.methodology_stages
  where methodology_version_id = new.methodology_version_id
    and stage_code = new.stage_code;

  if not found then
    raise exception 'Unknown methodology stage';
  end if;

  if new.sort_order is distinct from v_sort_order
     or new.required is distinct from v_required
  then
    raise exception
      'Stage result order/required flag does not match pinned methodology';
  end if;

  return new;
end
$function$;

create trigger trg_stage_results_validate
before insert or update on shablon.stage_results
for each row execute function shablon.validate_stage_result();

-- Evidence set rule must match its typed target.
create function shablon.validate_evidence_target_rule()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_claim_type shablon.analysis_claim_type;
  v_code text;
  v_obs_criterion text;
  v_obs_stage text;
begin
  select claim_type
  into v_claim_type
  from shablon.analysis_claims
  where claim_id = new.claim_id
    and analysis_id = new.analysis_id;

  if not found then
    raise exception 'Evidence target claim does not exist';
  end if;

  if v_claim_type = 'criterion_score' then
    select criterion_code
    into v_code
    from shablon.criterion_scores
    where criterion_score_id = new.claim_id
      and analysis_id = new.analysis_id;

    if new.rule_kind <> 'criterion'
       or new.criterion_code is distinct from v_code
    then
      raise exception
        'Criterion evidence rule must match target criterion';
    end if;

  elsif v_claim_type = 'stage_result' then
    select stage_code
    into v_code
    from shablon.stage_results
    where stage_result_id = new.claim_id
      and analysis_id = new.analysis_id;

    if new.rule_kind <> 'stage'
       or new.stage_code is distinct from v_code
    then
      raise exception
        'Stage evidence rule must match target stage';
    end if;

  elsif v_claim_type = 'observation' then
    select criterion_code, stage_code
    into v_obs_criterion, v_obs_stage
    from shablon.analysis_observations
    where observation_id = new.claim_id
      and analysis_id = new.analysis_id;

    if new.rule_kind = 'criterion'
       and (
         v_obs_criterion is null
         or new.criterion_code is distinct from v_obs_criterion
       )
    then
      raise exception
        'Observation criterion evidence does not match observation criterion';
    end if;

    if new.rule_kind = 'stage'
       and (
         v_obs_stage is null
         or new.stage_code is distinct from v_obs_stage
       )
    then
      raise exception
        'Observation stage evidence does not match observation stage';
    end if;

  elsif v_claim_type = 'ai_outcome' then
    if new.rule_kind <> 'analysis' then
      raise exception
        'AI outcome evidence must use an analysis-level rule';
    end if;
  end if;

  return new;
end
$function$;

create trigger trg_evidence_sets_validate_target_rule
before insert or update on shablon.evidence_sets
for each row execute function shablon.validate_evidence_target_rule();

-- Evidence set can be built while pending. Once verified/invalid, semantics
-- and refs freeze. After lawful retention, verified -> unavailable is allowed.
create function shablon.guard_evidence_set_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_analysis_state shablon.analysis_state;
  v_old_semantic jsonb;
  v_new_semantic jsonb;
begin
  select analysis_state
  into v_analysis_state
  from shablon.analysis_versions
  where analysis_id = coalesce(new.analysis_id, old.analysis_id);

  if tg_op = 'INSERT' then
    if v_analysis_state <> 'candidate' then
      raise exception 'Cannot add evidence to non-candidate analysis';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if v_analysis_state <> 'candidate'
       or old.reference_integrity <> 'pending'
    then
      raise exception 'Cannot delete frozen evidence set';
    end if;
    return old;
  end if;

  if v_analysis_state <> 'candidate' then
    if not (
      old.reference_integrity = 'verified'
      and new.reference_integrity = 'unavailable_by_retention'
    ) then
      raise exception
        'Only verified -> unavailable_by_retention is allowed after analysis validation';
    end if;
  end if;

  if old.reference_integrity <> 'pending' then
    v_old_semantic := to_jsonb(old)
      - 'reference_integrity'
      - 'verification_error_code';
    v_new_semantic := to_jsonb(new)
      - 'reference_integrity'
      - 'verification_error_code';

    if v_old_semantic is distinct from v_new_semantic then
      raise exception
        'Verified evidence semantics are immutable';
    end if;

    if not (
      old.reference_integrity = new.reference_integrity
      or (
        old.reference_integrity = 'verified'
        and new.reference_integrity = 'unavailable_by_retention'
      )
    ) then
      raise exception
        'Invalid evidence integrity transition';
    end if;
  end if;

  return new;
end
$function$;

create trigger trg_evidence_sets_guard
before insert or update or delete on shablon.evidence_sets
for each row execute function shablon.guard_evidence_set_mutation();

-- Child evidence refs freeze as soon as their evidence set is no longer pending.
create function shablon.guard_evidence_ref_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_evidence_id uuid;
  v_integrity shablon.evidence_integrity;
  v_analysis_state shablon.analysis_state;
begin
  if tg_op = 'DELETE' then
    v_evidence_id := old.evidence_id;
  else
    v_evidence_id := new.evidence_id;
  end if;

  select e.reference_integrity, a.analysis_state
  into v_integrity, v_analysis_state
  from shablon.evidence_sets e
  join shablon.analysis_versions a
    on a.analysis_id = e.analysis_id
  where e.evidence_id = v_evidence_id;

  if v_integrity is distinct from 'pending'
     or v_analysis_state is distinct from 'candidate'
  then
    raise exception
      'Evidence refs are immutable after verification/analysis validation';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end
$function$;

create trigger trg_evidence_conversation_refs_guard
before insert or update or delete on shablon.evidence_conversation_refs
for each row execute function shablon.guard_evidence_ref_mutation();

create trigger trg_evidence_knowledge_refs_guard
before insert or update or delete on shablon.evidence_knowledge_refs
for each row execute function shablon.guard_evidence_ref_mutation();

create trigger trg_evidence_absence_checks_guard
before insert or update or delete on shablon.evidence_absence_checks
for each row execute function shablon.guard_evidence_ref_mutation();

-- Conversation ref must match exact safe segment timestamps/role/quote.
create function shablon.validate_evidence_conversation_ref()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_start bigint;
  v_end bigint;
  v_role shablon.business_role;
  v_text text;
begin
  select start_ms, end_ms, business_role, pseudonymized_text
  into v_start, v_end, v_role, v_text
  from shablon.pseudonymized_segments
  where pseudonymized_segment_id = new.pseudonymized_segment_id;

  if not found then
    raise exception 'Evidence conversation segment does not exist';
  end if;

  if new.start_ms < v_start
     or new.end_ms > v_end
     or new.business_role is distinct from v_role
  then
    raise exception
      'Evidence conversation ref does not match exact segment timestamp/role';
  end if;

  if new.quote_snapshot is not null
     and v_text is not null
     and position(new.quote_snapshot in v_text) = 0
  then
    raise exception
      'Evidence quote snapshot does not occur in exact pseudonymized segment';
  end if;

  return new;
end
$function$;

create trigger trg_evidence_conversation_refs_validate
before insert or update on shablon.evidence_conversation_refs
for each row execute function shablon.validate_evidence_conversation_ref();

-- Knowledge excerpt must come from exact analysis input fragment.
create function shablon.validate_evidence_knowledge_ref()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_text text;
begin
  select f.fragment_text
  into v_text
  from shablon.analysis_knowledge_inputs aki
  join shablon.knowledge_fragments f
    on f.fragment_id = aki.fragment_id
  where aki.analysis_id = new.analysis_id
    and aki.fragment_id = new.fragment_id;

  if not found then
    raise exception
      'Evidence knowledge fragment is not an exact analysis input';
  end if;

  if new.excerpt_snapshot is not null
     and position(new.excerpt_snapshot in v_text) = 0
  then
    raise exception
      'Evidence knowledge excerpt does not occur in exact input fragment';
  end if;

  return new;
end
$function$;

create trigger trg_evidence_knowledge_refs_validate
before insert or update on shablon.evidence_knowledge_refs
for each row execute function shablon.validate_evidence_knowledge_ref();

-- Absence evidence must use evidence_type=absence_check and exact pinned quality.
create function shablon.validate_evidence_absence_check()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_type shablon.evidence_type;
  v_reliability shablon.processing_reliability;
begin
  select evidence_type
  into v_type
  from shablon.evidence_sets
  where evidence_id = new.evidence_id
    and analysis_id = new.analysis_id;

  if v_type is distinct from 'absence_check' then
    raise exception
      'Absence check row requires evidence_type=absence_check';
  end if;

  select overall_reliability
  into v_reliability
  from shablon.processing_quality
  where quality_id = new.processing_quality_id;

  if new.coverage_sufficient
     and v_reliability = 'technically_incomplete'
  then
    raise exception
      'Technically incomplete processing cannot claim sufficient absence coverage';
  end if;

  return new;
end
$function$;

create trigger trg_evidence_absence_checks_validate
before insert or update on shablon.evidence_absence_checks
for each row execute function shablon.validate_evidence_absence_check();

-- Overall score = weighted average of applicable criterion scores.
create function shablon.calculate_analysis_overall_score(p_analysis_id uuid)
returns numeric
language sql
stable
set search_path = pg_catalog, shablon
as $function$
  select
    case
      when coalesce(sum(weight) filter (where applicable and weight > 0), 0) = 0
        then null
      else
        sum(score * weight) filter (where applicable and weight > 0)
        /
        sum(weight) filter (where applicable and weight > 0)
    end
  from shablon.criterion_scores
  where analysis_id = p_analysis_id
$function$;

-- Structural evidence gate.
create function shablon.validate_analysis_evidence_gate(p_analysis_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_missing_child integer;
  v_missing_evidence integer;
  v_bad_evidence integer;
  v_structural_bad integer;
begin
  -- Every typed base claim must have its matching structured child.
  select count(*)
  into v_missing_child
  from shablon.analysis_claims c
  where c.analysis_id = p_analysis_id
    and (
      (
        c.claim_type = 'criterion_score'
        and not exists (
          select 1
          from shablon.criterion_scores x
          where x.criterion_score_id = c.claim_id
            and x.analysis_id = c.analysis_id
        )
      )
      or
      (
        c.claim_type = 'stage_result'
        and not exists (
          select 1
          from shablon.stage_results x
          where x.stage_result_id = c.claim_id
            and x.analysis_id = c.analysis_id
        )
      )
      or
      (
        c.claim_type = 'observation'
        and not exists (
          select 1
          from shablon.analysis_observations x
          where x.observation_id = c.claim_id
            and x.analysis_id = c.analysis_id
        )
      )
      or
      (
        c.claim_type = 'ai_outcome'
        and not exists (
          select 1
          from shablon.ai_inferred_outcomes x
          where x.ai_outcome_id = c.claim_id
            and x.analysis_id = c.analysis_id
        )
      )
    );

  if v_missing_child <> 0 then
    raise exception
      'Evidence gate failed: % claim(s) have no typed target row',
      v_missing_child;
  end if;

  -- Pending/invalid evidence cannot exist when gate passes.
  select count(*)
  into v_bad_evidence
  from shablon.evidence_sets
  where analysis_id = p_analysis_id
    and (
      reference_integrity <> 'verified'
      or coverage_status = 'pending'
    );

  if v_bad_evidence <> 0 then
    raise exception
      'Evidence gate failed: % evidence set(s) are not verified/final',
      v_bad_evidence;
  end if;

  -- Required claim must have complete verified evidence of the required type.
  select count(*)
  into v_missing_evidence
  from shablon.analysis_claims c
  where c.analysis_id = p_analysis_id
    and c.evidence_requirement <> 'none'
    and not exists (
      select 1
      from shablon.evidence_sets e
      where e.analysis_id = c.analysis_id
        and e.claim_id = c.claim_id
        and e.reference_integrity = 'verified'
        and e.coverage_status = 'complete'
        and (
          (c.evidence_requirement = 'presence' and e.evidence_type = 'presence')
          or
          (c.evidence_requirement = 'absence_check' and e.evidence_type = 'absence_check')
          or
          (c.evidence_requirement = 'knowledge' and e.evidence_type = 'knowledge')
          or
          (c.evidence_requirement = 'composite' and e.evidence_type = 'composite')
        )
    );

  if v_missing_evidence <> 0 then
    raise exception
      'Evidence gate failed: % required claim(s) lack complete matching evidence',
      v_missing_evidence;
  end if;

  -- Evidence type must have the required physical parts.
  select count(*)
  into v_structural_bad
  from shablon.evidence_sets e
  where e.analysis_id = p_analysis_id
    and e.coverage_status = 'complete'
    and (
      (
        e.evidence_type = 'presence'
        and not exists (
          select 1
          from shablon.evidence_conversation_refs c
          where c.evidence_id = e.evidence_id
        )
      )
      or
      (
        e.evidence_type = 'knowledge'
        and not exists (
          select 1
          from shablon.evidence_knowledge_refs k
          where k.evidence_id = e.evidence_id
        )
      )
      or
      (
        e.evidence_type = 'absence_check'
        and not exists (
          select 1
          from shablon.evidence_absence_checks a
          where a.evidence_id = e.evidence_id
            and a.coverage_sufficient
            and a.result_absent
        )
      )
      or
      (
        e.evidence_type = 'composite'
        and (
          not exists (
            select 1
            from shablon.evidence_conversation_refs c
            where c.evidence_id = e.evidence_id
          )
          or
          not exists (
            select 1
            from shablon.evidence_knowledge_refs k
            where k.evidence_id = e.evidence_id
          )
        )
      )
    );

  if v_structural_bad <> 0 then
    raise exception
      'Evidence gate failed: % evidence set(s) lack required structural parts',
      v_structural_bad;
  end if;
end
$function$;

-- Candidate -> validated/current gate and post-validation immutability.
create function shablon.guard_analysis_version_update()
returns trigger
language plpgsql
set search_path = pg_catalog, shablon
as $function$
declare
  v_operation_state shablon.operation_state;
  v_privacy_status shablon.privacy_status;
  v_prompt_state shablon.config_version_state;
  v_methodology_state shablon.config_version_state;
  v_publication_state shablon.knowledge_publication_state;
  v_calculated_score numeric;
  v_old_semantic jsonb;
  v_new_semantic jsonb;
begin
  if old.analysis_state <> 'candidate' then
    v_old_semantic := to_jsonb(old)
      - 'analysis_state'
      - 'invalidation_reason'
      - 'current_at';
    v_new_semantic := to_jsonb(new)
      - 'analysis_state'
      - 'invalidation_reason'
      - 'current_at';

    if v_old_semantic is distinct from v_new_semantic then
      raise exception
        'Validated analysis semantics/input manifest are immutable';
    end if;
  end if;

  if old.analysis_state in ('validated', 'current', 'superseded', 'invalidated')
     and new.analysis_state = 'candidate'
  then
    raise exception
      'Analysis cannot return to candidate after validation/history';
  end if;

  if old.analysis_state = 'current'
     and new.analysis_state not in ('current', 'superseded', 'invalidated')
  then
    raise exception
      'Current analysis can only remain current or become superseded/invalidated';
  end if;

  if new.analysis_state in ('validated', 'current')
     and old.analysis_state is distinct from new.analysis_state
  then
    if new.core_validation_status <> 'passed'
       or new.evidence_gate_status <> 'passed'
       or new.validated_at is null
    then
      raise exception
        'Analysis validation/current requires passed CORE and evidence gates';
    end if;

    select operation_state
    into v_operation_state
    from shablon.operations
    where operation_id = new.analysis_operation_id
      and call_id = new.call_id;

    if v_operation_state is distinct from 'succeeded' then
      raise exception
        'Analysis operation is not succeeded';
    end if;

    select privacy_status
    into v_privacy_status
    from shablon.privacy_packages
    where privacy_package_id = new.privacy_package_id;

    if v_privacy_status is distinct from 'passed' then
      raise exception
        'Analysis privacy package is not passed';
    end if;

    select config_state
    into v_prompt_state
    from shablon.prompt_versions
    where prompt_version_id = new.prompt_version_id;

    if v_prompt_state not in ('active', 'superseded') then
      raise exception
        'Pinned prompt version was not active/historical-valid';
    end if;

    select config_state
    into v_methodology_state
    from shablon.methodology_versions
    where methodology_version_id = new.methodology_version_id;

    if v_methodology_state not in ('active', 'superseded') then
      raise exception
        'Pinned methodology version was not active/historical-valid';
    end if;

    select publication_state
    into v_publication_state
    from shablon.knowledge_publications
    where publication_id = new.knowledge_publication_id;

    if v_publication_state not in ('published', 'superseded', 'archived') then
      raise exception
        'Pinned knowledge publication was not published/historical-valid';
    end if;

    if not exists (
      select 1
      from shablon.analysis_claims
      where analysis_id = new.analysis_id
    ) then
      raise exception
        'Analysis has no structured claims';
    end if;

    perform shablon.validate_analysis_evidence_gate(new.analysis_id);

    v_calculated_score := shablon.calculate_analysis_overall_score(new.analysis_id);

    if v_calculated_score is null then
      if new.overall_score is not null then
        raise exception
          'Overall score must be NULL when no applicable positive-weight criteria exist';
      end if;
    elsif new.overall_score is null
       or abs(new.overall_score - v_calculated_score) > 0.000001
    then
      raise exception
        'Overall score does not match weighted applicable criterion scores';
    end if;
  end if;

  if new.analysis_state = 'current'
     and old.analysis_state <> 'validated'
  then
    raise exception
      'Analysis must become validated before current';
  end if;

  return new;
end
$function$;

create trigger trg_analysis_versions_guard_update
before update on shablon.analysis_versions
for each row execute function shablon.guard_analysis_version_update();

commit;
