-- leaderpact_invariants.sql — LeaderPact, the second product (0090): it is registered with its site and its event kinds;
-- nothing is ingested before its secrets are stored; product-events' door takes a lead request five times an hour from one
-- address and passes the rest to ingest_events, so a LeaderPact template request becomes a Sales ticket and a lead like
-- Orgpuls's; a content inventory lands in Growth › SEO on the product's own site only (plan rows, tracked keywords and the
-- change log), never moves a stage back, and is idempotent; no client role can call the door.
\ir _helpers.psql
begin;

create temp table t_site as select id from app.web_sites where hostname = 'leaderpact.com';

-- registered
select pg_temp.check(exists (select 1 from app.products where key = 'leaderpact' and stage = 'beta'), 'LeaderPact is a product');
select pg_temp.check((select product = 'leaderpact' and active from app.web_sites where hostname = 'leaderpact.com'), 'leaderpact.com is its site');
select pg_temp.check((select array_agg(kind order by kind) from app.product_event_kinds where product = 'leaderpact') = array['content.inventory', 'template.requested'],
                     'its event kinds are registered');
select pg_temp.check((select uses from app.product_event_kinds where product = 'leaderpact' and kind = 'content.inventory') = array['content'],
                     'content is a use of an event kind');

-- nothing before the secrets
select pg_temp.check(not (select enabled from app.installations where product = 'leaderpact'), 'the installation waits for its secrets');
select pg_temp.expect_error($$ select public.ingest_product_events('leaderpact', '[{"id": "1", "kind": "content.inventory", "payload": {}}]'::jsonb) $$,
                            'ingest: leaderpact is not installed', 'nothing is ingested before the secrets are stored');
update app.installations set enabled = true where product = 'leaderpact';

-- the door: leads become tickets and leads; the sixth request in an hour from one address is refused
create temp table t_r as select public.ingest_product_events('leaderpact', (
  select jsonb_agg(jsonb_build_object('id', (990100000 + n)::text, 'kind', 'template.requested', 'org_id', null,
                   'payload', jsonb_build_object('template', 'leadership-team-charter-template', 'name', 'Lp Test', 'email', 'Lp.Test@example.com',
                                                 'organisation', 'Test Ltd', 'consent', true, 'lang', 'en')))
  from generate_series(1, 6) n)) r;
select pg_temp.check((select (r ->> 'received')::int = 5 and (r ->> 'refused')::int = 1 from t_r), 'five requests an hour from one address, the sixth refused');
select pg_temp.check((select count(*) from app.events_in where product = 'leaderpact' and kind = 'template.requested') = 5, 'a refused request is not stored');
select pg_temp.check((select t.category_key = 'free_template' and t.queue_key = 'sales' and t.subject = 'Free template: leadership-team-charter-template'
                      from app.tickets t join app.events_in e on e.id = t.source_event_id where e.product = 'leaderpact' and e.source_id = 990100001),
                     'a LeaderPact template request is a Sales ticket');
select pg_temp.check(exists (select 1 from app.ticket_links k join app.tickets t on t.id = k.ticket_id join app.events_in e on e.id = t.source_event_id
                             where e.product = 'leaderpact' and e.source_id = 990100001 and k.kind = 'lead'),
                     'and a CRM lead');
select pg_temp.check((select (r ->> 'received')::int = 0 and (r ->> 'duplicate')::int = 1
                      from (select public.ingest_product_events('leaderpact', '[{"id": "990100001", "kind": "content.inventory", "payload": {}}]'::jsonb) r) x),
                     'an event already received is a duplicate');

-- the content inventory
create temp table t_inv as select jsonb_build_object(
  'site', 'www.leaderpact.com',
  'items', jsonb_build_array(
    jsonb_build_object('path', '/articles/leadership-team-size', 'kind', 'article', 'title', 'How big should a leadership team be?',
                       'queries', jsonb_build_array('Leadership Team Size', 'optimal team size'), 'status', 'published', 'published', '2026-10-13'),
    jsonb_build_object('path', '/articles/team-learning', 'kind', 'article', 'title', 'Team learning',
                       'queries', jsonb_build_array('team reflexivity'), 'status', 'planned'),
    jsonb_build_object('path', '../etc/passwd', 'kind', 'article', 'title', 'x', 'queries', jsonb_build_array('bad path'), 'status', 'published')),
  'keywords', jsonb_build_array('leadership team size', 'optimal team size', 'team reflexivity', '')) payload;

