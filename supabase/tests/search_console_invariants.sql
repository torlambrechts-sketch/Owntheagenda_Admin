-- search_console_invariants.sql — Google Search Console (0064): the key only through the owner's intake, the connection only
-- from the worker's verdict, each site's property, the import replacing its days, Growth › SEO reading Search Console's own
-- totals, the daily tick, and the worker functions the service role's alone.
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

-- a key shaped like Google's (not a real key: the database checks the shape, the edge function proves it with Google)
create temp table t_key as select jsonb_build_object('type', 'service_account', 'project_id', 'test', 'client_email', 'sentral-seo@test-project.iam.gserviceaccount.com',
  'private_key', '-----BEGIN PRIVATE KEY-----\nTESTONLY\n-----END PRIVATE KEY-----\n')::text k;
create temp table t_site as select (app.product_site('orgpuls')).id id;
create temp table t_other as select id from app.web_sites where active and id <> (select id from t_site) order by hostname limit 1;

-- ---------------------------------------------------------------------------
-- storage and secrets
select pg_temp.check((select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('app.search_console_sites'::regclass, 'app.search_console_totals'::regclass))
                     and not has_table_privilege('authenticated', 'app.search_console_totals', 'select')
                     and not has_table_privilege('authenticated', 'app.search_console_sites', 'select'), 'the new tables: RLS on, no grant');
select pg_temp.check(char_length(public.product_secret('search_console_worker_secret')) = 64, 'the cron''s key is generated in Vault, nobody types it');

