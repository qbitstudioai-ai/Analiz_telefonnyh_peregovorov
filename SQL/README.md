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
- `016_povtornoe_sozdanie_analiza_i_dokazatelstv_db04.sql` — фактический FAIL 42830 из-за позднего UNIQUE в `analysis_versions`;
- `017_proverka_analiza_i_dokazatelstv_db04.sql` — не запускался;
- `018_proverka_sostoyaniya_posle_vtoroi_oshibki_db04.sql` — PASS / 0 rows, частичных объектов нет;
- `019_povtornoe_sozdanie_analiza_i_dokazatelstv_db04.sql` — Success;
- `020_proverka_analiza_i_dokazatelstv_db04.sql` — PASS;
- `021_sozdanie_crm_otpravok_ispravlenii_i_audita_db05.sql` — Success;
- `022_proverka_crm_otpravok_ispravlenii_i_audita_db05.sql` — PASS;
- `023_otkat_crm_otpravok_ispravlenii_i_audita_db05_NE_ZAPUSKAT.sql` — recovery, самостоятельно не запускать;
- `024_sozdanie_predstavlenii_i_metrik_dashborda_db06.sql` — Success;
- `025_proverka_predstavlenii_i_metrik_dashborda_db06.sql` — PASS;
- `026_otkat_predstavlenii_i_metrik_dashborda_db06_NE_ZAPUSKAT.sql` — recovery, самостоятельно не запускать;
- `027_sozdanie_izolyacii_i_prav_dostupa_db07.sql` — Success;
- `028_proverka_izolyacii_i_prav_dostupa_db07.sql` — FAIL P0001: verify нашёл 9 capability-role memberships;
- `029_otkat_izolyacii_i_prav_dostupa_db07_NE_ZAPUSKAT.sql` — recovery, самостоятельно не запускать;
- `030_diagnostika_chlenstva_rolei_db07.sql` — следующий SQL, read-only диагностика фактических memberships.

DB-06 завершена: migration + verify PASS. DB-07 перед выдачей усиленно проверена по roles/views/RLS/SECURITY DEFINER/grants и negative privilege checks.
