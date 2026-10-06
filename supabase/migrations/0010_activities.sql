-- 0010_activities.sql — activities, their types, guests and reminders, and the staff member's reminder
-- preferences. Calendar sync and booking links store their configuration here; the provider adapters
-- (Google, Microsoft Graph) come with their keys (D-07) and until then the screens show «not connected».
--
-- Completing an activity, or a note, resets a deal's idle clock (deals.last_activity_at); a planned
-- activity does not. A deal card's activity state is derived: overdue, planned or none (app.deal_act).

create table app.activity_types (
  id        uuid primary key default gen_random_uuid(),
  key       text not null unique check (key ~ '^[a-z][a-z0-9_]{1,30}$'),
  name      text not null check (char_length(btrim(name)) between 1 and 40),
  glyph     text not null default '•' check (char_length(glyph) between 1 and 3),
  ord       int not null default 0,
  active    boolean not null default true,
  is_system boolean not null default false
);
insert into app.activity_types (key, name, glyph, ord, is_system) values
  ('call', 'Call', '☎', 10, true), ('meeting', 'Meeting', '◷', 20, true), ('task', 'Task', '✓', 30, true), ('deadline', 'Deadline', '⚑', 40, true),
  ('email', 'Email', '✉', 50, true), ('lunch', 'Lunch', '◒', 60, true), ('demo', 'Product demo', '▶', 70, true);

-- custom fields may be limited to some activity types
alter table app.fields add column activity_type_ids uuid[];

create table app.activities (
  id              uuid primary key default gen_random_uuid(),
  type_id         uuid not null references app.activity_types (id),
  subject         text not null check (char_length(btrim(subject)) between 1 and 200),
  starts_at       timestamptz,
  all_day         boolean not null default false,
  duration_min    int not null default 30 check (duration_min between 0 and 1440),
  priority        text not null default 'medium' check (priority in ('high', 'medium', 'low')),
  note            text check (note is null or char_length(note) <= 10000),
  done            boolean not null default false,
  done_at         timestamptz,
  done_by         uuid references app.admins (id) on delete set null,
  deal_id         uuid references app.deals (id) on delete set null,
  lead_id         uuid,                                            -- references app.leads (0011)
  person_id       uuid references app.people (id) on delete set null,
  organization_id uuid references app.organizations (id) on delete set null,
  video_provider  text check (video_provider is null or video_provider in ('meet', 'teams', 'zoom')),
  video_url       text check (video_url is null or char_length(video_url) <= 500),
  created_by_workflow uuid,
  owner_id        uuid references app.admins (id) on delete set null,
  visibility      text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels          uuid[] not null default '{}',
  custom          jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample       boolean not null default false,
  version         int not null default 1,
  created_at      timestamptz not null default now(),
  created_by      uuid,
  updated_at      timestamptz not null default now(),
  updated_by      uuid,
  deleted_at      timestamptz,
  check (done = (done_at is not null))
);
create index activities_start on app.activities (starts_at) where deleted_at is null;
create index activities_deal on app.activities (deal_id) where deleted_at is null;
create index activities_owner on app.activities (owner_id, done);

create table app.activity_guests (
  activity_id  uuid not null references app.activities (id) on delete cascade,
  email        text not null check (char_length(email) <= 254),
  name         text check (name is null or char_length(name) <= 200),
  person_id    uuid references app.people (id) on delete set null,
  response     text not null default 'needs_action' check (response in ('needs_action', 'accepted', 'tentative', 'declined')),
  responded_at timestamptz,
  primary key (activity_id, email)
);

create table app.activity_reminders (
  id          uuid primary key default gen_random_uuid(),
  activity_id uuid not null references app.activities (id) on delete cascade,
  channel     text not null check (channel in ('app', 'email', 'desktop', 'push')),
  offset_min  int not null check (offset_min between 0 and 10080),
  fired_at    timestamptz,
  unique (activity_id, channel, offset_min)
);

create table app.reminder_prefs (
  staff_id          uuid primary key references app.admins (id) on delete cascade,
  channels          text[] not null default array['app'],
  default_offset    int not null default 15 check (default_offset between 0 and 10080),
  next_step_prompt  boolean not null default true,
  check (channels <@ array['app', 'email', 'desktop', 'push'])
);

-- calendar connection and booking configuration (the sync adapters come with their providers)
create table app.calendar_connections (
  staff_id        uuid primary key references app.admins (id) on delete cascade,
  provider        text not null check (provider in ('google', 'microsoft')),
  account_email   text,
  calendar_id     text,
  mode            text not null default 'two_way' check (mode in ('one_way', 'two_way')),
  sync_type_ids   uuid[] not null default '{}',
  status          text not null default 'not_connected' check (status in ('not_connected', 'connected', 'error')),
  last_synced_at  timestamptz,
  vault_secret_id uuid
);

