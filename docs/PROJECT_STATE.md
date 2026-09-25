# Текущее состояние проекта

Обновлено: 2026-09-25. Реализация шаблона в test/локальном режиме.

## Режим

**Разрешена реализация только в test/локальном контуре по одной задаче из [WORKPLAN_IMPLEMENTATION](WORKPLAN_IMPLEMENTATION.md).**

Production не разрешён. Созданные SQL/workflow/code не считаются применёнными без фактического запуска и проверки в test.

## Последняя завершённая задача

**DB-06 — создан server-side SQL-слой dashboard metrics.**

Созданы migration/verify/rollback и [описание DB-06](implementation/DB-06.md).

Статически подтверждено:

- 12 DB-06 views и 7 shared metric/filter functions;
- dashboard считается по logical calls, а не webhook events;
- четыре terminal categories взаимно исключаются;
- official score использует current reliable analysis без open dispute;
- preliminary/technically incomplete считаются отдельно;
- N/A criterion не превращается в zero;
- stage denominator использует applicable calls;
- observation denominator выводится из applicable criterion/stage context;
- AI outcome и CRM/human fact остаются раздельными result sources;
- callback without-call считается только после переданного окна компании;
- speech metrics при current analysis совпадают с exact transcript/role inputs;
- все агрегаты используют один shared period/filter contract;
- metric functions возвращают drill-down call IDs;
- migration/rollback совпадают по 12 views и 7 functions;
- SQL lexical structure сбалансирована;
- CASCADE, executable service_role, bytea/blob, production DDL и признаки типовых секретов отсутствуют.

Не проверено: фактическое выполнение PostgreSQL/Supabase и численные fixture results. DB-01—DB-06 созданы в GitHub, но не применены.

## Следующая одна задача

**DB-07 — подготовить изоляцию и права test.**

Исполнитель: **ChatGPT**.

Цель: физически ограничить test runtime roles по обязанностям и подготовить negative permission tests без production roles/credentials.

Критерий готовности: migration/verify/rollback в GitHub; ordinary roles не имеют broad admin access, raw/mapping/knowledge/dashboard boundaries разделены, writes разрешены только обязанностям, negative tests проверяют denied operations, SQL статически проверен и не считается применённым.

## Что ещё не применялось

DB-01—DB-07 SQL, workflow, код, изменения n8n/Supabase/сервера, реальные Credentials, реальные данные/документы компаний, backup и production фактически не применялись и не тестировались.
