# Текущее состояние проекта

Обновлено: 2026-09-25. Реализация шаблона в test/локальном режиме.

## Режим

**Разрешена реализация только в test/локальном контуре по одной задаче из [WORKPLAN_IMPLEMENTATION](WORKPLAN_IMPLEMENTATION.md).**

Production не разрешён. Созданные SQL/workflow/code не считаются применёнными без фактического запуска и проверки в test.

## Последняя завершённая задача

**DB-05 — создан SQL-слой CRM/outgoing/corrections/audit.**

Созданы migration/verify/rollback и [описание DB-05](implementation/DB-05.md).

Статически подтверждено:

- 7 DB-05 tables, 10 enum types, 15 functions и 18 triggers;
- CRM/human confirmation физически отделён от AI inferred outcome;
- correction/cancel CRM-факта создают новую immutable source event chain;
- callback связывает missed → outbound call только по trusted basis и финальное решение immutable;
- outgoing action создаётся до delivery attempt и pin exact validated/current analysis;
- succeeded delivery требует provider-confirmed delivered;
- safe retry разрешён только для failed_retryable;
- confirmed delivery блокирует следующую попытку;
- outcome_unknown блокирует retry до reconciliation;
- reconciliation различает confirmed_delivered / confirmed_not_delivered / unresolved;
- dispute не является прямым изменением score;
- correction начинается proposed и applied требует succeeded operation;
- audit trail append-only;
- migration/rollback совпадают по 7 tables, 10 types и 15 functions;
- SQL lexical structure сбалансирована;
- CASCADE, executable service_role, bytea/blob, production DDL и признаки типовых секретов отсутствуют.

Не проверено: фактическое выполнение PostgreSQL/Supabase. DB-01—DB-05 созданы в GitHub, но не применены.

## Следующая одна задача

**DB-06 — подготовить dashboard views/metric SQL.**

Исполнитель: **ChatGPT**.

Цель: реализовать server-side views/functions дашборда поверх DB-01—DB-05 строго по METRICS/DASHBOARD_DATA_MAP, без альтернативных формул.

Критерий готовности: migration/verify/rollback в GitHub; official averages используют только current reliable analysis, N/A не превращается в zero, AI outcome и CRM confirmation остаются раздельными, агрегаты раскрываются до call IDs, SQL статически проверен и не считается применённым.

## Что ещё не применялось

DB-01—DB-06 SQL, workflow, код, изменения n8n/Supabase/сервера, реальные Credentials, реальные данные/документы компаний, backup и production фактически не применялись и не тестировались.
