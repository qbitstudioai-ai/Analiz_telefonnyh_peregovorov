# Текущее состояние проекта

Обновлено: 2026-09-25. Рабочий Supabase разрешён только для изолированного контура schema `shablon_analiz_telefonnyh_peregovorov`.

## Режим

**Разрешена реализация по одной задаче по `WORKPLAN_IMPLEMENTATION.md`.**

Физический контур Supabase `shablon_analiz_telefonnyh_peregovorov` уже создан и проверен в рамках DB-08B. Следующая разрешённая работа — кодовая задача `CORE-01` в репозитории.

Разрешено:

- продолжать реализацию задач плана в GitHub;
- для уже согласованного Supabase-контура выполнять только явно предусмотренные последующими задачами действия;
- создавать код и автотесты CORE без деплоя;
- подключать рабочие сервисные Credentials только в отдельной соответствующей задаче после явной проверки scope.

Не входит в разрешение автоматически:

- изменение или удаление существующих посторонних schemas/tables/data;
- destructive rollback в рабочем Supabase;
- подключение новых Credentials вне отдельной задачи;
- изменение сервера или deployment;
- переключение реального клиентского трафика;
- любые production-изменения;
- публикация секретов в GitHub.

## Последний завершённый подэтап

**DB-08B — физическая модель Supabase DB-01—DB-07 фактически применена и проверена PASS.**

Фактически подтверждено Павлом в рабочем Supabase:

- DB-01 migration + verify — PASS;
- DB-02 migration + verify — PASS;
- DB-03 migration + verify — PASS;
- DB-04 migration + verify — PASS после исправления двух DDL-дефектов;
- DB-05 migration + verify — PASS;
- DB-06 migration + verify — PASS;
- DB-07 migration `027` — `Success. No rows returned`;
- DB-07 verify `028` выявил неверное предположение о PostgreSQL 17 creator-admin memberships;
- read-only `030` подтвердил 9 безопасных automatic creator-admin memberships: `ADMIN=true / INHERIT=false / SET=false`, без probe-schema leftovers;
- DB-07 verify `031` выявил два alias-конфликта `v_role`;
- исправленный DB-07 verify `033` — `Success. No rows returned`;
- DB-07 negative privilege/RLS/grant matrix — PASS;
- destructive rollback не выполнялся;
- recovery-подход фактически подтверждён безопасно: транзакционные ошибки DB-04 не оставили частичных объектов, а ошибки verify DB-07 не оставили временных probe-schema;
- реальные LOGIN/service Credentials, n8n, серверные сервисы и dashboard к новому контуру пока не подключены.

DB-08B: **завершена**.

## Следующая одна задача

**CORE-01 — общие contract/version/idempotency validators.**

Исполнитель: **VSCode**.

Цель:

- реализовать общие валидаторы контрактов, версий, scope и idempotency;
- покрыть автотестами `accepted / duplicate / rejected`, operation states, scope и unknown contract;
- не менять Supabase schema;
- не создавать Credentials;
- не трогать n8n;
- не выполнять deploy.

До выдачи задания VSCode новая сессия должна сверить текущую структуру репозитория и профильные требования: `docs/specs/INTEGRATION_CONTRACTS.md`, `docs/specs/RELIABILITY_AND_IDEMPOTENCY.md`, `docs/specs/VERSIONING.md`, `docs/DATA_DICTIONARY.md`.

Критерий готовности CORE-01: автотесты подтверждают согласованное поведение validators; изменения записаны в GitHub и проверены ChatGPT после отчёта VSCode.

## SQL / DB-08B

Операционная последовательность DB-08B завершена.

Последние шаги:

- `027_sozdanie_izolyacii_i_prav_dostupa_db07.sql` — Success;
- `028_proverka_izolyacii_i_prav_dostupa_db07.sql` — исторический FAIL P0001;
- `029_otkat_izolyacii_i_prav_dostupa_db07_NE_ZAPUSKAT.sql` — не запускался;
- `030_diagnostika_chlenstva_rolei_db07.sql` — PASS, read-only диагностика;
- `031_povtornaya_proverka_izolyacii_i_prav_dostupa_db07.sql` — исторический FAIL 42702;
- `032_otkat_izolyacii_i_prav_dostupa_db07_NE_ZAPUSKAT.sql` — не запускался;
- `033_povtornaya_proverka_izolyacii_i_prav_dostupa_db07.sql` — **PASS**.

**Следующего SQL для запуска сейчас нет.** Rollback-файлы самостоятельно не запускать.

## Фактический статус применения

- DB-08B preflight — PASS;
- DB-01—DB-07 migrations — **применены**;
- DB-01—DB-07 verify — **PASS**;
- DB-07 access/isolation negative checks — **PASS**;
- DB-07: 9 NOLOGIN capability roles, 18 security-barrier views, 5 RLS policies, 2 SECURITY DEFINER functions фактически созданы и проверены;
- destructive rollback — **не выполнялся**;
- recovery evidence — **PASS в безопасной транзакционной форме**;
- реальные LOGIN/service Credentials — **не подключены**;
- n8n workflows — **не импортированы и не проверены**;
- серверные сервисы — **не изменялись**;
- dashboard — **не подключён и не проверен**;
- production traffic — **не переключался**.

Следующая задача: **CORE-01**, код и автотесты в репозитории, исполнитель VSCode, deploy не входит.
