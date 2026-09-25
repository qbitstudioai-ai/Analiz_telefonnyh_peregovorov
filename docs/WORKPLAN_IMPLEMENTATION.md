# План реализации шаблона

Статус: активируется после GATE-01 25 сентября 2026 года.

## Режим

Разрешена реализация **только в test/локальном контуре**.

Это разрешает создавать и проверять SQL, workflow, программный код и тестовые артефакты в репозитории и test-среде по отдельным задачам.

Это **не разрешение production**. Production-миграции, production Credentials, переключение рабочего трафика, удаление рабочих данных и реальные production side effects требуют отдельного явного разрешения Павла и [RELEASE_CHECKLIST](RELEASE_CHECKLIST.md).

Статусы: `[ ]` не начато, `[~]` в работе, `[x]` проверено, `[!]` пауза.

## Принципы реализации

- одна небольшая задача — один проверяемый результат;
- GitHub и фактический test-результат важнее пересказа;
- физическая реализация не меняет смысл DOC-04—DOC-18;
- test и production не используют общие Credentials;
- секреты, записи разговоров и частные данные не попадают в GitHub;
- SQL-файл, применённая миграция и проверенная БД — разные статусы;
- JSON workflow, импортированный workflow и успешно пройденный test — разные статусы;
- код/дашборд, deployed test build и production — разные статусы;
- перед применением destructive/production действий нужен отдельный gate.

## Этап A — физическая модель Supabase

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [x] DB-01 | ChatGPT | Базовая migration приёма и надёжности | Созданы migration/verify/guarded rollback для 8 базовых таблиц test-контура; статически проверены баланс SQL, состав таблиц, отсутствие executable bytea/blob/service_role/production DDL и составные FK call-operation; к Supabase не применено |
| [ ] DB-02 | ChatGPT | Migration транскрипции/privacy | Физически представлены transcript/segments/roles/pseudonymized package/mapping metadata с version links и retention fields без хранения постоянного аудио |
| [ ] DB-03 | ChatGPT | Migration конфигураций и знаний | Реализованы versioned prompt/methodology/filter/knowledge document-fragment-embedding-publication структуры и immutable provenance |
| [ ] DB-04 | ChatGPT | Migration analysis/evidence | Реализованы analyses, criteria, stages, observations, evidence, current/history и input manifest без fake refs |
| [ ] DB-05 | ChatGPT | Migration CRM/outgoing/corrections/audit | Реализованы CRM confirmations, outgoing actions/delivery attempts, callbacks, corrections и audit trail |
| [ ] DB-06 | ChatGPT | Dashboard views/metric SQL | Представления и функции реализуют METRICS/DASHBOARD_DATA_MAP без альтернативных формул |
| [ ] DB-07 | ChatGPT | Изоляция и права test | Созданы ограниченные test roles/grants/RLS/functions; negative tests DOC-10 подтверждают изоляцию на test |
| [ ] DB-08 | Павел + ChatGPT | Применение migrations в test Supabase | Павел запускает подготовленный SQL в test; ChatGPT по фактическому результату проверяет schema, constraints, права и rollback/recovery; production не затрагивается |

## Этап B — обработка и контракты

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [ ] CORE-01 | VSCode | Общие contract/version/idempotency validators | Автотесты покрывают accepted/duplicate/rejected, operation states, scope и unknown contract |
| [ ] CORE-02 | VSCode | Privacy package/gate | Тесты подтверждают, что raw identifiers/mapping/secrets не проходят во внешний пакет |
| [ ] CORE-03 | VSCode | Evidence/version gates | Fake segment/chunk refs блокируются, immutable input manifest воспроизводим |
| [ ] CORE-04 | VSCode | Knowledge retrieval boundary | Retrieval фиксирует publication + exact fragments и не делает cross-company/draft fallback |

