-- phase6_requests_invariants.sql — the Phase 6 screens' requests (0040): coupons for campaigns, the product-activity segment
-- field (tenant-level dates only, D-19), the campaign's language frozen with its content, template versions and restore, the
-- template line's start day, the PDF worker's state, and the Insights report entities «project» and «campaign» (INS-01).
\ir _helpers.psql
begin;

-- the rights this suite was written for: 0057 gave Marketing campaigns:reports_others, campaigns:workflows, campaigns:delete and
-- global:see (Simple's Growth and Platform); here Marketing keeps its earlier rights
update app.permission_sets set rights = array(select r from unnest(rights) r
  where r not in ('campaigns:reports_others', 'campaigns:workflows', 'campaigns:delete', 'global:see')) where key = 'marketing';

-- the rights this suite was written for: 0057 gave Sales campaigns:see and campaigns:add (CRM › Lists); here Sales stands for a
-- seller without any campaigns right
update app.permission_sets set rights = array(select r from unnest(rights) r where r not in ('campaigns:see', 'campaigns:add')) where key = 'sales';

-- the roles this suite was written for (0057 folded Projects into Sales): emma keeps the Projects set, which still exists
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'project') where email = 'emma@orgpuls.no';

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
-- structure: the new reads and writes are security definers for signed-in staff; the helpers stay closed
select pg_temp.check(p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false)
                     and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute'),
                     'signed-in staff only, security definer, empty search path: ' || p.oid::regprocedure::text)
from pg_proc p where p.oid in ('public.campaign_coupons()'::regprocedure, 'public.marketing_template_versions(uuid)'::regprocedure,
                               'public.marketing_template_restore(uuid, int)'::regprocedure, 'public.project_pdf_status()'::regprocedure,
                               'public.campaign_save(uuid, jsonb, int)'::regprocedure, 'public.campaign_duplicate(uuid)'::regprocedure,
                               'public.report_fields(text)'::regprocedure);
select pg_temp.check(not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), 'internal for nobody: ' || f)
from unnest(array['app.filter_sql(app.entities, jsonb)', 'app.campaign_guard()', 'app.campaign_row(app.campaigns, boolean)', 'app.prj_template_row(app.project_templates)',
                  'app.report_dim(app.entities, text)', 'app.report_measure(app.entities, jsonb)', 'app.report_check(jsonb)', 'app.report_run(jsonb, jsonb)']) f;

-- ---------------------------------------------------------------------------
-- R-CAMPAIGNS-02: the active coupons under campaigns:see
select pg_temp.as_nobody();
insert into app.coupons (code, description, percent, months, active) values ('P6RHMS', 'HMS-kampanje', 20, 3, true), ('P6ROLD', 'Utløpt', 50, 1, false);
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail($$select public.billing_overview('all')$$, 'forbidden', 'global:see', 'Marketing cannot read billing_overview');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.campaign_coupons()) x
                             where x = '{"code":"P6RHMS","description":"HMS-kampanje","percent":20.00,"months":3}'::jsonb),
                     'Marketing reads the active coupon with its code, description, percent and months');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.campaign_coupons()) x where x ->> 'code' = 'P6ROLD'), 'an inactive coupon is not offered');
select pg_temp.check((select count(*) from jsonb_array_elements(public.campaign_coupons())) = (select count(*) from app.coupons where active), 'every active coupon is offered');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.campaign_coupons()$$, 'forbidden', 'campaigns:see', 'Sales without campaigns:see cannot read the coupons');
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('campaigns', false);
select pg_temp.expect_detail($$select public.campaign_coupons()$$, 'module_off', 'campaigns', 'the coupons follow the campaigns module');
select public.module_set('campaigns', true);
-- the select's choice is accepted by campaign_save; an inactive one is refused
select pg_temp.as_staff('jonas@orgpuls.no');
create temp table t_promo as select (public.campaign_save(null, '{"type":"promotion","name":"P6R Kampanje","coupon_code":"P6RHMS"}') ->> 'id')::uuid id;
select pg_temp.check((select coupon_code from app.campaigns where id = (select id from t_promo)) = 'P6RHMS', 'a promotion takes an offered coupon');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select id from t_promo), '{"coupon_code":"P6ROLD"}'), 'invalid', 'coupon_code',
                             'a coupon that is not offered is refused');

