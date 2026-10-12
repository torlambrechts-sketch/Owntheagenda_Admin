-- 0079_dev_core.sql — Development, the core half (docs/crm-enrichment/v3/PLAN.md, wave 1, builder dev-core)
--
-- Development's records live in Sentral's database (PLAN.md decision 1). GitHub is not connected: nothing here reads or
-- writes a repository.
-- 1. Keys: each product numbers its roadmap items and work items in one sequence under its own prefix (OP-12, SK-3);
--    «sentral» is the platform's own work.
-- 2. The roadmap: outcomes in Now / Next / Later with an order, a goal and a delivery status, linked to the evidence behind
--    them (feature requests and their votes, tickets, deals, growth experiments, SEO plan items). No figure is stored:
--    votes, tickets, deals and MRR are counted when read, each under the reader's own right on its source. «Promote»
--    makes a Later item from a feature request, a winning experiment or an SEO plan item, with its evidence linked.
-- 3. The work board: work items (Story, Bug, Task, Spike; points; seven columns), sprints with dates. Committed and done
--    points are summed from the rows.
-- 4. Bug triage: bugs on Sentral's tickets and problems (0012). Severity S1–S3 sets a due time in business time from the
--    settings (S1 same business day 16:00, S2 three business days, S3 fourteen days). «Mark fixed» resolves a linked
--    problem through problem_resolve, so its open incidents get the resolution reply the person writes.
-- 5. Spec documents: RFCs with five sections and four sign-offs; a sign-off holds for the revision it was given on and
--    lapses when the spec's content changes.
-- 6. Claude (X-V3-2): three features through ai-run. Their context functions read only these records and the titles and
--    counts of what is linked — never a ticket's or a request's text, never a customer's name, never survey data. A draft
--    becomes a spec, work items or release notes only when a person uses it (dev_ai_apply).
-- Every table: app schema, RLS on, no policy, no grant. Every reader and writer: SECURITY DEFINER, search_path ''.

-- ===========================================================================
-- 1. keys
-- ===========================================================================
create table app.dev_keys (
  product  text primary key check (product ~ '^[a-z]{2,20}$'),
  prefix   text not null unique check (prefix ~ '^[A-Z]{2,4}$'),
  last_seq int not null default 0 check (last_seq >= 0)
);
insert into app.dev_keys (product, prefix) values ('orgpuls', 'OP'), ('skiftly', 'SK'), ('avvik', 'AV'), ('kurs', 'KR'), ('sentral', 'SE')
on conflict do nothing;
alter table app.dev_keys enable row level security;
revoke all on app.dev_keys from public, anon, authenticated;

-- the next number in a product's sequence; a product added later gets its first two to four letters as its prefix
create function app.dev_next_seq(p_product text) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v int; n int; v_prefix text;
begin
  update app.dev_keys set last_seq = last_seq + 1 where product = p_product returning last_seq into v;
  if v is not null then return v; end if;
  for n in 2..4 loop
    v_prefix := upper(left(regexp_replace(p_product, '[^a-z]', '', 'g'), n));
    if char_length(v_prefix) = n and not exists (select 1 from app.dev_keys k where k.prefix = v_prefix) then
      insert into app.dev_keys (product, prefix, last_seq) values (p_product, v_prefix, 0) on conflict (product) do nothing;
      update app.dev_keys set last_seq = last_seq + 1 where product = p_product returning last_seq into v;
      return v;
    end if;
  end loop;
  raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
end $fn$;

create function app.dev_key(p_product text, p_seq int) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select k.prefix from app.dev_keys k where k.product = p_product), upper(left(p_product, 2))) || '-' || p_seq
$fn$;

create function app.dev_today() returns date
  language sql stable set search_path = ''
as $fn$ select (now() at time zone 'Europe/Oslo')::date $fn$;

-- a business day: the business hours open that weekday and it is not a holiday (0012)
create function app.dev_business_day(p_day date) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from app.business_hours h where h.dow = extract(isodow from p_day)::int)
     and not exists (select 1 from app.holidays x where x.day = p_day)
$fn$;

create function app.dev_business_days(p_from date, p_to date) returns int
  language sql stable security definer set search_path = ''
as $fn$
  select count(*)::int from generate_series(p_from, least(p_to, p_from + 400), interval '1 day') d where app.dev_business_day(d::date)
$fn$;

-- ===========================================================================
-- 2. the roadmap
-- ===========================================================================
create table app.dev_roadmap_items (
  id          uuid primary key default gen_random_uuid(),
  product     text not null check (product ~ '^[a-z]{2,20}$'),
  seq         int not null check (seq >= 1),
  title       text not null check (char_length(btrim(title)) between 3 and 200),
  goal        text check (goal is null or char_length(goal) between 1 and 200),
  lane        text not null default 'later' check (lane in ('now', 'next', 'later')),
  ord         int not null default 0,
  status      text not null default 'backlog' check (status in ('backlog', 'spec', 'in_progress', 'review', 'staging', 'rollout', 'done')),
  owner_id    uuid references app.admins (id) on delete set null,
  source_kind text check (source_kind in ('feature_request', 'experiment', 'seo_plan')),
  source_ref  uuid,
  created_by  uuid references app.admins (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  archived_at timestamptz,
  version     int not null default 1,
  unique (product, seq),
  check ((source_kind is null) = (source_ref is null))
);
create unique index dev_roadmap_items_source on app.dev_roadmap_items (source_kind, source_ref) where source_kind is not null and archived_at is null;
create index dev_roadmap_items_lane on app.dev_roadmap_items (lane, ord) where archived_at is null;

create table app.dev_roadmap_links (
  item_id    uuid not null references app.dev_roadmap_items (id) on delete cascade,
  kind       text not null check (kind in ('feature_request', 'ticket', 'deal', 'experiment', 'seo_plan')),
  ref        uuid not null,
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (item_id, kind, ref)
);
create index dev_roadmap_links_ref on app.dev_roadmap_links (kind, ref);

alter table app.dev_roadmap_items enable row level security;
alter table app.dev_roadmap_links enable row level security;
revoke all on app.dev_roadmap_items, app.dev_roadmap_links from public, anon, authenticated;

-- ===========================================================================
-- 3. sprints, bugs and work items
-- ===========================================================================
create table app.dev_sprints (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  starts_on  date not null,
  ends_on    date not null,
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on >= starts_on and ends_on - starts_on <= 60)
);
create index dev_sprints_dates on app.dev_sprints (starts_on desc);

create table app.dev_bugs (
  id           uuid primary key default gen_random_uuid(),
  number       int generated always as identity unique,
  product      text not null check (product ~ '^[a-z]{2,20}$'),
  title        text not null check (char_length(btrim(title)) between 3 and 200),
  severity     text not null check (severity in ('s1', 's2', 's3')),
  source       text not null check (source in ('ticket', 'internal')),
  problem_id   uuid references app.tickets (id) on delete set null,
  assignee_id  uuid references app.admins (id) on delete set null,
  state        text not null default 'open' check (state in ('open', 'fixed', 'duplicate')),
  duplicate_of uuid references app.dev_bugs (id),
  due_at       timestamptz not null,
  fixed_at     timestamptz,
  fixed_by     uuid references app.admins (id) on delete set null,
  created_by   uuid references app.admins (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  version      int not null default 1,
  check ((state = 'fixed') = (fixed_at is not null)),
  check ((state = 'duplicate') = (duplicate_of is not null)),
  check (duplicate_of is distinct from id)
);
create index dev_bugs_open on app.dev_bugs (product, state, severity);
create index dev_bugs_problem on app.dev_bugs (problem_id) where problem_id is not null;

create table app.dev_bug_tickets (
  bug_id     uuid not null references app.dev_bugs (id) on delete cascade,
  ticket_id  uuid not null references app.tickets (id) on delete cascade,
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (bug_id, ticket_id)
);
create index dev_bug_tickets_ticket on app.dev_bug_tickets (ticket_id);

create table app.dev_work_items (
  id              uuid primary key default gen_random_uuid(),
  product         text not null check (product ~ '^[a-z]{2,20}$'),
  seq             int not null check (seq >= 1),
  kind            text not null default 'story' check (kind in ('story', 'bug', 'task', 'spike')),
  title           text not null check (char_length(btrim(title)) between 3 and 200),
  points          int check (points is null or points between 0 and 100),
  status          text not null default 'backlog' check (status in ('backlog', 'spec', 'in_progress', 'review', 'staging', 'rollout', 'done')),
  ord             int not null default 0,
  roadmap_item_id uuid references app.dev_roadmap_items (id) on delete set null,
  sprint_id       uuid references app.dev_sprints (id) on delete set null,
  assignee_id     uuid references app.admins (id) on delete set null,
  bug_id          uuid references app.dev_bugs (id) on delete set null,
  done_at         timestamptz,
  archived_at     timestamptz,
  created_by      uuid references app.admins (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         int not null default 1,
  unique (product, seq),
  check ((status = 'done') = (done_at is not null))
);
create index dev_work_items_board on app.dev_work_items (status, ord) where archived_at is null;
create index dev_work_items_roadmap on app.dev_work_items (roadmap_item_id) where roadmap_item_id is not null;
create index dev_work_items_sprint on app.dev_work_items (sprint_id) where sprint_id is not null;
create index dev_work_items_bug on app.dev_work_items (bug_id) where bug_id is not null;

alter table app.dev_sprints enable row level security;
alter table app.dev_bugs enable row level security;
alter table app.dev_bug_tickets enable row level security;
alter table app.dev_work_items enable row level security;
revoke all on app.dev_sprints, app.dev_bugs, app.dev_bug_tickets, app.dev_work_items from public, anon, authenticated;

-- ===========================================================================
-- 4. specs
-- ===========================================================================
create table app.dev_specs (
  id              uuid primary key default gen_random_uuid(),
  number          int generated always as identity unique,
  product         text not null check (product ~ '^[a-z]{2,20}$'),
  title           text not null check (char_length(btrim(title)) between 3 and 200),
  roadmap_item_id uuid references app.dev_roadmap_items (id) on delete set null,
  author_id       uuid references app.admins (id) on delete set null,
  status          text not null default 'draft' check (status in ('draft', 'in_review', 'approved')),
  problem         text check (problem is null or char_length(problem) <= 8000),
  options         text check (options is null or char_length(options) <= 8000),
  decision        text check (decision is null or char_length(decision) <= 8000),
  privacy         text check (privacy is null or char_length(privacy) <= 8000),
  rollout         text check (rollout is null or char_length(rollout) <= 8000),
  revision        int not null default 1 check (revision >= 1),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         int not null default 1
);
create unique index dev_specs_item on app.dev_specs (roadmap_item_id) where roadmap_item_id is not null;

create table app.dev_spec_signoffs (
  spec_id   uuid not null references app.dev_specs (id) on delete cascade,
  role      text not null check (role in ('product', 'engineering', 'security_privacy', 'support')),
  staff_id  uuid references app.admins (id) on delete set null,
  revision  int not null check (revision >= 1),
  signed_at timestamptz not null default now(),
  primary key (spec_id, role)
);

alter table app.dev_specs enable row level security;
alter table app.dev_spec_signoffs enable row level security;
revoke all on app.dev_specs, app.dev_spec_signoffs from public, anon, authenticated;

-- ===========================================================================
-- 5. settings: bug targets and the escaped-bug goal (the defaults are the decided values, PLAN.md)
-- ===========================================================================
insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord) values
  ('dev_target_sev_one', 'development', array['same_day', 'custom'], 'same_day', 'platform',
   'Development › Bug triage (S1: same business day 16:00; custom: business hours)', false, 'custom', 600),
  ('dev_target_sev_two', 'development', array['source_value', 'custom'], 'source_value', 'platform',
   'Development › Bug triage (S2: business days; source value 3)', false, 'custom', 610),
  ('dev_target_sev_three', 'development', array['source_value', 'custom'], 'source_value', 'platform',
   'Development › Bug triage (S3: calendar days; source value 14)', false, 'custom', 620),
  ('dev_escaped_goal', 'development', array['source_value', 'custom'], 'source_value', 'platform',
   'Development › Bug triage (bugs escaped to production per month, goal under; source value 3)', false, 'custom', 630)
on conflict (key) do nothing;

-- a setting's number when its custom option is chosen, else the source value
create function app.dev_setting_number(p_key text, p_default numeric) returns numeric
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select v.value_number from app.setting_values v join app.settings_registry r on r.key = v.key
                   where v.key = p_key and v.scope_id = '' and v.value = r.numeric_option and v.value_number is not null), p_default)
