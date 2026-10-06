-- 0005_settings_modules.sql — the settings register and the module switches.
--
-- Every feature rule is a setting (D-15, D-16). Each one defaults to the unrestricted choice; a few are
-- fixed and cannot be switched off (the anonymity firewall, the second factor). The register holds keys
-- only: the labels are message keys in the app. A change is audited with the option keys before and after.
-- Modules are the platform's own switches (D-17): all on by default; switching one off hides it for
-- every user and refuses its functions.

create table app.settings_registry (
  key        text primary key check (key ~ '^[a-z_]{2,40}$'),
  grp        text not null check (grp ~ '^[a-z_]{2,40}$'),
  options    text[] not null check (cardinality(options) >= 1),
  default_value text not null,
  scope      text not null default 'platform' check (scope in ('platform', 'entity', 'pipeline')),
  applies_to text not null default '',
  fixed      boolean not null default false,
  numeric_option text,             -- the option that takes a number (count limits: «A number»)
  ord        int not null default 0,
  check (default_value = any (options)),
  check (numeric_option is null or numeric_option = any (options))
);

create table app.setting_values (
  key          text not null references app.settings_registry (key) on delete cascade,
  scope_id     text not null default '' check (char_length(scope_id) <= 80),
  value        text not null,
  value_number numeric check (value_number is null or value_number >= 0),
  updated_by   uuid,
  updated_at   timestamptz not null default now(),
  primary key (key, scope_id)
);

insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord) values
  ('contact_rule', 'contacts_consent', array['no_rule', 'source_and_basis', 'opt_in_only'], 'no_rule', 'platform', 'CRM-01, CRM-04, LGN-04, PRO-05, PRO-07, WEB-04, AIA-07, MTG-05, MOB-01', false, null, 10),
  ('import_consent', 'contacts_consent', array['off', 'required_per_row'], 'off', 'platform', 'CRM-09', false, null, 20),
  ('sales_consent', 'contacts_consent', array['off', 'warn', 'block'], 'off', 'platform', 'COM-07, AUT-07, AUT-12', false, null, 30),
  ('tracking', 'tracking', array['on', 'off', 'per_email'], 'on', 'platform', 'COM-06', false, null, 40),
  ('form_tracking', 'tracking', array['on', 'off'], 'on', 'platform', 'LGN-03', false, null, 50),
  ('web_ident', 'tracking', array['on', 'off'], 'on', 'platform', 'WEB-01 – WEB-04', false, null, 60),
  ('widget_consent', 'tracking', array['off', 'on'], 'off', 'platform', 'LGN-05', false, null, 70),
  ('second_admin', 'approvals_audit', array['off', 'on'], 'off', 'platform', 'PIP-10, CRM-11, CRM-12', false, null, 80),
  ('typed_reason', 'approvals_audit', array['off', 'on'], 'off', 'platform', '*', false, null, 90),
  ('count_limits', 'limits', array['unlimited', 'number'], 'unlimited', 'platform', 'AUT-05, AUT-07, COM-07, INT-04, DOC-05, CUS-01, PRO-03', false, 'number', 100),
  ('plan_gates', 'limits', array['all_on', 'per_plan'], 'all_on', 'platform', 'ENT-01, ENT-02', false, null, 110),
  ('api_rate', 'limits', array['off', 'source_values', 'custom'], 'off', 'platform', 'INT-03', false, 'custom', 120),
  ('safeguards', 'safeguards', array['source_values', 'custom', 'off'], 'source_values', 'platform', 'AUT-09, INT-04', false, 'custom', 130),
  ('rec_notice', 'meetings', array['on_24h', 'custom', 'off'], 'on_24h', 'platform', 'MTG-02, MTG-08', false, 'custom', 140),
  ('firewall', 'platform_constant', array['fixed'], 'fixed', 'platform', '*', true, null, 150),
  ('mfa', 'platform_constant', array['fixed'], 'fixed', 'platform', 'SEC-06', true, null, 160),
  -- security (Security and privacy screen, D-29)
  ('session_idle', 'security', array['on_30', 'off'], 'on_30', 'platform', 'SEC-06', false, null, 200),
  ('ip_allowlist', 'security', array['off', 'on'], 'off', 'platform', 'SEC-06', false, null, 210),
  ('login_alerts', 'security', array['off', 'on'], 'off', 'platform', 'SEC-06', false, null, 220),
  -- default visibility per record type (Settings › Visibility groups); unrestricted by default (D-16)
  ('visibility_default', 'visibility', array['owner', 'group', 'group_sub', 'all'], 'all', 'entity', 'CRM-03', false, null, 300);

-- the effective value of a setting
create function app.setting(p_key text, p_scope_id text default '') returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select v.value from app.setting_values v where v.key = p_key and v.scope_id = coalesce(p_scope_id, '')),
                  (select r.default_value from app.settings_registry r where r.key = p_key))
