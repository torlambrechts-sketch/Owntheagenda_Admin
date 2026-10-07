-- simple_growth_invariants.sql — Sentral Simple › Growth (0058): the overview, SEO keywords and marketing campaigns.
\ir _helpers.psql
begin;

-- ---------------------------------------------------------------------------
-- structure: the new tables are closed like every other
select pg_temp.check((select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('app.seo_keywords'::regclass, 'app.ad_campaigns'::regclass)),
                     'seo_keywords and ad_campaigns have row level security on');
select pg_temp.check(not has_table_privilege('authenticated', 'app.ad_campaigns', 'select') and not has_table_privilege('authenticated', 'app.seo_keywords', 'select'),
                     'no client role reads seo_keywords or ad_campaigns');
select pg_temp.check((app.product_site('orgpuls')).hostname = 'orgpuls.com' and (app.product_site('skiftly')).id is null,
                     'orgpuls.com is Orgpuls''s site; an application without one has none');

-- ---------------------------------------------------------------------------
-- growth_overview
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error($$select public.growth_overview('orgpuls', 30)$$, 'forbidden', 'the overview needs a reports right');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_error($$select public.growth_overview('nope', 30)$$, 'invalid', 'an unknown application is refused');
create temp table t_g as select public.growth_overview('orgpuls', 7) g7, public.growth_overview('orgpuls', 30) g30, public.growth_overview('orgpuls', 45) gx;
select pg_temp.check((select (g7 ->> 'days')::int = 7 and jsonb_array_length(g7 -> 'daily') = 7 and (gx ->> 'days')::int = 30 from t_g),
                     'the period is 7, 30 or 90 days (anything else is 30), one daily point per day');
select pg_temp.check((select (g30 -> 'kpis' ->> 'signups')::int from t_g)
                     = (select count(*) from app.account_products where product = 'orgpuls' and created_at > now() - interval '30 days'),
                     'signups are the application''s accounts created in the period');
select pg_temp.check((select (g30 -> 'kpis' ->> 'signups_prev')::int from t_g)
                     = (select count(*) from app.account_products where product = 'orgpuls' and created_at > now() - interval '60 days' and created_at <= now() - interval '30 days'),
                     'the previous period is the same length before it');
select pg_temp.check((select coalesce(sum((x ->> 'signups')::int), 0) from t_g, jsonb_array_elements(g30 -> 'sources') x) = (select (g30 -> 'kpis' ->> 'signups')::int from t_g),
                     'the sources add up to the signups');
select pg_temp.check((select g30 -> 'kpis' -> 'visitors' = 'null'::jsonb and not (g30 ->> 'tracked')::boolean
                             and (select bool_and(x -> 'visitors' = 'null'::jsonb) from jsonb_array_elements(g30 -> 'daily') x)
                             and (select bool_and(x -> 'visits' = 'null'::jsonb) from jsonb_array_elements(g30 -> 'sources') x)
                             and jsonb_array_length(g30 -> 'pages') = 0 from t_g),
                     'without the tracker visitors, visits and landing pages are null or empty, never 0');
select pg_temp.check((select (g30 -> 'funnel' -> 0 -> 'count') = 'null'::jsonb and (g30 -> 'funnel' -> 1 -> 'count') = 'null'::jsonb and (g30 -> 'funnel' -> 2 -> 'count') = 'null'::jsonb
                             and (g30 -> 'funnel' -> 3 ->> 'count')::int = (g30 -> 'kpis' ->> 'signups')::int
                             and (g30 -> 'funnel' -> 4 ->> 'count')::int <= (g30 -> 'funnel' -> 3 ->> 'count')::int
                             and (g30 -> 'funnel' -> 5 ->> 'count')::int <= (g30 -> 'funnel' -> 3 ->> 'count')::int from t_g),
                     'the funnel''s top has no source; its bottom is the period''s accounts and what they reached');
select pg_temp.check((select (g30 -> 'kpis' -> 'trial_conversion' ->> 'trials')::int from t_g)
                     = (select sum(trials) from app.v_trial_conversion where product = 'orgpuls' and cohort >= date_trunc('month', now() - interval '75 days')
                        and cohort < date_trunc('month', now() - interval '45 days') + interval '1 month'),
                     'trial → paid uses analytics_business''s cohorts');
