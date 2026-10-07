-- 0043_security.sql — the Security screen (Phase 8): who is signed in and from where, the rules that refuse a sign-in,
-- the alerts a security event raises, second-factor recovery, access reviews, SSO configuration, data protection facts,
-- privacy (find, preview, export, erase), retention, the sub-processor and incident registers, and the audit log's
-- kind, source and principal. Spec: docs/crm-enrichment/specs/platform-security-mobile.md §2, §3.1–§3.3, §3.6–§3.8,
-- §3.10–§3.12, §4–§6, §8 (SEC-01..11, UF-15, SF-15, SF-27, SF-43). Design: design-reference/sentral/project/Security.dc.html.
-- Departures: docs/crm-enrichment/deviations/security-schema.md (V-P8S-*).
--
-- 0044_platform.sql runs after this one and owns the identity changes in app.me()/app.can() (§3.9). It calls
-- app.session_ok(session_id) from here for the session check, and registers mcp_access through settings_registry.hook.
--
-- No IP address is stored in clear: login_log and staff_sessions hold it sealed with a Vault key (security_ip_key), and
-- only global:security (or the person themself) reads it back. A device is a SHA-256 of a device cookie; a user agent is
-- parsed into a label and dropped. No password, TOTP secret or recovery code is stored outside Auth and Vault: recovery
-- codes are SHA-256 (0003). Nothing a customer or respondent wrote goes into app.audit, an event, a notification or a
-- security event: ids, counts and codes only. The dashboard figures are counted from login_log, staff_sessions and
-- security_events and nothing else (SEC-01 AC).
--
-- No SSO provider is connected: sso_providers models the configuration, and switching one on is refused with
-- not_connected until the Auth project reports it configured. No email provider is connected: alerts are delivered in
-- the app and the email delivery is recorded as not_connected.

-- ===========================================================================
-- the audit (§3.2): kind, source and principal; a purge path for rows older than five years
-- ===========================================================================
-- read | write | export | role | security, from the action (an audit row of a product command is a write)
create function app.audit_kind(p_action text, p_command text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case
    when p_action is null then 'write'
    when p_action ~ '\.(read|listed|viewed|searched)$' then 'read'
    when p_action ~ '\.exported$' or p_action ~ '^export\.' then 'export'
    when p_action ~ '^(staff|permission_set|group|team|access_review|mfa)\.' then 'role'
    when p_action ~ '^(security|session|security_rule|sso|recovery_codes|breakglass)\.' then 'security'
    else 'write' end
$fn$;

-- where a write came from and who made it: the gateway, the executor and the ticket actions set app.source,
-- app.principal_kind and app.principal_id for their transaction; otherwise a workflow run, the system or the web
create function app.audit_source() returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(
    (select s from (values (nullif(current_setting('app.source', true), ''))) v(s)
     where s in ('web', 'api', 'mcp', 'workflow', 'ticket', 'support_access', 'mobile', 'import', 'product', 'system')),
    case when nullif(current_setting('app.run_id', true), '') is not null then 'workflow'
         when app.me() is null then 'system' else 'web' end)
$fn$;

create function app.audit_principal_kind() returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(
    (select s from (values (nullif(current_setting('app.principal_kind', true), ''))) v(s)
     where s in ('staff', 'token', 'oauth', 'workflow', 'system', 'product')),
    case when nullif(current_setting('app.run_id', true), '') is not null then 'workflow'
         when app.me() is null then 'system' else 'staff' end)
$fn$;

create function app.audit_principal_id() returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v text := current_setting('app.principal_id', true); v_run text := current_setting('app.run_id', true);
begin
  -- plpgsql, not sql: the planner would estimate a cast of an empty setting and fail
  if v ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return v::uuid; end if;
  if v_run ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return (select r.workflow_id from app.workflow_runs r where r.id = v_run::uuid);
  end if;
  return null;
end $fn$;

-- legacy rows keep null (unknown, shown as «—»); every new row carries both, checked from here on (NOT VALID)
alter table app.audit
  add column kind text generated always as (app.audit_kind(action, command)) stored,
  add column source text check (source is null or source in ('web', 'api', 'mcp', 'workflow', 'ticket', 'support_access', 'mobile', 'import', 'product', 'system')),
  add column principal_kind text check (principal_kind is null or principal_kind in ('staff', 'token', 'oauth', 'workflow', 'system', 'product')),
  add column principal_id uuid;
alter table app.audit add constraint audit_source_set check (source is not null and principal_kind is not null) not valid;
create index audit_staff_at on app.audit (staff_id, at desc);
create index audit_account_at on app.audit (account_id, at desc);
create index audit_kind_at on app.audit (kind, at desc);

-- direct inserts (record_command, customer_action_log, the purge jobs) are stamped the same way as app.log
create function app.audit_stamp() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  new.source := coalesce(new.source, app.audit_source());
  new.principal_kind := coalesce(new.principal_kind, case when new.staff_id is not null and app.audit_principal_kind() = 'system' then 'staff'
                                                          else app.audit_principal_kind() end);
  new.principal_id := coalesce(new.principal_id, app.audit_principal_id());
  return new;
end $fn$;
create trigger audit_stamp before insert on app.audit for each row execute function app.audit_stamp();

-- app.log (0004 body) with the source and the principal
create or replace function app.log(p_action text, p_target_type text, p_target_id text, p_detail jsonb default null,
                                   p_account uuid default null)
  returns void language sql volatile security definer set search_path = ''
as $fn$
  insert into app.audit (actor, staff_id, action, target_type, target_id, detail, account_id, ok, reason, source, principal_kind, principal_id)
  values (coalesce(app.admin_email(), 'system'), app.me(), p_action, p_target_type, p_target_id, p_detail, p_account, true,
          nullif(current_setting('app.reason', true), ''), app.audit_source(), app.audit_principal_kind(), app.audit_principal_id());
$fn$;

-- audit_fixed → audit_guard: nothing may change an audit row; a row older than five years may go, and only inside the
-- audit purge (app.purging). TRUNCATE is refused. The trigger names stay (structure_invariants checks them).
create function app.audit_guard() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' and current_setting('app.purging', true) = 'on' and old.at < now() - interval '5 years' then
    return old;
  end if;
  raise exception 'the audit is append-only' using errcode = 'insufficient_privilege';
end $fn$;
drop trigger audit_fixed on app.audit;
create trigger audit_fixed before update or delete on app.audit for each row execute function app.audit_guard();
drop trigger audit_no_truncate on app.audit;
create trigger audit_no_truncate before truncate on app.audit for each statement execute function app.audit_guard();

-- ===========================================================================
-- tables (§3.3)
-- ===========================================================================
-- every sign-in attempt; unknown addresses by hash only; purged after 60 days
create table app.login_log (
  id           bigint generated always as identity primary key,
  at           timestamptz not null default now(),
  staff_id     uuid references app.admins (id) on delete cascade,
  email_sha256 bytea not null,
  session_id   uuid,
  outcome      text not null check (outcome in ('success', 'failed_password', 'failed_mfa', 'blocked_ip', 'blocked_time', 'blocked_inactive',
                                                'blocked_method', 'rate_limited')),
  method       text check (method is null or method in ('password_totp', 'google_totp', 'microsoft_totp', 'recovery_code')),
  ip_sealed    bytea,                                   -- pgp_sym_encrypt with the Vault key security_ip_key; never in clear
  device_label text check (device_label is null or char_length(device_label) <= 120),
  device_hash  bytea,
  city         text check (city is null or char_length(city) <= 80),
  country      text check (country is null or country ~ '^[A-Z]{2}$'),
  new_device   boolean not null default false,
  new_location boolean not null default false
);
create index login_log_staff_at on app.login_log (staff_id, at desc);
create index login_log_at on app.login_log (at desc);
create index login_log_email_at on app.login_log (email_sha256, at desc);

-- a sign-in's session (= auth.sessions.id = the JWT claim session_id); ended rows purged 60 days after they end
create table app.staff_sessions (
  session_id     uuid primary key,
  staff_id       uuid not null references app.admins (id) on delete cascade,
  created_at     timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  ip_sealed      bytea,
  last_ip_sealed bytea,
  device_label   text check (device_label is null or char_length(device_label) <= 120),
  device_hash    bytea,
  city           text check (city is null or char_length(city) <= 80),
  country        text check (country is null or country ~ '^[A-Z]{2}$'),
  method         text not null check (method in ('password_totp', 'google_totp', 'microsoft_totp', 'recovery_code')),
  ended_at       timestamptz,
  end_reason     text check (end_reason is null or end_reason in ('signed_out', 'idle_timeout', 'forced', 'ip_rule', 'time_rule', 'deactivated',
                                                                  'mfa_reset', 'recovery_code', 'expired')),
  ended_by       uuid references app.admins (id) on delete set null,
  check ((ended_at is null) = (end_reason is null))
);
create index staff_sessions_open on app.staff_sessions (staff_id) where ended_at is null;

-- new-device and new-location detection outlives the 60-day log; no IP
create table app.staff_devices (
  staff_id      uuid not null references app.admins (id) on delete cascade,
  device_hash   bytea not null,
  label         text check (label is null or char_length(label) <= 120),
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  primary key (staff_id, device_hash)
);
create table app.staff_locations (
  staff_id      uuid not null references app.admins (id) on delete cascade,
  country       text not null check (country ~ '^[A-Z]{2}$'),
  city          text not null check (char_length(city) between 1 and 80),
  first_seen_at timestamptz not null default now(),
  primary key (staff_id, country, city)
);

-- IP ranges and sign-in time windows (Europe/Oslo, D-04); archived, never deleted, so the audit can name them
create table app.security_rules (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('ip_range', 'time_window')),
  cidr        cidr,
  days        smallint[] check (days is null or (cardinality(days) between 1 and 7 and days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[])),
  starts      time,
  ends        time,
  label       text not null check (char_length(btrim(label)) between 1 and 80),
  created_by  uuid references app.admins (id) on delete set null,
  created_at  timestamptz not null default now(),
  archived_at timestamptz,
  version     int not null default 1,
  check ((kind = 'ip_range') = (cidr is not null)),
  check ((kind = 'time_window') = (days is not null and starts is not null and ends is not null)),
  check (starts is distinct from ends or starts is null)
);

-- what happened that security cares about; ids and counts only. Not the outbox: never webhookable (§3.10)
create table app.security_events (
  id               bigint generated always as identity primary key,
  at               timestamptz not null default now(),
  kind             text not null check (kind in ('new_device', 'new_location', 'failed_logins', 'account_locked', 'user_invited', 'password_reset',
                                                 'large_export', 'large_delete', 'session_revoked', 'mfa_reset', 'ip_blocked', 'time_blocked',
                                                 'api_token_old', 'webhook_banned', 'incident_logged', 'admin_login')),
  severity         text not null check (severity in ('info', 'low', 'high', 'critical')),
  subject_staff_id uuid references app.admins (id) on delete set null,
  actor_id         uuid references app.admins (id) on delete set null,
  detail           jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object'),
  alert_state      text not null default 'none' check (alert_state in ('none', 'queued', 'sent', 'digest', 'failed'))
);
create index security_events_at on app.security_events (at desc);
create index security_events_alert on app.security_events (id) where alert_state in ('queued', 'digest');

-- nobody changes what an event says; the alert state moves, and a removed admin's id may empty itself (FK)
create function app.security_event_guard() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if current_setting('app.purging', true) = 'on' then return old; end if;
    raise exception 'security events are append-only' using errcode = 'insufficient_privilege';
  end if;
  if new.id <> old.id or new.at <> old.at or new.kind <> old.kind or new.severity <> old.severity or new.detail <> old.detail
     or (new.subject_staff_id is distinct from old.subject_staff_id and new.subject_staff_id is not null)
     or (new.actor_id is distinct from old.actor_id and new.actor_id is not null) then
    raise exception 'security events are append-only' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $fn$;
create trigger security_event_guard before update or delete on app.security_events for each row execute function app.security_event_guard();

-- one alert per trigger, channel and recipient (SEC-02 AC); the Slack route has no recipient
create table app.security_alert_deliveries (
  event_id     bigint not null references app.security_events (id) on delete cascade,
  channel      text not null check (channel in ('in_app', 'email', 'slack')),
  recipient_id uuid references app.admins (id) on delete cascade,
  sent_at      timestamptz,
  status       text not null check (status in ('queued', 'sent', 'failed', 'not_connected')),
  unique nulls not distinct (event_id, channel, recipient_id)
);

-- the named recipients when security_alert_recipients = list
create table app.security_alert_recipients (
  staff_id uuid primary key references app.admins (id) on delete cascade,
  added_by uuid references app.admins (id) on delete set null,
  added_at timestamptz not null default now()
);

create table app.access_reviews (
  id           uuid primary key default gen_random_uuid(),
  due_on       date not null,
  started_at   timestamptz not null default now(),
  started_by   uuid references app.admins (id) on delete set null,
  completed_at timestamptz,
  completed_by uuid references app.admins (id) on delete set null
);
create unique index access_reviews_one_open on app.access_reviews ((true)) where completed_at is null;
create table app.access_review_items (
  review_id         uuid not null references app.access_reviews (id) on delete cascade,
  staff_id          uuid not null references app.admins (id) on delete cascade,
  permission_set_id uuid,                                -- snapshot at start
  group_id          uuid,
  decision          text check (decision is null or decision in ('keep', 'change', 'deactivate')),
  decided_by        uuid references app.admins (id) on delete set null,
  decided_at        timestamptz,
  primary key (review_id, staff_id)
);

-- Google and Microsoft sign-in (D-31): configuration only; credentials are the Auth project's, never a row
create table app.sso_providers (
  provider        text primary key check (provider in ('google', 'microsoft')),
  enabled         boolean not null default false,
  allowed_domains text[] not null default '{}' check (cardinality(allowed_domains) <= 20),
  configured      boolean not null default false,       -- reported by the Auth project (worker_sso_configured)
  updated_by      uuid references app.admins (id) on delete set null,
  updated_at      timestamptz,
  check (not enabled or configured)
);
insert into app.sso_providers (provider) values ('google'), ('microsoft');

-- when a password last changed (password_expiry); dates only, never a hash (Q4)
create table app.password_changes (
  staff_id   uuid not null references app.admins (id) on delete cascade,
  changed_at timestamptz not null default now(),
  primary key (staff_id, changed_at)
);

-- recovery-code attempts, for the 5-per-hour limit; pruned daily
create table app.recovery_attempts (
  staff_id uuid not null references app.admins (id) on delete cascade,
  at       timestamptz not null default now()
);
create index recovery_attempts_staff on app.recovery_attempts (staff_id, at desc);

-- backups and PITR (the worker, from the Management API) and restore tests (staff)
create table app.ops_checks (
  id          bigint generated always as identity primary key,
  kind        text not null check (kind in ('backup', 'pitr', 'restore_test')),
  at          timestamptz not null,
  ok          boolean not null,
  rpo_minutes int check (rpo_minutes is null or rpo_minutes >= 0),
  rto_minutes int check (rto_minutes is null or rto_minutes >= 0),
  detail      jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object'),
  recorded_by uuid references app.admins (id) on delete set null,     -- null = the worker
  unique (kind, at)
);
create function app.ops_check_guard() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' and new.id = old.id and new.kind = old.kind and new.at = old.at and new.ok = old.ok
     and new.rpo_minutes is not distinct from old.rpo_minutes and new.rto_minutes is not distinct from old.rto_minutes
     and new.detail = old.detail and new.recorded_by is null and old.recorded_by is not null then
    return new;                                        -- the recorder's account was removed (FK)
  end if;
  raise exception 'an operations check is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger ops_check_guard before update or delete on app.ops_checks for each row execute function app.ops_check_guard();

-- reviewed facts the Data protection tab states, so the copy is a row and not a component literal
create table app.platform_facts (
  key    text primary key check (key ~ '^[a-z_]{2,40}$'),
  value  text not null check (char_length(value) between 1 and 200),
  source text not null check (char_length(source) between 1 and 200)
);
insert into app.platform_facts (key, value, source) values
  ('db_region', 'eu-central-1', 'D-35; supabase project region'),
  ('hosting_region_label', 'EU · Frankfurt (eu-central-1)', 'D-35'),
  ('encryption_in_transit', 'HTTPS only · HSTS max-age 2 years, preload', 'next.config.ts headers'),
  ('encryption_at_rest', 'AES-256 (Supabase) · provider tokens in Vault', 'Supabase platform; migrations 0002, 0020, 0021'),
  ('isolation', 'CRM data separated from survey data: separate project, no survey tables', '0001; D-19; structure_invariants.sql'),
  ('rpo_minutes', '60', 'D-35'),
  ('rto_minutes', '240', 'D-35');

