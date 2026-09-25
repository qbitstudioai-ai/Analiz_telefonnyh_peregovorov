# Проверка эксплуатации и безопасного выпуска

Статус: DOC-18. Документ определяет блокирующие проверки перед production, требования к мониторингу, backup/restore, тестированию, rollback/reconciliation и доказательствам выпуска.

Это **не подтверждение**, что проверки уже пройдены. SQL, n8n, Supabase, сервер и production в DOC-18 не изменяются.

## Главное правило

Система не считается готовой к production только потому, что:

- workflow импортирован;
- код запускается;
- один тестовый звонок обработан;
- интерфейс открывается;
- backup создаётся;
- мониторинг показывает «зелёный» статус.

Production-ready означает, что для конкретной компании и среды есть фактические подтверждения обязательных проверок, известны версии выпуска, подготовлен безопасный rollback/reconciliation и нет открытого блокирующего риска.

## Статусы checklist

Для каждого пункта будущей проверки используется один из статусов:

- **PASS** — проверка реально выполнена в указанной среде и есть доказательство результата;
- **FAIL** — проверка выполнена и не прошла;
- **BLOCKED** — проверить пока нельзя из-за зависимости/доступа/ошибки;
- **NOT RUN** — проверка ещё не запускалась;
- **N/A** — пункт действительно неприменим, указана причина.

N/A без объяснения не считается подтверждением.

Любой обязательный FAIL, BLOCKED или NOT RUN означает, что соответствующий release gate не пройден.

## Паспорт выпуска

Перед каждым production-выпуском должен быть зафиксирован как минимум:

- компания;
- environment;
- release ID;
- Git commit/template version;
- версия workflow/config;
- schema/data migration version, если есть;
- версии CORE/adapter/dashboard;
- фактически выбранные модели/config транскрибации, LLM и embeddings;
- active prompt/methodology/filter versions;
- active knowledge publication version;
- release window;
- кто выполняет выпуск;
- кто дал бизнес-разрешение;
- что входит в scope;
- что явно не входит;
- ссылка/идентификатор набора тестовых доказательств;
- backup/restore evidence;
- rollback/reconciliation plan;
- результат post-release проверки.

Формат хранения выбирается при реализации, но release нельзя восстанавливать только по памяти исполнителя.

## Отдельное разрешение production

Изменение production, переключение реального трафика, миграции production данных, destructive operation и restore требуют отдельного явного разрешения Павла на конкретное действие.

Разрешение на документацию, тест или подготовку файлов не является разрешением production.

**Конкретное разрешение от 25 сентября 2026 года:** Павел разрешил использовать рабочий Supabase для создания и настройки изолированной schema `shablon_analiz_telefonnyh_peregovorov` и её реальных внутренних связей. Это разрешение ограничено `shablon_analiz_telefonnyh_peregovorov` и не является разрешением менять/удалять посторонние production-объекты, выполнять destructive rollback на единственном рабочем экземпляре или переключать реальный клиентский трафик.

Перед production-действием Павел должен видеть простыми словами:

- что изменится;
- какая компания и среда затронуты;
- какой риск;
- что проверено;
- что не проверено;
- как прекратить изменение;
- как восстанавливаться, если результат плохой.

## Release gates

### Gate 0 — точный scope и версии

Обязательно:

- определена одна company + environment;
- известен исходный production state;
- зафиксирован release commit/version;
- список изменяемых компонентов конечен и проверяем;
- test и production не смешаны;
- migration/config/workflow versions согласованы;
- нет неучтённых ручных изменений сервера;
- release package не содержит секретов и частных данных.

### Gate 1 — документационные зависимости

Перед реализацией/production требования DOC-04—DOC-17 должны быть учтены в соответствующем тест-плане.

Нельзя закрыть gate фразой «требование есть в документации». Нужно сопоставить реализацию и фактическую проверку.

### Gate 2 — изоляция компаний и сред

Должны пройти отрицательные проверки [ACCESS_AND_ISOLATION](specs/ACCESS_AND_ISOLATION.md), включая:

- компания A не читает B;
- A не пишет/удаляет B;
- dashboard A не получает B;
- vector search A не возвращает B;
- test не читает/не меняет production;
- production не читает/не меняет test;
- обычные runtime roles не имеют административных credentials;
- подмена company/schema/tenant в payload/URL не переключает контур;
- pool/connection reuse не переносит чужой контекст.

