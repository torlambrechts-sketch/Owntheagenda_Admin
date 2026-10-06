-- 0013_customers.sql — what the Customers screen reads about a customer company: its product tenants and
-- subscriptions, its users as the product reports them, survey rounds as counts (D-19, D-21: invited,
-- delivered, bounced, answered — never answers or respondents), activation milestones, structure counts,
-- support-access grants, the plan catalogue, and the audit trail scoped to the company.
--
-- Product events beyond 0001's kinds are projected by a trigger on app.events_in: survey.round,
-- counts.updated, milestone.reached and member.state. Orgpuls adds them as count-only events (D-21); until
-- it does, these tables are empty and the screen shows its empty treatment.

-- ---------------------------------------------------------------------------
alter table app.members
  add column last_login_at     timestamptz,
  add column mfa_enabled       boolean,
  add column auth_method       text check (auth_method is null or auth_method in ('password', 'magic_link', 'google', 'microsoft', 'sso')),
  add column invite_state      text check (invite_state is null or invite_state in ('pending', 'accepted')),
  add column invited_at        timestamptz,
  add column invited_by        text,
  add column is_billing_contact boolean not null default false;

create table app.product_survey_rounds (
  product          text not null,
  tenant_id        text not null,
  round_ref        text not null check (char_length(round_ref) between 1 and 100),
  name             text check (name is null or char_length(name) <= 120),
  kind             text check (kind is null or kind in ('main', 'pulse')),
  planned_at       timestamptz,
  opens_at         timestamptz,
  closes_at        timestamptz,
  invited          int check (invited is null or invited >= 0),
  delivered        int check (delivered is null or delivered >= 0),
  bounced          int check (bounced is null or bounced >= 0),
  answered         int check (answered is null or answered >= 0),
  reminders_sent   int check (reminders_sent is null or reminders_sent >= 0),
  gained_after_reminders int check (gained_after_reminders is null or gained_after_reminders >= 0),
  updated_at       timestamptz not null default now(),
  primary key (product, tenant_id, round_ref),
  foreign key (product, tenant_id) references app.account_products (product, tenant_id) on delete cascade
);

create table app.product_counts (
  product   text not null,
  tenant_id text not null,
  metric    text not null check (metric ~ '^[a-z_]{2,40}$'),
  value     int not null check (value >= 0),
  as_of     timestamptz not null default now(),
  primary key (product, tenant_id, metric),
  foreign key (product, tenant_id) references app.account_products (product, tenant_id) on delete cascade
);

create table app.activation_milestones (
  product    text not null,
  tenant_id  text not null,
  key        text not null check (key in ('account_created', 'employees_uploaded', 'survey_scheduled', 'survey_sent', 'result_unlocked',
                                          'results_viewed', 'first_tiltak', 'converted')),
  reached_at timestamptz not null,
  primary key (product, tenant_id, key),
  foreign key (product, tenant_id) references app.account_products (product, tenant_id) on delete cascade
);

-- support access instead of impersonation: the customer approves, time-boxed, read-only (the product
-- approves and reports page views; the request command is added to the product when this ships, D-40)
create table app.support_access_grants (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations (id) on delete cascade,
  product         text not null references app.products (key),
  staff_id        uuid not null references app.admins (id) on delete cascade,
  reason          text not null check (char_length(btrim(reason)) between 1 and 300),
  hours           int not null check (hours in (24, 72)),
  state           text not null default 'pending' check (state in ('pending', 'active', 'expired', 'revoked', 'denied')),
  requested_at    timestamptz not null default now(),
  approved_by     text,
  approved_at     timestamptz,
  expires_at      timestamptz,
  page_views      int not null default 0,
  is_sample       boolean not null default false
);