-- incidents and the 72-hour clock (GDPR art. 33). timestamptz + interval is only stable (a day or month depends on the
-- zone); 72 hours does not, so this wrapper is honestly immutable and can feed the generated column
create function app.plus_72h(p_at timestamptz) returns timestamptz
  language sql immutable set search_path = ''
as $fn$ select p_at + interval '72 hours' $fn$;
create table app.security_incidents (
  id              uuid primary key default gen_random_uuid(),
  title           text not null check (char_length(btrim(title)) between 1 and 200),
  summary         text not null default '' check (char_length(summary) <= 2000),
  detected_at     timestamptz not null,
  logged_at       timestamptz not null default now(),
  logged_by       uuid references app.admins (id) on delete set null,
  personal_data   boolean not null default false,
  state           text not null default 'investigating' check (state in ('investigating', 'assessed_not_notifiable', 'notified', 'closed')),
  notify_deadline timestamptz generated always as (app.plus_72h(detected_at)) stored,
  notified_at     timestamptz,
  notified_ref    text check (notified_ref is null or char_length(notified_ref) <= 120),
  closed_at       timestamptz,
  ticket_id       uuid references app.tickets (id) on delete set null,
  notice_48_at    timestamptz,
  notice_66_at    timestamptz,
  version         int not null default 1,
  check (state <> 'notified' or notified_at is not null),
  check (state <> 'closed' or closed_at is not null)
);

-- the sub-processor register: only providers in use, with the region in their contract (null = not yet recorded)
create table app.subprocessors (
  id           uuid primary key default gen_random_uuid(),
  name         text not null unique check (char_length(btrim(name)) between 1 and 80),
  purpose      text not null check (char_length(btrim(purpose)) between 1 and 200),
  region       text check (region is null or char_length(btrim(region)) between 1 and 60),
  in_use_since date not null,
  removed_at   date,
  public       boolean not null default true,
  ord          int not null default 0,
  version      int not null default 1
);
insert into app.subprocessors (name, purpose, region, in_use_since, public, ord) values
  ('Supabase', 'Database, auth, storage', 'EU · Frankfurt (eu-central-1)', date '2026-10-06', true, 10),
  ('Vercel', 'Hosting', null, date '2026-10-06', false, 20);

-- retention: each platform rule names the cron job that enforces it (cron.job.jobname)
create table app.retention_rules (
  key         text primary key check (key ~ '^[a-z_]{2,40}$'),
  keep        interval,
  basis       text not null check (basis in ('platform', 'product')),
  job_key     text check (job_key is null or job_key ~ '^[a-z0-9_-]{2,60}$'),
  setting_key text references app.settings_registry (key),      -- the register key that sets the period, when one does
  last_run_at timestamptz,
  last_purged bigint,
  ord         int not null default 0,
  check (basis = 'product' or (keep is not null and job_key is not null))
);

-- export and erasure jobs: subjects by id, never an email
create table app.privacy_jobs (
  id             uuid primary key default gen_random_uuid(),
  request_id     uuid references app.privacy_requests (id) on delete set null,
  kind           text not null check (kind in ('export', 'erasure')),
  subject        jsonb not null check (jsonb_typeof(subject) = 'object'),
  preview        jsonb not null check (jsonb_typeof(preview) = 'object'),
  state          text not null default 'previewed' check (state in ('previewed', 'approved', 'running', 'done', 'failed')),
  storage_path   text check (storage_path is null or storage_path ~ '^privacy/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,80}$'),
  url_expires_at timestamptz,
  created_by     uuid references app.admins (id) on delete set null,
  approved_by    uuid references app.admins (id) on delete set null,
  created_at     timestamptz not null default now(),
  finished_at    timestamptz,
  error          text check (error is null or char_length(error) <= 300),
  check (approved_by is null or approved_by <> created_by)
);

-- an erased address, by hash, for 13 months (Q9): no import, enrichment or intake re-creates the person meanwhile
create table app.erasure_tombstones (
  email_sha256 bytea primary key,
  erased_at    timestamptz not null default now(),
  request_id   uuid
);

-- ===========================================================================
-- settings (§3.6) and the per-key hook
-- ===========================================================================
alter table app.settings_registry add column hook text check (hook is null or hook ~ '^app\.[a-z_]+$');

update app.settings_registry set options = array['off', 'immediate', 'digest'], grp = 'security_alerts', applies_to = 'SEC-02' where key = 'login_alerts';
update app.setting_values set value = 'immediate' where key = 'login_alerts' and value = 'on';
update app.settings_registry set applies_to = 'SEC-03, SEC-06', hook = 'app.ip_allowlist_guard' where key = 'ip_allowlist';
update app.settings_registry set applies_to = applies_to || ', SEC-11' where key = 'second_admin' and applies_to not like '%SEC-11%';

insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord, hook) values
  ('signin_hours', 'security', array['off', 'on'], 'off', 'platform', 'SEC-03', false, null, 230, 'app.signin_hours_guard'),
  ('password_expiry', 'security', array['never', 'days'], 'never', 'platform', 'SEC-03', false, 'days', 240, null),
  ('password_reuse', 'security', array['off', 'number'], 'off', 'platform', 'SEC-03', false, 'number', 250, 'app.password_reuse_guard'),
  ('access_review_interval', 'security', array['quarterly', 'half_yearly'], 'quarterly', 'platform', 'SEC-09, SEC-11', false, null, 260, null),
  ('alert_new_device', 'security_alerts', array['off', 'immediate', 'digest'], 'off', 'platform', 'SEC-02', false, null, 310, null),
  ('alert_user_invited', 'security_alerts', array['off', 'immediate', 'digest'], 'immediate', 'platform', 'SEC-02', false, null, 320, null),
  ('alert_failed_logins', 'security_alerts', array['off', 'immediate', 'digest'], 'immediate', 'platform', 'SEC-02', false, null, 330, null),
  ('alert_failed_logins_count', 'security_alerts', array['source_value', 'custom'], 'source_value', 'platform', 'SEC-02', false, 'custom', 335, null),
  ('alert_password_reset', 'security_alerts', array['off', 'immediate', 'digest'], 'immediate', 'platform', 'SEC-02', false, null, 340, null),
  ('alert_large_export', 'security_alerts', array['off', 'immediate', 'digest'], 'immediate', 'platform', 'SEC-02', false, null, 350, null),
  ('alert_large_export_rows', 'security_alerts', array['source_value', 'custom'], 'source_value', 'platform', 'SEC-02', false, 'custom', 355, null),
  ('alert_digest_time', 'security_alerts', array['00:00', '01:00', '02:00', '03:00', '04:00', '05:00', '06:00', '07:00', '08:00', '09:00', '10:00', '11:00',
                                                 '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00', '19:00', '20:00', '21:00', '22:00', '23:00'],
   '08:00', 'platform', 'SEC-02', false, null, 360, null),
  ('security_alert_recipients', 'security_alerts', array['role', 'list'], 'role', 'platform', 'SEC-02', false, null, 370, null);

-- a number a register key carries when its numeric option is chosen, else the source value
create function app.setting_number(p_key text, p_source numeric) returns numeric
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select v.value_number from app.setting_values v join app.settings_registry r on r.key = v.key
                   where v.key = p_key and v.scope_id = '' and v.value = r.numeric_option), p_source)
$fn$;

-- setting_set (0005 body) with the key's hook, called before the write, and global:security for the security keys
create or replace function public.setting_set(p_key text, p_value text, p_scope_id text default '', p_number numeric default null)
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
  if r.grp in ('security', 'security_alerts') then perform app.require('global', 'security'); end if;
  v_old := app.setting(p_key, p_scope_id);
  if r.hook is not null then
    execute format('select %s($1, $2, $3, $4)', r.hook) using p_key, v_old, p_value, coalesce(p_scope_id, '');
  end if;
  insert into app.setting_values (key, scope_id, value, value_number, updated_by, updated_at)
  values (p_key, coalesce(p_scope_id, ''), p_value, p_number, v_me, now())
  on conflict (key, scope_id) do update set value = excluded.value, value_number = excluded.value_number,
    updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  perform app.log('setting.changed', 'setting', p_key,
                  jsonb_build_object('key', p_key, 'scope_id', coalesce(p_scope_id, ''), 'from', v_old, 'to', p_value));
  return jsonb_build_object('key', p_key, 'value', p_value);
end $fn$;

-- ===========================================================================
-- helpers: identity, the second factor, IPs, rules
-- ===========================================================================
-- the caller's session (JWT claim session_id), when there is one
create function app.current_session() returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v text := auth.jwt() ->> 'session_id';
begin
  if v ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return v::uuid; end if;
  return null;
end $fn$;

-- a second factor within the last N minutes (JWT amr), else forbidden/fresh_mfa: the UI asks for the code again
create function app.require_fresh_mfa(p_minutes int default 10) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_amr jsonb := auth.jwt() -> 'amr';
begin
  if jsonb_typeof(v_amr) = 'array' and exists (
       select 1 from jsonb_array_elements(v_amr) a
       where a ->> 'method' = 'totp' and (a ->> 'timestamp') ~ '^\d{9,11}$'
         and to_timestamp((a ->> 'timestamp')::bigint) >= now() - make_interval(mins => greatest(coalesce(p_minutes, 10), 1))) then
    return;
  end if;
  raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'fresh_mfa';
end $fn$;

-- does this staff member hold global:security?
create function app.staff_has_security(p_staff uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select ps.kind = 'admin' or 'global:security' = any (ps.rights)
                   from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = p_staff), false)
$fn$;

-- a verified authenticator factor (D-11: TOTP only)
create function app.staff_mfa_verified(p_email text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from auth.mfa_factors f join auth.users u on u.id = f.user_id
                 where lower(u.email) = lower(p_email) and f.factor_type = 'totp' and f.status = 'verified')
$fn$;

-- the IP key: created on first use (as the web salt, 0041), read only through these functions
create function app.ip_key(p_create boolean default false) returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v text;
begin
  select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'security_ip_key';
  if v is null and p_create then
    perform pg_advisory_xact_lock(hashtext('security_ip_key'));
    select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'security_ip_key';
    if v is null then
      perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'security_ip_key',
                                  'Seals staff sign-in IP addresses (0043): read by the security functions only.');
      select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'security_ip_key';
    end if;
  end if;
  return v;
end $fn$;

create function app.ip_seal(p_ip inet) returns bytea
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_ip is null then return null; end if;
  return extensions.pgp_sym_encrypt(host(p_ip), app.ip_key(true));
end $fn$;

create function app.ip_open(p_sealed bytea) returns inet
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_key text;
begin
  if p_sealed is null then return null; end if;
  v_key := app.ip_key(false);
  if v_key is null then return null; end if;
  return extensions.pgp_sym_decrypt(p_sealed, v_key)::inet;
exception when others then
  return null;
end $fn$;

-- «Chrome on macOS» from a user agent; the user agent itself is not kept
create function app.device_label(p_ua text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case when nullif(btrim(p_ua), '') is null then null else
    concat_ws(' on ',
      case when p_ua ~ 'Edg/' then 'Edge' when p_ua ~ 'Firefox/' then 'Firefox' when p_ua ~ 'Chrome/' then 'Chrome'
           when p_ua ~ 'Safari/' then 'Safari' else 'Browser' end,
      case when p_ua ~ 'iPhone' then 'iPhone' when p_ua ~ 'iPad' then 'iPad' when p_ua ~ 'Android' then 'Android'
           when p_ua ~ 'Windows' then 'Windows' when p_ua ~ 'Mac OS X|Macintosh' then 'macOS' when p_ua ~ 'Linux' then 'Linux' end) end
$fn$;

create function app.ip_ranges() returns cidr[]
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(array_agg(r.cidr order by r.created_at), '{}') from app.security_rules r where r.kind = 'ip_range' and r.archived_at is null
$fn$;

create function app.ip_match(p_ip inet, p_ranges cidr[]) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select p_ip is not null and exists (select 1 from unnest(p_ranges) r where p_ip <<= r)
$fn$;

-- a time window in the platform time zone; a window that ends before it starts runs overnight from its start day
create function app.window_match(p_at timestamptz, p_days smallint[], p_starts time, p_ends time) returns boolean
  language sql stable set search_path = ''
as $fn$
  select case when p_starts < p_ends
              then extract(isodow from l)::smallint = any (p_days) and l::time >= p_starts and l::time < p_ends
              else (extract(isodow from l)::smallint = any (p_days) and l::time >= p_starts)
                or (extract(isodow from l - interval '1 day')::smallint = any (p_days) and l::time < p_ends) end
  from (select p_at at time zone 'Europe/Oslo' as l) x
$fn$;

-- the current windows as jsonb, or a hypothetical set (preview)
create function app.time_windows() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('days', to_jsonb(r.days), 'starts', r.starts, 'ends', r.ends) order by r.created_at), '[]'::jsonb)
  from app.security_rules r where r.kind = 'time_window' and r.archived_at is null
$fn$;

create function app.windows_match(p_at timestamptz, p_windows jsonb) returns boolean
  language sql stable set search_path = ''
as $fn$
  select exists (select 1 from jsonb_array_elements(coalesce(p_windows, '[]'::jsonb)) w
                 where app.window_match(p_at, array(select jsonb_array_elements_text(w -> 'days'))::smallint[], (w ->> 'starts')::time, (w ->> 'ends')::time))
$fn$;

-- would the rules let this IP / this moment sign in?
create function app.ip_allowed(p_ip inet) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.setting('ip_allowlist') <> 'on' or app.ip_match(p_ip, app.ip_ranges())
$fn$;

create function app.time_allowed(p_at timestamptz) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.setting('signin_hours') <> 'on' or app.windows_match(p_at, app.time_windows())
$fn$;

-- the caller's own current IP, as the middleware last reported it for this session
create function app.my_ip() returns inet
  language sql volatile security definer set search_path = ''
as $fn$
  select app.ip_open(s.last_ip_sealed) from app.staff_sessions s
  where s.session_id = app.current_session() and s.staff_id = app.me() and s.ended_at is null
$fn$;

