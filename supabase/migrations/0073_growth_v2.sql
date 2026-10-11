-- 0073_growth_v2.sql — Growth v2 (SimpleGrowth.dc.html of 11 Oct 2026: Overview · Signup funnel and log · Pages and links ·
-- SEO › Keywords · Integrations). docs/crm-enrichment/growth-v2-gap.md maps every element to its source.
--
-- Every read takes the same scope: an application, a period (today, 7, 30 or 90 days), optionally one day and one hour of
-- it, and optionally a channel and a device class. Days and hours are Oslo's. The previous period is the one before; a
-- day or an hour is compared with the same one a week earlier.
--
-- Website figures count the tracker's sessions (cookieless, D-37). Account figures count the products' own events
-- (accounts created, milestones, subscriptions); they follow the channel through the account's first-touch attribution,
-- and a device filter cannot reach them (a device is a property of a visit, not of an account), so they are null under one.
--
-- Also:
-- * a press (`cta`) keeps the page it was made on (web_events.path), for «Links and buttons on our site»;
-- * a visit from another site is «referral» (it was «direct», having no rule) — the site's own hosts are not referrers;
-- * the crawler keeps what it read on each page (seo_pages: title, description, status, time) for the page card;
-- * page_vitals holds Core Web Vitals from PageSpeed Insights (pagespeed-run, 0073), read in Pages and links;
-- * growth_sync_log records each import with its rows and errors, read by Integrations › Sync log.
--
-- Nothing here is about a person: a session is a daily-salted hash, an account is an organisation's.

-- ===========================================================================
-- 1. the tracker: a press's page, referrals
-- ===========================================================================
alter table app.web_events add column if not exists path text check (path is null or (path ~ '^/' and char_length(path) <= 500));
create index if not exists web_sessions_started on app.web_sessions (site_id, started_at);
create index if not exists web_events_session on app.web_events (session_id, at);

insert into app.channel_rules (ord, channel, match)
select 950, 'referral', '{"referrer_host": "%.%"}'::jsonb
where not exists (select 1 from app.channel_rules where channel = 'referral');

