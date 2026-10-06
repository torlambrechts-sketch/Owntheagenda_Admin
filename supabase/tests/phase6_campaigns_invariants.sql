-- phase6_campaigns_invariants.sql — email campaigns (0037; CMP-01..09, UF-17, SF-19, SF-39): closed tables, rights per
-- action, audiences that equal subscribed matches, consent and suppressions honoured at every step, the provider
-- refusal, the state machine, A/B, unsubscribe and provider events, frozen content, the engine's campaign step.
\ir _helpers.psql
begin;

-- expect_detail(sql, message, detail): the statement must raise with this message and this detail
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

-- ---------------------------------------------------------------------------
-- structure: closed tables, hashed tokens, no IP, workers for the service role only, helpers for nobody
create temp table t_tables as select unnest(array['email_template_versions', 'sender_domains', 'campaigns', 'campaign_links', 'campaign_recipients', 'campaign_events']) t;
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' and c.relrowsecurity
                      and c.relname in (select t from t_tables)) = 6, 'all six campaign tables exist with row level security on');
select pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'app' and tablename in (select t from t_tables)), 'no campaign table has a policy');
select pg_temp.check(not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'app' and g.table_name in (select t from t_tables)
                                 and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
                 and (select count(distinct g.table_name) from information_schema.role_table_grants g where g.table_schema = 'app'
                      and g.table_name in (select t from t_tables) and g.grantee = 'service_role') = 6, 'no client grant on a campaign table; the service role has them');
select pg_temp.check(not has_table_privilege('authenticated', 'app.' || t, 'select') and not has_table_privilege('anon', 'app.' || t, 'select'),
                     'client roles cannot select app.' || t) from t_tables;
select pg_temp.check(not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name in (select t from t_tables)
                                 and column_name ~ '(^|_)(ip|ip_address|user_agent)($|_)'), 'no campaign table stores an IP address or a user agent');
select pg_temp.check((select data_type from information_schema.columns where table_schema = 'app' and table_name = 'campaign_recipients' and column_name = 'unsub_token_sha256') = 'bytea'
                 and not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'campaign_recipients' and column_name ~ 'token' and data_type <> 'bytea'),
                     'the unsubscribe token is stored only as a hash');
select pg_temp.check(not has_function_privilege('authenticated', p, 'execute') and not has_function_privilege('anon', p, 'execute') and has_function_privilege('service_role', p, 'execute'),
                     'worker for the service role only: ' || p)
from unnest(array['public.worker_campaign_batch(uuid, int)', 'public.worker_campaign_sent(uuid, text)', 'public.worker_campaign_failed(uuid, text)',
                  'public.worker_unsubscribe(text, text, text)', 'public.worker_email_events(jsonb)', 'public.worker_sender_domain_status(uuid, jsonb)']) p;
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                 and p.proname in ('campaigns_get', 'campaign_get', 'campaign_save', 'campaign_duplicate', 'campaign_delete', 'campaign_preview', 'campaign_test_send',
                                                   'campaign_schedule', 'campaign_cancel', 'campaign_pause', 'campaigns_compare', 'campaign_recipients', 'campaign_export',
                                                   'marketing_templates_get', 'marketing_template_save', 'marketing_template_delete', 'segment_count', 'segments_get', 'segment_save',
                                                   'segment_delete', 'hygiene_candidates', 'hygiene_archive', 'sender_domains_get', 'sender_domain_save', 'sender_domain_delete',
                                                   'sender_domain_recheck', 'deliverability_recommendations')
                                 and (not p.prosecdef or not coalesce('search_path=""' = any (p.proconfig), false) or not has_function_privilege('authenticated', p.oid, 'execute')
                                      or has_function_privilege('anon', p.oid, 'execute')))
                 and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('campaigns_get', 'campaign_save', 'campaign_schedule', 'segment_count')) = 4,
                     'the campaign RPCs are security definers with an empty search path, for signed-in staff only');
select pg_temp.check(not has_function_privilege('authenticated', p, 'execute') and not has_function_privilege('anon', p, 'execute'), 'internal for nobody: ' || p)
from unnest(array['app.campaign_due()', 'app.campaign_resolve(app.campaigns)', 'app.campaign_enqueue(uuid, uuid, text)', 'app.campaign_stats(uuid)',
                  'app.campaign_take(uuid, text)', 'app.segment_sql(jsonb, boolean)', 'app.marketing_skip(text, text)', 'app.campaign_ab_decide()',
                  'app.campaign_unsubscribe(app.campaign_recipients, text, text)', 'app.wf_step(app.workflow_runs, app.workflows, text, jsonb, uuid)']) p;
select pg_temp.check(exists (select 1 from app.entities where key = 'campaign' and tbl = 'campaigns' and scope = 'campaigns' and module = 'campaigns' and owned)
                 and app.entity_route('campaign') = '/campaigns', 'campaign is a record type in the campaigns scope, opening on /campaigns');
select pg_temp.check((select applies_to from app.settings_registry where key = 'tracking') like '%CMP-06%', 'the tracking rule applies to campaign figures (CMP-06)');
select pg_temp.check(exists (select 1 from pg_constraint where conname = 'suppressions_campaign_fk' and conrelid = 'app.suppressions'::regclass), 'a suppression names its campaign by foreign key');
select pg_temp.check((select count(*) from cron.job where jobname in ('platform-campaign-due', 'platform-campaign-ab', 'platform-campaign-prune', 'platform-dns-check')) = 4,
                     'the campaign jobs are scheduled');
select pg_temp.check((select count(*) from app.email_templates where kind = 'marketing' and layout and deleted_at is null and name in ('Newsletter', 'Product announcement')) = 2
                 and not exists (select 1 from app.email_templates where kind = 'marketing' and layout and design::text ~* '(fem er gulvet|minst 5)'),
                     'two starting layouts are seeded, without product claims (Q18)');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_error($$select public.setting_set('campaign_rules', 'fixed')$$, 'fixed_setting', 'the campaign rules are fixed (D-27)');

-- ---------------------------------------------------------------------------
-- fixture: an organisation on trial with a product user; people tagged P6C-HR in every marketing state
select pg_temp.as_nobody();
create temp table t_ids as select gen_random_uuid() org, gen_random_uuid() acct,
  (select id from app.admins where email = 'tor@orgpuls.no') tor, (select id from app.admins where email = 'jonas@orgpuls.no') jonas,
  (select id from app.admins where email = 'ingrid@orgpuls.no') ingrid;
insert into app.accounts (id, name, org_number) select acct, 'P6C Konto AS', '987650001' from t_ids;
insert into app.account_products (product, tenant_id, account_id) select 'orgpuls', 'p6c-tenant', acct from t_ids;
insert into app.subscriptions (product, tenant_id, trial_started_at, trial_ends_at) values ('orgpuls', 'p6c-tenant', now() - interval '3 days', now() + interval '11 days');
insert into app.members (product, tenant_id, user_id, role, email) values ('orgpuls', 'p6c-tenant', 'p6c-u1', 'hr', 'p6c.sub1@example.no');
insert into app.organizations (id, name, employees, fylke, account_id) select org, 'P6C Bygg AS', 50, 'Vestland', acct from t_ids;
create temp table t_p (k text primary key, id uuid not null default gen_random_uuid());
insert into t_p (k) values ('sub1'), ('sub2'), ('sub3'), ('dup'), ('pend'), ('unsub'), ('nocons'), ('supp'), ('noemail'), ('private');
insert into app.people (id, name, email, title, marketing_status, organization_id, owner_id, visibility, member_product, member_tenant, member_user)
select p.id, 'P6C ' || initcap(p.k) || ' Person',
       case p.k when 'noemail' then null when 'dup' then 'P6C.Sub1@Example.no' else 'p6c.' || p.k || '@example.no' end, 'P6C-HR',
       case p.k when 'pend' then 'pending' when 'unsub' then 'unsubscribed' when 'nocons' then 'no_consent' else 'subscribed' end,
       case when p.k in ('sub1', 'dup') then (select org from t_ids) end,
       (select tor from t_ids), case when p.k = 'private' then 'owner' else 'all' end,
       case when p.k = 'sub1' then 'orgpuls' end, case when p.k = 'sub1' then 'p6c-tenant' end, case when p.k = 'sub1' then 'p6c-u1' end
