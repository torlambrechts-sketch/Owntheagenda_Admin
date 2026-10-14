-- search_console_breakdown_invariants.sql — what Search Console reports beyond the searches it names (0091): the import
-- keeps each page's own figures and the countries and devices, replacing the days the totals report and dropping what is
-- not a path, a country or a device; a call without them (the function deployed before) leaves them as they were. A
-- page's figures include its unnamed searches: «Pages in Google», the page card, a change's before and after and pages
-- losing clicks read them; Keywords learns how much of the totals its list accounts for; SEO › Overview shows the
-- countries (ten and the rest) and the devices. The tables are no client's; the import is the service role's.
\ir _helpers.psql
begin;

create temp table t_site as select (app.product_site('orgpuls')).id id;
update app.integration_connections set status = 'connected', connected_at = now() where provider = 'search_console';
insert into app.search_console_sites (site_id, property) values ((select id from t_site), 'sc-domain:orgpuls.com')
on conflict (site_id) do update set property = excluded.property;
delete from app.search_console_totals where site_id = (select id from t_site);
delete from app.search_console_daily where site_id = (select id from t_site);
delete from app.search_console_pages where site_id = (select id from t_site);
delete from app.search_console_page_totals where site_id = (select id from t_site);
delete from app.search_console_segments where site_id = (select id from t_site);

-- ---------------------------------------------------------------------------
-- the import
create temp table t_r as select public.worker_search_console_import((select id from t_site),
  jsonb_build_array(jsonb_build_object('day', current_date - 3, 'impressions', 20, 'clicks', 3, 'position', 12),
                    jsonb_build_object('day', current_date - 2, 'impressions', 10, 'clicks', 1, 'position', 15)),
  jsonb_build_array(jsonb_build_object('day', current_date - 3, 'query', 'anonym medarbeiderundersøkelse', 'impressions', 8, 'clicks', 0, 'position', 9),
                    jsonb_build_object('day', current_date - 2, 'query', 'verneombud', 'impressions', 4, 'clicks', 0, 'position', 30)),
  jsonb_build_array(jsonb_build_object('day', current_date - 3, 'page', '/artikler/anonym', 'impressions', 12, 'clicks', 2, 'position', 9),
                    jsonb_build_object('day', current_date - 3, 'page', '/lovkrav', 'impressions', 8, 'clicks', 1, 'position', 20),
                    jsonb_build_object('day', current_date - 2, 'page', '/artikler/anonym', 'impressions', 10, 'clicks', 1, 'position', 15),
                    jsonb_build_object('day', current_date - 2, 'page', 'evil.example/x', 'impressions', 5, 'clicks', 5, 'position', 1)),
  jsonb_build_array(jsonb_build_object('day', current_date - 3, 'key', 'nor', 'impressions', 15, 'clicks', 3, 'position', 10),
                    jsonb_build_object('day', current_date - 3, 'key', 'swe', 'impressions', 4, 'clicks', 0, 'position', 20),
                    jsonb_build_object('day', current_date - 3, 'key', 'GBR', 'impressions', 1, 'clicks', 0, 'position', 40),
                    jsonb_build_object('day', current_date - 3, 'key', 'xx', 'impressions', 1, 'clicks', 0, 'position', 40),
                    jsonb_build_object('day', current_date - 2, 'key', 'nor', 'impressions', 10, 'clicks', 1, 'position', 15)),
  jsonb_build_array(jsonb_build_object('day', current_date - 3, 'key', 'MOBILE', 'impressions', 12, 'clicks', 2, 'position', 11),
                    jsonb_build_object('day', current_date - 3, 'key', 'desktop', 'impressions', 8, 'clicks', 1, 'position', 14),
                    jsonb_build_object('day', current_date - 3, 'key', 'smartwatch', 'impressions', 3, 'clicks', 0, 'position', 5),
                    jsonb_build_object('day', current_date - 2, 'key', 'desktop', 'impressions', 10, 'clicks', 1, 'position', 15))) r;
select pg_temp.check((select r = '{"totals": 2, "rows": 2, "pages": 3, "countries": 4, "devices": 3}'::jsonb from t_r),
                     'the import keeps the pages, countries and devices with the totals and the searches');