-- the plan catalogue: append-only versions (a price change is a new version)
create table app.plan_versions (
  id            uuid primary key default gen_random_uuid(),
  product       text not null references app.products (key),
  band_label    text not null check (char_length(band_label) between 1 and 40),
  min_employees int not null check (min_employees >= 0),
  max_employees int check (max_employees is null or max_employees >= min_employees),
  monthly_price numeric(12, 2) not null check (monthly_price >= 0),
  annual_price  numeric(12, 2) check (annual_price is null or annual_price >= 0),
  version       int not null default 1,
  active        boolean not null default true,
  valid_from    timestamptz not null default now(),
  unique (product, band_label, version)
);

create table app.coupons (
  code        text primary key check (code ~ '^[A-Z0-9_-]{3,30}$'),
  description text check (description is null or char_length(description) <= 200),
  percent     numeric(5, 2) check (percent is null or percent between 0 and 100),
  months      int check (months is null or months > 0),
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- projection of the count-only product events (D-21). The payloads carry counts, dates and ids only.
create function app.project_product_event() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare p jsonb := new.payload;
begin
  if new.tenant_id is null or not exists (select 1 from app.account_products where product = new.product and tenant_id = new.tenant_id) then return new; end if;
  case new.kind
    when 'survey.round' then
      insert into app.product_survey_rounds (product, tenant_id, round_ref, name, kind, planned_at, opens_at, closes_at, invited, delivered, bounced, answered,
                                             reminders_sent, gained_after_reminders, updated_at)
      values (new.product, new.tenant_id, left(p ->> 'round_id', 100), left(p ->> 'name', 120), case when p ->> 'kind' in ('main', 'pulse') then p ->> 'kind' end,
              (p ->> 'planned_at')::timestamptz, (p ->> 'opens_at')::timestamptz, (p ->> 'closes_at')::timestamptz,
              (p ->> 'invited')::int, (p ->> 'delivered')::int, (p ->> 'bounced')::int, (p ->> 'answered')::int,
              (p ->> 'reminders_sent')::int, (p ->> 'gained_after_reminders')::int, new.occurred_at)
      on conflict (product, tenant_id, round_ref) do update set name = coalesce(excluded.name, app.product_survey_rounds.name),
        kind = coalesce(excluded.kind, app.product_survey_rounds.kind), planned_at = coalesce(excluded.planned_at, app.product_survey_rounds.planned_at),
        opens_at = coalesce(excluded.opens_at, app.product_survey_rounds.opens_at), closes_at = coalesce(excluded.closes_at, app.product_survey_rounds.closes_at),
        invited = coalesce(excluded.invited, app.product_survey_rounds.invited), delivered = coalesce(excluded.delivered, app.product_survey_rounds.delivered),
        bounced = coalesce(excluded.bounced, app.product_survey_rounds.bounced), answered = coalesce(excluded.answered, app.product_survey_rounds.answered),
        reminders_sent = coalesce(excluded.reminders_sent, app.product_survey_rounds.reminders_sent),
        gained_after_reminders = coalesce(excluded.gained_after_reminders, app.product_survey_rounds.gained_after_reminders), updated_at = excluded.updated_at
      where app.product_survey_rounds.updated_at <= excluded.updated_at;
    when 'counts.updated' then
      insert into app.product_counts (product, tenant_id, metric, value, as_of)
      select new.product, new.tenant_id, k, (v #>> '{}')::int, new.occurred_at from jsonb_each(p) as x(k, v)
      where k ~ '^[a-z_]{2,40}$' and jsonb_typeof(v) = 'number'
      on conflict (product, tenant_id, metric) do update set value = excluded.value, as_of = excluded.as_of where app.product_counts.as_of <= excluded.as_of;
    when 'milestone.reached' then
      insert into app.activation_milestones (product, tenant_id, key, reached_at) values (new.product, new.tenant_id, p ->> 'key', new.occurred_at) on conflict do nothing;
    when 'member.state' then
      update app.members set last_login_at = coalesce((p ->> 'last_login_at')::timestamptz, last_login_at),
        mfa_enabled = coalesce((p ->> 'mfa_enabled')::boolean, mfa_enabled), auth_method = coalesce(p ->> 'auth_method', auth_method),
        invite_state = coalesce(p ->> 'invite_state', invite_state), invited_at = coalesce((p ->> 'invited_at')::timestamptz, invited_at),
        invited_by = coalesce(p ->> 'invited_by', invited_by), is_billing_contact = coalesce((p ->> 'is_billing_contact')::boolean, is_billing_contact)
      where product = new.product and tenant_id = new.tenant_id and user_id = p ->> 'user_id';
    else null;
  end case;
  return new;
exception when others then
  return new;   -- a malformed count never blocks the raw event; it stays in events_in for a later reader
end $fn$;
create trigger events_in_project after insert on app.events_in for each row
  when (new.kind in ('survey.round', 'counts.updated', 'milestone.reached', 'member.state')) execute function app.project_product_event();

-- ---------------------------------------------------------------------------
-- the customer list: organizations with their product state
create function app.org_customer(o app.organizations, p_product text default null) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  with subs as (
    select s.*, ap.created_at ap_created, app.sub_status(s) st, app.sub_mrr(s) mrr, ap.details
    from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
    where ap.account_id = o.account_id and ap.status = 'active' and (p_product is null or p_product = 'all' or true)
  ), rounds as (
    select r.* from app.product_survey_rounds r join app.account_products ap on ap.product = r.product and ap.tenant_id = r.tenant_id
    where ap.account_id = o.account_id
  )
  select jsonb_build_object(
    'id', o.id, 'name', o.name, 'org_number', o.org_number, 'account_id', o.account_id, 'industry', o.industry, 'fylke', o.fylke, 'city', o.city,
    'source', o.source, 'ehf', o.ehf, 'labels', to_jsonb(o.labels), 'owner_id', o.owner_id, 'csm_id', o.csm_id, 'version', o.version,
    'owner', (select a.name from app.admins a where a.id = o.owner_id),
    'employees', coalesce((select max((s.details ->> 'employees')::int) from subs s where s.details ? 'employees'), o.employees),
    'products', coalesce((select jsonb_agg(jsonb_build_object('key', s.product, 'status', s.st) order by s.product) from subs s), '[]'::jsonb),
    -- one status per company: the worst state across its products, in this order
    'status', (select s.st from subs s order by array_position(array['suspended', 'past_due', 'active', 'free', 'trial', 'expired', 'cancelled'], s.st) limit 1),
    'plan', (select s.plan from subs s where s.product = 'orgpuls' limit 1),
    'mrr', (select coalesce(sum(s.mrr), 0) from subs s),
    'priced', exists (select 1 from subs s where s.price is not null),
    'trial_ends_at', (select min(s.trial_ends_at) from subs s where s.st = 'trial'),
    'signup_at', (select min(s.ap_created) from subs s),
    'last_survey_at', (select max(coalesce(r.opens_at, r.closes_at)) from rounds r where r.delivered is not null),
    'response', (select round(100.0 * r.answered / nullif(r.delivered, 0)) from rounds r where r.closes_at < now() and r.delivered > 0 order by r.closes_at desc limit 1),
    'health', null,
    'is_sample', o.is_sample)
$fn$;

create function public.customers_get(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_rows jsonb; v_views jsonb;
begin
  with base as (
    select app.org_customer(o, q ->> 'product') j from app.organizations o
    where o.deleted_at is null and app.visible(o.owner_id, o.visibility) and (v_sandbox or not o.is_sample)
      and (q ->> 'product' is null or q ->> 'product' = 'all'
           or exists (select 1 from app.account_products ap where ap.account_id = o.account_id and ap.product = q ->> 'product' and ap.status = 'active'))
      and (q ->> 'customers_only' is null or o.account_id is not null)
  ), viewed as (
    select j, jsonb_build_object(
      'trials_week_no_survey', j ->> 'status' = 'trial' and (j ->> 'trial_ends_at')::timestamptz <= now() + interval '7 days' and j ->> 'last_survey_at' is null,
      'at_risk', (j ->> 'health')::int < 40 and j ->> 'status' <> 'cancelled',
      'past_due', j ->> 'status' = 'past_due',
      'multi_product', jsonb_array_length(j -> 'products') > 1,
      'ehf', (j ->> 'ehf')::boolean) v
    from base
  )
  select
    coalesce((select jsonb_agg(j order by j ->> 'name') from viewed
      where (q ->> 'view' is null or q ->> 'view' = 'all' or coalesce((v ->> (q ->> 'view'))::boolean, false))
        and (btrim(coalesce(q ->> 'q', '')) = '' or (j ->> 'name') ilike '%' || btrim(q ->> 'q') || '%' or (j ->> 'org_number') like '%' || regexp_replace(q ->> 'q', '\s', '', 'g') || '%'
             or exists (select 1 from app.members m join app.account_products ap on ap.product = m.product and ap.tenant_id = m.tenant_id
                        where ap.account_id = (j ->> 'account_id')::uuid and m.email ilike '%' || btrim(q ->> 'q') || '%'))
        and (q #>> '{f,status}' is null or j ->> 'status' = q #>> '{f,status}')
        and (q #>> '{f,plan}' is null or j ->> 'plan' = q #>> '{f,plan}')
        and (q #>> '{f,industry}' is null or j ->> 'industry' = q #>> '{f,industry}')
        and (q #>> '{f,fylke}' is null or j ->> 'fylke' = q #>> '{f,fylke}')
        and (q #>> '{f,source}' is null or j ->> 'source' = q #>> '{f,source}')
        and (q #>> '{f,product}' is null or (j -> 'products') @> jsonb_build_array(jsonb_build_object('key', q #>> '{f,product}')))
        and (q #>> '{f,health}' is null or case q #>> '{f,health}' when 'risk' then (j ->> 'health')::int < 40 when 'watch' then (j ->> 'health')::int between 40 and 69
                                                                    when 'healthy' then (j ->> 'health')::int >= 70 else true end)), '[]'::jsonb),
    jsonb_build_object('all', (select count(*) from viewed),
      'trials_week_no_survey', (select count(*) from viewed where (v ->> 'trials_week_no_survey')::boolean),
      'at_risk', (select count(*) from viewed where coalesce((v ->> 'at_risk')::boolean, false)),
      'past_due', (select count(*) from viewed where (v ->> 'past_due')::boolean),
      'multi_product', (select count(*) from viewed where (v ->> 'multi_product')::boolean),
      'ehf', (select count(*) from viewed where (v ->> 'ehf')::boolean))
  into v_rows, v_views;
  perform app.log('record.listed', 'organization', null, jsonb_build_object('count', jsonb_array_length(v_rows), 'view', 'customers'));
  return jsonb_build_object('rows', v_rows, 'views', v_views,
    'facets', jsonb_build_object(
      'plans', coalesce((select jsonb_agg(distinct s.plan) from app.subscriptions s where s.plan is not null), '[]'::jsonb),
      'industries', coalesce((select jsonb_agg(distinct o.industry) from app.organizations o where o.industry is not null and o.deleted_at is null), '[]'::jsonb),
      'fylker', coalesce((select jsonb_agg(distinct o.fylke) from app.organizations o where o.fylke is not null and o.deleted_at is null), '[]'::jsonb),
      'sources', coalesce((select jsonb_agg(distinct o.source) from app.organizations o where o.source is not null and o.deleted_at is null), '[]'::jsonb)));
end $fn$;

-- one customer company, everything its detail tabs show
create function public.customer_detail(p_org uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); o app.organizations; v_sandbox boolean := (select sandbox from app.admins where id = v_me);
begin
  select * into o from app.organizations where id = p_org;
  if not found or not app.visible(o.owner_id, o.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.recents (staff_id, entity, record_id) values (v_me, 'organization', p_org) on conflict (staff_id, entity, record_id) do update set at = now();
  perform app.log('record.read', 'organization', p_org::text, null, o.account_id);
  return app.org_customer(o) || jsonb_build_object(
    'address', o.address, 'postal_code', o.postal_code, 'nace', o.nace, 'website', o.website, 'phone', o.phone, 'email', o.email,
    'brreg_synced_at', o.brreg_synced_at, 'parent_id', o.parent_id, 'custom', o.custom, 'registered_employees', o.employees,
    'csm', (select a.name from app.admins a where a.id = o.csm_id),
    'subscriptions', coalesce((select jsonb_agg(jsonb_build_object('product', s.product, 'tenant_id', s.tenant_id, 'plan', s.plan, 'billing_interval', s.billing_interval,
                                 'status', app.sub_status(s), 'mrr', app.sub_mrr(s), 'price', s.price, 'currency', s.currency, 'seats', s.seats,
                                 'trial_ends_at', s.trial_ends_at, 'confirmed_at', s.confirmed_at, 'cancelled_at', s.cancelled_at, 'payment_state', s.payment_state,
                                 'since', ap.created_at) order by s.product)
                               from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
                               where ap.account_id = o.account_id and ap.status = 'active'), '[]'::jsonb),
    'users', coalesce((select jsonb_agg(jsonb_build_object('product', m.product, 'user_id', m.user_id, 'name', m.name, 'email', m.email, 'role', m.role, 'active', m.active,
                         'last_login_at', m.last_login_at, 'mfa_enabled', m.mfa_enabled, 'auth_method', m.auth_method, 'invite_state', m.invite_state,
                         'invited_by', m.invited_by, 'is_billing_contact', m.is_billing_contact) order by m.active desc, m.name)
                       from app.members m join app.account_products ap on ap.product = m.product and ap.tenant_id = m.tenant_id where ap.account_id = o.account_id), '[]'::jsonb),
    'rounds', coalesce((select jsonb_agg(to_jsonb(r) - 'tenant_id' order by coalesce(r.opens_at, r.planned_at) desc nulls last)
                        from app.product_survey_rounds r join app.account_products ap on ap.product = r.product and ap.tenant_id = r.tenant_id where ap.account_id = o.account_id), '[]'::jsonb),
    'counts', coalesce((select jsonb_object_agg(c.metric, c.value) from app.product_counts c join app.account_products ap on ap.product = c.product and ap.tenant_id = c.tenant_id
                        where ap.account_id = o.account_id and c.product = 'orgpuls'), '{}'::jsonb),
    'milestones', coalesce((select jsonb_object_agg(m.key, m.reached_at) from app.activation_milestones m join app.account_products ap on ap.product = m.product and ap.tenant_id = m.tenant_id
                            where ap.account_id = o.account_id and m.product = 'orgpuls'), '{}'::jsonb),
    'deals', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title, 'value', d.value, 'status', d.status, 'stage', s.name) order by d.created_at desc)
                       from app.deals d join app.stages s on s.id = d.stage_id where d.organization_id = o.id and d.deleted_at is null and app.visible(d.owner_id, d.visibility)
                         and (v_sandbox or not d.is_sample)), '[]'::jsonb),
    'contacts', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'title', p.title, 'email', p.email, 'marketing_status', p.marketing_status) order by p.name)
                          from app.people p where p.organization_id = o.id and p.deleted_at is null and app.visible(p.owner_id, p.visibility) and (v_sandbox or not p.is_sample)), '[]'::jsonb),
    'access_grants', coalesce((select jsonb_agg(to_jsonb(g) order by g.requested_at desc) from app.support_access_grants g where g.organization_id = o.id), '[]'::jsonb));
end $fn$;

-- the company's timeline: product events by kind, admin actions, tickets, CRM changes
create function public.customer_timeline(p_org uuid, p_limit int default 60) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare o app.organizations;
begin
  perform app.require('deals', 'see');
  select * into o from app.organizations where id = p_org;
  if not found or not app.visible(o.owner_id, o.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(x order by x ->> 'at' desc) from (
      (select jsonb_build_object('at', e.occurred_at, 'kind', case when e.kind like 'billing.%' then 'billing' when e.kind like 'member.%' then 'logins' else 'activation' end,
              'event', e.kind, 'product', e.product) x
       from app.events_in e join app.account_products ap on ap.product = e.product and ap.tenant_id = e.tenant_id where ap.account_id = o.account_id
       order by e.occurred_at desc limit p_limit)
      union all
      (select jsonb_build_object('at', a.at, 'kind', 'admin', 'event', coalesce(a.action, a.command), 'actor', coalesce(s.name, a.actor), 'reason', a.reason)
       from app.audit a left join app.admins s on s.id = a.staff_id
       where (a.account_id = o.account_id or (a.target_type = 'organization' and a.target_id = o.id::text)) and coalesce(a.action, '') not in ('record.read', 'record.listed')
       order by a.at desc limit p_limit)
      union all
      (select jsonb_build_object('at', t.created_at, 'kind', 'support', 'event', 'ticket.created', 'ref', 'T-' || t.number, 'status', t.status)
       from app.tickets t where t.organization_id = o.id and t.deleted_at is null order by t.created_at desc limit p_limit)
    ) s), '[]'::jsonb);
end $fn$;

-- the company's audit trail: writes and reads, with the reason when one was typed
create function public.customer_audit(p_org uuid, p_limit int default 100) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare o app.organizations;
begin
  perform app.require('global', 'see');
  select * into o from app.organizations where id = p_org;
  if not found or not app.visible(o.owner_id, o.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('at', a.at, 'who', coalesce(s.name, a.actor), 'action', coalesce(a.action, a.command), 'reason', a.reason, 'ok', a.ok) order by a.id desc)
                   from (select * from app.audit a where a.account_id = o.account_id or (a.target_type = 'organization' and a.target_id = o.id::text)
                         order by a.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) a left join app.admins s on s.id = a.staff_id), '[]'::jsonb);