Любая межкомпанейская утечка — безусловный blocker.

### Gate 3 — privacy и границы внешних AI

Должны быть фактически проверены требования [TRANSCRIPTION_AND_PRIVACY](specs/TRANSCRIPTION_AND_PRIVACY.md):

- внешний AI не получает аудио;
- исходная транскрипция не уходит вместо разрешённой версии;
- таблица соответствия псевдонимов не покидает защищённый контур;
- privacy-gate реально блокирует небезопасный пакет;
- ответ внешней модели также проходит проверку;
- raw/private content не появляется в обычных logs/execution data;
- внешнему embedding API отправляются только разрешённые fragments;
- provider/config соответствуют политике конкретного внедрения.

Privacy leak — безусловный blocker.

### Gate 4 — временное аудио и retention

Должны быть подтверждены требования [AUDIO_RETENTION](specs/AUDIO_RETENTION.md):

- известен максимальный срок временного аудио;
- аудио находится только в разрешённой временной области;
- временная область не попадает в обычный backup;
- после завершения звуковых этапов файл удаляется;
- cleanup обнаруживает orphan/expired files;
- ошибка удаления наблюдаема;
- свободное место контролируется;
- snapshot policy не делает скрытый долговременный архив;
- сроки транскрипций/псевдонимов/таблицы соответствия согласованы с backup retention.

Просроченное чувствительное содержимое без контролируемой политики — blocker.

### Gate 5 — идемпотентность и восстановление

Должны быть подтверждены сценарии [RELIABILITY_AND_IDEMPOTENCY](specs/RELIABILITY_AND_IDEMPOTENCY.md):

- duplicate event не создаёт второй звонок;
- retry не создаёт второй эквивалентный результат;
- restart продолжается с сохранённой точки;
- неизвестный внешний outcome не повторяется вслепую;
- подтверждённая доставка не отправляется второй раз;
- failed_retryable отличается от ошибки конфигурации;
- одновременно восстанавливающие процессы не создают двойной side effect;
- исчерпанный retry остаётся наблюдаемым.

Наличие неизвестного внешнего side effect без reconciliation-процедуры — blocker.

### Gate 6 — интеграционные контракты

Должны пройти проверки [INTEGRATION_CONTRACTS](specs/INTEGRATION_CONTRACTS.md):

- contract version распознаётся;
- company/environment/call/operation refs проверяются;
- accepted/duplicate/rejected различимы;
- transport success не выдаётся за business success;
- result refs сохраняются;
- потеря ответа после фактической записи/отправки не создаёт дубль;
- неизвестная contract version не исполняется по догадке;
- ошибки имеют безопасный машинный код без утечки содержимого.

### Gate 7 — качество транскрибации, ролей и производительность

До production должен быть фактически испытан выбранный стек по [TRANSCRIPTION_AND_PRIVACY](specs/TRANSCRIPTION_AND_PRIVACY.md):

- контрольный набор утверждён;
- WER/CER и критические смысловые ошибки измерены;
- DER/роли/таймкоды проверены;
- выбранные пороги качества зафиксированы как параметры внедрения;
- RTF/ресурсы измерены на целевом железе;
- одновременная обработка проверена при ожидаемой нагрузке;
- fallback/предварительный анализ ведёт себя по требованиям;
- выбранные модели/лицензии допустимы для внедрения.

Конкретные численные пороги шаблон не задаёт: они должны быть измерены и утверждены до production.

### Gate 8 — версии, знания и доказательства

Должны пройти проверки:

- [VERSIONING](specs/VERSIONING.md);
- [ANALYSIS_AND_KNOWLEDGE](specs/ANALYSIS_AND_KNOWLEDGE.md);
- [EVIDENCE_MODEL](specs/EVIDENCE_MODEL.md).

В частности:

- analysis хранит immutable input manifest;
- старые результаты не меняются из-за новой current configuration;
- publication version фиксируется до retrieval;
- exact knowledge fragments сохраняются;
- draft/чужие/архивные fragments не попадают в runtime;
- LLM не подтверждает fake segment/chunk refs;
- evidence-gate блокирует результат с нарушенными обязательными ссылками;
- новая publication/analysis version не переписывает историю;
- historical reanalysis является отдельной операцией.

