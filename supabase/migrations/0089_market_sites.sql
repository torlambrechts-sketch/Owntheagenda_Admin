-- 0089_market_sites.sql — one site per market: orgpuls.com (Norway), se.orgpuls.com (Sweden), empvibe.com (United Kingdom).
--
-- Tor, 13 Oct 2026: «how do we handle sub-domains? We have added empvibe.com for the english setup» — then «yes please» to
-- a site per market, after adding empvibe.com to Google Search Console. Until now Orgpuls had one site: orgpuls.com with
-- empvibe.com as an alias (0070) and se.orgpuls.com counted as its subdomain. Every visit kept its host, but Growth added
-- the three markets together, Pages put «/» of each in one row, Search Console read sc-domain:orgpuls.com only (the
-- Swedish queries inside Norway's, none of Empvibe's), and the crawler and PageSpeed read www.orgpuls.com only.
--
-- 1. Sites. se.orgpuls.com and empvibe.com become sites of Orgpuls beside orgpuls.com, which loses its empvibe.com
--    alias. web_sites.ord orders a product's sites; orgpuls.com is first, the site a reader of one site falls back to.
--    The crawler, PageSpeed, the index checks and the tracker already work per site, so each market is read on its own.
-- 2. Visits. A visit filed under orgpuls.com whose recorded host is another site's (empvibe.com, www.empvibe.com,
--    se.orgpuls.com) moves to that site, with its page views and events. The visits from before 0070 recorded no host
--    and stay with orgpuls.com.
-- 3. The site in Growth. growth_scope, growth_funnel, growth_pages and the SEO reads and writes take p_site (null: all of
--    the application's sites for the reads, its first site for SEO, as before); app.growth_sites and app.product_site take
--    it too and refuse a site that is not the application's. growth_sites_list names the application's sites for the
--    picker. An account's signup carries no site (nor a device), so with one site chosen Accounts and Paying are «—», as
--    with a device chosen: never another market's figure under this one's name.
-- 4. Search Console. orgpuls.com and se.orgpuls.com are both read through sc-domain:orgpuls.com, so each import keeps
--    only its own pages: worker_search_console_targets says each site's hosts and the other sites' hosts inside them, and
--    search-console-run filters by page. Norway's imported rows (which held Sweden's) are dropped and read again, filtered;
--    they are Google's, and the next run brings them back. A site without a property is looked up by the nightly run, not
--    only by «connect». Integrations shows each site's property.
-- 5. Referrers. A product's sites are not referrers to each other, nor their subdomains.

-- ---------------------------------------------------------------------------
-- 1. sites
alter table app.web_sites add column if not exists ord int not null default 100;
update app.web_sites set ord = 0 where hostname = 'orgpuls.com';
update app.web_sites set aliases = array_remove(aliases, 'empvibe.com') where hostname = 'orgpuls.com' and 'empvibe.com' = any (aliases);
insert into app.web_sites (hostname, key, product, ord)
select v.hostname, v.key, 'orgpuls', v.ord
from (values ('se.orgpuls.com', 'se-orgpuls-com', 10), ('empvibe.com', 'empvibe-com', 20)) v(hostname, key, ord)
where exists (select 1 from app.products where key = 'orgpuls')
on conflict (hostname) do update set product = excluded.product, ord = excluded.ord, active = true;

-- ---------------------------------------------------------------------------
-- 2. each visit to the site its host belongs to
update app.web_sessions s set site_id = t.id
from app.web_sites o, app.web_sites t
where s.site_id = o.id and o.hostname = 'orgpuls.com' and s.host is not null
  and t.id <> o.id and t.active and t.product is not distinct from o.product
  and regexp_replace(s.host, '^www\.', '') = any (array[t.hostname] || t.aliases);

-- ---------------------------------------------------------------------------
-- 3. the site helpers
create or replace function app.growth_sites(p_product text) returns uuid[]
  language sql stable security definer set search_path = ''
as $fn$ select array(select s.id from app.web_sites s where s.active and (nullif(p_product, 'all') is null or s.product = p_product) order by s.ord, s.hostname) $fn$;

