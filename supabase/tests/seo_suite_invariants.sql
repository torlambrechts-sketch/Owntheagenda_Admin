-- seo_suite_invariants.sql — Growth › SEO, the suite (0074): its tables are closed and its workers the service role's;
-- every read needs a reports right and the second factor; URL Inspection keeps a verdict per page and notices a page that
-- drops out; the crawl's link graph is replaced whole and yields suggestions, orphans and hubs; the content plan moves
-- through its stages and logs «Published» once; the change log and the link decisions write what they say; the alert
-- rules are checked and an alert reaches the right people once, on the rule's channels; a notification may link to
-- Growth › SEO › Alerts and never off the site.
\ir _helpers.psql
begin;

create or replace function pg_temp.expect_detail(p_sql text, p_message text, p_detail text, p_label text) returns void language plpgsql as $$
declare v_msg text; v_det text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
    if v_msg = p_message and coalesce(v_det, '') = coalesce(p_detail, '') then raise notice 'ok %', p_label; return; end if;
    raise exception 'FAIL %: expected «%» («%»), got «%» («%»)', p_label, p_message, p_detail, v_msg, v_det;
  end;
  raise exception 'FAIL %: expected «%», but it succeeded', p_label, p_message;
end $$;
create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- closed
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
    and c.relname in ('seo_index', 'seo_links', 'seo_mentions', 'seo_changes', 'seo_link_decisions', 'seo_alert_rules', 'seo_alerts', 'seo_alert_deliveries')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the suite''s tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relname in
  ('seo_index', 'seo_links', 'seo_mentions', 'seo_changes', 'seo_link_decisions', 'seo_alert_rules', 'seo_alerts', 'seo_alert_deliveries')) = 8, 'all eight exist');
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute') and has_function_privilege('service_role', f::regprocedure, 'execute'),
                     'only the service role runs ' || f)
from unnest(array['public.worker_seo_index_targets()', 'public.worker_seo_index_result(uuid, jsonb)', 'public.worker_seo_crawl_sites()',
                  'public.worker_seo_links(uuid, text, jsonb, jsonb)', 'public.worker_seo_alert_mail_claim(int)',
                  'public.worker_seo_alert_mail_done(uuid, uuid, boolean)']) f;
select pg_temp.check(not has_function_privilege('authenticated', 'app.seo_alerts_tick()', 'execute')
                     and not has_function_privilege('authenticated', 'app.seo_alert_raise(uuid, text, text, text, jsonb, interval)', 'execute'),
                     'nobody signed in raises an alert by hand');

-- ---------------------------------------------------------------------------
-- a site of its own for Orgpuls, connected to Search Console, with 120 days of figures
update app.web_sites set product = null where product = 'orgpuls';
insert into app.web_sites (hostname, product) values ('qa-seo.example', 'orgpuls');
create temp table t_site as select id from app.web_sites where hostname = 'qa-seo.example';
update app.integration_connections set status = 'connected' where provider = 'search_console';
insert into app.search_console_sites (site_id, property, last_day) values ((select id from t_site), 'sc-domain:qa-seo.example', current_date - 2);
-- «malen» on two pages (split), «lovkrav» on one; «gammel» lost its clicks; «langt unna» is on page three
insert into app.search_console_daily (day, site_id, query, impressions, clicks, position)
select current_date - g, (select id from t_site), q, i, c, p
from generate_series(1, 120) g,
     (values ('malen', 100, 3, 5.0), ('lovkrav', 50, 15, 1.5), ('gammel', 40, 2, 4.0), ('langt unna', 10, 0, 31.0)) v(q, i, c, p)
where not (q = 'gammel' and g <= 28);
insert into app.search_console_pages (day, site_id, query, page, impressions, clicks, position)
select d.day, d.site_id, d.query, x.page, (d.impressions * x.share)::int, (d.clicks * x.share)::int, d.position
from app.search_console_daily d
join (values ('malen', '/mal', 0.6), ('malen', '/mal-2024', 0.4), ('lovkrav', '/lovkrav', 1.0), ('gammel', '/gammel', 1.0), ('langt unna', '/', 1.0)) x(q, page, share) on x.q = d.query
where d.site_id = (select id from t_site);
insert into app.search_console_totals (day, site_id, impressions, clicks, position)
select day, site_id, sum(impressions) * 2, sum(clicks) * 2, 5 from app.search_console_daily where site_id = (select id from t_site) group by 1, 2;
insert into app.seo_keywords (site_id, query) values ((select id from t_site), 'malen'), ((select id from t_site), 'lovkrav'), ((select id from t_site), 'ingen data');