### Gate 9 — dashboard и административные операции

Должны быть фактически подтверждены:

- один и тот же фильтр даёт одинаковую выборку в связанных представлениях;
- официальные метрики используют согласованные определения;
- preliminary analysis не смешан с официальным;
- CRM fact не подменяется AI assumption;
- пользователь не видит чужую компанию;
- browser не получает DB/service credentials;
- права администратора следуют [DASHBOARD_ADMIN](specs/DASHBOARD_ADMIN.md);
- draft Save не активирует production;
- correction оставляет историю;
- bulk action имеет frozen scope;
- reanalysis не переотправляет feedback автоматически;
- audit trail не редактируется обычным пользователем.

### Gate 10 — backup и restore

Наличие backup-файла само по себе не считается проверенной защитой.

Обязательно:

- определено, что именно входит в backup;
- определено, что сознательно исключено;
- backup относится к правильной company/environment или к явно описанному инфраструктурному scope;
- backup не ослабляет границы доступа;
- временное аудио исключено либо имеет отдельную согласованную snapshot policy;
- сроки хранения backup согласованы с retention исходных транскрипций и таблиц соответствия;
- backup нельзя бессрочно хранить только потому, что его редко восстанавливают;
- известны RPO и RTO конкретного внедрения;
- backup создаётся по проверяемому расписанию;
- ошибка backup видна мониторингу;
- выполнено **реальное тестовое восстановление** в изолированную среду;
- после restore проверены schema/config/version consistency;
- после restore проверена изоляция компаний;
- после restore выполняется retention/reconciliation, чтобы старый backup не воскресил уже истёкшие данные как действующие;
- восстановленная среда не отправляет внешние сообщения/CRM effects без отдельного разрешения;
- результат restore test сохранён как evidence.

RPO/RTO и периодичность restore test являются параметрами внедрения; шаблон не выдумывает числа.

Backup без успешного restore test не считается подтверждённым recovery.

## Что должно входить в backup по смыслу

Конкретная технология определяется позже, но должны быть восстановимы:

- подтверждённые бизнес-данные Supabase, которые ещё подлежат хранению;
- версии и связи, необходимые для воспроизводимости;
- operation/attempt state;
- analysis/evidence;
- knowledge publication metadata и разрешённые документы в пределах retention;
- конфигурация приложения/workflow как воспроизводимый артефакт без plaintext secrets;
- необходимые настройки среды в безопасной форме;
- audit/critical operational state, если он является обязательным источником расследования.

Секреты хранятся и резервируются только через предназначенный защищённый механизм, а не в GitHub, обычной БД или экспортированном workflow JSON.

## Что не должно незаметно попадать в backup

Без отдельной утверждённой политики:

- временное аудио;
- n8n binary execution data с аудио;
- лишние raw payload;
- отладочные dumps;
- plaintext secrets;
- данные после истечения согласованного срока;
- временные файлы моделей/обработки, не являющиеся источником истины.

## Backup и российский контур

Backup, содержащий исходные персональные данные, исходные транскрипции или таблицу соответствия, не должен выносить эти данные за разрешённую границу российского контура.

Место хранения backup, доступ и срок являются параметрами внедрения и должны быть проверены до production.

## Post-restore quarantine

Восстановленная копия сначала считается **изолированной и не допущенной к внешним side effects**.

До открытия трафика выполняются:

1. проверка версии схемы/приложения;
2. проверка company/environment;
3. проверка credentials/bindings;
4. retention cleanup;
5. сверка незавершённых operations;
6. reconciliation outcome_unknown;
7. проверка outgoing actions;
8. проверка knowledge current publication;
9. проверка dashboard isolation;
10. smoke tests;
11. только затем отдельное решение об открытии трафика.

Restore старого состояния не является разрешением повторно отправить сообщения или повторить CRM-действия.

## Мониторинг

Мониторинг должен отвечать не только на вопрос «сервер жив?».

Минимально наблюдаются:

### Инфраструктура

- CPU;
- RAM;
- GPU/VRAM, если используется;
- диск и скорость роста;
- свободное место временного аудио;
- состояние контейнеров/процессов;
- database availability/connections;
- reverse proxy/API availability;
- часы/время сервера и ошибки синхронизации, если влияют на порядок событий.

### Процесс обработки