from t_p p;
insert into app.suppressions (email_sha256, scope, reason) values (app.email_hash('p6c.supp@example.no'), 'marketing', 'manual');
create temp table t_q as select '{"filters":[{"f":"title","op":"eq","v":"P6C-HR"}]}'::jsonb q;
create temp table t_html as select '<table><tr><td><p>Hei [Person.fornavn]</p><a href="https://orgpuls.com/sjekkliste">Les</a> <a href="https://orgpuls.com/pris">Pris</a></td></tr>'
  || '<tr><td>P6C Test AS, Postboks 1, 0101 Oslo · <a href="[Unsubscribe]">Meld deg av</a></td></tr></table>' h;

-- ---------------------------------------------------------------------------
-- rights per action and the module switch
select pg_temp.as_nobody();
select pg_temp.expect_error($$select public.campaigns_get()$$, 'not_signed_in', 'nobody lists campaigns');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.campaigns_get()$$, 'forbidden', 'campaigns:see', 'Sales without campaigns:see cannot list campaigns');
select pg_temp.expect_detail($$select public.campaign_save(null, '{"type":"newsletter","name":"x"}')$$, 'forbidden', 'campaigns:add', 'Sales cannot create a campaign');
select pg_temp.expect_detail(format('select public.segment_count(%L)', (select q from t_q)), 'forbidden', 'campaigns:see', 'Sales cannot count an audience');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check(jsonb_typeof(public.campaigns_get() -> 'rows') = 'array', 'the read-only analyst lists campaigns');
select pg_temp.expect_detail($$select public.campaign_save(null, '{"type":"newsletter","name":"x"}')$$, 'forbidden', 'campaigns:add', 'the analyst cannot create a campaign');
select pg_temp.expect_detail($$select public.sender_domain_save(null, '{"domain":"x.example.no","stream":"marketing","from_name":"X"}')$$, 'forbidden', 'campaigns:configure',
                             'the analyst cannot add a sender domain');
select pg_temp.expect_detail($$select public.hygiene_archive(0)$$, 'forbidden', 'campaigns:bulk', 'the analyst cannot archive for hygiene');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail($$select public.sender_domain_save(null, '{"domain":"x.example.no","stream":"marketing","from_name":"X"}')$$, 'forbidden', 'campaigns:configure',
                             'Marketing cannot configure sender domains (§6)');
select pg_temp.expect_detail($$select public.hygiene_archive(0)$$, 'forbidden', 'campaigns:bulk', 'Marketing cannot bulk-archive (§6)');
select pg_temp.expect_detail($$select public.sender_domain_recheck()$$, 'forbidden', 'campaigns:configure', 'Marketing cannot queue DNS checks');
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('campaigns', false);
select pg_temp.expect_detail($$select public.campaigns_get()$$, 'module_off', 'campaigns', 'a switched-off module refuses its functions');
select pg_temp.expect_detail($$select public.rec_list('campaign')$$, 'module_off', 'campaigns', 'the generic record path honours the module too');
select public.module_set('campaigns', true);

-- ---------------------------------------------------------------------------
-- audience (CMP-03): matches, and receivable = subscribed, with an address, not suppressed, once per address
select pg_temp.check(public.segment_count((select q from t_q)) = '{"matches":10,"receivable":4}'::jsonb,
                     'the admin sees 10 matches and 4 receivable addresses (pending, unsubscribed, no consent, suppressed, no address and a repeated address excluded)');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check(public.segment_count((select q from t_q)) = '{"matches":9,"receivable":3}'::jsonb, 'a person private to another owner is not in Marketing''s count (D-09)');
select pg_temp.expect_detail($$select public.segment_count('{"filters":[{"f":"nope","op":"eq","v":1}]}')$$, 'invalid', 'filter.nope', 'an unknown field is refused');
select pg_temp.check((public.segment_count('{"filters":[{"f":"title","op":"eq","v":"P6C-HR"},{"f":"organization.employees","op":"gte","v":26},{"f":"organization.employees","op":"lte","v":100}]}') ->> 'matches')::int = 2
                 and (public.segment_count('{"filters":[{"f":"title","op":"eq","v":"P6C-HR"},{"f":"organization.status","op":"eq","v":"trial"}]}') ->> 'matches')::int = 2
                 and (public.segment_count('{"filters":[{"f":"title","op":"eq","v":"P6C-HR"},{"f":"member.role","op":"eq","v":"hr"}]}') ->> 'matches')::int = 1
                 and (public.segment_count('{"filters":[{"f":"title","op":"eq","v":"P6C-HR"},{"or":[[{"f":"organization.fylke","op":"eq","v":"Vestland"}],[{"f":"marketing_status","op":"eq","v":"pending"}]]}]}') ->> 'matches')::int = 3
                 and (public.segment_count('{"filters":[{"f":"title","op":"eq","v":"P6C-HR"},{"f":"engagement.opened_days","op":"lte","v":90}]}') ->> 'matches')::int = 0,
                     'the audience fields: organization columns and trial status, product role, OR groups, days since the last open');
create temp table t_seg as select (public.segment_save(null, 'P6C HR', (select q from t_q), 'HR at test organisations') ->> 'id')::uuid id;
select pg_temp.check((select kind = 'segment' and screen = 'people' and shared and owner_id = (select jonas from t_ids) from app.saved_views where id = (select id from t_seg)),
                     'a segment is a shared saved view of people');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.segments_get()) s where (s ->> 'id')::uuid = (select id from t_seg) and (s ->> 'receivable')::int = 3),
                     'saved segments carry their counts, computed on open');
select pg_temp.check((public.view_delete((select id from t_seg)) ->> 'ok')::boolean = false and exists (select 1 from app.saved_views where id = (select id from t_seg)),
                     'the generic view path does not delete a segment');
create temp table t_seg0 as select (public.segment_save(null, 'P6C nobody', '{"filters":[{"f":"title","op":"eq","v":"P6C-NOBODY"}]}') ->> 'id')::uuid id;
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail(format('select public.segment_delete(%L)', (select id from t_seg0)), 'forbidden', 'campaigns:delete', 'the analyst cannot delete a segment');

-- ---------------------------------------------------------------------------
-- marketing templates (CMP-02): one store, layouts configured, versions append-only
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check((select count(*) from jsonb_array_elements(public.marketing_templates_get()) x where (x ->> 'layout')::boolean and x ->> 'name' in ('Newsletter', 'Product announcement')) = 2,
                     'Marketing sees the two layouts');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.templates_get()) x where x ->> 'name' in ('Newsletter', 'Product announcement')),
                     'the Inbox''s templates stay the sales ones');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail($$select public.marketing_template_save(null, '{"name":"Own HTML","html":"<table><tr><td>Hei</td></tr></table>"}')$$, 'invalid', 'html.footer',
                             'hand-written HTML without [Unsubscribe] is refused');
select pg_temp.expect_detail($$select public.marketing_template_save(null, '{"name":"Bad","html":"<script>x</script>[Unsubscribe]"}')$$, 'invalid', 'html', 'a script is refused');
select pg_temp.expect_detail($$select public.marketing_template_save(null, '{"name":"Bad","subject":"[Foo.bar]"}')$$, 'invalid', 'merge:Foo.bar', 'an unknown merge token is refused');
select pg_temp.expect_detail(format('select public.marketing_template_save(%L, %L)', (select id from app.email_templates where kind = 'marketing' and layout and name = 'Newsletter'),
                                    '{"name":"Mine now"}'), 'forbidden', 'campaigns:configure', 'a layout is changed only with campaigns:configure');
create temp table t_tpl as select (public.marketing_template_save(null, '{"name":"Webinar invite","scope":"shared","subject":"Webinar for [Person.fornavn]","html":"<table><tr><td>Hei</td></tr><tr><td><a href=\"[Unsubscribe]\">Av</a></td></tr></table>"}') ->> 'id')::uuid id;
select public.marketing_template_save((select id from t_tpl), '{"name":"Webinar invite (v2)"}', 1);
select pg_temp.check((select current_version from app.email_templates where id = (select id from t_tpl)) = 2
                 and (select count(*) from app.email_template_versions where template_id = (select id from t_tpl)) = 2, 'every save writes a template version');