create table app.booking_links (
  id           uuid primary key default gen_random_uuid(),
  staff_id     uuid not null references app.admins (id) on delete cascade,
  slug         text not null unique check (slug ~ '^[a-z0-9-]{3,60}$'),
  kind         text not null default 'general' check (kind in ('general', 'proposed')),
  title        text not null check (char_length(btrim(title)) between 1 and 120),
  description  text check (description is null or char_length(description) <= 500),
  duration_min int not null default 30 check (duration_min between 5 and 480),
  buffer_min   int not null default 15 check (buffer_min between 0 and 120),
  horizon_days int not null default 21 check (horizon_days between 1 and 120),
  video_provider text check (video_provider is null or video_provider in ('meet', 'teams', 'zoom')),
  person_id    uuid references app.people (id) on delete set null,
  deal_id      uuid references app.deals (id) on delete set null,
  expires_at   timestamptz,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table app.availability_rules (
  staff_id   uuid not null references app.admins (id) on delete cascade,
  weekday    smallint not null check (weekday between 1 and 7),
  hour       smallint not null check (hour between 0 and 23),
  primary key (staff_id, weekday, hour)
);

create table app.bookings (
  id          uuid primary key default gen_random_uuid(),
  link_id     uuid not null references app.booking_links (id) on delete cascade,
  person_id   uuid references app.people (id) on delete set null,
  name        text, email text,
  starts_at   timestamptz not null,
  activity_id uuid references app.activities (id) on delete set null,
  created_at  timestamptz not null default now(),
  cancelled_at timestamptz
);

-- ---------------------------------------------------------------------------
insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('activity', 'activities', 'deals', null, true, 'subject', array['priority'], array['subject'], 50);
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('activity', 'type_id', 'uuid', true, true, null, 1),
  ('activity', 'subject', 'text', true, true, null, 2),
  ('activity', 'starts_at', 'timestamptz', true, false, null, 3),
  ('activity', 'all_day', 'boolean', true, false, null, 4),
  ('activity', 'duration_min', 'int', true, false, null, 5),
  ('activity', 'priority', 'text', true, false, null, 6),
  ('activity', 'note', 'text', true, false, null, 7),
  ('activity', 'done', 'boolean', false, false, null, 8),
  ('activity', 'done_at', 'timestamptz', false, false, null, 9),
  ('activity', 'deal_id', 'uuid', true, false, 'deal', 10),
  ('activity', 'lead_id', 'uuid', true, false, null, 11),
  ('activity', 'person_id', 'uuid', true, false, 'person', 12),
  ('activity', 'organization_id', 'uuid', true, false, 'organization', 13),
  ('activity', 'video_provider', 'text', true, false, null, 14),
  ('activity', 'video_url', 'text', true, false, null, 15);

-- a deal card's activity state
create or replace function app.deal_act(p_deal uuid) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select case
    when exists (select 1 from app.activities a where a.deal_id = p_deal and not a.done and a.deleted_at is null and a.starts_at < now()) then 'overdue'
    when exists (select 1 from app.activities a where a.deal_id = p_deal and not a.done and a.deleted_at is null) then 'planned'
    else 'none' end
$fn$;

-- the shape the calendar and the to-do list read
create function app.activity_row(a app.activities) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select to_jsonb(a) - 'custom' || jsonb_build_object(
    'type', (select jsonb_build_object('key', t.key, 'name', t.name, 'glyph', t.glyph) from app.activity_types t where t.id = a.type_id),
    'owner', (select jsonb_build_object('name', s.name, 'initials', s.initials) from app.admins s where s.id = a.owner_id),
    'deal', (select jsonb_build_object('id', d.id, 'title', d.title) from app.deals d where d.id = a.deal_id),
    'organization', (select o.name from app.organizations o where o.id = coalesce(a.organization_id, (select organization_id from app.deals where id = a.deal_id))),
    'person', (select p.name from app.people p where p.id = a.person_id),
    'guests', (select count(*) from app.activity_guests g where g.activity_id = a.id),
    'declined', (select count(*) from app.activity_guests g where g.activity_id = a.id and g.response = 'declined'),
    'overdue', not a.done and a.starts_at < now(),
    'custom', a.custom)
$fn$;

-- activities in a time range (the calendar) or by state (the to-do list)
create function public.activities_get(p_query jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_rows jsonb; v_counts jsonb;
  v_owner uuid[] := case when jsonb_typeof(q -> 'owner_ids') = 'array' then array(select jsonb_array_elements_text(q -> 'owner_ids'))::uuid[] end;
  v_types uuid[] := case when jsonb_typeof(q -> 'type_ids') = 'array' then array(select jsonb_array_elements_text(q -> 'type_ids'))::uuid[] end;
  v_tz text := (select time_zone from app.admins where id = v_me);
  v_today date := (now() at time zone v_tz)::date;
begin
  with base as (
    select a.* from app.activities a
    where a.deleted_at is null and app.visible(a.owner_id, a.visibility) and (v_sandbox or not a.is_sample)
      and (v_owner is null or a.owner_id = any (v_owner)) and (v_types is null or a.type_id = any (v_types))
      and (q ->> 'deal_id' is null or a.deal_id = (q ->> 'deal_id')::uuid)
      and (q ->> 'person_id' is null or a.person_id = (q ->> 'person_id')::uuid)
      and (q ->> 'organization_id' is null or a.organization_id = (q ->> 'organization_id')::uuid)
      and (q ->> 'lead_id' is null or a.lead_id = (q ->> 'lead_id')::uuid)
  )
  select
    coalesce((select jsonb_agg(app.activity_row(b) order by b.starts_at nulls last, b.priority) from base b
              where (q ->> 'from' is null or b.starts_at >= (q ->> 'from')::timestamptz)
                and (q ->> 'to' is null or b.starts_at < (q ->> 'to')::timestamptz)
                and case coalesce(q ->> 'status', 'all') when 'open' then not b.done when 'done' then b.done else true end
                and case coalesce(q ->> 'tab', 'all')
                      when 'overdue' then not b.done and b.starts_at < now()
                      when 'today' then (b.starts_at at time zone v_tz)::date = v_today
                      when 'week' then (b.starts_at at time zone v_tz)::date between date_trunc('week', v_today)::date and date_trunc('week', v_today)::date + 6
                      when 'done' then b.done
                      else true end), '[]'::jsonb),
    jsonb_build_object(
      'all', (select count(*) from base where not done),
      'overdue', (select count(*) from base where not done and starts_at < now()),
      'today', (select count(*) from base where (starts_at at time zone v_tz)::date = v_today and not done),
      'week', (select count(*) from base where (starts_at at time zone v_tz)::date between date_trunc('week', v_today)::date and date_trunc('week', v_today)::date + 6 and not done),
      'done', (select count(*) from base where done))
  into v_rows, v_counts;
  perform app.log('record.listed', 'activity', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'counts', v_counts);
end $fn$;

-- done or open again. Completing resets the linked deal's idle clock; the answer says whether to prompt
-- for the next step (the staff member's preference).
create function public.activity_done(p_id uuid, p_done boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); a app.activities;
begin
  select * into a from app.activities where id = p_id and deleted_at is null for update;
  if not found or not app.visible(a.owner_id, a.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if a.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others'; end if;
  if a.done = p_done then return jsonb_build_object('id', a.id, 'prompt', false); end if;
  update app.activities set done = p_done, done_at = case when p_done then now() end, done_by = case when p_done then v_me end,
    version = version + 1, updated_at = now(), updated_by = v_me where id = a.id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id) values ('activity', a.id, 'done', to_jsonb(a.done), to_jsonb(p_done), v_me);
  if p_done and a.deal_id is not null then update app.deals set last_activity_at = now() where id = a.deal_id; end if;
  perform app.log(case when p_done then 'activity.completed' else 'activity.reopened' end, 'activity', a.id::text);
  perform app.emit(case when p_done then 'activity.completed' else 'activity.reopened' end, 'activity', a.id, jsonb_build_object('deal', a.deal_id), a.is_sample);
  return jsonb_build_object('id', a.id, 'prompt', p_done and a.deal_id is not null
    and coalesce((select next_step_prompt from app.reminder_prefs where staff_id = v_me), true)
    and not exists (select 1 from app.activities x where x.deal_id = a.deal_id and not x.done and x.deleted_at is null and x.id <> a.id));
end $fn$;

create function public.activities_done_bulk(p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid; n int := 0;
begin
  perform app.require('deals', 'bulk');
  foreach v_id in array coalesce(p_ids, '{}') loop perform public.activity_done(v_id, true); n := n + 1; end loop;
  return jsonb_build_object('done', n);
end $fn$;

-- guests and reminders of one activity, replaced as a set
create function public.activity_guests_set(p_id uuid, p_guests jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); a app.activities;
begin
  select * into a from app.activities where id = p_id and deleted_at is null;
  if not found or not app.visible(a.owner_id, a.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if a.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others'; end if;
  delete from app.activity_guests where activity_id = p_id and lower(email) not in (select lower(g ->> 'email') from jsonb_array_elements(coalesce(p_guests, '[]'::jsonb)) g);
  insert into app.activity_guests (activity_id, email, name, person_id)
  select p_id, lower(btrim(g ->> 'email')), nullif(btrim(g ->> 'name'), ''), (g ->> 'person_id')::uuid
  from jsonb_array_elements(coalesce(p_guests, '[]'::jsonb)) g where coalesce(g ->> 'email', '') ~ '^[^@\s]+@[^@\s]+$'
  on conflict (activity_id, email) do update set name = excluded.name, person_id = excluded.person_id;
  return coalesce((select jsonb_agg(to_jsonb(g)) from app.activity_guests g where g.activity_id = p_id), '[]'::jsonb);
end $fn$;

create function public.activity_reminders_set(p_id uuid, p_reminders jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); a app.activities;
begin
  select * into a from app.activities where id = p_id and deleted_at is null;
  if not found or not app.visible(a.owner_id, a.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  delete from app.activity_reminders where activity_id = p_id and fired_at is null;
  insert into app.activity_reminders (activity_id, channel, offset_min)
  select p_id, r ->> 'channel', (r ->> 'offset_min')::int from jsonb_array_elements(coalesce(p_reminders, '[]'::jsonb)) r
  on conflict do nothing;
  return coalesce((select jsonb_agg(jsonb_build_object('channel', channel, 'offset_min', offset_min)) from app.activity_reminders where activity_id = p_id), '[]'::jsonb);
end $fn$;

create function public.activity_detail(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); a app.activities;
begin
  select * into a from app.activities where id = p_id;
  if not found or not app.visible(a.owner_id, a.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('record.read', 'activity', p_id::text);
  return app.activity_row(a) || jsonb_build_object(
    'guest_list', coalesce((select jsonb_agg(to_jsonb(g) order by g.email) from app.activity_guests g where g.activity_id = p_id), '[]'::jsonb),
    'reminders', coalesce((select jsonb_agg(jsonb_build_object('channel', r.channel, 'offset_min', r.offset_min)) from app.activity_reminders r where r.activity_id = p_id), '[]'::jsonb));
end $fn$;

create function public.activity_types_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(to_jsonb(t) order by t.ord) from app.activity_types t), '[]'::jsonb);
end $fn$;

create function public.activity_type_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid;
begin
  perform app.require('deals', 'configure');
  if p_id is null then
    insert into app.activity_types (key, name, glyph, ord)
    values (coalesce(nullif(p_values ->> 'key', ''), 't_' || substr(md5(random()::text), 1, 6)), btrim(p_values ->> 'name'), coalesce(nullif(p_values ->> 'glyph', ''), '•'),
            (select coalesce(max(ord), 0) + 10 from app.activity_types)) returning id into v_id;
  else
    update app.activity_types set name = coalesce(nullif(btrim(p_values ->> 'name'), ''), name), glyph = coalesce(nullif(p_values ->> 'glyph', ''), glyph),
      active = coalesce((p_values ->> 'active')::boolean, active), ord = coalesce((p_values ->> 'ord')::int, ord)
    where id = p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('activity_type.saved', 'activity_type', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('id', v_id);
end $fn$;

-- my reminder channels, calendar connection, booking links and availability
create function public.my_scheduling() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return jsonb_build_object(
    'prefs', coalesce((select to_jsonb(p) - 'staff_id' from app.reminder_prefs p where p.staff_id = v_me),
                      jsonb_build_object('channels', jsonb_build_array('app'), 'default_offset', 15, 'next_step_prompt', true)),
    'email', (select email from app.admins where id = v_me),
    'calendar', (select to_jsonb(c) - 'staff_id' - 'vault_secret_id' from app.calendar_connections c where c.staff_id = v_me),
    'links', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at) from app.booking_links l where l.staff_id = v_me and l.active), '[]'::jsonb),
    'availability', coalesce((select jsonb_agg(jsonb_build_object('weekday', r.weekday, 'hour', r.hour)) from app.availability_rules r where r.staff_id = v_me), '[]'::jsonb),
    'bookings', coalesce((select jsonb_agg(jsonb_build_object('name', coalesce(b.name, p.name), 'starts_at', b.starts_at, 'link', l.title, 'created_at', b.created_at) order by b.created_at desc)
                          from app.bookings b join app.booking_links l on l.id = b.link_id left join app.people p on p.id = b.person_id
                          where l.staff_id = v_me and b.cancelled_at is null), '[]'::jsonb));
end $fn$;

create function public.reminder_prefs_set(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  insert into app.reminder_prefs (staff_id) values (v_me) on conflict do nothing;
  update app.reminder_prefs set
    channels = case when p_values ? 'channels' then array(select jsonb_array_elements_text(p_values -> 'channels')) else channels end,
    default_offset = coalesce((p_values ->> 'default_offset')::int, default_offset),
    next_step_prompt = coalesce((p_values ->> 'next_step_prompt')::boolean, next_step_prompt)
  where staff_id = v_me;
  return jsonb_build_object('ok', true);
end $fn$;

create function public.availability_set(p_cells jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  delete from app.availability_rules where staff_id = v_me;
  insert into app.availability_rules (staff_id, weekday, hour)
  select v_me, (c ->> 'weekday')::smallint, (c ->> 'hour')::smallint from jsonb_array_elements(coalesce(p_cells, '[]'::jsonb)) c on conflict do nothing;
  return jsonb_build_object('ok', true);
end $fn$;

create function public.booking_link_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_id uuid;
begin
  if p_id is null then
    insert into app.booking_links (staff_id, slug, kind, title, description, duration_min, video_provider, person_id, deal_id, expires_at)
    values (v_me, coalesce(nullif(p_values ->> 'slug', ''), substr(md5(random()::text), 1, 10)), coalesce(p_values ->> 'kind', 'general'),
            btrim(p_values ->> 'title'), p_values ->> 'description', coalesce((p_values ->> 'duration_min')::int, 30), p_values ->> 'video_provider',
            (p_values ->> 'person_id')::uuid, (p_values ->> 'deal_id')::uuid, (p_values ->> 'expires_at')::timestamptz)
    returning id into v_id;
  else
    update app.booking_links set title = coalesce(nullif(btrim(p_values ->> 'title'), ''), title), description = coalesce(p_values ->> 'description', description),
      duration_min = coalesce((p_values ->> 'duration_min')::int, duration_min), active = coalesce((p_values ->> 'active')::boolean, active)
    where id = p_id and staff_id = v_me returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('booking_link.saved', 'booking_link', v_id::text);
  return jsonb_build_object('id', v_id);
end $fn$;

-- the reminder job: in-app reminders become notifications; other channels wait for their providers
create function app.dispatch_reminders() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n int := 0;
begin
  for r in
    select ar.id, a.id activity_id, a.owner_id, a.subject, a.starts_at, ar.offset_min, t.name type_name, d.title deal_title, o.name org_name
    from app.activity_reminders ar join app.activities a on a.id = ar.activity_id join app.activity_types t on t.id = a.type_id
    left join app.deals d on d.id = a.deal_id left join app.organizations o on o.id = coalesce(a.organization_id, d.organization_id)
    where ar.fired_at is null and ar.channel = 'app' and not a.done and a.deleted_at is null and a.owner_id is not null
      and a.starts_at - make_interval(mins => ar.offset_min) <= now() and a.starts_at > now() - interval '1 hour'
    for update of ar skip locked
  loop
    perform app.notify(r.owner_id, 'reminder', 'reminder', jsonb_build_object('subject', r.subject, 'minutes', r.offset_min, 'type', r.type_name,
                       'record', coalesce(r.org_name, r.deal_title, '')), '/activities', 'activity', r.activity_id);
    update app.activity_reminders set fired_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $fn$;
select cron.schedule('platform-reminders', '* * * * *', 'select app.dispatch_reminders()');

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['activity_types', 'activities', 'activity_guests', 'activity_reminders', 'reminder_prefs', 'calendar_connections',
                           'booking_links', 'availability_rules', 'bookings'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.activity_row(app.activities)', 'app.dispatch_reminders()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.activities_get(jsonb)', 'public.activity_done(uuid, boolean)', 'public.activities_done_bulk(uuid[])',
                           'public.activity_guests_set(uuid, jsonb)', 'public.activity_reminders_set(uuid, jsonb)', 'public.activity_detail(uuid)',
                           'public.activity_types_get()', 'public.activity_type_save(uuid, jsonb)', 'public.my_scheduling()', 'public.reminder_prefs_set(jsonb)',
                           'public.availability_set(jsonb)', 'public.booking_link_save(uuid, jsonb)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
