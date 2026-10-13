-- growth_v2_invariants.sql — Growth v2 (0073): the tracker keeps a press's page and calls another site a referral (never
-- the site's own hosts); the Overview, the funnel and the pages count exactly the visits of the scope, filter by channel
-- and device, and never put a number on an account figure under a device filter; the log shows four characters of a
-- daily hash and nothing more; PageSpeed's key arrives only through the owner's one-time number and a refusal is recorded;
-- the sync log has its lines; the worker functions are the service role's and the new tables are closed.
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
create or replace function pg_temp.as_mfa(p_email text, p_age int default 30) returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'role', 'authenticated', 'aal', 'aal2', 'email', p_email,
                      'amr', jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint - p_age)))::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;
create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- a site of its own for Orgpuls, so every visit below is known
update app.web_sites set product = null where product = 'orgpuls';
insert into app.web_sites (hostname, product, aliases) values ('qa-growth.example', 'orgpuls', '{qa-growth.no}');
create temp table t_site as select id from app.web_sites where hostname = 'qa-growth.example';
create temp table t_now as select now() - interval '20 minutes' t0;
select pg_temp.as_service();
select public.worker_web_ingest(jsonb_build_array(
  -- A: from Google, desktop: home, pricing, a press, the form, the org.nr, done
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('a'), 'at', (select t0 from t_now), 'path', '/', 'referrer_host', 'www.google.com', 'device', 'desktop'),
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('a'), 'at', (select t0 + interval '30 seconds' from t_now), 'path', '/pris'),
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('a'), 'at', (select t0 + interval '40 seconds' from t_now), 'path', '/pris', 'event', jsonb_build_object('name', 'cta', 'value', 'kom-i-gang')),
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('a'), 'at', (select t0 + interval '50 seconds' from t_now), 'path', '/registrer'),
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('a'), 'at', (select t0 + interval '90 seconds' from t_now), 'path', '/registrer', 'event', jsonb_build_object('name', 'signup_started')),
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('a'), 'at', (select t0 + interval '150 seconds' from t_now), 'path', '/registrer', 'event', jsonb_build_object('name', 'signup_completed')),
  -- B: from another site, mobile, one page
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('b'), 'at', (select t0 + interval '2 minutes' from t_now), 'path', '/blogg', 'referrer_host', 'hrnorge.no', 'device', 'mobile'),
  -- C: «from» the site's own other host (no referrer), mobile: home and pricing
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('c'), 'at', (select t0 + interval '4 minutes' from t_now), 'path', '/', 'referrer_host', 'www.qa-growth.no', 'device', 'mobile'),
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('c'), 'at', (select t0 + interval '5 minutes' from t_now), 'path', '/pris'),
  -- D: a paid click, desktop: the form, the org.nr, a lookup error, gone
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('d'), 'at', (select t0 + interval '6 minutes' from t_now), 'path', '/kom-i-gang', 'device', 'desktop',
                     'utm', jsonb_build_object('utm_source', 'google', 'utm_medium', 'cpc', 'utm_campaign', 'qa')),
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('d'), 'at', (select t0 + interval '7 minutes' from t_now), 'path', '/kom-i-gang', 'event', jsonb_build_object('name', 'signup_started')),
  jsonb_build_object('site', 'qa-growth.example', 'visitor_hash', md5('d'), 'at', (select t0 + interval '8 minutes' from t_now), 'path', '/kom-i-gang', 'event', jsonb_build_object('name', 'signup_error', 'value', 'brreg_not_found'))));

-- ---------------------------------------------------------------------------
-- the tracker
create temp table t_s as select visitor_hash h, channel, referrer_host ref, device, id from app.web_sessions where site_id = (select id from t_site);
select pg_temp.check((select count(*) from t_s) = 4, 'four visits');
select pg_temp.check((select channel from t_s where h = md5('a')) = 'organic_search' and (select channel from t_s where h = md5('b')) = 'referral'
                     and (select channel from t_s where h = md5('d')) = 'paid_search', 'search, another site and a paid click are told apart; another site is a referral');
select pg_temp.check((select ref is null and channel = 'direct' from t_s where h = md5('c')), 'the site''s own hosts are not referrers');
select pg_temp.check((select path from app.web_events where session_id = (select id from t_s where h = md5('a')) and name = 'cta') = '/pris', 'a press keeps the page it was made on');

