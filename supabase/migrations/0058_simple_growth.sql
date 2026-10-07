-- 0058_simple_growth.sql — Sentral Simple › Growth (SimpleGrowth.dc.html, GrowthMarketing.dc.html): the overview of
-- Analytics over 7, 30 or 90 days, tracked SEO keywords, and paid marketing campaigns with their tracking links.
--
-- What is real and what is not (SIMPLE-PLAN.md): signups, trial → paid, signups by first-touch channel and the bottom of
-- the funnel come from the products' own events. Visitors, the funnel's top and landing pages need the website tracker
-- (D-37), which has sent nothing: they are null, never 0. Search Console is not connected, so positions are null.
-- Marketing spend is what people typed in (analytics_set_spend), keyed by the campaign's utm_campaign.
--
-- 1. A public site belongs to an application (web_sites.product): the tracking link's host, the SEO site and the
--    visitors of an application's overview. orgpuls.com is Orgpuls's site; www.owntheagenda.com is the company's.
-- 2. growth_overview(product, days): KPIs, the daily series, the funnel, sources and landing pages.
-- 3. seo_keywords + seo_get / seo_keyword_add / seo_keyword_remove.
-- 4. ad_campaigns + ad_campaigns_get / ad_campaign_save / ad_campaign_set_state. Pausing changes the record only; no
--    ad platform is connected.

-- ---------------------------------------------------------------------------
-- 1. the application a public site belongs to
alter table app.web_sites add column product text references app.products (key) on delete set null;
update app.web_sites set product = 'orgpuls' where hostname = 'orgpuls.com';

-- the application's public site: the first active one it owns (null when it has none)
create function app.product_site(p_product text) returns app.web_sites
  language sql stable security definer set search_path = ''
as $fn$
  select s.* from app.web_sites s where s.active and s.product = p_product order by s.hostname limit 1
$fn$;

