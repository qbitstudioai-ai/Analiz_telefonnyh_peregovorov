-- DB-06 rollback
-- TEST/LOCAL ONLY.
-- Removes only DB-06 views/functions and refuses to run if later/unknown
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
    raise exception 'DB-06 rollback refused: schema atp_test does not exist';
  end if;

  select string_agg(required_relation, ', ' order by required_relation)
  into v_missing
  from (
    values
      ('v_dashboard_business_confirmations_current'),
      ('v_dashboard_delivery_current'),
      ('v_dashboard_processing_quality_current'),
      ('v_dashboard_speech_metrics_current'),
      ('v_dashboard_zvonki'),
      ('v_dashboard_obshchaya_kartina'),
      ('v_dashboard_menedzhery'),
      ('v_dashboard_kriterii'),
      ('v_dashboard_etapy'),
      ('v_dashboard_oshibki'),
      ('v_dashboard_rezultaty'),
      ('v_dashboard_kachestvo')
  ) as required(required_relation)
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atp_test'
      and c.relname = required.required_relation
      and c.relkind = 'v'
  );

  if v_missing is not null then
    raise exception
      'DB-06 rollback refused: missing DB-06 view(s): %',
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
      'managers','calls','call_events','operations','operation_attempts',
      'filter_decisions','call_links','temporary_audio_artifacts',
      -- DB-02
      'raw_transcripts','transcript_segments','role_assignment_versions',
      'role_assignments','pseudonymized_transcripts','pseudonymized_segments',
      'privacy_packages','privacy_package_segments','pseudonym_mappings',
      'processing_quality','speech_metrics',
      -- DB-03
      'prompt_versions','methodology_versions','methodology_criteria',
      'methodology_stages','filter_rule_versions','knowledge_documents',
      'knowledge_document_versions','knowledge_fragments','knowledge_embeddings',
      'knowledge_publications','knowledge_publication_documents',
      'knowledge_publication_fragments',
      'knowledge_publication_fragment_products','v_runtime_knowledge_fragments',
      -- DB-04
      'analysis_versions','analysis_knowledge_inputs','analysis_claims',
      'criterion_scores','stage_results','analysis_observations',
      'ai_inferred_outcomes','evidence_sets','evidence_conversation_refs',
      'evidence_knowledge_refs','evidence_absence_checks',
      -- DB-05
      'business_confirmations','callback_links','outgoing_actions',
      'delivery_attempts','analysis_disputes','corrections','audit_events',
      -- DB-06
      'v_dashboard_business_confirmations_current',
      'v_dashboard_delivery_current',
      'v_dashboard_processing_quality_current',
      'v_dashboard_speech_metrics_current',
      'v_dashboard_zvonki',
      'v_dashboard_obshchaya_kartina',
      'v_dashboard_menedzhery',
      'v_dashboard_kriterii',
      'v_dashboard_etapy',
      'v_dashboard_oshibki',
      'v_dashboard_rezultaty',
      'v_dashboard_kachestvo'
    );

  if v_extra_relations is not null then
    raise exception
      'DB-06 rollback refused: later/unknown relations exist in atp_test: %',
      v_extra_relations;
  end if;
end
$guard$;

drop function atp_test.dashboard_result_metrics(timestamptz, timestamptz, jsonb);
drop function atp_test.dashboard_observation_metrics(timestamptz, timestamptz, jsonb);
drop function atp_test.dashboard_stage_metrics(timestamptz, timestamptz, jsonb);
drop function atp_test.dashboard_criterion_metrics(timestamptz, timestamptz, jsonb);
drop function atp_test.dashboard_manager_metrics(
  timestamptz, timestamptz, jsonb, text[], text[]
);
drop function atp_test.dashboard_overview(
  timestamptz, timestamptz, jsonb, timestamptz, interval, text[], text[]
);
drop function atp_test.dashboard_filter_call_ids(timestamptz, timestamptz, jsonb);

drop view atp_test.v_dashboard_kachestvo;
drop view atp_test.v_dashboard_rezultaty;
drop view atp_test.v_dashboard_oshibki;
drop view atp_test.v_dashboard_etapy;
drop view atp_test.v_dashboard_kriterii;
drop view atp_test.v_dashboard_menedzhery;
drop view atp_test.v_dashboard_obshchaya_kartina;
drop view atp_test.v_dashboard_zvonki;
drop view atp_test.v_dashboard_speech_metrics_current;
drop view atp_test.v_dashboard_processing_quality_current;
drop view atp_test.v_dashboard_delivery_current;
drop view atp_test.v_dashboard_business_confirmations_current;

commit;