-- is this session still good? For 0044's app.me() (§3.9): ended, idle (session_idle) or outside the sign-in hours
-- (signin_hours) is not. A missing row is allowed only in the two minutes after sign-in, before worker_login_event has
-- written it. IP rules are enforced when the middleware reports the session (worker_session_seen) and when a rule or
-- the allowlist changes (app.sessions_enforce_ip), because the IP is sealed and this is one primary-key lookup.
create function app.session_ok(p_session uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select case when p_session is null then false else coalesce(
    (select s.ended_at is null
            and (app.setting('session_idle') <> 'on_30' or s.last_seen_at >= now() - interval '30 minutes')
            and app.time_allowed(now())
     from app.staff_sessions s where s.session_id = p_session),
    exists (select 1 from auth.sessions a where a.id = p_session and a.created_at > now() - interval '2 minutes')) end
$fn$;

-- end a session: the row says why and by whom, and the Auth session goes with its refresh tokens
create function app.session_end(p_session uuid, p_reason text, p_by uuid default null) returns boolean
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.staff_sessions set ended_at = now(), end_reason = p_reason, ended_by = p_by where session_id = p_session and ended_at is null;
  if not found then return false; end if;
  delete from auth.sessions where id = p_session;
  return true;
end $fn$;

-- an ended session stays ended
create function app.staff_session_guard() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if old.ended_at is not null and (new.ended_at is distinct from old.ended_at or new.end_reason is distinct from old.end_reason
                                   or new.session_id <> old.session_id or new.staff_id <> old.staff_id) then
    raise exception 'an ended session stays ended' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $fn$;
create trigger staff_session_guard before update on app.staff_sessions for each row execute function app.staff_session_guard();

-- the login log is written once
create function app.login_log_guard() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  raise exception 'the login log is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger login_log_guard before update on app.login_log for each row execute function app.login_log_guard();

-- every open session outside the IP rules ends (a rule or the allowlist changed)
create function app.sessions_enforce_ip(p_ranges cidr[] default null) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s record; v_ranges cidr[] := coalesce(p_ranges, app.ip_ranges()); n int := 0;
begin
  for s in select session_id, last_ip_sealed from app.staff_sessions where ended_at is null for update skip locked loop
    if not app.ip_match(app.ip_open(s.last_ip_sealed), v_ranges) then
      if app.session_end(s.session_id, 'ip_rule', app.me()) then n := n + 1; end if;
    end if;
  end loop;
  return n;
end $fn$;

-- ===========================================================================
-- the register hooks
-- ===========================================================================
-- switching the allowlist on is tightening (fresh MFA) and must not lock the caller out: their own current IP must be
-- inside a rule. Every other open session outside the rules ends.
create function app.ip_allowlist_guard(p_key text, p_old text, p_new text, p_scope_id text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_new = 'on' and p_old is distinct from 'on' then
    perform app.require_fresh_mfa(10);
    if not app.ip_match(app.my_ip(), app.ip_ranges()) then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self_lockout';
    end if;
    perform app.sessions_enforce_ip();
  end if;
end $fn$;

-- switching sign-in hours on: fresh MFA, and now must be inside a window (the sessions outside end on their next check)
create function app.signin_hours_guard(p_key text, p_old text, p_new text, p_scope_id text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_new = 'on' and p_old is distinct from 'on' then
    perform app.require_fresh_mfa(10);
    if not app.windows_match(now(), app.time_windows()) then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self_lockout';
    end if;
  end if;
end $fn$;

-- password reuse needs a password history and a password-change flow that do not exist (Q4)
create function app.password_reuse_guard(p_key text, p_old text, p_new text, p_scope_id text) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if p_new <> 'off' then
    raise exception 'not_available' using errcode = 'invalid_parameter_value', detail = 'password_history';
  end if;
end $fn$;

-- ===========================================================================
-- security events and alerts (SEC-02)
-- ===========================================================================
-- the register key that decides a kind's alert
create function app.security_alert_key(p_kind text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case p_kind when 'new_device' then 'alert_new_device' when 'new_location' then 'alert_new_device'
                     when 'user_invited' then 'alert_user_invited' when 'failed_logins' then 'alert_failed_logins'
                     when 'password_reset' then 'alert_password_reset' when 'large_export' then 'alert_large_export'
                     when 'large_delete' then 'alert_large_export' when 'admin_login' then 'login_alerts' end
$fn$;

create function app.security_event(p_kind text, p_severity text, p_subject uuid, p_actor uuid, p_detail jsonb default '{}'::jsonb)
  returns bigint language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_key text := app.security_alert_key(p_kind); v_mode text; v_id bigint;
begin
  v_mode := case when v_key is null then 'off' else app.setting(v_key) end;
  insert into app.security_events (kind, severity, subject_staff_id, actor_id, detail, alert_state)
  values (p_kind, p_severity, p_subject, p_actor, coalesce(p_detail, '{}'::jsonb),
          case v_mode when 'immediate' then 'queued' when 'digest' then 'digest' else 'none' end)
  returning id into v_id;
  return v_id;
end $fn$;

-- who receives alerts: the named list (when set and not empty) or every active staff member holding global:security
create function app.security_recipients() returns setof uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if app.setting('security_alert_recipients') = 'list'
     and exists (select 1 from app.security_alert_recipients r join app.admins a on a.id = r.staff_id where a.active and not a.is_sample) then
    return query select a.id from app.security_alert_recipients r join app.admins a on a.id = r.staff_id
                 where a.active and not a.is_sample and app.staff_has_security(a.id) order by a.id;
  else
    return query select a.id from app.admins a where a.active and not a.is_sample and app.staff_has_security(a.id) order by a.id;
  end if;
end $fn$;

-- one event out: in-app now; email recorded as queued for the mailer, or not_connected; admin logins also to Slack
create function app.security_deliver(p_event bigint, p_digest boolean default false) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.security_events; r uuid; n int := 0; v_email text := case when app.connected('email') then 'queued' else 'not_connected' end;
begin
  select * into e from app.security_events where id = p_event for update;
  if not found or e.alert_state not in ('queued', 'digest') then return 0; end if;
  for r in select * from app.security_recipients() loop
    insert into app.security_alert_deliveries (event_id, channel, recipient_id, sent_at, status) values (e.id, 'in_app', r, now(), 'sent')
    on conflict do nothing;
    if found then
      n := n + 1;
      if not p_digest then
        perform app.notify(r, 'security', 'security.' || e.kind,
                           jsonb_build_object('event', e.id, 'staff', e.subject_staff_id, 'actor', e.actor_id) || (e.detail - 'event'), '/security');
      end if;
    end if;
    insert into app.security_alert_deliveries (event_id, channel, recipient_id, sent_at, status) values (e.id, 'email', r, null, v_email)
    on conflict do nothing;
  end loop;
  if e.kind = 'admin_login' then
    insert into app.security_alert_deliveries (event_id, channel, recipient_id, sent_at, status)
    values (e.id, 'slack', null, null, case when app.connected('slack') then 'queued' else 'not_connected' end) on conflict do nothing;
  end if;
  update app.security_events set alert_state = 'sent' where id = e.id;
  return n;
end $fn$;

-- job security_alerts (every minute): the queued events
create function app.security_alerts_run() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v bigint; n int := 0;
begin
  for v in select id from app.security_events where alert_state = 'queued' order by id limit 200 for update skip locked loop
    perform app.security_deliver(v); n := n + 1;
  end loop;
  return n;
end $fn$;

-- job security_digest (every 15 minutes; acts once a day in the hour alert_digest_time names, Europe/Oslo)
create function app.security_digest_due(p_now timestamptz default now()) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_local timestamp := p_now at time zone 'Europe/Oslo';
  v_day text := (p_now at time zone 'Europe/Oslo')::date::text;
  v_ids bigint[]; v_kinds jsonb; r uuid; v bigint;
begin
  if extract(hour from v_local)::int <> split_part(app.setting('alert_digest_time'), ':', 1)::int then return 0; end if;
  if exists (select 1 from app.audit where action = 'security.digest_sent' and detail ->> 'day' = v_day) then return 0; end if;
  select array_agg(id order by id) into v_ids from app.security_events where alert_state = 'digest';
  if v_ids is null then return 0; end if;
  select jsonb_object_agg(kind, n) into v_kinds from (select kind, count(*) n from app.security_events where id = any (v_ids) group by kind) k;
  for r in select * from app.security_recipients() loop
    perform app.notify(r, 'security', 'security.digest', jsonb_build_object('count', cardinality(v_ids), 'kinds', v_kinds, 'day', v_day), '/security');
  end loop;
  foreach v in array v_ids loop perform app.security_deliver(v, true); end loop;
  perform app.log('security.digest_sent', null, null, jsonb_build_object('day', v_day, 'events', cardinality(v_ids)));
  return cardinality(v_ids);
end $fn$;

-- the outbox side of SEC-02: large exports (export.created, 0011/0038) and bulk deletes (one rec_bulk = one actor, one
-- transaction time). The subscriber turns them into security events; app.security_alerts_run delivers them.
create function app.sub_security_alerts(ev app.events) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_rows numeric; v_n int; v_limit numeric := app.setting_number('alert_large_export_rows', 1000);
begin
  if ev.is_sample then return; end if;
  if ev.kind = 'export.created' then
    v_rows := case when (ev.payload ->> 'rows') ~ '^\d{1,9}$' then (ev.payload ->> 'rows')::numeric end;
    if v_rows >= v_limit and not exists (select 1 from app.security_events where kind = 'large_export' and detail ->> 'event' = ev.id::text) then
      perform app.security_event('large_export', 'low', null, ev.actor_id,
                                 jsonb_build_object('event', ev.id, 'rows', v_rows, 'entity', ev.subject_type, 'threshold', v_limit));
    end if;
  elsif ev.kind ~ '\.deleted$' and ev.actor_id is not null then
    select count(*) into v_n from app.events e where e.kind ~ '\.deleted$' and e.actor_id = ev.actor_id and e.created_at = ev.created_at;
    if v_n >= v_limit and not exists (select 1 from app.security_events where kind = 'large_delete' and actor_id = ev.actor_id
                                      and detail ->> 'at' = ev.created_at::text) then
      perform app.security_event('large_delete', 'high', null, ev.actor_id,
                                 jsonb_build_object('event', ev.id, 'rows', v_n, 'entity', ev.subject_type, 'at', ev.created_at::text, 'threshold', v_limit));
    end if;
  end if;
end $fn$;

insert into app.event_subscribers (name, fn, ord) values ('security_alerts', 'app.sub_security_alerts', 70);
-- the subscriber starts at the head of the outbox: old exports are not news
insert into app.event_cursors (subscriber, last_event_id) values ('security_alerts', coalesce((select max(id) from app.events), 0));

-- an invitation and a deactivation: the invite is a security event; a deactivated person's sessions end at once (SF-43.2)
create function app.admins_security_watch() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare s uuid;
begin
  if tg_op = 'INSERT' then
    -- an invitation is a staff member's act (staff_save); rows written outside a signed-in call (the fixture) are not invites
    if not new.is_sample and app.me() is not null then
      perform app.security_event('user_invited', 'info', new.id, app.me(),
                                 jsonb_build_object('permission_set', new.permission_set_id));
    end if;
  elsif old.active and not new.active then
    for s in select session_id from app.staff_sessions where staff_id = new.id and ended_at is null loop
      perform app.session_end(s, 'deactivated', app.me());
    end loop;
  end if;
  return null;
end $fn$;
create trigger admins_security_watch after insert or update of active on app.admins for each row execute function app.admins_security_watch();

-- an erased address is not re-created within 13 months, by any path (import, enrichment, form intake, staff)
create function app.person_tombstoned() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if new.email is not null and not new.is_sample and (tg_op = 'INSERT' or new.email is distinct from old.email)
     and exists (select 1 from app.erasure_tombstones t where t.email_sha256 = app.email_hash(new.email)) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'erased';
  end if;
  return new;
end $fn$;
create trigger person_tombstoned before insert or update of email on app.people for each row execute function app.person_tombstoned();

-- ===========================================================================
-- sign-in (service role): the sign-in action and the middleware report; the database decides (SF-27, SEC-03)
-- ===========================================================================
-- p_input: {email, outcome: success|failed_password|failed_mfa|rate_limited, session_id, method, ip, device_id,
-- device_label | user_agent, city, country}. Returns {allowed, reason, must_change_password}. A refused sign-in's Auth
-- session is deleted here.
create function public.worker_login_event(p_input jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_email   text := lower(btrim(coalesce(p_input ->> 'email', '')));
  v_outcome text := coalesce(nullif(p_input ->> 'outcome', ''), 'success');
  v_method  text := nullif(p_input ->> 'method', '');
  v_ip      inet;
  v_session uuid;
  v_staff   app.admins;
  v_dev     bytea;
  v_label   text := left(coalesce(nullif(btrim(p_input ->> 'device_label'), ''), app.device_label(p_input ->> 'user_agent')), 120);
  v_city    text := left(nullif(btrim(p_input ->> 'city'), ''), 80);
  v_country text := upper(nullif(btrim(p_input ->> 'country'), ''));
  v_new_dev boolean := false;
  v_new_loc boolean := false;
  v_must    boolean := false;
  v_streak  int;
begin
  if jsonb_typeof(p_input) is distinct from 'object' or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'email';
  end if;
  if v_outcome not in ('success', 'failed_password', 'failed_mfa', 'rate_limited') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'outcome';
  end if;
  if v_method is not null and v_method not in ('password_totp', 'google_totp', 'microsoft_totp', 'recovery_code') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'method';
  end if;
  begin
    v_ip := nullif(btrim(p_input ->> 'ip'), '')::inet;
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ip';
  end;
  if nullif(p_input ->> 'session_id', '') is not null then
    if (p_input ->> 'session_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'session_id';
    end if;
    v_session := (p_input ->> 'session_id')::uuid;
  end if;
  if v_country is not null and v_country !~ '^[A-Z]{2}$' then v_country := null; end if;
  if nullif(p_input ->> 'device_id', '') is not null then
    v_dev := extensions.digest('device:' || left(p_input ->> 'device_id', 200), 'sha256');
  end if;
  select * into v_staff from app.admins where email = v_email;

  if v_outcome = 'success' then
    if v_session is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'session_id'; end if;
    if v_method is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'method'; end if;
    if v_staff.id is null or not v_staff.active then
      v_outcome := 'blocked_inactive';
    elsif v_method in ('google_totp', 'microsoft_totp') and not exists (
            select 1 from app.sso_providers p where p.provider = split_part(v_method, '_', 1) and p.enabled
              and (cardinality(p.allowed_domains) = 0 or split_part(v_email, '@', 2) = any (p.allowed_domains))) then
      v_outcome := 'blocked_method';
    elsif not app.ip_allowed(v_ip) then
      v_outcome := 'blocked_ip';
    elsif not app.time_allowed(now()) then
      v_outcome := 'blocked_time';
    end if;
  end if;

  if v_outcome = 'success' then
    v_new_dev := v_dev is not null and exists (select 1 from app.staff_devices d where d.staff_id = v_staff.id)
                 and not exists (select 1 from app.staff_devices d where d.staff_id = v_staff.id and d.device_hash = v_dev);
    v_new_loc := v_city is not null and v_country is not null and exists (select 1 from app.staff_locations l where l.staff_id = v_staff.id)
                 and not exists (select 1 from app.staff_locations l where l.staff_id = v_staff.id and l.country = v_country and l.city = v_city);
  end if;

  insert into app.login_log (staff_id, email_sha256, session_id, outcome, method, ip_sealed, device_label, device_hash, city, country, new_device, new_location)
  values (v_staff.id, app.email_hash(v_email), v_session, v_outcome, v_method, app.ip_seal(v_ip), v_label, v_dev, v_city, v_country, v_new_dev, v_new_loc);

  if v_outcome = 'success' then
    insert into app.staff_sessions (session_id, staff_id, ip_sealed, last_ip_sealed, device_label, device_hash, city, country, method)
    values (v_session, v_staff.id, app.ip_seal(v_ip), app.ip_seal(v_ip), v_label, v_dev, v_city, v_country, v_method)
    on conflict (session_id) do nothing;
    if v_dev is not null then
      insert into app.staff_devices (staff_id, device_hash, label) values (v_staff.id, v_dev, v_label)
      on conflict (staff_id, device_hash) do update set last_seen_at = now(), label = coalesce(excluded.label, app.staff_devices.label);
    end if;
    if v_city is not null and v_country is not null then
      insert into app.staff_locations (staff_id, country, city) values (v_staff.id, v_country, v_city) on conflict do nothing;
    end if;
    if v_new_dev then
      perform app.security_event('new_device', 'low', v_staff.id, null, jsonb_build_object('device', v_label, 'city', v_city, 'country', v_country));
    end if;
    if v_new_loc then
      perform app.security_event('new_location', 'low', v_staff.id, null, jsonb_build_object('city', v_city, 'country', v_country));
    end if;
    if app.setting('login_alerts') <> 'off'
       and (select ps.kind = 'admin' from app.permission_sets ps where ps.id = v_staff.permission_set_id) then
      perform app.security_event('admin_login', 'info', v_staff.id, null, jsonb_build_object('method', v_method, 'city', v_city, 'country', v_country));
    end if;
    if app.setting('password_expiry') = 'days' and v_method = 'password_totp' then
      v_must := coalesce((select max(c.changed_at) from app.password_changes c where c.staff_id = v_staff.id),
                         (select u.created_at from auth.users u where lower(u.email) = v_email))
                < now() - make_interval(days => app.setting_number('password_expiry', 90)::int);
    end if;
  else
    if v_session is not null and v_outcome like 'blocked_%' then
      delete from auth.sessions where id = v_session;
    end if;
    if v_outcome = 'blocked_ip' then
      perform app.security_event('ip_blocked', 'high', v_staff.id, null, jsonb_build_object('country', v_country));
    elsif v_outcome = 'blocked_time' then
      perform app.security_event('time_blocked', 'high', v_staff.id, null, '{}'::jsonb);
    elsif v_outcome in ('failed_password', 'failed_mfa') then
      -- failures in a row: since the last success, within the hour; one event when the streak reaches the threshold
      select count(*) into v_streak from app.login_log l
      where l.email_sha256 = app.email_hash(v_email) and l.outcome in ('failed_password', 'failed_mfa') and l.at > now() - interval '1 hour'
        and l.at >= coalesce((select max(s.at) from app.login_log s where s.email_sha256 = app.email_hash(v_email) and s.outcome = 'success'), '-infinity');
      if v_streak = app.setting_number('alert_failed_logins_count', 3)::int then
        perform app.security_event('failed_logins', 'high', v_staff.id, null, jsonb_build_object('count', v_streak));
      end if;
    end if;
  end if;
  return jsonb_build_object('allowed', v_outcome = 'success', 'reason', case when v_outcome <> 'success' then v_outcome end,
                            'must_change_password', v_must);
end $fn$;

-- the middleware, at most once a minute per session: still good? Ends it when not (idle, deactivated, IP, hours)
create function public.worker_session_seen(p_session uuid, p_ip inet, p_ua text default null) returns jsonb
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
    when app.setting('session_idle') = 'on_30' and s.last_seen_at < now() - interval '30 minutes' then 'idle_timeout'
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

-- the password-reset request (the sign-in page) and a completed change (the profile), from the server actions
create function public.worker_password_reset(p_email text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_staff uuid;
begin
  select id into v_staff from app.admins where email = lower(btrim(p_email)) and active;
  if v_staff is null then return jsonb_build_object('ok', true); end if;    -- an unknown address learns nothing
  perform app.security_event('password_reset', 'low', v_staff, null, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $fn$;

create function public.worker_password_changed(p_email text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_staff uuid;
begin
  select id into v_staff from app.admins where email = lower(btrim(p_email));
  if v_staff is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.password_changes (staff_id) values (v_staff) on conflict do nothing;
  delete from app.password_changes where staff_id = v_staff and changed_at < (select max(changed_at) from app.password_changes where staff_id = v_staff);
  return jsonb_build_object('ok', true);
end $fn$;

-- the Auth project reports whether a provider is configured (a build-time read of the Auth config)
create function public.worker_sso_configured(p_provider text, p_configured boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.sso_providers set configured = coalesce(p_configured, false), enabled = enabled and coalesce(p_configured, false), updated_at = now()
  where provider = p_provider;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('provider', p_provider, 'configured', coalesce(p_configured, false));
end $fn$;

-- ===========================================================================
-- the assessment: derived on read, never stored, so an issue disappears when its condition clears
-- ===========================================================================
create function app.access_review_next_due() returns date
  language sql stable security definer set search_path = ''
as $fn$
  select (max(r.completed_at) + case when app.setting('access_review_interval') = 'half_yearly' then interval '6 months' else interval '3 months' end)::date
  from app.access_reviews r where r.completed_at is not null
$fn$;

create function app.security_issues() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v jsonb := '[]'::jsonb; x jsonb; v_due date := app.access_review_next_due();
begin
  -- staff invited more than three days ago without a second factor
  select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email), 'days', (current_date - a.created_at::date)) order by a.created_at) into x
  from app.admins a where a.active and not a.is_sample and a.created_at < now() - interval '3 days' and not app.staff_mfa_verified(a.email);
  if x is not null then v := v || jsonb_build_object('key', 'mfa_not_enrolled', 'severity', 'high', 'count', jsonb_array_length(x), 'staff', x, 'action', 'send_reminder'); end if;
  -- mailboxes that need re-authentication or whose watch runs out within three days (0020)
  select jsonb_agg(jsonb_build_object('id', m.id, 'address', m.address, 'status', m.status, 'watch_expires_at', m.watch_expires_at) order by m.address) into x
  from app.mailboxes m where m.deleted_at is null and not m.is_sample
    and (m.status in ('reauth', 'error') or (m.status not in ('disconnected') and m.watch_expires_at < now() + interval '3 days'));
  if x is not null then v := v || jsonb_build_object('key', 'mailbox_reauth', 'severity', 'high', 'count', jsonb_array_length(x), 'mailboxes', x, 'action', 'reauthenticate'); end if;
  -- personal API tokens older than 180 days (0044's table, when it exists)
  if to_regclass('app.api_tokens') is not null then
    execute $q$select jsonb_agg(jsonb_build_object('id', t.id, 'staff', t.staff_id, 'name', (select coalesce(a.name, a.email) from app.admins a where a.id = t.staff_id)))
               from app.api_tokens t where t.revoked_at is null and t.created_at < now() - interval '180 days'$q$ into x;
    if x is not null then v := v || jsonb_build_object('key', 'api_tokens_old', 'severity', 'low', 'count', jsonb_array_length(x), 'tokens', x, 'action', 'rotate'); end if;
  end if;
  -- the access review
  if v_due is null or v_due <= current_date + 30 then
    if not exists (select 1 from app.access_reviews where completed_at is null) then
      v := v || jsonb_build_object('key', 'access_review_due', 'severity', 'low', 'due_on', v_due,
                                   'staff', (select count(*) from app.admins where active and not is_sample), 'action', 'start_review');
    end if;
  end if;
  -- the allowlist on with no rule
  if app.setting('ip_allowlist') = 'on' and cardinality(app.ip_ranges()) = 0 then
    v := v || jsonb_build_object('key', 'ip_allowlist_empty', 'severity', 'high', 'action', 'add_rule');
  end if;
  -- banned webhooks and failed jobs (0044's tables, when they exist)
  if to_regclass('app.webhooks') is not null then
    execute $q$select jsonb_agg(jsonb_build_object('id', w.id)) from app.webhooks w where w.state = 'banned'$q$ into x;
    if x is not null then v := v || jsonb_build_object('key', 'webhooks_banned', 'severity', 'low', 'count', jsonb_array_length(x), 'webhooks', x, 'action', 'open_webhooks'); end if;
  end if;
  if to_regclass('app.job_runs') is not null then
    execute $q$select jsonb_agg(jsonb_build_object('id', j.id, 'job', j.job_key)) from app.job_runs j where j.state = 'failed' and j.finished_at > now() - interval '24 hours'$q$ into x;
    if x is not null then v := v || jsonb_build_object('key', 'jobs_failed', 'severity', 'high', 'count', jsonb_array_length(x), 'runs', x, 'action', 'open_jobs'); end if;
  end if;
  return v;
end $fn$;

-- ===========================================================================
-- the dashboard (SEC-01): every figure counted from the login log, the sessions and the security events
-- ===========================================================================
create function public.security_dashboard() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_issues jsonb := app.security_issues();
begin
  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'signed_in_now', (select count(*) from app.staff_sessions s where s.ended_at is null
                        and (app.setting('session_idle') <> 'on_30' or s.last_seen_at >= now() - interval '30 minutes')),
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
      'mfa', (select jsonb_build_object('enrolled', count(*) filter (where app.staff_mfa_verified(a.email)), 'active', count(*))
              from app.admins a where a.active and not a.is_sample)),
    'settings', jsonb_build_object('session_idle', app.setting('session_idle'), 'ip_allowlist', app.setting('ip_allowlist'),
                                   'signin_hours', app.setting('signin_hours'), 'ip_rules', cardinality(app.ip_ranges())),
    'live', coalesce((select jsonb_agg(jsonb_build_object('session_id', s.session_id, 'staff_id', s.staff_id, 'name', coalesce(a.name, a.email),
                                                          'city', s.city, 'country', s.country, 'device', s.device_label, 'method', s.method,
                                                          'since', s.created_at, 'last_seen_at', s.last_seen_at,
                                                          'current', s.session_id = app.current_session()) order by s.created_at)
                      from app.staff_sessions s join app.admins a on a.id = s.staff_id
                      where s.ended_at is null and (app.setting('session_idle') <> 'on_30' or s.last_seen_at >= now() - interval '30 minutes')), '[]'::jsonb),
    'issues', v_issues,
    'issues_open', jsonb_array_length(v_issues),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'kind', e.kind, 'severity', e.severity,
                                                            'subject_id', e.subject_staff_id, 'subject', (select coalesce(a.name, a.email) from app.admins a where a.id = e.subject_staff_id),
                                                            'actor_id', e.actor_id, 'actor', (select coalesce(a.name, a.email) from app.admins a where a.id = e.actor_id),
                                                            'detail', e.detail, 'alert_state', e.alert_state) order by e.id desc)
                        from app.security_events e where e.at > now() - interval '7 days'), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- sessions and login history (SEC-04)
-- ===========================================================================
create function public.session_revoke(p_session uuid, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); s app.staff_sessions;
begin
  select * into s from app.staff_sessions where session_id = p_session;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if s.staff_id <> v_me then perform app.require('global', 'security'); end if;
  perform app.take_reason(p_reason);
  if not app.session_end(p_session, 'forced', v_me) then return jsonb_build_object('ended', false); end if;
  perform app.security_event('session_revoked', 'info', s.staff_id, v_me, jsonb_build_object('count', 1));
  perform app.log('session.revoked', 'staff', s.staff_id::text, jsonb_build_object('session', p_session));
  return jsonb_build_object('ended', true);
end $fn$;

-- every open session of a person; one's own current session stays when it is oneself
create function public.staff_sessions_revoke_all(p_staff uuid, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); s uuid; n int := 0;
begin
  if p_staff is distinct from v_me then perform app.require('global', 'security'); end if;
  if not exists (select 1 from app.admins where id = p_staff) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.take_reason(p_reason);
  for s in select session_id from app.staff_sessions where staff_id = p_staff and ended_at is null
             and (p_staff <> v_me or session_id is distinct from app.current_session()) loop
    if app.session_end(s, 'forced', v_me) then n := n + 1; end if;
  end loop;
  if n > 0 then perform app.security_event('session_revoked', 'info', p_staff, v_me, jsonb_build_object('count', n)); end if;
  perform app.log('session.revoked_all', 'staff', p_staff::text, jsonb_build_object('count', n));
  return jsonb_build_object('ended', n);
end $fn$;

create function public.my_sessions() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('session_id', s.session_id, 'created_at', s.created_at, 'last_seen_at', s.last_seen_at,
                                                       'device', s.device_label, 'city', s.city, 'country', s.country, 'method', s.method,
                                                       'ip', host(app.ip_open(s.last_ip_sealed)), 'current', s.session_id = app.current_session())
                                    order by s.created_at desc)
                   from app.staff_sessions s where s.staff_id = v_me and s.ended_at is null), '[]'::jsonb);
end $fn$;

-- a person's sign-ins over the last N days (≤ 60, the retention): device, place, IP, method, how the session ended
create function public.login_history(p_staff uuid, p_days int default 60) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_days int := least(greatest(coalesce(p_days, 60), 1), 60); v jsonb;
begin
  if p_staff is distinct from v_me then perform app.require('global', 'security'); end if;
  if not exists (select 1 from app.admins where id = p_staff) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'outcome', l.outcome, 'method', l.method, 'device', l.device_label, 'new_device', l.new_device,
                                               'city', l.city, 'country', l.country, 'new_location', l.new_location, 'ip', host(app.ip_open(l.ip_sealed)),
                                               'session_id', l.session_id, 'ended_at', s.ended_at, 'end_reason', s.end_reason,
                                               'active', s.session_id is not null and s.ended_at is null) order by l.at desc), '[]'::jsonb)
    into v
  from app.login_log l left join app.staff_sessions s on s.session_id = l.session_id and l.outcome = 'success'
  where l.staff_id = p_staff and l.at > now() - make_interval(days => v_days);
  perform app.log('login_history.viewed', 'staff', p_staff::text, jsonb_build_object('rows', jsonb_array_length(v)));
  return v;