$fn$;

-- the targets in force: S1 'same_day' or a number of business hours; S2 business days; S3 calendar days
create function app.dev_targets() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    's1', case when app.setting('dev_target_sev_one') = 'custom' then to_jsonb(app.dev_setting_number('dev_target_sev_one', 8)) else to_jsonb('same_day'::text) end,
    's2', app.dev_setting_number('dev_target_sev_two', 3),
    's3', app.dev_setting_number('dev_target_sev_three', 14),
    'escaped_goal', app.dev_setting_number('dev_escaped_goal', 3))
$fn$;

-- when a bug of this severity found at this moment is due
create function app.dev_bug_due(p_from timestamptz, p_severity text) returns timestamptz
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_local timestamp := p_from at time zone 'Europe/Oslo';
  v_day date := (p_from at time zone 'Europe/Oslo')::date;
  v_left int; i int := 0;
begin
  if p_severity = 's1' then
    if app.setting('dev_target_sev_one') = 'custom' then
      return app.business_add(p_from, (app.dev_setting_number('dev_target_sev_one', 8) * 60)::int);
    end if;
    -- the same business day at 16:00; after 16:00, or on a day that is not one, the next business day's 16:00
    loop
      i := i + 1;
      exit when i > 400;
      if app.dev_business_day(v_day) and (v_day > v_local::date or v_local::time < time '16:00') then
        return (v_day + time '16:00') at time zone 'Europe/Oslo';
      end if;
      v_day := v_day + 1;
    end loop;
    return p_from + interval '1 day';
  elsif p_severity = 's2' then
    v_left := greatest(app.dev_setting_number('dev_target_sev_two', 3)::int, 0);
    while v_left > 0 and i < 800 loop
      i := i + 1;
      v_day := v_day + 1;
      if app.dev_business_day(v_day) then v_left := v_left - 1; end if;
    end loop;
    return (v_day + v_local::time) at time zone 'Europe/Oslo';
  end if;
  return p_from + make_interval(days => greatest(app.dev_setting_number('dev_target_sev_three', 14)::int, 0));
end $fn$;

-- ===========================================================================
-- 6. reading helpers: evidence under the reader's own rights
-- ===========================================================================
create function app.dev_sandbox() returns boolean
  language sql stable security definer set search_path = ''
as $fn$ select coalesce((select a.sandbox from app.admins a where a.id = app.me()), false) $fn$;

-- a ticket the reader may see (its queue, its visibility, not deleted, sample rows only in the sandbox)
create function app.dev_ticket_ok(t app.tickets) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select t.deleted_at is null and (app.dev_sandbox() or not t.is_sample) and app.queue_ok(t.queue_key) and app.visible(t.owner_id, t.visibility)
$fn$;

create function app.dev_deal_ok(d app.deals) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.can('deals', 'see') and d.deleted_at is null and d.archived_at is null and (app.dev_sandbox() or not d.is_sample)
     and app.visible(d.owner_id, d.visibility)
$fn$;

create function app.dev_seo_ok() returns boolean
  language sql stable security definer set search_path = ''
as $fn$ select app.can('global', 'reports_others') or app.can('campaigns', 'reports_others') $fn$;

-- what backs a roadmap item, counted now: votes of the linked feature requests (one per organisation), the tickets and
-- open deals linked to the item or to those requests, the linked experiments and SEO plan items. Each part is left out
-- for a reader without the right on its source.
create function app.dev_evidence(p_item uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_req uuid[];
  r jsonb := '{}'::jsonb;
  v_n int; v_mrr numeric; v_cur text; v_manual boolean; v_currencies int;
begin
  select coalesce(array_agg(l.ref), '{}') into v_req
  from app.dev_roadmap_links l join app.feature_requests f on f.id = l.ref where l.item_id = p_item and l.kind = 'feature_request';
  if cardinality(v_req) > 0 then
    r := r || jsonb_build_object('requests', cardinality(v_req),
                                 'votes', (select count(distinct v.organization_id) from app.feature_request_votes v where v.request_id = any (v_req)));
  end if;
  if app.can('tickets', 'see') then
    select count(*) into v_n from app.tickets t
    where app.dev_ticket_ok(t)
      and (t.id in (select l.ref from app.dev_roadmap_links l where l.item_id = p_item and l.kind = 'ticket')
           or t.id in (select fl.ref from app.feature_request_links fl where fl.kind = 'ticket' and fl.request_id = any (v_req)));
    if v_n > 0 then r := r || jsonb_build_object('tickets', v_n); end if;
  end if;
  if app.can('deals', 'see') then
    select count(*), bool_or(d.value_source <> 'items'), count(distinct d.currency), min(d.currency),
           sum((app.deal_revenue(d.id) ->> 'mrr')::numeric)
      into v_n, v_manual, v_currencies, v_cur, v_mrr
    from app.deals d
    where d.status = 'open' and app.dev_deal_ok(d)
      and (d.id in (select l.ref from app.dev_roadmap_links l where l.item_id = p_item and l.kind = 'deal')
           or d.id in (select fl.ref from app.feature_request_links fl where fl.kind = 'deal' and fl.request_id = any (v_req)));
    if v_n > 0 then
      -- MRR only when every deal is valued from its items in one currency; a deal valued by hand has no MRR
      r := r || jsonb_build_object('deals', jsonb_build_object('n', v_n,
                                   'mrr', case when not coalesce(v_manual, false) and v_currencies = 1 then round(v_mrr) end,
                                   'currency', case when v_currencies = 1 then v_cur end));
    end if;
  end if;
  if app.can('campaigns', 'see') then
    r := r || jsonb_build_object('experiments', coalesce((
      select jsonb_agg(jsonb_build_object('stage', x.stage, 'outcome', x.outcome) order by x.created_at)
      from app.growth_experiments x join app.dev_roadmap_links l on l.ref = x.id and l.kind = 'experiment'
      where l.item_id = p_item and x.archived_at is null), '[]'::jsonb));
  end if;
  if app.dev_seo_ok() then
    r := r || jsonb_build_object('seo', coalesce((
      select jsonb_agg(jsonb_build_object('stage', cp.stage) order by cp.created_at)
      from app.seo_content_plan cp join app.dev_roadmap_links l on l.ref = cp.id and l.kind = 'seo_plan'
      where l.item_id = p_item), '[]'::jsonb));
  end if;
  return r;
end $fn$;

-- the item's links by name, for the edit dialog and the Markdown file (ids and staff-written titles; each under its right)
create function app.dev_item_links(p_item uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(x.j order by x.k, x.at), '[]'::jsonb) from (
    select 1 k, l.created_at at, jsonb_build_object('kind', 'feature_request', 'ref', f.id, 'label', 'FR-' || f.ref, 'title', f.title) j
    from app.dev_roadmap_links l join app.feature_requests f on f.id = l.ref where l.item_id = p_item and l.kind = 'feature_request'
    union all
    select 2, l.created_at, jsonb_build_object('kind', 'ticket', 'ref', t.id, 'label', 'T-' || t.number, 'title', null)
    from app.dev_roadmap_links l join app.tickets t on t.id = l.ref where l.item_id = p_item and l.kind = 'ticket' and app.dev_ticket_ok(t)
    union all
    select 3, l.created_at, jsonb_build_object('kind', 'deal', 'ref', d.id, 'label', 'D-' || d.seq, 'title', d.title)
    from app.dev_roadmap_links l join app.deals d on d.id = l.ref where l.item_id = p_item and l.kind = 'deal' and app.dev_deal_ok(d)
    union all
    select 4, l.created_at, jsonb_build_object('kind', 'experiment', 'ref', x.id, 'label', null, 'title', x.hypothesis)
    from app.dev_roadmap_links l join app.growth_experiments x on x.id = l.ref where l.item_id = p_item and l.kind = 'experiment' and app.can('campaigns', 'see')
    union all
    select 5, l.created_at, jsonb_build_object('kind', 'seo_plan', 'ref', cp.id, 'label', null, 'title', cp.query)
    from app.dev_roadmap_links l join app.seo_content_plan cp on cp.id = l.ref where l.item_id = p_item and l.kind = 'seo_plan' and app.dev_seo_ok()) x
$fn$;

create function app.dev_staff_name(p uuid) returns text
  language sql stable security definer set search_path = ''
as $fn$ select coalesce(a.name, a.email) from app.admins a where a.id = p $fn$;

create function app.dev_item_json(i app.dev_roadmap_items) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', i.id, 'key', app.dev_key(i.product, i.seq), 'product', i.product, 'title', i.title, 'goal', i.goal, 'lane', i.lane, 'ord', i.ord,
    'status', i.status, 'owner', case when i.owner_id is not null then jsonb_build_object('id', i.owner_id, 'name', app.dev_staff_name(i.owner_id)) end,
    'source', i.source_kind, 'version', i.version, 'created_at', i.created_at, 'updated_at', i.updated_at,
    'evidence', app.dev_evidence(i.id), 'links', app.dev_item_links(i.id),
    'work', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where w.status = 'done'))
             from app.dev_work_items w where w.roadmap_item_id = i.id and w.archived_at is null),
    'spec', (select jsonb_build_object('id', s.id, 'ref', 'RFC-' || lpad(s.number::text, 3, '0'), 'status', s.status) from app.dev_specs s where s.roadmap_item_id = i.id))
