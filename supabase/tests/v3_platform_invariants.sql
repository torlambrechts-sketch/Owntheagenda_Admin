-- v3_platform_invariants.sql — Platform › the new tabs (0082). F-P1: a subscription counts under its plan by Orgpuls' key
-- (small/usual), not only by the band label. Roles and approvals: the registry, the policies seeded from today's rights with
-- nothing needing approval (D-30); a cell changed only by someone allowed to manage roles, on a fresh second factor, never
-- leaving nobody able to, and never beyond the role's rights (a stale row beyond them lets nobody through); command_authorize,
-- which product-command asks before it signs (R-PL-1): allow, deny, approve, and Settings › Second admin holding a deletion at
-- approval (D-30); the queue: only someone in approve mode asks, the arguments come from Sentral's records, a second person
-- who may take the action decides on a fresh second factor (never the requester), the approval runs once with exactly the
-- approved arguments, the command audit decides whether it ran when the app could not tell, the argument values are cleared
-- after it ran, was refused or expired, the sweep runs every five minutes through the job monitor, and nothing asked can be
-- changed. Customer success,
-- rollouts, errors and the billing portal: each read under its right, each value from its source or null, each follow-up
-- created once while it is open.
\ir _helpers.psql
begin;

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
create or replace function pg_temp.as_mfa(p_email text, p_age int default 30) returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'role', 'authenticated', 'aal', 'aal2', 'email', p_email,
                      'amr', jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint - p_age)))::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;
create or replace function pg_temp.set_of(p_key text) returns uuid language sql as $$ select id from app.permission_sets where key = p_key $$;
-- the approver approves, takes and sends an approved trial extension (product-command consuming the approval)
create or replace function pg_temp.send(p_id uuid) returns void language plpgsql as $$
declare j jsonb;
begin
  perform public.approval_decide(p_id, true);
  j := public.approval_take(p_id);
  perform public.command_authorize('orgpuls', 'billing.extend_trial', p_id, j -> 'args');
end $$;

-- ---------------------------------------------------------------------------
-- closed
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
    and c.relname in ('staff_actions', 'command_actions', 'action_policies', 'approval_requests', 'plus_followups')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the new tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace
                      and c.relname in ('staff_actions', 'command_actions', 'action_policies', 'approval_requests', 'plus_followups')) = 5, 'all five exist');
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute'), 'nobody signed in calls ' || f)
from unnest(array['app.action_mode(uuid, text)', 'app.approval_create(uuid, text, jsonb, text)', 'app.policy_apply(uuid, text, text, uuid)',
                  'app.approval_sweep()', 'app.approval_outcome(app.approval_requests)', 'app.approval_close(app.approval_requests, text, text, boolean)',
                  'app.mail_errors(text, int)', 'app.plan_band(text, text)', 'app.request_mrr(uuid, text)']) f;
select pg_temp.check(not has_function_privilege('anon', f::regprocedure, 'execute') and has_function_privilege('authenticated', f::regprocedure, 'execute'),
                     'only signed-in callers reach ' || f)
from unnest(array['public.command_authorize(text, text, uuid, jsonb)', 'public.access_matrix()', 'public.approvals_list()',
                  'public.approval_decide(uuid, boolean, text, text)', 'public.billing_portal(text)', 'public.customer_errors(text, int)']) f;

-- ---------------------------------------------------------------------------
-- F-P1: Orgpuls sends small/usual/group; a subscription on «small» counts under the ≤ 25 band
select pg_temp.as_staff('sara@orgpuls.no');
create temp table t_fp1 on commit drop as
  select s.tenant_id from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
  where s.product = 'orgpuls' and s.plan = '1–25' and ap.status = 'active' and app.sub_status(s) in ('trial', 'active', 'past_due') limit 1;
create temp table t_fp1_before on commit drop as
  select (x ->> 'accounts')::int n from jsonb_array_elements(public.plan_accounts('orgpuls')) x where x ->> 'band_label' = '1–25';
update app.plan_versions set plan_key = 'small' where product = 'orgpuls' and band_label = '1–25';
update app.subscriptions set plan = 'small' where product = 'orgpuls' and tenant_id = (select tenant_id from t_fp1);
select pg_temp.check((select (x ->> 'accounts')::int from jsonb_array_elements(public.plan_accounts('orgpuls')) x where x ->> 'band_label' = '1–25')
                     = (select n from t_fp1_before), 'F-P1: an account on plan «small» still counts under the 1–25 band');
select pg_temp.check((select x ->> 'plan_key' from jsonb_array_elements(public.plan_accounts('orgpuls')) x where x ->> 'band_label' = '1–25') = 'small',
                     'plan_accounts names each band''s key');
select pg_temp.check((app.plan_band('orgpuls', 'small')).max_employees = 25 and (app.plan_band('orgpuls', '1–25')).max_employees = 25
                     and (app.plan_band('orgpuls', 'group')).id is null, 'a plan is found by key or label; one the catalogue does not hold is null');

