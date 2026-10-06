-- 0025_analytics.sql — the platform's own analytics (Analytics, INS/ENT/WEB, D-21, D-37).
--
-- Business figures come from the subscription mirror (billing.changed, D-22) and the count-only product
-- events (D-21). A nightly snapshot per tenant feeds MRR movements (new, expansion, contraction, churn,
-- reactivation), deduplicated paying accounts and cohort retention. Health scores are computed here from
-- the weighted signals of the active health model; a score that falls below 40 emits
-- organization.health_dropped for workflows, and «org_health» becomes a condition for scoring and
-- workflows (PRO-03).
--
-- No survey figure is shown (D-19): rounds are counts and dates. Groups hidden by the threshold and
-- comment counts wait for a decision with Orgpuls and are not built.
--
-- Web analytics is in-house and cookieless (D-37): the tracker's edge function hashes IP and user agent
-- with a daily salt kept in Vault, resolves the company and drops the IP; the database stores the hash
-- only. «Visitors» over a period is a sum of daily uniques. The salt is destroyed every night.

-- ---------------------------------------------------------------------------
-- the mirror: the next renewal, when billing.changed carries it
alter table app.subscriptions add column current_period_end timestamptz;

create function app.billing_period_end() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if new.kind = 'billing.changed' and (new.payload ->> 'current_period_end') is not null then
    update app.subscriptions set current_period_end = (new.payload ->> 'current_period_end')::timestamptz
    where product = new.product and tenant_id = new.tenant_id;
  end if;
  return new;
exception when invalid_datetime_format or datetime_field_overflow then
  return new;
end $fn$;
create trigger events_in_period_end after insert on app.events_in for each row execute function app.billing_period_end();

create or replace function app.sub_renewal(s app.subscriptions) returns timestamptz
  language sql stable set search_path = ''
as $fn$
  select case when s.confirmed_at is null or s.cancelled_at is not null then null
              when s.current_period_end is not null and s.current_period_end > now() then s.current_period_end
              when s.billing_interval = 'year' then s.confirmed_at + make_interval(years => extract(year from age(now(), s.confirmed_at))::int + 1)
              else s.confirmed_at + make_interval(months => (extract(year from age(now(), s.confirmed_at)) * 12 + extract(month from age(now(), s.confirmed_at)))::int + 1) end
$fn$;

-- ---------------------------------------------------------------------------
-- MRR per tenant per day, movements per month, churns and their reasons
create table app.mrr_tenant_daily (
  day       date not null,
  product   text not null,
  tenant_id text not null,
  mrr       numeric not null,
  status    text not null,
  primary key (day, product, tenant_id)
);

create table app.mrr_movements (
  month     date not null,
  product   text not null,
  tenant_id text not null,
  kind      text not null check (kind in ('new', 'expansion', 'contraction', 'churn', 'reactivation')),
  delta     numeric not null,
  primary key (month, product, tenant_id)
);

create table app.churn_reasons (
  id   uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z_]{2,40}$'),
  ord  int not null default 0
);
insert into app.churn_reasons (code, ord) values ('price', 10), ('no_value', 20), ('missing_feature', 30), ('switched_competitor', 40),
  ('company_closed', 50), ('payment_failure', 60), ('other', 90);

create table app.account_churns (
  product         text not null,
  tenant_id       text not null,
  churned_at      timestamptz not null,
  mrr_lost        numeric not null,
  payment_failure boolean not null default false,
  reason_id       uuid references app.churn_reasons (id) on delete set null,
  set_by          uuid references app.admins (id) on delete set null,
  primary key (product, tenant_id, churned_at)
);

create function app.snapshot_mrr_tenants() returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m date := date_trunc('month', current_date)::date; r record; v_prev numeric;
begin
  insert into app.mrr_tenant_daily (day, product, tenant_id, mrr, status)
  select current_date, s.product, s.tenant_id, app.sub_mrr(s), app.sub_status(s)
  from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
  on conflict (day, product, tenant_id) do update set mrr = excluded.mrr, status = excluded.status;
  -- movements this month: today's MRR against the last snapshot before the month began
  for r in select t.product, t.tenant_id, t.mrr,
                  (select p.mrr from app.mrr_tenant_daily p where p.product = t.product and p.tenant_id = t.tenant_id and p.day < m order by p.day desc limit 1) before,
                  exists (select 1 from app.mrr_tenant_daily p where p.product = t.product and p.tenant_id = t.tenant_id and p.day < m and p.mrr > 0) ever_paid,
                  (select s.payment_state from app.subscriptions s where s.product = t.product and s.tenant_id = t.tenant_id) pay
           from app.mrr_tenant_daily t where t.day = current_date loop
    v_prev := coalesce(r.before, 0);
    delete from app.mrr_movements where month = m and product = r.product and tenant_id = r.tenant_id;
    if v_prev = 0 and r.mrr > 0 then
      insert into app.mrr_movements values (m, r.product, r.tenant_id, case when r.ever_paid then 'reactivation' else 'new' end, r.mrr);
    elsif v_prev > 0 and r.mrr = 0 then
      insert into app.mrr_movements values (m, r.product, r.tenant_id, 'churn', -v_prev);
      insert into app.account_churns (product, tenant_id, churned_at, mrr_lost, payment_failure, reason_id)
      values (r.product, r.tenant_id, now(), v_prev, r.pay in ('past_due', 'suspended'),
              case when r.pay in ('past_due', 'suspended') then (select id from app.churn_reasons where code = 'payment_failure') end)
      on conflict do nothing;
    elsif r.mrr > v_prev then
      insert into app.mrr_movements values (m, r.product, r.tenant_id, 'expansion', r.mrr - v_prev);
    elsif r.mrr < v_prev then
      insert into app.mrr_movements values (m, r.product, r.tenant_id, 'contraction', r.mrr - v_prev);
    end if;
  end loop;
end $fn$;
select cron.schedule('platform-mrr-tenants', '15 0 * * *', 'select app.snapshot_mrr_tenants()');

