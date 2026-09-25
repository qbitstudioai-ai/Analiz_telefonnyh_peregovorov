# Модель доказательств выводов анализа

Статус: DOC-14. Документ определяет, как оценки, наблюдения и предполагаемые результаты связываются с реальными входами конкретной версии анализа.

Это не SQL, не окончательная схема таблиц и не утверждение, что LLM сама является источником доказательства.

## Цель

Для любого значимого проверяемого вывода должно быть возможно установить:

- к какой analysis version относится вывод;
- какой факт разговора использован;
- где именно он находится: transcript version, segment ref и таймкод;
- какое правило, критерий или этап применён;
- использовались ли знания компании;
- какой exact knowledge fragment/document/publication version использован;
- проверены ли ссылки технически;
- достаточно ли обязательных частей доказательства по типу вывода;
- какие ограничения качества или retention влияют на возможность проверки.

LLM не может создать доказательство самим фактом того, что написала цитату, номер сегмента, документ или ссылку.

## Связанные документы

- [VERSIONING](VERSIONING.md) фиксирует immutable analysis input manifest.
- [DATA_DICTIONARY](../DATA_DICTIONARY.md) определяет сущности analysis, segments, knowledge fragments и dokazatelstva.
- [INTEGRATION_CONTRACTS](INTEGRATION_CONTRACTS.md) требует проверять ссылки ответа LLM до сохранения.
- [TRANSCRIPTION_AND_PRIVACY](TRANSCRIPTION_AND_PRIVACY.md) определяет версии текста, роли и privacy.
- [ANALYSIS_AND_KNOWLEDGE](ANALYSIS_AND_KNOWLEDGE.md) разделяет методику и факты компании.
- [METRICS](METRICS.md) требует раскрывать оценку до образующих её звонков и доказательств.

## Четыре разных сущности смысла

Нельзя смешивать:

1. **Факт разговора** — что реально содержится в сохранённой версии разговора.
2. **Факт компании** — что содержится в разрешённой версии знаний компании.
3. **Правило оценки** — что методика требует проверить и как трактовать.
4. **Вывод анализа** — оценка, наблюдение, рекомендация или предполагаемый результат, полученный из первых трёх.

Вывод модели не является доказательством самого себя.

Подтверждённый CRM/человеком бизнес-факт также отдельный класс факта и не превращается в доказательство того, что LLM правильно оценила разговор.

## Объект, который доказывается

Физическая таблица claims не требуется решением DOC-14. Доказательство должно ссылаться на конкретный target внутри analysis version.

Типичные evidence target:

- criterion score;
- stage decision;
- observation: ошибка / сильная сторона / предупреждение;
- AI conversation result;
- factual correction claim: менеджер сообщил факт, противоречащий знаниям;
- recommendation, если она основана на конкретном выявленном поведении;
- иная структурированная часть analysis, для которой методика требует доказательство.

Target должен иметь стабильную ссылку внутри immutable analysis version. Нельзя привязать доказательство только к свободному тексту, который позже может измениться.

## Доказательственный набор

Один вывод может требовать несколько источников. Логически доказательственный набор содержит:

- evidence ID;
- analysis version ID;
- target type и target ref;
- тип доказательственного набора;
- одну или несколько ссылок на разговор;
- ссылку на правило/критерий/этап;
- ноль или несколько ссылок на знания компании;
- ноль или одну ссылку на доверенный внешний бизнес-факт, если он действительно относится к типу вывода;
- статусы проверки;
- безопасное пояснение;
- операцию/валидатор, которые проверили ссылки;
- время проверки.

Физически это может быть одна или несколько таблиц. DOC-14 фиксирует смысл, а не SQL-нормализацию.

## Типы доказательств

### 1. Наличие факта в разговоре

Используется, когда вывод основан на конкретной реплике или нескольких репликах.

Минимальная ссылка:

- exact transcript/pseudonymized transcript version из analysis input manifest;
- segment ID;
- start/end timestamp;
- speaker business role из использованной role-assignment version;
- разрешённый excerpt/quote или проверяемая ссылка на текст;
- при нескольких репликах — все существенные segment refs.

Таймкод помогает найти место, но сам по себе без version+segment ref недостаточен.

### 2. Отсутствие ожидаемого действия

