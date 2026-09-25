-- DB-08B PRE-FLIGHT №2
-- Только чтение. Ничего не создаёт, не изменяет и не удаляет.
-- Фактический результат 25.09.2026: PASS, все запросы вернули 0 строк.

-- 1. Проверяем новую и прежние schema.
select
    nspname as schema_name
from pg_namespace
where nspname in (
    'shablon_analiz_telefonnyh_peregovorov',
    'shablon',
    'atp_test'
)
order by nspname;

-- 2. Проверяем, нет ли уже объектов в новой schema.
select
    n.nspname as schema_name,
    c.relname as object_name,
    c.relkind as object_kind
from pg_class c
join pg_namespace n
    on n.oid = c.relnamespace
where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
order by c.relkind, c.relname;

-- 3. Проверяем функции в новой schema.
select
    n.nspname as schema_name,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n
    on n.oid = p.pronamespace
where n.nspname = 'shablon_analiz_telefonnyh_peregovorov'
order by p.proname, arguments;

-- 4. Проверяем новые и старые capability roles.
select
    rolname,
    rolcanlogin,
    rolsuper,
    rolcreatedb,
    rolcreaterole,
    rolreplication,
    rolbypassrls
from pg_roles
where rolname like 'shablon\_%' escape '\'
   or rolname like 'atp\_test\_%' escape '\'
order by rolname;
