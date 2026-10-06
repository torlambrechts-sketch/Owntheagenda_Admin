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

-- ---------------------------------------------------------------------------
-- 0034: the Insights requests
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(not exists (select 1 from app.reports where is_template and template_key is null), 'every template report carries a key (R-INSIGHTS-02)');
select pg_temp.check((select bool_and(x ->> 'template_key' is not null) from app.dashboards d cross join lateral jsonb_array_elements(public.dashboard_get(d.id) -> 'tiles') x
                      where d.template_role is not null), 'dashboard_get returns each template tile''s key');
select pg_temp.check((select bool_and(x ? 'template_key' and x ->> 'template_key' is null) from jsonb_array_elements(public.dashboard_get((select id from t_dup)) -> 'tiles') x),
                     'a staff member''s own copy carries no template key');
create temp table t_conv as select d.template_role, x from app.dashboards d cross join lateral jsonb_array_elements(public.dashboard_get(d.id) -> 'tiles') x
  where d.template_role is not null and x ->> 'template_key' = 'stage_conversion';
select pg_temp.check((select array_agg(template_role order by template_role) from t_conv) = array['default', 'sales_manager']
                 and (select bool_and((x ->> 'span')::int = 4 and x -> 'definition' ->> 'type' = 'conversion' and x -> 'definition' ->> 'pipeline_id' is not null
                                      and not x -> 'result' ? 'error' and jsonb_array_length(x -> 'result' -> 'rows') > 0) from t_conv),
                     'Default and Sales manager show «Stage conversion» over one pipeline (R-INSIGHTS-01)');
-- «Deals per stage»: one pipeline where the template names it, and stages in pipeline order either way
create temp table t_stage_rows as select r.i, s.ord so, p.ord po, p.id pid
  from app.dashboards d cross join lateral jsonb_array_elements(public.dashboard_get(d.id) -> 'tiles') x
  cross join lateral jsonb_array_elements(x -> 'result' -> 'rows') with ordinality r(v, i)
  join app.stages s on s.id = (r.v ->> 'key')::uuid join app.pipelines p on p.id = s.pipeline_id
  where d.template_role = 'default' and x ->> 'template_key' = 'deals_per_stage';
select pg_temp.check(exists (select 1 from t_stage_rows)
                 and not exists (select 1 from t_stage_rows a join t_stage_rows b on b.i = a.i + 1 where (b.po, b.so) < (a.po, a.so))
                 and ((select count(distinct pid) from t_stage_rows) = 1
                      or not exists (select 1 from app.reports where template_key = 'deals_per_stage' and definition -> 'filters' @> '[{"f":"pipeline_id"}]')),
                     '«Deals per stage» keeps to one pipeline, its stages in order (R-INSIGHTS-03)');
-- lost reasons map to the configured list, case-insensitively; anything else is Other
create temp table t_lr as select id, (array['price', ' PRICE ', 'Weather'])[row_number() over (order by id)] r
  from (select id from app.deals where deleted_at is null and archived_at is null and not is_sample and status = 'open' order by id limit 3) x;
update app.deals d set lost_reason = t_lr.r from t_lr where d.id = t_lr.id;
create temp table t_lrr as select app.report_run('{"entity":"deal","measure":{"fn":"count"},"group_by":"lost_reason"}') r;
select pg_temp.check((select (x ->> 'value')::int from t_lrr, jsonb_array_elements(r -> 'rows') x where x ->> 'key' = 'Price')
                     = (select count(*) from app.deals where deleted_at is null and archived_at is null and not is_sample and lower(btrim(lost_reason)) = 'price')
                 and not exists (select 1 from t_lrr, jsonb_array_elements(r -> 'rows') x where x ->> 'key' in ('price', ' PRICE ', 'Weather'))
                 and (select id from t_lr where r = 'Weather') in (select (x ->> 'id')::uuid from jsonb_array_elements(
                        public.report_drill('{"entity":"deal","measure":{"fn":"count"},"group_by":"lost_reason"}', '{"key":"Other"}')) x),
                     'lost reasons are grouped by the configured list, the rest under Other (R-INSIGHTS-04)');