-- ---------------------------------------------------------------------------
-- R-CAMPAIGNS-03: product.last_round_days — days since a round opened in the person's tenants (organisation's account or
-- own membership); future rounds do not count; never ran one = empty
select pg_temp.as_nobody();
create temp table t_r as select gen_random_uuid() a1, gen_random_uuid() a2, gen_random_uuid() a3, gen_random_uuid() o1, gen_random_uuid() o2, gen_random_uuid() o3,
  gen_random_uuid() p1, gen_random_uuid() p2, gen_random_uuid() p3, gen_random_uuid() p4, gen_random_uuid() p5;
insert into app.accounts (id, name, org_number) select x.id, x.n, x.nr from t_r, lateral (values (a1, 'P6R Stille AS', '987650401'), (a2, 'P6R Aktiv AS', '987650402'),
  (a3, 'P6R Ny AS', '987650403')) x(id, n, nr);
insert into app.account_products (product, tenant_id, account_id) select 'orgpuls', x.t, x.a from t_r, lateral (values ('p6r-t1', a1), ('p6r-t2', a2), ('p6r-t3', a3)) x(t, a);
insert into app.product_survey_rounds (product, tenant_id, round_ref, kind, opens_at, closes_at, invited, answered) values
  ('orgpuls', 'p6r-t1', 'r1', 'main', now() - interval '200 days', now() - interval '186 days', 40, 31),
  ('orgpuls', 'p6r-t1', 'r2', 'pulse', now() - interval '120 days 3 hours', now() - interval '113 days', 40, 28),
  ('orgpuls', 'p6r-t1', 'r3', 'pulse', now() + interval '5 days', now() + interval '12 days', null, null),
  ('orgpuls', 'p6r-t2', 'r1', 'pulse', now() - interval '10 days 2 hours', now() - interval '3 days', 12, 9);
insert into app.members (product, tenant_id, user_id, role, email) values ('orgpuls', 'p6r-t2', 'p6r-u1', 'verneombud', 'p6r.member@example.no');
insert into app.organizations (id, name, account_id) select x.id, x.n, x.a from t_r, lateral (values (o1, 'P6R Stille AS', a1), (o2, 'P6R Aktiv AS', a2), (o3, 'P6R Ny AS', a3)) x(id, n, a);
insert into app.people (id, name, email, title, marketing_status, organization_id, member_product, member_tenant, member_user, visibility)
select x.id, x.n, x.e, 'P6R', 'subscribed', x.o, x.mp, x.mt, x.mu, 'all' from t_r,
  lateral (values (p1, 'P6R Stille', 'p6r.1@example.no', o1, null, null, null), (p2, 'P6R Aktiv', 'p6r.2@example.no', o2, null, null, null),
                  (p3, 'P6R Ny', 'p6r.3@example.no', o3, null, null, null), (p4, 'P6R Medlem', 'p6r.4@example.no', null, 'orgpuls', 'p6r-t2', 'p6r-u1'),
                  (p5, 'P6R Uten', 'p6r.5@example.no', null, null, null, null)) x(id, n, e, o, mp, mt, mu);
create or replace function pg_temp.seg(p_filters jsonb) returns uuid[] language plpgsql as $$
declare v uuid[];
begin
  execute format('select array_agg(t.id order by t.name) from app.people t where t.title = %L %s', 'P6R', app.filter_sql(app.entity('person'), p_filters)) into v;
  return coalesce(v, '{}');
end $$;
select pg_temp.check(pg_temp.seg('[{"f":"product.last_round_days","op":"gte","v":90}]') = array[(select p1 from t_r)],
                     'at least 90 days since the last round: the tenant whose last round opened 120 days ago (a planned round does not count)');
select pg_temp.check(pg_temp.seg('[{"f":"product.last_round_days","op":"eq","v":120}]') = array[(select p1 from t_r)], 'the field counts whole days since the round opened');
select pg_temp.check(pg_temp.seg('[{"f":"product.last_round_days","op":"lte","v":30}]') = array[(select p2 from t_r), (select p4 from t_r)],
                     'within 30 days: a person of the active organisation, and a product user of that tenant without an organisation');
