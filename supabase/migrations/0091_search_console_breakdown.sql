-- 0091_search_console_breakdown.sql — what Search Console reports beyond the searches it names: each page's own figures,
-- and the countries and devices the searches came from.
--
-- 1. A page's own figures (Tor, 14 Oct 2026). Search Console names a search only when enough people made it; the rest it
--    counts in a day's totals and leaves out of every list by search. search_console_pages (0072) is day × search × page,
--    so a page's figures summed from it missed every unnamed search: on orgpuls.com, 122 of 241 impressions and none of
--    the 3 clicks between 27 September and 11 October. search_console_page_totals is day × page, as Search Console's own
--    Pages report counts. «Pages in Google» (seo_get), a page change's before and after (seo_changes_get), pages losing
--    clicks (seo_opportunities) and the page card in Growth › Pages (growth_pages) read it once it is imported; which page
--    a search showed (ranking page, split searches, clusters) still reads search_console_pages.
-- 2. Countries and devices (Tor, same day): day × country and day × device in search_console_segments. SEO › Overview
--    shows the last 30 days and the 30 before: the ten countries seen most and the rest together, and the devices.
-- 3. What the list of searches leaves out: seo_get's totals carry the period's impressions and clicks in named searches,
--    so Keywords can say how much came from searches Google does not name.
-- 4. worker_search_console_import takes the three, each optional (the function deployed before this one sends none), and
--    replaces them for the days the totals report, as it does the totals and the searches. Every site's last_day is
--    reset, so the next run reads the last 180 days again, these included.
--
-- Nothing here is about a person: Google counts searches by country and device, never who searched.

-- ---------------------------------------------------------------------------
-- 1. the tables
-- ---------------------------------------------------------------------------
create table app.search_console_page_totals (
  day         date not null,
  site_id     uuid not null references app.web_sites (id) on delete cascade,
  page        text not null check (page ~ '^/' and char_length(page) <= 300),
  impressions int not null check (impressions >= 0),
  clicks      int not null check (clicks >= 0),
  position    numeric check (position is null or position > 0),
  primary key (day, site_id, page)
);
alter table app.search_console_page_totals enable row level security;
revoke all on app.search_console_page_totals from public, anon, authenticated;
create index search_console_page_totals_page on app.search_console_page_totals (site_id, page, day);

-- a country is ISO 3166-1 alpha-3 as Google writes it («nor»; «zzz» where it cannot tell); a device is one of Google's three
create table app.search_console_segments (
  day         date not null,
  site_id     uuid not null references app.web_sites (id) on delete cascade,
  kind        text not null check (kind in ('country', 'device')),
  key         text not null,
  impressions int not null check (impressions >= 0),
  clicks      int not null check (clicks >= 0),
  position    numeric check (position is null or position > 0),
  primary key (day, site_id, kind, key),
  check ((kind = 'country' and key ~ '^[a-z]{3}$') or (kind = 'device' and key in ('desktop', 'mobile', 'tablet')))
);
alter table app.search_console_segments enable row level security;
revoke all on app.search_console_segments from public, anon, authenticated;
create index search_console_segments_site on app.search_console_segments (site_id, kind, day);

-- a site's pages are read from their own figures once those are imported; until then, summed from the searches as before
create function app.search_console_page_totals_ready(p_site uuid) returns boolean
  language sql stable set search_path = ''