select pg_temp.expect_detail(format('select public.marketing_template_save(%L, %L, 1)', (select id from t_tpl), '{"name":"stale"}'), 'version_conflict', '2', 'a stale template version is refused');
select pg_temp.expect_error(format('update app.email_template_versions set subject = %L where template_id = %L', 'changed', (select id from t_tpl)),
                            'a template version is fixed', 'a template version cannot be changed');
select pg_temp.expect_detail(format('select public.marketing_template_delete(%L)', (select id from t_tpl)), 'forbidden', 'campaigns:delete', 'Marketing cannot delete a template');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_error(format('select public.template_save(%L, %L)', (select id from t_tpl), '{"name":"via the inbox"}'), 'not_found', 'the Inbox''s template path cannot change a marketing template');
create temp table t_tpl2 as select (public.marketing_template_save(null, '{"name":"Throwaway"}') ->> 'id')::uuid id;
select public.marketing_template_delete((select id from t_tpl2));
select pg_temp.check((select deleted_at is not null from app.email_templates where id = (select id from t_tpl2)), 'a template can be deleted with campaigns:delete');

-- ---------------------------------------------------------------------------
-- campaigns: drafts (CMP-01): the design's footer is fixed, the coupon only on a promotion, UTM unique
select pg_temp.as_staff('jonas@orgpuls.no');
create temp table t_c as select (public.campaign_save(null, jsonb_build_object('type', 'newsletter', 'name', 'Nyhetsbrev oktober P6C',
  'template_id', (select id from app.email_templates where kind = 'marketing' and layout and name = 'Newsletter'))) ->> 'id')::uuid id;
select pg_temp.check((select status = 'draft' and owner_id = (select jonas from t_ids) and utm_campaign = 'nyhetsbrev-oktober-p6c-' || to_char(now() at time zone 'Europe/Oslo', 'YYYY-MM')
                             and utm_source = 'newsletter' and utm_medium = 'email' and design -> 'rows' -> -1 ->> 'kind' = 'footer'
                      from app.campaigns where id = (select id from t_c)), 'a template starts a draft: its design, a UTM slug of the name and the month (CMP-02)');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_c), '{"design":{"rows":[{"kind":"footer"},{"kind":"title","text":"x"}]}}'),
                             'invalid', 'design.footer', 'the footer must be the last row');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_c), '{"design":{"rows":[{"kind":"title","text":"x"}]}}'),
                             'invalid', 'design.footer', 'the footer cannot be removed (D-27)');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_c), '{"design":{"rows":[{"kind":"footer","text":"Something else"}]}}'),
                             'invalid', 'design.0.text', 'the footer cannot be edited, apart from its background');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_c), '{"design":{"rows":[{"kind":"html","html":"<iframe src=x>"},{"kind":"footer"}]}}'),
                             'invalid', 'design.0.html', 'an HTML block is sanitised');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_c), '{"coupon_code":"HMS2026"}'), 'invalid', 'coupon_code', 'only an active coupon on a promotion');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L, 99)', (select id from t_c), '{"name":"x"}'), 'version_conflict', '1', 'a stale campaign version is refused');
select public.campaign_save((select id from t_c), jsonb_build_object('subject_a', 'Slik kartlegger dere arbeidsmiljøet, [Person.fornavn]', 'subject_b', 'Lovkravet dere må dokumentere',
                                                                     'notify_owners', true, 'segment_id', (select id from t_seg)));
select pg_temp.check((select ab_percent = 20 and ab_metric = 'clicks' and ab_wait = interval '4 hours' from app.campaigns where id = (select id from t_c)),
                     'a subject B turns on the A/B test with 20 %, clicks and four hours (Q17)');
select pg_temp.expect_detail(format('select public.campaign_save(null, %L)', jsonb_build_object('type', 'one_off', 'name', 'Other', 'utm_campaign',
                                    (select utm_campaign from app.campaigns where id = (select id from t_c)))), 'invalid', 'utm_campaign', 'a UTM campaign is unique');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_c), '{"name":"x"}'), 'forbidden', 'campaigns:add', 'the analyst cannot edit a campaign');
select pg_temp.check((public.campaign_get((select id from t_c)) ->> 'status') = 'draft', 'the analyst reads a campaign');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check((select (r -> 'audience' ->> 'count')::int = 3 and (r -> 'audience' ->> 'live')::boolean and r -> 'stats' = 'null'::jsonb
                      from jsonb_array_elements(public.campaigns_get('{"type":"newsletter"}') -> 'rows') r where (r ->> 'id')::uuid = (select id from t_c)),
                     'a draft lists its live audience estimate and no figures');
create temp table t_pv as select public.campaign_preview((select id from t_c), (select id from t_p where k = 'sub2'), '<p>Hei [Person.fornavn] i [Organisasjon.navn]</p>') v;
select pg_temp.check((select v ->> 'html' from t_pv) = '<p>Hei P6C i [Organisasjon.navn]</p>' and (select v -> 'missing' from t_pv) = '["Organisasjon.navn"]'::jsonb
                 and (select v ->> 'subject_a' from t_pv) = 'Slik kartlegger dere arbeidsmiljøet, P6C', 'the preview merges a chosen person and lists what has no value');
select pg_temp.check((public.campaign_preview((select id from t_c), null, '<p>[Organisasjon.navn]</p>') -> 'audience_missing') = '[{"token":"Organisasjon.navn","people":2}]'::jsonb,
                     'before scheduling, the receivable people without a value are counted per token (COM-05)');

-- ---------------------------------------------------------------------------
-- scheduling (CMP-05, CMP-08): refused with the field until the domain, the content and the audience are right
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c), (select h from t_html)), 'invalid', 'sender_domain',
                             'no sender domain, no schedule');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_dom as select (public.sender_domain_save(null, '{"domain":"news.p6c.example.no","stream":"marketing","from_name":"P6C Test","warmup_started_at":"2026-09-28"}') ->> 'id')::uuid id;
select public.sender_domain_save(null, '{"domain":"varsler.p6c.example.no","stream":"transactional","sends_here":false,"from_name":"P6C varsler"}');
select pg_temp.check(exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'dns_check' and message ->> 'sender_domain_id' = (select id::text from t_dom)),
                     'a new domain is DNS-checked at once');
select pg_temp.expect_detail(format('select public.sender_domain_save(%L, %L)', (select id from t_dom), '{"domain":"other.p6c.example.no"}'), 'invalid', 'domain', 'a domain''s name is fixed');
select pg_temp.as_staff('jonas@orgpuls.no');
select public.campaign_save((select id from t_c), jsonb_build_object('sender_domain_id', (select id from t_dom)));
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c), (select h from t_html)), 'invalid', 'sender_domain',
                             'an unauthenticated domain cannot schedule (CMP-08)');
select pg_temp.as_nobody();
select public.worker_sender_domain_status((select id from t_dom), '{"spf_ok":true,"dkim_ok":true,"dmarc_policy":"quarantine","verified":true}');
select pg_temp.check((select spf_ok and dkim_ok and dmarc_policy = 'quarantine' and verified_at is null from app.sender_domains where id = (select id from t_dom)),
                     'DNS checks run without the provider; «verified» is never set without it');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c), (select h from t_html)), 'invalid', 'sender_domain.postal_address',
                             'sender identity: the domain needs its postal address (D-27)');
select pg_temp.as_staff('tor@orgpuls.no');
select public.sender_domain_save((select id from t_dom), '{"postal_address":"P6C Test AS, Postboks 1, 0101 Oslo"}');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c), '<table><tr><td>Hei</td></tr></table>'), 'invalid', 'html.footer',
                             'HTML without the unsubscribe link is refused');
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c), '<p>Hei</p><a href="[Unsubscribe]">Av</a>'), 'invalid', 'html.footer',
                             'HTML without the sender''s postal address is refused');
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c), (select h || '<script>x</script>' from t_html)), 'invalid', 'html',
                             'HTML with a script is refused');
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c), (select h || '[Foo.bar]' from t_html)), 'invalid', 'merge:Foo.bar',
                             'an unknown merge field is refused');
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now() - interval ''1 day'', null, %L)', (select id from t_c), (select h from t_html)), 'invalid', 'scheduled_at',
                             'a time in the past is refused');