-- ---------------------------------------------------------------------------
-- the scope's checks
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error($$select public.growth_scope('orgpuls', 30)$$, 'forbidden', 'the Overview needs a reports right');
select pg_temp.expect_error($$select public.growth_funnel('orgpuls', 30)$$, 'forbidden', 'the funnel needs a reports right');
select pg_temp.expect_error($$select public.growth_pages('orgpuls', 30)$$, 'forbidden', 'Pages and links needs a reports right');
select pg_temp.expect_error($$select public.growth_integrations('orgpuls')$$, 'forbidden', 'Integrations needs a reports right');
select pg_temp.as_staff('tor@orgpuls.no', 'aal1');
select pg_temp.expect_error($$select public.growth_scope('orgpuls', 30)$$, 'not_signed_in', 'without the second factor nothing is read');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_error($$select public.growth_scope('orgpuls', 30, null, null, null, 'phone')$$, 'invalid', 'a device is desktop, mobile or tablet');
select pg_temp.expect_error($$select public.growth_scope('orgpuls', 30, null, null, 'Organic Search!')$$, 'invalid', 'a channel is a key');
select pg_temp.expect_error($$select public.growth_scope('orgpuls', 30, null, 10)$$, 'invalid', 'an hour needs its day');
select pg_temp.expect_error(format($$select public.growth_scope('orgpuls', 30, %L)$$, (now() at time zone 'Europe/Oslo')::date + 1), 'invalid', 'a day in the future is refused');
select pg_temp.expect_error($$select public.growth_scope('nope', 30)$$, 'invalid', 'an unknown application is refused');

-- ---------------------------------------------------------------------------
-- Overview
create temp table t_g as select public.growth_scope('orgpuls', 7) g, public.growth_scope('orgpuls', 7, null, null, null, 'mobile') gm,
  public.growth_scope('orgpuls', 7, null, null, 'referral') gr, public.growth_scope('orgpuls', 45) gx,
  public.growth_scope('orgpuls', 7, (now() at time zone 'Europe/Oslo')::date) gd,
  public.growth_scope('orgpuls', 7, ((select t0 from t_now) at time zone 'Europe/Oslo')::date, extract(hour from (select t0 from t_now) at time zone 'Europe/Oslo')::int) gh;
select pg_temp.check((select (g -> 'kpis' ->> 'visitors')::int = 4 and (g -> 'kpis' ->> 'started')::int = 2 from t_g), 'visitors and signups begun are the scope''s');
select pg_temp.check((select (g -> 'kpis' ->> 'accounts')::int from t_g)
                     = (select count(*) from app.account_products where product = 'orgpuls'
                          and created_at >= ((now() at time zone 'Europe/Oslo')::date - 6)::timestamp at time zone 'Europe/Oslo'),
                     'accounts are the application''s, created in the period''s Oslo days');
select pg_temp.check((select (gm -> 'kpis' ->> 'visitors')::int = 2 and gm -> 'kpis' -> 'accounts' = 'null'::jsonb and gm -> 'kpis' -> 'paying' = 'null'::jsonb
                             and gm -> 'kpis' -> 'spend' = 'null'::jsonb from t_g),
                     'a device filter counts its visits and puts no number on accounts, paying or spend');
select pg_temp.check((select (gr -> 'kpis' ->> 'visitors')::int = 1 from t_g), 'a channel filter counts its visits');
select pg_temp.check((select jsonb_array_length(g -> 'series') = 7 and (gx ->> 'days')::int = 30 and jsonb_array_length(gd -> 'series') = 24 and jsonb_array_length(gh -> 'series') = 24 from t_g),
                     'a period draws its days, a day and an hour draw the day''s 24 hours');
select pg_temp.check((select (gh -> 'kpis' ->> 'visitors')::int >= 1 and (gh -> 'kpis' ->> 'visitors')::int <= 4 from t_g), 'an hour counts the visits that began in it');
select pg_temp.check((select coalesce(sum((x ->> 'visits')::int), 0) = 4 from t_g, jsonb_array_elements(g -> 'channels') x), 'the channels add up to the visits');
select pg_temp.check((select g -> 'kpis' -> 'visitors_prev' = 'null'::jsonb from t_g), 'the period before the tracker''s first day has no visitors, not 0');

-- ---------------------------------------------------------------------------
-- the funnel and its log
create temp table t_f as select public.growth_funnel('orgpuls', 7, null, null, null, null, 4) f4, public.growth_funnel('orgpuls', 7, null, null, null, null, 1) f1;
select pg_temp.check((select array_agg((x ->> 'count')::int order by (x ->> 'key')::int) filter (where (x ->> 'key')::int <= 4) from t_f, jsonb_array_elements(f4 -> 'steps') x) = array[4, 3, 2, 2],
                     'the website''s steps count the visitors who reached each, never more than the step before');
