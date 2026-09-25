# Административная панель и границы пользовательского управления

Статус: DOC-16 завершён. Документ определяет логические роли, возможности административного интерфейса, аудит изменений и запреты.

Это не готовый UI, не Supabase Auth/RLS, не SQL grants и не разрешение изменять production сейчас.

## Цель

Админ-панель должна позволять управлять внедрением компании без редактирования workflow/БД вручную, но не становиться универсальным обходом:

- изоляции компаний и test/production;
- версионирования;
- evidence-gate;
- privacy;
- источников истины;
- правил production-действий.

Каждое изменение должно быть понятно по четырём вопросам: кто сделал, что изменил, в каком контуре и какое это имеет влияние на будущие/существующие результаты.

## Роли человека и технические роли — разные вещи

Роль пользователя интерфейса не равна PostgreSQL role или service Credential.

Браузер всегда работает через серверную часть дашборда/админ-панели.

Пользователь не получает:

- пароль PostgreSQL;
- service_role;
- runtime Credentials n8n;
- секреты CRM/телефонии/каналов;
- право произвольно выбирать schema;
- административный DB connection.

Сервер сам выполняет только заранее разрешённые операции своего контура.

## Логические пользовательские роли

Конкретные названия аккаунтов и технология авторизации определяются при реализации. По смыслу нужны как минимум следующие роли/способности.

### Руководитель компании

Базовый смысл — аналитический пользователь.

Может:

- смотреть разрешённый dashboard своей компании/среды;
- использовать фильтры и drill-down;
- видеть разрешённые analysis/evidence;
- выгружать разрешённые отчёты;
- создавать dispute/запрос на исправление, если эта функция включена.

По умолчанию не может:

- менять промт/методику;
- публиковать знания;
- переключать production config;
- менять Credentials;
- править БД напрямую;
- менять подтверждённые source facts бесследно.

Дополнительные административные способности могут быть выданы отдельно, но не следуют автоматически из роли руководителя.

### Администратор внедрения / Павел

Логическая роль для управления настройками конкретного разрешённого контура.

Может в пределах выданных capabilities:

- видеть состояние конфигурации и версии;
- редактировать draft-настройки;
- управлять связями источников/каналов без просмотра секретов;
- готовить prompt/methodology/filter versions;
- управлять knowledge drafts и инициировать публикацию по правилам DOC-17;
- выполнять разрешённые ручные corrections;
- инициировать test-проверки и ограниченный reanalysis;
- видеть audit trail и техническое состояние без раскрытия лишних персональных данных.

Эта роль не означает глобальный DB-admin.

### Редактор знаний

Может готовить документы/версии/черновики знаний своего контура.

Не получает автоматически право публикации или доступ к звонкам.

### Публикатор знаний

Может выполнить отдельное действие публикации разрешённой версии знаний своего контура по DOC-17.

Право чтения знаний продуктом и право публикации — разные способности.

### Корректор данных

Может выполнять только разрешённые типы ручного исправления с причиной и аудитом.

Это не право произвольно переписывать любой факт.

### Технический оператор

Может видеть health/status, запускать разрешённые test-проверки, безопасные retry/reconciliation операции и диагностические действия.

Не получает автоматически содержание разговоров или право менять бизнес-методику.

### Привилегированное инфраструктурное администрирование

Миграции, backup/restore, создание schema, DB-admin и аварийные операции не являются функциями обычной админ-панели.

Для них используются отдельные privileged identities и процедуры DOC-18.

## Capability вместо одной роли super-admin

Одна надпись «admin» недостаточна.

Система должна различать способности по смыслу, например:

- view_analytics;
- view_allowed_transcript;
- view_raw_transcript;
- edit_company_settings_draft;
- edit_prompt_draft;
- edit_methodology_draft;
- edit_filter_draft;
- edit_knowledge_draft;
- publish_knowledge;
- activate_config_test;
- activate_config_production;
- correct_roles;
- correct_transcript;
- confirm_business_fact_human;
- dispute_analysis;
- request_reanalysis;
- operate_integrations;
- view_technical_health;
- export_allowed_data;
- view_audit.

Это логические capability names, а не готовые permission codes.

## Выбор компании и среды

Компания и среда определяются серверной авторизацией/capability пользователя по [ACCESS_AND_ISOLATION](ACCESS_AND_ISOLATION.md).

Обязательные правила:

- URL/query/body не расширяют список доступных контуров;
- переключение компании возможно только между контурами, на которые у пользователя уже есть серверное право;
- test и production отображаются как разные контуры;
- действие всегда явно показывает target company + environment;
- изменение, начатое в test, не может записаться в production;
- production Credential не используется для test-action;
- экран не должен скрывать текущую среду в момент изменения.

## Классы административных действий

### A. Только чтение

Примеры:

- dashboard;
- версии и их статусы;
- audit trail;
- health интеграций;
- список активных конфигураций;
- evidence в разрешённых границах.

Чтение не создаёт новую business version.

### B. Изменение черновика

Примеры:

- draft prompt;
- draft methodology;
- draft filter;
- draft knowledge document;
- draft настройки компании.

До активации draft не влияет на runtime.

После первого использования/активации version immutable по [VERSIONING](VERSIONING.md).

### C. Активация/публикация версии

Это отдельное действие от сохранения draft.

Перед активацией сервер должен показать по смыслу:

- контур;
- тип версии;
- текущую active/current version;
- новую version;
- кто инициирует;
- ожидаемую область влияния;
- обязательные validation results.

Новая версия не переписывает старые analyses автоматически.

### D. Ручное исправление факта

Исправление создаёт audit/correction event.

Если изменяется versioned upstream input, применяются правила [VERSIONING](VERSIONING.md): новая version и, при влиянии, новая downstream chain.

### E. Операционное действие

Примеры:

- retry разрешённой failed_retryable operation;
- reconciliation outcome_unknown;
- проверка подключения;
- запуск test sample;
- запрос reanalysis.

Операционное действие не даёт права менять факт вручную, чтобы «убрать ошибку».

### F. Высокорисковое / production действие

Примеры:

- production activation;
- массовый reanalysis;
- массовая отправка;
- изменение production integration binding;
- удаление данных;
- retention cleanup вне обычной утверждённой политики;
- migration/restore.

Такие операции не должны выполняться скрытым side effect обычного Save.

Для production применяется отдельное явное действие с предварительной проверкой scope/impact и аудитом. В рамках текущего проекта фактическое production-изменение по-прежнему требует отдельного разрешения Павла.

## Какие настройки можно готовить через админ-панель

Логически допускаются:

- параметры компании;
- timezone и локальные отображаемые настройки;
- связи источников/адаптеров;
- правила фильтрации;
- справочник/привязки менеджеров через контролируемые операции;
- prompt versions;
- methodology/criteria/weights versions;
- разрешённые типы результатов;
- knowledge documents/drafts/publications;
- настройки выходных каналов без показа секретов;
- разрешённая model/config selection;
- quality thresholds/правила, если они утверждены;
- retention policy parameters после бизнес/юридического утверждения;
- dashboard display/admin settings, которые не меняют источники истины.

Не все эти параметры обязаны войти в первую версию UI. DOC-16 фиксирует границы, а не состав экранов MVP.

## Промт

Администратор с нужной capability может:

- создать draft;
- сравнить с active version;
- отправить на test;
- после разрешённой проверки активировать новую version для будущих analyses.

Нельзя:

- редактировать использованную version in place;
- автоматически пересчитать историю при Save;
- менять prompt у уже начатой operation;
- скрыть, какая version использована старым analysis.

## Методика, критерии и веса

Изменение criterion, applicability, weight, scale или stage rule создаёт новую methodology version.

Перед активацией должны быть видны как минимум изменённые элементы и влияние на будущую оценку по смыслу.

Старая статистика не пересчитывается молча.

Если нужен historical reanalysis — это отдельная операция с заданным scope.

## Правила фильтрации

Новая filter version влияет на новые решения после активации.

Старые filter decisions продолжают хранить старую version.

Нельзя изменить прошлую причину исключения только редактированием текущего фильтра.

## Знания

Админ-панель должна разделять:

- draft/edit;
- validation;
- publication;
- archive/depublication;
- runtime read.

Редактирование draft не меняет уже опубликованный набор.

Публикация создаёт новую publication version по [VERSIONING](VERSIONING.md).

Обычный analysis reader не получает право publish.

Точный lifecycle публикации, общая база знаний нескольких продуктов и approvals завершаются DOC-17.

## Менеджеры и привязки

Доверенные manager/CRM/extension связи могут обновляться через контролируемую административную операцию.

Обязателен audit:

- старое значение/версия;
- новое;
- источник/основание;
- автор;
- время.

Если исправление меняет role assignment конкретного звонка, применяются новая role version и возможный reanalysis.

Нельзя через display-name заставить старый звонок принадлежать другому manager без отдельной correction operation.

## Ручное исправление транскрипции

Допускается только capability, явно разрешающая correction.

Исправление:

- не редактирует старую transcript version in place;
- создаёт новую version;
- сохраняет автора/причину;
- повторно проходит roles/privacy;
- при влиянии создаёт новый analysis candidate;
- не переотправляет feedback автоматически.

## Ручное исправление роли

Исправление technical speaker → business role:

- сохраняет старое назначение;
- создаёт новую role-assignment version;
- требует основания;
- может invalidate прежний current analysis;
- запускает новую downstream chain только по разрешённому процессу.