$fn$;

create function app.dev_work_json(w app.dev_work_items) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', w.id, 'key', app.dev_key(w.product, w.seq), 'product', w.product, 'kind', w.kind, 'title', w.title, 'points', w.points,
    'status', w.status, 'ord', w.ord, 'sprint_id', w.sprint_id, 'version', w.version, 'done_at', w.done_at,
    'roadmap', (select jsonb_build_object('id', i.id, 'key', app.dev_key(i.product, i.seq), 'title', i.title) from app.dev_roadmap_items i where i.id = w.roadmap_item_id),
    'assignee', (select jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email), 'initials', a.initials) from app.admins a where a.id = w.assignee_id),
    'bug', (select jsonb_build_object('id', b.id, 'number', b.number, 'state', b.state) from app.dev_bugs b where b.id = w.bug_id))
$fn$;

-- the tickets behind a bug: those linked to it and the incidents of its problem, as the reader may see them
create function app.dev_bug_ticket_ids(b app.dev_bugs) returns uuid[]
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(array_agg(t.id), '{}') from app.tickets t
  where app.dev_ticket_ok(t)
    and (t.id in (select bt.ticket_id from app.dev_bug_tickets bt where bt.bug_id = b.id)
         or (b.problem_id is not null and t.problem_id = b.problem_id))
$fn$;

create function app.dev_bug_json(b app.dev_bugs) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_ids uuid[]; p app.tickets; v_seen boolean := app.can('tickets', 'see');
begin
  v_ids := case when v_seen then app.dev_bug_ticket_ids(b) else '{}' end;
  select * into p from app.tickets t where t.id = b.problem_id and t.deleted_at is null;
  return jsonb_build_object(
    'id', b.id, 'number', b.number, 'product', b.product, 'title', b.title, 'severity', b.severity, 'source', b.source, 'state', b.state,
    'due_at', b.due_at, 'fixed_at', b.fixed_at, 'created_at', b.created_at, 'version', b.version,
    'assignee', case when b.assignee_id is not null then jsonb_build_object('id', b.assignee_id, 'name', app.dev_staff_name(b.assignee_id)) end,
    'duplicate_of', (select jsonb_build_object('id', d.id, 'number', d.number) from app.dev_bugs d where d.id = b.duplicate_of),
    'problem', case when p.id is not null then jsonb_build_object('id', p.id, 'status', p.problem_status,
                    'number', case when v_seen and app.dev_ticket_ok(p) then p.number end,
                    'open_incidents', (select count(*) from app.tickets t where t.problem_id = p.id and t.deleted_at is null and t.status not in ('resolved', 'closed'))) end,
    'tickets', case when v_seen then cardinality(v_ids) end,
    'ticket_numbers', case when v_seen then (select coalesce(jsonb_agg(t.number order by t.number), '[]'::jsonb) from app.tickets t where t.id = any (v_ids)) end,
    'customers', case when v_seen then (select count(distinct t.organization_id) from app.tickets t where t.id = any (v_ids) and t.organization_id is not null) end,
    'work', (select jsonb_build_object('id', w.id, 'key', app.dev_key(w.product, w.seq), 'status', w.status)
             from app.dev_work_items w where w.bug_id = b.id and w.archived_at is null order by w.created_at limit 1));
end $fn$;

create function app.dev_spec_json(s app.dev_specs) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', s.id, 'number', s.number, 'ref', 'RFC-' || lpad(s.number::text, 3, '0'), 'product', s.product, 'title', s.title, 'status', s.status,
    'revision', s.revision, 'version', s.version, 'updated_at', s.updated_at, 'created_at', s.created_at,
    'author', case when s.author_id is not null then jsonb_build_object('id', s.author_id, 'name', app.dev_staff_name(s.author_id)) end,
    'roadmap', (select jsonb_build_object('id', i.id, 'key', app.dev_key(i.product, i.seq), 'title', i.title) from app.dev_roadmap_items i where i.id = s.roadmap_item_id),
    'sections', jsonb_build_object('problem', s.problem, 'options', s.options, 'decision', s.decision, 'privacy', s.privacy, 'rollout', s.rollout),
    'signoffs', coalesce((select jsonb_agg(jsonb_build_object('role', g.role, 'by', app.dev_staff_name(g.staff_id), 'at', g.signed_at,
                                                              'revision', g.revision, 'current', g.revision = s.revision) order by g.role)
                          from app.dev_spec_signoffs g where g.spec_id = s.id), '[]'::jsonb))
$fn$;

create function app.dev_staff() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email), 'initials', a.initials) order by coalesce(a.name, a.email)), '[]'::jsonb)
  from app.admins a where a.active and (app.dev_sandbox() or not a.is_sample)
$fn$;

-- the audit of one record, newest first: who did what and when, with the codes it carried (never a value someone typed)
create function app.dev_log(p_type text, p_id uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('at', x.at, 'by', x.who, 'action', x.action, 'detail', x.detail) order by x.at desc), '[]'::jsonb)
  from (select a.at, coalesce(app.dev_staff_name(a.staff_id), a.actor) who, a.action, a.detail from app.audit a
        where a.target_type = p_type and a.target_id = p_id::text and a.action is not null order by a.at desc limit 20) x
$fn$;

-- ===========================================================================
-- 7. the roadmap: read and write
-- ===========================================================================
create function public.dev_roadmap_get(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see'); v_p text := nullif(p_product, 'all');
begin
  if v_p is not null and not app.dev_product_ok(v_p) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(app.dev_item_json(i) order by case i.lane when 'now' then 0 when 'next' then 1 else 2 end, i.ord, i.created_at)
                       from app.dev_roadmap_items i where i.archived_at is null and (v_p is null or i.product = v_p)), '[]'::jsonb),
    -- the top candidate per source that no roadmap item links yet
    'candidates', jsonb_build_object(
      'feature_request', (select jsonb_build_object('id', f.id, 'title', f.title, 'product', f.product)
                          from app.feature_requests f
                          where f.status in ('under_review', 'planned') and (v_p is null or f.product = v_p)
                            and not exists (select 1 from app.dev_roadmap_links l join app.dev_roadmap_items i on i.id = l.item_id
                                            where l.kind = 'feature_request' and l.ref = f.id and i.archived_at is null)
                          order by (select count(*) from app.feature_request_votes v where v.request_id = f.id) desc, f.created_at limit 1),
      'experiment', case when app.can('campaigns', 'see') then (
                          select jsonb_build_object('id', x.id, 'title', x.hypothesis, 'product', x.product)
                          from app.growth_experiments x
                          where x.archived_at is null and x.outcome = 'win' and (v_p is null or x.product = v_p)
                            and not exists (select 1 from app.dev_roadmap_links l join app.dev_roadmap_items i on i.id = l.item_id
                                            where l.kind = 'experiment' and l.ref = x.id and i.archived_at is null)
                          order by x.ended_at desc nulls last limit 1) end,
      'seo_plan', case when app.dev_seo_ok() then (
                          select jsonb_build_object('id', cp.id, 'title', cp.query, 'product', s.product)
                          from app.seo_content_plan cp join app.web_sites s on s.id = cp.site_id
                          where cp.stage in ('idea', 'writing') and s.product is not null and (v_p is null or s.product = v_p)
                            and not exists (select 1 from app.dev_roadmap_links l join app.dev_roadmap_items i on i.id = l.item_id
                                            where l.kind = 'seo_plan' and l.ref = cp.id and i.archived_at is null)
                          order by cp.created_at desc limit 1) end),
    -- what the edit dialog links to
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'label', 'FR-' || f.ref, 'title', f.title, 'product', f.product) order by f.ref desc)
                          from app.feature_requests f where f.status <> 'declined'), '[]'::jsonb),
    'deals', case when app.can('deals', 'see') then coalesce((
               select jsonb_agg(jsonb_build_object('id', d.id, 'label', 'D-' || d.seq, 'title', d.title) order by d.updated_at desc)
               from (select * from app.deals x where x.status = 'open' and app.dev_deal_ok(x) order by x.updated_at desc limit 200) d), '[]'::jsonb) end,
    'staff', app.dev_staff(),
    'can_add', app.can('dev', 'add'));
end $fn$;

create function public.dev_roadmap_add(p_product text, p_title text, p_goal text default null, p_lane text default 'later') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); v app.dev_roadmap_items; v_goal text := nullif(btrim(coalesce(p_goal, '')), '');
begin
  if p_product is null or not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  if char_length(v_goal) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'goal'; end if;
  if coalesce(p_lane, '') not in ('now', 'next', 'later') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'lane'; end if;
  insert into app.dev_roadmap_items (product, seq, title, goal, lane, ord, created_by)
  values (p_product, app.dev_next_seq(p_product), btrim(p_title), v_goal, p_lane,
          coalesce((select max(i.ord) + 1 from app.dev_roadmap_items i where i.lane = p_lane and i.archived_at is null), 0), v_me)
  returning * into v;
  perform app.log('dev_roadmap.added', 'dev_roadmap_item', v.id::text, jsonb_build_object('lane', v.lane));
  return app.dev_item_json(v);
end $fn$;

