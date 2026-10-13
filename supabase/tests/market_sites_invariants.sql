-- market_sites_invariants.sql — one site per market (0089): orgpuls.com, se.orgpuls.com and empvibe.com are Orgpuls' sites;
-- a visit is filed under the site its host belongs to; Growth's reads take one site or all of the application's, SEO one
-- (the first unless another is chosen), and a site that is not the application's is refused; SEO's writes land on the site
-- chosen; Search Console imports each site's own pages, leaving out the other sites inside a shared domain property; the
-- application's sites are not referrers to each other.
\ir _helpers.psql
begin;

create temp table t_s as
select (select id from app.web_sites where hostname = 'orgpuls.com') no_site,
       (select id from app.web_sites where hostname = 'se.orgpuls.com') se_site,
       (select id from app.web_sites where hostname = 'empvibe.com') uk_site,
       (select id from app.web_sites where hostname = 'www.owntheagenda.com') other_site;

select pg_temp.check((select array_agg(hostname order by ord, hostname) from app.web_sites where product = 'orgpuls' and active)
                     = array['orgpuls.com', 'se.orgpuls.com', 'empvibe.com'],
                     'Orgpuls has a site per market, Norway first');
select pg_temp.check(not exists (select 1 from app.web_sites where hostname = 'orgpuls.com' and 'empvibe.com' = any (aliases)),
                     'empvibe.com is a site of its own, no longer orgpuls.com''s alias');

-- the tracker files each visit under its market's site
select public.worker_web_track(jsonb_build_object('site', 'se.orgpuls.com', 'visitor_hash', repeat('5e', 16), 'path', '/registrera', 'host', 'se.orgpuls.com'));
select public.worker_web_track(jsonb_build_object('site', 'empvibe.com', 'visitor_hash', repeat('0b', 16), 'path', '/pricing', 'host', 'www.empvibe.com'));
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', repeat('70', 16), 'path', '/', 'host', 'www.orgpuls.com'));
select pg_temp.check((select site_id from app.web_sessions where visitor_hash = repeat('5e', 16)) = (select se_site from t_s)
                     and (select site_id from app.web_sessions where visitor_hash = repeat('0b', 16)) = (select uk_site from t_s)
                     and (select site_id from app.web_sessions where visitor_hash = repeat('70', 16)) = (select no_site from t_s),
                     'a visit is its market''s site''s');

-- Growth: one site, or all of the application's
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select array_agg(x ->> 'hostname' order by ord) from jsonb_array_elements(public.growth_sites_list('orgpuls')) with ordinality a(x, ord))
                     = array['orgpuls.com', 'se.orgpuls.com', 'empvibe.com'],
                     'the picker names the application''s sites in order');
select pg_temp.check((public.growth_scope('orgpuls', 1, null, null, null, null, (select se_site from t_s)) -> 'kpis' ->> 'visitors')::int = 1
                     and (public.growth_scope('orgpuls', 1, null, null, null, null, (select uk_site from t_s)) -> 'kpis' ->> 'visitors')::int = 1
                     and (public.growth_scope('orgpuls', 1) -> 'kpis' ->> 'visitors')::int
                         >= (public.growth_scope('orgpuls', 1, null, null, null, null, (select no_site from t_s)) -> 'kpis' ->> 'visitors')::int + 2,
                     'a site''s figures are its own, and all sites add up the markets');
select pg_temp.check((public.growth_scope('orgpuls', 30, null, null, null, null, (select uk_site from t_s)) -> 'kpis' -> 'accounts') = 'null'::jsonb
                     and (public.growth_scope('orgpuls', 30) -> 'kpis' -> 'accounts') <> 'null'::jsonb,
                     'an account carries no site: with one site chosen Accounts is «—», never the application''s figure');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.growth_pages('orgpuls', 1, null, null, null, null, null, (select uk_site from t_s)) -> 'landing') x
                             where x ->> 'path' = '/pricing')
                     and not exists (select 1 from jsonb_array_elements(public.growth_pages('orgpuls', 1, null, null, null, null, null, (select se_site from t_s)) -> 'landing') x
                                     where x ->> 'path' = '/pricing'),
                     'Pages lists one market''s pages, not another''s');