## Оспаривание анализа

Руководителю может быть доступно действие «оспорить/запросить проверку», не равное прямому изменению балла.

Dispute хранит:

- analysis version;
- target/evidence;
- автора;
- причину;
- время;
- статус рассмотрения.

Разрешённый корректор может затем создать correction/new analysis version.

Нельзя редактировать AI score in place так, будто исходного результата не было.

## Подтверждение бизнес-факта человеком

Если внедрение разрешает human confirmation CRM-like факта, capability должна быть отдельной.

Ручной факт хранится с source=human/ролью автора и не маскируется как CRM confirmation.

Нельзя через обычный edit превратить AI assumption в «подтверждено CRM».

## Delivery и исходящие действия

Админ-панель может показывать outgoing action, attempts и outcome.

Разрешённый оператор может:

- инициировать reconciliation;
- выполнить retry только когда состояние допускает безопасный repeat;
- создать отдельное новое outgoing action при явном основании.

Нельзя:

- вручную отметить outcome_unknown как delivered без доверенного подтверждения;
- повторить confirmed delivery;
- скрыть старую attempt;
- автоматически отправить feedback после reanalysis только из-за смены current.

## Credentials и интеграции

Админ-панель не показывает существующее значение секрета обратно пользователю.

Допустимы по смыслу:

- connection label;
- provider/account ref;
- health/status;
- время последней успешной проверки;
- инициирование замены/ротации через защищённый secret flow;
- test connection.

Secret не хранится как обычная business field и не попадает в audit diff в открытом виде.

Изменение integration binding в production является отдельным production action.

## Исходная транскрипция и privacy

Capability view_raw_transcript отделена от обычного view_analytics.

По умолчанию evidence/dashboard использует разрешённый pseudonymized text.

Даже администратор не получает mapping псевдонимов только потому, что у него есть admin UI.

Доступ к raw transcript:

- ограничен своим контуром;
- журналируется;
- не выдаёт mapping/секреты;
- соблюдает retention policy.

Нужность raw-view для конкретной компании является параметром внедрения, а не автоматически включённой функцией.

## Test и production

Изменения готовятся и проверяются отдельно.

Минимальные правила:

- draft/test version не становится production-active автоматически;
- test data/credentials/channels не заменяются production значениями;
- production activation — отдельная операция;
- production action хранит actor, target, before/after version refs, reason и result;
- test send не может использовать production recipient/channel;
- test reanalysis не меняет production current analysis;
- production rollback, если он понадобится, означает явный возврат на ранее разрешённую version/конфигурацию, а не удаление истории.

Технический release/rollback процесс завершит DOC-18.

## Предпросмотр влияния

Для versioned/high-impact changes админ-панель должна по смыслу показывать до применения:

- company + environment;
- текущую version;
- candidate version;
- changed fields/objects;
- affects future only или требует отдельного reanalysis;
- число объектов scope при bulk action, когда его можно определить;
- validation status;
- связанные риски/blocked conditions.

Preview не является гарантией production успеха, но предотвращает скрытую смену области действия.

## Audit trail

Для каждого изменяющего действия обязательны:

- actor ID и его logical capability;
- company + environment;
- action type;
- target type/ref;
- before version/ref или state;
- after version/ref или requested change;
- reason/comment для correction/high-risk operations;
- request time;
- result time;
- operation ID, если создаётся backend operation;
- success/rejected/unknown result;
- machine error code при отказе;
- source channel UI/API, если это важно для расследования.

Audit immutable по смыслу для обычного пользователя.

Audit не содержит plaintext secrets и лишние raw conversation payload.

## Что руководитель видит, но не меняет по умолчанию

- metrics;
- calls;
- current analysis;
- criteria/stages/observations;
- AI result и CRM fact раздельно;
- evidence в разрешённой privacy-форме;
- delivery status;
- versions/provenance, необходимые для объяснения результата.

Руководитель не получает автоматическое право на system configuration только потому, что является владельцем бизнес-показателей.

## Что нельзя делать через обычный admin UI

- выполнять arbitrary SQL;
- выбирать произвольную schema;
- выдавать себе новую company membership;
- читать другую компанию;
- показывать service_role/postgres password;
- менять audit history;
- редактировать immutable used version;
- вручную делать fake evidence;
- создавать knowledge ref, которого не было в analysis manifest;
- помечать AI assumption как CRM-confirmed;
- помечать unknown delivery как delivered без доверенного источника;
- повторять внешний side effect вопреки idempotency state;
- без отдельного разрешения удалять production data;
- выполнять migration/restore;
- обходить privacy-gate;
- отправлять raw transcript внешней LLM;
- массово пересчитывать/переотправлять историю как side effect обычного Save.

## Bulk actions

Массовые действия требуют отдельного scope.