-- ---------------------------------------------------------------------------
-- health (D-21): weighted signals, a versioned model, nightly scores
create table app.health_models (
  id         uuid primary key default gen_random_uuid(),
  version    int not null unique,
  weights    jsonb not null check (jsonb_typeof(weights) = 'object'),
  active     boolean not null default false,
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index health_models_one_active on app.health_models (active) where active;
insert into app.health_models (version, weights, active) values
  (1, '{"admin_login":25,"survey_cadence":25,"response_trend":20,"tiltak_activity":15,"payment":15}', true);

create table app.health_scores (
  product   text not null,
  tenant_id text not null,
  day       date not null,
  score     smallint not null check (score between 0 and 100),
  factors   jsonb not null,
  model_id  uuid not null references app.health_models (id),
  primary key (product, tenant_id, day)
);

-- each signal 0..1, or null when the product has not sent what it needs (then it is left out and the
-- other weights are scaled up)
create function app.health_signals(p_product text, p_tenant text) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  with lr as (select max(m.last_login_at) at from app.members m where m.product = p_product and m.tenant_id = p_tenant and m.role in ('daglig_leder', 'avdelingsleder')),
       rounds as (select r.* from app.product_survey_rounds r where r.product = p_product and r.tenant_id = p_tenant and r.opens_at is not null order by r.opens_at desc limit 2),
       sub as (select s.payment_state, s.confirmed_at from app.subscriptions s where s.product = p_product and s.tenant_id = p_tenant)
  select jsonb_build_object(
    'admin_login', (select case when at is null then null when at > now() - interval '14 days' then 1 when at > now() - interval '30 days' then 0.6
                                when at > now() - interval '60 days' then 0.3 else 0 end from lr),
    'survey_cadence', (select case when count(*) = 0 then null when max(opens_at) > now() - interval '120 days' then 1
                                   when max(opens_at) > now() - interval '240 days' then 0.5 else 0 end from rounds),
    'response_trend', (select case when count(*) < 2 or bool_or(coalesce(invited, 0) = 0) then null else
                                    greatest(0, least(1, 0.5 + 2 * ((max(answered::numeric / invited) filter (where rn = 1)) - (max(answered::numeric / invited) filter (where rn = 2))))) end
                       from (select r.*, row_number() over (order by r.opens_at desc) rn from rounds r) x),
    'tiltak_activity', (select case when c.value is null then null when c.value > 0 then 1 else 0 end
                        from (select max(value) value from app.product_counts where product = p_product and tenant_id = p_tenant and metric in ('tiltak_open', 'tiltak_closed', 'tiltak_created')) c),
    'payment', (select case when payment_state = 'ok' then 1 when payment_state = 'past_due' then 0.3 when payment_state = 'suspended' then 0 end from sub))
$fn$;

create function app.health_compute(p_product text, p_tenant text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m app.health_models; s jsonb := app.health_signals(p_product, p_tenant); k text; w numeric; tot numeric := 0; wsum numeric := 0; f jsonb := '[]'::jsonb;
begin
  select * into m from app.health_models where active;
  for k, w in select key, value::numeric from jsonb_each_text(m.weights) loop
    if s ->> k is not null then
      tot := tot + w * (s ->> k)::numeric; wsum := wsum + w;
      f := f || jsonb_build_array(jsonb_build_object('signal', k, 'weight', w, 'value', (s ->> k)::numeric, 'loss', round(w * (1 - (s ->> k)::numeric), 1)));
    end if;
  end loop;
  if wsum = 0 then return null; end if;
  return jsonb_build_object('score', round(100 * tot / wsum)::int, 'factors', f, 'model', m.id);
end $fn$;

create function app.health_nightly() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; h jsonb; v_prev smallint; n int := 0; v_org uuid;
begin
  for r in select ap.product, ap.tenant_id, ap.account_id from app.account_products ap where ap.status = 'active' loop
    h := app.health_compute(r.product, r.tenant_id);
    continue when h is null;
    v_prev := (select score from app.health_scores where product = r.product and tenant_id = r.tenant_id and day < current_date order by day desc limit 1);
    insert into app.health_scores (product, tenant_id, day, score, factors, model_id)
    values (r.product, r.tenant_id, current_date, (h ->> 'score')::smallint, h -> 'factors', (h ->> 'model')::uuid)
    on conflict (product, tenant_id, day) do update set score = excluded.score, factors = excluded.factors, model_id = excluded.model_id;
    if (h ->> 'score')::int < 40 and (v_prev is null or v_prev >= 40) then
      v_org := (select o.id from app.organizations o where o.account_id = r.account_id and o.deleted_at is null order by o.created_at limit 1);
      if v_org is not null then
        insert into app.events (kind, subject_type, subject_id, payload)
        values ('organization.health_dropped', 'organization', v_org, jsonb_build_object('product', r.product, 'score', (h ->> 'score')::int, 'previous', v_prev));
      end if;
    end if;
    n := n + 1;
  end loop;
  return n;
end $fn$;
select cron.schedule('platform-health', '35 0 * * *', 'select app.health_nightly()');

-- an organisation's health: the lowest latest score of its applications
create function app.org_health(p_org uuid) returns smallint
  language sql stable security definer set search_path = ''
as $fn$
  select min(h.score) from app.organizations o join app.account_products ap on ap.account_id = o.account_id
  cross join lateral (select hs.score from app.health_scores hs where hs.product = ap.product and hs.tenant_id = ap.tenant_id order by hs.day desc limit 1) h
  where o.id = p_org
$fn$;

-- the parts of an organisation's score (its weakest application's factors)
create function app.org_health_parts(p_org uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select hs.factors from app.organizations o join app.account_products ap on ap.account_id = o.account_id
  cross join lateral (select h.factors, h.score from app.health_scores h where h.product = ap.product and h.tenant_id = ap.tenant_id order by h.day desc limit 1) hs
  where o.id = p_org order by hs.score limit 1
$fn$;

-- the customer list and detail read the score and its parts (0013 left them null)
do $$
declare src text;
begin
  src := pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'org_customer'));
  if position($r$'health', null,$r$ in src) = 0 then raise exception 'org_customer changed: health placeholder not found'; end if;
  src := replace(src, $r$'health', null,$r$, $r$'health', app.org_health(o.id), 'health_parts', app.org_health_parts(o.id),$r$);
  execute src;