end $fn$;

-- ===========================================================================
-- rules (SEC-03): IP ranges and time windows, with a preview and no self-lockout
-- ===========================================================================
create function app.security_rule_row(r app.security_rules) returns jsonb
  language sql stable set search_path = ''
as $fn$
  select jsonb_build_object('id', r.id, 'kind', r.kind, 'cidr', r.cidr::text, 'days', to_jsonb(r.days), 'starts', r.starts, 'ends', r.ends,
                            'label', r.label, 'created_at', r.created_at, 'version', r.version)
$fn$;

create function public.security_rules_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return jsonb_build_object(
    'ip_allowlist', app.setting('ip_allowlist'), 'signin_hours', app.setting('signin_hours'), 'session_idle', app.setting('session_idle'),
    'password_expiry', app.setting('password_expiry'), 'password_expiry_days', case when app.setting('password_expiry') = 'days' then app.setting_number('password_expiry', null) end,
    'password_reuse', app.setting('password_reuse'), 'password_reuse_available', false,
    'rules', coalesce((select jsonb_agg(app.security_rule_row(r) order by r.kind, r.created_at) from app.security_rules r where r.archived_at is null), '[]'::jsonb));
end $fn$;

-- after a change: with a rule on, the caller must still be inside it
create function app.security_self_check() returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if app.setting('ip_allowlist') = 'on' and not app.ip_match(app.my_ip(), app.ip_ranges()) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self_lockout';
  end if;
  if app.setting('signin_hours') = 'on' and not app.windows_match(now(), app.time_windows()) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self_lockout';
  end if;
end $fn$;

-- p_values: {kind, label, cidr} or {kind, label, days: [1..7], starts: 'HH:MM', ends: 'HH:MM'}
create function public.security_rule_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'security');
  r app.security_rules;
  v_kind text; v_cidr cidr; v_days smallint[]; v_starts time; v_ends time; v_label text := btrim(coalesce(p_values ->> 'label', ''));
begin
  if jsonb_typeof(p_values) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  if p_id is not null then
    select * into r from app.security_rules where id = p_id and archived_at is null for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and p_version <> r.version then
      raise exception 'version_conflict' using errcode = 'serialization_failure', detail = r.version::text;
    end if;
  end if;
  v_kind := coalesce(r.kind, p_values ->> 'kind');
  if v_kind is null or v_kind not in ('ip_range', 'time_window') or (p_values ? 'kind' and p_values ->> 'kind' <> v_kind) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end if;
  if char_length(v_label) not between 1 and 80 then
    if p_id is null or p_values ? 'label' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'label'; end if;
    v_label := r.label;
  end if;
  if v_kind = 'ip_range' then
    begin
      v_cidr := coalesce(nullif(btrim(p_values ->> 'cidr'), ''), r.cidr::text)::cidr;
    exception when others then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'cidr';
    end;
    if v_cidr is null or (family(v_cidr) = 4 and masklen(v_cidr) < 8) or (family(v_cidr) = 6 and masklen(v_cidr) < 16) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'cidr';
    end if;
  else
    begin
      v_days := case when p_values ? 'days' then array(select distinct jsonb_array_elements_text(p_values -> 'days')::smallint order by 1) else r.days end;
      v_starts := coalesce((p_values ->> 'starts')::time, r.starts);
      v_ends := coalesce((p_values ->> 'ends')::time, r.ends);
    exception when others then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'window';
    end;
    if v_days is null or cardinality(v_days) = 0 or not (v_days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'days';
    end if;
    if v_starts is null or v_ends is null or v_starts = v_ends then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'window'; end if;
  end if;
  -- changing a rule that is in force can only narrow who may sign in: a fresh second factor
  if p_id is not null and app.setting(case v_kind when 'ip_range' then 'ip_allowlist' else 'signin_hours' end) = 'on' then
    perform app.require_fresh_mfa(10);
  end if;
  if p_id is null then
    insert into app.security_rules (kind, cidr, days, starts, ends, label, created_by)
    values (v_kind, v_cidr, v_days, v_starts, v_ends, v_label, v_me) returning * into r;
  else
    update app.security_rules set cidr = v_cidr, days = v_days, starts = v_starts, ends = v_ends, label = v_label, version = version + 1
    where id = p_id returning * into r;
  end if;
  perform app.security_self_check();
  if v_kind = 'ip_range' and app.setting('ip_allowlist') = 'on' then perform app.sessions_enforce_ip(); end if;
  perform app.log('security_rule.saved', 'security_rule', r.id::text, jsonb_build_object('kind', v_kind, 'created', p_id is null));
  return app.security_rule_row(r);
end $fn$;

create function public.security_rule_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); r app.security_rules;
begin
  select * into r from app.security_rules where id = p_id and archived_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if app.setting(case r.kind when 'ip_range' then 'ip_allowlist' else 'signin_hours' end) = 'on' then perform app.require_fresh_mfa(10); end if;
  update app.security_rules set archived_at = now(), version = version + 1 where id = p_id;
  perform app.security_self_check();
  if r.kind = 'ip_range' and app.setting('ip_allowlist') = 'on' then perform app.sessions_enforce_ip(); end if;
  perform app.log('security_rule.deleted', 'security_rule', p_id::text, jsonb_build_object('kind', r.kind));
  return jsonb_build_object('ok', true);