end $fn$;

-- product users across companies (Customers › Users)
create function public.members_search(p_q text, p_limit int default 50) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'see'); q text := btrim(coalesce(p_q, ''));
begin
  perform app.log('record.listed', 'member', null, jsonb_build_object('q', char_length(q) > 0));
  return coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('product', m.product, 'tenant_id', m.tenant_id, 'user_id', m.user_id, 'name', m.name, 'email', m.email, 'role', m.role, 'active', m.active,
             'last_login_at', m.last_login_at, 'mfa_enabled', m.mfa_enabled, 'auth_method', m.auth_method, 'invite_state', m.invite_state,
             'invited_by', m.invited_by, 'invited_at', m.invited_at, 'is_billing_contact', m.is_billing_contact,
             'organization', (select jsonb_build_object('id', o.id, 'name', o.name) from app.organizations o where o.account_id = ap.account_id and o.deleted_at is null limit 1)) x
      from app.members m join app.account_products ap on ap.product = m.product and ap.tenant_id = m.tenant_id
      where q = '' or m.email ilike '%' || q || '%' or m.name ilike '%' || q || '%'
      order by m.name limit least(greatest(coalesce(p_limit, 50), 1), 200)) s), '[]'::jsonb);
end $fn$;

-- subscriptions and billing across companies
create function public.billing_overview(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  return (with s as (
      select s.*, app.sub_status(s) st, app.sub_mrr(s) mrr, ap.account_id from app.subscriptions s
      join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
      where ap.status = 'active' and (p_product is null or p_product = 'all' or s.product = p_product))
    select jsonb_build_object(
      'mrr', (select coalesce(sum(mrr), 0) from s), 'priced', (select count(*) from s where price is not null),
      'past_due_mrr', (select coalesce(sum(price), 0) from s where st = 'past_due'),
      'ehf', (select count(distinct o.id) from app.organizations o join s on s.account_id = o.account_id where o.ehf and o.deleted_at is null),
      'lifecycle', (select coalesce(jsonb_object_agg(st, n), '{}'::jsonb) from (select st, count(*) n from s group by st) x),
      'failed', coalesce((select jsonb_agg(jsonb_build_object('organization', o.name, 'organization_id', o.id, 'product', s.product, 'amount', s.price, 'state', s.payment_state))
                          from s join app.organizations o on o.account_id = s.account_id and o.deleted_at is null where s.st in ('past_due', 'suspended')), '[]'::jsonb),
      'plans', coalesce((select jsonb_agg(to_jsonb(p) order by p.product, p.min_employees) from app.plan_versions p where p.active), '[]'::jsonb),
      'coupons', coalesce((select jsonb_agg(to_jsonb(c) order by c.code) from app.coupons c where c.active), '[]'::jsonb)));
end $fn$;

create function public.access_request(p_org uuid, p_product text, p_hours int, p_reason text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'add'); v_id uuid;
begin
  insert into app.support_access_grants (organization_id, product, staff_id, reason, hours, is_sample)
  values (p_org, p_product, v_me, btrim(p_reason), p_hours, (select sandbox from app.admins where id = v_me)) returning id into v_id;
  perform app.log('support_access.requested', 'organization', p_org::text, jsonb_build_object('grant', v_id, 'hours', p_hours), (select account_id from app.organizations where id = p_org));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.access_grants_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  return coalesce((select jsonb_agg(to_jsonb(g) || jsonb_build_object('organization', o.name, 'staff', a.name) order by g.requested_at desc)
                   from app.support_access_grants g join app.organizations o on o.id = g.organization_id join app.admins a on a.id = g.staff_id), '[]'::jsonb);
end $fn$;

create function public.privacy_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('tickets', 'see');
  if not app.queue_ok('personvern') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'queue'; end if;
  return coalesce((select jsonb_agg(to_jsonb(p) || jsonb_build_object('ticket_ref', 'T-' || t.number, 'organization', o.name, 'owner', a.name) order by p.due_at)
                   from app.privacy_requests p left join app.tickets t on t.id = p.ticket_id left join app.organizations o on o.id = p.organization_id
                   left join app.admins a on a.id = p.owner_id where p.status in ('received', 'in_progress')), '[]'::jsonb);
end $fn$;

-- the company's activity for a staff member's command (product-command writes the command itself; this
-- records the reason and the company so the action shows in its audit trail)
create function public.customer_action_log(p_org uuid, p_action text, p_reason text, p_ok boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason_required' using errcode = 'invalid_parameter_value'; end if;
  insert into app.audit (actor, staff_id, action, target_type, target_id, account_id, ok, reason)
  values (coalesce(app.admin_email(), 'system'), app.me(), p_action, 'organization', p_org::text, (select account_id from app.organizations where id = p_org), p_ok, left(btrim(p_reason), 300));
  return jsonb_build_object('ok', true);
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['product_survey_rounds', 'product_counts', 'activation_milestones', 'support_access_grants', 'plan_versions', 'coupons'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.project_product_event()', 'app.org_customer(app.organizations, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.customers_get(jsonb)', 'public.customer_detail(uuid)', 'public.customer_timeline(uuid, int)', 'public.customer_audit(uuid, int)',
                           'public.members_search(text, int)', 'public.billing_overview(text)', 'public.access_request(uuid, text, int, text)', 'public.access_grants_get()',
                           'public.privacy_get()', 'public.customer_action_log(uuid, text, text, boolean)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
