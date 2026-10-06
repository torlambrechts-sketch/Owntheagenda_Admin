-- 0007_shell_jobs.sql — what the shell needs (profile, products, notifications, sandbox), the staff
-- administration functions, and the job runtime (pg_cron and pgmq, D-05) with the purge of soft-deleted
-- records after 30 days and of raw product events after 13 months (D-24).

-- ---------------------------------------------------------------------------
-- products as the shell shows them: a short description and the design's colour pair
alter table app.products
  add column description text check (description is null or char_length(description) <= 80),
  add column color text not null default '#F2EAD6' check (color ~ '^#[0-9A-F]{6}$'),
  add column ink   text not null default '#191510' check (ink ~ '^#[0-9A-F]{6}$'),
  add column ord   int not null default 0;
update app.products set description = 'Work-environment surveys', color = '#DCEBD3', ink = '#20431C', ord = 10 where key = 'orgpuls';

-- ---------------------------------------------------------------------------
-- notifications: a message key and its parameters, rendered in the reader's language
create table app.notifications (
  id         uuid primary key default gen_random_uuid(),
  staff_id   uuid not null references app.admins (id) on delete cascade,
  kind       text not null check (kind in ('mention', 'reminder', 'security', 'system')),
  key        text not null check (key ~ '^[a-z][a-zA-Z0-9_.]{1,80}$'),
  params     jsonb not null default '{}'::jsonb check (jsonb_typeof(params) = 'object'),
  route      text check (route is null or route ~ '^/[a-z0-9/_-]*$'),
  entity     text,
  record_id  uuid,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index notifications_staff on app.notifications (staff_id, created_at desc);

create function app.notify(p_staff uuid, p_kind text, p_key text, p_params jsonb default '{}'::jsonb, p_route text default null,
                           p_entity text default null, p_record uuid default null)
  returns void language sql volatile security definer set search_path = ''
as $fn$
  insert into app.notifications (staff_id, kind, key, params, route, entity, record_id)
  values (p_staff, p_kind, p_key, coalesce(p_params, '{}'::jsonb), p_route, p_entity, p_record);
$fn$;

create function public.notifications_get(p_kind text default null, p_limit int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return jsonb_build_object(
    'unread', (select count(*) from app.notifications where staff_id = v_me and read_at is null),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'key', n.key, 'params', n.params, 'route', n.route,
                                                           'entity', n.entity, 'record_id', n.record_id, 'created_at', n.created_at, 'read', n.read_at is not null)
                                        order by n.created_at desc)
                       from (select * from app.notifications where staff_id = v_me and (p_kind is null or kind = p_kind)
                             order by created_at desc limit least(greatest(coalesce(p_limit, 30), 1), 100)) n), '[]'::jsonb));
end $fn$;

create function public.notifications_read(p_ids uuid[] default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); n int;
begin
  update app.notifications set read_at = now() where staff_id = v_me and read_at is null and (p_ids is null or id = any (p_ids));
  get diagnostics n = row_count;
  return jsonb_build_object('read', n);
end $fn$;

-- ---------------------------------------------------------------------------
-- the shell: who I am, my preferences, the products, the modules and the register values the chrome shows
create function public.shell() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); r jsonb;
begin
  update app.admins set last_seen_at = now() where id = v_me and (last_seen_at is null or last_seen_at < now() - interval '1 minute');
  select jsonb_build_object('id', a.id, 'email', a.email, 'name', coalesce(a.name, a.email), 'initials', a.initials, 'title', a.title,
           'locale', a.locale, 'time_zone', a.time_zone, 'number_format', a.number_format, 'sandbox', a.sandbox,
           'permission_set', ps.name, 'permission_kind', ps.kind, 'rights', to_jsonb(ps.rights), 'owner', a.role = 'owner')
    into r
  from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = v_me;
  return jsonb_build_object(
    'me', r,
    'products', coalesce((select jsonb_agg(jsonb_build_object('key', p.key, 'name', p.name, 'description', p.description, 'color', p.color, 'ink', p.ink,
                                                              'installed', i.product is not null, 'enabled', coalesce(i.enabled, false)) order by p.ord, p.key)
                          from app.products p left join app.installations i on i.product = p.key), '[]'::jsonb),
    'modules', (select coalesce(jsonb_object_agg(m.key, m.enabled), '{}'::jsonb) from app.modules m),
    'settings', jsonb_build_object('session_idle', app.setting('session_idle'), 'ip_allowlist', app.setting('ip_allowlist')),
    'unread', (select count(*) from app.notifications where staff_id = v_me and read_at is null),
    'badges', '{}'::jsonb);