as $fn$ select exists (select 1 from app.search_console_page_totals t where t.site_id = p_site) $fn$;
revoke all on function app.search_console_page_totals_ready(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. the import
-- ---------------------------------------------------------------------------
-- one breakdown's rows for the days the totals report, replacing what was there for those days
create function app.search_console_segments_put(p_site uuid, p_days date[], p_kind text, p_rows jsonb) returns int
  language plpgsql volatile set search_path = ''
as $fn$
declare n int;
begin
  if p_kind not in ('country', 'device') or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) > 100000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  delete from app.search_console_segments where site_id = p_site and kind = p_kind and day = any (p_days);
  insert into app.search_console_segments (day, site_id, kind, key, impressions, clicks, position)
  select v.d, p_site, p_kind, v.k, v.i, v.c, v.pos
  from (select (x ->> 'day')::date d, lower(btrim(x ->> 'key')) k,
               greatest(sum((x ->> 'impressions')::int), 0) i, greatest(sum((x ->> 'clicks')::int), 0) c,
               round(sum((x ->> 'position')::numeric * (x ->> 'impressions')::int) / nullif(sum((x ->> 'impressions')::int), 0), 2) pos
        from jsonb_array_elements(p_rows) x
        where (x ->> 'day')::date = any (p_days)
        group by 1, 2) v
  where (p_kind = 'country' and v.k ~ '^[a-z]{3}$') or (p_kind = 'device' and v.k in ('desktop', 'mobile', 'tablet'));
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke all on function app.search_console_segments_put(uuid, date[], text, jsonb) from public, anon, authenticated;

-- one site's import: the day totals, the day × search rows and now the day × page, day × country and day × device rows,
-- replacing what was there for the days the totals report. The three new ones are optional: one not sent leaves its days
-- as they were.
drop function public.worker_search_console_import(uuid, jsonb, jsonb);
create function public.worker_search_console_import(p_site uuid, p_totals jsonb, p_rows jsonb,
                                                    p_pages jsonb default null, p_countries jsonb default null, p_devices jsonb default null)
  returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_days date[]; n_t int; n_r int; n_p int; n_c int; n_d int;
