-- 0023_screen_requests.sql — what the Phase 1 screens asked of the database (docs/crm-enrichment/requests/).
--
-- Security: reminders and ticket links now need the right to edit, and a ticket can no longer be changed
-- by someone who may not see its queue, nor moved into a queue they may not see. A bug: a note with an
-- @mention was refused on every screen, because its notification route carries the record in a query
-- string. And the functions the screens left disabled: saving the calendar choice, proposed booking times,
-- shifting activities, sorting and OR groups in lists, converting a deal back to a lead, lead numbers, a
-- thread line for an executed action, the record-type registry, and honest CSAT and period comparisons.

-- ---------------------------------------------------------------------------
-- notifications may link to a record: /contacts?person=<uuid> (contacts R-1)
alter table app.notifications drop constraint notifications_route_check;
alter table app.notifications add constraint notifications_route_check
  check (route is null or route ~ '^/[a-z0-9/_-]*(\?[a-z_]+=[0-9a-f-]{36})?$');

-- ---------------------------------------------------------------------------
-- reminders: the owner of the activity, or someone who may edit others' records (activities R-ACT-03)
create or replace function public.activity_reminders_set(p_id uuid, p_reminders jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); a app.activities;
begin
  select * into a from app.activities where id = p_id and deleted_at is null;
  if not found or not app.visible(a.owner_id, a.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if a.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others';
  end if;
  delete from app.activity_reminders where activity_id = p_id and fired_at is null;
  insert into app.activity_reminders (activity_id, channel, offset_min)
  select p_id, r ->> 'channel', (r ->> 'offset_min')::int from jsonb_array_elements(coalesce(p_reminders, '[]'::jsonb)) r
  on conflict do nothing;
  perform app.log('activity.reminders_set', 'activity', p_id::text, jsonb_build_object('count', jsonb_array_length(coalesce(p_reminders, '[]'::jsonb))));
  return coalesce((select jsonb_agg(jsonb_build_object('channel', channel, 'offset_min', offset_min)) from app.activity_reminders where activity_id = p_id), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
-- tickets (tickets R-2): a staff member changes a ticket only in a queue they may see, and only moves it to
-- one they may see. Writes the platform makes itself (intake, SLA clocks) have no staff member and pass.
create function app.ticket_queue_guard() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if app.me() is null then return new; end if;
  if not app.queue_ok(old.queue_key) or (new.queue_key is distinct from old.queue_key and not app.queue_ok(new.queue_key)) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'queue';
  end if;
  return new;
end $fn$;
create trigger tickets_queue_guard before update on app.tickets for each row execute function app.ticket_queue_guard();

create or replace function public.ticket_link(p_id uuid, p_kind text, p_ref text, p_label text default null, p_on boolean default true) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); t app.tickets;
begin
  select * into t from app.tickets where id = p_id and deleted_at is null;
  if not found or not app.queue_ok(t.queue_key) or not app.visible(t.owner_id, t.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.assignee_id is distinct from v_me and t.owner_id is distinct from v_me and not app.can('tickets', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'tickets:edit_others';
  end if;
  if p_on then insert into app.ticket_links (ticket_id, kind, ref, label, created_by) values (p_id, p_kind, p_ref, p_label, v_me) on conflict do nothing;
  else delete from app.ticket_links where ticket_id = p_id and kind = p_kind and ref = p_ref; end if;
  perform app.log('ticket.linked', 'ticket', p_id::text, jsonb_build_object('kind', p_kind, 'on', p_on));
  return jsonb_build_object('ok', true);
end $fn$;

-- an executed action as a line in the thread (tickets R-1): the actor, the action and the outcome — no
-- free text from the caller. The body holds «<action>:<ok|failed>»; the screen words it.
create function public.ticket_action_note(p_id uuid, p_action text, p_ok boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); t app.tickets; v_id uuid;
begin
  if coalesce(p_action, '') !~ '^[a-z_]+\.[a-z_]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'action'; end if;
  select * into t from app.tickets where id = p_id and deleted_at is null;
  if not found or not app.queue_ok(t.queue_key) or not app.visible(t.owner_id, t.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  -- the action must have been run by this staff member just now, as the audit records it
  if not exists (select 1 from app.audit a where a.staff_id = v_me and a.action in (p_action, 'customer.' || split_part(p_action, '.', 2)) and a.at > now() - interval '10 minutes') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'not_run';
  end if;
  insert into app.ticket_messages (ticket_id, kind, author_staff_id, body) values (p_id, 'admin_action', v_me, p_action || ':' || case when p_ok then 'ok' else 'failed' end)
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $fn$;

-- reports compare like with like, and CSAT counts answered surveys only (tickets R-3, R-6)
create or replace function public.ticket_reports(p_days integer default 30, p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_from timestamptz := now() - make_interval(days => least(greatest(coalesce(p_days, 30), 1), 365));
begin
  perform app.require('tickets', 'reports_others');
  return (with t as (select * from app.tickets x where x.created_at >= v_from and x.deleted_at is null and not x.is_sample
                     and (p_product is null or p_product = 'all' or x.product = p_product))
    select jsonb_build_object(
      'created', (select count(*) from t),
      'previous', (select count(*) from app.tickets x where x.created_at >= v_from - (now() - v_from) and x.created_at < v_from and x.deleted_at is null and not x.is_sample
                     and (p_product is null or p_product = 'all' or x.product = p_product)),
      'median_first_response_min', (select percentile_cont(0.5) within group (order by app.business_minutes(created_at, first_response_at)) from t where first_response_at is not null),
      'median_resolution_min', (select percentile_cont(0.5) within group (order by app.business_minutes(created_at, resolved_at)) from t where resolved_at is not null),
      'due', (select count(*) from t where first_response_due_at < now()),
      'met', (select count(*) from t where first_response_due_at < now() and first_response_at is not null and first_response_at <= first_response_due_at
                and (resolved_at is null or resolution_due_at is null or resolved_at <= resolution_due_at)),
      'resolved', (select count(*) from t where resolved_at is not null),
      'reopened', (select count(*) from t where reopened_count > 0),
      'csat_avg', (select round(avg(csat_score)::numeric, 1) from t where csat_score is not null and csat_at is not null),
      'csat_requested', (select count(*) from t where csat_requested_at is not null),
      'csat_answered', (select count(*) from t where csat_at is not null),
      'by_category', coalesce((select jsonb_agg(jsonb_build_object('key', category_key, 'trial', trial, 'customer', customer) order by trial + customer desc) from (
          select category_key, count(*) filter (where org_stage_at_open = 'trial') trial, count(*) filter (where org_stage_at_open <> 'trial' or org_stage_at_open is null) customer
          from t group by category_key) c), '[]'::jsonb),
      'frt_by_priority', coalesce((select jsonb_object_agg(priority, m) from (
          select priority, percentile_cont(0.5) within group (order by app.business_minutes(created_at, first_response_at)) m from t where first_response_at is not null group by priority) p), '{}'::jsonb)));
end $fn$;

-- the help centre's ticket-to-article rate: the share of the last 30 days' tickets linked to an article (tickets R-5)
create or replace function public.help_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_sandbox boolean;
begin
  perform app.require('tickets', 'see');
  v_sandbox := (select sandbox from app.admins where id = app.me());
  return jsonb_build_object(
    'articles', coalesce((select jsonb_agg(to_jsonb(a) - 'body' || jsonb_build_object(
        'views', (select coalesce(sum(views), 0) from app.help_article_stats_daily s where s.article_id = a.id and s.day > current_date - 30),
        'deflected', (select coalesce(sum(deflections), 0) from app.help_article_stats_daily s where s.article_id = a.id and s.day > current_date - 30)) order by a.updated_at desc)
      from app.help_articles a where v_sandbox or not a.is_sample), '[]'::jsonb),
    'gaps', coalesce((select jsonb_agg(jsonb_build_object('topic', g.topic, 'count', g.n) order by g.n desc) from (
        select t.topic, count(*) n from app.tickets t where t.topic is not null and t.created_at > now() - interval '30 days' and t.deleted_at is null
          and not exists (select 1 from app.help_articles a where a.status = 'published' and lower(a.title) like '%' || lower(t.topic) || '%')
        group by t.topic order by n desc limit 5) g), '[]'::jsonb),
    'article_rate', (select case when count(*) = 0 then null
                                 else round(100.0 * count(*) filter (where exists (select 1 from app.ticket_links l where l.ticket_id = t.id and l.kind = 'article')) / count(*), 1) end
                     from app.tickets t where t.created_at > now() - interval '30 days' and t.deleted_at is null and (v_sandbox or not t.is_sample)));
end $fn$;

-- ---------------------------------------------------------------------------
-- activities and scheduling
-- the calendar choice, stored before any provider is connected (activities R-ACT-01)
create function public.calendar_connection_save(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  if p_values ? 'provider' and p_values ->> 'provider' not in ('google', 'microsoft') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider'; end if;
  if p_values ? 'mode' and p_values ->> 'mode' not in ('one_way', 'two_way') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mode'; end if;
  if jsonb_typeof(p_values -> 'sync_type_ids') = 'array' and exists (select 1 from jsonb_array_elements_text(p_values -> 'sync_type_ids') x
                                                                     where not exists (select 1 from app.activity_types t where t.id::text = x)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sync_type_ids';
  end if;
  insert into app.calendar_connections (staff_id, provider, mode, calendar_id, sync_type_ids)
  values (v_me, coalesce(p_values ->> 'provider', 'google'), coalesce(p_values ->> 'mode', 'two_way'), left(p_values ->> 'calendar_id', 200),
          coalesce(array(select x::uuid from jsonb_array_elements_text(p_values -> 'sync_type_ids') x), '{}'))
  on conflict (staff_id) do update set
    provider = coalesce(p_values ->> 'provider', app.calendar_connections.provider),
    mode = coalesce(p_values ->> 'mode', app.calendar_connections.mode),
    calendar_id = case when p_values ? 'calendar_id' then left(p_values ->> 'calendar_id', 200) else app.calendar_connections.calendar_id end,
    sync_type_ids = case when jsonb_typeof(p_values -> 'sync_type_ids') = 'array' then array(select x::uuid from jsonb_array_elements_text(p_values -> 'sync_type_ids') x)
                         else app.calendar_connections.sync_type_ids end;
  perform app.log('calendar.saved', 'staff', v_me::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return (select to_jsonb(c) - 'staff_id' - 'vault_secret_id' from app.calendar_connections c where c.staff_id = v_me);
end $fn$;

-- proposed times on a booking link (activities R-ACT-02): at most ten, in the future
alter table app.booking_links add column proposed_times timestamptz[] not null default '{}' check (cardinality(proposed_times) <= 10);

create or replace function public.booking_link_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_id uuid; v_times timestamptz[];
begin
  if jsonb_typeof(p_values -> 'proposed_times') = 'array' then
    v_times := array(select x::timestamptz from jsonb_array_elements_text(p_values -> 'proposed_times') x order by 1);
    if cardinality(v_times) > 10 or exists (select 1 from unnest(v_times) t where t <= now()) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'proposed_times';
    end if;
  end if;
  if p_id is null then
    insert into app.booking_links (staff_id, slug, kind, title, description, duration_min, video_provider, person_id, deal_id, expires_at, proposed_times)
    values (v_me, coalesce(nullif(p_values ->> 'slug', ''), substr(md5(random()::text), 1, 10)), coalesce(p_values ->> 'kind', 'general'),
            btrim(p_values ->> 'title'), p_values ->> 'description', coalesce((p_values ->> 'duration_min')::int, 30), p_values ->> 'video_provider',
            (p_values ->> 'person_id')::uuid, (p_values ->> 'deal_id')::uuid, (p_values ->> 'expires_at')::timestamptz, coalesce(v_times, '{}'))
    returning id into v_id;
  else
    update app.booking_links set title = coalesce(nullif(btrim(p_values ->> 'title'), ''), title), description = coalesce(p_values ->> 'description', description),
      duration_min = coalesce((p_values ->> 'duration_min')::int, duration_min), active = coalesce((p_values ->> 'active')::boolean, active),
      proposed_times = coalesce(v_times, proposed_times)
    where id = p_id and staff_id = v_me returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('booking_link.saved', 'booking_link', v_id::text);
  return jsonb_build_object('id', v_id);
end $fn$;

-- bookings name the organisation of the booked person (activities R-ACT-04)
create or replace function public.my_scheduling() returns jsonb
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
    'bookings', coalesce((select jsonb_agg(jsonb_build_object('name', coalesce(b.name, p.name), 'organization', o.name, 'starts_at', b.starts_at, 'link', l.title,
                                                              'created_at', b.created_at) order by b.created_at desc)
                          from app.bookings b join app.booking_links l on l.id = b.link_id left join app.people p on p.id = b.person_id
                          left join app.organizations o on o.id = p.organization_id
                          where l.staff_id = v_me and b.cancelled_at is null), '[]'::jsonb));
end $fn$;

-- move activities by whole days, keeping each one's time of day, in one transaction (activities R-ACT-05)
create function public.activities_shift(p_ids uuid[], p_days int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); x uuid; n int := 0; a app.activities;
begin
  if p_days is null or p_days not between -365 and 365 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'days'; end if;
  if cardinality(p_ids) > 1 then perform app.require('deals', 'bulk'); end if;
  if cardinality(p_ids) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  foreach x in array coalesce(p_ids, '{}') loop
    select * into a from app.activities where id = x and deleted_at is null and starts_at is not null;
    continue when not found or not app.visible(a.owner_id, a.visibility);
    perform public.rec_save('activity', x, jsonb_build_object('starts_at', a.starts_at + make_interval(days => p_days)), null, null, 'ui');
    n := n + 1;
  end loop;
  return jsonb_build_object('moved', n);
end $fn$;

-- ---------------------------------------------------------------------------
-- lists: OR groups, and a deal's idle days, in the filter syntax (deals R-DEALS-02)
--   {or: [[filter, …], [filter, …]]}: each inner list ANDed, the lists ORed
--   {f: 'idle_days', op, v} on deals: whole days since the last activity, or since entering the stage
create or replace function app.filter_sql(e app.entities, p_filters jsonb) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  x jsonb; f text; op text; v jsonb; kind text; col text; out text := ''; ftype text; g jsonb; parts text[];
begin
  if p_filters is null or jsonb_typeof(p_filters) <> 'array' then return ''; end if;
  for x in select * from jsonb_array_elements(p_filters) loop
    if jsonb_typeof(x -> 'or') = 'array' then
      parts := '{}';
      for g in select * from jsonb_array_elements(x -> 'or') loop
        if jsonb_typeof(g) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.or'; end if;
        parts := parts || ('(true' || app.filter_sql(e, g) || ')');
      end loop;
      if cardinality(parts) > 0 then out := out || ' and (' || array_to_string(parts, ' or ') || ')'; end if;
      continue;
    end if;
    f := x ->> 'f'; op := coalesce(x ->> 'op', 'eq'); v := x -> 'v';
    if f = 'idle_days' and e.key = 'deal' then
      col := 'floor(extract(epoch from now() - coalesce(t.last_activity_at, t.stage_entered_at)) / 86400)';
      kind := 'numeric';
    elsif f like 'custom.%' then
      select type into ftype from app.fields where entity = e.key and key = substr(f, 8) and archived_at is null;
      if ftype is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.' || f; end if;
      col := format('(t.custom ->> %L)', substr(f, 8));
      kind := case when ftype in ('numerical') then 'numeric' when ftype = 'date' then 'date' else 'text' end;
      if kind <> 'text' then col := format('(%s)::%s', col, kind); end if;
      if ftype = 'multiple_options' then
        col := format('(t.custom -> %L)', substr(f, 8)); kind := 'jsonb';
      end if;
    else
      select c.kind into kind from app.entity_columns c where c.entity = e.key and c.col = f;
      if kind is null then
        kind := case f when 'owner_id' then 'uuid' when 'visibility' then 'text' when 'labels' then 'uuid[]'
                       when 'created_at' then 'timestamptz' when 'updated_at' then 'timestamptz' when 'created_by' then 'uuid'
                       when 'id' then 'uuid' else null end;
        if kind is null or (f in ('owner_id', 'visibility') and not e.owned) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.' || f;
        end if;
      end if;
      col := format('t.%I', f);
    end if;
    out := out || ' and ' || case op
      when 'eq' then format('%s = %s', col, app.lit(v, kind))
      when 'neq' then format('%s is distinct from %s', col, app.lit(v, kind))
      when 'in' then format('%s = any (%s)', col, app.lit(v, case when kind like '%[]' then kind else kind || '[]' end))
      when 'nin' then format('not (%s = any (%s))', col, app.lit(v, case when kind like '%[]' then kind else kind || '[]' end))
      when 'contains' then format('%s::text ilike %L', col, '%' || replace(replace(v #>> '{}', '%', '\%'), '_', '\_') || '%')
      when 'gt' then format('%s > %s', col, app.lit(v, kind))
      when 'gte' then format('%s >= %s', col, app.lit(v, kind))
      when 'lt' then format('%s < %s', col, app.lit(v, kind))
      when 'lte' then format('%s <= %s', col, app.lit(v, kind))
      when 'empty' then case when kind like '%[]' then format('coalesce(cardinality(%s), 0) = 0', col) else format('(%s is null or %s::text = %L)', col, col, '') end
      when 'notempty' then case when kind like '%[]' then format('cardinality(%s) > 0', col) else format('(%s is not null and %s::text <> %L)', col, col, '') end
      when 'has' then case when kind = 'jsonb' then format('%s ?| array(select jsonb_array_elements_text(%L::jsonb))', col, v::text)
                           else format('%s && %s', col, app.lit(v, kind)) end
      when 'within_days' then format('%s >= now() - make_interval(days => %s)', col, (v #>> '{}')::int)
      else null end;
    if out is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.op'; end if;
  end loop;
  return out;
end $fn$;

-- the deal list sorts by organisation, owner and labels too (deals R-DEALS-01)
create or replace function public.deal_list(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  e app.entities := app.entity('deal');
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_where text; v_rows jsonb; v_total bigint; v_order text := ''; v_dir text;
  s jsonb;
begin
  v_where := format('where %s and %s', case when (q ->> 'trash')::boolean then 't.deleted_at is not null'
                                             when (q ->> 'archived')::boolean then 't.deleted_at is null and t.archived_at is not null'
                                             else 't.deleted_at is null and t.archived_at is null' end, app.vis_sql(e));
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  if q ? 'pipeline_id' then v_where := v_where || format(' and t.pipeline_id = %L', (q ->> 'pipeline_id')::uuid); end if;
  if q ->> 'status' in ('open', 'won', 'lost') then v_where := v_where || format(' and t.status = %L', q ->> 'status'); end if;
  if btrim(coalesce(q ->> 'q', '')) <> '' then v_where := v_where || format(' and t.title ilike %L', '%' || replace(replace(btrim(q ->> 'q'), '%', '\%'), '_', '\_') || '%'); end if;
  v_where := v_where || app.filter_sql(e, q -> 'filters');
  for s in select * from jsonb_array_elements(coalesce(q -> 'sort', '[{"f":"value","dir":"desc"}]'::jsonb)) loop
    v_dir := case when s ->> 'dir' = 'asc' then 'asc' else 'desc' end;
    if s ->> 'f' = 'stage' then
      v_order := v_order || format('(select st.probability from app.stages st where st.id = t.stage_id) %s, ', v_dir);
    elsif s ->> 'f' = 'organization' then
      v_order := v_order || format('(select o.name from app.organizations o where o.id = t.organization_id) %s nulls last, ', v_dir);
    elsif s ->> 'f' = 'owner' then
      v_order := v_order || format('(select a.name from app.admins a where a.id = t.owner_id) %s nulls last, ', v_dir);
    elsif s ->> 'f' = 'labels' then
      v_order := v_order || format('(select min(l.name) from app.labels l where l.id = any (t.labels)) %s nulls last, ', v_dir);
    elsif exists (select 1 from app.entity_columns c where c.entity = 'deal' and c.col = s ->> 'f') or s ->> 'f' in ('created_at', 'updated_at') then
      v_order := v_order || format('t.%I %s nulls last, ', s ->> 'f', v_dir);
    else
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sort';
    end if;
  end loop;
  execute format('select count(*) from app.deals t %s', v_where) into v_total;
  execute format('select coalesce(jsonb_agg(x.c order by x.n), ''[]''::jsonb) from (select app.deal_card(t) c, row_number() over (order by %s t.seq) n from app.deals t %s order by 2 limit %s offset %s) x',
                 v_order, v_where, least(greatest(coalesce((q ->> 'limit')::int, 100), 1), 500), greatest(coalesce((q ->> 'offset')::int, 0), 0)) into v_rows;
  perform app.log('record.listed', 'deal', null, jsonb_build_object('count', jsonb_array_length(v_rows), 'view', 'list'));
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $fn$;

-- «Convert back to lead» (deals R-DEALS-03): a lead from the deal; the deal's activities and notes follow
-- it, and the deal is archived
create function public.deal_to_lead(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); d app.deals; r jsonb; v_lead uuid;
begin
  perform app.require_module('leads');
  select * into d from app.deals where id = p_id and deleted_at is null for update;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if d.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others';
  end if;
  if d.person_id is null and d.organization_id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'person_or_organization'; end if;
  r := public.rec_save('lead', null, jsonb_strip_nulls(jsonb_build_object('title', d.title, 'person_id', d.person_id, 'organization_id', d.organization_id,
                                                                          'value', nullif(d.value, 0), 'currency', d.currency, 'source', d.source, 'owner_id', d.owner_id)));
  v_lead := (r ->> 'id')::uuid;
  update app.activities set lead_id = v_lead where deal_id = p_id and deleted_at is null;
  update app.notes set entity = 'lead', record_id = v_lead where entity = 'deal' and record_id = p_id;
  update app.deals set archived_at = now(), version = version + 1, updated_at = now(), updated_by = v_me where id = p_id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('deal', p_id, 'archived_at', 'null'::jsonb, to_jsonb(now()), v_me, 'ui'), ('lead', v_lead, 'converted_from_deal', null, to_jsonb(p_id), v_me, 'ui');
  perform app.emit('deal.converted_to_lead', 'deal', p_id, jsonb_build_object('lead', v_lead), d.is_sample);
  perform app.log('deal.converted_to_lead', 'deal', p_id::text, jsonb_build_object('lead', v_lead));
  return jsonb_build_object('lead_id', v_lead);
end $fn$;

-- lead numbers, as the design writes them (L-501) (contacts R-4)
alter table app.leads add column seq bigint generated always as identity (start with 501) unique;
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values ('lead', 'seq', 'int', false, false, null, 11);

-- ---------------------------------------------------------------------------
-- settings
-- the record-type registry (settings R-SETTINGS-04)
create function public.entities_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('key', e.key, 'scope', e.scope, 'module', e.module, 'owned', e.owned, 'ord', e.ord,
                                                       'module_on', e.module is null or app.module_on(e.module)) order by e.ord)
                   from app.entities e), '[]'::jsonb);
end $fn$;

-- a field key stays taken by its archived field; say so instead of a bare unique violation (settings R-SETTINGS-05)
create function app.field_key_free() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if exists (select 1 from app.fields f where f.entity = new.entity and f.key = new.key and f.id is distinct from new.id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
  end if;
  return new;
end $fn$;
create trigger fields_key_free before insert on app.fields for each row execute function app.field_key_free();

-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['app.ticket_queue_guard()', 'app.field_key_free()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.ticket_action_note(uuid, text, boolean)', 'public.calendar_connection_save(jsonb)', 'public.activities_shift(uuid[], int)',
                           'public.deal_to_lead(uuid)', 'public.entities_get()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