select pg_temp.check(pg_temp.seg('[{"f":"product.last_round_days","op":"empty"}]') = array[(select p3 from t_r), (select p5 from t_r)],
                     'empty: a customer whose tenant never ran a round, and a person with no tenant');
select pg_temp.check(app.filter_sql(app.entity('person'), '[{"f":"product.last_round_days","op":"gte","v":90}]') ~ 'opens_at'
                 and app.filter_sql(app.entity('person'), '[{"f":"product.last_round_days","op":"gte","v":90}]') !~ '(invited|delivered|answered|bounced|reminders|gained)',
                     'the field reads when a round opened and nothing about its answers (D-19)');
select pg_temp.expect_detail($$select app.filter_sql(app.entity('organization'), '[{"f":"product.last_round_days","op":"gte","v":90}]')$$, 'invalid', 'filter.product.last_round_days',
                             'the field belongs to people only');
-- the design's segment «Customers without a pulse in 90 days», as the seed stores it, is accepted and counted
select pg_temp.as_staff('jonas@orgpuls.no');
create temp table t_pulse as select '{"filters":[{"f":"organization.status","op":"eq","v":"active"},{"or":[[{"f":"product.last_round_days","op":"gte","v":90}],[{"f":"product.last_round_days","op":"empty"}]]}]}'::jsonb q;
create temp table t_seg as select public.segment_save(null, 'P6R Customers without a pulse in 90 days', (select q from t_pulse)) r;
select pg_temp.check((select (r ->> 'matches')::int >= 0 and (r ->> 'receivable')::int <= (r ->> 'matches')::int from t_seg)
                 and (select (r ->> 'matches')::int from t_seg) = (public.segment_count((select q from t_pulse)) ->> 'matches')::int,
                     'the segment saves and its count is the live count');
select pg_temp.check((public.segment_count('{"filters":[{"f":"title","op":"eq","v":"P6R"},{"or":[[{"f":"product.last_round_days","op":"gte","v":90}],[{"f":"product.last_round_days","op":"empty"}]]}]}') ->> 'matches')::int = 3,
                     'segment_count takes the field inside an OR group (stille, ny, uten)');

-- ---------------------------------------------------------------------------
-- R-CAMPAIGNS-04: the campaign's language — set, returned, refused outside the list, copied, frozen with the content
create temp table t_c as select (public.campaign_save(null, '{"type":"newsletter","name":"P6R Newsletter EN","language":"en"}') ->> 'id')::uuid en,
                                (public.campaign_save(null, '{"type":"newsletter","name":"P6R Nyhetsbrev"}') ->> 'id')::uuid nb;
select pg_temp.check((public.campaign_get((select en from t_c)) ->> 'language') = 'en' and (public.campaign_get((select nb from t_c)) ->> 'language') = 'nb',
                     'the detail returns the language; a new campaign is bokmål unless told otherwise');
select pg_temp.check((public.campaign_save((select nb from t_c), '{"language":"nn"}') ->> 'language') = 'nn', 'a draft changes its language');
select pg_temp.check((public.campaign_save((select nb from t_c), '{"name":"P6R Nyhetsbrev (nynorsk)"}') ->> 'language') = 'nn', 'a save without the key keeps the language');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select en from t_c), '{"language":"de"}'), 'invalid', 'language', 'only nb, nn, en and sv');
select pg_temp.check((public.campaign_duplicate((select en from t_c)) ->> 'language') = 'en', 'a copy keeps the language');
select pg_temp.check((select language from app.campaigns where id = (select en from t_c)) = 'en'
                 and exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'campaigns' and column_name = 'language' and is_nullable = 'NO'),
                     'campaigns.language is a stored column, never null');
select pg_temp.as_nobody();
update app.campaigns set status = 'scheduled', rendered_html = '<p>x</p>', scheduled_at = now() + interval '1 day' where id = (select en from t_c);
select pg_temp.expect_error(format($$update app.campaigns set language = 'sv' where id = %L$$, (select en from t_c)), 'a scheduled or sent campaign''s content is fixed',
                            'a scheduled campaign keeps its language (the guard)');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format('select public.campaign_save(%L, %L)', (select en from t_c), '{"language":"sv"}'), 'invalid', 'status', 'campaign_save refuses a language change once scheduled');
select pg_temp.check((public.campaign_save((select en from t_c), '{"name":"P6R Newsletter EN (renamed)"}') ->> 'language') = 'en', 'renaming a scheduled campaign keeps its language');

