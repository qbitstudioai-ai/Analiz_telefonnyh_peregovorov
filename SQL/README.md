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

Текущая последовательность:

- `001_proverka_kontura.sql` — PASS;
- `002_sozdanie_bazovoi_shemy_db01.sql` — Success;
- `003_proverka_bazovoi_shemy_db01.sql` — исторический FAIL verify;
- `004_otkat_bazovoi_shemy_db01_NE_ZAPUSKAT.sql` — recovery, не запускать;
- `005_povtornaya_proverka_bazovoi_shemy_db01.sql` — PASS;
- `006_sozdanie_sloya_transkripcii_i_privacy_db02.sql` — Success;
- `007_proverka_sloya_transkripcii_i_privacy_db02.sql` — PASS;
- `008_otkat_sloya_transkripcii_i_privacy_db02_NE_ZAPUSKAT.sql` — recovery, не запускать;
- `009_sozdanie_konfiguracii_i_bazy_znanii_db03.sql` — следующий SQL;
- `010_proverka_konfiguracii_i_bazy_znanii_db03.sql` — verify DB-03 после успешного шага 009;
- `011_otkat_konfiguracii_i_bazy_znanii_db03_NE_ZAPUSKAT.sql` — recovery, самостоятельно не запускать.

После DB-03 нумерация продолжится с `012_...`.
