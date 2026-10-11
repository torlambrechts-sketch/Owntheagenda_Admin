-- 0074_seo_suite.sql — Growth › SEO, the suite (SeoSuite.dc.html of 11 Oct 2026; docs/crm-enrichment/growth-v2-gap.md,
-- deviations/growth-v2.md V-GR2-23 onwards).
--
-- The design's SEO tab has nine views. Keywords is built (0072, 0073). This adds the other eight's sources:
--   1. Index coverage: Search Console's URL Inspection, read by search-console-run for the crawled pages (seo_index).
--   2. The crawl's link graph: which page links to which, with what anchor, and which searches a page mentions
--      (seo_links, seo_mentions). seo-crawl writes them; Internal links and the brief read them.
--   3. The content plan gets its stages (Idea → Writing → Published → Measuring), a kind, a page and an owner.
--   4. The change log: what was changed on which page, by hand, by the plan or by a link decision (seo_changes).
--   5. Alerts: four rules with a source (a ranking drop, a page out of the index, an organic traffic drop, a failing Core
--      Web Vital), checked every hour, delivered in the app and by email (seo_alert_rules, seo_alerts,
--      seo_alert_deliveries).
--   6. The reads, one per view, and the writes. Values estimated in kroner are computed in lib/growth/seo.ts from the raw
--      figures these return, so the rule is in one place and tested.
--
-- Nothing here is about a person: searches are what Google counted, pages are public addresses, and a change note or an
-- anchor is what staff typed or a page shows publicly.

-- ===========================================================================
-- 1. Index coverage (URL Inspection)
-- ===========================================================================
create table app.seo_index (
  site_id       uuid not null references app.web_sites (id) on delete cascade,
  path          text not null check (path ~ '^/' and char_length(path) <= 300),
  -- Google's coverage state, reduced to the buckets the design draws (lib: coverageKey in _shared/google.ts)
  coverage      text not null check (coverage in ('indexed', 'crawled_not_indexed', 'discovered_not_indexed', 'duplicate', 'noindex',
                                                  'not_found', 'redirect', 'blocked', 'error', 'unknown', 'other')),
  last_crawl_at timestamptz,
  inspected_at  timestamptz not null default now(),
  -- set when a page that was indexed is not any more (the deindex alert); cleared when it is back
  dropped_at    timestamptz,
  primary key (site_id, path)
);
alter table app.seo_index enable row level security;
revoke all on app.seo_index from public, anon, authenticated;

alter table app.growth_sync_log drop constraint growth_sync_log_source_check;
alter table app.growth_sync_log add constraint growth_sync_log_source_check
  check (source in ('search_console', 'pagespeed', 'crawler', 'tracker', 'product_events', 'email', 'url_inspection'));

-- the address the site answers on after its redirects (orgpuls.com → https://www.orgpuls.com): URL Inspection needs it
alter table app.seo_crawls add column origin text check (origin is null or origin ~ '^https?://[a-z0-9.-]+(:\d+)?$');

-- 0064's tick, waiting as long as the run now takes (the import, then URL Inspection: about 140 seconds)
create or replace function app.search_console_tick() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_key text; v_url text := (select functions_url from app.mail_settings);
begin
  if not app.connected('search_console') then return jsonb_build_object('called', 0); end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'search_console_worker_secret';
  perform net.http_post(url := v_url || '/functions/v1/search-console-run', body := '{"kind":"run"}'::jsonb,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-worker-key', v_key), timeout_milliseconds := 150000);
  return jsonb_build_object('called', 1);
end $fn$;

-- the pages to inspect: each mapped site's crawled pages, the longest unchecked first, each at most once in 20 hours
create function public.worker_seo_index_targets() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('site_id', t.site_id, 'property', t.property, 'origin', t.origin, 'paths', t.paths)), '[]'::jsonb)
  from (
    select sc.site_id, sc.property,
           (select cr.origin from app.seo_crawls cr where cr.site_id = sc.site_id and cr.origin is not null order by cr.finished_at desc limit 1) origin,
           (select coalesce(jsonb_agg(x.path), '[]'::jsonb) from (
              select sp.path from app.seo_pages sp
              left join app.seo_index ix on ix.site_id = sp.site_id and ix.path = sp.path
              where sp.site_id = sc.site_id and sp.seen_at > now() - interval '14 days'
                and (ix.inspected_at is null or ix.inspected_at < now() - interval '20 hours')
              order by ix.inspected_at nulls first, sp.path limit 80) x) paths
    from app.search_console_sites sc
    where sc.property is not null and app.connected('search_console')
  ) t
  where t.origin is not null and jsonb_array_length(t.paths) > 0
$fn$;

-- one run's verdicts. A page indexed before and not now has dropped out (dropped_at); back in, that is cleared.
create function public.worker_seo_index_result(p_site uuid, p_rows jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int; v_dropped int;
begin
  if not exists (select 1 from app.web_sites where id = p_site) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) > 500 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  with v as (
    select distinct on (left(x ->> 'path', 300)) left(x ->> 'path', 300) path, x ->> 'coverage' coverage,
           case when (x ->> 'last_crawl_at') ~ '^\d{4}-\d{2}-\d{2}T' then (x ->> 'last_crawl_at')::timestamptz end last_crawl_at
    from jsonb_array_elements(p_rows) x
    where coalesce(x ->> 'path', '') ~ '^/'
      and x ->> 'coverage' in ('indexed', 'crawled_not_indexed', 'discovered_not_indexed', 'duplicate', 'noindex', 'not_found', 'redirect',
                               'blocked', 'error', 'unknown', 'other')
    order by left(x ->> 'path', 300)
  ), up as (
    insert into app.seo_index as ix (site_id, path, coverage, last_crawl_at, inspected_at, dropped_at)
    select p_site, v.path, v.coverage, v.last_crawl_at, now(), null from v
    on conflict (site_id, path) do update set
      coverage = excluded.coverage,
      last_crawl_at = coalesce(excluded.last_crawl_at, ix.last_crawl_at),
      inspected_at = now(),
      dropped_at = case when excluded.coverage = 'indexed' then null when ix.coverage = 'indexed' then now() else ix.dropped_at end
    returning (dropped_at = now()) dropped)
  select count(*), count(*) filter (where dropped) into n, v_dropped from up;
  insert into app.growth_sync_log (source, site_id, rows, info, state)
  values ('url_inspection', p_site, n,
          jsonb_build_object('indexed', (select count(*) from app.seo_index where site_id = p_site and coverage = 'indexed'),
                             'pages', (select count(*) from app.seo_index where site_id = p_site), 'dropped', v_dropped),
          case when v_dropped > 0 then 'warning' else 'ok' end);
  return jsonb_build_object('rows', n, 'dropped', v_dropped);
end $fn$;

-- ===========================================================================
-- 2. The crawl's link graph and the searches a page mentions
-- ===========================================================================
create table app.seo_links (
  site_id   uuid not null references app.web_sites (id) on delete cascade,
  from_path text not null check (from_path ~ '^/' and char_length(from_path) <= 300),
  to_path   text not null check (to_path ~ '^/' and char_length(to_path) <= 300),
  anchor    text check (anchor is null or char_length(anchor) <= 120),
  primary key (site_id, from_path, to_path)
);
alter table app.seo_links enable row level security;
revoke all on app.seo_links from public, anon, authenticated;
create index seo_links_to on app.seo_links (site_id, to_path);

create table app.seo_mentions (
  site_id uuid not null references app.web_sites (id) on delete cascade,
  path    text not null check (path ~ '^/' and char_length(path) <= 300),
  term    text not null check (char_length(term) between 2 and 80),
  primary key (site_id, path, term)
);
alter table app.seo_mentions enable row level security;
revoke all on app.seo_mentions from public, anon, authenticated;