-- ---------------------------------------------------------------------------
-- the registry and the seed (D-30: nothing needs approval; nobody gained anything)
select pg_temp.check((select count(*) from app.staff_actions) = 12, 'the matrix has the design''s twelve actions');
select pg_temp.check(not exists (select 1 from app.action_policies where mode = 'approve'), 'no action needs approval until someone switches it on');
select pg_temp.check(app.set_mode(pg_temp.set_of('admin'), 'account.delete') = 'allow' and app.set_mode(pg_temp.set_of('support'), 'account.delete') = 'deny',
                     'deleting an account stays the Admin''s');
select pg_temp.check(app.set_mode(pg_temp.set_of('support'), 'trial.extend') = 'allow' and app.set_mode(pg_temp.set_of('sales'), 'trial.extend') = 'deny',
                     'extending a trial follows Global › Edit others (Support yes, Sales no)');
select pg_temp.check(app.set_mode(pg_temp.set_of('analyst'), 'flags.change') = 'deny' and app.set_mode(pg_temp.set_of('admin'), 'announcements.publish') = 'allow',
                     'flags and announcements follow Global › Configure');
select pg_temp.check(app.set_mode(pg_temp.set_of('sales'), 'customers.export') = 'allow' and app.set_mode(pg_temp.set_of('support'), 'customers.export') = 'deny',
                     'a right-backed row shows the role''s right');
select pg_temp.check(app.set_mode(pg_temp.set_of('admin'), 'plan.change') = 'deny', 'an action with nothing behind it is allowed to nobody');

select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check(jsonb_array_length(public.access_matrix() -> 'roles') = 5 and jsonb_array_length(public.access_matrix() -> 'actions') = 12,
                     'Read-only reads the matrix: five roles, twelve actions');
select pg_temp.check(public.access_matrix() -> 'cells' -> pg_temp.set_of('admin')::text ->> 'plan.change' = 'none', 'an unavailable cell says so');
select pg_temp.check(public.access_matrix() ->> 'manage' = 'deny', 'Read-only may not change the matrix');
select pg_temp.as_nobody();
select pg_temp.expect_error('select public.access_matrix()', 'not_signed_in', 'the matrix needs a signed-in staff member');

-- changing a cell
select pg_temp.as_mfa('ingrid@orgpuls.no');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'trial.extend', 'approve')$$, pg_temp.set_of('support')),
                             'forbidden', 'action:roles.manage', 'Sales may not change the matrix');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'trial.extend', 'approve')$$, pg_temp.set_of('support')),
                             'forbidden', 'fresh_mfa', 'a change needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'flags.change', 'approve')$$, pg_temp.set_of('support')),
                             'invalid', 'mode', 'approval is offered only where the queue can execute the action');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'customers.export', 'deny')$$, pg_temp.set_of('sales')),
                             'invalid', 'action', 'a right-backed row is changed in Settings, not here');
select pg_temp.check((public.action_policy_set(pg_temp.set_of('support'), 'trial.extend', 'approve') ->> 'applied')::boolean,
                     'the owner switches approval on for Support''s trial extensions');
select pg_temp.check(exists (select 1 from app.audit a where a.action = 'action_policy.changed' and a.target_id = pg_temp.set_of('support')::text
                             and a.detail ->> 'to' = 'approve' and a.detail ->> 'from' = 'allow'), 'the change is audited with before and after');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'roles.manage', 'approve')$$, pg_temp.set_of('admin')),
                             'invalid', 'last_manager', 'the matrix can never be left without someone able to change it');

-- the matrix narrows a role, never widens it: the role's rights are the ceiling, and a right is given in Settings
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'account.delete', 'allow')$$, pg_temp.set_of('analyst')),
                             'invalid', 'beyond_role', 'Read-only cannot be allowed to delete an account (Admin only)');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'flags.change', 'allow')$$, pg_temp.set_of('analyst')),
                             'invalid', 'beyond_role', 'nor to change flags without Global › Configure');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'trial.extend', 'approve')$$, pg_temp.set_of('sales')),
                             'invalid', 'beyond_role', 'nor to ask for approval of what its rights do not reach');
select pg_temp.check(not (public.action_policy_set(pg_temp.set_of('analyst'), 'account.delete', 'deny') ->> 'applied')::boolean,
                     'denying is always possible (and here already so)');
select pg_temp.check(public.access_matrix() -> 'reach' -> pg_temp.set_of('analyst')::text = '[]'::jsonb
                     and public.access_matrix() -> 'reach' -> pg_temp.set_of('support')::text = '["trial.extend"]'::jsonb
                     and jsonb_array_length(public.access_matrix() -> 'reach' -> pg_temp.set_of('admin')::text) = 5,
                     'the matrix names the cells each role''s rights reach');
-- a policy row beyond the role (written by hand, or before a right was taken away in Settings) lets nobody through
insert into app.action_policies (permission_set_id, action, mode)
values (pg_temp.set_of('analyst'), 'account.delete', 'allow'), (pg_temp.set_of('analyst'), 'flags.change', 'allow')
on conflict (permission_set_id, action) do update set mode = excluded.mode;
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail($$select public.command_authorize('orgpuls', 'orgs.delete_now')$$, 'forbidden', 'action:account.delete',
                             'a stale row does not let Read-only delete an organisation through product-command');
