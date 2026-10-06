-- 0012_tickets.sql — ticketing (Appendix 2, D-20): queues, categories, SLA in business time, the thread,
-- problems and known errors, the help centre, macros, personvern requests, CSAT.
--
-- Priority is never picked: it follows impact × urgency (a generated column). SLA due times are business
-- time (Mon–Fri 08–16 Europe/Oslo, minus holidays); waiting on the customer pauses nothing (logged choice,
-- docs/crm-enrichment/DEVIATIONS.md). A ticket's messages are a person's own words: they never go into the
-- audit, an event payload or a notification — those carry ids only. Tickets get their own right scope.

-- ---------------------------------------------------------------------------
-- rights: a «tickets» scope beside deals, projects, campaigns and global
create or replace function app.right_ok(p_right text) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select split_part(p_right, ':', 1) in ('deals', 'projects', 'campaigns', 'global', 'tickets')
     and split_part(p_right, ':', 2) in ('see', 'add', 'edit_others', 'delete', 'bulk', 'export', 'configure',
                                         'workflows', 'reports_others', 'ai', 'security')
     and p_right ~ '^[a-z]+:[a-z_]+$'
$fn$;
update app.permission_sets set rights = rights || array['tickets:see', 'tickets:add', 'tickets:edit_others', 'tickets:reports_others', 'tickets:export', 'tickets:ai'] where key = 'support';
update app.permission_sets set rights = rights || array['tickets:see', 'tickets:add'] where key in ('sales', 'finance');
update app.permission_sets set rights = rights || array['tickets:see', 'tickets:reports_others'] where key = 'analyst';

-- ---------------------------------------------------------------------------
create table app.ticket_queues (
  key                text primary key check (key ~ '^[a-z_]{2,30}$'),
  name               text not null,
  ord                int not null default 0,
  permission_set_ids uuid[]               -- null: everyone with tickets:see
);
insert into app.ticket_queues (key, name, ord) values ('support', 'Support', 10), ('billing', 'Billing', 20), ('sales', 'Sales', 30), ('personvern', 'Personvern', 40);
update app.ticket_queues set permission_set_ids = array(select id from app.permission_sets where key in ('admin', 'support')) where key = 'personvern';

create table app.ticket_categories (
  key       text primary key check (key ~ '^[a-z_]{2,40}$'),
  name      text not null,
  queue_key text not null references app.ticket_queues (key),
  ord       int not null default 0,
  active    boolean not null default true
);
insert into app.ticket_categories (key, name, queue_key, ord) values
  ('survey_delivery', 'Survey delivery', 'support', 10), ('getting_started', 'Getting started', 'support', 20), ('billing', 'Billing', 'billing', 30),
  ('results_anonymity', 'Results and anonymity', 'support', 40), ('sales', 'Sales', 'sales', 50), ('personvern', 'Personvern request', 'personvern', 60),
  ('bug', 'Bug', 'support', 70), ('tiltak', 'Tiltak', 'support', 80), ('feature_request', 'Feature request', 'support', 90);

create table app.ticket_sla_policies (
  priority           text primary key check (priority in ('urgent', 'high', 'normal', 'low')),
  first_response_min int not null check (first_response_min > 0),
  resolution_min     int not null check (resolution_min > 0),
  ord                int not null
);
-- business minutes (a business day is 8 hours, 08–16)
insert into app.ticket_sla_policies values ('urgent', 240, 960, 10), ('high', 480, 2400, 20), ('normal', 960, 4800, 30), ('low', 2400, 9600, 40);

create table app.business_hours (
  dow    smallint primary key check (dow between 1 and 7),   -- ISO: 1 = Monday
  opens  time not null,
  closes time not null,
  check (closes > opens)
);
insert into app.business_hours values (1, '08:00', '16:00'), (2, '08:00', '16:00'), (3, '08:00', '16:00'), (4, '08:00', '16:00'), (5, '08:00', '16:00');

create table app.holidays (day date primary key, name text not null);

-- a time plus business minutes, in Europe/Oslo business hours
create function app.business_add(p_from timestamptz, p_minutes int) returns timestamptz
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_local timestamp := p_from at time zone 'Europe/Oslo';
  v_left int := greatest(p_minutes, 0);
  h app.business_hours; v_open timestamp; v_close timestamp; v_avail int; i int := 0;
begin
  loop
    i := i + 1;
    if i > 800 then return null; end if;
    select * into h from app.business_hours where dow = extract(isodow from v_local)::int;
    if found and not exists (select 1 from app.holidays where day = v_local::date) then
      v_open := v_local::date + h.opens; v_close := v_local::date + h.closes;
      if v_local < v_open then v_local := v_open; end if;
      if v_local < v_close then
        v_avail := floor(extract(epoch from v_close - v_local) / 60);
        if v_left <= v_avail then return (v_local + make_interval(mins => v_left)) at time zone 'Europe/Oslo'; end if;
        v_left := v_left - v_avail;
      end if;
    end if;
    v_local := (v_local::date + 1)::timestamp;
  end loop;