create function public.dev_roadmap_set(p_id uuid, p_version int, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); v app.dev_roadmap_items; k text; v_owner uuid;
begin
  if jsonb_typeof(p_patch) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('title', 'goal', 'status', 'owner_id') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
  end loop;
  select * into v from app.dev_roadmap_items i where i.id = p_id and i.archived_at is null for update;
  if v.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from v.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if p_patch ? 'title' and char_length(btrim(coalesce(p_patch ->> 'title', ''))) not between 3 and 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title';
  end if;
  if p_patch ? 'goal' and char_length(btrim(coalesce(p_patch ->> 'goal', ''))) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'goal'; end if;
  if p_patch ? 'status' and coalesce(p_patch ->> 'status', '') not in ('backlog', 'spec', 'in_progress', 'review', 'staging', 'rollout', 'done') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  if p_patch ? 'owner_id' and p_patch ->> 'owner_id' is not null then
    if (p_patch ->> 'owner_id') !~ '^[0-9a-f-]{36}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id'; end if;
    v_owner := (p_patch ->> 'owner_id')::uuid;
    if not exists (select 1 from app.admins a where a.id = v_owner and a.active) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'owner_id'; end if;
  end if;
  update app.dev_roadmap_items i set
    title = case when p_patch ? 'title' then btrim(p_patch ->> 'title') else i.title end,
    goal = case when p_patch ? 'goal' then nullif(btrim(coalesce(p_patch ->> 'goal', '')), '') else i.goal end,
    status = coalesce(p_patch ->> 'status', i.status),
    owner_id = case when p_patch ? 'owner_id' then v_owner else i.owner_id end,
    updated_at = now(), version = i.version + 1
  where i.id = p_id returning * into v;
  perform app.log('dev_roadmap.changed', 'dev_roadmap_item', p_id::text,
                  jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(p_patch) x)) || case when p_patch ? 'status' then jsonb_build_object('status', v.status) else '{}'::jsonb end);
  return app.dev_item_json(v);
end $fn$;

-- ← and → : another lane, at its end
create function public.dev_roadmap_move(p_id uuid, p_lane text, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); v app.dev_roadmap_items;
begin
  if coalesce(p_lane, '') not in ('now', 'next', 'later') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'lane'; end if;
  select * into v from app.dev_roadmap_items i where i.id = p_id and i.archived_at is null for update;
  if v.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from v.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if v.lane = p_lane then return app.dev_item_json(v); end if;
  update app.dev_roadmap_items i set lane = p_lane, updated_at = now(), version = i.version + 1,
    ord = coalesce((select max(x.ord) + 1 from app.dev_roadmap_items x where x.lane = p_lane and x.archived_at is null), 0)
  where i.id = p_id returning * into v;
  perform app.log('dev_roadmap.moved', 'dev_roadmap_item', p_id::text, jsonb_build_object('lane', p_lane));
  return app.dev_item_json(v);
end $fn$;

create function public.dev_roadmap_archive(p_id uuid, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); v app.dev_roadmap_items;
begin
  select * into v from app.dev_roadmap_items i where i.id = p_id and i.archived_at is null for update;
  if v.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from v.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  update app.dev_roadmap_items i set archived_at = now(), updated_at = now(), version = i.version + 1 where i.id = p_id;
  perform app.log('dev_roadmap.archived', 'dev_roadmap_item', p_id::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- link or unlink evidence: a feature request, a ticket (by id or number), a deal, an experiment, an SEO plan item —
-- each only as the person may see it on its own screen
create function public.dev_roadmap_link(p_id uuid, p_kind text, p_ref uuid, p_number bigint, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); v app.dev_roadmap_items; v_ref uuid := p_ref; t app.tickets; d app.deals;
begin
  select * into v from app.dev_roadmap_items i where i.id = p_id and i.archived_at is null;
  if v.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_kind = 'ticket' then
    select * into t from app.tickets x where (v_ref is not null and x.id = v_ref) or (v_ref is null and x.number = p_number);
    if t.id is null or not app.dev_ticket_ok(t) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'ticket'; end if;
    v_ref := t.id;
  elsif p_kind = 'deal' then
    select * into d from app.deals x where x.id = v_ref;
    if d.id is null or not app.dev_deal_ok(d) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'deal'; end if;
  elsif p_kind = 'feature_request' then
    if not exists (select 1 from app.feature_requests f where f.id = v_ref) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'feature_request'; end if;
  elsif p_kind = 'experiment' then
    perform app.require('campaigns', 'see');
    if not exists (select 1 from app.growth_experiments x where x.id = v_ref) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'experiment'; end if;
  elsif p_kind = 'seo_plan' then
    perform app.require_marketing_reports();
    if not exists (select 1 from app.seo_content_plan x where x.id = v_ref) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'seo_plan'; end if;
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end if;
  if coalesce(p_on, false) then
    insert into app.dev_roadmap_links (item_id, kind, ref, created_by) values (p_id, p_kind, v_ref, v_me) on conflict do nothing;
  else
    delete from app.dev_roadmap_links l where l.item_id = p_id and l.kind = p_kind and l.ref = v_ref;
  end if;
  update app.dev_roadmap_items i set updated_at = now() where i.id = p_id;
  perform app.log('dev_roadmap.linked', 'dev_roadmap_item', p_id::text, jsonb_build_object('kind', p_kind, 'on', coalesce(p_on, false)));
  select * into v from app.dev_roadmap_items i where i.id = p_id;
  return app.dev_item_json(v);
end $fn$;

-- «Promote from»: the source becomes a Later item with its evidence linked
create function public.dev_roadmap_promote(p_kind text, p_ref uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); v_title text; v_product text; v app.dev_roadmap_items;
begin
  if p_kind = 'feature_request' then
    select f.title, f.product into v_title, v_product from app.feature_requests f where f.id = p_ref;
  elsif p_kind = 'experiment' then
    perform app.require('campaigns', 'see');
    select left(btrim(x.hypothesis), 200), x.product into v_title, v_product from app.growth_experiments x where x.id = p_ref and x.archived_at is null;
  elsif p_kind = 'seo_plan' then
    perform app.require_marketing_reports();
    select cp.query, s.product into v_title, v_product from app.seo_content_plan cp join app.web_sites s on s.id = cp.site_id where cp.id = p_ref;
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end if;
  if v_title is null or v_product is null then raise exception 'not_found' using errcode = 'no_data_found', detail = p_kind; end if;
  if char_length(btrim(v_title)) < 3 then v_title := rpad(btrim(v_title), 3, '.'); end if;
  if exists (select 1 from app.dev_roadmap_items i where i.source_kind = p_kind and i.source_ref = p_ref and i.archived_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'promoted';
  end if;
  insert into app.dev_roadmap_items (product, seq, title, lane, ord, source_kind, source_ref, created_by)
  values (v_product, app.dev_next_seq(v_product), btrim(v_title), 'later',
          coalesce((select max(i.ord) + 1 from app.dev_roadmap_items i where i.lane = 'later' and i.archived_at is null), 0), p_kind, p_ref, v_me)
  returning * into v;
  insert into app.dev_roadmap_links (item_id, kind, ref, created_by) values (v.id, p_kind, p_ref, v_me);
  perform app.log('dev_roadmap.promoted', 'dev_roadmap_item', v.id::text, jsonb_build_object('kind', p_kind));
  return app.dev_item_json(v);
end $fn$;

-- ===========================================================================
-- 8. the work board
-- ===========================================================================
create function app.dev_current_sprint() returns app.dev_sprints
  language sql stable security definer set search_path = ''
as $fn$
  select s.* from app.dev_sprints s where s.starts_on <= app.dev_today() and s.ends_on >= app.dev_today() order by s.starts_on desc limit 1
$fn$;

create function public.dev_board_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see'); s app.dev_sprints := app.dev_current_sprint();
begin
  return jsonb_build_object(
    'today', app.dev_today(),
    'sprint', case when s.id is not null then jsonb_build_object(
      'id', s.id, 'name', s.name, 'starts_on', s.starts_on, 'ends_on', s.ends_on,
      'days', app.dev_business_days(s.starts_on, s.ends_on),
      'day', app.dev_business_days(s.starts_on, least(app.dev_today(), s.ends_on)),
      'committed', (select coalesce(sum(w.points), 0) from app.dev_work_items w where w.sprint_id = s.id and w.archived_at is null),
      'done', (select coalesce(sum(w.points), 0) from app.dev_work_items w where w.sprint_id = s.id and w.archived_at is null and w.status in ('rollout', 'done'))) end,
    'sprints', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'starts_on', x.starts_on, 'ends_on', x.ends_on) order by x.starts_on desc)
                         from (select * from app.dev_sprints y order by y.starts_on desc limit 12) x), '[]'::jsonb),
    -- open work, and what was finished in the running sprint or the last fourteen days
    'items', coalesce((select jsonb_agg(app.dev_work_json(w) order by w.ord, w.created_at)
                       from app.dev_work_items w
                       where w.archived_at is null
                         and (w.status <> 'done' or w.done_at > now() - interval '14 days' or (s.id is not null and w.sprint_id = s.id))), '[]'::jsonb),
    'roadmap', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'key', app.dev_key(i.product, i.seq), 'title', i.title, 'product', i.product)
                                          order by i.product, i.seq)
                         from app.dev_roadmap_items i where i.archived_at is null), '[]'::jsonb),
    'bugs', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'number', b.number, 'title', b.title, 'product', b.product) order by b.number desc)
                      from app.dev_bugs b where b.state = 'open'), '[]'::jsonb),
    'staff', app.dev_staff(),
    'can_add', app.can('dev', 'add'));
end $fn$;

