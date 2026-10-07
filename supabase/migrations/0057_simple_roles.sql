-- 0057_simple_roles.sql — Sentral Simple › Platform (design-reference/sentral-simple/SimplePlatform.dc.html).
--
-- 1. The design's five roles. «Team and roles» offers Admin / Sales / Support / Marketing / Read-only: today's permission sets
--    admin, sales, support, marketing and analyst (0003), renamed and patched so each role opens its section of Simple:
--      marketing += campaigns:reports_others, campaigns:workflows, campaigns:delete, global:see   (Growth; the applications)
--      sales     += campaigns:see, campaigns:add                                                 (CRM › Lists are segments)
--      support and analyst keep their rights; admin is every right.
--    Finance and Projects fold in, as the design's own map does (SimplePlatform.dc.html, RM: Finance → Read-only, Project →
--    Sales). Their rows stay — the history, the ticket queues and every suite that names them still resolve — but they are no
--    longer offered (permission_sets.offered), and their members move: finance → analyst, project → sales, one audited row each
--    (staff.role_folded). A custom set made in Settings is offered unless someone says otherwise.
-- 2. staff_save (0007 body) refuses a set that is not offered — unless the person already holds it — and refuses to change the
--    owner's set or switch the owner off: the owner is «Admin (owner)» (D-11).
-- 3. staff_list (0007 body) adds the set's key, the owner flag and, for global:security as the e-mail and last activity already
--    are, whether the person has a login yet (an invitation creates the staff row only; no Auth user, no e-mail — V-SPL-12).
--    access_model (0007 body) adds offered.
-- 4. plan_accounts(product): live accounts per plan band of a product (Plans and prices). The prices themselves are read with
--    billing_overview (0013); nothing here writes a price — Orgpuls owns checkout and has no command for it (D-40).
-- 5. status_notice_push_result(id, ok, error): the status message is delivered by the app calling Orgpuls' settings.set_notice
--    through product-command right after status_notice_set (no worker drains the queued product_command job yet). The person
--    who just published the notice records the outcome, once, within five minutes; «delivered» is accepted only when the
--    command audit written by product-command holds that person's successful settings.set_notice for the product since the
--    notice was set. worker_status_notice_pushed (0044, service role) stays the worker's path.

-- ---------------------------------------------------------------------------
-- 1. the five roles
alter table app.permission_sets add column offered boolean not null default true;

-- a custom set already carrying one of the five names keeps its rights under a marked name, so the rename cannot collide
update app.permission_sets p set name = left(p.name, 70) || ' (custom)', updated_at = now()
where p.name in ('Admin', 'Sales', 'Support', 'Marketing', 'Read-only')
  and p.key is distinct from (case p.name when 'Admin' then 'admin' when 'Sales' then 'sales' when 'Support' then 'support'
                                          when 'Marketing' then 'marketing' else 'analyst' end);

update app.permission_sets p set name = v.n, updated_at = now()
from (values ('admin', 'Admin'), ('sales', 'Sales'), ('support', 'Support'), ('marketing', 'Marketing'), ('analyst', 'Read-only')) v(k, n)
where p.key = v.k;

update app.permission_sets p set rights = p.rights || array(select x from unnest(v.add) x where not x = any (p.rights)), updated_at = now()
from (values ('marketing', array['campaigns:reports_others', 'campaigns:workflows', 'campaigns:delete', 'global:see']),
             ('sales', array['campaigns:see', 'campaigns:add'])) v(k, add)
where p.key = v.k;

update app.permission_sets set offered = false, updated_at = now() where key in ('finance', 'project');

do $$
declare
  r record;
  v_to text;
begin
  for r in select a.id, ps.key from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id
           where ps.key in ('finance', 'project') order by a.created_at loop
    v_to := case r.key when 'finance' then 'analyst' else 'sales' end;
    update app.admins set permission_set_id = (select id from app.permission_sets where key = v_to), updated_at = now() where id = r.id;
    perform app.log('staff.role_folded', 'staff', r.id::text, jsonb_build_object('from', r.key, 'to', v_to, 'migration', '0057'));
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 2. staff_save: only offered sets; the owner stays Admin and stays on
create or replace function public.staff_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_id uuid; v_email text; v_set uuid := (p_values ->> 'permission_set_id')::uuid;
        v_current uuid; v_role text;
