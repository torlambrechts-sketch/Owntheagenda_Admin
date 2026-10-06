-- phase4_invariants.sql — reports, dashboards, goals, forecasts (0024) and analytics, health, web (0025).
\ir _helpers.psql
begin;

-- ---------------------------------------------------------------------------
-- structure: the tracker stores a hash, never an address; worker functions are the service role's
select pg_temp.check(not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name like 'web\_%'
                                 and column_name ~ '(^|_)(ip|ip_address|user_agent|address)($|_)'), 'web analytics stores no IP address or user agent');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_web_ingest(jsonb)', 'execute')
                 and not has_function_privilege('authenticated', 'public.worker_web_salt()', 'execute'), 'the tracker''s functions belong to the service role');
select pg_temp.check(public.worker_web_salt() is not null and (select count(*) from vault.secrets where name like 'web_salt:%') = 1, 'one daily salt exists, in Vault');
select app.web_salt_rotate();
select pg_temp.check((select count(*) from vault.secrets where name like 'web_salt:%') = 1, 'rotating destroys the old salt');

-- ---------------------------------------------------------------------------
-- reports
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_open as select (app.report_run('{"entity":"deal","measure":{"fn":"sum","field":"value"},"filters":[{"f":"status","op":"eq","v":"open"}]}') ->> 'total')::numeric v;
select pg_temp.check((select v from t_open) = (select sum(value) from app.deals where status = 'open' and deleted_at is null and archived_at is null and not is_sample and currency = 'NOK'),
                     'a sum over open deals equals the deals');
create temp table t_by_owner as select app.report_run('{"entity":"deal","measure":{"fn":"sum","field":"value"},"group_by":"owner","filters":[{"f":"status","op":"eq","v":"open"}]}') r;
select pg_temp.check((select sum((x ->> 'value')::numeric) from t_by_owner, jsonb_array_elements(r -> 'rows') x) = (select v from t_open), 'the segments add up to the total');
select pg_temp.check((select x ->> 'label' from t_by_owner, jsonb_array_elements(r -> 'rows') x order by (x ->> 'value')::numeric desc limit 1) is not null, 'a segment carries its label');
-- the drill rows are the rows behind the segment
create temp table t_seg as select x ->> 'key' k, (x ->> 'value')::numeric v from t_by_owner, jsonb_array_elements(r -> 'rows') x order by 2 desc limit 1;
select pg_temp.check((select sum((x ->> 'value')::numeric) from jsonb_array_elements(public.report_drill('{"entity":"deal","group_by":"owner","filters":[{"f":"status","op":"eq","v":"open"}]}',
                        jsonb_build_object('key', (select k from t_seg)))) x) = (select v from t_seg), 'the drill-down returns the rows behind the segment (INS-08)');
select pg_temp.expect_error($$select app.report_run('{"entity":"deal","group_by":"password","measure":{"fn":"count"}}')$$, 'invalid', 'a dimension outside the registry is refused');
select pg_temp.expect_error($$select app.report_run('{"entity":"audit","measure":{"fn":"count"}}')$$, 'invalid', 'an entity outside the report whitelist is refused');
select pg_temp.expect_error($$select app.report_run('{"entity":"deal","measure":{"fn":"sum","field":"title"}}')$$, 'invalid', 'a sum over text is refused');
-- without «See reports of others» a staff member sees their own records
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((app.report_run('{"entity":"deal","measure":{"fn":"count"},"filters":[{"f":"status","op":"eq","v":"open"}]}') ->> 'total')::int
                     = (select count(*) from app.deals where status = 'open' and deleted_at is null and archived_at is null and not is_sample
                        and owner_id = (select id from app.admins where email = 'ingrid@orgpuls.no')), 'a staff member without the right sees their own records in reports');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error($$select public.report_export('{"entity":"deal","measure":{"fn":"count"}}')$$, 'forbidden', 'exporting rows needs the export right');
-- a period gives the period before for comparison
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(app.report_run('{"entity":"deal","measure":{"fn":"count"},"period":{"kind":"quarter","field":"created_at"}}') ? 'previous'
                 and (app.report_run('{"entity":"deal","measure":{"fn":"count"},"period":{"kind":"quarter","field":"created_at"}}') ->> 'previous') is not null, 'a periodic report carries the previous period');
select pg_temp.check(jsonb_array_length(app.report_run(jsonb_build_object('entity', 'deal', 'type', 'conversion', 'pipeline_id', (select id from app.pipelines where name = 'New business'))) -> 'rows')
                     = (select count(*) from app.stages where pipeline_id = (select id from app.pipelines where name = 'New business')), 'stage conversion has a row per stage');