end $$;

-- scoring and workflow conditions may test health (PRO-03): {f: 'org_health', op: gte|lte|lt|gt|eq, v: n}
create function app.health_test(p_org uuid, p_op text, p_v int) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(case coalesce(p_op, 'gte') when 'gte' then app.org_health(p_org) >= p_v when 'lte' then app.org_health(p_org) <= p_v
                  when 'gt' then app.org_health(p_org) > p_v when 'lt' then app.org_health(p_org) < p_v else app.org_health(p_org) = p_v end, false)
$fn$;

do $$
declare src text;
begin
  -- wf_match gains the org_health test, next to org_payment
  src := pg_get_functiondef('app.wf_match(text, uuid, jsonb)'::regprocedure);
  src := replace(src, $r$      elsif fl ->> 'f' = 'org_payment' then$r$,
                      $r$      elsif fl ->> 'f' = 'org_health' then
        v_hit := v_org is not null and app.health_test(v_org, fl ->> 'op', (fl ->> 'v')::int);
      elsif fl ->> 'f' = 'org_payment' then$r$);
  execute src;
end $$;

-- ---------------------------------------------------------------------------
-- metric definitions: the views reports and the CRM read (versioned here, shown on Metric definitions)
create view app.v_mrr_monthly with (security_invoker = true) as
  select date_trunc('month', day)::date as month, product, sum(mrr) filter (where day = month_end) mrr
  from (select d.*, max(d.day) over (partition by date_trunc('month', d.day), d.product) as month_end from app.mrr_daily d) x
  group by 1, 2;
create view app.v_net_new_mrr with (security_invoker = true) as
  select month, product, sum(delta) filter (where kind in ('new', 'reactivation')) new_mrr, sum(delta) filter (where kind = 'expansion') expansion,
         sum(delta) filter (where kind = 'contraction') contraction, sum(delta) filter (where kind = 'churn') churn, sum(delta) net
  from app.mrr_movements group by 1, 2;
create view app.v_trial_conversion with (security_invoker = true) as
  select date_trunc('month', s.trial_started_at)::date as cohort, s.product, count(*) trials,
         count(*) filter (where s.confirmed_at is not null and s.confirmed_at <= s.trial_started_at + interval '45 days') converted
  from app.subscriptions s where s.trial_started_at is not null group by 1, 2;
create view app.v_activated_orgs with (security_invoker = true) as
  select a.product, a.tenant_id, a.reached_at activated_at from app.activation_milestones a where a.key = 'result_unlocked';
create view app.v_logo_churn with (security_invoker = true) as
  select date_trunc('month', churned_at)::date as month, product, count(*) churned from app.account_churns group by 1, 2;
create view app.v_revenue_churn with (security_invoker = true) as
  select month, product, -sum(delta) filter (where kind in ('churn', 'contraction')) lost from app.mrr_movements group by 1, 2;
create view app.v_health_latest with (security_invoker = true) as
  select distinct on (product, tenant_id) product, tenant_id, day, score, factors from app.health_scores order by product, tenant_id, day desc;

create table app.metric_definitions (
  key       text primary key check (key ~ '^[a-z_]{2,40}$'),
  view_name text not null,
  migration text not null,
  version   int not null,
  ord       int not null default 0
);
insert into app.metric_definitions (key, view_name, migration, version, ord) values
  ('mrr', 'v_mrr_monthly', '0025_analytics.sql', 1, 10), ('net_new_mrr', 'v_net_new_mrr', '0025_analytics.sql', 1, 20),
  ('trial_conversion', 'v_trial_conversion', '0025_analytics.sql', 1, 30), ('activated', 'v_activated_orgs', '0025_analytics.sql', 1, 40),
  ('logo_churn', 'v_logo_churn', '0025_analytics.sql', 1, 50), ('revenue_churn', 'v_revenue_churn', '0025_analytics.sql', 1, 60),
  ('health', 'v_health_latest', '0025_analytics.sql', 1, 70);

-- ---------------------------------------------------------------------------
-- product usage history: counts over time and logins by role (D-21)
create table app.product_counts_daily (
  product   text not null,
  tenant_id text not null,
  day       date not null,
  metric    text not null,
  value     int not null,
  primary key (product, tenant_id, day, metric)
);
create function app.product_counts_history() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  insert into app.product_counts_daily (product, tenant_id, day, metric, value) values (new.product, new.tenant_id, new.as_of::date, new.metric, new.value)
  on conflict (product, tenant_id, day, metric) do update set value = excluded.value;
  return new;
end $fn$;
create trigger product_counts_history after insert or update on app.product_counts for each row execute function app.product_counts_history();

create table app.product_logins_daily (
  product   text not null,
  tenant_id text not null,
  day       date not null,
  role      text not null check (role in ('daglig_leder', 'avdelingsleder', 'verneombud')),
  logins    int not null check (logins >= 0),
  primary key (product, tenant_id, day, role)
);
-- logins.daily: {day, daglig_leder: n, avdelingsleder: n, verneombud: n}
create function app.product_logins_in() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare k text;
begin
  if new.kind <> 'logins.daily' or new.tenant_id is null then return new; end if;
  foreach k in array array['daglig_leder', 'avdelingsleder', 'verneombud'] loop
    if (new.payload ->> k) ~ '^\d+$' then
      insert into app.product_logins_daily (product, tenant_id, day, role, logins)
      values (new.product, new.tenant_id, coalesce((new.payload ->> 'day')::date, new.occurred_at::date), k, (new.payload ->> k)::int)
      on conflict (product, tenant_id, day, role) do update set logins = excluded.logins;
    end if;
  end loop;
  return new;
