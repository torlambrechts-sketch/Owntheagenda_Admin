-- 0044_platform.sql — the Platform and Mobile screens (Phase 8): applications and their health, the REST API with personal
-- tokens and OAuth apps, webhooks, the integration catalog, the AI connector (MCP), the job monitor, feature flags and the
-- status banner, content; the mobile views' own data (push devices, notification preferences, offline sync, places);
-- the production sandbox loader (R-SETTINGS-03) and revertable bulk changes (Contacts R-6).
-- Spec: docs/crm-enrichment/specs/platform-security-mobile.md §1, §3.2, §3.4–§3.12, §4–§8. Designs:
-- design-reference/sentral/project/Platform.dc.html, Mobile.dc.html. Departures: docs/crm-enrichment/deviations/platform-schema.md.
--
-- Nothing external is connected: no push provider (VAPID key), no OAuth client, no webhook target, no geocoder, no
-- product ping. The database models every flow and the worker_* functions (service role) stand in for the edge workers:
-- a worker reports what happened and the database decides what may happen next.
--
-- Identity (§3.9). app.me() gains a token branch: inside public.api_exec (service role only) the transaction carries
-- app.api_principal = 'token:<id>' or 'grant:<id>', and app.me() answers with that token's or grant's staff member while
-- the token is live, the grant unexpired, the staff member active and, for an assistant (MCP), mcp_access on. app.can()
-- then intersects the staff member's rights with the token's scopes, and global:security / global:configure are never
-- reachable through a token. A client cannot set the setting and only the service role can call api_exec. For a normal
-- staff session nothing changes: the JWT branch is 0021's, plus the session check of §3.9 through 0043's
-- app.session_ok(app.current_session()) when the JWT names a session (a JWT without a session claim is checked as before).
-- 0043 also provides app.require_fresh_mfa, settings_registry.hook (mcp_access → app.mcp_access_effect) and the audit's
-- source and principal, which app.log reads from the settings api_exec and sync_apply set.
--
-- Secrets. API tokens, OAuth codes, access and refresh tokens and client secrets are stored as SHA-256 only, returned once.
-- A webhook's signing secret lives in Vault and never leaves the database: the delivery is signed here
-- (HMAC-SHA256 over «t.body», D-32) and handed to the worker with its header. The delivery log keeps the envelope
-- (event, object, id, attempt, the names of the changed fields) and a hash of the body, never the record's values.
--
-- Every job runs through app.run_job, which writes job_runs; a failure notifies global:configure and emits job.failed.

-- ===========================================================================
-- §3.2 changes to existing objects
-- ===========================================================================
-- products and installations (Applications)
alter table app.products add column stage text not null default 'ga' check (stage in ('ga', 'beta'));
alter table app.installations
  add column region       text check (region is null or char_length(btrim(region)) between 1 and 60),
  add column api_version  text check (api_version is null or char_length(api_version) between 1 and 40),
  add column scopes       text[] not null default '{}' check (scopes <@ array['orgs:read', 'orgs:write', 'billing:read', 'billing:write',
                            'translations:read', 'translations:write', 'modules:read', 'modules:write', 'legal:read', 'legal:write',
                            'settings:read', 'settings:write']),
  add column created_at   timestamptz not null default now(),
  add column connected_by uuid references app.admins (id) on delete set null,
  add column last_ping_at timestamptz,
  add column last_ping_ms int check (last_ping_ms is null or last_ping_ms >= 0),
  add column last_ping_ok boolean,
  add column last_ping_status int check (last_ping_status is null or last_ping_status between 0 and 599);
-- an installation already running keeps every scope it uses today; connected since its first event
update app.installations i set
  scopes = array['orgs:read', 'orgs:write', 'billing:read', 'billing:write', 'translations:read', 'translations:write', 'modules:read',
                 'modules:write', 'legal:read', 'legal:write', 'settings:read', 'settings:write'],
  created_at = least(i.updated_at, coalesce((select min(e.received_at) from app.events_in e where e.product = i.product), i.updated_at));

-- an intake number opened for a new product may store only that product's two secrets, and never overwrites one
alter table app.intake_nonces add column product text references app.products (key) on delete cascade;

-- the mobile client as a changelog source (0042's list plus «mobile»)
alter table app.changelog drop constraint changelog_source_check;
alter table app.changelog add constraint changelog_source_check
  check (source in ('ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system', 'merge', 'enrichment', 'capture', 'meeting', 'mobile'));

-- notifications: an assignment and a chat request as kinds of their own, and once-only delivery (MOB-07)
alter table app.notifications drop constraint notifications_kind_check;
alter table app.notifications add constraint notifications_kind_check
  check (kind in ('mention', 'reminder', 'security', 'system', 'assignment', 'chat_request'));
alter table app.notifications add column dedupe_key text unique check (dedupe_key is null or char_length(dedupe_key) between 1 and 120);

-- the Nearby check-in (MOB-03)
insert into app.activity_types (key, name, glyph, ord, is_system) values ('visit', 'Visit', '⌖', 80, true) on conflict (key) do nothing;

-- ===========================================================================
-- identity (§3.9): the token branch of app.me(), the scope check of app.can(), fresh MFA, owner
-- ===========================================================================
-- the staff member behind a principal ('token:<id>' | 'grant:<id>'), or null when it is revoked, expired, its staff member
-- inactive, its app disabled, or it is an assistant while mcp_access is off (MCP-03: no call succeeds after switch-off)
create function app.principal_staff(p_principal text) returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid; v_kind text := split_part(coalesce(p_principal, ''), ':', 1); v_id text := split_part(coalesce(p_principal, ''), ':', 2);
begin
  if v_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return null; end if;
  if v_kind = 'token' then
    select t.staff_id into v from app.api_tokens t join app.admins a on a.id = t.staff_id
    where t.id = v_id::uuid and t.revoked_at is null and (t.expires_at is null or t.expires_at > now()) and a.active;
  elsif v_kind = 'grant' then
    select g.staff_id into v from app.oauth_grants g join app.oauth_apps ap on ap.id = g.app_id join app.admins a on a.id = g.staff_id
    where g.id = v_id::uuid and g.revoked_at is null and g.access_expires_at > now() and ap.disabled_at is null and a.active
      and (ap.kind <> 'mcp' or app.setting('mcp_access') = 'on');
  end if;
  return v;
end $fn$;

-- may this principal use this right? Its scopes ('*' = everything its staff member may, else api_scopes); never the
-- security or configuration rights (§3.8)
create function app.principal_allows(p_principal text, p_right text) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_scopes text[]; v_kind text := split_part(coalesce(p_principal, ''), ':', 1); v_id text := split_part(coalesce(p_principal, ''), ':', 2);
begin
  if p_right in ('global:security', 'global:configure') then return false; end if;
  if v_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  v_scopes := case v_kind when 'token' then (select t.scopes from app.api_tokens t where t.id = v_id::uuid)
                          when 'grant' then (select g.scopes from app.oauth_grants g where g.id = v_id::uuid) end;
  if v_scopes is null then return false; end if;
  if '*' = any (v_scopes) then return true; end if;
  return exists (select 1 from app.api_scopes s where s.scope = any (v_scopes) and p_right = any (s.rights));
end $fn$;

-- who is asking: acting_as inside a database-internal session (0021), a token principal inside api_exec, else an aal2 JWT
-- (0021) whose session, when it names one, app.session_ok (0043) accepts
create or replace function app.me() returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid; v_p text := nullif(current_setting('app.api_principal', true), ''); v_claims text;
begin
  if session_user not in ('authenticator', 'anon', 'authenticated', 'service_role') and nullif(current_setting('app.acting_as', true), '') is not null then
    select a.id into v from app.admins a where a.id = nullif(current_setting('app.acting_as', true), '')::uuid and a.active;
    if v is not null then return v; end if;
  end if;
  if v_p is not null then
    v_claims := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}');
    if v_claims::jsonb ->> 'role' = 'service_role' then return app.principal_staff(v_p); end if;
    return null;                                            -- a principal outside the service role is nobody
  end if;
  select a.id into v from app.admins a join auth.users u on lower(u.email) = a.email
  where u.id = auth.uid() and u.email_confirmed_at is not null and a.active and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
  -- the session check (§3.9 item 1, 0043): a JWT that names a session the session register refuses (ended, idle, outside the
  -- sign-in hours) is nobody; a JWT without a session claim is checked as before
  if v is null or (app.current_session() is not null and not app.session_ok(app.current_session())) then return null; end if;
  return v;
end $fn$;

-- may the caller do this action in this scope? Inside a token principal, also within the token's scopes
create or replace function app.can(p_scope text, p_action text) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_ok boolean; v_p text := nullif(current_setting('app.api_principal', true), '');
begin
  select (ps.kind = 'admin' or (p_scope || ':' || p_action) = any (ps.rights)) into v_ok
  from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = app.me();
  if not coalesce(v_ok, false) then return false; end if;
  if v_p is null then return true; end if;
  return app.principal_allows(v_p, p_scope || ':' || p_action);
end $fn$;

-- the owner (admins.role = 'owner'), D-11
create function app.require_owner() returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid := app.require_staff();
begin
  if not exists (select 1 from app.admins a where a.id = v and a.role = 'owner') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'owner_only';
  end if;
  return v;
end $fn$;

-- a number from the register: the custom number when the key is set to its numeric option, else the source value
create function app.setting_num(p_key text, p_source numeric) returns numeric
  language sql stable security definer set search_path = ''
as $fn$
  select case when app.setting(p_key) = r.numeric_option
              then coalesce((select v.value_number from app.setting_values v where v.key = p_key and v.scope_id = ''), p_source)
              else p_source end
  from app.settings_registry r where r.key = p_key
$fn$;

-- a random token: prefix plus base62 of 32 random bytes (§3.12.1)
create function app.random_token(p_prefix text, p_bytes int default 32) returns text
  language sql volatile set search_path = ''
as $fn$
  select p_prefix || string_agg(substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (get_byte(b, i) % 62) + 1, 1), '' order by i)
  from (select extensions.gen_random_bytes(greatest(p_bytes, 16)) b) r, generate_series(0, greatest(p_bytes, 16) - 1) i
$fn$;

-- ===========================================================================
-- §3.4 tables: applications, API, OAuth, webhooks, catalog, MCP, jobs
-- ===========================================================================
-- every call between Sentral and a product, both directions (commands out, event batches in); kinds, times and codes only
create table app.integration_calls (
  id          bigint generated always as identity primary key,
  product     text not null references app.products (key) on delete cascade,
  direction   text not null check (direction in ('out', 'in')),
  kind        text not null check (kind ~ '^[a-z_]+\.[a-z_]+$'),
  at          timestamptz not null default now(),
  duration_ms int check (duration_ms is null or duration_ms >= 0),
  ok          boolean not null,
  status      int check (status is null or status between 0 and 599),
  error_code  text check (error_code is null or error_code ~ '^[a-z0-9_.:-]{1,60}$')
);
create index integration_calls_product on app.integration_calls (product, at desc);

-- what a product's events are used for (data, not code), and the commands Sentral may call: a mirror of
-- supabase/functions/_shared/orgpuls.ts (the TS list stays the authority; tests/product-commands.test.ts asserts equality)
create table app.product_event_kinds (
  product   text not null references app.products (key) on delete cascade,
  kind      text not null check (kind ~ '^[a-z_]+\.[a-z_]+$'),
  uses      text[] not null default '{}' check (uses <@ array['crm', 'funnel', 'billing', 'health', 'activation', 'usage', 'tickets', 'leads', 'workflows', 'support_access']),
  label_key text not null check (label_key ~ '^[a-z][a-zA-Z0-9_.]{1,80}$'),
  primary key (product, kind)
);
create table app.product_commands (
  product     text not null references app.products (key) on delete cascade,
  command     text not null check (command ~ '^[a-z]+\.[a-z_]+$'),
  scope       text not null check (scope ~ '^[a-z]+:(read|write)$'),
  used_by     text[] not null default '{}' check (used_by <@ array['applications', 'customers', 'tickets', 'flags', 'content', 'settings', 'privacy']),
  destructive boolean not null default false,
  primary key (product, command)
);

-- the banner a product shows (settings.set_notice), with its history; a notice linked to a problem ticket is cleared when the
-- problem is resolved (Tickets R-4's banner half)
create table app.status_notices (
  id                uuid primary key default gen_random_uuid(),
  product           text not null references app.products (key) on delete cascade,
  text              text check (text is null or char_length(text) <= 500),
  maintenance       boolean not null default false,
  problem_ticket_id uuid references app.tickets (id) on delete set null,
  set_by            uuid references app.admins (id) on delete set null,
  set_at            timestamptz not null default now(),
  cleared_at        timestamptz,
  pushed_at         timestamptz,
  push_error        text check (push_error is null or push_error ~ '^[a-z0-9_.:-]{1,60}$')
);
create index status_notices_product on app.status_notices (product, set_at desc);

-- the outbox kinds, as data: which may be subscribed by a webhook and which start a workflow (R-AUTOMATION-04)
create table app.event_catalog (
  kind             text primary key check (kind ~ '^[a-z_]+\.[a-z_]+$'),
  family           text not null check (family ~ '^[a-z_]{2,40}$'),
  entity           text references app.entities (key) on delete cascade,
  webhookable      boolean not null default false,
  workflow_trigger boolean not null default true,
  label_key        text not null check (label_key ~ '^[a-z][a-zA-Z0-9_.]{1,80}$')
);

-- personal tokens (INT-02): one active per staff member, SHA-256 only
create table app.api_tokens (
  id            uuid primary key default gen_random_uuid(),
  staff_id      uuid not null references app.admins (id) on delete cascade,
  name          text not null check (char_length(btrim(name)) between 1 and 80),
  token_sha256  bytea not null unique check (length(token_sha256) = 32),
  prefix        text not null default 'sk_live_' check (prefix = 'sk_live_'),
  last4         text not null check (last4 ~ '^[0-9A-Za-z]{4}$'),
  scopes        text[] not null default '{*}' check (cardinality(scopes) between 1 and 20),
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz,
  expires_at    timestamptz,
  revoked_at    timestamptz,
  revoked_by    uuid references app.admins (id) on delete set null,
  revoke_reason text check (revoke_reason is null or revoke_reason in ('rotated', 'revoked', 'staff_deactivated', 'mfa_reset')),
  is_sample     boolean not null default false,
  check ((revoked_at is null) = (revoke_reason is null))
);
create unique index api_tokens_one_active on app.api_tokens (staff_id) where revoked_at is null;

-- what a scope lets a token do; '*' = everything its staff member may (except security and configuration)
create table app.api_scopes (
  scope  text primary key check (scope ~ '^[a-z_]+:(read|write)$|^\*$'),
  rights text[] not null check (app.rights_ok(rights) and not (rights && array['global:security', 'global:configure'])),
  ord    int not null default 0
);

-- OAuth apps (integrations, extensions) and dynamically registered assistants (kind mcp, public, PKCE)
create table app.oauth_apps (
  id                   uuid primary key default gen_random_uuid(),
  client_id            text not null unique check (client_id ~ '^client_[A-Za-z0-9]{16,40}$'),
  name                 text not null check (char_length(btrim(name)) between 1 and 80),
  kind                 text not null check (kind in ('integration', 'mcp', 'extension')),
  owner_id             uuid references app.admins (id) on delete set null,
  redirect_uris        text[] not null check (cardinality(redirect_uris) between 1 and 10),
  client_secret_sha256 bytea check (client_secret_sha256 is null or length(client_secret_sha256) = 32),
  allowed_scopes       text[] not null check (cardinality(allowed_scopes) between 1 and 20),
  dynamic              boolean not null default false,
  created_at           timestamptz not null default now(),
  disabled_at          timestamptz,
  check (kind <> 'mcp' or client_secret_sha256 is null),
  check (not dynamic or kind = 'mcp')
);
create table app.oauth_codes (
  code_sha256    bytea primary key check (length(code_sha256) = 32),
  app_id         uuid not null references app.oauth_apps (id) on delete cascade,
  staff_id       uuid not null references app.admins (id) on delete cascade,
  scopes         text[] not null,
  redirect_uri   text not null check (char_length(redirect_uri) <= 2000),
  code_challenge text not null check (code_challenge ~ '^[A-Za-z0-9_-]{43,128}$'),
  expires_at     timestamptz not null,
  used_at        timestamptz
);
create table app.oauth_grants (
  id                 uuid primary key default gen_random_uuid(),
  app_id             uuid not null references app.oauth_apps (id) on delete cascade,
  staff_id           uuid not null references app.admins (id) on delete cascade,
  scopes             text[] not null check (cardinality(scopes) between 1 and 20),
  access_sha256      bytea not null unique check (length(access_sha256) = 32),
  access_expires_at  timestamptz not null,
  refresh_sha256     bytea unique check (refresh_sha256 is null or length(refresh_sha256) = 32),
  refresh_expires_at timestamptz,
  created_at         timestamptz not null default now(),
  last_used_at       timestamptz,
  revoked_at         timestamptz,
  revoke_reason      text check (revoke_reason is null or revoke_reason in ('revoked', 'mcp_off', 'app_removed', 'staff_deactivated', 'rotated', 'mfa_reset')),
  check ((revoked_at is null) = (revoke_reason is null)),
  check (revoked_at is null or refresh_sha256 is null)
);
create index oauth_grants_staff on app.oauth_grants (staff_id) where revoked_at is null;

-- rate limits (INT-03): token cost per operation (Part F), hourly usage, the 2-second burst window, the day's budget,
-- idempotency keys on create
create table app.api_costs (
  op   text primary key check (op in ('get', 'list', 'create', 'update', 'delete', 'delete_list', 'search', 'convert', 'merge', 'index_search')),
  cost int not null check (cost >= 0)
);
create table app.api_requests_hourly (
  hour           timestamptz not null check (hour = date_trunc('hour', hour)),
  principal_kind text not null check (principal_kind in ('token', 'grant')),
  principal_id   uuid not null,
  requests       int not null default 0 check (requests >= 0),
  cost           bigint not null default 0 check (cost >= 0),
  throttled      int not null default 0 check (throttled >= 0),
  primary key (hour, principal_kind, principal_id)
);
create unlogged table app.api_burst (
  principal_id uuid not null,
  second       bigint not null,
  n            int not null check (n >= 0),
  primary key (principal_id, second)
);
create table app.api_budget_day (
  day          date primary key,
  used         bigint not null default 0 check (used >= 0),
  warned75_at  timestamptz,
  warned100_at timestamptz
);
create table app.api_idempotency (
  principal_id uuid not null,
  key          text not null check (char_length(key) between 8 and 100),
  response     jsonb not null,
  created_at   timestamptz not null default now(),
  primary key (principal_id, key)
);

-- webhooks (INT-04, SF-23, D-32)
create table app.webhooks (
  id                     uuid primary key default gen_random_uuid(),
  owner_id               uuid not null references app.admins (id) on delete cascade,
  event_kind             text not null references app.event_catalog (kind),
  url                    text not null check (app.url_public(url)),
  vault_secret_id        uuid,
  state                  text not null default 'active' check (state in ('active', 'paused', 'banned', 'blocked', 'deleted')),
  banned_until           timestamptz,
  first_attempt_failures int not null default 0 check (first_attempt_failures >= 0),
  last_success_at        timestamptz,
  failing_since          timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz,
  version                int not null default 1,
  is_sample              boolean not null default false,
  check ((state = 'banned') = (banned_until is not null)),
  check ((state = 'deleted') = (deleted_at is not null)),
  check (state = 'deleted' or vault_secret_id is not null)
);
create index webhooks_kind on app.webhooks (event_kind) where state = 'active';
create index webhooks_owner on app.webhooks (owner_id) where state <> 'deleted';

-- one row per attempt; the envelope holds names and ids only, never a record's values (customer free text stays out of logs)
create table app.webhook_deliveries (
  id              uuid primary key default gen_random_uuid(),
  webhook_id      uuid not null references app.webhooks (id) on delete cascade,
  event_id        bigint not null references app.events (id) on delete cascade,
  redelivery      smallint not null default 0 check (redelivery between 0 and 100),
  attempt         smallint not null check (attempt between 1 and 4),
  state           text not null default 'queued' check (state in ('queued', 'sent', 'failed', 'skipped')),
  scheduled_at    timestamptz not null default now(),
  claimed_at      timestamptz,
  sent_at         timestamptz,
  duration_ms     int check (duration_ms is null or duration_ms >= 0),
  response_status int check (response_status is null or response_status between 0 and 599),
  error_code      text check (error_code is null or error_code ~ '^[a-z0-9_.:-]{1,60}$'),
  envelope        jsonb check (envelope is null or jsonb_typeof(envelope) = 'object'),
  body_sha256     bytea check (body_sha256 is null or length(body_sha256) = 32),
  bytes           int check (bytes is null or bytes >= 0),
  signed_at       bigint,
  unique (webhook_id, event_id, redelivery, attempt)
);
create index webhook_deliveries_due on app.webhook_deliveries (scheduled_at) where state = 'queued';
create index webhook_deliveries_hook on app.webhook_deliveries (webhook_id, scheduled_at desc);

-- the integration catalog (INT-05..11, D-42) and what the company installed
create table app.integration_catalog (
  key         text primary key check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  collection  text not null check (collection in ('productivity_mail', 'team_chat', 'close_paid', 'automate')),
  provider    text,
  connection  text not null check (connection in ('company', 'per_user', 'api', 'extension')),
  access      text[] not null,
  tags        text[] not null default '{}',
  terms       text not null default '' check (char_length(terms) <= 500),      -- the English name and description, for search
  first_party boolean not null default true,
  ord         int not null default 0,
  active      boolean not null default true
);
create table app.installed_apps (
  key          text primary key references app.integration_catalog (key) on delete cascade,
  installed_by uuid references app.admins (id) on delete set null,
  installed_at timestamptz not null default now(),
  settings     jsonb not null default '{}'::jsonb check (jsonb_typeof(settings) = 'object'),
  removed_at   timestamptz,
  removed_by   uuid references app.admins (id) on delete set null
);

-- the AI connector's sync index (MCP-01): CRM records only, filtered by app.visible when read, never when written
create table app.mcp_index (
  entity     text not null references app.entities (key) on delete cascade,
  record_id  uuid not null,
  title      text not null check (char_length(title) <= 300),
  body       tsvector not null,
  owner_id   uuid,
  visibility text not null check (visibility in ('owner', 'group', 'group_sub', 'all')),
  updated_at timestamptz not null,
  primary key (entity, record_id)
);
create index mcp_index_body on app.mcp_index using gin (body);

-- the job monitor: the registry and one row per run
create table app.job_defs (
  key        text primary key check (key ~ '^[a-z_]{2,40}$'),
  product    text references app.products (key) on delete cascade,
  label_key  text not null check (label_key ~ '^[a-z][a-zA-Z0-9_.]{1,80}$'),
  schedule   text,
  source     text not null check (source in ('cron', 'queue', 'product')),
  fn         text check (fn ~ '^app\.[a-z_]+$'),
  retry_fn   text check (retry_fn ~ '^app\.[a-z_]+$'),
  quiet      boolean not null default false,          -- every-minute jobs: a run that found nothing to do writes no row
  last_run_at timestamptz,
  last_state text check (last_state is null or last_state in ('succeeded', 'failed')),
  check (source <> 'cron' or fn is not null)
);
create table app.job_runs (
  id           bigint generated always as identity primary key,
  job_key      text not null references app.job_defs (key) on delete cascade,
  state        text not null check (state in ('queued', 'running', 'succeeded', 'failed')),
  queued_at    timestamptz not null default now(),
  started_at   timestamptz,
  finished_at  timestamptz,
  info         jsonb not null default '{}'::jsonb check (jsonb_typeof(info) = 'object'),
  error        text check (error is null or char_length(error) <= 300),
  retry_of     bigint references app.job_runs (id) on delete set null,
  requested_by uuid references app.admins (id) on delete set null
);
create index job_runs_job on app.job_runs (job_key, queued_at desc);
create index job_runs_recent on app.job_runs (queued_at desc);

-- ===========================================================================
-- §3.5 tables: mobile
-- ===========================================================================
-- Web Push devices (MOB-07). The endpoint is a capability URL: written by the client, read only by the push worker
create table app.push_devices (
  id           uuid primary key default gen_random_uuid(),
  staff_id     uuid not null references app.admins (id) on delete cascade,
  platform     text not null default 'web_push' check (platform in ('web_push')),
  endpoint     text not null unique check (endpoint ~ '^https://' and char_length(endpoint) <= 1000),
  p256dh       text not null check (p256dh ~ '^[A-Za-z0-9_=-]{40,200}$'),
  auth_secret  text not null check (auth_secret ~ '^[A-Za-z0-9_=-]{16,60}$'),
  label        text check (label is null or char_length(label) <= 120),
  created_at   timestamptz not null default now(),
  last_used_at timestamptz,
  failures     int not null default 0 check (failures >= 0),
  revoked_at   timestamptz
);
create index push_devices_staff on app.push_devices (staff_id) where revoked_at is null;
create table app.push_deliveries (
  notification_id uuid not null references app.notifications (id) on delete cascade,
  device_id       uuid not null references app.push_devices (id) on delete cascade,
  state           text not null default 'queued' check (state in ('queued', 'sent', 'failed', 'gone')),
  queued_at       timestamptz not null default now(),
  claimed_at      timestamptz,
  sent_at         timestamptz,
  status          int check (status is null or status between 0 and 599),
  primary key (notification_id, device_id)
);
create index push_deliveries_due on app.push_deliveries (queued_at) where state = 'queued';

-- which channels each notification kind uses (reminders keep reminder_prefs, 0010)
create table app.notification_prefs (
  staff_id uuid not null references app.admins (id) on delete cascade,
  kind     text not null check (kind in ('assignment', 'mention', 'chat_request', 'security', 'system')),
  channels text[] not null default array['in_app', 'push'] check (channels <@ array['in_app', 'push', 'email']),
  primary key (staff_id, kind)
);

-- offline sync (SF-31): one receipt per device mutation makes a retry idempotent
create table app.sync_receipts (
  staff_id    uuid not null references app.admins (id) on delete cascade,
  device_id   uuid not null,
  mutation_id uuid not null,
  received_at timestamptz not null default now(),
  result      text not null check (result in ('applied', 'superseded', 'rejected')),
  error_code  text check (error_code is null or error_code ~ '^[a-z_]{1,40}$'),
  response    jsonb not null default '{}'::jsonb check (jsonb_typeof(response) = 'object'),
  primary key (staff_id, device_id, mutation_id)
);

-- where a record is (MOB-02, MOB-03): the organisation's address or an address custom field, from the geocoder or by hand
create table app.record_geo (
  entity      text not null references app.entities (key) on delete cascade,
  record_id   uuid not null,
  field_key   text not null default 'address' check (field_key = 'address' or field_key ~ '^custom\.[a-z][a-z0-9_]{1,40}$'),
  lat         numeric(9, 6) not null check (lat between -90 and 90),
  lng         numeric(9, 6) not null check (lng between -180 and 180),
  source      text not null check (source in ('geonorge', 'manual')),
  geocoded_at timestamptz not null default now(),
  primary key (entity, record_id, field_key)
);
create index record_geo_box on app.record_geo (lat, lng);

-- mobile capture on the files records already have (0038): what was captured, audio and webp/heic photos, the transcript
alter table app.record_files
  add column capture_kind  text check (capture_kind is null or capture_kind in ('photo', 'audio', 'scan', 'card')),
  add column transcript    text check (transcript is null or char_length(transcript) <= 50000),
  add column transcript_at timestamptz;
alter table app.record_files drop constraint record_files_mime_check;
alter table app.record_files add constraint record_files_mime_check
  check (mime in ('application/pdf', 'image/png', 'image/jpeg', 'text/csv', 'text/plain',
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
                  'image/webp', 'image/heic', 'audio/webm', 'audio/mp4', 'audio/mpeg'));

-- ===========================================================================
-- bulk changes that can be reverted (Contacts R-6)
-- ===========================================================================
create table app.bulk_changes (
  id            uuid primary key default gen_random_uuid(),
  entity        text not null references app.entities (key) on delete cascade,
  staff_id      uuid references app.admins (id) on delete set null,
  at            timestamptz not null default now(),
  fields        text[] not null,
  count         int not null check (count >= 0),
  is_sample     boolean not null default false,
  reverted_at   timestamptz,
  reverted_by   uuid references app.admins (id) on delete set null,
  revert_result jsonb check (revert_result is null or jsonb_typeof(revert_result) = 'object')
);
create index bulk_changes_recent on app.bulk_changes (entity, at desc);
create table app.bulk_change_items (
  change_id     uuid not null references app.bulk_changes (id) on delete cascade,
  record_id     uuid not null,
  before        jsonb not null check (jsonb_typeof(before) = 'object'),    -- the touched fields' values before, custom keys under «custom»
  after_version int not null,
  outcome       text check (outcome is null or outcome in ('reverted', 'stale', 'gone', 'forbidden')),
  primary key (change_id, record_id)
);

-- nobody changes what a bulk change recorded; the outcome is written once by the revert. A row goes only with its change
-- (the cascade, after the parent is gone) or in a purge
create function app.bulk_item_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if current_setting('app.purging', true) = 'on' or not exists (select 1 from app.bulk_changes c where c.id = old.change_id) then return old; end if;
    raise exception 'a bulk change item is kept with its change' using errcode = 'insufficient_privilege';
  end if;
  if (new.change_id, new.record_id, new.before, new.after_version) is distinct from (old.change_id, old.record_id, old.before, old.after_version)
     or (old.outcome is not null and new.outcome is distinct from old.outcome) then
    raise exception 'a bulk change item cannot be changed' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $fn$;
create trigger bulk_item_fixed before update or delete on app.bulk_change_items for each row execute function app.bulk_item_fixed();

-- ===========================================================================
-- §3.6 settings (options are keys; labels are message keys). Defaults leave everything working (D-16).
-- ===========================================================================
insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord) values
  ('api_budget_base', 'limits', array['source_value', 'custom'], 'source_value', 'platform', 'INT-03 (requests per seat per day; source value 30 000; read while api_rate is on)', false, 'custom', 121),
  ('api_plan_multiplier', 'limits', array['source_value', 'custom'], 'source_value', 'platform', 'INT-03 (multiplier; source value 1; D-17: not a plan attribute)', false, 'custom', 122),
  ('api_burst_token', 'limits', array['source_value', 'custom'], 'source_value', 'platform', 'INT-03 (calls per 2 s per personal token; source value 20)', false, 'custom', 123),
  ('api_burst_oauth', 'limits', array['source_value', 'custom'], 'source_value', 'platform', 'INT-03 (calls per 2 s per OAuth grant; source value 80)', false, 'custom', 124),
  ('api_burst_search', 'limits', array['source_value', 'custom'], 'source_value', 'platform', 'INT-03 (searches per 2 s; source value 10)', false, 'custom', 125),
  ('webhook_timeout_s', 'safeguards', array['source_value', 'custom'], 'source_value', 'platform', 'INT-04 (seconds; source value 10; read while safeguards is custom)', false, 'custom', 131),
  ('webhook_ban_after', 'safeguards', array['source_value', 'custom'], 'source_value', 'platform', 'INT-04 (first-attempt failures in a row; source value 10; read while safeguards is custom)', false, 'custom', 132),
  ('webhook_ban_min', 'safeguards', array['source_value', 'custom'], 'source_value', 'platform', 'INT-04 (minutes banned; source value 30; read while safeguards is custom)', false, 'custom', 133),
  ('webhook_delete_days', 'safeguards', array['source_value', 'custom'], 'source_value', 'platform', 'INT-04, SF-23 (days without success; source value 3; read while safeguards is custom)', false, 'custom', 134),
  ('mcp_access', 'integrations', array['on', 'off'], 'on', 'platform', 'MCP-03 (off revokes every assistant grant and refuses new ones)', false, null, 400),
  ('mcp_sync', 'integrations', array['on', 'off'], 'on', 'platform', 'MCP-01 (the sync index, every 30 min)', false, null, 410),
  ('push_notifications', 'mobile', array['on', 'off'], 'on', 'platform', 'MOB-07 (also needs the mobile module)', false, null, 500);