end $fn$;

-- who would have been refused in the last 30 days under a change. p_change: {ip_allowlist?: on|off, signin_hours?: on|off,
-- rule?: {id?, kind, cidr | days, starts, ends}, remove?: rule id}
create function public.security_rule_preview(p_change jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'security');
  v_ip_on boolean := coalesce(p_change ->> 'ip_allowlist', app.setting('ip_allowlist')) = 'on';
  v_hours_on boolean := coalesce(p_change ->> 'signin_hours', app.setting('signin_hours')) = 'on';
  v_drop uuid[] := '{}';
  v_ranges cidr[]; v_windows jsonb; v_rule jsonb := p_change -> 'rule'; v_rows jsonb;
begin
  if jsonb_typeof(p_change) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'change'; end if;
  begin
    if (p_change ->> 'remove') is not null then v_drop := v_drop || (p_change ->> 'remove')::uuid; end if;
    if (v_rule ->> 'id') is not null then v_drop := v_drop || (v_rule ->> 'id')::uuid; end if;
    v_ranges := array(select r.cidr from app.security_rules r where r.kind = 'ip_range' and r.archived_at is null and r.id <> all (v_drop))
                || case when v_rule ->> 'kind' = 'ip_range' then array[(v_rule ->> 'cidr')::cidr] else '{}'::cidr[] end;
    v_windows := coalesce((select jsonb_agg(jsonb_build_object('days', to_jsonb(r.days), 'starts', r.starts, 'ends', r.ends))
                           from app.security_rules r where r.kind = 'time_window' and r.archived_at is null and r.id <> all (v_drop)), '[]'::jsonb)
                 || case when v_rule ->> 'kind' = 'time_window'
                         then jsonb_build_array(jsonb_build_object('days', v_rule -> 'days', 'starts', (v_rule ->> 'starts')::time, 'ends', (v_rule ->> 'ends')::time))
                         else '[]'::jsonb end;
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'change';
  end;
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', x.staff_id, 'name', (select coalesce(a.name, a.email) from app.admins a where a.id = x.staff_id),
                                               'refused', x.refused, 'sign_ins', x.total) order by x.refused desc), '[]'::jsonb) into v_rows
  from (select l.staff_id, count(*) total,
               count(*) filter (where (v_ip_on and not app.ip_match(app.ip_open(l.ip_sealed), v_ranges)) or (v_hours_on and not app.windows_match(l.at, v_windows))) refused
        from app.login_log l where l.outcome = 'success' and l.staff_id is not null and l.at > now() - interval '30 days' group by l.staff_id) x
  where x.refused > 0;
  return jsonb_build_object('staff', v_rows,
                            'self_lockout', (v_ip_on and not app.ip_match(app.my_ip(), v_ranges)) or (v_hours_on and not app.windows_match(now(), v_windows)));
end $fn$;

-- ===========================================================================
-- alerts (SEC-02): the toggles are register keys set with setting_set; this reads them with the recipients
-- ===========================================================================
create function public.alerts_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return jsonb_build_object(
    'settings', (select jsonb_object_agg(k, app.setting(k)) from unnest(array['alert_new_device', 'alert_user_invited', 'alert_failed_logins',
                 'alert_password_reset', 'alert_large_export', 'login_alerts', 'alert_digest_time', 'security_alert_recipients']) k),
    'failed_logins_count', app.setting_number('alert_failed_logins_count', 3),
    'large_export_rows', app.setting_number('alert_large_export_rows', 1000),
    'recipients', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email), 'email', a.email) order by a.name)
                            from app.admins a where a.id in (select * from app.security_recipients())), '[]'::jsonb),
    'listed', coalesce((select jsonb_agg(r.staff_id) from app.security_alert_recipients r), '[]'::jsonb),
    'email', case when app.connected('email') then 'connected' else 'not_connected' end,
    'slack', case when app.connected('slack') then 'connected' else 'not_connected' end,
    'slack_channel', (select c.config ->> 'channel' from app.integration_connections c where c.provider = 'slack' and c.status = 'connected'));
end $fn$;

create function public.alert_recipients_set(p_staff uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security');
begin
  if exists (select 1 from unnest(coalesce(p_staff, '{}')) s where not exists (select 1 from app.admins a where a.id = s and a.active and app.staff_has_security(a.id))) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'staff';
  end if;
  delete from app.security_alert_recipients where staff_id <> all (coalesce(p_staff, '{}'));
  insert into app.security_alert_recipients (staff_id, added_by) select distinct s, v_me from unnest(coalesce(p_staff, '{}')) s on conflict do nothing;
  perform app.log('security.recipients_set', null, null, jsonb_build_object('count', (select count(*) from app.security_alert_recipients)));
  return jsonb_build_object('count', (select count(*) from app.security_alert_recipients));
end $fn$;

-- ===========================================================================
-- SSO and two-factor (SEC-05, SEC-06; D-11, D-31)
-- ===========================================================================
create function public.sso_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return jsonb_build_object(
    'providers', coalesce((select jsonb_agg(jsonb_build_object('provider', p.provider, 'enabled', p.enabled, 'configured', p.configured,
                     'state', case when not p.configured then 'not_connected' when p.enabled then 'on' else 'off' end,
                     'allowed_domains', to_jsonb(p.allowed_domains), 'updated_at', p.updated_at,
                     'users', (select count(*) from (select distinct on (l.staff_id) l.staff_id, l.method from app.login_log l
                                                     where l.outcome = 'success' and l.staff_id is not null order by l.staff_id, l.at desc) x
                               where x.method = p.provider || '_totp')) order by p.provider) from app.sso_providers p), '[]'::jsonb),
    'access_review_due', app.access_review_next_due(),
    'access_review_open', exists (select 1 from app.access_reviews where completed_at is null));
end $fn$;

create function public.sso_set(p_provider text, p_enabled boolean, p_domains text[] default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); p app.sso_providers; v_domains text[];
begin
  perform app.require_fresh_mfa(10);
  select * into p from app.sso_providers where provider = p_provider for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  v_domains := coalesce(array(select distinct lower(btrim(d)) from unnest(p_domains) d where btrim(d) <> '' order by 1), p.allowed_domains);
  if exists (select 1 from unnest(v_domains) d where d !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$') or cardinality(v_domains) > 20 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'domains';
  end if;
  if coalesce(p_enabled, false) and not p.configured then
    raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = p_provider;
  end if;
  update app.sso_providers set enabled = coalesce(p_enabled, false), allowed_domains = v_domains, updated_by = v_me, updated_at = now() where provider = p_provider;
  perform app.log('sso.changed', 'sso_provider', p_provider, jsonb_build_object('enabled', coalesce(p_enabled, false), 'domains', cardinality(v_domains)));
  return jsonb_build_object('provider', p_provider, 'enabled', coalesce(p_enabled, false));
end $fn$;

create function public.mfa_overview() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return (select jsonb_build_object(
    'enforced', (select fixed from app.settings_registry where key = 'mfa'),
    'active', count(*),
    'authenticator', count(*) filter (where app.staff_mfa_verified(a.email)),
    'not_enrolled', coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email)) order by a.name)
                             filter (where not app.staff_mfa_verified(a.email)), '[]'::jsonb),
    'recovery_codes', count(*) filter (where exists (select 1 from app.recovery_codes r where r.staff_id = a.id and r.used_at is null)))
    from app.admins a where a.active and not a.is_sample);
end $fn$;

-- ten codes, shown once; the old ones go
create function public.recovery_codes_generate() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_codes text[] := '{}'; v_code text;
begin
  perform app.require_fresh_mfa(10);
  delete from app.recovery_codes where staff_id = v_me;
  for i in 1..10 loop
    v_code := encode(extensions.gen_random_bytes(5), 'hex');
    insert into app.recovery_codes (staff_id, hash) values (v_me, extensions.digest(v_code, 'sha256'));
    v_codes := v_codes || (substr(v_code, 1, 5) || '-' || substr(v_code, 6, 5));
  end loop;
  perform app.log('recovery_codes.generated', 'staff', v_me::text, jsonb_build_object('count', 10));
  return jsonb_build_object('codes', to_jsonb(v_codes));
end $fn$;

-- the one aal1 entry point (D-11): a used code removes the person's factors and ends their other sessions; they enrol
-- again. At most five attempts an hour; a wrong code answers {ok: false} so the attempt is counted.
create function public.recovery_code_redeem(p_code text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_email text := app.admin_email();
  v_staff uuid;
  v_code text := lower(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));
  s uuid;
begin
  if v_email is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  select id into v_staff from app.admins where email = v_email;
  if (select count(*) from app.recovery_attempts where staff_id = v_staff and at > now() - interval '1 hour') >= 5 then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'rate_limited';
  end if;
  insert into app.recovery_attempts (staff_id) values (v_staff);
  update app.recovery_codes set used_at = now() where staff_id = v_staff and hash = extensions.digest(v_code, 'sha256') and used_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'remaining_attempts', 5 - (select count(*) from app.recovery_attempts where staff_id = v_staff and at > now() - interval '1 hour'));
  end if;
  delete from auth.mfa_factors where user_id = auth.uid();
  for s in select session_id from app.staff_sessions where staff_id = v_staff and ended_at is null and session_id is distinct from app.current_session() loop
    perform app.session_end(s, 'recovery_code', v_staff);
  end loop;
  delete from app.recovery_attempts where staff_id = v_staff;
  perform app.security_event('mfa_reset', 'high', v_staff, v_staff, jsonb_build_object('via', 'recovery_code'));
  insert into app.audit (actor, staff_id, action, target_type, target_id, ok, source, principal_kind, principal_id)
  values (v_email, v_staff, 'recovery_codes.redeemed', 'staff', v_staff::text, true, 'web', 'staff', v_staff);
  return jsonb_build_object('ok', true, 'enrol', true);
end $fn$;