create temp table t_c0 as select (public.campaign_save(null, jsonb_build_object('type', 'one_off', 'name', 'Nobody P6C', 'subject_a', 'Hei', 'segment_id', (select id from t_seg0),
                                                                                'sender_domain_id', (select id from t_dom))) ->> 'id')::uuid id;
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c0), (select h from t_html)), 'invalid', 'audience',
                             'nobody who can receive it, no schedule');
select pg_temp.expect_detail(format('select public.campaign_test_send(%L, %L)', (select id from t_c), (select h from t_html)), 'not_connected', 'email',
                             'a test send needs the email provider');
-- scheduled without the provider (the database lets you build, schedule and count)
select public.campaign_schedule((select id from t_c), now(), (select version from app.campaigns where id = (select id from t_c)), (select h from t_html));
select pg_temp.check((select status = 'scheduled' and rendered_html = (select h from t_html) and audience_name = 'P6C HR' and tracking from app.campaigns where id = (select id from t_c)),
                     'scheduling freezes the HTML and the audience''s name');
select pg_temp.check((select count(*) from app.campaign_links where campaign_id = (select id from t_c)) = 2, 'the frozen HTML''s links are registered (the unsubscribe token is not one)');
select pg_temp.check(exists (select 1 from app.events where kind = 'campaign.scheduled' and subject_id = (select id from t_c) and payload @> '{"type":"newsletter","audience_count":3}'),
                     'campaign.scheduled carries the type and the audience count');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_c), '{"subject_a":"Changed"}'), 'invalid', 'status', 'a scheduled campaign''s content cannot be saved');
select public.campaign_save((select id from t_c), '{"name":"Nyhetsbrev oktober P6C"}');
select pg_temp.expect_error(format('update app.campaigns set rendered_html = %L where id = %L', '<p>other</p>', (select id from t_c)),
                            'a scheduled or sent campaign''s content is fixed', 'the frozen HTML cannot be changed, by any path');
select pg_temp.expect_error(format('update app.campaign_links set url = %L where campaign_id = %L', 'https://evil.example', (select id from t_c)),
                            'a sent campaign''s links are fixed', 'the links cannot be changed');
select pg_temp.expect_detail(format('select public.campaign_delete(array[%L]::uuid[])', (select id from t_c)), 'forbidden', 'campaigns:delete', 'Marketing has no delete right');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format('select public.campaign_delete(array[%L]::uuid[])', (select id from t_c)), 'invalid', 'status', 'only a draft can be deleted');
select pg_temp.expect_error(format('select public.rec_delete(%L, array[%L]::uuid[])', 'campaign', (select id from t_c)), 'a sent campaign is kept for its report',
                            'the generic delete cannot remove a scheduled campaign');
select pg_temp.expect_error(format('update app.campaigns set status = %L where id = %L', 'draft', (select id from t_c)), 'a campaign cannot move from scheduled to draft',
                            'status follows the state machine');
select pg_temp.expect_detail(format('select public.segment_delete(%L)', (select id from t_seg)), 'invalid', 'in_use', 'a segment a scheduled campaign still needs cannot be deleted');

-- ---------------------------------------------------------------------------
-- due: held without the provider, then without a verified domain; started once both are there
select pg_temp.as_nobody();
select app.campaign_due();
select pg_temp.check((select status = 'scheduled' and hold_reason = 'not_connected:email' from app.campaigns where id = (select id from t_c))
                 and not exists (select 1 from app.campaign_recipients where campaign_id = (select id from t_c)), 'a due campaign waits for the provider, nobody is resolved');
select app.campaign_due();
select pg_temp.check((select count(*) from app.notifications where staff_id = (select jonas from t_ids) and key = 'campaign.held' and record_id = (select id from t_c)) = 1,
                     'the owner is told once per hold reason');
select pg_temp.expect_detail(format('select public.worker_campaign_batch(%L)', (select id from t_c)), 'not_connected', 'email', 'the send worker needs the provider');
update app.integration_connections set status = 'connected' where provider = 'email';
select app.campaign_due();
select pg_temp.check((select status = 'scheduled' and hold_reason = 'sender_domain' from app.campaigns where id = (select id from t_c)), 'an unverified domain holds the send (CMP-08)');
select public.worker_sender_domain_status((select id from t_dom), '{"verified":true,"provider_domain_id":"dom-1"}');
select pg_temp.check((select verified_at is not null from app.sender_domains where id = (select id from t_dom)), 'the provider verifies the domain once connected');
select pg_temp.as_staff('jonas@orgpuls.no');
create temp table t_ts as select public.campaign_test_send((select id from t_c)) r;
select pg_temp.check((select r from t_ts) = '{"to":"jonas@orgpuls.no","queued":true}'::jsonb
                 and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'campaign_test' and message ->> 'to' = 'jonas@orgpuls.no' and message ->> 'campaign_id' = (select id::text from t_c))
                 and not exists (select 1 from app.campaign_recipients where campaign_id = (select id from t_c)), 'a test goes to the caller''s own address and is not a recipient');
select pg_temp.as_nobody();
select pg_temp.as_staff('jonas@orgpuls.no');
create temp table t_expect as select (public.segment_count((select q from t_q)) ->> 'receivable')::int n;
select pg_temp.as_nobody();
select app.campaign_due();
select pg_temp.check((select status = 'sending' and hold_reason is null and started_at is not null and audience_count = (select n from t_expect) from app.campaigns where id = (select id from t_c)),
                     'the campaign starts; its frozen audience equals the owner''s receivable count (CMP-03)');
select pg_temp.check((select count(*) from app.campaign_recipients where campaign_id = (select id from t_c) and state = 'queued') = 3
                 and (select skip_reason from app.campaign_recipients where campaign_id = (select id from t_c) and person_id = (select id from t_p where k = 'pend')) = 'not_subscribed'
                 and (select skip_reason from app.campaign_recipients where campaign_id = (select id from t_c) and person_id = (select id from t_p where k = 'unsub')) = 'not_subscribed'
                 and (select skip_reason from app.campaign_recipients where campaign_id = (select id from t_c) and person_id = (select id from t_p where k = 'supp')) = 'suppressed'
                 and (select skip_reason from app.campaign_recipients where campaign_id = (select id from t_c) and person_id = (select id from t_p where k = 'noemail')) = 'no_email'
                 and (select count(*) from app.campaign_recipients where campaign_id = (select id from t_c) and person_id in (select id from t_p where k in ('sub1', 'dup'))
                      and ((state = 'queued') or skip_reason = 'duplicate')) = 2
                 and not exists (select 1 from app.campaign_recipients where campaign_id = (select id from t_c) and person_id = (select id from t_p where k = 'private'))
                 and not exists (select 1 from app.campaign_recipients where campaign_id = (select id from t_c) and state = 'skipped' and email is not null),
                     'pending double opt-in, unsubscribed, suppressed, addressless and repeated addresses are skipped with the reason; skipped rows keep no address');
select pg_temp.check((select count(*) filter (where variant = 'a') = 1 and count(*) filter (where variant = 'b') = 1 and count(*) filter (where variant = 'w') = 1
                      from app.campaign_recipients where campaign_id = (select id from t_c) and state = 'queued'), 'A/B: a test group for A and for B, the rest waits for the winner');
select pg_temp.check(exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'campaign_send' and message ->> 'campaign_id' = (select id::text from t_c)), 'a send job is queued');

-- the send worker: the test groups first, merged per person, a fresh unsubscribe token each, kept only as a hash
create temp table t_b as select public.worker_campaign_batch((select id from t_c), 50) b;
select pg_temp.check(jsonb_array_length((select b -> 'recipients' from t_b)) = 2
                 and not exists (select 1 from jsonb_array_elements((select b -> 'recipients' from t_b)) x where x ->> 'variant' = 'w'), 'the winner''s group waits for the decision');