select public.ingest_product_events('leaderpact', jsonb_build_array(jsonb_build_object('id', '990100101', 'kind', 'content.inventory', 'payload', (select payload from t_inv))));
select pg_temp.check((select stage = 'published' and path = '/articles/leadership-team-size' and published_at::date = '2026-10-13' and kind = 'gap'
                      from app.seo_content_plan where site_id = (select id from t_site) and query = 'leadership team size'),
                     'a published page is a published plan row with its path, under its first search, lower-cased');
select pg_temp.check((select stage = 'idea' and path = '/articles/team-learning' from app.seo_content_plan where site_id = (select id from t_site) and query = 'team reflexivity'),
                     'a planned page is an idea');
select pg_temp.check(not exists (select 1 from app.seo_content_plan where query = 'bad path'), 'a path of the wrong shape is not taken');
select pg_temp.check((select count(*) from app.seo_keywords where site_id = (select id from t_site)) = 3, 'every search named is tracked, an empty one is not');
select pg_temp.check((select count(*) = 1 and min(day) = '2026-10-13' from app.seo_changes
                      where site_id = (select id from t_site) and path = '/articles/leadership-team-size' and kind = 'new_page' and source = 'plan'),
                     'a page''s first publication is a change in the log, on its day');

-- a stage someone set is not moved back; a page that goes live moves on; the same inventory again changes nothing
update app.seo_content_plan set stage = 'measuring' where site_id = (select id from t_site) and query = 'leadership team size';
update app.seo_content_plan set stage = 'writing' where site_id = (select id from t_site) and query = 'team reflexivity';
select public.ingest_product_events('leaderpact', jsonb_build_array(jsonb_build_object('id', '990100102', 'kind', 'content.inventory', 'payload', (select payload from t_inv))));
select pg_temp.check((select stage from app.seo_content_plan where site_id = (select id from t_site) and query = 'leadership team size') = 'measuring'
                     and (select stage from app.seo_content_plan where site_id = (select id from t_site) and query = 'team reflexivity') = 'writing',
                     'a stage someone set is never moved back');
select pg_temp.check((select count(*) from app.seo_changes where site_id = (select id from t_site) and kind = 'new_page') = 1
                     and (select count(*) from app.seo_keywords where site_id = (select id from t_site)) = 3,
                     'the same inventory again adds nothing');
select public.ingest_product_events('leaderpact', jsonb_build_array(jsonb_build_object('id', '990100103', 'kind', 'content.inventory', 'payload',
  jsonb_set((select payload from t_inv), '{items,1,status}', '"published"'))));
select pg_temp.check((select stage = 'published' and published_at is not null from app.seo_content_plan where site_id = (select id from t_site) and query = 'team reflexivity'),
                     'a page that goes live moves on to published');

-- a product writes only its own site
select public.ingest_product_events('leaderpact', jsonb_build_array(jsonb_build_object('id', '990100104', 'kind', 'content.inventory', 'payload',
  jsonb_build_object('site', 'orgpuls.com', 'items', jsonb_build_array(jsonb_build_object('path', '/x', 'queries', jsonb_build_array('not ours'), 'status', 'published')),
                     'keywords', jsonb_build_array('not ours')))));
select pg_temp.check(not exists (select 1 from app.seo_content_plan where query = 'not ours') and not exists (select 1 from app.seo_keywords where query = 'not ours')
                     and exists (select 1 from app.audit where action = 'content.skipped'
                                 and target_id = (select id::text from app.events_in where product = 'leaderpact' and source_id = 990100104)),
                     'an inventory naming another product''s site writes nothing, and says so');

-- no client role may call the door
select pg_temp.check(not has_function_privilege('anon', 'public.ingest_product_events(text, jsonb)', 'execute')
                     and not has_function_privilege('authenticated', 'public.ingest_product_events(text, jsonb)', 'execute')
                     and has_function_privilege('service_role', 'public.ingest_product_events(text, jsonb)', 'execute'),
                     'only the service role calls product-events'' door');

rollback;
