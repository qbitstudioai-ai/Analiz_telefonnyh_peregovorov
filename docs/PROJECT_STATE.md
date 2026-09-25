# Текущее состояние проекта

Обновлено: 2026-09-25. Реализация шаблона в test/локальном режиме.

## Режим

**Разрешена реализация только в test/локальном контуре по одной задаче из [WORKPLAN_IMPLEMENTATION](WORKPLAN_IMPLEMENTATION.md).**

Production не разрешён. Созданные SQL/workflow/code не считаются применёнными без фактического запуска и проверки в test.

## Последняя завершённая задача

**DB-03 — создан SQL-слой конфигураций и общей базы знаний.**

Созданы migration/verify/rollback и [описание DB-03](implementation/DB-03.md).

Статически подтверждено:

- 13 DB-03 tables + 1 internal published-only knowledge view;
- prompt/methodology/filter версии обязаны начинаться как draft и после activation не редактируются in-place;
- methodology criteria/stages заморожены после выхода parent из draft;
- filter decision теперь имеет FK на exact filter-rule version;
- canonical document, document version, fragment version и embedding version разделены;
- publication фиксирует exact document/fragment/embedding membership;
- published membership/manifest нельзя вернуть в draft/ready или переписать;
- каждый published fragment имеет explicit product scope;
- external embedding проверяется по exact document policy и exact fragment hash;
- один canonical fragment может обслуживать несколько продуктов без копирования исходного документа;
- raw internal runtime view не предназначен для прямого GRANT product-reader; product-scoped permission boundary будет DB-07;
- executable SQL не содержит production schema DDL/service_role/bytea/blob;
- признаков типовых реальных секретов не найдено.

Не проверено: фактическое выполнение PostgreSQL/Supabase. DB-01—DB-03 созданы в GitHub, но не применены.

## Следующая одна задача

**DB-04 — подготовить migration analysis и evidence.**

Исполнитель: **ChatGPT**.

Цель: физически реализовать immutable analysis input manifest, criteria/stages/observations/AI outcome и проверяемую evidence-модель, которая допускает current analysis только после evidence gate.

Критерий готовности: migration/verify/rollback в GitHub; analysis pins exact upstream versions, fake/non-input segment/knowledge refs блокируются, evidence types/coverage физически различимы, current analysis требует passed evidence gate, SQL статически проверен и не считается применённым.

## Что ещё не применялось

DB-01—DB-04 SQL, workflow, код, изменения n8n/Supabase/сервера, реальные Credentials, реальные данные/документы компаний, backup и production фактически не применялись и не тестировались.