begin
  if not exists (select 1 from app.search_console_sites where site_id = p_site and property is not null) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  if jsonb_typeof(p_totals) <> 'array' or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 100000
     or (p_pages is not null and (jsonb_typeof(p_pages) <> 'array' or jsonb_array_length(p_pages) > 100000)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  select coalesce(array_agg(distinct (x ->> 'day')::date), '{}') into v_days from jsonb_array_elements(p_totals) x;
  delete from app.search_console_totals where site_id = p_site and day = any (v_days);
  delete from app.search_console_daily where site_id = p_site and day = any (v_days);
  insert into app.search_console_totals (day, site_id, impressions, clicks, position)
  select (x ->> 'day')::date, p_site, greatest((x ->> 'impressions')::int, 0), greatest((x ->> 'clicks')::int, 0), nullif((x ->> 'position')::numeric, 0)
  from jsonb_array_elements(p_totals) x
  on conflict (day, site_id) do update set impressions = excluded.impressions, clicks = excluded.clicks, position = excluded.position;
  get diagnostics n_t = row_count;
  insert into app.search_console_daily (day, site_id, query, impressions, clicks, position)
  select (x ->> 'day')::date, p_site, left(lower(btrim(x ->> 'query')), 200), greatest(sum((x ->> 'impressions')::int), 0), greatest(sum((x ->> 'clicks')::int), 0),
         round(sum((x ->> 'position')::numeric * (x ->> 'impressions')::int) / nullif(sum((x ->> 'impressions')::int), 0), 2)
  from jsonb_array_elements(p_rows) x
  where (x ->> 'day')::date = any (v_days) and coalesce(btrim(x ->> 'query'), '') <> ''
  group by 1, 3;
  get diagnostics n_r = row_count;
  if p_pages is not null then
    delete from app.search_console_page_totals where site_id = p_site and day = any (v_days);
    insert into app.search_console_page_totals (day, site_id, page, impressions, clicks, position)
    select (x ->> 'day')::date, p_site, left(x ->> 'page', 300), greatest(sum((x ->> 'impressions')::int), 0), greatest(sum((x ->> 'clicks')::int), 0),
           round(sum((x ->> 'position')::numeric * (x ->> 'impressions')::int) / nullif(sum((x ->> 'impressions')::int), 0), 2)
    from jsonb_array_elements(p_pages) x
    where (x ->> 'day')::date = any (v_days) and coalesce(x ->> 'page', '') ~ '^/'
    group by 1, 3;
    get diagnostics n_p = row_count;
  end if;
  if p_countries is not null then n_c := app.search_console_segments_put(p_site, v_days, 'country', p_countries); end if;
  if p_devices is not null then n_d := app.search_console_segments_put(p_site, v_days, 'device', p_devices); end if;
  update app.search_console_sites set last_import_at = now(), last_error = null,
    last_day = greatest(last_day, (select max(d) from unnest(v_days) d)), updated_at = now()
  where site_id = p_site;
  return jsonb_build_object('totals', n_t, 'rows', n_r) || jsonb_strip_nulls(jsonb_build_object('pages', n_p, 'countries', n_c, 'devices', n_d));
end $fn$;
revoke all on function public.worker_search_console_import(uuid, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.worker_search_console_import(uuid, jsonb, jsonb, jsonb, jsonb, jsonb) to service_role;

-- the next run reads the last 180 days again, the three new ones with them
update app.search_console_sites set last_day = null, updated_at = now() where last_day is not null;

-- ---------------------------------------------------------------------------
-- 3. the readers
-- ---------------------------------------------------------------------------

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
  v_full boolean := app.search_console_page_totals_ready(v_site.id);
begin
  select * into c from app.integration_connections where provider = 'search_console';
  select * into sc from app.search_console_sites where site_id = v_site.id;
  -- a period counts pages only once pages were imported for it (0072 starts the import)
  v_pages := exists (select 1 from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - d)
             or exists (select 1 from app.search_console_page_totals p where p.site_id = v_site.id and p.day > current_date - d);
  v_pages_prev := exists (select 1 from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - 2 * d and p.day <= current_date - d)
                  or exists (select 1 from app.search_console_page_totals p where p.site_id = v_site.id and p.day > current_date - 2 * d and p.day <= current_date - d);
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
                               / nullif(sum(t.impressions) filter (where t.day <= current_date - d and t.position is not null), 0), 1),
        -- what the period's named searches add up to (0091): the rest came from searches Google does not name
        'named_impressions', (select coalesce(sum(s.impressions), 0) from app.search_console_daily s where s.site_id = v_site.id and s.day > current_date - d),
        'named_clicks', (select coalesce(sum(s.clicks), 0) from app.search_console_daily s where s.site_id = v_site.id and s.day > current_date - d))
        -- pages Google showed in search in the period (0072), the honest stand-in for «Indexed pages»; null before pages are
        -- imported. From the pages' own figures once imported (0091): a page shown only for unnamed searches counts too
        || jsonb_build_object(
             'pages', case when v_pages then (case when v_full then (select count(distinct p.page) from app.search_console_page_totals p
                                                                    where p.site_id = v_site.id and p.day > current_date - d and p.impressions > 0)
                                                   else (select count(distinct p.page) from app.search_console_pages p
                                                         where p.site_id = v_site.id and p.day > current_date - d and p.impressions > 0) end) end,
             'pages_prev', case when v_pages_prev then (case when v_full then (select count(distinct p.page) from app.search_console_page_totals p
                                                                              where p.site_id = v_site.id and p.day > current_date - 2 * d and p.day <= current_date - d and p.impressions > 0)
                                                             else (select count(distinct p.page) from app.search_console_pages p
                                                                   where p.site_id = v_site.id and p.day > current_date - 2 * d and p.day <= current_date - d and p.impressions > 0) end) end)
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
  -- how far back the pages' own figures (0091) and the searches by page (0072) go
  v_tot_from date := (select min(t.day) from app.search_console_page_totals t where t.site_id = v_site.id);
  v_q_from date := (select min(p.day) from app.search_console_pages p where p.site_id = v_site.id);
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
          -- a page: its own figures (0091) when they reach the four weeks before the change, or as far back as the searches by
          -- page do; else summed from the searches by page, as before
          select p.day, p.day >= c.day after, p.clicks c, p.impressions i,
                 case when p.position is not null then p.position * p.impressions end pw, case when p.position is not null then p.impressions end iw
          from app.search_console_page_totals p
          where c.path is not null and v_tot_from <= greatest(c.day - 28, coalesce(v_q_from, c.day - 28))
            and p.site_id = c.site_id and p.page = c.path and p.day >= c.day - 28 and p.day < c.day + 28
          union all
          select p.day, p.day >= c.day, p.clicks, p.impressions,
                 case when p.position is not null then p.position * p.impressions end, case when p.position is not null then p.impressions end
          from app.search_console_pages p
          where c.path is not null and (v_tot_from is null or v_tot_from > greatest(c.day - 28, coalesce(v_q_from, c.day - 28)))
            and p.site_id = c.site_id and p.page = c.path and p.day >= c.day - 28 and p.day < c.day + 28
          union all
          select d.day, d.day >= c.day, d.clicks, d.impressions,
                 case when d.position is not null then d.position * d.impressions end, case when d.position is not null then d.impressions end
          from app.search_console_daily d
          where c.path is null and d.site_id = c.site_id and d.query = c.query and d.day >= c.day - 28 and d.day < c.day + 28) r) m on true), '[]'::jsonb));