update app.settings_registry set applies_to = applies_to || ', INT-03 (budget and burst keys)' where key = 'api_rate' and applies_to not like '%budget%';

-- ===========================================================================
-- registries (data, not code)
-- ===========================================================================
-- the outbox kinds: record types' own (created, updated, deleted, merged), the named ones, and this phase's admin events
insert into app.event_catalog (kind, family, entity, webhookable, workflow_trigger, label_key)
select e.key || '.' || a, e.key, e.key, e.key in ('organization', 'person', 'lead', 'deal', 'activity', 'ticket', 'project', 'campaign', 'document'), true,
       'events.' || e.key || '.' || a
from app.entities e cross join unnest(array['created', 'updated', 'deleted']) a
where e.key not in ('email_thread', 'catalog_item', 'form', 'document_template')
on conflict do nothing;
insert into app.event_catalog (kind, family, entity, webhookable, workflow_trigger, label_key) values
  ('organization.merged', 'organization', 'organization', true, true, 'events.organization.merged'),
  ('person.merged', 'person', 'person', true, true, 'events.person.merged'),
  ('deal.stage_changed', 'deal', 'deal', true, true, 'events.deal.stage_changed'),
  ('deal.won', 'deal', 'deal', true, true, 'events.deal.won'),
  ('deal.lost', 'deal', 'deal', true, true, 'events.deal.lost'),
  ('deal.reopened', 'deal', 'deal', true, true, 'events.deal.reopened'),
  ('deal.archived', 'deal', 'deal', false, true, 'events.deal.archived'),
  ('deal.unarchived', 'deal', 'deal', false, true, 'events.deal.unarchived'),
  ('deal.converted_to_lead', 'deal', 'deal', false, true, 'events.deal.converted_to_lead'),
  ('activity.completed', 'activity', 'activity', true, true, 'events.activity.completed'),
  ('activity.reopened', 'activity', 'activity', true, true, 'events.activity.reopened'),
  ('lead.converted', 'lead', 'lead', true, true, 'events.lead.converted'),
  ('note.created', 'note', null, true, true, 'events.note.created'),
  ('consent.changed', 'person', 'person', true, true, 'events.consent.changed'),
  ('ticket.replied', 'ticket', 'ticket', true, true, 'events.ticket.replied'),
  ('problem.resolved', 'ticket', 'ticket', true, true, 'events.problem.resolved'),
  ('file.attached', 'file', null, false, true, 'events.file.attached'),
  ('form.submitted', 'form', 'form', false, true, 'events.form.submitted'),
  ('project.phase_changed', 'project', 'project', false, true, 'events.project.phase_changed'),
  ('project.completed', 'project', 'project', false, true, 'events.project.completed'),
  ('project.reopened', 'project', 'project', false, true, 'events.project.reopened'),
  ('project.task_completed', 'project', 'project', false, true, 'events.project.task_completed'),
  ('project.milestone_reached', 'project', 'project', false, true, 'events.project.milestone_reached'),
  ('campaign.sent', 'campaign', 'campaign', false, true, 'events.campaign.sent'),
  ('chat.completed', 'chat', null, false, true, 'events.chat.completed'),
  ('export.created', 'export', null, false, false, 'events.export.created'),
  -- this phase (§3.10): never webhookable
  ('api_token.created', 'api', null, false, true, 'events.api_token.created'),
  ('api_token.revoked', 'api', null, false, true, 'events.api_token.revoked'),
  ('oauth.granted', 'api', null, false, true, 'events.oauth.granted'),
  ('oauth.revoked', 'api', null, false, true, 'events.oauth.revoked'),
  ('webhook.banned', 'webhook', null, false, true, 'events.webhook.banned'),
  ('webhook.deleted', 'webhook', null, false, true, 'events.webhook.deleted'),
  ('webhook.ping', 'webhook', null, false, false, 'events.webhook.ping'),
  ('integration.installed', 'integration', null, false, true, 'events.integration.installed'),
  ('integration.removed', 'integration', null, false, true, 'events.integration.removed'),
  ('mcp.switched', 'mcp', null, false, false, 'events.mcp.switched'),
  ('job.failed', 'job', null, false, true, 'events.job.failed'),
  ('status_notice.changed', 'status_notice', null, false, false, 'events.status_notice.changed'),
  ('usage.limit_warning', 'usage', null, false, true, 'events.usage.limit_warning'),
  ('usage.limit_reached', 'usage', null, false, true, 'events.usage.limit_reached')
on conflict (kind) do nothing;

-- token scopes (§3.8): read = see; write = see, add, edit others, delete, bulk. Never security or configuration
insert into app.api_scopes (scope, rights, ord)
select s || ':read', array[s || ':see'], o * 10 from unnest(array['deals', 'projects', 'campaigns', 'tickets', 'global']) with ordinality x(s, o)
union all
select s || ':write', array[s || ':see', s || ':add', s || ':edit_others', s || ':delete', s || ':bulk'], o * 10 + 1
from unnest(array['deals', 'projects', 'campaigns', 'tickets']) with ordinality x(s, o)
union all select '*', '{}', 0;

-- Part F reference costs; create = update (not given), convert and merge as an update, an index search as a search
insert into app.api_costs (op, cost) values ('get', 2), ('list', 20), ('create', 10), ('update', 10), ('delete', 6), ('delete_list', 10),
  ('search', 40), ('convert', 10), ('merge', 10), ('index_search', 40);

-- the catalog: four collections, eight entries (Platform.dc.html); names and descriptions are message keys catalog.<key>.*
insert into app.integration_catalog (key, collection, provider, connection, access, tags, terms, first_party, ord) values
  ('gw', 'productivity_mail', 'google', 'per_user', array['contacts', 'calendar', 'mail', 'drive'], array['google', 'gmail', 'calendar', 'meet', 'drive'],
   'Google Workspace contacts calendar tasks Drive files Gmail Meet links sign-in', true, 10),
  ('m365', 'productivity_mail', 'microsoft', 'per_user', array['mail', 'calendar', 'contacts', 'files'], array['microsoft', 'outlook', 'exchange', 'onedrive', 'sharepoint'],
   'Microsoft 365 Outlook Exchange mail calendar contacts Teams links notifications OneDrive SharePoint', true, 20),
  ('slack', 'team_chat', 'slack', 'company', array['deal_events', 'search'], array['chat', 'channels', 'notifications'],
   'Slack deal events to channels or DMs search deals and people from chat', true, 30),
  ('teams', 'team_chat', 'teams', 'company', array['deal_events', 'search'], array['chat', 'channels', 'notifications'],
   'Microsoft Teams deal events to channels search from chat', true, 40),
  ('acc', 'close_paid', 'accounting', 'company', array['deals', 'products', 'invoices'], array['invoice', 'ehf', 'accounting', 'billing'],
   'Accounting system EHF create invoices from deals with person organization and products status on the deal send invoices when a deal is won', true, 50),
  ('sign', 'close_paid', 'esign', 'company', array['documents'], array['signature', 'documents'],
   'External e-signature send documents to an external signing service', true, 60),
  ('zap', 'automate', null, 'api', array['scoped_by_token'], array['zapier', 'make', 'automation', 'no-code'],
   'No-code automation platforms connectors built on the API and webhooks', false, 70),
  ('ext', 'automate', null, 'extension', array['per_app'], array['extensions', 'panels', 'actions'],
   'App extensions panels in deal and contact views actions that open a link dialog or embedded view', false, 80);

-- Orgpuls' commands (the allow-list in supabase/functions/_shared/orgpuls.ts) and what uses them
insert into app.product_commands (product, command, scope, used_by, destructive)
select 'orgpuls', c, s, u, d from (values
  ('orgs.list', 'orgs:read', array['applications', 'customers'], false), ('orgs.get', 'orgs:read', array['customers'], false),
  ('orgs.deletions', 'orgs:read', array['customers'], false), ('orgs.delete_now', 'orgs:write', array['customers', 'privacy'], true),
  ('orgs.resync', 'orgs:read', array['applications', 'customers'], false),
  ('billing.cancellation', 'billing:read', array['customers'], false), ('billing.extend_trial', 'billing:write', array['customers', 'tickets'], false),
  ('billing.cancel', 'billing:write', array['customers'], true), ('billing.cancel_withdraw', 'billing:write', array['customers'], false),
  ('translations.list', 'translations:read', array['content'], false), ('translations.sources', 'translations:read', array['content'], false),
  ('translations.history', 'translations:read', array['content'], false), ('translations.auto_approve', 'translations:read', array['content'], false),
  ('translations.import', 'translations:write', array['content'], false), ('translations.update', 'translations:write', array['content'], false),
  ('translations.approve', 'translations:write', array['content'], false), ('translations.set_auto_approve', 'translations:write', array['content'], false),
  ('overrides.list', 'translations:read', array['content'], false), ('overrides.import', 'translations:write', array['content'], false),
  ('overrides.approve', 'translations:write', array['content'], false),
  ('modules.list', 'modules:read', array['flags', 'content'], false), ('modules.set_status', 'modules:write', array['flags'], false),
  ('modules.set_validation', 'modules:write', array['flags'], false), ('modules.sync', 'modules:write', array['flags'], false),
  ('modules.pilot', 'modules:write', array['flags'], false), ('locales.pilots', 'modules:read', array['flags'], false),
  ('locales.pilot', 'modules:write', array['flags'], false),
  ('legal.reviews', 'legal:read', array['content'], false), ('legal.approvals', 'legal:read', array['content'], false),
  ('legal.review', 'legal:write', array['content'], false), ('legal.set', 'legal:write', array['content'], false),
  ('legal.auto_record', 'legal:write', array['content'], false),
  ('settings.notice', 'settings:read', array['settings'], false), ('settings.set_notice', 'settings:write', array['settings'], false),
  ('settings.set_indexing', 'settings:write', array['settings'], false)
) as x(c, s, u, d);

-- what Orgpuls' event kinds (D-14) feed
insert into app.product_event_kinds (product, kind, uses, label_key)
select 'orgpuls', k, u, 'platform.eventUse.' || replace(k, '.', '_') from (values
  ('org.created', array['crm', 'funnel', 'workflows']), ('org.deleted', array['crm', 'billing']), ('org.attribution', array['funnel']),
  ('billing.changed', array['billing', 'workflows']), ('member.joined', array['crm', 'health']), ('member.left', array['crm', 'health']),
  ('usage.daily', array['usage', 'health']), ('survey.round', array['activation', 'health']), ('counts.updated', array['usage', 'health']),
  ('milestone.reached', array['activation', 'workflows']), ('member.state', array['crm']), ('logins.daily', array['health']),
  ('support.requested', array['tickets']), ('contact.submitted', array['tickets', 'leads']), ('demo.requested', array['leads'])
) as x(k, u);

-- ===========================================================================
-- §3.11 jobs: the registry, app.run_job, failures
-- ===========================================================================
-- every platform schedule (0007–0042) and this phase's, plus the queue jobs edge workers report through worker_job_run
insert into app.job_defs (key, label_key, schedule, source, fn, quiet) values
  ('purge', 'jobs.purge', '17 3 * * *', 'cron', 'app.purge', false),
  ('mrr_snapshot', 'jobs.mrr_snapshot', '5 0 * * *', 'cron', 'app.snapshot_mrr', false),
  ('reminders', 'jobs.reminders', '* * * * *', 'cron', 'app.dispatch_reminders', true),
  ('duplicates', 'jobs.duplicates', '23 2 * * *', 'cron', 'app.duplicates_scan', false),
  ('mail_due', 'jobs.mail_due', '* * * * *', 'cron', 'app.mail_due', true),
  ('dispatch', 'jobs.dispatch', '* * * * *', 'cron', 'app.dispatch_events', true),
  ('workflow_resume', 'jobs.workflow_resume', '* * * * *', 'cron', 'app.wf_resume_due', true),
  ('workflow_dates', 'jobs.workflow_dates', '7 * * * *', 'cron', 'app.wf_dates', false),
  ('feed_checks', 'jobs.feed_checks', '23 * * * *', 'cron', 'app.feed_checks', false),
  ('scores', 'jobs.scores', '41 2 * * *', 'cron', 'app.scores_nightly', false),
  ('pipeline_snapshot', 'jobs.pipeline_snapshot', '55 23 * * *', 'cron', 'app.snapshot_pipeline', false),
  ('mrr_tenants', 'jobs.mrr_tenants', '15 0 * * *', 'cron', 'app.snapshot_mrr_tenants', false),
  ('health', 'jobs.health', '35 0 * * *', 'cron', 'app.health_nightly', false),
  ('web_salt', 'jobs.web_salt', '0 0 * * *', 'cron', 'app.web_salt_rotate', false),
  ('web_prune', 'jobs.web_prune', '45 3 * * *', 'cron', 'app.web_prune', false),
  ('chat_fallback', 'jobs.chat_fallback', '* * * * *', 'cron', 'app.chat_fallback', true),
  ('capture_prune', 'jobs.capture_prune', '52 3 * * *', 'cron', 'app.capture_prune', false),
  ('signature_expire', 'jobs.signature_expire', '37 4 * * *', 'cron', 'app.signature_expire', false),
  ('campaign_due', 'jobs.campaign_due', '* * * * *', 'cron', 'app.campaign_due', true),
  ('campaign_ab', 'jobs.campaign_ab', '*/10 * * * *', 'cron', 'app.campaign_ab_decide', true),
  ('campaign_prune', 'jobs.campaign_prune', '44 3 * * *', 'cron', 'app.campaign_prune', false),
  ('dns_check', 'jobs.dns_check', '13 2 * * *', 'cron', 'app.sender_domains_check_all', false),
  ('files_purge', 'jobs.files_purge', '41 3 * * *', 'cron', 'app.files_purge', false),
  ('meeting_calendar_scan', 'jobs.meeting_calendar_scan', '*/10 * * * *', 'cron', 'app.mtg_calendar_scan', true),
  ('meeting_notices', 'jobs.meeting_notices', '*/5 * * * *', 'cron', 'app.mtg_notices_due', true),
  ('meeting_bots', 'jobs.meeting_bots', '* * * * *', 'cron', 'app.mtg_bots_due', true),
  ('meeting_briefs', 'jobs.meeting_briefs', '*/10 * * * *', 'cron', 'app.mtg_briefs_due', true),
  ('meeting_purge', 'jobs.meeting_purge', '23 3 * * *', 'cron', 'app.mtg_purge', false),
  -- this phase
  ('webhook_sweep', 'jobs.webhook_sweep', '* * * * *', 'cron', 'app.webhook_sweep', true),
  ('api_burst_prune', 'jobs.api_burst_prune', '* * * * *', 'cron', 'app.api_burst_prune', true),
  ('mcp_index', 'jobs.mcp_index', '*/30 * * * *', 'cron', 'app.mcp_index_refresh', false),
  ('status_notices', 'jobs.status_notices', '*/5 * * * *', 'cron', 'app.status_notices_due', true),
  ('platform_prune', 'jobs.platform_prune', '29 3 * * *', 'cron', 'app.platform_prune', false);
insert into app.job_defs (key, label_key, source) values
  ('webhook_send', 'jobs.webhook_send', 'queue'), ('push_send', 'jobs.push_send', 'queue'), ('geocode', 'jobs.geocode', 'queue'),
  ('product_command', 'jobs.product_command', 'queue'), ('transcription', 'jobs.transcription', 'queue');

-- what a job returned, as counts only (D-19: a count is allowed, a name never)
create function app.job_info(p_result text) returns jsonb
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if p_result ~ '^-?\d+(\.\d+)?$' then return jsonb_build_object('count', p_result::numeric); end if;
  if p_result ~ '^\s*\{' then
    return coalesce((select jsonb_object_agg(k, v) from jsonb_each(p_result::jsonb) x(k, v) where jsonb_typeof(v) in ('number', 'boolean')), '{}'::jsonb);
  end if;
  return '{}'::jsonb;
end $fn$;

-- a run failed: global:configure hears it once per failure streak (SF-26 step 6), and job.failed goes to the outbox
create function app.job_failed(p_run bigint) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.job_runs;
begin
  select * into r from app.job_runs where id = p_run;
  if not found then return; end if;
  perform app.notify(a.id, 'system', 'job.failed', jsonb_build_object('job', r.job_key), '/applications', null, null)
  from app.admins a where a.active and not a.is_sample and app.can_for(a.id, 'global', 'configure');
  perform app.emit('job.failed', null, null, jsonb_build_object('run', r.id, 'job', r.job_key));
end $fn$;