-- the searches the crawler looks for in a page's text: the tracked keywords and the forty seen most in 90 days
create function app.seo_terms(p_site uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(t.term order by t.term), '[]'::jsonb) from (
    select k.query term from app.seo_keywords k where k.site_id = p_site and char_length(k.query) between 2 and 80
    union
    select q.query from (
      select d.query from app.search_console_daily d
      where d.site_id = p_site and d.day > current_date - 90 and char_length(d.query) between 2 and 80
      group by d.query order by sum(d.impressions) desc, d.query limit 40) q
  ) t
$fn$;

-- 0072's list, with each site's terms
create or replace function public.worker_seo_crawl_sites() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('site_id', s.id, 'hostname', s.hostname, 'terms', app.seo_terms(s.id)) order by s.hostname), '[]'::jsonb)
  from app.web_sites s where s.active and s.product is not null
$fn$;

-- a whole crawl's links and mentions, written over the last crawl's (a partial crawl sends none)
create function public.worker_seo_links(p_site uuid, p_origin text, p_links jsonb, p_mentions jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n_links int; n_mentions int;
begin
  if not exists (select 1 from app.web_sites where id = p_site) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_origin is not null and p_origin !~ '^https?://[a-z0-9.-]+(:\d+)?$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'origin';
  end if;
  if jsonb_typeof(p_links) is distinct from 'array' or jsonb_array_length(p_links) > 40000
     or jsonb_typeof(p_mentions) is distinct from 'array' or jsonb_array_length(p_mentions) > 20000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  delete from app.seo_links where site_id = p_site;
  insert into app.seo_links (site_id, from_path, to_path, anchor)
  select distinct on (y.f, y.t) p_site, y.f, y.t, y.a
  from (select left(x ->> 'from', 300) f, left(x ->> 'to', 300) t, nullif(left(btrim(coalesce(x ->> 'anchor', '')), 120), '') a
        from jsonb_array_elements(p_links) x) y
  where y.f ~ '^/' and y.t ~ '^/' and y.f <> y.t
  order by y.f, y.t, y.a nulls last;
  get diagnostics n_links = row_count;
  delete from app.seo_mentions where site_id = p_site;
  insert into app.seo_mentions (site_id, path, term)
  select distinct p_site, left(x ->> 'path', 300), lower(btrim(x ->> 'term'))
  from jsonb_array_elements(p_mentions) x
  where coalesce(x ->> 'path', '') ~ '^/' and char_length(btrim(coalesce(x ->> 'term', ''))) between 2 and 80;
  get diagnostics n_mentions = row_count;
  update app.seo_crawls set origin = p_origin
  where id = (select cr.id from app.seo_crawls cr where cr.site_id = p_site order by cr.finished_at desc limit 1);
  return jsonb_build_object('links', n_links, 'mentions', n_mentions);
end $fn$;

-- ===========================================================================
-- 3. The content plan's stages
-- ===========================================================================
alter table app.seo_content_plan
  add column kind text not null default 'gap' check (kind in ('striking', 'low_ctr', 'gap', 'cannibal', 'decay')),
  add column path text check (path is null or (path ~ '^/' and char_length(path) <= 300)),
  add column stage text not null default 'idea' check (stage in ('idea', 'writing', 'published', 'measuring')),
  add column owner_id uuid references app.admins (id) on delete set null,
  add column published_at timestamptz,
  add column updated_at timestamptz not null default now();
update app.seo_content_plan set owner_id = created_by where owner_id is null and created_by is not null;

-- ===========================================================================
-- 4. The change log and the link decisions
-- ===========================================================================
create table app.seo_changes (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references app.web_sites (id) on delete cascade,
  day        date not null,
  -- the page changed, or for a new page not yet known by its address, the search it was written for
  path       text check (path is null or (path ~ '^/' and char_length(path) <= 300)),
  query      text check (query is null or char_length(query) between 1 and 200),
  kind       text not null check (kind in ('title_meta', 'content', 'links', 'schema', 'speed', 'new_page', 'merge')),
  note       text check (note is null or char_length(note) <= 200),
  source     text not null default 'manual' check (source in ('manual', 'plan', 'link')),
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  check (path is not null or query is not null)
);
alter table app.seo_changes enable row level security;
revoke all on app.seo_changes from public, anon, authenticated;
create index seo_changes_site on app.seo_changes (site_id, day desc);

create table app.seo_link_decisions (
  site_id    uuid not null references app.web_sites (id) on delete cascade,
  from_path  text not null check (from_path ~ '^/' and char_length(from_path) <= 300),
  to_path    text not null check (to_path ~ '^/' and char_length(to_path) <= 300),
  anchor     text check (anchor is null or char_length(anchor) <= 120),
  decision   text not null check (decision in ('added', 'skipped')),
  decided_by uuid references app.admins (id) on delete set null,
  decided_at timestamptz not null default now(),
  primary key (site_id, from_path, to_path)
);
alter table app.seo_link_decisions enable row level security;
revoke all on app.seo_link_decisions from public, anon, authenticated;

-- ===========================================================================
-- 5. Alerts
-- ===========================================================================
-- a rule without a row is on, in the app and by email
create table app.seo_alert_rules (
  site_id    uuid not null references app.web_sites (id) on delete cascade,
  rule       text not null check (rule in ('rank', 'deindex', 'traffic', 'cwv')),
  enabled    boolean not null default true,
  channels   text[] not null default '{app,email}' check (channels <@ array['app', 'email']::text[]),
  updated_by uuid references app.admins (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (site_id, rule)
);
alter table app.seo_alert_rules enable row level security;
revoke all on app.seo_alert_rules from public, anon, authenticated;

create table app.seo_alerts (
  id              uuid primary key default gen_random_uuid(),
  site_id         uuid not null references app.web_sites (id) on delete cascade,
  rule            text not null check (rule in ('rank', 'deindex', 'traffic', 'cwv')),
  -- what it is about (a search, a page, an hour) and the moment, so the same thing is raised once
  subject         text not null check (char_length(subject) between 1 and 300),
  key             text not null check (char_length(key) between 1 and 340),
  params          jsonb not null default '{}'::jsonb check (jsonb_typeof(params) = 'object'),
  at              timestamptz not null default now(),
  acknowledged_at timestamptz,
  acknowledged_by uuid references app.admins (id) on delete set null,
  unique (site_id, rule, key)
);
alter table app.seo_alerts enable row level security;
revoke all on app.seo_alerts from public, anon, authenticated;
create index seo_alerts_site on app.seo_alerts (site_id, at desc);
create index seo_alerts_subject on app.seo_alerts (site_id, rule, subject, at desc);

create table app.seo_alert_deliveries (
  alert_id     uuid not null references app.seo_alerts (id) on delete cascade,
  recipient_id uuid not null references app.admins (id) on delete cascade,
  status       text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  claimed_at   timestamptz,
  sent_at      timestamptz,
  primary key (alert_id, recipient_id)
);
alter table app.seo_alert_deliveries enable row level security;
revoke all on app.seo_alert_deliveries from public, anon, authenticated;

-- an alert's notification opens Growth › SEO › Alerts: a route of one segment with short parameters (never «//host»),
-- beside 0023's record links
alter table app.notifications drop constraint notifications_route_check;
alter table app.notifications add constraint notifications_route_check
  check (route is null or route ~ '^/[a-z0-9/_-]*(\?[a-z_]+=[0-9a-f-]{36})?$'
         or route ~ '^/[a-z0-9_-]+\?[a-z]+=[a-z0-9_-]{1,40}(&[a-z]+=[a-z0-9_-]{1,40}){0,3}$');

-- a site's rule as it stands (the defaults when nobody changed it)
create function app.seo_rule(p_site uuid, p_rule text) returns app.seo_alert_rules
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select r from app.seo_alert_rules r where r.site_id = p_site and r.rule = p_rule),
                  row(p_site, p_rule, true, '{app,email}'::text[], null, now())::app.seo_alert_rules)