exception when foreign_key_violation or invalid_datetime_format then return new;
end $fn$;
create trigger events_in_logins after insert on app.events_in for each row execute function app.product_logins_in();

-- ---------------------------------------------------------------------------
-- attribution and spend
create table app.channel_rules (
  id      uuid primary key default gen_random_uuid(),
  ord     int not null,
  match   jsonb not null check (jsonb_typeof(match) = 'object'),     -- {utm_source, utm_medium, referrer_host}: values are lower-case patterns (LIKE)
  channel text not null check (channel ~ '^[a-z_]{2,40}$')
);
insert into app.channel_rules (ord, match, channel) values
  (10, '{"utm_medium":"cpc"}', 'paid_search'), (20, '{"utm_medium":"paid_social"}', 'paid_social'), (30, '{"utm_medium":"email"}', 'email'),
  (40, '{"utm_source":"newsletter"}', 'email'), (50, '{"referrer_host":"%google.%"}', 'organic_search'), (60, '{"referrer_host":"%bing.%"}', 'organic_search'),
  (70, '{"referrer_host":"%linkedin.%"}', 'social'), (80, '{"referrer_host":"%facebook.%"}', 'social'), (90, '{"utm_source":"partner%"}', 'partner'),
  (1000, '{}', 'direct');

create function app.channel_of(p_touch jsonb) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select r.channel from app.channel_rules r
                   where (not (r.match ? 'utm_source') or lower(coalesce(p_touch ->> 'utm_source', '')) like r.match ->> 'utm_source')
                     and (not (r.match ? 'utm_medium') or lower(coalesce(p_touch ->> 'utm_medium', '')) like r.match ->> 'utm_medium')
                     and (not (r.match ? 'referrer_host') or lower(coalesce(p_touch ->> 'referrer_host', p_touch ->> 'referrer', '')) like r.match ->> 'referrer_host')
                   order by r.ord limit 1), 'direct')
$fn$;

create table app.marketing_spend (
  campaign   text not null check (char_length(btrim(campaign)) between 1 and 120),
  month      date not null check (month = date_trunc('month', month)::date),
  channel    text,
  amount     numeric(14, 2) not null check (amount >= 0),
  currency   text not null default 'NOK' check (currency ~ '^[A-Z]{3}$'),
  entered_by uuid references app.admins (id) on delete set null,
  entered_at timestamptz not null default now(),
  primary key (campaign, month)
);

-- ---------------------------------------------------------------------------
-- web analytics (WEB-01/02, D-37)
create table app.web_sites (
  id       uuid primary key default gen_random_uuid(),
  hostname text not null unique check (hostname = lower(hostname) and hostname ~ '^[a-z0-9.-]+$'),
  active   boolean not null default true
);
insert into app.web_sites (hostname) values ('www.owntheagenda.com'), ('orgpuls.com');

create table app.web_sessions (
  id                 uuid primary key default gen_random_uuid(),
  site_id            uuid not null references app.web_sites (id) on delete cascade,
  day                date not null,
  visitor_hash       text not null check (char_length(visitor_hash) between 16 and 128),   -- daily salt; the IP is never stored
  started_at         timestamptz not null,
  entry_path         text check (entry_path is null or char_length(entry_path) <= 500),
  referrer_host      text check (referrer_host is null or char_length(referrer_host) <= 200),
  utm                jsonb not null default '{}'::jsonb check (jsonb_typeof(utm) = 'object'),
  channel            text,
  company_org_number text check (company_org_number is null or company_org_number ~ '^\d{9}$'),
  pageviews          int not null default 1 check (pageviews >= 0)
);
create index web_sessions_day on app.web_sessions (site_id, day);

create table app.web_pageviews (
  session_id uuid not null references app.web_sessions (id) on delete cascade,
  at         timestamptz not null,
  path       text not null check (char_length(path) <= 500)
);
create index web_pageviews_session on app.web_pageviews (session_id, at);

create table app.web_events (
  session_id uuid not null references app.web_sessions (id) on delete cascade,
  at         timestamptz not null,
  name       text not null check (name ~ '^[a-z_]{2,40}$'),
  value      text check (value is null or char_length(value) <= 120)
);

-- the daily salt: one Vault secret, replaced every night (the old one is destroyed)
create function app.web_salt_rotate() returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  delete from vault.secrets where name like 'web_salt:%';
  perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'web_salt:' || current_date, 'Daily salt for the cookieless tracker (0025); destroyed nightly.');
end $fn$;
select cron.schedule('platform-web-salt', '0 0 * * *', 'select app.web_salt_rotate()');

create function public.worker_web_salt() returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'web_salt:' || current_date
$fn$;