-- add a work item (p_id null) or change one: product, kind, title, points, column, epic, sprint, assignee, bug
create function public.dev_work_item_save(p_id uuid, p_version int, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('dev', 'add'); k text; w app.dev_work_items; v_product text; v_status text; v_points int;
  v_item uuid; v_sprint uuid; v_assignee uuid; v_bug uuid; v_kind text; v_title text;
begin
  if jsonb_typeof(p_values) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
  for k in select jsonb_object_keys(p_values) loop
    if k not in ('product', 'kind', 'title', 'points', 'status', 'roadmap_item_id', 'sprint_id', 'assignee_id', 'bug_id') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
    if k in ('roadmap_item_id', 'sprint_id', 'assignee_id', 'bug_id') and p_values ->> k is not null and (p_values ->> k) !~ '^[0-9a-f-]{36}$' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  if p_id is not null then
    select * into w from app.dev_work_items x where x.id = p_id and x.archived_at is null for update;
    if w.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is distinct from w.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
    if p_values ? 'product' and p_values ->> 'product' is distinct from w.product then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  end if;
  v_kind := coalesce(p_values ->> 'kind', w.kind, 'story');
  v_title := case when p_values ? 'title' then btrim(coalesce(p_values ->> 'title', '')) else w.title end;
  v_status := coalesce(p_values ->> 'status', w.status, 'backlog');
  v_points := case when p_values ? 'points' then (case when jsonb_typeof(p_values -> 'points') = 'number' then (p_values ->> 'points')::numeric::int end) else w.points end;
  v_item := case when p_values ? 'roadmap_item_id' then (p_values ->> 'roadmap_item_id')::uuid else w.roadmap_item_id end;
  v_sprint := case when p_values ? 'sprint_id' then (p_values ->> 'sprint_id')::uuid else w.sprint_id end;
  v_assignee := case when p_values ? 'assignee_id' then (p_values ->> 'assignee_id')::uuid else w.assignee_id end;
  v_bug := case when p_values ? 'bug_id' then (p_values ->> 'bug_id')::uuid else w.bug_id end;
  v_product := coalesce(w.product, p_values ->> 'product',
                        (select i.product from app.dev_roadmap_items i where i.id = v_item), (select b.product from app.dev_bugs b where b.id = v_bug));
  if v_product is null or not app.dev_product_ok(v_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if v_kind not in ('story', 'bug', 'task', 'spike') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if char_length(coalesce(v_title, '')) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  if v_status not in ('backlog', 'spec', 'in_progress', 'review', 'staging', 'rollout', 'done') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  if p_values ? 'points' and p_values -> 'points' <> 'null'::jsonb and (v_points is null or v_points not between 0 and 100) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'points';
  end if;
  if v_item is not null and not exists (select 1 from app.dev_roadmap_items i where i.id = v_item and i.archived_at is null and i.product = v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'roadmap_item_id';
  end if;
  if v_sprint is not null and not exists (select 1 from app.dev_sprints s where s.id = v_sprint) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'sprint_id'; end if;
  if v_assignee is not null and not exists (select 1 from app.admins a where a.id = v_assignee and a.active) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'assignee_id';
  end if;
  if v_bug is not null and not exists (select 1 from app.dev_bugs b where b.id = v_bug and b.product = v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'bug_id';
  end if;
  if p_id is null then
    insert into app.dev_work_items (product, seq, kind, title, points, status, ord, roadmap_item_id, sprint_id, assignee_id, bug_id, done_at, created_by)
    values (v_product, app.dev_next_seq(v_product), v_kind, v_title, v_points, v_status,
            coalesce((select max(x.ord) + 1 from app.dev_work_items x where x.status = v_status and x.archived_at is null), 0),
            v_item, v_sprint, v_assignee, v_bug, case when v_status = 'done' then now() end, v_me)
    returning * into w;
    perform app.log('dev_work.added', 'dev_work_item', w.id::text, jsonb_build_object('status', w.status));
  else
    update app.dev_work_items x set kind = v_kind, title = v_title, points = v_points, roadmap_item_id = v_item, sprint_id = v_sprint,
      assignee_id = v_assignee, bug_id = v_bug,
      ord = case when v_status <> x.status then coalesce((select max(y.ord) + 1 from app.dev_work_items y where y.status = v_status and y.archived_at is null), 0) else x.ord end,
      done_at = case when v_status = 'done' then coalesce(x.done_at, now()) end,
      status = v_status, updated_at = now(), version = x.version + 1
    where x.id = p_id returning * into w;
    perform app.log('dev_work.changed', 'dev_work_item', w.id::text,
                    jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(p_values) x), 'status', w.status));
  end if;
  return app.dev_work_json(w);
end $fn$;

-- a card to another column (drag and drop, or the keyboard): at the end of it
create function public.dev_work_item_move(p_id uuid, p_status text, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); w app.dev_work_items;
begin
  if coalesce(p_status, '') not in ('backlog', 'spec', 'in_progress', 'review', 'staging', 'rollout', 'done') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  select * into w from app.dev_work_items x where x.id = p_id and x.archived_at is null for update;
  if w.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from w.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if w.status = p_status then return app.dev_work_json(w); end if;
  update app.dev_work_items x set status = p_status,
    ord = coalesce((select max(y.ord) + 1 from app.dev_work_items y where y.status = p_status and y.archived_at is null), 0),
    done_at = case when p_status = 'done' then now() end, updated_at = now(), version = x.version + 1
  where x.id = p_id returning * into w;
  perform app.log('dev_work.moved', 'dev_work_item', p_id::text, jsonb_build_object('status', p_status));
  return app.dev_work_json(w);
end $fn$;

create function public.dev_work_item_archive(p_id uuid, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); w app.dev_work_items;
begin
  select * into w from app.dev_work_items x where x.id = p_id and x.archived_at is null for update;
  if w.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from w.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  update app.dev_work_items x set archived_at = now(), updated_at = now(), version = x.version + 1 where x.id = p_id;
  perform app.log('dev_work.archived', 'dev_work_item', p_id::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- a sprint: a name and its first and last day, not overlapping another
create function public.dev_sprint_save(p_id uuid, p_name text, p_starts date, p_ends date) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); s app.dev_sprints;
begin
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 60 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if p_starts is null or p_ends is null or p_ends < p_starts or p_ends - p_starts > 60 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dates'; end if;
  if exists (select 1 from app.dev_sprints x where x.id is distinct from p_id and x.starts_on <= p_ends and x.ends_on >= p_starts) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'overlap';
  end if;
  if p_id is null then
    insert into app.dev_sprints (name, starts_on, ends_on, created_by) values (btrim(p_name), p_starts, p_ends, v_me) returning * into s;
    perform app.log('dev_sprint.added', 'dev_sprint', s.id::text);
  else
    update app.dev_sprints x set name = btrim(p_name), starts_on = p_starts, ends_on = p_ends, updated_at = now() where x.id = p_id returning * into s;
    if s.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    perform app.log('dev_sprint.changed', 'dev_sprint', s.id::text);
  end if;
  return jsonb_build_object('id', s.id, 'name', s.name, 'starts_on', s.starts_on, 'ends_on', s.ends_on);
end $fn$;

-- ===========================================================================
-- 9. bug triage
-- ===========================================================================
create function public.dev_bugs_get(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see'); v_p text := nullif(p_product, 'all');
begin
  if v_p is not null and not app.dev_product_ok(v_p) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  return jsonb_build_object(
    'now', now(),
    'targets', app.dev_targets(),
    -- open bugs by severity and due time, then what was fixed or merged in the last 30 days
    'bugs', coalesce((select jsonb_agg(app.dev_bug_json(b) order by b.state <> 'open', b.severity, b.due_at, b.number)
                      from app.dev_bugs b
                      where (v_p is null or b.product = v_p)
                        and (b.state = 'open' or b.updated_at > now() - interval '30 days')), '[]'::jsonb),
    'kpi', (select jsonb_build_object(
      'open', count(*) filter (where b.state = 'open'),
      's1', count(*) filter (where b.state = 'open' and b.severity = 's1'),
      's2', count(*) filter (where b.state = 'open' and b.severity = 's2'),
      's3', count(*) filter (where b.state = 'open' and b.severity = 's3'),
      'fixed_30', count(*) filter (where b.state = 'fixed' and b.fixed_at > now() - interval '30 days'),
      'within_30', count(*) filter (where b.state = 'fixed' and b.fixed_at > now() - interval '30 days' and b.fixed_at <= b.due_at),
      'escaped_30', count(*) filter (where b.source = 'ticket' and b.state <> 'duplicate' and b.created_at > now() - interval '30 days'),
      'median_h', (select percentile_cont(0.5) within group (order by extract(epoch from x.fixed_at - x.created_at) / 3600)
                   from app.dev_bugs x where x.state = 'fixed' and x.fixed_at > now() - interval '90 days' and (v_p is null or x.product = v_p)),
      'median_s1_h', (select percentile_cont(0.5) within group (order by extract(epoch from x.fixed_at - x.created_at) / 3600)
                      from app.dev_bugs x where x.state = 'fixed' and x.severity = 's1' and x.fixed_at > now() - interval '90 days' and (v_p is null or x.product = v_p)),
      'median_s2_h', (select percentile_cont(0.5) within group (order by extract(epoch from x.fixed_at - x.created_at) / 3600)
                      from app.dev_bugs x where x.state = 'fixed' and x.severity = 's2' and x.fixed_at > now() - interval '90 days' and (v_p is null or x.product = v_p)))
      from app.dev_bugs b where v_p is null or b.product = v_p),
    'staff', app.dev_staff(),
    'problems', case when app.can('tickets', 'see') then coalesce((
                  select jsonb_agg(jsonb_build_object('id', t.id, 'number', t.number, 'subject', t.subject, 'status', t.problem_status) order by t.number desc)
                  from (select * from app.tickets x where x.type = 'problem' and x.problem_status <> 'resolved' and app.dev_ticket_ok(x) order by x.number desc limit 100) t), '[]'::jsonb) end,
    'can_add', app.can('dev', 'add'),
    'can_resolve', app.can('tickets', 'edit_others'));
end $fn$;

-- the number on the «Bug triage» pill: open bugs of one application
create function public.dev_open_bugs(p_product text) returns int
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see');
begin
  return (select count(*) from app.dev_bugs b where b.state = 'open' and b.product = p_product);
end $fn$;

create function app.dev_ticket_by_number(p_number bigint) returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare t app.tickets;
begin
  select * into t from app.tickets x where x.number = p_number;
  if t.id is null or not app.dev_ticket_ok(t) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'ticket'; end if;
  return t.id;
end $fn$;

create function app.dev_problem_ok(p_problem uuid) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
declare t app.tickets;
begin
  select * into t from app.tickets x where x.id = p_problem and x.type = 'problem';
  if t.id is null or not app.dev_ticket_ok(t) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'problem'; end if;
end $fn$;

-- a bug: from tickets a customer filed (source ticket: at least one ticket or a problem) or found internally
create function public.dev_bug_create(p_product text, p_title text, p_severity text, p_source text, p_problem uuid default null,
                                      p_tickets bigint[] default '{}') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); b app.dev_bugs; n bigint; v_ids uuid[] := '{}';
begin
  if p_product is null or not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  if coalesce(p_severity, '') not in ('s1', 's2', 's3') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'severity'; end if;
  if coalesce(p_source, '') not in ('ticket', 'internal') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source'; end if;
  if cardinality(coalesce(p_tickets, '{}')) > 50 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'tickets'; end if;
  if p_problem is not null then perform app.dev_problem_ok(p_problem); end if;
  foreach n in array coalesce(p_tickets, '{}') loop
    v_ids := v_ids || app.dev_ticket_by_number(n);
  end loop;
  if p_source = 'ticket' and cardinality(v_ids) = 0 and p_problem is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'tickets'; end if;
  insert into app.dev_bugs (product, title, severity, source, problem_id, due_at, created_by)
  values (p_product, btrim(p_title), p_severity, p_source, p_problem, app.dev_bug_due(now(), p_severity), v_me) returning * into b;
  insert into app.dev_bug_tickets (bug_id, ticket_id, created_by) select b.id, x, v_me from unnest(v_ids) x on conflict do nothing;
  perform app.log('dev_bug.added', 'dev_bug', b.id::text, jsonb_build_object('severity', b.severity, 'source', b.source, 'tickets', cardinality(v_ids)));
  return app.dev_bug_json(b);
end $fn$;

-- title, severity (the due time follows from when it was found), assignee, problem: while the bug is open
create function public.dev_bug_set(p_id uuid, p_version int, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); b app.dev_bugs; k text; v_sev text; v_assignee uuid; v_problem uuid;
begin
  if jsonb_typeof(p_patch) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('title', 'severity', 'assignee_id', 'problem_id') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
    if k in ('assignee_id', 'problem_id') and p_patch ->> k is not null and (p_patch ->> k) !~ '^[0-9a-f-]{36}$' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  select * into b from app.dev_bugs x where x.id = p_id for update;
  if b.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from b.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if b.state <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if p_patch ? 'title' and char_length(btrim(coalesce(p_patch ->> 'title', ''))) not between 3 and 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title';
  end if;
  v_sev := coalesce(p_patch ->> 'severity', b.severity);
  if v_sev not in ('s1', 's2', 's3') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'severity'; end if;
  v_assignee := case when p_patch ? 'assignee_id' then (p_patch ->> 'assignee_id')::uuid else b.assignee_id end;
  if p_patch ? 'assignee_id' and v_assignee is not null and not exists (select 1 from app.admins a where a.id = v_assignee and a.active) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'assignee_id';
  end if;
  v_problem := case when p_patch ? 'problem_id' then (p_patch ->> 'problem_id')::uuid else b.problem_id end;
  if p_patch ? 'problem_id' and v_problem is not null then perform app.dev_problem_ok(v_problem); end if;
  update app.dev_bugs x set
    title = case when p_patch ? 'title' then btrim(p_patch ->> 'title') else x.title end,
    severity = v_sev, due_at = case when v_sev <> x.severity then app.dev_bug_due(x.created_at, v_sev) else x.due_at end,
    assignee_id = v_assignee, problem_id = v_problem, updated_at = now(), version = x.version + 1
  where x.id = p_id returning * into b;
  perform app.log('dev_bug.changed', 'dev_bug', p_id::text, jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(p_patch) x), 'severity', b.severity));
  return app.dev_bug_json(b);