create temp table t_r as select (x ->> 'id')::uuid id, x ->> 'variant' variant, x ->> 'unsub_token' tok, x ->> 'subject' subject, x ->> 'html' html
  from jsonb_array_elements((select b -> 'recipients' from t_b)) x;
select pg_temp.check((select subject from t_r where variant = 'b') = 'Lovkravet dere må dokumentere' and (select subject from t_r where variant = 'a') ~ '^Slik kartlegger dere arbeidsmiljøet, P6C$'
                 and (select bool_and(html ~ 'Hei P6C' and html ~ '\[Unsubscribe\]') from t_r), 'each recipient gets their subject variant with merge fields resolved');
select pg_temp.check((select bool_and(r.unsub_token_sha256 = app.token_hash(t.tok)) from t_r t join app.campaign_recipients r on r.id = t.id), 'the unsubscribe token is stored as its SHA-256');
select pg_temp.check((select b -> 'campaign' ->> 'from' from t_b) = 'news@news.p6c.example.no' and jsonb_array_length((select b -> 'campaign' -> 'links' from t_b)) = 2,
                     'the batch carries the sender identity and the tracked links');
select public.worker_campaign_sent((select id from t_r where variant = 'a'), 'msg-p6c-a');
select public.worker_campaign_sent((select id from t_r where variant = 'b'), 'msg-p6c-b');
select pg_temp.check((select status from app.campaigns where id = (select id from t_c)) = 'sending', 'still sending while the winner''s group waits');
-- provider events: delivered, a prefetch and a human open, a click; a duplicate; a survey-stream event that names nobody
create temp table t_ev as select public.worker_email_events(jsonb_build_array(
  jsonb_build_object('event_id', 'p6c-e1', 'kind', 'delivered', 'message_id', 'msg-p6c-a', 'at', now()),
  jsonb_build_object('event_id', 'p6c-e2', 'kind', 'delivered', 'message_id', 'msg-p6c-b', 'at', now()),
  jsonb_build_object('event_id', 'p6c-e3', 'kind', 'opened', 'message_id', 'msg-p6c-a', 'client_class', 'prefetch', 'city', 'Prefetchby'),
  jsonb_build_object('event_id', 'p6c-e4', 'kind', 'opened', 'message_id', 'msg-p6c-a', 'client_class', 'human', 'city', 'Bergen', 'country', 'NO'),
  jsonb_build_object('event_id', 'p6c-e5', 'kind', 'clicked', 'message_id', 'msg-p6c-b', 'client_class', 'human',
                     'link_token', (select token from app.campaign_links where campaign_id = (select id from t_c) and url = 'https://orgpuls.com/pris')),
  jsonb_build_object('event_id', 'p6c-e4', 'kind', 'opened', 'message_id', 'msg-p6c-a', 'client_class', 'human'),
  jsonb_build_object('event_id', 'svar-1', 'kind', 'delivered', 'message_id', 'survey-invitation-123'))) r;
select pg_temp.check((select r from t_ev) = '{"processed":5,"duplicates":1,"unknown":1}'::jsonb, 'events are idempotent; an event that names no recipient is not stored');
select pg_temp.check(not exists (select 1 from app.campaign_events where provider_event_id = 'svar-1'), 'survey-invitation events never enter the platform (D-34)');
create temp table t_s as select app.campaign_stats((select id from t_c)) s;
select pg_temp.check((select (s ->> 'delivered')::int = 2 and (s ->> 'unique_opens')::int = 1 and (s ->> 'total_opens')::int = 1 and (s ->> 'unique_clicks')::int = 1
                             and (s ->> 'open_rate')::numeric = 50.0 and (s ->> 'click_rate')::numeric = 50.0 and (s ->> 'ctor')::numeric = 100.0
                             and (s ->> 'a_metric')::numeric = 0.0 and (s ->> 'b_metric')::numeric = 100.0 from t_s),
                     'figures: prefetch opens excluded, rates over delivered, click-through over unique opens, A/B by clicks (CMP-06)');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check((public.campaign_get((select id from t_c)) -> 'top_locations') = '["Bergen"]'::jsonb, 'top locations come from the provider''s geo of human opens only');
select pg_temp.check((select r -> 'stats' from jsonb_array_elements(public.campaigns_get() -> 'rows') r where (r ->> 'id')::uuid = (select id from t_c)) = app.campaign_stats((select id from t_c))
                 and (public.campaigns_compare(array[(select id from t_c)]) -> 'rows' -> 0 -> 'stats') = app.campaign_stats((select id from t_c)),
                     'the list, the card and the comparison print the same figures (CMP-09)');
select pg_temp.as_nobody();
select pg_temp.check((select count(*) from app.events where kind = 'campaign.delivered' and payload ->> 'campaign' = (select id::text from t_c)) = 2
                 and (select count(*) from app.events where kind = 'campaign.opened' and payload ->> 'campaign' = (select id::text from t_c)) = 1
                 and exists (select 1 from app.events where kind = 'campaign.clicked' and subject_type = 'person' and payload ? 'link'), 'delivered, opened (not for prefetch) and clicked are emitted about the person');
select pg_temp.check((select count(*) from app.notifications where staff_id = (select tor from t_ids) and key = 'campaign.engaged' and params ->> 'campaign' = 'Nyhetsbrev oktober P6C') = 2, 'owners are notified of a person''s first engagement');
-- A/B decision after the wait, then the rest gets the winner
select pg_temp.check(app.campaign_ab_decide() = 0, 'no decision before the wait is over');
update app.campaigns set started_at = now() - interval '5 hours' where id = (select id from t_c);
select app.campaign_ab_decide();
select pg_temp.check((select ab_winner from app.campaigns where id = (select id from t_c)) = 'b'
                 and exists (select 1 from app.notifications where key = 'campaign.ab_decided' and record_id = (select id from t_c)), 'B wins on clicks; the owner hears it');
create temp table t_b2 as select public.worker_campaign_batch((select id from t_c), 50) b;
insert into t_r select (x ->> 'id')::uuid, x ->> 'variant', x ->> 'unsub_token', x ->> 'subject', x ->> 'html' from jsonb_array_elements((select b -> 'recipients' from t_b2)) x;
select pg_temp.check((select subject from t_r where variant = 'w') = 'Lovkravet dere må dokumentere', 'the rest is sent the winning subject');
select public.worker_campaign_sent((select id from t_r where variant = 'w'), 'msg-p6c-w');
select pg_temp.check((select status = 'sent' and sent_at is not null from app.campaigns where id = (select id from t_c))
                 and exists (select 1 from app.events where kind = 'campaign.sent' and subject_id = (select id from t_c) and payload @> '{"audience_count":3}')
                 and exists (select 1 from app.notifications where staff_id = (select jonas from t_ids) and key in ('campaign.sent', 'campaign.sent_with_problems') and record_id = (select id from t_c)),
                     'with nobody left in the queue the campaign is sent, emitted and reported to its owner');
select pg_temp.expect_error(format('update app.campaigns set ab_winner = %L where id = %L', 'a', (select id from t_c)), 'a scheduled or sent campaign''s content is fixed',
                            'a decided winner cannot be changed');

-- ---------------------------------------------------------------------------
-- unsubscribe (one click, honoured in the same transaction), complaint, hard bounce, five soft bounces
select public.worker_unsubscribe((select tok from t_r where variant = 'a'), 'marketing', 'one_click');
create temp table t_ra as select r.* from app.campaign_recipients r where r.id = (select id from t_r where variant = 'a');
select pg_temp.check((select unsubscribed_at is not null from t_ra)
                 and exists (select 1 from app.suppressions where email_sha256 = app.email_hash((select email from t_ra)) and scope = 'marketing' and reason = 'unsubscribed'
                             and campaign_id = (select id from t_c))
                 and (select marketing_status from app.people where id = (select person_id from t_ra)) = 'unsubscribed'
                 and exists (select 1 from app.consent_events where person_id = (select person_id from t_ra) and status = 'unsubscribed' and ref_type = 'campaign'
                             and ref_id = (select id from t_c) and detail = 'one_click'),
                     'one-click unsubscribe: the recipient, the suppression by hash and the consent record at once');