select pg_temp.expect_detail($$select public.command_authorize('orgpuls', 'modules.set_status')$$, 'forbidden', 'action:flags.change',
                             'nor change a module');
select pg_temp.check(public.access_matrix() -> 'cells' -> pg_temp.set_of('analyst')::text ->> 'account.delete' = 'deny', 'the matrix shows it denied');

-- ---------------------------------------------------------------------------
-- command_authorize: what product-command asks before it signs
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.command_authorize('orgpuls', 'billing.extend_trial')$$, 'approval_required', 'trial.extend',
                             'a Support member in approve mode cannot extend a trial alone');
select pg_temp.expect_detail($$select public.command_authorize('orgpuls', 'orgs.delete_now')$$, 'forbidden', 'action:account.delete',
                             'Support cannot delete an organisation');
select pg_temp.check((public.command_authorize('orgpuls', 'orgs.list') ->> 'ok')::boolean, 'a read needs Global › See only');
select pg_temp.expect_detail($$select public.command_authorize('orgpuls', 'settings.set_indexing')$$, 'forbidden', 'global:configure',
                             'a write tied to no action needs Global › Configure');
select pg_temp.expect_detail($$select public.command_authorize('orgpuls', 'orgs.nothing')$$, 'invalid', 'command', 'an unknown command is refused');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail($$select public.command_authorize('orgpuls', 'billing.extend_trial')$$, 'forbidden', 'action:trial.extend',
                             'Read-only could extend a trial before (R-PL-1); now it cannot');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(public.command_authorize('orgpuls', 'orgs.delete_now') ->> 'mode' = 'allow', 'the Admin deletes without approval while it is off');
select pg_temp.as_staff('tor@orgpuls.no', 'aal1');
select pg_temp.expect_error($$select public.command_authorize('orgpuls', 'orgs.list')$$, 'not_signed_in', 'no second factor, no command');

-- ---------------------------------------------------------------------------
-- the queue
create temp table t_org on commit drop as
  select o.id, o.org_number, ap.tenant_id from app.organizations o
  join app.account_products ap on ap.account_id = o.account_id and ap.product = 'orgpuls' and ap.status = 'active'
  join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
  where o.deleted_at is null and o.org_number is not null and app.sub_status(s) = 'trial' order by o.name limit 1;
grant all on t_org to authenticated;
select pg_temp.check((select count(*) from t_org) = 1, 'an Orgpuls organisation in trial to ask about');

select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.approval_request('trial.extend', '{"organization": "%s", "days": 14}', 'Asked on the phone')$$, (select id from t_org)),
                             'invalid', 'not_needed', 'someone allowed to act alone does not ask');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail(format($$select public.approval_request('trial.extend', '{"organization": "%s", "days": 14}', 'Asked on the phone')$$, (select id from t_org)),
                             'forbidden', 'action:trial.extend', 'someone denied the action cannot ask for it');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_error(format($$select public.approval_request('trial.extend', '{"organization": "%s", "days": 14}', '')$$, (select id from t_org)),
                            'reason_required', 'a request needs a reason');
select pg_temp.expect_detail(format($$select public.approval_request('trial.extend', '{"organization": "%s", "days": 99}', 'Asked on the phone')$$, (select id from t_org)),
                             'invalid', 'days', 'a trial is extended by 1 to 60 days');
create temp table t_req on commit drop as
  select (public.approval_request('trial.extend', jsonb_build_object('organization', (select id from t_org), 'days', 14), 'Asked on the phone') ->> 'id')::uuid id;
grant all on t_req to authenticated;
select pg_temp.check((select r.state = 'pending' and r.args ->> 'p_org' = (select tenant_id from t_org) and (r.args ->> 'p_days')::int = 14
                      and r.requested_by = (select id from app.admins where email = 'hanna@orgpuls.no')
                      from app.approval_requests r where r.id = (select id from t_req)),
                     'the request holds the tenant and days, built from Sentral''s records');
select pg_temp.check(exists (select 1 from app.notifications n join app.admins a on a.id = n.staff_id
                             where a.email = 'tor@orgpuls.no' and n.key = 'approval.requested' and n.route = '/platform?tab=access'),
                     'everyone who may decide is told');
select pg_temp.check(not exists (select 1 from app.notifications n join app.admins a on a.id = n.staff_id
                                 where a.email in ('hanna@orgpuls.no', 'ingrid@orgpuls.no') and n.key = 'approval.requested'),
                     'neither the requester nor someone denied the action is told');
select pg_temp.check(not exists (select 1 from app.audit a where a.target_id = (select id::text from t_req) and a.detail::text like '%Asked on the phone%'),
                     'the audit carries ids and keys, not the reason or the arguments');
select pg_temp.check((select (x ->> 'mine')::boolean and not (x ->> 'can_decide')::boolean and not x ? 'args'
                      from jsonb_array_elements(public.approvals_list() -> 'rows') x where (x ->> 'id')::uuid = (select id from t_req)),
                     'the requester sees their request, cannot decide it, and never sees the arguments');
