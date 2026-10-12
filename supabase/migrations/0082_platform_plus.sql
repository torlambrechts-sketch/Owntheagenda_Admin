-- 0082_platform_plus.sql — Platform › the new tabs (docs/crm-enrichment/v3/platform-gap.md; PLAN.md wave 1, builder «platform»)
--
-- 1. F-P1: plan_accounts matched a subscription's plan against the band label, while Orgpuls sends its plan keys (small, usual,
--    group): on real data every count was 0. plan_versions gains plan_key; a plan is found by key, or by label for rows written
--    before keys (app.plan_band). Orgpuls' two sized plans are Liten «small» (≤ 25) and Vanlig «usual» (≤ 100).
-- 2. Roles and approvals (X-V3-4: today's five roles). A registry of the sensitive actions, each tied to what enforces it: a
--    product command (asked by product-command through command_authorize before it signs), this database (the matrix itself),
--    an existing right (shown as that right; changed in Settings), or nothing yet (shown as not available). A policy per
--    (permission set, action) — allow, approve or deny — seeded from today's rights, so nobody gains or loses anything by the
--    migration, and no action needs approval until someone switches it on (D-30). The role's rights are the ceiling: the matrix
--    narrows what a role may do (allow → approve → deny), never widens it; a right is given in Settings. Settings › Second
--    admin on makes deleting an account need a second admin's approval here too, where product-command asks (D-30). A request
--    is approved by a second person who may take the action too, never the requester, on a fresh second factor; it expires
--    after seven days; the approval executes the action (a product command run once by the approver, bound to the approved
--    arguments, or the policy change itself), and the command audit decides whether it ran. The command's argument values are
--    kept only until it has run, been refused or expired (R-PL-6), swept every five minutes by the job monitor; the audit holds
--    ids, kinds and codes.
-- 3. Customer success on Sentral's own data: onboarding completion from usage, members and the milestones Orgpuls reports;
--    feature requests (0078) with the MRR of the accounts asking, computed only for people who may see deals; renewal signals
--    (near the plan's employee limit, a health drop, no sign-in); «Create deal» and a CSM task, each once while it is open.
-- 4. Rollouts and announcements, Sentral's half: the real reach of an announcement (active customer users × subscriptions);
--    accounts near their plan's employee limit from usage; errors per customer from what Sentral itself knows (ticket replies
--    and campaign mail that did not arrive) with «Create ticket», once while it is open.
-- 5. Billing portal: each account's current plan from the catalogue and its billing-ticket counts. No invoice, card, dunning or
--    discount exists in Sentral or Orgpuls (Orgpuls invoices by e-mail or EHF; D-22).
-- Every table: app schema, RLS on, no policy, no grant. Every reader and writer: SECURITY DEFINER with search_path ''.

-- ===========================================================================
-- 0. helpers
-- ===========================================================================
-- an integer a product sent in a usage row (a JSON number or digits), else null
create function app.usage_int(p jsonb, p_key text) returns int
  language sql immutable set search_path = ''
as $fn$
  select case when jsonb_typeof(p -> p_key) = 'number' and (p ->> p_key) ~ '^\d{1,9}(\.0+)?$' then (p ->> p_key)::numeric::int
              when jsonb_typeof(p -> p_key) = 'string' and (p ->> p_key) ~ '^\d{1,9}$' then (p ->> p_key)::int end
$fn$;

-- a time a product sent in a usage row, else null (stable: the cast reads the session's time zone for a time without one)
create function app.usage_time(p jsonb, p_key text) returns timestamptz
  language plpgsql stable set search_path = ''
as $fn$
begin
  if coalesce(p ->> p_key, '') !~ '^\d{4}-\d{2}-\d{2}' then return null; end if;
  return (p ->> p_key)::timestamptz;
exception when others then
  return null;
end $fn$;

-- the newest usage row a product sent for one of its tenants
create function app.usage_latest(p_product text, p_tenant text) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select u.data || jsonb_build_object('_day', u.day) from app.usage_daily u
  where u.product = p_product and u.tenant_id = p_tenant order by u.day desc limit 1
$fn$;

-- a product's active accounts with the organisation Sentral keeps for each (sample organisations only in the sandbox)
create function app.plus_accounts_of(p_product text)
  returns table (tenant_id text, account_id uuid, organization_id uuid, name text, created_at timestamptz)
  language sql stable security definer set search_path = ''
as $fn$
  select ap.tenant_id, ap.account_id, o.id, coalesce(o.name, a.name), ap.created_at
  from app.account_products ap
  join app.accounts a on a.id = ap.account_id
  left join lateral (select x.id, x.name from app.organizations x
                     where x.account_id = ap.account_id and x.deleted_at is null
                       and (not x.is_sample or coalesce((select s.sandbox from app.admins s where s.id = app.me()), false))
                     order by x.created_at limit 1) o on true
  where ap.product = p_product and ap.status = 'active'
$fn$;

create function app.plus_product_ok(p_product text) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if p_product is null or not exists (select 1 from app.products p where p.key = p_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
end $fn$;

-- ===========================================================================
-- 1. F-P1: plans by key
-- ===========================================================================
alter table app.plan_versions add column plan_key text check (plan_key is null or plan_key ~ '^[a-z][a-z_]{1,19}$');
update app.plan_versions set plan_key = case max_employees when 25 then 'small' when 100 then 'usual' end
where product = 'orgpuls' and plan_key is null and max_employees in (25, 100);

-- the catalogue band a subscription's plan names: by the product's plan key, or by the band label (rows written before keys);
-- the newest active version. Null when the catalogue does not know the plan.
create function app.plan_band(p_product text, p_plan text) returns app.plan_versions
  language sql stable security definer set search_path = ''
as $fn$
  select pv.* from app.plan_versions pv
  where pv.product = p_product and pv.active and p_plan is not null and (pv.plan_key = p_plan or pv.band_label = p_plan)
  order by (pv.plan_key is not distinct from p_plan) desc, pv.version desc limit 1
$fn$;

-- 0057's body, counting a subscription under its band by key or by label
create or replace function public.plan_accounts(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  if not exists (select 1 from app.products where key = p_product) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('band_label', b.band_label, 'plan_key', b.plan_key, 'accounts', (
             select count(distinct ap.account_id) from app.subscriptions s
             join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
             where s.product = p_product and (s.plan = b.plan_key or s.plan = b.band_label) and ap.status = 'active'
               and app.sub_status(s) not in ('cancelled', 'expired')))
           order by b.min_employees)
    from (select distinct on (pv.band_label) pv.band_label, pv.plan_key, pv.min_employees from app.plan_versions pv
          where pv.product = p_product and pv.active order by pv.band_label, pv.version desc) b), '[]'::jsonb);
end $fn$;

-- ===========================================================================
-- 2. Roles and approvals
-- ===========================================================================
-- the sensitive actions, in the matrix's order. enforced: command (product-command asks command_authorize), database (this
-- migration's own functions), right (the cell is the role's right, changed in Settings), none (nothing can do it yet).
-- basis_right: the right a role must hold to be allowed the action at all (null: Admin sets only); the matrix can only narrow it.
create table app.staff_actions (
  key         text primary key check (key ~ '^[a-z_]+\.[a-z_]+$'),
  ord         int not null unique,
  enforced    text not null check (enforced in ('command', 'database', 'right', 'none')),
  basis_right text check (basis_right is null or app.right_ok(basis_right)),
  approvable  boolean not null default false,
  check (enforced <> 'right' or basis_right is not null),
  check (not approvable or enforced in ('command', 'database'))
);
insert into app.staff_actions (key, ord, enforced, basis_right, approvable) values
  ('accounts.view', 10, 'right', 'global:see', false),
  ('tickets.reply', 20, 'right', 'tickets:add', false),
  ('trial.extend', 30, 'command', 'global:edit_others', true),
  ('support_access.request', 40, 'right', 'global:add', false),
  ('plan.change', 50, 'none', null, false),
  ('credit_note.issue', 60, 'none', null, false),
  ('discount.over_threshold', 70, 'none', null, false),
  ('account.delete', 80, 'command', null, true),
  ('flags.change', 90, 'command', 'global:configure', false),
  ('announcements.publish', 100, 'command', 'global:configure', false),
  ('customers.export', 110, 'right', 'deals:export', false),
  ('roles.manage', 120, 'database', 'global:security', true);