select pg_temp.check(not exists (select 1 from app.search_console_page_totals where site_id = (select id from t_site) and page !~ '^/'),
                     'a page is a path: a full address is not one');
select pg_temp.check((select array_agg(key order by key) from app.search_console_segments where site_id = (select id from t_site) and kind = 'country' and day = current_date - 3)
                       = array['gbr', 'nor', 'swe']
                     and (select array_agg(key order by key) from app.search_console_segments where site_id = (select id from t_site) and kind = 'device' and day = current_date - 3)
                       = array['desktop', 'mobile'],
                     'a country is Google''s three letters and a device one of its three, written small; anything else is left out');

-- a window replaces the days its totals report, and only those
select public.worker_search_console_import((select id from t_site),
  jsonb_build_array(jsonb_build_object('day', current_date - 2, 'impressions', 10, 'clicks', 1, 'position', 15)),
  jsonb_build_array(jsonb_build_object('day', current_date - 2, 'query', 'verneombud', 'impressions', 4, 'clicks', 0, 'position', 30)),
  jsonb_build_array(jsonb_build_object('day', current_date - 2, 'page', '/lovkrav', 'impressions', 10, 'clicks', 1, 'position', 15)),
  jsonb_build_array(jsonb_build_object('day', current_date - 2, 'key', 'nor', 'impressions', 10, 'clicks', 1, 'position', 15)),
  jsonb_build_array(jsonb_build_object('day', current_date - 2, 'key', 'desktop', 'impressions', 10, 'clicks', 1, 'position', 15)));
select pg_temp.check(not exists (select 1 from app.search_console_page_totals where site_id = (select id from t_site) and day = current_date - 2 and page = '/artikler/anonym')
                     and (select impressions from app.search_console_page_totals where site_id = (select id from t_site) and day = current_date - 2 and page = '/lovkrav') = 10
                     and (select count(*) from app.search_console_page_totals where site_id = (select id from t_site) and day = current_date - 3) = 2,
                     'a window replaces its own days, and leaves the others as they were');

-- the function deployed before 0091 sends no pages, countries or devices: their days stay as they were
select public.worker_search_console_import((select id from t_site),
  jsonb_build_array(jsonb_build_object('day', current_date - 3, 'impressions', 20, 'clicks', 3, 'position', 12)),
  jsonb_build_array(jsonb_build_object('day', current_date - 3, 'query', 'anonym medarbeiderundersøkelse', 'impressions', 8, 'clicks', 0, 'position', 9)));
select pg_temp.check((select count(*) from app.search_console_page_totals where site_id = (select id from t_site) and day = current_date - 3) = 2
                     and (select count(*) from app.search_console_segments where site_id = (select id from t_site) and day = current_date - 3) = 5,
                     'an import without them leaves them as they were');
select pg_temp.expect_error(format($$select public.worker_search_console_import(%L, '[]', '[]', '{}')$$, (select id from t_site)), 'invalid',
                            'pages that are not a list are refused');

-- what the readers below find: one named search on a page, a country list longer than ten, a period before, a page losing clicks
insert into app.search_console_pages (day, site_id, query, page, impressions, clicks, position)
values (current_date - 3, (select id from t_site), 'anonym medarbeiderundersøkelse', '/artikler/anonym', 8, 0, 9);
insert into app.search_console_segments (day, site_id, kind, key, impressions, clicks, position)
select current_date - 4, (select id from t_site), 'country', 'c' || chr(96 + g) || chr(96 + g), 1, 0, 50 from generate_series(1, 11) g;
insert into app.search_console_segments (day, site_id, kind, key, impressions, clicks, position)
values (current_date - 40, (select id from t_site), 'country', 'nor', 5, 1, 12);
insert into app.search_console_page_totals (day, site_id, page, impressions, clicks, position) values
  (current_date - 100, (select id from t_site), '/forfall', 100, 12, 4),
  (current_date - 10, (select id from t_site), '/forfall', 50, 2, 9);

-- ---------------------------------------------------------------------------
-- the readers
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_g as select public.seo_get('orgpuls', 30) g;
select pg_temp.check((select (g -> 'totals' ->> 'impressions')::int = 30 and (g -> 'totals' ->> 'named_impressions')::int = 12
                             and (g -> 'totals' ->> 'clicks')::int = 4 and (g -> 'totals' ->> 'named_clicks')::int = 0 from t_g),
                     'Keywords learns how much of the totals its named searches account for');