select pg_temp.check((select (f4 ->> 'stopped')::int = 1 and f4 -> 'reasons' @> '[{"kind": "error", "value": "brreg_not_found", "count": 1}]'
                             and f4 -> 'reasons' @> '[{"kind": "exit", "value": "/kom-i-gang", "count": 1}]' from t_f),
                     'step 4: the visit that finished is not «stopped»; the one that stopped shows its exit and its form error');
select pg_temp.check((select (f4 ->> 'median_seconds')::numeric = 60 from t_f), 'the median time from the org.nr to done is the visits'' own');
select pg_temp.check((select (f1 ->> 'stopped')::int = 1 and f1 -> 'reasons' @> '[{"kind": "exit", "value": "/blogg"}]' from t_f), 'step 1: the one-page visit left on its page');
select pg_temp.check((select bool_and(x ->> 'visitor' ~ '^v_[0-9a-f]{4}$') and count(*) = 4 from t_f, jsonb_array_elements(f4 -> 'log') x),
                     'the log shows four characters of a daily hash, nothing that names anyone');
select pg_temp.check((select (x ->> 'reached')::int = 5 from t_f, jsonb_array_elements(f4 -> 'log') x where x ->> 'visitor' = 'v_' || left(md5('a'), 4)),
                     'the visit that finished signup on the site reached step 5');
select pg_temp.check(not exists (select 1 from t_f, jsonb_array_elements(f4 -> 'log') x where x::text like '%' || md5('a') || '%'), 'the whole hash never leaves the database');
select pg_temp.check((select (f4 -> 'steps' -> 4 -> 'count') <> 'null'::jsonb and (public.growth_funnel('orgpuls', 7, null, null, null, 'mobile', 4) -> 'steps' -> 4 -> 'count') = 'null'::jsonb from t_f),
                     'the account steps have no number under a device filter');

-- ---------------------------------------------------------------------------
-- Pages and links
create temp table t_p as select public.growth_pages('orgpuls', 7) p;
select pg_temp.check((select p -> 'landing' @> '[{"path": "/", "visits": 2, "started": 1}]' and p -> 'landing' @> '[{"path": "/blogg", "visits": 1, "bounce": 100.0}]' from t_p),
                     'landing pages count their visits, bounces and signups begun');
select pg_temp.check((select p ->> 'path' = '/' from t_p), 'the card shows the most visited landing page unless one is picked');
select pg_temp.check((select p -> 'referrers' @> '[{"host": "hrnorge.no", "visits": 1, "is_new": true}]' and not (p -> 'referrers')::text like '%google%' from t_p),
                     'a site that sends visits is listed (new in the period); search engines are not referring sites');
select pg_temp.check((select p -> 'ctas' @> '[{"value": "kom-i-gang", "path": "/pris", "clicks": 1, "sessions": 1, "page_sessions": 2, "started": 1}]' from t_p),
                     'a press: its page, the visits that pressed against those that saw the page, and the signups that followed');

-- ---------------------------------------------------------------------------
-- the crawler's page facts, the sync log, Technical SEO beyond the crawl
select pg_temp.as_service();
select public.worker_seo_pages((select id from t_site), '[{"path": "/", "title": "QA", "description": "d", "h1": 1, "status": 200, "ms": 420, "noindex": false}]');
select pg_temp.check((select title from app.seo_pages where site_id = (select id from t_site) and path = '/') = 'QA', 'the crawler keeps what a page says about itself');
select public.worker_seo_crawl_result((select id from t_site), 12, 900, '[]'::jsonb, null);
set constraints all immediate;
select pg_temp.check(exists (select 1 from app.growth_sync_log where source = 'crawler' and site_id = (select id from t_site) and rows = 12 and state = 'ok'),
                     'a crawl writes its line in the sync log');
update app.integration_connections set status = 'connected' where provider = 'search_console';
insert into app.search_console_sites (site_id, property) values ((select id from t_site), 'sc-domain:qa-growth.example') on conflict (site_id) do update set property = excluded.property;
insert into app.search_console_pages (day, site_id, query, page, impressions, clicks, position)
values (current_date - 3, (select id from t_site), 'qa delt', '/a', 30, 1, 8), (current_date - 3, (select id from t_site), 'qa delt', '/b', 20, 0, 12),
       (current_date - 3, (select id from t_site), 'qa ene', '/a', 50, 2, 5), (current_date - 3, (select id from t_site), 'qa ene', '/b', 2, 0, 30);
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select public.seo_get('orgpuls', 30) -> 'cannibal') @> '[{"query": "qa delt"}]' and not (public.seo_get('orgpuls', 30) -> 'cannibal') @> '[{"query": "qa ene"}]',
                     'a search two pages split is cannibalization; a page with a few stray impressions is not');