Выводы вроде «не задал уточняющий вопрос», «не предложил следующий шаг» или «не назвал обязательное условие» не имеют честной цитаты отсутствующей фразы.

Для такого вывода используется evidence type absence_check.

Он должен содержать:

- правило/критерий, которое требовало действие;
- область проверки: весь разговор или конкретный этап/интервал;
- transcript version и role-assignment version;
- достаточность покрытия разговором/сегментами;
- ограничения качества распознавания/ролей;
- результат проверки отсутствия подходящего действия;
- при необходимости соседние segment refs, показывающие контекст границ проверяемого этапа.

Нельзя выдумывать цитату «менеджер ничего не сказал».

Если качество транскрипции/ролей не позволяет надёжно проверить отсутствие, доказательство помечается неполным и вывод не повышается до надёжного по правилам методики.

### 3. Факт из знаний компании

Если вывод зависит от цены, гарантии, регламента, характеристик, допустимого обещания или другого факта компании, требуется knowledge evidence.

Минимально:

- knowledge publication version из analysis manifest;
- exact knowledge fragment ID/version, реально включённый во вход анализа;
- document ID/version;
- разрешённый excerpt или проверяемая ссылка на fragment;
- при необходимости положение/раздел документа;
- связь с правилом оценки.

Ссылка на весь документ без конкретного fragment недостаточна там, где вывод основан на конкретном факте.

### 4. Сопоставление разговора и знаний

Для вывода «менеджер сообщил неверный факт» требуется составное доказательство:

- conversation evidence: что именно сказал менеджер;
- rule evidence: почему это проверяется;
- knowledge evidence: какой факт компании считается актуальным;
- analysis version, которая использовала обе точные версии входов.

LLM не может сослаться на документ, которого не было в knowledge fragment refs analysis manifest.

### 5. Предполагаемый результат разговора

ИИ-результат вроде «клиент согласился на встречу» должен ссылаться на реплики/таймкоды, из которых это следует.

Это остаётся предполагаемым результатом анализа.

Если позже CRM подтверждает встречу/оплату, CRM-факт хранится отдельно по DATA_DICTIONARY и может показываться рядом, но не заменяет исходное evidence AI result задним числом.

### 6. Рекомендация

Общая обучающая формулировка может быть производной от verified observation.

Если рекомендация утверждает конкретную проблему текущего звонка, она должна ссылаться на observation/criterion и его доказательство.

Рекомендация не должна вводить новый «факт разговора», которого нет в проверяемых источниках.

## Rule evidence

Для оценочного вывода должна существовать ссылка на правило, определяющее, почему факт важен.

Минимально:

- methodology version;
- stable criterion/stage/rule code;
- применимость правила к типу звонка;
- требуемый тип evidence;
- если используется вес/порог — значение из той же methodology version.

Промт сам по себе не заменяет methodology rule, если балл должен быть объясним по стабильному критерию.

## Conversation reference

Conversation reference относится только к версиям, которые входят в analysis input manifest.

CORE проверяет:

- segment существует;
- segment принадлежит точной transcript/pseudonymized version;
- call_ref совпадает;
- role берётся из pinned role-assignment version;
- timestamps находятся в пределах существующего segment;
- excerpt соответствует сохранённому тексту согласно разрешённой нормализации;
- segment действительно был доступен analysis, если контракт требует передавать только выбранный subset.

Если ссылка указывает на другой звонок, другую version или несуществующий segment, reference invalid.

## Quote snapshot

Для удобства аудита evidence может хранить короткий разрешённый quote snapshot.

Quote snapshot:

- не является отдельным источником истины;
- обязан соответствовать source ref;
- хранит версию источника;
- проходит privacy-правила;
- не может быть длиннее необходимого для доказательства;
- после исправления transcript остаётся историческим снимком старой analysis version и не «перепривязывается» к новому тексту.

Если политика retention запрещает сохранять quote после удаления source content, остаются допустимые metadata/refs и честный статус ограниченной проверяемости.

## Knowledge reference

CORE проверяет:

- fragment существует;
- fragment относится к точной document version;
- publication version была pinned analysis manifest;
- fragment входил в разрешённую publication;
- если вывод был сделан внешней LLM на основании RAG, exact fragment ref действительно входил в фактический analysis context;
- excerpt соответствует fragment;
- fragment принадлежит той же компании/среде;
- fragment не draft/archived вне pinned publication.