- скорость входящих событий;
- backlog/queue;
- возраст самого старого незавершённого элемента;
- операции в in_progress_unconfirmed;
- failed_retryable;
- failed_final;
- outcome_unknown;
- количество retry;
- зависшие этапы;
- время от события до анализа;
- время от анализа до delivery.

### AI/локальные сервисы

- ошибки транскрибации;
- latency/RTF;
- загрузка GPU;
- ошибки диаризации/ролей;
- LLM error/timeout/rate limit;
- embedding/retrieval error;
- privacy-gate blocks;
- evidence-gate blocks;
- доля preliminary/technically incomplete результатов.

### Хранение и retention

- expired audio not deleted;
- orphan audio;
- cleanup failures;
- возраст oldest temporary audio;
- свободное место;
- transcription/pseudonym retention jobs;
- backup success/failure;
- возраст последнего успешного backup;
- возраст последнего успешного restore test;
- snapshot policy violations.

### Интеграции

- входные webhook/API failures;
- auth/credential errors;
- CRM sync failures;
- delivery failures;
- outcome_unknown delivery;
- reconciliation backlog;
- provider availability.

### Dashboard

- server API availability;
- query errors;
- медленные/неполные выборки;
- расхождение health данных и фактических processing states;
- ошибки authorization/isolation.

## Alerting

Для каждого production deployment до запуска определяются:

- какие сигналы являются warning;
- какие являются critical;
- пороги;
- окно времени;
- канал доставки алерта;
- кто отвечает;
- когда требуется ручное вмешательство;
- что считается восстановлением.

Шаблон не задаёт универсальные проценты CPU, минуты задержки или объём диска.

Critical alert должен быть проверен искусственным безопасным сценарием до production либо в test: недостаточно только настроить правило и никогда не проверить доставку.

Обязательные категории critical/blocking alerts по смыслу:

- недоступность основного состояния БД;
- невозможность безопасно записывать состояние;
- cross-company/isolation anomaly;
- privacy leak/block failure;
- истёкшее неудалённое аудио;
- критически низкое свободное место;
- backup failure дольше утверждённого окна;
- массовый stuck/backlog;
- массовый auth failure;
- повторяющиеся outcome_unknown side effects;
- monitoring itself unavailable.

## Логи

Обычные operational logs содержат:

- company/environment в безопасной технической форме;
- call_ref;
- operation_id;
- attempt_id;
- stage;
- contract/version refs;
- machine error class/code;
- timestamps;
- safe external request ref, если разрешено.

Обычные логи не содержат:

- полный raw transcript;
- таблицу соответствия;
- полный аудиофайл;
- plaintext passwords/tokens;
- произвольный полный LLM payload;
- документы клиента целиком.

Диагностическое расширение доступа к содержимому — отдельная контролируемая операция.

## Проверка мониторинга

До production требуется подтвердить как минимум:

- сервис down вызывает alert;
- искусственный safe failed_retryable виден;
- outcome_unknown виден отдельно;
- backup failure виден;
- cleanup failure виден;
- low disk warning/critical проверены безопасным способом;
- alert реально приходит назначенному получателю;
- после восстановления alert закрывается/меняет состояние;
- monitoring не раскрывает запрещённые данные.

## Ресурсы и нагрузка

До production измеряются на целевом или репрезентативном железе:

- CPU/RAM baseline;
- GPU/VRAM;
- disk usage/growth;
- размер временного аудио при ожидаемом concurrency;
- транскрибационный RTF;
- число одновременных обработок;
- database нагрузка;
- dashboard query latency;
- external API rate limits;
- backlog recovery после краткого сбоя.

Нужно проверить не только «один звонок работает», но и ожидаемую параллельную нагрузку плюс согласованный запас.

Конкретный размер запаса является параметром внедрения.

Если мощность недостаточна, release блокируется либо уменьшается разрешённая concurrency до проверенного значения.

## Test strategy

### Уровень 1 — локальные/unit проверки

Для чистых функций/валидаторов:

- contract validation;
- idempotency keys;
- privacy detector/gate;
- evidence refs;
- version selection;
- metrics;
- role rules;
- payload sanitization.

### Уровень 2 — component/integration test

Проверяются реальные границы между:

- source adapter и n8n;
- n8n и Supabase;
- n8n/CORE и транскрибацией;
- CORE и privacy;
- CORE и knowledge retrieval;
- CORE и LLM adapter;
- Supabase и dashboard server;
- outgoing adapter и каналом.

### Уровень 3 — end-to-end test

Минимальные сценарии:

- обычный клиентский звонок;
- исключённый звонок;
- пропущенный звонок;
- повторный звонок;
- duplicate webhook;
- low-quality/preliminary;
- privacy blocked;
- failed/retryable stage;
- outcome_unknown delivery;
- knowledge update with new publication;
- manual correction/reanalysis;
- dashboard drill-down;
- test/prod isolation.

### Уровень 4 — negative/security/isolation

Обязательны DOC-10/DOC-16/DOC-17 negative tests и попытки:

- подменить company;
- подменить object ID;
- прочитать raw data без capability;
- использовать admin endpoint обычной ролью;
- получить secret через UI/log/error;
- прочитать draft/other-company knowledge;
- передать raw data внешней модели.

### Уровень 5 — failure/recovery

Проверяются:

- restart n8n/CORE;
- database temporary unavailable;
- transcription timeout;
- LLM timeout;
- network loss after possible external side effect;
- disk pressure;
- cleanup failure;
- backup failure;
- restore;
- rollback/reconciliation.

## Тестовые данные

По возможности используются синтетические или специально разрешённые тестовые записи.

Реальные клиентские записи не копируются в test «для удобства».

Если для качества нужен реальный контрольный набор, его использование, доступ, хранение и обезличивание должны быть отдельно разрешены и соответствовать privacy/retention правилам.

## Secret management

До production:

- секреты отсутствуют в GitHub;
- секреты отсутствуют в workflow JSON;
- secret values не возвращаются через admin UI;
- test/prod используют разные credentials;
- компании используют разные runtime credentials;
- права минимальны;
- известен процесс rotation/revocation;
- ошибка/истечение credential наблюдаема;
- увольнение/смена ответственного не требует публикации секрета в документации;
- backup секретов, если он нужен, выполняется отдельным защищённым механизмом.

Найденный plaintext secret в репозитории/log/export — blocker до ротации и очистки допустимых копий.

## Pre-release freeze

Перед финальным test run фиксируются версии:

- code/commit;
- workflows;
- schema/migrations;
- adapters;
- models/config;
- prompt/methodology/filter;
- knowledge publication;
- dashboard build.

После freeze изменение одного из этих входов, влияющее на результат, требует повторить затронутые проверки.

Нельзя провести тест на одной версии, а выпустить другую и считать тест действующим.

## Rollback

Rollback должен быть подготовлен **до** production-выпуска.

Для каждого изменяемого компонента указывается:

- previous known-good version;
- условие остановки выпуска;
- способ вернуть предыдущую версию;
- нужен ли data restore;
- совместимы ли старая версия приложения и новая схема данных;
- что делать с operations, начатыми во время выпуска;
- что делать с external side effects;
- кто принимает решение;
- как проверить состояние после rollback.

## Rollback не равен undo внешнего мира

Нельзя автоматически «откатить»:

- уже доставленное сообщение;
- реально созданную CRM сущность;
- подтверждённую оплату;
- внешний AI вызов;
- webhook, уже принятый внешней стороной.

Для них применяется reconciliation/compensating action только если оно поддерживается и разрешено.

Повторный side effect нельзя выполнять только потому, что приложение откатили.

## Миграции и данные

До migration должны быть известны:

- направление изменения;
- совместимость версий;
- backfill, если нужен;
- оценка длительности/блокировок;
- backup;
- rollback или forward-fix strategy;
- проверка данных после применения.

Если migration необратима, это явно указывается. Нельзя писать «rollback есть», если фактически единственный путь — restore backup или forward fix.

Production migration требует отдельного разрешения Павла.

## Release procedure

Нормативная последовательность:

1. Зафиксировать scope и версии.
2. Проверить отсутствие более новых непроверенных изменений.
3. Пройти обязательные test gates в test.
4. Подтвердить backup и restore evidence.
5. Подтвердить monitoring/alerts.
6. Подготовить rollback/reconciliation.
7. Получить отдельное разрешение production.
8. Создать свежий pre-release backup по утверждённой процедуре, если это требуется для данного изменения.
9. Применить только разрешённый scope.
10. Выполнить безопасные post-release smoke tests.
11. Проверить monitoring/backlog/errors.
12. Зафиксировать фактический результат.
13. При blocker выполнить stop/rollback/reconciliation по плану.
14. Только после проверки объявить выпуск успешным.