-- ---------------------------------------------------------------------------
-- reads: a reports right and the second factor
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format($$select public.%s('orgpuls')$$, f), 'forbidden', f || ' needs a reports right')
from unnest(array['seo_overview', 'seo_opportunities', 'seo_clusters', 'seo_plan_get', 'seo_links_get', 'seo_changes_get', 'seo_alerts_get']) f;
select pg_temp.as_staff('sara@orgpuls.no', 'aal1');
select pg_temp.expect_error($$select public.seo_overview('orgpuls')$$, 'not_signed_in', 'without the second factor nothing is read');
select pg_temp.as_staff('sara@orgpuls.no');
create temp table t_ov as select public.seo_overview('orgpuls') v;
-- the last 30 days are the 29 reported (yesterday back), «gammel» only on the oldest of them; the 30 before are whole
select pg_temp.check((select (v -> 'clicks' ->> 'now')::int = 2 * (29 * 18 + 2) and (v -> 'clicks' ->> 'prev')::int = 2 * 30 * 20 from t_ov),
                     'organic clicks: Search Console''s day totals, the last 30 days and the 30 before');
select pg_temp.check((select (v -> 'clicks' ->> 'named')::int = 29 * 18 + 2 from t_ov), 'and the clicks Search Console names a search for');
select pg_temp.check((select (v ->> 'attributed')::boolean = (exists (select 1 from app.account_products ap where ap.product = 'orgpuls' and app.has_source(ap.attribution)))
                             and ((v -> 'mrr_won') is null or jsonb_typeof(v -> 'mrr_won') = 'null') = not (v ->> 'attributed')::boolean from t_ov),
                     'organic revenue only where the product reports an account''s source');
select pg_temp.check(app.has_source('{"first_touch": {"utm_source": "google"}}') and app.has_source('{"referrer": "www.google.com"}') and not app.has_source('{"heard": "venn"}')
                     and not app.has_source(null), 'how a person says they heard is not a source');
select pg_temp.check((select jsonb_array_length(v -> 'keywords') = 3 from t_ov), 'the tracked keywords come with their figures for visibility');

create temp table t_op as select public.seo_opportunities('orgpuls') v;
select pg_temp.check((select v -> 'queries' @> '[{"query": "malen", "page": "/mal", "tracked": true}]' and v -> 'queries' @> '[{"query": "langt unna", "position": 31.0}]' from t_op),
                     'the searches of the last 28 days, with the page Google showed most');
select pg_temp.check((select v -> 'cannibal' @> '[{"query": "malen"}]' and not v -> 'cannibal' @> '[{"query": "lovkrav"}]' from t_op),
                     'a search split over two pages is cannibalization');
select pg_temp.check((select v -> 'decay' @> '[{"path": "/gammel", "clicks": 0, "query": "gammel"}]' and (v -> 'decay' -> 0 ->> 'clicks_before')::int >= 10 from t_op),
                     'a page that lost its clicks against three months before is decay');
select pg_temp.check((select (v -> 'econ') ? 'clicks' and (v -> 'econ') ? 'paying_now' from t_op), 'the economics travel with the opportunities');

create temp table t_cl as select public.seo_clusters('orgpuls') v;
select pg_temp.check((select jsonb_array_length(v -> 'clusters') = 2 and (v ->> 'unclustered')::int = 1 from t_cl),
                     'a topic per main page; a tracked keyword without a page is counted, not placed');
select pg_temp.check((select c -> 'pages' @> '[{"path": "/mal"}, {"path": "/mal-2024"}]' and jsonb_array_length(c -> 'keywords' -> 0 -> 'weeks') = 12
                      from t_cl, jsonb_array_elements(v -> 'clusters') c where c ->> 'main' = '/mal'), 'a topic has its pages and twelve weeks per keyword');