-- ---------------------------------------------------------------------------
-- 2. the overview. p_product: a product key (null or 'all': every product and site). p_days: 7 | 30 | 90.
-- Visitors are sums of daily uniques on the application's site, null while its tracker has never sent a session.
-- Funnel: the accounts created in the period, and how many of them sent a first survey and became paying.
-- Spend: NOK typed in for the application's marketing campaigns in the calendar months the period touches; the
-- paying customers of those same months are its denominator (spend is entered per month, never pro-rated).
create function public.growth_overview(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  d int := case when p_days in (7, 30, 90) then p_days else 30 end;
  v_from timestamptz := now() - make_interval(days => d);
  v_prev timestamptz := now() - make_interval(days => 2 * d);
  v_month date := date_trunc('month', now() - make_interval(days => d))::date;
  v_product text := nullif(p_product, 'all');
  v_sites uuid[];
  v_live boolean;
begin
  perform app.require_marketing_reports();
  if v_product is not null and not exists (select 1 from app.products where key = v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  v_sites := array(select s.id from app.web_sites s where s.active and (v_product is null or s.product = v_product) order by s.hostname);
  v_live := exists (select 1 from app.web_sessions w where w.site_id = any (v_sites));
  return jsonb_build_object(
    'days', d,
    'site', (select jsonb_build_object('id', s.id, 'hostname', s.hostname) from app.web_sites s where s.id = v_sites[1]),
    'tracked', v_live,
    'kpis', jsonb_build_object(
      'visitors', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                         where w.site_id = any (v_sites) and w.day > current_date - d) end,
      'visitors_prev', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                              where w.site_id = any (v_sites) and w.day > current_date - 2 * d and w.day <= current_date - d) end,
      'signups', (select count(*) from app.account_products ap where ap.created_at > v_from and app.in_scope(v_product, ap.product)),
      'signups_prev', (select count(*) from app.account_products ap where ap.created_at > v_prev and ap.created_at <= v_from and app.in_scope(v_product, ap.product)),
      -- the definition analytics_business uses: trials started in the cohort months, converted within 45 days
      'trial_conversion', (select jsonb_build_object('trials', sum(t.trials), 'converted', sum(t.converted)) from app.v_trial_conversion t
                           where t.cohort >= date_trunc('month', now() - make_interval(days => d + 45))
                             and t.cohort < date_trunc('month', now() - interval '45 days') + interval '1 month'
                             and app.in_scope(v_product, t.product)),
      'spend', (select sum(ms.amount) from app.marketing_spend ms left join app.ad_campaigns c on c.utm_campaign = ms.campaign
                where ms.month >= v_month and ms.currency = 'NOK' and app.in_scope(v_product, c.product)),
      'spend_excluded_currency', (select count(*) from app.marketing_spend ms left join app.ad_campaigns c on c.utm_campaign = ms.campaign
                                  where ms.month >= v_month and ms.currency <> 'NOK' and app.in_scope(v_product, c.product)),
      'spend_from', v_month,
      'paying_new', (select count(*) from app.subscriptions s where s.confirmed_at >= v_month and app.in_scope(v_product, s.product))),
    'daily', (select jsonb_agg(jsonb_build_object(
                'day', g.day,
                'signups', (select count(*) from app.account_products ap where ap.created_at::date = g.day and app.in_scope(v_product, ap.product)),
                'visitors', case when v_live then (select count(distinct w.visitor_hash) from app.web_sessions w where w.site_id = any (v_sites) and w.day = g.day) end)
              order by g.day)
              from (select generate_series(current_date - d + 1, current_date, interval '1 day')::date as day) g),
    'funnel', (with c as (select ap.product, ap.tenant_id from app.account_products ap where ap.created_at > v_from and app.in_scope(v_product, ap.product))
               select jsonb_build_array(
                 jsonb_build_object('key', 'visited', 'count', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                                                                      where w.site_id = any (v_sites) and w.day > current_date - d) end),
                 jsonb_build_object('key', 'viewed_pricing', 'count', null),
                 jsonb_build_object('key', 'started_signup', 'count', null),
                 jsonb_build_object('key', 'account_created', 'count', (select count(*) from c)),
                 jsonb_build_object('key', 'survey_sent', 'count', (select count(*) from c join app.activation_milestones m
                                                                     on m.product = c.product and m.tenant_id = c.tenant_id and m.key = 'survey_sent')),
                 jsonb_build_object('key', 'paying', 'count', (select count(*) from c join app.subscriptions s
                                                                on s.product = c.product and s.tenant_id = c.tenant_id and s.confirmed_at is not null)))),
    -- signups by the first touch's channel; visits are the site's sessions by channel, null without the tracker
    'sources', coalesce((select jsonb_agg(jsonb_build_object('channel', coalesce(v.ch, g.ch), 'visits', case when v_live then coalesce(v.n, 0) end, 'signups', coalesce(g.n, 0))
                                          order by coalesce(g.n, 0) desc, coalesce(v.n, 0) desc, coalesce(v.ch, g.ch)) from
        (select coalesce(w.channel, 'direct') ch, count(*) n from app.web_sessions w where w.site_id = any (v_sites) and w.day > current_date - d group by 1) v
        full join (select app.channel_of(coalesce(ap.attribution -> 'first_touch', ap.attribution, '{}'::jsonb)) ch, count(*) n from app.account_products ap
                   where ap.created_at > v_from and app.in_scope(v_product, ap.product) group by 1) g on g.ch = v.ch), '[]'::jsonb),
    -- a session cannot be joined to a signup (cookieless, D-37), so a landing page carries visits only
    'pages', coalesce((select jsonb_agg(jsonb_build_object('path', x.entry_path, 'visits', x.n) order by x.n desc, x.entry_path) from (
        select w.entry_path, count(*) n from app.web_sessions w where w.site_id = any (v_sites) and w.day > current_date - d and w.entry_path is not null
        group by 1 order by 2 desc limit 10) x), '[]'::jsonb));
end $fn$;

-- ---------------------------------------------------------------------------
-- 3. SEO: the keywords a team tracks on an application's site; figures from Search Console's nightly import
create table app.seo_keywords (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references app.web_sites (id) on delete cascade,
  query      text not null check (char_length(query) between 1 and 200 and query = lower(btrim(query))),
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (site_id, query)
);