-- run a scheduled job and record it. The job's work and its row commit together; a failure rolls back the work and keeps
-- the failed row. An every-minute («quiet») job that found nothing to do writes no row.
create function app.run_job(p_key text, p_retry_of bigint default null, p_by uuid default null) returns bigint
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d app.job_defs; v_res text; v_err text; v_start timestamptz := clock_timestamp(); v_info jsonb := '{}'::jsonb; v_id bigint;
begin
  select * into d from app.job_defs where key = p_key for update;
  if not found or d.fn is null then raise exception 'not_found' using errcode = 'no_data_found', detail = 'job'; end if;
  begin
    execute format('select (%s())::text', d.fn) into v_res;
  exception when others then
    v_err := left(sqlstate || ': ' || sqlerrm, 300);
  end;
  if v_err is null then
    v_info := app.job_info(v_res);
    update app.job_defs set last_run_at = now(), last_state = 'succeeded' where key = p_key;
    if d.quiet and p_retry_of is null and not exists (select 1 from jsonb_each(v_info) x(k, v)
                                                      where (jsonb_typeof(v) = 'number' and (v #>> '{}')::numeric <> 0) or v = 'true'::jsonb) then
      return null;
    end if;
    insert into app.job_runs (job_key, state, queued_at, started_at, finished_at, info, retry_of, requested_by)
    values (p_key, 'succeeded', v_start, v_start, clock_timestamp(), v_info, p_retry_of, p_by) returning id into v_id;
  else
    insert into app.job_runs (job_key, state, queued_at, started_at, finished_at, error, retry_of, requested_by)
    values (p_key, 'failed', v_start, v_start, clock_timestamp(), v_err, p_retry_of, p_by) returning id into v_id;
    update app.job_defs set last_run_at = now(), last_state = 'failed' where key = p_key;
    if d.last_state is distinct from 'failed' or p_retry_of is not null then perform app.job_failed(v_id); end if;
  end if;
  return v_id;
end $fn$;

-- ===========================================================================
-- notifications: kinds of their own, once-only delivery, push
-- ===========================================================================
-- a notification that is delivered at most once per dedupe key
create function app.notify_once(p_staff uuid, p_kind text, p_key text, p_params jsonb, p_route text, p_entity text, p_record uuid, p_dedupe text)
  returns boolean language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid;
begin
  insert into app.notifications (staff_id, kind, key, params, route, entity, record_id, dedupe_key)
  values (p_staff, p_kind, p_key, coalesce(p_params, '{}'::jsonb), p_route, p_entity, p_record, left(p_dedupe, 120))
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  return v_id is not null;
end $fn$;

-- 0007's notify, unchanged for every caller except one: «assignment.assigned» (0021, 0039) becomes kind «assignment», delivered
-- once per event (the dispatcher's app.event_id) or per workflow run (app.run_id), so an assignment processed twice sends one
-- push (MOB-07)
create or replace function app.notify(p_staff uuid, p_kind text, p_key text, p_params jsonb default '{}'::jsonb, p_route text default null,
                                      p_entity text default null, p_record uuid default null)
  returns void language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_ref text := coalesce(nullif(current_setting('app.event_id', true), ''),
                         case when nullif(current_setting('app.run_id', true), '') is not null then 'r' || current_setting('app.run_id', true) end);
begin
  if p_key = 'assignment.assigned' then
    perform app.notify_once(p_staff, 'assignment', p_key, p_params, p_route, p_entity, p_record,
                            case when v_ref is not null then 'assignment:' || v_ref || ':' || coalesce(p_record::text, '-') || ':' || p_staff end);
    return;
  end if;
  insert into app.notifications (staff_id, kind, key, params, route, entity, record_id)
  values (p_staff, p_kind, p_key, coalesce(p_params, '{}'::jsonb), p_route, p_entity, p_record);
end $fn$;

-- the dispatcher (0021) with the event's id in app.event_id while a subscriber handles it, so what a subscriber notifies is
-- delivered once per event even when the event is handled again
create or replace function app.dispatch_events() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.event_subscribers; ev app.events; v_last bigint; n int := 0;
begin
  for s in select * from app.event_subscribers where enabled order by ord loop
    select last_event_id into v_last from app.event_cursors where subscriber = s.name for update skip locked;
    continue when not found;
    for ev in select * from app.events where id > v_last order by id limit 500 loop
      perform set_config('app.event_id', 'e' || ev.id, true);
      begin
        execute format('select %s($1)', s.fn) using ev;
      exception when others then
        insert into app.event_failures (subscriber, event_id, error) values (s.name, ev.id, left(sqlerrm, 500));
      end;
      v_last := ev.id; n := n + 1;
    end loop;
    perform set_config('app.event_id', '', true);
    update app.event_cursors set last_event_id = v_last, updated_at = now() where subscriber = s.name;
  end loop;
  return n;
end $fn$;

-- Web Push is configured when the VAPID private key is in Vault (§3.12.8)
create function app.push_ready() returns boolean
  language sql stable security definer set search_path = ''
as $fn$ select exists (select 1 from vault.secrets s where s.name = 'vapid_private_key') $fn$;

-- a new notification goes to the staff member's devices when push is on (setting and module), configured, and the kind's
-- channels include push (no row: in-app and push). Reminders follow reminder_prefs (0010) and always push.
create function app.notification_push() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare n int;
begin
  if app.setting('push_notifications') <> 'on' or not app.module_on('mobile') or not app.push_ready() then return new; end if;
  if new.kind <> 'reminder' and not coalesce((select 'push' = any (p.channels) from app.notification_prefs p where p.staff_id = new.staff_id and p.kind = new.kind), true) then
    return new;
  end if;
  insert into app.push_deliveries (notification_id, device_id)
  select new.id, d.id from app.push_devices d where d.staff_id = new.staff_id and d.revoked_at is null
  on conflict do nothing;
  get diagnostics n = row_count;
  if n > 0 then perform pgmq.send('jobs', jsonb_build_object('job', 'push_send')); end if;
  return new;
end $fn$;
create trigger notification_push after insert on app.notifications for each row execute function app.notification_push();

-- a visitor asks for a person (a playbook's handoff, 0031): the staff online for chat hear it once (kind chat_request)
create function app.chat_requested() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if new.state = 'queued' and old.state is distinct from 'queued' then
    perform app.notify_once(p.staff_id, 'chat_request', 'chat.requested',
                            jsonb_build_object('page', left(split_part(coalesce(new.page_path, ''), '?', 1), 80)),
                            '/lead-capture?chat=' || new.id, null, null,
                            'chat:' || new.id || ':' || extract(epoch from new.queued_at)::bigint || ':' || p.staff_id)
    from app.chat_presence p join app.admins a on a.id = p.staff_id
    where p.online_until > now() and a.active and a.is_sample = new.is_sample;
  end if;
  return new;
end $fn$;
create trigger chat_requested after update of state on app.chat_conversations for each row execute function app.chat_requested();

-- ===========================================================================
-- webhooks (§1.3; INT-04, SF-23, D-32)
-- ===========================================================================
-- the retry and ban policy: source values (10 s; retries after 3, 30, 150 s = 4 attempts; banned 30 min after 10 first-attempt
-- failures in a row; deleted after 3 days without success), the custom numbers when safeguards is custom, no ban or deletion when off
create function app.webhook_policy() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_mode text := app.setting('safeguards'); c boolean := app.setting('safeguards') = 'custom';
begin
  return jsonb_build_object(
    'mode', v_mode,
    'timeout_s', case when c then app.setting_num('webhook_timeout_s', 10) else 10 end,
    'retry_s', jsonb_build_array(3, 30, 150),
    'attempts', 4,
    'ban_after', case when v_mode = 'off' then null when c then app.setting_num('webhook_ban_after', 10) else 10 end,
    'ban_min', case when v_mode = 'off' then null when c then app.setting_num('webhook_ban_min', 30) else 30 end,
    'delete_days', case when v_mode = 'off' then null when c then app.setting_num('webhook_delete_days', 3) else 3 end);
end $fn$;

-- may this staff member see this subject (the module, the scope's «see», the record's visibility)? Deleted rows count: a
-- *.deleted event is about a row still in the bin
create function app.subject_visible_for(p_staff uuid, p_entity text, p_id uuid) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities; v_owner uuid; v_vis text; v_found boolean;
begin
  select * into e from app.entities where key = p_entity;
  if not found or p_id is null then return false; end if;
  if e.module is not null and not app.module_on(e.module) then return false; end if;
  if not app.can_for(p_staff, e.scope, 'see') then return false; end if;
  if e.key = 'email_thread' then return false; end if;
  if e.owned then
    execute format('select t.owner_id, t.visibility, true from app.%I t where t.id = %L', e.tbl, p_id) into v_owner, v_vis, v_found;
    return coalesce(v_found, false) and app.visible_for(p_staff, v_owner, v_vis);
  end if;
  execute format('select exists (select 1 from app.%I t where t.id = %L)', e.tbl, p_id) into v_found;
  return v_found;
end $fn$;

-- the outbox subscriber: a webhookable event becomes attempt 1 for each active webhook on its kind whose owner may see it
create function app.sub_webhooks(ev app.events) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int;
begin
  if not exists (select 1 from app.event_catalog c where c.kind = ev.kind and c.webhookable) then return; end if;
  insert into app.webhook_deliveries (webhook_id, event_id, attempt, scheduled_at)
  select w.id, ev.id, 1, now() from app.webhooks w
  where w.event_kind = ev.kind and w.state = 'active' and w.is_sample = ev.is_sample
    and app.subject_visible_for(w.owner_id, ev.subject_type, ev.subject_id)
  on conflict do nothing;
  get diagnostics n = row_count;
  if n > 0 then perform pgmq.send('jobs', jsonb_build_object('job', 'webhook_send')); end if;
end $fn$;
insert into app.event_subscribers (name, fn, ord) values ('webhooks', 'app.sub_webhooks', 60);
insert into app.event_cursors (subscriber, last_event_id) values ('webhooks', coalesce((select max(id) from app.events), 0));

-- the body a delivery sends, built when it is sent: {event, object, id, occurred_at, meta, current, previous}. current = the row
-- now, without fields hidden from the webhook's owner; previous = current overlaid with the changelog's old values of the fields
-- the event changed, as of the event. The envelope (no values) is what the log keeps.
create function app.webhook_payload(p_delivery uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  d app.webhook_deliveries; w app.webhooks; ev app.events; e app.entities; v_cur jsonb; v_prev jsonb; v_fields text[]; f text; v_old jsonb;
  v_hidden text[]; v_set uuid; v_env jsonb; v_source text; v_action text;
begin
  select * into d from app.webhook_deliveries where id = p_delivery;
  select * into w from app.webhooks where id = d.webhook_id;
  select * into ev from app.events where id = d.event_id;
  v_action := split_part(ev.kind, '.', 2);
  v_fields := case when jsonb_typeof(ev.payload -> 'fields') = 'array' then array(select jsonb_array_elements_text(ev.payload -> 'fields')) else '{}' end;
  if ev.kind = 'webhook.ping' then
    v_env := jsonb_build_object('event', 'ping', 'object', 'webhook', 'id', w.id, 'occurred_at', ev.created_at,
                                'meta', jsonb_build_object('source', 'system', 'attempt', d.attempt, 'webhook_id', w.id, 'delivery_id', d.id), 'fields', '[]'::jsonb);
    return jsonb_build_object('envelope', v_env, 'body', (v_env - 'fields') || jsonb_build_object('current', jsonb_build_object('id', w.id), 'previous', null));
  end if;
  select * into e from app.entities where key = ev.subject_type;
  if e.key is not null then
    execute format('select to_jsonb(t) - ''edited_fields'' from app.%I t where t.id = %L', e.tbl, ev.subject_id) into v_cur;
    select permission_set_id into v_set from app.admins where id = w.owner_id;
    v_hidden := array(select fl.key from app.fields fl where fl.entity = e.key and v_set = any (fl.hidden_for));
    if v_cur is not null and cardinality(v_hidden) > 0 then
      v_cur := jsonb_set(v_cur, '{custom}', coalesce(v_cur -> 'custom', '{}'::jsonb) - v_hidden);
    end if;
    if v_action not in ('created', 'deleted') and v_cur is not null then
      v_prev := v_cur;
      foreach f in array v_fields loop
        continue when f like 'custom.%' and substr(f, 8) = any (v_hidden);
        select c.old_value into v_old from app.changelog c
        where c.entity = e.key and c.record_id = ev.subject_id and c.field = f and c.at <= ev.created_at order by c.id desc limit 1;
        if f like 'custom.%' then
          v_prev := jsonb_set(v_prev, array['custom', substr(f, 8)], coalesce(v_old, 'null'::jsonb), true);
        elsif v_prev ? f then
          v_prev := jsonb_set(v_prev, array[f], coalesce(v_old, 'null'::jsonb));
        end if;
      end loop;
    end if;
    select c.source into v_source from app.changelog c where c.entity = e.key and c.record_id = ev.subject_id and c.at <= ev.created_at
    order by c.id desc limit 1;
  end if;
  v_env := jsonb_build_object('event', ev.kind, 'object', ev.subject_type, 'id', ev.subject_id, 'occurred_at', ev.created_at,
                              'meta', jsonb_build_object('actor_id', ev.actor_id, 'source', coalesce(v_source, 'system'), 'attempt', d.attempt,
                                                         'webhook_id', w.id, 'delivery_id', d.id),
                              'fields', to_jsonb(v_fields));
  return jsonb_build_object('envelope', v_env, 'body', (v_env - 'fields') || jsonb_build_object('current', v_cur, 'previous', v_prev));
end $fn$;

-- a webhook goes: its secret leaves Vault, queued attempts are skipped, the owner hears why (SF-23 step 5)
create function app.webhook_remove(p_id uuid, p_reason text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare w app.webhooks;
begin
  select * into w from app.webhooks where id = p_id and state <> 'deleted' for update;
  if not found then return; end if;
  if w.vault_secret_id is not null then delete from vault.secrets where id = w.vault_secret_id; end if;
  update app.webhooks set state = 'deleted', deleted_at = now(), banned_until = null, vault_secret_id = null, updated_at = now(), version = version + 1 where id = p_id;
  update app.webhook_deliveries set state = 'skipped', error_code = 'webhook_deleted' where webhook_id = p_id and state = 'queued';
  if p_reason = 'failing' then
    perform app.notify(w.owner_id, 'system', 'webhook.deleted', jsonb_build_object('event', w.event_kind, 'host', substring(w.url from '^https://(?:[^@/]*@)?([^:/?#]+)')),
                       '/api?webhook=' || w.id, null, null);
    perform app.emit('webhook.deleted', 'webhook', w.id, jsonb_build_object('reason', p_reason), w.is_sample);
  end if;
end $fn$;

-- the sweep (every minute): bans that ran out, webhooks failing past the deletion horizon, and a nudge for due attempts
create function app.webhook_sweep() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p jsonb := app.webhook_policy(); v_unbanned int; v_deleted int := 0; v_due int; r record;
begin
  update app.webhooks set state = 'active', banned_until = null, first_attempt_failures = 0, updated_at = now()
  where state = 'banned' and banned_until <= now();
  get diagnostics v_unbanned = row_count;
  if p ->> 'delete_days' is not null then
    for r in select id from app.webhooks where state in ('active', 'banned', 'blocked') and failing_since is not null
               and failing_since < now() - make_interval(days => (p ->> 'delete_days')::int)
               and (last_success_at is null or last_success_at < failing_since) loop
      perform app.webhook_remove(r.id, 'failing');
      v_deleted := v_deleted + 1;
    end loop;
  end if;
  select count(*) into v_due from app.webhook_deliveries d join app.webhooks w on w.id = d.webhook_id
  where d.state = 'queued' and d.scheduled_at <= now() and w.state = 'active' and (d.claimed_at is null or d.claimed_at < now() - interval '2 minutes');
  if v_due > 0 then perform pgmq.send('jobs', jsonb_build_object('job', 'webhook_send')); end if;
  return jsonb_build_object('unbanned', v_unbanned, 'deleted', v_deleted, 'due', v_due);
end $fn$;

-- the webhooks a staff member sees (their own; all with global:configure), the limit, the policy and the recent deliveries
create function public.webhooks_get(p_filter jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_all boolean := app.can('global', 'configure'); f jsonb := coalesce(p_filter, '{}'::jsonb);
begin
  return jsonb_build_object(
    'webhooks', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'owner_id', w.owner_id, 'owner', (select coalesce(a.name, a.email) from app.admins a where a.id = w.owner_id),
                            'event_kind', w.event_kind, 'url', w.url, 'state', w.state, 'banned_until', w.banned_until, 'retrying',
                            exists (select 1 from app.webhook_deliveries d where d.webhook_id = w.id and d.state = 'queued' and d.attempt > 1),
                            'last_success_at', w.last_success_at, 'failing_since', w.failing_since, 'created_at', w.created_at, 'version', w.version,
                            'mine', w.owner_id = v_me) order by w.created_at desc)
                          from app.webhooks w where w.state <> 'deleted' and (w.owner_id = v_me or v_all)
                            and (f ->> 'owner_id' is null or w.owner_id::text = f ->> 'owner_id')
                            and w.is_sample = coalesce((select sandbox from app.admins where id = v_me), false)), '[]'::jsonb),
    'deliveries', coalesce((select jsonb_agg(x.j order by x.at desc) from (
                     select d.scheduled_at at, jsonb_build_object('id', d.id, 'webhook_id', d.webhook_id, 'at', coalesce(d.sent_at, d.scheduled_at),
                              'event', w.event_kind, 'host', substring(w.url from '^https://(?:[^@/]*@)?([^:/?#]+)'), 'status', d.response_status,
                              'state', d.state, 'attempt', d.attempt, 'attempts', 4, 'error', d.error_code) j
                     from app.webhook_deliveries d join app.webhooks w on w.id = d.webhook_id
                     where (w.owner_id = v_me or v_all) and d.state <> 'queued' or (w.owner_id = v_me or v_all) and d.attempt > 1
                     order by d.scheduled_at desc limit 20) x), '[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(c.kind order by c.family, c.kind) from app.event_catalog c where c.webhookable), '[]'::jsonb),
    'limit', app.count_limit(),
    'count_limits', app.setting('count_limits'),
    'policy', app.webhook_policy(),
    'can_manage_all', v_all);
end $fn$;

-- create (secret returned once) or edit a webhook. Create: a webhookable kind, a public https URL, within count_limits per owner
create function public.webhook_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_staff(); w app.webhooks; v_kind text := btrim(p_values ->> 'event_kind'); v_url text := btrim(p_values ->> 'url');
  v_secret text; v_id uuid := gen_random_uuid(); v_limit numeric := app.count_limit();
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  if p_id is null or p_values ? 'event_kind' then
    if not exists (select 1 from app.event_catalog c where c.kind = v_kind and c.webhookable) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'event_kind';
    end if;
  end if;
  if (p_id is null or p_values ? 'url') and not app.url_public(v_url) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'url'; end if;
  if p_id is null then
    if v_limit is not null and (select count(*) from app.webhooks where owner_id = v_me and state <> 'deleted') >= v_limit then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'count_limit';
    end if;
    v_secret := app.random_token('whsec_', 32);
    insert into app.webhooks (id, owner_id, event_kind, url, vault_secret_id, is_sample)
    values (v_id, v_me, v_kind, v_url, vault.create_secret(v_secret, 'webhook:' || v_id, 'A webhook''s signing secret (0044): read only by the database to sign its deliveries.'),
            coalesce((select sandbox from app.admins where id = v_me), false));
    perform app.log('webhook.saved', 'webhook', v_id::text, jsonb_build_object('event_kind', v_kind, 'created', true));
    return jsonb_build_object('id', v_id, 'version', 1, 'secret', v_secret);
  end if;
  select * into w from app.webhooks where id = p_id and state <> 'deleted' for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if w.owner_id <> v_me and not app.can('global', 'configure') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure'; end if;
  if p_version is not null and p_version <> w.version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = w.version::text; end if;
  update app.webhooks set event_kind = case when p_values ? 'event_kind' then v_kind else event_kind end,
                          url = case when p_values ? 'url' then v_url else url end,
                          state = case when p_values ? 'url' and state = 'blocked' then 'active' else state end,
                          version = version + 1, updated_at = now()
  where id = p_id returning * into w;
  perform app.log('webhook.saved', 'webhook', p_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('id', w.id, 'version', w.version);
end $fn$;

create function app.webhook_mine(p_id uuid) returns app.webhooks
  language plpgsql stable security definer set search_path = ''
as $fn$
declare w app.webhooks; v_me uuid := app.require_staff();
begin
  select * into w from app.webhooks where id = p_id and state <> 'deleted';
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if w.owner_id <> v_me and not app.can('global', 'configure') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure'; end if;
  return w;
end $fn$;

create function public.webhook_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare w app.webhooks := app.webhook_mine(p_id);
begin
  perform app.webhook_remove(w.id, 'deleted');
  perform app.log('webhook.deleted', 'webhook', w.id::text, null);
  return jsonb_build_object('id', w.id);
end $fn$;

-- pause or resume; a blocked webhook may be resumed after its owner fixed the target
create function public.webhook_set_state(p_id uuid, p_state text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare w app.webhooks := app.webhook_mine(p_id);
begin
  if p_state not in ('active', 'paused') or w.state = 'banned' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  update app.webhooks set state = p_state, updated_at = now(), version = version + 1 where id = w.id;
  perform app.log('webhook.saved', 'webhook', w.id::text, jsonb_build_object('state', p_state));
  return jsonb_build_object('id', w.id, 'state', p_state);
end $fn$;

-- «Send test»: a synthetic ping event as attempt 1 for this webhook only
create function public.webhook_test(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare w app.webhooks := app.webhook_mine(p_id); v_ev bigint; v_id uuid;
begin
  if w.state <> 'active' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  v_ev := app.emit('webhook.ping', 'webhook', w.id, '{}'::jsonb, w.is_sample);
  insert into app.webhook_deliveries (webhook_id, event_id, attempt) values (w.id, v_ev, 1) returning id into v_id;
  perform pgmq.send('jobs', jsonb_build_object('job', 'webhook_send'));
  perform app.log('webhook.tested', 'webhook', w.id::text, null);
  return jsonb_build_object('delivery_id', v_id);
end $fn$;

-- «Redeliver»: a fresh attempt 1 of a past event
create function public.webhook_redeliver(p_delivery uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d app.webhook_deliveries; w app.webhooks; v_id uuid;
begin
  select * into d from app.webhook_deliveries where id = p_delivery;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  w := app.webhook_mine(d.webhook_id);
  if w.state <> 'active' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  insert into app.webhook_deliveries (webhook_id, event_id, redelivery, attempt)
  values (w.id, d.event_id, (select coalesce(max(x.redelivery), 0) + 1 from app.webhook_deliveries x where x.webhook_id = w.id and x.event_id = d.event_id), 1)
  returning id into v_id;
  perform pgmq.send('jobs', jsonb_build_object('job', 'webhook_send'));
  perform app.log('webhook.redelivered', 'webhook', w.id::text, jsonb_build_object('delivery', d.id));
  return jsonb_build_object('delivery_id', v_id);
end $fn$;

create function public.webhook_deliveries_get(p_webhook uuid, p_cursor timestamptz default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare w app.webhooks;
begin
  select * into w from app.webhooks where id = p_webhook;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if w.owner_id <> app.require_staff() and not app.can('global', 'configure') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'event_id', d.event_id, 'event', w.event_kind, 'attempt', d.attempt, 'attempts', 4,
                                                       'redelivery', d.redelivery, 'state', d.state, 'scheduled_at', d.scheduled_at, 'sent_at', d.sent_at,
                                                       'status', d.response_status, 'duration_ms', d.duration_ms, 'error', d.error_code) order by d.scheduled_at desc)
                   from (select * from app.webhook_deliveries x where x.webhook_id = w.id and (p_cursor is null or x.scheduled_at < p_cursor)
                         order by x.scheduled_at desc limit 50) d), '[]'::jsonb);
end $fn$;

-- one delivery as logged: the envelope (event, object, id, meta, the changed fields' names) and the body's hash; an audited read
create function public.webhook_delivery_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d app.webhook_deliveries; w app.webhooks;
begin
  select * into d from app.webhook_deliveries where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into w from app.webhooks where id = d.webhook_id;
  if w.owner_id <> app.require_staff() and not app.can('global', 'configure') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
  end if;
  perform app.log('webhook_delivery.read', 'webhook', w.id::text, jsonb_build_object('delivery', d.id));
  return jsonb_build_object('id', d.id, 'event', w.event_kind, 'attempt', d.attempt, 'attempts', 4, 'state', d.state, 'status', d.response_status,
                            'duration_ms', d.duration_ms, 'error', d.error_code, 'scheduled_at', d.scheduled_at, 'sent_at', d.sent_at,
                            'envelope', d.envelope, 'body_sha256', encode(d.body_sha256, 'hex'), 'bytes', d.bytes,
                            'signature_header', 'Sentral-Signature', 'signed_at', d.signed_at);
end $fn$;

-- the worker: due attempts with their signed body. The secret never leaves the database: the signature is
-- t=<unix>,v1=<hex HMAC-SHA256(secret, t || '.' || body)> and the worker must send the body exactly as given
create function public.worker_webhook_claim(p_limit int default 20) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d record; v_p jsonb; v_body text; v_secret text; v_t bigint; v_out jsonb := '[]'::jsonb; v_pol jsonb := app.webhook_policy(); ev app.events;
begin
  for d in select x.id, x.webhook_id, x.event_id, x.attempt, w.owner_id, w.url, w.vault_secret_id from app.webhook_deliveries x join app.webhooks w on w.id = x.webhook_id
           where x.state = 'queued' and x.scheduled_at <= now() and w.state = 'active' and (x.claimed_at is null or x.claimed_at < now() - interval '2 minutes')
           order by x.scheduled_at limit least(greatest(coalesce(p_limit, 20), 1), 100) for update of x skip locked loop
    select * into ev from app.events where id = d.event_id;
    if ev.kind <> 'webhook.ping' and not app.subject_visible_for(d.owner_id, ev.subject_type, ev.subject_id) then
      update app.webhook_deliveries set state = 'skipped', error_code = 'not_visible', claimed_at = now() where id = d.id;
      continue;
    end if;
    v_p := app.webhook_payload(d.id);
    v_body := (v_p -> 'body')::text;
    select s.decrypted_secret into v_secret from vault.decrypted_secrets s where s.id = d.vault_secret_id;
    if v_secret is null then
      update app.webhook_deliveries set state = 'skipped', error_code = 'no_secret', claimed_at = now() where id = d.id;
      continue;
    end if;
    v_t := extract(epoch from now())::bigint;
    update app.webhook_deliveries set claimed_at = now(), envelope = v_p -> 'envelope', body_sha256 = extensions.digest(v_body, 'sha256'),
      bytes = octet_length(v_body), signed_at = v_t where id = d.id;
    v_out := v_out || jsonb_build_object('delivery_id', d.id, 'url', d.url, 'body', v_body, 'attempt', d.attempt, 'timeout_s', v_pol -> 'timeout_s',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'Sentral-Event', ev.kind, 'Sentral-Delivery', d.id,
                                    'Sentral-Signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_body, v_secret, 'sha256'), 'hex')));
  end loop;
  return v_out;
end $fn$;

-- the worker reports an attempt: success clears the failure streak; a failure schedules the next attempt (3, 30, 150 s), counts
-- first-attempt failures and bans past the policy; a private address found at send time blocks the webhook
create function public.worker_webhook_done(p_delivery uuid, p_status int, p_ms int, p_error text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d app.webhook_deliveries; w app.webhooks; v_ok boolean; v_pol jsonb := app.webhook_policy(); v_next timestamptz;
begin
  select * into d from app.webhook_deliveries where id = p_delivery and state = 'queued' and claimed_at is not null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_error is not null and p_error !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'error'; end if;
  v_ok := p_error is null and p_status between 200 and 299;
  update app.webhook_deliveries set state = case when v_ok then 'sent' else 'failed' end, sent_at = now(), response_status = p_status,
    duration_ms = greatest(p_ms, 0), error_code = p_error where id = d.id;
  select * into w from app.webhooks where id = d.webhook_id for update;
  if v_ok then
    update app.webhooks set first_attempt_failures = 0, last_success_at = now(), failing_since = null where id = w.id;
    return jsonb_build_object('state', 'sent');
  end if;
  if p_error = 'private_address' then
    update app.webhooks set state = 'blocked', updated_at = now() where id = w.id and state = 'active';
    return jsonb_build_object('state', 'failed', 'webhook', 'blocked');
  end if;
  update app.webhooks set failing_since = coalesce(failing_since, now()),
    first_attempt_failures = first_attempt_failures + case when d.attempt = 1 then 1 else 0 end
  where id = w.id returning * into w;
  if d.attempt < 4 then
    v_next := now() + make_interval(secs => (v_pol -> 'retry_s' ->> (d.attempt - 1))::int);
    insert into app.webhook_deliveries (webhook_id, event_id, redelivery, attempt, scheduled_at) values (w.id, d.event_id, d.redelivery, d.attempt + 1, v_next)
    on conflict do nothing;
  end if;
  if w.state = 'active' and v_pol ->> 'ban_after' is not null and w.first_attempt_failures >= (v_pol ->> 'ban_after')::int then
    update app.webhooks set state = 'banned', banned_until = now() + make_interval(mins => (v_pol ->> 'ban_min')::int), updated_at = now() where id = w.id;
    perform app.notify(w.owner_id, 'system', 'webhook.banned', jsonb_build_object('event', w.event_kind, 'host', substring(w.url from '^https://(?:[^@/]*@)?([^:/?#]+)'),
                       'minutes', (v_pol ->> 'ban_min')::int), '/api?webhook=' || w.id, null, null);
    perform app.emit('webhook.banned', 'webhook', w.id, jsonb_build_object('failures', w.first_attempt_failures), w.is_sample);
    return jsonb_build_object('state', 'failed', 'next_at', v_next, 'webhook', 'banned');
  end if;
  return jsonb_build_object('state', 'failed', 'next_at', v_next);
end $fn$;

-- ===========================================================================
-- REST API and tokens (§1.2; INT-01..03)
-- ===========================================================================
-- the plural a record type has in a path (/v2/persons, /v2/activities)
create function app.api_plural(p_entity text) returns text
  language sql immutable set search_path = ''
as $fn$ select case when p_entity ~ 'y$' then regexp_replace(p_entity, 'y$', 'ies') else p_entity || 's' end $fn$;

-- the record types the API and the AI connector serve: every registered type except mail threads (their access follows the
-- mailbox, not a scope)
create function app.api_entities() returns setof app.entities
  language sql stable security definer set search_path = ''
as $fn$ select * from app.entities where key <> 'email_thread' order by ord $fn$;

-- the endpoint rows the screen lists: method, path, operation, cost (Part F)
create function app.api_endpoints() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(x.j order by x.o), '[]'::jsonb) from (
    select e.ord * 10 + m.o o, jsonb_build_object('method', m.method, 'path', '/v2/' || app.api_plural(e.key) || m.suffix, 'op', m.op, 'entity', e.key,
                                                  'cost', (select c.cost from app.api_costs c where c.op = m.op)) j
    from app.api_entities() e cross join (values (1, 'GET', '', 'list'), (2, 'POST', '', 'create'), (3, 'GET', '/{id}', 'get'), (4, 'PATCH', '/{id}', 'update'),
                                                 (5, 'DELETE', '/{id}', 'delete'), (6, 'DELETE', '', 'delete_list')) m(o, method, suffix, op)
    union all
    select 100000 + o, jsonb_build_object('method', method, 'path', path, 'op', op, 'entity', ent, 'cost', (select c.cost from app.api_costs c where c.op = x.op))
    from (values (1, 'GET', '/v2/search', 'search', null), (2, 'POST', '/v2/leads/{id}/convert', 'convert', 'lead'),
                 (3, 'POST', '/v2/{entity}/merge', 'merge', null), (4, 'GET', '/v2/index/search', 'index_search', null)) x(o, method, path, op, ent)) x
$fn$;

-- the column kinds as JSON Schema
create function app.api_schema_type(p_kind text) returns jsonb
  language sql immutable set search_path = ''
as $fn$
  select case p_kind when 'int' then '{"type":"integer"}' when 'numeric' then '{"type":"number"}' when 'boolean' then '{"type":"boolean"}'
                     when 'date' then '{"type":"string","format":"date"}' when 'timestamptz' then '{"type":"string","format":"date-time"}'
                     when 'uuid' then '{"type":"string","format":"uuid"}' when 'uuid[]' then '{"type":"array","items":{"type":"string","format":"uuid"}}'
                     when 'text[]' then '{"type":"array","items":{"type":"string"}}' when 'jsonb' then '{"type":"object"}' else '{"type":"string"}' end::jsonb
$fn$;

-- the API definition, generated from the registry (INT-01: «generated from the same registry»): OpenAPI 3.1 with every record
-- type, its columns and its custom fields, the cost per operation, and the AI connector's tool list (MCP-02)
create function public.api_definition() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_paths jsonb := '{}'::jsonb; v_schemas jsonb := '{}'::jsonb; v_tools jsonb := '[]'::jsonb; e app.entities; v_props jsonb; v_custom jsonb; p text;
begin
  perform app.require_staff();
  for e in select * from app.api_entities() loop
    p := '/' || app.api_plural(e.key);
    select coalesce(jsonb_object_agg(c.col, app.api_schema_type(c.kind) || case when not c.writable then '{"readOnly":true}'::jsonb else '{}'::jsonb end), '{}'::jsonb)
      into v_props from app.entity_columns c where c.entity = e.key;
    select coalesce(jsonb_object_agg(f.key, jsonb_build_object('title', f.label, 'x-field-type', f.type)), '{}'::jsonb)
      into v_custom from app.fields f where f.entity = e.key and f.archived_at is null;
    v_props := v_props || jsonb_build_object('id', '{"type":"string","format":"uuid","readOnly":true}'::jsonb, 'version', '{"type":"integer","readOnly":true}'::jsonb,
                                             'labels', app.api_schema_type('uuid[]'), 'custom', jsonb_build_object('type', 'object', 'properties', v_custom))
               || case when e.owned then jsonb_build_object('owner_id', app.api_schema_type('uuid'), 'visibility', '{"type":"string","enum":["owner","group","group_sub","all"]}'::jsonb) else '{}'::jsonb end;
    v_schemas := v_schemas || jsonb_build_object(e.key, jsonb_build_object('type', 'object', 'properties', v_props,
                   'required', coalesce((select jsonb_agg(c.col) from app.entity_columns c where c.entity = e.key and c.required), '[]'::jsonb)));
    v_paths := v_paths || jsonb_build_object(p, jsonb_build_object(
                 'get', jsonb_build_object('operationId', 'list_' || app.api_plural(e.key), 'x-cost', (select cost from app.api_costs where op = 'list'),
                                           'parameters', '[{"name":"cursor","in":"query","schema":{"type":"string"}},{"name":"filter","in":"query","schema":{"type":"string"}}]'::jsonb),
                 'post', jsonb_build_object('operationId', 'add_' || e.key, 'x-cost', (select cost from app.api_costs where op = 'create'),
                                            'requestBody', jsonb_build_object('content', jsonb_build_object('application/json', jsonb_build_object('schema', jsonb_build_object('$ref', '#/components/schemas/' || e.key))))),
                 'delete', jsonb_build_object('operationId', 'delete_' || app.api_plural(e.key), 'x-cost', (select cost from app.api_costs where op = 'delete_list'))),
               p || '/{id}', jsonb_build_object(
                 'get', jsonb_build_object('operationId', 'get_' || e.key, 'x-cost', (select cost from app.api_costs where op = 'get')),
                 'patch', jsonb_build_object('operationId', 'update_' || e.key, 'x-cost', (select cost from app.api_costs where op = 'update')),
                 'delete', jsonb_build_object('operationId', 'delete_' || e.key, 'x-cost', (select cost from app.api_costs where op = 'delete'))));
    v_tools := v_tools || jsonb_build_array(
      jsonb_build_object('name', 'list_' || app.api_plural(e.key), 'op', 'list', 'entity', e.key, 'input_schema', '{"type":"object","properties":{"query":{"type":"object"}}}'::jsonb),
      jsonb_build_object('name', 'get_' || e.key, 'op', 'get', 'entity', e.key, 'input_schema', '{"type":"object","properties":{"id":{"type":"string","format":"uuid"}},"required":["id"]}'::jsonb),
      jsonb_build_object('name', 'add_' || e.key, 'op', 'create', 'entity', e.key, 'input_schema', jsonb_build_object('type', 'object', 'properties', jsonb_build_object('values', jsonb_build_object('$ref', '#/components/schemas/' || e.key)))),
      jsonb_build_object('name', 'update_' || e.key, 'op', 'update', 'entity', e.key, 'input_schema', jsonb_build_object('type', 'object', 'properties', jsonb_build_object('id', '{"type":"string","format":"uuid"}'::jsonb, 'version', '{"type":"integer"}'::jsonb, 'values', jsonb_build_object('$ref', '#/components/schemas/' || e.key)), 'required', '["id","values"]'::jsonb)),
      jsonb_build_object('name', 'delete_' || e.key, 'op', 'delete', 'entity', e.key, 'input_schema', '{"type":"object","properties":{"id":{"type":"string","format":"uuid"}},"required":["id"]}'::jsonb));
  end loop;
  v_paths := v_paths || jsonb_build_object(
    '/search', jsonb_build_object('get', jsonb_build_object('operationId', 'search', 'x-cost', (select cost from app.api_costs where op = 'search'))),
    '/leads/{id}/convert', jsonb_build_object('post', jsonb_build_object('operationId', 'convert_lead_to_deal', 'x-cost', (select cost from app.api_costs where op = 'convert'))),
    '/{entity}/merge', jsonb_build_object('post', jsonb_build_object('operationId', 'merge_records', 'x-cost', (select cost from app.api_costs where op = 'merge'))),
    '/index/search', jsonb_build_object('get', jsonb_build_object('operationId', 'find_records', 'x-cost', (select cost from app.api_costs where op = 'index_search'))));
  v_tools := v_tools || jsonb_build_array(
    jsonb_build_object('name', 'search', 'op', 'search', 'entity', null, 'input_schema', '{"type":"object","properties":{"q":{"type":"string"}},"required":["q"]}'::jsonb),
    jsonb_build_object('name', 'find_records', 'op', 'index_search', 'entity', null, 'input_schema', '{"type":"object","properties":{"q":{"type":"string"},"limit":{"type":"integer"}},"required":["q"]}'::jsonb),
    jsonb_build_object('name', 'convert_lead_to_deal', 'op', 'convert', 'entity', 'lead', 'input_schema', '{"type":"object","properties":{"id":{"type":"string","format":"uuid"},"pipeline_id":{"type":"string","format":"uuid"},"stage_id":{"type":"string","format":"uuid"}},"required":["id"]}'::jsonb));
  return jsonb_build_object('openapi', '3.1.0', 'info', jsonb_build_object('title', 'Sentral API', 'version', '2'),
    'servers', '[{"url":"/v2"}]'::jsonb, 'paths', v_paths, 'components', jsonb_build_object('schemas', v_schemas,
      'securitySchemes', '{"bearer":{"type":"http","scheme":"bearer"}}'::jsonb), 'security', '[{"bearer":[]}]'::jsonb,
    'x-pagination', 'cursor', 'x-costs', (select jsonb_object_agg(op, cost) from app.api_costs), 'tools', v_tools);
end $fn$;

-- the day's budget: base × multiplier × active staff (D-17: the multiplier is a setting, not a plan)
create function app.api_budget() returns bigint
  language sql stable security definer set search_path = ''
as $fn$
  select (case when app.setting('api_rate') = 'custom' then app.setting_num('api_budget_base', 30000) else 30000 end
          * case when app.setting('api_rate') = 'custom' then app.setting_num('api_plan_multiplier', 1) else 1 end
          * greatest((select count(*) from app.admins a where a.active and not a.is_sample), 1))::bigint
$fn$;

-- the burst limit per 2 s for a principal and an operation
create function app.api_burst_limit(p_kind text, p_op text) returns int
  language sql stable security definer set search_path = ''
as $fn$
  select (case when p_op in ('search', 'index_search') then case when app.setting('api_rate') = 'custom' then app.setting_num('api_burst_search', 10) else 10 end
               when p_kind = 'token' then case when app.setting('api_rate') = 'custom' then app.setting_num('api_burst_token', 20) else 20 end
               else case when app.setting('api_rate') = 'custom' then app.setting_num('api_burst_oauth', 80) else 80 end end)::int
$fn$;

-- the budget passed a threshold today: global:configure hears it once (in-app until the email provider exists, D-07)
create function app.api_budget_warn(p_pct int, p_budget bigint) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.notify_once(a.id, 'system', 'api.budget_warning', jsonb_build_object('percent', p_pct, 'budget', p_budget), '/api', null, null,
                          'api_budget:' || ((now() at time zone 'Europe/Oslo')::date) || ':' || p_pct || ':' || a.id)
  from app.admins a where a.active and not a.is_sample and app.can_for(a.id, 'global', 'configure');
  perform app.emit(case when p_pct >= 100 then 'usage.limit_reached' else 'usage.limit_warning' end, null, null, jsonb_build_object('percent', p_pct, 'budget', p_budget));
end $fn$;

-- meter one call (INT-03): off → no limit; otherwise the burst window, then the day's budget. → {allowed, limit, remaining, reset, reason}
create function app.api_meter(p_kind text, p_principal uuid, p_op text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_sec bigint := floor(extract(epoch from clock_timestamp()))::bigint; v_lim int; v_n bigint; v_budget bigint; v_cost int; v_used bigint;
  v_day date := (now() at time zone 'Europe/Oslo')::date; d app.api_budget_day;
  v_reset bigint := extract(epoch from (((now() at time zone 'Europe/Oslo')::date + 1)::timestamp at time zone 'Europe/Oslo'))::bigint;
begin
  if app.setting('api_rate') = 'off' then return jsonb_build_object('allowed', true, 'limit', null, 'remaining', null, 'reset', null); end if;
  v_lim := app.api_burst_limit(p_kind, p_op);
  select coalesce(sum(n), 0) into v_n from app.api_burst where principal_id = p_principal and second >= v_sec - 1;
  if v_n >= v_lim then
    return jsonb_build_object('allowed', false, 'reason', 'burst', 'limit', v_lim, 'remaining', 0, 'reset', v_sec + 2);
  end if;
  insert into app.api_burst (principal_id, second, n) values (p_principal, v_sec, 1)
  on conflict (principal_id, second) do update set n = app.api_burst.n + 1;
  v_budget := app.api_budget();
  v_cost := coalesce((select cost from app.api_costs where op = p_op), 0);
  insert into app.api_budget_day (day) values (v_day) on conflict do nothing;
  select * into d from app.api_budget_day where day = v_day for update;
  if d.used + v_cost > v_budget then
    if d.warned100_at is null then
      update app.api_budget_day set warned100_at = now() where day = v_day;
      perform app.api_budget_warn(100, v_budget);
    end if;
    return jsonb_build_object('allowed', false, 'reason', 'budget', 'limit', v_budget, 'remaining', greatest(v_budget - d.used, 0), 'reset', v_reset);
  end if;
  v_used := d.used + v_cost;
  update app.api_budget_day set used = v_used where day = v_day;
  if v_used >= v_budget * 0.75 and d.warned75_at is null then
    update app.api_budget_day set warned75_at = now() where day = v_day;
    perform app.api_budget_warn(75, v_budget);
  end if;
  return jsonb_build_object('allowed', true, 'limit', v_budget, 'remaining', v_budget - v_used, 'reset', v_reset);
end $fn$;

-- a bearer token by its hash: an active personal token or a live grant → {kind, id, staff_id, mcp, scopes}, else null
create function app.api_principal_of(p_hash bytea) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select x.j from (
    select jsonb_build_object('kind', 'token', 'id', t.id, 'staff_id', t.staff_id, 'mcp', false, 'scopes', to_jsonb(t.scopes)) j
    from app.api_tokens t join app.admins a on a.id = t.staff_id
    where t.token_sha256 = p_hash and t.revoked_at is null and (t.expires_at is null or t.expires_at > now()) and a.active
    union all
    select jsonb_build_object('kind', 'grant', 'id', g.id, 'staff_id', g.staff_id, 'mcp', ap.kind = 'mcp', 'scopes', to_jsonb(g.scopes))
    from app.oauth_grants g join app.oauth_apps ap on ap.id = g.app_id join app.admins a on a.id = g.staff_id
    where g.access_sha256 = p_hash and g.revoked_at is null and g.access_expires_at > now() and ap.disabled_at is null and a.active
      and (ap.kind <> 'mcp' or app.setting('mcp_access') = 'on')) x
  limit 1
$fn$;

-- a uuid argument, or invalid with the argument's name
create function app.arg_uuid(p_args jsonb, p_key text) returns uuid
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if coalesce(p_args ->> p_key, '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = p_key;
  end if;
  return (p_args ->> p_key)::uuid;
end $fn$;

-- the gateway's check (worker): who a token is and what limits apply, or null (INT-02: a revoked token or grant is refused)
create function public.worker_api_auth(p_hash bytea) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v jsonb := app.api_principal_of(p_hash);
begin
  if v is null then return null; end if;
  return v || jsonb_build_object('rate', jsonb_build_object('mode', app.setting('api_rate'), 'budget_day', case when app.setting('api_rate') <> 'off' then app.api_budget() end,
                                                            'burst', case when app.setting('api_rate') <> 'off' then app.api_burst_limit(v ->> 'kind', 'get') end));
end $fn$;

-- one API or assistant call (§1.2 step 3). It sets the principal for this transaction (app.me() answers for the token,
-- app.can() intersects its scopes), the audit's source and principal (app.source, app.principal_kind, app.principal_id), meters
-- the call, and runs the same definer functions the screens use. → {status: 200|429, body, rate:{limit, remaining, reset}}
create function public.api_exec(p_hash bytea, p_op text, p_args jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_auth jsonb := app.api_principal_of(p_hash); a jsonb := coalesce(p_args, '{}'::jsonb); v_kind text; v_pid uuid; v_mcp boolean;
  v_meter jsonb; v_res jsonb; v_src text; v_key text; v_ent text := a ->> 'entity';
begin
  if v_auth is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  if p_op is null or p_op not in (select op from app.api_costs) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'op'; end if;
  v_kind := v_auth ->> 'kind'; v_pid := (v_auth ->> 'id')::uuid; v_mcp := (v_auth ->> 'mcp')::boolean;
  perform set_config('app.api_principal', v_kind || ':' || v_pid, true);
  perform set_config('app.source', case when v_mcp then 'mcp' else 'api' end, true);
  perform set_config('app.principal_kind', case when v_kind = 'token' then 'token' else 'oauth' end, true);
  perform set_config('app.principal_id', v_pid::text, true);
  if app.me() is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  if v_ent is not null and v_ent = 'email_thread' then raise exception 'not_found' using errcode = 'no_data_found', detail = 'entity'; end if;
  v_meter := app.api_meter(v_kind, v_pid, p_op);
  if not (v_meter ->> 'allowed')::boolean then
    return jsonb_build_object('status', 429, 'reason', v_meter ->> 'reason', 'rate', v_meter - 'allowed' - 'reason');
  end if;
  if v_kind = 'token' then update app.api_tokens set last_used_at = now() where id = v_pid and (last_used_at is null or last_used_at < now() - interval '1 minute');
  else update app.oauth_grants set last_used_at = now() where id = v_pid and (last_used_at is null or last_used_at < now() - interval '1 minute'); end if;
  v_src := case when v_mcp then 'assistant' else 'api' end;
  case p_op
    when 'list' then v_res := public.rec_list(v_ent, coalesce(a -> 'query', '{}'::jsonb));
    when 'get' then v_res := public.rec_get(v_ent, app.arg_uuid(a, 'id'), a ->> 'reason');
    when 'create' then
      v_key := a ->> 'idempotency_key';
      if v_key is not null then
        if char_length(v_key) not between 8 and 100 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'idempotency_key'; end if;
        select i.response into v_res from app.api_idempotency i where i.principal_id = v_pid and i.key = v_key and i.created_at > now() - interval '24 hours';
        if found then return jsonb_build_object('status', 200, 'body', v_res, 'replayed', true, 'rate', v_meter - 'allowed'); end if;
      end if;
      v_res := public.rec_save(v_ent, null, a -> 'values', null, a ->> 'reason', v_src);
      if v_key is not null then
        insert into app.api_idempotency (principal_id, key, response) values (v_pid, v_key, v_res)
        on conflict (principal_id, key) do update set response = excluded.response, created_at = now();
      end if;
    when 'update' then v_res := public.rec_save(v_ent, app.arg_uuid(a, 'id'), a -> 'values', (a ->> 'version')::int, a ->> 'reason', v_src);
    when 'delete' then v_res := public.rec_delete(v_ent, array[app.arg_uuid(a, 'id')], a ->> 'reason');
    when 'delete_list' then
      if jsonb_typeof(a -> 'ids') <> 'array' or exists (select 1 from jsonb_array_elements_text(a -> 'ids') x where x !~* '^[0-9a-f-]{36}$') then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids';
      end if;
      v_res := public.rec_delete(v_ent, array(select jsonb_array_elements_text(a -> 'ids'))::uuid[], a ->> 'reason');
    when 'search' then v_res := public.search(a ->> 'q');
    when 'index_search' then v_res := app.mcp_search(a ->> 'q', coalesce((a ->> 'limit')::int, 20));
    when 'convert' then v_res := public.lead_convert(app.arg_uuid(a, 'id'), (a ->> 'pipeline_id')::uuid, (a ->> 'stage_id')::uuid);
    when 'merge' then v_res := public.records_merge(v_ent, app.arg_uuid(a, 'keep'), app.arg_uuid(a, 'merge'), coalesce(a -> 'values', '{}'::jsonb));
  end case;
  return jsonb_build_object('status', 200, 'body', v_res, 'rate', v_meter - 'allowed');
end $fn$;

-- the gateway's usage, in batches (counts only)
create function public.worker_api_usage(p_rows jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r jsonb; n int := 0;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if r ->> 'principal_kind' not in ('token', 'grant') or coalesce(r ->> 'principal_id', '') !~* '^[0-9a-f-]{36}$' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'principal';
    end if;
    insert into app.api_requests_hourly (hour, principal_kind, principal_id, requests, cost, throttled)
    values (date_trunc('hour', coalesce((r ->> 'hour')::timestamptz, now())), r ->> 'principal_kind', (r ->> 'principal_id')::uuid,
            greatest(coalesce((r ->> 'requests')::int, 0), 0), greatest(coalesce((r ->> 'cost')::bigint, 0), 0), greatest(coalesce((r ->> 'throttled')::int, 0), 0))
    on conflict (hour, principal_kind, principal_id) do update set requests = app.api_requests_hourly.requests + excluded.requests,
      cost = app.api_requests_hourly.cost + excluded.cost, throttled = app.api_requests_hourly.throttled + excluded.throttled;
    n := n + 1;
  end loop;
  return jsonb_build_object('rows', n);
end $fn$;

-- a new personal token, shown once (INT-02); refused while one is active (rotate instead). A second factor within 10 minutes
create function public.api_token_create(p_name text, p_expires_at timestamptz default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_tok text; v_id uuid;
begin
  perform app.require_fresh_mfa(10);
  if coalesce(btrim(p_name), '') = '' or char_length(btrim(p_name)) > 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if p_expires_at is not null and p_expires_at <= now() then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'expires_at'; end if;
  if exists (select 1 from app.api_tokens where staff_id = v_me and revoked_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'active_token';
  end if;
  v_tok := app.random_token('sk_live_', 32);
  insert into app.api_tokens (staff_id, name, token_sha256, last4, expires_at, is_sample)
  values (v_me, btrim(p_name), extensions.digest(v_tok, 'sha256'), right(v_tok, 4), p_expires_at, coalesce((select sandbox from app.admins where id = v_me), false))
  returning id into v_id;
  perform app.log('api_token.created', 'api_token', v_id::text, null);
  perform app.emit('api_token.created', 'api_token', v_id, '{}'::jsonb);
  return jsonb_build_object('id', v_id, 'token', v_tok, 'masked', 'sk_live_…' || right(v_tok, 4), 'expires_at', p_expires_at);
end $fn$;

-- rotate: the active token stops at once and a new one is shown once (INT-02 «rotating invalidates the old one at once»)
create function public.api_token_rotate() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); t app.api_tokens; v_tok text; v_id uuid;
begin
  perform app.require_fresh_mfa(10);
  select * into t from app.api_tokens where staff_id = v_me and revoked_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.api_tokens set revoked_at = now(), revoked_by = v_me, revoke_reason = 'rotated' where id = t.id;
  v_tok := app.random_token('sk_live_', 32);
  insert into app.api_tokens (staff_id, name, token_sha256, last4, scopes, expires_at, is_sample)
  values (v_me, t.name, extensions.digest(v_tok, 'sha256'), right(v_tok, 4), t.scopes,
          case when t.expires_at is not null then now() + (t.expires_at - t.created_at) end, t.is_sample)
  returning id into v_id;
  perform app.log('api_token.rotated', 'api_token', v_id::text, jsonb_build_object('previous', t.id));
  perform app.emit('api_token.revoked', 'api_token', t.id, jsonb_build_object('reason', 'rotated'));
  perform app.emit('api_token.created', 'api_token', v_id, '{}'::jsonb);
  return jsonb_build_object('id', v_id, 'token', v_tok, 'masked', 'sk_live_…' || right(v_tok, 4));
end $fn$;

-- revoke at once: the token's owner, or global:security
create function public.api_token_revoke(p_id uuid, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); t app.api_tokens;
begin
  select * into t from app.api_tokens where id = p_id and revoked_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.staff_id <> v_me and not app.can('global', 'security') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:security'; end if;
  perform app.take_reason(p_reason);
  update app.api_tokens set revoked_at = now(), revoked_by = v_me, revoke_reason = 'revoked' where id = t.id;
  perform app.log('api_token.revoked', 'api_token', t.id::text, null);
  perform app.emit('api_token.revoked', 'api_token', t.id, jsonb_build_object('reason', 'revoked'));
  return jsonb_build_object('id', t.id);
end $fn$;

-- the REST API tab: endpoints, tokens and grants (one's own; all with global:security), the rate status, 24 h usage
create function public.api_overview() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_sec boolean := app.can('global', 'security'); v_all boolean := app.can('global', 'security') or app.can('global', 'configure');
  v_day date := (now() at time zone 'Europe/Oslo')::date;
begin
  return jsonb_build_object(
    'endpoints', app.api_endpoints(),
    'tokens', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'kind', 'personal', 'name', t.name, 'staff', (select coalesce(a.name, a.email) from app.admins a where a.id = t.staff_id),
                          'masked', t.prefix || '…' || t.last4, 'scopes', to_jsonb(t.scopes), 'created_at', t.created_at, 'last_used_at', t.last_used_at,
                          'expires_at', t.expires_at, 'mine', t.staff_id = v_me) order by t.staff_id = v_me desc, t.created_at)
                        from app.api_tokens t where t.revoked_at is null and (t.staff_id = v_me or v_sec)), '[]'::jsonb),
    'grants', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'kind', ap.kind, 'app', ap.name, 'client', left(ap.client_id, 10) || '…',
                          'staff', (select coalesce(a.name, a.email) from app.admins a where a.id = g.staff_id), 'scopes', to_jsonb(g.scopes),
                          'created_at', g.created_at, 'last_used_at', g.last_used_at, 'mine', g.staff_id = v_me) order by g.created_at)
                        from app.oauth_grants g join app.oauth_apps ap on ap.id = g.app_id where g.revoked_at is null and (g.staff_id = v_me or v_sec)), '[]'::jsonb),
    'has_token', exists (select 1 from app.api_tokens where staff_id = v_me and revoked_at is null),
    'rate', jsonb_build_object('mode', app.setting('api_rate'), 'budget_day', case when app.setting('api_rate') <> 'off' then app.api_budget() end,
                               'used_today', case when app.setting('api_rate') <> 'off' then coalesce((select used from app.api_budget_day where day = v_day), 0) end,
                               'burst_token', case when app.setting('api_rate') <> 'off' then app.api_burst_limit('token', 'get') end,
                               'burst_oauth', case when app.setting('api_rate') <> 'off' then app.api_burst_limit('grant', 'get') end,
                               'burst_search', case when app.setting('api_rate') <> 'off' then app.api_burst_limit('token', 'search') end),
    'usage', (select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'requests', coalesce(u.n, 0)) order by h), '[]'::jsonb)
              from generate_series(date_trunc('hour', now()) - interval '23 hours', date_trunc('hour', now()), interval '1 hour') h
              left join lateral (select sum(r.requests) n from app.api_requests_hourly r where r.hour = h
                                   and (v_all or (r.principal_kind = 'token' and r.principal_id in (select id from app.api_tokens where staff_id = v_me))
                                        or (r.principal_kind = 'grant' and r.principal_id in (select id from app.oauth_grants where staff_id = v_me)))) u on true),
    'usage_scope', case when v_all then 'company' else 'mine' end);
end $fn$;

-- ===========================================================================
-- OAuth apps and grants (§1.2, §1.5; UF-16 step 2, MCP-01..03)
-- ===========================================================================
-- scopes an app may ask for: known scopes only
create function app.scopes_ok(p_scopes text[]) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select cardinality(p_scopes) between 1 and 20 and not exists (select 1 from unnest(p_scopes) s where s not in (select scope from app.api_scopes))
$fn$;

-- redirect URIs: https, public hosts, at most ten (exact match at authorisation)
create function app.redirects_ok(p_uris text[]) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select cardinality(p_uris) between 1 and 10 and not exists (select 1 from unnest(p_uris) u where not app.url_public(u) or u ~ '#')
$fn$;

create function public.oauth_apps_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_all boolean := app.can('global', 'configure');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', ap.id, 'client_id', ap.client_id, 'name', ap.name, 'kind', ap.kind, 'redirect_uris', to_jsonb(ap.redirect_uris),
                          'allowed_scopes', to_jsonb(ap.allowed_scopes), 'confidential', ap.client_secret_sha256 is not null, 'dynamic', ap.dynamic,
                          'owner', (select coalesce(a.name, a.email) from app.admins a where a.id = ap.owner_id), 'created_at', ap.created_at, 'disabled_at', ap.disabled_at,
                          'grants', (select count(*) from app.oauth_grants g where g.app_id = ap.id and g.revoked_at is null)) order by ap.created_at)
                   from app.oauth_apps ap where v_all or ap.owner_id = v_me
                     or exists (select 1 from app.oauth_grants g where g.app_id = ap.id and g.staff_id = v_me and g.revoked_at is null)), '[]'::jsonb);
