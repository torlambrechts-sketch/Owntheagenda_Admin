-- phase8_security_invariants.sql — the Security screen (0043; SEC-01..11, UF-15, SF-15, SF-27, SF-43; §3.2 audit and register hook).
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

-- as_s(email, session, fresh, aal): a signed-in user with a session claim and, when fresh, a TOTP within the minute
create or replace function pg_temp.as_s(p_email text, p_session uuid default null, p_fresh boolean default true, p_aal text default 'aal2') returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'role', 'authenticated', 'aal', p_aal, 'email', p_email, 'session_id', p_session,
    'amr', case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint)) else '[]'::jsonb end)::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;

-- a sign-in as the sign-in action reports it, with an Auth session row behind it
create or replace function pg_temp.signin(p_email text, p_ip text, p_device text, p_city text default 'Oslo', p_country text default 'NO',
                                          p_method text default 'password_totp') returns jsonb language plpgsql as $$
declare v_sid uuid := gen_random_uuid(); r jsonb;
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) select v_sid, u.id, now(), now(), 'aal2' from auth.users u where lower(u.email) = p_email;
  r := public.worker_login_event(jsonb_build_object('email', p_email, 'outcome', 'success', 'session_id', v_sid, 'method', p_method, 'ip', p_ip,
                                                    'device_id', p_device, 'user_agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Chrome/129.0 Safari/537.36',
                                                    'city', p_city, 'country', p_country));
  return r || jsonb_build_object('session_id', v_sid);
end $$;

create or replace function pg_temp.sid(p_email text) returns uuid language sql as $$
  select s.session_id from app.staff_sessions s join app.admins a on a.id = s.staff_id where a.email = p_email and s.ended_at is null order by s.created_at desc limit 1
$$;

create temp table t_staff as select (select id from app.admins where email = 'tor@orgpuls.no') tor, (select id from app.admins where email = 'ingrid@orgpuls.no') ingrid,
  (select id from app.admins where email = 'ola@orgpuls.no') ola, (select id from app.admins where email = 'hanna@orgpuls.no') hanna,
  (select id from app.admins where email = 'magnus@orgpuls.no') magnus, (select id from app.admins where email = 'emma@orgpuls.no') emma;

-- ---------------------------------------------------------------------------
-- structure: closed tables, client functions for staff, workers for the service role, helpers for nobody
create temp table t_tables as select unnest(array['login_log', 'staff_sessions', 'staff_devices', 'staff_locations', 'security_rules', 'security_events',
  'security_alert_deliveries', 'security_alert_recipients', 'access_reviews', 'access_review_items', 'sso_providers', 'password_changes', 'recovery_attempts',
  'ops_checks', 'platform_facts', 'security_incidents', 'subprocessors', 'retention_rules', 'privacy_jobs', 'erasure_tombstones']) t;
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' and c.relrowsecurity
                      and c.relname in (select t from t_tables)) = 20, 'all twenty security tables exist with row level security on');
select pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'app' and tablename in (select t from t_tables)), 'no security table has a policy');
select pg_temp.check(not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'app' and g.table_name in (select t from t_tables)
                                 and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
                 and (select count(distinct g.table_name) from information_schema.role_table_grants g where g.table_schema = 'app'
                      and g.table_name in (select t from t_tables) and g.grantee = 'service_role') = 20, 'no client grant on a security table; the service role has them');
select pg_temp.check(not exists (select 1 from information_schema.columns c where c.table_schema = 'app' and c.table_name in (select t from t_tables)
                                 and c.data_type = 'inet'), 'no security table holds an IP address in clear (sealed bytea only)');
create temp table t_rpcs as select unnest(array['public.setting_set(text, text, text, numeric)', 'public.security_dashboard()', 'public.session_revoke(uuid, text)',
  'public.staff_sessions_revoke_all(uuid, text)', 'public.my_sessions()', 'public.login_history(uuid, int)', 'public.security_rules_get()',
  'public.security_rule_save(uuid, jsonb, int)', 'public.security_rule_delete(uuid)', 'public.security_rule_preview(jsonb)', 'public.alerts_get()',
  'public.alert_recipients_set(uuid[])', 'public.sso_get()', 'public.sso_set(text, boolean, text[])', 'public.mfa_overview()', 'public.recovery_codes_generate()',
  'public.recovery_code_redeem(text)', 'public.staff_mfa_reset(uuid, text)', 'public.staff_mfa_reminder(uuid)', 'public.access_review_start()',
  'public.access_review_get(uuid)', 'public.access_review_decide(uuid, uuid, text)', 'public.access_review_complete(uuid)', 'public.firewall_status()',
  'public.protection_get()', 'public.restore_test_record(timestamptz, boolean, int, int, text)', 'public.privacy_find(text)', 'public.privacy_preview(jsonb)',
  'public.privacy_export(jsonb, uuid, text)', 'public.privacy_export_url(uuid)', 'public.privacy_erase(jsonb, uuid, text, text)', 'public.privacy_approve(uuid)',
  'public.privacy_jobs_get()', 'public.retention_get()', 'public.subprocessors_get()', 'public.subprocessor_save(uuid, jsonb, int)', 'public.incidents_get()',
  'public.incident_save(uuid, jsonb, int)', 'public.audit_search(jsonb, bigint, int)']) f;
select pg_temp.check(not exists (select 1 from t_rpcs where not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')),
                     'every security function is for signed-in staff (' || (select count(*) from t_rpcs) || '), never anon');
select pg_temp.check(not exists (select 1 from t_rpcs r join pg_proc p on p.oid = r.f::regprocedure where not p.prosecdef or not ('search_path=""' = any (p.proconfig))),
                     'every security function is security definer with an empty search path');
select pg_temp.check(not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute')
                     and has_function_privilege('service_role', f, 'execute'), 'service role only: ' || f)
from unnest(array['public.worker_login_event(jsonb)', 'public.worker_session_seen(uuid, inet, text)', 'public.worker_password_reset(text)',
  'public.worker_password_changed(text)', 'public.worker_sso_configured(text, boolean)', 'public.worker_backup_seen(jsonb)',
  'public.worker_privacy_package(uuid)', 'public.worker_privacy_done(uuid, text, text)', 'public.subprocessors_public()']) f;
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'app'::regnamespace
                                 and p.proname in ('audit_kind', 'audit_source', 'audit_principal_kind', 'audit_principal_id', 'audit_stamp', 'audit_guard', 'log',
                                   'security_event_guard', 'ops_check_guard', 'setting_number', 'current_session', 'require_fresh_mfa', 'staff_has_security',
                                   'staff_mfa_verified', 'ip_key', 'ip_seal', 'ip_open', 'device_label', 'ip_ranges', 'ip_match', 'window_match', 'time_windows',
                                   'windows_match', 'ip_allowed', 'time_allowed', 'my_ip', 'session_ok', 'session_end', 'staff_session_guard', 'login_log_guard',
                                   'sessions_enforce_ip', 'ip_allowlist_guard', 'signin_hours_guard', 'password_reuse_guard', 'security_alert_key', 'security_event',
                                   'security_recipients', 'security_deliver', 'security_alerts_run', 'security_digest_due', 'sub_security_alerts',
                                   'admins_security_watch', 'person_tombstoned', 'access_review_next_due', 'security_issues', 'security_rule_row',
                                   'security_self_check', 'access_review_due', 'privacy_subject', 'privacy_counts', 'privacy_product_user', 'privacy_erase_run',
                                   'retention_mark', 'incident_row', 'incident_clock', 'audit_target', 'sessions_expire', 'security_prune', 'purge_audit',
                                   'retention_tickets', 'retention_email_bodies', 'plus_72h')
                                 and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
                     'no app helper of 0043 is callable by a client role');
select pg_temp.check(not exists (select 1 from app.settings_registry r where r.hook is not null and to_regprocedure(r.hook || '(text, text, text, text)') is null)
                     and (select hook from app.settings_registry where key = 'ip_allowlist') = 'app.ip_allowlist_guard'
                     and (select hook from app.settings_registry where key = 'signin_hours') = 'app.signin_hours_guard',
                     'every register hook resolves to a function (key, old, new, scope); ip_allowlist and signin_hours carry theirs');
select pg_temp.check((select fn = 'app.sub_security_alerts' and ord = 70 and enabled from app.event_subscribers where name = 'security_alerts')
                     and exists (select 1 from app.event_cursors where subscriber = 'security_alerts'), 'the security_alerts subscriber is registered (70) with its cursor');
select pg_temp.check(not exists (select 1 from app.retention_rules r where r.basis = 'platform' and not exists (select 1 from cron.job c where c.jobname = r.job_key and c.active))
                     and (select job_key is null and keep is null from app.retention_rules where key = 'survey_responses'),
                     'every platform retention rule names a scheduled job; the product rule has none and is never enforced here');
select pg_temp.check((select array_agg(jobname order by jobname) from cron.job where jobname like 'security-%')
                     = array['security-access-review-due', 'security-alerts', 'security-audit-purge', 'security-backup-poll', 'security-digest', 'security-incident-clock',
                             'security-login-prune', 'security-retention-email', 'security-retention-tickets', 'security-sessions-expire'], 'the security jobs are scheduled');
select pg_temp.check((select value from app.platform_facts where key = 'db_region') = 'eu-central-1'
                     and (select region from app.subprocessors where name = 'Supabase') like '%eu-central-1%'
                     and not exists (select 1 from app.subprocessors where name ~* '(stripe|anthropic|okta)')
                     and (select region is null and not public from app.subprocessors where name = 'Vercel'),
                     'residency is eu-central-1 (D-35); only providers in use are listed; an unrecorded region is not invented');