select pg_temp.check((app.report_run('{"entity":"deal","measure":{"fn":"count"},"filters":[{"f":"title","op":"ncontains","v":"a"}]}') ->> 'total')::int
                   + (app.report_run('{"entity":"deal","measure":{"fn":"count"},"filters":[{"f":"title","op":"contains","v":"a"}]}') ->> 'total')::int
                   = (app.report_run('{"entity":"deal","measure":{"fn":"count"}}') ->> 'total')::int, '«does not contain» is the complement of «contains» (R-INSIGHTS-06)');
-- Progress: a deal that moves to a later stage of its pipeline
create temp table t_prog as
  select d.id deal, (select s.id from app.stages s where s.pipeline_id = d.pipeline_id order by s.ord limit 1) s1,
         (select s.id from app.stages s where s.pipeline_id = d.pipeline_id order by s.ord offset 1 limit 1) s2
  from app.deals d where d.status = 'open' and not d.is_sample and d.deleted_at is null and d.archived_at is null
    and d.pipeline_id = (select id from app.pipelines where name = 'New business') order by d.id limit 1;
insert into app.deal_stage_history (deal_id, stage_id, entered_at) select deal, s1, now() - interval '2 hours' from t_prog;
insert into app.deal_stage_history (deal_id, stage_id, entered_at) select deal, s2, now() - interval '1 hour' from t_prog;
select pg_temp.check((select (x ->> 'value')::int from jsonb_array_elements(app.report_run('{"entity":"deal","type":"progress","period":{"kind":"last_30"}}') -> 'rows') x
                      where (x ->> 'key')::uuid = (select s2 from t_prog)) >= 1
                 and (select deal from t_prog) in (select (x ->> 'id')::uuid from jsonb_array_elements(
                        public.report_drill('{"entity":"deal","type":"progress","period":{"kind":"last_30"}}', jsonb_build_object('key', (select s2 from t_prog)))) x),
                     'Progress counts the deals that moved to a later stage, and drills to them (R-INSIGHTS-05)');
create temp table t_cdef as select jsonb_build_object('entity', 'deal', 'type', 'conversion', 'pipeline_id', (select id from app.pipelines where name = 'New business')) def;
select pg_temp.check((select count(*) from jsonb_array_elements(public.report_drill((select def from t_cdef), jsonb_build_object('key', (select s2 from t_prog)))) x)
                     = (select (x ->> 'entered')::int from jsonb_array_elements(app.report_run((select def from t_cdef)) -> 'rows') x where (x ->> 'key')::uuid = (select s2 from t_prog))
                 and (select deal from t_prog) in (select (x ->> 'id')::uuid from jsonb_array_elements(public.report_drill((select def from t_cdef), jsonb_build_object('key', (select s2 from t_prog)))) x),
                     'a conversion row drills to the deals that entered its stage (R-INSIGHTS-09)');
-- Products: the lines of won deals by catalog item
create temp table t_item as select gen_random_uuid() id;
insert into app.catalog_items (id, name) select id, 'Testvare 0034' from t_item;
create temp table t_won as select id from app.deals where status = 'won' and not is_sample and deleted_at is null and archived_at is null and currency = 'NOK' order by id limit 1;
insert into app.deal_items (deal_id, item_id, name, quantity, unit_price, discount_pct) select (select id from t_won), id, 'Testvare 0034', 2, 1000, 10 from t_item;
create temp table t_prod as select x from jsonb_array_elements(app.report_run('{"entity":"deal","type":"products","measure":{"fn":"sum","field":"value"}}') -> 'rows') x
  where x ->> 'key' = (select id::text from t_item);
