-- simple_platform_invariants.sql — Sentral Simple › Platform (0057): the five roles, offered sets, the owner, staff_list's
-- additions, plan_accounts and the status message's delivery record.
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

create temp table t_staff as select
  (select id from app.admins where email = 'tor@orgpuls.no') tor, (select id from app.admins where email = 'ingrid@orgpuls.no') ingrid,
  (select id from app.admins where email = 'sara@orgpuls.no') sara, (select id from app.admins where email = 'hanna@orgpuls.no') hanna,
  (select id from app.permission_sets where key = 'finance') finance, (select id from app.permission_sets where key = 'project') project,
  (select id from app.permission_sets where key = 'marketing') marketing, (select id from app.permission_sets where key = 'analyst') analyst,
  (select id from app.permission_sets where key = 'admin') admin_set;

-- ---------------------------------------------------------------------------
-- the five roles
select pg_temp.check((select array_agg(key || '=' || name order by key) from app.permission_sets where offered and key is not null)
                     = array['admin=Admin', 'analyst=Read-only', 'marketing=Marketing', 'sales=Sales', 'support=Support'],
                     'the offered presets are the design''s five roles: Admin, Sales, Support, Marketing, Read-only');
select pg_temp.check((select bool_and(not offered) from app.permission_sets where key in ('finance', 'project'))
                     and (select count(*) from app.permission_sets where key in ('finance', 'project')) = 2,
                     'Finance and Projects still exist (history, queues) but are not offered');
select pg_temp.check((select rights @> array['campaigns:reports_others', 'campaigns:workflows', 'campaigns:delete', 'global:see', 'campaigns:see'] from app.permission_sets where key = 'marketing'),
                     'Marketing opens Growth: campaign reports, workflows, delete, and Global › See');
select pg_temp.check((select rights @> array['campaigns:see', 'campaigns:add', 'deals:see'] and not rights && array['campaigns:delete', 'campaigns:configure']
                      from app.permission_sets where key = 'sales'), 'Sales gets CRM › Lists (campaigns see and add), nothing more of Campaigns');
select pg_temp.check((select rights @> array['tickets:see', 'global:see'] from app.permission_sets where key = 'support'), 'Support keeps tickets and Global');
select pg_temp.check((select rights <@ x and rights @> x
                      from app.permission_sets, (select array(select s || ':' || a from unnest(array['deals', 'projects', 'campaigns', 'global', 'tickets']) s,
                                                                                       unnest(array['see', 'reports_others']) a) x) v
                      where key = 'analyst'), 'Read-only sees and reads reports, nothing else');
select pg_temp.check(not exists (select 1 from app.admins a join app.permission_sets p on p.id = a.permission_set_id where a.active and not p.offered),
                     'nobody holds a set that is not offered (Finance → Read-only, Projects → Sales)');
select pg_temp.check((select p.key from app.admins a join app.permission_sets p on p.id = a.permission_set_id where a.email = 'sara@orgpuls.no') = 'analyst'
                     and (select p.key from app.admins a join app.permission_sets p on p.id = a.permission_set_id where a.email = 'emma@orgpuls.no') = 'sales',
                     'the design''s map: Finance is Read-only, Project is Sales');
select pg_temp.check(not exists (select 1 from app.audit where action = 'staff.role_folded' and (detail ->> 'from') not in ('finance', 'project')),
                     'a fold is audited with where the person came from');

-- ---------------------------------------------------------------------------
-- staff_list and access_model
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select x ->> 'permission_set_key' = 'admin' and (x ->> 'owner')::boolean and (x ->> 'login')::boolean
                      from jsonb_array_elements(public.staff_list()) x where (x ->> 'id')::uuid = (select tor from t_staff)),
                     'staff_list names the set''s key, the owner and, for global:security, whether a login exists');
select pg_temp.check((select bool_and(not (x ->> 'owner')::boolean) from jsonb_array_elements(public.staff_list()) x where (x ->> 'id')::uuid <> (select tor from t_staff)),
                     'only the owner is the owner');
select pg_temp.check((select (x -> 'offered')::boolean = false from jsonb_array_elements(public.access_model() -> 'permission_sets') x where x ->> 'key' = 'finance')
                     and (select (x -> 'offered')::boolean from jsonb_array_elements(public.access_model() -> 'permission_sets') x where x ->> 'key' = 'sales'),
                     'access_model says which sets are offered');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((select bool_and(x -> 'login' = 'null'::jsonb and x -> 'last_seen_at' = 'null'::jsonb) from jsonb_array_elements(public.staff_list()) x),
                     'without global:security nobody''s login state or last activity is read');