select pg_temp.check((select bool_and(not enabled and not configured) and count(*) = 2 from app.sso_providers), 'Google and Microsoft are modelled, neither configured nor on (D-31)');

-- ---------------------------------------------------------------------------
-- the audit (§3.2): kind, source, principal; append-only with a five-year purge door
select pg_temp.check(exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'audit' and column_name = 'kind' and is_generated = 'ALWAYS')
                     and (select count(*) from pg_indexes where schemaname = 'app' and indexname in ('audit_staff_at', 'audit_account_at', 'audit_kind_at')) = 3,
                     'audit.kind is generated and the three indexes exist');
select pg_temp.check(app.audit_kind('record.read', null) = 'read' and app.audit_kind('privacy.searched', null) = 'read' and app.audit_kind('record.exported', null) = 'export'
                     and app.audit_kind('export.created', null) = 'export' and app.audit_kind('staff.invited', null) = 'role' and app.audit_kind('mfa.reset', null) = 'role'
                     and app.audit_kind('session.revoked', null) = 'security' and app.audit_kind('security_rule.saved', null) = 'security'
                     and app.audit_kind('record.updated', null) = 'write' and app.audit_kind(null, 'org.extend_trial') = 'write', 'audit kinds map from the action');
select pg_temp.check((select p.proname from pg_trigger t join pg_proc p on p.oid = t.tgfoid where t.tgrelid = 'app.audit'::regclass and t.tgname = 'audit_fixed') = 'audit_guard'
                     and (select p.proname from pg_trigger t join pg_proc p on p.oid = t.tgfoid where t.tgrelid = 'app.audit'::regclass and t.tgname = 'audit_no_truncate') = 'audit_guard',
                     'the audit triggers run audit_guard');
select pg_temp.as_staff('tor@orgpuls.no');
select app.log('test.write', 'organization', null);
select pg_temp.check((select source = 'web' and principal_kind = 'staff' and principal_id is null and staff_id = (select tor from t_staff) and kind = 'write'
                      from app.audit order by id desc limit 1), 'app.log stamps a staff write from the web');
select set_config('app.source', 'api', true), set_config('app.principal_kind', 'token', true), set_config('app.principal_id', '00000000-0000-0000-0000-00000000a0a1', true);
select app.log('record.read', 'organization', null);
select pg_temp.check((select source = 'api' and principal_kind = 'token' and principal_id = '00000000-0000-0000-0000-00000000a0a1' and kind = 'read'
                      from app.audit order by id desc limit 1), 'app.log reads app.source / app.principal_kind / app.principal_id');
select set_config('app.source', 'evil', true), set_config('app.principal_kind', 'root', true), set_config('app.principal_id', 'x', true);
select app.log('test.write', null, null);
select pg_temp.check((select source = 'web' and principal_kind = 'staff' and principal_id is null from app.audit order by id desc limit 1),
                     'an unknown source or principal falls back instead of failing the write');
select set_config('app.source', '', true), set_config('app.principal_kind', '', true), set_config('app.principal_id', '', true);
select pg_temp.as_nobody();
insert into app.audit (actor, action, ok) values ('system', 'job.test', true);
select pg_temp.check((select source = 'system' and principal_kind = 'system' from app.audit order by id desc limit 1), 'a direct system insert is stamped system');
insert into app.audit (at, actor, action, ok) values (now() - interval '6 years', 'system', 'test.ancient', true), (now() - interval '4 years', 'system', 'test.old', true);
select pg_temp.expect_error($$update app.audit set ok = ok where action = 'test.ancient'$$, 'the audit is append-only', 'an audit row cannot be updated, however old');
select pg_temp.expect_error($$delete from app.audit where action = 'test.ancient'$$, 'the audit is append-only', 'an old audit row cannot be deleted outside the purge');
select set_config('app.purging', 'on', true);
select pg_temp.expect_error($$delete from app.audit where action = 'test.old'$$, 'the audit is append-only', 'a row younger than five years cannot be deleted even while purging');
select pg_temp.expect_error($$delete from app.audit where action = 'job.test'$$, 'the audit is append-only', 'a recent row cannot be deleted while purging');
select set_config('app.purging', '', true);
select pg_temp.expect_error($$truncate app.audit$$, 'the audit is append-only', 'the audit still cannot be truncated');
create temp table t_purged as select app.purge_audit() n;
select pg_temp.check((select n from t_purged) = 1 and not exists (select 1 from app.audit where action = 'test.ancient') and exists (select 1 from app.audit where action = 'test.old')
                     and (select last_purged from app.retention_rules where key = 'audit_log') = 1
                     and exists (select 1 from app.audit where action = 'job.purged' and detail ->> 'rule' = 'audit_log'), 'the audit purge removes only rows older than five years and says so');

-- ---------------------------------------------------------------------------
-- the register: the security keys, their defaults (D-29, Q5) and the rights to change them
select pg_temp.check((select options from app.settings_registry where key = 'login_alerts') = array['off', 'immediate', 'digest'] and app.setting('login_alerts') = 'off'
                     and app.setting('ip_allowlist') = 'off' and app.setting('signin_hours') = 'off' and app.setting('alert_new_device') = 'off'
                     and app.setting('alert_user_invited') = 'immediate' and app.setting('alert_failed_logins') = 'immediate' and app.setting('alert_password_reset') = 'immediate'
                     and app.setting('alert_large_export') = 'immediate' and app.setting('password_expiry') = 'never' and app.setting('password_reuse') = 'off'
                     and app.setting('alert_digest_time') = '08:00' and app.setting('security_alert_recipients') = 'role' and app.setting('access_review_interval') = 'quarterly',
                     'defaults: login alerts and the allowlist off (D-29), new device off, the other alerts immediate (Q5), nothing restricted');