select pg_temp.check((select (x ->> 'value')::numeric from t_prod) = 1800 and (select x ->> 'label' from t_prod) = 'Testvare 0034'
                 and (select (x ->> 'value')::numeric from jsonb_array_elements(app.report_run('{"entity":"deal","type":"products","measure":{"fn":"sum","field":"quantity"}}') -> 'rows') x
                      where x ->> 'key' = (select id::text from t_item)) = 2
                 and (select id from t_won) in (select (x ->> 'id')::uuid from jsonb_array_elements(
                        public.report_drill('{"entity":"deal","type":"products"}', jsonb_build_object('key', (select id from t_item)))) x),
                     'Products sums the won deals'' lines by catalog item, and drills to the deals (R-INSIGHTS-05)');
select pg_temp.expect_error($$select app.report_run('{"entity":"activity","type":"progress"}')$$, 'invalid', 'progress and products are deal reports');
-- the deal forecast says what it leaves out; undated deals follow the sandbox rule
update app.deals set currency = 'EUR' where id = (select id from app.deals where status = 'open' and not is_sample and deleted_at is null and archived_at is null
  and expected_close_date >= date_trunc('month', now() at time zone 'Europe/Oslo') and expected_close_date < date_trunc('month', now() at time zone 'Europe/Oslo') + interval '4 months'
  order by id limit 1);
update app.deals set is_sample = true, expected_close_date = null where id = (select id from app.deals where status = 'open' and not is_sample and deleted_at is null and archived_at is null
  and currency = 'NOK' order by id desc limit 1);
create temp table t_fc as select public.forecast_deals(4) f;
select pg_temp.check((select (f ->> 'excluded_currency')::int from t_fc) >= 1
                 and (select (f ->> 'excluded_currency')::int from t_fc) = (select count(*) from app.deals where status = 'open' and not is_sample and deleted_at is null and archived_at is null
                        and currency <> 'NOK' and expected_close_date >= date_trunc('month', now() at time zone 'Europe/Oslo')
                        and expected_close_date < date_trunc('month', now() at time zone 'Europe/Oslo') + interval '4 months')
                 and (select (f ->> 'undated')::int from t_fc) = (select count(*) from app.deals where status = 'open' and not is_sample and deleted_at is null and archived_at is null
                        and expected_close_date is null),
                     'the deal forecast counts the deals it leaves out, and undated deals follow the sandbox rule (R-INSIGHTS-07)');

-- ---------------------------------------------------------------------------
-- 0034: the Analytics requests
select pg_temp.as_nobody();
create temp table t_eur_sub as select s.product, s.tenant_id from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
  where app.sub_mrr(s) > 0 and ap.created_at > now() - interval '90 days'
    and not exists (select 1 from app.account_churns c where c.product = s.product and c.tenant_id = s.tenant_id) order by s.product, s.tenant_id limit 1;
update app.subscriptions set currency = 'EUR' where (product, tenant_id) in (select product, tenant_id from t_eur_sub);
select app.snapshot_mrr();
insert into app.mrr_movements (month, product, tenant_id, kind, delta) select date_trunc('month', current_date)::date, product, tenant_id, 'expansion', 777 from t_eur_sub
  on conflict (month, product, tenant_id) do update set kind = 'expansion', delta = 777;
insert into app.account_churns (product, tenant_id, churned_at, mrr_lost) select product, tenant_id, now(), 999 from t_eur_sub;
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_biz as select public.analytics_business() b;
select pg_temp.check((select (b ->> 'excluded_currency')::int from t_biz) >= 1
                 and (select (b ->> 'excluded_currency')::int from t_biz) = (select count(*) from app.subscriptions s where app.sub_mrr(s) > 0 and s.currency <> 'NOK')
                 and (select (b ->> 'mrr')::numeric from t_biz) = (select sum(app.sub_mrr(s)) from app.subscriptions s where s.currency = 'NOK')
                 and (select (b -> 'churn' ->> 'mrr_lost')::numeric from t_biz) = (select coalesce(sum(c.mrr_lost), 0) from app.account_churns c where c.churned_at > now() - interval '30 days'
                        and not exists (select 1 from app.subscriptions s where s.product = c.product and s.tenant_id = c.tenant_id and s.currency <> 'NOK'))
                 and (select (b -> 'churn' ->> 'logos')::int from t_biz) = (select count(*) from app.account_churns where churned_at > now() - interval '30 days')
                 and coalesce((select (x ->> 'expansion')::numeric from t_biz, jsonb_array_elements(b -> 'movements') x where x ->> 'month' = to_char(current_date, 'YYYY-MM')), 0)
                     = (select coalesce(sum(delta), 0) from app.mrr_movements mv where mv.month = date_trunc('month', current_date)::date and mv.kind = 'expansion'
                        and not exists (select 1 from app.subscriptions s where s.product = mv.product and s.tenant_id = mv.tenant_id and s.currency <> 'NOK')),
                     'MRR, movements and churned MRR sum NOK only and say how many subscriptions they left out (R-1)');