-- one site of the application's, or all of them; a site that is not the application's is refused
create function app.growth_sites(p_product text, p_site uuid) returns uuid[]
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if p_site is null then return app.growth_sites(p_product); end if;
  if not exists (select 1 from app.web_sites s where s.id = p_site and s.active and (nullif(p_product, 'all') is null or s.product = p_product)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site';
  end if;
  return array[p_site];
end $fn$;

create or replace function app.product_site(p_product text) returns app.web_sites
  language sql stable security definer set search_path = ''
as $fn$
  select s.* from app.web_sites s where s.active and s.product = p_product order by s.ord, s.hostname limit 1
$fn$;

-- the site SEO reads and writes: the one chosen, or the application's first
create function app.product_site(p_product text, p_site uuid) returns app.web_sites
  language plpgsql stable security definer set search_path = ''
as $fn$
declare s app.web_sites;
begin
  if p_site is null then return app.product_site(p_product); end if;
  select * into s from app.web_sites w where w.id = p_site and w.active and (p_product is null or w.product = p_product);
  if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site'; end if;
  return s;
end $fn$;
revoke all on function app.growth_sites(text, uuid), app.product_site(text, uuid) from public, anon, authenticated;

-- the application's sites, for Growth's site picker
create function public.growth_sites_list(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_marketing_reports();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'hostname', s.hostname) order by s.ord, s.hostname)
                   from app.web_sites s where s.id = any (app.growth_sites(nullif(p_product, 'all')))), '[]'::jsonb);
end $fn$;
revoke all on function public.growth_sites_list(text) from public, anon;
grant execute on function public.growth_sites_list(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Search Console: each site's own pages; a site without a property is looked up by the nightly run
create or replace function public.worker_search_console_sites() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('site_id', s.id, 'hostname', s.hostname, 'property', c.property) order by s.ord, s.hostname), '[]'::jsonb)
  from app.web_sites s left join app.search_console_sites c on c.site_id = s.id where s.active
$fn$;

-- the hosts a site's pages are on (its hostname and aliases, each with its subdomains) and the other sites' hosts inside
-- them, which its import leaves out (se.orgpuls.com inside orgpuls.com)
create or replace function public.worker_search_console_targets() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('site_id', c.site_id, 'property', c.property,
           'from', greatest(coalesce(c.last_day - 4, current_date - 180), current_date - 480), 'to', current_date - 1,
           'hosts', to_jsonb(array[s.hostname] || s.aliases),
           'except', to_jsonb(array(select o.hostname from app.web_sites o
                                    where o.active and o.id <> s.id
                                      and exists (select 1 from unnest(array[s.hostname] || s.aliases) h where o.hostname like '%.' || h)
                                    order by o.hostname)))
           order by s.ord, c.site_id), '[]'::jsonb)
  from app.search_console_sites c join app.web_sites s on s.id = c.site_id
  where s.active and c.property is not null and app.connected('search_console')
$fn$;

-- Norway's imported rows held Sweden's: dropped, and read again filtered (from 180 days back) by the next run
delete from app.search_console_totals t using app.web_sites s where t.site_id = s.id and s.hostname = 'orgpuls.com';
delete from app.search_console_daily t using app.web_sites s where t.site_id = s.id and s.hostname = 'orgpuls.com';
delete from app.search_console_pages t using app.web_sites s where t.site_id = s.id and s.hostname = 'orgpuls.com';
update app.search_console_sites c set last_day = null, updated_at = now() from app.web_sites s where c.site_id = s.id and s.hostname = 'orgpuls.com';