$fn$;

-- raise one alert: nothing when the rule is off, or when the same subject was raised within p_quiet. Everybody who may
-- read Growth's reports hears it on the rule's channels. → 1 when raised
create function app.seo_alert_raise(p_site uuid, p_rule text, p_subject text, p_key text, p_params jsonb, p_quiet interval) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.seo_alert_rules := app.seo_rule(p_site, p_rule); v_id uuid; v_mail boolean := app.mail_ready();
begin
  if not r.enabled then return 0; end if;
  if exists (select 1 from app.seo_alerts a where a.site_id = p_site and a.rule = p_rule and a.subject = left(p_subject, 300) and a.at > now() - p_quiet) then
    return 0;
  end if;
  insert into app.seo_alerts (site_id, rule, subject, key, params)
  values (p_site, p_rule, left(p_subject, 300), left(p_key, 340), coalesce(p_params, '{}'::jsonb))
  on conflict (site_id, rule, key) do nothing returning id into v_id;
  if v_id is null then return 0; end if;
  if 'app' = any (r.channels) then
    perform app.notify_once(a.id, 'system', 'seo.alert_' || p_rule, coalesce(p_params, '{}'::jsonb), '/growth?tab=seo&sub=alerts', null, null,
                            'seo_alert:' || v_id || ':' || a.id)
    from app.admins a
    where a.active and not a.is_sample and (app.can_for(a.id, 'global', 'reports_others') or app.can_for(a.id, 'campaigns', 'reports_others'));
  end if;
  if 'email' = any (r.channels) and v_mail then
    insert into app.seo_alert_deliveries (alert_id, recipient_id)
    select v_id, a.id from app.admins a
    where a.active and not a.is_sample and (app.can_for(a.id, 'global', 'reports_others') or app.can_for(a.id, 'campaigns', 'reports_others'))
    on conflict do nothing;
  end if;
  return 1;
end $fn$;

-- the hourly check: four rules over Search Console, the tracker, URL Inspection and PageSpeed Insights
create function app.seo_alerts_tick() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s record; r record; n int := 0; v_h timestamptz; v_now int; v_base numeric; v_weeks int; v_since timestamptz;
begin
  for s in select w.id from app.web_sites w where w.active and w.product is not null loop
    -- a tracked keyword in the top ten that fell three places or more: Search Console's last seven days against the seven
    -- before, each with at least ten impressions. Once a week per keyword.
    for r in
      with l as (select max(d.day) d from app.search_console_daily d where d.site_id = s.id),
      k as (
        select kw.query, l.d,
               sum(d.position * d.impressions) filter (where d.day > l.d - 7 and d.position is not null)
                 / nullif(sum(d.impressions) filter (where d.day > l.d - 7 and d.position is not null), 0) p_now,
               sum(d.position * d.impressions) filter (where d.day <= l.d - 7 and d.position is not null)
                 / nullif(sum(d.impressions) filter (where d.day <= l.d - 7 and d.position is not null), 0) p_prev,
               coalesce(sum(d.impressions) filter (where d.day > l.d - 7), 0) i_now,
               coalesce(sum(d.impressions) filter (where d.day <= l.d - 7), 0) i_prev
        from app.seo_keywords kw cross join l
        join app.search_console_daily d on d.site_id = kw.site_id and d.query = kw.query and d.day > l.d - 14
        where kw.site_id = s.id
        group by kw.query, l.d)
      select * from k where k.p_prev <= 10 and k.p_now >= k.p_prev + 3 and k.i_now >= 10 and k.i_prev >= 10
    loop
      n := n + app.seo_alert_raise(s.id, 'rank', r.query, r.query || '@' || r.d,
                                   jsonb_build_object('query', r.query, 'from', round(r.p_prev, 1), 'to', round(r.p_now, 1)), interval '7 days');
    end loop;

    -- a page that was in Google's index and has dropped out (URL Inspection)
    for r in select ix.path, ix.coverage, ix.dropped_at from app.seo_index ix
             where ix.site_id = s.id and ix.dropped_at is not null and ix.dropped_at > now() - interval '2 days' loop
      n := n + app.seo_alert_raise(s.id, 'deindex', r.path, r.path || '@' || r.dropped_at::date,
                                   jsonb_build_object('path', r.path, 'coverage', r.coverage), interval '7 days');
    end loop;

    -- organic visits in the last full hour at least 30 % below the same hour on the same weekday, averaged over the weeks
    -- the tracker has (up to four), when that hour usually brings five or more
    v_h := date_trunc('hour', now()) - interval '1 hour';
    v_since := (select min(x.started_at) from app.web_sessions x where x.site_id = s.id);
    if v_since is not null then
      select count(*) into v_now from app.web_sessions x
      where x.site_id = s.id and coalesce(x.channel, 'direct') = 'organic_search' and x.started_at >= v_h and x.started_at < v_h + interval '1 hour';
      select count(*) filter (where v_h - g * interval '7 days' >= date_trunc('hour', v_since)),
             avg(c) filter (where v_h - g * interval '7 days' >= date_trunc('hour', v_since))
        into v_weeks, v_base
      from (select g, (select count(*) from app.web_sessions x
                       where x.site_id = s.id and coalesce(x.channel, 'direct') = 'organic_search'
                         and x.started_at >= v_h - g * interval '7 days' and x.started_at < v_h - g * interval '7 days' + interval '1 hour') c
            from generate_series(1, 4) g) w;
      if v_weeks > 0 and v_base >= 5 and v_now <= v_base * 0.7 then
        n := n + app.seo_alert_raise(s.id, 'traffic', 'organic', 'organic@' || to_char(v_h at time zone 'Europe/Oslo', 'YYYY-MM-DD"T"HH24'),
                                     jsonb_build_object('hour', to_char(v_h at time zone 'Europe/Oslo', 'HH24:MI'), 'now', v_now, 'before', round(v_base)),
                                     interval '6 hours');
      end if;
    end if;

    -- a measured page whose mobile LCP is over 2.5 s or INP over 200 ms (PageSpeed Insights measures the top pages)
    for r in select pv.path, pv.lcp_ms, pv.inp_ms from app.page_vitals pv
             where pv.site_id = s.id and pv.strategy = 'mobile' and (pv.lcp_ms > 2500 or pv.inp_ms > 200) loop
      n := n + app.seo_alert_raise(s.id, 'cwv', r.path, r.path || '@' || current_date,
                                   jsonb_build_object('path', r.path, 'metric', case when r.lcp_ms > 2500 then 'lcp' else 'inp' end,
                                                      'value', case when r.lcp_ms > 2500 then round(r.lcp_ms / 1000.0, 1) else r.inp_ms end),
                                   interval '28 days');
    end loop;
  end loop;
  return jsonb_build_object('raised', n);
end $fn$;

insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
values ('seo_alerts', 'jobs.seo_alerts', '23 * * * *', 'cron', 'app.seo_alerts_tick', true)
on conflict (key) do nothing;
select cron.schedule('platform-seo-alerts', '23 * * * *', 'select app.run_job(''seo_alerts'')');