select pg_temp.check((select count(*) from jsonb_array_elements(public.staff_list()) x where x ->> 'email' is not null) = 1,
                     'and only one''s own address');

-- ---------------------------------------------------------------------------
-- staff_save: offered sets only; the owner stays Admin and active
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.staff_save(%L, jsonb_build_object('permission_set_id', %L))$$, (select ingrid from t_staff), (select finance from t_staff)),
                             'invalid', 'permission_set', 'a set that is not offered cannot be given');
select pg_temp.expect_detail(format($$select public.staff_save(null, jsonb_build_object('email', 'ny.p57@orgpuls.no', 'permission_set_id', %L))$$, (select project from t_staff)),
                             'invalid', 'permission_set', 'nor given to someone invited');
select public.staff_save((select ingrid from t_staff), jsonb_build_object('permission_set_id', (select marketing from t_staff)));
select pg_temp.check((select permission_set_id from app.admins where id = (select ingrid from t_staff)) = (select marketing from t_staff), 'an offered set is given');
create temp table t_inv as select (public.staff_save(null, '{"email": "Ny.P57@orgpuls.no"}') ->> 'id')::uuid id;
select pg_temp.check((select permission_set_id = (select analyst from t_staff) and email = 'ny.p57@orgpuls.no' and name is null and active
                      from app.admins where id = (select id from t_inv)), 'an invitation is a staff row on Read-only, the address lower-cased, no name made up');
select pg_temp.check((select (x ->> 'login')::boolean = false and x ->> 'name' = 'ny.p57@orgpuls.no' from jsonb_array_elements(public.staff_list()) x
                      where (x ->> 'id')::uuid = (select id from t_inv)), 'the invited person has no login yet and is listed by their address');
select pg_temp.check(exists (select 1 from app.audit where action = 'staff.invited' and target_id = (select id::text from t_inv)), 'the invitation is audited');
-- someone already on a set that is not offered keeps it while other fields change
update app.admins set permission_set_id = (select finance from t_staff) where id = (select sara from t_staff);
select public.staff_save((select sara from t_staff), jsonb_build_object('permission_set_id', (select finance from t_staff), 'title', 'Økonomi'));
select pg_temp.check((select permission_set_id = (select finance from t_staff) and title = 'Økonomi' from app.admins where id = (select sara from t_staff)),
                     'a person already on a folded set may keep it');
select public.staff_save((select sara from t_staff), jsonb_build_object('active', false));
select public.staff_save((select sara from t_staff), jsonb_build_object('active', true));
select pg_temp.check((select active from app.admins where id = (select sara from t_staff)), 'remove and restore: active off, then on');
-- the owner
update app.admins set permission_set_id = (select admin_set from t_staff) where id = (select hanna from t_staff);
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail(format($$select public.staff_save(%L, '{"active": false}')$$, (select tor from t_staff)), 'forbidden', 'owner', 'nobody switches the owner off');
select pg_temp.expect_detail(format($$select public.staff_save(%L, jsonb_build_object('permission_set_id', %L))$$, (select tor from t_staff), (select analyst from t_staff)),
                             'forbidden', 'owner', 'nobody moves the owner off Admin');
select public.staff_save((select tor from t_staff), jsonb_build_object('permission_set_id', (select admin_set from t_staff), 'title', 'Daglig leder'));
select pg_temp.check((select title from app.admins where id = (select tor from t_staff)) = 'Daglig leder', 'the owner''s profile can still be edited, their set unchanged');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.staff_save(%L, '{"active": false}')$$, (select tor from t_staff)), 'forbidden', 'self', 'the owner cannot switch themselves off either');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format($$select public.staff_save(%L, '{"active": false}')$$, (select sara from t_staff)), 'forbidden', 'global:security', 'changing the team needs global:security');

-- ---------------------------------------------------------------------------
-- plan_accounts: live accounts per band, the bands in order
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select array_agg(x ->> 'band_label') from jsonb_array_elements(public.plan_accounts('orgpuls')) x)
                     = (select array_agg(band_label order by min_employees) from app.plan_versions where product = 'orgpuls' and active),
                     'plan_accounts lists the product''s active bands in order');
select pg_temp.check((select bool_and((x ->> 'accounts')::int = (select count(distinct ap.account_id) from app.subscriptions s
                        join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
                        where s.product = 'orgpuls' and s.plan = x ->> 'band_label' and ap.status = 'active' and app.sub_status(s) not in ('cancelled', 'expired')))
                      from jsonb_array_elements(public.plan_accounts('orgpuls')) x), 'each band counts its live accounts (not cancelled, not expired)');