-- ---------------------------------------------------------------------------
-- URL Inspection: targets once a whole crawl named the origin; a verdict per page; a page out of the index is noticed
select pg_temp.as_service();
insert into app.seo_crawls (site_id, pages, ms) values ((select id from t_site), 3, 100);
insert into app.seo_pages (site_id, path, status, ms) values ((select id from t_site), '/', 200, 100), ((select id from t_site), '/mal', 200, 100),
  ((select id from t_site), '/lovkrav', 200, 100), ((select id from t_site), '/ensom', 200, 100), ((select id from t_site), '/mal-2024', 200, 100);
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.worker_seo_index_targets()) t where t ->> 'site_id' = (select id::text from t_site)),
                     'no inspection before a crawl knows the site''s address');
select pg_temp.expect_detail($$select public.worker_seo_links((select id from t_site), 'javascript:alert(1)', '[]', '[]')$$, 'invalid', 'origin', 'an origin is a plain address');
select public.worker_seo_links((select id from t_site), 'https://www.qa-seo.example',
  '[{"from": "/", "to": "/mal", "anchor": "Mal"}, {"from": "/", "to": "/lovkrav", "anchor": "Lovkrav"}, {"from": "/mal", "to": "/", "anchor": "Hjem"},
    {"from": "/lovkrav", "to": "/", "anchor": "Hjem"}, {"from": "/mal-2024", "to": "/", "anchor": "Hjem"}, {"from": "/mal", "to": "/mal", "anchor": "selv"},
    {"from": "/mal", "to": "/lovkrav", "anchor": null}, {"from": "/mal", "to": "/lovkrav", "anchor": "lovkravet"}]',
  '[{"path": "/mal-2024", "term": "malen"}, {"path": "/lovkrav", "term": "malen"}, {"path": "/mal", "term": "lovkrav"}, {"path": "/ensom", "term": "Lovkrav"}]');
select pg_temp.check((select count(*) from app.seo_links where site_id = (select id from t_site)) = 6, 'a link to itself is dropped and one row is kept per pair');
select pg_temp.check((select anchor from app.seo_links where site_id = (select id from t_site) and from_path = '/mal' and to_path = '/lovkrav') = 'lovkravet',
                     'and the pair keeps an anchor that says something');
select pg_temp.check((select t -> 'paths' ?& array['/', '/mal', '/lovkrav', '/ensom'] and t ->> 'origin' = 'https://www.qa-seo.example' and t ->> 'property' = 'sc-domain:qa-seo.example'
                      from jsonb_array_elements(public.worker_seo_index_targets()) t where t ->> 'site_id' = (select id::text from t_site)), 'then every crawled page is a target');
select public.worker_seo_index_result((select id from t_site),
  '[{"path": "/", "coverage": "indexed"}, {"path": "/mal", "coverage": "indexed", "last_crawl_at": "2026-10-01T10:00:00Z"}, {"path": "/lovkrav", "coverage": "indexed"},
    {"path": "/ensom", "coverage": "crawled_not_indexed"}, {"path": "/mal-2024", "coverage": "duplicate"}, {"path": "nope", "coverage": "indexed"}, {"path": "/x", "coverage": "made_up"}]');
select pg_temp.check((select count(*) from app.seo_index where site_id = (select id from t_site)) = 5, 'a verdict per page; a bad path or bucket is ignored');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.worker_seo_index_targets()) t where t ->> 'site_id' = (select id::text from t_site)),
                     'a page inspected today is not asked again');
select public.worker_seo_index_result((select id from t_site), '[{"path": "/lovkrav", "coverage": "not_found"}]');
select pg_temp.check((select dropped_at is not null and coverage = 'not_found' from app.seo_index where site_id = (select id from t_site) and path = '/lovkrav'),
                     'an indexed page that is not any more has dropped out');
select pg_temp.check((select state = 'warning' and (info ->> 'dropped')::int = 1 from app.growth_sync_log where source = 'url_inspection' and site_id = (select id from t_site) order by id desc limit 1),
                     'the sync log says so');

-- ---------------------------------------------------------------------------
-- Internal links, the overview's coverage
select pg_temp.as_staff('sara@orgpuls.no');
create temp table t_ln as select public.seo_links_get('orgpuls') v;
select pg_temp.check((select v -> 'suggestions' @> '[{"from": "/mal-2024", "anchor": "malen", "to": "/mal", "decision": null}]'
                             and v -> 'suggestions' @> '[{"from": "/ensom", "anchor": "lovkrav", "to": "/lovkrav"}, {"from": "/lovkrav", "anchor": "malen", "to": "/mal"}]'
                             and not v -> 'suggestions' @> '[{"from": "/mal", "to": "/lovkrav"}]' from t_ln),
                     'a page that mentions a search without linking to its main page is a suggestion; a page that links already is not');