select pg_temp.check((public.analytics_attribution('first', 90) ->> 'excluded_currency')::int >= 1, 'attribution says how many subscriptions it left out of MRR (R-1)');
select public.analytics_set_spend('Sosiale annonser 0034', current_date, 5000, 'paid_social');
insert into app.marketing_spend (campaign, month, channel, amount, currency) values ('EUR test 0034', date_trunc('month', current_date)::date, 'paid_social', 300, 'EUR');
create temp table t_att as select public.analytics_attribution('first', 90) a;
select pg_temp.check((select (x ->> 'spend')::numeric from t_att, jsonb_array_elements(a -> 'channels') x where x ->> 'channel' = 'paid_social') = 5000
                 and (select (x ->> 'signups')::int from t_att, jsonb_array_elements(a -> 'channels') x where x ->> 'channel' = 'paid_social')
                     = (select count(*) from app.account_products ap where ap.created_at > now() - interval '90 days'
                        and app.channel_of(coalesce(ap.attribution -> 'first_touch', ap.attribution, '{}'::jsonb)) = 'paid_social')
                 and (select array_agg(distinct x ->> 'currency' order by x ->> 'currency') from t_att, jsonb_array_elements(a -> 'spend') x) = array['EUR', 'NOK'],
                     'a channel with spend appears without signups; its spend sums NOK, each spend row names its currency (R-1, R-8)');
select pg_temp.check((select (b ->> 'first_snapshot')::date from t_biz) = (select min(day) from app.mrr_tenant_daily)
                 and (public.analytics_retention() ->> 'first_snapshot')::date = (select min(day) from app.mrr_tenant_daily), 'the first snapshot is returned as a date (R-2)');
select pg_temp.check((select (b -> 'churn' ->> 'paying_start')::int from t_biz)
                     is not distinct from (select sum(paying)::int from app.mrr_daily where day = (select max(day) from app.mrr_daily where day <= current_date - 30)),
                     'logo churn has the paying subscriptions at the start of the period (R-4)');
select pg_temp.check((select sum((x ->> 'count')::int) from t_biz, jsonb_array_elements(b -> 'by_size') x) = (select sum((x ->> 'count')::int) from t_biz, jsonb_array_elements(b -> 'by_industry') x)
                 and exists (select 1 from t_biz, jsonb_array_elements(b -> 'by_size') x where x ->> 'key' <> ''),
                     'customers by size count the same customers as by industry (R-6)');
-- retention: no figure before the first snapshot; churn per month with its denominator
create temp table t_ret as select public.analytics_retention(null, 'logos') r;
select pg_temp.check(exists (select 1 from t_ret, jsonb_array_elements(r -> 'cohorts') c, jsonb_array_elements(c -> 'cells') z where z = 'null'::jsonb)
                 and not exists (select 1 from t_ret, jsonb_array_elements(r -> 'cohorts') c, jsonb_array_elements(c -> 'cells') with ordinality z(v, k)
                                 where (to_date(c ->> 'cohort', 'YYYY-MM') + make_interval(months => (k - 1)::int))::date < (select date_trunc('month', min(day))::date from app.mrr_tenant_daily)
                                   and z.v <> 'null'::jsonb),
                     'a logos cell before any snapshot is no figure, not 0 (R-4)');