select pg_temp.expect_error($$ select public.growth_scope('orgpuls', 30, null, null, null, null, (select other_site from t_s)) $$, 'invalid',
                            'a site that is not the application''s is refused');
select pg_temp.expect_error($$ select public.seo_get('orgpuls', 30, (select other_site from t_s)) $$, 'invalid',
                            'SEO refuses a site that is not the application''s');

-- SEO: one site, the first unless another is chosen; its writes land on the site chosen
select pg_temp.check(public.seo_get('orgpuls', 30) -> 'site' ->> 'hostname' = 'orgpuls.com'
                     and public.seo_get('orgpuls', 30, (select uk_site from t_s)) -> 'site' ->> 'hostname' = 'empvibe.com',
                     'SEO reads the first site unless another is chosen');
select public.seo_keyword_add('orgpuls', 'staff wellbeing survey', (select uk_site from t_s));
select pg_temp.check(exists (select 1 from app.seo_keywords k where k.query = 'staff wellbeing survey' and k.site_id = (select uk_site from t_s))
                     and not exists (select 1 from app.seo_keywords k where k.query = 'staff wellbeing survey' and k.site_id = (select no_site from t_s)),
                     'a keyword tracked for Empvibe is Empvibe''s');
select pg_temp.as_nobody();

-- Search Console: each site's own pages
update app.integration_connections set status = 'connected' where provider = 'search_console';
insert into app.search_console_sites (site_id, property) values
  ((select no_site from t_s), 'sc-domain:orgpuls.com'), ((select se_site from t_s), 'sc-domain:orgpuls.com'), ((select uk_site from t_s), 'sc-domain:empvibe.com')
on conflict (site_id) do update set property = excluded.property;
create temp table t_t as select x from jsonb_array_elements(public.worker_search_console_targets()) x;
select pg_temp.check((select x -> 'hosts' = '["orgpuls.com"]'::jsonb and x -> 'except' = '["se.orgpuls.com"]'::jsonb from t_t where x ->> 'site_id' = (select no_site from t_s)::text)
                     and (select x -> 'hosts' = '["se.orgpuls.com"]'::jsonb and x -> 'except' = '[]'::jsonb from t_t where x ->> 'site_id' = (select se_site from t_s)::text)
                     and (select x -> 'hosts' = '["empvibe.com"]'::jsonb and x -> 'except' = '[]'::jsonb from t_t where x ->> 'site_id' = (select uk_site from t_s)::text),
                     'Norway''s import leaves out Sweden''s pages inside the shared domain property; each imports its own');
select pg_temp.check((select count(*) from jsonb_array_elements(public.worker_search_console_sites()) x where x ? 'property') >= 3,
                     'the nightly run sees which sites still have no property');

-- the application's sites are not referrers to each other
select pg_temp.check(app.web_foreign_referrer((select no_site from t_s), 'www.empvibe.com') is null
                     and app.web_foreign_referrer((select uk_site from t_s), 'se.orgpuls.com') is null
                     and app.web_foreign_referrer((select no_site from t_s), 'en.orgpuls.com') is null
                     and app.web_foreign_referrer((select no_site from t_s), 'www.google.com') = 'www.google.com'
                     and app.web_foreign_referrer((select no_site from t_s), 'notorgpuls.com') = 'notorgpuls.com',
                     'a visit from another of the application''s sites is not a referral; one from elsewhere is');

-- the site helpers are not callable from outside
select pg_temp.check(not has_function_privilege('authenticated', 'app.growth_sites(text, uuid)', 'execute')
                     and not has_function_privilege('anon', 'public.growth_sites_list(text)', 'execute')
                     and not has_function_privilege('anon', 'public.seo_get(text, int, uuid)', 'execute')
                     and has_function_privilege('authenticated', 'public.seo_get(text, int, uuid)', 'execute'),
                     'the readers keep their grants; the helpers have none');

rollback;