select public.worker_unsubscribe((select tok from t_r where variant = 'a'), 'marketing', 'link');
select pg_temp.check((select count(*) from app.events where kind = 'campaign.unsubscribed' and subject_id = (select person_id from t_ra)) = 1, 'a repeated unsubscribe changes nothing');
select pg_temp.expect_error($$select public.worker_unsubscribe('not-a-token')$$, 'not_found', 'an unknown token is not found');
select pg_temp.expect_detail(format('select public.worker_unsubscribe(%L, %L)', (select tok from t_r where variant = 'a'), 'everything'), 'invalid', 'scope', 'the scope is marketing or all');
select public.worker_email_events(jsonb_build_array(jsonb_build_object('event_id', 'p6c-e6', 'kind', 'complained', 'message_id', 'msg-p6c-b'),
                                                    jsonb_build_object('event_id', 'p6c-e7', 'kind', 'bounced', 'bounce_kind', 'hard', 'smtp_code', '550', 'message_id', 'msg-p6c-w')));
select pg_temp.check((select state from app.campaign_recipients where id = (select id from t_r where variant = 'b')) = 'complained'
                 and (select marketing_status from app.people p join app.campaign_recipients r on r.person_id = p.id where r.id = (select id from t_r where variant = 'b')) = 'unsubscribed'
                 and exists (select 1 from app.suppressions s join app.campaign_recipients r on s.email_sha256 = app.email_hash(r.email) where r.id = (select id from t_r where variant = 'b')
                             and s.reason = 'complaint' and s.scope = 'marketing'), 'a complaint unsubscribes and suppresses for marketing');
select pg_temp.check((select state = 'bounced' and bounce_kind = 'hard' from app.campaign_recipients where id = (select id from t_r where variant = 'w'))
                 and (select marketing_status from app.people p join app.campaign_recipients r on r.person_id = p.id where r.id = (select id from t_r where variant = 'w')) = 'bounced'
                 and exists (select 1 from app.suppressions s join app.campaign_recipients r on s.email_sha256 = app.email_hash(r.email) where r.id = (select id from t_r where variant = 'w')
                             and s.reason = 'hard_bounce' and s.scope = 'all')
                 and exists (select 1 from app.consent_events c join app.campaign_recipients r on r.person_id = c.person_id where r.id = (select id from t_r where variant = 'w')
                             and c.status = 'bounced' and c.ref_type = 'provider' and c.detail = '550'),
                     'a hard bounce suppresses the address for everything and marks the person bounced (code 550 in the log)');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.consent_log(20) -> 'rows') x where x ->> 'ref_type' = 'campaign' and x ->> 'ref_label' = 'Nyhetsbrev oktober P6C'),
                     'the consent log names the campaign an unsubscribe came from');
select pg_temp.check((public.segment_count((select q from t_q)) ->> 'receivable')::int = 1, 'after the unsubscribe, complaint and bounce only the private subscriber can receive (CMP-04)');

-- ---------------------------------------------------------------------------
-- tracking off (setting): opens and clicks are neither recorded nor shown
select public.setting_set('tracking', 'off');
create temp table t_c2 as select (public.campaign_save(null, jsonb_build_object('type', 'one_off', 'name', 'Untracked P6C', 'subject_a', 'Hei', 'segment_id', (select id from t_seg),
                                                                                'sender_domain_id', (select id from t_dom))) ->> 'id')::uuid id;
select public.campaign_schedule((select id from t_c2), now(), null, (select h from t_html));
select public.setting_set('tracking', 'on');
select pg_temp.check((select not tracking from app.campaigns where id = (select id from t_c2)), 'tracking off is frozen into the campaign when it is scheduled');
select pg_temp.as_nobody();
select app.campaign_due();
create temp table t_b3 as select public.worker_campaign_batch((select id from t_c2), 50) b;
select pg_temp.check(jsonb_array_length((select b -> 'recipients' from t_b3)) = 1 and (select b -> 'recipients' -> 0 ->> 'name' from t_b3) = 'P6C Private Person',
                     'the admin''s campaign reaches the subscriber only the admin may see; every unsubscribed address is left out');
select public.worker_campaign_sent((select (b -> 'recipients' -> 0 ->> 'id')::uuid from t_b3), 'msg-p6c-c2');
select public.worker_email_events(jsonb_build_array(jsonb_build_object('event_id', 'p6c-e8', 'kind', 'delivered', 'message_id', 'msg-p6c-c2'),
                                                    jsonb_build_object('event_id', 'p6c-e9', 'kind', 'opened', 'message_id', 'msg-p6c-c2', 'client_class', 'human')));
select pg_temp.check(not exists (select 1 from app.campaign_events where provider_event_id = 'p6c-e9')
                 and (app.campaign_stats((select id from t_c2)) ->> 'unique_opens') is null and (app.campaign_stats((select id from t_c2)) ->> 'delivered')::int = 1,
                     'an untracked campaign records no opens and shows none');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check((select r ->> 'name' is null and r ->> 'email' is null and r ->> 'state' = 'delivered' from jsonb_array_elements(public.campaign_recipients((select id from t_c2), 'delivered') -> 'rows') r)
                 and (public.campaign_recipients((select id from t_c2)) -> 'stats' ->> 'delivered')::int = 1,
                     'a recipient the caller may not see is listed without name or address');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check(jsonb_array_length(public.campaign_recipients((select id from t_c)) -> 'rows') = 9
                 and jsonb_array_length(public.campaign_recipients((select id from t_c), 'skipped') -> 'rows') = 6, 'reports of others: the analyst reads the recipients, by state');
select pg_temp.expect_detail(format('select public.campaign_export(%L)', (select id from t_c)), 'forbidden', 'campaigns:export', 'exporting recipients needs campaigns:export');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_x as select public.campaign_export((select id from t_c)) x;
select pg_temp.check((select (x ->> 'rows')::int = 9 and x ->> 'content' like 'email,name,state,skip_reason,variant,%' and x ->> 'mime' = 'text/csv' from t_x)
                 and exists (select 1 from app.audit where action = 'record.exported' and target_id = (select id::text from t_c) and detail ->> 'count' = '9'),
                     'the recipients export as CSV, audited with the count');
select pg_temp.check(app.csv_cell('=HYPERLINK("x")') = '"''=HYPERLINK(""x"")"' and app.csv_cell('Plain') = 'Plain', 'a CSV cell cannot carry a formula');
select pg_temp.as_nobody();

-- the batch checks consent again at the moment of sending
insert into app.people (name, email, title, marketing_status) values ('P6C Recheck', 'p6c.recheck@example.no', 'P6C-RECHECK', 'subscribed');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_seg2 as select (public.segment_save(null, 'P6C recheck', '{"filters":[{"f":"title","op":"eq","v":"P6C-RECHECK"}]}') ->> 'id')::uuid id;
create temp table t_c3 as select (public.campaign_save(null, jsonb_build_object('type', 'one_off', 'name', 'Recheck P6C', 'subject_a', 'Hei', 'segment_id', (select id from t_seg2),
                                                                                'sender_domain_id', (select id from t_dom))) ->> 'id')::uuid id;
select public.campaign_schedule((select id from t_c3), now(), null, (select h from t_html));
select pg_temp.as_nobody();
select app.campaign_due();
select pg_temp.as_staff('tor@orgpuls.no');
select public.consent_set((select id from app.people where email = 'p6c.recheck@example.no'), 'unsubscribed', 'Phone call');
select pg_temp.as_nobody();
create temp table t_b4 as select public.worker_campaign_batch((select id from t_c3), 50) b;
select pg_temp.check(jsonb_array_length((select b -> 'recipients' from t_b4)) = 0
                 and (select state = 'skipped' and skip_reason = 'not_subscribed' and email is null from app.campaign_recipients where campaign_id = (select id from t_c3))
                 and (select status from app.campaigns where id = (select id from t_c3)) = 'sent',
                     'an unsubscribe after the audience was resolved is honoured: the address is never mailed (CMP-04)');