-- the owner resets another person's second factor (D-11): factors, codes and sessions go
create function public.staff_mfa_reset(p_staff uuid, p_reason text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_email text; s uuid; n int := 0;
begin
  if (select role from app.admins where id = v_me) <> 'owner' then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'owner_only';
  end if;
  perform app.require_fresh_mfa(10);
  if p_staff = v_me then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self'; end if;
  select email into v_email from app.admins where id = p_staff;
  if v_email is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.take_reason(p_reason);
  delete from auth.mfa_factors f using auth.users u where u.id = f.user_id and lower(u.email) = v_email;
  get diagnostics n = row_count;
  delete from app.recovery_codes where staff_id = p_staff;
  for s in select session_id from app.staff_sessions where staff_id = p_staff and ended_at is null loop
    perform app.session_end(s, 'mfa_reset', v_me);
  end loop;
  perform app.security_event('mfa_reset', 'high', p_staff, v_me, jsonb_build_object('via', 'owner', 'factors', n));
  perform app.notify(p_staff, 'security', 'security.mfa_reset_by_owner', '{}'::jsonb, null);
  perform app.log('mfa.reset', 'staff', p_staff::text, jsonb_build_object('factors', n));
  return jsonb_build_object('factors_removed', n);
end $fn$;

-- a reminder to enrol: in the app now; email when the provider exists (not_connected until then)
create function public.staff_mfa_reminder(p_staff uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_email text;
begin
  select email into v_email from app.admins where id = p_staff and active;
  if v_email is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if app.staff_mfa_verified(v_email) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'enrolled'; end if;
  perform app.notify(p_staff, 'security', 'security.mfa_reminder', jsonb_build_object('by', v_me), '/settings');
  perform app.log('mfa.reminded', 'staff', p_staff::text);
  return jsonb_build_object('in_app', true, 'email', case when app.connected('email') then 'queued' else 'not_connected' end);
end $fn$;

-- ===========================================================================
-- access reviews (Appendix 2; the quarterly review)
-- ===========================================================================
create function public.access_review_start() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_id uuid;
begin
  if exists (select 1 from app.access_reviews where completed_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'open_review';
  end if;
  insert into app.access_reviews (due_on, started_by) values (coalesce(app.access_review_next_due(), current_date), v_me) returning id into v_id;
  insert into app.access_review_items (review_id, staff_id, permission_set_id, group_id)
  select v_id, a.id, a.permission_set_id, a.group_id from app.admins a where a.active and not a.is_sample;
  perform app.log('access_review.started', 'access_review', v_id::text, jsonb_build_object('staff', (select count(*) from app.access_review_items where review_id = v_id)));
  return jsonb_build_object('id', v_id, 'items', (select count(*) from app.access_review_items where review_id = v_id));
end $fn$;

create function public.access_review_get(p_review uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare r app.access_reviews;
begin
  perform app.require('global', 'security');
  select * into r from app.access_reviews where id = p_review or (p_review is null and completed_at is null) order by started_at desc limit 1;
  if not found then
    return jsonb_build_object('review', null, 'next_due', app.access_review_next_due(), 'interval', app.setting('access_review_interval'));
  end if;
  return jsonb_build_object('review', to_jsonb(r), 'next_due', app.access_review_next_due(), 'interval', app.setting('access_review_interval'),
    'items', coalesce((select jsonb_agg(jsonb_build_object('staff_id', i.staff_id, 'name', coalesce(a.name, a.email), 'permission_set_id', i.permission_set_id,
                                                           'permission_set', ps.name, 'group_id', i.group_id, 'group', g.name, 'decision', i.decision,
                                                           'decided_at', i.decided_at) order by a.name)
                       from app.access_review_items i join app.admins a on a.id = i.staff_id
                       left join app.permission_sets ps on ps.id = i.permission_set_id left join app.visibility_groups g on g.id = i.group_id
                       where i.review_id = r.id), '[]'::jsonb));
end $fn$;

create function public.access_review_decide(p_review uuid, p_staff uuid, p_decision text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security');
begin
  if p_decision is null or p_decision not in ('keep', 'change', 'deactivate') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'decision';
  end if;
  update app.access_review_items i set decision = p_decision, decided_by = v_me, decided_at = now()
  from app.access_reviews r where r.id = i.review_id and r.completed_at is null and i.review_id = p_review and i.staff_id = p_staff;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('access_review.decided', 'access_review', p_review::text, jsonb_build_object('staff', p_staff, 'decision', p_decision));
  return jsonb_build_object('ok', true);
end $fn$;

create function public.access_review_complete(p_review uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security');
begin
  if not exists (select 1 from app.access_reviews where id = p_review and completed_at is null) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  if exists (select 1 from app.access_review_items where review_id = p_review and decision is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'undecided';
  end if;
  update app.access_reviews set completed_at = now(), completed_by = v_me where id = p_review;
  perform app.log('access_review.completed', 'access_review', p_review::text,
                  (select jsonb_object_agg(decision, n) from (select decision, count(*) n from app.access_review_items where review_id = p_review group by decision) d));
  return jsonb_build_object('ok', true, 'next_due', app.access_review_next_due());
end $fn$;

-- job access_review_due (daily): a weekly reminder to global:security while the review is due and not started
create function app.access_review_due() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_due date := app.access_review_next_due(); r uuid; n int := 0;
begin
  if (v_due is not null and v_due > current_date) or exists (select 1 from app.access_reviews where completed_at is null)
     or exists (select 1 from app.notifications where key = 'security.access_review_due' and created_at > now() - interval '7 days') then
    return 0;
  end if;
  for r in select * from app.security_recipients() loop
    perform app.notify(r, 'security', 'security.access_review_due', jsonb_build_object('due_on', v_due), '/security'); n := n + 1;
  end loop;
  return n;
end $fn$;

-- ===========================================================================
-- data protection (SEC-10; Part G firewall, residency, recovery; D-35)
-- ===========================================================================
-- the firewall's claims, each proved live (the same assertions as structure_invariants.sql)
create function public.firewall_status() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v jsonb;
begin
  perform app.require('global', 'see');
  v := jsonb_build_array(
    jsonb_build_object('key', 'no_grants', 'ok',
      not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'app' and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
      and not exists (select 1 from pg_policies where schemaname = 'app')
      and not exists (select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' and not c.relrowsecurity)),
    jsonb_build_object('key', 'no_references', 'ok',
      not exists (select 1 from information_schema.columns c where c.table_schema in ('app', 'public')
                  and c.column_name ~ '(^|_)(answer|answers|respondent|respondents|response_value|score_item|survey_comment)(_|$)')
      and not exists (select 1 from pg_class c where c.relnamespace in ('app'::regnamespace, 'public'::regnamespace) and c.relkind in ('r', 'v', 'm')
                      and c.relname ~ '(answer|respondent|survey_response|response_comment|extra_answer)')),
    jsonb_build_object('key', 'aggregates_only', 'ok',
      not exists (select 1 from app.events_in e where e.kind ~ '(answer|respondent|response)' limit 1)),
    jsonb_build_object('key', 'no_tracking_in_surveys', 'ok', (select fixed from app.settings_registry where key = 'survey_flow_block') is true),
    jsonb_build_object('key', 'no_contacts_from_respondents', 'ok',
      not exists (select 1 from app.people p where p.source ~* '(respondent|survey)' limit 1)),
    jsonb_build_object('key', 'tested', 'ok', (select fixed from app.settings_registry where key = 'firewall') is true));
  return jsonb_build_object('ok', not exists (select 1 from jsonb_array_elements(v) x where not (x ->> 'ok')::boolean), 'checks', v, 'ci', null);
end $fn$;

create function public.protection_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_rpo int := (select value::int from app.platform_facts where key = 'rpo_minutes'); v_rto int := (select value::int from app.platform_facts where key = 'rto_minutes');
begin
  perform app.require('global', 'security');
  return jsonb_build_object(
    'facts', (select jsonb_object_agg(f.key, jsonb_build_object('value', f.value, 'source', f.source)) from app.platform_facts f),
    'last_backup', (select jsonb_build_object('at', o.at, 'ok', o.ok) from app.ops_checks o where o.kind = 'backup' and o.ok order by o.at desc limit 1),
    'pitr', (select jsonb_build_object('at', o.at, 'ok', o.ok) from app.ops_checks o where o.kind = 'pitr' order by o.at desc limit 1),
    'pitr_warning', not coalesce((select o.ok from app.ops_checks o where o.kind = 'pitr' order by o.at desc limit 1), false),
    'last_restore_test', (select jsonb_build_object('at', o.at, 'ok', o.ok, 'rpo_minutes', o.rpo_minutes, 'rto_minutes', o.rto_minutes,
                                                    'meets_objectives', o.ok and o.rpo_minutes <= v_rpo and o.rto_minutes <= v_rto)
                          from app.ops_checks o where o.kind = 'restore_test' order by o.at desc limit 1),
    'objectives', jsonb_build_object('rpo_minutes', v_rpo, 'rto_minutes', v_rto));
end $fn$;

-- SF-43.5, SEC-10 AC: a restore test, recorded by staff; it meets the objectives when RPO ≤ 60 and RTO ≤ 240 (D-35)
create function public.restore_test_record(p_at timestamptz, p_ok boolean, p_rpo_min int, p_rto_min int, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_id bigint;
begin
  if p_at is null or p_at > now() + interval '5 minutes' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'at'; end if;
  if p_ok is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ok'; end if;
  if p_rpo_min is null or p_rpo_min < 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rpo'; end if;
  if p_rto_min is null or p_rto_min < 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rto'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'note'; end if;
  insert into app.ops_checks (kind, at, ok, rpo_minutes, rto_minutes, detail, recorded_by)
  values ('restore_test', p_at, p_ok, p_rpo_min, p_rto_min, case when nullif(btrim(p_note), '') is null then '{}'::jsonb else jsonb_build_object('note', btrim(p_note)) end, v_me)
  returning id into v_id;
  perform app.log('restore_test.recorded', 'ops_check', v_id::text, jsonb_build_object('ok', p_ok, 'rpo', p_rpo_min, 'rto', p_rto_min));
  return jsonb_build_object('id', v_id, 'meets_objectives', p_ok and p_rpo_min <= (select value::int from app.platform_facts where key = 'rpo_minutes')
                                                             and p_rto_min <= (select value::int from app.platform_facts where key = 'rto_minutes'));
end $fn$;

-- the backup worker (Management API, hourly): [{kind: backup|pitr, at, ok}]
create function public.worker_backup_seen(p_rows jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare x jsonb; n int := 0;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) > 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    if x ->> 'kind' not in ('backup', 'pitr') or (x ->> 'at') is null or jsonb_typeof(x -> 'ok') <> 'boolean' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
    end if;
    insert into app.ops_checks (kind, at, ok) values (x ->> 'kind', (x ->> 'at')::timestamptz, (x ->> 'ok')::boolean) on conflict (kind, at) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return jsonb_build_object('recorded', n);
end $fn$;

-- ===========================================================================
-- privacy (SEC-11; SF-15; D-24, D-27)
-- ===========================================================================
-- the people and leads named by a subject {people: [uuid], leads: [uuid]}; leads of those people come along
create function app.privacy_subject(p_subject jsonb, out people uuid[], out leads uuid[], out emails text[])
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  begin
    people := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_subject -> 'people', '[]'::jsonb)) x);
    leads := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_subject -> 'leads', '[]'::jsonb)) x);
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject';
  end;
  if cardinality(people) + cardinality(leads) = 0 or cardinality(people) + cardinality(leads) > 20 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject';
  end if;
  if exists (select 1 from unnest(people) p where not exists (select 1 from app.people x where x.id = p))
     or exists (select 1 from unnest(leads) l where not exists (select 1 from app.leads x where x.id = l)) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  leads := array(select distinct x from (select unnest(leads) x union select l.id from app.leads l where l.person_id = any (people)) y);
  emails := array(select distinct lower(btrim(p.email)) from app.people p where p.id = any (people) and nullif(btrim(p.email), '') is not null);
end $fn$;

-- counts per module, from the real tables
create function app.privacy_counts(p_people uuid[], p_leads uuid[], p_emails text[]) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'people', (select count(*) from app.people where id = any (p_people)),
    'leads', (select count(*) from app.leads where id = any (p_leads)),
    'emails', (select count(*) from app.email_messages m where m.person_id = any (p_people) or lower(m.from_addr) = any (p_emails)
               or exists (select 1 from jsonb_array_elements(m.to_addrs || m.cc || m.bcc) a where lower(a ->> 'address') = any (p_emails))),
    'email_participants', (select count(*) from app.email_thread_participants t where t.person_id = any (p_people) or t.address = any (p_emails)),
    'activities', (select count(*) from app.activities a where a.person_id = any (p_people) or a.lead_id = any (p_leads)),
    'activity_guests', (select count(*) from app.activity_guests g where g.person_id = any (p_people) or lower(g.email) = any (p_emails)),
    'deals', (select count(*) from app.deals d where d.person_id = any (p_people)),
    'deal_participants', (select count(*) from app.deal_participants d where d.person_id = any (p_people)),
    'tickets', (select count(*) from app.tickets t where t.person_id = any (p_people) or lower(t.requester_email) = any (p_emails)),
    'consent_events', (select count(*) from app.consent_events c where c.person_id = any (p_people)
                       or c.email_sha256 = any (array(select app.email_hash(e) from unnest(p_emails) e))),
    'form_submissions', (select count(*) from app.form_submissions f where f.person_id = any (p_people) or f.lead_id = any (p_leads)),
    'chat_conversations', (select count(*) from app.chat_conversations c where c.person_id = any (p_people) or c.lead_id = any (p_leads)),
    'campaign_recipients', (select count(*) from app.campaign_recipients c where c.person_id = any (p_people) or lower(c.email) = any (p_emails)),
    'meetings', (select count(distinct a.meeting_id) from app.meeting_attendees a where a.person_id = any (p_people) or lower(a.email) = any (p_emails)),
    'documents', (select count(*) from app.documents d where d.person_id = any (p_people)),
    'signatures', (select count(*) from app.signature_signers s where s.person_id = any (p_people)),
    'bookings', (select count(*) from app.bookings b where b.person_id = any (p_people)),
    'product_events', (select count(*) from app.events_in e where lower(e.payload ->> 'email') = any (p_emails)),
    'enrichment_requests', (select count(*) from app.enrichment_requests r where (r.entity = 'person' and r.record_id = any (p_people))
                            or (r.entity = 'lead' and r.record_id = any (p_leads))),
    'history', (select count(*) from app.changelog c where (c.entity = 'person' and c.record_id = any (p_people)) or (c.entity = 'lead' and c.record_id = any (p_leads))))
$fn$;

-- an active product user (members) is erased in the product (D-40), not here: the next member event would re-create them
create function app.privacy_product_user(p_emails text[]) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from app.members m where m.active and lower(m.email) = any (p_emails))
$fn$;

-- find a person: an exact address or a name; the query is never stored
create function public.privacy_find(p_q text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_q text := btrim(coalesce(p_q, '')); v_email text; v_people jsonb; v_out jsonb;
begin
  if char_length(v_q) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'q'; end if;
  v_email := case when v_q like '%@%' then lower(v_q) end;
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email, 'organization', o.name, 'deleted', p.deleted_at is not null,
                                               'leads', (select coalesce(jsonb_agg(l.id), '[]'::jsonb) from app.leads l where l.person_id = p.id)) order by p.name), '[]'::jsonb)
    into v_people
  from (select * from app.people x where not x.is_sample and (case when v_email is not null then lower(x.email) = v_email
                                                                   else x.name ilike '%' || replace(replace(v_q, '%', '\%'), '_', '\_') || '%' end)
        order by x.name limit 20) p
  left join app.organizations o on o.id = p.organization_id;
  v_out := jsonb_build_object(
    'people', v_people,
    'members', case when v_email is null then '[]'::jsonb else
                 coalesce((select jsonb_agg(jsonb_build_object('product', m.product, 'tenant_id', m.tenant_id, 'active', m.active)) from app.members m where lower(m.email) = v_email), '[]'::jsonb) end,
    'email_participants', case when v_email is null then 0 else (select count(*) from app.email_thread_participants t where t.address = v_email) end,
    'tickets', case when v_email is null then 0 else (select count(*) from app.tickets t where lower(t.requester_email) = v_email) end,
    'consent_events', case when v_email is null then 0 else (select count(*) from app.consent_events c where c.email_sha256 = app.email_hash(v_email)) end,
    'erased', case when v_email is null then false else exists (select 1 from app.erasure_tombstones t where t.email_sha256 = app.email_hash(v_email)) end);
  perform app.log('privacy.searched', null, null, jsonb_build_object('by', case when v_email is null then 'name' else 'email' end, 'hits', jsonb_array_length(v_people)));
  return v_out;
end $fn$;

create function public.privacy_preview(p_subject jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); s record; v_counts jsonb;
begin
  s := app.privacy_subject(p_subject);
  v_counts := app.privacy_counts(s.people, s.leads, s.emails);
  perform app.log('privacy.previewed', null, null, jsonb_build_object('counts', v_counts));
  return jsonb_build_object('counts', v_counts, 'product_user', app.privacy_product_user(s.emails), 'emails', cardinality(s.emails),
                            'confirm', case when cardinality(s.emails) = 1 then 'email' else 'name' end,
                            'second_admin', app.setting('second_admin') = 'on');
end $fn$;

-- an access request: a job and a package the worker writes to the private bucket; the link lives 24 h
create function public.privacy_export(p_subject jsonb, p_request uuid default null, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); s record; v_id uuid; v_counts jsonb;
begin
  perform app.take_reason(p_reason);
  s := app.privacy_subject(p_subject);
  if p_request is not null and not exists (select 1 from app.privacy_requests where id = p_request) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'request';
  end if;
  v_counts := app.privacy_counts(s.people, s.leads, s.emails);
  insert into app.privacy_jobs (request_id, kind, subject, preview, state, created_by)
  values (p_request, 'export', jsonb_build_object('people', to_jsonb(s.people), 'leads', to_jsonb(s.leads)), v_counts, 'approved', v_me) returning id into v_id;
  update app.privacy_requests set status = 'in_progress' where id = p_request and status = 'received';
  perform pgmq.send('jobs', jsonb_build_object('job', 'privacy_package', 'privacy_job_id', v_id));
  perform app.log('privacy.exported', 'privacy_job', v_id::text, jsonb_build_object('counts', v_counts));
  return jsonb_build_object('job', v_id, 'state', 'approved');
end $fn$;

-- the worker reads the package's rows (every row about the person), then reports where it wrote the file
create function public.worker_privacy_package(p_job uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare j app.privacy_jobs; v_people uuid[]; v_leads uuid[]; v_emails text[];
begin
  select * into j from app.privacy_jobs where id = p_job and kind = 'export' for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if j.state not in ('approved', 'running') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  update app.privacy_jobs set state = 'running' where id = p_job;
  v_people := array(select x::uuid from jsonb_array_elements_text(j.subject -> 'people') x);
  v_leads := array(select x::uuid from jsonb_array_elements_text(j.subject -> 'leads') x);
  v_emails := array(select distinct lower(email) from app.people where id = any (v_people) and email is not null);
  return jsonb_build_object(
    'people', (select coalesce(jsonb_agg(to_jsonb(p) - 'custom' || jsonb_build_object('custom', p.custom)), '[]'::jsonb) from app.people p where p.id = any (v_people)),
    'leads', (select coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb) from app.leads l where l.id = any (v_leads)),
    'activities', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from app.activities a where a.person_id = any (v_people) or a.lead_id = any (v_leads)),
    'deal_participants', (select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb) from app.deal_participants d where d.person_id = any (v_people)),
    'tickets', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from app.tickets t where t.person_id = any (v_people) or lower(t.requester_email) = any (v_emails)),
    'consent_events', (select coalesce(jsonb_agg(to_jsonb(c) - 'email_sha256'), '[]'::jsonb) from app.consent_events c where c.person_id = any (v_people)),
    'form_submissions', (select coalesce(jsonb_agg(to_jsonb(f) - 'fingerprint'), '[]'::jsonb) from app.form_submissions f where f.person_id = any (v_people) or f.lead_id = any (v_leads)),
    'email_messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'direction', m.direction, 'from', m.from_addr, 'to', m.to_addrs, 'cc', m.cc,
                                                                    'subject', m.subject, 'body_text', m.body_text, 'at', coalesce(m.sent_at, m.received_at, m.created_at))), '[]'::jsonb)
                       from app.email_messages m where m.person_id = any (v_people) or lower(m.from_addr) = any (v_emails)),
    'campaign_recipients', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from app.campaign_recipients c where c.person_id = any (v_people)),
    'meetings', (select coalesce(jsonb_agg(jsonb_build_object('meeting_id', a.meeting_id, 'email', a.email, 'name', a.name)), '[]'::jsonb)
                 from app.meeting_attendees a where a.person_id = any (v_people) or lower(a.email) = any (v_emails)),
    'history', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from app.changelog c where (c.entity = 'person' and c.record_id = any (v_people))
                or (c.entity = 'lead' and c.record_id = any (v_leads))));
end $fn$;

