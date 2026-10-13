-- web_collect_invariants.sql — the website tracker's way in (0066): only registered sites and daily-salted hashes are
-- kept, at most 300 hits per visitor and day, the time is the server's, and Growth › Analytics reads pricing views and
-- started signups from it. The worker functions are the service role's alone.
\ir _helpers.psql
begin;

create temp table t_h as select repeat('ab', 16) h, repeat('cd', 16) h2;
select pg_temp.check(public.worker_web_sites() ? 'orgpuls.com', 'the collector learns the registered sites');
select pg_temp.check((public.worker_web_track(jsonb_build_object('site', 'evil.example', 'visitor_hash', (select h from t_h), 'path', '/')) ->> 'kept')::int = 0,
                     'a site that is not registered is not recorded');
select pg_temp.check((public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', '203.0.113.7', 'path', '/')) ->> 'kept')::int = 0,
                     'anything but a hash (an address) is not recorded');
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', (select h from t_h), 'path', '/', 'referrer_host', 'google.com',
                                                  'utm', '{"utm_source":"linkedin"}'::jsonb, 'at', '2001-01-01T00:00:00Z'));
select pg_temp.check(exists (select 1 from app.web_sessions s join app.web_sites w on w.id = s.site_id
                             where w.hostname = 'orgpuls.com' and s.visitor_hash = (select h from t_h) and s.day = current_date and s.utm ->> 'utm_source' = 'linkedin'),
                     'a page view makes today''s session (the time is the server''s, never the browser''s)');
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', (select h from t_h), 'path', '/priser'));
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', (select h from t_h), 'path', '/', 'event', '{"name":"cta","value":"kom-i-gang"}'::jsonb));
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', (select h from t_h), 'path', '/registrer', 'event', '{"name":"signup_started"}'::jsonb));
select pg_temp.check((select count(*) from app.web_pageviews p join app.web_sessions s on s.id = p.session_id where s.visitor_hash = (select h from t_h)) = 2
                     and exists (select 1 from app.web_events e join app.web_sessions s on s.id = e.session_id where s.visitor_hash = (select h from t_h) and e.name = 'cta')
                     and exists (select 1 from app.web_events e join app.web_sessions s on s.id = e.session_id where s.visitor_hash = (select h from t_h) and e.name = 'signup_started'),
                     'page views and presses land in one session');

-- an event that reaches Sentral before its page view starts the visit; the page view joins it and says where the visit
-- came from, so the signup is not a second «Direct» visit (0086)
create temp table t_h3 as select repeat('ef', 16) h;
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', (select h from t_h3), 'path', '/registrer', 'event', '{"name":"signup_started"}'::jsonb));
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', (select h from t_h3), 'path', '/registrer', 'referrer_host', 'www.google.com'));
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', (select h from t_h3), 'path', '/registrer', 'event', '{"name":"signup_step","value":"org"}'::jsonb));
select pg_temp.check((select count(*) from app.web_sessions where visitor_hash = (select h from t_h3)) = 1,
                     'a page view and the events sent with it make one visit, whichever arrives first');
select pg_temp.check((select s.channel = 'organic_search' and s.referrer_host = 'www.google.com' and s.pageviews = 1 and s.entry_path = '/registrer'
                      from app.web_sessions s where s.visitor_hash = (select h from t_h3)),
                     'the first page view of a visit an event started gives it its referrer and channel');
select pg_temp.check((select count(*) from app.web_events e join app.web_sessions s on s.id = e.session_id where s.visitor_hash = (select h from t_h3)) = 2,
                     'the signup''s events stay in that visit');
select pg_temp.check(position('pg_advisory_xact_lock' in pg_get_functiondef('public.worker_web_ingest(jsonb)'::regprocedure)) > 0,
                     'one visitor''s hits are taken one at a time, so two sent together cannot make two visits');

-- the cap
do $$ begin for i in 1..300 loop perform public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', repeat('cd', 16), 'path', '/side')); end loop; end $$;
select pg_temp.check((public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', (select h2 from t_h), 'path', '/side')) ->> 'reason') = 'cap'
                     and (select sum(pageviews) from app.web_sessions where visitor_hash = (select h2 from t_h)) = 300,
                     'one visitor is counted at most 300 times a day');

-- Growth › Analytics
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_g as select public.growth_overview('orgpuls', 30) g;
select pg_temp.check((select (x ->> 'count')::int >= 1 from t_g, jsonb_array_elements(g -> 'funnel') x where x ->> 'key' = 'viewed_pricing')
                     and (select (x ->> 'count')::int >= 1 from t_g, jsonb_array_elements(g -> 'funnel') x where x ->> 'key' = 'started_signup')
                     and (select (x ->> 'count')::int >= 2 from t_g, jsonb_array_elements(g -> 'funnel') x where x ->> 'key' = 'visited'),
                     'the funnel reads visits, pricing views and started signups from the tracker');

select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_web_track(jsonb)', 'execute')
                     and not has_function_privilege('anon', 'public.worker_web_sites()', 'execute')
                     and has_function_privilege('service_role', 'public.worker_web_track(jsonb)', 'execute'),
                     'the tracker''s functions are the service role''s alone');

rollback;