Наличие похожего текста в сегодняшней knowledge base не доказывает, что он был доступен старому analysis.

## Внешний подтверждённый факт

CRM/human confirmation имеет собственный source ref, время и происхождение.

Он может служить доказательством отдельного факта «оплата подтверждена CRM», но не доказательством качества конкретной реплики менеджера.

Если dashboard показывает AI result рядом с CRM confirmation, обе ссылки сохраняются раздельно.

## Структурная проверка и истинность вывода

Evidence verification делится на два уровня.

### Reference integrity

Проверяет техническую корректность ссылок.

Канонические статусы по смыслу:

- verified — все обязательные refs существуют, версии совпадают, excerpt/timestamp проходят проверку;
- invalid — хотя бы одна обязательная ссылка не существует, указывает не на тот input или quote не соответствует source;
- unavailable_by_retention — ссылка исторически известна, но содержимое законно удалено и полноценно перепроверить его уже нельзя.

### Evidence coverage

Проверяет, присутствуют ли обязательные части доказательственного набора для данного типа вывода.

Статусы:

- complete — все типы evidence, которые требует rule, присутствуют и reference integrity допустим;
- partial — реальные ссылки есть, но обязательная часть отсутствует или качество не позволяет считать покрытие достаточным;
- not_applicable — конкретный дополнительный тип evidence для этого target не требуется.

Reference verified означает только: «ссылка настоящая и соответствует pinned input». Это не математическое доказательство истинности смыслового вывода LLM.

Семантическое решение остаётся analysis result и может быть оспорено/исправлено отдельным процессом.

## Evidence gate перед подтверждением analysis

До перехода candidate analysis в подтверждённую/current version CORE проверяет evidence requirements.

Минимально:

1. target существует в candidate analysis;
2. rule ref существует в pinned methodology;
3. все conversation refs существуют в pinned transcript context;
4. knowledge refs, если обязательны, входят в pinned publication и exact analysis context;
5. quotes и timestamps совпадают с source;
6. refs не выходят в другой call/company/environment;
7. privacy правил выдачи evidence не нарушены;
8. evidence type соответствует target/rule;
9. absence_check имеет определённую область и достаточное качество входов;
10. нет model-generated source IDs, которых не было во входах.

Если обязательная ссылка invalid, соответствующий claim не может считаться подтверждённым доказательным выводом.

Политика того, блокирует ли это всю analysis version или делает отдельный claim/analysis preliminary, определяется критичностью rule/methodology; DOC-14 не выдумывает единый порог для всех компаний.

## Что требует доказательства

По умолчанию evidence обязательно для:

- каждого criterion score, который влияет на общий балл;
- каждого stage reached/missed, влияющего на отчёт;
- каждой ошибки/сильной стороны, показываемой пользователю как факт конкретного звонка;
- AI result разговора;
- утверждения о фактической ошибке менеджера относительно знаний компании;
- конкретной рекомендации, если она основана на заявленном нарушении;
- любого другого вывода, который методика помечает как evidence_required.

Свободный мотивационный текст, не содержащий новых фактических утверждений, может ссылаться на уже доказанные observations вместо создания отдельного evidence.

## Несколько доказательств

Один target может иметь несколько independent или complementary evidence items.

Примеры:

- несколько реплик клиента подтверждают одно возражение;
- один criterion требует реплику менеджера и ответ клиента;
- factual mismatch требует conversation + knowledge;
- отсутствие следующего шага требует absence_check на финальном интервале разговора.

Нельзя считать число evidence items «уверенностью» автоматически.

## Противоречащие источники

Если два разрешённых knowledge fragments pinned publication противоречат друг другу:

- LLM не выбирает молча удобный fragment;
- evidence фиксирует оба релевантных источника;
- claim получает предупреждение/неполноту согласно правилам анализа;
- критический факт не повышается до надёжного без разрешения конфликта.

Исправление знаний создаёт новую version/publication по VERSIONING; старое evidence остаётся привязано к старой publication.

## Низкое качество транскрипции или ролей

Evidence может быть structurally valid, но опираться на предварительную transcript/role quality.

Поэтому evidence сохраняет ссылки на quality context analysis manifest.

Если правило требует надёжного speaker attribution, а роль предположена/не определена, нельзя скрывать это за корректным segment ref.

