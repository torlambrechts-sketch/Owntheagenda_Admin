-- web_analytics_detail_invariants.sql — Analytics › Web's detail (0068): the device class is kept only as one of three
-- words, «started signup» is the organisation number sent (never a press or a visit to the form), and analytics_web
-- answers where visits came from, where they ended and how far each signup attempt got, without an address or a hash.
\ir _helpers.psql
begin;

create temp table t_h as select repeat('e1', 16) a, repeat('e2', 16) b, repeat('e3', 16) c;
-- one hit at a set minute of today (worker_web_track would stamp them all with the transaction's now())
create function pg_temp.hit(p_hash text, p_min int, p_item jsonb) returns void language plpgsql as $$
begin
  perform public.worker_web_ingest(jsonb_build_array(p_item || jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', p_hash,
                                                                                  'at', current_date + make_interval(mins => p_min))));
end $$;
-- a: lands on an article from Google on a phone, opens the form, sends the org.nr, hits an error, finishes
select pg_temp.hit((select a from t_h), 60, '{"path":"/artikler/x0068","referrer_host":"google.com","device":"mobile"}');
select pg_temp.hit((select a from t_h), 61, '{"path":"/registrer"}');
select pg_temp.hit((select a from t_h), 62, '{"path":"/registrer","event":{"name":"signup_started"}}');
select pg_temp.hit((select a from t_h), 63, '{"path":"/registrer","event":{"name":"signup_error","value":"lookup_not_found"}}');
select pg_temp.hit((select a from t_h), 64, '{"path":"/registrer","event":{"name":"signup_completed"}}');
-- b: comes from an ad with a keyword, presses towards signup, opens the form and leaves
select pg_temp.hit((select b from t_h), 70, '{"path":"/x0068-ad","device":"desktop","utm":{"utm_source":"google-ads","utm_medium":"cpc","utm_campaign":"x0068","utm_term":"medarbeiderundersøkelse x0068"}}');
select pg_temp.hit((select b from t_h), 71, '{"path":"/x0068-ad","event":{"name":"cta","value":"prov-gratis"}}');
select pg_temp.hit((select b from t_h), 72, '{"path":"/registrer"}');
-- c: a device word that is not one of the three is not kept
select pg_temp.hit((select c from t_h), 80, '{"path":"/","device":"Mozilla/5.0 (iPhone)"}');

select pg_temp.check((select device from app.web_sessions where visitor_hash = (select a from t_h)) = 'mobile'
                     and (select device from app.web_sessions where visitor_hash = (select c from t_h)) is null,
                     'the device class is one of three words, anything else is dropped');

select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_w as select public.analytics_web(null, 30) w;
select pg_temp.check((select (w -> 'signup' ->> 'opened')::int >= 2 and (w -> 'signup' ->> 'started')::int >= 1 and (w -> 'signup' ->> 'completed')::int >= 1
                             and (w -> 'signup' ->> 'cta')::int >= 1 from t_w),
                     'the signup form''s funnel counts sessions: a press, the form opened, the org.nr sent, done');
select pg_temp.check(exists (select 1 from t_w, jsonb_array_elements(w -> 'signup' -> 'errors') x where x ->> 'value' = 'lookup_not_found' and (x ->> 'count')::int = 1),
                     'the form''s errors are counted by their code');
select pg_temp.check((select (x ->> 'started')::int = 1 and (x ->> 'completed')::int = 1 from t_w, jsonb_array_elements(w -> 'landing') x where x ->> 'path' = '/artikler/x0068')
                     and (select (x ->> 'started')::int = 0 from t_w, jsonb_array_elements(w -> 'landing') x where x ->> 'path' = '/x0068-ad'),
                     'a landing page is credited with the signups that began on it');
select pg_temp.check(exists (select 1 from t_w, jsonb_array_elements(w -> 'sources') x where x ->> 'source' = 'google-ads' and x ->> 'medium' = 'cpc' and x ->> 'campaign' = 'x0068')
                     and exists (select 1 from t_w, jsonb_array_elements(w -> 'sources') x where x ->> 'source' = 'google.com')
                     and exists (select 1 from t_w, jsonb_array_elements(w -> 'paid_terms') x where x ->> 'term' = 'medarbeiderundersøkelse x0068' and (x ->> 'sessions')::int = 1),
                     'sources by utm or referrer, and the ads'' search terms');
select pg_temp.check(exists (select 1 from t_w, jsonb_array_elements(w -> 'exits') x where x ->> 'path' = '/registrer' and (x ->> 'exits')::int >= 2)
                     and exists (select 1 from t_w, jsonb_array_elements(w -> 'devices') x where x ->> 'device' = 'mobile' and (x ->> 'completed')::int >= 1),
                     'where visits end, and devices with their signups');
select pg_temp.check((select x ->> 'outcome' from t_w, jsonb_array_elements(w -> 'attempts') x where x ->> 'entry' = '/x0068-ad') = 'opened'
                     and (select x ->> 'outcome' from t_w, jsonb_array_elements(w -> 'attempts') x where x ->> 'entry' = '/artikler/x0068') = 'completed'
                     and (select jsonb_array_length(x -> 'steps') from t_w, jsonb_array_elements(w -> 'attempts') x where x ->> 'entry' = '/artikler/x0068') = 5,
                     'each signup attempt is a journey of pages and events, and how far it got');
select pg_temp.check((select w::text from t_w) not like '%' || (select a from t_h) || '%',
                     'no visitor hash leaves the database');
select pg_temp.check((select x -> 'search' is not null and x ? 'top_pages' and x ? 'avg_seconds' and x ? 'visitors_prev' from t_w, lateral (select w x) y),
                     'the view carries its new parts');

-- Growth › Analytics: a press or a visit to the form is not a started signup
create temp table t_g as select public.growth_overview('orgpuls', 30) g;
select pg_temp.check((select (x ->> 'count')::int from t_g, jsonb_array_elements(g -> 'funnel') x where x ->> 'key' = 'started_signup')
                     = (select count(distinct (s.day, s.visitor_hash)) from app.web_sessions s join app.web_sites ws on ws.id = s.site_id
                        where ws.product = 'orgpuls' and ws.active and s.day > current_date - 30
                          and exists (select 1 from app.web_events e where e.session_id = s.id and e.name = 'signup_started')),
                     '«Started signup» is the organisation number sent');

rollback;