-- the tracker's batch, from the edge function after hashing and company lookup:
-- [{site, visitor_hash, session_key, at, path, referrer_host, utm, company_org_number, event?: {name, value}}]
create function public.worker_web_ingest(p_batch jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare x jsonb; v_site uuid; v_sess uuid; v_utm jsonb; n int := 0;
begin
  if jsonb_typeof(p_batch) <> 'array' or jsonb_array_length(p_batch) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'batch'; end if;
  for x in select * from jsonb_array_elements(p_batch) loop
    select id into v_site from app.web_sites where hostname = lower(x ->> 'site') and active;
    -- the hash is the tracker's daily-salted digest; anything else (an address, a cookie) is dropped
    continue when v_site is null or coalesce(x ->> 'visitor_hash', '') !~ '^[0-9a-f]{32,64}$';
    v_utm := case when jsonb_typeof(x -> 'utm') = 'object' then x -> 'utm' else '{}'::jsonb end;
    -- a session: the same visitor hash on the same day, within 30 minutes of its last page
    select s.id into v_sess from app.web_sessions s
    where s.site_id = v_site and s.day = (x ->> 'at')::timestamptz::date and s.visitor_hash = x ->> 'visitor_hash'
      and exists (select 1 from app.web_pageviews p where p.session_id = s.id and p.at > (x ->> 'at')::timestamptz - interval '30 minutes')
    order by s.started_at desc limit 1;
    if v_sess is null then
      insert into app.web_sessions (site_id, day, visitor_hash, started_at, entry_path, referrer_host, utm, channel, company_org_number, pageviews)
      values (v_site, (x ->> 'at')::timestamptz::date, x ->> 'visitor_hash', (x ->> 'at')::timestamptz, left(x ->> 'path', 500), left(x ->> 'referrer_host', 200),
              v_utm, app.channel_of(v_utm || jsonb_build_object('referrer_host', x ->> 'referrer_host')),
              case when x ->> 'company_org_number' ~ '^\d{9}$' then x ->> 'company_org_number' end, 0)
      returning id into v_sess;
    end if;
    if jsonb_typeof(x -> 'event') = 'object' then
      insert into app.web_events (session_id, at, name, value) values (v_sess, (x ->> 'at')::timestamptz, x -> 'event' ->> 'name', left(x -> 'event' ->> 'value', 120));
    else
      insert into app.web_pageviews (session_id, at, path) values (v_sess, (x ->> 'at')::timestamptz, left(coalesce(x ->> 'path', '/'), 500));
      update app.web_sessions set pageviews = pageviews + 1 where id = v_sess;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('stored', n);
end $fn$;

-- raw web rows live 13 months (D-24)
create function app.web_prune() returns void
  language sql volatile security definer set search_path = ''
as $fn$ delete from app.web_sessions where day < current_date - interval '13 months' $fn$;
select cron.schedule('platform-web-prune', '45 3 * * *', 'select app.web_prune()');

-- Search Console arrives through its provider integration
alter table app.integration_connections drop constraint integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check
  check (provider in ('slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging', 'search_console'));
insert into app.integration_connections (provider) values ('search_console');
create table app.search_console_daily (
  day         date not null,
  site_id     uuid not null references app.web_sites (id) on delete cascade,
  query       text not null check (char_length(query) <= 200),
  impressions int not null,
  clicks      int not null,
  position    numeric,
  primary key (day, site_id, query)
);

insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord) values
  ('activation_target', 'analytics', array['source_values', 'custom'], 'source_values', 'platform', 'Analytics › Activation (20 min to first send)', false, 'custom', 410),
  ('renewal_window', 'analytics', array['source_values', 'custom'], 'source_values', 'platform', 'Analytics › Health (renewals within 60 days)', false, 'custom', 420);

-- ---------------------------------------------------------------------------
-- the Analytics screen. p_product: a product key, or null / 'all'. p_days: 30 | 90 | 365.
create function app.in_scope(p_product text, p_row_product text) returns boolean
  language sql immutable set search_path = ''
as $fn$ select p_product is null or p_product = 'all' or p_row_product = p_product $fn$;

create function public.analytics_business(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 365) then p_days else 30 end; v_mrr numeric; v_prev numeric;
begin
  perform app.require('global', 'reports_others');
  v_mrr := (select sum(mrr) from app.mrr_daily where day = (select max(day) from app.mrr_daily) and app.in_scope(p_product, product));
  v_prev := (select sum(mrr) from app.mrr_daily where day = (select max(day) from app.mrr_daily where day <= current_date - d) and app.in_scope(p_product, product));
  return jsonb_build_object(
    'mrr', v_mrr, 'mrr_prev', v_prev,
    'paying_accounts', (select count(distinct ap.account_id) from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
                        where app.sub_mrr(s) > 0 and app.in_scope(p_product, s.product)),
    'customers', (select count(distinct ap.account_id) from app.account_products ap where ap.status = 'active' and app.in_scope(p_product, ap.product)),
    'trials', (select count(*) from app.subscriptions s where app.sub_status(s) = 'trial' and app.in_scope(p_product, s.product)),
    'trials_ending_7', (select count(*) from app.subscriptions s where app.sub_status(s) = 'trial' and s.trial_ends_at < now() + interval '7 days' and app.in_scope(p_product, s.product)),
    'trial_conversion', (select jsonb_build_object('trials', sum(trials), 'converted', sum(converted)) from app.v_trial_conversion
                         where cohort >= date_trunc('month', now() - make_interval(days => d + 45)) and cohort < date_trunc('month', now() - interval '45 days') + interval '1 month'
                           and app.in_scope(p_product, product)),
    'movements', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'new', coalesce(new_mrr, 0), 'expansion', coalesce(expansion, 0),
                                                               'contraction', coalesce(contraction, 0), 'churn', coalesce(churn, 0), 'net', coalesce(net, 0)) order by month)
                           from (select month, sum(new_mrr) new_mrr, sum(expansion) expansion, sum(contraction) contraction, sum(churn) churn, sum(net) net
                                 from app.v_net_new_mrr where app.in_scope(p_product, product) and month > date_trunc('month', now()) - interval '12 months' group by month) x), '[]'::jsonb),
    'mrr_by_product', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'product', product, 'mrr', mrr) order by month, product)
                                from app.v_mrr_monthly where month > date_trunc('month', now()) - interval '12 months' and app.in_scope(p_product, product)), '[]'::jsonb),
    'trials_by_source', coalesce((select jsonb_agg(jsonb_build_object('channel', ch, 'trials', n, 'converted', c) order by n desc) from (
        select app.channel_of(coalesce(ap.attribution -> 'first_touch', ap.attribution, '{}'::jsonb)) ch, count(*) n,
               count(*) filter (where s.confirmed_at is not null and s.confirmed_at <= s.trial_started_at + interval '45 days') c
        from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
        where s.trial_started_at > now() - make_interval(days => d) and app.in_scope(p_product, s.product) group by 1) x), '[]'::jsonb),
    'bands', coalesce((select jsonb_agg(jsonb_build_object('band', b.band_label, 'accounts', b.n, 'mrr', b.mrr) order by b.min_employees) from (
        select pv.band_label, pv.min_employees, count(*) n, sum(app.sub_mrr(s)) mrr from app.subscriptions s
        join app.plan_versions pv on pv.product = s.product and s.seats between pv.min_employees and coalesce(pv.max_employees, 2147483647)
        where app.sub_mrr(s) > 0 and app.in_scope(p_product, s.product) group by pv.band_label, pv.min_employees) b), '[]'::jsonb),
    'by_industry', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'count', n) order by n desc) from (
        select coalesce(o.industry, '') k, count(distinct o.id) n from app.organizations o join app.account_products ap on ap.account_id = o.account_id
        where ap.status = 'active' and app.in_scope(p_product, ap.product) and o.deleted_at is null and not o.is_sample group by 1) x), '[]'::jsonb),
    'by_fylke', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'count', n) order by n desc) from (
        select coalesce(o.fylke, '') k, count(distinct o.id) n from app.organizations o join app.account_products ap on ap.account_id = o.account_id
        where ap.status = 'active' and app.in_scope(p_product, ap.product) and o.deleted_at is null and not o.is_sample group by 1) x), '[]'::jsonb),
    'activated_after_result', (select jsonb_build_object('paying', count(*), 'tiltak_30d', count(*) filter (where t.reached_at <= r.reached_at + interval '30 days'))
                               from app.subscriptions s join app.activation_milestones r on r.product = s.product and r.tenant_id = s.tenant_id and r.key = 'result_unlocked'
                               left join app.activation_milestones t on t.product = s.product and t.tenant_id = s.tenant_id and t.key = 'first_tiltak'
                               where app.sub_mrr(s) > 0 and app.in_scope(p_product, s.product)),
    'churn', (select jsonb_build_object('logos', count(*), 'mrr_lost', coalesce(sum(mrr_lost), 0)) from app.account_churns
              where churned_at > now() - make_interval(days => d) and app.in_scope(p_product, product)));