end $fn$;

-- my own preferences
create function public.profile_set(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  update app.admins set
    locale = coalesce(p_values ->> 'locale', locale),
    time_zone = coalesce(p_values ->> 'time_zone', time_zone),
    number_format = coalesce(p_values ->> 'number_format', number_format),
    name = case when p_values ? 'name' then nullif(btrim(p_values ->> 'name'), '') else name end,
    phone = case when p_values ? 'phone' then nullif(btrim(p_values ->> 'phone'), '') else phone end,
    updated_at = now()
  where id = v_me;
  if (p_values ? 'time_zone') and not exists (select 1 from pg_timezone_names where name = p_values ->> 'time_zone') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'time_zone';
  end if;
  perform app.log('profile.updated', 'staff', v_me::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('ok', true);
end $fn$;

-- sandbox: my own switch; sample records are shown and new records are samples while it is on
create function public.sandbox_set(p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  update app.admins set sandbox = p_on, updated_at = now() where id = v_me;
  perform app.log('sandbox.switched', 'staff', v_me::text, jsonb_build_object('on', p_on));
  return jsonb_build_object('sandbox', p_on);
end $fn$;

-- the counts the sandbox section shows
create function public.sandbox_counts() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities; n bigint; out jsonb := '{}'::jsonb;
begin
  perform app.require_staff();
  for e in select * from app.entities order by ord loop
    execute format('select count(*) from app.%I where is_sample', e.tbl) into n;
    out := out || jsonb_build_object(e.key, n);
  end loop;
  return out || jsonb_build_object('last_cleared', (select max(at) from app.audit where action = 'sandbox.cleared'));
end $fn$;

-- remove every sample record in one step
create function public.sandbox_clear() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities; n bigint; total bigint := 0;
begin
  perform app.require('global', 'configure');
  perform set_config('app.purging', 'on', true);
  for e in select * from app.entities order by ord desc loop
    execute format('with d as (delete from app.%I where is_sample returning id), c as (delete from app.changelog l using d where l.entity = %L and l.record_id = d.id) select count(*) from d', e.tbl, e.key) into n;
    total := total + n;
  end loop;
  delete from app.events where is_sample;
  delete from app.admins where is_sample;
  perform app.log('sandbox.cleared', null, null, jsonb_build_object('count', total));
  return jsonb_build_object('removed', total);
end $fn$;

-- ---------------------------------------------------------------------------
-- staff administration (Settings › Users and teams, Permission sets, Visibility groups)
create function public.staff_list() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_full boolean := app.can('global', 'security');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email), 'initials', a.initials, 'title', a.title,
           'email', case when v_full or a.id = v_me then a.email end, 'active', a.active, 'permission_set_id', a.permission_set_id,
           'permission_set', ps.name, 'group_id', a.group_id, 'group', g.name, 'team_id', a.team_id, 'last_seen_at', case when v_full then a.last_seen_at end,
           'is_sample', a.is_sample,
           'mfa', case when v_full then (select coalesce(bool_or(f.status = 'verified'), false) from auth.mfa_factors f join auth.users u on u.id = f.user_id
                                         where lower(u.email) = a.email and f.factor_type = 'totp') end)
         order by a.active desc, coalesce(a.name, a.email))
    from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id join app.visibility_groups g on g.id = a.group_id
    where not a.is_sample or (select sandbox from app.admins where id = v_me)), '[]'::jsonb);