end $fn$;

-- register (p_id null) or edit an integration or extension app; a confidential app's secret is returned once.
-- Assistants register themselves (worker_oauth_register)
create function public.oauth_app_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'configure'); v jsonb := coalesce(p_values, '{}'::jsonb); ap app.oauth_apps; v_secret text; v_id uuid; v_client text;
  v_uris text[] := case when jsonb_typeof(v -> 'redirect_uris') = 'array' then array(select jsonb_array_elements_text(v -> 'redirect_uris')) end;
  v_scopes text[] := case when jsonb_typeof(v -> 'allowed_scopes') = 'array' then array(select jsonb_array_elements_text(v -> 'allowed_scopes')) end;
begin
  if p_id is null then
    perform app.require_fresh_mfa(10);
    if coalesce(v ->> 'kind', 'integration') not in ('integration', 'extension') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
    if coalesce(btrim(v ->> 'name'), '') = '' or char_length(btrim(v ->> 'name')) > 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
    if v_uris is null or not app.redirects_ok(v_uris) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'redirect_uris'; end if;
    if v_scopes is null or not app.scopes_ok(v_scopes) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'allowed_scopes'; end if;
    v_client := app.random_token('client_', 24);
    if coalesce((v ->> 'confidential')::boolean, true) then v_secret := app.random_token('cs_', 32); end if;
    insert into app.oauth_apps (client_id, name, kind, owner_id, redirect_uris, client_secret_sha256, allowed_scopes)
    values (v_client, btrim(v ->> 'name'), coalesce(v ->> 'kind', 'integration'), v_me, v_uris,
            case when v_secret is not null then extensions.digest(v_secret, 'sha256') end, v_scopes)
    returning id into v_id;
    perform app.log('oauth_app.saved', 'oauth_app', v_id::text, jsonb_build_object('created', true, 'scopes', to_jsonb(v_scopes)));
    return jsonb_build_object('id', v_id, 'client_id', v_client, 'client_secret', v_secret);
  end if;
  select * into ap from app.oauth_apps where id = p_id for update;
  if not found or ap.kind = 'mcp' then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if v_uris is not null and not app.redirects_ok(v_uris) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'redirect_uris'; end if;
  if v_scopes is not null and not app.scopes_ok(v_scopes) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'allowed_scopes'; end if;
  if (v ? 'name') and (coalesce(btrim(v ->> 'name'), '') = '' or char_length(btrim(v ->> 'name')) > 80) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if coalesce((v ->> 'rotate_secret')::boolean, false) then
    perform app.require_fresh_mfa(10);
    v_secret := app.random_token('cs_', 32);
  end if;
  update app.oauth_apps set name = coalesce(nullif(btrim(v ->> 'name'), ''), name), redirect_uris = coalesce(v_uris, redirect_uris),
    allowed_scopes = coalesce(v_scopes, allowed_scopes),
    client_secret_sha256 = case when v_secret is not null then extensions.digest(v_secret, 'sha256') else client_secret_sha256 end
  where id = p_id;
  -- a narrower app narrows its grants at once
  if v_scopes is not null then
    update app.oauth_grants set revoked_at = now(), revoke_reason = 'revoked', refresh_sha256 = null
    where app_id = p_id and revoked_at is null and not (scopes <@ v_scopes);
  end if;
  perform app.log('oauth_app.saved', 'oauth_app', p_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(v)))));
  return jsonb_build_object('id', p_id, 'client_id', ap.client_id, 'client_secret', v_secret);
end $fn$;

-- disable an app: its grants are revoked at once
create function public.oauth_app_disable(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); n int;
begin
  update app.oauth_apps set disabled_at = now() where id = p_id and disabled_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.oauth_grants set revoked_at = now(), revoke_reason = 'app_removed', refresh_sha256 = null where app_id = p_id and revoked_at is null;
  get diagnostics n = row_count;
  delete from app.oauth_codes where app_id = p_id;
  perform app.log('oauth_app.disabled', 'oauth_app', p_id::text, jsonb_build_object('grants', n));
  if n > 0 then perform app.emit('oauth.revoked', 'oauth_app', p_id, jsonb_build_object('grants', n, 'reason', 'app_removed')); end if;
  return jsonb_build_object('id', p_id, 'grants_revoked', n);
end $fn$;

create function public.oauth_grants_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_sec boolean := app.can('global', 'security');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'app', ap.name, 'kind', ap.kind, 'staff', (select coalesce(a.name, a.email) from app.admins a where a.id = g.staff_id),
                          'scopes', to_jsonb(g.scopes), 'created_at', g.created_at, 'last_used_at', g.last_used_at, 'mine', g.staff_id = v_me) order by g.created_at)
                   from app.oauth_grants g join app.oauth_apps ap on ap.id = g.app_id where g.revoked_at is null and (g.staff_id = v_me or v_sec)), '[]'::jsonb);