-- the owner's intake: owner only, fresh second factor, bound to the key's one name
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.search_console_intake()$$, 'forbidden', 'owner_only', 'only the owner opens an intake for the Google key');
select pg_temp.as_mfa('tor@orgpuls.no', 1800);
select pg_temp.expect_detail($$select public.search_console_intake()$$, 'forbidden', 'fresh_mfa', 'the intake needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
create temp table t_code as select public.search_console_intake() ->> 'intake_code' code;
create temp table t_code2 as select public.search_console_intake() ->> 'intake_code' code;
select pg_temp.check((select purpose from app.intake_nonces where hash = extensions.digest((select code from t_code), 'sha256')) = 'search_console',
                     'the number is bound to the Google key');
select pg_temp.as_service();
select pg_temp.expect_detail(format($$select public.store_product_secrets(%L, '{"brevo_api_key": "%s"}')$$, (select code from t_code), repeat('a', 40)),
                             'invalid', 'key', 'a Search Console number stores the Google key and nothing else');
select pg_temp.expect_detail(format($$select public.store_product_secrets(%L, '{"search_console_key": "{\"type\": \"authorized_user\"}"}')$$, (select code from t_code2)),
                             'invalid', 'key', 'only a service account''s key is accepted');
create temp table t_code3 as select null::text code;
select pg_temp.as_mfa('tor@orgpuls.no');
update t_code3 set code = public.search_console_intake() ->> 'intake_code';
select pg_temp.as_service();
select pg_temp.check((public.store_product_secrets((select code from t_code3), jsonb_build_object('search_console_key', (select k from t_key))) ->> 'stored')::int = 1,
                     'the key is stored under its one name');
select pg_temp.check((public.product_secret('search_console_key'))::jsonb ->> 'client_email' = 'sentral-seo@test-project.iam.gserviceaccount.com',
                     'search-console-run can read the key (service role)');
select pg_temp.check((select config ->> 'client_email' from app.integration_connections where provider = 'search_console') = 'sentral-seo@test-project.iam.gserviceaccount.com'
                     and (select config::text from app.integration_connections where provider = 'search_console') !~ 'PRIVATE KEY',
                     'only the account''s address is kept outside Vault');
select pg_temp.check((select status from app.integration_connections where provider = 'search_console') = 'not_connected',
                     'storing a key connects nothing: only the worker''s verdict does');

-- ---------------------------------------------------------------------------
-- the verdict and each site's property
select pg_temp.check(jsonb_array_length(public.worker_search_console_sites()) >= 1
                     and public.worker_search_console_sites() @> jsonb_build_array(jsonb_build_object('hostname', 'orgpuls.com')), 'the worker learns the sites to look for');
select pg_temp.expect_detail($$select public.worker_search_console_result(false, '{"code": "Google said no"}')$$, 'invalid', 'code', 'a verdict''s code is a code, never Google''s words');
select pg_temp.check((public.worker_search_console_result(false, '{"code": "http_401"}') ->> 'status') = 'error', 'a refused key is an error');
select pg_temp.check((public.worker_search_console_result(true, jsonb_build_object('sites', jsonb_build_array(
                        jsonb_build_object('site_id', (select id from t_site), 'property', 'sc-domain:orgpuls.com'),
                        jsonb_build_object('site_id', (select id from t_other), 'property', null)))) ->> 'status') = 'connected', 'a proven key connects');
select pg_temp.check((select property from app.search_console_sites where site_id = (select id from t_site)) = 'sc-domain:orgpuls.com'
                     and (select last_error from app.search_console_sites where site_id = (select id from t_other)) = 'no_property',
                     'each site has its property, or says the account cannot see one');
select pg_temp.check((select (x ->> 'from')::date = current_date - 180 from jsonb_array_elements(public.worker_search_console_targets()) x where (x ->> 'site_id')::uuid = (select id from t_site))
                     and not exists (select 1 from jsonb_array_elements(public.worker_search_console_targets()) x where (x ->> 'site_id')::uuid = (select id from t_other)),
                     'the first import reaches 180 days back; a site without a property is not asked for');

-- ---------------------------------------------------------------------------
-- the import
select public.worker_search_console_import((select id from t_site),
  jsonb_build_array(jsonb_build_object('day', current_date - 1, 'impressions', 500, 'clicks', 50, 'position', 4.5),
                    jsonb_build_object('day', current_date - 40, 'impressions', 200, 'clicks', 10, 'position', 9)),
  jsonb_build_array(jsonb_build_object('day', current_date - 1, 'query', 'Arbeidsmiljøundersøkelse', 'impressions', 120, 'clicks', 12, 'position', 3),
                    jsonb_build_object('day', current_date - 1, 'query', 'arbeidsmiljøundersøkelse ', 'impressions', 80, 'clicks', 8, 'position', 5),
                    jsonb_build_object('day', current_date - 40, 'query', 'arbeidsmiljøundersøkelse', 'impressions', 50, 'clicks', 2, 'position', 11)));
select pg_temp.check((select impressions from app.search_console_daily where site_id = (select id from t_site) and day = current_date - 1 and query = 'arbeidsmiljøundersøkelse') = 200
                     and (select position from app.search_console_daily where site_id = (select id from t_site) and day = current_date - 1 and query = 'arbeidsmiljøundersøkelse') = 3.80,
                     'queries are kept lower case; the same query twice sums, its position weighted by impressions');
select public.worker_search_console_import((select id from t_site),
  jsonb_build_array(jsonb_build_object('day', current_date - 1, 'impressions', 600, 'clicks', 60, 'position', 4)),
  jsonb_build_array(jsonb_build_object('day', current_date - 1, 'query', 'arbeidsmiljøundersøkelse', 'impressions', 150, 'clicks', 15, 'position', 3)),
  -- the pages' own figures, as search-console-run sends them since 0091
  jsonb_build_array(jsonb_build_object('day', current_date - 1, 'page', '/', 'impressions', 600, 'clicks', 60, 'position', 4)));
select pg_temp.check((select impressions from app.search_console_totals where site_id = (select id from t_site) and day = current_date - 1) = 600
                     and (select impressions from app.search_console_daily where site_id = (select id from t_site) and day = current_date - 1 and query = 'arbeidsmiljøundersøkelse') = 150
                     and (select impressions from app.search_console_daily where site_id = (select id from t_site) and day = current_date - 40 and query = 'arbeidsmiljøundersøkelse') = 50,
                     'importing a day again replaces that day and leaves the others');
select pg_temp.check((select last_day from app.search_console_sites where site_id = (select id from t_site)) = current_date - 1
                     and (select (x ->> 'from')::date = current_date - 5 from jsonb_array_elements(public.worker_search_console_targets()) x where (x ->> 'site_id')::uuid = (select id from t_site)),
                     'the next import starts a few days before the last imported day (Search Console revises them), its pages caught up (0091)');
select pg_temp.expect_detail(format($$select public.worker_search_console_import(%L, '[]', '[]')$$, (select id from t_other)), 'not_found', null, 'a site without a property takes no rows');
select pg_temp.expect_detail(format($$select public.worker_search_console_failed(%L, 'Quota exceeded for x@y')$$, (select id from t_site)), 'invalid', 'code', 'a failure is a code, never Google''s words');
select public.worker_search_console_failed((select id from t_site), 'http_429');
select pg_temp.check((select last_error from app.search_console_sites where site_id = (select id from t_site)) = 'http_429', 'a failed import says why');

-- ---------------------------------------------------------------------------
-- Growth › SEO
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_k as select (public.seo_keyword_add('orgpuls', 'arbeidsmiljøundersøkelse') ->> 'id')::uuid id;
create temp table t_s as select public.seo_get('orgpuls', 30) s;
select pg_temp.check((select (s -> 'totals' ->> 'impressions')::int = 600 and (s -> 'totals' ->> 'clicks')::int = 60 and (s -> 'totals' ->> 'impressions_prev')::int = 200 from t_s),
                     'the totals are Search Console''s own (anonymised queries included), not the sum of the query rows');
select pg_temp.check((select (x ->> 'impressions')::int = 150 and (x ->> 'position')::numeric = 3.0 and (x ->> 'position_prev')::numeric = 11.0
                      from t_s, jsonb_array_elements(s -> 'keywords') x where (x ->> 'id')::uuid = (select id from t_k)), 'a tracked keyword reads its own rows');
select pg_temp.check((select s -> 'search_console' ->> 'property' = 'sc-domain:orgpuls.com' and (s -> 'search_console' ->> 'can_manage')::boolean
                             and s -> 'search_console' ->> 'client_email' = 'sentral-seo@test-project.iam.gserviceaccount.com' from t_s),
                     'the owner sees the property and the account to give access to');
-- every search Google shows the site for is listed, tracked or not; a tracked head term counts the longer searches (0084)
select public.worker_search_console_import((select id from t_site),
  jsonb_build_array(jsonb_build_object('day', current_date - 2, 'impressions', 40, 'clicks', 0, 'position', 9)),
  jsonb_build_array(jsonb_build_object('day', current_date - 2, 'query', 'kartlegging arbeidsmiljøundersøkelse mal', 'impressions', 30, 'clicks', 0, 'position', 9),
                    jsonb_build_object('day', current_date - 2, 'query', 'verneombud plikter', 'impressions', 10, 'clicks', 0, 'position', 14)));
create temp table t_s2 as select public.seo_get('orgpuls', 30) s;
select pg_temp.check((select count(*) = 1 from t_s2, jsonb_array_elements(s -> 'keywords') x
                      where x ->> 'query' = 'verneombud plikter' and not (x ->> 'tracked')::boolean and x ->> 'id' is null and (x ->> 'impressions')::int = 10
                        and (x ->> 'position')::numeric = 14.0),
                     'a search nobody tracks is listed with its figures');
select pg_temp.check((select (x ->> 'tracked')::boolean and (x -> 'variants' ->> 'queries')::int = 1 and (x -> 'variants' ->> 'impressions')::int = 30
                      from t_s2, jsonb_array_elements(s -> 'keywords') x where (x ->> 'id')::uuid = (select id from t_k)),
                     'a tracked keyword counts the longer searches that contain it');
select pg_temp.check((select count(*) from t_s2, jsonb_array_elements(s -> 'keywords') x where x ->> 'query' = 'arbeidsmiljøundersøkelse') = 1
                     and (select (s ->> 'keywords_total')::int = 3 from t_s2), 'a tracked search is listed once; keywords_total counts every search in the period');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check(not (public.seo_get('orgpuls', 30) -> 'search_console' ->> 'can_manage')::boolean, 'others see the state, not the controls');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.search_console_disconnect()$$, 'forbidden', 'owner_only', 'only the owner disconnects');

-- ---------------------------------------------------------------------------
-- the tick, the disconnect, the grants
select pg_temp.check((app.search_console_tick() ->> 'called')::int = 1, 'connected: the daily tick knocks on search-console-run');
select pg_temp.check(exists (select 1 from app.job_defs where key = 'search_console_import' and schedule = '41 4 * * *'), 'it runs every night');
select pg_temp.as_mfa('tor@orgpuls.no');
select public.search_console_disconnect();
select pg_temp.check((app.search_console_tick() ->> 'called')::int = 0 and jsonb_array_length(public.worker_search_console_targets()) = 0,
                     'disconnected: nothing is imported');
select pg_temp.check((public.seo_get('orgpuls', 30) -> 'totals') = 'null'::jsonb, 'and Growth › SEO shows no figures');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_search_console_import(uuid, jsonb, jsonb, jsonb, jsonb, jsonb)', 'execute')
                     and not has_function_privilege('authenticated', 'public.worker_search_console_result(boolean, jsonb, uuid)', 'execute')
                     and has_function_privilege('service_role', 'public.worker_search_console_targets()', 'execute')
                     and not has_function_privilege('anon', 'public.search_console_intake()', 'execute'),
                     'the worker functions are the service role''s alone');

rollback;