select pg_temp.check((select v -> 'orphans' @> '[{"path": "/ensom"}, {"path": "/mal-2024"}]' and not v -> 'orphans' @> '[{"path": "/mal"}]' from t_ln),
                     'a crawled page no other page links to is an orphan');
select pg_temp.check((select v -> 'hubs' -> 0 @> '{"path": "/", "inlinks": 3, "anchor": "Hjem"}' from t_ln), 'the most linked page, with its usual anchor');
select pg_temp.check((select (v -> 'index' ->> 'indexed')::int = 2 and (v -> 'index' ->> 'pages')::int = 5 and (v -> 'index' ->> 'dropped')::int = 1
                      from (select public.seo_overview('orgpuls') v) x), 'index coverage on the overview');

-- ---------------------------------------------------------------------------
-- the content plan
select pg_temp.expect_error($$select public.seo_plan_add('orgpuls', 'malen', 'cannibal', '/mal')$$, 'forbidden', 'planning needs Campaigns › Add');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail($$select public.seo_plan_add('orgpuls', 'malen', 'guess', '/mal')$$, 'invalid', 'kind', 'a kind of work from the list');
select pg_temp.expect_detail($$select public.seo_plan_add('orgpuls', 'malen', 'gap', 'https://evil.example/')$$, 'invalid', 'path', 'a page is a path on the site');
create temp table t_p as select (public.seo_plan_add('orgpuls', '  Langt   Unna ', 'gap') ->> 'id')::uuid id;
select pg_temp.check((select query = 'langt unna' and stage = 'idea' and owner_id = (select id from app.admins where email = 'emma@orgpuls.no') from app.seo_content_plan where id = (select id from t_p)),
                     'an item: the search as Search Console writes it, an idea, owned by who planned it');
select pg_temp.check((public.seo_plan_add('orgpuls', 'langt unna', 'striking') ->> 'id')::uuid = (select id from t_p), 'a search is planned once');
select public.seo_plan_move((select id from t_p), 'writing');
select pg_temp.check((public.seo_plan_move((select id from t_p), 'published') ->> 'logged')::boolean, 'reaching «Published» logs the change');
select public.seo_plan_move((select id from t_p), 'measuring');
select public.seo_plan_move((select id from t_p), 'writing');
select public.seo_plan_move((select id from t_p), 'published');
select pg_temp.check((select count(*) = 1 and bool_and(kind = 'new_page' and path is null and query = 'langt unna' and source = 'plan')
                      from app.seo_changes where site_id = (select id from t_site) and source = 'plan'),
                     'once, as a new page known by its search until it has an address');
select pg_temp.expect_detail($$select public.seo_plan_move((select id from t_p), 'done')$$, 'invalid', 'stage', 'a stage from the four');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check((select i -> 'measured' is null or jsonb_typeof(i -> 'measured') = 'null' from jsonb_array_elements(public.seo_plan_get('orgpuls') -> 'items') i
                      where i ->> 'id' = (select id::text from t_p)), 'nothing is measured before 28 days are reported');
select pg_temp.check((select (b -> 'brief' ->> 'id')::uuid = (select id from t_p) and jsonb_typeof(b -> 'brief' -> 'terms') = 'array'
                      from (select public.seo_plan_get('orgpuls', (select id from t_p)) b) x), 'the brief of an item');
-- an item published 40 days ago is measured on the page's figures
update app.seo_content_plan set path = '/mal', published_at = now() - interval '40 days', stage = 'measuring' where id = (select id from t_p);
select pg_temp.check((select (i -> 'measured' ->> 'clicks_before')::int > 0 and (i -> 'measured' ->> 'position_after')::numeric = 5.0
                      from jsonb_array_elements(public.seo_plan_get('orgpuls') -> 'items') i where i ->> 'id' = (select id::text from t_p)),
                     '28 days after, the page''s clicks and position before and after');