-- the alert emails mail-run sends (0060's pattern for security alerts)
create function public.worker_seo_alert_mail_claim(p_limit int default 50) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; d app.sender_domains := app.mail_sender(); out jsonb := '[]'::jsonb;
begin
  if not app.mail_ready() then return out; end if;
  for r in select x.alert_id, x.recipient_id, al.rule, al.params, al.at, ws.hostname, a.email, coalesce(a.locale, 'en') locale
           from app.seo_alert_deliveries x join app.seo_alerts al on al.id = x.alert_id join app.web_sites ws on ws.id = al.site_id
           join app.admins a on a.id = x.recipient_id
           where x.status = 'queued' and a.active and (x.claimed_at is null or x.claimed_at < now() - interval '10 minutes')
           order by al.at limit least(greatest(coalesce(p_limit, 50), 1), 200) for update of x skip locked loop
    update app.seo_alert_deliveries set claimed_at = now() where alert_id = r.alert_id and recipient_id = r.recipient_id;
    out := out || jsonb_build_array(jsonb_build_object('alert', r.alert_id, 'recipient', r.recipient_id, 'rule', r.rule, 'params', r.params,
      'at', r.at, 'site', r.hostname, 'to', r.email, 'locale', r.locale, 'from', d.from_local || '@' || d.domain, 'from_name', d.from_name));
  end loop;
  return out;
end $fn$;

create function public.worker_seo_alert_mail_done(p_alert uuid, p_recipient uuid, p_ok boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.seo_alert_deliveries set status = case when p_ok then 'sent' else 'failed' end, sent_at = case when p_ok then now() end, claimed_at = null
  where alert_id = p_alert and recipient_id = p_recipient and status = 'queued';
  return jsonb_build_object('ok', found);
end $fn$;

-- ===========================================================================
-- 6. Reads
-- ===========================================================================
-- the economics an opportunity is priced with: clicks to signups (the tracker's organic visits that finished signup since
-- it started, at most 90 days), accounts to paying (the last 365 days), and the average revenue per paying account now
create function app.seo_econ(p_product text, p_site uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  with t as (
    select (select min(x.day) from app.web_sessions x where x.site_id = any (app.growth_sites(p_product))) t0
  ), since as (
    -- without the tracker there is no signup rate; with it, the window starts when it did (at most 90 days back)
    select t.t0, greatest(current_date - 90, t.t0) d from t
  ), m as (
    select sum(md.mrr) mrr, sum(md.paying) paying from app.mrr_daily md
    where md.day = (select max(day) from app.mrr_daily) and app.in_scope(p_product, md.product)
  )
  select jsonb_build_object(
    'since', case when since.t0 is not null then since.d end,
    'clicks', case when since.t0 is not null then (select sum(t.clicks) from app.search_console_totals t where t.site_id = p_site and t.day >= since.d) end,
    'signups', case when since.t0 is not null then (select count(*) from app.web_sessions x
                     where x.site_id = any (app.growth_sites(p_product)) and x.day >= since.d and coalesce(x.channel, 'direct') = 'organic_search'
                       and exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_completed')) end,
    'accounts', (select count(*) from app.account_products ap where app.in_scope(p_product, ap.product) and ap.created_at > now() - interval '365 days'),
    'paying', (select count(*) from app.account_products ap where app.in_scope(p_product, ap.product) and ap.created_at > now() - interval '365 days'
                 and exists (select 1 from app.subscriptions sb where sb.product = ap.product and sb.tenant_id = ap.tenant_id and sb.confirmed_at is not null)),
    'mrr', m.mrr, 'paying_now', m.paying)
  from since, m
$fn$;

-- the account's attribution names a source (first touch, utm or referrer); Orgpuls reports only how a person heard of it
create function app.has_source(p_attribution jsonb) returns boolean
  language sql immutable set search_path = ''
as $fn$ select coalesce(p_attribution ? 'first_touch' or p_attribution ?| array['utm_source', 'utm_medium', 'referrer'], false) $fn$;

-- SEO overview: the KPIs, index coverage and the facts behind the figures
create function public.seo_overview(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product);
  v_conn boolean := app.connected('search_console');
  sc app.search_console_sites;
  v_sites uuid[] := app.growth_sites(v_product);
  v_since date;
  v_attr boolean;
begin
  select * into sc from app.search_console_sites where site_id = v_site.id;
  v_since := (select min(x.day) from app.web_sessions x where x.site_id = any (v_sites));
  v_attr := exists (select 1 from app.account_products ap where app.in_scope(v_product, ap.product) and app.has_source(ap.attribution));
  return jsonb_build_object(
    'connected', v_conn and sc.property is not null,
    'site', case when v_site.id is not null then jsonb_build_object('id', v_site.id, 'hostname', v_site.hostname) end,
    'last_import_at', sc.last_import_at, 'last_day', sc.last_day,
    'tracked_since', v_since,
    'clicks', case when v_conn and sc.property is not null then (select jsonb_build_object(
        'now', sum(t.clicks) filter (where t.day > current_date - 30),
        'prev', sum(t.clicks) filter (where t.day <= current_date - 30),
        -- the share Search Console names a search for: the rest are rare searches it leaves out
        'named', (select sum(d.clicks) from app.search_console_daily d where d.site_id = v_site.id and d.day > current_date - 30))
      from app.search_console_totals t where t.site_id = v_site.id and t.day > current_date - 60) end,
    'signups', jsonb_build_object(
      'now', case when v_since is not null then (select count(*) from app.web_sessions x
               where x.site_id = any (v_sites) and x.day > current_date - 30 and coalesce(x.channel, 'direct') = 'organic_search'
                 and exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_completed')) end,
      'prev', case when v_since is not null and v_since <= current_date - 59 then (select count(*) from app.web_sessions x
               where x.site_id = any (v_sites) and x.day > current_date - 60 and x.day <= current_date - 30 and coalesce(x.channel, 'direct') = 'organic_search'
                 and exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_completed')) end),
    'attributed', v_attr,
    'mrr_won', case when v_attr then jsonb_build_object(
      'now', (select coalesce(sum(app.sub_mrr(sb)), 0) from app.subscriptions sb
              join app.account_products ap on ap.product = sb.product and ap.tenant_id = sb.tenant_id
              where app.in_scope(v_product, sb.product) and sb.confirmed_at > now() - interval '30 days' and app.account_channel(ap.attribution) = 'organic_search'),
      'prev', (select coalesce(sum(app.sub_mrr(sb)), 0) from app.subscriptions sb
               join app.account_products ap on ap.product = sb.product and ap.tenant_id = sb.tenant_id
               where app.in_scope(v_product, sb.product) and sb.confirmed_at > now() - interval '60 days' and sb.confirmed_at <= now() - interval '30 days'
                 and app.account_channel(ap.attribution) = 'organic_search')) end,
    -- the tracked keywords' last 30 days and the 30 before: visibility is computed from these (lib/growth/seo.ts)
    'keywords', case when v_conn and sc.property is not null then coalesce((select jsonb_agg(jsonb_build_object('query', k.query,
        'impressions', x.i, 'position', x.p, 'impressions_prev', x.ip, 'position_prev', x.pp) order by k.query)
      from app.seo_keywords k
      left join lateral (
        select sum(d.impressions) filter (where d.day > current_date - 30) i, sum(d.impressions) filter (where d.day <= current_date - 30) ip,
               sum(d.position * d.impressions) filter (where d.day > current_date - 30 and d.position is not null)
                 / nullif(sum(d.impressions) filter (where d.day > current_date - 30 and d.position is not null), 0) p,
               sum(d.position * d.impressions) filter (where d.day <= current_date - 30 and d.position is not null)
                 / nullif(sum(d.impressions) filter (where d.day <= current_date - 30 and d.position is not null), 0) pp
        from app.search_console_daily d where d.site_id = k.site_id and d.query = k.query and d.day > current_date - 60) x on true
      where k.site_id = v_site.id), '[]'::jsonb) end,
    'index', case when v_site.id is not null then jsonb_build_object(
      'pages', (select count(*) from app.seo_index ix where ix.site_id = v_site.id),
      'indexed', (select count(*) from app.seo_index ix where ix.site_id = v_site.id and ix.coverage = 'indexed'),
      'dropped', (select count(*) from app.seo_index ix where ix.site_id = v_site.id and ix.dropped_at > now() - interval '7 days'),
      'last_at', (select max(ix.inspected_at) from app.seo_index ix where ix.site_id = v_site.id),
      'crawled', (select count(*) from app.seo_pages sp where sp.site_id = v_site.id and sp.seen_at > now() - interval '14 days'),
      'buckets', coalesce((select jsonb_agg(jsonb_build_object('coverage', b.coverage, 'count', b.n) order by b.n desc, b.coverage)
                           from (select ix.coverage, count(*) n from app.seo_index ix where ix.site_id = v_site.id group by 1) b), '[]'::jsonb)) end);
end $fn$;

-- Opportunities: the raw rows each kind is found in; lib/growth/seo.ts types and prices them
create function public.seo_opportunities(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product);
  v_ok boolean := app.connected('search_console') and exists (select 1 from app.search_console_sites sc where sc.site_id = v_site.id and sc.property is not null);
begin
  return jsonb_build_object(
    'connected', v_ok,
    'econ', case when v_site.id is not null then app.seo_econ(v_product, v_site.id) end,
    -- every search of the last 28 days with five impressions or more (the 300 seen most): striking distance, low click
    -- rate and content gaps are read from these
    'queries', case when v_ok then coalesce((select jsonb_agg(jsonb_build_object('query', q.query, 'impressions', q.i, 'clicks', q.c, 'position', q.p,
                                                                                 'page', q.page, 'tracked', q.tracked) order by q.i desc, q.query) from (
        select d.query, sum(d.impressions) i, sum(d.clicks) c,
               round(sum(d.position * d.impressions) filter (where d.position is not null) / nullif(sum(d.impressions) filter (where d.position is not null), 0), 1) p,
               (select p.page from app.search_console_pages p where p.site_id = v_site.id and p.query = d.query and p.day > current_date - 28
                group by p.page having sum(p.impressions) > 0 order by sum(p.impressions) desc, p.page limit 1) page,
               exists (select 1 from app.seo_keywords k where k.site_id = v_site.id and k.query = d.query) tracked
        from app.search_console_daily d where d.site_id = v_site.id and d.day > current_date - 28
        group by d.query having sum(d.impressions) >= 5
        order by sum(d.impressions) desc, d.query limit 300) q), '[]'::jsonb) end,
    -- searches split over two or more pages, each with at least a fifth of the impressions (0073's rule), last 28 days
    'cannibal', case when v_ok then coalesce((select jsonb_agg(jsonb_build_object('query', cb.query, 'impressions', cb.i, 'clicks', cb.c, 'position', cb.pos,
                                                                                  'pages', cb.pages) order by cb.i desc, cb.query) from (
        select x.query, sum(x.i) i, sum(x.c) c,
               round(sum(x.pw) / nullif(sum(x.iw), 0), 1) pos,
               jsonb_agg(jsonb_build_object('page', x.page, 'impressions', x.i, 'clicks', x.c) order by x.i desc, x.page) pages
        from (select p.query, p.page, sum(p.impressions) i, sum(p.clicks) c,
                     sum(p.position * p.impressions) filter (where p.position is not null) pw, sum(p.impressions) filter (where p.position is not null) iw,
                     sum(sum(p.impressions)) over (partition by p.query) qt
              from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - 28
              group by 1, 2) x
        where x.qt >= 10 and x.i >= x.qt * 0.2
        group by x.query having count(*) >= 2
        order by 2 desc, 1 limit 10) cb), '[]'::jsonb) end,
    -- pages whose clicks over the last 28 days fell by a quarter or more against the same 28 days three months before
    'decay', case when v_ok then coalesce((select jsonb_agg(jsonb_build_object('path', dc.page, 'clicks', dc.c_now, 'clicks_before', dc.c_before,
                                                                               'impressions', dc.i_now, 'query', dc.top_query) order by dc.c_before - dc.c_now desc, dc.page) from (
      select * from (
        select p.page,
               coalesce(sum(p.clicks) filter (where p.day > current_date - 28), 0) c_now,
               coalesce(sum(p.clicks) filter (where p.day > current_date - 119 and p.day <= current_date - 91), 0) c_before,
               coalesce(sum(p.impressions) filter (where p.day > current_date - 28), 0) i_now,
               (select p2.query from app.search_console_pages p2 where p2.site_id = v_site.id and p2.page = p.page and p2.day > current_date - 119
                group by p2.query order by sum(p2.clicks) desc, sum(p2.impressions) desc, p2.query limit 1) top_query
        from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - 119
        group by p.page) dc0
      where dc0.c_before >= 10 and dc0.c_now <= dc0.c_before * 0.75
      order by dc0.c_before - dc0.c_now desc, dc0.page limit 10) dc), '[]'::jsonb) end,
    'planned', coalesce((select jsonb_agg(jsonb_build_object('query', cp.query, 'stage', cp.stage)) from app.seo_content_plan cp where cp.site_id = v_site.id), '[]'::jsonb));
end $fn$;

-- Topic clusters: the tracked keywords grouped by the page Google shows most for each over 90 days, with their weekly
-- impressions and positions over twelve weeks, the pages that rank for them and what the plan holds for them
create function public.seo_clusters(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product);
  v_ok boolean := app.connected('search_console') and exists (select 1 from app.search_console_sites sc where sc.site_id = v_site.id and sc.property is not null);
begin
  if not v_ok then return jsonb_build_object('connected', false, 'clusters', '[]'::jsonb, 'unclustered', 0); end if;
  return (
    with main as (
      select distinct on (p.query) p.query, p.page
      from app.search_console_pages p join app.seo_keywords k on k.site_id = p.site_id and k.query = p.query
      where p.site_id = v_site.id and p.day > current_date - 90
      group by p.query, p.page having sum(p.impressions) > 0
      order by p.query, sum(p.impressions) desc, p.page
    ), cl as (
      select m.page main, array_agg(m.query order by m.query) queries from main m group by m.page
    ), clp as (
      -- each cluster's pages: every page with impressions for its keywords over 90 days
      select cl.main, p.page, sum(p.clicks) c, sum(p.impressions) i,
             round(sum(p.position * p.impressions) filter (where p.position is not null) / nullif(sum(p.impressions) filter (where p.position is not null), 0), 1) pos
      from cl join app.search_console_pages p on p.site_id = v_site.id and p.query = any (cl.queries) and p.day > current_date - 90
      group by cl.main, p.page having sum(p.impressions) > 0
    )
    select jsonb_build_object(
      'connected', true,
      'unclustered', (select count(*) from app.seo_keywords k where k.site_id = v_site.id and not exists (select 1 from main where main.query = k.query)),
      'clusters', coalesce(jsonb_agg(jsonb_build_object(
        'main', cl.main,
        'title', (select sp.title from app.seo_pages sp where sp.site_id = v_site.id and sp.path = cl.main),
        'clicks', (select coalesce(sum(clp.c), 0) from clp where clp.main = cl.main),
        'keywords', (select jsonb_agg(jsonb_build_object('query', q.query, 'weeks', q.weeks, 'position', q.pos) order by q.query) from (
            select kq query,
                   (select jsonb_agg(jsonb_build_object('impressions', coalesce(w.i, 0), 'clicks', coalesce(w.c, 0), 'position', round(w.p, 2)) order by g.g)
                    from generate_series(0, 11) g(g)
                    left join lateral (
                      select sum(d.impressions) i, sum(d.clicks) c,
                             sum(d.position * d.impressions) filter (where d.position is not null) / nullif(sum(d.impressions) filter (where d.position is not null), 0) p
                      from app.search_console_daily d
                      where d.site_id = v_site.id and d.query = kq and d.day > current_date - 84 + 7 * g.g and d.day <= current_date - 77 + 7 * g.g) w on true) weeks,
                   (select round(sum(d.position * d.impressions) filter (where d.position is not null) / nullif(sum(d.impressions) filter (where d.position is not null), 0), 1)
                    from app.search_console_daily d where d.site_id = v_site.id and d.query = kq and d.day > current_date - 28) pos
            from unnest(cl.queries) kq) q),
        'pages', (select jsonb_agg(jsonb_build_object('path', x.page, 'title', (select sp.title from app.seo_pages sp where sp.site_id = v_site.id and sp.path = x.page),
                                                      'clicks', x.c, 'impressions', x.i, 'position', x.pos) order by x.page = cl.main desc, x.c desc, x.i desc, x.page)
                  from (select * from clp where clp.main = cl.main order by clp.page = cl.main desc, clp.c desc, clp.i desc limit 8) x),
        'plan', (select coalesce(jsonb_agg(jsonb_build_object('id', cp.id, 'query', cp.query, 'stage', cp.stage, 'path', cp.path) order by cp.created_at), '[]'::jsonb)
                 from app.seo_content_plan cp where cp.site_id = v_site.id
                   and (cp.query = any (cl.queries) or cp.path in (select clp.page from clp where clp.main = cl.main))))
        order by (select coalesce(sum(clp.c), 0) from clp where clp.main = cl.main) desc, cl.main), '[]'::jsonb))
    from (select * from cl order by (select coalesce(sum(clp.c), 0) from clp where clp.main = cl.main) desc, cl.main limit 12) cl);
end $fn$;

-- Content plan: the items with their owners and, 28 days after publishing (as far as Search Console has reported), what
-- changed for the page or the search; with p_item, the brief: related searches and questions from Search Console's own
-- queries, and the pages that mention the search without linking to the item's page
create function public.seo_plan_get(p_product text default null, p_item uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product);
  v_last date := (select sc.last_day from app.search_console_sites sc where sc.site_id = v_site.id);
  it app.seo_content_plan;
  v_tokens text[];
begin
  select * into it from app.seo_content_plan cp where cp.id = p_item and cp.site_id = v_site.id;
  v_tokens := case when it.id is not null then
    (select array_agg(distinct tk) from regexp_split_to_table(it.query, '\s+') tk where char_length(tk) >= 4) end;
  return jsonb_build_object(
    'last_day', v_last,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', cp.id, 'query', cp.query, 'kind', cp.kind, 'path', cp.path, 'stage', cp.stage,
        'owner', (select coalesce(a.name, a.email) from app.admins a where a.id = coalesce(cp.owner_id, cp.created_by)),
        'created_at', cp.created_at, 'published_at', cp.published_at,
        'measure_on', case when cp.published_at is not null and cp.stage in ('published', 'measuring') then (cp.published_at at time zone 'Europe/Oslo')::date + 28 end,
        'measured', case when cp.published_at is not null and cp.stage in ('published', 'measuring') and v_last is not null and v_last >= (cp.published_at at time zone 'Europe/Oslo')::date + 28 then (
          select jsonb_build_object(
            'clicks_before', coalesce(sum(m.c) filter (where m.after = false), 0), 'clicks_after', coalesce(sum(m.c) filter (where m.after), 0),
            'position_before', round(sum(m.pw) filter (where m.after = false) / nullif(sum(m.iw) filter (where m.after = false), 0), 1),
            'position_after', round(sum(m.pw) filter (where m.after) / nullif(sum(m.iw) filter (where m.after), 0), 1))
          from (
            select p.day >= (cp.published_at at time zone 'Europe/Oslo')::date after, p.clicks c,
                   case when p.position is not null then p.position * p.impressions end pw, case when p.position is not null then p.impressions end iw
            from app.search_console_pages p
            where cp.path is not null and p.site_id = cp.site_id and p.page = cp.path
              and p.day >= (cp.published_at at time zone 'Europe/Oslo')::date - 28 and p.day < (cp.published_at at time zone 'Europe/Oslo')::date + 28
            union all
            select d.day >= (cp.published_at at time zone 'Europe/Oslo')::date, d.clicks,
                   case when d.position is not null then d.position * d.impressions end, case when d.position is not null then d.impressions end
            from app.search_console_daily d
            where cp.path is null and d.site_id = cp.site_id and d.query = cp.query
              and d.day >= (cp.published_at at time zone 'Europe/Oslo')::date - 28 and d.day < (cp.published_at at time zone 'Europe/Oslo')::date + 28) m) end)
      order by cp.updated_at desc, cp.created_at desc)
      from app.seo_content_plan cp where cp.site_id = v_site.id), '[]'::jsonb),
    'brief', case when it.id is not null then jsonb_build_object(
      'id', it.id,
      -- searches Search Console saw in 90 days that share a word of four letters or more with the item's search
      'terms', coalesce((select jsonb_agg(r.query order by r.i desc, r.query) from (
          select d.query, sum(d.impressions) i from app.search_console_daily d
          where d.site_id = v_site.id and d.day > current_date - 90 and d.query <> it.query
            and d.query !~ '^(hva|hvordan|hvorfor|hvor|når|hvem|kan|er|skal|må|bør|what|how|why|when|where|who|can|is|does|do|should)\s'
            and exists (select 1 from unnest(v_tokens) tk where position(' ' || tk || ' ' in ' ' || d.query || ' ') > 0)
          group by d.query order by 2 desc, 1 limit 8) r), '[]'::jsonb),
      -- the questions among them: what people ask that the page should answer
      'questions', coalesce((select jsonb_agg(r.query order by r.i desc, r.query) from (
          select d.query, sum(d.impressions) i from app.search_console_daily d
          where d.site_id = v_site.id and d.day > current_date - 90
            and d.query ~ '^(hva|hvordan|hvorfor|hvor|når|hvem|kan|er|skal|må|bør|what|how|why|when|where|who|can|is|does|do|should)\s'
            and exists (select 1 from unnest(v_tokens) tk where position(' ' || tk || ' ' in ' ' || d.query || ' ') > 0)
          group by d.query order by 2 desc, 1 limit 6) r), '[]'::jsonb),
      -- pages that mention the search and do not link to the item's page yet
      'links', case when it.path is not null then coalesce((select jsonb_agg(jsonb_build_object('from', m.path, 'anchor', m.term) order by m.path) from (
          select distinct on (mn.path) mn.path, mn.term from app.seo_mentions mn
          where mn.site_id = v_site.id and mn.path <> it.path and (mn.term = it.query or mn.term = any (v_tokens))
            and not exists (select 1 from app.seo_links l where l.site_id = v_site.id and l.from_path = mn.path and l.to_path = it.path)
          order by mn.path, mn.term = it.query desc, mn.term limit 5) m), '[]'::jsonb) else '[]'::jsonb end) end);
end $fn$;

-- Internal links: suggestions (a page mentions a search whose main page it does not link to), orphan pages and the pages
-- linked most, from the last whole crawl
create function public.seo_links_get(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product);
  v_sites uuid[] := app.growth_sites(nullif(p_product, 'all'));
begin
  return jsonb_build_object(
    'crawled_at', (select max(cr.finished_at) from app.seo_crawls cr where cr.site_id = v_site.id and cr.origin is not null),
    'links', (select count(*) from app.seo_links l where l.site_id = v_site.id),
    'suggestions', coalesce((select jsonb_agg(jsonb_build_object('from', s.from_path, 'anchor', s.term, 'to', s.to_path, 'decision', s.decision) order by s.decision nulls first, s.i desc, s.from_path) from (
        with main as (
          select distinct on (p.query) p.query term, p.page, sum(p.impressions) i
          from app.search_console_pages p
          where p.site_id = v_site.id and p.day > current_date - 90
          group by p.query, p.page having sum(p.impressions) > 0
          order by p.query, sum(p.impressions) desc, p.page
        )
        select * from (
          select distinct on (mn.path, main.page) mn.path from_path, mn.term, main.page to_path, main.i, dc.decision
          from app.seo_mentions mn join main on main.term = mn.term
          left join app.seo_link_decisions dc on dc.site_id = mn.site_id and dc.from_path = mn.path and dc.to_path = main.page
          where mn.site_id = v_site.id and mn.path <> main.page
            and exists (select 1 from app.seo_pages sp where sp.site_id = v_site.id and sp.path = main.page)
            and not exists (select 1 from app.seo_links l where l.site_id = v_site.id and l.from_path = mn.path and l.to_path = main.page)
          order by mn.path, main.page, main.i desc) s0
        order by s0.i desc, s0.from_path, s0.to_path limit 40) s), '[]'::jsonb),
    'orphans', coalesce((select jsonb_agg(jsonb_build_object('path', o.path, 'visits', o.visits) order by o.visits desc, o.path) from (
        select sp.path,
               (select count(*) from app.web_pageviews pv join app.web_sessions x on x.id = pv.session_id
                where x.site_id = any (v_sites) and x.started_at > now() - interval '30 days' and pv.path = sp.path) visits
        from app.seo_pages sp
        where sp.site_id = v_site.id and sp.seen_at > now() - interval '14 days' and sp.status between 200 and 299 and sp.path <> '/'
          and exists (select 1 from app.seo_links l0 where l0.site_id = v_site.id)
          and not exists (select 1 from app.seo_links l where l.site_id = v_site.id and l.to_path = sp.path and l.from_path <> sp.path)
        limit 12) o), '[]'::jsonb),
    'hubs', coalesce((select jsonb_agg(jsonb_build_object('path', h.to_path, 'inlinks', h.n, 'anchor', h.anchor) order by h.n desc, h.to_path) from (
        select l.to_path, count(distinct l.from_path) n,
               (select l2.anchor from app.seo_links l2 where l2.site_id = v_site.id and l2.to_path = l.to_path and l2.anchor is not null
                group by l2.anchor order by count(*) desc, l2.anchor limit 1) anchor
        from app.seo_links l where l.site_id = v_site.id
        group by l.to_path order by 2 desc, 1 limit 8) h), '[]'::jsonb));
end $fn$;

-- Change log: each change with Search Console's 28 days before and after (once they are reported), the site's organic
-- clicks per day over 60 days, and the crawled pages to pick from
create function public.seo_changes_get(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product);
  v_last date := (select sc.last_day from app.search_console_sites sc where sc.site_id = v_site.id);
begin
  return jsonb_build_object(
    'last_day', v_last,
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', t.day, 'clicks', t.clicks) order by t.day)
                       from app.search_console_totals t where t.site_id = v_site.id and t.day > current_date - 60), '[]'::jsonb),
    'pages', coalesce((select jsonb_agg(sp.path order by sp.path <> '/', sp.path) from app.seo_pages sp
                       where sp.site_id = v_site.id and sp.seen_at > now() - interval '14 days' and sp.status between 200 and 299), '[]'::jsonb),
    'changes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'day', c.day, 'path', c.path, 'query', c.query, 'kind', c.kind, 'note', c.note, 'source', c.source,
        'by', (select coalesce(a.name, a.email) from app.admins a where a.id = c.created_by),
        'ready', v_last is not null and v_last >= c.day + 28,
        'before', m.b, 'after', m.a) order by c.day desc, c.created_at desc)
      from (select * from app.seo_changes c0 where c0.site_id = v_site.id order by c0.day desc, c0.created_at desc limit 50) c
      left join lateral (
        select jsonb_build_object('clicks', coalesce(sum(r.c) filter (where not r.after), 0), 'impressions', coalesce(sum(r.i) filter (where not r.after), 0),
                                  'position', round(sum(r.pw) filter (where not r.after) / nullif(sum(r.iw) filter (where not r.after), 0), 1),
                                  'days', count(distinct r.day) filter (where not r.after)) b,
               jsonb_build_object('clicks', coalesce(sum(r.c) filter (where r.after), 0), 'impressions', coalesce(sum(r.i) filter (where r.after), 0),
                                  'position', round(sum(r.pw) filter (where r.after) / nullif(sum(r.iw) filter (where r.after), 0), 1),
                                  'days', count(distinct r.day) filter (where r.after)) a
        from (
          select p.day, p.day >= c.day after, p.clicks c, p.impressions i,
                 case when p.position is not null then p.position * p.impressions end pw, case when p.position is not null then p.impressions end iw
          from app.search_console_pages p
          where c.path is not null and p.site_id = c.site_id and p.page = c.path and p.day >= c.day - 28 and p.day < c.day + 28
          union all
          select d.day, d.day >= c.day, d.clicks, d.impressions,
                 case when d.position is not null then d.position * d.impressions end, case when d.position is not null then d.impressions end
          from app.search_console_daily d
          where c.path is null and d.site_id = c.site_id and d.query = c.query and d.day >= c.day - 28 and d.day < c.day + 28) r) m on true), '[]'::jsonb));