select pg_temp.check(public.approvals_list() -> 'requestable' = '["trial.extend"]'::jsonb, 'Support may ask for a trial extension');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.approvals_list() -> 'rows') x where (x ->> 'id')::uuid = (select id from t_req)),
                     'someone denied the action does not see the request');
select pg_temp.as_mfa('hanna@orgpuls.no');
select pg_temp.expect_detail(format($$select public.approval_decide(%L, true)$$, (select id from t_req)), 'forbidden', 'own_request', 'nobody approves their own request');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.approval_decide(%L, true)$$, (select id from t_req)), 'forbidden', 'fresh_mfa', 'approving needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.check((select (x ->> 'can_decide')::boolean from jsonb_array_elements(public.approvals_list() -> 'rows') x where (x ->> 'id')::uuid = (select id from t_req)),
                     'the Admin may decide it');
select pg_temp.check(public.approval_decide((select id from t_req), true) ->> 'state' = 'approved', 'approved: the command runs next');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_error(format($$select public.approval_take(%L)$$, (select id from t_req)), 'not_found', 'only the approver takes it');
select pg_temp.as_mfa('tor@orgpuls.no');
create temp table t_take on commit drop as select public.approval_take((select id from t_req)) j;
grant all on t_take to authenticated;
select pg_temp.check((select j -> 'args' ->> 'p_org' from t_take) = (select tenant_id from t_org) and (select j ->> 'command' from t_take) = 'billing.extend_trial',
                     'the approver gets the approved command and arguments');
select pg_temp.expect_error(format($$select public.approval_take(%L)$$, (select id from t_req)), 'invalid', 'it is taken once');
select pg_temp.expect_detail(format($$select public.command_authorize('orgpuls', 'billing.extend_trial', %L, '{"p_org": "x", "p_days": 60, "p_reason": "x"}')$$, (select id from t_req)),
                             'forbidden', 'approval', 'other arguments than the approved ones are refused');
select pg_temp.check(public.command_authorize('orgpuls', 'billing.extend_trial', (select id from t_req), (select j -> 'args' from t_take)) ->> 'mode' = 'approved',
                     'the approved arguments pass, bound to the approval');
select pg_temp.expect_detail(format($$select public.command_authorize('orgpuls', 'billing.extend_trial', %L, %L)$$, (select id from t_req), (select j -> 'args' from t_take)),
                             'forbidden', 'approval', 'an approval is used once');
select pg_temp.expect_detail(format($$select public.approval_done(%L, true)$$, (select id from t_req)), 'invalid', 'not_sent',
                             '«executed» needs the successful call in the command audit');
select public.record_command('tor@orgpuls.no', 'orgpuls', 'billing.extend_trial', array['p_days', 'p_org', 'p_reason'], true, null);
select pg_temp.check(public.approval_done((select id from t_req), true) ->> 'state' = 'executed', 'the outcome is recorded');
select pg_temp.check((select r.args is null and r.state = 'executed' and r.consumed_at is not null from app.approval_requests r where r.id = (select id from t_req)),
                     'the argument values are cleared once it ran');
select pg_temp.check(exists (select 1 from app.notifications n join app.admins a on a.id = n.staff_id
                             where a.email = 'hanna@orgpuls.no' and n.key = 'approval.decided' and n.params ->> 'state' = 'executed'),
                     'the requester is told the outcome');

-- an outcome the app could not see (no answer in time): the command audit decides, not the app's guess
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_u on commit drop as
  select v.d, (public.approval_request('trial.extend', jsonb_build_object('organization', (select id from t_org), 'days', v.d), 'Asked again') ->> 'id')::uuid id
  from (values (5), (6), (7), (8)) v(d);
grant all on t_u to authenticated;
create or replace function pg_temp.u(p_days int) returns uuid language sql as $$ select id from t_u where d = p_days $$;
select pg_temp.as_mfa('magnus@orgpuls.no');
select pg_temp.send(pg_temp.u(5));
select public.record_command('magnus@orgpuls.no', 'orgpuls', 'billing.extend_trial', array['p_days', 'p_org', 'p_reason'], true, null);
select pg_temp.check(public.approval_done(pg_temp.u(5), null, 'unreachable') ->> 'state' = 'executed',
                     'no answer in time, but the audit holds the call: executed, not «failed»');
select pg_temp.check(public.approval_decide(pg_temp.u(7), true) ->> 'state' = 'approved', 'approved');
create temp table t_u7 on commit drop as select public.approval_take(pg_temp.u(7)) j;
grant all on t_u7 to authenticated;
select pg_temp.check(public.approval_done(pg_temp.u(7), null, 'unreachable') ->> 'state' = 'failed', 'nothing went out under the approval: failed at once');
select pg_temp.check((select result_code = 'unreachable' and args is null from app.approval_requests where id = pg_temp.u(7)), 'with the app''s code, its arguments gone');
select pg_temp.expect_detail(format($$select public.command_authorize('orgpuls', 'billing.extend_trial', %L, %L)$$, pg_temp.u(7), (select j -> 'args' from t_u7)),
                             'forbidden', 'approval', 'and a late call under it is refused');