-- which product command performs which action; a command not listed is a read (global:see) or another write (global:configure)
create table app.command_actions (
  product text not null,
  command text not null,
  action  text not null references app.staff_actions (key),
  primary key (product, command),
  foreign key (product, command) references app.product_commands (product, command) on delete cascade
);
insert into app.command_actions (product, command, action) values
  ('orgpuls', 'billing.extend_trial', 'trial.extend'),
  ('orgpuls', 'orgs.delete_now', 'account.delete'),
  ('orgpuls', 'modules.set_status', 'flags.change'),
  ('orgpuls', 'modules.set_validation', 'flags.change'),
  ('orgpuls', 'modules.sync', 'flags.change'),
  ('orgpuls', 'modules.pilot', 'flags.change'),
  ('orgpuls', 'locales.pilot', 'flags.change'),
  ('orgpuls', 'settings.set_notice', 'announcements.publish');

create table app.action_policies (
  permission_set_id uuid not null references app.permission_sets (id) on delete cascade,
  action            text not null references app.staff_actions (key) on delete cascade,
  mode              text not null check (mode in ('allow', 'approve', 'deny')),
  updated_by        uuid references app.admins (id) on delete set null,
  updated_at        timestamptz not null default now(),
  primary key (permission_set_id, action)
);

-- does a permission set hold a right (an Admin set holds every right; a null right: Admin sets only)
create function app.set_holds(p_set uuid, p_right text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select ps.kind = 'admin' or (p_right is not null and p_right = any (ps.rights)) from app.permission_sets ps where ps.id = p_set), false)
$fn$;

-- seeded from today's rights: allowed where the set holds the action's basis right, else denied; nothing needs approval (D-30)
insert into app.action_policies (permission_set_id, action, mode)
select ps.id, a.key, case when app.set_holds(ps.id, a.basis_right) then 'allow' else 'deny' end
from app.permission_sets ps cross join app.staff_actions a where a.enforced in ('command', 'database');

-- a permission set's mode for an action. The set's rights are the ceiling: without the action's basis right it is denied,
-- whatever a policy row says (a row written before its right was taken away in Settings, or by hand). Within them: its policy,
-- or (no row: a set made after this migration) allowed, the same rule the seed used. Settings › Second admin on (D-30) turns
-- an allowed deletion into one that needs a second admin's approval — here, so product-command's gate enforces it too.
create function app.set_mode(p_set uuid, p_action text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select case
    when a.key is null or a.enforced = 'none' or p_set is null then 'deny'
    when not app.set_holds(p_set, a.basis_right) then 'deny'
    when a.enforced = 'right' then 'allow'
    else (select case when m.mode = 'allow' and a.key = 'account.delete' and app.setting('second_admin') = 'on' then 'approve' else m.mode end
          from (select coalesce((select p.mode from app.action_policies p where p.permission_set_id = p_set and p.action = a.key), 'allow') mode) m) end
  from (select 1) one left join app.staff_actions a on a.key = p_action
$fn$;

-- a staff member's mode for an action (deny when they are not active)
create function app.action_mode(p_staff uuid, p_action text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select app.set_mode(s.permission_set_id, p_action) from app.admins s where s.id = p_staff and s.active), 'deny')
$fn$;

