# План реализации шаблона

Статус: активируется после GATE-01 25 сентября 2026 года.

## Режим

Разрешена реализация **в рабочем Supabase только внутри schema `shablon_analiz_telefonnyh_peregovorov`**.

Это разрешает создавать, применять и проверять SQL внутри `shablon_analiz_telefonnyh_peregovorov`, а также по мере последующих задач подключать реальные сервисные Credentials к этому контуру.

Это **не blanket-разрешение на весь production**. Нельзя без отдельного решения менять/удалять посторонние схемы и данные, выполнять destructive rollback на единственном рабочем экземпляре или переключать реальный клиентский трафик.

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
| [x] DB-01 | ChatGPT + Павел | Базовая migration приёма и надёжности | Migration фактически применена в рабочем Supabase; исправленный verify PASS; подтверждены 8 базовых таблиц, dedup/idempotency/composite FK/temporary-audio constraints; синтетические verify-данные откатились |
| [x] DB-02 | ChatGPT + Павел | Migration транскрипции/privacy | Migration фактически применена в рабочем Supabase; verify PASS; подтверждены 11 DB-02 tables, raw/pseudonym/mapping separation, exact safe package set, role constraints, quality/speech metrics; verify-данные откатились |
| [x] DB-03 | ChatGPT + Павел | Migration конфигураций и знаний | Migration фактически применена в рабочем Supabase; verify PASS; подтверждены 13 tables + runtime source view, draft-first lifecycle, immutable publication membership, exact knowledge provenance и product scope; verify-данные откатились |
| [x] DB-04 | ChatGPT + Павел | Migration analysis/evidence | После двух исправленных DDL-дефектов migration фактически применена в рабочем Supabase; verify PASS; подтверждены 11 tables, typed claims/evidence, exact safe segment/knowledge refs, absence coverage и evidence gate; verify-данные откатились |
| [x] DB-05 | ChatGPT + Павел | Migration CRM/outgoing/corrections/audit | Migration фактически применена в рабочем Supabase; verify PASS; подтверждены 7 tables, CRM/human separation, outgoing-before-send, delivery/reconciliation guards, corrections/disputes и append-only audit; verify-данные откатились |
| [x] DB-06 | ChatGPT + Павел | Dashboard views/metric SQL | Migration фактически применена в рабочем Supabase; verify PASS; подтверждены 12 views + 7 metric/filter functions, shared filters, logical-call metrics, dispute/N/A gates и drill-down IDs; verify завершился rollback |
| [x] DB-07 | ChatGPT + Павел | Изоляция и права шаблонного контура | Migration фактически применена; после исправления PostgreSQL 17 creator-admin membership assumption и двух alias-конфликтов итоговый verify `033` PASS; подтверждены 9 NOLOGIN roles, 18 security-barrier views, 5 RLS policies, 2 SECURITY DEFINER functions, PUBLIC/default privilege hardening и positive/negative access matrix |
| [x] DB-08A | ChatGPT | Адаптация DB-01—DB-07 к рабочей schema `shablon` | Migration/verify/rollback были переведены с `atp_test` на рабочий контур `shablon`; SQL к Supabase не применялся |
| [x] DB-08A.1 | ChatGPT | Окончательное имя рабочего контура | До применения SQL schema переименована в `shablon_analiz_telefonnyh_peregovorov` во всех migration/verify/rollback и документации; DB-07 roles используют `shablon_analiz_telefonnyh_peregovorov_*`; DB-05 audit использует `scope_ref='shablon_analiz_telefonnyh_peregovorov'`; к Supabase ещё не применено |
| [x] DB-08B | Павел + ChatGPT | Применение migrations в рабочем Supabase | DB-01—DB-07 migrations фактически применены и verify PASS; DB-07 negative privilege matrix PASS; recovery безопасно подтверждён транзакционными откатами без частичных/probe объектов; destructive rollback не запускался; внешние Credentials не подключены |

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

## Финальный этап — тиражируемый SQL-шаблон новой компании

Этот этап выполняется **после полной настройки и фактической проверки Supabase и n8n**, когда структура рабочего контура стабилизирована.

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [ ] TPL-01 | ChatGPT + VSCode | Параметризованный SQL-шаблон развёртывания новой компании | Из одного проверенного эталона генерируется чистая company-schema по параметрам компании/schema/role-prefix; есть preflight, полный DDL, FK/functions/views/RLS/roles/grants, verify и безопасный отказ при конфликте; шаблон не содержит данных, секретов и исторических отладочных SQL; тестовое развёртывание в новой пустой schema даёт PASS |

Правило: операционная история `SQL/DB-08B/` не используется как установщик новой компании. Источником шаблона служит только финальная проверенная каноническая структура после завершения Supabase+n8n.

## Gate production

| Статус / ID | Исполнитель | Результат | Критерий готовности |
|---|---|---|---|
| [ ] PROD-GATE | Павел | Отдельное решение о production | Павел явно разрешает конкретный release после test evidence, rollback/reconciliation и RELEASE_CHECKLIST; без этого production запрещён |

## Текущая следующая задача

**CORE-01 — общие contract/version/idempotency validators.**

Исполнитель: **VSCode**.

Цель: реализовать общий слой проверки контрактов, версий, scope, operation result/state и idempotency до сборки n8n workflows.

Обязательное чтение перед изменениями:

- `README.md`;
- `docs/CHATGPT_INSTRUCTIONS.md`;
- `docs/PROJECT_STATE.md`;
- `docs/specs/INTEGRATION_CONTRACTS.md`;
- `docs/specs/RELIABILITY_AND_IDEMPOTENCY.md`;
- `docs/specs/VERSIONING.md`;
- `docs/DATA_DICTIONARY.md`.

Границы CORE-01:

- код и автотесты в репозитории;
- Supabase schema/SQL не изменять;
- n8n workflow не создавать и не импортировать;
- Credentials не создавать и не подключать;
- сервер и deployment не изменять;
- production не затрагивать.

Критерий готовности:

- автотесты покрывают `accepted / duplicate / rejected`;
- проверены operation states;
- проверены scope boundaries;
- unknown/unsupported contract/version отклоняется предсказуемо;
- idempotency validator не смешивает duplicate event с новым событием того же звонка;
- тесты и код проходят проверки проекта;
- VSCode делает commit/push и возвращает SHA;
- ChatGPT после отчёта самостоятельно сверяет изменения в GitHub.
