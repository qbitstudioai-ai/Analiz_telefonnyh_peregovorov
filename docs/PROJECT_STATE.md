# Текущее состояние проекта

Обновлено: 2026-09-25. Техническое проектирование требований.

## Режим

**Разрешено техническое проектирование в документации по одному ID.**

SQL, JSON workflow, программный код, n8n, Supabase, сервер и production пока не изменяются. Демонстрационный дашборд использует вымышленные данные и не подключён к Supabase.

## Последняя завершённая задача

**DOC-13 — описано версионирование артефактов и анализа.**

Создан [VERSIONING](specs/VERSIONING.md).

Зафиксировано:

- подтверждённая использованная version immutable; исправление создаёт новую version или отдельное correction event;
- version_id является точной ссылкой, а current не определяется простым max(version_number);
- current, historical/superseded и invalidated имеют разный смысл;
- retry той же operation с теми же input_refs не является новой semantic version;
- перспективное изменение промта/методики/model/knowledge влияет на будущие операции и не переписывает историю автоматически;
- исправляющее изменение конкретной транскрипции/ролей/privacy может invalidate зависимый current и требует новой downstream-цепочки;
- входы analysis замораживаются при старте operation и не переключаются на новые настройки посреди выполнения;
- каждый analysis хранит immutable input manifest: transcript, roles, pseudonymized/privacy package, prompt, methodology, model/config, knowledge publication + exact fragments, history context, contract и влияющий CORE/quality version;
- новая analysis version становится current только после успешной проверки;
- failed candidate не снимает валидный current; invalidated current может временно оставить звонок без действующего анализа до reanalysis;
- новый current analysis не создаёт повторную отправку обратной связи автоматически;
- provider с плавающим model alias не выдаётся за полностью воспроизводимый build;
- определены 26 обязательных проверяемых сценариев будущей реализации.

SQL-механизм current pointer, locking, hashes, массовый reanalysis policy и admin UX ещё не выбраны.

## Следующая одна задача

**DOC-14 — описать доказательную базу выводов.**

Цель: создать docs/specs/EVIDENCE_MODEL.md и определить связь каждого проверяемого вывода/оценки с конкретным analysis version, цитатой/segment ref и таймкодом, правилом/критерием, knowledge fragment/document/version при использовании знаний и статусом проверки доказательства.

Критерий готовности: по любому значимому выводу можно понять, что именно было сказано, где в разговоре, какое правило применено, использовался ли факт компании и на какой версии материала основан вывод; LLM не может создать «доказательство» ссылкой на несуществующий вход.

## Что не применялось

SQL, workflow, код, миграции, настройки n8n/Supabase, сервер, реальные Credentials, реальные данные компаний и production не изменялись и не тестировались.
