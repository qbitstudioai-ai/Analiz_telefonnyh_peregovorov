-- DB-05 rollback
-- TEST/LOCAL ONLY.
-- Removes only DB-05 objects and refuses to run if later/unknown
-- relational objects already exist in atp_test.

begin;

do $guard$
declare
  v_missing text;
  v_extra_relations text;
begin
  if not exists (
    select 1 from pg_namespace where nspname = 'atp_test'
  ) then
    raise exception 'DB-05 rollback refused: schema atp_test does not exist';
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
    where n.nspname = 'atp_test'
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
      'DB-05 rollback refused: later/unknown relations exist in atp_test: %',
      v_extra_relations;
  end if;
end
$guard$;

drop table atp_test.audit_events;
drop table atp_test.corrections;
drop table atp_test.analysis_disputes;
drop table atp_test.delivery_attempts;
drop table atp_test.outgoing_actions;
drop table atp_test.callback_links;
drop table atp_test.business_confirmations;

alter table atp_test.role_assignment_versions
  drop constraint role_assignment_versions_role_call_unique;

alter table atp_test.operation_attempts
  drop constraint operation_attempts_attempt_operation_unique;

drop function atp_test.guard_audit_event_append_only();
drop function atp_test.guard_correction_update();
drop function atp_test.guard_correction_initial_state();
drop function atp_test.guard_analysis_dispute_update();
drop function atp_test.guard_analysis_dispute_initial_state();
drop function atp_test.guard_delivery_attempt_delete();
drop function atp_test.guard_delivery_attempt_update();
drop function atp_test.guard_delivery_attempt_insert();
drop function atp_test.guard_outgoing_action_update();
drop function atp_test.validate_outgoing_action_insert();
drop function atp_test.guard_callback_link_update();
drop function atp_test.validate_callback_link();
drop function atp_test.guard_db05_history_delete();
drop function atp_test.guard_business_confirmation_immutable();
drop function atp_test.validate_business_confirmation_insert();

drop type atp_test.audit_result;
drop type atp_test.correction_target_type;
drop type atp_test.correction_state;
drop type atp_test.dispute_state;
drop type atp_test.delivery_reconciliation_state;
drop type atp_test.delivery_provider_status;
drop type atp_test.outgoing_action_state;
drop type atp_test.callback_link_state;
drop type atp_test.business_confirmation_event_kind;
drop type atp_test.business_confirmation_source;

commit;
