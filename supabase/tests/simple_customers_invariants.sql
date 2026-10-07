-- simple_customers_invariants.sql — Sentral Simple › Customers (0056): the service request on a ticket, the «requests» queue,
-- the company row scoped to one application, the timeline's outcome and the KPI row.
\ir _helpers.psql
begin;

-- the KPI row: anyone who may open the section, figures that agree with the list
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_sum as select public.simple_customers_summary('orgpuls') s;
create temp table t_rows as select x from jsonb_array_elements(public.customers_get('{"product":"orgpuls"}') -> 'rows') x;
select pg_temp.check((select s ?& array['mrr', 'arr', 'paying', 'trials', 'trial_conversion', 'open_tickets', 'median_first_response_min'] from t_sum),
  'the summary names every KPI');
select pg_temp.check((select (s ->> 'mrr')::numeric = (select sum((x ->> 'mrr')::numeric) from t_rows) from t_sum), 'MRR is the sum of the listed accounts'' MRR in this application');
select pg_temp.check((select (s ->> 'arr')::numeric = (s ->> 'mrr')::numeric * 12 from t_sum), 'ARR is twelve months of MRR');
select pg_temp.check((select (s ->> 'paying')::int = (select count(*) from t_rows where x ->> 'status' in ('active', 'past_due') and (x ->> 'mrr')::numeric > 0) from t_sum),
  'paying accounts are the active and past-due accounts with MRR');
select pg_temp.check((select (s ->> 'trials')::int = (select count(*) from t_rows where x ->> 'status' = 'trial') from t_sum), 'trials are the accounts in a trial');
select pg_temp.check((select (s ->> 'open_tickets')::int = (public.tickets_get('{"view":"open","product":"orgpuls"}') #>> '{counts,open}')::int from t_sum),
  'open tickets match the inbox count');
-- no price in scope: MRR is unknown, not zero
create temp table t_prices as select s.product, s.tenant_id, s.price from app.subscriptions s where s.product = 'kurs';
select pg_temp.as_nobody();
update app.subscriptions set price = null where product = 'kurs';
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select public.simple_customers_summary('kurs') -> 'mrr' = 'null'::jsonb and public.simple_customers_summary('kurs') -> 'arr' = 'null'::jsonb),
  'MRR and ARR are null while no subscription in scope carries a price');
select pg_temp.as_nobody();
update app.subscriptions s set price = p.price from t_prices p where s.product = p.product and s.tenant_id = p.tenant_id;
-- trial → paid is a share of real trials, or null
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select s -> 'trial_conversion' = 'null'::jsonb or (s ->> 'trial_conversion')::numeric between 0 and 100 from t_sum), 'trial → paid is a percentage or null');
-- rights: the KPIs need deals:see or tickets:see, not the reports rights; the ticket figures need tickets:see (test-only sets)
select pg_temp.as_nobody();
insert into app.permission_sets (key, name, kind, rights) values
  ('scu_deals', 'SCU test — deals see', 'custom', array['deals:see']), ('scu_tickets', 'SCU test — tickets see', 'custom', array['tickets:see']),
  ('scu_none', 'SCU test — projects only', 'custom', array['projects:see']);
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'scu_deals') where email = 'jonas@orgpuls.no';
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'scu_tickets') where email = 'hanna@orgpuls.no';
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'scu_none') where email = 'emma@orgpuls.no';
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check((select s -> 'open_tickets' = 'null'::jsonb and s -> 'median_first_response_min' = 'null'::jsonb and (s ->> 'paying')::int = (select (s ->> 'paying')::int from t_sum)
                      from (select public.simple_customers_summary('orgpuls') s) x), 'deals:see alone reads the account KPIs; the ticket figures are null');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((select s -> 'open_tickets' <> 'null'::jsonb and s ? 'mrr' from (select public.simple_customers_summary('orgpuls') s) x), 'tickets:see alone reads the KPIs, ticket figures included');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_error($$select public.simple_customers_summary('orgpuls')$$, 'forbidden', 'without deals:see or tickets:see the summary is refused');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_error($$select public.simple_customers_summary('nope')$$, 'invalid', 'an unknown application is refused');
select pg_temp.as_nobody();
select pg_temp.expect_error($$select public.simple_customers_summary('orgpuls')$$, 'not_signed_in', 'nobody signed in reads nothing');
select pg_temp.check(not has_function_privilege('anon', 'public.simple_customers_summary(text)', 'execute'), 'anon cannot call the summary');

-- the company row in one application: that application's figures, every application listed
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select (x ->> 'mrr')::numeric = (select app.sub_mrr(s) from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
                                                      join app.organizations o on o.account_id = ap.account_id where o.name = 'Lumio AS' and s.product = 'skiftly')
                             and jsonb_array_length(x -> 'products') = 2
                      from jsonb_array_elements(public.customers_get('{"product":"skiftly"}') -> 'rows') x where x ->> 'name' = 'Lumio AS'),
  'scoped to Skiftly, a company shows Skiftly''s MRR and still lists both applications');
