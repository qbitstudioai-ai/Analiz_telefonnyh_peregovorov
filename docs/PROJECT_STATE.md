# Текущее состояние проекта

Обновлено: 2026-09-25. Реализация шаблона в test/локальном режиме.

## Режим

**Разрешена реализация только в test/локальном контуре по одной задаче из [WORKPLAN_IMPLEMENTATION](WORKPLAN_IMPLEMENTATION.md).**

Production не разрешён. Созданные SQL/workflow/code не считаются применёнными без фактического запуска и проверки в test.

## Последняя завершённая задача

**DB-04 — создан SQL-слой analysis/evidence.**

Созданы migration/verify/rollback и [описание DB-04](implementation/DB-04.md).

Статически подтверждено:

- 11 DB-04 tables, 13 functions, 9 enum types и 18 triggers;
- analysis version фиксирует exact call/operation/transcript/roles/privacy/quality/prompt/methodology/knowledge publication/model/config manifest;
- direct INSERT сразу как validated/current заблокирован отдельным initial-state guard;
- candidate нельзя создать с заранее passed evidence gate;
- criteria/stages/observations/AI outcome являются typed claims exact analysis version;
- knowledge evidence может ссылаться только на exact `analysis_knowledge_inputs`;
- conversation evidence может ссылаться только на exact safe segment pinned privacy package;
- absence evidence использует scope + processing quality, а не выдуманную цитату;
- evidence reference integrity и coverage физически различимы;
- current analysis требует validated state, CORE validation и structural evidence gate;
- migration/rollback совпадают по 11 tables, 13 functions и 9 types;
- SQL lexical structure сбалансирована;
- executable `service_role`, `bytea/blob` и признаки типовых реальных секретов отсутствуют.

Не проверено: фактическое выполнение PostgreSQL/Supabase. DB-01—DB-04 созданы в GitHub, но не применены.

## Следующая одна задача

**DB-05 — подготовить migration CRM/outgoing/corrections/audit.**

Исполнитель: **ChatGPT**.

Цель: физически реализовать подтверждённые CRM/человеком факты, callback-связи, outgoing actions/delivery attempts, corrections/disputes и audit trail без смешения с AI outcome и без небезопасного повторения внешних side effects.

Критерий готовности: migration/verify/rollback в GitHub; CRM fact отделён от AI outcome, outgoing action создаётся до send, confirmed delivery блокирует повтор, outcome_unknown остаётся наблюдаемым/reconciliation-required, correction/audit сохраняют происхождение и историю, SQL статически проверен и не считается применённым.

## Что ещё не применялось

DB-01—DB-05 SQL, workflow, код, изменения n8n/Supabase/сервера, реальные Credentials, реальные данные/документы компаний, backup и production фактически не применялись и не тестировались.
