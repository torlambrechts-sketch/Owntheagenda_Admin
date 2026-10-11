-- 0071_session_remember.sql — «Remember this device for 30 days» at the second factor.
--
-- With session_idle on (on_30), a session idle for 30 minutes is ended, and the next page asks for the password and the
-- code again. The owner asked for the code to be remembered on a device for 30 days. A code cannot be remembered: every
-- admin call still needs a session that proved its second factor (aal2, app.me()), and only entering the code gives
-- one. What is remembered is that session: when the person ticks «Remember this device» as they enter the code, their
-- session on that device is exempt from the idle rule for 30 days (staff_sessions.trusted_until), so it stays signed in
-- there and is not asked again. Everything else still ends it: signing out, a forced end from Security, the IP rules, the
-- sign-in hours, a deactivated account, a reset factor. Security › Live sessions shows it as remembered, and the owner can
-- switch the option off (session_remember, Security › Rules), which takes effect at once for every session.

-- ===========================================================================
-- 1. the setting and the column
-- ===========================================================================
insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord)
values ('session_remember', 'security', array['days_30', 'off'], 'days_30', 'platform', 'SEC-06', false, null, 205)
on conflict (key) do nothing;

alter table app.staff_sessions add column if not exists trusted_until timestamptz;

-- is a session idle under the rule? Not while the device is remembered and the owner allows it.
create or replace function app.session_idle(p_last_seen timestamptz, p_trusted_until timestamptz) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.setting('session_idle') = 'on_30' and p_last_seen < now() - interval '30 minutes'
     and not (app.setting('session_remember') = 'days_30' and coalesce(p_trusted_until > now(), false))
$fn$;
revoke all on function app.session_idle(timestamptz, timestamptz) from public, anon, authenticated;

-- ===========================================================================
-- 2. the person's own session, after the code: remembered for 30 days
-- ===========================================================================
create or replace function public.session_remember() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.me(); v_s uuid := app.current_session(); v_until timestamptz;
begin
  if v_me is null or v_s is null then raise exception 'forbidden' using errcode = 'insufficient_privilege'; end if;
  if app.setting('session_remember') <> 'days_30' then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  update app.staff_sessions set trusted_until = now() + interval '30 days'
  where session_id = v_s and staff_id = v_me and ended_at is null
  returning trusted_until into v_until;
  return jsonb_build_object('ok', v_until is not null, 'until', v_until);
end $fn$;
revoke all on function public.session_remember() from public, anon;
grant execute on function public.session_remember() to authenticated;