insert into app.plan_versions (product, band_label, min_employees, max_employees, monthly_price, version, active)
select product, band_label, min_employees, max_employees, monthly_price + 10, version + 1, true from app.plan_versions where product = 'orgpuls' and band_label = '1–25' and active;
select pg_temp.check((select count(*) from jsonb_array_elements(public.plan_accounts('orgpuls')) x where x ->> 'band_label' = '1–25') = 1,
                     'a band with a newer price version is still one band');
select pg_temp.expect_detail($$select public.plan_accounts('nope')$$, 'not_found', null, 'an unknown product is not found');
update app.admins set permission_set_id = (select project from t_staff) where email = 'emma@orgpuls.no';
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail($$select public.plan_accounts('orgpuls')$$, 'forbidden', 'global:see', 'plan_accounts needs global:see, as billing_overview');

-- ---------------------------------------------------------------------------
-- the status message's delivery: recorded by its publisher, once, and «delivered» only with the command in the audit
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_n1 as select (public.status_notice_set('orgpuls', 'Planlagt vedlikehold i kveld P57') ->> 'id')::uuid id;
select pg_temp.expect_detail(format($$select public.status_notice_push_result(%L, true)$$, (select id from t_n1)), 'invalid', 'no_command',
                             'delivered is refused while the command audit holds no successful settings.set_notice');
select public.record_command('tor@orgpuls.no', 'orgpuls', 'settings.set_notice', array['p_en', 'p_no', 'p_on'], false, 'http_502');
select pg_temp.expect_detail(format($$select public.status_notice_push_result(%L, true)$$, (select id from t_n1)), 'invalid', 'no_command', 'a failed call is not a delivery');
select public.record_command('magnus@orgpuls.no', 'orgpuls', 'settings.set_notice', array['p_en', 'p_no', 'p_on'], true, null);
select pg_temp.expect_detail(format($$select public.status_notice_push_result(%L, true)$$, (select id from t_n1)), 'invalid', 'no_command', 'nor someone else''s call');
select public.record_command('tor@orgpuls.no', 'orgpuls', 'settings.set_notice', array['p_en', 'p_no', 'p_on'], true, null);
select public.status_notice_push_result((select id from t_n1), true);
select pg_temp.check((select pushed_at is not null and push_error is null from app.status_notices where id = (select id from t_n1))
                     and public.status_notice_get('orgpuls') #>> '{current,pushed_at}' is not null, 'the delivery is recorded and status_notice_get shows it');
select pg_temp.check(exists (select 1 from app.audit where action = 'status_notice.pushed' and (detail ->> 'notice')::uuid = (select id from t_n1)), 'and audited');
select pg_temp.expect_detail(format($$select public.status_notice_push_result(%L, false, 'timeout')$$, (select id from t_n1)), 'invalid', 'recorded', 'only once');
create temp table t_n2 as select (public.status_notice_set('orgpuls', null) ->> 'id')::uuid id;
select pg_temp.expect_detail(format($$select public.status_notice_push_result(%L, false, 'Not A Code')$$, (select id from t_n2)), 'invalid', 'error',
                             'a failure carries a code, never free text');
select public.status_notice_push_result((select id from t_n2), false, 'http_502');
select pg_temp.check((select push_error = 'http_502' and pushed_at is null from app.status_notices where id = (select id from t_n2)), 'a failed delivery keeps its code');
create temp table t_n3 as select (public.status_notice_set('orgpuls', 'Gammel melding P57') ->> 'id')::uuid id;
update app.status_notices set set_at = now() - interval '10 minutes' where id = (select id from t_n3);
select pg_temp.expect_detail(format($$select public.status_notice_push_result(%L, false, 'timeout')$$, (select id from t_n3)), 'invalid', 'late', 'only right after publishing');
create temp table t_n4 as select (public.status_notice_set('orgpuls', 'Hannas melding P57') ->> 'id')::uuid id;
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail(format($$select public.status_notice_push_result(%L, false, 'timeout')$$, (select id from t_n4)), 'not_found', null, 'only by who published it');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format($$select public.status_notice_push_result(%L, false, 'timeout')$$, (select id from t_n4)), 'forbidden', 'global:configure',
                             'and with global:configure, as the banner itself');

-- the new functions are for signed-in staff only
select pg_temp.check(has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), 'staff only: ' || f)
from unnest(array['public.plan_accounts(text)', 'public.status_notice_push_result(uuid, boolean, text)']) f;

rollback;
