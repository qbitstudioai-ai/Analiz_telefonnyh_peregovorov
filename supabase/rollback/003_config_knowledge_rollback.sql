-- DB-03 rollback
-- APPROVED WORKING CONTOUR. Rollback is limited to schema shablon and requires an explicit safety check before execution.
-- Removes only DB-03 objects and refuses to run if later/unknown
-- relational objects already exist in shablon.

begin;

do $guard$
declare
  v_missing text;
  v_extra_relations text;
begin
  if not exists (
    select 1
    from pg_namespace
    where nspname = 'shablon'
  ) then
    raise exception 'DB-03 rollback refused: schema shablon does not exist';
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
    where n.nspname = 'shablon'
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
  where n.nspname = 'shablon'
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
      'DB-03 rollback refused: later/unknown relations exist in shablon: %',
      v_extra_relations;
  end if;
end
$guard$;

drop view shablon.v_runtime_knowledge_fragments;

alter table shablon.filter_decisions
  drop constraint fk_filter_decisions_rules_version;

drop table shablon.knowledge_publication_fragment_products;
drop table shablon.knowledge_publication_fragments;
drop table shablon.knowledge_publication_documents;
drop table shablon.knowledge_publications;
drop table shablon.knowledge_embeddings;
drop table shablon.knowledge_fragments;
drop table shablon.knowledge_document_versions;
drop table shablon.knowledge_documents;

drop table shablon.filter_rule_versions;
drop table shablon.methodology_stages;
drop table shablon.methodology_criteria;
drop table shablon.methodology_versions;
drop table shablon.prompt_versions;

drop function shablon.guard_knowledge_embedding_update();
drop function shablon.guard_knowledge_fragment_update();
drop function shablon.guard_knowledge_document_update();
drop function shablon.validate_knowledge_publication_activation();
drop function shablon.guard_knowledge_publication_update();
drop function shablon.guard_knowledge_publication_membership();
drop function shablon.guard_methodology_child_mutation();
drop function shablon.guard_config_semantic_update();
drop function shablon.guard_config_initial_state();

drop type shablon.knowledge_publication_state;
drop type shablon.embedding_state;
drop type shablon.knowledge_editorial_state;
drop type shablon.config_version_state;

commit;
