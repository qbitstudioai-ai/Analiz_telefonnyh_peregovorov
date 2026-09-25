-- DB-03 rollback
-- TEST/LOCAL ONLY.
-- Removes only DB-03 objects and refuses to run if later/unknown
-- relational objects already exist in atp_test.

begin;

do $guard$
declare
  v_missing text;
  v_extra_relations text;
begin
  if not exists (
    select 1
    from pg_namespace
    where nspname = 'atp_test'
  ) then
    raise exception 'DB-03 rollback refused: schema atp_test does not exist';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('prompt_versions'),
      ('methodology_versions'),
      ('methodology_criteria'),
      ('methodology_stages'),
      ('filter_rule_versions'),
      ('knowledge_documents'),
      ('knowledge_document_versions'),
      ('knowledge_fragments'),
      ('knowledge_embeddings'),
      ('knowledge_publications'),
      ('knowledge_publication_documents'),
      ('knowledge_publication_fragments'),
      ('knowledge_publication_fragment_products'),
      ('v_runtime_knowledge_fragments')
  ) as required(required_relation)
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname = required.required_relation
      and c.relkind in ('r', 'p', 'v', 'm')
  );

  if v_missing is not null then
    raise exception
      'DB-03 rollback refused: missing DB-03 relation(s): %',
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
      'speech_metrics',
      -- DB-03
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
      'knowledge_publication_fragment_products',
      'v_runtime_knowledge_fragments'
    );

  if v_extra_relations is not null then
    raise exception
      'DB-03 rollback refused: later/unknown relations exist in atp_test: %',
      v_extra_relations;
  end if;
end
$guard$;

drop view atp_test.v_runtime_knowledge_fragments;

alter table atp_test.filter_decisions
  drop constraint fk_filter_decisions_rules_version;

drop table atp_test.knowledge_publication_fragment_products;
drop table atp_test.knowledge_publication_fragments;
drop table atp_test.knowledge_publication_documents;
drop table atp_test.knowledge_publications;
drop table atp_test.knowledge_embeddings;
drop table atp_test.knowledge_fragments;
drop table atp_test.knowledge_document_versions;
drop table atp_test.knowledge_documents;

drop table atp_test.filter_rule_versions;
drop table atp_test.methodology_stages;
drop table atp_test.methodology_criteria;
drop table atp_test.methodology_versions;
drop table atp_test.prompt_versions;

drop function atp_test.guard_knowledge_embedding_update();
drop function atp_test.guard_knowledge_fragment_update();
drop function atp_test.guard_knowledge_document_update();
drop function atp_test.validate_knowledge_publication_activation();
drop function atp_test.guard_knowledge_publication_update();
drop function atp_test.guard_knowledge_publication_membership();
drop function atp_test.guard_methodology_child_mutation();
drop function atp_test.guard_config_semantic_update();
drop function atp_test.guard_config_initial_state();

drop type atp_test.knowledge_publication_state;
drop type atp_test.embedding_state;
drop type atp_test.knowledge_editorial_state;
drop type atp_test.config_version_state;

commit;