-- ---------------------------------------------------------------------------
-- R-CAMPAIGNS-05: a template's versions, and restoring one as the next version
create temp table t_tpl as select (public.marketing_template_save(null, jsonb_build_object('name', 'P6R Webinar', 'scope', 'shared', 'subject', 'Første emne',
  'html', '<table><tr><td>Hei</td></tr><tr><td><a href="[Unsubscribe]">Av</a></td></tr></table>')) ->> 'id')::uuid id;
select public.marketing_template_save((select id from t_tpl), '{"subject":"Andre emne"}', 1);
select pg_temp.check((select array_agg((x ->> 'version')::int || ':' || (x ->> 'subject')) from jsonb_array_elements(public.marketing_template_versions((select id from t_tpl))) x)
                     = array['2:Andre emne', '1:Første emne']
                 and (select bool_and(x ->> 'by' = (select name from app.admins where email = 'jonas@orgpuls.no') and (x ->> 'created_at') is not null)
                      from jsonb_array_elements(public.marketing_template_versions((select id from t_tpl))) x),
                     'the versions, newest first, with subject, when and by whom');
create temp table t_rest as select public.marketing_template_restore((select id from t_tpl), 1) r;
select pg_temp.check((select (r ->> 'current_version')::int = 3 and (r ->> 'version')::int = 3 from t_rest)
                 and (select subject = 'Første emne' and current_version = 3 from app.email_templates where id = (select id from t_tpl))
                 and (select subject = 'Første emne' from app.email_template_versions where template_id = (select id from t_tpl) and version = 3)
                 and (select subject = 'Andre emne' from app.email_template_versions where template_id = (select id from t_tpl) and version = 2),
                     'restoring version 1 saves it as version 3; versions 1 and 2 are kept as they were');
select pg_temp.check(exists (select 1 from app.audit where action = 'template.restored' and target_id = (select id::text from t_tpl) and detail ->> 'from_version' = '1'),
                     'a restore is audited with the version it came from');
select pg_temp.expect_detail(format('select public.marketing_template_restore(%L, 3)', (select id from t_tpl)), 'invalid', 'version', 'the current version is not restored onto itself');
select pg_temp.expect_detail(format('select public.marketing_template_restore(%L, 99)', (select id from t_tpl)), 'not_found', 'version', 'an unknown version');
create temp table t_priv as select (public.marketing_template_save(null, '{"name":"P6R Privat","scope":"private","subject":"x","html":"<table><tr><td><a href=\"[Unsubscribe]\">Av</a></td></tr></table>"}') ->> 'id')::uuid id;
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check(jsonb_array_length(public.marketing_template_versions((select id from t_tpl))) = 3, 'a shared template''s versions are read under campaigns:see');
select pg_temp.expect_error(format('select public.marketing_template_versions(%L)', (select id from t_priv)), 'not_found', 'another''s private template has no versions to read');
select pg_temp.expect_detail(format('select public.marketing_template_restore(%L, 1)', (select id from t_tpl)), 'forbidden', 'campaigns:add', 'the read-only analyst cannot restore');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format('select public.marketing_template_versions(%L)', (select id from t_tpl)), 'forbidden', 'campaigns:see', 'Sales cannot read template versions');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format('select public.marketing_template_restore(%L, 1)', (select id from app.email_templates where kind = 'marketing' and layout and name = 'Newsletter')),
                             'invalid', 'version', 'a layout with one version has nothing older to restore');
select pg_temp.as_staff('tor@orgpuls.no');
select public.marketing_template_save((select id from app.email_templates where kind = 'marketing' and layout and name = 'Newsletter'), '{"subject":"P6R emne"}');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format('select public.marketing_template_restore(%L, 1)', (select id from app.email_templates where kind = 'marketing' and layout and name = 'Newsletter')),
                             'forbidden', 'campaigns:configure', 'restoring a layout needs campaigns:configure, as saving one does');