select pg_temp.check((public.growth_overview('kurs', 30) -> 'kpis' -> 'spend') = 'null'::jsonb or exists (select 1 from app.ad_campaigns where product = 'kurs'),
                     'no spend typed in reads null, not 0');
create temp table t_spend0 as select coalesce((public.growth_overview('orgpuls', 30) -> 'kpis' ->> 'spend')::numeric, 0) v;
-- a tracked session on the application's site makes visitors real
insert into app.web_sessions (site_id, day, visitor_hash, started_at, entry_path, utm, channel)
values ((app.product_site('orgpuls')).id, current_date, repeat('a', 32), now(), '/lovkrav', '{"utm_campaign":"nobody-uses-this"}', 'organic_search');
select pg_temp.check((public.growth_overview('orgpuls', 7) -> 'kpis' ->> 'visitors')::int = 1
                 and (public.growth_overview('orgpuls', 7) -> 'pages' -> 0 ->> 'path') = '/lovkrav'
                 and (public.growth_overview('skiftly', 7) -> 'kpis' -> 'visitors') = 'null'::jsonb,
                     'a session on the site counts a visitor and a landing page; another application''s overview is untouched');

-- ---------------------------------------------------------------------------
-- marketing campaigns
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_error($$select public.ad_campaigns_get('orgpuls')$$, 'forbidden', 'campaigns need Campaigns › See');
select pg_temp.expect_error($$select public.ad_campaign_save(null, '{"product":"orgpuls","name":"X","channel":"linkedin"}')$$, 'forbidden', 'creating one needs Campaigns › Add');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_c as select (public.ad_campaign_save(null, '{"product":"orgpuls","name":"Growth test — Q4","channel":"google_ads","landing_path":"/lovkrav","budget":18000}') ->> 'id')::uuid id;
select pg_temp.check((select utm_source = 'google-ads' and utm_medium = 'cpc' and utm_campaign = 'growth-test-q4' and state = 'scheduled' and currency = 'NOK'
                      from app.ad_campaigns where id = (select id from t_c)), 'a new campaign gets its channel''s utm, the name''s slug and starts scheduled');
select pg_temp.check(app.channel_of('{"utm_source":"google-ads","utm_medium":"cpc"}') = 'paid_search' and app.channel_of('{"utm_source":"linkedin","utm_medium":"paid_social"}') = 'paid_social',
                     'its links land under the channel the campaign is');
select pg_temp.check((public.ad_campaign_save(null, '{"product":"orgpuls","name":"Growth test – Q4","channel":"linkedin"}') ->> 'utm_campaign') = 'growth-test-q4-2',
                     'utm_campaign is unique: the second gets -2');
select pg_temp.expect_error($$select public.ad_campaign_save(null, '{"product":"orgpuls","name":"X","channel":"tiktok"}')$$, 'invalid', 'an unknown channel is refused');
select pg_temp.expect_error($$select public.ad_campaign_save(null, '{"product":"orgpuls","name":"X","channel":"other","landing_path":"https://evil.example"}')$$, 'invalid', 'a landing path is a path');
select pg_temp.expect_error($$select public.ad_campaign_save(null, '{"product":"orgpuls","name":"X","channel":"other","starts_on":"2026-10-10","ends_on":"2026-10-01"}')$$, 'invalid', 'it cannot end before it starts');
select pg_temp.expect_error($$select public.ad_campaign_save(null, '{"product":"orgpuls","name":"X","channel":"other","price":1}')$$, 'invalid', 'an unknown key is refused');
-- figures: nothing typed in, no tracker for this utm, no signups yet
create temp table t_r as select x from jsonb_array_elements(public.ad_campaigns_get('orgpuls') -> 'rows') x where (x ->> 'id')::uuid = (select id from t_c);
select pg_temp.check((select x -> 'figures' -> 'spent' = 'null'::jsonb and (x -> 'figures' ->> 'visits')::int = 0 and (x -> 'figures' ->> 'signups')::int = 0 from t_r),
                     'a new campaign has no spend (null), and 0 visits once the site is tracked');