-- clicks, impressions and the impression-weighted position over the period and the one before it; per keyword the
-- position now and before. Every figure is null while Search Console is not connected.
create function public.seo_get(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  d int := case when p_days in (7, 30, 90) then p_days else 30 end;
  v_site app.web_sites := app.product_site(nullif(p_product, 'all'));
  v_conn boolean := app.connected('search_console');
begin
  return jsonb_build_object(
    'connected', v_conn, 'days', d,
    'site', case when v_site.id is not null then jsonb_build_object('id', v_site.id, 'hostname', v_site.hostname) end,
    'totals', case when v_conn and v_site.id is not null then (
      select jsonb_build_object(
        'clicks', sum(sc.clicks) filter (where sc.day > current_date - d),
        'clicks_prev', sum(sc.clicks) filter (where sc.day <= current_date - d),
        'impressions', sum(sc.impressions) filter (where sc.day > current_date - d),
        'impressions_prev', sum(sc.impressions) filter (where sc.day <= current_date - d),
        'position', round(sum(sc.position * sc.impressions) filter (where sc.day > current_date - d and sc.position is not null)
                          / nullif(sum(sc.impressions) filter (where sc.day > current_date - d and sc.position is not null), 0), 1),
        'position_prev', round(sum(sc.position * sc.impressions) filter (where sc.day <= current_date - d and sc.position is not null)
                               / nullif(sum(sc.impressions) filter (where sc.day <= current_date - d and sc.position is not null), 0), 1))
      from app.search_console_daily sc where sc.site_id = v_site.id and sc.day > current_date - 2 * d) end,
    'keywords', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'query', k.query, 'created_at', k.created_at, 'mine', k.created_by = v_me,
        'impressions', case when v_conn then x.i end, 'clicks', case when v_conn then x.c end,
        'position', case when v_conn then x.p end, 'position_prev', case when v_conn then x.pp end) order by k.created_at, k.query)
      from app.seo_keywords k
      left join lateral (
        select sum(sc.impressions) filter (where sc.day > current_date - d) i, sum(sc.clicks) filter (where sc.day > current_date - d) c,
               round(sum(sc.position * sc.impressions) filter (where sc.day > current_date - d and sc.position is not null)
                     / nullif(sum(sc.impressions) filter (where sc.day > current_date - d and sc.position is not null), 0), 1) p,
               round(sum(sc.position * sc.impressions) filter (where sc.day <= current_date - d and sc.position is not null)
                     / nullif(sum(sc.impressions) filter (where sc.day <= current_date - d and sc.position is not null), 0), 1) pp
        from app.search_console_daily sc where sc.site_id = k.site_id and sc.query = k.query and sc.day > current_date - 2 * d) x on true
      where k.site_id = v_site.id), '[]'::jsonb));
end $fn$;

-- track a keyword on the application's site (lower case, single spaces; at most 200 per site)
create function public.seo_keyword_add(p_product text, p_query text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'add');
  v_site app.web_sites := app.product_site(p_product);
  v_q text := lower(btrim(regexp_replace(coalesce(p_query, ''), '\s+', ' ', 'g')));
  v_id uuid;
begin
  if v_site.id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site'; end if;
  if char_length(v_q) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'query'; end if;
  if exists (select 1 from app.seo_keywords where site_id = v_site.id and query = v_q) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'duplicate';
  end if;
  if (select count(*) from app.seo_keywords where site_id = v_site.id) >= 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'limit';
  end if;
  insert into app.seo_keywords (site_id, query, created_by) values (v_site.id, v_q, v_me) returning id into v_id;
  perform app.log('seo.keyword_added', 'seo_keyword', v_id::text, jsonb_build_object('site', v_site.hostname));
  return jsonb_build_object('id', v_id, 'query', v_q);
end $fn$;