select pg_temp.check((select (g -> 'totals' ->> 'pages')::int from t_g) = 3,
                     '«Pages in Google» counts a page shown only for searches Google does not name');

create temp table t_p as select public.growth_pages('orgpuls', 30, null, null, null, null, '/artikler/anonym') g;
select pg_temp.check((select g -> 'page' -> 'google' = '{"days": 30, "impressions": 12, "clicks": 2, "position": 9.0, "named_impressions": 8, "named_clicks": 0}'::jsonb from t_p),
                     'the page card shows the page''s own figures from Google, and what its named searches account for');

create temp table t_o as select public.seo_overview('orgpuls') -> 'segments' g;
select pg_temp.check((select (g ->> 'imported')::boolean and jsonb_array_length(g -> 'countries') = 10
                             and g -> 'countries' -> 0 = '{"key": "nor", "impressions": 25, "clicks": 4, "position": 12.0, "impressions_prev": 5}'::jsonb
                             and g -> 'countries_other' = '{"countries": 4, "impressions": 4, "clicks": 0}'::jsonb from t_o),
                     'SEO › Overview: the ten countries seen most, each against the 30 days before, and the rest together');
select pg_temp.check((select array(select x ->> 'key' from jsonb_array_elements(g -> 'devices') x) = array['desktop', 'mobile']
                             and (g -> 'devices' -> 0 ->> 'clicks')::int = 2 and (g -> 'devices' -> 1 ->> 'impressions')::int = 12 from t_o),
                     'and the devices, the most seen first');

select public.seo_change_add('orgpuls', '/lovkrav', 'content', null);
select pg_temp.check((select (x -> 'before' ->> 'impressions')::int = 18 and (x -> 'before' ->> 'clicks')::int = 2
                      from jsonb_array_elements(public.seo_changes_get('orgpuls') -> 'changes') x where x ->> 'path' = '/lovkrav'),
                     'a page change''s before counts the page''s own figures, unnamed searches included');

select pg_temp.check((select (x ->> 'clicks')::int = 2 and (x ->> 'clicks_before')::int = 12
                      from jsonb_array_elements(public.seo_opportunities('orgpuls') -> 'decay') x where x ->> 'path' = '/forfall'),
                     'a page losing clicks is found from its own figures');

-- before a site's pages have their own figures, its pages are read from the searches as before
select pg_temp.check(not app.search_console_page_totals_ready((select id from app.web_sites where hostname = 'empvibe.com'))
                     and app.search_console_page_totals_ready((select id from t_site)),
                     'a site without its pages'' own figures reads them from the searches, as before');
select pg_temp.check((public.seo_get('orgpuls', 30, (select id from app.web_sites where hostname = 'empvibe.com')) -> 'totals') = 'null'::jsonb
                     and (public.seo_overview('orgpuls', (select id from app.web_sites where hostname = 'empvibe.com')) -> 'segments') = 'null'::jsonb,
                     'a site with no property shows no figures, nor countries and devices');
select pg_temp.as_nobody();

-- ---------------------------------------------------------------------------
-- no client's tables; the import is the service role's
select pg_temp.check((select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                      where n.nspname = 'app' and c.relname in ('search_console_page_totals', 'search_console_segments'))
                     and not exists (select 1 from pg_policies where schemaname = 'app' and tablename in ('search_console_page_totals', 'search_console_segments'))
                     and not has_table_privilege('authenticated', 'app.search_console_page_totals', 'select')
                     and not has_table_privilege('anon', 'app.search_console_segments', 'select'),
                     'the tables have RLS, no policy and no grant');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_search_console_import(uuid, jsonb, jsonb, jsonb, jsonb, jsonb)', 'execute')
                     and has_function_privilege('service_role', 'public.worker_search_console_import(uuid, jsonb, jsonb, jsonb, jsonb, jsonb)', 'execute')
                     and not has_function_privilege('authenticated', 'app.search_console_segments_put(uuid, date[], text, jsonb)', 'execute')
                     and not has_function_privilege('authenticated', 'app.search_console_page_totals_ready(uuid)', 'execute'),
                     'the import is the service role''s; the helpers are nobody''s');

rollback;