end $fn$;

-- Alerts: the four rules as they stand, whether email can go out, and the newest 30 alerts
create function public.seo_alerts_get(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_site app.web_sites := app.product_site(nullif(p_product, 'all'));
begin
  return jsonb_build_object(
    'mail_ready', app.mail_ready(),
    'rules', case when v_site.id is not null then (select jsonb_agg(jsonb_build_object('rule', r.rule, 'enabled', r.enabled, 'channels', to_jsonb(r.channels)) order by g.o)
                                                  from unnest(array['rank', 'deindex', 'traffic', 'cwv']) with ordinality g(rule, o)
                                                  cross join lateral app.seo_rule(v_site.id, g.rule) r) else '[]'::jsonb end,
    'open', (select count(*) from app.seo_alerts a where a.site_id = v_site.id and a.acknowledged_at is null),
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'rule', a.rule, 'params', a.params, 'at', a.at, 'acknowledged_at', a.acknowledged_at) order by a.at desc)
                         from (select * from app.seo_alerts a0 where a0.site_id = v_site.id order by a0.at desc limit 30) a), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- 7. Writes
-- ===========================================================================
-- «Do it» and «Plan»: a search into the content plan, with what kind of work it is and the page it concerns
create function public.seo_plan_add(p_product text, p_query text, p_kind text, p_path text default null) returns jsonb
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
  if p_kind is null or p_kind not in ('striking', 'low_ctr', 'gap', 'cannibal', 'decay') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end if;
  if p_path is not null and (p_path !~ '^/' or char_length(p_path) > 300) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path'; end if;
  insert into app.seo_content_plan (site_id, query, kind, path, created_by, owner_id) values (v_site.id, v_q, p_kind, p_path, v_me, v_me)
  on conflict (site_id, query) do nothing returning id into v_id;
  if v_id is not null then perform app.log('seo.article_planned', 'web_site', v_site.id::text, jsonb_build_object('query', v_q, 'kind', p_kind)); end if;
  return jsonb_build_object('planned', true, 'id', coalesce(v_id, (select cp.id from app.seo_content_plan cp where cp.site_id = v_site.id and cp.query = v_q)));
