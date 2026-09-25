-- DB-04 rollback
-- APPROVED WORKING CONTOUR. Rollback is limited to schema shablon and requires an explicit safety check before execution.
-- Removes only DB-04 objects and refuses to run when later/unknown
-- relational objects already exist in shablon.

begin;

do $guard$
declare
  v_missing text;
  v_extra_relations text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'shablon'
  ) then
    raise exception 'DB-04 rollback refused: schema shablon does not exist';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('analysis_versions'),
      ('analysis_knowledge_inputs'),
      ('analysis_claims'),
      ('criterion_scores'),
      ('stage_results'),
      ('analysis_observations'),
      ('ai_inferred_outcomes'),
      ('evidence_sets'),
      ('evidence_conversation_refs'),
      ('evidence_knowledge_refs'),
      ('evidence_absence_checks')
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
      'DB-04 rollback refused: missing DB-04 relation(s): %',
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
      'v_runtime_knowledge_fragments',
      -- DB-04
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
    );

  if v_extra_relations is not null then
    raise exception
      'DB-04 rollback refused: later/unknown relations exist in shablon: %',
      v_extra_relations;
  end if;
end
$guard$;

drop table shablon.evidence_conversation_refs;
drop table shablon.evidence_knowledge_refs;
drop table shablon.evidence_absence_checks;
drop table shablon.evidence_sets;
drop table shablon.criterion_scores;
drop table shablon.stage_results;
drop table shablon.analysis_observations;
drop table shablon.ai_inferred_outcomes;
drop table shablon.analysis_claims;
drop table shablon.analysis_knowledge_inputs;
drop table shablon.analysis_versions;

alter table shablon.processing_quality
  drop constraint processing_quality_quality_inputs_call_unique;

alter table shablon.privacy_packages
  drop constraint privacy_packages_package_role_call_unique;

drop function shablon.guard_analysis_version_update();
drop function shablon.validate_analysis_evidence_gate(uuid);
drop function shablon.calculate_analysis_overall_score(uuid);
drop function shablon.validate_evidence_absence_check();
drop function shablon.validate_evidence_knowledge_ref();
drop function shablon.validate_evidence_conversation_ref();
drop function shablon.guard_evidence_ref_mutation();
drop function shablon.guard_evidence_set_mutation();
drop function shablon.validate_evidence_target_rule();
drop function shablon.validate_stage_result();
drop function shablon.validate_criterion_score();
drop function shablon.guard_analysis_child_mutation();
drop function shablon.guard_analysis_initial_state();

drop type shablon.absence_scope_kind;
drop type shablon.observation_type;
drop type shablon.evidence_rule_kind;
drop type shablon.evidence_coverage;
drop type shablon.evidence_integrity;
drop type shablon.evidence_type;
drop type shablon.evidence_requirement;
drop type shablon.analysis_claim_type;
drop type shablon.analysis_state;

commit;