-- ---------------------------------------------------------------------------
-- dashboards
create temp table t_tpl as select id from app.dashboards where template_role = 'default';
select pg_temp.check(app.dashboard_role((select id from t_tpl)) = 'viewer', 'a role template is open to everyone, read-only');
select pg_temp.check((select count(*) from jsonb_array_elements(public.dashboard_get((select id from t_tpl)) -> 'tiles') x where x -> 'result' ? 'error') = 0,
                     'every template tile runs');
create temp table t_dup as select (public.dashboard_duplicate((select id from t_tpl), 'Default (copy)') ->> 'id')::uuid id;
select pg_temp.check(app.dashboard_role((select id from t_dup)) = 'owner'
                 and (select count(*) from app.dashboard_tiles where dashboard_id = (select id from t_dup)) = (select count(*) from app.dashboard_tiles where dashboard_id = (select id from t_tpl)),
                     'duplicating copies the tiles to the caller');
select public.dashboard_save((select id from t_dup), null, (select jsonb_agg(jsonb_build_object('report_id', report_id, 'position', 10 - position, 'span', 12)) from app.dashboard_tiles where dashboard_id = (select id from t_dup)));
select pg_temp.check((select bool_and(span = 12) from app.dashboard_tiles where dashboard_id = (select id from t_dup)), 'the layout is stored as arranged (INS-03)');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format('select public.dashboard_get(%L)', (select id from t_dup)), 'not_found', 'an unshared dashboard is not someone else''s');
select pg_temp.as_staff('tor@orgpuls.no');
select public.dashboard_share((select id from t_dup), 'team', (select id from app.teams where name = 'Sales Norway'), 'viewer');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(app.dashboard_role((select id from t_dup)) = 'viewer', 'sharing with a team opens it to its members');
select pg_temp.expect_error(format('select public.dashboard_save(%L, %L)', (select id from t_dup), 'Mine'), 'forbidden', 'a viewer cannot change it');

-- ---------------------------------------------------------------------------
-- goals
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_goal as select (public.goal_save(null, jsonb_build_object('name', 'Mine aktiviteter', 'kind', 'activities_added', 'assignee_kind', 'staff',
  'assignee_id', (select id from app.admins where email = 'ingrid@orgpuls.no'), 'frequency', 'monthly', 'target_count', 10)) ->> 'id')::uuid id;
create temp table t_g0 as select (x ->> 'current')::numeric c from jsonb_array_elements(public.goals_get()) x where (x ->> 'id')::uuid = (select id from t_goal);
select public.rec_save('activity', null, jsonb_build_object('type_id', (select id from app.activity_types where key = 'task'), 'subject', 'Mot målet'));
select pg_temp.check((select (x ->> 'current')::numeric from jsonb_array_elements(public.goals_get()) x where (x ->> 'id')::uuid = (select id from t_goal)) = (select c + 1 from t_g0),
                     'a goal counts the matching records of its interval');
select pg_temp.expect_error($$select public.goal_save(null, '{"name":"Firma","kind":"deals_won","assignee_kind":"company","frequency":"quarterly","target_value":100000}')$$,
                            'forbidden', 'a company goal needs the configure right');

-- forecasts
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(jsonb_array_length(public.forecast_deals(4) -> 'months') = 4, 'the deal forecast covers the next N months');
select pg_temp.check((select sum((x ->> 'best')::numeric) from jsonb_array_elements(public.forecast_deals(24) -> 'months') x)
                     = (select coalesce(sum(value), 0) from app.deals where status = 'open' and deleted_at is null and archived_at is null and not is_sample and currency = 'NOK'
                        and expected_close_date >= date_trunc('month', now() at time zone 'Europe/Oslo') and expected_close_date < date_trunc('month', now() at time zone 'Europe/Oslo') + interval '24 months'),
                     'best case is the open value closing in those months');

-- ---------------------------------------------------------------------------
-- MRR movements and churn
select pg_temp.as_nobody();
create temp table t_sub as select product, tenant_id from app.subscriptions where app.sub_mrr(subscriptions) > 0 limit 1;
insert into app.mrr_tenant_daily (day, product, tenant_id, mrr, status) select date_trunc('month', current_date)::date - 1, product, tenant_id, 0, 'trial' from t_sub;
select app.snapshot_mrr_tenants();
select pg_temp.check((select kind from app.mrr_movements m join t_sub s using (product, tenant_id) where m.month = date_trunc('month', current_date)::date) = 'new',
                     'a tenant that starts paying this month is new MRR');