end $fn$;

-- the activation funnel for a signup cohort (the month an account was created)
create function public.analytics_activation(p_product text default null, p_cohort date default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare c date := coalesce(date_trunc('month', p_cohort)::date, date_trunc('month', now())::date - interval '1 month');
        keys text[] := array['account_created', 'employees_uploaded', 'survey_scheduled', 'survey_sent', 'result_unlocked', 'results_viewed', 'first_tiltak', 'converted'];
begin
  perform app.require('global', 'reports_others');
  return jsonb_build_object('cohort', to_char(c, 'YYYY-MM'),
    'cohorts', (select jsonb_agg(to_char(m, 'YYYY-MM') order by m desc) from generate_series(date_trunc('month', now()) - interval '3 months', date_trunc('month', now()), interval '1 month') m),
    'target_min', case when app.setting('activation_target') = 'custom' then (select value_number from app.setting_values where key = 'activation_target' and scope_id = '') else 20 end,
    'steps', (with t as (select a.product, a.tenant_id from app.activation_milestones a where a.key = 'account_created' and date_trunc('month', a.reached_at) = c
                         and app.in_scope(p_product, a.product))
              select jsonb_agg(jsonb_build_object('key', k, 'count', (select count(*) from t join app.activation_milestones m on m.product = t.product and m.tenant_id = t.tenant_id and m.key = k),
                     'median_min', (select percentile_cont(0.5) within group (order by extract(epoch from m.reached_at - p.reached_at) / 60)
                                    from t join app.activation_milestones m on m.product = t.product and m.tenant_id = t.tenant_id and m.key = k
                                    join app.activation_milestones p on p.product = t.product and p.tenant_id = t.tenant_id and p.key = keys[greatest(i - 1, 1)::int]
                                    where i > 1)) order by i)
              from unnest(keys) with ordinality u(k, i)));
end $fn$;

-- retention by signup cohort (the month of first confirmation): logos still paying, revenue against month 0
create function public.analytics_retention(p_product text default null, p_mode text default 'logos') returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'reports_others');
  if p_mode not in ('logos', 'revenue') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mode'; end if;
  return jsonb_build_object('mode', p_mode,
    'cohorts', coalesce((with co as (select s.product, s.tenant_id, date_trunc('month', s.confirmed_at)::date cohort from app.subscriptions s
                                     where s.confirmed_at > now() - interval '12 months' and app.in_scope(p_product, s.product)),
                              me as (select t.product, t.tenant_id, date_trunc('month', t.day)::date as month, max(t.mrr) mrr from app.mrr_tenant_daily t group by 1, 2, 3)
      select jsonb_agg(jsonb_build_object('cohort', to_char(cohort, 'YYYY-MM'), 'size', size, 'cells', cells) order by cohort) from (
        select co.cohort, count(distinct (co.product, co.tenant_id)) size,
               (select jsonb_agg(v order by k) from (
                  select k, case when p_mode = 'logos' then round(100.0 * count(*) filter (where me.mrr > 0) / nullif(count(distinct (c2.product, c2.tenant_id)), 0), 1)
                                 else round(100.0 * sum(me.mrr) / nullif(sum(m0.mrr), 0), 1) end v
                  from generate_series(0, (extract(year from age(date_trunc('month', now()), co.cohort)) * 12 + extract(month from age(date_trunc('month', now()), co.cohort)))::int) k
                  join co c2 on c2.cohort = co.cohort
                  left join me on me.product = c2.product and me.tenant_id = c2.tenant_id and me.month = (co.cohort + make_interval(months => k))::date
                  left join me m0 on m0.product = c2.product and m0.tenant_id = c2.tenant_id and m0.month = co.cohort
                  group by k) z) cells
        from co group by co.cohort) x), '[]'::jsonb),
    'churn_by_month', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'logos', churned) order by month) from (
        select month, sum(churned) churned from app.v_logo_churn where app.in_scope(p_product, product) and month > date_trunc('month', now()) - interval '12 months' group by month) x), '[]'::jsonb),
    'reasons', coalesce((select jsonb_agg(jsonb_build_object('code', coalesce(r.code, 'unknown'), 'count', n) order by n desc) from (
        select c.reason_id, count(*) n from app.account_churns c where c.churned_at > now() - interval '6 months' and app.in_scope(p_product, c.product) group by c.reason_id) x
        left join app.churn_reasons r on r.id = x.reason_id), '[]'::jsonb));