Минимально фиксируются:

- operation type;
- filter/scope snapshot;
- estimated/actual target count;
- versions/inputs;
- actor/reason;
- dry-run/validation result, если применимо;
- progress/result;
- per-item failures без утечки данных.

Bulk reanalysis создаёт новые operations/versions и не означает bulk feedback send.

## Удаление

Обычная кнопка Delete не должна физически стирать production history, analysis/evidence/audit.

Удаление по retention или законному основанию — отдельный контролируемый процесс с scope, reason, policy/version и подтверждением результата.

Фактическое удаление production данных сейчас и в будущем требует отдельного разрешения и правил DOC-18.

## Ошибки и отказ

Если действие не прошло authorization/validation/version/evidence/privacy gate:

- оно rejected;
- target не меняется;
- сохраняется безопасный audit result;
- UI показывает понятную причину без секрета;
- запрещённый action не заменяется fallback с более широкими правами.

## Минимальный lifecycle изменения

Для versioned configuration:

draft → validate/test → approved/allowed activation → active for new operations → historical/superseded.

Конкретный approval workflow зависит от типа настройки и DOC-17/DOC-18.

Для correction:

request/dispute → authorized correction → new version/event → dependent validation/reanalysis → optional current switch.

## Обязательные проверки DOC-16

Будущая реализация должна подтвердить как минимум:

1. Руководитель без admin capability не может изменить prompt.
2. Руководитель без raw-transcript capability не получает raw text через API/URL manipulation.
3. Admin A не может открыть/edit company B.
4. Test-admin action не меняет production.
5. URL company/schema parameter не расширяет server-side membership.
6. Браузер не получает service_role/postgres credential.
7. Existing integration secret нельзя прочитать обратно из UI.
8. Secret rotation audit не содержит plaintext secret.
9. Save prompt draft не меняет active prompt.
10. Activation prompt создаёт/выбирает новую immutable version.
11. Started analysis остаётся на frozen old prompt after new activation.
12. Methodology weight edit создаёт новую version и не переписывает historical score.
13. Filter edit не переписывает старое filter decision.
14. Knowledge draft edit не меняет published runtime set.
15. User with knowledge-read permission but without publish capability не публикует draft.
16. Production publication/activation является отдельным action от test.
17. Manager mapping correction оставляет old value + actor + reason.
18. Role correction создаёт new role version и не edits old analysis in place.
19. Transcript correction создаёт new transcript/downstream versions.
20. Dispute analysis не меняет score напрямую.
21. Human confirmation хранится как human source, а не fake CRM source.
22. Invalid/fake evidence нельзя добавить как confirmed evidence через UI.
23. outcome_unknown delivery нельзя вручную превратить в delivered без trusted confirmation.
24. confirmed delivery нельзя retry той же logical operation.
25. New current analysis не отправляет feedback автоматически.
26. Bulk reanalysis не создаёт bulk outgoing actions без отдельного explicit action.
27. Production high-impact action показывает target environment/scope before apply.
28. Rejected action оставляет target unchanged и audit record.
29. Audit содержит actor, contour, before/after refs, reason/result.
30. Ordinary admin не может изменить/delete audit history.
31. Admin UI не предлагает arbitrary SQL/migration/restore как обычную business operation.
32. Retention deletion отделено от ordinary edit/delete.
33. Raw transcript access, если разрешён, журналируется и ограничен своим contour.
34. Pseudonym mapping не выдаётся ordinary admin/dashboard role.
35. Production rollback возвращает разрешённую version явно и сохраняет историю.
36. Bulk action фиксирует exact scope и не расширяется из-за изменившегося UI filter после запуска.

## Что не определяется DOC-16

- конкретные экраны и дизайн;
- Supabase Auth/RLS implementation;
- названия database roles;
- SSO/provider;
- точная approval chain компании;
- кто именно у конкретного заказчика получает business approval capabilities;
- SQL audit schema;
- DOC-17 knowledge publication workflow details;
- DOC-18 production deployment/rollback details.

Эти решения не могут превращать обычный admin UI в unrestricted infrastructure access.

## Критерий DOC-16

Документ готов, если:

- руководитель, администратор, knowledge editor/publisher, corrector и technical operator различимы по смыслу;
- capabilities отделены от одной роли super-admin;
- company + environment нельзя переключить пользовательским параметром;
- draft, activation, correction, operation и production action различаются;
- versioned changes следуют VERSIONING;
- evidence corrections следуют EVIDENCE_MODEL;
- raw/private data имеют отдельные права;
- secrets не раскрываются;
- все изменяющие действия имеют audit trail;
- dangerous/destructive/infrastructure operations не являются обычным Save;
- test не может незаметно повлиять на production.

SQL, UI, Supabase roles, сервер и production в DOC-16 не изменялись.