end $fn$;

-- business minutes between two times
create function app.business_minutes(p_from timestamptz, p_to timestamptz) returns int
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_a timestamp := p_from at time zone 'Europe/Oslo'; v_b timestamp := p_to at time zone 'Europe/Oslo';
  d date; h app.business_hours; total numeric := 0; s timestamp; e timestamp;
begin
  if p_to <= p_from then return 0; end if;
  d := v_a::date;
  while d <= v_b::date and d - v_a::date < 400 loop
    select * into h from app.business_hours where dow = extract(isodow from d)::int;
    if found and not exists (select 1 from app.holidays where day = d) then
      s := greatest(v_a, d + h.opens); e := least(v_b, d + h.closes);
      if e > s then total := total + extract(epoch from e - s) / 60; end if;
    end if;
    d := d + 1;
  end loop;
  return floor(total);
end $fn$;

create function app.ticket_priority(p_impact text, p_urgency text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case
    when p_impact = 'many_orgs' and p_urgency = 'blocking' then 'urgent'
    when p_impact = 'many_orgs' or p_urgency = 'blocking' then 'high'
    when p_impact = 'one_org' then 'normal'
    else 'low' end
$fn$;

-- ---------------------------------------------------------------------------
create table app.tickets (
  id                    uuid primary key default gen_random_uuid(),
  number                bigint generated always as identity (start with 2300) unique,
  type                  text not null default 'question' check (type in ('question', 'service_request', 'incident', 'problem')),
  category_key          text not null references app.ticket_categories (key),
  queue_key             text not null references app.ticket_queues (key),
  status                text not null default 'new' check (status in ('new', 'open', 'waiting_customer', 'waiting_us', 'resolved', 'closed')),
  impact                text not null default 'one_user' check (impact in ('one_user', 'one_org', 'many_orgs')),
  urgency               text not null default 'not_blocking' check (urgency in ('not_blocking', 'blocking')),
  priority              text generated always as (app.ticket_priority(impact, urgency)) stored,
  subject               text not null check (char_length(btrim(subject)) between 1 and 200),
  organization_id       uuid references app.organizations (id) on delete set null,
  person_id             uuid references app.people (id) on delete set null,
  requester_email       text check (requester_email is null or char_length(requester_email) <= 254),
  product               text references app.products (key),
  channel               text not null default 'staff' check (channel in ('in_app', 'email', 'contact_form', 'staff')),
  assignee_id           uuid references app.admins (id) on delete set null,
  problem_id            uuid references app.tickets (id) on delete set null,
  problem_status        text check (problem_status is null or problem_status in ('investigating', 'known_error', 'resolved')),
  root_cause            text check (root_cause is null or char_length(root_cause) <= 2000),
  workaround            text check (workaround is null or char_length(workaround) <= 2000),
  status_banner         boolean not null default false,
  topic                 text check (topic is null or char_length(topic) <= 80),
  context               jsonb not null default '{}'::jsonb check (jsonb_typeof(context) = 'object'),
  org_stage_at_open     text check (org_stage_at_open is null or org_stage_at_open in ('trial', 'customer', 'none')),
  first_response_due_at timestamptz,
  resolution_due_at     timestamptz,
  first_response_at     timestamptz,
  resolved_at           timestamptz,
  closed_at             timestamptz,
  reopened_count        int not null default 0,
  csat_score            smallint check (csat_score is null or csat_score between 1 and 5),
  csat_requested_at     timestamptz,
  csat_at               timestamptz,
  csat_token_hash       bytea,
  source_event_id       bigint references app.events_in (id) on delete set null,
  owner_id              uuid references app.admins (id) on delete set null,   -- the problem owner; for others the creator
  visibility            text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels                uuid[] not null default '{}',
  custom                jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample             boolean not null default false,
  version               int not null default 1,
  created_at            timestamptz not null default now(),
  created_by            uuid,
  updated_at            timestamptz not null default now(),
  updated_by            uuid,
  deleted_at            timestamptz,
  check ((type = 'problem') = (problem_status is not null)),
  check (problem_id is null or type <> 'problem')
);
create index tickets_open on app.tickets (queue_key, status) where deleted_at is null;
create index tickets_org on app.tickets (organization_id);
create index tickets_problem on app.tickets (problem_id);

-- SLA due times follow the priority (set on create and when impact or urgency change)
create function app.ticket_sla() returns trigger
  language plpgsql set search_path = ''
as $fn$
declare p app.ticket_sla_policies;
begin
  -- a generated column is computed after BEFORE triggers, so the priority is derived here
  select * into p from app.ticket_sla_policies where priority = app.ticket_priority(new.impact, new.urgency);
  if tg_op = 'INSERT' or app.ticket_priority(new.impact, new.urgency) is distinct from old.priority then
    new.first_response_due_at := app.business_add(new.created_at, p.first_response_min);
    new.resolution_due_at := app.business_add(new.created_at, p.resolution_min);
  end if;
  if tg_op = 'UPDATE' and old.status in ('resolved', 'closed') and new.status not in ('resolved', 'closed') then
    new.reopened_count := old.reopened_count + 1; new.resolved_at := null; new.closed_at := null;
  end if;
  if new.status = 'resolved' and new.resolved_at is null then new.resolved_at := now(); end if;
  if new.status = 'closed' and new.closed_at is null then new.closed_at := now(); new.resolved_at := coalesce(new.resolved_at, now()); end if;
  return new;
end $fn$;
create trigger ticket_sla before insert or update on app.tickets for each row execute function app.ticket_sla();

create table app.ticket_messages (
  id               uuid primary key default gen_random_uuid(),
  ticket_id        uuid not null references app.tickets (id) on delete cascade,
  kind             text not null check (kind in ('customer', 'reply', 'note', 'system', 'admin_action')),
  author_staff_id  uuid references app.admins (id) on delete set null,
  author_person_id uuid references app.people (id) on delete set null,
  body             text not null check (char_length(body) between 1 and 20000),
  macro_id         uuid,
  mentions         uuid[] not null default '{}',
  email_message_id text,
  delivery_status  text check (delivery_status is null or delivery_status in ('queued', 'sent', 'failed', 'not_configured')),
  created_at       timestamptz not null default now()
);
create index ticket_messages_ticket on app.ticket_messages (ticket_id, created_at);

create table app.ticket_links (
  ticket_id  uuid not null references app.tickets (id) on delete cascade,
  kind       text not null check (kind in ('survey', 'invoice', 'deal', 'lead', 'article')),
  ref        text not null check (char_length(ref) <= 100),
  label      text check (label is null or char_length(label) <= 200),
  created_by uuid,
  created_at timestamptz not null default now(),
  primary key (ticket_id, kind, ref)
);

create table app.privacy_requests (
  id              uuid primary key default gen_random_uuid(),
  ticket_id       uuid references app.tickets (id) on delete set null,
  organization_id uuid references app.organizations (id) on delete set null,
  kind            text not null check (kind in ('access', 'correction', 'deletion')),
  requester_category text check (requester_category is null or char_length(requester_category) <= 80),
  received_at     timestamptz not null default now(),
  due_at          timestamptz not null,
  status          text not null default 'received' check (status in ('received', 'in_progress', 'done', 'rejected')),
  owner_id        uuid references app.admins (id) on delete set null,
  closed_at       timestamptz,
  is_sample       boolean not null default false
);

-- the 30-day clock
create function app.privacy_due() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  new.due_at := new.received_at + interval '30 days';
  return new;
end $fn$;
create trigger privacy_due before insert or update of received_at on app.privacy_requests for each row execute function app.privacy_due();

create table app.help_articles (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique check (slug ~ '^[a-z0-9-]{2,80}$'),
  title        text not null check (char_length(btrim(title)) between 1 and 200),
  body         text not null default '',
  category_key text references app.ticket_categories (key),
  locale       text not null default 'nb' check (locale in ('nb', 'nn', 'en')),
  status       text not null default 'draft' check (status in ('draft', 'published')),
  version      int not null default 1,
  problem_id   uuid references app.tickets (id) on delete set null,
  published_at timestamptz,
  is_sample    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table app.help_article_stats_daily (
  article_id  uuid not null references app.help_articles (id) on delete cascade,
  day         date not null,
  views       int not null default 0,
  deflections int not null default 0,
  primary key (article_id, day)
);

create table app.ticket_macros (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(btrim(name)) between 1 and 120),
  category_key text references app.ticket_categories (key),
  active       boolean not null default true,
  is_sample    boolean not null default false,
  created_at   timestamptz not null default now()
);
create table app.ticket_macro_versions (
  macro_id     uuid not null references app.ticket_macros (id) on delete cascade,
  locale       text not null check (locale in ('nb', 'nn', 'en')),
  version      int not null,
  body         text not null check (char_length(body) between 1 and 10000),
  published_at timestamptz not null default now(),
  published_by uuid,
  primary key (macro_id, locale, version)
);
alter table app.ticket_messages add constraint ticket_messages_macro foreign key (macro_id) references app.ticket_macros (id) on delete set null;

-- ---------------------------------------------------------------------------
alter table app.entities drop constraint entities_scope_check;
alter table app.entities add constraint entities_scope_check check (scope in ('deals', 'projects', 'campaigns', 'global', 'tickets'));
insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('ticket', 'tickets', 'tickets', null, true, 'subject', array['number', 'status'], array['subject', 'number'], 40);
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('ticket', 'number', 'int', false, false, null, 1), ('ticket', 'type', 'text', true, false, null, 2), ('ticket', 'category_key', 'text', true, true, null, 3),
  ('ticket', 'queue_key', 'text', true, true, null, 4), ('ticket', 'status', 'text', true, false, null, 5), ('ticket', 'impact', 'text', true, false, null, 6),
  ('ticket', 'urgency', 'text', true, false, null, 7), ('ticket', 'priority', 'text', false, false, null, 8), ('ticket', 'subject', 'text', true, true, null, 9),
  ('ticket', 'organization_id', 'uuid', true, false, 'organization', 10), ('ticket', 'person_id', 'uuid', true, false, 'person', 11),
  ('ticket', 'product', 'text', true, false, null, 12), ('ticket', 'channel', 'text', false, false, null, 13), ('ticket', 'assignee_id', 'uuid', true, false, null, 14),
  ('ticket', 'problem_id', 'uuid', true, false, 'ticket', 15), ('ticket', 'problem_status', 'text', true, false, null, 16),
  ('ticket', 'root_cause', 'text', true, false, null, 17), ('ticket', 'workaround', 'text', true, false, null, 18), ('ticket', 'status_banner', 'boolean', true, false, null, 19),
  ('ticket', 'topic', 'text', true, false, null, 20), ('ticket', 'first_response_due_at', 'timestamptz', false, false, null, 21),
  ('ticket', 'resolution_due_at', 'timestamptz', false, false, null, 22), ('ticket', 'first_response_at', 'timestamptz', false, false, null, 23),
  ('ticket', 'resolved_at', 'timestamptz', false, false, null, 24), ('ticket', 'csat_score', 'int', false, false, null, 25),
  ('ticket', 'requester_email', 'text', true, false, null, 26);

-- may the caller work in this queue?
create function app.queue_ok(p_queue text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.can('tickets', 'see') and coalesce((select q.permission_set_ids is null
      or (select permission_set_id from app.admins where id = app.me()) = any (q.permission_set_ids)
      or (select ps.kind = 'admin' from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = app.me())
    from app.ticket_queues q where q.key = p_queue), false)
$fn$;

create function app.ticket_row(t app.tickets) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select to_jsonb(t) - 'csat_token_hash' - 'custom' || jsonb_build_object(
    'ref', 'T-' || t.number,
    'organization', (select jsonb_build_object('id', o.id, 'name', o.name, 'org_number', o.org_number, 'employees', o.employees, 'account_id', o.account_id) from app.organizations o where o.id = t.organization_id),
    'person', (select jsonb_build_object('id', p.id, 'name', p.name, 'title', p.title, 'email', p.email) from app.people p where p.id = t.person_id),
    'assignee', (select jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials) from app.admins a where a.id = t.assignee_id),
    'problem_ref', (select 'T-' || p.number from app.tickets p where p.id = t.problem_id),
    'incidents', (select count(*) from app.tickets i where i.problem_id = t.id and i.deleted_at is null),
    'responded', t.first_response_at is not null,
    'first_response_left_min', case when t.first_response_at is null then
        case when t.first_response_due_at > now() then app.business_minutes(now(), t.first_response_due_at) else -app.business_minutes(t.first_response_due_at, now()) end end,
    'first_response_used_min', case when t.first_response_at is not null then app.business_minutes(t.created_at, t.first_response_at) end,
    'resolution_left_min', case when t.resolved_at is null then
        case when t.resolution_due_at > now() then app.business_minutes(now(), t.resolution_due_at) else -app.business_minutes(t.resolution_due_at, now()) end end,
    'sla_risk', t.first_response_at is null and t.status not in ('resolved', 'closed') and t.first_response_due_at is not null
                and now() > t.created_at + (t.first_response_due_at - t.created_at) * 0.7)
$fn$;

-- the inbox: a queue view, rows and the counts for every chip
create function public.tickets_get(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('tickets', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_view text := coalesce(q ->> 'view', 'open');
  v_rows jsonb; v_counts jsonb;
begin
  with base as (
    select t.* from app.tickets t
    where t.deleted_at is null and app.queue_ok(t.queue_key) and app.visible(t.owner_id, t.visibility) and (v_sandbox or not t.is_sample)
      and (q ->> 'product' is null or q ->> 'product' = 'all' or t.product = q ->> 'product')
      and (q ->> 'organization_id' is null or t.organization_id = (q ->> 'organization_id')::uuid)
  ), r as (select b.*, app.ticket_row(b) j from base b)
  select
    coalesce((select jsonb_agg(r.j order by
                case when coalesce(q ->> 'sort', 'sla') = 'priority' then array_position(array['urgent', 'high', 'normal', 'low'], r.priority) end,
                case when coalesce(q ->> 'sort', 'sla') = 'newest' then extract(epoch from r.created_at) end desc,
                case when coalesce(q ->> 'sort', 'sla') = 'sla' then coalesce(r.first_response_due_at, r.resolution_due_at) end nulls last,
                r.number desc)
              from r where case v_view
                when 'open' then r.status not in ('resolved', 'closed')
                when 'mine' then r.assignee_id = v_me and r.status not in ('resolved', 'closed')
                when 'unassigned' then r.assignee_id is null and r.status not in ('resolved', 'closed')
                when 'sla' then (r.j ->> 'sla_risk')::boolean
                when 'closed' then r.status in ('resolved', 'closed')
                when 'problems' then r.type = 'problem'
                else r.queue_key = v_view and r.status not in ('resolved', 'closed') end
                and (btrim(coalesce(q ->> 'q', '')) = '' or r.subject ilike '%' || btrim(q ->> 'q') || '%' or ('T-' || r.number) ilike '%' || btrim(q ->> 'q') || '%'
                     or (r.j #>> '{organization,name}') ilike '%' || btrim(q ->> 'q') || '%')), '[]'::jsonb),
    jsonb_build_object(
      'open', (select count(*) from r where status not in ('resolved', 'closed')),
      'mine', (select count(*) from r where assignee_id = v_me and status not in ('resolved', 'closed')),
      'unassigned', (select count(*) from r where assignee_id is null and status not in ('resolved', 'closed')),
      'sla', (select count(*) from r where (j ->> 'sla_risk')::boolean),
      'closed', (select count(*) from r where status in ('resolved', 'closed')),
      'queues', (select coalesce(jsonb_object_agg(k.key, (select count(*) from r where r.queue_key = k.key and r.status not in ('resolved', 'closed'))), '{}'::jsonb)
                 from app.ticket_queues k where app.queue_ok(k.key)))
  into v_rows, v_counts;
  perform app.log('record.listed', 'ticket', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'counts', v_counts);
end $fn$;

-- one ticket with its thread, links and the organization's state; the read is audited (D-12)
create function public.ticket_detail(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); t app.tickets;
begin
  select * into t from app.tickets where id = p_id and deleted_at is null;
  if not found or not app.queue_ok(t.queue_key) or not app.visible(t.owner_id, t.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.recents (staff_id, entity, record_id) values (v_me, 'ticket', p_id) on conflict (staff_id, entity, record_id) do update set at = now();
  perform app.log('ticket.read', 'ticket', p_id::text, null, (select account_id from app.organizations where id = t.organization_id));
  return app.ticket_row(t) || jsonb_build_object(
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'body', m.body, 'created_at', m.created_at, 'delivery_status', m.delivery_status,
                           'author', coalesce((select name from app.admins where id = m.author_staff_id), (select name from app.people where id = m.author_person_id), t.requester_email))
                         order by m.created_at) from app.ticket_messages m where m.ticket_id = t.id), '[]'::jsonb),
    'links', coalesce((select jsonb_agg(jsonb_build_object('kind', l.kind, 'ref', l.ref, 'label', l.label)) from app.ticket_links l where l.ticket_id = t.id), '[]'::jsonb),
    'privacy', (select jsonb_build_object('id', pr.id, 'kind', pr.kind, 'due_at', pr.due_at, 'status', pr.status) from app.privacy_requests pr where pr.ticket_id = t.id),
    'subscription', (select jsonb_build_object('status', app.sub_status(s), 'trial_ends_at', s.trial_ends_at, 'plan', s.plan)
                     from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.product = coalesce(t.product, 'orgpuls')
                     join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id where o.id = t.organization_id limit 1));
end $fn$;

-- create a ticket (staff, or an intake worker through app.ticket_intake)
create function public.ticket_create(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'add'); v_cat app.ticket_categories; r jsonb; v_id uuid;
begin
  select * into v_cat from app.ticket_categories where key = p_values ->> 'category_key' and active;
  if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'category_key'; end if;
  r := public.rec_save('ticket', null, (p_values - 'description') || jsonb_build_object('queue_key', coalesce(p_values ->> 'queue_key', v_cat.queue_key),
         'type', coalesce(p_values ->> 'type', case when v_cat.key = 'personvern' then 'service_request' else 'question' end)));
  v_id := (r ->> 'id')::uuid;
  update app.tickets t set org_stage_at_open = coalesce((select case app.sub_status(s) when 'trial' then 'trial' when 'active' then 'customer' else 'none' end
      from app.organizations o join app.account_products ap on ap.account_id = o.account_id join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
      where o.id = t.organization_id order by s.confirmed_at desc nulls last limit 1), 'none') where t.id = v_id;
  if coalesce(btrim(p_values ->> 'description'), '') <> '' then
    insert into app.ticket_messages (ticket_id, kind, author_staff_id, body) values (v_id, 'note', v_me, btrim(p_values ->> 'description'));
  end if;
  if v_cat.key = 'personvern' then
    insert into app.privacy_requests (ticket_id, organization_id, kind, owner_id, is_sample)
    select v_id, t.organization_id, coalesce(p_values ->> 'privacy_kind', 'access'), v_me, t.is_sample from app.tickets t where t.id = v_id;
  end if;
  perform app.emit('ticket.created', 'ticket', v_id, jsonb_build_object('queue', coalesce(p_values ->> 'queue_key', v_cat.queue_key)));
  return r || jsonb_build_object('ref', 'T-' || (select number from app.tickets where id = v_id), 'queue_key', (select queue_key from app.tickets where id = v_id));
end $fn$;

-- reply to the customer, or write an internal note. A reply sets the first response; the status after
-- sending is the agent's choice. Sending the e-mail is the mail worker's job (D-07): until the provider is
-- configured the message is stored with delivery_status «not_configured».
create function public.ticket_message(p_id uuid, p_kind text, p_body text, p_after text default null, p_macro uuid default null, p_mentions uuid[] default '{}')
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); t app.tickets; v_msg uuid;
begin
  if p_kind not in ('reply', 'note') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  select * into t from app.tickets where id = p_id and deleted_at is null for update;
  if not found or not app.queue_ok(t.queue_key) or not app.visible(t.owner_id, t.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.assignee_id is distinct from v_me and t.owner_id is distinct from v_me and not app.can('tickets', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'tickets:edit_others';
  end if;
  insert into app.ticket_messages (ticket_id, kind, author_staff_id, body, macro_id, mentions, delivery_status)
  values (p_id, p_kind, v_me, btrim(p_body), p_macro, coalesce(p_mentions, '{}'), case when p_kind = 'reply' then 'not_configured' end)
  returning id into v_msg;
  if p_kind = 'reply' then
    update app.tickets set first_response_at = coalesce(first_response_at, now()),
      status = case when p_after in ('waiting_customer', 'resolved', 'open', 'waiting_us', 'closed') then p_after when status = 'new' then 'open' else status end,
      assignee_id = coalesce(assignee_id, v_me), version = version + 1, updated_at = now(), updated_by = v_me
    where id = p_id;
    perform app.emit('ticket.replied', 'ticket', p_id, jsonb_build_object('message', v_msg), t.is_sample);
  else
    perform app.notify(m, 'mention', 'mention', jsonb_build_object('actor', (select name from app.admins where id = v_me), 'record', 'T-' || t.number, 'excerpt', ''),
                       '/tickets?ticket=' || p_id, 'ticket', p_id)
    from unnest(coalesce(p_mentions, '{}')) m where m <> v_me;
  end if;
  insert into app.changelog (entity, record_id, field, new_value, actor_id) values ('ticket', p_id, '*' || p_kind, jsonb_build_object('message', v_msg), v_me);
  perform app.log(case p_kind when 'reply' then 'ticket.replied' else 'ticket.noted' end, 'ticket', p_id::text, jsonb_build_object('message', v_msg),
                  (select account_id from app.organizations where id = t.organization_id));
  return jsonb_build_object('id', v_msg);
end $fn$;

create function public.ticket_link(p_id uuid, p_kind text, p_ref text, p_label text default null, p_on boolean default true) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); t app.tickets;
begin
  select * into t from app.tickets where id = p_id and deleted_at is null;
  if not found or not app.queue_ok(t.queue_key) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_on then insert into app.ticket_links (ticket_id, kind, ref, label, created_by) values (p_id, p_kind, p_ref, p_label, v_me) on conflict do nothing;
  else delete from app.ticket_links where ticket_id = p_id and kind = p_kind and ref = p_ref; end if;
  perform app.log('ticket.linked', 'ticket', p_id::text, jsonb_build_object('kind', p_kind, 'on', p_on));
  return jsonb_build_object('ok', true);
end $fn$;

-- resolving a problem resolves its open incidents with a message and asks for CSAT on each
create function public.problem_resolve(p_problem uuid, p_body text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others'); p app.tickets; i record; n int := 0;
begin
  select * into p from app.tickets where id = p_problem and type = 'problem' and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.tickets set problem_status = 'resolved', status = 'resolved', version = version + 1, updated_at = now(), updated_by = v_me where id = p_problem;
  for i in select id from app.tickets where problem_id = p_problem and status not in ('resolved', 'closed') and deleted_at is null loop
    perform public.ticket_message(i.id, 'reply', p_body, 'resolved');
    n := n + 1;
  end loop;
  perform app.log('problem.resolved', 'ticket', p_problem::text, jsonb_build_object('incidents', n));
  perform app.emit('problem.resolved', 'ticket', p_problem, jsonb_build_object('incidents', n));
  return jsonb_build_object('notified', n);
end $fn$;

-- intake from product events (D-20): support.requested → ticket; contact.submitted → ticket (and a lead,
-- added with phase 5's capture); the event's payload is the requester's own message, stored in the thread
create function app.ticket_intake(p_event bigint) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.events_in; v_id uuid; v_org uuid; v_cat text; v_queue text;
begin
  select * into e from app.events_in where id = p_event;
  if not found or e.kind not in ('support.requested', 'contact.submitted') then return null; end if;
  if exists (select 1 from app.tickets where source_event_id = p_event) then return null; end if;
  select o.id into v_org from app.organizations o join app.account_products ap on ap.account_id = o.account_id
  where ap.product = e.product and ap.tenant_id = e.tenant_id and o.deleted_at is null limit 1;
  v_cat := coalesce((select key from app.ticket_categories where key = e.payload ->> 'category' and active), case e.kind when 'contact.submitted' then 'sales' else 'getting_started' end);
  v_queue := (select queue_key from app.ticket_categories where key = v_cat);
  insert into app.tickets (type, category_key, queue_key, subject, organization_id, requester_email, product, channel, context, source_event_id, org_stage_at_open)
  values ('question', v_cat, v_queue, left(coalesce(nullif(btrim(e.payload ->> 'subject'), ''), e.kind), 200), v_org, left(e.payload ->> 'email', 254), e.product,
          case e.kind when 'contact.submitted' then 'contact_form' else 'in_app' end,
          jsonb_strip_nulls(jsonb_build_object('role', e.payload ->> 'role', 'page', e.payload ->> 'page', 'browser', e.payload ->> 'browser', 'app_version', e.payload ->> 'app_version')),
          p_event, 'none')
  returning id into v_id;
  if coalesce(btrim(e.payload ->> 'message'), '') <> '' then
    insert into app.ticket_messages (ticket_id, kind, body) values (v_id, 'customer', left(btrim(e.payload ->> 'message'), 20000));
  end if;
  insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'ticket.created', 'ticket', v_id::text, true, jsonb_build_object('event', p_event));
  return v_id;
end $fn$;

create function app.ticket_intake_trigger() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  perform app.ticket_intake(new.id);
  return new;
end $fn$;
create trigger events_in_tickets after insert on app.events_in for each row when (new.kind in ('support.requested', 'contact.submitted')) execute function app.ticket_intake_trigger();

-- the help centre, macros and the SLA configuration
create function public.help_get() returns jsonb
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
        group by t.topic order by n desc limit 5) g), '[]'::jsonb));
end $fn$;

create function public.help_article_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid;
begin
  perform app.require('tickets', 'configure');
  if p_id is null then
    insert into app.help_articles (slug, title, body, category_key, locale, problem_id)
    values (coalesce(nullif(p_values ->> 'slug', ''), substr(md5(random()::text), 1, 12)), btrim(p_values ->> 'title'), coalesce(p_values ->> 'body', ''),
            p_values ->> 'category_key', coalesce(p_values ->> 'locale', 'nb'), (p_values ->> 'problem_id')::uuid)
    returning id into v_id;
  else
    update app.help_articles set title = coalesce(nullif(btrim(p_values ->> 'title'), ''), title), body = coalesce(p_values ->> 'body', body),
      status = coalesce(p_values ->> 'status', status), published_at = case when p_values ->> 'status' = 'published' then now() else published_at end,
      version = version + case when p_values ? 'body' then 1 else 0 end, updated_at = now()
    where id = p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('article.saved', 'help_article', v_id::text, jsonb_build_object('status', p_values ->> 'status'));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.macros_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_sandbox boolean;
begin
  perform app.require('tickets', 'see');
  v_sandbox := (select sandbox from app.admins where id = app.me());
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'category_key', m.category_key,
      'used', (select count(*) from app.ticket_messages tm where tm.macro_id = m.id),
      'versions', coalesce((select jsonb_agg(jsonb_build_object('locale', v.locale, 'version', v.version, 'body', v.body, 'published_at', v.published_at) order by v.locale, v.version desc)
                            from app.ticket_macro_versions v where v.macro_id = m.id), '[]'::jsonb)) order by m.name)
    from app.ticket_macros m where m.active and (v_sandbox or not m.is_sample)), '[]'::jsonb);