end $fn$;

create function public.dev_bug_link(p_id uuid, p_number bigint, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); b app.dev_bugs; v_ticket uuid;
begin
  select * into b from app.dev_bugs x where x.id = p_id;
  if b.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  v_ticket := app.dev_ticket_by_number(p_number);
  if coalesce(p_on, false) then
    insert into app.dev_bug_tickets (bug_id, ticket_id, created_by) values (p_id, v_ticket, v_me) on conflict do nothing;
  else
    delete from app.dev_bug_tickets x where x.bug_id = p_id and x.ticket_id = v_ticket;
  end if;
  update app.dev_bugs x set updated_at = now() where x.id = p_id returning * into b;
  perform app.log('dev_bug.linked', 'dev_bug', p_id::text, jsonb_build_object('on', coalesce(p_on, false)));
  return app.dev_bug_json(b);
end $fn$;

-- «Merge duplicate»: this bug duplicates p_into; its tickets, problem and board cards go to the one that stays
create function public.dev_bug_merge(p_id uuid, p_into uuid, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); b app.dev_bugs; keep app.dev_bugs;
begin
  select * into b from app.dev_bugs x where x.id = p_id for update;
  if b.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from b.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if b.state <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  select * into keep from app.dev_bugs x where x.id = p_into for update;
  if keep.id is null or keep.id = b.id then raise exception 'not_found' using errcode = 'no_data_found', detail = 'into'; end if;
  if keep.state = 'duplicate' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'into'; end if;
  insert into app.dev_bug_tickets (bug_id, ticket_id, created_by) select keep.id, x.ticket_id, v_me from app.dev_bug_tickets x where x.bug_id = b.id on conflict do nothing;
  delete from app.dev_bug_tickets x where x.bug_id = b.id;
  update app.dev_work_items w set bug_id = keep.id, updated_at = now() where w.bug_id = b.id and w.product = keep.product;
  update app.dev_bugs x set problem_id = coalesce(x.problem_id, b.problem_id), updated_at = now(), version = x.version + 1 where x.id = keep.id;
  update app.dev_bugs x set state = 'duplicate', duplicate_of = keep.id, updated_at = now(), version = x.version + 1 where x.id = b.id returning * into b;
  perform app.log('dev_bug.merged', 'dev_bug', b.id::text, jsonb_build_object('into', keep.number));
  return app.dev_bug_json(b);
end $fn$;

-- «Mark fixed»: the bug is closed; a linked problem that is not resolved yet is resolved through problem_resolve (0012),
-- which needs Tickets › Edit others and queues the person's message as the reply on every open incident of the problem.
-- 'notified' counts those tickets (not customers); 'mail_ready' says whether the problem's application can email the
-- replies at all (0061 mail_ready_for), so the toast says what really happened.
create function public.dev_bug_fix(p_id uuid, p_version int, p_body text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); b app.dev_bugs; p app.tickets; v_open int := 0; v_notified int := 0; v_resolved boolean := false;
        v_body text := nullif(btrim(coalesce(p_body, '')), ''); v_mail boolean;
begin
  select * into b from app.dev_bugs x where x.id = p_id for update;
  if b.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from b.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if b.state <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if char_length(v_body) > 20000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  select * into p from app.tickets t where t.id = b.problem_id and t.deleted_at is null;
  if p.id is not null and coalesce(p.problem_status, '') <> 'resolved' then
    select count(*) into v_open from app.tickets t where t.problem_id = p.id and t.deleted_at is null and t.status not in ('resolved', 'closed');
    if v_open > 0 and v_body is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
    v_notified := coalesce((public.problem_resolve(p.id, coalesce(v_body, '')) ->> 'notified')::int, 0);
    v_resolved := true;
    v_mail := app.mail_ready_for(p.product);
  end if;
  update app.dev_bugs x set state = 'fixed', fixed_at = now(), fixed_by = v_me, updated_at = now(), version = x.version + 1 where x.id = p_id returning * into b;
  perform app.log('dev_bug.fixed', 'dev_bug', p_id::text, jsonb_build_object('problem_resolved', v_resolved, 'notified', v_notified));
  return app.dev_bug_json(b) || jsonb_build_object('notified', v_notified, 'problem_resolved', v_resolved, 'mail_ready', v_mail);
end $fn$;

-- ===========================================================================
-- 10. specs
-- ===========================================================================
create function public.dev_specs_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see');
begin
  return jsonb_build_object(
    'specs', coalesce((select jsonb_agg(app.dev_spec_json(s) order by s.number) from app.dev_specs s), '[]'::jsonb),
    'roadmap', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'key', app.dev_key(i.product, i.seq), 'title', i.title, 'product', i.product)
                                          order by i.product, i.seq)
                         from app.dev_roadmap_items i where i.archived_at is null
                           and not exists (select 1 from app.dev_specs s where s.roadmap_item_id = i.id)), '[]'::jsonb),
    'can_add', app.can('dev', 'add'));
end $fn$;

-- a spec: new (p_id null: product or roadmap item, title) or changed. A change to the title or a section is a new
-- revision: the sign-offs given on the old one lapse, and an approved spec goes back to review.
create function public.dev_spec_save(p_id uuid, p_version int, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); s app.dev_specs; k text; v_item uuid; v_product text; v_changed boolean := false; f text;
begin
  if jsonb_typeof(p_values) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
  for k in select jsonb_object_keys(p_values) loop
    if k not in ('product', 'title', 'roadmap_item_id', 'problem', 'options', 'decision', 'privacy', 'rollout') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
    if k in ('problem', 'options', 'decision', 'privacy', 'rollout') and char_length(coalesce(p_values ->> k, '')) > 8000 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  if p_values ? 'title' and char_length(btrim(coalesce(p_values ->> 'title', ''))) not between 3 and 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title';
  end if;
  if p_values ? 'roadmap_item_id' and p_values ->> 'roadmap_item_id' is not null then
    if (p_values ->> 'roadmap_item_id') !~ '^[0-9a-f-]{36}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'roadmap_item_id'; end if;
    v_item := (p_values ->> 'roadmap_item_id')::uuid;
    select i.product into v_product from app.dev_roadmap_items i where i.id = v_item and i.archived_at is null;
    if v_product is null then raise exception 'not_found' using errcode = 'no_data_found', detail = 'roadmap_item_id'; end if;
    if exists (select 1 from app.dev_specs x where x.roadmap_item_id = v_item and x.id is distinct from p_id) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'roadmap_item_id';
    end if;
  end if;
  if p_id is null then
    v_product := coalesce(v_product, p_values ->> 'product');
    if v_product is null or not app.dev_product_ok(v_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
    if not p_values ? 'title' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
    insert into app.dev_specs (product, title, roadmap_item_id, author_id, problem, options, decision, privacy, rollout)
    values (v_product, btrim(p_values ->> 'title'), v_item, v_me, nullif(btrim(coalesce(p_values ->> 'problem', '')), ''),
            nullif(btrim(coalesce(p_values ->> 'options', '')), ''), nullif(btrim(coalesce(p_values ->> 'decision', '')), ''),
            nullif(btrim(coalesce(p_values ->> 'privacy', '')), ''), nullif(btrim(coalesce(p_values ->> 'rollout', '')), ''))
    returning * into s;
    perform app.log('dev_spec.added', 'dev_spec', s.id::text);
    return app.dev_spec_json(s);
  end if;
  select * into s from app.dev_specs x where x.id = p_id for update;
  if s.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from s.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if v_product is not null and v_product <> s.product then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'roadmap_item_id'; end if;
  if p_values ? 'product' and p_values ->> 'product' is distinct from s.product then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  v_changed := (p_values ? 'title' and btrim(p_values ->> 'title') is distinct from s.title);
  foreach f in array array['problem', 'options', 'decision', 'privacy', 'rollout'] loop
    if p_values ? f and nullif(btrim(coalesce(p_values ->> f, '')), '') is distinct from (to_jsonb(s) ->> f) then v_changed := true; end if;
  end loop;
  update app.dev_specs x set
    title = case when p_values ? 'title' then btrim(p_values ->> 'title') else x.title end,
    roadmap_item_id = case when p_values ? 'roadmap_item_id' then v_item else x.roadmap_item_id end,
    problem = case when p_values ? 'problem' then nullif(btrim(coalesce(p_values ->> 'problem', '')), '') else x.problem end,
    options = case when p_values ? 'options' then nullif(btrim(coalesce(p_values ->> 'options', '')), '') else x.options end,
    decision = case when p_values ? 'decision' then nullif(btrim(coalesce(p_values ->> 'decision', '')), '') else x.decision end,
    privacy = case when p_values ? 'privacy' then nullif(btrim(coalesce(p_values ->> 'privacy', '')), '') else x.privacy end,
    rollout = case when p_values ? 'rollout' then nullif(btrim(coalesce(p_values ->> 'rollout', '')), '') else x.rollout end,
    revision = x.revision + case when v_changed then 1 else 0 end,
    status = case when v_changed and x.status = 'approved' then 'in_review' else x.status end,
    updated_at = now(), version = x.version + 1
  where x.id = p_id returning * into s;
  perform app.log('dev_spec.changed', 'dev_spec', p_id::text, jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(p_values) x), 'revision', s.revision));
  return app.dev_spec_json(s);