end $fn$;

-- ← and →: an item to another stage. Reaching «Published» the first time logs the change and sets the date it is measured
-- from; going back and forward again keeps that date and logs nothing more.
create function public.seo_plan_move(p_id uuid, p_stage text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); it app.seo_content_plan; v_logged boolean := false;
begin
  if p_stage is null or p_stage not in ('idea', 'writing', 'published', 'measuring') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage';
  end if;
  select * into it from app.seo_content_plan where id = p_id for update;
  if it.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.seo_content_plan
     set stage = p_stage, updated_at = now(),
         -- the first publishing date stays when a card goes back, so going forward again logs nothing twice
         published_at = case when p_stage in ('published', 'measuring') then coalesce(published_at, now()) else published_at end
   where id = p_id;
  if p_stage in ('published', 'measuring') and it.published_at is null then
    insert into app.seo_changes (site_id, day, path, query, kind, note, source, created_by)
    values (it.site_id, (now() at time zone 'Europe/Oslo')::date, it.path, case when it.path is null then it.query end,
            case it.kind when 'gap' then 'new_page' when 'cannibal' then 'merge' when 'low_ctr' then 'title_meta' else 'content' end,
            left(it.query, 200), 'plan', v_me);
    v_logged := true;
  end if;
  perform app.log('seo.plan_moved', 'web_site', it.site_id::text, jsonb_build_object('stage', p_stage));
  return jsonb_build_object('stage', p_stage, 'logged', v_logged);