end $fn$;

create function public.macro_publish(p_id uuid, p_name text, p_category text, p_locale text, p_body text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'configure'); v_id uuid := p_id; v_ver int;
begin
  if v_id is null then insert into app.ticket_macros (name, category_key) values (btrim(p_name), p_category) returning id into v_id; end if;
  select coalesce(max(version), 0) + 1 into v_ver from app.ticket_macro_versions where macro_id = v_id and locale = p_locale;
  insert into app.ticket_macro_versions (macro_id, locale, version, body, published_by) values (v_id, p_locale, v_ver, p_body, v_me);
  perform app.log('macro.published', 'macro', v_id::text, jsonb_build_object('locale', p_locale, 'version', v_ver));
  return jsonb_build_object('id', v_id, 'version', v_ver);
end $fn$;

create function public.ticket_config() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('tickets', 'see');
  return jsonb_build_object(
    'queues', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'name', name, 'allowed', app.queue_ok(key)) order by ord) from app.ticket_queues), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'name', name, 'queue_key', queue_key) order by ord) from app.ticket_categories where active), '[]'::jsonb),
    'sla', coalesce((select jsonb_agg(to_jsonb(s) order by ord) from app.ticket_sla_policies s), '[]'::jsonb),
    'hours', coalesce((select jsonb_agg(jsonb_build_object('dow', dow, 'opens', opens, 'closes', closes) order by dow) from app.business_hours), '[]'::jsonb),
    'assignees', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials) order by a.name) from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id
                           where a.active and not a.is_sample and (ps.kind = 'admin' or 'tickets:see' = any (ps.rights))), '[]'::jsonb));