create temp table t_cbm as select x from t_ret, jsonb_array_elements(r -> 'churn_by_month') x where x ->> 'month' = to_char(now(), 'YYYY-MM');
select pg_temp.check((select (x ->> 'logos')::int from t_cbm) = (select count(*) from app.account_churns where date_trunc('month', churned_at) = date_trunc('month', now()))
                 and (select (x ->> 'mrr_lost')::numeric from t_cbm) = (select coalesce(sum(c.mrr_lost), 0) from app.account_churns c where date_trunc('month', c.churned_at) = date_trunc('month', now())
                        and not exists (select 1 from app.subscriptions s where s.product = c.product and s.tenant_id = c.tenant_id and s.currency <> 'NOK'))
                 and (select (x ->> 'paying_start')::int from t_cbm)
                     is not distinct from (select sum(paying)::int from app.mrr_daily where day = (select max(day) from app.mrr_daily where day < date_trunc('month', now())::date)),
                     'churn per month carries the paying subscriptions at its start and its lost MRR in NOK (R-4)');
-- the churn list names each churn; its reason is set from it
create temp table t_ch as select x from jsonb_array_elements(public.analytics_churns(null, 30) -> 'churns') x
  where (x ->> 'product', x ->> 'tenant_id') = (select product, tenant_id from t_eur_sub);
select public.analytics_set_churn_reason((select x ->> 'product' from t_ch), (select x ->> 'tenant_id' from t_ch), (select (x ->> 'churned_at')::timestamptz from t_ch), 'price');
select pg_temp.check((select x ->> 'organization' from t_ch) is not null and (select (x ->> 'mrr_lost')::numeric from t_ch) = 999 and (select x ->> 'currency' from t_ch) = 'EUR'
                 and (select x ->> 'reason' from jsonb_array_elements(public.analytics_churns(null, 30) -> 'churns') x
                      where (x ->> 'product', x ->> 'tenant_id') = (select product, tenant_id from t_eur_sub)) = 'price'
                 and public.analytics_churns() -> 'reasons' ? 'payment_failure',
                     'the churn list names each churn, and its reason can be set from it (R-4)');
-- activation medians from signup
select pg_temp.as_nobody();
create temp table t_act as select product, tenant_id from app.account_products where status = 'active' order by product, tenant_id limit 1;
insert into app.activation_milestones (product, tenant_id, key, reached_at)
select product, tenant_id, v.k, timestamptz '2020-01-05 10:00+00' + v.o from t_act, (values ('account_created', interval '0'), ('survey_sent', interval '90 minutes'), ('converted', interval '3 days')) v(k, o)
on conflict (product, tenant_id, key) do update set reached_at = excluded.reached_at;
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.analytics_activation(null, '2020-01-01') ->> 'first_send_median_min')::numeric = 90
                 and (public.analytics_activation(null, '2020-01-01') ->> 'paid_median_min')::numeric = 4320
                 and public.analytics_activation(null, '2019-01-01') ->> 'first_send_median_min' is null, 'activation medians run from signup; an empty cohort has none (R-3)');
-- usage per application and over the period
select pg_temp.as_nobody();
create temp table t_uc as select product, tenant_id, row_number() over (order by product, tenant_id) rn from app.account_products
  where status = 'active' and created_at < now() - interval '60 days' order by product, tenant_id limit 2;
insert into app.product_counts (product, tenant_id, metric, value, as_of) select product, tenant_id, 'tiltak_created', 5, now() - interval '40 days' from t_uc where rn = 1;
update app.product_counts set value = 9, as_of = now() where metric = 'tiltak_created' and (product, tenant_id) in (select product, tenant_id from t_uc where rn = 1);
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.analytics_usage(null, 30) -> 'counts_delta' ->> 'tiltak_created')::int = 9 - 5
                 and (public.analytics_usage(null, 30) -> 'counts_by_product' -> (select product from t_uc where rn = 1) ->> 'tiltak_created')::int = 9
                 and (public.analytics_usage(null, 30) -> 'response_rate' ->> 'all')::numeric is not distinct from
                     (select round(100.0 * sum(answered) / nullif(sum(invited), 0), 1) from app.product_survey_rounds where closes_at < now() and closes_at > now() - interval '30 days'),
                     'usage per application, the change over the period, and one response rate (R-5)');