select pg_temp.send(pg_temp.u(6));
select pg_temp.check(public.approval_done(pg_temp.u(6), null, 'timeout') ->> 'state' = 'executing', 'sent, and no answer in the audit yet: it stays open');
select pg_temp.check((select state = 'executing' and args is null from app.approval_requests where id = pg_temp.u(6)), 'without its arguments');
update app.approval_requests set taken_at = taken_at - interval '11 minutes' where id = pg_temp.u(6);
select pg_temp.check((app.approval_sweep() ->> 'failed')::int = 1, 'the sweep settles it after ten minutes');
select pg_temp.check((select state = 'failed' and result_code = 'unconfirmed' from app.approval_requests where id = pg_temp.u(6)),
                     'no call in the audit: failed');
select pg_temp.send(pg_temp.u(8));
select pg_temp.check(public.approval_done(pg_temp.u(8), null, 'timeout') ->> 'state' = 'executing', 'the answer comes after the app gave up');
select public.record_command('magnus@orgpuls.no', 'orgpuls', 'billing.extend_trial', array['p_days', 'p_org', 'p_reason'], true, null);
update app.approval_requests set taken_at = taken_at - interval '11 minutes' where id = pg_temp.u(8);
select pg_temp.check((app.approval_sweep() ->> 'executed')::int = 1, 'the sweep settles it');
select pg_temp.check((select state = 'executed' and result_code is null and args is null from app.approval_requests where id = pg_temp.u(8)),
                     'the call is in the audit: executed');
select pg_temp.check(exists (select 1 from app.notifications n join app.admins a on a.id = n.staff_id
                             where a.email = 'hanna@orgpuls.no' and n.key = 'approval.decided' and n.params ->> 'state' = 'executed'
                               and n.params ->> 'ref' = (select 'A-' || r.ref from app.approval_requests r where r.id = pg_temp.u(8))),
                     'and the requester is told');
select pg_temp.check((select a.detail ->> 'settled_by' from app.audit a where a.action = 'approval.executed' and a.target_id = pg_temp.u(8)::text) = 'sweep'
                     and (select a.detail ->> 'settled_by' from app.audit a where a.action = 'approval.executed' and a.target_id = pg_temp.u(5)::text) = 'approver',
                     'the audit says who settled each outcome');

-- nothing asked can be changed; the state only moves forward; nothing is deleted
select pg_temp.expect_error(format($$update app.approval_requests set reason = 'Something else' where id = %L$$, (select id from t_req)),
                            'an approval request cannot be changed', 'the reason cannot be changed');
select pg_temp.expect_error(format($$update app.approval_requests set state = 'pending' where id = %L$$, (select id from t_req)),
                            'an approval request only moves forward', 'the state never moves back');
select pg_temp.expect_error(format($$delete from app.approval_requests where id = %L$$, (select id from t_req)), 'approval requests are kept', 'a request is never deleted');

-- rejection and expiry clear the arguments
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_req2 on commit drop as
  select (public.approval_request('trial.extend', jsonb_build_object('organization', (select id from t_org), 'days', 7), 'A second ask') ->> 'id')::uuid id;
grant all on t_req2 to authenticated;
select pg_temp.as_mfa('magnus@orgpuls.no');
select pg_temp.check(public.approval_decide((select id from t_req2), false, 'Not this time') ->> 'state' = 'rejected', 'a colleague who may act rejects it');
select pg_temp.check((select args is null and decided_by = (select id from app.admins where email = 'magnus@orgpuls.no') from app.approval_requests where id = (select id from t_req2)),
                     'a rejected request keeps no arguments');
insert into app.approval_requests (action, product, command, params, args, reason, requested_by, requested_at, expires_at)
values ('trial.extend', 'orgpuls', 'billing.extend_trial', '{"days": 3}', '{"p_org": "t", "p_days": 3, "p_reason": "r"}', 'Old request',
        (select id from app.admins where email = 'hanna@orgpuls.no'), now() - interval '8 days', now() - interval '1 day');
select pg_temp.check(exists (select 1 from app.job_defs where key = 'approval_sweep' and fn = 'app.approval_sweep' and source = 'cron' and schedule = '*/5 * * * *')
                     and exists (select 1 from cron.job where jobname = 'platform-approval-sweep' and schedule = '*/5 * * * *'
                                 and command = 'select app.run_job(''approval_sweep'')'),
                     'the sweep runs every five minutes through the job monitor, whether or not anyone opens the queue');
create temp table t_sweep on commit drop as select app.run_job('approval_sweep') id;
select pg_temp.check((select state = 'expired' and args is null from app.approval_requests where reason = 'Old request'), 'after seven days a request expires and its arguments go');
select pg_temp.check((select r.state = 'succeeded' and (r.info ->> 'expired')::int >= 1 from app.job_runs r where r.id = (select id from t_sweep)),
                     'the job monitor records the run with its counts');