-- ---------------------------------------------------------------------------
-- 5. a product's sites are not referrers to each other, nor their subdomains
create or replace function app.web_foreign_referrer(p_site uuid, p_host text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select case when p_host is null or btrim(p_host) = '' then null
              when exists (select 1 from app.web_sites me join app.web_sites s on s.id = me.id or (me.product is not null and s.product = me.product)
                           cross join lateral unnest(array[s.hostname] || s.aliases) h(x)
                           where me.id = p_site
                             and (regexp_replace(lower(p_host), '^www\.', '') = regexp_replace(h.x, '^www\.', '')
                                  or lower(p_host) like '%.' || regexp_replace(h.x, '^www\.', ''))) then null
              else lower(p_host) end
$fn$;

-- ---------------------------------------------------------------------------
-- 4. Integrations: each site's Search Console property
CREATE OR REPLACE FUNCTION public.growth_integrations(p_product text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require_marketing_reports(); v_product text := nullif(p_product, 'all'); v_sites uuid[] := app.growth_sites(nullif(p_product, 'all'));
begin
  return jsonb_build_object(
    'can_manage', exists (select 1 from app.admins where id = v_me and role = 'owner'),
    'tracker', jsonb_build_object(
      'sites', coalesce((select jsonb_agg(jsonb_build_object('hostname', s.hostname, 'aliases', s.aliases, 'last_seen_at', s.last_seen_at) order by s.hostname)
                         from app.web_sites s where s.id = any (v_sites)), '[]'::jsonb),
      'last_seen_at', (select max(s.last_seen_at) from app.web_sites s where s.id = any (v_sites)),
      'sessions_24h', (select count(*) from app.web_sessions x where x.site_id = any (v_sites) and x.started_at > now() - interval '24 hours')),
    'search_console', (select jsonb_build_object('status', c.status, 'property', sc.property, 'last_import_at', sc.last_import_at, 'last_error', coalesce(sc.last_error, c.config ->> 'last_error'),
                         -- each market site's property (0089): orgpuls.com and se.orgpuls.com share the domain property, empvibe.com has its own
                         'sites', coalesce((select jsonb_agg(jsonb_build_object('hostname', w.hostname, 'property', x.property, 'last_import_at', x.last_import_at,
                                                                                'last_error', x.last_error) order by w.ord, w.hostname)
                                            from app.web_sites w left join app.search_console_sites x on x.site_id = w.id where w.id = any (v_sites)), '[]'::jsonb))
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
end $function$;

-- ---------------------------------------------------------------------------
-- 3. Growth's reads and SEO's reads and writes take the site (generated from their definitions after 0088: p_site added
--    last, with a default, and passed to app.growth_sites / app.product_site)
drop function public.growth_funnel(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text, p_step integer);
CREATE OR REPLACE FUNCTION public.growth_funnel(p_product text DEFAULT NULL::text, p_days integer DEFAULT 30, p_day date DEFAULT NULL::date, p_hour integer DEFAULT NULL::integer, p_channel text DEFAULT NULL::text, p_device text DEFAULT NULL::text, p_step integer DEFAULT 4, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w record; v_sites uuid[]; v_product text := nullif(p_product, 'all'); v_dev boolean := p_device is not null or p_site is not null;  -- an account carries neither a device nor a site (0089)
  st int := case when p_step between 1 and 7 then p_step else 4 end; v_since date;
begin
  perform app.require_marketing_reports();
  perform app.growth_check_filters(p_channel, p_device);
  select * into w from app.growth_window(p_days, p_day, p_hour);
  v_sites := app.growth_sites(v_product, p_site);
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
end $function$;
revoke all on function public.growth_funnel(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text, p_step integer, p_site uuid) from public, anon;
grant execute on function public.growth_funnel(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text, p_step integer, p_site uuid) to authenticated, service_role;

drop function public.growth_pages(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text, p_path text);
CREATE OR REPLACE FUNCTION public.growth_pages(p_product text DEFAULT NULL::text, p_days integer DEFAULT 30, p_day date DEFAULT NULL::date, p_hour integer DEFAULT NULL::integer, p_channel text DEFAULT NULL::text, p_device text DEFAULT NULL::text, p_path text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w record; v_sites uuid[]; v_product text := nullif(p_product, 'all'); v_path text; v_site uuid;
begin
  perform app.require_marketing_reports();
  perform app.growth_check_filters(p_channel, p_device);
  if p_path is not null and (p_path !~ '^/' or char_length(p_path) > 500) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path'; end if;
  select * into w from app.growth_window(p_days, p_day, p_hour);
  v_sites := app.growth_sites(v_product, p_site);
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
end $function$;
revoke all on function public.growth_pages(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text, p_path text, p_site uuid) from public, anon;
grant execute on function public.growth_pages(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text, p_path text, p_site uuid) to authenticated, service_role;

drop function public.growth_scope(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text);
CREATE OR REPLACE FUNCTION public.growth_scope(p_product text DEFAULT NULL::text, p_days integer DEFAULT 30, p_day date DEFAULT NULL::date, p_hour integer DEFAULT NULL::integer, p_channel text DEFAULT NULL::text, p_device text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w record; v_sites uuid[]; v_product text := nullif(p_product, 'all'); v_since date; v_dev boolean := p_device is not null or p_site is not null;  -- an account carries neither a device nor a site (0089)
  v_series jsonb; v_spend numeric; v_spend_prev numeric; v_s0 timestamptz; v_s1 timestamptz;
begin
  perform app.require_marketing_reports();
  perform app.growth_check_filters(p_channel, p_device);
  if v_product is not null and not exists (select 1 from app.products where key = v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  select * into w from app.growth_window(p_days, p_day, p_hour);
  v_sites := app.growth_sites(v_product, p_site);
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
end $function$;
revoke all on function public.growth_scope(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text, p_site uuid) from public, anon;
grant execute on function public.growth_scope(p_product text, p_days integer, p_day date, p_hour integer, p_channel text, p_device text, p_site uuid) to authenticated, service_role;

drop function public.seo_alert_rule_set(p_product text, p_rule text, p_enabled boolean, p_channels text[]);
CREATE OR REPLACE FUNCTION public.seo_alert_rule_set(p_product text, p_rule text, p_enabled boolean, p_channels text[], p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require('campaigns', 'edit_others'); v_site app.web_sites := app.product_site(p_product, p_site);
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
end $function$;
revoke all on function public.seo_alert_rule_set(p_product text, p_rule text, p_enabled boolean, p_channels text[], p_site uuid) from public, anon;
grant execute on function public.seo_alert_rule_set(p_product text, p_rule text, p_enabled boolean, p_channels text[], p_site uuid) to authenticated, service_role;

drop function public.seo_alerts_get(p_product text);
CREATE OR REPLACE FUNCTION public.seo_alerts_get(p_product text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  v_site app.web_sites := app.product_site(nullif(p_product, 'all'), p_site);
begin
  return jsonb_build_object(
    'mail_ready', app.mail_ready(),
    'rules', case when v_site.id is not null then (select jsonb_agg(jsonb_build_object('rule', r.rule, 'enabled', r.enabled, 'channels', to_jsonb(r.channels)) order by g.o)
                                                  from unnest(array['rank', 'deindex', 'traffic', 'cwv']) with ordinality g(rule, o)
                                                  cross join lateral app.seo_rule(v_site.id, g.rule) r) else '[]'::jsonb end,
    'open', (select count(*) from app.seo_alerts a where a.site_id = v_site.id and a.acknowledged_at is null),
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'rule', a.rule, 'params', a.params, 'at', a.at, 'acknowledged_at', a.acknowledged_at) order by a.at desc)
                         from (select * from app.seo_alerts a0 where a0.site_id = v_site.id order by a0.at desc limit 30) a), '[]'::jsonb));
end $function$;
revoke all on function public.seo_alerts_get(p_product text, p_site uuid) from public, anon;
grant execute on function public.seo_alerts_get(p_product text, p_site uuid) to authenticated, service_role;

drop function public.seo_change_add(p_product text, p_path text, p_kind text, p_note text);
CREATE OR REPLACE FUNCTION public.seo_change_add(p_product text, p_path text, p_kind text, p_note text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require('campaigns', 'add');
  v_site app.web_sites := app.product_site(p_product, p_site);
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
end $function$;
revoke all on function public.seo_change_add(p_product text, p_path text, p_kind text, p_note text, p_site uuid) from public, anon;
grant execute on function public.seo_change_add(p_product text, p_path text, p_kind text, p_note text, p_site uuid) to authenticated, service_role;

drop function public.seo_changes_get(p_product text);
CREATE OR REPLACE FUNCTION public.seo_changes_get(p_product text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product, p_site);
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
end $function$;
revoke all on function public.seo_changes_get(p_product text, p_site uuid) from public, anon;
grant execute on function public.seo_changes_get(p_product text, p_site uuid) to authenticated, service_role;

drop function public.seo_clusters(p_product text);
CREATE OR REPLACE FUNCTION public.seo_clusters(p_product text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product, p_site);
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
end $function$;
revoke all on function public.seo_clusters(p_product text, p_site uuid) from public, anon;
grant execute on function public.seo_clusters(p_product text, p_site uuid) to authenticated, service_role;

drop function public.seo_get(p_product text, p_days integer);
CREATE OR REPLACE FUNCTION public.seo_get(p_product text DEFAULT NULL::text, p_days integer DEFAULT 30, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  d int := case when p_days in (7, 30, 90) then p_days when p_days = 1 then 7 else 30 end;
  v_site app.web_sites := app.product_site(nullif(p_product, 'all'), p_site);
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
    -- every search Google showed the site for in the period (the 200 with most impressions) and the keywords tracked by
    -- hand (0084); a tracked keyword also counts the longer searches that contain it, since Google rarely reports a
    -- head term like «arbeidsmiljø» on its own
    'keywords_total', case when v_conn and v_site.id is not null then (select count(distinct s.query) from app.search_console_daily s
                        where s.site_id = v_site.id and s.day > current_date - d and s.impressions > 0) end,
    'keywords', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'query', k.query, 'tracked', k.id is not null, 'created_at', k.created_at, 'mine', k.created_by = v_me,
        'impressions', case when v_conn then x.i end, 'clicks', case when v_conn then x.c end,
        'position', case when v_conn then x.p end, 'position_prev', case when v_conn then x.pp end,
        -- the page Google showed most for it in the period (0072)
        'page', case when v_conn then (select p.page from app.search_console_pages p where p.site_id = v_site.id and p.query = k.query and p.day > current_date - d
                                       group by p.page having sum(p.impressions) > 0 order by sum(p.impressions) desc, p.page limit 1) end,
        'variants', case when v_conn and k.id is not null then (
            select jsonb_build_object('queries', count(distinct v.query), 'impressions', coalesce(sum(v.impressions), 0))
            from app.search_console_daily v
            where v.site_id = v_site.id and v.day > current_date - d and v.impressions > 0 and v.query <> k.query
              and strpos(lower(v.query), lower(k.query)) > 0) end) order by k.id is null, k.created_at, x.i desc nulls last, k.query)
      from (select t.id, t.query, t.created_at, t.created_by from app.seo_keywords t where t.site_id = v_site.id
            union all
            select null::uuid, q.query, null::timestamptz, null::uuid from (
              select s.query from app.search_console_daily s
              where v_conn and s.site_id = v_site.id and s.day > current_date - d
                and not exists (select 1 from app.seo_keywords t where t.site_id = v_site.id and t.query = s.query)
              group by s.query having sum(s.impressions) > 0
              order by sum(s.impressions) desc, s.query limit 200) q) k
      left join lateral (
        select sum(sc2.impressions) filter (where sc2.day > current_date - d) i, sum(sc2.clicks) filter (where sc2.day > current_date - d) c,
               round(sum(sc2.position * sc2.impressions) filter (where sc2.day > current_date - d and sc2.position is not null)
                     / nullif(sum(sc2.impressions) filter (where sc2.day > current_date - d and sc2.position is not null), 0), 1) p,
               round(sum(sc2.position * sc2.impressions) filter (where sc2.day <= current_date - d and sc2.position is not null)
                     / nullif(sum(sc2.impressions) filter (where sc2.day <= current_date - d and sc2.position is not null), 0), 1) pp
        from app.search_console_daily sc2 where sc2.site_id = v_site.id and sc2.query = k.query and sc2.day > current_date - 2 * d) x on true
      where v_site.id is not null), '[]'::jsonb),
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
end $function$;
revoke all on function public.seo_get(p_product text, p_days integer, p_site uuid) from public, anon;
grant execute on function public.seo_get(p_product text, p_days integer, p_site uuid) to authenticated, service_role;

drop function public.seo_idea_plan(p_product text, p_query text);
CREATE OR REPLACE FUNCTION public.seo_idea_plan(p_product text, p_query text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require('campaigns', 'add');
  v_site app.web_sites := app.product_site(p_product, p_site);
  v_q text := lower(btrim(regexp_replace(coalesce(p_query, ''), '\s+', ' ', 'g')));
  v_id uuid;
begin
  if v_site.id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site'; end if;
  if char_length(v_q) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'query'; end if;
  insert into app.seo_content_plan (site_id, query, created_by) values (v_site.id, v_q, v_me)
  on conflict (site_id, query) do nothing returning id into v_id;
  if v_id is not null then perform app.log('seo.article_planned', 'web_site', v_site.id::text, jsonb_build_object('query', v_q)); end if;
  return jsonb_build_object('query', v_q, 'planned', true);
end $function$;
revoke all on function public.seo_idea_plan(p_product text, p_query text, p_site uuid) from public, anon;
grant execute on function public.seo_idea_plan(p_product text, p_query text, p_site uuid) to authenticated, service_role;

drop function public.seo_issue_fix(p_product text, p_kind text);
CREATE OR REPLACE FUNCTION public.seo_issue_fix(p_product text, p_kind text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require('campaigns', 'add'); v_site app.web_sites := app.product_site(p_product, p_site); n int;
begin
  if v_site.id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site'; end if;
  update app.seo_issues set fixed_at = now(), fixed_by = v_me
  where site_id = v_site.id and kind = p_kind and resolved_at is null and fixed_at is null;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('seo.issue_marked_fixed', 'web_site', v_site.id::text, jsonb_build_object('kind', p_kind));
  return jsonb_build_object('kind', p_kind);
end $function$;
revoke all on function public.seo_issue_fix(p_product text, p_kind text, p_site uuid) from public, anon;
grant execute on function public.seo_issue_fix(p_product text, p_kind text, p_site uuid) to authenticated, service_role;

drop function public.seo_keyword_add(p_product text, p_query text);
CREATE OR REPLACE FUNCTION public.seo_keyword_add(p_product text, p_query text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require('campaigns', 'add');
  v_site app.web_sites := app.product_site(p_product, p_site);
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
end $function$;
revoke all on function public.seo_keyword_add(p_product text, p_query text, p_site uuid) from public, anon;
grant execute on function public.seo_keyword_add(p_product text, p_query text, p_site uuid) to authenticated, service_role;

drop function public.seo_keyword_history(p_product text, p_query text, p_days integer);
CREATE OR REPLACE FUNCTION public.seo_keyword_history(p_product text, p_query text, p_days integer DEFAULT 30, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_site app.web_sites := app.product_site(nullif(p_product, 'all'), p_site); d int := case when p_days in (7, 30, 90) then p_days else 30 end;
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
end $function$;
revoke all on function public.seo_keyword_history(p_product text, p_query text, p_days integer, p_site uuid) from public, anon;
grant execute on function public.seo_keyword_history(p_product text, p_query text, p_days integer, p_site uuid) to authenticated, service_role;

drop function public.seo_link_decide(p_product text, p_from text, p_to text, p_anchor text, p_decision text);
CREATE OR REPLACE FUNCTION public.seo_link_decide(p_product text, p_from text, p_to text, p_anchor text, p_decision text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require('campaigns', 'add');
  v_site app.web_sites := app.product_site(p_product, p_site);
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
end $function$;
revoke all on function public.seo_link_decide(p_product text, p_from text, p_to text, p_anchor text, p_decision text, p_site uuid) from public, anon;
grant execute on function public.seo_link_decide(p_product text, p_from text, p_to text, p_anchor text, p_decision text, p_site uuid) to authenticated, service_role;

drop function public.seo_links_get(p_product text);
CREATE OR REPLACE FUNCTION public.seo_links_get(p_product text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product, p_site);
  v_sites uuid[] := app.growth_sites(nullif(p_product, 'all'), p_site);
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
end $function$;
revoke all on function public.seo_links_get(p_product text, p_site uuid) from public, anon;
grant execute on function public.seo_links_get(p_product text, p_site uuid) to authenticated, service_role;

drop function public.seo_opportunities(p_product text);
CREATE OR REPLACE FUNCTION public.seo_opportunities(p_product text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product, p_site);
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
end $function$;
revoke all on function public.seo_opportunities(p_product text, p_site uuid) from public, anon;
grant execute on function public.seo_opportunities(p_product text, p_site uuid) to authenticated, service_role;

drop function public.seo_overview(p_product text);
CREATE OR REPLACE FUNCTION public.seo_overview(p_product text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product, p_site);
  v_conn boolean := app.connected('search_console');
  sc app.search_console_sites;
  v_sites uuid[] := app.growth_sites(v_product, p_site);
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
end $function$;
revoke all on function public.seo_overview(p_product text, p_site uuid) from public, anon;
grant execute on function public.seo_overview(p_product text, p_site uuid) to authenticated, service_role;

drop function public.seo_plan_add(p_product text, p_query text, p_kind text, p_path text);
CREATE OR REPLACE FUNCTION public.seo_plan_add(p_product text, p_query text, p_kind text, p_path text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require('campaigns', 'add');
  v_site app.web_sites := app.product_site(p_product, p_site);
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
end $function$;
revoke all on function public.seo_plan_add(p_product text, p_query text, p_kind text, p_path text, p_site uuid) from public, anon;
grant execute on function public.seo_plan_add(p_product text, p_query text, p_kind text, p_path text, p_site uuid) to authenticated, service_role;

drop function public.seo_plan_get(p_product text, p_item uuid);
CREATE OR REPLACE FUNCTION public.seo_plan_get(p_product text DEFAULT NULL::text, p_item uuid DEFAULT NULL::uuid, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_site app.web_sites := app.product_site(v_product, p_site);
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
end $function$;
revoke all on function public.seo_plan_get(p_product text, p_item uuid, p_site uuid) from public, anon;
grant execute on function public.seo_plan_get(p_product text, p_item uuid, p_site uuid) to authenticated, service_role;
