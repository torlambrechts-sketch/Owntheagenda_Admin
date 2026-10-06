-- 0003_staff_access.sql — the people who work in the platform, what they may do, and what they may see.
--
-- app.admins becomes the staff table (D-08, D-10): every CRM user is a row here with a profile and a
-- permission set. Signing in still needs an active row, a confirmed account and a second factor
-- (app.is_admin, D-11). On top of that:
--   * a permission set grants actions per scope (the design's matrix: Deals, Projects, Campaigns, Global);
--   * a visibility group places the person in a tree; a record's visibility is decided against the
--     owner's group (owner only, owner's group, owner's group and sub-groups, everyone).
-- Both are checked inside the security-definer functions that read and write records (D-09). No table
-- gains a policy or a client grant.

-- ---------------------------------------------------------------------------
-- permission sets: a matrix of action × scope, stored as the granted pairs ('deals:see', 'global:security')
create table app.permission_sets (
  id         uuid primary key default gen_random_uuid(),
  key        text unique check (key is null or key ~ '^[a-z_]{2,40}$'),   -- presets carry a key, custom sets none
  name       text not null unique check (char_length(btrim(name)) between 1 and 80),
  kind       text not null check (kind in ('admin', 'regular', 'custom')),
  rights     text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- the actions and scopes a right is made of; a right outside this list cannot be granted
create function app.right_ok(p_right text) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select split_part(p_right, ':', 1) in ('deals', 'projects', 'campaigns', 'global')
     and split_part(p_right, ':', 2) in ('see', 'add', 'edit_others', 'delete', 'bulk', 'export', 'configure',
                                         'workflows', 'reports_others', 'ai', 'security')
     and p_right ~ '^[a-z]+:[a-z_]+$'
$fn$;
create function app.rights_ok(p_rights text[]) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select coalesce(bool_and(app.right_ok(r)), true) from unnest(p_rights) r
$fn$;
alter table app.permission_sets add constraint rights_known check (app.rights_ok(rights));

-- visibility groups: a tree with one root («Everyone»)
create table app.visibility_groups (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique check (char_length(btrim(name)) between 1 and 80),
  parent_id  uuid references app.visibility_groups (id) on delete restrict,
  created_at timestamptz not null default now(),
  check (parent_id is distinct from id)
);
create unique index visibility_groups_one_root on app.visibility_groups ((true)) where parent_id is null;

-- teams: used by assignment, reports and goals
create table app.teams (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique check (char_length(btrim(name)) between 1 and 80),
  manager_id uuid,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- the staff profile on app.admins. `role` keeps its meaning (owner may reset another person's second
-- factor, D-11); `title` is the job label the design shows («Sales», «Support»).
alter table app.admins
  add column id                uuid not null default gen_random_uuid() unique,
  add column name              text check (name is null or char_length(btrim(name)) between 1 and 120),
  add column initials          text check (initials is null or char_length(initials) between 1 and 3),
  add column title             text check (title is null or char_length(title) between 1 and 60),
  add column phone             text check (phone is null or char_length(phone) <= 40),
  add column locale            text not null default 'en' check (locale in ('en', 'no')),
  add column time_zone         text not null default 'Europe/Oslo' check (char_length(time_zone) between 3 and 60),
  add column number_format     text not null default 'space_comma' check (number_format in ('space_comma', 'comma_dot', 'dot_comma')),
  add column permission_set_id uuid references app.permission_sets (id),
  add column group_id          uuid references app.visibility_groups (id),
  add column team_id           uuid references app.teams (id) on delete set null,
  add column sandbox           boolean not null default false,
  add column is_sample         boolean not null default false,
  add column last_seen_at      timestamptz,
  add column created_by        uuid,
  add column updated_at        timestamptz not null default now();
alter table app.teams add constraint teams_manager foreign key (manager_id) references app.admins (id) on delete set null;

create table app.team_members (
  team_id  uuid not null references app.teams (id) on delete cascade,
  staff_id uuid not null references app.admins (id) on delete cascade,
  primary key (team_id, staff_id)
);

-- recovery codes for the second factor (D-11): stored as SHA-256, each used once
create table app.recovery_codes (
  staff_id   uuid not null references app.admins (id) on delete cascade,
  hash       bytea not null,
  used_at    timestamptz,
  created_at timestamptz not null default now(),
  primary key (staff_id, hash)
);

-- ---------------------------------------------------------------------------
-- presets (D-08). Rights per scope follow the design's matrix rows:
-- see, add, edit_others, delete, bulk, export, configure, workflows, reports_others, ai, security
insert into app.visibility_groups (name) values ('Everyone');

insert into app.permission_sets (key, name, kind, rights)
select k, n, kd, array(select s || ':' || a from unnest(sc) s, unnest(ac) a)
from (values
  ('admin', 'Admin (full)', 'admin', array['deals', 'projects', 'campaigns', 'global'],
     array['see', 'add', 'edit_others', 'delete', 'bulk', 'export', 'configure', 'workflows', 'reports_others', 'ai', 'security']),
  ('sales', 'Regular — Sales', 'regular', array['deals', 'global'], array['see', 'add', 'delete', 'export', 'ai']),
  ('marketing', 'Regular — Marketing', 'regular', array['campaigns', 'deals'], array['see', 'add', 'edit_others', 'export', 'ai']),
  ('project', 'Regular — Projects', 'regular', array['projects'], array['see', 'add', 'edit_others', 'ai']),
  ('support', 'Custom — Support', 'custom', array['global', 'deals'], array['see', 'add', 'edit_others', 'ai']),
  ('finance', 'Custom — Finance', 'custom', array['global', 'deals'], array['see', 'export', 'reports_others']),
  ('analyst', 'Custom — Read-only', 'custom', array['deals', 'projects', 'campaigns', 'global'], array['see', 'reports_others'])
) as p(k, n, kd, sc, ac);

-- everybody already on the list was a full admin
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'admin'),
                      group_id = (select id from app.visibility_groups where parent_id is null),
                      title = coalesce(title, 'Super-admin');
alter table app.admins alter column permission_set_id set not null, alter column group_id set not null;

-- ---------------------------------------------------------------------------
-- who is asking. app.me() is the staff id of a signed-in admin with aal2, null for anybody else.
create function app.me() returns uuid
  language sql stable security definer set search_path = ''
as $fn$
  select a.id from app.admins a join auth.users u on lower(u.email) = a.email
  where u.id = auth.uid() and u.email_confirmed_at is not null and a.active
    and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
$fn$;

-- may the caller do this action in this scope?
create function app.can(p_scope text, p_action text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select (ps.kind = 'admin' or (p_scope || ':' || p_action) = any (ps.rights))
                   from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id
                   where a.id = app.me()), false)
$fn$;

-- the same, or an error a caller can recognise
create function app.require(p_scope text, p_action text) returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid := app.me();
begin
  if v is null then
    raise exception 'not_signed_in' using errcode = 'insufficient_privilege';
  end if;
  if not app.can(p_scope, p_action) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = p_scope || ':' || p_action;
  end if;
  return v;
end $fn$;

-- an admin of any rights, for reads that every staff member may make (their own profile, the shell)
create function app.require_staff() returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid := app.me();
begin
  if v is null then
    raise exception 'not_signed_in' using errcode = 'insufficient_privilege';
  end if;
  return v;
end $fn$;

-- the groups under a group, the group included
create function app.group_and_below(p_group uuid) returns setof uuid
  language sql stable security definer set search_path = ''
as $fn$
  with recursive t(id) as (select p_group union all select g.id from app.visibility_groups g join t on g.parent_id = t.id)
  select id from t
$fn$;

-- may the caller see a record with this owner and this visibility?
create function app.visible(p_owner uuid, p_visibility text) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.me();
  v_kind text;
  v_my_group uuid;
  v_owner_group uuid;
begin
  if v_me is null then return false; end if;
  if p_visibility = 'all' or p_owner = v_me then return true; end if;
  select ps.kind, a.group_id into v_kind, v_my_group
  from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = v_me;
  if v_kind = 'admin' then return true; end if;
  if p_owner is null then return p_visibility <> 'owner'; end if;
  select group_id into v_owner_group from app.admins where id = p_owner;
  return case p_visibility
    when 'group' then v_owner_group = v_my_group
    when 'group_sub' then v_my_group in (select app.group_and_below(v_owner_group))
    else false
  end;
end $fn$;

-- ---------------------------------------------------------------------------
-- closed: RLS on, no policy, no client grant
do $$
declare t text;
begin
  foreach t in array array['permission_sets', 'visibility_groups', 'teams', 'team_members', 'recovery_codes'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
revoke all on table app.recovery_codes from service_role;
revoke all on function app.right_ok(text) from public, anon, authenticated;
revoke all on function app.rights_ok(text[]) from public, anon, authenticated;
revoke all on function app.me() from public, anon;
revoke all on function app.can(text, text) from public, anon;
revoke all on function app.require(text, text) from public, anon;
revoke all on function app.require_staff() from public, anon;
revoke all on function app.group_and_below(uuid) from public, anon;
revoke all on function app.visible(uuid, text) from public, anon;
