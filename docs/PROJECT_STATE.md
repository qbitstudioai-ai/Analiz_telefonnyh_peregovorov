# Текущее состояние проекта

Обновлено: 2026-09-25. Реализация шаблона в test/локальном режиме.

## Режим

**Разрешена реализация только в test/локальном контуре по одной задаче из [WORKPLAN_IMPLEMENTATION](WORKPLAN_IMPLEMENTATION.md).**

Production не разрешён. Созданные SQL/workflow/code не считаются применёнными без фактического запуска и проверки в test.

## Последняя завершённая задача

**DB-07 — создан канонический SQL-слой test access/isolation.**

Канонический комплект:

- `supabase/migrations/007_test_access_isolation.sql`;
- `supabase/verify/007_test_access_isolation_verify.sql`;
- `supabase/rollback/007_test_access_isolation_rollback.sql`;
- [описание DB-07](implementation/DB-07.md).

Во время финальной сверки найден второй параллельно созданный DB-07 комплект. Он был сравнен с более ранним GitHub-вариантом; полезные улучшения перенесены в ранний канонический комплект, SQL-дефект `evidence_knowledge_ref_id` исправлен, повторные файлы удалены.

Статически подтверждено:

- 9 NOLOGIN capability roles без superuser/createdb/createrole/replication/bypassrls;
- отдельные orchestrator, CORE, privacy, raw-reader, knowledge-reader, knowledge-admin, dashboard, admin-api и monitoring capabilities;
- 18 `security_barrier` runtime/safe views;
- runtime prompt/methodology/filter views показывают только active+passed configuration;
- product knowledge reader читает только published `call_analysis` scope;
- dashboard читает privacy-passed pseudonymized segments/evidence без raw/mapping/base-table bypass;
- отдельная raw transcript reader capability не получает pseudonym mapping;
- 5 RLS policies служат defense-in-depth role gate на raw transcripts/segments/mapping, а межфирменная граница остаётся schema + отдельная Credential;
- 2 controlled SECURITY DEFINER admin functions создают dispute/correction proposal + audit, но не применяют correction автоматически;
- knowledge administration отделено от runtime reader и call/privacy data;
- monitoring видит только минимизированные technical views;
- PUBLIC relation/function access и default PUBLIC function EXECUTE закрыты;
- verify содержит другой-test и production-like probe schemas, positive/negative privilege matrix, destructive privilege/secret-column checks;
- rollback отказывается при уже привязанных login-role memberships и later/unknown relations;
- migration/rollback совпадают по 9 roles, 18 views, 2 functions и 5 policies;
- SQL lexical structure сбалансирована;
- plaintext password, executable service_role, bytea/blob, production DDL, CASCADE и признаки типовых реальных секретов отсутствуют.

Не проверено: фактическое выполнение PostgreSQL/Supabase и реальные privilege/RLS denials. DB-01—DB-07 созданы в GitHub, но не применены.

## Следующая одна задача

**DB-08 — применить migrations DB-01—DB-07 в test Supabase и выполнить verify.**

Исполнители: **Павел + ChatGPT**.

Павел выполняет только готовые SQL-действия в test Supabase и сообщает фактический результат. ChatGPT ведёт порядок, анализирует ошибки, сверяет schema/constraints/views/functions/roles/policies и фиксирует PASS/FAIL.

Критерий готовности: migrations 001—007 и verify 001—007 фактически выполнены в test; privilege/isolation checks подтверждены; rollback/recovery проверен безопасно; секреты/production не затронуты. До такого подтверждения схема остаётся только созданной в GitHub.

## Что ещё не применялось

DB-01—DB-07 SQL, workflow, код, изменения n8n/Supabase/сервера, реальные Credentials, реальные данные/документы компаний, backup и production фактически не применялись и не тестировались.