-- stop tracking: one's own keyword with Campaigns › Add, anyone's with Edit others
create function public.seo_keyword_remove(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); k app.seo_keywords;
begin
  select * into k from app.seo_keywords where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if k.created_by is distinct from v_me and not app.can('campaigns', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:edit_others';
  end if;
  delete from app.seo_keywords where id = p_id;
  perform app.log('seo.keyword_removed', 'seo_keyword', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- ---------------------------------------------------------------------------
-- 4. paid marketing campaigns (the email campaigns are app.campaigns). The tracking link is the application's site +
-- the landing path + utm_source/utm_medium/utm_campaign; the medium follows channel_rules so the signups it brings
-- land under the right channel (cpc → paid search, paid_social, email). utm_campaign is fixed once created: links are
-- out in the world. Spend is marketing_spend under that utm_campaign.
create table app.ad_campaigns (
  id           uuid primary key default gen_random_uuid(),
  product      text not null references app.products (key),
  name         text not null check (char_length(btrim(name)) between 1 and 120),
  channel      text not null check (channel in ('google_ads', 'linkedin', 'facebook', 'newsletter', 'webinar', 'other')),
  landing_path text not null default '/' check (char_length(landing_path) <= 300 and landing_path ~ '^/[A-Za-z0-9/_.~%-]*$'),
  utm_source   text not null check (utm_source ~ '^[a-z0-9_-]{1,60}$'),
  utm_medium   text not null check (utm_medium ~ '^[a-z0-9_-]{1,60}$'),
  utm_campaign text not null unique check (utm_campaign ~ '^[a-z0-9_-]{1,60}$'),
  budget       numeric(14, 2) check (budget is null or budget >= 0),
  currency     text not null default 'NOK' check (currency = 'NOK'),
  starts_on    date,
  ends_on      date,
  state        text not null default 'scheduled' check (state in ('scheduled', 'live', 'paused', 'ended')),
  created_by   uuid references app.admins (id) on delete set null,
  is_sample    boolean not null default false,
  version      int not null default 1,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);
create index ad_campaigns_product on app.ad_campaigns (product, created_at);

-- the medium and source a channel's links carry, and the spend channel (channel_rules' keys) it is entered under
create function app.ad_utm(p_channel text) returns jsonb
  language sql immutable set search_path = ''
as $fn$
  select case p_channel
    when 'google_ads' then '{"source":"google-ads","medium":"cpc","spend":"paid_search"}'
    when 'linkedin' then '{"source":"linkedin","medium":"paid_social","spend":"paid_social"}'
    when 'facebook' then '{"source":"facebook","medium":"paid_social","spend":"paid_social"}'
    when 'newsletter' then '{"source":"newsletter","medium":"email","spend":"email"}'
    when 'webinar' then '{"source":"webinar","medium":"event","spend":null}'
    else '{"source":"other","medium":"referral","spend":null}' end::jsonb
$fn$;

-- a utm_campaign no campaign of either kind uses: the name's slug, then -2, -3 …
create function app.ad_utm_campaign(p_name text) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_base text := coalesce(nullif(app.slug(p_name), ''), 'campaign'); v text := v_base; i int := 1;
begin
  while exists (select 1 from app.ad_campaigns where utm_campaign = v) or exists (select 1 from app.campaigns where utm_campaign = v and deleted_at is null) loop
    i := i + 1; v := left(v_base, 56) || '-' || i;
  end loop;
  return v;
end $fn$;

-- the state shown: a campaign whose end date has passed has ended
create function app.ad_state(c app.ad_campaigns) returns text
  language sql stable set search_path = ''
as $fn$ select case when c.ends_on is not null and c.ends_on < current_date then 'ended' else c.state end $fn$;

-- the application's campaigns with spend (NOK), visits by utm_campaign (null while its site's tracker has never sent a
-- session), signups and paying customers whose first touch carried the campaign. Figures of another person's campaign
-- need Campaigns › See reports of others or Edit others (as campaign_reports_ok, V-P6C-19).
create function public.ad_campaigns_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  v_site app.web_sites := app.product_site(p_product);
  v_live boolean;
  v_others boolean := app.can('campaigns', 'reports_others') or app.can('global', 'reports_others') or app.can('campaigns', 'edit_others');