end $fn$;

create function public.oauth_grant_revoke(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); g app.oauth_grants;
begin
  select * into g from app.oauth_grants where id = p_id and revoked_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if g.staff_id <> v_me and not app.can('global', 'security') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:security'; end if;
  update app.oauth_grants set revoked_at = now(), revoke_reason = 'revoked', refresh_sha256 = null where id = g.id;
  perform app.log('oauth_grant.revoked', 'oauth_grant', g.id::text, null);
  perform app.emit('oauth.revoked', 'oauth_grant', g.id, jsonb_build_object('reason', 'revoked'));
  return jsonb_build_object('id', g.id);
end $fn$;

-- the consent: a signed-in staff member authorises an app (exact redirect, scopes within the app's, PKCE S256 only, 10 minutes,
-- used once). The code is returned once and stored as a hash
create function public.oauth_authorize(p_client_id text, p_redirect_uri text, p_scopes text[], p_code_challenge text, p_method text default 'S256') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); ap app.oauth_apps; v_code text;
begin
  select * into ap from app.oauth_apps where client_id = p_client_id and disabled_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'client'; end if;
  if ap.kind = 'mcp' and app.setting('mcp_access') <> 'on' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'mcp_off'; end if;
  if p_redirect_uri is null or not (p_redirect_uri = any (ap.redirect_uris)) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'redirect_uri'; end if;
  if p_scopes is null or not app.scopes_ok(p_scopes) or not (p_scopes <@ ap.allowed_scopes) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scopes'; end if;
  if coalesce(p_method, '') <> 'S256' or coalesce(p_code_challenge, '') !~ '^[A-Za-z0-9_-]{43,128}$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'code_challenge';
  end if;
  v_code := app.random_token('oc_', 32);
  insert into app.oauth_codes (code_sha256, app_id, staff_id, scopes, redirect_uri, code_challenge, expires_at)
  values (extensions.digest(v_code, 'sha256'), ap.id, v_me, p_scopes, p_redirect_uri, p_code_challenge, now() + interval '10 minutes');
  perform app.log('oauth.authorized', 'oauth_app', ap.id::text, jsonb_build_object('scopes', to_jsonb(p_scopes)));
  return jsonb_build_object('code', v_code, 'redirect_uri', p_redirect_uri, 'expires_in', 600);
end $fn$;

-- PKCE: base64url(sha256(verifier)) without padding
create function app.pkce_s256(p_verifier text) returns text
  language sql immutable set search_path = ''
as $fn$ select rtrim(translate(encode(extensions.digest(p_verifier, 'sha256'), 'base64'), '+/', '-_'), '=') $fn$;

-- the token endpoint (worker): an authorisation code with its verifier, or a refresh token. Access tokens live one hour, refresh
-- tokens 30 days; both are returned once and rotated on refresh
create function public.worker_oauth_token(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v jsonb := coalesce(p_values, '{}'::jsonb); ap app.oauth_apps; c app.oauth_codes; g app.oauth_grants; v_access text; v_refresh text; v_id uuid;
begin
  select * into ap from app.oauth_apps where client_id = v ->> 'client_id' and disabled_at is null;
  if not found then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'client'; end if;
  if ap.client_secret_sha256 is not null and extensions.digest(coalesce(v ->> 'client_secret', ''), 'sha256') <> ap.client_secret_sha256 then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'client';
  end if;
  if ap.kind = 'mcp' and app.setting('mcp_access') <> 'on' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'mcp_off'; end if;
  v_access := app.random_token('oat_', 32);
  v_refresh := app.random_token('ort_', 32);
  if v ->> 'grant_type' = 'authorization_code' then
    select * into c from app.oauth_codes where code_sha256 = extensions.digest(coalesce(v ->> 'code', ''), 'sha256') for update;
    if not found or c.used_at is not null or c.expires_at < now() or c.app_id <> ap.id or c.redirect_uri is distinct from v ->> 'redirect_uri'
       or app.pkce_s256(coalesce(v ->> 'code_verifier', '')) <> c.code_challenge then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'code';
    end if;
    if not exists (select 1 from app.admins a where a.id = c.staff_id and a.active) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'staff'; end if;
    update app.oauth_codes set used_at = now() where code_sha256 = c.code_sha256;
    insert into app.oauth_grants (app_id, staff_id, scopes, access_sha256, access_expires_at, refresh_sha256, refresh_expires_at)
    values (ap.id, c.staff_id, c.scopes, extensions.digest(v_access, 'sha256'), now() + interval '1 hour', extensions.digest(v_refresh, 'sha256'), now() + interval '30 days')
    returning id into v_id;
    insert into app.audit (actor, staff_id, action, target_type, target_id, ok, detail)
    values ('system', c.staff_id, 'oauth.granted', 'oauth_grant', v_id::text, true, jsonb_build_object('app', ap.id, 'kind', ap.kind));
    perform app.emit('oauth.granted', 'oauth_grant', v_id, jsonb_build_object('app', ap.id, 'kind', ap.kind));
  elsif v ->> 'grant_type' = 'refresh_token' then
    select * into g from app.oauth_grants where refresh_sha256 = extensions.digest(coalesce(v ->> 'refresh_token', ''), 'sha256') for update;
    if not found or g.revoked_at is not null or g.refresh_expires_at < now() or g.app_id <> ap.id
       or not exists (select 1 from app.admins a where a.id = g.staff_id and a.active) then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'refresh_token';
    end if;
    update app.oauth_grants set access_sha256 = extensions.digest(v_access, 'sha256'), access_expires_at = now() + interval '1 hour',
      refresh_sha256 = extensions.digest(v_refresh, 'sha256'), refresh_expires_at = now() + interval '30 days' where id = g.id;
    v_id := g.id;
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'grant_type';
  end if;
  return jsonb_build_object('access_token', v_access, 'token_type', 'bearer', 'expires_in', 3600, 'refresh_token', v_refresh, 'grant_id', v_id);
end $fn$;

-- dynamic client registration (RFC 7591) for assistants only: a public client (PKCE), https redirects, refused while mcp_access is off
create function public.worker_oauth_register(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v jsonb := coalesce(p_values, '{}'::jsonb); v_client text; v_id uuid;
  v_uris text[] := case when jsonb_typeof(v -> 'redirect_uris') = 'array' then array(select jsonb_array_elements_text(v -> 'redirect_uris')) end;
begin
  if app.setting('mcp_access') <> 'on' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'mcp_off'; end if;
  if coalesce(btrim(v ->> 'client_name'), '') = '' or char_length(btrim(v ->> 'client_name')) > 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'client_name'; end if;
  if v_uris is null or not app.redirects_ok(v_uris) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'redirect_uris'; end if;
  v_client := app.random_token('client_', 24);
  insert into app.oauth_apps (client_id, name, kind, redirect_uris, allowed_scopes, dynamic)
  values (v_client, btrim(v ->> 'client_name'), 'mcp', v_uris, array['*'], true) returning id into v_id;
  insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'oauth_app.registered', 'oauth_app', v_id::text, true, jsonb_build_object('kind', 'mcp'));
  return jsonb_build_object('client_id', v_client, 'token_endpoint_auth_method', 'none', 'redirect_uris', to_jsonb(v_uris));
end $fn$;

-- ===========================================================================
-- the AI connector (§1.5; MCP-01..03, UF-22)
-- ===========================================================================
-- the effect of switching mcp_access (the register's hook, §3.6): off revokes every assistant grant and pending code at once.
-- API tokens and other integrations are untouched. Called by setting_set's hook (0043) when the register has one, and by mcp_set.
create function app.mcp_access_effect(p_key text, p_old text, p_new text, p_scope_id text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int;
begin
  if p_key <> 'mcp_access' or p_new <> 'off' then return; end if;
  update app.oauth_grants g set revoked_at = now(), revoke_reason = 'mcp_off', refresh_sha256 = null
  from app.oauth_apps ap where ap.id = g.app_id and ap.kind = 'mcp' and g.revoked_at is null;
  get diagnostics n = row_count;
  delete from app.oauth_codes c using app.oauth_apps ap where ap.id = c.app_id and ap.kind = 'mcp';
  if n > 0 then
    insert into app.audit (actor, staff_id, action, target_type, target_id, ok, detail)
    values (coalesce(app.admin_email(), 'system'), app.me(), 'oauth_grant.revoked', 'setting', 'mcp_access', true, jsonb_build_object('grants', n, 'reason', 'mcp_off'));
    perform app.emit('oauth.revoked', null, null, jsonb_build_object('grants', n, 'reason', 'mcp_off'));
  end if;
end $fn$;

-- the effect is mcp_access's hook: 0043's setting_set calls it before writing the value
update app.settings_registry set hook = 'app.mcp_access_effect' where key = 'mcp_access';

create function public.mcp_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_all boolean := app.can('global', 'configure');
begin
  return jsonb_build_object(
    'access', app.setting('mcp_access'),
    'sync', app.setting('mcp_sync'),
    'connected', (select count(*) from app.oauth_grants g join app.oauth_apps ap on ap.id = g.app_id where ap.kind = 'mcp' and g.revoked_at is null and g.refresh_expires_at > now()),
    'last_index_at', (select max(r.finished_at) from app.job_runs r where r.job_key = 'mcp_index' and r.state = 'succeeded'),
    'assistants', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'app', ap.name, 'staff', (select coalesce(a.name, a.email) from app.admins a where a.id = g.staff_id),
                              'last_used_at', g.last_used_at, 'created_at', g.created_at, 'mine', g.staff_id = v_me) order by g.last_used_at desc nulls last)
                            from app.oauth_grants g join app.oauth_apps ap on ap.id = g.app_id
                            where ap.kind = 'mcp' and g.revoked_at is null and (g.staff_id = v_me or v_all)), '[]'::jsonb),
    'tools', public.api_definition() -> 'tools',
    'can_configure', v_all);
end $fn$;

-- the company switch (MCP-03): off revokes every assistant grant and refuses new ones; the per-call check refuses even a grant
-- the revocation missed
create function public.mcp_set(p_enabled boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); v_old text := app.setting('mcp_access'); v_new text := case when p_enabled then 'on' else 'off' end;
begin
  if p_enabled is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'enabled'; end if;
  perform public.setting_set('mcp_access', v_new);
  perform app.mcp_access_effect('mcp_access', v_old, v_new, '');
  perform app.log('mcp.switched', 'setting', 'mcp_access', jsonb_build_object('from', v_old, 'to', v_new));
  perform app.emit('mcp.switched', null, null, jsonb_build_object('to', v_new));
  return jsonb_build_object('access', v_new);
end $fn$;

create function public.mcp_sync_set(p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'configure');
  if p_on is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'on'; end if;
  perform public.setting_set('mcp_sync', case when p_on then 'on' else 'off' end);
  if not p_on then delete from app.mcp_index; end if;
  return jsonb_build_object('sync', case when p_on then 'on' else 'off' end);
end $fn$;