select pg_temp.check(app.setting_number('alert_failed_logins_count', 3) = 3 and app.setting_number('alert_large_export_rows', 1000) = 1000, 'the thresholds are the source values');
insert into app.permission_sets (key, name, kind, rights) values ('configonly', 'P8 config only', 'custom', array['global:configure', 'global:see']);
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'configonly') where email = 'emma@orgpuls.no';
select pg_temp.as_s('emma@orgpuls.no');
select pg_temp.expect_detail($$select public.setting_set('alert_new_device', 'immediate')$$, 'forbidden', 'global:security', 'a security key needs global:security, not only configure');
select public.setting_set('tracking', 'off');
select pg_temp.check(app.setting('tracking') = 'off', 'other keys still need only global:configure');
select pg_temp.as_s('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.setting_set('login_alerts', 'on')$$, 'invalid', 'value', 'login_alerts is no longer on/off');
select pg_temp.expect_detail($$select public.setting_set('password_reuse', 'number', '', 5)$$, 'not_available', 'password_history', 'password reuse cannot be switched on: no history exists (Q4)');
select public.setting_set('password_reuse', 'off');

-- ---------------------------------------------------------------------------
-- sign-in (SF-27): sessions, devices, locations; nothing in clear
select pg_temp.check((pg_temp.signin('tor@orgpuls.no', '84.208.12.40', 'tor-mac') ->> 'allowed')::boolean, 'a sign-in is allowed by default');
select pg_temp.signin('ingrid@orgpuls.no', '10.1.2.3', 'ingrid-iphone');
select pg_temp.signin('hanna@orgpuls.no', '46.9.101.220', 'hanna-win');
select pg_temp.signin('hanna@orgpuls.no', '46.9.101.221', 'hanna-new', 'Bergen', 'NO');
select pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc');
select pg_temp.check((select count(*) from app.staff_sessions where ended_at is null) = 5, 'each sign-in opened a session');
select pg_temp.check((select new_device and new_location from app.login_log where device_hash = extensions.digest('device:hanna-new', 'sha256'))
                     and not (select new_device or new_location from app.login_log where device_hash = extensions.digest('device:hanna-win', 'sha256')),
                     'a second device and a second city are new; a person''s first sign-in is not');
select pg_temp.check((select count(*) from app.security_events where kind in ('new_device', 'new_location')) = 2
                     and (select bool_and(alert_state = 'none') from app.security_events where kind in ('new_device', 'new_location')),
                     'new device and location are security events; their alert is off by default (D-29)');
select pg_temp.check((select device_label from app.staff_sessions where session_id = pg_temp.sid('tor@orgpuls.no')) = 'Chrome on macOS',
                     'the user agent becomes a label and is not kept');
select pg_temp.check(not exists (select 1 from app.login_log where encode(ip_sealed, 'escape') like '%84.208%')
                     and app.ip_open((select ip_sealed from app.login_log where staff_id = (select tor from t_staff) limit 1)) = '84.208.12.40'::inet,
                     'the IP is sealed (not readable in the row) and opens with the Vault key');
select pg_temp.check(exists (select 1 from vault.secrets where name = 'security_ip_key'), 'the IP key lives in Vault');

-- ---------------------------------------------------------------------------
-- SEC-01: the dashboard figures equal the login log
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
create temp table t_dash as select public.security_dashboard() d;
select pg_temp.check((select (d -> 'kpis' ->> 'signed_in_now')::int from t_dash)
                     = (select count(*) from app.staff_sessions where ended_at is null and last_seen_at >= now() - interval '30 minutes'), 'signed in now = open sessions');
select pg_temp.check((select (d -> 'kpis' -> 'new_devices_7d' ->> 'count')::int from t_dash)
                     = (select count(*) from app.login_log where outcome = 'success' and new_device and at > now() - interval '7 days')
                     and (select d -> 'kpis' -> 'new_devices_7d' -> 'staff' -> 0 ->> 'name' from t_dash) = (select name from app.admins where email = 'hanna@orgpuls.no'),
                     'new devices · 7 d = the log''s new_device sign-ins, named');
select pg_temp.check((select (d -> 'kpis' -> 'new_locations_7d' ->> 'count')::int from t_dash)
                     = (select count(*) from app.login_log where outcome = 'success' and new_location and at > now() - interval '7 days')
                     and (select d -> 'kpis' -> 'new_locations_7d' -> 'places' -> 0 ->> 'city' from t_dash) = 'Bergen', 'new locations · 7 d = the log''s new_location sign-ins');
select pg_temp.check((select (d -> 'kpis' -> 'security_events_7d' ->> 'count')::int from t_dash) = (select count(*) from app.security_events where at > now() - interval '7 days')
                     and (select (d -> 'kpis' -> 'security_events_7d' ->> 'critical')::int from t_dash) = 0, 'security events · 7 d = the events table');
select pg_temp.check((select (d -> 'kpis' -> 'mfa' ->> 'enrolled')::int = 9 and (d -> 'kpis' -> 'mfa' ->> 'active')::int = 9 from t_dash), 'MFA coverage = verified factors of active staff');
select pg_temp.check((select jsonb_array_length(d -> 'live') from t_dash) = 5 and (select count(*) from jsonb_array_elements((select d -> 'live' from t_dash)) x where (x ->> 'current')::boolean) = 1,
                     'the live rows are the open sessions; the caller''s own is marked');
select pg_temp.check((select d -> 'settings' ->> 'ip_allowlist' = 'off' and d -> 'settings' ->> 'session_idle' = 'on_30' from t_dash), 'the footnote renders the real settings (D-29)');
select pg_temp.check(exists (select 1 from jsonb_array_elements((select d -> 'issues' from t_dash)) i where i ->> 'key' = 'access_review_due')
                     and (select (d ->> 'issues_open')::int = jsonb_array_length(d -> 'issues') from t_dash), 'never reviewed: the access review is due; N open = the count');
select pg_temp.as_s('ingrid@orgpuls.no', pg_temp.sid('ingrid@orgpuls.no'));
select pg_temp.expect_detail($$select public.security_dashboard()$$, 'forbidden', 'global:security', 'the dashboard is admin only (SEC-01)');
select pg_temp.as_nobody();
select pg_temp.expect_error($$select public.security_dashboard()$$, 'not_signed_in', 'nobody gets the dashboard');

-- ---------------------------------------------------------------------------
-- SEC-04: logging out a device ends its session at once
select pg_temp.as_s('ingrid@orgpuls.no', pg_temp.sid('ingrid@orgpuls.no'));
select pg_temp.expect_detail(format($$select public.session_revoke(%L)$$, pg_temp.sid('tor@orgpuls.no')), 'forbidden', 'global:security', 'nobody else''s session without global:security');
select pg_temp.expect_detail(format($$select public.login_history(%L)$$, (select tor from t_staff)), 'forbidden', 'global:security', 'nobody else''s login history without global:security');
select pg_temp.check(jsonb_array_length(public.login_history((select ingrid from t_staff))) = 1 and jsonb_array_length(public.my_sessions()) = 1, 'one''s own history and sessions');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
create temp table t_isid as select pg_temp.sid('ingrid@orgpuls.no') sid;
select pg_temp.check(app.session_ok((select sid from t_isid)), 'a fresh session is good');
select public.session_revoke((select sid from t_isid), null);
select pg_temp.check((select end_reason = 'forced' and ended_by = (select tor from t_staff) from app.staff_sessions where session_id = (select sid from t_isid))
                     and not exists (select 1 from auth.sessions where id = (select sid from t_isid)) and not app.session_ok((select sid from t_isid)),
                     'session_revoke ends the row, deletes the Auth session and app.session_ok refuses it at once (SEC-04, for 0044''s app.me())');
select pg_temp.check(exists (select 1 from app.security_events where kind = 'session_revoked' and subject_staff_id = (select ingrid from t_staff))
                     and exists (select 1 from app.audit where action = 'session.revoked' and target_id = (select ingrid::text from t_staff) and kind = 'security'),
                     'the log-out is a security event and audited');
select pg_temp.expect_error(format($$update app.staff_sessions set ended_at = null, end_reason = null where session_id = %L$$, (select sid from t_isid)),
                            'an ended session stays ended', 'an ended session cannot be revived');
select pg_temp.check((select (public.security_dashboard() -> 'kpis' ->> 'forced_logouts_7d')::int)
                     = (select count(*) from app.staff_sessions where end_reason = 'forced' and ended_at > now() - interval '7 days'), 'forced logouts · 7 d = the sessions ended by force');
create temp table t_hist as select public.login_history((select hanna from t_staff)) h;
select pg_temp.check((select jsonb_array_length(h) from t_hist) = 2 and (select bool_or(x ->> 'ip' = '46.9.101.221') from t_hist, jsonb_array_elements(h) x)
                     and (select bool_and((x ->> 'active')::boolean) from t_hist, jsonb_array_elements(h) x), 'login history: device, place, IP, method, active');
select pg_temp.signin('tor@orgpuls.no', '84.208.12.40', 'tor-mac');
select pg_temp.check((public.staff_sessions_revoke_all((select tor from t_staff), null) ->> 'ended')::int = 1
                     and exists (select 1 from app.staff_sessions where session_id = app.current_session() and ended_at is null),
                     'log out of all devices ends one''s other sessions and keeps the current one');
select pg_temp.check(not app.session_ok(null) and not app.session_ok(gen_random_uuid()), 'no session, or an unknown one past the grace window, is not good');
insert into auth.sessions (id, user_id, created_at, updated_at, aal) select '00000000-0000-0000-0000-0000000005e5', id, now(), now(), 'aal2' from auth.users where email = 'tor@orgpuls.no';
select pg_temp.check(app.session_ok('00000000-0000-0000-0000-0000000005e5'), 'an Auth session not yet reported is good within the two-minute grace window');
update app.staff_sessions set last_seen_at = now() - interval '31 minutes' where session_id = pg_temp.sid('magnus@orgpuls.no');
select pg_temp.check(not app.session_ok(pg_temp.sid('magnus@orgpuls.no')), 'session_idle on_30: a session idle 31 minutes is not good');
select public.setting_set('session_idle', 'off');
select pg_temp.check(app.session_ok(pg_temp.sid('magnus@orgpuls.no')) and app.sessions_expire() = 0, 'session_idle off: it is good and nothing expires');
select public.setting_set('session_idle', 'on_30');
create temp table t_msid as select pg_temp.sid('magnus@orgpuls.no') sid;
create temp table t_exp1 as select app.sessions_expire() n;
select pg_temp.check((select n from t_exp1) = 1 and (select end_reason from app.staff_sessions where session_id = (select sid from t_msid)) = 'idle_timeout',
                     'the expiry job ends the idle session');

-- SEC-09: a deactivated person's sessions end at once
select pg_temp.signin('ingrid@orgpuls.no', '10.1.2.3', 'ingrid-iphone');
create temp table t_isid2 as select pg_temp.sid('ingrid@orgpuls.no') sid;
select public.staff_save((select ingrid from t_staff), '{"active": false}');
select pg_temp.check((select end_reason from app.staff_sessions where session_id = (select sid from t_isid2)) = 'deactivated', 'deactivating a user ends their sessions (SF-43.2)');
select pg_temp.check((pg_temp.signin('ingrid@orgpuls.no', '10.1.2.3', 'ingrid-iphone') ->> 'reason') = 'blocked_inactive', 'a deactivated user cannot sign in (SEC-09)');
select public.staff_save((select ingrid from t_staff), '{"active": true}');

-- ---------------------------------------------------------------------------
-- SEC-03: rules, the hook and self-lockout
select pg_temp.signin('ingrid@orgpuls.no', '10.1.2.3', 'ingrid-iphone');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'), false);
select pg_temp.expect_detail($$select public.setting_set('ip_allowlist', 'on')$$, 'forbidden', 'fresh_mfa', 'switching the allowlist on needs a fresh second factor');
select pg_temp.as_s('tor@orgpuls.no', null);
select pg_temp.expect_detail($$select public.setting_set('ip_allowlist', 'on')$$, 'forbidden', 'self_lockout', 'without a known current IP the switch is refused');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select pg_temp.expect_detail($$select public.setting_set('ip_allowlist', 'on')$$, 'forbidden', 'self_lockout', 'no rule covers the caller: refused (self_lockout)');
select pg_temp.expect_detail($$select public.security_rule_save(null, '{"kind": "ip_range", "label": "All", "cidr": "0.0.0.0/0"}')$$, 'invalid', 'cidr', 'a range wider than /8 is refused');
select pg_temp.expect_detail($$select public.security_rule_save(null, '{"kind": "ip_range", "label": "Bad", "cidr": "84.208.12.300/24"}')$$, 'invalid', 'cidr', 'a malformed range is refused');
create temp table t_rule as select (public.security_rule_save(null, '{"kind": "ip_range", "label": "Office", "cidr": "84.208.12.0/24"}') ->> 'id')::uuid id;
create temp table t_prev as select public.security_rule_preview('{"ip_allowlist": "on"}') p;
select pg_temp.check((select not (p ->> 'self_lockout')::boolean from t_prev)
                     and (select bool_or((x ->> 'staff_id')::uuid = (select ingrid from t_staff) and (x ->> 'refused')::int >= 1) from t_prev, jsonb_array_elements(p -> 'staff') x)
                     and not (select bool_or((x ->> 'staff_id')::uuid = (select tor from t_staff)) from t_prev, jsonb_array_elements(p -> 'staff') x),
                     'the preview lists staff whose sign-ins in 30 days would have been refused, and not the caller');
select pg_temp.check((public.security_rule_preview(jsonb_build_object('ip_allowlist', 'on', 'remove', (select id from t_rule))) ->> 'self_lockout')::boolean,
                     'the preview warns when a change would lock the caller out');
select public.setting_set('ip_allowlist', 'on');
select pg_temp.check(app.setting('ip_allowlist') = 'on'
                     and exists (select 1 from app.staff_sessions where staff_id = (select ingrid from t_staff) and end_reason = 'ip_rule')
                     and exists (select 1 from app.staff_sessions where session_id = app.current_session() and ended_at is null),
                     'switched on: sessions outside the rules end (ip_rule); the caller stays');
create temp table t_blk as select pg_temp.signin('ingrid@orgpuls.no', '185.12.4.77', 'ingrid-iphone') r;
select pg_temp.check((select not (r ->> 'allowed')::boolean and r ->> 'reason' = 'blocked_ip' from t_blk)
                     and (select outcome from app.login_log order by id desc limit 1) = 'blocked_ip'
                     and not exists (select 1 from auth.sessions where id = (select (r ->> 'session_id')::uuid from t_blk))
                     and not exists (select 1 from app.staff_sessions where session_id = (select (r ->> 'session_id')::uuid from t_blk)),
                     'a login from a blocked IP is refused, logged blocked_ip, and its Auth session deleted (SEC-03)');
select pg_temp.check(exists (select 1 from app.security_events where kind = 'ip_blocked' and subject_staff_id = (select ingrid from t_staff)), 'the block is a security event');
select pg_temp.check((public.worker_session_seen(app.current_session(), '84.208.12.99'::inet, null) ->> 'ok')::boolean, 'a session inside the rules stays good');
create temp table t_seen as select public.worker_session_seen(app.current_session(), '185.12.4.77'::inet, null) r;
select pg_temp.check((select r ->> 'reason' from t_seen) = 'ip_rule' and not app.session_ok(app.current_session()), 'a live session that moves outside the rules is ended (ip_rule)');
select pg_temp.signin('tor@orgpuls.no', '84.208.12.40', 'tor-mac');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select pg_temp.expect_detail(format($$select public.security_rule_delete(%L)$$, (select id from t_rule)), 'forbidden', 'self_lockout', 'deleting the rule the caller stands on is refused');
select pg_temp.expect_detail(format($$select public.security_rule_save(%L, '{"cidr": "10.9.0.0/16"}', 1)$$, (select id from t_rule)), 'forbidden', 'self_lockout',
                             'narrowing it past the caller is refused');
select pg_temp.check(exists (select 1 from app.security_rules where id = (select id from t_rule) and archived_at is null and version = 1), 'a refused change leaves the rule as it was');
select pg_temp.expect_detail(format($$select public.security_rule_save(%L, '{"label": "Kontor"}', 7)$$, (select id from t_rule)), 'version_conflict', '1', 'a stale version is refused');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'), false);
select pg_temp.expect_detail(format($$select public.security_rule_save(%L, '{"label": "Kontor"}', 1)$$, (select id from t_rule)), 'forbidden', 'fresh_mfa',
                             'editing a rule in force needs a fresh second factor');
select pg_temp.check((public.security_rule_save(null, '{"kind": "ip_range", "label": "VPN", "cidr": "10.8.0.0/16"}') ->> 'kind') = 'ip_range', 'adding a range only widens: no fresh factor needed');
select public.setting_set('ip_allowlist', 'off');
select pg_temp.check(app.setting('ip_allowlist') = 'off' and (pg_temp.signin('ingrid@orgpuls.no', '185.12.4.77', 'ingrid-iphone') ->> 'allowed')::boolean,
                     'allowlist off: the same IP signs in (both states of ip_allowlist)');

-- sign-in hours
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select pg_temp.expect_detail($$select public.setting_set('signin_hours', 'on')$$, 'forbidden', 'self_lockout', 'sign-in hours with no window covering now: refused');
select public.security_rule_save(null, '{"kind": "time_window", "label": "Always", "days": [1,2,3,4,5,6,7], "starts": "00:00", "ends": "23:59:59"}');
select public.setting_set('signin_hours', 'on');
select pg_temp.check(app.setting('signin_hours') = 'on' and app.time_allowed(now()) is not null, 'with a window covering now the switch goes on');
select pg_temp.check(app.window_match('2026-10-05 07:30+00', array[1,2,3,4,5]::smallint[], '08:00', '17:00')            -- Monday 09:30 Oslo
                     and not app.window_match('2026-10-04 07:30+00', array[1,2,3,4,5]::smallint[], '08:00', '17:00')     -- Sunday
                     and not app.window_match('2026-10-05 16:30+00', array[1,2,3,4,5]::smallint[], '08:00', '17:00')     -- Monday 18:30
                     and app.window_match('2026-10-06 03:00+00', array[1]::smallint[], '22:00', '06:00'),               -- Monday's night shift, Tuesday 05:00
                     'windows run in Europe/Oslo on ISO days; an overnight window belongs to its start day');
-- a window that excludes now, written directly (the RPC would refuse it as a self-lockout)
update app.security_rules set archived_at = now() where kind = 'time_window';
insert into app.security_rules (kind, days, starts, ends, label)
values ('time_window', array[extract(isodow from now() at time zone 'Europe/Oslo')::smallint],
        ((now() at time zone 'Europe/Oslo') + interval '2 hours')::time, ((now() at time zone 'Europe/Oslo') + interval '3 hours')::time, 'Later');
select pg_temp.check((pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc') ->> 'reason') = 'blocked_time'
                     and not app.session_ok(pg_temp.sid('tor@orgpuls.no')), 'outside every window: the sign-in is refused (blocked_time) and live sessions are not good');
delete from app.setting_values where key = 'signin_hours';
select pg_temp.check(app.session_ok(pg_temp.sid('tor@orgpuls.no')) and (pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc') ->> 'allowed')::boolean,
                     'sign-in hours off: the same moment is allowed (both states of signin_hours)');

-- password expiry (checked at sign-in)
insert into app.password_changes (staff_id, changed_at) values ((select magnus from t_staff), now() - interval '40 days');
select pg_temp.check(not (pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc') ->> 'must_change_password')::boolean, 'password_expiry never: no forced change');
select public.setting_set('password_expiry', 'days', '', 30);
select pg_temp.check((pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc') ->> 'must_change_password')::boolean, 'password_expiry 30 days: a 40-day-old password must change');
select public.worker_password_changed('magnus@orgpuls.no');
select pg_temp.check(not (pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc') ->> 'must_change_password')::boolean
                     and (select count(*) from app.password_changes where staff_id = (select magnus from t_staff)) = 1, 'after a change it does not; only the latest date is kept');
select public.setting_set('password_expiry', 'never');

-- ---------------------------------------------------------------------------
-- SEC-02: each trigger produces one alert to admins
select pg_temp.check((select array_agg(x order by x) from app.security_recipients() x) = array[(select tor from t_staff)], 'recipients by role: the global:security holders');
-- failed logins in a row: one event when the streak reaches the threshold
select public.worker_login_event('{"email": "ola@orgpuls.no", "outcome": "failed_password"}') from generate_series(1, 4);
select pg_temp.check((select count(*) from app.security_events where kind = 'failed_logins' and subject_staff_id = (select ola from t_staff)) = 1
                     and (select (detail ->> 'count')::int from app.security_events where kind = 'failed_logins' and subject_staff_id = (select ola from t_staff)) = 3,
                     'four failures in a row raise one failed_logins event, at the third');
insert into app.login_log (at, staff_id, email_sha256, outcome) values
  (now() - interval '10 minutes', (select hanna from t_staff), app.email_hash('hanna@orgpuls.no'), 'failed_password'),
  (now() - interval '9 minutes', (select hanna from t_staff), app.email_hash('hanna@orgpuls.no'), 'failed_password'),
  (now() - interval '5 minutes', (select hanna from t_staff), app.email_hash('hanna@orgpuls.no'), 'success');
select public.worker_login_event('{"email": "hanna@orgpuls.no", "outcome": "failed_mfa"}');
select pg_temp.check(not exists (select 1 from app.security_events where kind = 'failed_logins' and subject_staff_id = (select hanna from t_staff)), 'a success breaks the streak');
select public.worker_login_event('{"email": "nobody@example.com", "outcome": "failed_password"}') from generate_series(1, 3);
select pg_temp.check((select count(*) from app.login_log where staff_id is null and email_sha256 = app.email_hash('nobody@example.com')) = 3
                     and exists (select 1 from app.security_events where kind = 'failed_logins' and subject_staff_id is null), 'an unknown address is logged by hash only, and still alerts');
select public.setting_set('alert_failed_logins_count', 'custom', '', 5);
select public.worker_login_event('{"email": "eirik@orgpuls.no", "outcome": "failed_password"}') from generate_series(1, 4);
select pg_temp.check(not exists (select 1 from app.security_events e join app.admins a on a.id = e.subject_staff_id where e.kind = 'failed_logins' and a.email = 'eirik@orgpuls.no'),
                     'alert_failed_logins_count 5: four failures raise nothing');
select public.worker_login_event('{"email": "eirik@orgpuls.no", "outcome": "failed_password"}');
select pg_temp.check(exists (select 1 from app.security_events e join app.admins a on a.id = e.subject_staff_id where e.kind = 'failed_logins' and a.email = 'eirik@orgpuls.no'),
                     'the fifth does');
select public.setting_set('alert_failed_logins_count', 'source_value');
-- delivery: once per event, channel and recipient, however often the job runs
select app.security_alerts_run();
select app.security_alerts_run();
select pg_temp.check(not exists (select 1 from app.security_alert_deliveries group by event_id, channel, recipient_id having count(*) > 1)
                     and (select count(*) from app.security_alert_deliveries d join app.security_events e on e.id = d.event_id where e.kind = 'failed_logins' and d.channel = 'in_app')
                         = (select count(*) from app.security_events where kind = 'failed_logins')
                     and (select bool_and(status = 'not_connected') from app.security_alert_deliveries where channel = 'email')
                     and not exists (select 1 from app.security_events where alert_state = 'queued'),
                     'each trigger produces one alert per channel and recipient; email is not_connected (SEC-02)');
select pg_temp.check((select count(*) from app.notifications where staff_id = (select tor from t_staff) and key = 'security.failed_logins')
                     = (select count(*) from app.security_events where kind = 'failed_logins'), 'one in-app notification per event');
select pg_temp.check(not exists (select 1 from app.security_alert_deliveries d join app.security_events e on e.id = d.event_id where e.alert_state = 'none'),
                     'an event whose alert is off is never delivered');
-- alert_user_invited, alert_password_reset
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
create temp table t_new as select (public.staff_save(null, '{"email": "petter@orgpuls.no", "name": "Petter Aas"}') ->> 'id')::uuid id;
select pg_temp.check((select alert_state from app.security_events where kind = 'user_invited' and subject_staff_id = (select id from t_new)) = 'queued'
                     and (select actor_id from app.security_events where kind = 'user_invited' and subject_staff_id = (select id from t_new)) = (select tor from t_staff),
                     'an invitation is a security event queued for alerting');
select public.setting_set('alert_password_reset', 'off');
select public.worker_password_reset('sara@orgpuls.no');
select pg_temp.check((select alert_state from app.security_events where kind = 'password_reset' order by id desc limit 1) = 'none', 'alert_password_reset off: recorded, not alerted');
select public.setting_set('alert_password_reset', 'immediate');
select public.worker_password_reset('sara@orgpuls.no');
select pg_temp.check((select alert_state from app.security_events where kind = 'password_reset' order by id desc limit 1) = 'queued', 'alert_password_reset immediate: queued');
select pg_temp.check((public.worker_password_reset('nobody@example.com') ->> 'ok')::boolean
                     and (select count(*) from app.security_events where kind = 'password_reset') = 2, 'an unknown address learns nothing and raises nothing');
-- login_alerts: admin logins, also to Slack (not connected)
select pg_temp.signin('tor@orgpuls.no', '84.208.12.40', 'tor-mac');
select pg_temp.check(not exists (select 1 from app.security_events where kind = 'admin_login'), 'login_alerts off: an admin login raises nothing (D-29)');
select public.setting_set('login_alerts', 'immediate');
select pg_temp.signin('tor@orgpuls.no', '84.208.12.40', 'tor-mac');
select pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc');
select app.security_alerts_run();
select pg_temp.check((select count(*) from app.security_events where kind = 'admin_login') = 1
                     and (select status from app.security_alert_deliveries d join app.security_events e on e.id = d.event_id where e.kind = 'admin_login' and d.channel = 'slack') = 'not_connected',
                     'login_alerts immediate: an admin login (not a support login) alerts, Slack recorded not_connected');
select public.setting_set('login_alerts', 'off');
-- large exports and bulk deletes through the outbox subscriber
select public.export_log('person', 1200, 'csv', 'all');
select public.export_log('person', 12, 'csv', 'all');
select app.sub_security_alerts(e) from app.events e where e.kind = 'export.created' and e.id > (select last_event_id from app.event_cursors where subscriber = 'security_alerts');
select pg_temp.check((select count(*) from app.security_events where kind = 'large_export') = 1
                     and (select (detail ->> 'rows')::int from app.security_events where kind = 'large_export') = 1200, 'alert_large_export_rows 1000: 1 200 rows alert, 12 do not');
select public.setting_set('alert_large_export_rows', 'custom', '', 10);
select app.sub_security_alerts(e) from app.events e where e.kind = 'export.created' and e.id > (select last_event_id from app.event_cursors where subscriber = 'security_alerts');
select pg_temp.check((select count(*) from app.security_events where kind = 'large_export') = 2, 'a custom threshold of 10: the 12-row export alerts too, once');
select public.setting_set('alert_large_export_rows', 'source_value');
-- the digest
select public.setting_set('alert_new_device', 'digest');
select pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-laptop');
select app.security_alerts_run();
select pg_temp.check((select alert_state from app.security_events where kind = 'new_device' order by id desc limit 1) = 'digest', 'digest mode: the immediate job leaves it');
select public.setting_set('alert_digest_time', '07:00');
select pg_temp.check(app.security_digest_due('2026-10-07 06:10+00') = 0, 'alert_digest_time 07:00: nothing at 08:10 Oslo');
create temp table t_dg as select app.security_digest_due('2026-10-07 05:10+00') n;
select pg_temp.check((select n from t_dg) >= 1 and (select alert_state from app.security_events where kind = 'new_device' order by id desc limit 1) = 'sent'
                     and exists (select 1 from app.notifications where key = 'security.digest' and staff_id = (select tor from t_staff))
                     and app.security_digest_due('2026-10-07 05:40+00') = 0, 'at 07:10 Oslo the digest goes, once a day');
select public.setting_set('alert_new_device', 'off');
-- named recipients
select pg_temp.expect_detail(format($$select public.alert_recipients_set(array[%L]::uuid[])$$, (select ingrid from t_staff)), 'invalid', 'staff', 'a recipient must hold global:security');
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'admin') where email = 'hanna@orgpuls.no';
select pg_temp.check((select count(*) from app.security_recipients()) = 2, 'by role: two holders now');
select public.alert_recipients_set(array[(select hanna from t_staff)]);
select public.setting_set('security_alert_recipients', 'list');
select pg_temp.check((select array_agg(x) from app.security_recipients() x) = array[(select hanna from t_staff)], 'security_alert_recipients list: only the named ones');
select public.worker_password_reset('sara@orgpuls.no');
select app.security_alerts_run();
select pg_temp.check((select array_agg(d.recipient_id) from app.security_alert_deliveries d where d.channel = 'in_app' and d.event_id = (select max(id) from app.security_events))
                     = array[(select hanna from t_staff)], 'and only they receive the alert');
select public.setting_set('security_alert_recipients', 'role');
select pg_temp.check((select alerts_get -> 'settings' ->> 'security_alert_recipients' = 'role' and alerts_get ->> 'email' = 'not_connected' and alerts_get ->> 'slack' = 'not_connected'
                      and jsonb_array_length(alerts_get -> 'recipients') = 2 from public.alerts_get()), 'alerts_get: the settings, the real recipients, in-app only');

-- ---------------------------------------------------------------------------
-- SEC-05: SSO is configuration until the Auth project has the provider (D-31)
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'), false);
select pg_temp.expect_detail($$select public.sso_set('google', true, array['orgpuls.no'])$$, 'forbidden', 'fresh_mfa', 'an SSO change needs a fresh second factor');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select pg_temp.expect_detail($$select public.sso_set('google', true, array['orgpuls.no'])$$, 'not_connected', 'google', 'switching Google on is refused while it is not configured');
select pg_temp.expect_detail($$select public.sso_set('google', false, array['not a domain'])$$, 'invalid', 'domains', 'a malformed domain is refused');
select pg_temp.expect_error($$select public.sso_set('okta', true, null)$$, 'not_found', 'Okta and SAML do not exist (D-31)');
select pg_temp.check((pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc', 'Oslo', 'NO', 'google_totp') ->> 'reason') = 'blocked_method',
                     'a Google sign-in while Google is off is refused (blocked_method)');
select public.worker_sso_configured('google', true);
select public.sso_set('google', true, array['orgpuls.no']);
create temp table t_g as select pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc', 'Oslo', 'NO', 'google_totp') r;
select pg_temp.check((select (r ->> 'allowed')::boolean from t_g)
                     and (select (x ->> 'users')::int from jsonb_array_elements(public.sso_get() -> 'providers') x where x ->> 'provider' = 'google') = 1,
                     'configured and on: an invited @orgpuls.no user signs in with Google, then TOTP; «N users» counts them');
select public.sso_set('google', true, array['example.no']);
select pg_temp.check((pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc', 'Oslo', 'NO', 'google_totp') ->> 'reason') = 'blocked_method',
                     'an address outside the allowed domains is refused');
select public.worker_sso_configured('google', false);
select pg_temp.check((select not enabled from app.sso_providers where provider = 'google'), 'unconfigured at the Auth project, the switch goes off with it');

-- ---------------------------------------------------------------------------
-- SEC-06: no RPC here at aal1 but recovery; recovery codes; the owner reset
select pg_temp.as_s('tor@orgpuls.no', null, true, 'aal1');
create temp table t_aal1 as
  select r.f, format('select %s(%s)', p.oid::regproc, (select string_agg('null::' || format_type(t, null), ', ') from unnest(p.proargtypes) t)) q
  from t_rpcs r join pg_proc p on p.oid = r.f::regprocedure where r.f <> 'public.recovery_code_redeem(text)';
do $$
declare r record;
begin
  for r in select * from t_aal1 loop
    begin
      execute r.q;
      raise exception 'FAIL % ran at aal1', r.f;
    exception when others then
      if sqlerrm <> 'not_signed_in' then raise exception 'FAIL % at aal1 raised «%»', r.f, sqlerrm; end if;
    end;
  end loop;
end $$;
select pg_temp.check(true, 'every security function refuses aal1 with not_signed_in (' || (select count(*) from t_aal1) || '), except recovery_code_redeem');
select pg_temp.as_s('ola@orgpuls.no', pg_temp.sid('ola@orgpuls.no'), false);
select pg_temp.expect_detail($$select public.recovery_codes_generate()$$, 'forbidden', 'fresh_mfa', 'generating codes needs a fresh second factor');
select pg_temp.signin('ola@orgpuls.no', '84.208.12.41', 'ola-pc');
select pg_temp.signin('ola@orgpuls.no', '84.208.12.42', 'ola-phone');
select pg_temp.as_s('ola@orgpuls.no', pg_temp.sid('ola@orgpuls.no'));
create temp table t_codes as select public.recovery_codes_generate() -> 'codes' c;
select pg_temp.check((select jsonb_array_length(c) from t_codes) = 10 and (select count(*) from app.recovery_codes where staff_id = (select ola from t_staff) and used_at is null) = 10
                     and not exists (select 1 from app.recovery_codes r, t_codes, jsonb_array_elements_text(c) x where encode(r.hash, 'escape') like '%' || replace(x, '-', '') || '%'),
                     'ten codes, shown once, stored as SHA-256 only');
select pg_temp.as_s('ola@orgpuls.no', pg_temp.sid('ola@orgpuls.no'), false, 'aal1');
select pg_temp.check(not (public.recovery_code_redeem('wrong-code') ->> 'ok')::boolean, 'a wrong code answers ok false (and is counted)');
create temp table t_osid as select pg_temp.sid('ola@orgpuls.no') cur;
select pg_temp.check((public.recovery_code_redeem((select c ->> 3 from t_codes)) ->> 'ok')::boolean, 'a recovery code works at aal1, the one deliberate exception');
select pg_temp.check(not app.staff_mfa_verified('ola@orgpuls.no')
                     and (select count(*) from app.staff_sessions where staff_id = (select ola from t_staff) and ended_at is null) = 1
                     and exists (select 1 from app.staff_sessions where staff_id = (select ola from t_staff) and end_reason = 'recovery_code')
                     and (select used_at is not null from app.recovery_codes where staff_id = (select ola from t_staff) and hash = extensions.digest((select replace(c ->> 3, '-', '') from t_codes), 'sha256'))
                     and exists (select 1 from app.audit where action = 'recovery_codes.redeemed' and staff_id = (select ola from t_staff) and principal_kind = 'staff'),
                     'redeemed: the factors are gone, the other sessions ended, the code used, audited; they enrol again');
select pg_temp.check(not (public.recovery_code_redeem((select c ->> 3 from t_codes)) ->> 'ok')::boolean, 'a code is used once');
select public.recovery_code_redeem('wrong') from generate_series(1, 4);
select pg_temp.expect_detail($$select public.recovery_code_redeem('wrong')$$, 'forbidden', 'rate_limited', 'five attempts an hour, then refused');
-- issues follow the condition: ola has no factor now
update app.admins set created_at = now() - interval '6 days' where email = 'ola@orgpuls.no';
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select pg_temp.check((select (i -> 'staff' -> 0 ->> 'id')::uuid = (select ola from t_staff) and (i -> 'staff' -> 0 ->> 'days')::int = 6
                      from jsonb_array_elements(public.security_dashboard() -> 'issues') i where i ->> 'key' = 'mfa_not_enrolled'),
                     'an invited person without a factor after six days is a high issue');
select pg_temp.check((public.mfa_overview() ->> 'authenticator')::int = 8 and (public.mfa_overview() -> 'not_enrolled' -> 0 ->> 'id')::uuid = (select ola from t_staff)
                     and (public.mfa_overview() ->> 'enforced')::boolean, 'the MFA overview counts factors and names who is not enrolled; enforcement is fixed');
create temp table t_remind as select public.staff_mfa_reminder((select ola from t_staff)) r;
select pg_temp.check((select r ->> 'email' from t_remind) = 'not_connected'
                     and exists (select 1 from app.notifications where staff_id = (select ola from t_staff) and key = 'security.mfa_reminder'), 'the reminder goes in-app; email is not connected');
select pg_temp.expect_detail(format($$select public.staff_mfa_reminder(%L)$$, (select magnus from t_staff)), 'invalid', 'enrolled', 'no reminder for an enrolled person');
-- the owner reset
select pg_temp.as_s('hanna@orgpuls.no', pg_temp.sid('hanna@orgpuls.no'));
select pg_temp.expect_detail(format($$select public.staff_mfa_reset(%L, 'lost phone')$$, (select magnus from t_staff)), 'forbidden', 'owner_only', 'only the owner resets a factor (D-11)');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'), false);
select pg_temp.expect_detail(format($$select public.staff_mfa_reset(%L, 'lost phone')$$, (select magnus from t_staff)), 'forbidden', 'fresh_mfa', 'with a fresh second factor');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select pg_temp.expect_detail(format($$select public.staff_mfa_reset(%L, 'x')$$, (select tor from t_staff)), 'forbidden', 'self', 'not one''s own');
create temp table t_reset as select public.staff_mfa_reset((select magnus from t_staff), 'lost phone') r;
select pg_temp.check((select (r ->> 'factors_removed')::int from t_reset) = 1 and not app.staff_mfa_verified('magnus@orgpuls.no')
                     and not exists (select 1 from app.staff_sessions where staff_id = (select magnus from t_staff) and ended_at is null)
                     and exists (select 1 from app.staff_sessions where staff_id = (select magnus from t_staff) and end_reason = 'mfa_reset')
                     and exists (select 1 from app.security_events where kind = 'mfa_reset' and subject_staff_id = (select magnus from t_staff) and actor_id = (select tor from t_staff))
                     and (select kind = 'role' and reason = 'lost phone' from app.audit where action = 'mfa.reset' order by id desc limit 1),
                     'the owner reset removes the factor and ends the sessions, as a security event and a role audit row with the reason');

-- ---------------------------------------------------------------------------
-- access reviews and access_review_interval
select pg_temp.as_s('ingrid@orgpuls.no', pg_temp.sid('ingrid@orgpuls.no'));
select pg_temp.expect_detail($$select public.access_review_start()$$, 'forbidden', 'global:security', 'reviews need global:security');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
create temp table t_rev as select (public.access_review_start() ->> 'id')::uuid id;
select pg_temp.check((select count(*) from app.access_review_items where review_id = (select id from t_rev)) = (select count(*) from app.admins where active and not is_sample),
                     'a review snapshots every active staff member');
select pg_temp.expect_detail($$select public.access_review_start()$$, 'invalid', 'open_review', 'one open review at a time');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.security_dashboard() -> 'issues') i where i ->> 'key' = 'access_review_due'), 'started: the issue clears');
select pg_temp.expect_detail(format($$select public.access_review_complete(%L)$$, (select id from t_rev)), 'invalid', 'undecided', 'every person needs a decision');
select pg_temp.expect_detail(format($$select public.access_review_decide(%L, %L, 'maybe')$$, (select id from t_rev), (select ola from t_staff)), 'invalid', 'decision', 'decisions are keep, change or deactivate');
select public.access_review_decide((select id from t_rev), staff_id, 'keep') from app.access_review_items where review_id = (select id from t_rev);
select public.access_review_complete((select id from t_rev));
select pg_temp.check(app.access_review_next_due() = (now() + interval '3 months')::date, 'quarterly: the next review is due in three months');
select public.setting_set('access_review_interval', 'half_yearly');
select pg_temp.check(app.access_review_next_due() = (now() + interval '6 months')::date and app.access_review_due() = 0, 'half_yearly: in six months; the reminder job stays quiet');

-- ---------------------------------------------------------------------------
-- SEC-10: data protection
select pg_temp.check((public.firewall_status() ->> 'ok')::boolean and jsonb_array_length(public.firewall_status() -> 'checks') = 6, 'the firewall''s six claims hold, checked live');
select pg_temp.as_s('emma@orgpuls.no');
select pg_temp.check((public.firewall_status() ->> 'ok')::boolean, 'the firewall status needs only global:see');
select pg_temp.expect_detail($$select public.protection_get()$$, 'forbidden', 'global:security', 'protection details need global:security');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select pg_temp.check((select protection_get -> 'last_backup' = 'null'::jsonb and (protection_get ->> 'pitr_warning')::boolean and protection_get -> 'last_restore_test' = 'null'::jsonb
                      and protection_get -> 'facts' -> 'db_region' ->> 'value' = 'eu-central-1' from public.protection_get()),
                     'nothing recorded: no backup time, no restore test, the PITR warning (D-35)');
select pg_temp.check((public.restore_test_record(now() - interval '1 day', true, 30, 120, 'Monthly drill') ->> 'meets_objectives')::boolean, 'RPO 30, RTO 120: meets the objectives (SEC-10)');
select pg_temp.check(not (public.restore_test_record(now(), true, 90, 120) ->> 'meets_objectives')::boolean, 'RPO 90: does not');
select public.worker_backup_seen('[{"kind": "backup", "at": "2026-10-07T00:00:00Z", "ok": true}, {"kind": "pitr", "at": "2026-10-07T00:00:00Z", "ok": true}]');
select pg_temp.check((select (protection_get -> 'last_backup' ->> 'ok')::boolean and not (protection_get ->> 'pitr_warning')::boolean
                      and not (protection_get -> 'last_restore_test' ->> 'meets_objectives')::boolean from public.protection_get()), 'the worker''s backup and PITR show; the latest restore test decides');
select pg_temp.expect_error($$update app.ops_checks set ok = false$$, 'an operations check is append-only', 'an operations check cannot be changed');
select pg_temp.check(not exists (select 1 from app.audit where detail::text like '%Monthly drill%'), 'the note stays out of the audit');

-- ---------------------------------------------------------------------------
-- SEC-11: privacy: find, preview, export, erase
insert into app.people (id, name, email, phone, owner_id) values ('00000000-0000-0000-0000-0000000008e1', 'Erik Slett', 'erik@slett.example', '+47 900 00 001', (select tor from t_staff));
insert into app.leads (id, title, person_id, owner_id) values ('00000000-0000-0000-0000-0000000008e2', 'Erik lead', '00000000-0000-0000-0000-0000000008e1', (select tor from t_staff));
insert into app.activities (id, subject, person_id, owner_id, type_id)
select '00000000-0000-0000-0000-0000000008e3', 'Ring Erik', '00000000-0000-0000-0000-0000000008e1', (select tor from t_staff), id from app.activity_types order by ord limit 1;
insert into app.email_threads (id, subject) values ('00000000-0000-0000-0000-0000000008e4', 'Hei');
insert into app.email_thread_participants (thread_id, address) values ('00000000-0000-0000-0000-0000000008e4', 'erik@slett.example'), ('00000000-0000-0000-0000-0000000008e4', 'tor@orgpuls.no');
insert into app.email_messages (thread_id, direction, state, from_addr, to_addrs, subject, body_text, source)
values ('00000000-0000-0000-0000-0000000008e4', 'in', 'received', 'erik@slett.example', '[{"address": "tor@orgpuls.no"}]', 'Hei', 'Hemmelig innhold', 'sync');
insert into app.email_threads (id, subject) values ('00000000-0000-0000-0000-0000000008e5', 'Felles');
insert into app.email_thread_participants (thread_id, address) values ('00000000-0000-0000-0000-0000000008e5', 'erik@slett.example'), ('00000000-0000-0000-0000-0000000008e5', 'kari@annen.example');
insert into app.email_messages (thread_id, direction, state, from_addr, to_addrs, cc, subject, body_text, source)
values ('00000000-0000-0000-0000-0000000008e5', 'in', 'received', 'kari@annen.example', '[{"address": "tor@orgpuls.no"}]', '[{"address": "erik@slett.example"}]', 'Felles', 'x', 'sync');
insert into app.events_in (product, source_id, kind, payload, occurred_at)
values ('orgpuls', 880088, 'demo.contact', '{"email": "erik@slett.example", "name": "Erik Slett", "count": 3}', now());
insert into app.members (product, tenant_id, user_id, email, name, active) values ('orgpuls', 'orgpuls-o1', 'u-erik', 'erik@slett.example', 'Erik Slett', true);
insert into app.privacy_requests (kind, received_at) values ('deletion', now()) returning id \gset req_
select pg_temp.as_s('ingrid@orgpuls.no', pg_temp.sid('ingrid@orgpuls.no'));
select pg_temp.expect_detail($$select public.privacy_find('erik@slett.example')$$, 'forbidden', 'global:security', 'privacy search needs global:security');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
create temp table t_find as select public.privacy_find('ERIK@slett.example') f;
select pg_temp.check((select (f -> 'people' -> 0 ->> 'id')::uuid = '00000000-0000-0000-0000-0000000008e1' and jsonb_array_length(f -> 'members') = 1
                      and (f ->> 'email_participants')::int = 2 from t_find), 'privacy_find: the person, their product membership, their mail');
select pg_temp.check((select detail ->> 'by' = 'email' and detail::text not like '%erik%' from app.audit where action = 'privacy.searched' order by id desc limit 1),
                     'the search is audited without the query');
select pg_temp.expect_detail($$select public.privacy_find('ab')$$, 'invalid', 'q', 'a query needs three characters');
create temp table t_prv as select public.privacy_preview('{"people": ["00000000-0000-0000-0000-0000000008e1"]}') p;
select pg_temp.check((select (p -> 'counts' ->> 'people')::int = 1 and (p -> 'counts' ->> 'leads')::int = 1 and (p -> 'counts' ->> 'activities')::int = 1
                      and (p -> 'counts' ->> 'emails')::int = 2 and (p -> 'counts' ->> 'product_events')::int = 1 and (p ->> 'product_user')::boolean from t_prv),
                     'the preview counts per module from the real tables, and flags the product user');
select pg_temp.expect_detail($$select public.privacy_preview('{"people": ["00000000-0000-0000-0000-00000000dead"]}')$$, 'not_found', null, 'an unknown subject is not found');
-- export
create temp table t_exp as select (public.privacy_export('{"people": ["00000000-0000-0000-0000-0000000008e1"]}', :'req_id', null) ->> 'job')::uuid id;
select pg_temp.check((select state = 'approved' from app.privacy_jobs where id = (select id from t_exp))
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'privacy_package' and message ->> 'privacy_job_id' = (select id::text from t_exp)),
                     'an export is a job on the queue');
select pg_temp.check((public.worker_privacy_package((select id from t_exp)) -> 'people' -> 0 ->> 'email') = 'erik@slett.example', 'the worker reads every row about the person');
select pg_temp.expect_detail(format($$select public.worker_privacy_done(%L, 'elsewhere/x.json')$$, (select id from t_exp)), 'invalid', 'path', 'the package goes under its job''s path');
select public.worker_privacy_done((select id from t_exp), 'privacy/' || (select id from t_exp) || '/package.json');
create temp table t_url as select public.privacy_export_url((select id from t_exp)) u;
select pg_temp.check((select state = 'done' and url_expires_at = now() + interval '24 hours' from app.privacy_jobs where id = (select id from t_exp))
                     and (select u ->> 'path' from t_url) like 'privacy/%'
                     and (select status = 'done' from app.privacy_requests where id = :'req_id')
                     and exists (select 1 from app.events where kind = 'privacy.exported' and subject_id = (select id from t_exp))
                     and exists (select 1 from app.audit where action = 'privacy_package.viewed' and kind = 'read'), 'the package link lives 24 h, the request is done, the read is audited');
-- erase: the gates
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'), false);
select pg_temp.expect_detail($$select public.privacy_erase('{"people": ["00000000-0000-0000-0000-0000000008e1"]}', null, 'erik@slett.example')$$, 'forbidden', 'fresh_mfa',
                             'erasure needs a fresh second factor');
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select pg_temp.expect_detail($$select public.privacy_erase('{"people": ["00000000-0000-0000-0000-0000000008e1"]}', null, 'erik@feil.example')$$, 'invalid', 'confirm',
                             'the typed confirmation must be the address');
select pg_temp.expect_detail($$select public.privacy_erase('{"people": ["00000000-0000-0000-0000-0000000008e1"]}', null, 'Erik@Slett.example')$$, 'forbidden', 'product_user',
                             'an active product user is erased in the product, not here');
update app.members set active = false where user_id = 'u-erik';
-- second admin on: a request, then another security holder approves
select public.setting_set('second_admin', 'on');
create temp table t_er as select public.privacy_erase('{"people": ["00000000-0000-0000-0000-0000000008e1"]}', null, 'erik@slett.example', 'request') r;
select pg_temp.check((select r ->> 'approval' = 'required' from t_er) and exists (select 1 from app.people where id = '00000000-0000-0000-0000-0000000008e1')
                     and exists (select 1 from app.notifications where staff_id = (select hanna from t_staff) and key = 'security.erasure_approval'),
                     'second_admin on: nothing is erased until a second admin approves; they are told');
select pg_temp.expect_detail(format($$select public.privacy_approve(%L)$$, (select r ->> 'job' from t_er)), 'forbidden', 'self', 'the requester cannot approve their own erasure');
select pg_temp.as_s('hanna@orgpuls.no', pg_temp.sid('hanna@orgpuls.no'));
select public.privacy_approve((select (r ->> 'job')::uuid from t_er));
select pg_temp.check(not exists (select 1 from app.people where id = '00000000-0000-0000-0000-0000000008e1') and not exists (select 1 from app.leads where id = '00000000-0000-0000-0000-0000000008e2')
                     and (select person_id is null from app.activities where id = '00000000-0000-0000-0000-0000000008e3')
                     and not exists (select 1 from app.email_threads where id = '00000000-0000-0000-0000-0000000008e4')
                     and exists (select 1 from app.email_threads where id = '00000000-0000-0000-0000-0000000008e5')
                     and not exists (select 1 from app.email_thread_participants where address = 'erik@slett.example')
                     and not exists (select 1 from app.email_messages where cc::text like '%erik@slett%' or from_addr = 'erik@slett.example')
                     and (select not payload ? 'email' and not payload ? 'name' and payload ? 'count' from app.events_in where source_id = 880088)
                     and (select email is null and name is null from app.members where user_id = 'u-erik')
                     and not exists (select 1 from app.changelog where record_id in ('00000000-0000-0000-0000-0000000008e1', '00000000-0000-0000-0000-0000000008e2')),
                     'approved: the person and lead are gone from every module; their own thread goes, the shared one is redacted; event payloads blanked (SEC-11, D-24)');
select pg_temp.check(exists (select 1 from app.suppressions where email_sha256 = app.email_hash('erik@slett.example') and reason = 'erasure')
                     and exists (select 1 from app.erasure_tombstones where email_sha256 = app.email_hash('erik@slett.example'))
                     and (select state = 'done' and approved_by = (select hanna from t_staff) from app.privacy_jobs where id = (select (r ->> 'job')::uuid from t_er))
                     and (select detail::text not like '%erik%' from app.audit where action = 'privacy.erased' order by id desc limit 1)
                     and exists (select 1 from app.events where kind = 'privacy.erased'), 'the address stays suppressed and tombstoned; the audit has counts, never the address');
select pg_temp.expect_detail($$insert into app.people (name, email) values ('Erik igjen', 'erik@slett.example')$$, 'forbidden', 'erased', 'an erased address is not re-created (13 months)');
select pg_temp.check((public.privacy_find('erik@slett.example') ->> 'erased')::boolean, 'the search says the address was erased');
select public.setting_set('second_admin', 'off');
-- second admin off: at once
insert into app.people (id, name, email) values ('00000000-0000-0000-0000-0000000008f1', 'Frida Fjern', 'frida@fjern.example');
create temp table t_fr as select public.privacy_erase('{"people": ["00000000-0000-0000-0000-0000000008f1"]}', null, 'frida@fjern.example') r;
select pg_temp.check((select r ->> 'state' from t_fr) = 'done'
                     and not exists (select 1 from app.people where id = '00000000-0000-0000-0000-0000000008f1'), 'second_admin off: the erasure runs at once');

-- ---------------------------------------------------------------------------
-- incidents and the 72-hour clock
select pg_temp.expect_detail($$select public.incident_save(null, jsonb_build_object('title', 'x', 'summary', repeat('a', 2001)))$$, 'invalid', 'summary', 'a summary is at most 2 000 characters');
create temp table t_inc as select public.incident_save(null, jsonb_build_object('title', 'Webhook endpoint exposed', 'summary', 'Blokkert av filteret, ingen data ute.',
                                                                                 'detected_at', now() - interval '50 hours')) i;
select pg_temp.check((select (i ->> 'notify_deadline')::timestamptz = now() - interval '50 hours' + interval '72 hours' and (i ->> 'hours_left')::int = 22
                      and (i ->> 'elapsed_pct')::int = 69 and i ->> 'state' = 'investigating' from t_inc), 'the clock runs from detection: 22 h left, 69 % elapsed');
select pg_temp.check(exists (select 1 from app.security_events where kind = 'incident_logged' and detail ->> 'incident' = (select i ->> 'id' from t_inc))
                     and exists (select 1 from app.events where kind = 'incident.logged'), 'logging it is a security event and an outbox event');
create temp table t_clk as select app.incident_clock() a;
insert into t_clk select app.incident_clock();
select pg_temp.check((select array_agg(a) from t_clk) = array[1, 0]
                     and exists (select 1 from app.notifications where key = 'security.incident_deadline' and (params ->> 'hours')::int = 48), 'at 48 h the security holders are told, once');
update app.security_incidents set detected_at = now() - interval '67 hours' where id = (select (i ->> 'id')::uuid from t_inc);
create temp table t_clk2 as select app.incident_clock() a;
select pg_temp.check((select a from t_clk2) = 1 and exists (select 1 from app.notifications where key = 'security.incident_deadline' and (params ->> 'hours')::int = 66),
                     'and again at 66 h');
select pg_temp.expect_detail(format($$select public.incident_save(%L, '{"state": "closed"}', 9)$$, (select i ->> 'id' from t_inc)), 'version_conflict', '1', 'a stale version is refused');
select pg_temp.check((select i ->> 'state' = 'closed' and i ->> 'closed_at' is not null and (i ->> 'elapsed_pct')::int = 100 and i -> 'hours_left' = 'null'::jsonb
                      from public.incident_save((select (i ->> 'id')::uuid from t_inc), '{"state": "closed"}', 1) i), 'closed: the bar is full and the clock stops');
select pg_temp.check(not exists (select 1 from app.audit where detail::text like '%Blokkert%') and not exists (select 1 from app.security_events where detail::text like '%Blokkert%')
                     and not exists (select 1 from app.notifications where params::text like '%Blokkert%'), 'the summary never reaches the audit, an event or a notification');

-- sub-processors
select pg_temp.expect_detail($$select public.subprocessor_save(null, '{"name": "Postmark", "purpose": "Email", "public": true}')$$, 'invalid', 'region', 'a public entry needs its contract region');
select public.subprocessor_save(null, '{"name": "Postmark", "purpose": "Transactional email", "region": "EU", "public": true}');
select pg_temp.check((select array_agg(x ->> 'name' order by x ->> 'name') from jsonb_array_elements(public.subprocessors_public()) x) = array['Postmark', 'Supabase'],
                     'the public list holds public entries with a region, not Vercel until its region is recorded');
select pg_temp.expect_detail(format($$select public.subprocessor_save(%L, '{"purpose": "x"}', 5)$$, (select id from app.subprocessors where name = 'Supabase')), 'version_conflict', '1', 'versioned');

-- retention
select pg_temp.check((select bool_and((x ->> 'in_force')::boolean) from jsonb_array_elements(public.retention_get()) x where x ->> 'basis' = 'platform')
                     and (select x -> 'setting' ->> 'value' from jsonb_array_elements(public.retention_get()) x where x ->> 'key' = 'meeting_recordings') = '12_months',
                     'every platform rule is in force through its job; recordings follow rec_retention');
update app.email_messages set sent_at = now() - interval '6 years' where id = (select id from app.email_messages where body_text is not null and direction = 'out' limit 1);
create temp table t_rb as select app.retention_email_bodies() n;
select pg_temp.check((select n from t_rb) >= 1 and not exists (select 1 from app.email_messages where coalesce(sent_at, received_at, created_at) < now() - interval '5 years' and body_text is not null),
                     'email bodies older than five years are emptied');
update app.tickets set closed_at = now() - interval '4 years', status = 'closed' where id = (select id from app.tickets where not is_sample order by created_at limit 1);
create temp table t_rt as select app.retention_tickets() n;
select pg_temp.check((select n from t_rt) = 1 and not exists (select 1 from app.tickets where closed_at < now() - interval '3 years')
                     and (select last_purged from app.retention_rules where key = 'tickets_closed') = 1, 'tickets closed more than three years ago go, with their messages');
select app.security_prune();
select pg_temp.check((select last_run_at = now() from app.retention_rules where key = 'login_log'), 'the login prune runs and marks its rule');

-- ---------------------------------------------------------------------------
-- the audit log search
create temp table t_aud as select public.audit_search('{"kind": "security"}', null, 5) a;
select pg_temp.check((select jsonb_array_length(a -> 'rows') = 5 and (a ->> 'next') is not null from t_aud)
                     and (select bool_and(x ->> 'kind' = 'security') from t_aud, jsonb_array_elements(a -> 'rows') x), 'filtered by kind, five a page, with a cursor');
select pg_temp.check((select bool_and((x ->> 'id')::bigint < (select (a ->> 'next')::bigint from t_aud)) from jsonb_array_elements(public.audit_search('{"kind": "security"}', (select (a ->> 'next')::bigint from t_aud), 5) -> 'rows') x),
                     'the next page continues below the cursor');
select pg_temp.check((select bool_and(x ->> 'source' = 'api') from jsonb_array_elements(public.audit_search('{"source": "api"}') -> 'rows') x)
                     and (select jsonb_array_length(public.audit_search('{"q": "Tor Lambrechts"}', null, 3) -> 'rows')) = 3, 'by source and by staff name');
select pg_temp.check((select detail -> 'filter' = '["q"]'::jsonb and detail::text not like '%Lambrechts%' from app.audit where action = 'audit.searched' order by id desc limit 1),
                     'the search is audited with filter keys only');
select app.log('record.updated', 'person', '00000000-0000-0000-0000-0000000008f1');
select pg_temp.check((public.audit_search('{"q": "record.updated"}', null, 1) -> 'rows' -> 0 -> 'target' ->> 'state') = 'removed', 'an erased target reads «(removed)»');
select pg_temp.expect_detail($$select public.audit_search('{"kind": "everything"}')$$, 'invalid', 'kind', 'an unknown kind is refused');
select pg_temp.as_s('ingrid@orgpuls.no', pg_temp.sid('ingrid@orgpuls.no'));
select pg_temp.expect_detail($$select public.audit_search('{}')$$, 'forbidden', 'global:security', 'the audit log needs global:security');

-- typed_reason applies to the security writes
select pg_temp.as_s('tor@orgpuls.no', pg_temp.sid('tor@orgpuls.no'));
select public.setting_set('typed_reason', 'on');
select pg_temp.signin('magnus@orgpuls.no', '193.69.41.7', 'magnus-pc');
select pg_temp.expect_error(format($$select public.session_revoke(%L)$$, pg_temp.sid('magnus@orgpuls.no')), 'reason_required', 'typed_reason on: a log-out needs a reason');
select public.session_revoke(pg_temp.sid('magnus@orgpuls.no'), 'stolen laptop');
select pg_temp.check((select reason from app.audit where action = 'session.revoked' order by id desc limit 1) = 'stolen laptop', 'and carries it into the audit');
select public.setting_set('typed_reason', 'off');

-- nothing a person wrote reaches the logs; no IP leaves the sealed columns
select pg_temp.check(not exists (select 1 from app.audit where detail::text ~ '(erik@slett|84\.208\.12|185\.12\.4|Hemmelig)')
                     and not exists (select 1 from app.security_events where detail::text ~ '(erik@slett|84\.208\.12|185\.12\.4)')
                     and not exists (select 1 from app.notifications where params::text ~ '(erik@slett|84\.208\.12|185\.12\.4)')
                     and not exists (select 1 from app.events where payload::text ~ '(erik@slett|84\.208\.12|185\.12\.4)'),
                     'no address, IP or message text in the audit, security events, notifications or the outbox');

rollback;