-- ---------------------------------------------------------------------------
-- the approval queue
create table app.approval_requests (
  id              uuid primary key default gen_random_uuid(),
  ref             int generated always as identity unique,
  action          text not null references app.staff_actions (key),
  product         text check (product is null or product ~ '^[a-z]{2,20}$'),
  command         text check (command is null or command ~ '^[a-z]+\.[a-z_]+$'),
  organization_id uuid references app.organizations (id) on delete set null,
  -- what the request is about, as ids, counts and keys (no free text)
  params          jsonb not null default '{}'::jsonb check (jsonb_typeof(params) = 'object'),
  -- the command's argument values, kept only until it has run, been refused or expired (R-PL-6)
  args            jsonb check (args is null or jsonb_typeof(args) = 'object'),
  reason          text not null check (char_length(btrim(reason)) between 3 and 300),
  state           text not null default 'pending'
                  check (state in ('pending', 'approved', 'rejected', 'executing', 'executed', 'failed', 'expired')),
  requested_by    uuid references app.admins (id) on delete set null,
  requested_at    timestamptz not null default now(),
  expires_at      timestamptz not null default now() + interval '7 days',
  decided_by      uuid references app.admins (id) on delete set null,
  decided_at      timestamptz,
  decision_note   text check (decision_note is null or char_length(decision_note) <= 300),
  taken_at        timestamptz,
  consumed_at     timestamptz,
  -- the command audit's newest id when product-command consumed the approval: the call it then made is the approver's next
  -- row for this command (the audit's own order, not the clock)
  audit_mark      bigint,
  executed_at     timestamptz,
  result_code     text check (result_code is null or result_code ~ '^[a-z0-9_]{1,40}$'),
  check (decided_by is null or requested_by is null or decided_by <> requested_by),
  check (args is null or state in ('pending', 'approved', 'executing')),
  check ((command is null) = (product is null))
);
create index approval_requests_open on app.approval_requests (state, requested_at desc);

-- nobody may change what was asked; the state only moves forward. A person or organisation removed becomes null (the
-- references' own maintenance); nothing is deleted.
create function app.approval_guard() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'approval requests are kept' using errcode = 'insufficient_privilege';
  end if;
  if new.action is distinct from old.action or new.product is distinct from old.product or new.command is distinct from old.command
     or new.params is distinct from old.params or new.reason is distinct from old.reason or new.requested_at is distinct from old.requested_at
     or new.expires_at is distinct from old.expires_at or new.ref is distinct from old.ref
     or (new.requested_by is distinct from old.requested_by and new.requested_by is not null)
     or (new.organization_id is distinct from old.organization_id and new.organization_id is not null)
     or (old.decided_by is not null and new.decided_by is distinct from old.decided_by and new.decided_by is not null)
     or (old.audit_mark is not null and new.audit_mark is distinct from old.audit_mark)
     or (old.args is null and new.args is not null) then
    raise exception 'an approval request cannot be changed' using errcode = 'insufficient_privilege';
  end if;
  if new.state is distinct from old.state and not ((old.state, new.state) in (
       ('pending', 'approved'), ('pending', 'rejected'), ('pending', 'expired'), ('pending', 'executed'), ('pending', 'failed'),
       ('approved', 'executing'), ('approved', 'failed'), ('executing', 'executed'), ('executing', 'failed'))) then
    raise exception 'an approval request only moves forward' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $fn$;
create trigger approval_guard before update or delete on app.approval_requests for each row execute function app.approval_guard();

alter table app.staff_actions enable row level security;
alter table app.command_actions enable row level security;
alter table app.action_policies enable row level security;
alter table app.approval_requests enable row level security;
revoke all on app.staff_actions, app.command_actions, app.action_policies, app.approval_requests from public, anon, authenticated;

-- what the command audit says of an approved command: «ran» (product-command's call by the approver after it consumed the
-- approval reached the product), «not_ran» (that call was refused or failed), «not_sent» (the approval was never consumed, so
-- nothing went out under it), or null (consumed, and no answer in the audit yet)
create function app.approval_outcome(r app.approval_requests) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select case when r.consumed_at is null or r.audit_mark is null then 'not_sent'
    else (select case when au.ok then 'ran' else 'not_ran' end from app.audit au
          where au.id > r.audit_mark and au.command = r.command and au.product = r.product
            and au.actor = (select x.email from app.admins x where x.id = r.decided_by)
          order by au.id limit 1) end
$fn$;

-- a command's request comes to its end: its state and code, the argument values gone, a line in the audit (saying whether the
-- approver reported it or the sweep settled it from the command audit, whoever's session the sweep ran in), the requester told
create function app.approval_close(r app.approval_requests, p_state text, p_code text, p_swept boolean) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.approval_requests set state = p_state, args = null, executed_at = now(), result_code = p_code where id = r.id;
  perform app.log(case when p_state = 'executed' then 'approval.executed' else 'approval.failed' end, 'approval', r.id::text,
                  jsonb_build_object('action', r.action, 'ref', r.ref, 'code', p_code,
                                     'settled_by', case when p_swept then 'sweep' else 'approver' end),
                  (select o.account_id from app.organizations o where o.id = r.organization_id));
  if r.requested_by is not null then
    perform app.notify(r.requested_by, 'system', 'approval.decided', jsonb_build_object('ref', 'A-' || r.ref, 'state', p_state), '/platform?tab=access');
  end if;
end $fn$;

-- requests past their time: expired after seven days; an approval not taken within ten minutes ends as failed; one taken and
-- not reported back within ten minutes (product-command answers long before) ends as the command audit says: executed when
-- the call ran, else failed. The argument values go with them. Run every five minutes by the job monitor (section 7) and
-- before each change to the queue; returns its counts.
create function app.approval_sweep() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.approval_requests; v_out text; v_expired int; v_not_taken int; v_executed int := 0; v_failed int := 0;
begin
  update app.approval_requests set state = 'expired', args = null where state = 'pending' and expires_at <= now();
  get diagnostics v_expired = row_count;
  update app.approval_requests set state = 'failed', result_code = 'not_taken', args = null, executed_at = now()
  where state = 'approved' and decided_at < now() - interval '10 minutes';
  get diagnostics v_not_taken = row_count;
  for r in select * from app.approval_requests x where x.state = 'executing' and x.taken_at < now() - interval '10 minutes' for update loop
    v_out := app.approval_outcome(r);
    if v_out = 'ran' then
      perform app.approval_close(r, 'executed', null, true);
      v_executed := v_executed + 1;
    else
      perform app.approval_close(r, 'failed', case v_out when 'not_sent' then 'timeout' when 'not_ran' then 'failed' else 'unconfirmed' end, true);
      v_failed := v_failed + 1;
    end if;
  end loop;
  return jsonb_build_object('expired', v_expired, 'not_taken', v_not_taken, 'executed', v_executed, 'failed', v_failed);
end $fn$;

-- a change to the matrix: the set, an action Sentral enforces, a mode it can enforce within the set's rights (the matrix
-- narrows a role, never widens it: a set without the action's basis right can only be denied, and a right is given in
-- Settings), and no deletion allowed alone while Settings › Second admin is on (D-30); returns the mode it has now
create function app.policy_check(p_set uuid, p_action text, p_mode text) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare a app.staff_actions;
begin
  if p_set is null or not exists (select 1 from app.permission_sets ps where ps.id = p_set) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'permission_set';
  end if;
  select * into a from app.staff_actions x where x.key = p_action;
  if not found or a.enforced not in ('command', 'database') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'action'; end if;
  if p_mode is null or p_mode not in ('allow', 'approve', 'deny') or (p_mode = 'approve' and not a.approvable) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mode';
  end if;
  if p_mode in ('allow', 'approve') and not app.set_holds(p_set, a.basis_right) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'beyond_role';
  end if;
  if p_mode = 'allow' and a.key = 'account.delete' and app.setting('second_admin') = 'on' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'second_admin';
  end if;
  return app.set_mode(p_set, p_action);
end $fn$;

-- at least one active person may still change the matrix alone, or two may (one asks, the other approves)
create function app.roles_manage_guard() returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if not exists (select 1 from app.admins x where x.active and not x.is_sample and app.action_mode(x.id, 'roles.manage') = 'allow')
     and (select count(*) from app.admins x where x.active and not x.is_sample and app.action_mode(x.id, 'roles.manage') in ('allow', 'approve')) < 2 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'last_manager';
  end if;
end $fn$;

create function app.policy_apply(p_set uuid, p_action text, p_mode text, p_by uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_from text := app.policy_check(p_set, p_action, p_mode);
begin
  insert into app.action_policies (permission_set_id, action, mode, updated_by, updated_at) values (p_set, p_action, p_mode, p_by, now())
  on conflict (permission_set_id, action) do update set mode = excluded.mode, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  if p_action = 'roles.manage' then perform app.roles_manage_guard(); end if;
  perform app.log('action_policy.changed', 'permission_set', p_set::text, jsonb_build_object('action', p_action, 'from', v_from, 'to', p_mode));
end $fn$;

-- a request: who may ask (their mode is approve), what it is about, and the command's arguments built here from Sentral's
-- records (the tenant, the typed org.nr), never taken from the caller
create function app.approval_create(p_me uuid, p_action text, p_params jsonb, p_reason text) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  a app.staff_actions; v_mode text := app.action_mode(p_me, p_action); v_org app.organizations; v_org_id uuid; v_tenant text; v_nr text;
  v_days int; v_params jsonb := '{}'::jsonb; v_args jsonb; v_product text; v_command text; v_id uuid; v_ref int; v_set uuid;
  v_target text; v_to text; v_from text; v_reason text := btrim(coalesce(p_reason, '')); v_who text;
begin
  select * into a from app.staff_actions x where x.key = p_action;
  if not found or not a.approvable then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'action'; end if;
  if v_mode = 'deny' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'action:' || p_action; end if;
  if v_mode = 'allow' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'not_needed'; end if;
  if char_length(v_reason) not between 3 and 300 then raise exception 'reason_required' using errcode = 'invalid_parameter_value'; end if;
  if jsonb_typeof(p_params) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'params'; end if;

  if p_action in ('trial.extend', 'account.delete') then
    v_product := 'orgpuls';
    v_command := case p_action when 'trial.extend' then 'billing.extend_trial' else 'orgs.delete_now' end;
    if coalesce(p_params ->> 'organization', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'organization';
    end if;
    v_org_id := (p_params ->> 'organization')::uuid;
    select * into v_org from app.organizations o where o.id = v_org_id and o.deleted_at is null;
    if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'organization'; end if;
    select ap.tenant_id into v_tenant from app.account_products ap
    where ap.account_id = v_org.account_id and ap.product = v_product and ap.status = 'active' order by ap.created_at limit 1;
    if v_tenant is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'no_orgpuls'; end if;
    if p_action = 'trial.extend' then
      v_days := case when coalesce(p_params ->> 'days', '') ~ '^\d{1,2}$' then (p_params ->> 'days')::int end;
      if v_days is null or v_days not between 1 and 60 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'days'; end if;
      if not exists (select 1 from app.subscriptions s where s.product = v_product and s.tenant_id = v_tenant and app.sub_status(s) = 'trial') then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'not_in_trial';
      end if;
      v_params := jsonb_build_object('days', v_days);
      v_args := jsonb_build_object('p_org', v_tenant, 'p_days', v_days, 'p_reason', v_reason);
    else
      -- D-30: the org.nr typed by the requester (and again by the approver)
      v_nr := coalesce(v_org.org_number, (select x.org_number from app.accounts x where x.id = v_org.account_id));
      if v_nr is null or regexp_replace(coalesce(p_params ->> 'confirm', ''), '\s', '', 'g') <> v_nr then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'confirm_mismatch';
      end if;
      v_args := jsonb_build_object('p_org', v_tenant, 'p_confirm', v_nr, 'p_reason', v_reason);
    end if;
  else
    -- roles.manage: one cell of the matrix
    if coalesce(p_params ->> 'set', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'permission_set';
    end if;
    v_set := (p_params ->> 'set')::uuid; v_target := p_params ->> 'action'; v_to := p_params ->> 'mode';
    v_from := app.policy_check(v_set, v_target, v_to);
    if v_from = v_to then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'unchanged'; end if;
    v_params := jsonb_build_object('set', v_set, 'action', v_target, 'mode', v_to, 'from', v_from);
  end if;

  insert into app.approval_requests (action, product, command, organization_id, params, args, reason, requested_by)
  values (p_action, v_product, v_command, v_org.id, v_params, v_args, v_reason, p_me)
  returning id, ref into v_id, v_ref;
  perform app.log('approval.requested', 'approval', v_id::text, jsonb_build_object('action', p_action, 'ref', v_ref), v_org.account_id);
  v_who := (select coalesce(x.name, x.email) from app.admins x where x.id = p_me);
  perform app.notify(x.id, 'system', 'approval.requested', jsonb_build_object('ref', 'A-' || v_ref, 'who', v_who), '/platform?tab=access')
  from app.admins x where x.active and not x.is_sample and x.id <> p_me and app.action_mode(x.id, p_action) in ('allow', 'approve');
  return v_id;
end $fn$;

-- one request as the queue shows it: ids, names, counts and the requester's reason; never the argument values
create function app.approval_json(r app.approval_requests, p_me uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', r.id, 'ref', r.ref, 'action', r.action, 'product', r.product,
    'state', case when r.state = 'pending' and r.expires_at <= now() then 'expired' else r.state end,
    'organization', (select jsonb_build_object('id', o.id, 'name', o.name) from app.organizations o where o.id = r.organization_id),
    'days', case when (r.params ->> 'days') ~ '^\d{1,3}$' then (r.params ->> 'days')::int end,
    'policy', case when r.action = 'roles.manage' then jsonb_build_object(
                'set', r.params ->> 'set', 'set_key', (select ps.key from app.permission_sets ps where ps.id::text = r.params ->> 'set'),
                'set_name', (select ps.name from app.permission_sets ps where ps.id::text = r.params ->> 'set'),
                'action', r.params ->> 'action', 'mode', r.params ->> 'mode', 'from', r.params ->> 'from') end,
    'reason', r.reason,
    'requested_by', (select coalesce(x.name, x.email) from app.admins x where x.id = r.requested_by),
    'requested_at', r.requested_at, 'expires_at', r.expires_at,
    'decided_by', (select coalesce(x.name, x.email) from app.admins x where x.id = r.decided_by),
    'decided_at', r.decided_at, 'decision_note', r.decision_note, 'executed_at', r.executed_at, 'result_code', r.result_code,
    'mine', r.requested_by is not distinct from p_me,
    'can_decide', r.state = 'pending' and r.expires_at > now() and r.requested_by is distinct from p_me
                  and app.action_mode(p_me, r.action) in ('allow', 'approve'),
    'confirm', r.action = 'account.delete')
$fn$;

-- ---------------------------------------------------------------------------
-- the matrix: the five roles (X-V3-4), the actions, each cell's mode and where it comes from; per role, the actions its rights
-- reach (the only cells the matrix can open); and the actions a setting holds at «needs approval» (Second admin, D-30)
create function public.access_matrix() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'see');
begin
  return jsonb_build_object(
    'roles', coalesce((select jsonb_agg(jsonb_build_object('id', ps.id, 'key', ps.key, 'name', ps.name)
                                        order by array_position(array['admin', 'sales', 'support', 'marketing', 'analyst'], ps.key))
                       from app.permission_sets ps where ps.key in ('admin', 'sales', 'support', 'marketing', 'analyst')), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(jsonb_build_object('key', a.key, 'enforced', a.enforced, 'basis_right', a.basis_right,
                                                             'approvable', a.approvable) order by a.ord)
                         from app.staff_actions a), '[]'::jsonb),
    'cells', coalesce((select jsonb_object_agg(ps.id::text, (select jsonb_object_agg(a.key, case when a.enforced = 'none' then 'none' else app.set_mode(ps.id, a.key) end)
                                                             from app.staff_actions a))
                       from app.permission_sets ps where ps.key in ('admin', 'sales', 'support', 'marketing', 'analyst')), '{}'::jsonb),
    'reach', coalesce((select jsonb_object_agg(ps.id::text, (select coalesce(jsonb_agg(a.key order by a.ord), '[]'::jsonb) from app.staff_actions a
                                                             where a.enforced in ('command', 'database') and app.set_holds(ps.id, a.basis_right)))
                       from app.permission_sets ps where ps.key in ('admin', 'sales', 'support', 'marketing', 'analyst')), '{}'::jsonb),
    'forced', case when app.setting('second_admin') = 'on' then '["account.delete"]'::jsonb else '[]'::jsonb end,
    'manage', app.action_mode(v_me, 'roles.manage'));
end $fn$;

-- change one cell: alone with «allow» for roles.manage, as a request with «approve»; a fresh second factor either way
create function public.action_policy_set(p_set uuid, p_action text, p_mode text, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_manage text := app.action_mode(v_me, 'roles.manage'); v_from text; v_id uuid;
begin
  if v_manage = 'deny' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'action:roles.manage'; end if;
  perform app.require_fresh_mfa(10);
  perform app.approval_sweep();
  v_from := app.policy_check(p_set, p_action, p_mode);
  if v_from = p_mode then return jsonb_build_object('applied', false, 'approval', null, 'mode', v_from); end if;
  if v_manage = 'approve' then
    v_id := app.approval_create(v_me, 'roles.manage', jsonb_build_object('set', p_set, 'action', p_action, 'mode', p_mode), p_reason);
    return jsonb_build_object('applied', false, 'approval', v_id, 'mode', v_from);
  end if;
  perform app.policy_apply(p_set, p_action, p_mode, v_me);
  return jsonb_build_object('applied', true, 'approval', null, 'mode', p_mode);
end $fn$;

-- ask for an action you may take only with a second person's approval
create function public.approval_request(p_action text, p_params jsonb, p_reason text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_id uuid;
begin
  perform app.approval_sweep();
  v_id := app.approval_create(v_me, p_action, p_params, p_reason);
  return app.approval_json((select r from app.approval_requests r where r.id = v_id), v_me);
end $fn$;

-- the queue: your own requests, and every request for an action you may take; open ones first, then the last 30 days
create function public.approvals_list() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(app.approval_json(r, v_me) order by (r.state = 'pending' and r.expires_at > now()) desc, r.requested_at desc)
                      from app.approval_requests r
                      where r.id in (select x.id from app.approval_requests x
                                     where (x.requested_by = v_me or app.action_mode(v_me, x.action) in ('allow', 'approve'))
                                       and (x.state = 'pending' or x.requested_at > now() - interval '30 days')
                                     order by x.requested_at desc limit 60)), '[]'::jsonb),
    'open', (select count(*) from app.approval_requests x where x.state = 'pending' and x.expires_at > now()
             and (x.requested_by = v_me or app.action_mode(v_me, x.action) in ('allow', 'approve'))),
    'requestable', coalesce((select jsonb_agg(a.key order by a.ord) from app.staff_actions a
                             where a.approvable and a.enforced = 'command' and app.action_mode(v_me, a.key) = 'approve'), '[]'::jsonb));
end $fn$;

-- approve or reject (a fresh second factor; never your own request; only someone who may take the action). A policy change
-- is made here and then; a product command is run next by the approver (approval_take, product-command, approval_done).
create function public.approval_decide(p_id uuid, p_yes boolean, p_note text default null, p_confirm text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); r app.approval_requests; a app.staff_actions; v_det text; v_code text; v_state text;
begin
  perform app.require_fresh_mfa(10);
  perform app.approval_sweep();
  select * into r from app.approval_requests x where x.id = p_id for update;
  if not found or not (r.requested_by is not distinct from v_me or app.action_mode(v_me, r.action) in ('allow', 'approve')) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  if r.requested_by is not distinct from v_me then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'own_request'; end if;
  if app.action_mode(v_me, r.action) not in ('allow', 'approve') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'action:' || r.action;
  end if;
  if r.state <> 'pending' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if p_yes is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'decision'; end if;
  if p_note is not null and char_length(p_note) > 300 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'note'; end if;

  if not p_yes then
    update app.approval_requests set state = 'rejected', args = null, decided_by = v_me, decided_at = now(), decision_note = nullif(btrim(p_note), '')
    where id = p_id;
    perform app.log('approval.rejected', 'approval', p_id::text, jsonb_build_object('action', r.action, 'ref', r.ref));
    if r.requested_by is not null then
      perform app.notify(r.requested_by, 'system', 'approval.decided', jsonb_build_object('ref', 'A-' || r.ref, 'state', 'rejected'), '/platform?tab=access');
    end if;
    return jsonb_build_object('id', p_id, 'state', 'rejected', 'executor', null);
  end if;

  -- D-30: a deletion is confirmed by typing the org.nr again
  if r.action = 'account.delete' and (r.args ->> 'p_confirm' is null or regexp_replace(coalesce(p_confirm, ''), '\s', '', 'g') <> r.args ->> 'p_confirm') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'confirm_mismatch';
  end if;
  select * into a from app.staff_actions x where x.key = r.action;

  if a.enforced = 'database' then
    begin
      if app.set_mode((r.params ->> 'set')::uuid, r.params ->> 'action') is distinct from r.params ->> 'from' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'changed_since';
      end if;
      perform app.policy_apply((r.params ->> 'set')::uuid, r.params ->> 'action', r.params ->> 'mode', v_me);
      v_state := 'executed';
    exception when others then
      get stacked diagnostics v_det = pg_exception_detail;
      v_code := case when coalesce(v_det, '') ~ '^[a-z0-9_]{1,40}$' then v_det else 'failed' end;
      v_state := 'failed';
    end;
    update app.approval_requests set state = v_state, args = null, decided_by = v_me, decided_at = now(), executed_at = now(),
      decision_note = nullif(btrim(p_note), ''), result_code = v_code
    where id = p_id;
    perform app.log(case when v_state = 'executed' then 'approval.executed' else 'approval.failed' end, 'approval', p_id::text,
                    jsonb_build_object('action', r.action, 'ref', r.ref, 'code', v_code));
    if r.requested_by is not null then
      perform app.notify(r.requested_by, 'system', 'approval.decided', jsonb_build_object('ref', 'A-' || r.ref, 'state', v_state), '/platform?tab=access');
    end if;
    return jsonb_build_object('id', p_id, 'state', v_state, 'executor', 'database', 'code', v_code);
  end if;

  update app.approval_requests set state = 'approved', decided_by = v_me, decided_at = now(), decision_note = nullif(btrim(p_note), '')
  where id = p_id;
  perform app.log('approval.approved', 'approval', p_id::text, jsonb_build_object('action', r.action, 'ref', r.ref));
  return jsonb_build_object('id', p_id, 'state', 'approved', 'executor', 'command');
end $fn$;

-- the approver takes an approved command to run it, once, within ten minutes of approving: its arguments come back here and
-- go to product-command, which binds the call to this approval (command_authorize)
create function public.approval_take(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); r app.approval_requests;
begin
  perform app.approval_sweep();
  select * into r from app.approval_requests x where x.id = p_id for update;
  if not found or r.decided_by is distinct from v_me then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'approved' or r.command is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  update app.approval_requests set state = 'executing', taken_at = now() where id = p_id;
  return jsonb_build_object('id', r.id, 'action', r.action, 'product', r.product, 'command', r.command, 'args', r.args,
                            'organization_id', r.organization_id, 'reason', r.reason);
end $fn$;

-- the outcome, reported by the approver. p_ok true: product-command answered that the command ran — «executed», accepted only
-- when the command audit holds that call; false: it answered that it did not (a refusal, the product's own error) — «failed»;
-- null: the app could not tell (no answer in time). Then the command audit decides: the call ran → executed; refused, or nothing
-- was sent under the approval → failed; no answer in the audit yet → it stays «executing» and approval_sweep decides from the
-- audit after ten minutes. The argument values are cleared either way.
create function public.approval_done(p_id uuid, p_ok boolean, p_code text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); r app.approval_requests; v_out text; v_state text;
        v_code text := case when coalesce(p_code, '') ~ '^[a-z0-9_]{1,40}$' then p_code else 'failed' end;
begin
  select * into r from app.approval_requests x where x.id = p_id for update;
  if not found or r.decided_by is distinct from v_me then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'executing' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  v_out := app.approval_outcome(r);
  if p_ok and v_out is distinct from 'ran' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'not_sent'; end if;
  v_state := case when p_ok then 'executed' when not p_ok then 'failed'
                  when v_out = 'ran' then 'executed' when v_out is null then 'executing' else 'failed' end;
  if v_state = 'executing' then
    update app.approval_requests set args = null where id = p_id;
    return jsonb_build_object('id', p_id, 'state', v_state, 'code', v_code);
  end if;
  perform app.approval_close(r, v_state, case when v_state = 'executed' then null else v_code end, false);
  return jsonb_build_object('id', p_id, 'state', v_state, 'code', case when v_state = 'executed' then null else v_code end);
end $fn$;

-- product-command asks this with the caller's own token before it signs (R-PL-1). A command tied to an action follows the
-- caller's mode for it: allow; deny → forbidden; approve → only under an approval the caller decided and took, with exactly the
-- approved arguments, used once. The mode is app.set_mode's: denied beyond the role's rights whatever a policy row says, and
-- a deletion needs approval while Settings › Second admin is on (D-30). A command tied to no action is a read (Global › See)
-- or another write (Global › Configure).
create function public.command_authorize(p_product text, p_command text, p_approval uuid default null, p_args jsonb default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.me(); v_scope text; v_action text; v_mode text; r app.approval_requests;
begin
  if v_me is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  select c.scope into v_scope from app.product_commands c where c.product = p_product and c.command = p_command;
  if v_scope is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'command'; end if;
  select ca.action into v_action from app.command_actions ca where ca.product = p_product and ca.command = p_command;
  if v_action is null then
    perform app.require('global', case when v_scope like '%:read' then 'see' else 'configure' end);
    return jsonb_build_object('ok', true, 'action', null, 'mode', 'allow');
  end if;
  v_mode := app.action_mode(v_me, v_action);
  if v_mode = 'deny' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'action:' || v_action; end if;
  if p_approval is not null then
    select * into r from app.approval_requests x where x.id = p_approval for update;
    if not found or r.action <> v_action or r.product is distinct from p_product or r.command is distinct from p_command
       or r.state <> 'executing' or r.decided_by is distinct from v_me or r.consumed_at is not null
       or r.taken_at < now() - interval '5 minutes' or r.args is distinct from p_args then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'approval';
    end if;
    update app.approval_requests set consumed_at = now(), audit_mark = (select coalesce(max(au.id), 0) from app.audit au) where id = p_approval;
    return jsonb_build_object('ok', true, 'action', v_action, 'mode', 'approved');
  end if;
  if v_mode = 'approve' then raise exception 'approval_required' using errcode = 'insufficient_privilege', detail = v_action; end if;
  return jsonb_build_object('ok', true, 'action', v_action, 'mode', 'allow');
end $fn$;

-- the product's accounts that have an organisation in Sentral (pickers)
create function public.plus_accounts(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  perform app.plus_product_ok(p_product);
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.organization_id, 'name', x.name) order by lower(x.name))
                   from (select distinct on (a.organization_id) a.* from app.plus_accounts_of(p_product) a where a.organization_id is not null) x), '[]'::jsonb);