Такой claim/analysis получает ограничение надёжности по методике.

## Таймкоды

Таймкод относится к exact transcript/audio provenance.

Если transcript correction изменила сегментацию или timestamps:

- старое evidence сохраняет старые refs/timestamps;
- новый analysis использует новые segment refs;
- old evidence не перепривязывается автоматически по похожему тексту.

Таймкод без segment/version ref не является достаточным primary key доказательства.

## Evidence и privacy

Внутренний evidence может ссылаться на защищённый source, но пользовательская выдача должна соблюдать права.

По умолчанию внешней LLM и обычному dashboard не передаются:

- raw transcript, если нет отдельного права;
- mapping псевдонимов;
- реальные CRM IDs человека;
- секреты.

Dashboard может показывать разрешённый pseudonymized quote + timestamp + explanation.

Если руководитель имеет отдельное право на исходный текст по [DASHBOARD_ADMIN](DASHBOARD_ADMIN.md), сервер всё равно проверяет контур и source ref; браузер не получает произвольный доступ к БД.

## Evidence и versioning

Evidence принадлежит immutable analysis version.

После нового transcript/knowledge/methodology version:

- старое evidence не изменяется;
- current switch не перепривязывает refs;
- reanalysis создаёт новый evidence set;
- historical dashboard может объяснить старый result по старым refs настолько, насколько retention это позволяет.

Исправление critical evidence defect может invalidate current analysis по [VERSIONING](VERSIONING.md).

## Evidence и retention

Retention не должен заставлять хранить raw PII бесконечно только ради доказательности.

До удаления разрешённого source система должна учитывать, какие безопасные производные evidence нужны продукту и разрешены политикой.

После удаления могут сохраняться:

- IDs/versions/provenance;
- pseudonymized short quote, если это разрешено;
- timestamp/segment metadata;
- rule refs;
- knowledge refs;
- deletion status.

Если исходное содержимое более недоступно, статус проверки не должен ложно говорить, что source можно заново проверить.

## Evidence в dashboard

Путь drill-down должен быть:

метрика/оценка → звонок → current analysis version → criterion/observation/result → evidence.

Для evidence показываются в разрешённом объёме:

- кто говорил;
- короткая quote/контекст;
- timestamp;
- criterion/rule;
- если использованы знания — document/fragment/version или понятное название источника;
- статус/ограничение evidence;
- analysis version.

Dashboard не генерирует новую цитату и не подменяет evidence собственной интерпретацией.

## Evidence для агрегатов

Средняя оценка или частота ошибки не получает одну «цитату на всю метрику».

Она раскрывается до списка образующих calls/analyses, а каждый individual result — до своего evidence.

Это соответствует [METRICS](METRICS.md) и [DASHBOARD_DATA_MAP](../DASHBOARD_DATA_MAP.md).

## Ручное оспаривание

Если уполномоченный пользователь считает evidence или вывод неверным:

- исходное evidence не удаляется;
- создаётся correction/dispute event с автором, причиной и временем;
- при изменении source/claim создаётся новая version по VERSIONING;
- current может быть пересмотрен только проверяемым процессом;
- права/UX определены в [DASHBOARD_ADMIN](DASHBOARD_ADMIN.md).

## Минимальный логический состав evidence

| Поле по смыслу | Назначение |
|---|---|
| evidence_id | Стабильный внутренний ID |
| analysis_version_ref | Какая immutable analysis создала target |
| target_type / target_ref | Что именно доказывается |
| evidence_type | presence / absence_check / knowledge / composite / confirmed_external |
| rule_ref | Methodology version + stable rule/criterion/stage code |
| conversation_refs | Exact transcript/segment refs и timestamps |
| quote_snapshot | Короткий разрешённый snapshot, если нужен |
| knowledge_refs | Publication/document/fragment version refs |
| external_fact_ref | Доверенный CRM/human fact, если применимо |
| reference_integrity | verified / invalid / unavailable_by_retention |
| coverage_status | complete / partial / not_applicable |
| quality_context_ref | Ссылка на pinned quality/roles status |
| verification_error_code | Машинная причина проблемы |
| verified_by_operation | Какая CORE/validator operation выполнила проверку |
| verified_at | Время проверки |

Названия физических колонок не утверждены.

## Запрещённые способы «доказать» вывод

