# SQL для фактического запуска

Эта папка хранит **операционные SQL-файлы, которые ChatGPT фактически передаёт Павлу для запуска**.

Правила:

- каноническая реализация продолжает храниться в `supabase/migrations`, `supabase/verify` и `supabase/rollback`;
- в `SQL/<TASK-ID>/` лежит проверенный рабочий пакет конкретной задачи;
- файлы называются по порядку фактического запуска: `NNN_ponyatnoe_nazvanie.sql`;
- номер всегда растёт последовательно без скрытых скачков; имя кратко объясняет действие человеку;
- migration/verify копируются из канонического комплекта и перед запуском должны совпадать с ним;
- rollback хранится рядом для recovery, но **не запускается без отдельного явного указания ChatGPT и разрешения Павла**;
- после каждого фактического запуска результат фиксируется в `docs/PROJECT_STATE.md`;
- секреты, токены, пароли, реальные записи разговоров и частные данные сюда не добавляются.

## Текущий пакет

`SQL/DB-08B/` — фактическое применение DB-01—DB-07 в рабочем Supabase, schema `shablon_analiz_telefonnyh_peregovorov`.

Актуальная последовательность:

- `001`—`011` — DB-01—DB-03 завершены; DB-01—DB-03 verify PASS;
- `012_sozdanie_analiza_i_dokazatelstv_db04.sql` — фактический FAIL 42830, исторический выполненный SQL;
- `013_proverka_analiza_i_dokazatelstv_db04.sql` — не запускался;
- `014_otkat_analiza_i_dokazatelstv_db04_NE_ZAPUSKAT.sql` — recovery, самостоятельно не запускать;
- `015_proverka_sostoyaniya_posle_oshibki_db04.sql` — PASS / 0 rows, частичных объектов нет;
- `016_povtornoe_sozdanie_analiza_i_dokazatelstv_db04.sql` — следующий SQL, исправленная DB-04 migration;
- `017_proverka_analiza_i_dokazatelstv_db04.sql` — актуальный verify после успешного 016.

Исправление DB-04: добавлен точный UNIQUE target `analysis_claims (claim_id, analysis_id)` для FK из `evidence_sets`.