-- ---------------------------------------------------------------------------
-- R-PROJECTS-04: a template line's day is the day it starts
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_pt as select (public.project_template_save(null, jsonb_build_object('name', 'P6R Oppstart', 'organized_by', 'groups',
  'groups', jsonb_build_array(jsonb_build_object('key', 'g1', 'name', 'Oppstart')),
  'items', jsonb_build_array(
    jsonb_build_object('key', 'i1', 'group', 'g1', 'name', 'Kickoff meeting', 'start_offset_days', 0, 'due_offset_days', 2),
    jsonb_build_object('key', 'i2', 'group', 'g1', 'name', 'Upload employee list', 'start_offset_days', 3, 'due_offset_days', 8),
    jsonb_build_object('key', 'i3', 'group', 'g1', 'name', 'Only a due date', 'due_offset_days', 6),
    jsonb_build_object('key', 'm1', 'group', 'g1', 'kind', 'milestone', 'name', 'List ready', 'due_offset_days', 9),
    jsonb_build_object('key', 'a1', 'group', 'g1', 'kind', 'activity', 'name', 'Training call', 'activity_type', 'meeting', 'activity_time', '10:00', 'due_offset_days', 12)))) ->> 'id')::uuid id;
select pg_temp.check((select jsonb_agg(jsonb_build_array(y -> 'day', y -> 'name')) from jsonb_array_elements(
                        (select x -> 'preview' from jsonb_array_elements(public.project_templates_get()) x where x ->> 'id' = (select id::text from t_pt))) y)
                     = '[[0,"Kickoff meeting"],[3,"Upload employee list"],[6,"Only a due date"],[9,"List ready"],[12,"Training call"]]'::jsonb,
                     'Day N is a task''s start offset (its due offset without one); milestones and activities their due offset');
select pg_temp.check((select x -> 'preview' from jsonb_array_elements(public.project_templates_get()) x where x ->> 'id' = (select id::text from t_pt))
                     = (public.project_template_get((select id from t_pt)) -> 'preview'), 'the editor reads the same preview');

-- ---------------------------------------------------------------------------
-- R-PROJECTS-02: whether the PDF worker runs
select pg_temp.check(exists (select 1 from app.integration_connections where provider = 'pdf' and status = 'not_connected')
                 and (select count(*) from app.integration_connections where provider in ('slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony',
                                                                                          'messaging', 'search_console', 'ai', 'email', 'ip_company', 'esign')) = 13,
                     'provider pdf is registered, not connected; the other providers are kept');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.check(public.project_pdf_status() = '{"pdf_connected":false}'::jsonb, 'the screen reads that the PDF worker is not connected');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.integrations_get()) x where x ->> 'provider' = 'pdf' and x ->> 'status' = 'not_connected'),
                     'the integrations list shows the PDF worker');
select pg_temp.as_nobody();
update app.integration_connections set status = 'connected' where provider = 'pdf';
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.check((public.project_pdf_status() ->> 'pdf_connected')::boolean, 'once the worker is connected the dialog may create the PDF');
select pg_temp.as_nobody();
update app.integration_connections set status = 'not_connected' where provider = 'pdf';
select pg_temp.expect_error($$insert into app.integration_connections (provider) values ('pdf2')$$,
                            'new row for relation "integration_connections" violates check constraint "integration_connections_provider_check"', 'an unknown provider is refused');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.project_pdf_status()$$, 'forbidden', 'projects:see', 'the PDF state is read under projects:see');
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('projects', false);
select pg_temp.expect_detail($$select public.project_pdf_status()$$, 'module_off', 'projects', 'and with the projects module on');
select public.module_set('projects', true);

-- ---------------------------------------------------------------------------
-- INS-01: report entity «project» — board, phase, status, health, owner; duration_days; visibility and «reports of others»
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_b as select (public.project_board_save(null, '{"name":"P6R Tavle","phases":[{"name":"P6R Start"},{"name":"P6R Drift"}]}') ->> 'id')::uuid id;
create temp table t_ph as select (select id from app.project_phases where board_id = (select id from t_b) and name = 'P6R Start') start,
                                 (select id from app.project_phases where board_id = (select id from t_b) and name = 'P6R Drift') drift;
create temp table t_pr as select
  (public.project_create(jsonb_build_object('name', 'P6R Tor åpen', 'board_id', (select id from t_b), 'visibility', 'all')) ->> 'id')::uuid tor_all,
  (public.project_create(jsonb_build_object('name', 'P6R Tor privat', 'board_id', (select id from t_b), 'visibility', 'owner')) ->> 'id')::uuid tor_priv;