select pg_temp.check((select (x ->> 'mrr')::numeric = (select sum(app.sub_mrr(s)) from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
                                                      join app.organizations o on o.account_id = ap.account_id where o.name = 'Lumio AS' and ap.status = 'active')
                      from jsonb_array_elements(public.customers_get('{}') -> 'rows') x where x ->> 'name' = 'Lumio AS'),
  'without a scope the company row still sums every application');

-- the «requests» queue: open service requests, counted beside the others
create temp table t_req as select public.tickets_get('{"view":"requests"}') r;
select pg_temp.check((select jsonb_array_length(r -> 'rows') = (r #>> '{counts,requests}')::int from t_req), 'the requests count is the requests view''s length');
select pg_temp.check((select bool_and(x ->> 'type' = 'service_request' and x ->> 'status' not in ('resolved', 'closed')) from t_req, jsonb_array_elements(r -> 'rows') x),
  'the requests view holds open service requests only');
select pg_temp.check((select (r #>> '{counts,requests}')::int = (select count(*) from app.tickets where type = 'service_request' and status not in ('resolved', 'closed') and deleted_at is null and not is_sample)
                      from t_req), 'every open service request is in the queue');

-- intake: a support.requested with a request becomes a service request carrying only the command's arguments
select pg_temp.as_nobody();
insert into app.events_in (product, source_id, kind, tenant_id, payload, occurred_at) values
  ('orgpuls', 998001, 'support.requested', 'orgpuls-o1', '{"subject":"Forleng prøven","message":"Vi trenger to uker til","request":{"kind":"extend_trial","args":{"days":14,"note":"fritekst"}}}', now()),
  ('orgpuls', 998002, 'support.requested', 'orgpuls-o1', '{"subject":"Ukjent ønske","message":"Hei","request":{"kind":"teleport","args":{}}}', now()),
  ('orgpuls', 998003, 'support.requested', 'orgpuls-o1', '{"subject":"Lang prøve","message":"Hei","request":{"kind":"extend_trial","args":{"days":99}}}', now()),
  ('orgpuls', 998004, 'support.requested', 'orgpuls-o1', '{"subject":"Bytt plan","message":"Hei","request":{"kind":"change_plan","args":{"plan":"26–100"}}}', now());
select pg_temp.check((select type = 'service_request' and request = '{"kind":"extend_trial","args":{"days":14}}'::jsonb from app.tickets where source_event_id = (select id from app.events_in where source_id = 998001)),
  'a request becomes a service request with its kind and days, and nothing else');
select pg_temp.check((select type = 'question' and request is null from app.tickets where source_event_id = (select id from app.events_in where source_id = 998002)),
  'an unknown kind leaves an ordinary question');
select pg_temp.check((select request = '{"kind":"extend_trial","args":{}}'::jsonb from app.tickets where source_event_id = (select id from app.events_in where source_id = 998003)),
  'days outside 1–60 are dropped');
select pg_temp.check((select request = '{"kind":"change_plan","args":{"plan":"26–100"}}'::jsonb from app.tickets where source_event_id = (select id from app.events_in where source_id = 998004)),
  'a plan change keeps the plan it names');
select pg_temp.check(not exists (select 1 from app.events e where (e.payload ->> 'event_in')::bigint in (select id from app.events_in where source_id between 998001 and 998004)
                                    and (e.payload::text like '%fritekst%' or e.payload::text like '%extend_trial%' or e.payload -> 'data' ? 'request')),
  'the request does not reach a platform event');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select public.ticket_detail(id) -> 'request' = request from app.tickets where source_event_id = (select id from app.events_in where source_id = 998001)),
  'ticket_detail returns the request');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.tickets_get('{"view":"requests","product":"orgpuls"}') -> 'rows') x where x #>> '{request,kind}' = 'extend_trial'),
  'the inbox rows carry the request');
select pg_temp.as_nobody();
select pg_temp.expect_error($$update app.tickets set request = '{"kind":"teleport"}' where number = 2312$$,
  'new row for relation "tickets" violates check constraint "tickets_request_check"', 'a request kind outside the list is refused');
select pg_temp.check(app.ticket_request('{"kind":"other","args":{"text":"x"}}') = '{"kind":"other","args":{}}'::jsonb, 'kind «other» carries no arguments');

-- the timeline: an admin row says whether it worked; reads are not events
select pg_temp.as_staff('tor@orgpuls.no');
select public.customer_action_log((select id from app.organizations where name = 'Lumio AS'), 'customer.extend_trial', 'Test', false);
select public.ticket_detail((select id from app.tickets where number = 2310));
create temp table t_tl as select x from jsonb_array_elements(public.customer_timeline((select id from app.organizations where name = 'Lumio AS'))) x;
select pg_temp.check(exists (select 1 from t_tl where x ->> 'event' = 'customer.extend_trial' and x -> 'ok' = 'false'::jsonb), 'a failed action shows as failed in the timeline');
select pg_temp.check(not exists (select 1 from t_tl where x ->> 'event' ~ '\.(read|listed)$'), 'reads stay out of the timeline');

rollback;
