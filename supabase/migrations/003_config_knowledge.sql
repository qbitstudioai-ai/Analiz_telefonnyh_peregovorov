-- DB-03
-- Versioned configuration and shared knowledge model.
-- TEST/LOCAL ONLY. Depends on DB-01 and DB-02.
--
-- Key invariants:
--   draft != active/published;
--   a publication pins exact document/fragment/embedding versions;
--   product scope is explicit per published fragment;
--   publication membership becomes immutable after publication;
--   embeddings are derived from exact fragment versions and model/config.

begin;

do $guard$
declare
  v_missing text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-03 requires schema atp_test';
  end if;

  select string_agg(required_table, ', ' order by required_table)
  into v_missing
  from (
    values
      ('filter_decisions'),
      ('operations'),
      ('raw_transcripts'),
      ('privacy_packages')
  ) as required(required_table)
  where not exists (
    select 1
    from pg_tables
    where schemaname = 'atp_test'
      and tablename = required.required_table
  );

  if v_missing is not null then
    raise exception 'DB-03 requires DB-01/DB-02. Missing: %', v_missing;
  end if;

  if exists (
    select 1
    from pg_tables
    where schemaname = 'atp_test'
      and tablename in (
        'prompt_versions',
        'methodology_versions',
        'methodology_criteria',
        'methodology_stages',
        'filter_rule_versions',
        'knowledge_documents',
        'knowledge_document_versions',
        'knowledge_fragments',
        'knowledge_embeddings',
        'knowledge_publications',
        'knowledge_publication_documents',
        'knowledge_publication_fragments',
        'knowledge_publication_fragment_products'
      )
  ) then
    raise exception
      'DB-03 refuses to run because one or more DB-03 tables already exist';
  end if;
end
$guard$;

create type atp_test.config_version_state as enum (
  'draft',
  'ready',
  'active',
  'superseded',
  'invalidated'
);

create type atp_test.knowledge_editorial_state as enum (
  'draft',
  'ready',
  'archived'
);

create type atp_test.embedding_state as enum (
  'pending',
  'ready',
  'failed',
  'invalidated'
);

create type atp_test.knowledge_publication_state as enum (
  'draft',
  'ready',
  'published',
  'superseded',
  'archived',
  'invalidated'
);

-- Generic guard for prompt/methodology/filter rows after leaving draft.
create function atp_test.guard_config_semantic_update()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_old jsonb;
  v_new jsonb;
begin
  if old.config_state <> 'draft' and new.config_state = 'draft' then
    raise exception
      '% cannot return to draft after leaving draft; create a new version',
      tg_table_name;
  end if;

  if old.config_state = 'active'
     and new.config_state not in ('active', 'superseded', 'invalidated')
  then
    raise exception
      '% active version can only remain active or become superseded/invalidated',
      tg_table_name;
  end if;

  if old.config_state <> 'draft' then
    v_old := to_jsonb(old)
      - 'config_state'
      - 'validation_status'
      - 'activated_at'
      - 'invalidation_reason';
    v_new := to_jsonb(new)
      - 'config_state'
      - 'validation_status'
      - 'activated_at'
      - 'invalidation_reason';

    if v_old is distinct from v_new then
      raise exception
        '% is immutable after leaving draft; create a new version',
        tg_table_name;
    end if;
  end if;

  return new;
end
$function$;