begin
  if p_id is null then
    if v_set is not null and not exists (select 1 from app.permission_sets where id = v_set and offered) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'permission_set';
    end if;
    v_email := lower(btrim(p_values ->> 'email'));
    insert into app.admins (email, name, initials, title, permission_set_id, group_id, team_id, locale, time_zone, created_by)
    values (v_email, nullif(btrim(p_values ->> 'name'), ''), nullif(btrim(p_values ->> 'initials'), ''), nullif(btrim(p_values ->> 'title'), ''),
            coalesce(v_set, (select id from app.permission_sets where key = 'analyst')),
            coalesce((p_values ->> 'group_id')::uuid, (select id from app.visibility_groups where parent_id is null)),
            (p_values ->> 'team_id')::uuid, coalesce(p_values ->> 'locale', 'en'), coalesce(p_values ->> 'time_zone', 'Europe/Oslo'), v_me)
    returning id into v_id;
    perform app.log('staff.invited', 'staff', v_id::text);
  else
    if p_id = v_me and (p_values ? 'active' or p_values ? 'permission_set_id') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self';
    end if;
    select permission_set_id, role into v_current, v_role from app.admins where id = p_id;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if v_role = 'owner' and (p_values ? 'active' or (v_set is not null and v_set <> v_current)) then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'owner';
    end if;
    if v_set is not null and v_set <> v_current and not exists (select 1 from app.permission_sets where id = v_set and offered) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'permission_set';
    end if;
    update app.admins set
      name = case when p_values ? 'name' then nullif(btrim(p_values ->> 'name'), '') else name end,
      initials = case when p_values ? 'initials' then nullif(btrim(p_values ->> 'initials'), '') else initials end,
      title = case when p_values ? 'title' then nullif(btrim(p_values ->> 'title'), '') else title end,
      permission_set_id = coalesce(v_set, permission_set_id),
      group_id = coalesce((p_values ->> 'group_id')::uuid, group_id),
      team_id = case when p_values ? 'team_id' then (p_values ->> 'team_id')::uuid else team_id end,
      active = coalesce((p_values ->> 'active')::boolean, active),
      updated_at = now()
    where id = p_id returning id into v_id;
    perform app.log('staff.updated', 'staff', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  end if;
  return jsonb_build_object('id', v_id);
end $fn$;

-- ---------------------------------------------------------------------------
-- 3. staff_list and access_model, additive
create or replace function public.staff_list() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_full boolean := app.can('global', 'security');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email), 'initials', a.initials, 'title', a.title,
           'email', case when v_full or a.id = v_me then a.email end, 'active', a.active, 'permission_set_id', a.permission_set_id,
           'permission_set', ps.name, 'permission_set_key', ps.key, 'owner', a.role = 'owner',
           'group_id', a.group_id, 'group', g.name, 'team_id', a.team_id, 'last_seen_at', case when v_full then a.last_seen_at end,
           'is_sample', a.is_sample,
           'mfa', case when v_full then (select coalesce(bool_or(f.status = 'verified'), false) from auth.mfa_factors f join auth.users u on u.id = f.user_id
                                         where lower(u.email) = a.email and f.factor_type = 'totp') end,
           'login', case when v_full then exists (select 1 from auth.users u where lower(u.email) = a.email and u.email_confirmed_at is not null) end)
         order by a.active desc, coalesce(a.name, a.email))
    from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id join app.visibility_groups g on g.id = a.group_id
    where not a.is_sample or (select sandbox from app.admins where id = v_me)), '[]'::jsonb);
end $fn$;

create or replace function public.access_model() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return jsonb_build_object(
    'permission_sets', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'key', p.key, 'name', p.name, 'kind', p.kind, 'rights', to_jsonb(p.rights),
                                   'offered', p.offered,
                                   'members', (select count(*) from app.admins a where a.permission_set_id = p.id and a.active and not a.is_sample)) order by p.created_at, p.name)
                                 from app.permission_sets p), '[]'::jsonb),
    'groups', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'parent_id', g.parent_id,
                          'members', (select count(*) from app.admins a where a.group_id = g.id and a.active and not a.is_sample)) order by g.created_at)
                        from app.visibility_groups g), '[]'::jsonb),
    'teams', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'manager_id', t.manager_id,
                         'manager', (select coalesce(a.name, a.email) from app.admins a where a.id = t.manager_id),
                         'members', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email)) order by a.name)
                                              from app.team_members m join app.admins a on a.id = m.staff_id where m.team_id = t.id), '[]'::jsonb)) order by t.name)
                       from app.teams t), '[]'::jsonb));
end $fn$;

-- ---------------------------------------------------------------------------
-- 4. accounts per plan band: active installations whose subscription is on that band and neither cancelled nor expired
create function public.plan_accounts(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  if not exists (select 1 from app.products where key = p_product) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('band_label', b.band_label, 'accounts', (
             select count(distinct ap.account_id) from app.subscriptions s
             join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
             where s.product = p_product and s.plan = b.band_label and ap.status = 'active' and app.sub_status(s) not in ('cancelled', 'expired')))
           order by b.min_employees)
    from (select distinct on (pv.band_label) pv.band_label, pv.min_employees from app.plan_versions pv
          where pv.product = p_product and pv.active order by pv.band_label, pv.version desc) b), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
-- 5. the status message's delivery, as the publisher's own call reported it
create function public.status_notice_push_result(p_id uuid, p_ok boolean, p_error text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); n app.status_notices;
begin
  select * into n from app.status_notices where id = p_id for update;
  if not found or n.set_by is distinct from v_me then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_ok is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ok'; end if;
  if n.pushed_at is not null or n.push_error is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
  if n.set_at < now() - interval '5 minutes' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'late'; end if;
  if not p_ok and coalesce(p_error, '') !~ '^[a-z0-9_]{1,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'error'; end if;
  if p_ok and not exists (select 1 from app.audit a where a.command = 'settings.set_notice' and a.product = n.product and a.ok
                            and a.actor = app.admin_email() and a.at >= n.set_at) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'no_command';
  end if;
  update app.status_notices set pushed_at = case when p_ok then now() end, push_error = case when p_ok then null else p_error end where id = p_id;
  perform app.log('status_notice.pushed', 'product', n.product, jsonb_build_object('notice', p_id, 'ok', p_ok, 'error', case when p_ok then null else p_error end));
  return jsonb_build_object('id', p_id, 'ok', p_ok);
end $fn$;

revoke all on function public.plan_accounts(text) from public, anon;
grant execute on function public.plan_accounts(text) to authenticated;
revoke all on function public.status_notice_push_result(uuid, boolean, text) from public, anon;
grant execute on function public.status_notice_push_result(uuid, boolean, text) to authenticated;