end $function$;
revoke all on function public.seo_changes_get(p_product text, p_site uuid) from public, anon;
grant execute on function public.seo_changes_get(p_product text, p_site uuid) to authenticated, service_role;

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
  v_full boolean := app.search_console_page_totals_ready(v_site.id);
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
    -- pages whose clicks over the last 28 days fell by a quarter or more against the same 28 days three months before; a
    -- page's clicks are its own figures once imported (0091), unnamed searches included
    'decay', case when v_ok then coalesce((select jsonb_agg(jsonb_build_object('path', dc.page, 'clicks', dc.c_now, 'clicks_before', dc.c_before,
                                                                               'impressions', dc.i_now, 'query', dc.top_query) order by dc.c_before - dc.c_now desc, dc.page) from (
      select * from (
        select p.page,
               coalesce(sum(p.clicks) filter (where p.day > current_date - 28), 0) c_now,
               coalesce(sum(p.clicks) filter (where p.day > current_date - 119 and p.day <= current_date - 91), 0) c_before,
               coalesce(sum(p.impressions) filter (where p.day > current_date - 28), 0) i_now,
               (select p2.query from app.search_console_pages p2 where p2.site_id = v_site.id and p2.page = p.page and p2.day > current_date - 119
                group by p2.query order by sum(p2.clicks) desc, sum(p2.impressions) desc, p2.query limit 1) top_query
        from (select t.page, t.day, t.clicks, t.impressions from app.search_console_page_totals t
              where v_full and t.site_id = v_site.id and t.day > current_date - 119
              union all
              select q.page, q.day, q.clicks, q.impressions from app.search_console_pages q
              where not v_full and q.site_id = v_site.id and q.day > current_date - 119) p
        group by p.page) dc0
      where dc0.c_before >= 10 and dc0.c_now <= dc0.c_before * 0.75
      order by dc0.c_before - dc0.c_now desc, dc0.page limit 10) dc), '[]'::jsonb) end,
    'planned', coalesce((select jsonb_agg(jsonb_build_object('query', cp.query, 'stage', cp.stage)) from app.seo_content_plan cp where cp.site_id = v_site.id), '[]'::jsonb));
