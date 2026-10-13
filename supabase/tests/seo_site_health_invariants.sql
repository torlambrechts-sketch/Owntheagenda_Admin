-- seo_site_health_invariants.sql — Growth › SEO's pages, Site health and Content ideas (0072): Search Console's pages
-- replace their window, «Ranking page» and «Pages in Google» read them; a crawl opens, keeps and resolves issues, «Mark
-- fixed» hides one until the next crawl agrees or brings it back; ideas are weak searches nobody tracks, and «Plan
-- article» plans one; the worker functions are the service role's, the actions need Campaigns › Add.
\ir _helpers.psql
begin;

create temp table t_site as select (app.product_site('orgpuls')).id id;
-- connected, with a property, as search-console-run leaves it
update app.integration_connections set status = 'connected', connected_at = now() where provider = 'search_console';
insert into app.search_console_sites (site_id, property) values ((select id from t_site), 'sc-domain:orgpuls.com')
on conflict (site_id) do update set property = excluded.property;
delete from app.search_console_daily where site_id = (select id from t_site);
delete from app.search_console_pages where site_id = (select id from t_site);
insert into app.search_console_totals (day, site_id, impressions, clicks, position)
select current_date - g, (select id from t_site), 10, 1, 20 from generate_series(1, 20) g on conflict do nothing;

-- ---------------------------------------------------------------------------
-- pages
select public.worker_search_console_pages((select id from t_site), current_date - 5, current_date - 1, jsonb_build_array(
  jsonb_build_object('day', current_date - 2, 'query', 'Anonym undersøkelse', 'page', '/artikler/anonym', 'impressions', 8, 'clicks', 0, 'position', 15.6),
  jsonb_build_object('day', current_date - 2, 'query', 'anonym undersøkelse', 'page', '/', 'impressions', 2, 'clicks', 0, 'position', 30),
  jsonb_build_object('day', current_date - 3, 'query', 'verneombud plikter', 'page', '/verneombud', 'impressions', 6, 'clicks', 1, 'position', 4),
  jsonb_build_object('day', current_date - 3, 'query', 'x', 'page', 'https://evil.example/', 'impressions', 6, 'clicks', 1, 'position', 4)));
select pg_temp.check((select count(*) from app.search_console_pages where site_id = (select id from t_site)) = 3, 'pages are paths; a full address is not one');
select public.worker_search_console_pages((select id from t_site), current_date - 3, current_date - 3, '[]'::jsonb);
select pg_temp.check((select count(*) from app.search_console_pages where site_id = (select id from t_site) and impressions > 0) = 2
                     and (select impressions from app.search_console_pages where site_id = (select id from t_site) and day = current_date - 3) = 0,
                     'a window replaces its own days only: a row no longer reported is set to nothing, not deleted');
select public.worker_search_console_pages((select id from t_site), current_date - 3, current_date - 3, jsonb_build_array(
  jsonb_build_object('day', current_date - 3, 'query', 'verneombud plikter', 'page', '/verneombud', 'impressions', 6, 'clicks', 1, 'position', 4)));
insert into app.search_console_daily (day, site_id, query, impressions, clicks, position) values
  (current_date - 2, (select id from t_site), 'anonym undersøkelse', 10, 0, 18.4),
  (current_date - 3, (select id from t_site), 'verneombud plikter', 6, 1, 4),
  (current_date - 4, (select id from t_site), 'qps nordic forklart', 5, 0, 18),
  (current_date - 4, (select id from t_site), 'enkel', 1, 0, 40);
insert into app.seo_keywords (site_id, query) values ((select id from t_site), 'verneombud plikter') on conflict do nothing;

select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_g as select public.seo_get('orgpuls', 30) g;
select pg_temp.check((select (g -> 'totals' ->> 'pages')::int = 3 from t_g), 'pages in Google: pages shown in the period');
select pg_temp.check((select x ->> 'page' from t_g, jsonb_array_elements(g -> 'keywords') x where x ->> 'query' = 'verneombud plikter') = '/verneombud',
                     'a tracked keyword''s ranking page is the page Google showed most');

-- ---------------------------------------------------------------------------
-- content ideas
select pg_temp.check((select array_agg(x ->> 'query' order by x ->> 'query') from t_g, jsonb_array_elements(g -> 'ideas') x)
                     = array['anonym undersøkelse', 'qps nordic forklart'],
                     'ideas: seen, outside the top ten, not tracked; a single impression is not one');