select public.project_move((select tor_all from t_pr), (select drift from t_ph));
select public.project_health_set((select tor_all from t_pr), 'at_risk');
select pg_temp.as_staff('emma@orgpuls.no');
create temp table t_pe as select (public.project_create(jsonb_build_object('name', 'P6R Emma', 'board_id', (select id from t_b), 'visibility', 'all')) ->> 'id')::uuid emma;
select public.project_close((select emma from t_pe), 'done');
select pg_temp.as_nobody();
update app.projects set created_at = now() - interval '10 days' where id in ((select tor_all from t_pr), (select emma from t_pe));
update app.projects set created_at = now() - interval '30 days' where id = (select tor_priv from t_pr);
update app.projects set closed_at = now() - interval '4 days' where id = (select emma from t_pe);
create temp table t_pd as select jsonb_build_object('entity', 'project', 'filters', jsonb_build_array(jsonb_build_object('f', 'board_id', 'op', 'eq', 'v', (select id from t_b)))) d;
create or replace function pg_temp.rows_of(p jsonb) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_array(x -> 'label', x -> 'value') order by x ->> 'label'), '[]'::jsonb) from jsonb_array_elements(p -> 'rows') x
$$;
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(pg_temp.rows_of(public.report_run((select d from t_pd) || '{"group_by":"phase"}')) = '[["P6R Drift",1],["P6R Start",2]]'::jsonb
                 and (select array_agg(x ->> 'label') from jsonb_array_elements(public.report_run((select d from t_pd) || '{"group_by":"phase"}') -> 'rows') x) = array['P6R Start', 'P6R Drift'],
                     'projects per phase, labelled and ordered by the board''s phases');
select pg_temp.check(pg_temp.rows_of(public.report_run((select d from t_pd) || '{"group_by":"board"}')) = '[["P6R Tavle",3]]'::jsonb, 'projects per board, labelled by the board');
select pg_temp.check(pg_temp.rows_of(public.report_run((select d from t_pd) || '{"group_by":"status"}')) = '[["done",1],["open",2]]'::jsonb, 'projects per status (generic rule)');
select pg_temp.check(pg_temp.rows_of(public.report_run((select d from t_pd) || '{"group_by":"health"}')) = '[["at_risk",1],[null,2]]'::jsonb, 'projects per health; «not set» is its own row');
select pg_temp.check(pg_temp.rows_of(public.report_run((select d from t_pd) || '{"group_by":"owner"}'))
                     = jsonb_build_array(jsonb_build_array((select name from app.admins where email = 'emma@orgpuls.no'), 1), jsonb_build_array((select name from app.admins where email = 'tor@orgpuls.no'), 2))
                    or pg_temp.rows_of(public.report_run((select d from t_pd) || '{"group_by":"owner"}'))
                     = jsonb_build_array(jsonb_build_array((select name from app.admins where email = 'tor@orgpuls.no'), 2), jsonb_build_array((select name from app.admins where email = 'emma@orgpuls.no'), 1)),
                     'projects per owner');
create temp table t_dur as select public.report_run((select d from t_pd) || '{"measure":{"fn":"duration_days"}}') r;
select pg_temp.check((select (r ->> 'total')::numeric = round((10 + 6 + 30) / 3.0, 1) and r ->> 'unit' = 'days' from t_dur),
                     'duration_days: the average days from creation to closing, or to today while open (10, 6 and 30 days)');
select pg_temp.check((public.report_run((select d from t_pd) || '{"type":"duration","group_by":"status"}') ->> 'unit') = 'days'
                 and pg_temp.rows_of(public.report_run((select d from t_pd) || '{"type":"duration","group_by":"status"}')) = '[["done",6.0],["open",20.0]]'::jsonb,
                     'a project Duration report is its average duration');
select pg_temp.expect_detail($$select public.report_run('{"entity":"deal","measure":{"fn":"duration_days"}}')$$, 'invalid', 'measure', 'duration_days is a project measure');
select pg_temp.expect_detail($$select public.report_run('{"entity":"deal","group_by":"phase"}')$$, 'invalid', 'group_by', 'phase is a project dimension');
select pg_temp.check((select array_agg(x ->> 'title' order by x ->> 'title') from jsonb_array_elements(public.report_drill((select d from t_pd) || '{"group_by":"phase"}',
                        jsonb_build_object('key', (select start from t_ph)))) x) = array['P6R Emma', 'P6R Tor privat'], 'a phase row opens its projects');