-- Prompt versions.
create table atp_test.prompt_versions (
  prompt_version_id uuid primary key default gen_random_uuid(),
  family_ref text not null,
  version_no integer not null,
  predecessor_prompt_version_id uuid,
  prompt_text text not null,
  content_sha256 text not null,
  config_state atp_test.config_version_state not null default 'draft',
  validation_status atp_test.validation_status not null default 'pending',
  activated_at timestamptz,
  actor_ref text not null,
  change_reason text,
  invalidation_reason text,
  created_at timestamptz not null default now(),

  constraint prompt_versions_family_not_blank
    check (btrim(family_ref) <> ''),
  constraint prompt_versions_version_positive
    check (version_no > 0),
  constraint prompt_versions_text_not_blank
    check (btrim(prompt_text) <> ''),
  constraint prompt_versions_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint prompt_versions_actor_not_blank
    check (btrim(actor_ref) <> ''),
  constraint prompt_versions_activation_valid
    check (
      config_state <> 'active'
      or (
        validation_status = 'passed'
        and activated_at is not null
      )
    ),
  constraint prompt_versions_invalidation_reason
    check (
      config_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint prompt_versions_id_family_unique
    unique (prompt_version_id, family_ref),
  constraint prompt_versions_predecessor_same_family
    foreign key (predecessor_prompt_version_id, family_ref)
    references atp_test.prompt_versions(prompt_version_id, family_ref)
    on delete restrict
);

create unique index uq_prompt_versions_family_version
  on atp_test.prompt_versions (family_ref, version_no);

create unique index uq_prompt_versions_one_active
  on atp_test.prompt_versions (family_ref)
  where config_state = 'active';

create trigger trg_prompt_versions_guard_semantic_update
before update on atp_test.prompt_versions
for each row execute function atp_test.guard_config_semantic_update();

-- Methodology versions.
create table atp_test.methodology_versions (
  methodology_version_id uuid primary key default gen_random_uuid(),
  family_ref text not null,
  version_no integer not null,
  predecessor_methodology_version_id uuid,
  title text not null,
  scoring_config jsonb not null default '{}'::jsonb,
  result_rules jsonb not null default '{}'::jsonb,
  content_sha256 text not null,
  config_state atp_test.config_version_state not null default 'draft',
  validation_status atp_test.validation_status not null default 'pending',
  activated_at timestamptz,
  actor_ref text not null,
  change_reason text,
  invalidation_reason text,
  created_at timestamptz not null default now(),

  constraint methodology_versions_family_not_blank
    check (btrim(family_ref) <> ''),
  constraint methodology_versions_version_positive
    check (version_no > 0),
  constraint methodology_versions_title_not_blank
    check (btrim(title) <> ''),
  constraint methodology_versions_scoring_object
    check (jsonb_typeof(scoring_config) = 'object'),
  constraint methodology_versions_result_rules_object
    check (jsonb_typeof(result_rules) = 'object'),
  constraint methodology_versions_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint methodology_versions_actor_not_blank
    check (btrim(actor_ref) <> ''),
  constraint methodology_versions_activation_valid
    check (
      config_state <> 'active'
      or (
        validation_status = 'passed'
        and activated_at is not null
      )
    ),
  constraint methodology_versions_invalidation_reason
    check (
      config_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint methodology_versions_id_family_unique
    unique (methodology_version_id, family_ref),
  constraint methodology_versions_predecessor_same_family
    foreign key (predecessor_methodology_version_id, family_ref)
    references atp_test.methodology_versions(methodology_version_id, family_ref)
    on delete restrict
);

create unique index uq_methodology_versions_family_version
  on atp_test.methodology_versions (family_ref, version_no);

create unique index uq_methodology_versions_one_active
  on atp_test.methodology_versions (family_ref)
  where config_state = 'active';

create trigger trg_methodology_versions_guard_semantic_update
before update on atp_test.methodology_versions
for each row execute function atp_test.guard_config_semantic_update();

create table atp_test.methodology_criteria (
  methodology_version_id uuid not null references atp_test.methodology_versions(methodology_version_id) on delete restrict,
  criterion_code text not null,
  display_name text not null,
  sort_order integer not null,
  weight numeric not null,
  scale_min numeric not null default 1,
  scale_max numeric not null default 10,
  applicability_rule jsonb not null default '{}'::jsonb,
  required boolean not null default true,
  created_at timestamptz not null default now(),

  constraint methodology_criteria_pk
    primary key (methodology_version_id, criterion_code),
  constraint methodology_criteria_code_not_blank
    check (btrim(criterion_code) <> ''),
  constraint methodology_criteria_name_not_blank
    check (btrim(display_name) <> ''),
  constraint methodology_criteria_order_nonnegative
    check (sort_order >= 0),
  constraint methodology_criteria_weight_nonnegative
    check (weight >= 0),
  constraint methodology_criteria_scale_valid
    check (scale_max > scale_min),
  constraint methodology_criteria_applicability_object
    check (jsonb_typeof(applicability_rule) = 'object'),
  constraint methodology_criteria_order_unique
    unique (methodology_version_id, sort_order)
);

create table atp_test.methodology_stages (
  methodology_version_id uuid not null references atp_test.methodology_versions(methodology_version_id) on delete restrict,
  stage_code text not null,
  display_name text not null,
  sort_order integer not null,
  applicability_rule jsonb not null default '{}'::jsonb,
  required boolean not null default true,
  created_at timestamptz not null default now(),

  constraint methodology_stages_pk
    primary key (methodology_version_id, stage_code),
  constraint methodology_stages_code_not_blank
    check (btrim(stage_code) <> ''),
  constraint methodology_stages_name_not_blank
    check (btrim(display_name) <> ''),
  constraint methodology_stages_order_nonnegative
    check (sort_order >= 0),
  constraint methodology_stages_applicability_object
    check (jsonb_typeof(applicability_rule) = 'object'),
  constraint methodology_stages_order_unique
    unique (methodology_version_id, sort_order)
);

create function atp_test.guard_methodology_child_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_methodology_id uuid;
  v_state atp_test.config_version_state;
begin
  if tg_op = 'DELETE' then
    v_methodology_id := old.methodology_version_id;
  else
    v_methodology_id := new.methodology_version_id;
  end if;

  select config_state
  into v_state
  from atp_test.methodology_versions
  where methodology_version_id = v_methodology_id;

  if v_state is distinct from 'draft' then
    raise exception
      'Methodology children are immutable when parent state is %; create a new methodology version',
      v_state;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end
$function$;

create trigger trg_methodology_criteria_guard
before insert or update or delete on atp_test.methodology_criteria
for each row execute function atp_test.guard_methodology_child_mutation();

create trigger trg_methodology_stages_guard
before insert or update or delete on atp_test.methodology_stages
for each row execute function atp_test.guard_methodology_child_mutation();

-- Filter rule versions.
create table atp_test.filter_rule_versions (
  filter_rule_version_ref text primary key default gen_random_uuid()::text,
  family_ref text not null,
  version_no integer not null,
  predecessor_filter_rule_version_ref text,
  rules_json jsonb not null,
  content_sha256 text not null,
  config_state atp_test.config_version_state not null default 'draft',
  validation_status atp_test.validation_status not null default 'pending',
  activated_at timestamptz,
  actor_ref text not null,
  change_reason text,
  invalidation_reason text,
  created_at timestamptz not null default now(),

  constraint filter_rule_versions_ref_not_blank
    check (btrim(filter_rule_version_ref) <> ''),
  constraint filter_rule_versions_family_not_blank
    check (btrim(family_ref) <> ''),
  constraint filter_rule_versions_version_positive
    check (version_no > 0),
  constraint filter_rule_versions_rules_object
    check (jsonb_typeof(rules_json) = 'object'),
  constraint filter_rule_versions_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint filter_rule_versions_actor_not_blank
    check (btrim(actor_ref) <> ''),
  constraint filter_rule_versions_activation_valid
    check (
      config_state <> 'active'
      or (
        validation_status = 'passed'
        and activated_at is not null
      )
    ),
  constraint filter_rule_versions_invalidation_reason
    check (
      config_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint filter_rule_versions_ref_family_unique
    unique (filter_rule_version_ref, family_ref),
  constraint filter_rule_versions_predecessor_same_family
    foreign key (predecessor_filter_rule_version_ref, family_ref)
    references atp_test.filter_rule_versions(filter_rule_version_ref, family_ref)
    on delete restrict
);

create unique index uq_filter_rule_versions_family_version
  on atp_test.filter_rule_versions (family_ref, version_no);

create unique index uq_filter_rule_versions_one_active
  on atp_test.filter_rule_versions (family_ref)
  where config_state = 'active';

create trigger trg_filter_rule_versions_guard_semantic_update
before update on atp_test.filter_rule_versions
for each row execute function atp_test.guard_config_semantic_update();

alter table atp_test.filter_decisions
  add constraint fk_filter_decisions_rules_version
  foreign key (filter_rules_version_ref)
  references atp_test.filter_rule_versions(filter_rule_version_ref)
  on delete restrict;

-- Canonical knowledge document.
create table atp_test.knowledge_documents (
  document_id uuid primary key default gen_random_uuid(),
  stable_code text not null unique,
  title text not null,
  source_type text not null,
  source_ref text,
  created_at timestamptz not null default now(),

  constraint knowledge_documents_code_not_blank
    check (btrim(stable_code) <> ''),
  constraint knowledge_documents_title_not_blank
    check (btrim(title) <> ''),
  constraint knowledge_documents_source_type_not_blank
    check (btrim(source_type) <> '')
);

-- Version of canonical knowledge document.
create table atp_test.knowledge_document_versions (
  document_version_id uuid primary key default gen_random_uuid(),
  document_id uuid not null references atp_test.knowledge_documents(document_id) on delete restrict,
  version_no integer not null,
  predecessor_document_version_id uuid,
  source_version_ref text,
  content text not null,
  content_sha256 text not null,
  metadata jsonb not null default '{}'::jsonb,
  external_embedding_allowed boolean not null default false,
  embedding_policy_ref text,
  editorial_state atp_test.knowledge_editorial_state not null default 'draft',
  validation_status atp_test.validation_status not null default 'pending',
  validation_codes text[] not null default '{}'::text[],
  version_state atp_test.artifact_version_state not null default 'candidate',
  actor_ref text not null,
  change_reason text,
  invalidation_reason text,
  created_at timestamptz not null default now(),

  constraint knowledge_document_versions_version_positive
    check (version_no > 0),
  constraint knowledge_document_versions_content_not_blank
    check (btrim(content) <> ''),
  constraint knowledge_document_versions_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint knowledge_document_versions_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint knowledge_document_versions_actor_not_blank
    check (btrim(actor_ref) <> ''),
  constraint knowledge_document_versions_embedding_policy
    check (
      not external_embedding_allowed
      or (embedding_policy_ref is not null and btrim(embedding_policy_ref) <> '')
    ),
  constraint knowledge_document_versions_ready_validated
    check (
      editorial_state <> 'ready'
      or validation_status = 'passed'
    ),
  constraint knowledge_document_versions_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint knowledge_document_versions_id_document_unique
    unique (document_version_id, document_id),
  constraint knowledge_document_versions_predecessor_same_document
    foreign key (predecessor_document_version_id, document_id)
    references atp_test.knowledge_document_versions(document_version_id, document_id)
    on delete restrict
);

create unique index uq_knowledge_document_versions_number
  on atp_test.knowledge_document_versions (document_id, version_no);

create unique index uq_knowledge_document_versions_one_current
  on atp_test.knowledge_document_versions (document_id)
  where version_state = 'current';

-- Chunk/fragment version.
create table atp_test.knowledge_fragments (
  fragment_id uuid primary key default gen_random_uuid(),
  document_id uuid not null,
  document_version_id uuid not null,
  fragment_family_key text not null,
  fragment_version_no integer not null,
  predecessor_fragment_id uuid,
  fragment_order integer not null,
  chunking_config_version text not null,
  normalization_config_version text not null,
  fragment_text text not null,
  content_sha256 text not null,
  source_locator jsonb not null default '{}'::jsonb,
  validation_status atp_test.validation_status not null default 'pending',
  version_state atp_test.artifact_version_state not null default 'candidate',
  invalidation_reason text,
  created_at timestamptz not null default now(),

  constraint knowledge_fragments_family_key_not_blank
    check (btrim(fragment_family_key) <> ''),
  constraint knowledge_fragments_version_positive
    check (fragment_version_no > 0),
  constraint knowledge_fragments_order_nonnegative
    check (fragment_order >= 0),
  constraint knowledge_fragments_chunking_not_blank
    check (btrim(chunking_config_version) <> ''),
  constraint knowledge_fragments_normalization_not_blank
    check (btrim(normalization_config_version) <> ''),
  constraint knowledge_fragments_text_not_blank
    check (btrim(fragment_text) <> ''),
  constraint knowledge_fragments_hash_not_blank
    check (btrim(content_sha256) <> ''),
  constraint knowledge_fragments_locator_object
    check (jsonb_typeof(source_locator) = 'object'),
  constraint knowledge_fragments_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint knowledge_fragments_id_docversion_document_unique
    unique (fragment_id, document_version_id, document_id),
  constraint knowledge_fragments_id_family_unique
    unique (fragment_id, document_id, fragment_family_key),
  constraint knowledge_fragments_document_version_exact
    foreign key (document_version_id, document_id)
    references atp_test.knowledge_document_versions(document_version_id, document_id)
    on delete restrict,
  constraint knowledge_fragments_predecessor_same_family
    foreign key (predecessor_fragment_id, document_id, fragment_family_key)
    references atp_test.knowledge_fragments(fragment_id, document_id, fragment_family_key)
    on delete restrict
);

create unique index uq_knowledge_fragments_version
  on atp_test.knowledge_fragments (
    document_version_id,
    fragment_family_key,
    fragment_version_no
  );

create unique index uq_knowledge_fragments_one_current
  on atp_test.knowledge_fragments (document_id, fragment_family_key)
  where version_state = 'current';

-- Embedding version. real[] deliberately avoids fixing a pgvector dimension
-- before AI-03 selects the embedding model/config. A later migration may add
-- pgvector indexes without changing fragment/version provenance.
create table atp_test.knowledge_embeddings (
  embedding_id uuid primary key default gen_random_uuid(),
  fragment_id uuid not null references atp_test.knowledge_fragments(fragment_id) on delete restrict,
  version_no integer not null,
  predecessor_embedding_id uuid,
  provider text not null,
  model_name text not null,
  model_version text,
  config_version text not null,
  config jsonb not null default '{}'::jsonb,
  dimensions integer not null,
  vector_data real[],
  input_sha256 text not null,
  embedding_state atp_test.embedding_state not null default 'pending',
  validation_status atp_test.validation_status not null default 'pending',
  version_state atp_test.artifact_version_state not null default 'candidate',
  external_api boolean not null default false,
  actor_ref text not null,
  source_operation_ref text,
  error_code text,
  invalidation_reason text,
  calculated_at timestamptz,
  created_at timestamptz not null default now(),

  constraint knowledge_embeddings_version_positive
    check (version_no > 0),
  constraint knowledge_embeddings_provider_not_blank
    check (btrim(provider) <> ''),
  constraint knowledge_embeddings_model_not_blank
    check (btrim(model_name) <> ''),
  constraint knowledge_embeddings_config_version_not_blank
    check (btrim(config_version) <> ''),
  constraint knowledge_embeddings_config_object
    check (jsonb_typeof(config) = 'object'),
  constraint knowledge_embeddings_dimensions_positive
    check (dimensions > 0),
  constraint knowledge_embeddings_vector_dimensions
    check (
      vector_data is null
      or cardinality(vector_data) = dimensions
    ),
  constraint knowledge_embeddings_input_hash_not_blank
    check (btrim(input_sha256) <> ''),
  constraint knowledge_embeddings_ready_has_vector
    check (
      embedding_state <> 'ready'
      or (
        vector_data is not null
        and validation_status = 'passed'
        and calculated_at is not null
      )
    ),
  constraint knowledge_embeddings_failed_has_error
    check (
      embedding_state <> 'failed'
      or (error_code is not null and btrim(error_code) <> '')
    ),
  constraint knowledge_embeddings_actor_not_blank
    check (btrim(actor_ref) <> ''),
  constraint knowledge_embeddings_invalidated_reason
    check (
      version_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint knowledge_embeddings_id_fragment_unique
    unique (embedding_id, fragment_id),
  constraint knowledge_embeddings_family_unique_target
    unique (embedding_id, fragment_id, provider, model_name, config_version),
  constraint knowledge_embeddings_predecessor_same_family
    foreign key (
      predecessor_embedding_id,
      fragment_id,
      provider,
      model_name,
      config_version
    )
    references atp_test.knowledge_embeddings(
      embedding_id,
      fragment_id,
      provider,
      model_name,
      config_version
    )
    on delete restrict
);

create unique index uq_knowledge_embeddings_version
  on atp_test.knowledge_embeddings (
    fragment_id,
    provider,
    model_name,
    config_version,
    version_no
  );

create unique index uq_knowledge_embeddings_one_current
  on atp_test.knowledge_embeddings (
    fragment_id,
    provider,
    model_name,
    config_version
  )
  where version_state = 'current';

-- Publication manifest.
create table atp_test.knowledge_publications (
  publication_id uuid primary key default gen_random_uuid(),
  family_ref text not null,
  version_no integer not null,
  predecessor_publication_id uuid,
  publication_state atp_test.knowledge_publication_state not null default 'draft',
  validation_status atp_test.validation_status not null default 'pending',
  manifest_sha256 text not null,
  actor_ref text not null,
  source_operation_ref text,
  validation_ref text,
  change_reason text,
  published_at timestamptz,
  is_current boolean not null default false,
  invalidation_reason text,
  created_at timestamptz not null default now(),

  constraint knowledge_publications_family_not_blank
    check (btrim(family_ref) <> ''),
  constraint knowledge_publications_version_positive
    check (version_no > 0),
  constraint knowledge_publications_manifest_hash_not_blank
    check (btrim(manifest_sha256) <> ''),
  constraint knowledge_publications_actor_not_blank
    check (btrim(actor_ref) <> ''),
  constraint knowledge_publications_current_is_published
    check (
      not is_current
      or (
        publication_state = 'published'
        and validation_status = 'passed'
        and published_at is not null
      )
    ),
  constraint knowledge_publications_published_validated
    check (
      publication_state <> 'published'
      or (
        validation_status = 'passed'
        and published_at is not null
      )
    ),
  constraint knowledge_publications_invalidated_reason
    check (
      publication_state <> 'invalidated'
      or (invalidation_reason is not null and btrim(invalidation_reason) <> '')
    ),
  constraint knowledge_publications_id_family_unique
    unique (publication_id, family_ref),
  constraint knowledge_publications_predecessor_same_family
    foreign key (predecessor_publication_id, family_ref)
    references atp_test.knowledge_publications(publication_id, family_ref)
    on delete restrict
);

create unique index uq_knowledge_publications_family_version
  on atp_test.knowledge_publications (family_ref, version_no);

create unique index uq_knowledge_publications_one_current
  on atp_test.knowledge_publications (family_ref)
  where is_current;

create table atp_test.knowledge_publication_documents (
  publication_id uuid not null references atp_test.knowledge_publications(publication_id) on delete restrict,
  document_version_id uuid not null,
  document_id uuid not null,
  document_order integer not null,
  created_at timestamptz not null default now(),

  constraint knowledge_publication_documents_pk
    primary key (publication_id, document_version_id),
  constraint knowledge_publication_documents_order_nonnegative
    check (document_order >= 0),
  constraint knowledge_publication_documents_order_unique
    unique (publication_id, document_order),
  constraint knowledge_publication_documents_exact_version
    foreign key (document_version_id, document_id)
    references atp_test.knowledge_document_versions(document_version_id, document_id)
    on delete restrict
);

create table atp_test.knowledge_publication_fragments (
  publication_id uuid not null,
  fragment_id uuid not null,
  document_version_id uuid not null,
  document_id uuid not null,
  embedding_id uuid,
  requires_embedding boolean not null default true,
  fragment_order integer not null,
  created_at timestamptz not null default now(),

  constraint knowledge_publication_fragments_pk
    primary key (publication_id, fragment_id),
  constraint knowledge_publication_fragments_order_nonnegative
    check (fragment_order >= 0),
  constraint knowledge_publication_fragments_order_unique
    unique (publication_id, fragment_order),
  constraint knowledge_publication_fragments_embedding_required
    check (not requires_embedding or embedding_id is not null),
  constraint knowledge_publication_fragments_document_membership
    foreign key (publication_id, document_version_id)
    references atp_test.knowledge_publication_documents(publication_id, document_version_id)
    on delete restrict,
  constraint knowledge_publication_fragments_exact_fragment
    foreign key (fragment_id, document_version_id, document_id)
    references atp_test.knowledge_fragments(fragment_id, document_version_id, document_id)
    on delete restrict,
  constraint knowledge_publication_fragments_exact_embedding
    foreign key (embedding_id, fragment_id)
    references atp_test.knowledge_embeddings(embedding_id, fragment_id)
    on delete restrict
);

create table atp_test.knowledge_publication_fragment_products (
  publication_id uuid not null,
  fragment_id uuid not null,
  product_code text not null,
  created_at timestamptz not null default now(),

  constraint knowledge_publication_fragment_products_pk
    primary key (publication_id, fragment_id, product_code),
  constraint knowledge_publication_fragment_products_code_not_blank
    check (btrim(product_code) <> ''),
  constraint knowledge_publication_fragment_products_membership
    foreign key (publication_id, fragment_id)
    references atp_test.knowledge_publication_fragments(publication_id, fragment_id)
    on delete restrict
);

-- Membership is editable only before publication.
create function atp_test.guard_knowledge_publication_membership()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_publication_id uuid;
  v_state atp_test.knowledge_publication_state;
begin
  if tg_op = 'DELETE' then
    v_publication_id := old.publication_id;
  else
    v_publication_id := new.publication_id;
  end if;

  select publication_state
  into v_state
  from atp_test.knowledge_publications
  where publication_id = v_publication_id;

  if v_state not in ('draft', 'ready') then
    raise exception
      'Knowledge publication membership is immutable in state %; create a new publication version',
      v_state;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end
$function$;

create trigger trg_knowledge_publication_documents_guard
before insert or update or delete on atp_test.knowledge_publication_documents
for each row execute function atp_test.guard_knowledge_publication_membership();

create trigger trg_knowledge_publication_fragments_guard
before insert or update or delete on atp_test.knowledge_publication_fragments
for each row execute function atp_test.guard_knowledge_publication_membership();

create trigger trg_knowledge_publication_products_guard
before insert or update or delete on atp_test.knowledge_publication_fragment_products
for each row execute function atp_test.guard_knowledge_publication_membership();

-- Publication row becomes immutable by meaning after publication.
create function atp_test.guard_knowledge_publication_update()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  if old.publication_state not in ('draft', 'ready')
     and new.publication_state in ('draft', 'ready')
  then
    raise exception
      'Published/historical knowledge publication cannot return to draft/ready';
  end if;

  if old.publication_state = 'published'
     and new.publication_state not in ('published', 'superseded', 'archived', 'invalidated')
  then
    raise exception
      'Published knowledge publication has an invalid state transition';
  end if;

  if old.publication_state not in ('draft', 'ready') then
    if old.family_ref is distinct from new.family_ref
       or old.version_no is distinct from new.version_no
       or old.predecessor_publication_id is distinct from new.predecessor_publication_id
       or old.manifest_sha256 is distinct from new.manifest_sha256
       or old.actor_ref is distinct from new.actor_ref
       or old.source_operation_ref is distinct from new.source_operation_ref
       or old.validation_ref is distinct from new.validation_ref
       or old.change_reason is distinct from new.change_reason
       or old.published_at is distinct from new.published_at
       or old.validation_status is distinct from new.validation_status
    then
      raise exception
        'Knowledge publication manifest/provenance is immutable after publication';
    end if;
  end if;

  return new;
end
$function$;

create trigger trg_knowledge_publication_guard_update
before update on atp_test.knowledge_publications
for each row execute function atp_test.guard_knowledge_publication_update();

-- Validate exact manifest at activation.
create function atp_test.validate_knowledge_publication_activation()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
begin
  if tg_op = 'INSERT' and new.publication_state = 'published' then
    raise exception
      'Insert knowledge publication as draft/ready, add exact membership, then activate it';
  end if;

  if new.publication_state = 'published'
     and (
       tg_op = 'INSERT'
       or old.publication_state is distinct from 'published'
       or (not old.is_current and new.is_current)
     )
  then
    if new.validation_status <> 'passed'
       or new.published_at is null
    then
      raise exception
        'Publication activation requires validation_status=passed and published_at';
    end if;

    if not exists (
      select 1
      from atp_test.knowledge_publication_documents
      where publication_id = new.publication_id
    ) then
      raise exception 'Publication has no document versions';
    end if;

    if not exists (
      select 1
      from atp_test.knowledge_publication_fragments
      where publication_id = new.publication_id
    ) then
      raise exception 'Publication has no fragment versions';
    end if;

    if exists (
      select 1
      from atp_test.knowledge_publication_documents pd
      join atp_test.knowledge_document_versions dv
        on dv.document_version_id = pd.document_version_id
      where pd.publication_id = new.publication_id
        and (
          dv.editorial_state <> 'ready'
          or dv.validation_status <> 'passed'
          or dv.version_state = 'invalidated'
        )
    ) then
      raise exception 'Publication contains a document version that is not ready/valid';
    end if;

    if exists (
      select 1
      from atp_test.knowledge_publication_documents pd
      where pd.publication_id = new.publication_id
        and not exists (
          select 1
          from atp_test.knowledge_publication_fragments pf
          where pf.publication_id = pd.publication_id
            and pf.document_version_id = pd.document_version_id
        )
    ) then
      raise exception 'Publication contains a document without fragments';
    end if;

    if exists (
      select 1
      from atp_test.knowledge_publication_fragments pf
      join atp_test.knowledge_fragments f
        on f.fragment_id = pf.fragment_id
      where pf.publication_id = new.publication_id
        and (
          f.validation_status <> 'passed'
          or f.version_state = 'invalidated'
        )
    ) then
      raise exception 'Publication contains an invalid fragment';
    end if;

    if exists (
      select 1
      from atp_test.knowledge_publication_fragments pf
      left join atp_test.knowledge_embeddings e
        on e.embedding_id = pf.embedding_id
      where pf.publication_id = new.publication_id
        and pf.requires_embedding
        and (
          e.embedding_id is null
          or e.embedding_state <> 'ready'
          or e.validation_status <> 'passed'
          or e.version_state = 'invalidated'
        )
    ) then
      raise exception 'Publication requires an embedding that is not ready/valid';
    end if;

    if exists (
      select 1
      from atp_test.knowledge_publication_fragments pf
      join atp_test.knowledge_fragments f
        on f.fragment_id = pf.fragment_id
      join atp_test.knowledge_document_versions dv
        on dv.document_version_id = pf.document_version_id
      join atp_test.knowledge_embeddings e
        on e.embedding_id = pf.embedding_id
      where pf.publication_id = new.publication_id
        and (
          e.input_sha256 <> f.content_sha256
          or (
            e.external_api
            and not dv.external_embedding_allowed
          )
        )
    ) then
      raise exception
        'Publication embedding provenance/policy does not match exact fragment/document';
    end if;

    if exists (
      select 1
      from atp_test.knowledge_publication_fragments pf
      where pf.publication_id = new.publication_id
        and not exists (
          select 1
          from atp_test.knowledge_publication_fragment_products pp
          where pp.publication_id = pf.publication_id
            and pp.fragment_id = pf.fragment_id
        )
    ) then
      raise exception 'Every published fragment requires at least one product scope';
    end if;
  end if;

  return new;
end
$function$;

create trigger trg_knowledge_publication_validate_activation
before insert or update on atp_test.knowledge_publications
for each row execute function atp_test.validate_knowledge_publication_activation();

-- Document/fragment/embedding semantic immutability once ready/published.
create function atp_test.guard_knowledge_document_update()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_published boolean;
begin
  if old.editorial_state <> 'draft' and new.editorial_state = 'draft' then
    raise exception
      'Knowledge document version cannot return to draft; create a new version';
  end if;

  if old.validation_status = 'passed' and new.validation_status <> 'passed' then
    raise exception
      'Validated knowledge document cannot regress validation; invalidate or create a new version';
  end if;

  if old.version_state in ('current', 'superseded', 'invalidated')
     and new.version_state = 'candidate'
  then
    raise exception
      'Knowledge document version cannot return to candidate state';
  end if;

  select exists (
    select 1
    from atp_test.knowledge_publication_documents pd
    join atp_test.knowledge_publications p
      on p.publication_id = pd.publication_id
    where pd.document_version_id = old.document_version_id
      and p.publication_state in ('published', 'superseded', 'archived')
  )
  into v_published;

  if old.editorial_state <> 'draft' or v_published then
    if old.content is distinct from new.content
       or old.content_sha256 is distinct from new.content_sha256
       or old.metadata is distinct from new.metadata
       or old.source_version_ref is distinct from new.source_version_ref
       or old.external_embedding_allowed is distinct from new.external_embedding_allowed
       or old.embedding_policy_ref is distinct from new.embedding_policy_ref
       or old.document_id is distinct from new.document_id
       or old.version_no is distinct from new.version_no
       or old.predecessor_document_version_id is distinct from new.predecessor_document_version_id
    then
      raise exception
        'Knowledge document version is semantically immutable; create a new version';
    end if;
  end if;

  return new;
end
$function$;

create trigger trg_knowledge_document_versions_guard
before update on atp_test.knowledge_document_versions
for each row execute function atp_test.guard_knowledge_document_update();

create function atp_test.guard_knowledge_fragment_update()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_published boolean;
begin
  if old.validation_status = 'passed' and new.validation_status <> 'passed' then
    raise exception
      'Validated knowledge fragment cannot regress validation; invalidate or create a new version';
  end if;

  if old.version_state in ('current', 'superseded', 'invalidated')
     and new.version_state = 'candidate'
  then
    raise exception
      'Knowledge fragment cannot return to candidate state';
  end if;

  select exists (
    select 1
    from atp_test.knowledge_publication_fragments pf
    join atp_test.knowledge_publications p
      on p.publication_id = pf.publication_id
    where pf.fragment_id = old.fragment_id
      and p.publication_state in ('published', 'superseded', 'archived')
  )
  into v_published;

  if old.validation_status = 'passed' or v_published then
    if old.document_id is distinct from new.document_id
       or old.document_version_id is distinct from new.document_version_id
       or old.fragment_family_key is distinct from new.fragment_family_key
       or old.fragment_version_no is distinct from new.fragment_version_no
       or old.predecessor_fragment_id is distinct from new.predecessor_fragment_id
       or old.fragment_order is distinct from new.fragment_order
       or old.chunking_config_version is distinct from new.chunking_config_version
       or old.normalization_config_version is distinct from new.normalization_config_version
       or old.fragment_text is distinct from new.fragment_text
       or old.content_sha256 is distinct from new.content_sha256
       or old.source_locator is distinct from new.source_locator
    then
      raise exception
        'Knowledge fragment version is semantically immutable; create a new version';
    end if;
  end if;

  return new;
end
$function$;

create trigger trg_knowledge_fragments_guard
before update on atp_test.knowledge_fragments
for each row execute function atp_test.guard_knowledge_fragment_update();

create function atp_test.guard_knowledge_embedding_update()
returns trigger
language plpgsql
set search_path = pg_catalog, atp_test
as $function$
declare
  v_published boolean;
begin
  if old.embedding_state = 'ready'
     and new.embedding_state not in ('ready', 'invalidated')
  then
    raise exception
      'Ready knowledge embedding can only remain ready or become invalidated';
  end if;

  if old.validation_status = 'passed' and new.validation_status <> 'passed' then
    raise exception
      'Validated knowledge embedding cannot regress validation; invalidate or create a new version';
  end if;

  if old.version_state in ('current', 'superseded', 'invalidated')
     and new.version_state = 'candidate'
  then
    raise exception
      'Knowledge embedding cannot return to candidate state';
  end if;

  select exists (
    select 1
    from atp_test.knowledge_publication_fragments pf
    join atp_test.knowledge_publications p
      on p.publication_id = pf.publication_id
    where pf.embedding_id = old.embedding_id
      and p.publication_state in ('published', 'superseded', 'archived')
  )
  into v_published;

  if old.embedding_state = 'ready' or v_published then
    if old.fragment_id is distinct from new.fragment_id
       or old.version_no is distinct from new.version_no
       or old.predecessor_embedding_id is distinct from new.predecessor_embedding_id
       or old.provider is distinct from new.provider
       or old.model_name is distinct from new.model_name
       or old.model_version is distinct from new.model_version
       or old.config_version is distinct from new.config_version
       or old.config is distinct from new.config
       or old.dimensions is distinct from new.dimensions
       or old.vector_data is distinct from new.vector_data
       or old.input_sha256 is distinct from new.input_sha256
       or old.external_api is distinct from new.external_api
    then
      raise exception
        'Knowledge embedding version is immutable after ready/publication; create a new version';
    end if;
  end if;

  return new;
end
$function$;

create trigger trg_knowledge_embeddings_guard
before update on atp_test.knowledge_embeddings
for each row execute function atp_test.guard_knowledge_embedding_update();

-- Internal published-only runtime source surface.
-- DB-07 must expose it through product-scoped restricted access.
-- Do NOT grant product readers unrestricted SELECT on this raw view.
create view atp_test.v_runtime_knowledge_fragments as
select
  p.publication_id,
  p.family_ref as publication_family_ref,
  p.version_no as publication_version_no,
  pp.product_code,
  d.document_id,
  d.stable_code as document_code,
  dv.document_version_id,
  f.fragment_id,
  f.fragment_family_key,
  f.fragment_version_no,
  f.fragment_order,
  f.fragment_text,
  f.content_sha256 as fragment_sha256,
  pf.requires_embedding,
  e.embedding_id,
  e.provider as embedding_provider,
  e.model_name as embedding_model,
  e.model_version as embedding_model_version,
  e.config_version as embedding_config_version,
  e.dimensions as embedding_dimensions,
  e.vector_data
from atp_test.knowledge_publications p
join atp_test.knowledge_publication_fragments pf
  on pf.publication_id = p.publication_id
join atp_test.knowledge_publication_fragment_products pp
  on pp.publication_id = pf.publication_id
 and pp.fragment_id = pf.fragment_id
join atp_test.knowledge_fragments f
  on f.fragment_id = pf.fragment_id
join atp_test.knowledge_document_versions dv
  on dv.document_version_id = pf.document_version_id
join atp_test.knowledge_documents d
  on d.document_id = dv.document_id
left join atp_test.knowledge_embeddings e
  on e.embedding_id = pf.embedding_id
where p.publication_state = 'published'
  and p.is_current
  and p.validation_status = 'passed'
  and dv.editorial_state = 'ready'
  and dv.validation_status = 'passed'
  and dv.version_state <> 'invalidated'
  and f.validation_status = 'passed'
  and f.version_state <> 'invalidated'
  and (
    not pf.requires_embedding
    or (
      e.embedding_id is not null
      and e.embedding_state = 'ready'
      and e.validation_status = 'passed'
      and e.version_state <> 'invalidated'
    )
  );

comment on view atp_test.v_runtime_knowledge_fragments is
  'Internal published-only knowledge source. DB-07 must enforce product-scoped access and must not grant unrestricted SELECT to product runtime readers.';

commit;