-- spend and a signup through the link
select public.analytics_set_spend('growth-test-q4', date_trunc('month', now())::date, 12400, 'paid_search');
update app.account_products set attribution = '{"first_touch":{"utm_campaign":"growth-test-q4","utm_medium":"cpc","utm_source":"google-ads"}}'
where (product, tenant_id) = (select product, tenant_id from app.account_products where product = 'orgpuls' order by created_at desc limit 1);
create temp table t_r2 as select x from jsonb_array_elements(public.ad_campaigns_get('orgpuls') -> 'rows') x where (x ->> 'id')::uuid = (select id from t_c);
select pg_temp.check((select (x -> 'figures' ->> 'spent')::numeric = 12400 and (x -> 'figures' ->> 'signups')::int = 1 and jsonb_array_length(x -> 'figures' -> 'spend') = 1 from t_r2),
                     'spend is what was typed in under the utm_campaign; signups are first touches with it');
select pg_temp.check((public.growth_overview('orgpuls', 30) -> 'kpis' ->> 'spend')::numeric = (select v + 12400 from t_spend0), 'the overview''s spend is the application''s campaigns'' spend');
select pg_temp.check(coalesce((public.growth_overview('skiftly', 30) -> 'kpis' ->> 'spend')::numeric, 0)
                     = coalesce((select sum(ms.amount) from app.marketing_spend ms join app.ad_campaigns c on c.utm_campaign = ms.campaign
                                 where c.product = 'skiftly' and ms.currency = 'NOK' and ms.month >= date_trunc('month', now() - interval '30 days')), 0),
                     'another application does not carry it');
-- state: the record only
select pg_temp.expect_error(format('select public.ad_campaign_set_state(%L, %L)', (select id from t_c), 'paused'), 'invalid', 'a scheduled campaign cannot be paused');
select public.ad_campaign_set_state((select id from t_c), 'live');
select pg_temp.check((select state = 'live' and starts_on = current_date from app.ad_campaigns where id = (select id from t_c)), 'launching sets it live from today');
select public.ad_campaign_set_state((select id from t_c), 'paused');
select pg_temp.check((select state from app.ad_campaigns where id = (select id from t_c)) = 'paused', 'a live campaign can be paused');
select pg_temp.expect_error(format('select public.ad_campaign_save(%L, %L)', (select id from t_c), '{"channel":"facebook"}'), 'invalid', 'the channel is fixed once it has gone live');
select public.ad_campaign_save((select id from t_c), '{"ends_on":"2020-01-01","starts_on":null}');
select pg_temp.check((select x ->> 'state' from jsonb_array_elements(public.ad_campaigns_get('orgpuls') -> 'rows') x where (x ->> 'id')::uuid = (select id from t_c)) = 'ended',
                     'a campaign past its end date has ended');
select pg_temp.expect_error(format('select public.ad_campaign_set_state(%L, %L)', (select id from t_c), 'live'), 'invalid', 'an ended campaign cannot be resumed');
select pg_temp.expect_error(format('select public.ad_campaign_set_state(%L, %L, 1)', (select id from t_c), 'live'), 'version_conflict', 'an old version is refused');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error(format('select public.ad_campaign_set_state(%L, %L)', (select id from t_c), 'live'), 'forbidden', 'read-only staff cannot change a campaign');
select pg_temp.check(jsonb_array_length(public.ad_campaigns_get('orgpuls') -> 'rows') >= 2, 'read-only staff with Campaigns › See read them');

-- ---------------------------------------------------------------------------
-- SEO
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_k as select (public.seo_keyword_add('orgpuls', '  Growth   TEST søkeord ') ->> 'id')::uuid id;
select pg_temp.check((select query from app.seo_keywords where id = (select id from t_k)) = 'growth test søkeord', 'a keyword is stored lower case with single spaces');
select pg_temp.expect_error($$select public.seo_keyword_add('orgpuls', 'growth test søkeord')$$, 'invalid', 'a keyword is tracked once');
select pg_temp.expect_error($$select public.seo_keyword_add('skiftly', 'vaktplan')$$, 'invalid', 'an application without a site has no keywords');
select pg_temp.check((select s ->> 'connected' = 'false' and s -> 'totals' = 'null'::jsonb and (select x -> 'position' from jsonb_array_elements(s -> 'keywords') x where (x ->> 'id')::uuid = (select id from t_k)) = 'null'::jsonb
                      from (select public.seo_get('orgpuls', 30) s) x), 'while Search Console is not connected every figure is null');