end $fn$;

-- product usage: rounds as counts (D-19), logins by role, counts reported per tenant
create function public.analytics_usage(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 365) then p_days else 30 end;
begin
  perform app.require('global', 'reports_others');
  return jsonb_build_object(
    'rounds', (select jsonb_build_object('main', count(*) filter (where kind = 'main'), 'pulse', count(*) filter (where kind = 'pulse')) from app.product_survey_rounds
               where opens_at > now() - make_interval(days => d) and app.in_scope(p_product, product)),
    'response_rate', (select jsonb_build_object('main', round(100.0 * sum(answered) filter (where kind = 'main') / nullif(sum(invited) filter (where kind = 'main'), 0), 1),
                                                'pulse', round(100.0 * sum(answered) filter (where kind = 'pulse') / nullif(sum(invited) filter (where kind = 'pulse'), 0), 1))
                      from app.product_survey_rounds where closes_at < now() and closes_at > now() - make_interval(days => d) and app.in_scope(p_product, product)),
    'reminder_gain', (select round(100.0 * sum(gained_after_reminders) / nullif(sum(answered - gained_after_reminders), 0), 1) from app.product_survey_rounds
                      where closes_at > now() - make_interval(days => d) and app.in_scope(p_product, product)),
    'rounds_by_month', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'main', mn, 'pulse', pu) order by m) from (
        select date_trunc('month', opens_at) m, count(*) filter (where kind = 'main') mn, count(*) filter (where kind = 'pulse') pu from app.product_survey_rounds
        where opens_at > date_trunc('month', now()) - interval '12 months' and app.in_scope(p_product, product) group by 1) x), '[]'::jsonb),
    'logins', coalesce((select jsonb_object_agg(role, n) from (select role, sum(logins) n from app.product_logins_daily
                        where day > current_date - d and app.in_scope(p_product, product) group by role) x), '{}'::jsonb),
    'counts', coalesce((select jsonb_object_agg(metric, n) from (select metric, sum(value) n from app.product_counts where app.in_scope(p_product, product) group by metric) x), '{}'::jsonb));
end $fn$;

create function public.analytics_web(p_site uuid default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 365) then p_days else 30 end;
begin
  perform app.require('global', 'reports_others');
  return jsonb_build_object(
    'sites', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'hostname', hostname) order by hostname) from app.web_sites where active), '[]'::jsonb),
    'search_console', (select status from app.integration_connections where provider = 'search_console'),
    'visitors', (select count(distinct (day, visitor_hash)) from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site)),
    'sessions', (select count(*) from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site)),
    'pageviews', (select coalesce(sum(pageviews), 0) from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site)),
    'bounces', (select count(*) filter (where pageviews <= 1) from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site)),
    'signups', (select count(*) from app.account_products where created_at > now() - make_interval(days => d)),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'visitors', v, 'sessions', s) order by day) from (
        select day, count(distinct visitor_hash) v, count(*) s from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site) group by day) x), '[]'::jsonb),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('channel', channel, 'sessions', n) order by n desc) from (
        select coalesce(channel, 'direct') channel, count(*) n from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site) group by 1) x), '[]'::jsonb),
    'landing', coalesce((select jsonb_agg(jsonb_build_object('path', entry_path, 'sessions', n, 'bounce', b) order by n desc) from (
        select entry_path, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b from app.web_sessions
        where day > current_date - d and (p_site is null or site_id = p_site) group by 1 order by 2 desc limit 10) x), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'value', value, 'count', n) order by n desc) from (
        select e.name, e.value, count(*) n from app.web_events e join app.web_sessions s on s.id = e.session_id
        where s.day > current_date - d and (p_site is null or s.site_id = p_site) group by 1, 2 order by 3 desc limit 20) x), '[]'::jsonb),
    'companies', (select count(distinct company_org_number) from app.web_sessions where day > current_date - d and company_org_number is not null and (p_site is null or site_id = p_site)),
    'search', coalesce((select jsonb_agg(jsonb_build_object('query', query, 'impressions', i, 'clicks', c) order by c desc) from (
        select query, sum(impressions) i, sum(clicks) c from app.search_console_daily where day > current_date - d and (p_site is null or site_id = p_site)
        group by 1 order by 3 desc limit 10) x), '[]'::jsonb));
end $fn$;

-- attribution per channel: signups, activated, paid, MRR won, spend, CAC (first or last touch)
create function public.analytics_attribution(p_touch text default 'first', p_days int default 90) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 365) then p_days else 90 end;
begin
  perform app.require('global', 'reports_others');
  if p_touch not in ('first', 'last') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'touch'; end if;
  return jsonb_build_object('touch', p_touch,
    'has_last_touch', exists (select 1 from app.account_products where attribution ? 'last_touch'),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('channel', ch, 'signups', signups, 'activated', act, 'paid', paid, 'mrr', mrr,
                                                              'spend', (select sum(amount) from app.marketing_spend ms where ms.channel = ch and ms.month > date_trunc('month', now() - make_interval(days => d))))
                                    order by signups desc) from (
      select app.channel_of(coalesce(ap.attribution -> (p_touch || '_touch'), case when p_touch = 'first' then ap.attribution end, '{}'::jsonb)) ch,
             count(*) signups,
             count(*) filter (where exists (select 1 from app.activation_milestones m where m.product = ap.product and m.tenant_id = ap.tenant_id and m.key = 'result_unlocked')) act,
             count(*) filter (where s.confirmed_at is not null) paid,
             coalesce(sum(app.sub_mrr(s)), 0) mrr
      from app.account_products ap left join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
      where ap.created_at > now() - make_interval(days => d) group by 1) x), '[]'::jsonb),
    'spend', coalesce((select jsonb_agg(jsonb_build_object('campaign', campaign, 'month', to_char(month, 'YYYY-MM'), 'channel', channel, 'amount', amount) order by month desc, campaign)
                       from app.marketing_spend where month > date_trunc('month', now() - make_interval(days => d))), '[]'::jsonb));