begin
  if not exists (select 1 from app.products where key = p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  v_live := v_site.id is not null and exists (select 1 from app.web_sessions w where w.site_id = v_site.id);
  return jsonb_build_object(
    'site', case when v_site.id is not null then jsonb_build_object('id', v_site.id, 'hostname', v_site.hostname) end,
    'tracked', v_live,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'channel', c.channel, 'landing_path', c.landing_path,
        'utm', jsonb_build_object('source', c.utm_source, 'medium', c.utm_medium, 'campaign', c.utm_campaign),
        'budget', c.budget, 'currency', c.currency, 'starts_on', c.starts_on, 'ends_on', c.ends_on,
        'state', app.ad_state(c), 'version', c.version, 'created_at', c.created_at, 'mine', c.created_by = v_me,
        'figures', case when c.created_by = v_me or v_others then jsonb_build_object(
          'spend', (select coalesce(jsonb_agg(jsonb_build_object('month', to_char(ms.month, 'YYYY-MM'), 'amount', ms.amount, 'currency', ms.currency) order by ms.month), '[]'::jsonb)
                    from app.marketing_spend ms where ms.campaign = c.utm_campaign),
          'spent', (select sum(ms.amount) from app.marketing_spend ms where ms.campaign = c.utm_campaign and ms.currency = 'NOK'),
          'visits', case when v_live then (select count(*) from app.web_sessions w where w.site_id = v_site.id and w.utm ->> 'utm_campaign' = c.utm_campaign) end,
          'signups', (select count(*) from app.account_products ap
                      where lower(coalesce(ap.attribution -> 'first_touch', ap.attribution) ->> 'utm_campaign') = c.utm_campaign),
          'paid', (select count(*) from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
                   where lower(coalesce(ap.attribution -> 'first_touch', ap.attribution) ->> 'utm_campaign') = c.utm_campaign and s.confirmed_at is not null)) end)
      order by c.created_at, c.name)
      from app.ad_campaigns c where c.product = p_product and (not c.is_sample or v_sandbox)), '[]'::jsonb));
end $fn$;

-- create (p_id null) or change a campaign. values: product (create), name, channel, landing_path, budget, starts_on,
-- ends_on. The utm source and medium follow the channel until the campaign has gone live; utm_campaign never changes.
create function public.ad_campaign_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'add'); v jsonb := coalesce(p_values, '{}'::jsonb); c app.ad_campaigns; k text;
  v_name text; v_channel text; v_path text; v_budget numeric; v_start date; v_end date; v_id uuid;