end $fn$;

-- «Log change»: a page, a kind of change and a note, today
create function public.seo_change_add(p_product text, p_path text, p_kind text, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'add');
  v_site app.web_sites := app.product_site(p_product);
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_id uuid;
begin
  if v_site.id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site'; end if;
  if p_path is null or p_path !~ '^/' or char_length(p_path) > 300 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path'; end if;
  if p_kind is null or p_kind not in ('title_meta', 'content', 'links', 'schema', 'speed', 'new_page', 'merge') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end if;
  if char_length(v_note) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'note'; end if;
  insert into app.seo_changes (site_id, day, path, kind, note, source, created_by)
  values (v_site.id, (now() at time zone 'Europe/Oslo')::date, p_path, p_kind, v_note, 'manual', v_me) returning id into v_id;
  perform app.log('seo.change_logged', 'web_site', v_site.id::text, jsonb_build_object('kind', p_kind));
  return jsonb_build_object('id', v_id);
end $fn$;

-- «Add link» or «Skip» on a suggestion; adding logs the change on the page the link goes on. Sentral does not edit the
-- website: the next crawl sees the link, and the suggestion is gone.
create function public.seo_link_decide(p_product text, p_from text, p_to text, p_anchor text, p_decision text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'add');
  v_site app.web_sites := app.product_site(p_product);
  v_anchor text := nullif(left(btrim(coalesce(p_anchor, '')), 120), '');
  v_was text;