-- visibility and «See reports of others»
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((public.report_run((select d from t_pd)) ->> 'total')::int = 2, 'the analyst (reports of others) counts what they may see: not the owner-only project');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.check((public.report_run((select d from t_pd)) ->> 'total')::int = 1, 'without «See reports of others» a report counts one''s own projects');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format('select public.report_run(%L)', (select d from t_pd)), 'forbidden', 'projects:see', 'Sales without projects:see cannot report on projects');
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('projects', false);
select pg_temp.expect_detail(format('select public.report_run(%L)', (select d from t_pd)), 'module_off', 'projects', 'a project report needs the projects module');
select public.module_set('projects', true);
select pg_temp.check((select f -> 'dimensions' @> '["owner","board","phase","status","health","label","created_month"]' and f -> 'measures' = '["duration_days"]'
                      from (select public.report_fields('project') f) x), 'the builder is offered board, phase, status, health and owner, and duration_days');
create temp table t_rep as select (public.report_save(null, 'P6R Prosjekter per fase', (select d from t_pd) || '{"group_by":"phase"}') ->> 'id')::uuid id;
select pg_temp.check(exists (select 1 from app.reports where id = (select id from t_rep) and definition ->> 'entity' = 'project'), 'a project report can be saved');

-- ---------------------------------------------------------------------------
-- INS-01: report entity «campaign» — type, status, owner; sent, open rate and click rate from app.campaign_stats
select pg_temp.as_nobody();
create temp table t_cm as select gen_random_uuid() c1, gen_random_uuid() c2, gen_random_uuid() c3, gen_random_uuid() c4,
  (select id from app.admins where email = 'tor@orgpuls.no') tor, (select id from app.admins where email = 'jonas@orgpuls.no') jonas;
insert into app.campaigns (id, name, type, status, rendered_html, utm_campaign, tracking, owner_id, visibility, started_at, sent_at)
select x.id, x.n, x.ty, x.st, case when x.st <> 'draft' then '<p>x</p>' end, x.u, x.tr, x.o, x.v, case when x.st = 'sent' then now() - interval '2 days' end,
       case when x.st = 'sent' then now() - interval '2 days' end
from t_cm, lateral (values (c1, 'P6R Sendt A', 'newsletter', 'sent', 'p6r-c1', true, tor, 'all'), (c2, 'P6R Sendt B', 'one_off', 'sent', 'p6r-c2', false, jonas, 'all'),
                           (c3, 'P6R Utkast', 'newsletter', 'draft', 'p6r-c3', true, tor, 'all'), (c4, 'P6R Privat', 'newsletter', 'sent', 'p6r-c4', true, tor, 'owner')) x(id, n, ty, st, u, tr, o, v);
insert into app.campaign_recipients (campaign_id, state, sent_at, delivered_at, first_open_at, first_click_at, opens, clicks)
select c, 'delivered', now() - interval '2 days', now() - interval '2 days', case when g <= o then now() - interval '1 day' end, case when g <= k then now() - interval '1 day' end,
       case when g <= o then 1 else 0 end, case when g <= k then 1 else 0 end
from t_cm, lateral (values (c1, 10, 4, 2), (c2, 5, 5, 3), (c4, 3, 3, 0)) x(c, n, o, k), generate_series(1, x.n) g;
insert into app.campaign_recipients (campaign_id, state, skip_reason) select c1, 'skipped', 'not_subscribed' from t_cm;
create temp table t_cd as select '{"entity":"campaign","filters":[{"f":"utm_campaign","op":"in","v":["p6r-c1","p6r-c2","p6r-c3","p6r-c4"]}]}'::jsonb d;
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select (r ->> 'total')::int = 18 and r ->> 'unit' = 'count' from (select public.report_run((select d from t_cd) || '{"measure":{"fn":"sent"}}') r) x),
                     'sent: the recipients sent (a skipped one is not), summed over the campaigns (10 + 5 + 3)');
select pg_temp.check((select (r ->> 'total')::numeric = 53.8 and r ->> 'unit' = 'percent' from (select public.report_run((select d from t_cd) || '{"measure":{"fn":"open_rate"}}') r) x),
                     'open rate: unique opens ÷ delivered over the tracked campaigns only (7 of 13); the untracked campaign''s opens are not figures');