update app.integration_connections set status = 'connected' where provider = 'search_console';
insert into app.search_console_daily (day, site_id, query, impressions, clicks, position) values
  (current_date - 1, (app.product_site('orgpuls')).id, 'growth test søkeord', 300, 30, 4),
  (current_date - 2, (app.product_site('orgpuls')).id, 'growth test søkeord', 100, 10, 8),
  (current_date - 40, (app.product_site('orgpuls')).id, 'growth test søkeord', 100, 5, 9);
create temp table t_s as select public.seo_get('orgpuls', 30) s;
select pg_temp.check((select (s -> 'totals' ->> 'clicks')::int = 40 and (s -> 'totals' ->> 'impressions')::int = 400 and (s -> 'totals' ->> 'position')::numeric = 5.0
                             and (s -> 'totals' ->> 'clicks_prev')::int = 5 from t_s), 'clicks and impressions sum, the position is weighted by impressions');
select pg_temp.check((select (x ->> 'position')::numeric = 5.0 and (x ->> 'position_prev')::numeric = 9.0
                      from t_s, jsonb_array_elements(s -> 'keywords') x where (x ->> 'id')::uuid = (select id from t_k)),
                     'a keyword carries its position now and in the period before');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error($$select public.seo_keyword_add('orgpuls', 'pulsundersøkelse')$$, 'forbidden', 'tracking a keyword needs Campaigns › Add');
select pg_temp.expect_error(format('select public.seo_keyword_remove(%L)', (select id from t_k)), 'forbidden', 'so does removing one');
select pg_temp.as_staff('jonas@orgpuls.no');
select public.seo_keyword_remove((select id from t_k));
select pg_temp.check(not exists (select 1 from app.seo_keywords where id = (select id from t_k)), 'Edit others removes a colleague''s keyword');

-- ---------------------------------------------------------------------------
-- email and automation (0060): the engine's new tests
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_seg as select (public.segment_save(null, 'Subscribed (test)', '{"filters":[{"f":"marketing_status","op":"eq","v":"subscribed"}]}') ->> 'id')::uuid id;
create temp table t_pp as select
  (select id from app.people where marketing_status = 'subscribed' and deleted_at is null order by created_at limit 1) yes,
  (select id from app.people where marketing_status is distinct from 'subscribed' and deleted_at is null order by created_at limit 1) no;
select pg_temp.check(app.wf_match('person', (select yes from t_pp), jsonb_build_array(jsonb_build_array(jsonb_build_object('f', 'segment', 'v', (select id from t_seg)))))
                 and not app.wf_match('person', (select no from t_pp), jsonb_build_array(jsonb_build_array(jsonb_build_object('f', 'segment', 'v', (select id from t_seg)))))
                 and app.wf_match('person', (select no from t_pp), jsonb_build_array(jsonb_build_array(jsonb_build_object('f', 'segment', 'op', 'neq', 'v', (select id from t_seg))))),
                     'a condition can ask whether the record''s person is on a list (and not on it)');
select pg_temp.check(app.wf_match('lead', (select l.id from app.leads l join app.people p on p.id = l.person_id where p.marketing_status = 'subscribed' limit 1),
                                  jsonb_build_array(jsonb_build_array(jsonb_build_object('f', 'segment', 'v', (select id from t_seg))))),
                     'a lead is on a list through its contact');
create temp table t_org as select
  (select o.id from app.organizations o where app.org_paying(o.id) and o.deleted_at is null limit 1) paying,
  (select o.id from app.organizations o where not app.org_paying(o.id) and o.deleted_at is null limit 1) free;
select pg_temp.check(app.wf_match('organization', (select paying from t_org), '[[{"f":"org_paying"}]]')
                 and app.wf_match('organization', (select free from t_org), '[[{"f":"org_paying","op":"neq"}]]')
                 and not app.wf_match('organization', (select free from t_org), '[[{"f":"org_paying"}]]'),
                     'a condition can ask whether the organisation pays');