begin
  if v_site.id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site'; end if;
  if p_from is null or p_from !~ '^/' or char_length(p_from) > 300 or p_to is null or p_to !~ '^/' or char_length(p_to) > 300 or p_from = p_to then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path';
  end if;
  if p_decision is null or p_decision not in ('added', 'skipped') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'decision'; end if;
  select decision into v_was from app.seo_link_decisions where site_id = v_site.id and from_path = p_from and to_path = p_to;
  insert into app.seo_link_decisions (site_id, from_path, to_path, anchor, decision, decided_by)
  values (v_site.id, p_from, p_to, v_anchor, p_decision, v_me)
  on conflict (site_id, from_path, to_path) do update set anchor = excluded.anchor, decision = excluded.decision, decided_by = excluded.decided_by, decided_at = now();
  if p_decision = 'added' and v_was is distinct from 'added' then
    insert into app.seo_changes (site_id, day, path, kind, note, source, created_by)
    values (v_site.id, (now() at time zone 'Europe/Oslo')::date, p_from, 'links', left(coalesce('«' || v_anchor || '» → ', '→ ') || p_to, 200), 'link', v_me);
  end if;
  perform app.log('seo.link_decided', 'web_site', v_site.id::text, jsonb_build_object('decision', p_decision));
  return jsonb_build_object('decision', p_decision);
end $fn$;

-- a rule on or off, and its channels
create function public.seo_alert_rule_set(p_product text, p_rule text, p_enabled boolean, p_channels text[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'edit_others'); v_site app.web_sites := app.product_site(p_product);
begin
  if v_site.id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site'; end if;
  if p_rule is null or p_rule not in ('rank', 'deindex', 'traffic', 'cwv') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rule'; end if;
  if p_enabled is null or p_channels is null or not (p_channels <@ array['app', 'email']::text[]) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'channels';
  end if;
  insert into app.seo_alert_rules (site_id, rule, enabled, channels, updated_by)
  values (v_site.id, p_rule, p_enabled, (select coalesce(array_agg(distinct c order by c), '{}') from unnest(p_channels) c), v_me)
  on conflict (site_id, rule) do update set enabled = excluded.enabled, channels = excluded.channels, updated_by = excluded.updated_by, updated_at = now();
  perform app.log('seo.alert_rule_set', 'web_site', v_site.id::text, jsonb_build_object('rule', p_rule, 'enabled', p_enabled, 'channels', to_jsonb(p_channels)));
  return jsonb_build_object('rule', p_rule, 'enabled', p_enabled);
end $fn$;

-- «Acknowledge» and «Reopen»
create function public.seo_alert_ack(p_id uuid, p_ack boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add');
begin
  update app.seo_alerts set acknowledged_at = case when p_ack then now() end, acknowledged_by = case when p_ack then v_me end where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('acknowledged', coalesce(p_ack, false));
end $fn$;

-- ===========================================================================
-- grants
-- ===========================================================================
revoke all on function app.seo_terms(uuid) from public, anon, authenticated;
revoke all on function app.seo_rule(uuid, text) from public, anon, authenticated;
revoke all on function app.seo_alert_raise(uuid, text, text, text, jsonb, interval) from public, anon, authenticated;
revoke all on function app.seo_alerts_tick() from public, anon, authenticated;
revoke all on function app.seo_econ(text, uuid) from public, anon, authenticated;
revoke all on function app.has_source(jsonb) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.seo_overview(text)', 'public.seo_opportunities(text)', 'public.seo_clusters(text)', 'public.seo_plan_get(text, uuid)',
                           'public.seo_links_get(text)', 'public.seo_changes_get(text)', 'public.seo_alerts_get(text)',
                           'public.seo_plan_add(text, text, text, text)', 'public.seo_plan_move(uuid, text)', 'public.seo_change_add(text, text, text, text)',
                           'public.seo_link_decide(text, text, text, text, text)', 'public.seo_alert_rule_set(text, text, boolean, text[])',
                           'public.seo_alert_ack(uuid, boolean)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_seo_index_targets()', 'public.worker_seo_index_result(uuid, jsonb)', 'public.worker_seo_crawl_sites()',
                           'public.worker_seo_links(uuid, text, jsonb, jsonb)', 'public.worker_seo_alert_mail_claim(int)',
                           'public.worker_seo_alert_mail_done(uuid, uuid, boolean)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