end $fn$;

-- ===========================================================================
-- 3. Customer success
-- ===========================================================================
-- what Customer success and the error list created for an account, so the same thing is not created twice while it is open
create table app.plus_followups (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null check (kind in ('expansion_deal', 'risk_task', 'error_ticket')),
  product         text not null check (product ~ '^[a-z]{2,20}$'),
  organization_id uuid not null references app.organizations (id) on delete cascade,
  deal_id         uuid references app.deals (id) on delete cascade,
  activity_id     uuid references app.activities (id) on delete cascade,
  ticket_id       uuid references app.tickets (id) on delete cascade,
  created_by      uuid references app.admins (id) on delete set null,
  created_at      timestamptz not null default now(),
  check ((kind = 'expansion_deal') = (deal_id is not null)),
  check ((kind = 'risk_task') = (activity_id is not null)),
  check ((kind = 'error_ticket') = (ticket_id is not null))
);
create index plus_followups_org on app.plus_followups (organization_id, product, kind);
alter table app.plus_followups enable row level security;
revoke all on app.plus_followups from public, anon, authenticated;

-- the open record a follow-up of this kind created for the account: a deal still open, a task not done, a ticket not resolved
create function app.followup_open(p_kind text, p_org uuid, p_product text) returns uuid
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(f.deal_id, f.activity_id, f.ticket_id) from app.plus_followups f
  left join app.deals d on d.id = f.deal_id
  left join app.activities ac on ac.id = f.activity_id
  left join app.tickets t on t.id = f.ticket_id
  where f.kind = p_kind and f.organization_id = p_org and f.product = p_product
    and ((f.kind = 'expansion_deal' and d.status = 'open' and d.deleted_at is null and d.archived_at is null)
      or (f.kind = 'risk_task' and not ac.done and ac.deleted_at is null)
      or (f.kind = 'error_ticket' and t.status not in ('resolved', 'closed') and t.deleted_at is null))
  order by f.created_at desc limit 1