create function public.worker_privacy_done(p_job uuid, p_path text, p_error text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare j app.privacy_jobs;
begin
  select * into j from app.privacy_jobs where id = p_job and kind = 'export' and state = 'running' for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_error is not null then
    update app.privacy_jobs set state = 'failed', error = left(p_error, 300), finished_at = now() where id = p_job;
    return jsonb_build_object('state', 'failed');
  end if;
  if p_path is null or p_path !~ ('^privacy/' || p_job::text || '/[A-Za-z0-9._-]{1,80}$') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path';
  end if;
  update app.privacy_jobs set state = 'done', storage_path = p_path, url_expires_at = now() + interval '24 hours', finished_at = now() where id = p_job;
  update app.privacy_requests set status = 'done', closed_at = now() where id = j.request_id and status in ('received', 'in_progress');
  perform app.emit('privacy.exported', 'privacy_job', p_job, jsonb_build_object('request', j.request_id));
  return jsonb_build_object('state', 'done');
end $fn$;

-- the package's path for the server to sign (24 h); the read is audited
create function public.privacy_export_url(p_job uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); j app.privacy_jobs;
begin
  select * into j from app.privacy_jobs where id = p_job and kind = 'export';
  if not found or j.state <> 'done' then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if j.url_expires_at <= now() then raise exception 'not_available' using errcode = 'invalid_parameter_value', detail = 'expired'; end if;
  perform app.log('privacy_package.viewed', 'privacy_job', p_job::text);
  return jsonb_build_object('path', j.storage_path, 'expires_at', j.url_expires_at);
end $fn$;

-- the erasure itself, in one transaction (D-24: delete the rows, blank name, email and phone in stored events)
create function app.privacy_erase_run(p_job uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  j app.privacy_jobs; v_people uuid[]; v_leads uuid[]; v_emails text[]; v_threads uuid[]; v_counts jsonb; n bigint; v_done jsonb := '{}'::jsonb;
begin
  select * into j from app.privacy_jobs where id = p_job and kind = 'erasure' for update;
  update app.privacy_jobs set state = 'running' where id = p_job;
  v_people := array(select x::uuid from jsonb_array_elements_text(j.subject -> 'people') x);
  v_leads := array(select x::uuid from jsonb_array_elements_text(j.subject -> 'leads') x);
  v_emails := array(select distinct lower(btrim(email)) from app.people where id = any (v_people) and nullif(btrim(email), '') is not null);
  v_counts := app.privacy_counts(v_people, v_leads, v_emails);

  insert into app.erasure_tombstones (email_sha256, erased_at, request_id)
  select app.email_hash(e), now(), j.request_id from unnest(v_emails) e
  on conflict (email_sha256) do update set erased_at = excluded.erased_at, request_id = excluded.request_id;

  delete from app.call_logs c using app.activities a where a.id = c.activity_id and (a.person_id = any (v_people) or a.lead_id = any (v_leads));
  delete from app.activity_guests where person_id = any (v_people) or lower(email) = any (v_emails);
  delete from app.enrichment_requests where (entity = 'person' and record_id = any (v_people)) or (entity = 'lead' and record_id = any (v_leads));

  -- mail: a thread whose only outside participant is the person goes; elsewhere the address is redacted
  v_threads := array(select t.thread_id from app.email_thread_participants t group by t.thread_id
                     having bool_or(coalesce(t.address = any (v_emails) or t.person_id = any (v_people), false))
                        and bool_and(coalesce(t.address = any (v_emails) or t.person_id = any (v_people), false)
                                     or exists (select 1 from app.mailboxes m where lower(m.address) = t.address)
                                     or exists (select 1 from app.admins a where a.email = t.address)));
  delete from app.email_threads where id = any (v_threads);
  delete from app.email_thread_participants where address = any (v_emails) or person_id = any (v_people);
  update app.email_messages m set
    from_addr = case when lower(m.from_addr) = any (v_emails) then '' else m.from_addr end,
    from_name = case when lower(m.from_addr) = any (v_emails) then null else m.from_name end,
    to_addrs = coalesce((select jsonb_agg(a) from jsonb_array_elements(m.to_addrs) a where lower(a ->> 'address') <> all (v_emails)), '[]'::jsonb),
    cc = coalesce((select jsonb_agg(a) from jsonb_array_elements(m.cc) a where lower(a ->> 'address') <> all (v_emails)), '[]'::jsonb),
    bcc = coalesce((select jsonb_agg(a) from jsonb_array_elements(m.bcc) a where lower(a ->> 'address') <> all (v_emails)), '[]'::jsonb)
  where m.person_id = any (v_people) or lower(m.from_addr) = any (v_emails)
     or exists (select 1 from jsonb_array_elements(m.to_addrs || m.cc || m.bcc) a where lower(a ->> 'address') = any (v_emails));

  update app.tickets set requester_email = null where lower(requester_email) = any (v_emails);
  update app.members set email = null, name = null where not active and lower(email) = any (v_emails);
  update app.events_in set payload = payload - 'name' - 'email' - 'phone' where lower(payload ->> 'email') = any (v_emails);
  update app.events set payload = payload - 'name' - 'email' - 'phone'
  where (subject_type = 'person' and subject_id = any (v_people)) or (subject_type = 'lead' and subject_id = any (v_leads))
     or lower(payload ->> 'email') = any (v_emails);

  -- the records: their own triggers redact meetings, forms, chats and campaign rows and add the suppression (0031–0042)
  delete from app.leads where id = any (v_leads);
  delete from app.people where id = any (v_people);
  perform set_config('app.purging', 'on', true);
  delete from app.changelog where (entity = 'person' and record_id = any (v_people)) or (entity = 'lead' and record_id = any (v_leads))
                               or (entity = 'email_thread' and record_id = any (v_threads));
  get diagnostics n = row_count;
  perform set_config('app.purging', '', true);

  update app.privacy_jobs set state = 'done', finished_at = now() where id = p_job;
  update app.privacy_requests set status = 'done', closed_at = now() where id = j.request_id and status in ('received', 'in_progress');
  perform app.log('privacy.erased', 'privacy_job', p_job::text, jsonb_build_object('counts', v_counts, 'threads', cardinality(v_threads)));
  perform app.emit('privacy.erased', 'privacy_job', p_job, jsonb_build_object('request', j.request_id, 'counts', v_counts));
  return v_counts;
end $fn$;

-- erase: typed confirmation (the address, or the name when there is none), a fresh second factor, never an active product
-- user, and a second admin's approval when second_admin is on
create function public.privacy_erase(p_subject jsonb, p_request uuid, p_confirm text, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); s record; v_id uuid; v_counts jsonb; v_expect text; r uuid;
begin
  perform app.require_fresh_mfa(10);
  perform app.take_reason(p_reason);
  s := app.privacy_subject(p_subject);
  if cardinality(s.emails) > 1 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
  v_expect := coalesce(s.emails[1], (select lower(btrim(name)) from app.people where id = any (s.people) order by created_at limit 1),
                       (select lower(btrim(title)) from app.leads where id = any (s.leads) order by created_at limit 1));
  if lower(btrim(coalesce(p_confirm, ''))) is distinct from v_expect then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'confirm';
  end if;
  if app.privacy_product_user(s.emails) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'product_user'; end if;
  if p_request is not null and not exists (select 1 from app.privacy_requests where id = p_request) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'request';
  end if;
  v_counts := app.privacy_counts(s.people, s.leads, s.emails);
  insert into app.privacy_jobs (request_id, kind, subject, preview, created_by)
  values (p_request, 'erasure', jsonb_build_object('people', to_jsonb(s.people), 'leads', to_jsonb(s.leads)), v_counts, v_me) returning id into v_id;
  if app.setting('second_admin') = 'on' then
    for r in select * from app.security_recipients() loop
      continue when r = v_me;
      perform app.notify(r, 'security', 'security.erasure_approval', jsonb_build_object('job', v_id, 'by', v_me), '/security');
    end loop;
    perform app.log('privacy.erase_requested', 'privacy_job', v_id::text, jsonb_build_object('counts', v_counts));
    return jsonb_build_object('job', v_id, 'state', 'previewed', 'approval', 'required', 'counts', v_counts);
  end if;
  update app.privacy_jobs set state = 'approved' where id = v_id;
  return jsonb_build_object('job', v_id, 'state', 'done', 'counts', app.privacy_erase_run(v_id));
end $fn$;

create function public.privacy_approve(p_job uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); j app.privacy_jobs; v_emails text[];
begin
  perform app.require_fresh_mfa(10);
  select * into j from app.privacy_jobs where id = p_job and kind = 'erasure' for update;
  if not found or j.state <> 'previewed' then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if j.created_by = v_me then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self'; end if;
  v_emails := array(select distinct lower(btrim(email)) from app.people where id in (select x::uuid from jsonb_array_elements_text(j.subject -> 'people') x) and email is not null);
  if app.privacy_product_user(v_emails) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'product_user'; end if;
  update app.privacy_jobs set state = 'approved', approved_by = v_me where id = p_job;
  perform app.log('privacy.approved', 'privacy_job', p_job::text);
  return jsonb_build_object('job', p_job, 'state', 'done', 'counts', app.privacy_erase_run(p_job));
end $fn$;

create function public.privacy_jobs_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return coalesce((select jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'state', j.state, 'preview', j.preview, 'request_id', j.request_id,
                                                       'created_at', j.created_at, 'created_by', (select coalesce(a.name, a.email) from app.admins a where a.id = j.created_by),
                                                       'approved_by', (select coalesce(a.name, a.email) from app.admins a where a.id = j.approved_by),
                                                       'finished_at', j.finished_at, 'url_expires_at', j.url_expires_at, 'error', j.error) order by j.created_at desc)
                   from (select * from app.privacy_jobs order by created_at desc limit 100) j), '[]'::jsonb);
end $fn$;

-- ===========================================================================
-- retention (§2.6): each platform rule names its job; the last run comes from the job or pg_cron
-- ===========================================================================
insert into app.retention_rules (key, keep, basis, job_key, setting_key, ord) values
  ('crm_soft_deleted', interval '30 days', 'platform', 'platform-purge', null, 10),
  ('product_events_raw', interval '13 months', 'platform', 'platform-purge', null, 20),
  ('login_log', interval '60 days', 'platform', 'security-login-prune', null, 30),
  ('tickets_closed', interval '3 years', 'platform', 'security-retention-tickets', null, 40),
  ('email_bodies', interval '5 years', 'platform', 'security-retention-email', null, 50),
  ('meeting_recordings', interval '12 months', 'platform', 'platform-meeting-purge', 'rec_retention', 60),
  ('audit_log', interval '5 years', 'platform', 'security-audit-purge', null, 70),
  ('erasure_tombstones', interval '13 months', 'platform', 'security-login-prune', null, 80),
  ('survey_responses', null, 'product', null, null, 90);

create function public.retention_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return coalesce((select jsonb_agg(jsonb_build_object('key', r.key, 'keep', r.keep::text, 'basis', r.basis, 'job', r.job_key,
                     'setting', case when r.setting_key is not null then jsonb_build_object('key', r.setting_key, 'value', app.setting(r.setting_key)) end,
                     'in_force', r.basis = 'platform' and exists (select 1 from cron.job c where c.jobname = r.job_key and c.active),
                     'last_run_at', coalesce(r.last_run_at, (select max(d.end_time) from cron.job_run_details d join cron.job c on c.jobid = d.jobid
                                                             where c.jobname = r.job_key and d.status = 'succeeded')),
                     'last_purged', r.last_purged) order by r.ord)
                   from app.retention_rules r), '[]'::jsonb);
end $fn$;

create function app.retention_mark(p_key text, p_purged bigint) returns void
  language sql volatile security definer set search_path = ''
as $fn$
  update app.retention_rules set last_run_at = now(), last_purged = p_purged where key = p_key;
$fn$;

-- ===========================================================================
-- sub-processors (§2.6, Q8)
-- ===========================================================================
create function public.subprocessors_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return coalesce((select jsonb_agg(to_jsonb(s) order by s.removed_at nulls first, s.ord, s.name) from app.subprocessors s), '[]'::jsonb);
end $fn$;

create function public.subprocessor_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); s app.subprocessors;
begin
  if jsonb_typeof(p_values) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  if p_id is not null then
    select * into s from app.subprocessors where id = p_id for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and p_version <> s.version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = s.version::text; end if;
  end if;
  begin
    s.name := btrim(coalesce(p_values ->> 'name', s.name));
    s.purpose := btrim(coalesce(p_values ->> 'purpose', s.purpose));
    s.region := case when p_values ? 'region' then nullif(btrim(p_values ->> 'region'), '') else s.region end;
    s.in_use_since := coalesce((p_values ->> 'in_use_since')::date, s.in_use_since, current_date);
    s.removed_at := case when p_values ? 'removed_at' then (p_values ->> 'removed_at')::date else s.removed_at end;
    s.public := coalesce((p_values ->> 'public')::boolean, s.public, true);
    s.ord := coalesce((p_values ->> 'ord')::int, s.ord, 0);
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end;
  if char_length(coalesce(s.name, '')) not between 1 and 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if char_length(coalesce(s.purpose, '')) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'purpose'; end if;
  if char_length(s.region) > 60 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'region'; end if;
  if s.public and s.region is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'region'; end if;
  if exists (select 1 from app.subprocessors x where lower(x.name) = lower(s.name) and x.id is distinct from p_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
  end if;
  if p_id is null then
    insert into app.subprocessors (name, purpose, region, in_use_since, removed_at, public, ord)
    values (s.name, s.purpose, s.region, s.in_use_since, s.removed_at, s.public, s.ord) returning * into s;
  else
    update app.subprocessors set name = s.name, purpose = s.purpose, region = s.region, in_use_since = s.in_use_since, removed_at = s.removed_at,
      public = s.public, ord = s.ord, version = version + 1 where id = p_id returning * into s;
  end if;
  perform app.log('subprocessor.saved', 'subprocessor', s.id::text, jsonb_build_object('created', p_id is null, 'public', s.public));
  return to_jsonb(s);
end $fn$;

-- the public list (Q8): served by the public host's server with the service role, cached; never anon (structure_invariants)
create function public.subprocessors_public() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'purpose', s.purpose, 'region', s.region, 'in_use_since', s.in_use_since) order by s.ord, s.name), '[]'::jsonb)
  from app.subprocessors s where s.public and s.removed_at is null and s.region is not null
$fn$;

-- ===========================================================================
-- incidents and the 72-hour clock
-- ===========================================================================
create function app.incident_row(i app.security_incidents) returns jsonb
  language sql stable set search_path = ''
as $fn$
  select to_jsonb(i) || jsonb_build_object(
    'hours_left', case when i.state = 'investigating' then greatest(0, ceil(extract(epoch from i.notify_deadline - now()) / 3600))::int end,
    'elapsed_pct', case when i.state = 'investigating' then least(100, greatest(0, round(extract(epoch from now() - i.detected_at) / (72 * 36))))::int else 100 end,
    'logged_by_name', (select coalesce(a.name, a.email) from app.admins a where a.id = i.logged_by))
$fn$;

create function public.incidents_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return coalesce((select jsonb_agg(app.incident_row(i) order by (i.state = 'investigating') desc, i.detected_at desc) from app.security_incidents i), '[]'::jsonb);
end $fn$;

-- p_values: {title, summary, detected_at, personal_data, state, notified_at, notified_ref, ticket_id}
create function public.incident_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); i app.security_incidents; v_new boolean := p_id is null;
begin
  if jsonb_typeof(p_values) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  if not v_new then
    select * into i from app.security_incidents where id = p_id for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and p_version <> i.version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = i.version::text; end if;
  end if;
  begin
    i.title := btrim(coalesce(p_values ->> 'title', i.title));
    i.summary := coalesce(p_values ->> 'summary', i.summary, '');
    i.detected_at := coalesce((p_values ->> 'detected_at')::timestamptz, i.detected_at, now());
    i.personal_data := coalesce((p_values ->> 'personal_data')::boolean, i.personal_data, false);
    i.state := coalesce(p_values ->> 'state', i.state, 'investigating');
    i.notified_ref := case when p_values ? 'notified_ref' then nullif(btrim(p_values ->> 'notified_ref'), '') else i.notified_ref end;
    i.notified_at := case when p_values ? 'notified_at' then (p_values ->> 'notified_at')::timestamptz else i.notified_at end;
    i.ticket_id := case when p_values ? 'ticket_id' then (p_values ->> 'ticket_id')::uuid else i.ticket_id end;
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end;
  if char_length(coalesce(i.title, '')) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  if char_length(i.summary) > 2000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'summary'; end if;
  if i.detected_at > now() + interval '5 minutes' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'detected_at'; end if;
  if i.state not in ('investigating', 'assessed_not_notifiable', 'notified', 'closed') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if char_length(i.notified_ref) > 120 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'notified_ref'; end if;
  if i.ticket_id is not null and not exists (select 1 from app.tickets where id = i.ticket_id) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ticket_id'; end if;
  if i.state = 'notified' then i.notified_at := coalesce(i.notified_at, now()); end if;
  i.closed_at := case when i.state = 'closed' then coalesce(i.closed_at, now()) when i.state = 'investigating' then null else i.closed_at end;
  if v_new then
    insert into app.security_incidents (title, summary, detected_at, logged_by, personal_data, state, notified_at, notified_ref, closed_at, ticket_id)
    values (i.title, i.summary, i.detected_at, v_me, i.personal_data, i.state, i.notified_at, i.notified_ref, i.closed_at, i.ticket_id) returning * into i;
    perform app.security_event('incident_logged', case when i.personal_data then 'critical' else 'high' end, null, v_me, jsonb_build_object('incident', i.id));
    perform app.emit('incident.logged', 'security_incident', i.id, jsonb_build_object('personal_data', i.personal_data));
  else
    update app.security_incidents set title = i.title, summary = i.summary, detected_at = i.detected_at, personal_data = i.personal_data, state = i.state,
      notified_at = i.notified_at, notified_ref = i.notified_ref, closed_at = i.closed_at, ticket_id = i.ticket_id, version = version + 1
    where id = p_id returning * into i;
  end if;
  perform app.log('incident.saved', 'security_incident', i.id::text, jsonb_build_object('created', v_new, 'state', i.state, 'personal_data', i.personal_data,
                  'fields', to_jsonb(array(select jsonb_object_keys(p_values) order by 1))));
  return app.incident_row(i);