select pg_temp.check(app.wf_match('organization', (select o.id from app.organizations o where app.org_milestone(o.id, 'employees_uploaded') limit 1), '[[{"f":"org_milestone","v":"employees_uploaded"}]]')
                 and not app.wf_match('organization', (select o.id from app.organizations o where app.org_milestone(o.id, 'employees_uploaded') limit 1), '[[{"f":"org_milestone","op":"neq","v":"employees_uploaded"}]]'),
                     'a condition can ask whether an activation milestone was reached');

-- the editor's save compiles onto the engine
create temp table t_seq as select public.simple_sequence_save(null, jsonb_build_object(
  'name', 'Webinar follow-up', 'trigger', 'deal_stage', 'stage_id', (select id from app.stages where name = 'Proposal sent' limit 1), 'list', (select id from t_seg),
  'exit', 'paying',
  'steps', jsonb_build_array(jsonb_build_object('kind', 'email', 'text', 'Takk for at du var med'), jsonb_build_object('kind', 'wait', 'days', 4),
                             jsonb_build_object('kind', 'cond', 'cond', 'employees_missing'), jsonb_build_object('kind', 'email', 'text', 'Book en gjennomgang'),
                             jsonb_build_object('kind', 'task', 'text', 'Ring kunden')))) r;
create temp table t_w as select (r ->> 'id')::uuid id from t_seq;
select pg_temp.check((select w.kind = 'workflow' and w.state = 'draft' and w.template_key = 'simple_sequence' and w.trigger_type = 'event'
                             and w.trigger_config ->> 'entity' = 'deal' and w.trigger_config ->> 'event' = 'stage_changed'
                             and w.trigger_config -> 'groups' -> 0 @> jsonb_build_array(jsonb_build_object('f', 'segment', 'v', (select id from t_seg)))
                             and jsonb_array_length(w.options -> 'simple' -> 'steps') = 5
                      from app.workflows w where w.id = (select id from t_w)), 'a simple campaign is a workflow: trigger, list and model are stored');
select pg_temp.check((select array_agg(x ->> 'kind' order by n) from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version,
                             jsonb_array_elements(v.graph -> 'steps') with ordinality t(x, n) where w.id = (select id from t_w))
                     = array['campaign_action', 'delay', 'condition', 'condition', 'campaign_action', 'condition', 'create_activity'],
                     'steps compile to campaign_action, delay, condition and create_activity, with «stop when» before each later email and task');
select pg_temp.check((select count(*) from app.campaigns c where c.type = 'automated' and c.status = 'draft' and c.deleted_at is null
                      and c.id in (select (x ->> 'campaign_id')::uuid from t_seq, jsonb_array_elements(r -> 'simple' -> 'steps') x where x ->> 'kind' = 'email')
                      and c.name like 'Webinar follow-up · %') = 2, 'each email is an automated campaign draft named after the sequence');
select pg_temp.check((select (x -> 'blockers') ? 'not_connected:email' and (x ->> 'enrolled')::int = 0 and jsonb_array_length(x -> 'emails') = 2
                             and (x -> 'emails' -> 0 -> 'stats') = 'null'::jsonb
                      from jsonb_array_elements(public.simple_sequences_get()) x where (x ->> 'id')::uuid = (select id from t_w)),
                     'the list carries what blocks activation, the runs started and each email''s figures (none yet)');
select pg_temp.expect_error(format('select public.workflow_set_state(%L, %L)', (select id from t_w), 'active'), 'invalid', 'without an email provider it cannot be activated');
-- change: the first email goes, the second gets a new subject
create temp table t_seq2 as select public.simple_sequence_save((select id from t_w), jsonb_build_object(
  'name', 'Webinar follow-up', 'trigger', 'deal_stage', 'stage_id', (select id from app.stages where name = 'Proposal sent' limit 1), 'list', null, 'exit', 'never',
  'steps', jsonb_build_array(jsonb_build_object('kind', 'wait', 'days', 2),
                             jsonb_build_object('kind', 'email', 'text', 'Book en gjennomgang nå', 'campaign_id', (select r -> 'simple' -> 'steps' -> 3 ->> 'campaign_id' from t_seq)))),
  (select (r ->> 'version')::int from t_seq)) r;
select pg_temp.check((select r -> 'simple' -> 'steps' -> 1 ->> 'campaign_id' from t_seq2) = (select r -> 'simple' -> 'steps' -> 3 ->> 'campaign_id' from t_seq)
                 and (select subject_a from app.campaigns where id = (select (r -> 'simple' -> 'steps' -> 3 ->> 'campaign_id')::uuid from t_seq)) = 'Book en gjennomgang nå',
                     'an email keeps its campaign and takes the new subject');