-- a deletion while Settings › Second admin is on (D-30): the gate product-command asks holds it at approval too; an Admin asks
-- with the org.nr typed, and a second admin approves, typing it again
insert into app.setting_values (key, scope_id, value) values ('second_admin', '', 'on')
on conflict (key, scope_id) do update set value = excluded.value;
update app.admins set permission_set_id = pg_temp.set_of('admin') where email = 'eirik@orgpuls.no';
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.command_authorize('orgpuls', 'orgs.delete_now')$$, 'approval_required', 'account.delete',
                             'with Second admin on, an Admin cannot delete an organisation alone, not even straight through product-command');
select pg_temp.check(public.access_matrix() -> 'cells' -> pg_temp.set_of('admin')::text ->> 'account.delete' = 'approve'
                     and public.access_matrix() -> 'forced' = '["account.delete"]'::jsonb, 'the matrix shows the deletion needing approval, and why');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'account.delete', 'allow')$$, pg_temp.set_of('admin')),
                             'invalid', 'second_admin', 'the matrix cannot allow it alone while the setting is on');
select pg_temp.check(public.approvals_list() -> 'requestable' ? 'account.delete', 'the Admin may ask for it');
select pg_temp.expect_detail(format($$select public.approval_request('account.delete', '{"organization": "%s", "confirm": "000000000"}', 'Cancelled, retention ended')$$, (select id from t_org)),
                             'invalid', 'confirm_mismatch', 'the requester types the org.nr');
create temp table t_del on commit drop as
  select (public.approval_request('account.delete', jsonb_build_object('organization', (select id from t_org), 'confirm', (select org_number from t_org)), 'Cancelled, retention ended') ->> 'id')::uuid id;
grant all on t_del to authenticated;
select pg_temp.as_mfa('magnus@orgpuls.no');
select pg_temp.expect_error(format($$select public.approval_decide(%L, true, null, %L)$$, (select id from t_del), (select org_number from t_org)), 'not_found',
                            'someone who may not delete cannot approve a deletion');
select pg_temp.as_mfa('eirik@orgpuls.no');
select pg_temp.expect_detail(format($$select public.approval_decide(%L, true)$$, (select id from t_del)), 'invalid', 'confirm_mismatch', 'the second admin types it again');
select pg_temp.check(public.approval_decide((select id from t_del), true, null, (select org_number from t_org)) ->> 'state' = 'approved', 'typed again, it is approved');

-- the matrix through the queue: with two able to manage roles, the Admin's own changes need a second person
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'roles.manage', 'allow')$$, pg_temp.set_of('support')),
                             'invalid', 'beyond_role', 'managing roles needs Global › Security first');
update app.permission_sets set rights = rights || array['global:security'] where key = 'support';   -- given in Settings
select public.action_policy_set(pg_temp.set_of('support'), 'roles.manage', 'allow');
select pg_temp.check((public.action_policy_set(pg_temp.set_of('admin'), 'roles.manage', 'approve') ->> 'applied')::boolean,
                     'with Support able to manage roles, the Admin may switch approval on for itself');
select pg_temp.expect_detail(format($$select public.action_policy_set(%L, 'trial.extend', 'allow', 'Sales handles renewals now')$$, pg_temp.set_of('sales')),
                             'invalid', 'beyond_role', 'a request beyond the role''s rights is refused before anyone is asked');
create temp table t_pol on commit drop as
  select (public.action_policy_set(pg_temp.set_of('support'), 'trial.extend', 'allow', 'Support extends trials alone again') ->> 'approval')::uuid id;
grant all on t_pol to authenticated;
select pg_temp.check((select id from t_pol) is not null and app.set_mode(pg_temp.set_of('support'), 'trial.extend') = 'approve',
                     'in approve mode a change becomes a request and changes nothing yet');
select pg_temp.expect_detail(format($$select public.approval_decide(%L, true)$$, (select id from t_pol)), 'forbidden', 'own_request', 'the Admin cannot approve its own change');
select pg_temp.as_mfa('magnus@orgpuls.no');
select pg_temp.check(public.approval_decide((select id from t_pol), true) ->> 'state' = 'executed', 'a second person approves and the change is made');
select pg_temp.check(app.set_mode(pg_temp.set_of('support'), 'trial.extend') = 'allow', 'the approved change is in force');
select pg_temp.as_mfa('tor@orgpuls.no');
create temp table t_pol2 on commit drop as
  select (public.action_policy_set(pg_temp.set_of('admin'), 'trial.extend', 'deny', 'Try it') ->> 'approval')::uuid id;
grant all on t_pol2 to authenticated;
-- meanwhile someone else changes the same cell
update app.action_policies set mode = 'approve' where permission_set_id = pg_temp.set_of('admin') and action = 'trial.extend';
select pg_temp.as_mfa('hanna@orgpuls.no');
select pg_temp.check(public.approval_decide((select id from t_pol2), true) ->> 'state' = 'failed', 'a request for a cell changed since fails');
select pg_temp.check((select result_code = 'changed_since' from app.approval_requests where id = (select id from t_pol2))
                     and app.set_mode(pg_temp.set_of('admin'), 'trial.extend') = 'approve', 'the newer change is not overwritten');

