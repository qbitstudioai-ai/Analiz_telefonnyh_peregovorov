# Текущее состояние проекта

Обновлено: 2026-09-25. Техническое проектирование требований.

## Режим

**Разрешено техническое проектирование в документации по одному ID.**

SQL, JSON workflow, программный код, n8n, Supabase, сервер и production пока не изменяются. Демонстрационный дашборд использует вымышленные данные и не подключён к Supabase.

## Последняя завершённая задача

**DOC-17 — доведена спецификация общей базы знаний нескольких продуктов.**

Обновлён [ANALYSIS_AND_KNOWLEDGE](specs/ANALYSIS_AND_KNOWLEDGE.md).

Зафиксировано:

- у компании один канонический источник knowledge documents, а продукты не создают независимые копии без необходимости;
- document, fragment, embedding и publication version являются разными сущностями;
- lifecycle: draft → validation → publication → runtime read → superseded/archive/depublication; invalidated выделен отдельно;
- publication является отдельной явной операцией и фиксирует exact разрешённый набор;
- runtime reader фиксирует publication version до retrieval и сохраняет exact fragment refs;
- бот и анализ звонков используют отдельные runtime identities и не вызывают workflow друг друга;
- reader, editor и publisher разделены;
- product scope позволяет разным продуктам получать разные разрешённые subsets одного канонического источника;
- test и production имеют отдельные publication families и не активируют друг друга автоматически;
- новая публикация действует только на новые операции и не переписывает старые analyses;
- historical reanalysis является отдельной операцией;
- embeddings привязаны к exact fragment + model/config и не расширяют права;
- vector search ограничен company + environment + publication + product scope;
- пустой retrieval не заменяется знаниями другой компании, draft или общими знаниями LLM;
- fact-dependent анализ не подтверждается без обязательного knowledge input;
- определены 36 обязательных сценариев будущей проверки.

SQL/RLS, физическая RAG-схема, chunk size, vector index, конкретная embedding model, реальные документы и production публикации не создавались и не тестировались.

## Следующая одна задача

**DOC-18 — описать мониторинг, резервирование, тестирование и безопасный выпуск.**

Цель: создать `docs/RELEASE_CHECKLIST.md` и закрепить эксплуатационные требования: health/alerts, backup/restore, retention-aware backup, test strategy, release gates, rollback/reconciliation, секреты, ресурсы и блокирующие проверки перед production — без фактического деплоя или изменения сервера.

Критерий готовности: существует единый проверяемый checklist, по которому нельзя назвать систему готовой к production без подтверждённых тестов из DOC-04—DOC-17, восстановления backup, изоляции компаний, privacy, delivery/idempotency, мониторинга и подготовленного rollback.

## Что не применялось

SQL, workflow, код, миграции, настройки n8n/Supabase, сервер, реальные Credentials, реальные документы компаний и production не изменялись и не тестировались.