-- signups and MRR won by the campaign's UTM, last touch, after sending started (Q14)
create temp table t_acct2 as select gen_random_uuid() id;
insert into app.accounts (id, name) select id, 'P6C Signup AS' from t_acct2;
insert into app.account_products (product, tenant_id, account_id, attribution)
select 'orgpuls', 'p6c-signup', id, jsonb_build_object('first_touch', jsonb_build_object('utm_campaign', 'something-else'),
                                                       'last_touch', jsonb_build_object('utm_campaign', (select utm_campaign from app.campaigns where id = (select id from t_c))))
from t_acct2;
insert into app.subscriptions (product, tenant_id, confirmed_at, price, currency, billing_interval) values ('orgpuls', 'p6c-signup', now(), 1200, 'NOK', 'month');
select pg_temp.check((app.campaign_stats((select id from t_c)) ->> 'signups')::int = 1 and (app.campaign_stats((select id from t_c)) ->> 'mrr_won')::numeric = 1200
                 and (app.campaign_stats((select id from t_c2)) ->> 'signups')::int = 0, 'a signup whose last touch carries the campaign''s UTM counts, with its MRR in NOK');

-- ---------------------------------------------------------------------------
-- cancel, duplicate, delete a draft
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_c4 as select (public.campaign_save(null, jsonb_build_object('type', 'promotion', 'name', 'Cancel P6C', 'subject_a', 'Hei', 'segment_id', (select id from t_seg),
                                                                                'sender_domain_id', (select id from t_dom))) ->> 'id')::uuid id;
select public.campaign_schedule((select id from t_c4), now() + interval '2 days', null, (select h from t_html));
select public.campaign_cancel((select id from t_c4));
select pg_temp.check((select status = 'canceled' and canceled_at is not null from app.campaigns where id = (select id from t_c4))
                 and exists (select 1 from app.events where kind = 'campaign.canceled' and subject_id = (select id from t_c4)), 'a scheduled campaign is canceled');
select pg_temp.expect_detail(format('select public.campaign_cancel(%L)', (select id from t_c4)), 'invalid', 'status', 'only a scheduled campaign can be canceled');
select pg_temp.expect_detail(format('select public.campaign_schedule(%L, now(), null, %L)', (select id from t_c4), (select h from t_html)), 'invalid', 'status',
                             'a canceled campaign is not scheduled again');
create temp table t_c5 as select (public.campaign_duplicate((select id from t_c4)) ->> 'id')::uuid id;
select pg_temp.check((select status = 'draft' and owner_id = (select tor from t_ids) and utm_campaign <> (select utm_campaign from app.campaigns where id = (select id from t_c4))
                             and rendered_html is null from app.campaigns where id = (select id from t_c5)), 'a duplicate is a new draft with its own UTM');
select public.campaign_delete(array[(select id from t_c5)]);
select pg_temp.check((select deleted_at is not null from app.campaigns where id = (select id from t_c5)), 'a draft can be deleted');
select pg_temp.expect_detail(format('select public.campaign_pause(%L, true)', (select id from t_c4)), 'invalid', 'type', 'only an automated campaign pauses');

-- ---------------------------------------------------------------------------
-- automated campaigns and the engine's campaign_action (CMP-07, AUT-07)
create temp table t_ca as select (public.campaign_save(null, jsonb_build_object('type', 'automated', 'name', 'Trial nurture — day 2 P6C', 'subject_a', 'Kom i gang, [Person.fornavn]',
                                                                                'sender_domain_id', (select id from t_dom))) ->> 'id')::uuid id;
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_ca), '{"subject_b":"B"}'), 'invalid', 'subject_b', 'an automated campaign has no A/B test');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format('select app.wf_validate(%L, %L, %L)', 'workflow', jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('key', 's1', 'kind', 'campaign_action',
                                    'config', jsonb_build_object('campaign_id', (select id from t_ca))))), 'person'), 'forbidden', 'campaigns:workflows',
                             'a campaign step needs Campaigns › workflows (§6)');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format('select public.workflow_save(null, %L, %L)', '{"name":"P6C bad","trigger_type":"event","trigger_config":{"entity":"person","event":"created"}}',
                                    jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('key', 's1', 'kind', 'campaign_action', 'config', jsonb_build_object('campaign_id', (select id from t_c)))))),
                             'invalid', 'graph.s1.campaign_id', 'a campaign step names an automated campaign');
create temp table t_wf as select (public.workflow_save(null, '{"name":"P6C nurture","trigger_type":"event","trigger_config":{"entity":"person","event":"created"}}',
  jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('key', 's1', 'kind', 'campaign_action', 'config', jsonb_build_object('campaign_id', (select id from t_ca))),
                                                jsonb_build_object('key', 's2', 'kind', 'add_note', 'config', jsonb_build_object('body', 'Nurture queued'))))) ->> 'id')::uuid id;
select pg_temp.check(app.wf_blockers((select id from t_wf)) = array['campaign_inactive'], 'a draft automated campaign blocks the workflow');
select public.campaign_schedule((select id from t_ca), null, null, (select h from t_html));
select pg_temp.check((select status from app.campaigns where id = (select id from t_ca)) = 'active', 'scheduling an automated campaign switches it on');
select pg_temp.check(app.wf_blockers((select id from t_wf)) = '{}'::text[], 'with the provider, a verified domain and an active campaign nothing blocks it');
update app.integration_connections set status = 'not_connected' where provider = 'email';
select pg_temp.check(app.wf_blockers((select id from t_wf)) = array['not_connected:email'], 'without the provider the workflow cannot be switched on (replaces not_available:campaigns)');
update app.integration_connections set status = 'connected' where provider = 'email';
select pg_temp.as_nobody();
insert into app.people (name, email, title, marketing_status) values ('P6C Nurture Yes', 'p6c.yes@example.no', 'P6C-AUTO', 'subscribed'),
                                                                     ('P6C Nurture No', 'p6c.no@example.no', 'P6C-AUTO', 'pending');
create temp table t_runs as select app.wf_start((select id from t_wf), 'person', p.id, null, null) run, p.email from app.people p where p.title = 'P6C-AUTO';
select pg_temp.check((select bool_and(r.state = 'completed') from app.workflow_runs r where r.id in (select run from t_runs)), 'both runs complete');
select pg_temp.check((select state = 'queued' and send_key = (select s.id::text from app.workflow_run_steps s where s.run_id = (select run from t_runs where email = 'p6c.yes@example.no') and s.step_key = 's1')
                      from app.campaign_recipients where campaign_id = (select id from t_ca) and email = 'p6c.yes@example.no'),
                     'a subscribed person is queued, keyed by the run step');
select pg_temp.check((select s.state = 'skipped' and s.output ->> 'skip_reason' = 'not_subscribed' from app.workflow_run_steps s
                      where s.run_id = (select run from t_runs where email = 'p6c.no@example.no') and s.step_key = 's1')
                 and exists (select 1 from app.campaign_recipients r join app.people p on p.id = r.person_id where r.campaign_id = (select id from t_ca)
                             and p.email = 'p6c.no@example.no' and r.state = 'skipped' and r.skip_reason = 'not_subscribed'),
                     'a triggered email obeys consent: pending double opt-in is skipped with the reason and the run goes on (CMP-07)');
select pg_temp.as_staff('tor@orgpuls.no');
select public.campaign_pause((select id from t_ca), true);
select pg_temp.as_nobody();
select pg_temp.check((select status from app.campaigns where id = (select id from t_ca)) = 'paused'
                 and jsonb_array_length(public.worker_campaign_batch((select id from t_ca)) -> 'recipients') = 0, 'a paused campaign sends nobody');
select pg_temp.as_staff('tor@orgpuls.no');
select public.campaign_pause((select id from t_ca), false);
select pg_temp.as_nobody();
create temp table t_b5 as select public.worker_campaign_batch((select id from t_ca)) b;
select pg_temp.check(jsonb_array_length((select b -> 'recipients' from t_b5)) = 1, 'resumed, the queued recipient is sent');
select public.worker_campaign_failed((select (b -> 'recipients' -> 0 ->> 'id')::uuid from t_b5), 'mailbox_full');
select pg_temp.check((select state = 'failed' and failure_code = 'mailbox_full' from app.campaign_recipients where id = (select (b -> 'recipients' -> 0 ->> 'id')::uuid from t_b5)),
                     'a send the provider refused is recorded as failed with its code');
