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
| [x] DB-04 | ChatGPT | Migration analysis/evidence | Созданы migration/verify/guarded rollback для 11 tables; exact input manifest, typed claims/evidence, exact safe segment/knowledge refs, absence coverage и current evidence gate статически проверены; direct final-state INSERT bypass закрыт; к Supabase не применено |
| [x] DB-05 | ChatGPT | Migration CRM/outgoing/corrections/audit | Созданы migration/verify/guarded rollback для 7 tables; CRM/human facts отделены от AI outcome, callback использует trusted refs, outgoing action предшествует send, delivered/unknown retry gates, corrections/disputes и append-only audit статически проверены; к Supabase не применено |
| [x] DB-06 | ChatGPT | Dashboard views/metric SQL | Созданы migration/verify/guarded rollback для 12 views + 7 metric/filter functions; logical-call decomposition, current/reliable/no-dispute averages, N/A criteria, stages, AI/CRM split, callback window, speech provenance и drill-down IDs статически проверены; к Supabase не применено |
| [x] DB-07 | ChatGPT | Изоляция и права шаблонного контура | Канонический migration/verify/guarded rollback: 9 NOLOGIN capability roles, 18 security-barrier runtime/safe views, 5 defense-in-depth RLS policies на raw/mapping, 2 audited SECURITY DEFINER proposal functions, PUBLIC/default privilege hardening и positive/negative matrix; физический контур обновлён DB-08A до `shablon_analiz_telefonnyh_peregovorov`; к Supabase ещё не применено |
| [x] DB-08A | ChatGPT | Адаптация DB-01—DB-07 к рабочей schema `shablon` | Migration/verify/rollback были переведены с `atp_test` на рабочий контур `shablon`; SQL к Supabase не применялся |
| [x] DB-08A.1 | ChatGPT | Окончательное имя рабочего контура | До применения SQL schema переименована в `shablon_analiz_telefonnyh_peregovorov` во всех migration/verify/rollback и документации; DB-07 roles используют `shablon_analiz_telefonnyh_peregovorov_*`; DB-05 audit использует `scope_ref='shablon_analiz_telefonnyh_peregovorov'`; к Supabase ещё не применено |
| [~] DB-08B | Павел + ChatGPT | Применение migrations в рабочем Supabase | DB-01—DB-03 migration + verify PASS; исправленная DB-04 migration `019` фактически применена с `Success`; следующий шаг — `020_proverka_analiza_i_dokazatelstv_db04.sql` |

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

**DB-08B — применение DB-01—DB-07 в рабочем Supabase schema `shablon_analiz_telefonnyh_peregovorov`.**

Исполнители: **Павел + ChatGPT**.

Цель: впервые фактически применить подготовленную цепочку SQL в согласованном рабочем Supabase, не затрагивая посторонние схемы/данные, затем выполнить verify и подтвердить физические связи и access boundaries.

Порядок DB-08B:

1. до запуска подтвердить, что открыт нужный рабочий Supabase-проект;
2. безопасный preflight выполнен PASS: целевой/старые schemas, объекты, функции и capability roles не найдены;
3. рабочие SQL для фактического запуска хранить в `SQL/DB-08B/`; применить migrations 001 → 007 строго по порядку;
4. после каждой migration зафиксировать фактический результат;
5. выполнить verify 001 → 007;
6. отдельно проверить DB-07 role/privilege/RLS matrix;
7. реальные LOGIN/Credentials создавать или привязывать только после PASS DB-07;
8. rollback/recovery не выполнять destructively на единственном рабочем экземпляре; использовать транзакционный/quarantine сценарий;
9. посторонние schemas/data и реальный клиентский трафик не трогать.

Критерий готовности:

- SQL фактически выполнен именно в согласованном рабочем Supabase;
- schema `shablon_analiz_telefonnyh_peregovorov` создана и содержит ожидаемые tables/FK/views/functions/roles/policies;
- migrations 001—007 завершились без необъяснённых ошибок;
- verify 001—007 дали PASS;
- DB-07 negative privilege checks подтвердили запреты;
- межтабличные связи являются реальными FK/constraints, а не заглушками;
- секретов нет в GitHub;
- recovery-подход фактически проверен безопасным способом без разрушения рабочего контура;
- явно зафиксировано, какие внешние сервисные Credentials уже подключены, а какие ещё нет.

Профильные документы DB-08B: [RELEASE_CHECKLIST](RELEASE_CHECKLIST.md), [ACCESS_AND_ISOLATION](specs/ACCESS_AND_ISOLATION.md), [PROJECT_STATE](PROJECT_STATE.md), [implementation/DB-01](implementation/DB-01.md), [implementation/DB-02](implementation/DB-02.md), [implementation/DB-03](implementation/DB-03.md), [implementation/DB-04](implementation/DB-04.md), [implementation/DB-05](implementation/DB-05.md), [implementation/DB-06](implementation/DB-06.md), [implementation/DB-07](implementation/DB-07.md).
