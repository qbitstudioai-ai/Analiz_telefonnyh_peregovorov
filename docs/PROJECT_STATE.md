# Текущее состояние проекта

Обновлено: 2026-09-25. Реализация шаблона в test/локальном режиме.

## Режим

**Разрешена реализация только в test/локальном контуре по одной задаче из [WORKPLAN_IMPLEMENTATION](WORKPLAN_IMPLEMENTATION.md).**

Production не разрешён. Созданные SQL/workflow/code не считаются применёнными без фактического запуска и проверки в test.

## Последняя завершённая задача

**DB-02 — создан SQL-слой транскрипции и privacy.**

Созданы migration/verify/rollback и [описание DB-02](implementation/DB-02.md).

Статически подтверждено:

- 11 новых DB-02 таблиц;
- raw transcript, pseudonymized transcript и reverse mapping физически разделены;
- privacy package/segment set не имеют direct FK на raw transcript/raw segments/mapping;
- blocked privacy package не допускает LLM operation;
- exact call/transcript/role ownership защищён composite FK;
- retention mapping удаляет и protected value, и protected local ref;
- version/current constraints и processing-quality/speech-metrics связи присутствуют;
- executable SQL не содержит bytea/blob/service_role/production DDL;
- признаков типовых реальных секретов не найдено.

Не проверено: фактическое выполнение PostgreSQL/Supabase. DB-01 и DB-02 созданы в GitHub, но не применены.

## Следующая одна задача

**DB-03 — подготовить migration конфигураций и общей базы знаний.**

Исполнитель: **ChatGPT**.

Цель: реализовать versioned prompt/methodology/filter и knowledge document/fragment/embedding/publication model с exact published membership и product scope.

Критерий готовности: migration/verify/rollback в GitHub; draft не смешан с publication, publication фиксирует exact versions, embedding привязан к exact fragment+model/config, current/history/invalidation различимы, SQL статически проверен и не считается применённым.

## Что ещё не применялось

DB-01/DB-02/DB-03 SQL, workflow, код, изменения n8n/Supabase/сервера, реальные Credentials, реальные данные/документы компаний, backup и production фактически не применялись и не тестировались.