end $fn$;

-- job incident_clock (hourly): at 48 h and 66 h without a decision, global:security is told
create function app.incident_clock() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare i app.security_incidents; r uuid; n int := 0; v_mark text;
begin
  for i in select * from app.security_incidents where state = 'investigating' and detected_at <= now() - interval '48 hours'
           and (notice_48_at is null or (notice_66_at is null and detected_at <= now() - interval '66 hours')) for update skip locked loop
    v_mark := case when i.detected_at <= now() - interval '66 hours' and i.notice_66_at is null then '66' else '48' end;
    for r in select * from app.security_recipients() loop
      perform app.notify(r, 'security', 'security.incident_deadline', jsonb_build_object('incident', i.id, 'hours', v_mark::int,
                         'hours_left', greatest(0, ceil(extract(epoch from i.notify_deadline - now()) / 3600))::int), '/security');
    end loop;
    update app.security_incidents set notice_48_at = coalesce(notice_48_at, now()), notice_66_at = case when v_mark = '66' then now() else notice_66_at end where id = i.id;
    perform app.emit('incident.deadline_near', 'security_incident', i.id, jsonb_build_object('hours', v_mark::int));
    n := n + 1;
  end loop;
  return n;
end $fn$;

-- ===========================================================================
-- the audit log (SEC-11; D-12): search with kind, source and principal; «What» is the target's current title
-- ===========================================================================
create function app.audit_target(p_type text, p_id text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities; v_exists boolean; v_title text;
begin
  if p_type is null or p_id is null then return null; end if;
  select * into e from app.entities where key = p_type;
  if not found then return jsonb_build_object('state', 'other'); end if;
  if p_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return jsonb_build_object('state', 'removed'); end if;
  execute format('select true from app.%I t where t.id = %L and t.deleted_at is null', e.tbl, p_id) into v_exists;
  if v_exists is null then return jsonb_build_object('state', 'removed'); end if;
  v_title := app.record_title(e.key, p_id::uuid);
  return case when v_title is null then jsonb_build_object('state', 'hidden') else jsonb_build_object('state', 'ok', 'title', v_title) end;
end $fn$;

-- p_filter: {q, kind, source, staff_id, from, to}; cursor = the last id of the previous page
create function public.audit_search(p_filter jsonb default '{}'::jsonb, p_cursor bigint default null, p_limit int default 50) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'security');
  f jsonb := coalesce(p_filter, '{}'::jsonb);
  v_q text := nullif(btrim(f ->> 'q'), '');
  v_kind text := nullif(f ->> 'kind', '');
  v_source text := nullif(f ->> 'source', '');
  v_staff uuid; v_from timestamptz; v_to timestamptz; v_rows jsonb; v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter'; end if;
  if v_kind is not null and v_kind not in ('read', 'write', 'export', 'role', 'security') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if v_source is not null and v_source not in ('web', 'api', 'mcp', 'workflow', 'ticket', 'support_access', 'mobile', 'import', 'product', 'system') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source';
  end if;
  if char_length(v_q) > 100 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'q'; end if;
  begin
    v_staff := nullif(f ->> 'staff_id', '')::uuid;
    v_from := nullif(f ->> 'from', '')::timestamptz;
    v_to := nullif(f ->> 'to', '')::timestamptz;
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter';
  end;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'at', a.at, 'kind', a.kind, 'action', coalesce(a.action, a.command), 'command', a.command is not null, 'ok', a.ok,
           'staff_id', a.staff_id, 'who', coalesce(s.name, case when a.staff_id is null then null else a.actor end),
           'principal_kind', a.principal_kind, 'principal_id', a.principal_id,
           'workflow', case when a.principal_kind = 'workflow' then (select w.name from app.workflows w where w.id = a.principal_id) end,
           'source', a.source, 'target_type', a.target_type, 'target_id', a.target_id, 'target', app.audit_target(a.target_type, a.target_id),
           'organization', o.name, 'account_id', a.account_id, 'reason', a.reason is not null) order by a.id desc), '[]'::jsonb)
    into v_rows
  from (select x.* from app.audit x
        left join app.admins sx on sx.id = x.staff_id
        left join lateral (select ox.name from app.organizations ox where ox.account_id = x.account_id order by ox.created_at limit 1) oxn on true
        where (p_cursor is null or x.id < p_cursor) and (v_kind is null or x.kind = v_kind) and (v_source is null or x.source = v_source)
          and (v_staff is null or x.staff_id = v_staff) and (v_from is null or x.at >= v_from) and (v_to is null or x.at < v_to)
          and (v_q is null or sx.name ilike '%' || v_q || '%' or oxn.name ilike '%' || v_q || '%' or coalesce(x.action, x.command) ilike '%' || v_q || '%')
        order by x.id desc limit v_limit) a
  left join app.admins s on s.id = a.staff_id
  left join lateral (select o2.name from app.organizations o2 where o2.account_id = a.account_id order by o2.created_at limit 1) o on true;
  perform app.log('audit.searched', null, null, jsonb_build_object('filter', to_jsonb(array(select k from jsonb_object_keys(f) k order by 1)),
                                                                   'rows', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'next', case when jsonb_array_length(v_rows) = v_limit then (v_rows -> (v_limit - 1) ->> 'id')::bigint end,
                            'typed_reason', app.setting('typed_reason'));
end $fn$;

-- ===========================================================================
-- jobs (§3.11)
-- ===========================================================================
-- sessions_expire (every 5 min): idle, deactivated, outside the hours, outside the IP rules
create function app.sessions_expire() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s record; n int := 0; v_reason text; v_ranges cidr[] := app.ip_ranges();
begin
  for s in select ss.session_id, ss.staff_id, ss.last_seen_at, ss.last_ip_sealed, a.active
           from app.staff_sessions ss join app.admins a on a.id = ss.staff_id where ss.ended_at is null for update of ss skip locked loop
    v_reason := case
      when not s.active then 'deactivated'
      when app.setting('session_idle') = 'on_30' and s.last_seen_at < now() - interval '30 minutes' then 'idle_timeout'
      when not app.time_allowed(now()) then 'time_rule'
      when app.setting('ip_allowlist') = 'on' and not app.ip_match(app.ip_open(s.last_ip_sealed), v_ranges) then 'ip_rule' end;
    if v_reason is not null and app.session_end(s.session_id, v_reason, null) then n := n + 1; end if;
  end loop;
  return n;
end $fn$;

-- login_log_prune (daily): the log and ended sessions after 60 days, attempts after a day, tombstones after 13 months
create function app.security_prune() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n_log bigint; n_sess bigint; n_tomb bigint;
begin
  delete from app.login_log where at < now() - interval '60 days';
  get diagnostics n_log = row_count;
  delete from app.staff_sessions where ended_at < now() - interval '60 days';
  get diagnostics n_sess = row_count;
  delete from app.recovery_attempts where at < now() - interval '1 day';
  delete from app.erasure_tombstones where erased_at < now() - interval '13 months';
  get diagnostics n_tomb = row_count;
  perform app.retention_mark('login_log', n_log + n_sess);
  perform app.retention_mark('erasure_tombstones', n_tomb);
  insert into app.audit (actor, action, ok, detail) values ('system', 'job.purged', true,
    jsonb_build_object('rule', 'login_log', 'login_log', n_log, 'sessions', n_sess, 'tombstones', n_tomb));
  return jsonb_build_object('login_log', n_log, 'sessions', n_sess, 'tombstones', n_tomb);
end $fn$;

-- audit_purge (monthly): rows older than five years, through the guard's one door
create function app.purge_audit() returns bigint
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n bigint;
begin
  perform set_config('app.purging', 'on', true);
  delete from app.audit where at < now() - interval '5 years';
  get diagnostics n = row_count;
  perform set_config('app.purging', '', true);
  perform app.retention_mark('audit_log', n);
  insert into app.audit (actor, action, ok, detail) values ('system', 'job.purged', true, jsonb_build_object('rule', 'audit_log', 'rows', n));
  return n;
end $fn$;

-- retention_tickets (daily): tickets closed more than three years ago, with their history
create function app.retention_tickets() returns bigint
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n bigint;
begin
  perform set_config('app.purging', 'on', true);
  with d as (delete from app.tickets where closed_at < now() - interval '3 years' returning id),
       c as (delete from app.changelog l using d where l.entity = 'ticket' and l.record_id = d.id)
  select count(*) into n from d;
  perform set_config('app.purging', '', true);
  perform app.retention_mark('tickets_closed', n);
  insert into app.audit (actor, action, ok, detail) values ('system', 'job.purged', true, jsonb_build_object('rule', 'tickets_closed', 'rows', n));
  return n;
end $fn$;

-- retention_email_bodies (daily): the bodies of messages older than five years; headers and threads stay
create function app.retention_email_bodies() returns bigint
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n bigint;
begin
  update app.email_messages set body_text = null, body_html = null
  where coalesce(sent_at, received_at, created_at) < now() - interval '5 years' and (body_text is not null or body_html is not null);
  get diagnostics n = row_count;
  perform app.retention_mark('email_bodies', n);
  insert into app.audit (actor, action, ok, detail) values ('system', 'job.purged', true, jsonb_build_object('rule', 'email_bodies', 'rows', n));
  return n;
end $fn$;

select cron.schedule('security-alerts', '* * * * *', 'select app.security_alerts_run()');
select cron.schedule('security-digest', '*/15 * * * *', 'select app.security_digest_due()');
select cron.schedule('security-sessions-expire', '*/5 * * * *', 'select app.sessions_expire()');
select cron.schedule('security-login-prune', '33 3 * * *', 'select app.security_prune()');
select cron.schedule('security-incident-clock', '11 * * * *', 'select app.incident_clock()');
select cron.schedule('security-access-review-due', '27 6 * * *', 'select app.access_review_due()');
select cron.schedule('security-audit-purge', '47 4 1 * *', 'select app.purge_audit()');
select cron.schedule('security-retention-tickets', '53 4 * * *', 'select app.retention_tickets()');
select cron.schedule('security-retention-email', '57 4 * * *', 'select app.retention_email_bodies()');
select cron.schedule('security-backup-poll', '7 * * * *', $$select pgmq.send('jobs', '{"job": "ops_backup_poll"}'::jsonb)$$);

-- ===========================================================================
-- closed: RLS on, no policy, no client grant; functions for staff, workers for the service role, helpers for nobody
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array['login_log', 'staff_sessions', 'staff_devices', 'staff_locations', 'security_rules', 'security_events',
                           'security_alert_deliveries', 'security_alert_recipients', 'access_reviews', 'access_review_items', 'sso_providers',
                           'password_changes', 'recovery_attempts', 'ops_checks', 'platform_facts', 'security_incidents', 'subprocessors',
                           'retention_rules', 'privacy_jobs', 'erasure_tombstones'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.audit_kind(text, text)', 'app.plus_72h(timestamptz)', 'app.audit_source()', 'app.audit_principal_kind()', 'app.audit_principal_id()', 'app.audit_stamp()',
                           'app.audit_guard()', 'app.log(text, text, text, jsonb, uuid)', 'app.security_event_guard()', 'app.ops_check_guard()',
                           'app.setting_number(text, numeric)', 'app.current_session()', 'app.require_fresh_mfa(int)', 'app.staff_has_security(uuid)',
                           'app.staff_mfa_verified(text)', 'app.ip_key(boolean)', 'app.ip_seal(inet)', 'app.ip_open(bytea)', 'app.device_label(text)',
                           'app.ip_ranges()', 'app.ip_match(inet, cidr[])', 'app.window_match(timestamptz, smallint[], time, time)', 'app.time_windows()',
                           'app.windows_match(timestamptz, jsonb)', 'app.ip_allowed(inet)', 'app.time_allowed(timestamptz)', 'app.my_ip()',
                           'app.session_ok(uuid)', 'app.session_end(uuid, text, uuid)', 'app.staff_session_guard()', 'app.login_log_guard()',
                           'app.sessions_enforce_ip(cidr[])', 'app.ip_allowlist_guard(text, text, text, text)', 'app.signin_hours_guard(text, text, text, text)',
                           'app.password_reuse_guard(text, text, text, text)', 'app.security_alert_key(text)',
                           'app.security_event(text, text, uuid, uuid, jsonb)', 'app.security_recipients()', 'app.security_deliver(bigint, boolean)',
                           'app.security_alerts_run()', 'app.security_digest_due(timestamptz)', 'app.sub_security_alerts(app.events)',
                           'app.admins_security_watch()', 'app.person_tombstoned()', 'app.access_review_next_due()', 'app.security_issues()',
                           'app.security_rule_row(app.security_rules)', 'app.security_self_check()', 'app.access_review_due()',
                           'app.privacy_subject(jsonb)', 'app.privacy_counts(uuid[], uuid[], text[])', 'app.privacy_product_user(text[])',
                           'app.privacy_erase_run(uuid)', 'app.retention_mark(text, bigint)', 'app.incident_row(app.security_incidents)',
                           'app.incident_clock()', 'app.audit_target(text, text)', 'app.sessions_expire()', 'app.security_prune()', 'app.purge_audit()',
                           'app.retention_tickets()', 'app.retention_email_bodies()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.setting_set(text, text, text, numeric)', 'public.security_dashboard()', 'public.session_revoke(uuid, text)',
                           'public.staff_sessions_revoke_all(uuid, text)', 'public.my_sessions()', 'public.login_history(uuid, int)',
                           'public.security_rules_get()', 'public.security_rule_save(uuid, jsonb, int)', 'public.security_rule_delete(uuid)',
                           'public.security_rule_preview(jsonb)', 'public.alerts_get()', 'public.alert_recipients_set(uuid[])', 'public.sso_get()',
                           'public.sso_set(text, boolean, text[])', 'public.mfa_overview()', 'public.recovery_codes_generate()',
                           'public.recovery_code_redeem(text)', 'public.staff_mfa_reset(uuid, text)', 'public.staff_mfa_reminder(uuid)',
                           'public.access_review_start()', 'public.access_review_get(uuid)', 'public.access_review_decide(uuid, uuid, text)',
                           'public.access_review_complete(uuid)', 'public.firewall_status()', 'public.protection_get()',
                           'public.restore_test_record(timestamptz, boolean, int, int, text)', 'public.privacy_find(text)', 'public.privacy_preview(jsonb)',
                           'public.privacy_export(jsonb, uuid, text)', 'public.privacy_export_url(uuid)', 'public.privacy_erase(jsonb, uuid, text, text)',
                           'public.privacy_approve(uuid)', 'public.privacy_jobs_get()', 'public.retention_get()', 'public.subprocessors_get()',
                           'public.subprocessor_save(uuid, jsonb, int)', 'public.incidents_get()', 'public.incident_save(uuid, jsonb, int)',
                           'public.audit_search(jsonb, bigint, int)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_login_event(jsonb)', 'public.worker_session_seen(uuid, inet, text)', 'public.worker_password_reset(text)',
                           'public.worker_password_changed(text)', 'public.worker_sso_configured(text, boolean)', 'public.worker_backup_seen(jsonb)',
                           'public.worker_privacy_package(uuid)', 'public.worker_privacy_done(uuid, text, text)', 'public.subprocessors_public()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