select pg_temp.check((public.report_run((select d from t_cd) || '{"measure":{"fn":"click_rate"}}') ->> 'total')::numeric = 15.4, 'click rate: 2 of 13 tracked deliveries');
select pg_temp.check((select (x ->> 'value')::numeric = (app.campaign_stats((select c1 from t_cm)) ->> 'open_rate')::numeric
                      from jsonb_array_elements(public.report_run((select d from t_cd) || '{"group_by":"type","measure":{"fn":"open_rate"},"filters":[{"f":"utm_campaign","op":"eq","v":"p6r-c1"}]}') -> 'rows') x),
                     'one campaign''s rate in a report is the campaign card''s figure (same function, CMP-09)');
select pg_temp.check(pg_temp.rows_of(public.report_run((select d from t_cd) || '{"group_by":"type","measure":{"fn":"open_rate"}}')) = '[["newsletter",53.8],["one_off",null]]'::jsonb,
                     'an untracked campaign''s rate is no figure (null), never zero');
select pg_temp.check(pg_temp.rows_of(public.report_run((select d from t_cd) || '{"group_by":"status"}')) = '[["draft",1],["sent",3]]'::jsonb
                 and pg_temp.rows_of(public.report_run((select d from t_cd) || '{"group_by":"type"}')) = '[["newsletter",3],["one_off",1]]'::jsonb,
                     'campaigns per status and per type (generic rule)');
select pg_temp.check(jsonb_array_length(public.report_run((select d from t_cd) || '{"group_by":"owner"}') -> 'rows') = 2, 'campaigns per owner');
select pg_temp.check(pg_temp.rows_of(public.report_run((select d from t_cd) || '{"group_by":"status","measure":{"fn":"sent"}}')) = '[["draft",0],["sent",18]]'::jsonb,
                     'a draft has sent nobody: 0, a real count');
select pg_temp.expect_detail($$select public.report_run('{"entity":"project","measure":{"fn":"open_rate"}}')$$, 'invalid', 'measure', 'rates are campaign measures');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((public.report_run((select d from t_cd) || '{"measure":{"fn":"sent"}}') ->> 'total')::int = 15
                 and (public.report_run((select d from t_cd) || '{"measure":{"fn":"open_rate"}}') ->> 'total')::numeric = 40.0,
                     'the analyst''s figures leave out the campaign they may not see (4 of 10)');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check((public.report_run((select d from t_cd) || '{"measure":{"fn":"sent"}}') ->> 'total')::int = 5
                 and public.report_run((select d from t_cd) || '{"measure":{"fn":"open_rate"}}') -> 'total' = 'null'::jsonb,
                     'without «See reports of others» Marketing counts its own campaigns; its untracked one has no open rate');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format('select public.report_run(%L)', (select d from t_cd)), 'forbidden', 'campaigns:see', 'Projects without campaigns:see cannot report on campaigns');
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('campaigns', false);
select pg_temp.expect_detail(format('select public.report_run(%L)', (select d from t_cd)), 'module_off', 'campaigns', 'a campaign report needs the campaigns module');
select public.module_set('campaigns', true);
select pg_temp.check((select f -> 'dimensions' @> '["owner","type","status"]' and f -> 'measures' = '["sent","open_rate","click_rate"]' and not f -> 'dimensions' ? 'board'
                      from (select public.report_fields('campaign') f) x), 'the builder is offered type, status and owner, and sent, open rate and click rate');
select pg_temp.check((select f -> 'measures' = '["weighted","cycle_days"]' from (select public.report_fields('deal') f) x)
                 and (select f -> 'measures' = '[]' from (select public.report_fields('person') f) x), 'the other entities keep their measures');
select pg_temp.check((select array_agg(x ->> 'title' order by x ->> 'title') from jsonb_array_elements(public.report_drill((select d from t_cd) || '{"group_by":"type"}',
                        '{"key":"one_off"}')) x) = array['P6R Sendt B'], 'a campaign row opens its campaigns');
select pg_temp.expect_detail($$select public.report_run('{"entity":"meeting"}')$$, 'invalid', 'entity', 'the entity list stays closed');

rollback;