end $fn$;

-- Draft, In review, Approved; Approved only with all four sign-offs on the current revision
create function public.dev_spec_status(p_id uuid, p_status text, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); s app.dev_specs;
begin
  if coalesce(p_status, '') not in ('draft', 'in_review', 'approved') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  select * into s from app.dev_specs x where x.id = p_id for update;
  if s.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is distinct from s.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if p_status = 'approved' and (select count(*) from app.dev_spec_signoffs g where g.spec_id = s.id and g.revision = s.revision) < 4 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signoffs';
  end if;
  update app.dev_specs x set status = p_status, updated_at = now(), version = x.version + 1 where x.id = p_id returning * into s;
  perform app.log('dev_spec.status', 'dev_spec', p_id::text, jsonb_build_object('status', p_status));
  return app.dev_spec_json(s);
end $fn$;

-- a sign-off for one role on the current revision, or withdrawn; an approved spec that loses one goes back to review
create function public.dev_spec_sign(p_id uuid, p_role text, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); s app.dev_specs;
begin
  if coalesce(p_role, '') not in ('product', 'engineering', 'security_privacy', 'support') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'role'; end if;
  select * into s from app.dev_specs x where x.id = p_id for update;
  if s.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if coalesce(p_on, false) then
    insert into app.dev_spec_signoffs (spec_id, role, staff_id, revision) values (p_id, p_role, v_me, s.revision)
    on conflict (spec_id, role) do update set staff_id = excluded.staff_id, revision = excluded.revision, signed_at = now();
  else
    delete from app.dev_spec_signoffs g where g.spec_id = p_id and g.role = p_role;
    update app.dev_specs x set status = 'in_review', updated_at = now(), version = x.version + 1 where x.id = p_id and x.status = 'approved';
  end if;
  perform app.log(case when coalesce(p_on, false) then 'dev_spec.signed' else 'dev_spec.unsigned' end, 'dev_spec', p_id::text,
                  jsonb_build_object('role', p_role, 'revision', s.revision));
  select * into s from app.dev_specs x where x.id = p_id;
  return app.dev_spec_json(s);
end $fn$;

-- ===========================================================================
-- 11. the Markdown roadmap: the records the files are generated from
-- ===========================================================================
create function public.dev_files_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see');
begin
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(app.dev_item_json(i) || jsonb_build_object(
        'problem', (select s.problem from app.dev_specs s where s.roadmap_item_id = i.id),
        'tasks', coalesce((select jsonb_agg(jsonb_build_object('key', app.dev_key(w.product, w.seq), 'title', w.title, 'done', w.status = 'done') order by w.seq)
                           from app.dev_work_items w where w.roadmap_item_id = i.id and w.archived_at is null), '[]'::jsonb),
        'log', app.dev_log('dev_roadmap_item', i.id)) order by i.product, i.seq)
      from app.dev_roadmap_items i where i.archived_at is null), '[]'::jsonb),
    'bugs', coalesce((select jsonb_agg(app.dev_bug_json(b) || jsonb_build_object(
        'tasks', coalesce((select jsonb_agg(jsonb_build_object('key', app.dev_key(w.product, w.seq), 'title', w.title, 'done', w.status = 'done') order by w.seq)
                           from app.dev_work_items w where w.bug_id = b.id and w.archived_at is null), '[]'::jsonb),
        'updated_at', b.updated_at,
        'log', app.dev_log('dev_bug', b.id)) order by b.number)
      from app.dev_bugs b where b.state = 'open' or b.updated_at > now() - interval '90 days'), '[]'::jsonb),
    'staff', app.dev_staff(),
    'can_add', app.can('dev', 'add'));
end $fn$;

-- ===========================================================================
-- 12. Claude: three features, their context, and using a draft
-- ===========================================================================
-- the item as Claude reads it: Sentral's own fields, staff-written titles and counts. Never a ticket's text or subject,
-- never a feature request's problem text, never an organisation's or a person's name, never an amount.
create function app.dev_ai_item(p_item uuid) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare i app.dev_roadmap_items; e jsonb; v text; v_name text;
begin
  select * into i from app.dev_roadmap_items x where x.id = p_item and x.archived_at is null;
  if i.id is null then return null; end if;
  e := app.dev_evidence(i.id);
  v_name := case when i.product = 'sentral' then 'Sentral (the internal admin platform)' else coalesce((select p.name from app.products p where p.key = i.product), i.product) end;
  v := 'Product: ' || v_name || E'\n'
    || 'Roadmap item: ' || app.dev_key(i.product, i.seq) || ' ' || i.title || E'\n'
    || 'Goal: ' || coalesce(i.goal, 'not set') || E'\n'
    || 'Lane: ' || i.lane || E'\n'
    || 'Delivery status: ' || replace(i.status, '_', ' ') || E'\n';
  v := v || E'\nEvidence (counts only):\n';
  if e ? 'requests' then
    v := v || '- ' || (e ->> 'votes') || ' organisations voted on ' || (e ->> 'requests') || ' feature request(s): '
           || (select string_agg(f.title, '; ' order by f.ref) from app.dev_roadmap_links l join app.feature_requests f on f.id = l.ref
               where l.item_id = i.id and l.kind = 'feature_request') || E'\n';
  end if;
  if e ? 'tickets' then v := v || '- ' || (e ->> 'tickets') || E' linked support ticket(s)\n'; end if;
  if e ? 'deals' then v := v || '- ' || (e -> 'deals' ->> 'n') || E' open sales deal(s) waiting for it\n'; end if;
  if jsonb_array_length(coalesce(e -> 'experiments', '[]'::jsonb)) > 0 then
    v := v || '- growth experiment(s): '
           || (select string_agg(x.hypothesis || ' (' || x.stage || coalesce(', ' || x.outcome, '') || ')', '; ')
               from app.dev_roadmap_links l join app.growth_experiments x on x.id = l.ref where l.item_id = i.id and l.kind = 'experiment') || E'\n';
  end if;
  if jsonb_array_length(coalesce(e -> 'seo', '[]'::jsonb)) > 0 then v := v || '- ' || jsonb_array_length(e -> 'seo') || E' SEO content plan item(s)\n'; end if;
  if not (e ? 'requests' or e ? 'tickets' or e ? 'deals') and jsonb_array_length(coalesce(e -> 'experiments', '[]'::jsonb)) = 0 then
    v := v || E'- none recorded\n';
  end if;
  return v;
end $fn$;

create function app.dev_ai_spec_text(p_item uuid) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select E'\nCurrent spec ' || 'RFC-' || lpad(s.number::text, 3, '0') || ' (' || s.title || E'):\n'
      || '## Problem' || E'\n' || coalesce(s.problem, '(empty)') || E'\n'
      || '## Options' || E'\n' || coalesce(s.options, '(empty)') || E'\n'
      || '## Decision' || E'\n' || coalesce(s.decision, '(empty)') || E'\n'
      || '## Privacy and anonymity' || E'\n' || coalesce(s.privacy, '(empty)') || E'\n'
      || '## Rollout' || E'\n' || coalesce(s.rollout, '(empty)') || E'\n'
  from app.dev_specs s where s.roadmap_item_id = p_item
$fn$;

create function app.dev_ai_rules() returns text
  language sql immutable set search_path = ''
as $fn$
  select 'Sentral is the internal admin platform of a company that builds Norwegian B2B SaaS products. Its first product, Orgpuls, '
      || 'surveys the psychosocial work environment and promises that no single survey answer can be traced to a person: '
      || 'survey answers never leave Orgpuls and Sentral never reads them. Use only the facts given; do not invent figures, '
      || 'customers or dates. Write in the language of the roadmap item''s title.'
$fn$;

