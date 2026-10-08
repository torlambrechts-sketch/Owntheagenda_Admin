-- product_customers_invariants.sql — an application's customers are Sentral's customers (0067): org.created gives the
-- account a CRM company (linked by organisation number, or made), the signup time is the product's own, a tenant that
-- only announces its deletion makes no account, the header's health tolerates a quiet day, and Growth › Analytics divides
-- only the signups of the days the tracker counted.
\ir _helpers.psql
begin;

create temp table t_ev as select (9900000000 + (extract(epoch from clock_timestamp()) * 1000)::bigint % 100000000) base;
create or replace function pg_temp.ev(n int, kind text, tenant text, payload jsonb) returns jsonb language sql as $$
  select jsonb_build_object('id', ((select base from t_ev) + n)::text, 'kind', kind, 'org_id', tenant, 'payload', payload, 'created_at', now())
$$;

-- a new organisation in the product
select public.ingest_events('orgpuls', jsonb_build_array(pg_temp.ev(1, 'org.created', 'pc-tenant-1',
  '{"name": "Testfirma AS", "org_number": "999888777", "employee_count": 12, "created_at": "2026-01-15T09:00:00+00:00"}'::jsonb)));
select pg_temp.check((select ap.created_at from app.account_products ap where ap.product = 'orgpuls' and ap.tenant_id = 'pc-tenant-1') = '2026-01-15T09:00:00+00:00',
                     'the signup time is when the organisation started in the product, not when Sentral heard of it');
select pg_temp.check(exists (select 1 from app.organizations o join app.account_products ap on ap.account_id = o.account_id
                             where ap.tenant_id = 'pc-tenant-1' and o.org_number = '999888777' and o.employees = 12 and o.source = 'orgpuls' and o.deleted_at is null),
                     'the account gets its CRM company, with the number, size and the application it came from');

-- delivered again: still one company
select public.ingest_events('orgpuls', jsonb_build_array(pg_temp.ev(2, 'org.created', 'pc-tenant-1',
  '{"name": "Testfirma AS", "org_number": "999888777", "created_at": "2026-01-15T09:00:00+00:00"}'::jsonb)));
select pg_temp.check((select count(*) from app.organizations o where o.org_number = '999888777' and o.deleted_at is null) = 1,
                     'a second org.created makes no second company');

-- a company the CRM already had, with the same number: linked, not duplicated
insert into app.organizations (name, org_number, source) values ('Kjent Kunde AS', '999888666', 'manual');
select public.ingest_events('orgpuls', jsonb_build_array(pg_temp.ev(3, 'org.created', 'pc-tenant-2',
  '{"name": "Kjent Kunde AS", "org_number": "999888666", "created_at": "2026-02-01T09:00:00+00:00"}'::jsonb)));
select pg_temp.check((select count(*) from app.organizations o where o.org_number = '999888666' and o.deleted_at is null) = 1
                     and (select o.source from app.organizations o where o.org_number = '999888666') = 'manual'
                     and (select o.account_id from app.organizations o where o.org_number = '999888666')
                         = (select ap.account_id from app.account_products ap where ap.tenant_id = 'pc-tenant-2'),
                     'an existing company with the number is linked to the account, not copied');

-- a time in the future is not believed
select public.ingest_events('orgpuls', jsonb_build_array(pg_temp.ev(4, 'org.created', 'pc-tenant-3',
  '{"name": "Fremtid AS", "created_at": "2999-01-01T00:00:00+00:00"}'::jsonb)));
select pg_temp.check((select ap.created_at from app.account_products ap where ap.tenant_id = 'pc-tenant-3') <= now(),
                     'a creation time in the future leaves Sentral''s own');
select pg_temp.check(app.product_created_at('not a time') is null and app.product_created_at('2026-13-45T00:00:00Z') is null,
                     'anything that is not a time is ignored, never an error');

-- a tenant whose first word is its deletion
select public.ingest_events('orgpuls', jsonb_build_array(pg_temp.ev(5, 'org.deleted', 'pc-tenant-gone', '{}'::jsonb)));
select pg_temp.check(not exists (select 1 from app.account_products ap where ap.tenant_id = 'pc-tenant-gone')
                     and exists (select 1 from app.events_in e where e.tenant_id = 'pc-tenant-gone' and e.kind = 'org.deleted'),
                     'a tenant deleted before it was announced leaves the event, not an account');

-- Customers lists it
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.customers_get('{"product": "orgpuls"}'::jsonb) -> 'rows') r where r ->> 'name' = 'Testfirma AS'),
                     'Customers lists the application''s new customer');
select pg_temp.as_nobody();

-- the header's health: a quiet morning is not a fault, a silent day is
update app.events_in set received_at = now() - interval '2 hours' where product = 'orgpuls';
update app.installations set last_ping_ok = null where product = 'orgpuls';
select pg_temp.check(app.application_health('orgpuls') ->> 'status' <> 'degraded', 'two hours without an event is not degraded');
update app.events_in set received_at = now() - interval '30 hours' where product = 'orgpuls';
select pg_temp.check(app.application_health('orgpuls') ->> 'status' = 'degraded', 'thirty hours without an event is degraded');

-- Growth › Analytics: the visit → signup share divides only the tracked days' signups
update app.account_products set created_at = now() - interval '3 days' where product = 'orgpuls' and tenant_id = 'pc-tenant-1';
update app.account_products set created_at = now() - interval '1 minute' where product = 'orgpuls' and tenant_id = 'pc-tenant-2';
select public.worker_web_track(jsonb_build_object('site', 'orgpuls.com', 'visitor_hash', repeat('ef', 16), 'path', '/'));
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_g as select public.growth_overview('orgpuls', 7) g;
select pg_temp.as_nobody();
select pg_temp.check((select (g -> 'kpis' ->> 'signups_tracked')::int from t_g)
                     = (select count(*) from app.account_products ap where ap.product = 'orgpuls' and ap.created_at > now() - interval '7 days'
                          and ap.created_at >= (select (g ->> 'tracked_since')::date from t_g)::timestamptz),
                     'the tracked signups are those since the tracker''s first day');
select pg_temp.check((select (g -> 'kpis' ->> 'signups_tracked')::int < (g -> 'kpis' ->> 'signups')::int from t_g)
                     or (select (g ->> 'tracked_since')::date <= current_date - 6 from t_g),
                     'a signup before the tracker''s first day is a signup, not a converted visit');
select pg_temp.check((select (g ->> 'tracked_since')::date <= current_date - 13 from t_g) or (select g -> 'kpis' -> 'visitors_prev' = 'null'::jsonb from t_g),
                     'no previous period''s visitors before the tracker had one');
select pg_temp.check(not exists (select 1 from t_g, jsonb_array_elements(g -> 'daily') x
                                 where (x ->> 'day')::date < (g ->> 'tracked_since')::date and x -> 'visitors' <> 'null'::jsonb),
                     'no daily visitors before the tracker''s first day');

select pg_temp.check(not has_function_privilege('authenticated', 'app.link_product_org(uuid, text)', 'execute')
                     and not has_function_privilege('anon', 'app.link_product_org(uuid, text)', 'execute'),
                     'linking is the ingest''s, nobody calls it');

rollback;