-- the sync index (every 30 min while mcp_sync is on): title and search text per live, non-sample CRM record, with owner and
-- visibility; nothing from a product table. Off empties it.
create function app.mcp_index_refresh() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities; n int := 0; m int; v_txt text;
begin
  if app.setting('mcp_sync') <> 'on' then
    delete from app.mcp_index;
    return 0;
  end if;
  for e in select * from app.api_entities() x where x.owned loop
    v_txt := (select string_agg(format('coalesce(t.%I::text, '''')', s), ' || '' '' || ') from unnest(e.search) s);
    execute format($q$insert into app.mcp_index (entity, record_id, title, body, owner_id, visibility, updated_at)
                      select %L, t.id, left(coalesce(t.%I::text, ''), 300), to_tsvector('simple', coalesce(t.%I::text, '') || ' ' || %s), t.owner_id, t.visibility, t.updated_at
                      from app.%I t where t.deleted_at is null and not t.is_sample
                      on conflict (entity, record_id) do update set title = excluded.title, body = excluded.body, owner_id = excluded.owner_id,
                        visibility = excluded.visibility, updated_at = excluded.updated_at where app.mcp_index.updated_at < excluded.updated_at$q$,
                   e.key, e.title_col, e.title_col, coalesce(v_txt, ''''''), e.tbl);
    get diagnostics m = row_count; n := n + m;
    execute format('delete from app.mcp_index i where i.entity = %L and not exists (select 1 from app.%I t where t.id = i.record_id and t.deleted_at is null and not t.is_sample)',
                   e.key, e.tbl);
  end loop;
  return n;
end $fn$;

-- search the index as the caller: candidates by text, then each checked against the live record (module, scope, visibility)
create function app.mcp_search(p_q text, p_limit int default 20) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); r record; e app.entities; v_title text; v_out jsonb := '[]'::jsonb; v_n int := 0;
begin
  if app.setting('mcp_sync') <> 'on' then raise exception 'not_available' using errcode = 'invalid_parameter_value', detail = 'mcp_sync'; end if;
  if coalesce(btrim(p_q), '') = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'q'; end if;
  for r in select i.entity, i.record_id from app.mcp_index i where i.body @@ plainto_tsquery('simple', p_q)
           order by ts_rank(i.body, plainto_tsquery('simple', p_q)) desc limit 200 loop
    select * into e from app.entities where key = r.entity;
    continue when (e.module is not null and not app.module_on(e.module)) or not app.can(e.scope, 'see');
    execute format('select t.%I::text from app.%I t where t.id = %L and t.deleted_at is null and %s', e.title_col, e.tbl, r.record_id, app.vis_sql(e)) into v_title;
    continue when v_title is null;
    v_out := v_out || jsonb_build_object('entity', e.key, 'id', r.record_id, 'title', v_title);
    v_n := v_n + 1;
    exit when v_n >= least(greatest(coalesce(p_limit, 20), 1), 50);
  end loop;
  return v_out;
end $fn$;

-- ===========================================================================
-- the integration catalog (§1.4; INT-05..11, AIA-06, D-42)
-- ===========================================================================
-- who is connected to a catalog entry: per-user mailboxes and calendars of its provider, personal tokens for the automation
-- platforms, the staff member who connected a company connector
create function app.integration_connected(p_key text) returns table (staff_id uuid, via text)
  language plpgsql stable security definer set search_path = ''
as $fn$
declare c app.integration_catalog;
begin
  select * into c from app.integration_catalog where key = p_key;
  if not found then return; end if;
  if c.connection = 'per_user' then
    return query select m.owner_id, 'mailbox'::text from app.mailboxes m
                 where m.provider = c.provider and m.deleted_at is null and m.owner_id is not null and m.status not in ('disconnected')
                 union select cc.staff_id, 'calendar'::text from app.calendar_connections cc where cc.provider = c.provider and cc.status = 'connected';
  elsif c.connection = 'api' then
    return query select t.staff_id, 'token'::text from app.api_tokens t where t.revoked_at is null;
  elsif c.connection = 'company' then
    return query select ic.connected_by, 'company'::text from app.integration_connections ic
                 where ic.provider = c.provider and ic.status = 'connected' and ic.connected_by is not null;
  end if;
end $fn$;

-- the catalog with its state for the caller. A search scores each entry by the words of the query (four letters or more) found
-- in its name, description and tags, plus trigram similarity; the best-scoring entries are the matches («best matches»)
create function public.integration_catalog_get(p_q text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_q text := lower(btrim(coalesce(p_q, '')));
begin
  return jsonb_build_object(
    'query', nullif(v_q, ''),
    'items', coalesce((
      with scored as (
        select c.*, case when v_q = '' then 0 else
                 (select count(distinct w) from regexp_split_to_table(v_q, '[^a-z0-9æøå]+') w
                  where char_length(w) >= 4 and (lower(c.terms) ~ ('\m' || w) or w = any (c.tags)))
                 + case when extensions.word_similarity(v_q, lower(c.terms)) > 0.6 then 1 else 0 end end score
        from app.integration_catalog c where c.active)
      select jsonb_agg(jsonb_build_object('key', c.key, 'collection', c.collection, 'provider', c.provider, 'connection', c.connection,
               'access', to_jsonb(c.access), 'tags', to_jsonb(c.tags), 'first_party', c.first_party,
               'installed', exists (select 1 from app.installed_apps i where i.key = c.key and i.removed_at is null),
               'company_connected', case when c.connection = 'company' then app.connected(c.provider) end,
               'mine', exists (select 1 from app.integration_connected(c.key) x where x.staff_id = v_me),
               'users', (select count(distinct x.staff_id) from app.integration_connected(c.key) x),
               'score', c.score,
               'match', c.score > 0 and c.score = (select max(s2.score) from scored s2)) order by c.ord)
      from scored c), '[]'::jsonb));
end $fn$;

create function public.integration_install(p_key text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); c app.integration_catalog;
begin
  select * into c from app.integration_catalog where key = p_key and active;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.installed_apps (key, installed_by, installed_at) values (c.key, v_me, now())
  on conflict (key) do update set installed_by = excluded.installed_by, installed_at = now(), removed_at = null, removed_by = null
  where app.installed_apps.removed_at is not null;
  if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'installed'; end if;
  perform app.log('integration.installed', 'integration', c.key, null);
  perform app.emit('integration.installed', null, null, jsonb_build_object('key', c.key));
  return jsonb_build_object('key', c.key, 'connect_required', case when c.connection = 'company' and not app.connected(c.provider) then c.provider end);
end $fn$;

-- remove (INT-11 «removing an integration revokes its access»). Without p_confirm: the preview of every effect. With
-- p_confirm = the key: the Vault secrets go, the company connection is not_connected, per-user mailboxes and calendars of that
-- provider are disconnected, an extension's apps are disabled with their grants
create function public.integration_remove(p_key text, p_confirm text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'configure'); c app.integration_catalog; v_preview jsonb; v_mb int := 0; v_cal int := 0; v_grants int := 0; r record;
  v_step text;
begin
  select * into c from app.integration_catalog where key = p_key;
  if not found or not exists (select 1 from app.installed_apps i where i.key = p_key and i.removed_at is null) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  v_step := case c.provider when 'slack' then 'slack' when 'teams' then 'teams' when 'accounting' then 'accounting_invoice' end;
  v_preview := jsonb_build_object(
    'users', (select count(distinct x.staff_id) from app.integration_connected(c.key) x),
    'mailboxes', case when c.connection = 'per_user' then (select count(*) from app.mailboxes m where m.provider = c.provider and m.deleted_at is null and m.status <> 'disconnected') else 0 end,
    'calendars', case when c.connection = 'per_user' then (select count(*) from app.calendar_connections cc where cc.provider = c.provider and cc.status = 'connected') else 0 end,
    'company_connection', c.connection = 'company' and app.connected(c.provider),
    'workflows', case when v_step is null then 0 else (select count(*) from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version
                                                       where w.state = 'active' and w.deleted_at is null and jsonb_path_exists(v.flat, '$.*.kind ? (@ == $k)', jsonb_build_object('k', v_step))) end,
    'grants', case when c.connection = 'extension' then (select count(*) from app.oauth_grants g join app.oauth_apps ap on ap.id = g.app_id where ap.kind = 'extension' and g.revoked_at is null) else 0 end);
  if p_confirm is null then return jsonb_build_object('key', c.key, 'preview', v_preview); end if;
  if p_confirm <> c.key then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'confirm'; end if;
  if c.connection = 'company' and c.provider is not null then
    delete from vault.secrets s using app.integration_connections ic where ic.provider = c.provider and s.id = ic.vault_secret_id;
    update app.integration_connections set status = 'not_connected', vault_secret_id = null, connected_by = null, connected_at = null where provider = c.provider;
  elsif c.connection = 'per_user' then
    for r in select id, vault_secret_id from app.mailboxes where provider = c.provider and deleted_at is null and status <> 'disconnected' for update loop
      if r.vault_secret_id is not null then delete from vault.secrets where id = r.vault_secret_id; end if;
      update app.mailboxes set status = 'disconnected', vault_secret_id = null, sync_cursor = null, watch_expires_at = null where id = r.id;
      update app.email_messages set state = 'canceled', failure_code = 'mailbox_disconnected' where mailbox_id = r.id and state in ('scheduled', 'queued', 'awaiting_review');
      v_mb := v_mb + 1;
    end loop;
    delete from vault.secrets s using app.calendar_connections cc where cc.provider = c.provider and s.id = cc.vault_secret_id;
    update app.calendar_connections set status = 'not_connected', vault_secret_id = null where provider = c.provider and status <> 'not_connected';
    get diagnostics v_cal = row_count;
  elsif c.connection = 'extension' then
    update app.oauth_grants g set revoked_at = now(), revoke_reason = 'app_removed', refresh_sha256 = null
    from app.oauth_apps ap where ap.id = g.app_id and ap.kind = 'extension' and g.revoked_at is null;
    get diagnostics v_grants = row_count;
    update app.oauth_apps set disabled_at = now() where kind = 'extension' and disabled_at is null;
  end if;
  update app.installed_apps set removed_at = now(), removed_by = v_me where key = c.key;
  perform app.log('integration.removed', 'integration', c.key, jsonb_build_object('mailboxes', v_mb, 'calendars', v_cal, 'grants', v_grants));
  perform app.emit('integration.removed', null, null, jsonb_build_object('key', c.key));
  return jsonb_build_object('key', c.key, 'removed', true, 'mailboxes', v_mb, 'calendars', v_cal, 'grants', v_grants);
end $fn$;

create function public.integration_users(p_key text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'configure');
  if not exists (select 1 from app.integration_catalog where key = p_key) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('staff_id', x.staff_id, 'name', (select coalesce(a.name, a.email) from app.admins a where a.id = x.staff_id), 'via', x.via)
                                    order by x.via, x.staff_id) from app.integration_connected(p_key) x), '[]'::jsonb);
end $fn$;

-- one staff member's access to an entry, revoked: their mailboxes and calendar of that provider, or their token
create function public.integration_user_revoke(p_key text, p_staff uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); c app.integration_catalog; n int := 0; m int; r record;
begin
  select * into c from app.integration_catalog where key = p_key;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if c.connection = 'per_user' then
    for r in select id, vault_secret_id from app.mailboxes where provider = c.provider and owner_id = p_staff and deleted_at is null and status <> 'disconnected' for update loop
      if r.vault_secret_id is not null then delete from vault.secrets where id = r.vault_secret_id; end if;
      update app.mailboxes set status = 'disconnected', vault_secret_id = null, sync_cursor = null, watch_expires_at = null where id = r.id;
      n := n + 1;
    end loop;
    delete from vault.secrets s using app.calendar_connections cc where cc.staff_id = p_staff and cc.provider = c.provider and s.id = cc.vault_secret_id;
    update app.calendar_connections set status = 'not_connected', vault_secret_id = null where staff_id = p_staff and provider = c.provider and status <> 'not_connected';
    get diagnostics m = row_count; n := n + m;
  elsif c.connection = 'api' then
    update app.api_tokens set revoked_at = now(), revoked_by = v_me, revoke_reason = 'revoked' where staff_id = p_staff and revoked_at is null;
    get diagnostics n = row_count;
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'connection';
  end if;
  if n = 0 then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('integration.user_revoked', 'integration', c.key, jsonb_build_object('staff', p_staff, 'count', n));
  return jsonb_build_object('key', c.key, 'revoked', n);
end $fn$;

-- AIA-06: the context the AI gateway sends with a described need: the catalog and what the company already uses. The need itself
-- is neither stored nor logged; the gateway validates the model's answer with worker_integration_validate
create function public.integration_recommend(p_need text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'ai');
  perform app.require_connected('ai');
  if coalesce(btrim(p_need), '') = '' or char_length(p_need) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'need'; end if;
  perform app.log('catalog.recommendation_requested', 'integration', null, null);
  return jsonb_build_object('basis', 'in_use', 'catalog', coalesce((select jsonb_agg(jsonb_build_object('key', c.key, 'terms', c.terms, 'tags', to_jsonb(c.tags),
            'installed', exists (select 1 from app.installed_apps i where i.key = c.key and i.removed_at is null),
            'connected', case when c.provider is not null then app.connected(c.provider) end) order by c.ord) from app.integration_catalog c where c.active), '[]'::jsonb));
end $fn$;

-- the model's answer, kept only as catalog keys that exist (at most three)
create function public.worker_integration_validate(p_keys jsonb) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select jsonb_agg(z.k order by z.o) from (
                     select y.k, y.o from (select distinct on (x.k) x.k, x.o
                                           from jsonb_array_elements_text(case when jsonb_typeof(p_keys) = 'array' then p_keys else '[]'::jsonb end) with ordinality x(k, o)
                                           where x.k in (select key from app.integration_catalog where active) order by x.k, x.o) y
                     order by y.o limit 3) z), '[]'::jsonb)
$fn$;

-- ===========================================================================
-- applications (§1.1)
-- ===========================================================================
-- the derived health of an installed product (the design's thresholds): unreachable when the last ping failed; degraded when the
-- last 15 minutes show more than 1.5 % errors or p95 over 500 ms, or the last event is older than the push interval (5 min) plus 5
create function app.application_health(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare i app.installations; v_n bigint; v_err numeric; v_p95 numeric; v_last timestamptz; v_status text;
begin
  select * into i from app.installations where product = p_product;
  select count(*), avg(case when ok then 0 else 1 end), percentile_cont(0.95) within group (order by duration_ms) filter (where direction = 'out' and duration_ms is not null)
    into v_n, v_err, v_p95 from app.integration_calls where product = p_product and at > now() - interval '15 minutes';
  select max(received_at) into v_last from app.events_in where product = p_product;
  v_status := case when i.product is null then 'not_installed'
                   when not i.enabled then 'disabled'
                   when i.last_ping_ok is false then 'unreachable'
                   when v_n = 0 and v_last is null then 'no_data'
                   when v_err > 0.015 or v_p95 > 500 or v_last < now() - interval '10 minutes' then 'degraded'
                   else 'operational' end;
  return jsonb_build_object('status', v_status, 'calls_15m', v_n, 'calls_per_min', round(v_n / 15.0, 1), 'p95_ms', round(v_p95), 'error_rate', round(v_err, 4),
                            'last_event_at', v_last, 'last_ping_at', i.last_ping_at, 'last_ping_ok', i.last_ping_ok, 'last_ping_ms', i.last_ping_ms);
end $fn$;

create function public.applications_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  return coalesce((select jsonb_agg(jsonb_build_object('key', p.key, 'name', p.name, 'description', p.description, 'color', p.color, 'ink', p.ink, 'stage', p.stage,
            'installed', i.product is not null, 'region', i.region, 'health', app.application_health(p.key),
            'orgs', (select count(*) from app.account_products ap where ap.product = p.key and ap.status = 'active'),
            'spark', (select jsonb_agg(coalesce(c.n, 0) order by h) from generate_series(date_trunc('hour', now()) - interval '23 hours', date_trunc('hour', now()), interval '1 hour') h
                      left join lateral (select count(*) n from app.integration_calls x where x.product = p.key and x.at >= h and x.at < h + interval '1 hour') c on true))
          order by p.ord, p.key) from app.products p left join app.installations i on i.product = p.key), '[]'::jsonb);
end $fn$;

-- one application: the connection (the real scheme: signed commands and HMAC-verified events), what is synced, the events
-- received in 30 days and the commands Sentral may call. Secrets are reported as present or not, never read
create function public.application_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare p app.products; i app.installations;
begin
  perform app.require('global', 'see');
  select * into p from app.products where key = p_product;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into i from app.installations where product = p_product;
  return jsonb_build_object(
    'key', p.key, 'name', p.name, 'description', p.description, 'stage', p.stage, 'installed', i.product is not null,
    'health', app.application_health(p.key),
    'connection', case when i.product is not null then jsonb_build_object('api_url', i.api_url, 'api_version', i.api_version, 'region', i.region, 'enabled', i.enabled,
        'scopes', to_jsonb(i.scopes), 'token_secret', exists (select 1 from vault.secrets s where s.name = p.key || '_token_secret'),
        'webhook_secret', exists (select 1 from vault.secrets s where s.name = p.key || '_webhook_secret'),
        'event_kinds_30d', (select count(distinct kind) from app.events_in where product = p.key and received_at > now() - interval '30 days'),
        'last_sync_at', (select max(received_at) from app.events_in where product = p.key), 'connected_since', i.created_at,
        'last_ping_at', i.last_ping_at, 'last_ping_ok', i.last_ping_ok, 'last_ping_ms', i.last_ping_ms, 'last_ping_status', i.last_ping_status) end,
    'synced', jsonb_build_object(
        'organizations', (select count(*) from app.account_products ap where ap.product = p.key and ap.status = 'active'),
        'organizations_last', (select max(received_at) from app.events_in where product = p.key and kind like 'org.%'),
        'users', (select count(*) from app.members m where m.product = p.key and m.active),
        'users_last', (select max(received_at) from app.events_in where product = p.key and kind like 'member.%'),
        'subscriptions', (select count(*) from app.subscriptions s where s.product = p.key and app.sub_mrr(s) > 0),
        'subscriptions_last', (select max(received_at) from app.events_in where product = p.key and kind = 'billing.changed'),
        'usage_events_24h', (select count(*) from app.events_in where product = p.key and received_at > now() - interval '1 day'),
        'usage_last', (select max(received_at) from app.events_in where product = p.key and kind in ('usage.daily', 'counts.updated', 'logins.daily')),
        'flags', null),
    'events', coalesce((select jsonb_agg(jsonb_build_object('kind', x.kind, 'count', x.n, 'uses', coalesce(to_jsonb(k.uses), '[]'::jsonb), 'label_key', k.label_key) order by x.n desc, x.kind)
                        from (select kind, count(*) n from app.events_in where product = p.key and received_at > now() - interval '30 days' group by kind) x
                        left join app.product_event_kinds k on k.product = p.key and k.kind = x.kind), '[]'::jsonb),
    'commands', coalesce((select jsonb_agg(jsonb_build_object('command', c.command, 'scope', c.scope, 'used_by', to_jsonb(c.used_by), 'destructive', c.destructive,
                            'allowed', i.product is not null and c.scope = any (i.scopes)) order by c.command)
                          from app.product_commands c where c.product = p.key), '[]'::jsonb));
end $fn$;

-- an intake number bound to one product (0002's app.open_intake opens an unbound one for an operator)
create function app.open_product_intake(p_product text) returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  delete from app.intake_nonces where expires_at < now();
  insert into app.intake_nonces (hash, expires_at, product) values (extensions.digest(v, 'sha256'), now() + interval '15 minutes', p_product);
  return v;
end $fn$;

-- the secrets intake (0002) with the binding: a number opened for a product stores only that product's token and webhook
-- secrets, never overwrites one (forbidden, detail «exists»), and enables the installation once both are there
create or replace function public.store_product_secrets(p_nonce text, p_secrets jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare k text; v text; n int := 0; v_product text;
begin
  delete from app.intake_nonces where hash = extensions.digest(coalesce(p_nonce, ''), 'sha256') and expires_at > now() returning product into v_product;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if jsonb_typeof(p_secrets) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  for k, v in select key, value from jsonb_each_text(p_secrets) loop
    if k !~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$' or char_length(coalesce(v, '')) < 32 or char_length(v) > 500 then
      raise exception 'store_product_secrets: % is not a product secret', k using errcode = 'invalid_parameter_value';
    end if;
    if v_product is not null then
      if k not in (v_product || '_token_secret', v_product || '_webhook_secret') then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'exists';
      end if;
    end if;
    if exists (select 1 from vault.secrets s where s.name = k) then
      perform vault.update_secret((select s.id from vault.secrets s where s.name = k), v);
    else
      perform vault.create_secret(v, k, 'A product''s shared secret (0002): read by the edge functions only.');
    end if;
    n := n + 1;
  end loop;
  if v_product is not null and exists (select 1 from vault.secrets s where s.name = v_product || '_token_secret')
     and exists (select 1 from vault.secrets s where s.name = v_product || '_webhook_secret') then
    update app.installations set enabled = true, updated_at = now() where product = v_product and not enabled;
  end if;
  return jsonb_build_object('ok', true, 'stored', n);
end $fn$;

-- connect a new application (owner, fresh second factor). No secret passes through a person: the answer is an intake number
-- bound to the new product key, which the product's operator uses to post its secrets to secret-intake
create function public.application_connect(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_owner(); v jsonb := coalesce(p_values, '{}'::jsonb); v_key text := lower(btrim(v ->> 'key'));
  v_scopes text[] := case when jsonb_typeof(v -> 'scopes') = 'array' then array(select jsonb_array_elements_text(v -> 'scopes')) else '{}' end;
begin
  perform app.require_fresh_mfa(10);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key'; end if;
  if exists (select 1 from app.products where key = v_key) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key_taken'; end if;
  if coalesce(btrim(v ->> 'name'), '') = '' or char_length(btrim(v ->> 'name')) > 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if coalesce(v ->> 'api_url', '') !~ '^https://[^\s/]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'api_url'; end if;
  if char_length(coalesce(v ->> 'public_key', '')) not between 20 and 2000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'public_key'; end if;
  if not (v_scopes <@ array['orgs:read', 'orgs:write', 'billing:read', 'billing:write', 'translations:read', 'translations:write', 'modules:read',
                            'modules:write', 'legal:read', 'legal:write', 'settings:read', 'settings:write']) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scopes';
  end if;
  if (v ? 'region') and char_length(coalesce(btrim(v ->> 'region'), '')) not between 1 and 60 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'region'; end if;
  if coalesce(v ->> 'stage', 'ga') not in ('ga', 'beta') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage'; end if;
  if (v ? 'description') and char_length(coalesce(v ->> 'description', '')) > 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'description'; end if;
  insert into app.products (key, name, description, stage, ord)
  values (v_key, btrim(v ->> 'name'), nullif(btrim(v ->> 'description'), ''), coalesce(v ->> 'stage', 'ga'), (select coalesce(max(ord), 0) + 10 from app.products));
  insert into app.installations (product, api_url, public_key, enabled, region, scopes, connected_by)
  values (v_key, v ->> 'api_url', v ->> 'public_key', false, nullif(btrim(v ->> 'region'), ''), v_scopes, v_me);
  perform app.log('application.connected', 'product', v_key, jsonb_build_object('scopes', to_jsonb(v_scopes)));
  return jsonb_build_object('product', v_key, 'intake_code', app.open_product_intake(v_key), 'expires_in', 900);
end $fn$;

create function public.application_update(p_product text, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_owner(); v jsonb := coalesce(p_values, '{}'::jsonb);
  v_scopes text[] := case when jsonb_typeof(v -> 'scopes') = 'array' then array(select jsonb_array_elements_text(v -> 'scopes')) end;
begin
  if not exists (select 1 from app.products where key = p_product) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if (v ? 'name') and (coalesce(btrim(v ->> 'name'), '') = '' or char_length(btrim(v ->> 'name')) > 80) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if (v ? 'stage') and v ->> 'stage' not in ('ga', 'beta') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage'; end if;
  if (v ? 'api_url') and coalesce(v ->> 'api_url', '') !~ '^https://[^\s/]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'api_url'; end if;
  if v_scopes is not null and not (v_scopes <@ array['orgs:read', 'orgs:write', 'billing:read', 'billing:write', 'translations:read', 'translations:write',
                                                     'modules:read', 'modules:write', 'legal:read', 'legal:write', 'settings:read', 'settings:write']) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scopes';
  end if;
  update app.products set name = coalesce(nullif(btrim(v ->> 'name'), ''), name), stage = coalesce(v ->> 'stage', stage),
    description = case when v ? 'description' then nullif(btrim(v ->> 'description'), '') else description end where key = p_product;
  update app.installations set api_url = coalesce(v ->> 'api_url', api_url), region = case when v ? 'region' then nullif(btrim(v ->> 'region'), '') else region end,
    scopes = coalesce(v_scopes, scopes), enabled = coalesce((v ->> 'enabled')::boolean, enabled), updated_at = now() where product = p_product;
  perform app.log('application.updated', 'product', p_product, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(v)))));
  return jsonb_build_object('product', p_product);
end $fn$;

-- the product-command and orgpuls-events functions report each call (kinds, times, codes)
create function public.worker_integration_call(p_rows jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r jsonb; n int := 0;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if not exists (select 1 from app.products where key = r ->> 'product') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
    insert into app.integration_calls (product, direction, kind, at, duration_ms, ok, status, error_code)
    values (r ->> 'product', r ->> 'direction', r ->> 'kind', least(coalesce((r ->> 'at')::timestamptz, now()), now()), (r ->> 'duration_ms')::int,
            coalesce((r ->> 'ok')::boolean, false), (r ->> 'status')::int, r ->> 'error_code');
    n := n + 1;
  end loop;
  return jsonb_build_object('rows', n);
end $fn$;

-- «Test connection»: product-command sends a harmless read and reports it here (latency, status, the product's version when its reply has one)
create function public.worker_application_ping(p_product text, p_ok boolean, p_ms int, p_status int, p_version text default null, p_kind text default 'orgs.list')
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.installations set last_ping_at = now(), last_ping_ok = coalesce(p_ok, false), last_ping_ms = greatest(p_ms, 0), last_ping_status = p_status,
    api_version = case when p_version ~ '^[A-Za-z0-9._+-]{1,40}$' then p_version else api_version end
  where product = p_product;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.integration_calls (product, direction, kind, duration_ms, ok, status, error_code)
  values (p_product, 'out', coalesce(p_kind, 'orgs.list'), greatest(p_ms, 0), coalesce(p_ok, false), p_status, case when not coalesce(p_ok, false) then 'ping_failed' end);
  return app.application_health(p_product);
end $fn$;

-- ===========================================================================
-- feature flags, status banner, content (§1.7, §1.8)
-- ===========================================================================
create function public.flags_get(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  return jsonb_build_object(
    'modules', coalesce((select jsonb_agg(jsonb_build_object('key', m.key, 'enabled', m.enabled, 'updated_at', m.updated_at) order by m.ord) from app.modules m), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(jsonb_build_object('key', p.key, 'name', p.name,
                   'flags_command', exists (select 1 from app.product_commands c where c.product = p.key and c.command = 'modules.list'),
                   'pilots_command', exists (select 1 from app.product_commands c where c.product = p.key and c.command = 'locales.pilots'),
                   'set_command', exists (select 1 from app.product_commands c where c.product = p.key and c.command = 'modules.set_status'),
                   'active_tenants', (select count(*) from app.account_products ap where ap.product = p.key and ap.status = 'active')) order by p.ord)
                 from app.products p join app.installations i on i.product = p.key where p_product is null or p.key = p_product), '[]'::jsonb));
end $fn$;

create function public.status_notice_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  if not exists (select 1 from app.products where key = p_product) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object(
    'notice_command', exists (select 1 from app.product_commands c where c.product = p_product and c.command = 'settings.set_notice'),
    'maintenance_command', exists (select 1 from app.product_commands c where c.product = p_product and c.command = 'settings.set_maintenance'),
    'current', (select jsonb_build_object('id', n.id, 'text', n.text, 'maintenance', n.maintenance, 'problem_ticket_id', n.problem_ticket_id,
                         'problem_number', (select t.number from app.tickets t where t.id = n.problem_ticket_id), 'set_at', n.set_at, 'pushed_at', n.pushed_at, 'push_error', n.push_error)
                from app.status_notices n where n.product = p_product and n.cleared_at is null and n.text is not null order by n.set_at desc limit 1),
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'text', n.text, 'maintenance', n.maintenance, 'set_at', n.set_at, 'cleared_at', n.cleared_at,
                           'set_by', (select coalesce(a.name, a.email) from app.admins a where a.id = n.set_by)) order by n.set_at desc)
                         from (select * from app.status_notices where product = p_product order by set_at desc limit 20) n), '[]'::jsonb));
end $fn$;

-- set or clear (p_text null) the product's banner through settings.set_notice; maintenance mode is a product command that does
-- not exist yet (D-40): refused as not_available until product_commands has settings.set_maintenance, then owner, fresh second
-- factor and the product key typed as confirmation
create function public.status_notice_set(p_product text, p_text text, p_problem uuid default null, p_maintenance boolean default false, p_confirm text default null)
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); v_id uuid;
begin
  if not exists (select 1 from app.installations where product = p_product) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not exists (select 1 from app.product_commands c where c.product = p_product and c.command = 'settings.set_notice') then
    raise exception 'not_available' using errcode = 'invalid_parameter_value', detail = 'settings.set_notice';
  end if;
  if coalesce(p_maintenance, false) then
    if not exists (select 1 from app.product_commands c where c.product = p_product and c.command = 'settings.set_maintenance') then
      raise exception 'not_available' using errcode = 'invalid_parameter_value', detail = 'maintenance';
    end if;
    perform app.require_owner();
    perform app.require_fresh_mfa(10);
    if p_confirm is distinct from p_product then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'confirm'; end if;
  end if;
  if p_text is not null and char_length(btrim(p_text)) not between 1 and 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'text'; end if;
  if p_problem is not null and not exists (select 1 from app.tickets t where t.id = p_problem and t.type = 'problem' and t.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'problem';
  end if;
  update app.status_notices set cleared_at = now() where product = p_product and cleared_at is null;
  insert into app.status_notices (product, text, maintenance, problem_ticket_id, set_by)
  values (p_product, nullif(btrim(p_text), ''), coalesce(p_maintenance, false), p_problem, v_me) returning id into v_id;
  perform pgmq.send('jobs', jsonb_build_object('job', 'product_command', 'product', p_product, 'command', 'settings.set_notice', 'notice_id', v_id));
  perform app.log('status_notice.set', 'product', p_product, jsonb_build_object('notice', v_id, 'cleared', p_text is null, 'maintenance', coalesce(p_maintenance, false)));
  perform app.emit('status_notice.changed', null, null, jsonb_build_object('product', p_product, 'notice', v_id));
  return jsonb_build_object('id', v_id);
end $fn$;

-- the worker that ran settings.set_notice reports back
create function public.worker_status_notice_pushed(p_id uuid, p_ok boolean, p_error text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.status_notices set pushed_at = case when p_ok then now() end, push_error = case when p_ok then null else coalesce(p_error, 'failed') end where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('id', p_id);
end $fn$;

-- a notice linked to a problem ticket is cleared when the problem is resolved (every 5 min)
create function app.status_notices_due() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; v_id uuid; n int := 0;
begin
  for r in select n2.id, n2.product from app.status_notices n2 join app.tickets t on t.id = n2.problem_ticket_id
           where n2.cleared_at is null and n2.text is not null and t.problem_status = 'resolved' for update of n2 skip locked loop
    update app.status_notices set cleared_at = now() where id = r.id;
    insert into app.status_notices (product, text) values (r.product, null) returning id into v_id;
    perform pgmq.send('jobs', jsonb_build_object('job', 'product_command', 'product', r.product, 'command', 'settings.set_notice', 'notice_id', v_id));
    perform app.emit('status_notice.changed', null, null, jsonb_build_object('product', r.product, 'notice', v_id, 'reason', 'problem_resolved'));
    n := n + 1;
  end loop;
  return n;
end $fn$;

-- the Content tab: what the platform holds (help texts, macros) and which product commands back each card (D-23)
create function public.content_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'see');
  if not exists (select 1 from app.products where key = p_product) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object(
    'help', jsonb_build_object('articles', (select count(*) from app.help_articles h where not h.is_sample),
                               'published', (select count(*) from app.help_articles h where not h.is_sample and h.published_at is not null),
                               'last_change', (select max(h.updated_at) from app.help_articles h where not h.is_sample),
                               'macros', (select count(*) from app.ticket_macros m where m.active and not m.is_sample)),
    'cards', jsonb_build_object(
      'question_set', jsonb_build_object('command', null), 'pulse_templates', jsonb_build_object('command', null), 'tiltak', jsonb_build_object('command', null),
      'legal', jsonb_build_object('command', case when exists (select 1 from app.product_commands c where c.product = p_product and c.command = 'legal.reviews') then 'legal.reviews' end),
      'templates', jsonb_build_object('command', case when exists (select 1 from app.product_commands c where c.product = p_product and c.command = 'translations.list') then 'translations.list' end),
      'modules', jsonb_build_object('command', case when exists (select 1 from app.product_commands c where c.product = p_product and c.command = 'modules.list') then 'modules.list' end)),
    'draft_command', false, 'rollback_command', false);
end $fn$;

-- ===========================================================================
-- the job monitor (§1.6)
-- ===========================================================================
create function public.jobs_get(p_filter jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare f jsonb := coalesce(p_filter, '{}'::jsonb); v_cron_running bigint;
begin
  perform app.require('global', 'see');
  select count(*) into v_cron_running from cron.job_run_details d where d.status = 'running' and d.command like 'select app.run_job(%' and d.start_time > now() - interval '1 day';
  return jsonb_build_object(
    'stats', jsonb_build_object(
      'queued', coalesce((select m.queue_length from pgmq.metrics('jobs') m), 0) + (select count(*) from app.job_runs where state = 'queued'),
      'running', (select count(*) from app.job_runs where state = 'running') + v_cron_running,
      'failed_24h', (select count(*) from app.job_runs where state = 'failed' and queued_at > now() - interval '24 hours'),
      'succeeded_24h', (select count(*) from app.job_runs where state = 'succeeded' and queued_at > now() - interval '24 hours')),
    'jobs', coalesce((select jsonb_agg(jsonb_build_object('key', d.key, 'label_key', d.label_key, 'product', d.product, 'schedule', d.schedule, 'source', d.source,
                        'quiet', d.quiet, 'last_run_at', d.last_run_at, 'last_state', d.last_state,
                        'last_run', (select jsonb_build_object('id', r.id, 'state', r.state, 'at', coalesce(r.finished_at, r.queued_at), 'info', r.info, 'error', r.error)
                                     from app.job_runs r where r.job_key = d.key order by r.id desc limit 1)) order by d.source, d.key)
                      from app.job_defs d), '[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'job', r.job_key, 'state', r.state, 'queued_at', r.queued_at, 'finished_at', r.finished_at,
                        'info', r.info, 'error', r.error, 'retry_of', r.retry_of) order by r.id desc)
                      from (select * from app.job_runs x where (f ->> 'state' is null or x.state = f ->> 'state') and (f ->> 'job' is null or x.job_key = f ->> 'job')
                            order by x.id desc limit 50) r), '[]'::jsonb));
end $fn$;

-- retry a failed run: a scheduled job runs again now (its retry function when it has one); a queue job is queued again; a
-- product's job needs its jobs.retry command (D-40)
create function public.job_retry(p_run bigint) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); r app.job_runs; d app.job_defs; v_id bigint;
begin
  select * into r from app.job_runs where id = p_run;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'failed' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  select * into d from app.job_defs where key = r.job_key;
  if d.source = 'product' then raise exception 'not_available' using errcode = 'invalid_parameter_value', detail = 'jobs.retry'; end if;
  perform app.log('job.retried', 'job', r.job_key, jsonb_build_object('run', r.id));
  if d.source = 'cron' then
    if d.retry_fn is not null then
      execute format('select %s()', d.retry_fn);
      insert into app.job_runs (job_key, state, started_at, finished_at, retry_of, requested_by) values (d.key, 'succeeded', now(), now(), r.id, v_me) returning id into v_id;
    else
      v_id := app.run_job(d.key, r.id, v_me);
    end if;
  else
    insert into app.job_runs (job_key, state, retry_of, requested_by) values (d.key, 'queued', r.id, v_me) returning id into v_id;
    perform pgmq.send('jobs', jsonb_build_object('job', d.key, 'run', v_id, 'retry_of', r.id));
  end if;
  return jsonb_build_object('run', v_id, 'state', (select state from app.job_runs where id = v_id));
end $fn$;

-- an edge worker or a product reports a run (queue jobs; product jobs as counts only, D-19)
create function public.worker_job_run(p_key text, p_state text, p_info jsonb default '{}'::jsonb, p_error text default null, p_run bigint default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d app.job_defs; v_id bigint := p_run; v_info jsonb;
begin
  select * into d from app.job_defs where key = p_key;
  if not found or d.source = 'cron' then raise exception 'not_found' using errcode = 'no_data_found', detail = 'job'; end if;
  if p_state not in ('queued', 'running', 'succeeded', 'failed') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  v_info := coalesce((select jsonb_object_agg(k, v) from jsonb_each(case when jsonb_typeof(p_info) = 'object' then p_info else '{}'::jsonb end) x(k, v)
                      where jsonb_typeof(v) in ('number', 'boolean')), '{}'::jsonb);
  if v_id is null then
    insert into app.job_runs (job_key, state, started_at, finished_at, info, error)
    values (p_key, p_state, case when p_state <> 'queued' then now() end, case when p_state in ('succeeded', 'failed') then now() end, v_info, left(p_error, 300))
    returning id into v_id;
  else
    update app.job_runs set state = p_state, started_at = coalesce(started_at, case when p_state <> 'queued' then now() end),
      finished_at = case when p_state in ('succeeded', 'failed') then now() end, info = v_info, error = left(p_error, 300)
    where id = v_id and job_key = p_key;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  if p_state in ('succeeded', 'failed') then
    if p_state = 'failed' and d.last_state is distinct from 'failed' then perform app.job_failed(v_id); end if;
    update app.job_defs set last_run_at = now(), last_state = p_state where key = p_key;
  end if;
  return jsonb_build_object('run', v_id);
end $fn$;

-- ===========================================================================
-- mobile (§7; MOB-01..08, AIA-07, UF-21, SF-31, SF-44, D-38): the same rights as the web plus the mobile module.
-- Device coordinates are request parameters only: never stored, logged or sent anywhere (§3.12.7)
-- ===========================================================================
create function app.mobile_require() returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid := app.require('deals', 'see');
begin
  perform app.require_module('mobile');
  return v;
end $fn$;

-- great-circle distance in km
create function app.km(p_lat1 numeric, p_lng1 numeric, p_lat2 numeric, p_lng2 numeric) returns numeric
  language sql immutable set search_path = ''
as $fn$
  select round((2 * 6371 * asin(least(1, sqrt(power(sin(radians((p_lat2 - p_lat1)::float8) / 2), 2)
                  + cos(radians(p_lat1::float8)) * cos(radians(p_lat2::float8)) * power(sin(radians((p_lng2 - p_lng1)::float8) / 2), 2)))))::numeric, 2)
$fn$;

create function app.coords_ok(p_lat numeric, p_lng numeric) returns boolean
  language sql immutable set search_path = ''
as $fn$ select p_lat is not null and p_lng is not null and p_lat between -90 and 90 and p_lng between -180 and 180 $fn$;

-- the organisations within a radius of a point that the caller may see, with their distance (any of their geocoded addresses)
create function app.orgs_near(p_lat numeric, p_lng numeric, p_km numeric) returns table (organization_id uuid, km numeric)
  language sql stable security definer set search_path = ''
as $fn$
  select o.id, min(app.km(p_lat, p_lng, g.lat, g.lng))
  from app.record_geo g join app.organizations o on o.id = g.record_id and g.entity = 'organization'
  where g.lat between p_lat - p_km / 111.0 and p_lat + p_km / 111.0
    and g.lng between p_lng - p_km / greatest(111.0 * cos(radians(p_lat::float8)), 1) and p_lng + p_km / greatest(111.0 * cos(radians(p_lat::float8)), 1)
    and o.deleted_at is null and app.visible(o.owner_id, o.visibility)
    and (not o.is_sample or coalesce((select a.sandbox from app.admins a where a.id = app.me()), false))
  group by o.id
  having min(app.km(p_lat, p_lng, g.lat, g.lng)) <= p_km
$fn$;

-- Focus (MOB-02): the counts use the web lists' own filters (activities_get «overdue», deal_list open and past close), owner = me
create function public.mobile_focus(p_lat numeric default null, p_lng numeric default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.mobile_require(); v_tz text := (select time_zone from app.admins where id = v_me);
  v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_today date := (now() at time zone (select time_zone from app.admins where id = app.me()))::date;
  v_geo boolean := app.coords_ok(p_lat, p_lng); v_goal app.goals;
begin
  select * into v_goal from app.goals g where g.kind = 'deals_won' and g.assignee_kind = 'staff' and g.assignee_id = v_me and g.deleted_at is null
    and g.starts_on <= v_today and (g.ends_on is null or g.ends_on >= v_today) and (v_sandbox or not g.is_sample) order by g.created_at desc limit 1;
  return jsonb_build_object(
    'hour', extract(hour from now() at time zone v_tz)::int,
    'name', (select coalesce(a.name, a.email) from app.admins a where a.id = v_me),
    'overdue_activities', (select count(*) from app.activities a where a.deleted_at is null and app.visible(a.owner_id, a.visibility) and (v_sandbox or not a.is_sample)
                             and a.owner_id = v_me and not a.done and a.starts_at < now()),
    'deals_past_close', case when app.module_on('deals') then (select count(*) from app.deals d where d.deleted_at is null and d.archived_at is null
                             and app.visible(d.owner_id, d.visibility) and (v_sandbox or not d.is_sample) and d.owner_id = v_me and d.status = 'open'
                             and d.expected_close_date < v_today) end,
    'today', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'subject', a.subject, 'starts_at', a.starts_at, 'done', a.done,
                          'type', (select t.key from app.activity_types t where t.id = a.type_id),
                          'organization', (select o.name from app.organizations o where o.id = a.organization_id),
                          'deal', (select d.title from app.deals d where d.id = a.deal_id),
                          'km', case when v_geo and a.organization_id is not null then (select min(app.km(p_lat, p_lng, g.lat, g.lng)) from app.record_geo g
                                                                                         where g.entity = 'organization' and g.record_id = a.organization_id) end)
                        order by a.starts_at)
                      from app.activities a where a.deleted_at is null and app.visible(a.owner_id, a.visibility) and (v_sandbox or not a.is_sample)
                        and a.owner_id = v_me and (a.starts_at at time zone v_tz)::date = v_today), '[]'::jsonb),
    'unread_threads', (select count(*) from app.email_threads t join app.mailboxes m on m.id = t.mailbox_id
                       where t.archived_at is null and t.deleted_at is null and m.deleted_at is null
                         and (m.owner_id = v_me or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = v_me))
                         and app.thread_unread(t.id, v_me)),
    'nearby_10km', case when v_geo then (select count(*) from app.orgs_near(p_lat, p_lng, 10)) end,
    'closing_this_week', case when app.module_on('deals') then (select jsonb_build_object('count', count(*), 'value_nok', coalesce(sum(d.value) filter (where d.currency = 'NOK'), 0),
                             'excluded_currency', count(*) filter (where d.currency <> 'NOK'))
                           from app.deals d where d.deleted_at is null and d.archived_at is null and app.visible(d.owner_id, d.visibility) and (v_sandbox or not d.is_sample)
                             and d.owner_id = v_me and d.status = 'open'
                             and d.expected_close_date between date_trunc('week', v_today)::date and date_trunc('week', v_today)::date + 6) end,
    'month', case when app.module_on('deals') then jsonb_build_object(
               'won_value_nok', (select coalesce(sum(d.value), 0) from app.deals d where d.deleted_at is null and d.owner_id = v_me and d.status = 'won' and d.currency = 'NOK'
                                   and (v_sandbox or not d.is_sample) and (d.won_at at time zone v_tz)::date >= date_trunc('month', v_today)::date),
               'new_deals', (select count(*) from app.deals d where d.deleted_at is null and d.owner_id = v_me and (v_sandbox or not d.is_sample)
                               and (d.created_at at time zone v_tz)::date >= date_trunc('month', v_today)::date),
               'goal', case when v_goal.id is not null then jsonb_build_object('id', v_goal.id, 'name', v_goal.name, 'progress', app.goal_progress(v_goal),
                                                                               'target_value', v_goal.target_value, 'target_count', v_goal.target_count) end) end,
    'tasks_due_today', case when app.module_on('projects') and app.can('projects', 'see') then
                         (select count(*) from app.project_items i join app.projects p on p.id = i.project_id
                          where i.deleted_at is null and p.deleted_at is null and i.kind = 'task' and not i.done and i.due_on = v_today
                            and (v_sandbox or not p.is_sample)
                            and (i.owner_id = v_me or exists (select 1 from app.project_item_assignees x where x.item_id = i.id and x.staff_id = v_me))) end,
    'chats_waiting', case when app.module_on('leadgen') then (select count(*) from app.chat_conversations c where c.state = 'queued' and c.is_sample = v_sandbox) end,
    'contact_rule', app.setting('contact_rule'));
end $fn$;

-- Nearby (MOB-03): organisations near the device (and people through them), with the open deal, health and last visit
create function public.nearby(p_lat numeric, p_lng numeric, p_radius_km numeric default 10, p_entities text[] default array['organization'], p_filter jsonb default '{}'::jsonb)
  returns jsonb language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.mobile_require(); f jsonb := coalesce(p_filter, '{}'::jsonb); v_out jsonb;
begin
  if not app.coords_ok(p_lat, p_lng) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'coordinates'; end if;
  if p_radius_km is null or p_radius_km <= 0 or p_radius_km > 100 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'radius_km'; end if;
  if p_entities is null or not (p_entities <@ array['organization', 'person']) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entities'; end if;
  with near as (select n.organization_id, n.km from app.orgs_near(p_lat, p_lng, p_radius_km) n),
  rows as (
    select n.km, o.id, o.name, o.city, o.account_id,
      (select jsonb_build_object('id', d.id, 'title', d.title, 'stage', (select s.name from app.stages s where s.id = d.stage_id))
       from app.deals d where d.organization_id = o.id and d.deleted_at is null and d.archived_at is null and d.status = 'open' and app.visible(d.owner_id, d.visibility)
       order by d.last_activity_at desc nulls last, d.updated_at desc limit 1) deal,
      (select h.score from app.health_scores h join app.account_products ap on ap.product = h.product and ap.tenant_id = h.tenant_id
       where ap.account_id = o.account_id order by h.day desc limit 1) health,
      exists (select 1 from app.account_products ap where ap.account_id = o.account_id and ap.status = 'active') customer,
      (select max(a.done_at) from app.activities a join app.activity_types t on t.id = a.type_id
       where a.organization_id = o.id and a.done and a.deleted_at is null and t.key in ('visit', 'meeting')) last_visit_at
    from near n join app.organizations o on o.id = n.organization_id)
  select coalesce(jsonb_agg(x.j order by x.km), '[]'::jsonb) into v_out from (
    select r.km, jsonb_build_object('entity', 'organization', 'id', r.id, 'title', r.name, 'city', r.city, 'km', r.km, 'deal', r.deal, 'health', r.health,
                                    'customer', r.customer, 'last_visit_at', r.last_visit_at) j
    from rows r where 'organization' = any (p_entities)
      and (not coalesce((f ->> 'customers_only')::boolean, false) or r.customer)
      and (f ->> 'no_visit_days' is null or r.last_visit_at is null or r.last_visit_at < now() - make_interval(days => (f ->> 'no_visit_days')::int))
    union all
    select r.km, jsonb_build_object('entity', 'person', 'id', p.id, 'title', p.name, 'subtitle', p.title, 'organization', r.name, 'organization_id', r.id, 'km', r.km)
    from rows r join app.people p on p.organization_id = r.id and p.deleted_at is null and app.visible(p.owner_id, p.visibility)
    where 'person' = any (p_entities) and (not p.is_sample or coalesce((select a.sandbox from app.admins a where a.id = v_me), false))
    order by 1 limit 200) x;
  perform app.log('record.listed', 'organization', null, jsonb_build_object('count', jsonb_array_length(v_out), 'view', 'nearby'));
  return v_out;
end $fn$;

-- Check in (MOB-03): a done «visit» on the record, no coordinates stored
create function public.checkin(p_entity text, p_id uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.mobile_require(); e app.entities; v_title text; v jsonb; r jsonb; v_org uuid; v_person uuid; v_deal uuid; v_lead uuid;
begin
  if p_entity not in ('organization', 'person', 'deal', 'lead') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
  e := app.entity(p_entity);
  execute format('select t.%I::text from app.%I t where t.id = %L and t.deleted_at is null and %s', e.title_col, e.tbl, p_id, app.vis_sql(e)) into v_title;
  if v_title is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_note is not null and char_length(p_note) > 10000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'note'; end if;
  case p_entity
    when 'organization' then v_org := p_id;
    when 'person' then v_person := p_id; v_org := (select organization_id from app.people where id = p_id);
    when 'deal' then v_deal := p_id; select organization_id, person_id into v_org, v_person from app.deals where id = p_id;
    when 'lead' then v_lead := p_id; select organization_id, person_id into v_org, v_person from app.leads where id = p_id;
  end case;
  v := jsonb_strip_nulls(jsonb_build_object('type_id', (select id from app.activity_types where key = 'visit'), 'subject', left(v_title, 200), 'starts_at', now(),
                                            'duration_min', 0, 'note', nullif(btrim(p_note), ''), 'organization_id', v_org, 'person_id', v_person, 'deal_id', v_deal, 'lead_id', v_lead));
  r := public.rec_save('activity', null, v, null, null, 'mobile');
  perform public.activity_done((r ->> 'id')::uuid, true);
  return jsonb_build_object('activity_id', r ->> 'id');
end $fn$;

-- push devices (MOB-07): the endpoint is write-only; registering the same endpoint again moves it to the caller
create function public.push_device_register(p_endpoint text, p_p256dh text, p_auth text, p_label text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_id uuid;
begin
  perform app.require_module('mobile');
  if p_endpoint is null or not app.url_public(p_endpoint) or char_length(p_endpoint) > 1000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'endpoint'; end if;
  if coalesce(p_p256dh, '') !~ '^[A-Za-z0-9_=-]{40,200}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'p256dh'; end if;
  if coalesce(p_auth, '') !~ '^[A-Za-z0-9_=-]{16,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'auth'; end if;
  if p_label is not null and char_length(p_label) > 120 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'label'; end if;
  insert into app.push_devices (staff_id, endpoint, p256dh, auth_secret, label)
  values (v_me, p_endpoint, p_p256dh, p_auth, nullif(btrim(p_label), ''))
  on conflict (endpoint) do update set staff_id = excluded.staff_id, p256dh = excluded.p256dh, auth_secret = excluded.auth_secret, label = excluded.label,
    revoked_at = null, failures = 0, created_at = now()
  returning id into v_id;
  perform app.log('push_device.registered', 'push_device', v_id::text, null);
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.push_device_revoke(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  update app.push_devices set revoked_at = now() where id = p_id and staff_id = v_me and revoked_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('push_device.revoked', 'push_device', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

create function public.push_devices_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return jsonb_build_object(
    'push_ready', app.push_ready(), 'setting', app.setting('push_notifications'), 'module', app.module_on('mobile'),
    'devices', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'platform', d.platform, 'label', d.label, 'created_at', d.created_at,
                           'last_used_at', d.last_used_at, 'failures', d.failures) order by d.created_at desc)
                         from app.push_devices d where d.staff_id = v_me and d.revoked_at is null), '[]'::jsonb));
end $fn$;

create function public.notification_prefs_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('kind', k, 'channels', coalesce((select to_jsonb(p.channels) from app.notification_prefs p where p.staff_id = v_me and p.kind = k),
                                                                                     '["in_app","push"]'::jsonb)) order by o)
                   from unnest(array['assignment', 'mention', 'chat_request', 'security', 'system']) with ordinality x(k, o)), '[]'::jsonb);
end $fn$;

-- per kind: in-app always (the notification is the record), push on or off. Email waits for the provider (D-07)
create function public.notification_prefs_set(p_kind text, p_channels text[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  if p_kind not in ('assignment', 'mention', 'chat_request', 'security', 'system') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if p_channels is null or not (p_channels <@ array['in_app', 'push']) or not ('in_app' = any (p_channels)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'channels';
  end if;
  insert into app.notification_prefs (staff_id, kind, channels) values (v_me, p_kind, array(select distinct c from unnest(p_channels) c order by c))
  on conflict (staff_id, kind) do update set channels = excluded.channels;
  perform app.log('notification_prefs.saved', 'staff', v_me::text, jsonb_build_object('kind', p_kind, 'channels', to_jsonb(p_channels)));
  return jsonb_build_object('kind', p_kind, 'channels', to_jsonb(p_channels));
end $fn$;

-- the push worker: queued deliveries with the device's endpoint and keys and the notification's key and parameters
create function public.worker_push_claim(p_limit int default 50) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_out jsonb := '[]'::jsonb; r record;
begin
  if not app.push_ready() then return v_out; end if;
  for r in select pd.notification_id, pd.device_id, d.endpoint, d.p256dh, d.auth_secret, n.kind, n.key, n.params, n.route
           from app.push_deliveries pd join app.push_devices d on d.id = pd.device_id join app.notifications n on n.id = pd.notification_id
           where pd.state = 'queued' and d.revoked_at is null and (pd.claimed_at is null or pd.claimed_at < now() - interval '2 minutes')
           order by pd.queued_at limit least(greatest(coalesce(p_limit, 50), 1), 200) for update of pd skip locked loop
    update app.push_deliveries set claimed_at = now() where notification_id = r.notification_id and device_id = r.device_id;
    v_out := v_out || jsonb_build_object('notification_id', r.notification_id, 'device_id', r.device_id, 'endpoint', r.endpoint, 'p256dh', r.p256dh, 'auth', r.auth_secret,
                                         'payload', jsonb_build_object('kind', r.kind, 'key', r.key, 'params', r.params, 'route', r.route));
  end loop;
  return v_out;
end $fn$;

-- the push service's answer: 2xx sent; 404/410 the subscription is gone and the device is revoked; else failed
create function public.worker_push_done(p_notification uuid, p_device uuid, p_status int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_state text := case when p_status between 200 and 299 then 'sent' when p_status in (404, 410) then 'gone' else 'failed' end;
begin
  update app.push_deliveries set state = v_state, sent_at = now(), status = p_status
  where notification_id = p_notification and device_id = p_device and state = 'queued';
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.push_devices set last_used_at = case when v_state = 'sent' then now() else last_used_at end,
    failures = case when v_state = 'sent' then 0 else failures + 1 end,
    revoked_at = case when v_state = 'gone' or (v_state = 'failed' and failures + 1 >= 10) then now() else revoked_at end
  where id = p_device;
  return jsonb_build_object('state', v_state);
end $fn$;

create function public.worker_vapid_key() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_priv text; v_pub text;
begin
  select s.decrypted_secret into v_priv from vault.decrypted_secrets s where s.name = 'vapid_private_key';
  select s.decrypted_secret into v_pub from vault.decrypted_secrets s where s.name = 'vapid_public_key';
  if v_priv is null then raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = 'push'; end if;
  return jsonb_build_object('private_key', v_priv, 'public_key', v_pub);
end $fn$;

-- ---------------------------------------------------------------------------
-- offline sync (SF-31, MOB-05): each mutation in order, in its own savepoint. A known mutation id returns its stored result. A
-- record still at the device's base version takes the change through the normal function. Otherwise the latest change wins: the
-- device's time (never later than now) against the record's updated_at; the earlier value stays in the changelog. A refusal is
-- «rejected» with its code and is not retried.
create function app.sync_one(p_m jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_op text := p_m ->> 'op'; v_ent text := p_m ->> 'entity'; v_id uuid; v_base int := (p_m ->> 'base_version')::int;
  v_fields jsonb := coalesce(p_m -> 'fields', '{}'::jsonb); v_at timestamptz := least(coalesce((p_m ->> 'client_at')::timestamptz, now()), now());
  e app.entities; v_ver int; v_upd timestamptz; v_row jsonb; r jsonb; v_conflict boolean := false;
begin
  if v_op not in ('create', 'update', 'note', 'activity_done', 'stage_move') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'op'; end if;
  if jsonb_typeof(v_fields) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields'; end if;
  if v_op = 'create' then
    if v_ent not in ('deal', 'activity') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
    r := public.rec_save(v_ent, null, v_fields, null, null, 'mobile');
    return jsonb_build_object('result', 'applied', 'entity', v_ent, 'id', r ->> 'id', 'version', (r ->> 'version')::int);
  end if;
  v_id := app.arg_uuid(p_m, 'record_id');
  if v_op = 'note' then
    if v_ent not in ('deal', 'person', 'organization', 'lead', 'activity') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
    if coalesce(btrim(v_fields ->> 'body'), '') = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
    r := public.note_save(v_ent, v_id, null, v_fields ->> 'body');
    return jsonb_build_object('result', 'applied', 'entity', 'note', 'id', r ->> 'id', 'record', jsonb_build_object('entity', v_ent, 'id', v_id));
  end if;
  v_ent := case v_op when 'activity_done' then 'activity' when 'stage_move' then 'deal' else v_ent end;
  if v_ent not in ('deal', 'activity') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
  e := app.entity(v_ent);
  execute format('select t.version, t.updated_at, to_jsonb(t) from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, v_id, app.vis_sql(e)) into v_ver, v_upd, v_row;
  if v_ver is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if v_base is not null and v_base <> v_ver then
    if v_at <= v_upd then
      return jsonb_build_object('result', 'superseded', 'entity', v_ent, 'id', v_id, 'version', v_ver, 'current', v_row);
    end if;
    v_conflict := true;
  end if;
  case v_op
    when 'update' then r := public.rec_save(v_ent, v_id, v_fields, v_ver, null, 'mobile');
    when 'activity_done' then
      perform public.activity_done(v_id, coalesce((v_fields ->> 'done')::boolean, true));
      r := jsonb_build_object('id', v_id, 'version', (select version from app.activities where id = v_id));
    when 'stage_move' then
      r := public.deal_move(v_id, app.arg_uuid(v_fields, 'stage_id'), v_ver, v_fields -> 'custom', 'mobile');
      if r ? 'missing' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'missing_fields'; end if;
  end case;
  return jsonb_build_object('result', 'applied', 'entity', v_ent, 'id', v_id, 'version', (r ->> 'version')::int, 'conflict', v_conflict);
end $fn$;

create function public.sync_apply(p_device uuid, p_mutations jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.mobile_require(); m jsonb; v_mid uuid; v_res jsonb; v_prev app.sync_receipts; v_out jsonb := '[]'::jsonb;
  v_msg text; v_det text; n_ok int := 0; n_sup int := 0; n_rej int := 0;
begin
  if p_device is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'device'; end if;
  perform set_config('app.source', 'mobile', true);                  -- the audit's source (0043's app.log)
  if jsonb_typeof(p_mutations) <> 'array' or jsonb_array_length(p_mutations) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mutations'; end if;
  for m in select value from jsonb_array_elements(p_mutations) loop
    v_mid := app.arg_uuid(m, 'mutation_id');
    select * into v_prev from app.sync_receipts where staff_id = v_me and device_id = p_device and mutation_id = v_mid;
    if found then
      v_out := v_out || (v_prev.response || jsonb_build_object('mutation_id', v_mid, 'replayed', true));
      continue;
    end if;
    begin
      v_res := app.sync_one(m);
    exception when others then
      get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
      v_res := jsonb_build_object('result', 'rejected', 'error', case when v_msg ~ '^[a-z_]{1,40}$' then v_msg else 'error' end,
                                  'detail', case when v_det ~ '^[a-z0-9_.:]{1,60}$' then v_det end);
    end;
    insert into app.sync_receipts (staff_id, device_id, mutation_id, result, error_code, response)
    values (v_me, p_device, v_mid, v_res ->> 'result', v_res ->> 'error', v_res - 'current');
    v_out := v_out || (v_res || jsonb_build_object('mutation_id', v_mid));
    case v_res ->> 'result' when 'applied' then n_ok := n_ok + 1; when 'superseded' then n_sup := n_sup + 1; else n_rej := n_rej + 1; end case;
  end loop;
  perform app.log('sync.applied', 'staff', v_me::text, jsonb_build_object('applied', n_ok, 'superseded', n_sup, 'rejected', n_rej));
  return jsonb_build_object('results', v_out, 'applied', n_ok, 'superseded', n_sup, 'rejected', n_rej);
end $fn$;

-- what changed since the device's cursor (outbox ids): records it may see, with their version, for it to re-read
create function public.sync_changes(p_since bigint default 0, p_limit int default 200) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.mobile_require(); v_sandbox boolean := (select sandbox from app.admins where id = v_me); r record; e app.entities; v_ver int; v_del boolean;
  v_out jsonb := '[]'::jsonb; v_cursor bigint := coalesce(p_since, 0); v_n int := 0; v_lim int := least(greatest(coalesce(p_limit, 200), 1), 500);
begin
  for r in select x.subject_type, x.subject_id, max(x.id) last_id from (
             select ev.id, ev.subject_type, ev.subject_id from app.events ev
             where ev.id > coalesce(p_since, 0) and ev.subject_type in ('deal', 'activity', 'person', 'organization', 'lead') and ev.subject_id is not null
               and (v_sandbox or not ev.is_sample)
             order by ev.id limit v_lim * 5) x
           group by x.subject_type, x.subject_id order by max(x.id) loop
    v_cursor := greatest(v_cursor, r.last_id);
    select * into e from app.entities where key = r.subject_type;
    continue when e.module is not null and not app.module_on(e.module);
    continue when not app.can(e.scope, 'see');
    v_ver := null;
    execute format('select t.version, t.deleted_at is not null from app.%I t where t.id = %L and %s', e.tbl, r.subject_id, app.vis_sql(e)) into v_ver, v_del;
    continue when v_ver is null;
    v_out := v_out || jsonb_build_object('entity', e.key, 'id', r.subject_id, 'version', v_ver, 'deleted', v_del);
    v_n := v_n + 1;
    exit when v_n >= v_lim;
  end loop;
  return jsonb_build_object('changes', v_out, 'cursor', v_cursor,
                            'more', exists (select 1 from app.events ev where ev.id > v_cursor and ev.subject_type in ('deal', 'activity', 'person', 'organization', 'lead')));
end $fn$;

-- ---------------------------------------------------------------------------
-- capture (MOB-06, AIA-07, SF-44): a file the caller uploaded to a record (0038's upload path) marked as what was captured; an audio
-- note is queued for transcription when the provider is connected
create function public.capture_save(p_entity text, p_id uuid, p_file_id uuid, p_kind text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.mobile_require(); f app.record_files; v_tr text;
begin
  if p_kind not in ('photo', 'audio', 'scan', 'card') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  select * into f from app.record_files where id = p_file_id and entity = p_entity and record_id = p_id and uploaded_by = v_me and deleted_at is null and ready_at is not null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if (p_kind = 'audio') <> (f.mime like 'audio/%') or (p_kind in ('photo', 'scan', 'card') and f.mime not like 'image/%' and f.mime <> 'application/pdf') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mime';
  end if;
  update app.record_files set capture_kind = p_kind where id = f.id;
  if p_kind = 'audio' then
    if app.connected('transcription') then
      perform pgmq.send('jobs', jsonb_build_object('job', 'transcription', 'file_id', f.id));
      v_tr := 'queued';
    else
      v_tr := 'not_connected';
    end if;
  end if;
  perform app.log('file.captured', p_entity, p_id::text, jsonb_build_object('file', f.id, 'kind', p_kind));
  return jsonb_build_object('id', f.id, 'kind', p_kind, 'transcription', v_tr);
end $fn$;

-- the transcription worker returns the audio note's text (only while the provider is connected)
create function public.worker_capture_transcript(p_file uuid, p_text text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.record_files;
begin
  perform app.require_connected('transcription');
  select * into f from app.record_files where id = p_file and capture_kind = 'audio' and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_text is null or char_length(p_text) > 50000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'text'; end if;
  update app.record_files set transcript = p_text, transcript_at = now() where id = f.id;
  if f.uploaded_by is not null then
    perform app.notify(f.uploaded_by, 'system', 'capture.transcript_ready', jsonb_build_object('file', f.id), app.entity_route(f.entity), f.entity, f.record_id);
  end if;
  return jsonb_build_object('id', f.id);
end $fn$;

-- the captured files of a record, with the transcript where there is one
create function public.captures_get(p_entity text, p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.file_entity(p_entity);
begin
  if not app.record_visible(e, p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('transcription', case when app.connected('transcription') then 'connected' else 'not_connected' end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.capture_kind, 'filename', f.filename, 'mime', f.mime, 'created_at', f.created_at,
                         'transcript', f.transcript, 'transcript_at', f.transcript_at) order by f.created_at desc)
                       from app.record_files f where f.entity = e.key and f.record_id = p_id and f.capture_kind is not null and f.deleted_at is null and f.ready_at is not null), '[]'::jsonb));
end $fn$;

-- the reviewed business-card draft becomes a contact (AIA-07: shown, edited, then saved), under contact_rule: opt_in_only refuses
-- (invalid, detail contact_rule, as 0031); source_and_basis needs a basis
create function public.card_draft_save(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.mobile_require(); v jsonb := coalesce(p_values, '{}'::jsonb); v_org uuid; r jsonb; v_person jsonb;
begin
  if app.setting('contact_rule') = 'opt_in_only' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'contact_rule'; end if;
  if app.setting('contact_rule') = 'source_and_basis' and coalesce(btrim(v ->> 'basis'), '') = '' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'basis';
  end if;
  if coalesce(btrim(v ->> 'name'), '') = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if v ->> 'organization_id' is not null then
    v_org := app.arg_uuid(v, 'organization_id');
  elsif coalesce(btrim(v ->> 'organization_name'), '') <> '' then
    select o.id into v_org from app.organizations o where lower(o.name) = lower(btrim(v ->> 'organization_name')) and o.deleted_at is null
      and app.visible(o.owner_id, o.visibility) order by o.created_at limit 1;
    if v_org is null then
      r := public.rec_save('organization', null, jsonb_build_object('name', btrim(v ->> 'organization_name'), 'source', 'Card scan'), null, null, 'mobile');
      v_org := (r ->> 'id')::uuid;
    end if;
  end if;
  v_person := jsonb_strip_nulls(jsonb_build_object('name', btrim(v ->> 'name'), 'title', nullif(btrim(v ->> 'title'), ''), 'email', nullif(lower(btrim(v ->> 'email')), ''),
                                                   'phone', nullif(btrim(v ->> 'phone'), ''), 'organization_id', v_org, 'source', 'Card scan'));
  r := public.rec_save('person', null, v_person, null, null, 'mobile');
  return jsonb_build_object('person_id', r ->> 'id', 'organization_id', v_org);
end $fn$;

-- geocoding (MOB-03): an organisation whose address changed loses its place and is queued; the worker (Geonorge) reports back
create function app.org_address_changed() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if tg_op = 'INSERT' or (new.address, new.postal_code, new.city, new.country) is distinct from (old.address, old.postal_code, old.city, old.country) then
    delete from app.record_geo where entity = 'organization' and record_id = new.id and field_key = 'address' and source = 'geonorge';
    if new.address is not null and new.deleted_at is null and new.country = 'NO' then
      perform pgmq.send('jobs', jsonb_build_object('job', 'geocode', 'entity', 'organization', 'id', new.id));
    end if;
  end if;
  return new;
end $fn$;
create trigger org_address_changed after insert or update of address, postal_code, city, country on app.organizations
  for each row execute function app.org_address_changed();

-- organisations with a Norwegian address and no place yet (the address is a company's, never a person's)
create function public.worker_geocode_claim(p_limit int default 50) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('entity', 'organization', 'id', o.id, 'field_key', 'address', 'address', o.address, 'postal_code', o.postal_code,
                                               'city', o.city, 'country', o.country)), '[]'::jsonb)
  from (select * from app.organizations o where o.deleted_at is null and o.address is not null and o.country = 'NO'
          and not exists (select 1 from app.record_geo g where g.entity = 'organization' and g.record_id = o.id and g.field_key = 'address')
        order by o.updated_at desc limit least(greatest(coalesce(p_limit, 50), 1), 500)) o
$fn$;

create function public.worker_geocode_done(p_entity text, p_id uuid, p_field text, p_lat numeric, p_lng numeric) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_entity <> 'organization' or not exists (select 1 from app.organizations where id = p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not app.coords_ok(p_lat, p_lng) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'coordinates'; end if;
  insert into app.record_geo (entity, record_id, field_key, lat, lng, source) values (p_entity, p_id, coalesce(p_field, 'address'), p_lat, p_lng, 'geonorge')
  on conflict (entity, record_id, field_key) do update set lat = excluded.lat, lng = excluded.lng, source = 'geonorge', geocoded_at = now()
  where app.record_geo.source = 'geonorge';
  return jsonb_build_object('ok', true);
end $fn$;

-- a place set by hand on an organisation the caller may edit (wins over the geocoder)
create function public.record_geo_set(p_entity text, p_id uuid, p_lat numeric, p_lng numeric) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities;
begin
  if p_entity <> 'organization' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
  e := app.entity(p_entity);
  perform app.require(e.scope, 'see');
  if not app.record_visible(e, p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not app.record_editable(e, p_id) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others'; end if;
  if not app.coords_ok(p_lat, p_lng) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'coordinates'; end if;
  insert into app.record_geo (entity, record_id, field_key, lat, lng, source) values (p_entity, p_id, 'address', p_lat, p_lng, 'manual')
  on conflict (entity, record_id, field_key) do update set lat = excluded.lat, lng = excluded.lng, source = 'manual', geocoded_at = now();
  perform app.log('record.geo_set', p_entity, p_id::text, null);
  return jsonb_build_object('ok', true);
end $fn$;

-- ===========================================================================
-- redefined: the generic save (0042's body; the source list adds «mobile») and the upload (0038's body; webp, heic and audio)
-- ===========================================================================
create or replace function public.rec_save(p_entity text, p_id uuid, p_values jsonb, p_version int default null,
                                p_reason text default null, p_source text default 'ui')
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid;
  v_sandbox boolean;
  v_old jsonb; v_new jsonb;
  k text; v jsonb; kind text; w boolean;
  v_cols text[] := '{}'; v_vals text[] := '{}'; v_sets text[] := '{}';
  v_id uuid; v_changed text[] := '{}'; v_req record;
  v_source text := coalesce(p_source, 'ui');
  v_has_edited boolean;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end if;
  if v_source not in ('ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system', 'meeting', 'mobile') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source';
  end if;
  v_me := app.require(e.scope, case when p_id is null then 'add' else 'see' end);
  v_sandbox := (select sandbox from app.admins where id = v_me);
  perform app.take_reason(p_reason);
  v_has_edited := exists (select 1 from information_schema.columns c where c.table_schema = 'app' and c.table_name = e.tbl and c.column_name = 'edited_fields');

  if p_id is not null then
    execute format('select to_jsonb(t) from app.%I t where t.id = %L and t.deleted_at is null and %s for update', e.tbl, p_id, app.vis_sql(e)) into v_old;
    if v_old is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and (v_old ->> 'version')::int <> p_version then
      raise exception 'version_conflict' using errcode = 'serialization_failure', detail = v_old ->> 'version';
    end if;
    if e.owned and (v_old ->> 'owner_id') is distinct from v_me::text and not app.can(e.scope, 'edit_others') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others';
    end if;
    if not e.owned and not app.can(e.scope, 'add') and not app.can(e.scope, 'edit_others') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others';
    end if;
  end if;

  for k, v in select * from jsonb_each(p_values) loop
    if k = 'custom' then
      perform app.check_custom(e.key, v);
      if p_id is null then
        v_cols := v_cols || 'custom'::text; v_vals := v_vals || format('jsonb_strip_nulls(%L::jsonb)', v::text);
      else
        v_sets := v_sets || format('custom = jsonb_strip_nulls(t.custom || %L::jsonb)', v::text);
      end if;
      continue;
    elsif k in ('owner_id', 'visibility') and e.owned then
      kind := case k when 'owner_id' then 'uuid' else 'text' end; w := true;
      if k = 'owner_id' and jsonb_typeof(v) = 'string' and not exists (select 1 from app.admins a where a.id::text = v #>> '{}' and a.active) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id';
      end if;
    elsif k = 'labels' then
      kind := 'uuid[]'; w := true;
      if exists (select 1 from jsonb_array_elements_text(v) x where not exists (select 1 from app.labels l where l.id::text = x and l.entity = e.key)) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'labels';
      end if;
    else
      select c.kind, c.writable into kind, w from app.entity_columns c where c.entity = e.key and c.col = k;
      if kind is null or not w then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
    end if;
    if p_id is null then
      v_cols := v_cols || k; v_vals := v_vals || app.lit(v, kind);
    else
      v_sets := v_sets || format('%I = %s', k, app.lit(v, kind));
    end if;
  end loop;

  if p_id is null then
    -- required columns and required custom fields on create
    for v_req in select c.col from app.entity_columns c where c.entity = e.key and c.required loop
      if coalesce(btrim(p_values ->> v_req.col), '') = '' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_req.col || ':required';
      end if;
    end loop;
    for v_req in select f.key from app.fields f where f.entity = e.key and f.quality = 'required' and f.from_stage_id is null and f.archived_at is null loop
      if jsonb_typeof(p_values #> array['custom', v_req.key]) is null or jsonb_typeof(p_values #> array['custom', v_req.key]) = 'null' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'custom.' || v_req.key || ':required';
      end if;
    end loop;
    if e.owned and not (p_values ? 'owner_id') then v_cols := v_cols || 'owner_id'::text; v_vals := v_vals || quote_literal(v_me); end if;
    if e.owned and not (p_values ? 'visibility') then
      v_cols := v_cols || 'visibility'::text; v_vals := v_vals || quote_literal(app.setting('visibility_default', e.key));
    end if;
    v_cols := v_cols || array['created_by', 'updated_by', 'is_sample'];
    v_vals := v_vals || array[quote_literal(v_me), quote_literal(v_me), quote_literal(v_sandbox)];
    if v_has_edited and v_source = 'ui' then
      v_cols := v_cols || 'edited_fields'::text; v_vals := v_vals || app.lit(to_jsonb(array(select jsonb_object_keys(p_values))), 'text[]');
    end if;
    execute format('insert into app.%I as t (%s) values (%s) returning to_jsonb(t)', e.tbl,
                   (select string_agg(format('%I', c), ', ') from unnest(v_cols) c), array_to_string(v_vals, ', ')) into v_new;
    v_id := (v_new ->> 'id')::uuid;
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
    values (e.key, v_id, '*created', null, null, v_me, v_source);
    perform app.log('record.created', e.key, v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
    perform app.emit(e.key || '.created', e.key, v_id, '{}'::jsonb, v_sandbox);
    return jsonb_build_object('id', v_id, 'version', 1);
  end if;

  if cardinality(v_sets) = 0 then
    return jsonb_build_object('id', p_id, 'version', (v_old ->> 'version')::int);
  end if;
  v_sets := v_sets || array['version = t.version + 1', 'updated_at = now()', format('updated_by = %L', v_me)];
  if v_has_edited and v_source = 'ui' then
    v_sets := v_sets || format('edited_fields = array(select distinct x from unnest(t.edited_fields || %s) x)',
                               app.lit(to_jsonb(array(select jsonb_object_keys(p_values - 'custom'))), 'text[]'));
  end if;
  execute format('update app.%I as t set %s where t.id = %L returning to_jsonb(t)', e.tbl, array_to_string(v_sets, ', '), p_id) into v_new;

  -- the history: one row per field whose value changed
  for k in select jsonb_object_keys(p_values) loop
    if k = 'custom' then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
      select e.key, p_id, 'custom.' || ck, v_old #> array['custom', ck], v_new #> array['custom', ck], v_me, v_source
      from jsonb_object_keys(p_values -> 'custom') ck
      where (v_old #> array['custom', ck]) is distinct from (v_new #> array['custom', ck]);
      v_changed := v_changed || array(select 'custom.' || ck from jsonb_object_keys(p_values -> 'custom') ck
                                      where (v_old #> array['custom', ck]) is distinct from (v_new #> array['custom', ck]));
    elsif (v_old -> k) is distinct from (v_new -> k) then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
      values (e.key, p_id, k, v_old -> k, v_new -> k, v_me, v_source);
      v_changed := v_changed || k;
    end if;
  end loop;
  perform app.log('record.updated', e.key, p_id::text, jsonb_build_object('fields', to_jsonb(v_changed)));
  if cardinality(v_changed) > 0 then
    perform app.emit(e.key || '.updated', e.key, p_id, jsonb_build_object('fields', to_jsonb(v_changed)), (v_new ->> 'is_sample')::boolean);
  end if;
  return jsonb_build_object('id', p_id, 'version', (v_new ->> 'version')::int);
end $fn$;

create or replace function public.file_upload_begin(p_entity text, p_id uuid, p_filename text, p_mime text, p_size bigint) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities := app.file_entity(p_entity); v_me uuid := app.me(); v_name text := btrim(p_filename); v_id uuid := gen_random_uuid(); v_path text; v_ext text; v_want text;
begin
  if not app.record_visible(e, p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not app.record_editable(e, p_id) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others'; end if;
  if p_mime is null or p_mime not in ('application/pdf', 'image/png', 'image/jpeg', 'text/csv', 'text/plain',
                                      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
                                      'image/webp', 'image/heic', 'audio/webm', 'audio/mp4', 'audio/mpeg') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mime';
  end if;
  v_ext := lower(substring(coalesce(v_name, '') from '\.([A-Za-z0-9]{1,5})$'));
  v_want := case p_mime when 'application/pdf' then 'pdf' when 'image/png' then 'png' when 'text/csv' then 'csv' when 'text/plain' then 'txt'
                        when 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then 'docx'
                        when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then 'xlsx'
                        when 'application/vnd.openxmlformats-officedocument.presentationml.presentation' then 'pptx'
                        when 'image/jpeg' then case when v_ext = 'jpeg' then 'jpeg' else 'jpg' end
                        when 'image/webp' then 'webp' when 'image/heic' then 'heic' when 'audio/webm' then 'webm' when 'audio/mp4' then 'm4a'
                        when 'audio/mpeg' then 'mp3' end;
  if v_name is null or char_length(v_name) not between 1 and 255 or v_name ~ '[/\\[:cntrl:]]' or v_ext is distinct from v_want then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filename';
  end if;
  if p_size is null or p_size not between 1 and 26214400 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'size'; end if;
  v_path := e.key || '/' || p_id || '/' || v_id || '/' || left(regexp_replace(v_name, '[^A-Za-z0-9._-]', '_', 'g'), 200);
  insert into app.record_files (id, entity, record_id, storage_path, filename, mime, size_bytes, source, uploaded_by, is_sample)
  values (v_id, e.key, p_id, v_path, v_name, p_mime, p_size, 'upload', v_me, coalesce((select sandbox from app.admins where id = v_me), false));
  perform app.log('file.upload_started', e.key, p_id::text, jsonb_build_object('file', v_id, 'size', p_size, 'mime', p_mime));
  return jsonb_build_object('id', v_id, 'bucket', 'record-files', 'path', v_path, 'expires_in', 300);
end $fn$;

-- ===========================================================================
-- revertable bulk changes (Contacts R-6): rec_bulk (0006's body) records each record's touched values before the change
-- ===========================================================================
create or replace function public.rec_bulk(p_entity text, p_ids uuid[], p_values jsonb, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid; v_id uuid; n int := 0; v_change uuid; v_old jsonb; v_before jsonb; r jsonb; k text;
begin
  v_me := app.require(e.scope, 'bulk');
  if cardinality(p_ids) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  insert into app.bulk_changes (entity, staff_id, fields, count, is_sample)
  values (e.key, v_me, array(select jsonb_object_keys(p_values)), 0, coalesce((select sandbox from app.admins where id = v_me), false))
  returning id into v_change;
  foreach v_id in array coalesce(p_ids, '{}') loop
    execute format('select to_jsonb(t) from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, v_id, app.vis_sql(e)) into v_old;
    v_before := '{}'::jsonb;
    for k in select jsonb_object_keys(p_values) loop
      if k = 'custom' and jsonb_typeof(p_values -> 'custom') = 'object' then
        v_before := v_before || jsonb_build_object('custom', coalesce((select jsonb_object_agg(ck, coalesce(v_old #> array['custom', ck], 'null'::jsonb))
                                                                       from jsonb_object_keys(p_values -> 'custom') ck), '{}'::jsonb));
      else
        v_before := v_before || jsonb_build_object(k, coalesce(v_old -> k, 'null'::jsonb));
      end if;
    end loop;
    r := public.rec_save(p_entity, v_id, p_values, null, p_reason, 'ui');
    insert into app.bulk_change_items (change_id, record_id, before, after_version) values (v_change, v_id, v_before, (r ->> 'version')::int)
    on conflict (change_id, record_id) do nothing;
    n := n + 1;
  end loop;
  update app.bulk_changes set count = n where id = v_change;
  return jsonb_build_object('updated', n, 'change_id', v_change);
end $fn$;

create function public.bulk_changes_get(p_entity text default null, p_limit int default 50) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_sandbox boolean := (select sandbox from app.admins where id = app.me());
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'entity', c.entity, 'staff', (select coalesce(a.name, a.email) from app.admins a where a.id = c.staff_id),
                          'at', c.at, 'fields', to_jsonb(c.fields), 'count', c.count, 'reverted_at', c.reverted_at, 'revert_result', c.revert_result,
                          'can_revert', c.reverted_at is null and app.can(e.scope, 'bulk')) order by c.at desc)
                   from (select * from app.bulk_changes x where (p_entity is null or x.entity = p_entity) and x.is_sample = v_sandbox order by x.at desc
                         limit least(greatest(coalesce(p_limit, 50), 1), 200)) c
                   join app.entities e on e.key = c.entity
                   where app.can(e.scope, 'see') and (e.module is null or app.module_on(e.module))), '[]'::jsonb);
end $fn$;

-- revert one bulk change: every record still at the version the change left is set back to its before-values (through rec_save,
-- so rights and rules apply); a record changed since is refused («stale»), a removed one «gone», one the caller may not edit «forbidden»
create function public.bulk_change_revert(p_id uuid, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_staff(); c app.bulk_changes; e app.entities; i app.bulk_change_items; v_ver int; v_del timestamptz; v_found boolean;
  v_out text; n_rev int := 0; n_stale int := 0; n_gone int := 0; n_forb int := 0; v_res jsonb;
begin
  select * into c from app.bulk_changes where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if c.reverted_at is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'reverted'; end if;
  e := app.entity(c.entity);
  perform app.require(e.scope, 'bulk');
  perform app.take_reason(p_reason);
  for i in select * from app.bulk_change_items where change_id = c.id order by record_id loop
    v_found := false; v_ver := null; v_del := null;
    execute format('select true, t.version, t.deleted_at from app.%I t where t.id = %L', e.tbl, i.record_id) into v_found, v_ver, v_del;
    if not coalesce(v_found, false) or v_del is not null then
      v_out := 'gone'; n_gone := n_gone + 1;
    elsif v_ver <> i.after_version then
      v_out := 'stale'; n_stale := n_stale + 1;
    else
      begin
        perform public.rec_save(c.entity, i.record_id, i.before, i.after_version, p_reason, 'ui');
        v_out := 'reverted'; n_rev := n_rev + 1;
      exception
        when insufficient_privilege then v_out := 'forbidden'; n_forb := n_forb + 1;
        when no_data_found then v_out := 'forbidden'; n_forb := n_forb + 1;
        when serialization_failure then v_out := 'stale'; n_stale := n_stale + 1;
      end;
    end if;
    update app.bulk_change_items set outcome = v_out where change_id = i.change_id and record_id = i.record_id;
  end loop;
  v_res := jsonb_build_object('reverted', n_rev, 'stale', n_stale, 'gone', n_gone, 'forbidden', n_forb);
  update app.bulk_changes set reverted_at = now(), reverted_by = v_me, revert_result = v_res where id = c.id;
  perform app.log('bulk_change.reverted', c.entity, null, v_res || jsonb_build_object('change', c.id));
  return v_res || jsonb_build_object('id', c.id);
end $fn$;

-- ===========================================================================
-- the production sandbox loader (R-SETTINGS-03, CUS-08): clears the sample records and loads the demo tenant again, every row a
-- sample. A live (non-sample) row is never touched: everything below writes or deletes «is_sample» rows only
-- ===========================================================================
create function public.sandbox_reset() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'configure'); v_removed jsonb; v_pipe uuid; v_stage uuid; v_org uuid; v_person uuid; v_deal uuid; v_lead uuid;
  v_call uuid; v_mail uuid; v_note uuid; v_tz text := (select time_zone from app.admins where id = app.me()); v_today date;
begin
  v_today := (now() at time zone v_tz)::date;
  v_removed := public.sandbox_clear();
  delete from app.notes where is_sample;
  select p.id into v_pipe from app.pipelines p where p.archived_at is null and not p.is_sample order by p.ord, p.created_at limit 1;
  select s.id into v_stage from app.stages s where s.pipeline_id = v_pipe order by (s.name = 'Proposal sent') desc, s.ord limit 1;
  insert into app.organizations (name, org_number, city, country, industry, employees, owner_id, visibility, is_sample, created_by, updated_by)
  values ('Lumio AS', '987467565', 'Oslo', 'NO', 'Professional services', 48, v_me, 'all', true, v_me, v_me) returning id into v_org;
  insert into app.people (name, title, email, phone, organization_id, contact_type, owner_id, visibility, is_sample, created_by, updated_by)
  values ('Kari Nordmann', 'Daglig leder', 'kari.nordmann@lumio.no', '+47 505 61 574', v_org, 'prospect', v_me, 'all', true, v_me, v_me) returning id into v_person;
  if v_stage is not null and app.module_on('deals') then
    insert into app.deals (title, value, currency, pipeline_id, stage_id, person_id, organization_id, expected_close_date, owner_id, visibility, is_sample, created_by, updated_by)
    values ('Lumio AS — Expansion to Skiftly', 64000, 'NOK', v_pipe, v_stage, v_person, v_org, v_today + 60, v_me, 'all', true, v_me, v_me) returning id into v_deal;
    insert into app.deal_stage_history (deal_id, stage_id, entered_at, moved_by, source) values (v_deal, v_stage, now(), v_me, 'system');
    insert into app.notes (entity, record_id, body, author_id, is_sample)
    values ('deal', v_deal, 'Kari wants Skiftly for the two warehouse teams first. Budget decision at the October board meeting.', v_me, true) returning id into v_note;
  end if;
  if app.module_on('leads') then
    insert into app.leads (title, organization_id, person_id, source, owner_id, visibility, is_sample, created_by, updated_by)
    values ('Lumio AS — Annual pulse', v_org, v_person, 'Website', v_me, 'all', true, v_me, v_me) returning id into v_lead;
  end if;
  insert into app.activities (type_id, subject, starts_at, duration_min, deal_id, person_id, organization_id, owner_id, visibility, is_sample, created_by, updated_by)
  values ((select id from app.activity_types where key = 'call'), 'Discovery call', ((v_today + 1)::timestamp + time '10:00') at time zone v_tz, 30,
          v_deal, v_person, v_org, v_me, 'all', true, v_me, v_me) returning id into v_call;
  insert into app.activities (type_id, subject, starts_at, duration_min, deal_id, person_id, organization_id, owner_id, visibility, is_sample, created_by, updated_by)
  values ((select id from app.activity_types where key = 'email'), 'Reply on pricing', ((v_today + 2)::timestamp + time '15:00') at time zone v_tz, 15,
          v_deal, v_person, v_org, v_me, 'all', true, v_me, v_me) returning id into v_mail;
  insert into app.changelog (entity, record_id, field, actor_id, source)
  select x.entity, x.id, '*created', v_me, 'system' from (values ('organization', v_org), ('person', v_person), ('deal', v_deal), ('lead', v_lead),
                                                                ('activity', v_call), ('activity', v_mail)) x(entity, id) where x.id is not null;
  perform app.log('sandbox.reset', null, null, jsonb_build_object('removed', (v_removed ->> 'removed')::bigint, 'organizations', 1, 'people', 1,
                                                                   'deals', case when v_deal is null then 0 else 1 end, 'leads', case when v_lead is null then 0 else 1 end, 'activities', 2,
                                                                   'notes', case when v_note is null then 0 else 1 end));
  return jsonb_build_object('removed', (v_removed ->> 'removed')::bigint, 'created', jsonb_build_object('organization', 1, 'person', 1,
                            'deal', case when v_deal is null then 0 else 1 end, 'lead', case when v_lead is null then 0 else 1 end, 'activity', 2,
                            'note', case when v_note is null then 0 else 1 end));
end $fn$;

-- the sandbox counts (0007's body) with the last reset
create or replace function public.sandbox_counts() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities; n bigint; out jsonb := '{}'::jsonb;
begin
  perform app.require_staff();
  for e in select * from app.entities order by ord loop
    execute format('select count(*) from app.%I where is_sample', e.tbl) into n;
    out := out || jsonb_build_object(e.key, n);
  end loop;
  return out || jsonb_build_object('last_cleared', (select max(at) from app.audit where action = 'sandbox.cleared'),
                                   'last_reset', (select max(at) from app.audit where action = 'sandbox.reset'));
end $fn$;

-- ===========================================================================
-- deactivation (SEC-09): a deactivated staff member's tokens, grants, codes and push devices end with them
-- ===========================================================================
create function app.staff_deactivated_platform() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if old.active and not new.active then
    update app.api_tokens set revoked_at = now(), revoke_reason = 'staff_deactivated' where staff_id = new.id and revoked_at is null;
    update app.oauth_grants set revoked_at = now(), revoke_reason = 'staff_deactivated', refresh_sha256 = null where staff_id = new.id and revoked_at is null;
    delete from app.oauth_codes where staff_id = new.id;
    update app.push_devices set revoked_at = now() where staff_id = new.id and revoked_at is null;
  end if;
  return new;
end $fn$;
create trigger staff_deactivated_platform after update of active on app.admins for each row execute function app.staff_deactivated_platform();

-- a second-factor reset (0043: the owner's staff_mfa_reset or a redeemed recovery code, both recorded as the security event
-- «mfa_reset») revokes the person's token and grants: whoever held them no longer passes the person's second factor
create function app.staff_mfa_reset_platform() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if new.kind = 'mfa_reset' and new.subject_staff_id is not null then
    update app.api_tokens set revoked_at = now(), revoke_reason = 'mfa_reset' where staff_id = new.subject_staff_id and revoked_at is null;
    update app.oauth_grants set revoked_at = now(), revoke_reason = 'mfa_reset', refresh_sha256 = null where staff_id = new.subject_staff_id and revoked_at is null;
    delete from app.oauth_codes where staff_id = new.subject_staff_id;
  end if;
  return new;
end $fn$;
create trigger staff_mfa_reset_platform after insert on app.security_events for each row execute function app.staff_mfa_reset_platform();

-- ===========================================================================
-- retention for this phase's logs (daily) and the burst window (every minute)
-- ===========================================================================
create function app.platform_prune() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a int; b int; c int; d int; e int; f int; g int; h int;
begin
  delete from app.integration_calls where at < now() - interval '30 days'; get diagnostics a = row_count;
  delete from app.webhook_deliveries where state <> 'queued' and coalesce(sent_at, scheduled_at) < now() - interval '30 days'; get diagnostics b = row_count;
  delete from app.api_requests_hourly where hour < now() - interval '90 days'; get diagnostics c = row_count;
  delete from app.api_idempotency where created_at < now() - interval '24 hours';
  delete from app.api_budget_day where day < current_date - 90;
  delete from app.job_runs where queued_at < now() - interval '90 days' and state in ('succeeded', 'failed'); get diagnostics d = row_count;
  delete from app.sync_receipts where received_at < now() - interval '30 days'; get diagnostics e = row_count;
  delete from app.oauth_codes where expires_at < now() - interval '1 day';
  delete from app.push_deliveries where state <> 'queued' and queued_at < now() - interval '30 days'; get diagnostics f = row_count;
  delete from app.bulk_changes where at < now() - interval '90 days'; get diagnostics g = row_count;
  delete from app.push_devices where revoked_at < now() - interval '90 days'; get diagnostics h = row_count;
  return jsonb_build_object('integration_calls', a, 'webhook_deliveries', b, 'api_requests_hourly', c, 'job_runs', d, 'sync_receipts', e,
                            'push_deliveries', f, 'bulk_changes', g, 'push_devices', h);
end $fn$;

create function app.api_burst_prune() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int;
begin
  delete from app.api_burst where second < floor(extract(epoch from now()))::bigint - 10;
  get diagnostics n = row_count;
  return n;
end $fn$;

-- the outbox kinds as data, for the automation trigger picker (R-AUTOMATION-04) and the webhook form
create function public.event_catalog_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('kind', c.kind, 'family', c.family, 'entity', c.entity, 'webhookable', c.webhookable,
                                                       'workflow_trigger', c.workflow_trigger, 'label_key', c.label_key) order by c.family, c.kind)
                   from app.event_catalog c), '[]'::jsonb);
end $fn$;

-- ===========================================================================
-- schedules: every platform job now runs through app.run_job (same names, same times), plus this phase's
-- ===========================================================================
-- Security's schedules (0043) that call one function join the registry under their own names
insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
select 'security_' || replace(substr(j.jobname, 10), '-', '_'), 'jobs.security_' || replace(substr(j.jobname, 10), '-', '_'), j.schedule, 'cron',
       substring(j.command from '^select (app\.[a-z_]+)\(\)$'), j.schedule ~ '^\*'
from cron.job j where j.jobname like 'security-%' and j.command ~ '^select app\.[a-z_]+\(\)$'
on conflict (key) do nothing;

do $$
declare d record;
begin
  for d in select key, schedule from app.job_defs where source = 'cron' loop
    perform cron.schedule(case when d.key like 'security\_%' then replace(d.key, '_', '-') else 'platform-' || replace(d.key, '_', '-') end,
                          d.schedule, format('select app.run_job(%L)', d.key));
  end loop;
end $$;

-- ===========================================================================
-- closed: RLS on every new table, no policy, no client grant
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array['integration_calls', 'product_event_kinds', 'product_commands', 'status_notices', 'event_catalog', 'api_tokens', 'api_scopes',
                           'oauth_apps', 'oauth_codes', 'oauth_grants', 'api_costs', 'api_requests_hourly', 'api_burst', 'api_budget_day', 'api_idempotency',
                           'webhooks', 'webhook_deliveries', 'integration_catalog', 'installed_apps', 'mcp_index', 'job_defs', 'job_runs', 'push_devices',
                           'push_deliveries', 'notification_prefs', 'sync_receipts', 'record_geo', 'bulk_changes', 'bulk_change_items'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.principal_staff(text)', 'app.principal_allows(text, text)', 'app.require_owner()',
                           'app.setting_num(text, numeric)', 'app.random_token(text, int)', 'app.bulk_item_fixed()', 'app.job_info(text)', 'app.job_failed(bigint)',
                           'app.run_job(text, bigint, uuid)', 'app.notify_once(uuid, text, text, jsonb, text, text, uuid, text)', 'app.push_ready()',
                           'app.notification_push()', 'app.chat_requested()', 'app.webhook_policy()', 'app.subject_visible_for(uuid, text, uuid)',
                           'app.sub_webhooks(app.events)', 'app.webhook_payload(uuid)', 'app.webhook_remove(uuid, text)', 'app.webhook_sweep()', 'app.webhook_mine(uuid)',
                           'app.api_plural(text)', 'app.api_entities()', 'app.api_endpoints()', 'app.api_schema_type(text)', 'app.api_budget()',
                           'app.api_burst_limit(text, text)', 'app.api_budget_warn(int, bigint)', 'app.api_meter(text, uuid, text)', 'app.api_principal_of(bytea)',
                           'app.arg_uuid(jsonb, text)', 'app.scopes_ok(text[])', 'app.redirects_ok(text[])', 'app.pkce_s256(text)',
                           'app.mcp_access_effect(text, text, text, text)', 'app.mcp_index_refresh()', 'app.mcp_search(text, int)', 'app.integration_connected(text)',
                           'app.application_health(text)', 'app.open_product_intake(text)', 'app.status_notices_due()', 'app.mobile_require()',
                           'app.km(numeric, numeric, numeric, numeric)', 'app.coords_ok(numeric, numeric)', 'app.orgs_near(numeric, numeric, numeric)',
                           'app.sync_one(jsonb)', 'app.org_address_changed()', 'app.staff_deactivated_platform()', 'app.staff_mfa_reset_platform()', 'app.platform_prune()', 'app.api_burst_prune()',
                           'app.me()', 'app.can(text, text)', 'app.notify(uuid, text, text, jsonb, text, text, uuid)', 'app.dispatch_events()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.webhooks_get(jsonb)', 'public.webhook_save(uuid, jsonb, int)', 'public.webhook_delete(uuid)', 'public.webhook_set_state(uuid, text)',
                           'public.webhook_test(uuid)', 'public.webhook_redeliver(uuid)', 'public.webhook_deliveries_get(uuid, timestamptz)', 'public.webhook_delivery_get(uuid)',
                           'public.api_definition()', 'public.api_token_create(text, timestamptz)', 'public.api_token_rotate()', 'public.api_token_revoke(uuid, text)',
                           'public.api_overview()', 'public.oauth_apps_get()', 'public.oauth_app_save(uuid, jsonb)', 'public.oauth_app_disable(uuid)',
                           'public.oauth_grants_get()', 'public.oauth_grant_revoke(uuid)', 'public.oauth_authorize(text, text, text[], text, text)',
                           'public.mcp_get()', 'public.mcp_set(boolean)', 'public.mcp_sync_set(boolean)',
                           'public.integration_catalog_get(text)', 'public.integration_install(text)', 'public.integration_remove(text, text)', 'public.integration_users(text)',
                           'public.integration_user_revoke(text, uuid)', 'public.integration_recommend(text)',
                           'public.applications_get()', 'public.application_get(text)', 'public.application_connect(jsonb)', 'public.application_update(text, jsonb)',
                           'public.flags_get(text)', 'public.status_notice_get(text)', 'public.status_notice_set(text, text, uuid, boolean, text)', 'public.content_get(text)',
                           'public.jobs_get(jsonb)', 'public.job_retry(bigint)',
                           'public.mobile_focus(numeric, numeric)', 'public.nearby(numeric, numeric, numeric, text[], jsonb)', 'public.checkin(text, uuid, text)',
                           'public.push_device_register(text, text, text, text)', 'public.push_device_revoke(uuid)', 'public.push_devices_get()',
                           'public.notification_prefs_get()', 'public.notification_prefs_set(text, text[])', 'public.sync_apply(uuid, jsonb)',
                           'public.sync_changes(bigint, int)', 'public.capture_save(text, uuid, uuid, text)', 'public.captures_get(text, uuid)',
                           'public.card_draft_save(jsonb)', 'public.record_geo_set(text, uuid, numeric, numeric)',
                           'public.bulk_changes_get(text, int)', 'public.bulk_change_revert(uuid, text)', 'public.sandbox_reset()', 'public.event_catalog_get()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_webhook_claim(int)', 'public.worker_webhook_done(uuid, int, int, text)', 'public.api_exec(bytea, text, jsonb)',
                           'public.worker_api_auth(bytea)', 'public.worker_api_usage(jsonb)', 'public.worker_oauth_token(jsonb)', 'public.worker_oauth_register(jsonb)',
                           'public.worker_integration_validate(jsonb)', 'public.worker_integration_call(jsonb)',
                           'public.worker_application_ping(text, boolean, int, int, text, text)', 'public.worker_status_notice_pushed(uuid, boolean, text)',
                           'public.worker_job_run(text, text, jsonb, text, bigint)', 'public.worker_push_claim(int)', 'public.worker_push_done(uuid, uuid, int)',
                           'public.worker_vapid_key()', 'public.worker_capture_transcript(uuid, text)', 'public.worker_geocode_claim(int)',
                           'public.worker_geocode_done(text, uuid, text, numeric, numeric)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