select pg_temp.check((public.seo_keyword_history('orgpuls', 'QA delt', 30) -> 'pages') @> '[{"page": "/a", "impressions": 30}]', 'a keyword''s pages, by its lower-cased query');

-- ---------------------------------------------------------------------------
-- PageSpeed Insights: the key, the readings, a refusal
select pg_temp.check(char_length(public.product_secret('pagespeed_worker_secret')) = 64, 'the nightly job''s key is generated in Vault');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.pagespeed_intake()$$, 'forbidden', 'owner_only', 'only the owner opens an intake for the PageSpeed key');
select pg_temp.as_mfa('tor@orgpuls.no', 1800);
select pg_temp.expect_detail($$select public.pagespeed_intake()$$, 'forbidden', 'fresh_mfa', 'the intake needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
create temp table t_code as select public.pagespeed_intake() ->> 'intake_code' code, public.pagespeed_intake() ->> 'intake_code' code2;
select pg_temp.as_service();
select pg_temp.expect_detail(format($$select public.store_product_secrets(%L, '{"search_console_key": "x"}')$$, (select code from t_code)), 'invalid', 'key',
                             'a PageSpeed number stores the PageSpeed key and nothing else');
select public.store_product_secrets((select code2 from t_code), jsonb_build_object('pagespeed_api_key', 'AIza' || repeat('Q', 35)));
select pg_temp.check(public.product_secret('pagespeed_api_key') = 'AIza' || repeat('Q', 35)
                     and (select status from app.integration_connections where provider = 'pagespeed') = 'connected',
                     'the key lands in Vault, readable by the service role, and the integration is on');
select public.worker_pagespeed_result((select id from t_site), '[]'::jsonb, 'key_refused');
select pg_temp.check((select status = 'error' and config ->> 'last_error' = 'key_refused' from app.integration_connections where provider = 'pagespeed')
                     and exists (select 1 from app.growth_sync_log where source = 'pagespeed' and state = 'failed'), 'a refused key is recorded on the connection and in the log');
select public.worker_pagespeed_result((select id from t_site), '[{"path": "/", "lcp_ms": 3100, "inp_ms": null, "cls": 0.02, "score": 71, "field": false}]'::jsonb, null);
select pg_temp.check((select lcp_ms from app.page_vitals where site_id = (select id from t_site) and path = '/') = 3100
                     and (select status from app.integration_connections where provider = 'pagespeed') = 'connected', 'a reading is kept and the connection is on again');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.growth_pages('orgpuls', 7) -> 'landing') @> '[{"path": "/", "lcp_ms": 3100}]' and (public.seo_get('orgpuls', 30) -> 'slow') @> '[{"path": "/", "lcp_ms": 3100}]',
                     'Pages and Technical SEO read the vitals');
select pg_temp.check((select (d -> 'tracker' ->> 'sessions_24h')::int = 4 and d -> 'pagespeed' ->> 'status' = 'connected' and jsonb_array_length(d -> 'log') > 0
                      from (select public.growth_integrations('orgpuls') d) x), 'Integrations reads the states and the log');
select pg_temp.as_mfa('tor@orgpuls.no');
select public.pagespeed_disconnect();
select pg_temp.check((select status from app.integration_connections where provider = 'pagespeed') = 'not_connected' and (app.pagespeed_tick() ->> 'called')::int = 0,
                     'off: nothing is measured');

-- ---------------------------------------------------------------------------
-- structure
select pg_temp.check((select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('app.seo_pages'::regclass, 'app.page_vitals'::regclass, 'app.growth_sync_log'::regclass))
                     and not has_table_privilege('authenticated', 'app.page_vitals', 'select') and not has_table_privilege('authenticated', 'app.growth_sync_log', 'select')
                     and not has_table_privilege('authenticated', 'app.seo_pages', 'select'), 'the new tables: RLS on, no grant');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_pagespeed_result(uuid, jsonb, text)', 'execute')
                     and not has_function_privilege('authenticated', 'public.worker_seo_pages(uuid, jsonb)', 'execute')
                     and not has_function_privilege('authenticated', 'public.worker_growth_sync(text, uuid, int, jsonb, text)', 'execute')
                     and has_function_privilege('service_role', 'public.worker_pagespeed_targets()', 'execute')
                     and not has_function_privilege('anon', 'public.growth_scope(text, int, date, int, text, text, uuid)', 'execute'),
                     'the workers are the service role''s; nothing is open to anon');
select pg_temp.check(exists (select 1 from cron.job where jobname = 'platform-pagespeed'), 'the nightly measurement is scheduled');

rollback;
