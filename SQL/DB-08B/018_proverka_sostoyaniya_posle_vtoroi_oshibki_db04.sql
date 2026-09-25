-- DB-08B / DB-04 post-error state check after failed step 016
-- READ ONLY. Ничего не создаёт, не изменяет и не удаляет.
-- PASS = запрос завершился успешно и вернул 0 строк.
-- Если будет хотя бы одна строка, НЕ запускать следующий SQL и передать результат ChatGPT.

with unexpected_objects as (
  select
    'relation'::text as object_kind,
    c.relname::text as object_name
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and c.relkind in ('r', 'p', 'v', 'm')
    and c.relname in (
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

  union all

  select
    'type'::text,
    t.typname::text
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and t.typname in (
      'analysis_state',
      'analysis_claim_type',
      'evidence_requirement',
      'evidence_type',
      'evidence_integrity',
      'evidence_coverage',
      'evidence_rule_kind',
      'observation_type',
      'absence_scope_kind'
    )

  union all

  select
    'function'::text,
    p.proname::text
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and p.proname in (
      'guard_analysis_initial_state',
      'guard_analysis_child_mutation',
      'validate_criterion_score',
      'validate_stage_result',
      'validate_evidence_target_rule',
      'guard_evidence_set_mutation',
      'guard_evidence_ref_mutation',
      'validate_evidence_conversation_ref',
      'validate_evidence_knowledge_ref',
      'validate_evidence_absence_check',
      'calculate_analysis_overall_score',
      'validate_analysis_evidence_gate',
      'guard_analysis_version_update'
    )

  union all

  select
    'constraint'::text,
    con.conname::text
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
    and (
      (c.relname = 'privacy_packages'
       and con.conname = 'privacy_packages_package_role_call_unique')
      or
      (c.relname = 'processing_quality'
       and con.conname = 'processing_quality_quality_inputs_call_unique')
    )
)
select object_kind, object_name
from unexpected_objects
order by object_kind, object_name;
