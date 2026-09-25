# Текущее состояние проекта

Обновлено: 2026-09-25. Реализация шаблона в test/локальном режиме.

## Режим

**Разрешена реализация только в test/локальном контуре по одной задаче из [WORKPLAN_IMPLEMENTATION](WORKPLAN_IMPLEMENTATION.md).**

Production не разрешён. Созданные SQL/workflow/code не считаются применёнными без фактического запуска и проверки в test.

## Последняя завершённая задача

**DB-07 — создан SQL-слой test access/isolation.**

Созданы migration/verify/rollback и [описание DB-07](implementation/DB-07.md).

Статически подтверждено:

- 8 NOLOGIN capability roles без superuser/createdb/createrole/replication/bypassrls;
- 6 security-barrier safe views;
- 4 controlled SECURITY DEFINER correction/dispute functions с pinned search_path;
- PUBLIC лишён ambient schema/table/function access в atp_test;
- future functions владельца migration не получают PUBLIC EXECUTE автоматически;
- orchestrator не читает raw/mapping и не администрирует знания;
- privacy role является единственной обычной runtime capability с raw transcript/pseudonym mapping access;
- CORE работает с pseudonymized inputs и product-scoped published knowledge без raw/mapping/base-draft knowledge;
- product knowledge reader читает только published call_analysis view и не publish/edit;
- dashboard read-only и не получает raw/mapping/base knowledge/direct correction writes;
- correction operator пишет только через controlled functions + audit;
- monitoring видит только минимизированные technical views;
- cross-schema negative checks подготовлены для другого test contour и production probe;
- RLS внутри single-company+environment schema сознательно не добавлен: tenant discriminator внутри contour отсутствует, поэтому изоляция обеспечивается schema + отдельной Credential + grants;
- migration/rollback совпадают по 8 roles, 6 views и 4 functions;
- SQL lexical structure сбалансирована;
- plaintext password, executable service_role, bytea/blob, production DDL, CASCADE и признаки типовых реальных секретов отсутствуют.

Не проверено: фактическое выполнение PostgreSQL/Supabase и реальные privilege denials. DB-01—DB-07 созданы в GitHub, но не применены.

## Следующая одна задача

**DB-08 — применить migrations DB-01—DB-07 в test Supabase и выполнить verify.**

Исполнители: **Павел + ChatGPT**.

Павел выполняет только готовые SQL-действия в test Supabase и сообщает фактический результат. ChatGPT ведёт порядок, анализирует ошибки, сверяет schema/constraints/roles и фиксирует PASS/FAIL.

Критерий готовности: migrations 001—007 и verify 001—007 фактически выполнены в test; privilege/isolation checks подтверждены; rollback/recovery проверен безопасно; секреты/production не затронуты. До такого подтверждения схема остаётся только созданной в GitHub.

## Что ещё не применялось

DB-01—DB-07 SQL, workflow, код, изменения n8n/Supabase/сервера, реальные Credentials, реальные данные/документы компаний, backup и production фактически не применялись и не тестировались.