end $fn$;

create function public.analytics_set_spend(p_campaign text, p_month date, p_amount numeric, p_channel text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'reports_others');
begin
  if p_amount is null then
    delete from app.marketing_spend where campaign = btrim(p_campaign) and month = date_trunc('month', p_month)::date;
  else
    insert into app.marketing_spend (campaign, month, channel, amount, entered_by) values (btrim(p_campaign), date_trunc('month', p_month)::date, p_channel, p_amount, v_me)
    on conflict (campaign, month) do update set amount = excluded.amount, channel = excluded.channel, entered_by = v_me, entered_at = now();
  end if;
  perform app.log('analytics.spend_set', 'campaign', btrim(p_campaign), jsonb_build_object('month', p_month, 'amount', p_amount));
  return jsonb_build_object('ok', true);
end $fn$;

create function public.analytics_health(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_window int := case when app.setting('renewal_window') = 'custom' then coalesce((select value_number from app.setting_values where key = 'renewal_window' and scope_id = '')::int, 60) else 60 end;
begin
  perform app.require('global', 'reports_others');
  return jsonb_build_object(
    'model', (select jsonb_build_object('id', id, 'version', version, 'weights', weights) from app.health_models where active),
    'distribution', coalesce((select jsonb_agg(jsonb_build_object('bucket', b * 10, 'count', n) order by b) from (
        select least(score / 10, 9) b, count(*) n from app.v_health_latest where app.in_scope(p_product, product) group by 1) x), '[]'::jsonb),
    'scored', (select count(*) from app.v_health_latest where app.in_scope(p_product, product)),
    'renewal_window', v_window,
    'at_risk', coalesce((select jsonb_agg(x order by (x ->> 'score')::int) from (
        select jsonb_build_object('organization_id', o.id, 'name', o.name, 'product', h.product, 'score', h.score,
                                  'factors', (select jsonb_agg(f order by (f ->> 'loss')::numeric desc) from jsonb_array_elements(h.factors) f where (f ->> 'loss')::numeric > 0),
                                  'renews_at', app.sub_renewal(s)) x
        from app.v_health_latest h join app.account_products ap on ap.product = h.product and ap.tenant_id = h.tenant_id
        join app.subscriptions s on s.product = h.product and s.tenant_id = h.tenant_id
        join app.organizations o on o.account_id = ap.account_id and o.deleted_at is null
        where h.score < 40 and app.sub_mrr(s) > 0 and app.in_scope(p_product, h.product)
          and (app.sub_renewal(s) is null or app.sub_renewal(s) < now() + make_interval(days => v_window))) y), '[]'::jsonb));
end $fn$;

create function public.health_model_save(p_weights jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); v_id uuid; k text;
begin
  if jsonb_typeof(p_weights) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'weights'; end if;
  for k in select jsonb_object_keys(p_weights) loop
    if k not in ('admin_login', 'survey_cadence', 'response_trend', 'tiltak_activity', 'payment') or (p_weights ->> k)::numeric not between 0 and 100 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'weights.' || k;
    end if;
  end loop;
  update app.health_models set active = false where active;
  insert into app.health_models (version, weights, active, created_by) values ((select coalesce(max(version), 0) + 1 from app.health_models), p_weights, true, v_me)
  returning id into v_id;
  perform app.log('health.model_saved', 'health_model', v_id::text, jsonb_build_object('weights', p_weights));
  perform app.health_nightly();
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.analytics_set_churn_reason(p_product text, p_tenant text, p_churned_at timestamptz, p_code text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'edit_others');
begin
  update app.account_churns set reason_id = (select id from app.churn_reasons where code = p_code), set_by = v_me
  where product = p_product and tenant_id = p_tenant and churned_at = p_churned_at;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('analytics.churn_reason', 'tenant', p_tenant, jsonb_build_object('code', p_code));
  return jsonb_build_object('ok', true);
end $fn$;

create function public.analytics_metric_definitions() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('key', key, 'view', view_name, 'migration', migration, 'version', version) order by ord) from app.metric_definitions), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['mrr_tenant_daily', 'mrr_movements', 'churn_reasons', 'account_churns', 'health_models', 'health_scores', 'metric_definitions',
                           'product_counts_daily', 'product_logins_daily', 'channel_rules', 'marketing_spend', 'web_sites', 'web_sessions', 'web_pageviews',
                           'web_events', 'search_console_daily'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
  foreach t in array array['v_mrr_monthly', 'v_net_new_mrr', 'v_trial_conversion', 'v_activated_orgs', 'v_logo_churn', 'v_revenue_churn', 'v_health_latest'] loop
    execute format('revoke all on app.%I from public, anon, authenticated', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.billing_period_end()', 'app.snapshot_mrr_tenants()', 'app.health_signals(text, text)', 'app.health_compute(text, text)', 'app.health_nightly()',
                           'app.org_health(uuid)', 'app.org_health_parts(uuid)', 'app.health_test(uuid, text, int)', 'app.product_counts_history()', 'app.product_logins_in()',
                           'app.channel_of(jsonb)', 'app.web_salt_rotate()', 'app.web_prune()', 'app.in_scope(text, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.analytics_business(text, int)', 'public.analytics_activation(text, date)', 'public.analytics_retention(text, text)',
                           'public.analytics_usage(text, int)', 'public.analytics_web(uuid, int)', 'public.analytics_attribution(text, int)',
                           'public.analytics_set_spend(text, date, numeric, text)', 'public.analytics_health(text)', 'public.health_model_save(jsonb)',
                           'public.analytics_set_churn_reason(text, text, timestamptz, text)', 'public.analytics_metric_definitions()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_web_salt()', 'public.worker_web_ingest(jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- the first salt, so the tracker can start
select app.web_salt_rotate();