select pg_temp.check((select deleted_at is not null from app.campaigns where id = (select (r -> 'simple' -> 'steps' -> 0 ->> 'campaign_id')::uuid from t_seq)),
                     'an email taken out removes its draft');
select pg_temp.check((select not (trigger_config ? 'groups') or jsonb_array_length(trigger_config -> 'groups' -> 0) = 1 from app.workflows where id = (select id from t_w)),
                     'without a list the trigger is the stage alone');
select pg_temp.expect_error(format('select public.simple_sequence_save(%L, %L, 1)', (select id from t_w),
                            '{"name":"X","trigger":"form_submitted","exit":"never","steps":[{"kind":"task","text":"Ring"}]}'), 'version_conflict', 'an old version is refused');
select pg_temp.expect_error($$select public.simple_sequence_save(null, '{"name":"X","trigger":"trial_started","exit":"never","steps":[{"kind":"task","text":"Ring"}]}')$$,
                            'invalid', 'an account trigger is not available (no person to email)');
select pg_temp.expect_error($$select public.simple_sequence_save(null, '{"name":"X","trigger":"form_submitted","exit":"never","steps":[{"kind":"cond","cond":"on_list"}]}')$$,
                            'invalid', '«on the list» needs a list');
select pg_temp.expect_error($$select public.simple_sequence_save(null, '{"name":"X","trigger":"form_submitted","exit":"never","steps":[{"kind":"cond","cond":"opened_last"}]}')$$,
                            'invalid', 'campaign opens are not a condition the engine has');
select pg_temp.expect_error($$select public.simple_sequence_save(null, '{"name":"X","trigger":"form_submitted","exit":"never","steps":[{"kind":"wait","days":0}]}')$$,
                            'invalid', 'a wait is at least a day');
select pg_temp.expect_error($$select public.simple_sequence_save(null, '{"name":"X","trigger":"form_submitted","exit":"later","steps":[{"kind":"task","text":"Ring"}]}')$$,
                            'invalid', 'an unknown exit is refused');
create temp table t_pc as select (public.simple_sequence_save(null, '{"name":"Paying check","trigger":"form_submitted","exit":"paying","steps":[{"kind":"wait","days":1},{"kind":"cond","cond":"not_paying"},{"kind":"task","text":"Ring"}]}') ->> 'id')::uuid id;
select pg_temp.check((select array_agg(x ->> 'kind' order by n) from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version,
                             jsonb_array_elements(v.graph -> 'steps') with ordinality t(x, n) where w.id = (select id from t_pc))
                     = array['delay', 'condition', 'create_activity'], '«stop when» is not repeated right after the same condition');
-- a sequence of tasks only has nothing to send, so it runs
create temp table t_task as select (public.simple_sequence_save(null, '{"name":"Form follow-up","trigger":"form_submitted","exit":"never","steps":[{"kind":"task","text":"Call them"}]}') ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_task), 'active');
select pg_temp.check((select x ->> 'state' = 'active' and x ->> 'activated' = 'true' and jsonb_array_length(x -> 'blockers') = 0
                      from jsonb_array_elements(public.simple_sequences_get()) x where (x ->> 'id')::uuid = (select id from t_task)), 'a sequence without emails can be activated');
-- the engine's and the campaigns' rights hold
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check(not app.can('deals', 'workflows'), 'Marketing does not manage deal workflows');
select pg_temp.expect_error($$select public.simple_sequence_save(null, '{"name":"X","trigger":"form_submitted","exit":"never","steps":[{"kind":"email","text":"Hei"}]}')$$,
                            'forbidden', 'a lead-triggered campaign needs Deals › Manage workflows');
select pg_temp.check(jsonb_array_length(public.simple_sequences_get()) >= 2, 'every staff member reads the list');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_error(format('select public.simple_sequence_save(%L, %L)', (select id from t_task),
                            '{"name":"Mine","trigger":"form_submitted","exit":"never","steps":[{"kind":"task","text":"Ring"}]}'), 'forbidden', 'another person''s campaign is not changed without the rights');

rollback;