-- ===========================================================================
-- 3. every place the idle rule ends or hides a session reads app.session_idle
-- ===========================================================================
create or replace function app.session_ok(p_session uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select case when p_session is null then false else coalesce(
    (select s.ended_at is null
            and not app.session_idle(s.last_seen_at, s.trusted_until)
            and app.time_allowed(now())
     from app.staff_sessions s where s.session_id = p_session),
    exists (select 1 from auth.sessions a where a.id = p_session and a.created_at > now() - interval '10 minutes')
      and app.time_allowed(now())) end
$fn$;

create or replace function public.worker_session_seen(p_session uuid, p_ip inet, p_ua text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.staff_sessions; v_reason text;
begin
  select * into s from app.staff_sessions where session_id = p_session for update;
  if not found then
    return jsonb_build_object('ok', exists (select 1 from auth.sessions a where a.id = p_session and a.created_at > now() - interval '2 minutes'),
                              'reason', 'pending');
  end if;
  if s.ended_at is not null then return jsonb_build_object('ok', false, 'reason', s.end_reason); end if;
  v_reason := case
    when not exists (select 1 from app.admins a where a.id = s.staff_id and a.active) then 'deactivated'
    when app.session_idle(s.last_seen_at, s.trusted_until) then 'idle_timeout'
    when not app.ip_allowed(p_ip) then 'ip_rule'
    when not app.time_allowed(now()) then 'time_rule' end;
  if v_reason is not null then
    perform app.session_end(p_session, v_reason, null);
    return jsonb_build_object('ok', false, 'reason', v_reason);
  end if;
  update app.staff_sessions set last_seen_at = now(), last_ip_sealed = coalesce(app.ip_seal(p_ip), last_ip_sealed),
                                device_label = coalesce(device_label, app.device_label(p_ua))
  where session_id = p_session;
  return jsonb_build_object('ok', true);
end $fn$;

create or replace function app.sessions_expire() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s record; n int := 0; v_reason text; v_ranges cidr[] := app.ip_ranges();
begin
  for s in select ss.session_id, ss.staff_id, ss.last_seen_at, ss.trusted_until, ss.last_ip_sealed, a.active
           from app.staff_sessions ss join app.admins a on a.id = ss.staff_id where ss.ended_at is null for update of ss skip locked loop
    v_reason := case
      when not s.active then 'deactivated'
      when app.session_idle(s.last_seen_at, s.trusted_until) then 'idle_timeout'
      when not app.time_allowed(now()) then 'time_rule'
      when app.setting('ip_allowlist') = 'on' and not app.ip_match(app.ip_open(s.last_ip_sealed), v_ranges) then 'ip_rule' end;
    if v_reason is not null and app.session_end(s.session_id, v_reason, null) then n := n + 1; end if;
  end loop;
  return n;
end $fn$;

create or replace function public.security_dashboard() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_issues jsonb := app.security_issues(); v_enrolled int; v_active int;
begin
  select count(*) filter (where app.staff_mfa_verified(a.email)), count(*) into v_enrolled, v_active from app.admins a where a.active and not a.is_sample;
  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'signed_in_now', (select count(*) from app.staff_sessions s where s.ended_at is null
                        and not app.session_idle(s.last_seen_at, s.trusted_until)),
      'new_devices_7d', jsonb_build_object(
        'count', (select count(*) from app.login_log l where l.outcome = 'success' and l.new_device and l.at > now() - interval '7 days'),
        'staff', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email)) order by a.name)
                           from app.admins a where a.id in (select l.staff_id from app.login_log l where l.outcome = 'success' and l.new_device
                                                            and l.at > now() - interval '7 days')), '[]'::jsonb)),
      'new_locations_7d', jsonb_build_object(
        'count', (select count(*) from app.login_log l where l.outcome = 'success' and l.new_location and l.at > now() - interval '7 days'),
        'places', coalesce((select jsonb_agg(distinct jsonb_build_object('city', l.city, 'country', l.country))
                            from app.login_log l where l.outcome = 'success' and l.new_location and l.at > now() - interval '7 days'), '[]'::jsonb)),
      'security_events_7d', jsonb_build_object(
        'count', (select count(*) from app.security_events e where e.at > now() - interval '7 days'),
        'critical', (select count(*) from app.security_events e where e.at > now() - interval '7 days' and e.severity = 'critical')),
      'forced_logouts_7d', (select count(*) from app.staff_sessions s where s.end_reason = 'forced' and s.ended_at > now() - interval '7 days'),
      'mfa', jsonb_build_object('enrolled', v_enrolled, 'active', v_active,
                                'coverage_pct', case when v_active > 0 then round(100.0 * v_enrolled / v_active)::int end)),
    'settings', jsonb_build_object('session_idle', app.setting('session_idle'), 'session_remember', app.setting('session_remember'), 'ip_allowlist', app.setting('ip_allowlist'),
                                   'signin_hours', app.setting('signin_hours'), 'ip_rules', cardinality(app.ip_ranges())),
    'live', coalesce((select jsonb_agg(jsonb_build_object('session_id', s.session_id, 'staff_id', s.staff_id, 'name', coalesce(a.name, a.email),
                                                          'city', s.city, 'country', s.country, 'device', s.device_label, 'method', s.method,
                                                          'since', s.created_at, 'last_seen_at', s.last_seen_at,
                                                          'remembered_until', case when s.trusted_until > now() then s.trusted_until end,
                                                          'current', s.session_id = app.current_session()) order by s.created_at)
                      from app.staff_sessions s join app.admins a on a.id = s.staff_id
                      where s.ended_at is null and not app.session_idle(s.last_seen_at, s.trusted_until)), '[]'::jsonb),
    'issues', v_issues,
    'issues_open', jsonb_array_length(v_issues),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'kind', e.kind, 'severity', e.severity,
                                                            'subject_id', e.subject_staff_id, 'subject', (select coalesce(a.name, a.email) from app.admins a where a.id = e.subject_staff_id),
                                                            'actor_id', e.actor_id, 'actor', (select coalesce(a.name, a.email) from app.admins a where a.id = e.actor_id),
                                                            'detail', e.detail, 'alert_state', e.alert_state) order by e.id desc)
                        from app.security_events e where e.at > now() - interval '7 days'), '[]'::jsonb));
end $fn$;

-- Security › Rules reads the switch beside the idle rule
create or replace function public.security_rules_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return jsonb_build_object(
    'ip_allowlist', app.setting('ip_allowlist'), 'signin_hours', app.setting('signin_hours'), 'session_idle', app.setting('session_idle'), 'session_remember', app.setting('session_remember'),
    'password_expiry', app.setting('password_expiry'), 'password_expiry_days', case when app.setting('password_expiry') = 'days' then app.setting_number('password_expiry', null) end,
    'password_reuse', app.setting('password_reuse'), 'password_reuse_available', false,
    'rules', coalesce((select jsonb_agg(app.security_rule_row(r) order by r.kind, r.created_at) from app.security_rules r where r.archived_at is null), '[]'::jsonb));
end $fn$;
