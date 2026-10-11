-- 0072_seo_site_health.sql — Growth › SEO gets the three parts SimpleGrowth.dc.html drew and V-SGR-06/08 left out for
-- want of a source: the page each search ranks with, the pages Google shows, Site health with «Mark fixed», and
-- Content ideas with «Plan article».
--
-- * Pages. search-console-run imports Search Console's day × query × page rows beside its day × query ones
--   (search_console_pages). «Ranking page» is the page Google showed most for a tracked keyword; the KPI the design
--   calls «Indexed pages» is «Pages in Google»: pages shown in search in the period. Google offers no count of indexed
--   pages through its API, and this is what can be counted.
-- * Site health. The edge function seo-crawl reads the application's public site every night (and on «Check now»): the
--   sitemap, every page in it, and the links between them. The issues it finds replace the last crawl's: one row per
--   kind (missing or duplicate titles and meta descriptions, missing H1, a page that errors, noindex on a page in the
--   sitemap, a slow page, broken internal links, no sitemap). «Mark fixed» hides an issue until the next crawl: if the
--   crawl still finds it, it comes back marked as such; if not, it is resolved.
-- * Content ideas. Searches Google already shows the site for (Search Console) outside its top ten that nobody tracks
--   yet; «Plan article» puts one in the content plan (seo_content_plan).
--
-- Nothing here is about a person: queries are what Google counted, pages are public addresses.

-- ===========================================================================
-- 1. Search Console's pages
-- ===========================================================================
create table app.search_console_pages (
  day         date not null,
  site_id     uuid not null references app.web_sites (id) on delete cascade,
  query       text not null check (char_length(query) between 1 and 200),
  page        text not null check (page ~ '^/' and char_length(page) <= 300),
  impressions int not null check (impressions >= 0),
  clicks      int not null check (clicks >= 0),
  position    numeric check (position is null or position > 0),
  primary key (day, site_id, query, page)
);
alter table app.search_console_pages enable row level security;
revoke all on app.search_console_pages from public, anon, authenticated;
create index search_console_pages_query on app.search_console_pages (site_id, query, day);

-- one window's day × query × page rows: written over what was there for those days, and a row Google no longer
-- reports for a day in the window is set to nothing (an update, not a delete: the connector refuses deletes)
create function public.worker_search_console_pages(p_site uuid, p_from date, p_to date, p_rows jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int;
begin
  if not exists (select 1 from app.search_console_sites where site_id = p_site and property is not null) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 100000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  with v as (
    select (x ->> 'day')::date d, left(lower(btrim(x ->> 'query')), 200) q, left(x ->> 'page', 300) pg,
           greatest(sum((x ->> 'impressions')::int), 0) i, greatest(sum((x ->> 'clicks')::int), 0) c,
           round(sum((x ->> 'position')::numeric * (x ->> 'impressions')::int) / nullif(sum((x ->> 'impressions')::int), 0), 2) pos
    from jsonb_array_elements(p_rows) x
    where (x ->> 'day')::date between p_from and p_to and coalesce(btrim(x ->> 'query'), '') <> '' and coalesce(x ->> 'page', '') ~ '^/'
    group by 1, 2, 3),
  up as (
    insert into app.search_console_pages (day, site_id, query, page, impressions, clicks, position)
    select d, p_site, q, pg, i, c, pos from v
    on conflict (day, site_id, query, page) do update set impressions = excluded.impressions, clicks = excluded.clicks, position = excluded.position
    returning day, query, page)
  update app.search_console_pages p set impressions = 0, clicks = 0, position = null
  where p.site_id = p_site and p.day between p_from and p_to and p.impressions + p.clicks > 0
    and not exists (select 1 from up where up.day = p.day and up.query = p.query and up.page = p.page);
  select count(*) into n from app.search_console_pages where site_id = p_site and day between p_from and p_to and impressions + clicks > 0;
  return jsonb_build_object('rows', n);
end $fn$;

-- ===========================================================================
-- 2. Site health: crawls and issues
-- ===========================================================================
create table app.seo_crawls (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references app.web_sites (id) on delete cascade,
  finished_at timestamptz not null default now(),
  pages       int not null check (pages >= 0),
  ms          int not null check (ms >= 0),
  error       text check (error is null or error ~ '^[a-z0-9_.:-]{1,60}$')
);
alter table app.seo_crawls enable row level security;
revoke all on app.seo_crawls from public, anon, authenticated;
create index seo_crawls_site on app.seo_crawls (site_id, finished_at desc);

create table app.seo_issues (
  site_id       uuid not null references app.web_sites (id) on delete cascade,
  kind          text not null check (kind in ('sitemap_missing', 'page_error', 'noindex', 'missing_title', 'missing_description', 'slow_page',
                                              'duplicate_title', 'duplicate_description', 'missing_h1', 'broken_link')),
  severity      text not null check (severity in ('high', 'medium')),
  count         int not null check (count >= 1),
  paths         jsonb not null default '[]'::jsonb check (jsonb_typeof(paths) = 'array' and jsonb_array_length(paths) <= 5),
  value         text check (value is null or char_length(value) <= 200),
  ms            int check (ms is null or ms >= 0),
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  fixed_at      timestamptz,
  fixed_by      uuid references app.admins (id) on delete set null,
  reopened_at   timestamptz,
  resolved_at   timestamptz,
  primary key (site_id, kind)
);
alter table app.seo_issues enable row level security;
revoke all on app.seo_issues from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'seo_crawl_worker_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'seo_crawl_worker_secret',
                                'The nightly job''s key to seo-crawl (0072). Generated; nobody types it.');
  end if;