## Этап C — n8n test workflows

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [ ] N8N-01 | ChatGPT | Вход/регистрация/дедупликация/фильтрация | Полный JSON импортируется в test n8n и корректно обрабатывает normal/duplicate/excluded/missed cases |
| [ ] N8N-02 | ChatGPT | Получение/временное аудио/cleanup | JSON соблюдает AUDIO_RETENTION, сохраняет metadata и не делает аудио постоянным |
| [ ] N8N-03 | ChatGPT + VSCode | Транскрибация/диаризация/роли | Test workflow использует выбранный после испытаний локальный adapter и фиксирует quality/provenance |
| [ ] N8N-04 | ChatGPT | Privacy/knowledge/LLM analysis | Внешний вызов возможен только после privacy-gate; analysis сохраняет versions/evidence |
| [ ] N8N-05 | ChatGPT | CRM/result/delivery | AI result отделён от CRM fact; outgoing action создаётся до send; retry/outcome_unknown безопасны |
| [ ] N8N-06 | ChatGPT | Recovery/reconciliation/cleanup | Partial failures DOC-05 восстанавливаются с сохранённой точки без дублей |

## Этап D — модели и контрольный набор

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [ ] AI-01 | Павел + ChatGPT | Разрешённый контрольный набор | Определены доступ, retention и эталоны без публикации реальных данных в GitHub |
| [ ] AI-02 | VSCode | Benchmark кандидатов транскрибации/диаризации | Измерены WER/CER/DER/таймкоды/RTF/resources на test hardware |
| [ ] AI-03 | Павел + ChatGPT | Выбор stack/thresholds | Павел утверждает вариант на основе измерений; выбор и ограничения записаны |
| [ ] AI-04 | VSCode | Load/resource test | Проверена согласованная concurrency и backlog recovery на репрезентативном железе |

## Этап E — dashboard/admin

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [ ] UI-01 | VSCode | Test dashboard backend | Сервер читает только разрешённый contour и общие metric views |
| [ ] UI-02 | VSCode | Dashboard UI | Фильтры/drill-down/evidence соответствуют FEEDBACK_AND_DASHBOARD |
| [ ] UI-03 | VSCode | Admin capabilities/audit | Draft/activation/correction/operations разделены; секреты не раскрываются |
| [ ] UI-04 | VSCode | Negative authorization tests | URL/ID manipulation не раскрывает другой contour/raw data/admin actions |

## Этап F — эксплуатационная test-готовность

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [ ] OPS-01 | VSCode | Test deployment stack | Test services воспроизводимо поднимаются без production Credentials |
| [ ] OPS-02 | VSCode | Monitoring/alerts | Проверены service/down, backlog, cleanup, disk, backup и alert delivery |
| [ ] OPS-03 | VSCode + Павел | Backup/restore test | Создан test backup и фактически восстановлен в quarantine; side effects отключены |
| [ ] OPS-04 | ChatGPT | Full test release checklist | Все обязательные applicable gates имеют PASS/evidence либо перечислены blockers |

## Gate production

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [ ] PROD-GATE | Павел | Отдельное решение о production | Павел явно разрешает конкретный release после test evidence, rollback/reconciliation и RELEASE_CHECKLIST; без этого production запрещён |

## Текущая следующая задача

**DB-02 — migration транскрипции и privacy.**

Цель: подготовить второй SQL-набор поверх DB-01 для versioned transcription/privacy данных без применения к Supabase.

Объём DB-02:

- исходные транскрипции;
- сегменты с таймкодами/technical speaker;
- версии назначения ролей МЕНЕДЖЕР/КЛИЕНТ;
- псевдонимизированные транскрипции;
- privacy packages/gate result;
- защищённые pseudonym mappings metadata;
- processing quality;
- speech metrics.

Критерий готовности:

- migration/verify/rollback записаны в GitHub;
- новые сущности связаны с exact call/transcript/operation versions;
- raw/pseudonym/mapping физически разделены;
- внешний privacy package не может ссылаться на mapping/raw content;
- retention metadata предусмотрены;
- SQL проходит статическую проверку;
- к Supabase не применён.

Профильные документы DB-02: [DATA_DICTIONARY](DATA_DICTIONARY.md), [TRANSCRIPTION_AND_PRIVACY](specs/TRANSCRIPTION_AND_PRIVACY.md), [VERSIONING](specs/VERSIONING.md), [INTEGRATION_CONTRACTS](specs/INTEGRATION_CONTRACTS.md), [ACCESS_AND_ISOLATION](specs/ACCESS_AND_ISOLATION.md), [RELEASE_CHECKLIST](RELEASE_CHECKLIST.md).