end $fn$;

create function public.staff_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_id uuid; v_email text;
begin
  if p_id is null then
    v_email := lower(btrim(p_values ->> 'email'));
    insert into app.admins (email, name, initials, title, permission_set_id, group_id, team_id, locale, time_zone, created_by)
    values (v_email, nullif(btrim(p_values ->> 'name'), ''), nullif(btrim(p_values ->> 'initials'), ''), nullif(btrim(p_values ->> 'title'), ''),
            coalesce((p_values ->> 'permission_set_id')::uuid, (select id from app.permission_sets where key = 'analyst')),
            coalesce((p_values ->> 'group_id')::uuid, (select id from app.visibility_groups where parent_id is null)),
            (p_values ->> 'team_id')::uuid, coalesce(p_values ->> 'locale', 'en'), coalesce(p_values ->> 'time_zone', 'Europe/Oslo'), v_me)
    returning id into v_id;
    perform app.log('staff.invited', 'staff', v_id::text);
  else
    if p_id = v_me and (p_values ? 'active' or p_values ? 'permission_set_id') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self';
    end if;
    update app.admins set
      name = case when p_values ? 'name' then nullif(btrim(p_values ->> 'name'), '') else name end,
      initials = case when p_values ? 'initials' then nullif(btrim(p_values ->> 'initials'), '') else initials end,
      title = case when p_values ? 'title' then nullif(btrim(p_values ->> 'title'), '') else title end,
      permission_set_id = coalesce((p_values ->> 'permission_set_id')::uuid, permission_set_id),
      group_id = coalesce((p_values ->> 'group_id')::uuid, group_id),
      team_id = case when p_values ? 'team_id' then (p_values ->> 'team_id')::uuid else team_id end,
      active = coalesce((p_values ->> 'active')::boolean, active),
      updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    perform app.log('staff.updated', 'staff', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  end if;
  return jsonb_build_object('id', v_id);
end $fn$;

-- copy another person's access (permission set, group, team) onto a staff member
create function public.staff_copy_access(p_from uuid, p_to uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  update app.admins t set permission_set_id = f.permission_set_id, group_id = f.group_id, team_id = f.team_id, updated_at = now()
  from app.admins f where f.id = p_from and t.id = p_to and t.id <> app.me();
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('staff.access_copied', 'staff', p_to::text, jsonb_build_object('from', p_from));
  return jsonb_build_object('ok', true);
end $fn$;

-- replace a person: their records are reassigned to another staff member and they are deactivated
create function public.staff_replace(p_old uuid, p_new uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities; n bigint; total bigint := 0;
begin
  perform app.require('global', 'security');
  if p_old = app.me() or p_old = p_new then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self'; end if;
  if not exists (select 1 from app.admins where id = p_new and active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'new'; end if;
  for e in select * from app.entities where owned loop
    execute format('with u as (update app.%I set owner_id = %L, updated_at = now(), version = version + 1 where owner_id = %L returning 1) select count(*) from u', e.tbl, p_new, p_old) into n;
    total := total + n;
  end loop;
  update app.admins set active = false, updated_at = now() where id = p_old;
  perform app.log('staff.replaced', 'staff', p_old::text, jsonb_build_object('by', p_new, 'records', total));
  return jsonb_build_object('reassigned', total);
end $fn$;

create function public.access_model() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return jsonb_build_object(
    'permission_sets', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'key', p.key, 'name', p.name, 'kind', p.kind, 'rights', to_jsonb(p.rights),
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

create function public.permission_set_save(p_id uuid, p_name text, p_rights text[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid; v_kind text;
begin
  perform app.require('global', 'security');
  if p_id is null then
    insert into app.permission_sets (name, kind, rights) values (btrim(p_name), 'custom', coalesce(p_rights, '{}')) returning id into v_id;
  else
    select kind into v_kind from app.permission_sets where id = p_id;
    if v_kind = 'admin' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'admin_set'; end if;
    update app.permission_sets set name = coalesce(nullif(btrim(p_name), ''), name), rights = coalesce(p_rights, rights), updated_at = now()
    where id = p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('permission_set.saved', 'permission_set', v_id::text, jsonb_build_object('rights', to_jsonb(p_rights)));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.group_save(p_id uuid, p_name text, p_parent uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid;
begin
  perform app.require('global', 'security');
  if p_id is null then
    insert into app.visibility_groups (name, parent_id) values (btrim(p_name), coalesce(p_parent, (select id from app.visibility_groups where parent_id is null)))
    returning id into v_id;
  else
    if p_parent is not null and p_parent in (select app.group_and_below(p_id)) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'parent';
    end if;
    update app.visibility_groups set name = coalesce(nullif(btrim(p_name), ''), name),
      parent_id = case when parent_id is null then null else coalesce(p_parent, parent_id) end where id = p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('group.saved', 'group', v_id::text);
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.team_save(p_id uuid, p_name text, p_manager uuid, p_members uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid;
begin
  perform app.require('global', 'security');
  if p_id is null then
    insert into app.teams (name, manager_id) values (btrim(p_name), p_manager) returning id into v_id;
  else
    update app.teams set name = coalesce(nullif(btrim(p_name), ''), name), manager_id = p_manager where id = p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_members is not null then
    delete from app.team_members where team_id = v_id;
    insert into app.team_members (team_id, staff_id) select v_id, m from unnest(p_members) m on conflict do nothing;
  end if;
  perform app.log('team.saved', 'team', v_id::text);
  return jsonb_build_object('id', v_id);
end $fn$;

-- ---------------------------------------------------------------------------
-- jobs: pg_cron schedules, pgmq carries work to edge-function workers
create extension if not exists pg_cron;
create extension if not exists pgmq;
select pgmq.create('jobs');

create function app.purge() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities; n bigint; total bigint := 0; v_events bigint;
begin
  perform set_config('app.purging', 'on', true);
  for e in select * from app.entities order by ord desc loop
    execute format('with d as (delete from app.%I where deleted_at < now() - interval ''30 days'' returning id), c as (delete from app.changelog l using d where l.entity = %L and l.record_id = d.id) select count(*) from d', e.tbl, e.key) into n;
    total := total + n;
  end loop;
  delete from app.events_in where received_at < now() - interval '13 months';
  get diagnostics v_events = row_count;
  delete from app.recents where at < now() - interval '90 days';
  delete from app.notifications where created_at < now() - interval '180 days' and read_at is not null;
  insert into app.audit (actor, action, ok, detail) values ('system', 'job.purged', true, jsonb_build_object('records', total, 'events_in', v_events));
  return jsonb_build_object('records', total, 'events_in', v_events);
end $fn$;

select cron.schedule('platform-purge', '17 3 * * *', 'select app.purge()');

do $$
declare t text;
begin
  foreach t in array array['notifications'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.notify(uuid, text, text, jsonb, text, text, uuid)', 'app.purge()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.notifications_get(text, int)', 'public.notifications_read(uuid[])', 'public.shell()', 'public.profile_set(jsonb)',
                           'public.sandbox_set(boolean)', 'public.sandbox_counts()', 'public.sandbox_clear()', 'public.staff_list()',
                           'public.staff_save(uuid, jsonb)', 'public.staff_copy_access(uuid, uuid)', 'public.staff_replace(uuid, uuid)',
                           'public.access_model()', 'public.permission_set_save(uuid, text, text[])', 'public.group_save(uuid, text, uuid)',
                           'public.team_save(uuid, text, uuid, uuid[])'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