-- ---------------------------------------------------------------------------
-- Customer success
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check(jsonb_array_length(public.onboarding_completion('orgpuls', 365) -> 'steps') = 7, 'seven onboarding steps');
select pg_temp.check((public.onboarding_completion('orgpuls', 365) -> 'steps' -> 0 ->> 'done')::int = (public.onboarding_completion('orgpuls', 365) ->> 'cohort')::int,
                     'every account in the cohort was created');
create temp table t_kurs on commit drop as
  select ap.tenant_id from app.account_products ap where ap.product = 'kurs' and ap.status = 'active' order by ap.created_at desc limit 1;
select pg_temp.check(public.onboarding_completion('kurs', 365) -> 'steps' -> 5 -> 'done' = 'null'::jsonb
                     and public.onboarding_completion('kurs', 365) -> 'steps' -> 1 -> 'done' = 'null'::jsonb,
                     'a step whose source a product never sent is «—», not 0 %');
insert into app.usage_daily (product, tenant_id, day, data) values ('kurs', (select tenant_id from t_kurs), current_date, '{"employees": 12, "rounds_planned": 1}');
select pg_temp.check((public.onboarding_completion('kurs', 365) -> 'steps' -> 1 ->> 'done')::int >= 1
                     and (public.onboarding_completion('kurs', 365) -> 'steps' -> 3 ->> 'done')::int >= 1, 'usage counts the steps it covers');

-- feature requests: the MRR asking only for people who may see deals
create temp table t_fr on commit drop as select id from app.feature_requests where false;
grant all on t_fr to authenticated;
select pg_temp.as_staff('tor@orgpuls.no');
insert into t_fr select (public.feature_request_add('orgpuls', 'Import employees from Visma', null, (select id from t_org)) ->> 'id')::uuid;
update app.subscriptions set price = 565, currency = 'NOK', confirmed_at = now() - interval '1 day', billing_interval = 'month'
where product = 'orgpuls' and tenant_id = (select tenant_id from t_org);
select pg_temp.check((select (x -> 'asking' ->> 'mrr')::numeric from jsonb_array_elements(public.success_requests('orgpuls') -> 'rows') x
                      where (x ->> 'id')::uuid = (select id from t_fr)) = 565, 'the MRR asking is the asking account''s MRR');
insert into app.permission_sets (key, name, kind, rights) values ('tmp_viewer', 'Viewer (test)', 'custom', array['global:see']);
update app.admins set permission_set_id = pg_temp.set_of('tmp_viewer') where email = 'ola@orgpuls.no';
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check(not (public.success_requests('orgpuls') ->> 'money')::boolean
                     and (select x -> 'asking' from jsonb_array_elements(public.success_requests('orgpuls') -> 'rows') x
                          where (x ->> 'id')::uuid = (select id from t_fr)) = 'null'::jsonb, 'without Deals › See there is no MRR asking');
select pg_temp.check(app.set_mode(pg_temp.set_of('tmp_viewer'), 'trial.extend') = 'deny', 'a set made later follows the seed''s rule');

-- renewal signals and the follow-ups
select pg_temp.as_staff('ingrid@orgpuls.no');
insert into app.usage_daily (product, tenant_id, day, data)
select 'orgpuls', s.tenant_id, current_date, jsonb_build_object('employees', 24, 'last_sign_in_at', now() - interval '45 days')
from app.subscriptions s where s.product = 'orgpuls' and s.tenant_id = (select tenant_id from t_fp1);
create temp table t_sig on commit drop as
  select x from jsonb_array_elements(public.renewal_signals('orgpuls')) x
  join app.organizations o on o.id = (x -> 'organization' ->> 'id')::uuid
  join app.account_products ap on ap.account_id = o.account_id and ap.product = 'orgpuls' and ap.tenant_id = (select tenant_id from t_fp1);
select pg_temp.check(exists (select 1 from t_sig where x ->> 'kind' = 'expansion' and (x ->> 'employees')::int = 24 and (x ->> 'max')::int = 25),
                     '24 employees on a 25-employee plan is an expansion signal');
select pg_temp.check(exists (select 1 from t_sig where x ->> 'kind' = 'at_risk' and (x ->> 'days_since_sign_in')::int >= 45), 'no sign-in for 45 days is at risk');
create temp table t_sorg on commit drop as select (x -> 'organization' ->> 'id')::uuid id from t_sig limit 1;
grant all on t_sorg to authenticated;
create temp table t_deal on commit drop as select public.success_deal_create((select id from t_sorg), 'orgpuls', 'Expansion: next plan') j;
select pg_temp.check(not ((select j from t_deal) ->> 'existing')::boolean
                     and exists (select 1 from app.deals d where d.id = ((select j from t_deal) ->> 'id')::uuid and d.organization_id = (select id from t_sorg)),
                     'Create deal makes a deal on the account');
select pg_temp.check((public.success_deal_create((select id from t_sorg), 'orgpuls', 'Expansion: next plan') ->> 'existing')::boolean,
                     'a second click finds the open deal instead of making another');
select pg_temp.check((select (x ->> 'open') is not null from jsonb_array_elements(public.renewal_signals('orgpuls')) x
                      where (x -> 'organization' ->> 'id')::uuid = (select id from t_sorg) and x ->> 'kind' = 'expansion'), 'the signal shows its open deal');