$fn$;

-- the register as the Settings screen shows it
create function public.settings_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'key', r.key, 'group', r.grp, 'options', to_jsonb(r.options), 'default', r.default_value, 'scope', r.scope,
      'applies_to', r.applies_to, 'fixed', r.fixed, 'numeric_option', r.numeric_option,
      'values', coalesce((select jsonb_agg(jsonb_build_object('scope_id', v.scope_id, 'value', v.value, 'number', v.value_number,
                                                              'updated_at', v.updated_at) order by v.scope_id)
                          from app.setting_values v where v.key = r.key), '[]'::jsonb)) order by r.ord)
    from app.settings_registry r), '[]'::jsonb);
end $fn$;

create function public.setting_set(p_key text, p_value text, p_scope_id text default '', p_number numeric default null)
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'configure');
  r app.settings_registry;
  v_old text;
begin
  select * into r from app.settings_registry where key = p_key;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.fixed then raise exception 'fixed_setting' using errcode = 'insufficient_privilege'; end if;
  if not (p_value = any (r.options)) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'value'; end if;
  if r.scope = 'platform' and coalesce(p_scope_id, '') <> '' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scope_id';
  end if;
  if r.scope <> 'platform' and coalesce(p_scope_id, '') !~ '^[a-z0-9_-]{1,80}$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scope_id';
  end if;
  if p_number is not null and p_value is distinct from r.numeric_option then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'number';
  end if;
  v_old := app.setting(p_key, p_scope_id);
  insert into app.setting_values (key, scope_id, value, value_number, updated_by, updated_at)
  values (p_key, coalesce(p_scope_id, ''), p_value, p_number, v_me, now())
  on conflict (key, scope_id) do update set value = excluded.value, value_number = excluded.value_number,
    updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  perform app.log('setting.changed', 'setting', p_key,
                  jsonb_build_object('key', p_key, 'scope_id', coalesce(p_scope_id, ''), 'from', v_old, 'to', p_value));
  return jsonb_build_object('key', p_key, 'value', p_value);
end $fn$;

-- the log of setting changes (from the audit), newest first
create function public.settings_log(p_limit int default 50) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'actor', l.actor_name, 'key', l.detail ->> 'key',
                                                       'scope_id', l.detail ->> 'scope_id', 'from', l.detail ->> 'from', 'to', l.detail ->> 'to')
                                    order by l.id desc)
                   from (select a.id, a.at, a.detail, coalesce(s.name, a.actor) actor_name
                         from app.audit a left join app.admins s on s.id = a.staff_id
                         where a.action in ('setting.changed', 'module.changed')
                         order by a.id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) l), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
-- modules
create table app.modules (
  key        text primary key check (key ~ '^[a-z_]{2,40}$'),
  enabled    boolean not null default true,
  ord        int not null default 0,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
insert into app.modules (key, ord) values
  ('deals', 10), ('leads', 20), ('projects', 30), ('campaigns', 40), ('documents', 50), ('meetings', 60),
  ('leadgen', 70), ('visitors', 80), ('mobile', 90);

create function app.module_on(p_key text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select m.enabled from app.modules m where m.key = p_key), true)
$fn$;

create function app.require_module(p_key text) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if not app.module_on(p_key) then
    raise exception 'module_off' using errcode = 'insufficient_privilege', detail = p_key;
  end if;
end $fn$;

create function public.modules_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('key', m.key, 'enabled', m.enabled) order by m.ord) from app.modules m), '[]'::jsonb);
end $fn$;

create function public.module_set(p_key text, p_enabled boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure');
begin
  update app.modules set enabled = p_enabled, updated_by = v_me, updated_at = now() where key = p_key;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('module.changed', 'module', p_key,
                  jsonb_build_object('key', p_key, 'from', case when p_enabled then 'off' else 'on' end, 'to', case when p_enabled then 'on' else 'off' end));
  return jsonb_build_object('key', p_key, 'enabled', p_enabled);
end $fn$;

do $$
declare t text;
begin
  foreach t in array array['settings_registry', 'setting_values', 'modules'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
revoke all on function app.setting(text, text) from public, anon, authenticated;
revoke all on function app.module_on(text) from public, anon, authenticated;
revoke all on function app.require_module(text) from public, anon, authenticated;
revoke all on function public.settings_get() from public, anon;
revoke all on function public.setting_set(text, text, text, numeric) from public, anon;
revoke all on function public.settings_log(int) from public, anon;
revoke all on function public.modules_get() from public, anon;
revoke all on function public.module_set(text, boolean) from public, anon;
grant execute on function public.settings_get(), public.setting_set(text, text, text, numeric), public.settings_log(int),
  public.modules_get(), public.module_set(text, boolean) to authenticated;
