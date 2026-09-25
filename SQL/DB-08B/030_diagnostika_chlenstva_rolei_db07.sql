-- DB-08B / DB-07 membership diagnostic after verify step 028
-- READ ONLY. Ничего не создаёт, не изменяет и не удаляет.
-- Показывает текущего пользователя, membership всех 9 capability roles
-- и возможные остатки временных probe-schema после неудачного verify.

with target_roles(role_name) as (
  values
    ('shablon_analiz_telefonnyh_peregovorov_orchestrator'),
    ('shablon_analiz_telefonnyh_peregovorov_core'),
    ('shablon_analiz_telefonnyh_peregovorov_privacy'),
    ('shablon_analiz_telefonnyh_peregovorov_raw_transcript_reader'),
    ('shablon_analiz_telefonnyh_peregovorov_knowledge_reader'),
    ('shablon_analiz_telefonnyh_peregovorov_knowledge_admin'),
    ('shablon_analiz_telefonnyh_peregovorov_dashboard'),
    ('shablon_analiz_telefonnyh_peregovorov_admin_api'),
    ('shablon_analiz_telefonnyh_peregovorov_monitor')
),
session_info as (
  select
    'session_role'::text as record_type,
    null::text as capability_role,
    r.rolname::text as member_role,
    null::text as grantor_role,
    null::boolean as admin_option,
    null::boolean as inherit_option,
    null::boolean as set_option,
    r.rolcanlogin as member_can_login,
    r.rolsuper as member_superuser,
    r.rolcreaterole as member_createrole,
    r.rolbypassrls as member_bypassrls
  from pg_roles r
  where r.rolname = current_user
),
memberships as (
  select
    'membership'::text as record_type,
    parent.rolname::text as capability_role,
    member.rolname::text as member_role,
    grantor.rolname::text as grantor_role,
    m.admin_option,
    m.inherit_option,
    m.set_option,
    member.rolcanlogin as member_can_login,
    member.rolsuper as member_superuser,
    member.rolcreaterole as member_createrole,
    member.rolbypassrls as member_bypassrls
  from pg_auth_members m
  join pg_roles parent on parent.oid = m.roleid
  join pg_roles member on member.oid = m.member
  join pg_roles grantor on grantor.oid = m.grantor
  join target_roles t on t.role_name = parent.rolname
),
probe_leftovers as (
  select
    'probe_schema_leftover'::text as record_type,
    n.nspname::text as capability_role,
    null::text as member_role,
    null::text as grantor_role,
    null::boolean as admin_option,
    null::boolean as inherit_option,
    null::boolean as set_option,
    null::boolean as member_can_login,
    null::boolean as member_superuser,
    null::boolean as member_createrole,
    null::boolean as member_bypassrls
  from pg_namespace n
  where n.nspname in ('atp_verify_other', 'atp_verify_prod')
)
select *
from (
  select * from session_info
  union all
  select * from memberships
  union all
  select * from probe_leftovers
) q
order by
  case record_type
    when 'session_role' then 1
    when 'membership' then 2
    else 3
  end,
  capability_role nulls first,
  member_role nulls first;