-- ---------------------------------------------------------------------------
-- the change log and the link decisions
select pg_temp.expect_error($$select public.seo_change_add('orgpuls', '/mal', 'content', 'x')$$, 'forbidden', 'logging needs Campaigns › Add');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail($$select public.seo_change_add('orgpuls', 'mal', 'content', 'x')$$, 'invalid', 'path', 'a change is on a page');
select pg_temp.expect_detail($$select public.seo_change_add('orgpuls', '/mal', 'magic', 'x')$$, 'invalid', 'kind', 'a kind from the list');
select pg_temp.expect_detail(format($$select public.seo_change_add('orgpuls', '/mal', 'content', %L)$$, repeat('x', 201)), 'invalid', 'note', 'a note of 200 characters at most');
select public.seo_change_add('orgpuls', '/mal', 'schema', '  FAQ  ');
select pg_temp.check(exists (select 1 from app.seo_changes where site_id = (select id from t_site) and path = '/mal' and kind = 'schema' and note = 'FAQ'
                             and day = (now() at time zone 'Europe/Oslo')::date and source = 'manual'), 'a change is logged today, as typed');
select public.seo_link_decide('orgpuls', '/mal-2024', '/mal', 'malen', 'skipped');
select public.seo_link_decide('orgpuls', '/ensom', '/lovkrav', 'lovkrav', 'added');
select public.seo_link_decide('orgpuls', '/ensom', '/lovkrav', 'lovkrav', 'added');
select pg_temp.check((select count(*) from app.seo_changes where site_id = (select id from t_site) and source = 'link') = 1
                     and exists (select 1 from app.seo_changes where source = 'link' and path = '/ensom' and kind = 'links' and note = '«lovkrav» → /lovkrav'),
                     '«Add link» logs the change on the page the link goes on, once; «Skip» logs nothing');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check((select v -> 'suggestions' @> '[{"from": "/mal-2024", "decision": "skipped"}, {"from": "/ensom", "decision": "added"}]' from (select public.seo_links_get('orgpuls') v) x),
                     'a decided suggestion says what was decided until the crawl finds the link');
select pg_temp.check((select jsonb_array_length(v -> 'changes') = 3 and jsonb_array_length(v -> 'daily') >= 55 and v -> 'pages' @> '["/", "/mal"]'
                      from (select public.seo_changes_get('orgpuls') v) x), 'the change log, the clicks per day and the pages to pick from');

-- ---------------------------------------------------------------------------
-- alerts
select pg_temp.expect_error($$select public.seo_alert_rule_set('orgpuls', 'rank', false, '{app}')$$, 'forbidden', 'a rule needs Campaigns › Edit others''');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail($$select public.seo_alert_rule_set('orgpuls', 'snippet', true, '{app}')$$, 'invalid', 'rule', 'only the rules with a source');
select pg_temp.expect_detail($$select public.seo_alert_rule_set('orgpuls', 'rank', true, '{app,slack}')$$, 'invalid', 'channels', 'channels are the app and email');
select public.seo_alert_rule_set('orgpuls', 'traffic', false, '{app}');
select pg_temp.check((select r -> 'enabled' = 'false' and r -> 'channels' = '["app"]' from jsonb_array_elements(public.seo_alerts_get('orgpuls') -> 'rules') r where r ->> 'rule' = 'traffic')
                     and (select r -> 'enabled' = 'true' and r -> 'channels' = '["app", "email"]' from jsonb_array_elements(public.seo_alerts_get('orgpuls') -> 'rules') r where r ->> 'rule' = 'rank'),
                     'a rule nobody touched is on in the app and by email');
-- email can go out: a connected provider and a verified sender
update app.integration_connections set status = 'connected' where provider = 'email';
insert into app.sender_domains (domain, stream, sends_here, from_name, from_local, spf_ok, dkim_ok, dmarc_policy, verified_at, product)
values ('seoqa.example', 'transactional', true, 'Orgpuls', 'varsel', true, true, 'none', now(), 'orgpuls');
select pg_temp.check(app.mail_ready(), 'mail is ready for the test');
-- a ranking drop: «lovkrav» was 1,5 and is 5,5 in the last seven reported days
update app.search_console_daily set position = 5.5 where site_id = (select id from t_site) and query = 'lovkrav' and day > current_date - 8;
select app.seo_alerts_tick();
select pg_temp.check((select count(*) from app.seo_alerts where site_id = (select id from t_site)) = 2, 'the hourly check raises the ranking drop and the page out of the index');
select app.seo_alerts_tick();
select pg_temp.check((select count(*) from app.seo_alerts where site_id = (select id from t_site)) = 2, 'and not again');
create temp table t_al as select id, rule, params from app.seo_alerts where site_id = (select id from t_site);
select pg_temp.check((select params @> '{"query": "lovkrav", "from": 1.5, "to": 5.5}' from t_al where rule = 'rank')
                     and (select params @> '{"path": "/lovkrav", "coverage": "not_found"}' from t_al where rule = 'deindex'), 'each with its figures');