update app.mrr_tenant_daily set mrr = 500 where day = date_trunc('month', current_date)::date - 1 and (product, tenant_id) in (select product, tenant_id from t_sub);
update app.subscriptions set cancel_effective_at = now() - interval '1 hour', payment_state = 'past_due' where (product, tenant_id) in (select product, tenant_id from t_sub);
select app.snapshot_mrr_tenants();
select pg_temp.check((select kind from app.mrr_movements m join t_sub s using (product, tenant_id) where m.month = date_trunc('month', current_date)::date) = 'churn'
                 and exists (select 1 from app.account_churns c join t_sub s using (product, tenant_id) where c.payment_failure
                             and c.reason_id = (select id from app.churn_reasons where code = 'payment_failure')), 'a cancellation is churn, coded as payment failure when unpaid');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.analytics_business() -> 'churn' ->> 'logos')::int >= 1, 'the business view counts the churn');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error('select public.analytics_business()', 'forbidden', 'analytics needs Global › See reports of others');

-- ---------------------------------------------------------------------------
-- health
select pg_temp.as_nobody();
create temp table t_ap as select ap.product, ap.tenant_id, ap.account_id from app.account_products ap join app.organizations o on o.account_id = ap.account_id where ap.status = 'active' limit 1;
update app.subscriptions set payment_state = 'suspended', cancel_effective_at = null where (product, tenant_id) in (select product, tenant_id from t_ap);
insert into app.health_scores (product, tenant_id, day, score, factors, model_id)
select product, tenant_id, current_date - 1, 80, '[]', (select id from app.health_models where active) from t_ap
on conflict (product, tenant_id, day) do update set score = 80;
update app.members set last_login_at = now() - interval '200 days' where (product, tenant_id) in (select product, tenant_id from t_ap);
select app.health_nightly();
select pg_temp.check((select score from app.health_scores h join t_ap using (product, tenant_id) where h.day = current_date) < 40, 'an unpaid tenant without logins scores low');
select pg_temp.check(exists (select 1 from app.events where kind = 'organization.health_dropped'
                             and subject_id in (select o.id from app.organizations o where o.account_id = (select account_id from t_ap))), 'falling below 40 emits organization.health_dropped');
select pg_temp.check((select factors from app.health_scores h join t_ap using (product, tenant_id) where h.day = current_date) @> '[{"signal":"payment"}]', 'the score keeps its factors');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select (x ->> 'health')::int from jsonb_array_elements(public.customers_get('{}') -> 'rows') x
                      where (x ->> 'account_id')::uuid = (select account_id from t_ap) limit 1) < 40, 'the customer list shows the score');
select pg_temp.check(app.wf_match('organization', (select o.id from app.organizations o where o.account_id = (select account_id from t_ap) limit 1),
                                  '[[{"f":"org_health","op":"lt","v":40}]]'), 'health is a condition for scoring and workflows (PRO-03)');
select pg_temp.expect_error($$select public.health_model_save('{"admin_login":25,"secret":5}')$$, 'invalid', 'a weight for an unknown signal is refused');

-- ---------------------------------------------------------------------------
-- web analytics
select pg_temp.as_nobody();
select public.worker_web_ingest(jsonb_build_array(
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('a', 32), 'at', now() - interval '10 minutes', 'path', '/', 'utm', '{"utm_medium":"cpc"}'::jsonb),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('a', 32), 'at', now() - interval '5 minutes', 'path', '/priser'),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('a', 32), 'at', now() - interval '4 minutes', 'event', '{"name":"kom_i_gang","value":"hero"}'::jsonb),
  jsonb_build_object('site', 'evil.example', 'visitor_hash', repeat('b', 32), 'at', now(), 'path', '/')));
select pg_temp.check((select count(*) from app.web_sessions where visitor_hash = repeat('a', 32)) = 1 and (select pageviews from app.web_sessions where visitor_hash = repeat('a', 32)) = 2,
                     'pages within 30 minutes belong to one session');
select pg_temp.check((select channel from app.web_sessions where visitor_hash = repeat('a', 32)) = 'paid_search', 'the channel comes from the rules');
select pg_temp.check(not exists (select 1 from app.web_sessions where visitor_hash = repeat('b', 32)), 'a site that is not ours is ignored');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.analytics_web() ->> 'sessions')::int >= 1 and (public.analytics_web() ->> 'bounces')::int >= 0, 'the web view reads the sessions');
select pg_temp.check(jsonb_array_length(public.analytics_metric_definitions()) = 7, 'seven metric definitions with their versions');

rollback;