create function app.ai_ctx_spec_draft(p_subject uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v text := app.dev_ai_item(p_subject);
begin
  if v is null then return null; end if;
  return jsonb_build_object(
    'system', app.dev_ai_rules() || ' You draft an engineering spec (an RFC) for the roadmap item. Answer with exactly five sections, '
           || 'each starting with its heading on a line of its own, in this order: «## Problem», «## Options», «## Decision», '
           || '«## Privacy and anonymity», «## Rollout». Plain prose or short lists under each heading; no other headings, no preamble. '
           || 'Under Privacy and anonymity, say whether the change touches survey data or personal data, and how it stays within the rules above.',
    'prompt', v || coalesce(app.dev_ai_spec_text(p_subject), ''));
end $fn$;

create function app.ai_ctx_task_plan(p_subject uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v text := app.dev_ai_item(p_subject); v_work text;
begin
  if v is null then return null; end if;
  select string_agg('- ' || app.dev_key(w.product, w.seq) || ' ' || w.kind || ': ' || w.title || ' (' || replace(w.status, '_', ' ') || ')', E'\n' order by w.seq)
    into v_work from app.dev_work_items w where w.roadmap_item_id = p_subject and w.archived_at is null;
  return jsonb_build_object(
    'system', app.dev_ai_rules() || ' You break the roadmap item into small, testable work items that are not on the board yet. '
           || 'Answer with one work item per line, in the form «- Kind: title», where Kind is Story, Task, Spike or Bug and the title is '
           || 'under 120 characters. At most 12 lines. No other text.',
    'prompt', v || coalesce(app.dev_ai_spec_text(p_subject), E'\nNo spec yet.\n')
           || E'\nWork items already on the board:\n' || coalesce(v_work, '- none') || E'\n');
end $fn$;

create function app.ai_ctx_release_note_draft(p_subject uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v text := app.dev_ai_item(p_subject); v_done text;
begin
  if v is null then return null; end if;
  select string_agg('- ' || w.kind || ': ' || w.title, E'\n' order by w.done_at)
    into v_done from app.dev_work_items w where w.roadmap_item_id = p_subject and w.archived_at is null and w.status = 'done';
  if v_done is null then return null; end if;
  return jsonb_build_object(
    'system', app.dev_ai_rules() || ' You write customer-facing release notes for the finished work. One note per line, in the form '
           || '«- New: …», «- Improved: …» or «- Fixed: …», each under 160 characters, in plain language, without internal ids or names. '
           || 'At most 6 lines. No other text.',
    'prompt', v || E'\nFinished work items:\n' || v_done || E'\n');
end $fn$;

insert into app.ai_features (key, scope, action, subject_type, context_fn, max_tokens) values
  ('spec_draft', 'dev', 'add', 'dev_roadmap_item', 'app.ai_ctx_spec_draft', 4000),
  ('task_plan', 'dev', 'add', 'dev_roadmap_item', 'app.ai_ctx_task_plan', 2000),
  ('release_note_draft', 'dev', 'add', 'dev_roadmap_item', 'app.ai_ctx_release_note_draft', 1500)
on conflict (key) do nothing;

-- the jobs: every call of the three features in 30 days with its draft, and the usage they add up to
create function public.dev_jobs_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see'); v_month timestamptz := date_trunc('month', now() at time zone 'Europe/Oslo') at time zone 'Europe/Oslo';
begin
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'feature', c.feature, 'at', c.at, 'state', c.state, 'error', c.error_code, 'model', c.model,
        'input_tokens', c.input_tokens, 'output_tokens', c.output_tokens, 'latency_ms', c.latency_ms,
        'by', app.dev_staff_name(c.staff_id),
        'item', (select jsonb_build_object('id', i.id, 'key', app.dev_key(i.product, i.seq), 'title', i.title) from app.dev_roadmap_items i where i.id = c.subject_id),
        'output', (select jsonb_build_object('id', o.id, 'state', o.state, 'chars', char_length(o.body)) from app.ai_outputs o where o.ai_call_id = c.id))
        order by c.at desc)
      from (select * from app.ai_calls x where x.feature in ('spec_draft', 'task_plan', 'release_note_draft') and x.at > now() - interval '30 days'
            order by x.at desc limit 100) c), '[]'::jsonb),
    'kpi', jsonb_build_object(
      'calls', (select count(*) from app.ai_calls x where x.feature in ('spec_draft', 'task_plan', 'release_note_draft') and x.at > now() - interval '30 days'),
      'failed', (select count(*) from app.ai_calls x where x.feature in ('spec_draft', 'task_plan', 'release_note_draft') and x.at > now() - interval '30 days'
                 and x.state not in ('ok', 'retried_ok')),
      'drafts', (select count(*) from app.ai_outputs o where o.feature in ('spec_draft', 'task_plan', 'release_note_draft') and o.created_at > now() - interval '30 days'),
      'used', (select count(*) from app.ai_outputs o where o.feature in ('spec_draft', 'task_plan', 'release_note_draft') and o.created_at > now() - interval '30 days' and o.state = 'used'),
      'discarded', (select count(*) from app.ai_outputs o where o.feature in ('spec_draft', 'task_plan', 'release_note_draft') and o.created_at > now() - interval '30 days' and o.state = 'discarded'),
      'median_ms', (select percentile_cont(0.5) within group (order by x.latency_ms) from app.ai_calls x
                    where x.feature in ('spec_draft', 'task_plan', 'release_note_draft') and x.at > now() - interval '30 days' and x.state in ('ok', 'retried_ok') and x.latency_ms is not null),
      'tokens_month', (select coalesce(sum(coalesce(x.input_tokens, 0) + coalesce(x.output_tokens, 0)), 0) from app.ai_calls x
                       where x.feature in ('spec_draft', 'task_plan', 'release_note_draft') and x.at >= v_month),
      'cost_micros_month', (select sum(x.cost_micros) from app.ai_calls x where x.feature in ('spec_draft', 'task_plan', 'release_note_draft') and x.at >= v_month
                            having count(*) = count(x.cost_micros) and count(*) > 0)));
end $fn$;

-- «Use»: a person accepts a draft; it becomes the item's spec (a new revision), work items in Backlog, or draft release
-- notes (0078), each for a person to edit. The app parses the draft; this checks every value again.
create function public.dev_ai_apply(p_output uuid, p_payload jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('dev', 'add'); o app.ai_outputs; i app.dev_roadmap_items; s app.dev_specs; x jsonb; n int := 0; f text;
begin
  select * into o from app.ai_outputs y where y.id = p_output and y.feature in ('spec_draft', 'task_plan', 'release_note_draft') for update;
  if o.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if o.state <> 'ready' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  select * into i from app.dev_roadmap_items y where y.id = o.subject_id and y.archived_at is null;
  if i.id is null then raise exception 'not_found' using errcode = 'no_data_found', detail = 'subject'; end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
  if o.feature = 'spec_draft' then
    foreach f in array array['problem', 'options', 'decision', 'privacy', 'rollout'] loop
      if jsonb_typeof(p_payload -> f) is distinct from 'string' or char_length(p_payload ->> f) > 8000 then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = f;
      end if;
    end loop;
    select * into s from app.dev_specs y where y.roadmap_item_id = i.id for update;
    if s.id is null then
      insert into app.dev_specs (product, title, roadmap_item_id, author_id, problem, options, decision, privacy, rollout)
      values (i.product, i.title, i.id, v_me, nullif(btrim(p_payload ->> 'problem'), ''), nullif(btrim(p_payload ->> 'options'), ''),
              nullif(btrim(p_payload ->> 'decision'), ''), nullif(btrim(p_payload ->> 'privacy'), ''), nullif(btrim(p_payload ->> 'rollout'), ''))
      returning * into s;
    else
      update app.dev_specs y set problem = nullif(btrim(p_payload ->> 'problem'), ''), options = nullif(btrim(p_payload ->> 'options'), ''),
        decision = nullif(btrim(p_payload ->> 'decision'), ''), privacy = nullif(btrim(p_payload ->> 'privacy'), ''),
        rollout = nullif(btrim(p_payload ->> 'rollout'), ''), revision = y.revision + 1,
        status = case when y.status = 'approved' then 'in_review' else y.status end, updated_at = now(), version = y.version + 1
      where y.id = s.id returning * into s;
    end if;
    n := 1;
    perform app.log('dev_spec.changed', 'dev_spec', s.id::text, jsonb_build_object('source', 'ai', 'revision', s.revision));
  elsif o.feature = 'task_plan' then
    if jsonb_typeof(p_payload -> 'tasks') is distinct from 'array' or jsonb_array_length(p_payload -> 'tasks') not between 1 and 20 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'tasks';
    end if;
    for x in select value from jsonb_array_elements(p_payload -> 'tasks') loop
      if coalesce(x ->> 'kind', '') not in ('story', 'bug', 'task', 'spike') or char_length(btrim(coalesce(x ->> 'title', ''))) not between 3 and 200 then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'tasks';
      end if;
      insert into app.dev_work_items (product, seq, kind, title, status, ord, roadmap_item_id, created_by)
      values (i.product, app.dev_next_seq(i.product), x ->> 'kind', btrim(x ->> 'title'), 'backlog',
              coalesce((select max(y.ord) + 1 from app.dev_work_items y where y.status = 'backlog' and y.archived_at is null), 0), i.id, v_me);
      n := n + 1;
    end loop;
    perform app.log('dev_work.planned', 'dev_roadmap_item', i.id::text, jsonb_build_object('source', 'ai', 'added', n));
  else
    if jsonb_typeof(p_payload -> 'notes') is distinct from 'array' or jsonb_array_length(p_payload -> 'notes') not between 1 and 10 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'notes';
    end if;
    for x in select value from jsonb_array_elements(p_payload -> 'notes') loop
      perform public.release_note_save(null, i.product, x ->> 'kind', x ->> 'title', null, null, 'ai');
      n := n + 1;
    end loop;
  end if;
  update app.ai_outputs y set state = 'used', decided_at = now() where y.id = p_output;
  perform app.log('dev_ai.used', 'dev_roadmap_item', i.id::text, jsonb_build_object('feature', o.feature, 'created', n));
  return jsonb_build_object('ok', true, 'created', n, 'feature', o.feature, 'spec', s.id);
end $fn$;

-- ===========================================================================
-- 13. rights on the functions
-- ===========================================================================
do $$
declare f text;
begin
  foreach f in array array[
    'app.dev_next_seq(text)', 'app.dev_key(text, int)', 'app.dev_business_day(date)', 'app.dev_business_days(date, date)',
    'app.dev_setting_number(text, numeric)', 'app.dev_targets()', 'app.dev_bug_due(timestamptz, text)', 'app.dev_sandbox()',
    'app.dev_ticket_ok(app.tickets)', 'app.dev_deal_ok(app.deals)', 'app.dev_seo_ok()', 'app.dev_evidence(uuid)', 'app.dev_item_links(uuid)',
    'app.dev_staff_name(uuid)', 'app.dev_item_json(app.dev_roadmap_items)', 'app.dev_work_json(app.dev_work_items)',
    'app.dev_bug_ticket_ids(app.dev_bugs)', 'app.dev_bug_json(app.dev_bugs)', 'app.dev_spec_json(app.dev_specs)', 'app.dev_staff()',
    'app.dev_log(text, uuid)', 'app.dev_current_sprint()', 'app.dev_ticket_by_number(bigint)', 'app.dev_problem_ok(uuid)',
    'app.dev_ai_item(uuid)', 'app.dev_ai_spec_text(uuid)', 'app.dev_ai_rules()', 'app.dev_today()',
    'app.ai_ctx_spec_draft(uuid)', 'app.ai_ctx_task_plan(uuid)', 'app.ai_ctx_release_note_draft(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'public.dev_roadmap_get(text)', 'public.dev_roadmap_add(text, text, text, text)', 'public.dev_roadmap_set(uuid, int, jsonb)',
    'public.dev_roadmap_move(uuid, text, int)', 'public.dev_roadmap_archive(uuid, int)', 'public.dev_roadmap_link(uuid, text, uuid, bigint, boolean)',
    'public.dev_roadmap_promote(text, uuid)', 'public.dev_board_get()', 'public.dev_work_item_save(uuid, int, jsonb)',
    'public.dev_work_item_move(uuid, text, int)', 'public.dev_work_item_archive(uuid, int)', 'public.dev_sprint_save(uuid, text, date, date)',
    'public.dev_bugs_get(text)', 'public.dev_open_bugs(text)', 'public.dev_bug_create(text, text, text, text, uuid, bigint[])',
    'public.dev_bug_set(uuid, int, jsonb)', 'public.dev_bug_link(uuid, bigint, boolean)', 'public.dev_bug_merge(uuid, uuid, int)',
    'public.dev_bug_fix(uuid, int, text)', 'public.dev_specs_get()', 'public.dev_spec_save(uuid, int, jsonb)',
    'public.dev_spec_status(uuid, text, int)', 'public.dev_spec_sign(uuid, text, boolean)', 'public.dev_files_get()',
    'public.dev_jobs_get()', 'public.dev_ai_apply(uuid, jsonb)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