end $$;

create or replace function public.product_secret(p_name text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
  where s.name = p_name and (p_name ~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$'
                             or p_name in ('brevo_api_key', 'mail_worker_secret', 'mail_events_secret', 'search_console_key', 'search_console_worker_secret',
                                           'seo_crawl_worker_secret'))
$fn$;
revoke all on function public.product_secret(text) from public, anon, authenticated;
grant execute on function public.product_secret(text) to service_role;

-- the sites to crawl: an application's public sites (Sentral's own address is not one)
create function public.worker_seo_crawl_sites() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('site_id', s.id, 'hostname', s.hostname) order by s.hostname), '[]'::jsonb)
  from app.web_sites s where s.active and s.product is not null
$fn$;

-- one crawl's verdict. A crawl that could not reach the site, or ran out of time, changes no issue it did not see.
create function public.worker_seo_crawl_result(p_site uuid, p_pages int, p_ms int, p_issues jsonb, p_error text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare x jsonb; v_kinds text[] := '{}'; n_open int := 0; n_back int := 0; n_gone int := 0; v_was timestamptz;
begin
  if not exists (select 1 from app.web_sites where id = p_site) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_error is not null and p_error !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'error'; end if;
  if jsonb_typeof(p_issues) <> 'array' or jsonb_array_length(p_issues) > 20 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'issues'; end if;
  insert into app.seo_crawls (site_id, pages, ms, error) values (p_site, greatest(coalesce(p_pages, 0), 0), greatest(coalesce(p_ms, 0), 0), p_error);
  if p_error = 'unreachable' then return jsonb_build_object('open', null); end if;
  for x in select * from jsonb_array_elements(p_issues) loop
    v_kinds := v_kinds || (x ->> 'kind');
    select fixed_at into v_was from app.seo_issues where site_id = p_site and kind = x ->> 'kind' and resolved_at is null;
    insert into app.seo_issues (site_id, kind, severity, count, paths, value, ms)
    values (p_site, x ->> 'kind', x ->> 'severity', greatest((x ->> 'count')::int, 1),
            coalesce((select jsonb_agg(left(p #>> '{}', 300)) from (select p from jsonb_array_elements(coalesce(x -> 'paths', '[]'::jsonb)) p limit 5) y), '[]'::jsonb),
            left(x ->> 'value', 200), nullif((x ->> 'ms')::int, 0))
    on conflict (site_id, kind) do update set
      severity = excluded.severity, count = excluded.count, paths = excluded.paths, value = excluded.value, ms = excluded.ms, last_seen_at = now(),
      -- marked fixed but still there: it comes back, said so; resolved before and found again: a new first sighting
      reopened_at = case when app.seo_issues.resolved_at is null and app.seo_issues.fixed_at is not null then now()
                         when app.seo_issues.resolved_at is not null then null else app.seo_issues.reopened_at end,
      first_seen_at = case when app.seo_issues.resolved_at is not null then now() else app.seo_issues.first_seen_at end,
      fixed_at = null, fixed_by = null, resolved_at = null;
    n_open := n_open + 1;
    if v_was is not null then n_back := n_back + 1; end if;
  end loop;
  -- what a complete crawl no longer finds is resolved
  if p_error is null then
    update app.seo_issues set resolved_at = now()
    where site_id = p_site and resolved_at is null and not (kind = any (v_kinds));
    get diagnostics n_gone = row_count;
  end if;
  return jsonb_build_object('open', n_open, 'reopened', n_back, 'resolved', n_gone);
end $fn$;

-- «Check now» asks with the person's own token: may they manage the application's SEO?
create function public.seo_crawl_check_ready() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add');
begin
  return jsonb_build_object('me', v_me);
end $fn$;

-- «Mark fixed»: hidden until the next crawl, which agrees (resolved) or brings it back
create function public.seo_issue_fix(p_product text, p_kind text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); v_site app.web_sites := app.product_site(p_product); n int;
begin
  if v_site.id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site'; end if;
  update app.seo_issues set fixed_at = now(), fixed_by = v_me
  where site_id = v_site.id and kind = p_kind and resolved_at is null and fixed_at is null;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('seo.issue_marked_fixed', 'web_site', v_site.id::text, jsonb_build_object('kind', p_kind));
  return jsonb_build_object('kind', p_kind);
end $fn$;

-- the nightly crawl: knock on seo-crawl with the worker key
create function app.seo_crawl_tick() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_key text; v_url text := (select functions_url from app.mail_settings);
begin
  if v_url is null or not exists (select 1 from app.web_sites where active and product is not null) then return jsonb_build_object('called', 0); end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'seo_crawl_worker_secret';
  perform net.http_post(url := v_url || '/functions/v1/seo-crawl', body := '{}'::jsonb,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-worker-key', v_key), timeout_milliseconds := 120000);
  return jsonb_build_object('called', 1);
end $fn$;

insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
values ('seo_crawl', 'jobs.seo_crawl', '13 5 * * *', 'cron', 'app.seo_crawl_tick', true)
on conflict (key) do nothing;
select cron.schedule('platform-seo-crawl', '13 5 * * *', 'select app.run_job(''seo_crawl'')');

-- ===========================================================================
-- 3. Content ideas: the content plan
-- ===========================================================================
create table app.seo_content_plan (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references app.web_sites (id) on delete cascade,
  query      text not null check (char_length(query) between 1 and 200 and query = lower(btrim(query))),
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (site_id, query)
);
alter table app.seo_content_plan enable row level security;
revoke all on app.seo_content_plan from public, anon, authenticated;

create function public.seo_idea_plan(p_product text, p_query text) returns jsonb
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
  insert into app.seo_content_plan (site_id, query, created_by) values (v_site.id, v_q, v_me)
  on conflict (site_id, query) do nothing returning id into v_id;
  if v_id is not null then perform app.log('seo.article_planned', 'web_site', v_site.id::text, jsonb_build_object('query', v_q)); end if;
  return jsonb_build_object('query', v_q, 'planned', true);
end $fn$;

-- ===========================================================================
-- 4. Growth › SEO reads all of it
-- ===========================================================================
create or replace function public.seo_get(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  d int := case when p_days in (7, 30, 90) then p_days else 30 end;
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
            order by sum(s.impressions) desc, s.query limit 6) q), '[]'::jsonb) end);
end $fn$;

-- ===========================================================================
-- grants
-- ===========================================================================
revoke all on function app.seo_crawl_tick() from public, anon, authenticated;
revoke all on function public.seo_crawl_check_ready() from public, anon;
revoke all on function public.seo_issue_fix(text, text) from public, anon;
revoke all on function public.seo_idea_plan(text, text) from public, anon;
grant execute on function public.seo_crawl_check_ready(), public.seo_issue_fix(text, text), public.seo_idea_plan(text, text) to authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.worker_search_console_pages(uuid, date, date, jsonb)', 'public.worker_seo_crawl_sites()',
                           'public.worker_seo_crawl_result(uuid, int, int, jsonb, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