$fn$;

-- onboarding completion by step for the accounts created in the last N days. A step whose source Orgpuls has never sent for
-- this product is null («—»), not 0 %: results viewed and the first tiltak come only as milestones (D-21), which Orgpuls has not
-- added yet.
create function public.onboarding_completion(p_product text, p_days int default 180) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  d int := case when p_days in (30, 90, 180, 365) then p_days else 180 end;
  v_usage boolean; v_members boolean;
begin
  perform app.require('global', 'see');
  perform app.plus_product_ok(p_product);
  v_usage := exists (select 1 from app.usage_daily u where u.product = p_product);
  v_members := exists (select 1 from app.members m where m.product = p_product);
  return (
    with c as (
      select ap.tenant_id from app.account_products ap
      where ap.product = p_product and ap.status = 'active' and ap.created_at > now() - make_interval(days => d)
    ), u as (
      select c.tenant_id,
             coalesce(max(app.usage_int(x.data, 'employees')), 0) emp,
             coalesce(max(coalesce(app.usage_int(x.data, 'rounds_planned'), 0) + coalesce(app.usage_int(x.data, 'rounds_open'), 0)
                          + coalesce(app.usage_int(x.data, 'rounds_closed'), 0)), 0) planned,
             coalesce(max(coalesce(app.usage_int(x.data, 'rounds_open'), 0) + coalesce(app.usage_int(x.data, 'rounds_closed'), 0)), 0) sent,
             (select count(*) from app.members m where m.product = p_product and m.tenant_id = c.tenant_id) members
      from c left join app.usage_daily x on x.product = p_product and x.tenant_id = c.tenant_id
      group by c.tenant_id
    ), ms as (
      select m.tenant_id, m.key from app.activation_milestones m join c on c.tenant_id = m.tenant_id where m.product = p_product
    ), src as (
      select k, exists (select 1 from app.activation_milestones m where m.product = p_product and m.key = k) has
      from unnest(array['employees_uploaded', 'survey_scheduled', 'survey_sent', 'results_viewed', 'first_tiltak']) k
    )
    select jsonb_build_object('days', d, 'cohort', (select count(*) from c), 'steps', jsonb_build_array(
      jsonb_build_object('key', 'account_created', 'done', (select count(*) from c)),
      jsonb_build_object('key', 'employees_uploaded', 'done', case when v_usage or (select has from src where k = 'employees_uploaded') then
        (select count(*) from u where u.emp > 0 or exists (select 1 from ms where ms.tenant_id = u.tenant_id and ms.key = 'employees_uploaded')) end),
      jsonb_build_object('key', 'team_invited', 'done', case when v_members then (select count(*) from u where u.members >= 2) end),
      jsonb_build_object('key', 'survey_scheduled', 'done', case when v_usage or (select has from src where k = 'survey_scheduled') then
        (select count(*) from u where u.planned > 0 or exists (select 1 from ms where ms.tenant_id = u.tenant_id and ms.key = 'survey_scheduled')) end),
      jsonb_build_object('key', 'survey_sent', 'done', case when v_usage or (select has from src where k = 'survey_sent') then
        (select count(*) from u where u.sent > 0 or exists (select 1 from ms where ms.tenant_id = u.tenant_id and ms.key = 'survey_sent')) end),
      jsonb_build_object('key', 'results_viewed', 'done', case when (select has from src where k = 'results_viewed') then
        (select count(distinct ms.tenant_id) from ms where ms.key = 'results_viewed') end),
      jsonb_build_object('key', 'first_tiltak', 'done', case when (select has from src where k = 'first_tiltak') then
        (select count(distinct ms.tenant_id) from ms where ms.key = 'first_tiltak') end))));
