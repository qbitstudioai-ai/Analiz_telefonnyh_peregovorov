-- DB-05 rollback
-- APPROVED WORKING CONTOUR. Rollback is limited to schema shablon_analiz_telefonnyh_peregovorov and requires an explicit safety check before execution.
-- Removes only DB-05 objects and refuses to run if later/unknown
-- relational objects already exist in shablon_analiz_telefonnyh_peregovorov.

begin;

do $guard$
declare
  v_missing text;
  v_extra_relations text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'shablon_analiz_telefonnyh_peregovorov'
  ) then
    raise exception 'DB-05 rollback refused: schema shablon_analiz_telefonnyh_peregovorov does not exist';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('business_confirmations'),
      ('callback_links'),
      ('outgoing_actions'),
      ('delivery_attempts'),
      ('analysis_disputes'),
      ('corrections'),
      ('audit_events')
  ) as required(required_relation)
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
      and c.relname = required.required_relation
      and c.relkind in ('r', 'p', 'v', 'm')
  );

  if v_missing is not null then
    raise exception
      'DB-05 rollback refused: missing DB-05 relation(s): %',
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
      'evidence_absence_checks',
      -- DB-05
      'business_confirmations',
      'callback_links',
      'outgoing_actions',
      'delivery_attempts',
      'analysis_disputes',
      'corrections',
      'audit_events'
    );

  if v_extra_relations is not null then
    raise exception
      'DB-05 rollback refused: later/unknown relations exist in shablon_analiz_telefonnyh_peregovorov: %',
      v_extra_relations;
  end if;
end
$guard$;

drop table shablon_analiz_telefonnyh_peregovorov.audit_events;
drop table shablon_analiz_telefonnyh_peregovorov.corrections;
drop table shablon_analiz_telefonnyh_peregovorov.analysis_disputes;
drop table shablon_analiz_telefonnyh_peregovorov.delivery_attempts;
drop table shablon_analiz_telefonnyh_peregovorov.outgoing_actions;
drop table shablon_analiz_telefonnyh_peregovorov.callback_links;
drop table shablon_analiz_telefonnyh_peregovorov.business_confirmations;

alter table shablon_analiz_telefonnyh_peregovorov.role_assignment_versions
  drop constraint role_assignment_versions_role_call_unique;

alter table shablon_analiz_telefonnyh_peregovorov.operation_attempts
  drop constraint operation_attempts_attempt_operation_unique;

drop function shablon_analiz_telefonnyh_peregovorov.guard_audit_event_append_only();
drop function shablon_analiz_telefonnyh_peregovorov.guard_correction_update();
drop function shablon_analiz_telefonnyh_peregovorov.guard_correction_initial_state();
drop function shablon_analiz_telefonnyh_peregovorov.guard_analysis_dispute_update();
drop function shablon_analiz_telefonnyh_peregovorov.guard_analysis_dispute_initial_state();
drop function shablon_analiz_telefonnyh_peregovorov.guard_delivery_attempt_delete();
drop function shablon_analiz_telefonnyh_peregovorov.guard_delivery_attempt_update();
drop function shablon_analiz_telefonnyh_peregovorov.guard_delivery_attempt_insert();
drop function shablon_analiz_telefonnyh_peregovorov.guard_outgoing_action_update();
drop function shablon_analiz_telefonnyh_peregovorov.validate_outgoing_action_insert();
drop function shablon_analiz_telefonnyh_peregovorov.guard_callback_link_update();
drop function shablon_analiz_telefonnyh_peregovorov.validate_callback_link();
drop function shablon_analiz_telefonnyh_peregovorov.guard_db05_history_delete();
drop function shablon_analiz_telefonnyh_peregovorov.guard_business_confirmation_immutable();
drop function shablon_analiz_telefonnyh_peregovorov.validate_business_confirmation_insert();

drop type shablon_analiz_telefonnyh_peregovorov.audit_result;
drop type shablon_analiz_telefonnyh_peregovorov.correction_target_type;
drop type shablon_analiz_telefonnyh_peregovorov.correction_state;
drop type shablon_analiz_telefonnyh_peregovorov.dispute_state;
drop type shablon_analiz_telefonnyh_peregovorov.delivery_reconciliation_state;
drop type shablon_analiz_telefonnyh_peregovorov.delivery_provider_status;
drop type shablon_analiz_telefonnyh_peregovorov.outgoing_action_state;
drop type shablon_analiz_telefonnyh_peregovorov.callback_link_state;
drop type shablon_analiz_telefonnyh_peregovorov.business_confirmation_event_kind;
drop type shablon_analiz_telefonnyh_peregovorov.business_confirmation_source;

commit;
