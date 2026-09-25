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

## Последняя завершённая задача

**DB-08A.1 — рабочий контур переименован в schema `shablon_analiz_telefonnyh_peregovorov`.**

До фактического применения SQL Павел уточнил окончательное имя schema. В GitHub синхронно обновлены:

- migrations 001—007;
- verify 001—007;
- rollback 001—007;
- DB-07 capability roles → `shablon_analiz_telefonnyh_peregovorov_*`;
- DB-05 audit metadata → `scope_ref='shablon_analiz_telefonnyh_peregovorov'`, `environment_ref='working'`;
- профильная документация и планы.

Исторически DB-08A сначала адаптировал SQL к рабочей schema `shablon`; DB-08A.1 переименовал этот ещё не применённый контур в окончательное имя `shablon_analiz_telefonnyh_peregovorov`.

SQL по-прежнему **не применён** к Supabase.

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

- `001_proverka_kontura.sql` — фактически выполнен, PASS;
- `002_sozdanie_bazovoi_shemy_db01.sql` — фактически выполнен, **Success**;
- `003_proverka_bazovoi_shemy_db01.sql` — первый запуск выявил дефект verify; повторный запуск в Studio выполнил старый текст из открытой вкладки;
- `004_otkat_bazovoi_shemy_db01_NE_ZAPUSKAT.sql` — recovery-файл, не запускать без отдельного решения;
- `005_povtornaya_proverka_bazovoi_shemy_db01.sql` — **следующий разрешённый SQL**, открыть через `New Query` в Supabase Studio.

## Фактический статус применения

- DB-08B preflight — PASS;
- DB-01 migration — **применена**, Supabase вернул `Success. No rows returned`;
- DB-01 verify — **запускался и дал FAIL из-за дефекта самого verify SQL**: ожидался `foreign_key_violation`, но раньше сработал `uq_filter_decisions_operation`; migration/данные DB-01 этим результатом не признаны ошибочными;
- DB-02—DB-07 migrations — ещё не применялись;
- реальные Credentials, n8n workflow, серверные сервисы и dashboard к schema `shablon_analiz_telefonnyh_peregovorov` ещё не подключены и не проверены.

Исправление verify: добавлена отдельная неиспользованная filter operation для cross-call negative test, чтобы проверка доходила до составного FK, а не упиралась в уникальность `operation_id`. Второй полученный лог всё ещё содержит старый `v_filter_operation_id`, тогда как GitHub уже содержит `v_cross_call_filter_operation_id`; следовательно, в Studio был повторно выполнен старый текст из открытой вкладки. Для исключения путаницы создан новый шаг `005_povtornaya_proverka_bazovoi_shemy_db01.sql`. До его PASS нельзя утверждать, что DB-01 фактически проверена.