begin
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  for k in select jsonb_object_keys(v) loop
    if k not in ('product', 'name', 'channel', 'landing_path', 'budget', 'starts_on', 'ends_on') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  if p_id is not null then
    select * into c from app.ad_campaigns where id = p_id for update;
    if not found or (c.is_sample and not (select sandbox from app.admins where id = v_me)) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if c.created_by is distinct from v_me and not app.can('campaigns', 'edit_others') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:edit_others';
    end if;
    if p_version is not null and c.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = c.version::text; end if;
    if v ? 'product' and v ->> 'product' is distinct from c.product then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  elsif not exists (select 1 from app.products where key = v ->> 'product') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  v_name := btrim(coalesce(v ->> 'name', c.name, ''));
  if char_length(v_name) not between 1 and 120 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  v_channel := coalesce(v ->> 'channel', c.channel);
  if v_channel is null or v_channel not in ('google_ads', 'linkedin', 'facebook', 'newsletter', 'webinar', 'other') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'channel';
  end if;
  if c.id is not null and v_channel <> c.channel and c.state <> 'scheduled' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'channel';
  end if;
  v_path := coalesce(nullif(btrim(v ->> 'landing_path'), ''), c.landing_path, '/');
  if char_length(v_path) > 300 or v_path !~ '^/[A-Za-z0-9/_.~%-]*$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'landing_path'; end if;
  if v ? 'budget' and v -> 'budget' <> 'null'::jsonb and (jsonb_typeof(v -> 'budget') <> 'number' or (v ->> 'budget')::numeric not between 0 and 1e11) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'budget';
  end if;
  v_budget := case when v ? 'budget' then (v ->> 'budget')::numeric else c.budget end;
  begin
    v_start := case when v ? 'starts_on' then (v ->> 'starts_on')::date else c.starts_on end;
    v_end := case when v ? 'ends_on' then (v ->> 'ends_on')::date else c.ends_on end;
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_on';
  end;
  if v_end is not null and v_start is not null and v_end < v_start then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ends_on'; end if;
  if c.id is null then
    insert into app.ad_campaigns (product, name, channel, landing_path, utm_source, utm_medium, utm_campaign, budget, starts_on, ends_on, created_by, is_sample)
    values (v ->> 'product', v_name, v_channel, v_path, app.ad_utm(v_channel) ->> 'source', app.ad_utm(v_channel) ->> 'medium', app.ad_utm_campaign(v_name),
            v_budget, v_start, v_end, v_me, (select sandbox from app.admins where id = v_me))
    returning id into v_id;
    perform app.log('ad_campaign.created', 'ad_campaign', v_id::text, jsonb_build_object('channel', v_channel));
  else
    v_id := c.id;
    update app.ad_campaigns set name = v_name, channel = v_channel, landing_path = v_path, budget = v_budget, starts_on = v_start, ends_on = v_end,
      utm_source = case when state = 'scheduled' then app.ad_utm(v_channel) ->> 'source' else utm_source end,
      utm_medium = case when state = 'scheduled' then app.ad_utm(v_channel) ->> 'medium' else utm_medium end,
      version = version + 1, updated_at = now()
    where id = c.id;
    perform app.log('ad_campaign.updated', 'ad_campaign', v_id::text, jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(v) x)));
  end if;
  return (select jsonb_build_object('id', x.id, 'version', x.version, 'utm_campaign', x.utm_campaign, 'state', app.ad_state(x)) from app.ad_campaigns x where x.id = v_id);
end $fn$;

-- go live (from scheduled or paused) or pause (from live). The record only: no ad platform is reached. Going live
-- starts the campaign today unless it started earlier; an ended campaign is duplicated instead.
create function public.ad_campaign_set_state(p_id uuid, p_state text, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); c app.ad_campaigns;
begin
  select * into c from app.ad_campaigns where id = p_id for update;
  if not found or (c.is_sample and not (select sandbox from app.admins where id = v_me)) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if c.created_by is distinct from v_me and not app.can('campaigns', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:edit_others';
  end if;
  if p_version is not null and c.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = c.version::text; end if;
  if p_state not in ('live', 'paused') or app.ad_state(c) = 'ended'
     or (p_state = 'live' and c.state not in ('scheduled', 'paused')) or (p_state = 'paused' and c.state <> 'live') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state';
  end if;
  update app.ad_campaigns set state = p_state,
    starts_on = case when p_state = 'live' and (starts_on is null or starts_on > current_date) then current_date else starts_on end,
    version = version + 1, updated_at = now()
  where id = p_id;
  perform app.log('ad_campaign.' || p_state, 'ad_campaign', p_id::text, null);
  return (select jsonb_build_object('id', x.id, 'version', x.version, 'state', app.ad_state(x)) from app.ad_campaigns x where x.id = p_id);
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text; f text;
begin
  foreach t in array array['seo_keywords', 'ad_campaigns'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
  foreach f in array array['app.product_site(text)', 'app.ad_utm(text)', 'app.ad_utm_campaign(text)', 'app.ad_state(app.ad_campaigns)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.growth_overview(text, int)', 'public.seo_get(text, int)', 'public.seo_keyword_add(text, text)', 'public.seo_keyword_remove(uuid)',
                           'public.ad_campaigns_get(text)', 'public.ad_campaign_save(uuid, jsonb, int)', 'public.ad_campaign_set_state(uuid, text, int)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