-- five soft bounces since the last delivery count as a hard one (CMP-06 RU)
create temp table t_soft as select app.campaign_enqueue((select id from t_ca), (select id from app.people where email = 'p6c.yes@example.no'), 'soft-' || g) r, g from generate_series(1, 5) g;
update app.campaign_recipients set state = 'sent', sent_at = now(), provider_message_id = 'msg-p6c-' || send_key where campaign_id = (select id from t_ca) and send_key like 'soft-%';
select public.worker_email_events((select jsonb_agg(jsonb_build_object('event_id', 'p6c-soft-' || g, 'kind', 'bounced', 'bounce_kind', 'soft', 'message_id', 'msg-p6c-soft-' || g))
                                   from generate_series(1, 4) g));
select pg_temp.check((select marketing_status from app.people where email = 'p6c.yes@example.no') = 'subscribed', 'four soft bounces do not stop the address');
select public.worker_email_events('[{"event_id":"p6c-soft-5","kind":"bounced","bounce_kind":"soft","message_id":"msg-p6c-soft-5"}]');
select pg_temp.check((select marketing_status from app.people where email = 'p6c.yes@example.no') = 'bounced'
                 and exists (select 1 from app.suppressions where email_sha256 = app.email_hash('p6c.yes@example.no') and scope = 'all' and reason = 'soft_bounces'),
                     'the fifth soft bounce marks the person bounced and suppresses the address for everything');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format('select public.sender_domain_delete(%L)', (select id from t_dom)), 'invalid', 'in_use', 'a domain a running campaign sends from cannot be removed');

-- ---------------------------------------------------------------------------
-- list hygiene (setting list_hygiene has its effect), deliverability
create temp table t_h as select public.hygiene_candidates() h;
select pg_temp.check((select h ->> 'enabled' = 'true' and (h ->> 'months')::int = 12 and (h ->> 'count')::int >= 1 from t_h)
                 and (select id from app.people where email = 'p6c.private@example.no') in (select app.hygiene_ids())
                 and (select id from app.people where email = 'p6c.recheck@example.no') not in (select app.hygiene_ids()),
                     'a subscriber sent a campaign with no human open or click in 12 months is a hygiene candidate; one never sent is not');
select public.setting_set('list_hygiene', 'custom', '', 6);
select pg_temp.check((public.hygiene_candidates() ->> 'months')::int = 6, 'a custom number of months is honoured');
select public.setting_set('list_hygiene', 'off');
select pg_temp.check((select h ->> 'enabled' = 'false' and h -> 'count' = 'null'::jsonb from (select public.hygiene_candidates() h) x)
                 and not exists (select 1 from jsonb_array_elements(public.deliverability_recommendations()) r where r ->> 'kind' = 'hygiene'),
                     'with list_hygiene off there are no candidates and no recommendation');
select pg_temp.expect_detail($$select public.hygiene_archive(1)$$, 'invalid', 'list_hygiene', 'archiving needs list hygiene on');
select public.setting_set('list_hygiene', 'source_values');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.deliverability_recommendations()) r where r ->> 'kind' = 'hygiene'
                             and (r ->> 'count')::int = (select (h ->> 'count')::int from t_h)), 'the hygiene recommendation counts the candidates');
select pg_temp.expect_detail(format('select public.hygiene_archive(%s)', (select (h ->> 'count')::int + 5 from t_h)), 'invalid', 'expected',
                             'archiving is refused when the count changed since it was shown');
create temp table t_arch as select public.hygiene_archive((select (h ->> 'count')::int from t_h)) a;
select pg_temp.check(((select a from t_arch) ->> 'archived')::int = (select (h ->> 'count')::int from t_h) and (select marketing_status from app.people where email = 'p6c.private@example.no') = 'archived'
                 and exists (select 1 from app.consent_events c join app.people p on p.id = c.person_id where p.email = 'p6c.private@example.no' and c.status = 'archived'
                             and c.ref_type = 'list_hygiene'), 'list hygiene archives with source list_hygiene, by a staff action');
create temp table t_dg as select public.sender_domains_get() g;
select pg_temp.check((select (d -> 'rates' ->> 'sent')::int >= 4 and (d -> 'warmup' ->> 'days')::int = 30 and (d ->> 'verified')::boolean
                      from jsonb_array_elements((select g -> 'rows' from t_dg)) d where d ->> 'domain' = 'news.p6c.example.no')
                 and (select d -> 'rates' = 'null'::jsonb from jsonb_array_elements((select g -> 'rows' from t_dg)) d where d ->> 'domain' = 'varsler.p6c.example.no'),
                     'rates for domains this platform sends through; none for a domain another system sends from (Q6)');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.deliverability_recommendations()) r where r ->> 'kind' = 'dns_missing' and r ->> 'domain' = 'varsler.p6c.example.no')
                 and exists (select 1 from jsonb_array_elements(public.deliverability_recommendations()) r where r ->> 'kind' = 'identity' and (r ->> 'ok')::boolean),
                     'recommendations are computed: missing DNS records, and the sender identity check');
select pg_temp.check((public.sender_domain_recheck() ->> 'queued')::int >= 2, 'Re-check DNS queues a check per domain');
select public.sender_domain_delete((select id from app.sender_domains where domain = 'varsler.p6c.example.no'));
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.sender_domains_get() -> 'rows') d where d ->> 'domain' = 'varsler.p6c.example.no'),
                     'a domain no campaign sends from can be removed');

-- ---------------------------------------------------------------------------
-- append-only evidence, retention, erasure, and no recipient text in logs
select pg_temp.expect_error(format('update app.campaign_events set kind = %L where campaign_id = %L', 'clicked', (select id from t_c)), 'campaign events are append-only',
                            'a provider event cannot be changed');
select pg_temp.expect_error(format('delete from app.campaign_events where campaign_id = %L', (select id from t_c)), 'campaign events are append-only', 'nor deleted inside its retention');
insert into app.campaign_events (recipient_id, campaign_id, kind, at) select id, campaign_id, 'delivered', now() - interval '14 months' from t_ra;
create temp table t_pr as select app.campaign_prune() n;
select pg_temp.check((select n from t_pr) >= 1 and not exists (select 1 from app.campaign_events where at < now() - interval '13 months')
                 and exists (select 1 from app.campaign_events where campaign_id = (select id from t_c)), 'events older than 13 months are pruned; the recipients'' rollup stays');
create temp table t_before as select app.campaign_stats((select id from t_c)) s;
delete from app.people where id = (select person_id from t_ra);
select pg_temp.check((select person_id is null and email is null and city is null from app.campaign_recipients where id = (select id from t_ra))
                 and exists (select 1 from app.suppressions where email_sha256 = app.email_hash('p6c.sub1@example.no') or email_sha256 = app.email_hash('p6c.sub2@example.no')
                             or email_sha256 = app.email_hash('p6c.sub3@example.no'))
                 and (select (s ->> 'delivered')::int from t_before) = (app.campaign_stats((select id from t_c)) ->> 'delivered')::int,
                     'erasure blanks the recipient''s address and place; the suppression hash and the figures stay (SEC-11)');
select pg_temp.check(not exists (select 1 from app.events where kind like 'campaign.%' and payload::text ~* '(@|P6C|Bergen|Lovkravet|Slik kartlegger)')
                 and not exists (select 1 from app.audit where (action like 'campaign.%' or target_type in ('campaign', 'campaign_recipient', 'segment', 'sender_domain'))
                                 and detail::text ~* '(@example|Bergen|Lovkravet|Slik kartlegger|Hei P6C)'),
                     'events and the audit carry ids, kinds and counts, never an address, a place or the content');
select pg_temp.check((select count(*) from app.campaign_recipients r where r.campaign_id = (select id from t_c)) = 9
                 and exists (select 1 from app.audit where action = 'record.read' and target_type = 'campaign' and target_id = (select id::text from t_c)),
                     'reads of a campaign are audited (D-12)');

rollback;