Нельзя:

- принимать свободный quote из LLM без сверки с source;
- принимать segment ID, которого не было во входном manifest;
- принимать knowledge document/fragment, не переданный analysis;
- ссылаться на сегодняшнюю current knowledge version вместо pinned historical version;
- использовать сам текст рекомендации как доказательство ошибки;
- выдумывать цитату для отсутствующего действия;
- считать высокий model confidence доказательством;
- считать CRM sale доказательством высокого качества разговора;
- брать evidence из другого call/company/environment;
- скрывать низкое качество transcript/roles;
- переписывать старое evidence при correction;
- считать timestamp достаточным без version/source link.

## Обязательные проверки DOC-14

Будущая реализация должна подтвердить как минимум:

1. Criterion score содержит target ref и rule ref из pinned methodology.
2. Conversation evidence ссылается на segment из exact transcript version analysis manifest.
3. Несуществующий segment ID из ответа LLM отклоняется.
4. Segment другого call_ref отклоняется.
5. Segment другой transcript version, не входившей в manifest, отклоняется.
6. Quote, не совпадающий с source segment, получает invalid.
7. Timestamp вне границ referenced segment не принимается.
8. Исправление transcript не меняет старое evidence; новый analysis получает новые refs.
9. Role attribution evidence использует pinned role-assignment version.
10. Низкая надёжность роли остаётся видимой рядом с evidence.
11. Factual mismatch использует одновременно conversation evidence, rule ref и knowledge evidence.
12. Knowledge fragment существует в pinned publication.
13. Fragment из другой компании отклоняется.
14. Fragment current publication, которого не было в historical analysis manifest, не может задним числом стать evidence старого analysis.
15. LLM-generated fake document/chunk ID отклоняется.
16. Knowledge quote сверяется с exact fragment/version.
17. Два конфликтующих knowledge fragments не скрываются выбором одного без предупреждения.
18. Absence claim не содержит выдуманную цитату отсутствующей фразы.
19. Absence check фиксирует проверяемую область разговора и качество transcript/roles.
20. При недостаточном качестве absence evidence становится partial, а не falsely complete.
21. AI result о договорённости ссылается на реальные реплики/таймкоды.
22. Позднее CRM confirmation остаётся отдельным фактом и не переписывает AI evidence.
23. Recommendation, основанная на observation, трассируется до evidence observation.
24. Invalid required evidence не позволяет claim считаться подтверждённым доказательным выводом.
25. Reference verified не маркируется как гарантия semantic truth.
26. Dashboard A не читает evidence компании B.
27. Dashboard без права на raw text получает только разрешённый pseudonymized evidence.
28. Mapping псевдонимов не попадает в evidence payload браузера/LLM.
29. Новый current analysis имеет собственный evidence set и не наследует refs старого анализа автоматически.
30. Historical analysis продолжает ссылаться на historical knowledge/transcript versions.
31. Retention deletion не заставляет сохранять запрещённый raw source бесконечно.
32. После retention evidence честно показывает ограничение повторной проверки.
33. Aggregated metric раскрывается до calls, затем до individual evidence, а не до одной общей LLM-цитаты.
34. Correction/dispute сохраняет старое evidence и автора/причину изменения.

## Что не определяется DOC-14

- SQL table/column design;
- UI окончательного evidence viewer;
- права конкретных dashboard roles;
- единый численный confidence evidence;
- универсальный порог semantic sufficiency для всех критериев;
- автоматическая политика массового reanalysis;
- retention сроки;
- физический механизм hashes/signatures.

Эти решения не могут ослабить traceability и проверки source refs, определённые здесь.

## Критерий DOC-14

Документ готов, если:

- значимый analysis target связан с конкретной immutable analysis version;
- conversation evidence указывает на exact segment/version/timestamp;
- evaluative claim указывает на exact methodology rule;
- knowledge-based claim указывает на exact publication/document/fragment version;
- absence claim имеет проверяемую область, а не фиктивную цитату;
- CORE отличает integrity ссылок от истинности вывода;
- fake/non-input refs от LLM блокируются;
- privacy/quality/retention ограничения остаются видимыми;
- new analysis version получает свой evidence set;
- dashboard может пройти от оценки к реальному основанию.

SQL, n8n, Supabase, сервер и production в DOC-14 не изменялись.