select pg_temp.as_nobody();
insert into app.product_counts (product, tenant_id, metric, value, as_of) select product, tenant_id, 'tiltak_created', 3, now() from t_uc where rn = 2;
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(public.analytics_usage(null, 30) -> 'counts_delta' -> 'tiltak_created' = 'null'::jsonb, 'a change is no figure while a tenant has no count from the period''s start (R-5)');
-- web: per campaign, per channel, per day, and the search position
select pg_temp.as_nobody();
insert into app.search_console_daily (day, site_id, query, impressions, clicks, position)
select current_date - k, (select id from app.web_sites where hostname = 'www.owntheagenda.com'), 'arbeidsmiljø 0034', i, c, p from (values (1, 100, 10, 2), (2, 300, 5, 4)) v(k, i, c, p);
select public.worker_web_ingest(jsonb_build_array(jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('c', 32), 'at', now() - interval '3 minutes',
  'path', '/kampanje', 'utm', '{"utm_campaign":"host0034","utm_medium":"cpc"}'::jsonb)));
update app.account_products set attribution = '{"first_touch":{"utm_campaign":"host0034","utm_medium":"cpc"}}' where (product, tenant_id) in (select product, tenant_id from t_eur_sub);
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_web as select public.analytics_web(null, 90) w;
select pg_temp.check((select (x ->> 'position')::numeric from t_web, jsonb_array_elements(w -> 'search') x where x ->> 'query' = 'arbeidsmiljø 0034') = 3.5,
                     'the search table carries Search Console''s position, weighted by impressions (R-7)');
select pg_temp.check((select (x ->> 'sessions')::int = 1 and (x ->> 'signups')::int = 1 and (x ->> 'paid')::int = 1 from t_web, jsonb_array_elements(w -> 'campaigns') x
                      where x ->> 'campaign' = 'host0034')
                 and (select bool_and(x ? 'bounce' and x ? 'signups') from t_web, jsonb_array_elements(w -> 'channels') x)
                 and (select (x ->> 'signups')::int from t_web, jsonb_array_elements(w -> 'channels') x where x ->> 'channel' = 'paid_search')
                     = (select count(*) from app.account_products ap where ap.created_at > now() - interval '90 days'
                        and app.channel_of(coalesce(ap.attribution -> 'first_touch', ap.attribution, '{}'::jsonb)) = 'paid_search')
                 and (select bool_and(x ? 'signups') from t_web, jsonb_array_elements(w -> 'daily') x),
                     'web figures per campaign, per channel and per day (R-7)');
-- Marketing reads web analytics and attribution with Campaigns › See reports of others
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_error('select public.analytics_web()', 'forbidden', 'web analytics needs a reports right');
update app.permission_sets set rights = rights || array['campaigns:reports_others'] where key = 'marketing';
select pg_temp.check(public.analytics_web() ? 'sessions' and public.analytics_attribution() ? 'channels',
                     'Marketing with Campaigns › See reports of others reads web analytics and attribution (R-9)');
select pg_temp.expect_error('select public.analytics_business()', 'forbidden', 'the business figures still need Global › See reports of others');
select pg_temp.expect_error('select public.analytics_churns()', 'forbidden', 'the churn list needs Global › See reports of others');
select pg_temp.check((select bool_and(version >= 2 and migration = '0034_insights_analytics_requests.sql') from app.metric_definitions where key in ('mrr', 'net_new_mrr', 'revenue_churn')),
                     'the changed metric definitions carry a new version');

rollback;
