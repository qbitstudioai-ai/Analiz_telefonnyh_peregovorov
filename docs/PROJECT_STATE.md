# Текущее состояние проекта

Обновлено: 2026-09-25. Реализация шаблона в test/локальном режиме.

## Режим

**Разрешена реализация только в test/локальном контуре по одной задаче из [WORKPLAN_IMPLEMENTATION](WORKPLAN_IMPLEMENTATION.md).**

Production не разрешён. Созданные SQL/workflow/code не считаются применёнными без фактического запуска и проверки в test.

## Последняя завершённая задача

**DB-01 — создан базовый SQL-слой приёма и надёжности.**

Созданы:

- `supabase/migrations/001_base_ingest_reliability.sql`;
- `supabase/verify/001_base_ingest_reliability_verify.sql`;
- `supabase/rollback/001_base_ingest_reliability_rollback.sql`;
- [описание DB-01](implementation/DB-01.md).

Проверено статически:

- migration создаёт ровно 8 первичных таблиц `atp_test`;
- SQL lexical structure сбалансирована;
- executable SQL не содержит `bytea`/blob, `service_role` и production schema DDL;
- event identity и call identity защищены от второго non-duplicate результата;
- logical operation имеет idempotency key, retry вынесен в attempts;
- filter/audio ownership защищены составными FK `operation + call`;
- rollback отказывается удалять schema при наличии later/unknown tables.

Не проверено: фактическое выполнение PostgreSQL/Supabase. DB-01 создан в GitHub, но не применён.

## Следующая одна задача

**DB-02 — подготовить migration транскрипции и privacy для test.**

Исполнитель: **ChatGPT**.

Цель: поверх DB-01 реализовать исходные/псевдонимизированные транскрипции, segments, role assignments, privacy packages/mappings, quality и speech metrics с version/provenance/retention связями.

Критерий готовности: migration/verify/rollback записаны в GitHub, raw/pseudonym/mapping разделены физически, exact versions/operations связаны FK, privacy package не содержит mapping/raw content, retention metadata есть, SQL статически проверен и **не считается применённым**.

## Что ещё не применялось

DB-01/DB-02 SQL, workflow, код, изменения n8n/Supabase/сервера, реальные Credentials, реальные данные/документы компаний, backup и production фактически не применялись и не тестировались.