## Production smoke test

Smoke test не должен сам создавать нежелательный реальный бизнес-эффект.

Используется:

- выделенный test account/source;
- безопасный технический объект;
- test recipient/channel;
- либо другой заранее согласованный способ.

Проверяются по необходимости:

- входное событие;
- сохранение состояния;
- доступ БД;
- локальный AI service health;
- knowledge retrieval;
- dashboard;
- outgoing adapter без отправки реальному клиенту/менеджеру;
- monitoring.

## Go / No-Go

Release получает **GO** только если:

- все обязательные gates PASS;
- все N/A имеют обоснование;
- нет неизвестного cross-company/privacy риска;
- restore реально проверен;
- rollback/reconciliation готов;
- monitoring и alert delivery работают;
- ресурсы имеют подтверждённый запас;
- production scope и версии зафиксированы;
- получено отдельное разрешение Павла.

## Безусловные No-Go blockers

Production запрещён при любом из условий:

1. cross-company data exposure;
2. test может писать/отправлять в production;
3. raw/private data уходит внешнему AI вопреки политике;
4. найден plaintext production secret в Git/log/export;
5. backup отсутствует там, где он обязателен;
6. restore не проверен;
7. rollback/recovery plan отсутствует;
8. confirmed external side effect может быть повторён retry;
9. outcome_unknown не имеет reconciliation path;
10. expired audio/critical private data не удаляются по политике;
11. monitoring не видит критические ошибки;
12. critical alert не доставляется;
13. disk/resources не выдерживают проверенную нагрузку;
14. migration/version mismatch не разрешён;
15. обязательные DOC-04—DOC-17 проверки FAIL/BLOCKED/NOT RUN;
16. production release отличается от протестированного frozen input без повторной проверки;
17. не получено отдельное разрешение Павла.

## Post-release наблюдение

После выпуска проверяются:

- error rate;
- backlog;
- stuck operations;
- outcome_unknown;
- duplicate prevention;
- privacy/evidence blocks;
- temporary audio cleanup;
- disk;
- backup;
- dashboard;
- delivery;
- external provider errors;
- cross-company anomalies.

Длительность усиленного наблюдения и конкретные пороги задаются внедрением.

Успешный smoke test не отменяет необходимость наблюдать реальные рабочие сигналы после открытия трафика.

## Evidence выпуска

Для каждого release должны сохраняться в допустимой форме:

- release ID;
- commit/versions;
- checklist со статусами;
- ссылки на test results;
- restore result;
- monitoring/alert verification;
- load/resource result;
- secret scan result;
- migration result, если применимо;
- production approval;
- время начала/окончания;
- post-release smoke result;
- rollback/reconciliation actions, если были;
- известные ограничения.

В публичный GitHub не помещаются реальные production secrets, персональные данные, записи разговоров и закрытые клиентские документы.

## Что шаблон не задаёт

DOC-18 сознательно не выдумывает:

- RPO/RTO числа;
- backup interval;
- retention сроки;
- CPU/RAM/GPU thresholds;
- alert thresholds;
- максимальную concurrency;
- maintenance window;
- конкретный monitoring stack;
- конкретный backup product;
- конкретную CI/CD систему;
- конкретный secret manager;
- универсальную approval chain.

Эти значения должны быть определены и проверены для конкретного внедрения.

## Критерий DOC-18

DOC-18 готов как спецификация, если:

- существует единый release checklist;
- любой blocker однозначно запрещает production;
- backup отличается от проверенного restore;
- retention учитывает backup/snapshot;
- monitoring покрывает инфраструктуру и бизнес-процесс;
- alerts должны быть реально доставлены;
- тест-план покрывает happy path, negative, failure/recovery и load;
- rollback отделён от reconciliation внешних side effects;
- секреты не попадают в код/логи/экспорты;
- выпуск привязан к точным версиям;
- production требует отдельного разрешения;
- документ не утверждает, что хотя бы одна production-проверка уже пройдена.

Фактическая production-ready проверка будет возможна только после реализации и выполнения checklist в конкретной среде.