end $fn$;

create function public.sla_policy_save(p_priority text, p_first_response_min int, p_resolution_min int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('tickets', 'configure');
  update app.ticket_sla_policies set first_response_min = p_first_response_min, resolution_min = p_resolution_min where priority = p_priority;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('sla.saved', 'sla', p_priority, jsonb_build_object('first_response_min', p_first_response_min, 'resolution_min', p_resolution_min));
  return jsonb_build_object('ok', true);
end $fn$;

create function public.category_route(p_category text, p_queue text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('tickets', 'configure');
  update app.ticket_categories set queue_key = p_queue where key = p_category;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('routing.saved', 'ticket_category', p_category, jsonb_build_object('queue', p_queue));
  return jsonb_build_object('ok', true);
end $fn$;

-- reports over the last 30 days (business time medians, SLA compliance, reopen rate, CSAT)
create function public.ticket_reports(p_days int default 30, p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_from timestamptz := now() - make_interval(days => least(greatest(coalesce(p_days, 30), 1), 365));
begin
  perform app.require('tickets', 'reports_others');
  return (with t as (select * from app.tickets x where x.created_at >= v_from and x.deleted_at is null and not x.is_sample
                     and (p_product is null or p_product = 'all' or x.product = p_product))
    select jsonb_build_object(
      'created', (select count(*) from t),
      'previous', (select count(*) from app.tickets x where x.created_at >= v_from - (now() - v_from) and x.created_at < v_from and x.deleted_at is null and not x.is_sample),
      'median_first_response_min', (select percentile_cont(0.5) within group (order by app.business_minutes(created_at, first_response_at)) from t where first_response_at is not null),
      'median_resolution_min', (select percentile_cont(0.5) within group (order by app.business_minutes(created_at, resolved_at)) from t where resolved_at is not null),
      'due', (select count(*) from t where first_response_due_at < now()),
      'met', (select count(*) from t where first_response_due_at < now() and first_response_at is not null and first_response_at <= first_response_due_at
                and (resolved_at is null or resolution_due_at is null or resolved_at <= resolution_due_at)),
      'resolved', (select count(*) from t where resolved_at is not null),
      'reopened', (select count(*) from t where reopened_count > 0),
      'csat_avg', (select round(avg(csat_score)::numeric, 1) from t where csat_score is not null),
      'csat_requested', (select count(*) from t where csat_requested_at is not null),
      'csat_answered', (select count(*) from t where csat_at is not null),
      'by_category', coalesce((select jsonb_agg(jsonb_build_object('key', category_key, 'trial', trial, 'customer', customer) order by trial + customer desc) from (
          select category_key, count(*) filter (where org_stage_at_open = 'trial') trial, count(*) filter (where org_stage_at_open <> 'trial' or org_stage_at_open is null) customer
          from t group by category_key) c), '[]'::jsonb),
      'frt_by_priority', coalesce((select jsonb_object_agg(priority, m) from (
          select priority, percentile_cont(0.5) within group (order by app.business_minutes(created_at, first_response_at)) m from t where first_response_at is not null group by priority) p), '{}'::jsonb)));
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['ticket_queues', 'ticket_categories', 'ticket_sla_policies', 'business_hours', 'holidays', 'tickets', 'ticket_messages', 'ticket_links',
                           'privacy_requests', 'help_articles', 'help_article_stats_daily', 'ticket_macros', 'ticket_macro_versions'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.business_add(timestamptz, int)', 'app.business_minutes(timestamptz, timestamptz)', 'app.ticket_priority(text, text)', 'app.ticket_sla()',
                           'app.queue_ok(text)', 'app.ticket_row(app.tickets)', 'app.ticket_intake(bigint)', 'app.ticket_intake_trigger()', 'app.privacy_due()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.tickets_get(jsonb)', 'public.ticket_detail(uuid)', 'public.ticket_create(jsonb)', 'public.ticket_message(uuid, text, text, text, uuid, uuid[])',
                           'public.ticket_link(uuid, text, text, text, boolean)', 'public.problem_resolve(uuid, text)', 'public.help_get()', 'public.help_article_save(uuid, jsonb)',
                           'public.macros_get()', 'public.macro_publish(uuid, text, text, text, text)', 'public.ticket_config()', 'public.sla_policy_save(text, int, int)',
                           'public.category_route(text, text)', 'public.ticket_reports(int, text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