select pg_temp.check((public.success_task_create((select id from t_sorg), 'orgpuls', 'Call about sign-ins') ->> 'id') is not null, 'CSM task creates a task');
select pg_temp.check(exists (select 1 from app.activities a join app.organizations o on o.id = a.organization_id
                                 where a.organization_id = (select id from t_sorg) and a.subject = 'Call about sign-ins' and a.owner_id = coalesce(o.csm_id, o.owner_id)),
                     'a CSM task goes to the account''s customer success manager');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail(format($$select public.success_deal_create(%L, 'orgpuls', 'Expansion')$$, (select id from t_sorg)), 'forbidden', 'deals:add',
                             'Read-only creates no deal');

-- ---------------------------------------------------------------------------
-- Rollouts and announcements
select pg_temp.expect_detail($$select public.announcement_reach('orgpuls', array['owner'])$$, 'invalid', 'roles', 'an audience is Orgpuls'' own roles');
select pg_temp.check((public.announcement_reach('orgpuls') ->> 'users')::int = (
    select count(*) from app.members m join app.account_products ap on ap.product = m.product and ap.tenant_id = m.tenant_id and ap.status = 'active'
    join app.subscriptions s on s.product = m.product and s.tenant_id = m.tenant_id
    where m.product = 'orgpuls' and m.active and app.sub_status(s) not in ('cancelled', 'expired')), 'the reach is the live accounts'' active users');
select pg_temp.check((public.announcement_reach('orgpuls', array['daglig_leder'], array['trial']) ->> 'users')::int
                     <= (public.announcement_reach('orgpuls', array['daglig_leder']) ->> 'users')::int, 'narrowing the audience never widens it');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.limits_near('orgpuls') -> 'rows') x
                             where (x ->> 'employees')::int = 24 and (x ->> 'pct')::int = 96), 'an account at 96 % of its limit is listed');

-- errors per customer: Sentral's own failed mail, and a ticket once
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_err on commit drop as
  select t.id ticket, t.organization_id org from app.tickets t
  where t.product = 'orgpuls' and t.organization_id is not null and t.deleted_at is null and not t.is_sample limit 1;
insert into app.ticket_messages (ticket_id, kind, author_staff_id, body, delivery_status, mail_error)
values ((select ticket from t_err), 'reply', (select id from app.admins where email = 'hanna@orgpuls.no'), 'A reply', 'bounced', 'hard_bounce');
select pg_temp.check((select (x ->> 'replies')::int from jsonb_array_elements(public.customer_errors('orgpuls') -> 'rows') x
                      where (x -> 'organization' ->> 'id')::uuid = (select org from t_err)) >= 1, 'a bounced ticket reply is an error for its organisation');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.customer_errors('orgpuls') -> 'rows') x where x::text like '%A reply%'),
                     'the list carries counts, never a message');
create temp table t_et on commit drop as select public.error_ticket_create((select org from t_err), 'orgpuls', 'Email not delivered (24 h)', '1 ticket reply not delivered') j;
select pg_temp.check(not ((select j from t_et) ->> 'existing')::boolean
                     and exists (select 1 from app.tickets t where t.id = ((select j from t_et) ->> 'id')::uuid and t.category_key = 'bug'), 'Create ticket opens a bug ticket');
select pg_temp.check((public.error_ticket_create((select org from t_err), 'orgpuls', 'Email not delivered (24 h)', null) ->> 'id')::uuid = ((select j from t_et) ->> 'id')::uuid,
                     'a second click finds the open ticket');
select pg_temp.expect_detail(format($$select public.error_ticket_create(%L, 'orgpuls', 'Email not delivered', null)$$,
                                    (select o.id from app.organizations o where o.id not in (select e.organization_id from app.mail_errors('orgpuls', 24) e) limit 1)),
                             'invalid', 'no_errors', 'no ticket for an organisation Sentral knows no failure for');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail(format($$select public.error_ticket_create(%L, 'orgpuls', 'Email', null)$$, (select org from t_err)), 'forbidden', 'tickets:add',
                             'Read-only opens no ticket');

-- ---------------------------------------------------------------------------
-- Billing portal
select pg_temp.check(jsonb_array_length(public.billing_portal('orgpuls') -> 'accounts') > 0, 'the portal lists the product''s accounts');
select pg_temp.check((select x ->> 'band' from jsonb_array_elements(public.billing_portal('orgpuls') -> 'accounts') x
                      join app.organizations o on o.id = (x ->> 'id')::uuid
                      join app.account_products ap on ap.account_id = o.account_id and ap.product = 'orgpuls' and ap.tenant_id = (select tenant_id from t_fp1)
                      limit 1) = '1–25', 'an account on «small» shows the catalogue''s band');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check(not (public.billing_portal('orgpuls') ->> 'tickets')::boolean and public.billing_portal('orgpuls') -> 'tickets_30d' = 'null'::jsonb,
                     'without Tickets › See there are no ticket counts');
select pg_temp.expect_detail($$select public.billing_portal('nothing')$$, 'invalid', 'product', 'an unknown product is refused');

rollback;