end $function$;
revoke all on function public.seo_opportunities(p_product text, p_site uuid) from public, anon;
grant execute on function public.seo_opportunities(p_product text, p_site uuid) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.growth_pages(p_product text DEFAULT NULL::text, p_days integer DEFAULT 30, p_day date DEFAULT NULL::date, p_hour integer DEFAULT NULL::integer, p_channel text DEFAULT NULL::text, p_device text DEFAULT NULL::text, p_path text DEFAULT NULL::text, p_site uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w record; v_sites uuid[]; v_product text := nullif(p_product, 'all'); v_path text; v_site uuid; v_full boolean;
begin
  perform app.require_marketing_reports();
  perform app.growth_check_filters(p_channel, p_device);
  if p_path is not null and (p_path !~ '^/' or char_length(p_path) > 500) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path'; end if;
  select * into w from app.growth_window(p_days, p_day, p_hour);
  v_sites := app.growth_sites(v_product, p_site);
  v_site := v_sites[1];
  v_full := app.search_console_page_totals_ready(v_site);
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
        -- the page in Google search over the keywords' period (0091): its own figures, and how much of them its named
        -- searches account for; null before the pages' own figures are imported
        'google', case when v_full then (
          select jsonb_build_object('days', greatest(w.d, 28), 'impressions', coalesce(sum(g.impressions), 0), 'clicks', coalesce(sum(g.clicks), 0),
                                    'position', round(sum(g.position * g.impressions) filter (where g.position is not null)
                                                      / nullif(sum(g.impressions) filter (where g.position is not null), 0), 1),
                                    'named_impressions', (select coalesce(sum(p.impressions), 0) from app.search_console_pages p
                                                          where p.site_id = v_site and p.page = v_path and p.day > current_date - greatest(w.d, 28)),
                                    'named_clicks', (select coalesce(sum(p.clicks), 0) from app.search_console_pages p
                                                     where p.site_id = v_site and p.page = v_path and p.day > current_date - greatest(w.d, 28)))
          from app.search_console_page_totals g where g.site_id = v_site and g.page = v_path and g.day > current_date - greatest(w.d, 28)) end,
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
    -- the countries and devices the searches came from (0091), the last 30 days and the impressions of the 30 before: the
    -- ten countries seen most and the rest together; «imported» is false until the first import that reads them
    'segments', case when v_conn and sc.property is not null then (
      with g as (
        select x.kind, x.key, sum(x.impressions) filter (where x.day > current_date - 30) i, sum(x.clicks) filter (where x.day > current_date - 30) c,
               round(sum(x.position * x.impressions) filter (where x.day > current_date - 30 and x.position is not null)
                     / nullif(sum(x.impressions) filter (where x.day > current_date - 30 and x.position is not null), 0), 1) p,
               sum(x.impressions) filter (where x.day <= current_date - 30) ip
        from app.search_console_segments x where x.site_id = v_site.id and x.day > current_date - 60
        group by 1, 2),
      r as (select g.*, row_number() over (partition by g.kind order by g.i desc, g.key) rn from g where coalesce(g.i, 0) > 0)
      select jsonb_build_object(
        'imported', exists (select 1 from app.search_console_segments x where x.site_id = v_site.id),
        'countries', coalesce((select jsonb_agg(jsonb_build_object('key', r.key, 'impressions', r.i, 'clicks', coalesce(r.c, 0), 'position', r.p,
                                                                   'impressions_prev', coalesce(r.ip, 0)) order by r.rn)
                               from r where r.kind = 'country' and r.rn <= 10), '[]'::jsonb),
        'countries_other', (select jsonb_build_object('countries', count(*), 'impressions', sum(r.i), 'clicks', coalesce(sum(r.c), 0))
                            from r where r.kind = 'country' and r.rn > 10 having count(*) > 0),
        'devices', coalesce((select jsonb_agg(jsonb_build_object('key', r.key, 'impressions', r.i, 'clicks', coalesce(r.c, 0), 'position', r.p,
                                                                 'impressions_prev', coalesce(r.ip, 0)) order by r.rn)
                             from r where r.kind = 'device'), '[]'::jsonb))) end,
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
