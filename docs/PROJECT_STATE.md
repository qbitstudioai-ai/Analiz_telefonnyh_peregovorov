# Текущее состояние проекта

Обновлено: 2026-09-25. Рабочий Supabase разрешён только для изолированного контура schema `shablon_analiz_telefonnyh_peregovorov`.

## Режим

**Разрешена реализация по одной задаче в рабочем Supabase только внутри schema `shablon_analiz_telefonnyh_peregovorov`.**

Решение Павла от 25 сентября 2026 года заменяет прежнее ограничение «только test/локально» для этого контура.

Разрешено:

- создать и развивать schema `shablon_analiz_telefonnyh_peregovorov`;
- создать внутри неё реальные таблицы, связи, views, functions, RLS и capability roles по согласованным migrations;
- подключать к `shablon_analiz_telefonnyh_peregovorov` рабочие сервисные Credentials по мере соответствующих задач;
- выполнять verify, если проверка не оставляет фиктивные данные и не затрагивает посторонние схемы.

Не входит в разрешение автоматически:

- изменение или удаление существующих посторонних схем/таблиц/данных;
- destructive rollback в рабочем Supabase без отдельной проверки и разрешения;
- переключение реального клиентского трафика;
- публикация секретов в GitHub.

## Последний завершённый подэтап

**DB-08B / DB-04 — анализ и доказательства фактически применены и проверены PASS.**

Фактически подтверждено Павлом в рабочем Supabase:

- DB-01 migration + verify — PASS;
- DB-02 migration + verify — PASS;
- DB-03 migration + verify — PASS;
- DB-04 попытки `012` и `016` завершились FAIL 42830; после каждой ошибки read-only проверки `015` и `018` подтвердили 0 частичных объектов;
- исправленная migration `019_povtornoe_sozdanie_analiza_i_dokazatelstv_db04.sql` — `Success. No rows returned`;
- verify `020_proverka_analiza_i_dokazatelstv_db04.sql` — `Success. No rows returned`;
- verify DB-04 завершился без необработанной ошибки и выполнил финальный `ROLLBACK`.

DB-04: **применена + verify PASS**.

## Следующая одна задача

**DB-08B — фактически применить migrations DB-01—DB-07 в рабочем Supabase schema `shablon_analiz_telefonnyh_peregovorov` и выполнить verify.**

Исполнители: **Павел + ChatGPT**.

Павел уже выполнил первую read-only часть preflight: соединение показывает database `postgres`, user `postgres`, current schema `public`, PostgreSQL 17.6. Это подтверждает только параметры текущего соединения, но ещё не подтверждает отсутствие целевой schema.

Read-only preflight завершён PASS: запросы на `shablon_analiz_telefonnyh_peregovorov`, старые `shablon`/`atp_test`, объекты, функции и capability roles вернули 0 строк. Конфликтов перед DB-01 не обнаружено.

Критерий готовности:

- migrations 001→007 фактически выполнены в schema `shablon_analiz_telefonnyh_peregovorov`;
- verify 001→007 фактически PASS;
- schema/constraints/FK/views/functions/roles/RLS/grants сверены;
- отрицательные privilege checks подтверждены;
- рабочие Credentials для текущего DB-контура подключаются только после PASS DB-07;
- rollback/recovery проверяется без destructive воздействия на единственный рабочий экземпляр;
- существующие посторонние схемы/данные не затронуты.

## Текущий следующий SQL

Операционные SQL теперь фиксируются в отдельной папке `SQL/`.

Для DB-08B используется последовательная нумерация с понятными названиями:

- `001_proverka_kontura.sql` — PASS;
- `002_sozdanie_bazovoi_shemy_db01.sql` — Success;
- `003_proverka_bazovoi_shemy_db01.sql` — исторический FAIL проверочного SQL;
- `004_otkat_bazovoi_shemy_db01_NE_ZAPUSKAT.sql` — recovery, не запускать;
- `005_povtornaya_proverka_bazovoi_shemy_db01.sql` — PASS;
- `006_sozdanie_sloya_transkripcii_i_privacy_db02.sql` — Success;
- `007_proverka_sloya_transkripcii_i_privacy_db02.sql` — PASS;
- `008_otkat_sloya_transkripcii_i_privacy_db02_NE_ZAPUSKAT.sql` — recovery, не запускать;
- `009_sozdanie_konfiguracii_i_bazy_znanii_db03.sql` — Success;
- `010_proverka_konfiguracii_i_bazy_znanii_db03.sql` — PASS;
- `011_otkat_konfiguracii_i_bazy_znanii_db03_NE_ZAPUSKAT.sql` — recovery, не запускать;
- `012_sozdanie_analiza_i_dokazatelstv_db04.sql` — фактически запущен, **FAIL 42830**: отсутствовал unique target `(claim_id, analysis_id)` для FK `evidence_sets`;
- `013_proverka_analiza_i_dokazatelstv_db04.sql` — не запускался;
- `014_otkat_analiza_i_dokazatelstv_db04_NE_ZAPUSKAT.sql` — recovery, **не запускать**;
- `015_proverka_sostoyaniya_posle_oshibki_db04.sql` — фактически выполнен, **PASS / 0 rows**; частичных DB-04 объектов не найдено;
- `016_povtornoe_sozdanie_analiza_i_dokazatelstv_db04.sql` — фактически запущен, **FAIL 42830**: unique `(analysis_id, privacy_package_id)` создавался позже зависимых FK;
- `017_proverka_analiza_i_dokazatelstv_db04.sql` — не запускался;
- `018_proverka_sostoyaniya_posle_vtoroi_oshibki_db04.sql` — фактически выполнен, **PASS / 0 rows**; частичных DB-04 объектов после второй ошибки не найдено;
- `019_povtornoe_sozdanie_analiza_i_dokazatelstv_db04.sql` — Success;
- `020_proverka_analiza_i_dokazatelstv_db04.sql` — PASS;
- `021_sozdanie_crm_otpravok_ispravlenii_i_audita_db05.sql` — **следующий разрешённый SQL**;
- `022_proverka_crm_otpravok_ispravlenii_i_audita_db05.sql` — запускать только после успешного шага 021;
- `023_otkat_crm_otpravok_ispravlenii_i_audita_db05_NE_ZAPUSKAT.sql` — recovery, не запускать без отдельного решения.

## Фактический статус применения

- DB-08B preflight — PASS;
- DB-01 migration — **применена**;
- DB-01 verify — **PASS**;
- DB-02 migration — **применена**;
- DB-02 verify — **PASS**;
- DB-03 migration — **применена**;
- DB-03 verify — **PASS**;
- DB-04 migration — **применена**;
- DB-04 verify — **PASS**;
- DB-05—DB-07 migrations — ещё не применялись;
- реальные Credentials, n8n workflow, серверные сервисы и dashboard к schema `shablon_analiz_telefonnyh_peregovorov` ещё не подключены и не проверены.

Следующий шаг: DB-05 migration `021_sozdanie_crm_otpravok_ispravlenii_i_audita_db05.sql`.