end $fn$;

-- the MRR (NOK, paid subscriptions of the request's product) of the distinct accounts behind a request's votes, tickets and
-- deals; null when none of their subscriptions carries a price (Orgpuls does not send one yet, D-22)
create function app.request_mrr(p_request uuid, p_product text) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  with orgs as (
    select v.organization_id id from app.feature_request_votes v where v.request_id = p_request
    -- only tickets and deals the reader may see (their queue, their visibility; 0079's helpers)
    union select t.organization_id from app.feature_request_links l join app.tickets t on t.id = l.ref
          where l.request_id = p_request and l.kind = 'ticket' and t.organization_id is not null and app.dev_ticket_ok(t)
    union select d.organization_id from app.feature_request_links l join app.deals d on d.id = l.ref
          where l.request_id = p_request and l.kind = 'deal' and d.organization_id is not null and app.dev_deal_ok(d)
  ), subs as (
    select distinct on (s.product, s.tenant_id) s.price, s.currency, app.sub_mrr(s) mrr from orgs
    join app.organizations o on o.id = orgs.id
    join app.account_products ap on ap.account_id = o.account_id and ap.product = p_product and ap.status = 'active'
    join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
    order by s.product, s.tenant_id
  )
  select jsonb_build_object(
    'accounts', (select count(*) from orgs),
    'mrr', case when exists (select 1 from subs where subs.price is not null and subs.currency = 'NOK')
                then (select coalesce(sum(subs.mrr), 0) from subs where subs.price is not null and subs.currency = 'NOK') end,
    'unpriced', (select count(*) from subs where subs.price is null))
$fn$;

-- feature requests (0078) as Customer success shows them: votes, linked tickets and deals, and the MRR asking — only for
-- people who may see deals (R-PL-10)
create function public.success_requests(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_money boolean := app.can('deals', 'see');
begin
  perform app.require('global', 'see');
  perform app.plus_product_ok(p_product);
  return jsonb_build_object('money', v_money, 'rows', coalesce((select jsonb_agg(app.feature_request_json(r.id) || jsonb_build_object(
      'ticket_count', (select count(*) from app.feature_request_links l join app.tickets t on t.id = l.ref
                       where l.request_id = r.id and l.kind = 'ticket' and app.dev_ticket_ok(t)),
      'deal_count', (select count(*) from app.feature_request_links l join app.deals d on d.id = l.ref
                     where l.request_id = r.id and l.kind = 'deal' and app.dev_deal_ok(d)),
      'asking', case when v_money then app.request_mrr(r.id, p_product) end)
    order by r.status in ('shipped', 'declined'), (select count(*) from app.feature_request_votes v where v.request_id = r.id) desc, r.updated_at desc)
    from app.feature_requests r where r.product = p_product), '[]'::jsonb));
end $fn$;

-- renewal and expansion signals now: an account within five employees of its plan's limit (expansion); a health score down
-- 20 points or more against 30 days earlier, or no sign-in for 30 days (at risk). The renewal date is not sent by Orgpuls.
create function public.renewal_signals(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  perform app.plus_product_ok(p_product);
  return coalesce((select jsonb_agg(z.j order by z.kind_ord, lower(z.name)) from (
    with acc as (
      select distinct on (x.organization_id) x.tenant_id, x.organization_id, x.name, s.plan, x.created_at
      from app.plus_accounts_of(p_product) x
      join app.subscriptions s on s.product = p_product and s.tenant_id = x.tenant_id
      where x.organization_id is not null and app.sub_status(s) in ('trial', 'active', 'past_due', 'free')
      order by x.organization_id, x.created_at
    ), u as (
      select acc.*, app.usage_latest(p_product, acc.tenant_id) ud from acc
    ), b as (
      select u.*, app.usage_int(u.ud, 'employees') emp, pb.band_label, pb.max_employees,
             (select n.band_label from app.plan_versions n where n.product = p_product and n.active and pb.max_employees is not null
                and n.min_employees > pb.max_employees order by n.min_employees, n.version desc limit 1) next_label,
             (select h.score from app.health_scores h where h.product = p_product and h.tenant_id = u.tenant_id order by h.day desc limit 1) h_now,
             (select h.score from app.health_scores h where h.product = p_product and h.tenant_id = u.tenant_id
                and h.day <= (select max(h2.day) from app.health_scores h2 where h2.product = p_product and h2.tenant_id = u.tenant_id) - 30
              order by h.day desc limit 1) h_then,
             coalesce(app.usage_time(u.ud, 'last_sign_in_at'),
                      (select max(m.last_login_at) from app.members m where m.product = p_product and m.tenant_id = u.tenant_id)) last_in
      from u left join lateral app.plan_band(p_product, u.plan) pb on true
    )
    select 0 kind_ord, b.name, jsonb_build_object('organization', jsonb_build_object('id', b.organization_id, 'name', b.name), 'kind', 'expansion',
             'employees', b.emp, 'max', b.max_employees, 'band', b.band_label, 'next', b.next_label,
             'open', app.followup_open('expansion_deal', b.organization_id, p_product)) j
    from b where b.emp is not null and b.max_employees is not null and b.emp >= b.max_employees - 5
    union all
    select 1, b.name, jsonb_build_object('organization', jsonb_build_object('id', b.organization_id, 'name', b.name), 'kind', 'at_risk',
             'health_from', case when b.h_then - b.h_now >= 20 then b.h_then end, 'health_to', case when b.h_then - b.h_now >= 20 then b.h_now end,
             'days_since_sign_in', case when b.last_in < now() - interval '30 days' then (current_date - b.last_in::date) end,
             'open', app.followup_open('risk_task', b.organization_id, p_product))
    from b where coalesce(b.h_then - b.h_now >= 20, false) or coalesce(b.last_in < now() - interval '30 days', false)
  ) z), '[]'::jsonb);
end $fn$;

-- «Create deal» for an expansion signal: a deal on the account (deal_create; Deals › Add), once while it is open
create function public.success_deal_create(p_org uuid, p_product text, p_title text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); v_open uuid; r jsonb; v_id uuid;
begin
  perform app.plus_product_ok(p_product);
  if not exists (select 1 from app.organizations o where o.id = p_org and o.deleted_at is null) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'organization';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  v_open := app.followup_open('expansion_deal', p_org, p_product);
  if v_open is not null then return jsonb_build_object('id', v_open, 'existing', true); end if;
  r := public.deal_create(jsonb_build_object('title', btrim(p_title), 'organization_id', p_org, 'product', p_product, 'source', 'Customer success'));
  v_id := (r ->> 'id')::uuid;
  insert into app.plus_followups (kind, product, organization_id, deal_id, created_by) values ('expansion_deal', p_product, p_org, v_id, v_me);
  perform app.log('success.deal_created', 'organization', p_org::text, jsonb_build_object('deal', v_id, 'product', p_product));
  return jsonb_build_object('id', v_id, 'existing', false);
end $fn$;

-- «CSM task» for an at-risk signal: a task for the account's customer success manager (else its owner, else the caller), due
-- tomorrow, once while it is not done
create function public.success_task_create(p_org uuid, p_product text, p_subject text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); v_open uuid; o app.organizations; v_owner uuid; r jsonb; v_id uuid;
begin
  perform app.plus_product_ok(p_product);
  select * into o from app.organizations x where x.id = p_org and x.deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'organization'; end if;
  if char_length(btrim(coalesce(p_subject, ''))) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
  v_open := app.followup_open('risk_task', p_org, p_product);
  if v_open is not null then return jsonb_build_object('id', v_open, 'existing', true); end if;
  v_owner := coalesce((select a.id from app.admins a where a.id = o.csm_id and a.active),
                      (select a.id from app.admins a where a.id = o.owner_id and a.active), v_me);
  r := public.rec_save('activity', null, jsonb_build_object('type_id', (select t.id from app.activity_types t where t.key = 'task'),
         'subject', btrim(p_subject), 'organization_id', p_org, 'owner_id', v_owner, 'all_day', true,
         'starts_at', ((now() at time zone 'Europe/Oslo')::date + 1)::timestamp at time zone 'Europe/Oslo'));
  v_id := (r ->> 'id')::uuid;
  insert into app.plus_followups (kind, product, organization_id, activity_id, created_by) values ('risk_task', p_product, p_org, v_id, v_me);
  perform app.log('success.task_created', 'organization', p_org::text, jsonb_build_object('activity', v_id, 'product', p_product, 'owner', v_owner));
  return jsonb_build_object('id', v_id, 'existing', false, 'owner', (select coalesce(a.name, a.email) from app.admins a where a.id = v_owner));
end $fn$;

-- ===========================================================================
-- 4. Rollouts and announcements (Sentral's half)
-- ===========================================================================
-- how many of the product's active customer users an announcement would reach: members of accounts whose subscription is live,
-- narrowed by their role in the product and by trial. «≈»: the member list is Orgpuls' events, which can lag.
create function public.announcement_reach(p_product text, p_roles text[] default '{}', p_access text[] default '{}') returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_roles text[] := coalesce(p_roles, '{}'); v_access text[] := coalesce(p_access, '{}');
begin
  perform app.require('global', 'see');
  perform app.plus_product_ok(p_product);
  if not v_roles <@ array['daglig_leder', 'avdelingsleder', 'verneombud'] then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'roles'; end if;
  if not v_access <@ array['trial'] then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'access'; end if;
  return (with acc as (
      select ap.tenant_id from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
      where ap.product = p_product and ap.status = 'active' and app.sub_status(s) not in ('cancelled', 'expired')
        and (cardinality(v_access) = 0 or ('trial' = any (v_access) and app.sub_status(s) = 'trial'))
    )
    select jsonb_build_object(
      'known', exists (select 1 from app.members m where m.product = p_product),
      'accounts', (select count(distinct m.tenant_id) from app.members m join acc on acc.tenant_id = m.tenant_id
                   where m.product = p_product and m.active and (cardinality(v_roles) = 0 or m.role = any (v_roles))),
      'users', (select count(*) from app.members m join acc on acc.tenant_id = m.tenant_id
                where m.product = p_product and m.active and (cardinality(v_roles) = 0 or m.role = any (v_roles)))));
end $fn$;

-- accounts whose latest reported employee count is at 80 % or more of their plan's limit (D-PL-07: headcount is the only limit)
create function public.limits_near(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  perform app.plus_product_ok(p_product);
  return jsonb_build_object('warn_pct', 80, 'usage', exists (select 1 from app.usage_daily u where u.product = p_product),
    'rows', coalesce((select jsonb_agg(z.j order by z.pct desc, lower(z.name)) from (
      select x.name, round(100.0 * e.emp / pb.max_employees) pct,
             jsonb_build_object('organization', jsonb_build_object('id', x.organization_id, 'name', x.name), 'employees', e.emp,
                                'max', pb.max_employees, 'band', pb.band_label, 'pct', round(100.0 * e.emp / pb.max_employees),
                                'day', e.ud ->> '_day') j
      from (select distinct on (a.organization_id) a.* from app.plus_accounts_of(p_product) a where a.organization_id is not null order by a.organization_id, a.created_at) x
      join app.subscriptions s on s.product = p_product and s.tenant_id = x.tenant_id and app.sub_status(s) not in ('cancelled', 'expired')
      cross join lateral (select app.usage_latest(p_product, x.tenant_id) ud) l
      cross join lateral (select l.ud, app.usage_int(l.ud, 'employees') emp) e
      cross join lateral app.plan_band(p_product, s.plan) pb
      where pb.max_employees is not null and pb.max_employees > 0 and e.emp is not null and e.emp >= 0.8 * pb.max_employees
    ) z), '[]'::jsonb));
end $fn$;

-- per organisation, what Sentral's own mail to it failed in the window: ticket replies not delivered, campaign mail that
-- bounced or failed. Counts only (R-PL-2); the product's own error counts do not exist yet (errors.hourly).
create function app.mail_errors(p_product text, p_hours int)
  returns table (organization_id uuid, replies bigint, bounces bigint, failed bigint)
  language sql stable security definer set search_path = ''
as $fn$
  with sb as (select coalesce((select s.sandbox from app.admins s where s.id = app.me()), false) v),
  rep as (
    select t.organization_id org, count(*) n from app.ticket_messages m join app.tickets t on t.id = m.ticket_id
    where m.kind = 'reply' and m.delivery_status in ('bounced', 'failed') and m.created_at > now() - make_interval(hours => p_hours)
      and t.product = p_product and t.organization_id is not null and t.deleted_at is null and (not t.is_sample or (select v from sb))
    group by 1
  ), camp as (
    select p.organization_id org, count(*) filter (where r.state in ('bounced', 'soft_bounced')) b, count(*) filter (where r.state = 'failed') f
    from app.campaign_recipients r join app.campaigns c on c.id = r.campaign_id join app.people p on p.id = r.person_id
    where c.product = p_product and p.organization_id is not null and r.state in ('bounced', 'soft_bounced', 'failed')
      and coalesce(r.bounced_at, r.sent_at, r.created_at) > now() - make_interval(hours => p_hours)
      and (not r.is_sample or (select v from sb))
    group by 1
  )
  select coalesce(rep.org, camp.org), coalesce(rep.n, 0), coalesce(camp.b, 0), coalesce(camp.f, 0)
  from rep full join camp on camp.org = rep.org
$fn$;

create function public.customer_errors(p_product text, p_hours int default 24) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare h int := case when p_hours in (24, 72, 168) then p_hours else 24 end;
begin
  perform app.require('global', 'see');
  perform app.plus_product_ok(p_product);
  return jsonb_build_object('hours', h,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('organization', jsonb_build_object('id', o.id, 'name', o.name),
                       'replies', e.replies, 'bounces', e.bounces, 'failed', e.failed, 'total', e.replies + e.bounces + e.failed,
                       'ticket', (select jsonb_build_object('id', t.id, 'ref', 'T-' || t.number) from app.tickets t
                                  where t.id = app.followup_open('error_ticket', o.id, p_product)))
                     order by e.replies + e.bounces + e.failed desc, lower(o.name))
                     from app.mail_errors(p_product, h) e join app.organizations o on o.id = e.organization_id and o.deleted_at is null), '[]'::jsonb),
    'clean', (select count(distinct a.organization_id) from app.plus_accounts_of(p_product) a
              where a.organization_id is not null and a.organization_id not in (select e.organization_id from app.mail_errors(p_product, h) e)));
end $fn$;

-- «Create ticket» on an organisation's failed mail: a bug ticket carrying the counts (never an address or a message), once
-- while it is open; refused when Sentral knows no failure for it in the last 24 hours
create function public.error_ticket_create(p_org uuid, p_product text, p_subject text, p_body text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'add'); v_open uuid; r jsonb; v_id uuid;
begin
  perform app.plus_product_ok(p_product);
  if not exists (select 1 from app.organizations o where o.id = p_org and o.deleted_at is null) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'organization';
  end if;
  if char_length(btrim(coalesce(p_subject, ''))) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
  if char_length(coalesce(p_body, '')) > 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  v_open := app.followup_open('error_ticket', p_org, p_product);
  if v_open is not null then
    return jsonb_build_object('id', v_open, 'ref', (select 'T-' || t.number from app.tickets t where t.id = v_open), 'existing', true);
  end if;
  if not exists (select 1 from app.mail_errors(p_product, 24) e where e.organization_id = p_org) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'no_errors';
  end if;
  r := public.ticket_create(jsonb_build_object('category_key', 'bug', 'subject', btrim(p_subject), 'description', nullif(btrim(coalesce(p_body, '')), ''),
                                               'organization_id', p_org, 'product', p_product));
  v_id := (r ->> 'id')::uuid;
  insert into app.plus_followups (kind, product, organization_id, ticket_id, created_by) values ('error_ticket', p_product, p_org, v_id, v_me);
  perform app.log('customer.error_ticket', 'organization', p_org::text, jsonb_build_object('ticket', v_id, 'product', p_product));
  return jsonb_build_object('id', v_id, 'ref', r ->> 'ref', 'existing', false);
end $fn$;

-- ===========================================================================
-- 5. Billing portal
-- ===========================================================================
-- each account's current plan as the catalogue names it, and its billing tickets (counts, with Tickets › See)
create function public.billing_portal(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_tickets boolean := app.can('tickets', 'see') and app.queue_ok('billing');
        v_sb boolean := coalesce((select s.sandbox from app.admins s where s.id = app.me()), false);
begin
  perform app.require('global', 'see');
  perform app.plus_product_ok(p_product);
  return jsonb_build_object(
    'plans', coalesce((select jsonb_agg(jsonb_build_object('band', b.band_label, 'key', b.plan_key, 'min', b.min_employees, 'max', b.max_employees,
                                                           'monthly', b.monthly_price, 'annual', b.annual_price) order by b.min_employees)
                       from (select distinct on (pv.band_label) pv.* from app.plan_versions pv where pv.product = p_product and pv.active
                             order by pv.band_label, pv.version desc) b), '[]'::jsonb),
    'tickets', v_tickets,
    'tickets_30d', case when v_tickets then (select count(*) from app.tickets t where t.category_key = 'billing' and t.product = p_product
                                             and t.deleted_at is null and (not t.is_sample or v_sb) and t.created_at > now() - interval '30 days') end,
    'tickets_prev_30d', case when v_tickets then (select count(*) from app.tickets t where t.category_key = 'billing' and t.product = p_product
                                                  and t.deleted_at is null and (not t.is_sample or v_sb)
                                                  and t.created_at <= now() - interval '30 days' and t.created_at > now() - interval '60 days') end,
    'accounts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', x.organization_id, 'name', x.name, 'plan', s.plan, 'band', pb.band_label, 'key', pb.plan_key, 'max', pb.max_employees,
        'monthly', pb.monthly_price, 'interval', s.billing_interval, 'status', case when s.product is not null then app.sub_status(s) end,
        'trial_ends_at', s.trial_ends_at, 'cancel_effective_at', s.cancel_effective_at,
        'open_tickets', case when v_tickets then (select count(*) from app.tickets t where t.category_key = 'billing' and t.organization_id = x.organization_id
                                                   and t.deleted_at is null and t.status not in ('resolved', 'closed')) end,
        'tickets_30d', case when v_tickets then (select count(*) from app.tickets t where t.category_key = 'billing' and t.organization_id = x.organization_id
                                                  and t.deleted_at is null and t.created_at > now() - interval '30 days') end)
      order by lower(x.name))
      from (select distinct on (a.organization_id) a.* from app.plus_accounts_of(p_product) a where a.organization_id is not null order by a.organization_id, a.created_at) x
      left join app.subscriptions s on s.product = p_product and s.tenant_id = x.tenant_id
      left join lateral app.plan_band(p_product, s.plan) pb on true), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- 6. rights on the functions
-- ===========================================================================
do $$
declare f text;
begin
  foreach f in array array[
    'app.usage_int(jsonb, text)', 'app.usage_time(jsonb, text)', 'app.usage_latest(text, text)', 'app.plus_accounts_of(text)',
    'app.plus_product_ok(text)', 'app.plan_band(text, text)', 'app.set_holds(uuid, text)', 'app.set_mode(uuid, text)',
    'app.action_mode(uuid, text)', 'app.approval_guard()', 'app.approval_outcome(app.approval_requests)',
    'app.approval_close(app.approval_requests, text, text, boolean)', 'app.approval_sweep()', 'app.policy_check(uuid, text, text)',
    'app.roles_manage_guard()', 'app.policy_apply(uuid, text, text, uuid)', 'app.approval_create(uuid, text, jsonb, text)',
    'app.approval_json(app.approval_requests, uuid)', 'app.followup_open(text, uuid, text)', 'app.request_mrr(uuid, text)',
    'app.mail_errors(text, int)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'public.plan_accounts(text)', 'public.access_matrix()', 'public.action_policy_set(uuid, text, text, text)',
    'public.approval_request(text, jsonb, text)', 'public.approvals_list()', 'public.approval_decide(uuid, boolean, text, text)',
    'public.approval_take(uuid)', 'public.approval_done(uuid, boolean, text)', 'public.command_authorize(text, text, uuid, jsonb)',
    'public.plus_accounts(text)', 'public.onboarding_completion(text, int)', 'public.success_requests(text)', 'public.renewal_signals(text)',
    'public.success_deal_create(uuid, text, text)', 'public.success_task_create(uuid, text, text)',
    'public.announcement_reach(text, text[], text[])', 'public.limits_near(text)', 'public.customer_errors(text, int)',
    'public.error_ticket_create(uuid, text, text, text)', 'public.billing_portal(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ===========================================================================
-- 7. the schedule
-- ===========================================================================
-- the approval sweep runs every five minutes through the job monitor (0044), so a request past its time lets go of its argument
-- values, and a command nobody reported back is settled from the audit, without anyone opening the queue (R-PL-6)
insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
values ('approval_sweep', 'jobs.approval_sweep', '*/5 * * * *', 'cron', 'app.approval_sweep', true)
on conflict (key) do nothing;
select cron.schedule('platform-approval-sweep', '*/5 * * * *', 'select app.run_job(''approval_sweep'')');