select pg_temp.check((select x ->> 'page' from t_g, jsonb_array_elements(g -> 'ideas') x where x ->> 'query' = 'anonym undersøkelse') = '/artikler/anonym',
                     'an idea names the page that ranks today');
select public.seo_idea_plan('orgpuls', '  Anonym   undersøkelse ');
select public.seo_idea_plan('orgpuls', 'anonym undersøkelse');
select pg_temp.check((select count(*) from app.seo_content_plan where site_id = (select id from t_site)) = 1
                     and (select (x ->> 'planned')::boolean from jsonb_array_elements(public.seo_get('orgpuls', 30) -> 'ideas') x where x ->> 'query' = 'anonym undersøkelse'),
                     'Plan article plans it once, and the idea says so');

-- ---------------------------------------------------------------------------
-- site health
select pg_temp.as_nobody();
create temp table t_i as select jsonb_build_array(
  jsonb_build_object('kind', 'missing_description', 'severity', 'high', 'count', 3, 'paths', jsonb_build_array('/pris', '/kom-i-gang', '/bygg')),
  jsonb_build_object('kind', 'broken_link', 'severity', 'medium', 'count', 2, 'paths', jsonb_build_array('/gammel', '/borte'), 'value', '/artikler/a')) i;
select public.worker_seo_crawl_result((select id from t_site), 55, 40000, (select i from t_i), null);
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select jsonb_array_length(public.seo_get('orgpuls', 30) -> 'health' -> 'issues')) = 2
                     and (select (public.seo_get('orgpuls', 30) -> 'health' ->> 'pages')::int) = 55, 'a crawl opens its issues');
select public.seo_issue_fix('orgpuls', 'broken_link');
select public.seo_issue_fix('orgpuls', 'missing_description');
select pg_temp.check((select jsonb_array_length(public.seo_get('orgpuls', 30) -> 'health' -> 'issues')) = 0
                     and (select (public.seo_get('orgpuls', 30) -> 'health' ->> 'awaiting_check')::int) = 2, 'Mark fixed hides them until the next crawl');
select pg_temp.expect_error($$select public.seo_issue_fix('orgpuls', 'broken_link')$$, 'not_found', 'an issue already marked fixed cannot be marked again');
-- the next crawl still finds the description issue, not the broken links
select pg_temp.as_nobody();
select public.worker_seo_crawl_result((select id from t_site), 55, 40000, jsonb_build_array((select i -> 0 from t_i)), null);
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select (x ->> 'reopened')::boolean from jsonb_array_elements(public.seo_get('orgpuls', 30) -> 'health' -> 'issues') x where x ->> 'kind' = 'missing_description')
                     and (select resolved_at is not null from app.seo_issues where site_id = (select id from t_site) and kind = 'broken_link'),
                     'the crawl brings back what is still there and resolves what is gone');
-- an unreachable site changes nothing; a partial crawl resolves nothing
select pg_temp.as_nobody();
select public.worker_seo_crawl_result((select id from t_site), 0, 15000, '[]'::jsonb, 'unreachable');
select public.worker_seo_crawl_result((select id from t_site), 10, 110000, '[]'::jsonb, 'partial');
select pg_temp.check((select resolved_at is null from app.seo_issues where site_id = (select id from t_site) and kind = 'missing_description'),
                     'an unreachable or partial crawl resolves nothing it did not see');
select pg_temp.expect_error($$select public.worker_seo_crawl_result((select id from t_site), 1, 1, '[{"kind":"made_up","severity":"high","count":1}]'::jsonb, null)$$,
                            'new row for relation "seo_issues" violates check constraint "seo_issues_kind_check"', 'only known kinds');

-- ---------------------------------------------------------------------------
-- rights
select pg_temp.as_staff('tor@orgpuls.no', 'aal1');
select pg_temp.expect_error($$select public.seo_idea_plan('orgpuls', 'x')$$, 'not_signed_in', 'no second factor, no plan');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_seo_crawl_result(uuid, int, int, jsonb, text)', 'execute')
                     and not has_function_privilege('authenticated', 'public.worker_search_console_pages(uuid, date, date, jsonb)', 'execute')
                     and has_function_privilege('service_role', 'public.worker_seo_crawl_sites()', 'execute')
                     and not has_function_privilege('anon', 'public.seo_issue_fix(text, text, uuid)', 'execute'),
                     'the worker functions are the service role''s alone');
select pg_temp.check(public.product_secret('seo_crawl_worker_secret') is not null and exists (select 1 from cron.job where jobname = 'platform-seo-crawl'),
                     'the nightly crawl has its key and its schedule');

rollback;