select pg_temp.check((select array_agg(distinct a.email order by a.email) from app.notifications n join app.admins a on a.id = n.staff_id where n.key = 'seo.alert_rank')
                     = (select array_agg(a.email order by a.email) from app.admins a where a.active and not a.is_sample
                          and (app.can_for(a.id, 'global', 'reports_others') or app.can_for(a.id, 'campaigns', 'reports_others'))),
                     'everybody who may read Growth''s reports hears it in the app');
select pg_temp.check((select bool_and(route = '/growth?tab=seo&sub=alerts' and kind = 'system') from app.notifications where key like 'seo.alert_%'), 'the notification opens the alerts');
select pg_temp.check((select count(*) from app.seo_alert_deliveries where alert_id in (select id from t_al)) = 2 * (select count(*) from app.admins a where a.active and not a.is_sample
                          and (app.can_for(a.id, 'global', 'reports_others') or app.can_for(a.id, 'campaigns', 'reports_others'))), 'and by email, once each');
select pg_temp.as_service();
create temp table t_queued as select count(*) n from app.seo_alert_deliveries where status = 'queued';
create temp table t_claim as select public.worker_seo_alert_mail_claim(200) v;
select pg_temp.check((select jsonb_array_length(v) = (select n from t_queued) and v -> 0 ? 'to' and v -> 0 ->> 'from' = 'varsel@seoqa.example'
                      from t_claim), 'mail-run claims the emails with the sender');
select pg_temp.check(jsonb_array_length(public.worker_seo_alert_mail_claim(200)) = 0, 'a claimed email is not claimed twice');
select public.worker_seo_alert_mail_done((x ->> 'alert')::uuid, (x ->> 'recipient')::uuid, true) from t_claim, jsonb_array_elements(v) x;
select pg_temp.check(not exists (select 1 from app.seo_alert_deliveries where alert_id in (select id from t_al) and status <> 'sent'), 'and marks them sent');
-- a rule off raises nothing; the same subject is quiet for its period
select pg_temp.check(app.seo_alert_raise((select id from t_site), 'traffic', 'organic', 'organic@x', '{}', interval '6 hours') = 0, 'a rule switched off raises nothing');
select pg_temp.check(app.seo_alert_raise((select id from t_site), 'rank', 'lovkrav', 'lovkrav@other', '{}', interval '7 days') = 0, 'the same search is quiet for a week');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_error(format($$select public.seo_alert_ack(%L, true)$$, (select id from t_al where rule = 'rank')), 'forbidden', 'acknowledging needs Campaigns › Add');
select pg_temp.as_staff('emma@orgpuls.no');
select public.seo_alert_ack((select id from t_al where rule = 'rank'), true);
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check((select (v ->> 'open')::int = 1 and jsonb_array_length(v -> 'history') = 2 from (select public.seo_alerts_get('orgpuls') v) x), 'one open, one acknowledged');

-- ---------------------------------------------------------------------------
-- a notification may open Growth › SEO › Alerts, never another site
select pg_temp.expect_error($$insert into app.notifications (staff_id, kind, key, route) values ((select id from app.admins limit 1), 'system', 'seo.alert_rank', '//evil.example?a=b')$$,
                            'new row for relation "notifications" violates check constraint "notifications_route_check"', 'a route never leaves the site');
select pg_temp.expect_error($$insert into app.notifications (staff_id, kind, key, route) values ((select id from app.admins limit 1), 'system', 'seo.alert_rank', '/growth?tab=https://evil')$$,
                            'new row for relation "notifications" violates check constraint "notifications_route_check"', 'a parameter is a short word');

rollback;