-- the site's own hosts (and www twins) are not referrers: a visit that comes from them arrives with none
create function app.web_foreign_referrer(p_site uuid, p_host text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select case when p_host is null or btrim(p_host) = '' then null
              when exists (select 1 from app.web_sites s
                           where s.id = p_site
                             and regexp_replace(lower(p_host), '^www\.', '') = any (array[regexp_replace(s.hostname, '^www\.', '')]
                                   || array(select regexp_replace(a, '^www\.', '') from unnest(s.aliases) a))) then null
              else lower(p_host) end
$fn$;

CREATE OR REPLACE FUNCTION public.worker_web_ingest(p_batch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x jsonb; v_site uuid; v_sess uuid; v_utm jsonb; n int := 0; v_survey int := 0; v_org text; v_at timestamptz; v_crm uuid; v_new boolean;
  v_ident boolean := app.setting('web_ident') = 'on'; v_ref text;
begin
  if jsonb_typeof(p_batch) <> 'array' or jsonb_array_length(p_batch) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'batch'; end if;
  for x in select * from jsonb_array_elements(p_batch) loop
    -- never a survey host, even if one were registered (fixed rule, LGN-05)
    if lower(coalesce(x ->> 'site', '')) ~ '(^|\.)svar\.' then v_survey := v_survey + 1; continue; end if;
    select id into v_site from app.web_sites where hostname = lower(x ->> 'site') and active;
    -- the hash is the tracker's daily-salted digest; anything else (an address, a cookie) is dropped
    continue when v_site is null or coalesce(x ->> 'visitor_hash', '') !~ '^[0-9a-f]{32,64}$';
    v_at := (x ->> 'at')::timestamptz;
    v_utm := case when jsonb_typeof(x -> 'utm') = 'object' then x -> 'utm' else '{}'::jsonb end;
    v_ref := app.web_foreign_referrer(v_site, left(x ->> 'referrer_host', 200));
    v_org := case when v_ident and x ->> 'company_org_number' ~ '^\d{9}$'
                       and not exists (select 1 from app.web_companies w where w.org_number = x ->> 'company_org_number' and w.excluded)
                  then x ->> 'company_org_number' end;
    v_new := false;
    -- a session: the same visitor hash on the same day, within 30 minutes of its last page
    select s.id into v_sess from app.web_sessions s
    where s.site_id = v_site and s.day = v_at::date and s.visitor_hash = x ->> 'visitor_hash'
      and exists (select 1 from app.web_pageviews p where p.session_id = s.id and p.at > v_at - interval '30 minutes')
    order by s.started_at desc limit 1;
    if v_sess is null then
      insert into app.web_sessions (site_id, day, visitor_hash, started_at, entry_path, referrer_host, utm, channel, company_org_number, pageviews, device, host)
      values (v_site, v_at::date, x ->> 'visitor_hash', v_at, left(x ->> 'path', 500), v_ref,
              v_utm, app.channel_of(v_utm || jsonb_build_object('referrer_host', v_ref)), v_org, 0,
              case when x ->> 'device' in ('mobile', 'tablet', 'desktop') then x ->> 'device' end,
              case when x ->> 'host' ~ '^[a-z0-9.-]{1,253}$' then x ->> 'host' end)
      returning id into v_sess;
      v_new := true;
    end if;
    if jsonb_typeof(x -> 'event') = 'object' then
      -- the page the press or the step happened on (0073)
      insert into app.web_events (session_id, at, name, value, path)
      values (v_sess, v_at, x -> 'event' ->> 'name', left(x -> 'event' ->> 'value', 120),
              case when x ->> 'path' ~ '^/' then left(x ->> 'path', 500) end);
    else
      insert into app.web_pageviews (session_id, at, path) values (v_sess, v_at, left(coalesce(x ->> 'path', '/'), 500));
      update app.web_sessions set pageviews = pageviews + 1 where id = v_sess;
    end if;
    update app.web_sites set last_seen_at = greatest(coalesce(last_seen_at, v_at), v_at) where id = v_site;
    if v_new and v_org is not null then
      -- an unknown company: the register lookup (Brønnøysund, no key) runs in the edge worker
      if not exists (select 1 from app.web_companies w where w.org_number = v_org)
         and not exists (select 1 from app.web_sessions s where s.company_org_number = v_org and s.id <> v_sess and s.day > current_date - 30) then
        perform pgmq.send('jobs', jsonb_build_object('job', 'company_lookup', 'org_number', v_org));
      end if;
      -- visitor.identified: once per CRM organization per day, on its first session
      select o.id into v_crm from app.organizations o where o.org_number = v_org and o.deleted_at is null and not o.is_sample order by o.created_at limit 1;
      if v_crm is not null and not exists (select 1 from app.web_sessions s where s.company_org_number = v_org and s.day = v_at::date and s.id <> v_sess) then
        perform app.emit('visitor.identified', 'organization', v_crm,
                         jsonb_build_object('org_number', v_org, 'pages', (select pageviews from app.web_sessions where id = v_sess),
                                            'high_intent', coalesce(x ->> 'path', '') ~* '^/(pris|priser|pricing|demo|kontakt|contact)(/|$)'));
      end if;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('stored', n, 'dropped_survey', v_survey);
end $function$;

-- ===========================================================================
-- 2. what the crawler read on each page; Core Web Vitals; the sync log
-- ===========================================================================
create table app.seo_pages (
  site_id     uuid not null references app.web_sites (id) on delete cascade,
  path        text not null check (path ~ '^/' and char_length(path) <= 300),
  title       text check (title is null or char_length(title) <= 300),
  description text check (description is null or char_length(description) <= 400),
  h1          int not null default 0 check (h1 >= 0),
  status      int not null check (status between 0 and 999),
  ms          int not null check (ms >= 0),
  noindex     boolean not null default false,
  seen_at     timestamptz not null default now(),
  primary key (site_id, path)
);
alter table app.seo_pages enable row level security;
revoke all on app.seo_pages from public, anon, authenticated;

-- one crawl's pages, replacing what the last crawl read (a page no longer in the sitemap keeps its last reading, dated)
create function public.worker_seo_pages(p_site uuid, p_pages jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int;
begin
  if not exists (select 1 from app.web_sites where id = p_site) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if jsonb_typeof(p_pages) <> 'array' or jsonb_array_length(p_pages) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pages'; end if;
  insert into app.seo_pages (site_id, path, title, description, h1, status, ms, noindex, seen_at)
  select p_site, left(x ->> 'path', 300), left(nullif(x ->> 'title', ''), 300), left(nullif(x ->> 'description', ''), 400),
         greatest(coalesce((x ->> 'h1')::int, 0), 0), least(greatest(coalesce((x ->> 'status')::int, 0), 0), 999),
         greatest(coalesce((x ->> 'ms')::int, 0), 0), coalesce((x ->> 'noindex')::boolean, false), now()
  from jsonb_array_elements(p_pages) x
  where x ->> 'path' ~ '^/'
  on conflict (site_id, path) do update set title = excluded.title, description = excluded.description, h1 = excluded.h1,
    status = excluded.status, ms = excluded.ms, noindex = excluded.noindex, seen_at = excluded.seen_at;
  get diagnostics n = row_count;
  return jsonb_build_object('pages', n);
end $fn$;

create table app.page_vitals (
  site_id    uuid not null references app.web_sites (id) on delete cascade,
  path       text not null check (path ~ '^/' and char_length(path) <= 300),
  strategy   text not null default 'mobile' check (strategy in ('mobile', 'desktop')),
  lcp_ms     int check (lcp_ms is null or lcp_ms >= 0),
  inp_ms     int check (inp_ms is null or inp_ms >= 0),
  cls        numeric check (cls is null or cls >= 0),
  score      int check (score is null or score between 0 and 100),
  field      boolean not null default false,   -- INP and the others from real Chrome users (CrUX) rather than the lab run
  fetched_at timestamptz not null default now(),
  primary key (site_id, path, strategy)
);
alter table app.page_vitals enable row level security;
revoke all on app.page_vitals from public, anon, authenticated;

create table app.growth_sync_log (
  id      bigint generated always as identity primary key,
  at      timestamptz not null default now(),
  source  text not null check (source in ('search_console', 'pagespeed', 'crawler', 'tracker', 'product_events', 'email')),
  site_id uuid references app.web_sites (id) on delete cascade,
  rows    int check (rows is null or rows >= 0),
  info    jsonb not null default '{}'::jsonb check (jsonb_typeof(info) = 'object'),
  state   text not null check (state in ('ok', 'warning', 'failed'))
);
alter table app.growth_sync_log enable row level security;
revoke all on app.growth_sync_log from public, anon, authenticated;
create index growth_sync_log_at on app.growth_sync_log (at desc);

-- a worker's line in the log: counts and codes only
create function public.worker_growth_sync(p_source text, p_site uuid, p_rows int, p_info jsonb, p_state text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_info is not null and (jsonb_typeof(p_info) <> 'object' or length(p_info::text) > 2000) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'info';
  end if;
  insert into app.growth_sync_log (source, site_id, rows, info, state)
  values (p_source, p_site, p_rows, coalesce(p_info, '{}'::jsonb), p_state);
end $fn$;

-- the crawl's own line, written where the crawl's verdict is (worker_seo_crawl_result is 0072's; this follows it)
create function app.seo_crawl_logged() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  insert into app.growth_sync_log (at, source, site_id, rows, info, state)
  values (new.finished_at, 'crawler', new.site_id, new.pages,
          jsonb_build_object('ms', new.ms, 'issues', (select count(*) from app.seo_issues i where i.site_id = new.site_id and i.resolved_at is null and i.fixed_at is null))
            || case when new.error is not null then jsonb_build_object('code', new.error) else '{}'::jsonb end,
          case when new.error = 'unreachable' then 'failed' when new.error is not null then 'warning' else 'ok' end);
  return new;
end $fn$;
-- deferred: the line is written at commit, after the verdict has updated the issues it counts
create constraint trigger seo_crawls_logged after insert on app.seo_crawls deferrable initially deferred
  for each row execute function app.seo_crawl_logged();

-- Search Console's windows land here too (worker_search_console_import, 0064, is unchanged): one line per site and day
create function app.search_console_logged() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if new.last_import_at is distinct from old.last_import_at or new.last_error is distinct from old.last_error then
    insert into app.growth_sync_log (source, site_id, rows, info, state)
    values ('search_console', new.site_id,
            null,
            jsonb_build_object('last_day', new.last_day) || case when new.last_error is not null then jsonb_build_object('code', new.last_error) else '{}'::jsonb end,
            case when new.last_error is not null then 'failed' else 'ok' end);
  end if;
  return new;
end $fn$;
create trigger search_console_sites_logged after update on app.search_console_sites for each row execute function app.search_console_logged();

-- ===========================================================================
-- 3. the scope
-- ===========================================================================
-- [t0, t1) and the period before, in Oslo's days and hours. p_days 1 | 7 | 30 | 90; p_day within the last 90 days;
-- p_hour only with p_day.
create function app.growth_window(p_days int, p_day date, p_hour int)
  returns table (t0 timestamptz, t1 timestamptz, p0 timestamptz, p1 timestamptz, d int)
  language plpgsql stable set search_path = ''
as $fn$
declare
  v_d int := case when p_days in (1, 7, 30, 90) then p_days else 30 end;
  v_today date := (now() at time zone 'Europe/Oslo')::date;
begin
  if p_hour is not null and (p_day is null or p_hour not between 0 and 23) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'hour';
  end if;
  if p_day is not null and (p_day > v_today or p_day <= v_today - 90) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'day';
  end if;
  if p_hour is not null then
    t0 := (p_day::timestamp + make_interval(hours => p_hour)) at time zone 'Europe/Oslo';
    t1 := (p_day::timestamp + make_interval(hours => p_hour + 1)) at time zone 'Europe/Oslo';
    p0 := ((p_day - 7)::timestamp + make_interval(hours => p_hour)) at time zone 'Europe/Oslo';
    p1 := ((p_day - 7)::timestamp + make_interval(hours => p_hour + 1)) at time zone 'Europe/Oslo';
  elsif p_day is not null then
    t0 := p_day::timestamp at time zone 'Europe/Oslo';
    t1 := (p_day + 1)::timestamp at time zone 'Europe/Oslo';
    p0 := (p_day - 7)::timestamp at time zone 'Europe/Oslo';
    p1 := (p_day - 6)::timestamp at time zone 'Europe/Oslo';
  else
    t0 := (v_today - v_d + 1)::timestamp at time zone 'Europe/Oslo';
    t1 := (v_today + 1)::timestamp at time zone 'Europe/Oslo';
    p0 := (v_today - 2 * v_d + 1)::timestamp at time zone 'Europe/Oslo';
    p1 := t0;
  end if;
  d := v_d;
  return next;
end $fn$;

create function app.growth_check_filters(p_channel text, p_device text) returns void
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if p_channel is not null and p_channel !~ '^[a-z_]{2,30}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'channel'; end if;
  if p_device is not null and p_device not in ('desktop', 'mobile', 'tablet') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'device'; end if;
end $fn$;

-- an account's channel: its first touch, as the products report it (org.attribution)
create function app.account_channel(p_attribution jsonb) returns text
  language sql stable security definer set search_path = ''
as $fn$ select app.channel_of(coalesce(p_attribution -> 'first_touch', p_attribution, '{}'::jsonb)) $fn$;

create function app.growth_sites(p_product text) returns uuid[]
  language sql stable security definer set search_path = ''
as $fn$ select array(select s.id from app.web_sites s where s.active and (nullif(p_product, 'all') is null or s.product = p_product) order by s.hostname) $fn$;

-- the pages that say what the product costs or does
create function app.is_pricing_path(p_path text) returns boolean
  language sql immutable set search_path = ''
as $fn$ select coalesce(p_path, '') ~* '^/(en/|sv/|da/|de/)?(pris|priser|pricing|plattform|platform|produkt|product|funksjoner|features)(/|$)' $fn$;

create function app.is_signup_path(p_path text) returns boolean
  language sql immutable set search_path = ''
as $fn$ select coalesce(p_path, '') ~* '^/(en/|sv/|da/|de/)?(registrer|signup|kom-i-gang|get-started)(/|$)' $fn$;

-- the share of a month a window covers, by time (spend is entered per month)
create function app.month_share(p_month date, p_t0 timestamptz, p_t1 timestamptz) returns numeric
  language sql stable set search_path = ''
as $fn$
  select greatest(0, extract(epoch from least(p_t1, (p_month + interval '1 month')::timestamp at time zone 'Europe/Oslo')
                                      - greatest(p_t0, p_month::timestamp at time zone 'Europe/Oslo')))::numeric
         / extract(epoch from ((p_month + interval '1 month')::timestamp at time zone 'Europe/Oslo' - p_month::timestamp at time zone 'Europe/Oslo'))::numeric
$fn$;

-- ===========================================================================
-- 4. Overview
-- ===========================================================================
create function public.growth_scope(p_product text default null, p_days int default 30, p_day date default null, p_hour int default null,
                                    p_channel text default null, p_device text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  w record; v_sites uuid[]; v_product text := nullif(p_product, 'all'); v_since date; v_dev boolean := p_device is not null;
  v_series jsonb; v_spend numeric; v_spend_prev numeric; v_s0 timestamptz; v_s1 timestamptz;
begin
  perform app.require_marketing_reports();
  perform app.growth_check_filters(p_channel, p_device);
  if v_product is not null and not exists (select 1 from app.products where key = v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  select * into w from app.growth_window(p_days, p_day, p_hour);
  v_sites := app.growth_sites(v_product);
  v_since := (select min((x.started_at at time zone 'Europe/Oslo')::date) from app.web_sessions x where x.site_id = any (v_sites));

  -- spend is entered per month: a period takes each month's share by its days in it (never with a device filter). Under a
  -- channel, a campaign's spend counts where its utm parameters send its visits (app.channel_of, as for a session)
  if not v_dev and p_day is null then
    select sum(ms.amount * app.month_share(ms.month, w.t0, w.t1))
      into v_spend
    from app.marketing_spend ms left join app.ad_campaigns c on c.utm_campaign = ms.campaign
    where ms.currency = 'NOK' and app.in_scope(v_product, c.product)
      and ms.month::timestamp at time zone 'Europe/Oslo' < w.t1 and (ms.month + interval '1 month')::timestamp at time zone 'Europe/Oslo' > w.t0
      and (p_channel is null or app.channel_of(jsonb_build_object('utm_source', c.utm_source, 'utm_medium', c.utm_medium)) = p_channel);
    select sum(ms.amount * app.month_share(ms.month, w.p0, w.p1))
      into v_spend_prev
    from app.marketing_spend ms left join app.ad_campaigns c on c.utm_campaign = ms.campaign
    where ms.currency = 'NOK' and app.in_scope(v_product, c.product)
      and ms.month::timestamp at time zone 'Europe/Oslo' < w.p1 and (ms.month + interval '1 month')::timestamp at time zone 'Europe/Oslo' > w.p0
      and (p_channel is null or app.channel_of(jsonb_build_object('utm_source', c.utm_source, 'utm_medium', c.utm_medium)) = p_channel);
  end if;

  -- the chart: the period's days, or the chosen day's hours (with an hour chosen, the whole day stays drawn)
  v_s0 := case when p_day is not null then p_day::timestamp at time zone 'Europe/Oslo' else w.t0 end;
  v_s1 := case when p_day is not null then (p_day + 1)::timestamp at time zone 'Europe/Oslo' else w.t1 end;
  with s as (
    select x.id, x.started_at, x.visitor_hash, (x.started_at at time zone 'Europe/Oslo') lt,
           exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_started') started
    from app.web_sessions x
    where x.site_id = any (v_sites) and x.started_at >= v_s0 and x.started_at < v_s1
      and (p_channel is null or coalesce(x.channel, 'direct') = p_channel) and (p_device is null or x.device = p_device)
  ), a as (
    select ap.created_at, (ap.created_at at time zone 'Europe/Oslo') lt from app.account_products ap
    where not v_dev and app.in_scope(v_product, ap.product) and ap.created_at >= v_s0 and ap.created_at < v_s1
      and (p_channel is null or app.account_channel(ap.attribution) = p_channel)
  ), pay as (
    select sb.confirmed_at, (sb.confirmed_at at time zone 'Europe/Oslo') lt from app.subscriptions sb
    join app.account_products ap on ap.product = sb.product and ap.tenant_id = sb.tenant_id
    where not v_dev and app.in_scope(v_product, sb.product) and sb.confirmed_at >= v_s0 and sb.confirmed_at < v_s1
      and (p_channel is null or app.account_channel(ap.attribution) = p_channel)
  ), slots as (
    -- hours of the chosen day, or the days of the period
    select g, case when p_day is not null then g::int end h, case when p_day is null then (w.t0 at time zone 'Europe/Oslo')::date + g end dd
    from generate_series(0, case when p_day is not null then 23 else w.d - 1 end) g
  )
  select jsonb_agg(jsonb_build_object(
           'at', coalesce(to_char(sl.dd, 'YYYY-MM-DD'), sl.h::text),
           -- before the tracker's first day, visitors are not known
           'visitors', case when v_since is not null and coalesce(sl.dd, p_day) >= v_since then
                         (select count(distinct (s.lt::date, s.visitor_hash)) from s
                          where (sl.dd is not null and s.lt::date = sl.dd) or (sl.h is not null and extract(hour from s.lt) = sl.h)) end,
           'started', case when v_since is not null and coalesce(sl.dd, p_day) >= v_since then
                        (select count(*) from s where s.started and ((sl.dd is not null and s.lt::date = sl.dd) or (sl.h is not null and extract(hour from s.lt) = sl.h))) end,
           'accounts', case when not v_dev then (select count(*) from a where (sl.dd is not null and a.lt::date = sl.dd) or (sl.h is not null and extract(hour from a.lt) = sl.h)) end,
           'paying', case when not v_dev then (select count(*) from pay where (sl.dd is not null and pay.lt::date = sl.dd) or (sl.h is not null and extract(hour from pay.lt) = sl.h)) end)
         order by sl.g) into v_series
  from slots sl;

  return (
    with s as (
      select x.id, x.started_at, x.visitor_hash, coalesce(x.channel, 'direct') channel, (x.started_at at time zone 'Europe/Oslo') lt,
             exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_started') started
      from app.web_sessions x
      where x.site_id = any (v_sites) and x.started_at >= w.t0 and x.started_at < w.t1
        and (p_channel is null or coalesce(x.channel, 'direct') = p_channel) and (p_device is null or x.device = p_device)
    ), sp as (
      select x.id, x.visitor_hash, (x.started_at at time zone 'Europe/Oslo') lt,
             exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_started') started
      from app.web_sessions x
      where x.site_id = any (v_sites) and x.started_at >= w.p0 and x.started_at < w.p1
        and (p_channel is null or coalesce(x.channel, 'direct') = p_channel) and (p_device is null or x.device = p_device)
    ), a as (
      select ap.product, ap.tenant_id, ap.created_at, app.account_channel(ap.attribution) channel from app.account_products ap
      where not v_dev and app.in_scope(v_product, ap.product) and ap.created_at >= w.p0 and ap.created_at < w.t1
    ), pay as (
      select sb.confirmed_at, app.account_channel(ap.attribution) channel from app.subscriptions sb
      join app.account_products ap on ap.product = sb.product and ap.tenant_id = sb.tenant_id
      where not v_dev and app.in_scope(v_product, sb.product) and sb.confirmed_at >= w.p0 and sb.confirmed_at < w.t1
    )
    select jsonb_build_object(
      'days', w.d, 'day', p_day, 'hour', p_hour, 'channel', p_channel, 'device', p_device,
      'from', (w.t0 at time zone 'Europe/Oslo')::date, 'to', ((w.t1 at time zone 'Europe/Oslo') - interval '1 second')::date,
      'tracked_since', v_since,
      'site', (select jsonb_build_object('id', x.id, 'hostname', x.hostname) from app.web_sites x where x.id = v_sites[1]),
      -- the newest thing the figures were made of
      'updated_at', greatest((select max(x.last_seen_at) from app.web_sites x where x.id = any (v_sites)),
                             (select max(e.received_at) from app.events_in e where app.in_scope(v_product, e.product))),
      'kpis', jsonb_build_object(
        'visitors', case when v_since is not null then (select count(distinct (s.lt::date, s.visitor_hash)) from s) end,
        -- the previous period counts only when the tracker ran through it
        'visitors_prev', case when v_since is not null and v_since <= (w.p0 at time zone 'Europe/Oslo')::date then (select count(distinct (sp.lt::date, sp.visitor_hash)) from sp) end,
        'started', case when v_since is not null then (select count(*) from s where s.started) end,
        'started_prev', case when v_since is not null and v_since <= (w.p0 at time zone 'Europe/Oslo')::date then (select count(*) from sp where sp.started) end,
        'accounts', case when not v_dev then (select count(*) from a where a.created_at >= w.t0 and (p_channel is null or a.channel = p_channel)) end,
        'accounts_prev', case when not v_dev then (select count(*) from a where a.created_at < w.p1 and (p_channel is null or a.channel = p_channel)) end,
        'paying', case when not v_dev then (select count(*) from pay where pay.confirmed_at >= w.t0 and (p_channel is null or pay.channel = p_channel)) end,
        'paying_prev', case when not v_dev then (select count(*) from pay where pay.confirmed_at < w.p1 and (p_channel is null or pay.channel = p_channel)) end,
        'spend', round(v_spend), 'spend_prev', round(v_spend_prev)),
      'series', coalesce(v_series, '[]'::jsonb),
      -- the hour of the day most signups began in, over the scope
      'peak_hour', (select extract(hour from s.lt)::int from s where s.started group by 1 order by count(*) desc, 1 limit 1),
      -- visits and signups begun by device, for the Overview's opportunities
      'devices', coalesce((select jsonb_agg(jsonb_build_object('device', d.device, 'visits', d.n, 'started', d.st) order by d.n desc) from (
          select coalesce(x.device, 'unknown') device, count(*) n, count(*) filter (where exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_started')) st
          from app.web_sessions x
          where x.site_id = any (v_sites) and x.started_at >= w.t0 and x.started_at < w.t1 and x.device is not null
            and (p_channel is null or coalesce(x.channel, 'direct') = p_channel) and (p_device is null or x.device = p_device)
          group by 1) d), '[]'::jsonb),
      'channels', coalesce((select jsonb_agg(jsonb_build_object('channel', c.channel, 'visits', case when v_since is not null then coalesce(v.n, 0) end,
                                                                 'started', case when v_since is not null then coalesce(v.st, 0) end,
                                                                 'accounts', case when not v_dev then coalesce(ac.n, 0) end,
                                                                 'paying', case when not v_dev then coalesce(pc.n, 0) end)
                                             order by coalesce(v.n, 0) desc, coalesce(ac.n, 0) desc, c.channel) from
          (select s.channel from s union select a.channel from a where a.created_at >= w.t0 union select pay.channel from pay where pay.confirmed_at >= w.t0) c
          left join (select s.channel, count(*) n, count(*) filter (where s.started) st from s group by 1) v on v.channel = c.channel
          left join (select a.channel, count(*) n from a where a.created_at >= w.t0 group by 1) ac on ac.channel = c.channel
          left join (select pay.channel, count(*) n from pay where pay.confirmed_at >= w.t0 group by 1) pc on pc.channel = c.channel), '[]'::jsonb))
    from (select 1) one);
end $fn$;

-- ===========================================================================
-- 5. Signup funnel and log
-- ===========================================================================
-- A session reaches step 1 (a visit), 2 (a pricing or product page), 3 (a press towards signup, or the signup page),
-- 4 (the organisation number sent). Steps 5–8 are the accounts created in the scope and how many of them uploaded the
-- employee list, sent a first survey and became paying. Session steps count visitors (day × visitor), so they match
-- the Overview's visitors. p_step (1–7) is the transition the card explains: s → s + 1.
create function public.growth_funnel(p_product text default null, p_days int default 30, p_day date default null, p_hour int default null,
                                     p_channel text default null, p_device text default null, p_step int default 4) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  w record; v_sites uuid[]; v_product text := nullif(p_product, 'all'); v_dev boolean := p_device is not null;
  st int := case when p_step between 1 and 7 then p_step else 4 end; v_since date;
begin
  perform app.require_marketing_reports();
  perform app.growth_check_filters(p_channel, p_device);
  select * into w from app.growth_window(p_days, p_day, p_hour);
  v_sites := app.growth_sites(v_product);
  v_since := (select min((x.started_at at time zone 'Europe/Oslo')::date) from app.web_sessions x where x.site_id = any (v_sites));
  return (
    with base as (
      select x.id, x.started_at, x.visitor_hash, x.entry_path, x.pageviews, coalesce(x.channel, 'direct') channel, coalesce(x.device, 'unknown') device,
             coalesce(nullif(lower(btrim(x.utm ->> 'utm_source')), ''), x.referrer_host) source,
             (x.started_at at time zone 'Europe/Oslo')::date lday, x.started_at >= w.t0 cur
      from app.web_sessions x
      where x.site_id = any (v_sites) and ((x.started_at >= w.t0 and x.started_at < w.t1) or (x.started_at >= w.p0 and x.started_at < w.p1))
        and (p_channel is null or coalesce(x.channel, 'direct') = p_channel) and (p_device is null or x.device = p_device)
    ), s as (
      select b.*,
             (select min(p.at) from app.web_pageviews p where p.session_id = b.id and app.is_pricing_path(p.path)) t2,
             least((select min(e.at) from app.web_events e where e.session_id = b.id and e.name = 'cta'),
                   (select min(p.at) from app.web_pageviews p where p.session_id = b.id and app.is_signup_path(p.path))) t3,
             (select min(e.at) from app.web_events e where e.session_id = b.id and e.name = 'signup_started') t4,
             (select min(e.at) from app.web_events e where e.session_id = b.id and e.name = 'signup_completed') t5,
             (select p.path from app.web_pageviews p where p.session_id = b.id order by p.at desc limit 1) exit_path,
             greatest((select max(p.at) from app.web_pageviews p where p.session_id = b.id), (select max(e.at) from app.web_events e where e.session_id = b.id)) last_at
      from base b
    ), r as (
      select s.*, case when s.t4 is not null then 4 when s.t3 is not null then 3 when s.t2 is not null then 2 else 1 end reached from s
    ), vis as (
      -- a visitor (day × hash) reaches the furthest step any of its sessions reached
      select r.cur, r.lday, r.visitor_hash, max(r.reached) reached from r group by 1, 2, 3
    ), acc as (
      select ap.product, ap.tenant_id, ap.created_at, ap.created_at >= w.t0 cur, app.account_channel(ap.attribution) channel,
             (select m.reached_at from app.activation_milestones m where m.product = ap.product and m.tenant_id = ap.tenant_id and m.key = 'employees_uploaded') t6,
             (select m.reached_at from app.activation_milestones m where m.product = ap.product and m.tenant_id = ap.tenant_id and m.key = 'survey_sent') t7,
             (select sb.confirmed_at from app.subscriptions sb where sb.product = ap.product and sb.tenant_id = ap.tenant_id) t8
      from app.account_products ap
      where not v_dev and app.in_scope(v_product, ap.product)
        and ((ap.created_at >= w.t0 and ap.created_at < w.t1) or (ap.created_at >= w.p0 and ap.created_at < w.p1))
        and (p_channel is null or app.account_channel(ap.attribution) = p_channel)
    ), steps as (
      select k, cur,
             case when k <= 4 then case when v_since is null then null else (select count(*) from vis where vis.cur = c.cur and vis.reached >= k) end
                  when v_dev then null
                  when k = 5 then (select count(*) from acc where acc.cur = c.cur)
                  when k = 6 then (select count(*) from acc where acc.cur = c.cur and acc.t6 is not null)
                  when k = 7 then (select count(*) from acc where acc.cur = c.cur and acc.t7 is not null)
                  else (select count(*) from acc where acc.cur = c.cur and acc.t8 is not null) end n
      from generate_series(1, 8) k cross join (values (true), (false)) c(cur)
    )
    select jsonb_build_object(
      'days', w.d, 'day', p_day, 'hour', p_hour, 'step', st, 'tracked_since', v_since,
      'steps', (select jsonb_agg(jsonb_build_object('key', z.k, 'count', z.c, 'prev', z.p) order by z.k) from (
          select k, max(n) filter (where cur) c, max(n) filter (where not cur) p from steps group by k) z),
      -- the transition st → st + 1
      'median_seconds', case
          when st = 1 then (select percentile_cont(0.5) within group (order by extract(epoch from r.t2 - r.started_at)) from r where r.cur and r.t2 is not null)
          when st = 2 then (select percentile_cont(0.5) within group (order by extract(epoch from r.t3 - r.t2)) from r where r.cur and r.t2 is not null and r.t3 > r.t2)
          when st = 3 then (select percentile_cont(0.5) within group (order by extract(epoch from r.t4 - r.t3)) from r where r.cur and r.t3 is not null and r.t4 > r.t3)
          when st = 4 then (select percentile_cont(0.5) within group (order by extract(epoch from r.t5 - r.t4)) from r where r.cur and r.t4 is not null and r.t5 > r.t4)
          when st = 5 then (select percentile_cont(0.5) within group (order by extract(epoch from acc.t6 - acc.created_at)) from acc where acc.cur and acc.t6 is not null)
          when st = 6 then (select percentile_cont(0.5) within group (order by extract(epoch from acc.t7 - acc.t6)) from acc where acc.cur and acc.t6 is not null and acc.t7 > acc.t6)
          else (select percentile_cont(0.5) within group (order by extract(epoch from acc.t8 - acc.t7)) from acc where acc.cur and acc.t7 is not null and acc.t8 > acc.t7) end,
      -- why they stopped: where the visits that stopped at the step ended, and what the signup form reported
      'reasons', case when st <= 4 then coalesce((select jsonb_agg(x order by (x ->> 'count')::int desc, x ->> 'value') from (
          select jsonb_build_object('kind', 'exit', 'value', r.exit_path, 'count', count(*)) x from r
          where r.cur and r.reached = st and (st < 4 or r.t5 is null) and r.exit_path is not null group by r.exit_path order by count(*) desc, r.exit_path limit 4) y), '[]'::jsonb)
          || coalesce((select jsonb_agg(jsonb_build_object('kind', 'error', 'value', q.value, 'count', q.n) order by q.n desc, q.value) from (
                         select e.value, count(distinct e.session_id) n from app.web_events e join r on r.id = e.session_id
                         where st >= 3 and r.cur and r.reached = st and (st < 4 or r.t5 is null) and e.name = 'signup_error' and e.value is not null group by e.value) q), '[]'::jsonb)
        else '[]'::jsonb end,
      -- a visit that finished signup on the site did not stop at step 4
      'stopped', case when st <= 4 then (select count(*) from r where r.cur and r.reached = st and (st < 4 or r.t5 is null)) end,
      -- the continue rate by channel and by device (session steps), by the account's channel (account steps)
      'segments', case
          when st <= 3 then coalesce((select jsonb_agg(jsonb_build_object('kind', g.kind, 'key', g.key, 'entered', g.n, 'continued', g.c) order by g.kind, g.n desc, g.key) from (
              select 'channel' kind, r.channel key, count(*) n, count(*) filter (where r.reached > st) c from r where r.cur and r.reached >= st group by 2
              union all
              select 'device', r.device, count(*), count(*) filter (where r.reached > st) from r where r.cur and r.reached >= st and r.device <> 'unknown' group by 2) g), '[]'::jsonb)
          when st = 4 then coalesce((select jsonb_agg(jsonb_build_object('kind', g.kind, 'key', g.key, 'entered', g.n, 'continued', g.c) order by g.kind, g.n desc, g.key) from (
              -- the website's own «done» stands for step 5 inside a visit
              select 'channel' kind, r.channel key, count(*) n, count(*) filter (where r.t5 is not null) c from r where r.cur and r.reached >= 4 group by 2
              union all
              select 'device', r.device, count(*), count(*) filter (where r.t5 is not null) from r where r.cur and r.reached >= 4 and r.device <> 'unknown' group by 2) g), '[]'::jsonb)
          when v_dev then '[]'::jsonb
          else coalesce((select jsonb_agg(jsonb_build_object('kind', 'channel', 'key', g.channel, 'entered', g.n, 'continued', g.c) order by g.n desc, g.channel) from (
              select acc.channel, count(*) filter (where (st = 5) or (st = 6 and acc.t6 is not null) or (st = 7 and acc.t7 is not null)) n,
                     count(*) filter (where (st = 5 and acc.t6 is not null) or (st = 6 and acc.t6 is not null and acc.t7 is not null) or (st = 7 and acc.t7 is not null and acc.t8 is not null)) c
              from acc where acc.cur group by 1) g where g.n > 0), '[]'::jsonb) end,
      -- the visits of the scope, newest first, each with its path through the site
      'log_total', (select count(*) from r where r.cur),
      'log', coalesce((select jsonb_agg(j order by started_at desc) from (
          select r.started_at, jsonb_build_object(
                   'at', r.started_at, 'visitor', 'v_' || left(r.visitor_hash, 4), 'channel', r.channel, 'source', r.source, 'device', r.device,
                   'entry', r.entry_path, 'reached', case when r.t5 is not null then 5 else r.reached end,
                   'seconds', case when r.last_at > r.started_at then round(extract(epoch from (r.last_at - r.started_at)))::int end,
                   'exit', r.exit_path,
                   'trail', coalesce((select jsonb_agg(z.j order by z.at, z.k) from (
                       select h.at, h.k, h.j from (
                         select p.at, 0 k, jsonb_build_object('kind', 'view', 'path', p.path, 'at', p.at) j from app.web_pageviews p where p.session_id = r.id
                         union all
                         select e.at, 1 k, jsonb_build_object('kind', 'event', 'name', e.name, 'value', e.value, 'path', e.path, 'at', e.at) j from app.web_events e where e.session_id = r.id) h
                       order by h.at, h.k limit 30) z), '[]'::jsonb)) j
          from r where r.cur order by r.started_at desc limit 100) x), '[]'::jsonb))
    from (select 1) one);
end $fn$;

-- ===========================================================================
-- 6. Pages and links
-- ===========================================================================
create function public.growth_pages(p_product text default null, p_days int default 30, p_day date default null, p_hour int default null,
                                    p_channel text default null, p_device text default null, p_path text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  w record; v_sites uuid[]; v_product text := nullif(p_product, 'all'); v_path text; v_site uuid;
begin
  perform app.require_marketing_reports();
  perform app.growth_check_filters(p_channel, p_device);
  if p_path is not null and (p_path !~ '^/' or char_length(p_path) > 500) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path'; end if;
  select * into w from app.growth_window(p_days, p_day, p_hour);
  v_sites := app.growth_sites(v_product);
  v_site := v_sites[1];
  -- the page the card shows: the one asked for, else the most visited landing page
  v_path := coalesce(p_path, (select x.entry_path from app.web_sessions x
                              where x.site_id = any (v_sites) and x.started_at >= w.t0 and x.started_at < w.t1 and x.entry_path is not null
                                and (p_channel is null or coalesce(x.channel, 'direct') = p_channel) and (p_device is null or x.device = p_device)
                              group by 1 order by count(*) desc, 1 limit 1));
  return (
    with s as (
      select x.id, x.started_at, x.entry_path, x.pageviews, coalesce(x.channel, 'direct') channel, x.referrer_host,
             (x.started_at at time zone 'Europe/Oslo')::date lday,
             exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_started') started
      from app.web_sessions x
      where x.site_id = any (v_sites) and x.started_at >= w.t0 and x.started_at < w.t1
        and (p_channel is null or coalesce(x.channel, 'direct') = p_channel) and (p_device is null or x.device = p_device)
    )
    select jsonb_build_object(
      'days', w.d, 'day', p_day, 'hour', p_hour, 'path', v_path,
      'tracked', exists (select 1 from app.web_sessions x where x.site_id = any (v_sites)),
      'landing', coalesce((select jsonb_agg(jsonb_build_object('path', l.entry_path, 'visits', l.n, 'bounce', l.b, 'started', l.st,
                                                               'title', pg.title, 'lcp_ms', pv.lcp_ms, 'inp_ms', pv.inp_ms, 'cls', pv.cls)
                                            order by l.n desc, l.entry_path) from (
          select s.entry_path, count(*) n, round(100.0 * count(*) filter (where s.pageviews <= 1) / count(*), 1) b, count(*) filter (where s.started) st
          from s where s.entry_path is not null group by 1 order by 2 desc, 1 limit 40) l
          left join app.seo_pages pg on pg.site_id = v_site and pg.path = l.entry_path
          left join app.page_vitals pv on pv.site_id = v_site and pv.path = l.entry_path and pv.strategy = 'mobile'), '[]'::jsonb),
      'page', case when v_path is not null then jsonb_build_object(
        'path', v_path,
        'title', (select pg.title from app.seo_pages pg where pg.site_id = v_site and pg.path = v_path),
        'visits', (select count(*) from s where s.entry_path = v_path),
        'started', (select count(*) from s where s.entry_path = v_path and s.started),
        'daily', coalesce((select jsonb_agg(jsonb_build_object('day', g.dd, 'visits', (select count(*) from s where s.entry_path = v_path and s.lday = g.dd)) order by g.dd)
                           from (select (w.t0 at time zone 'Europe/Oslo')::date + i dd from generate_series(0, greatest(w.d, 1) - 1) i
                                 where p_day is null) g), '[]'::jsonb),
        'vitals', (select jsonb_build_object('lcp_ms', pv.lcp_ms, 'inp_ms', pv.inp_ms, 'cls', pv.cls, 'score', pv.score, 'field', pv.field, 'fetched_at', pv.fetched_at)
                   from app.page_vitals pv where pv.site_id = v_site and pv.path = v_path and pv.strategy = 'mobile'),
        'sources', coalesce((select jsonb_agg(jsonb_build_object('channel', c.channel, 'visits', c.n) order by c.n desc, c.channel) from (
            select s.channel, count(*) n from s where s.entry_path = v_path group by 1) c), '[]'::jsonb),
        'keywords', coalesce((select jsonb_agg(jsonb_build_object('query', k.query, 'impressions', k.i,
                                                                  'position', round(k.ps / nullif(k.pi, 0), 1)) order by k.i desc, k.query) from (
            select p.query, sum(p.impressions) i, sum(p.position * p.impressions) filter (where p.position is not null) ps,
                   sum(p.impressions) filter (where p.position is not null) pi
            from app.search_console_pages p where p.site_id = v_site and p.page = v_path and p.day > current_date - greatest(w.d, 28)
            group by 1 having sum(p.impressions) > 0 order by 2 desc, 1 limit 8) k), '[]'::jsonb)) end,
      -- other sites that sent visits (search engines are not referring sites): this period, the one before, when first seen
      'referrers', coalesce((select jsonb_agg(jsonb_build_object('host', h.host, 'channel', h.channel, 'visits', h.n, 'started', h.st, 'prev', h.prev, 'first_seen', h.first,
                                                                 'is_new', h.first >= w.t0)
                                              order by h.n desc, h.prev desc, h.host) from (
          select coalesce(c.host, p.host) host, coalesce(c.channel, p.channel) channel, coalesce(c.n, 0) n, coalesce(c.st, 0) st, coalesce(p.n, 0) prev,
                 (select min(x.started_at) from app.web_sessions x where x.site_id = any (v_sites) and x.referrer_host = coalesce(c.host, p.host)) first
          from (select s.referrer_host host, min(s.channel) channel, count(*) n, count(*) filter (where s.started) st from s
                where s.referrer_host is not null and s.channel not in ('organic_search', 'paid_search') group by 1) c
          full join (select x.referrer_host host, min(coalesce(x.channel, 'direct')) channel, count(*) n from app.web_sessions x
                     where x.site_id = any (v_sites) and x.started_at >= w.p0 and x.started_at < w.p1 and x.referrer_host is not null
                       and coalesce(x.channel, 'direct') not in ('organic_search', 'paid_search')
                       and (p_channel is null or coalesce(x.channel, 'direct') = p_channel) and (p_device is null or x.device = p_device)
                     group by 1) p on p.host = c.host
          order by 3 desc, 5 desc limit 25) h), '[]'::jsonb),
      -- presses on the site's links and buttons: the page, how many visits pressed, of the visits that saw the page, and how
      -- many of those went on to send the organisation number
      'ctas', coalesce((select jsonb_agg(jsonb_build_object('value', c.value, 'path', c.path, 'clicks', c.clicks, 'sessions', c.n, 'page_sessions', c.seen, 'started', c.st)
                                         order by c.clicks desc, c.value) from (
          select e.value, coalesce(e.path, (select p.path from app.web_pageviews p where p.session_id = e.session_id and p.at <= e.at order by p.at desc limit 1)) path,
                 count(*) clicks, count(distinct e.session_id) n,
                 count(distinct e.session_id) filter (where s.started) st
          from app.web_events e join s on s.id = e.session_id
          where e.name = 'cta' and e.value is not null group by 1, 2 order by 3 desc limit 20) c0
          cross join lateral (select c0.value, c0.path, c0.clicks, c0.n, c0.st,
                                     (select count(distinct p.session_id) from app.web_pageviews p join s on s.id = p.session_id where p.path = c0.path) seen) c), '[]'::jsonb))
    from (select 1) one);
end $fn$;

-- ===========================================================================
-- 7. SEO › Keywords: a keyword's position day by day; the periods 1 and 7 days
-- ===========================================================================
create function public.seo_keyword_history(p_product text, p_query text, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_site app.web_sites := app.product_site(nullif(p_product, 'all')); d int := case when p_days in (7, 30, 90) then p_days else 30 end;
begin
  perform app.require_marketing_reports();
  if p_query is null or char_length(p_query) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'query'; end if;
  return jsonb_build_object('query', lower(btrim(p_query)), 'days', d,
    'points', coalesce((select jsonb_agg(jsonb_build_object('day', x.day, 'position', x.position, 'impressions', x.impressions, 'clicks', x.clicks) order by x.day)
                        from app.search_console_daily x
                        where x.site_id = v_site.id and x.query = lower(btrim(p_query)) and x.day > current_date - d), '[]'::jsonb),
    -- the pages Google showed for it: two or more with real impressions is cannibalization
    'pages', coalesce((select jsonb_agg(jsonb_build_object('page', p.page, 'impressions', p.i, 'clicks', p.c) order by p.i desc, p.page) from (
        select p.page, sum(p.impressions) i, sum(p.clicks) c from app.search_console_pages p
        where p.site_id = v_site.id and p.query = lower(btrim(p_query)) and p.day > current_date - d
        group by 1 having sum(p.impressions) > 0 order by 2 desc, 1 limit 5) p), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- 7b. SEO › Keywords' Technical SEO: what Search Console and PageSpeed see that the crawl cannot (seo_get, 0072, extended)
-- ===========================================================================
create or replace function public.seo_get(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  d int := case when p_days in (7, 30, 90) then p_days when p_days = 1 then 7 else 30 end;
  v_site app.web_sites := app.product_site(nullif(p_product, 'all'));
  v_conn boolean := app.connected('search_console');
  c app.integration_connections;
  sc app.search_console_sites;
  v_pages boolean;
  v_pages_prev boolean;
begin
  select * into c from app.integration_connections where provider = 'search_console';
  select * into sc from app.search_console_sites where site_id = v_site.id;
  -- a period counts pages only once pages were imported for it (0072 starts the import)
  v_pages := exists (select 1 from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - d);
  v_pages_prev := exists (select 1 from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - 2 * d and p.day <= current_date - d);
  return jsonb_build_object(
    'connected', v_conn, 'days', d,
    'site', case when v_site.id is not null then jsonb_build_object('id', v_site.id, 'hostname', v_site.hostname) end,
    'search_console', jsonb_build_object(
      'status', c.status,
      'can_manage', exists (select 1 from app.admins where id = v_me and role = 'owner'),
      'key_stored', exists (select 1 from vault.secrets where name = 'search_console_key'),
      'client_email', c.config ->> 'client_email',
      'last_error', c.config ->> 'last_error',
      'property', sc.property,
      'site_error', sc.last_error,
      'last_import_at', sc.last_import_at,
      'last_day', sc.last_day),
    'totals', case when v_conn and v_site.id is not null and sc.property is not null then (
      select jsonb_build_object(
        'clicks', sum(t.clicks) filter (where t.day > current_date - d),
        'clicks_prev', sum(t.clicks) filter (where t.day <= current_date - d),
        'impressions', sum(t.impressions) filter (where t.day > current_date - d),
        'impressions_prev', sum(t.impressions) filter (where t.day <= current_date - d),
        'position', round(sum(t.position * t.impressions) filter (where t.day > current_date - d and t.position is not null)
                          / nullif(sum(t.impressions) filter (where t.day > current_date - d and t.position is not null), 0), 1),
        'position_prev', round(sum(t.position * t.impressions) filter (where t.day <= current_date - d and t.position is not null)
                               / nullif(sum(t.impressions) filter (where t.day <= current_date - d and t.position is not null), 0), 1))
        -- pages Google showed in search in the period (0072), the honest stand-in for «Indexed pages»; null before pages are imported
        || jsonb_build_object(
             'pages', case when v_pages then (select count(distinct p.page) from app.search_console_pages p
                                              where p.site_id = v_site.id and p.day > current_date - d and p.impressions > 0) end,
             'pages_prev', case when v_pages_prev then (select count(distinct p.page) from app.search_console_pages p
                                                        where p.site_id = v_site.id and p.day > current_date - 2 * d and p.day <= current_date - d and p.impressions > 0) end)
      from app.search_console_totals t where t.site_id = v_site.id and t.day > current_date - 2 * d) end,
    'keywords', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'query', k.query, 'created_at', k.created_at, 'mine', k.created_by = v_me,
        'impressions', case when v_conn then x.i end, 'clicks', case when v_conn then x.c end,
        'position', case when v_conn then x.p end, 'position_prev', case when v_conn then x.pp end,
        -- the page Google showed most for it in the period (0072)
        'page', case when v_conn then (select p.page from app.search_console_pages p where p.site_id = k.site_id and p.query = k.query and p.day > current_date - d
                                       group by p.page having sum(p.impressions) > 0 order by sum(p.impressions) desc, p.page limit 1) end) order by k.created_at, k.query)
      from app.seo_keywords k
      left join lateral (
        select sum(sc2.impressions) filter (where sc2.day > current_date - d) i, sum(sc2.clicks) filter (where sc2.day > current_date - d) c,
               round(sum(sc2.position * sc2.impressions) filter (where sc2.day > current_date - d and sc2.position is not null)
                     / nullif(sum(sc2.impressions) filter (where sc2.day > current_date - d and sc2.position is not null), 0), 1) p,
               round(sum(sc2.position * sc2.impressions) filter (where sc2.day <= current_date - d and sc2.position is not null)
                     / nullif(sum(sc2.impressions) filter (where sc2.day <= current_date - d and sc2.position is not null), 0), 1) pp
        from app.search_console_daily sc2 where sc2.site_id = k.site_id and sc2.query = k.query and sc2.day > current_date - 2 * d) x on true
      where k.site_id = v_site.id), '[]'::jsonb),
    -- Site health (0072): the last crawl and its open issues; an issue marked fixed waits for the next crawl to agree
    'health', case when v_site.id is not null then jsonb_build_object(
      'last_crawl_at', (select max(cr.finished_at) from app.seo_crawls cr where cr.site_id = v_site.id),
      'last_error', (select cr.error from app.seo_crawls cr where cr.site_id = v_site.id order by cr.finished_at desc limit 1),
      'pages', (select cr.pages from app.seo_crawls cr where cr.site_id = v_site.id and cr.pages > 0 order by cr.finished_at desc limit 1),
      'awaiting_check', (select count(*) from app.seo_issues i where i.site_id = v_site.id and i.resolved_at is null and i.fixed_at is not null),
      'issues', coalesce((select jsonb_agg(jsonb_build_object('kind', i.kind, 'severity', i.severity, 'count', i.count, 'paths', i.paths, 'value', i.value,
                                                              'ms', i.ms, 'first_seen_at', i.first_seen_at, 'reopened', i.reopened_at is not null)
                                           order by case i.severity when 'high' then 0 else 1 end, i.first_seen_at, i.kind)
                          from app.seo_issues i where i.site_id = v_site.id and i.resolved_at is null and i.fixed_at is null), '[]'::jsonb)) end,
    -- Content ideas (0072): searches Google already shows the site for, outside its top ten, not tracked yet; the last
    -- 28 days at least, so a 7-day range still has something to go on
    'ideas', case when v_conn and v_site.id is not null then coalesce((select jsonb_agg(jsonb_build_object('query', q.query, 'impressions', q.i, 'position', q.p, 'days', q.days,
                                                                                   'page', q.page, 'planned', q.planned) order by q.planned, q.i desc, q.query)
      from (select s.query, sum(s.impressions) i, greatest(d, 28) days,
                   round(sum(s.position * s.impressions) filter (where s.position is not null) / nullif(sum(s.impressions) filter (where s.position is not null), 0), 1) p,
                   (select p.page from app.search_console_pages p where p.site_id = v_site.id and p.query = s.query and p.day > current_date - greatest(d, 28)
                    group by p.page having sum(p.impressions) > 0 order by sum(p.impressions) desc, p.page limit 1) page,
                   exists (select 1 from app.seo_content_plan cp where cp.site_id = v_site.id and cp.query = s.query) planned
            from app.search_console_daily s
            where s.site_id = v_site.id and s.day > current_date - greatest(d, 28)
              and not exists (select 1 from app.seo_keywords k where k.site_id = v_site.id and k.query = s.query)
            group by s.query
            having sum(s.impressions) >= 3
               and sum(s.position * s.impressions) filter (where s.position is not null) / nullif(sum(s.impressions) filter (where s.position is not null), 0) > 10
            order by sum(s.impressions) desc, s.query limit 6) q), '[]'::jsonb) end,
    -- Technical SEO beyond the crawl (0073): searches two or more of the site's pages split (each with at least a fifth of
    -- the impressions), and landing pages PageSpeed Insights measured slow on mobile
    'cannibal', case when v_conn and v_site.id is not null then coalesce((select jsonb_agg(jsonb_build_object('query', cb.query, 'pages', cb.pages) order by cb.i desc, cb.query) from (
        select x.query, sum(x.i) i, jsonb_agg(jsonb_build_object('page', x.page, 'impressions', x.i) order by x.i desc, x.page) pages
        from (select p.query, p.page, sum(p.impressions) i, sum(sum(p.impressions)) over (partition by p.query) qt
              from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - greatest(d, 28)
              group by 1, 2) x
        where x.qt >= 10 and x.i >= x.qt * 0.2
        group by x.query having count(*) >= 2
        order by 2 desc, 1 limit 5) cb), '[]'::jsonb) end,
    'slow', case when v_site.id is not null then coalesce((select jsonb_agg(jsonb_build_object('path', v.path, 'lcp_ms', v.lcp_ms, 'inp_ms', v.inp_ms, 'field', v.field) order by v.lcp_ms desc)
        from app.page_vitals v where v.site_id = v_site.id and v.strategy = 'mobile' and (v.lcp_ms > 2500 or v.inp_ms > 200)), '[]'::jsonb) end);
end $fn$;

-- ===========================================================================
-- 8. Integrations
-- ===========================================================================
create function public.growth_integrations(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_marketing_reports(); v_product text := nullif(p_product, 'all'); v_sites uuid[] := app.growth_sites(nullif(p_product, 'all'));
begin
  return jsonb_build_object(
    'can_manage', exists (select 1 from app.admins where id = v_me and role = 'owner'),
    'tracker', jsonb_build_object(
      'sites', coalesce((select jsonb_agg(jsonb_build_object('hostname', s.hostname, 'aliases', s.aliases, 'last_seen_at', s.last_seen_at) order by s.hostname)
                         from app.web_sites s where s.id = any (v_sites)), '[]'::jsonb),
      'last_seen_at', (select max(s.last_seen_at) from app.web_sites s where s.id = any (v_sites)),
      'sessions_24h', (select count(*) from app.web_sessions x where x.site_id = any (v_sites) and x.started_at > now() - interval '24 hours')),
    'search_console', (select jsonb_build_object('status', c.status, 'property', sc.property, 'last_import_at', sc.last_import_at, 'last_error', coalesce(sc.last_error, c.config ->> 'last_error'))
                       from app.integration_connections c left join app.search_console_sites sc on sc.site_id = v_sites[1] where c.provider = 'search_console'),
    'pagespeed', jsonb_build_object(
      'status', (select c.status from app.integration_connections c where c.provider = 'pagespeed'),
      'last_error', (select c.config ->> 'last_error' from app.integration_connections c where c.provider = 'pagespeed'),
      'key_stored', exists (select 1 from vault.secrets where name = 'pagespeed_api_key'),
      'last_at', (select max(pv.fetched_at) from app.page_vitals pv where pv.site_id = any (v_sites)),
      'pages', (select count(*) from app.page_vitals pv where pv.site_id = any (v_sites))),
    'crawler', (select jsonb_build_object('last_at', cr.finished_at, 'pages', cr.pages, 'error', cr.error)
                from app.seo_crawls cr where cr.site_id = any (v_sites) order by cr.finished_at desc limit 1),
    'products', coalesce((select jsonb_agg(jsonb_build_object('product', p.key, 'name', p.name, 'last_event_at', (select max(e.received_at) from app.events_in e where e.product = p.key),
                                                               'events_24h', (select count(*) from app.events_in e where e.product = p.key and e.received_at > now() - interval '24 hours'))
                                           order by p.key)
                          from app.products p where app.in_scope(v_product, p.key)), '[]'::jsonb),
    'email', (select jsonb_build_object('status', c.status) from app.integration_connections c where c.provider = 'email'),
    -- every import, newest first: the workers' own lines, the products' events by hour, the tracker's visits by day
    'log', coalesce((select jsonb_agg(l order by (l ->> 'at')::timestamptz desc) from (
        select l from (
          select jsonb_build_object('at', g.at, 'source', g.source, 'rows', g.rows, 'info', g.info, 'state', g.state) l, g.at
          from app.growth_sync_log g where g.site_id is null or g.site_id = any (v_sites)
          union all
          select jsonb_build_object('at', max(e.received_at), 'source', 'product_events', 'rows', count(*),
                                    'info', jsonb_build_object('product', e.product, 'kinds', jsonb_agg(distinct e.kind)),
                                    'state', 'ok'), max(e.received_at)
          from app.events_in e where app.in_scope(v_product, e.product) and e.received_at > now() - interval '14 days'
          group by e.product, date_trunc('hour', e.received_at)
          union all
          select jsonb_build_object('at', max(x.started_at), 'source', 'tracker', 'rows', count(*),
                                    'info', jsonb_build_object('pageviews', sum(x.pageviews), 'day', (x.started_at at time zone 'Europe/Oslo')::date), 'state', 'ok'), max(x.started_at)
          from app.web_sessions x where x.site_id = any (v_sites) and x.started_at > now() - interval '14 days'
          group by (x.started_at at time zone 'Europe/Oslo')::date) u
        order by u.at desc limit 25) z), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- 9. PageSpeed Insights (pagespeed-run): its key, its pages, its readings; nightly
-- ===========================================================================
-- the pages to measure: each application site's most visited landing pages (30 days), then its home page
create function public.worker_pagespeed_targets() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('site_id', s.id, 'hostname', s.hostname, 'paths', (
           select coalesce(jsonb_agg(p.path order by p.n desc, p.path), '[]'::jsonb) from (
             select x.entry_path path, count(*) n from app.web_sessions x
             where x.site_id = s.id and x.started_at > now() - interval '30 days' and x.entry_path is not null and x.entry_path ~ '^/'
             group by 1 union select '/', 0 order by 2 desc, 1 limit 12) p))
         order by s.hostname), '[]'::jsonb)
  from app.web_sites s where s.active and s.product is not null
$fn$;

create function public.worker_pagespeed_result(p_site uuid, p_rows jsonb, p_error text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int := 0;
begin
  if not exists (select 1 from app.web_sites where id = p_site) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 50 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows'; end if;
  if p_error is not null and p_error !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'error'; end if;
  insert into app.page_vitals (site_id, path, strategy, lcp_ms, inp_ms, cls, score, field, fetched_at)
  select p_site, left(x ->> 'path', 300), coalesce(x ->> 'strategy', 'mobile'),
         nullif(x ->> 'lcp_ms', '')::int, nullif(x ->> 'inp_ms', '')::int, nullif(x ->> 'cls', '')::numeric,
         nullif(x ->> 'score', '')::int, coalesce((x ->> 'field')::boolean, false), now()
  from jsonb_array_elements(p_rows) x where x ->> 'path' ~ '^/'
  on conflict (site_id, path, strategy) do update set lcp_ms = excluded.lcp_ms, inp_ms = excluded.inp_ms, cls = excluded.cls,
    score = excluded.score, field = excluded.field, fetched_at = excluded.fetched_at;
  get diagnostics n = row_count;
  -- a refused key turns the connection to «error» with its code; a reading clears it
  update app.integration_connections set status = case when p_error ~ '^(key|http_400|http_403)' and n = 0 then 'error' when n > 0 then 'connected' else status end,
    config = config || jsonb_build_object('last_error', case when n = 0 then p_error end, 'last_run_at', now())
  where provider = 'pagespeed' and status <> 'not_connected';
  insert into app.growth_sync_log (source, site_id, rows, info, state)
  values ('pagespeed', p_site, n, case when p_error is not null then jsonb_build_object('code', p_error) else '{}'::jsonb end,
          case when p_error is not null and n = 0 then 'failed' when p_error is not null then 'warning' else 'ok' end);
  return jsonb_build_object('pages', n);
end $fn$;

-- «Measure now» and the key's card: may this person manage the site's integrations?
create function public.pagespeed_check_ready() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add');
begin
  return jsonb_build_object('me', v_me, 'key_stored', exists (select 1 from vault.secrets where name = 'pagespeed_api_key'));
end $fn$;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'pagespeed_worker_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'pagespeed_worker_secret',
                                'The nightly job''s key to pagespeed-run (0073). Generated; nobody types it.');
  end if;
end $$;

create or replace function public.product_secret(p_name text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
  where s.name = p_name and (p_name ~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$'
                             or p_name in ('brevo_api_key', 'mail_worker_secret', 'mail_events_secret', 'search_console_key', 'search_console_worker_secret',
                                           'seo_crawl_worker_secret', 'pagespeed_api_key', 'pagespeed_worker_secret'))
$fn$;
revoke all on function public.product_secret(text) from public, anon, authenticated;
grant execute on function public.product_secret(text) to service_role;

create function app.pagespeed_tick() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_key text; v_url text := (select functions_url from app.mail_settings);
begin
  -- without a PageSpeed key there is nothing to ask: Google's shared quota refuses keyless calls
  if v_url is null or not exists (select 1 from vault.secrets where name = 'pagespeed_api_key')
     or not exists (select 1 from app.integration_connections where provider = 'pagespeed' and status = 'connected') then
    return jsonb_build_object('called', 0);
  end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'pagespeed_worker_secret';
  perform net.http_post(url := v_url || '/functions/v1/pagespeed-run', body := '{}'::jsonb,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-worker-key', v_key), timeout_milliseconds := 150000);
  return jsonb_build_object('called', 1);
end $fn$;

insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
values ('pagespeed', 'jobs.pagespeed', '37 5 * * *', 'cron', 'app.pagespeed_tick', true)
on conflict (key) do nothing;
select cron.schedule('platform-pagespeed', '37 5 * * *', 'select app.run_job(''pagespeed'')');

-- ===========================================================================
-- 10. PageSpeed Insights' key: an intake number bound to «pagespeed», the owner's like Search Console's (0064)
-- ===========================================================================
alter table app.integration_connections drop constraint if exists integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check check (provider in (
  'slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging', 'search_console', 'ai', 'email',
  'ip_company', 'esign', 'pdf', 'meeting_bot', 'transcription', 'pagespeed'));
insert into app.integration_connections (provider, status) values ('pagespeed', 'not_connected') on conflict (provider) do nothing;
alter table app.intake_nonces drop constraint if exists intake_nonces_purpose_check;
alter table app.intake_nonces add constraint intake_nonces_purpose_check check (purpose is null or purpose in ('brevo', 'search_console', 'pagespeed'));

-- 0065's store_product_secrets, with PageSpeed's branch
CREATE OR REPLACE FUNCTION public.store_product_secrets(p_nonce text, p_secrets jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare k text; v text; n int := 0; v_product text; v_purpose text; v_key jsonb;
begin
  delete from app.intake_nonces where hash = extensions.digest(coalesce(p_nonce, ''), 'sha256') and expires_at > now() returning product, purpose into v_product, v_purpose;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if jsonb_typeof(p_secrets) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  -- the mail provider's key: that one name only, replaced when it exists (the owner rotates it this way)
  if v_purpose = 'brevo' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      if k <> 'brevo_api_key' or btrim(coalesce(v, '')) !~ '^[A-Za-z0-9_-]+$' or char_length(btrim(v)) not between 32 and 300 then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), btrim(v));
      else
        perform vault.create_secret(btrim(v), k, 'The Brevo API key (0060): read by mail-run only.');
      end if;
      n := n + 1;
    end loop;
    if n > 0 then
      update app.integration_connections set status = 'not_connected', config = config || jsonb_build_object('provider', 'brevo', 'key_stored_at', now())
      where provider = 'email';
      update app.mail_settings set last_error = null, last_check_at = null, updated_at = now() where id;
    end if;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  -- a Google service account's JSON key (0064): that one name only; only its address is kept outside Vault
  if v_purpose = 'search_console' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      begin
        v_key := v::jsonb;
      exception when others then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end;
      if k <> 'search_console_key' or char_length(v) > 6000 or jsonb_typeof(v_key) <> 'object' or v_key ->> 'type' is distinct from 'service_account'
         or coalesce(v_key ->> 'client_email', '') !~ '^[a-z0-9._-]{1,100}@[a-z0-9.-]{1,100}\.iam\.gserviceaccount\.com$'
         or coalesce(v_key ->> 'private_key', '') !~ '^-----BEGIN PRIVATE KEY-----' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), v);
      else
        perform vault.create_secret(v, k, 'A Google service account key for Search Console (0064): read by search-console-run only.');
      end if;
      update app.integration_connections set status = 'not_connected',
        config = config || jsonb_build_object('provider', 'google', 'client_email', v_key ->> 'client_email', 'key_stored_at', now(), 'last_error', null)
      where provider = 'search_console';
      n := n + 1;
    end loop;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  -- a Google API key for PageSpeed Insights (0073): that one name only; the integration is on once it is stored
  if v_purpose = 'pagespeed' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      if k <> 'pagespeed_api_key' or btrim(coalesce(v, '')) !~ '^[A-Za-z0-9_-]{30,80}$' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), btrim(v));
      else
        perform vault.create_secret(btrim(v), k, 'A Google API key for PageSpeed Insights (0073): read by pagespeed-run only.');
      end if;
      update app.integration_connections set status = 'connected', connected_at = now(),
        config = config || jsonb_build_object('key_stored_at', now(), 'last_error', null)
      where provider = 'pagespeed';
      n := n + 1;
    end loop;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  for k, v in select key, value from jsonb_each_text(p_secrets) loop
    if k !~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$' or char_length(coalesce(v, '')) < 32 or char_length(v) > 500 then
      raise exception 'store_product_secrets: % is not a product secret', k using errcode = 'invalid_parameter_value';
    end if;
    if v_product is not null then
      if k not in (v_product || '_token_secret', v_product || '_webhook_secret') then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'exists';
      end if;
    end if;
    if exists (select 1 from vault.secrets s where s.name = k) then
      perform vault.update_secret((select s.id from vault.secrets s where s.name = k), v);
    else
      perform vault.create_secret(v, k, 'A product''s shared secret (0002): read by the edge functions only.');
    end if;
    n := n + 1;
  end loop;
  if v_product is not null and exists (select 1 from vault.secrets s where s.name = v_product || '_token_secret')
     and exists (select 1 from vault.secrets s where s.name = v_product || '_webhook_secret') then
    update app.installations set enabled = true, updated_at = now() where product = v_product and not enabled;
  end if;
  return jsonb_build_object('ok', true, 'stored', n);
end $function$;

revoke all on function public.store_product_secrets(text, jsonb) from public, anon, authenticated;
grant execute on function public.store_product_secrets(text, jsonb) to service_role;

create function public.pagespeed_intake() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  perform app.require_fresh_mfa(10);
  insert into app.intake_nonces (hash, expires_at, purpose) values (extensions.digest(v, 'sha256'), now() + interval '15 minutes', 'pagespeed');
  perform app.log('pagespeed.intake_opened', 'integration', 'pagespeed');
  return jsonb_build_object('intake_code', v, 'expires_in', 900);
end $fn$;

-- off: nothing is measured; the key stays in Vault until it is replaced
create function public.pagespeed_disconnect() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner();
begin
  perform app.require_fresh_mfa(10);
  update app.integration_connections set status = 'not_connected', connected_at = null where provider = 'pagespeed';
  perform app.log('pagespeed.disconnected', 'integration', 'pagespeed', '{}'::jsonb);
  return jsonb_build_object('status', 'not_connected');
end $fn$;

-- ===========================================================================
-- grants
-- ===========================================================================
revoke all on function app.pagespeed_tick() from public, anon, authenticated;
revoke all on function app.seo_crawl_logged() from public, anon, authenticated;
revoke all on function app.search_console_logged() from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.growth_scope(text, int, date, int, text, text)', 'public.growth_funnel(text, int, date, int, text, text, int)',
                           'public.growth_pages(text, int, date, int, text, text, text)', 'public.seo_keyword_history(text, text, int)',
                           'public.growth_integrations(text)', 'public.pagespeed_check_ready()', 'public.pagespeed_intake()', 'public.pagespeed_disconnect()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_seo_pages(uuid, jsonb)', 'public.worker_growth_sync(text, uuid, int, jsonb, text)',
                           'public.worker_pagespeed_targets()', 'public.worker_pagespeed_result(uuid, jsonb, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
