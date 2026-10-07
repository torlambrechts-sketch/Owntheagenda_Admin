-- phase8_platform_invariants.sql — Platform and Mobile (0044; INT-01..11, MCP-01..03, MOB-01..08, AIA-06/07, ENT-01, SEC-07..09,
-- SF-23, SF-31, R-SETTINGS-03, Contacts R-6).
\ir _helpers.psql
begin;

-- the roles this suite was written for (0057 folded Projects into Sales): emma keeps the Projects set, which still exists
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'project') where email = 'emma@orgpuls.no';

-- the seed carries the design's platform fixtures (phase8-platform.mjs); this suite counts from an empty register
delete from app.webhooks; delete from app.api_tokens; delete from app.oauth_apps; delete from app.installed_apps; delete from app.status_notices;
delete from app.record_geo;  -- the mobile seed (phase8-mobile.mjs) places 46 organizations


-- the suite's own helpers. as_staff is redefined so it also leaves any token principal an earlier api_exec set in this transaction
create or replace function pg_temp.as_staff(p_email text, p_aal text default 'aal2') returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  if v is null then raise exception 'test helper: no auth user %', p_email; end if;
  perform set_config('app.api_principal', '', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated', 'aal', p_aal, 'email', p_email)::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;
-- a staff member who entered their TOTP code p_age seconds ago (fresh MFA), optionally in a given session
create or replace function pg_temp.as_mfa(p_email text, p_age int default 30, p_session uuid default null) returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  perform set_config('app.api_principal', '', true);
  perform set_config('request.jwt.claims', (jsonb_build_object('sub', v, 'role', 'authenticated', 'aal', 'aal2', 'email', p_email,
                      'amr', jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint - p_age)))
                      || case when p_session is not null then jsonb_build_object('session_id', p_session) else '{}'::jsonb end)::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;
-- the service role, as the edge functions call
create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('app.api_principal', '', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
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
create or replace function pg_temp.sid(p_email text) returns uuid language sql as $$ select id from app.admins where email = p_email $$;
create or replace function pg_temp.h(p_token text) returns bytea language sql as $$ select extensions.digest(p_token, 'sha256') $$;
-- make every queued attempt due, then claim them as the worker
create or replace function pg_temp.claim() returns jsonb language plpgsql as $$
begin
  update app.webhook_deliveries set scheduled_at = now() - interval '1 second' where state = 'queued';
  return public.worker_webhook_claim(100);
end $$;

-- ===========================================================================
-- structure: closed tables, client functions for signed-in staff, workers for the service role, helpers for nobody
-- ===========================================================================
create temp table t_tables as select unnest(array['integration_calls', 'product_event_kinds', 'product_commands', 'status_notices', 'event_catalog', 'api_tokens',
  'api_scopes', 'oauth_apps', 'oauth_codes', 'oauth_grants', 'api_costs', 'api_requests_hourly', 'api_burst', 'api_budget_day', 'api_idempotency', 'webhooks',
  'webhook_deliveries', 'integration_catalog', 'installed_apps', 'mcp_index', 'job_defs', 'job_runs', 'push_devices', 'push_deliveries', 'notification_prefs',
  'sync_receipts', 'record_geo', 'bulk_changes', 'bulk_change_items']) t;
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' and c.relrowsecurity
                      and c.relname in (select t from t_tables)) = 29, 'all 29 platform and mobile tables exist with row level security on');
select pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'app' and tablename in (select t from t_tables)), 'no new table has a policy');
select pg_temp.check(not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'app' and g.table_name in (select t from t_tables)
                                 and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
                 and (select count(distinct g.table_name) from information_schema.role_table_grants g where g.table_schema = 'app'
                      and g.table_name in (select t from t_tables) and g.grantee = 'service_role') = 29, 'no client grant on a new table; the service role has them');
select pg_temp.check(not has_table_privilege('authenticated', 'app.api_tokens', 'select') and not has_table_privilege('anon', 'app.webhooks', 'select')
                     and not has_table_privilege('authenticated', 'app.push_devices', 'select'), 'client roles cannot read tokens, webhooks or push endpoints');
create temp table t_rpcs as select unnest(array['public.webhooks_get(jsonb)', 'public.webhook_save(uuid, jsonb, int)', 'public.webhook_delete(uuid)',
  'public.webhook_set_state(uuid, text)', 'public.webhook_test(uuid)', 'public.webhook_redeliver(uuid)', 'public.webhook_deliveries_get(uuid, timestamptz)',
  'public.webhook_delivery_get(uuid)', 'public.api_definition()', 'public.api_token_create(text, timestamptz)', 'public.api_token_rotate()',
  'public.api_token_revoke(uuid, text)', 'public.api_overview()', 'public.oauth_apps_get()', 'public.oauth_app_save(uuid, jsonb)', 'public.oauth_app_disable(uuid)',
  'public.oauth_grants_get()', 'public.oauth_grant_revoke(uuid)', 'public.oauth_authorize(text, text, text[], text, text)', 'public.mcp_get()', 'public.mcp_set(boolean)',
  'public.mcp_sync_set(boolean)', 'public.integration_catalog_get(text)', 'public.integration_install(text)', 'public.integration_remove(text, text)', 'public.integration_users(text)',
  'public.integration_user_revoke(text, uuid)', 'public.integration_recommend(text)', 'public.applications_get()', 'public.application_get(text)',
  'public.application_connect(jsonb)', 'public.application_update(text, jsonb)', 'public.flags_get(text)', 'public.status_notice_get(text)',
  'public.status_notice_set(text, text, uuid, boolean, text)', 'public.content_get(text)', 'public.jobs_get(jsonb)', 'public.job_retry(bigint)',
  'public.mobile_focus(numeric, numeric)', 'public.nearby(numeric, numeric, numeric, text[], jsonb)', 'public.checkin(text, uuid, text)',
  'public.push_device_register(text, text, text, text)', 'public.push_device_revoke(uuid)', 'public.push_devices_get()', 'public.notification_prefs_get()',
  'public.notification_prefs_set(text, text[])', 'public.sync_apply(uuid, jsonb)', 'public.sync_changes(bigint, int)', 'public.capture_save(text, uuid, uuid, text)',
  'public.captures_get(text, uuid)', 'public.card_draft_save(jsonb)', 'public.record_geo_set(text, uuid, numeric, numeric)', 'public.bulk_changes_get(text, int)',
  'public.bulk_change_revert(uuid, text)', 'public.sandbox_reset()', 'public.event_catalog_get()']) f;
select pg_temp.check(not exists (select 1 from t_rpcs where not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')),
                     'every platform and mobile function is for signed-in staff (' || (select count(*) from t_rpcs) || '), never anon');
select pg_temp.check(not exists (select 1 from t_rpcs r join pg_proc p on p.oid = r.f::regprocedure where not p.prosecdef or not ('search_path=""' = any (p.proconfig))),
                     'every platform function is security definer with an empty search path');
create temp table t_workers as select unnest(array['public.worker_webhook_claim(int)', 'public.worker_webhook_done(uuid, int, int, text)', 'public.api_exec(bytea, text, jsonb)',
  'public.worker_api_auth(bytea)', 'public.worker_api_usage(jsonb)', 'public.worker_oauth_token(jsonb)', 'public.worker_oauth_register(jsonb)',
  'public.worker_integration_validate(jsonb)', 'public.worker_integration_call(jsonb)', 'public.worker_application_ping(text, boolean, int, int, text, text)',
  'public.worker_status_notice_pushed(uuid, boolean, text)', 'public.worker_job_run(text, text, jsonb, text, bigint)', 'public.worker_push_claim(int)',
  'public.worker_push_done(uuid, uuid, int)', 'public.worker_vapid_key()', 'public.worker_capture_transcript(uuid, text)', 'public.worker_geocode_claim(int)',
  'public.worker_geocode_done(text, uuid, text, numeric, numeric)']) f;
select pg_temp.check(not exists (select 1 from t_workers where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')
                                 or not has_function_privilege('service_role', f, 'execute')), 'the workers and api_exec (' || (select count(*) from t_workers) || ') are for the service role only');
select pg_temp.check(not has_function_privilege('authenticated', 'app.run_job(text, bigint, uuid)', 'execute') and not has_function_privilege('authenticated', 'app.mcp_access_effect(text, text, text, text)', 'execute')
                     and not has_function_privilege('authenticated', 'app.principal_staff(text)', 'execute') and not has_function_privilege('authenticated', 'app.me()', 'execute')
                     and not has_function_privilege('authenticated', 'app.open_product_intake(text)', 'execute') and not has_function_privilege('anon', 'app.sync_one(jsonb)', 'execute'),
                     'helpers are not callable by a client');

-- ===========================================================================
-- §3.2 changes to existing objects
-- ===========================================================================
select pg_temp.check((select stage from app.products where key = 'orgpuls') = 'ga', 'a product is generally available unless marked beta');
select pg_temp.check((select cardinality(scopes) from app.installations where product = 'orgpuls') = 12, 'the running Orgpuls installation keeps every scope it uses');
select pg_temp.check((select array_agg(command order by command) from app.product_commands where product = 'orgpuls') = array['billing.cancel', 'billing.cancel_withdraw',
  'billing.cancellation', 'billing.extend_trial', 'legal.approvals', 'legal.auto_record', 'legal.review', 'legal.reviews', 'legal.set', 'locales.pilot', 'locales.pilots',
  'modules.list', 'modules.pilot', 'modules.set_status', 'modules.set_validation', 'modules.sync', 'orgs.delete_now', 'orgs.deletions', 'orgs.get', 'orgs.list',
  'orgs.resync', 'overrides.approve', 'overrides.import', 'overrides.list', 'settings.notice', 'settings.set_indexing', 'settings.set_notice', 'translations.approve',
  'translations.auto_approve', 'translations.history', 'translations.import', 'translations.list', 'translations.set_auto_approve', 'translations.sources', 'translations.update'],
  'product_commands mirrors the 35 commands of _shared/orgpuls.ts');
insert into app.changelog (entity, record_id, field, source) values ('deal', gen_random_uuid(), 'title', 'mobile');
select pg_temp.check(true, 'the changelog accepts the source mobile');
select pg_temp.check(exists (select 1 from app.activity_types where key = 'visit' and active), 'the activity type visit exists');
select pg_temp.check((select fn from app.event_subscribers where name = 'webhooks') = 'app.sub_webhooks'
                     and (select last_event_id from app.event_cursors where subscriber = 'webhooks') <= (select coalesce(max(id), 0) from app.events),
                     'the webhooks subscriber is registered behind the dispatcher, starting at the current outbox');
select pg_temp.check(exists (select 1 from app.event_catalog where kind = 'person.created' and webhookable) and not exists (select 1 from app.event_catalog where kind = 'person.added')
                     and not exists (select 1 from app.event_catalog where webhookable and family in ('api', 'webhook', 'export', 'job', 'mcp', 'usage', 'integration')),
                     'webhooks subscribe to person.created (never person.added); admin, export and job events are never webhookable');
select pg_temp.check(not exists (select 1 from app.api_scopes where rights && array['global:security', 'global:configure']), 'no token scope carries security or configuration');

-- ===========================================================================
-- identity (§3.9): normal sessions unchanged; tokens; scopes; forged principals; the session check
-- ===========================================================================
create temp table t_staff as select pg_temp.sid('tor@orgpuls.no') tor, pg_temp.sid('ingrid@orgpuls.no') ingrid, pg_temp.sid('eirik@orgpuls.no') eirik,
  pg_temp.sid('ola@orgpuls.no') ola, pg_temp.sid('sara@orgpuls.no') sara;
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(app.me() = (select ingrid from t_staff) and app.can('deals', 'see') and not app.can('global', 'configure'), 'a normal staff session is unchanged');
select pg_temp.as_staff('ingrid@orgpuls.no', 'aal1');
select pg_temp.check(app.me() is null, 'aal1 is still nobody');

-- a deal of Ingrid's and one only Tor may see
create temp table t_deal as select id, title, version from app.deals where owner_id = (select ingrid from t_staff) and deleted_at is null and not is_sample
  and status = 'open' order by created_at limit 1;
update app.deals set visibility = 'owner' where id = (select id from app.deals where owner_id = (select tor from t_staff) and deleted_at is null and not is_sample order by created_at limit 1);
create temp table t_hidden as select id from app.deals where owner_id = (select tor from t_staff) and visibility = 'owner' and deleted_at is null and not is_sample limit 1;
select pg_temp.check((select count(*) from t_deal) = 1 and (select count(*) from t_hidden) = 1, 'fixture: a deal of Ingrid''s and one only Tor may see');

-- tokens: a fresh second factor, one active, the plaintext once and a hash only
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.api_token_create('CI')$$, 'forbidden', 'fresh_mfa', 'a token needs a fresh second factor');
select pg_temp.as_mfa('ingrid@orgpuls.no', 20 * 60);
select pg_temp.expect_detail($$select public.api_token_create('CI')$$, 'forbidden', 'fresh_mfa', 'a second factor 20 minutes old is not fresh');
select pg_temp.as_mfa('ingrid@orgpuls.no');
create temp table t_tok as select r ->> 'token' tok, (r ->> 'id')::uuid id from (select public.api_token_create('Zapier') r) x;
select pg_temp.check((select tok ~ '^sk_live_[0-9A-Za-z]{32}$' from t_tok), 'a token is sk_live_ and 32 base62 characters');
select pg_temp.check((select token_sha256 = pg_temp.h((select tok from t_tok)) and last4 = right((select tok from t_tok), 4) from app.api_tokens where id = (select id from t_tok))
                     and not exists (select 1 from app.api_tokens t where to_jsonb(t)::text like '%' || (select tok from t_tok) || '%'), 'only the hash and the last four are stored');
select pg_temp.expect_detail($$select public.api_token_create('Again')$$, 'invalid', 'active_token', 'one active token per staff member (rotate instead)');
select pg_temp.check(exists (select 1 from app.events where kind = 'api_token.created' and subject_id = (select id from t_tok))
                     and exists (select 1 from app.audit where action = 'api_token.created' and target_id = (select id::text from t_tok)), 'creation is audited and emitted');
select pg_temp.check((public.api_overview() -> 'tokens' -> 0 ->> 'masked') like 'sk_live_…%' and (public.api_overview() ->> 'has_token')::boolean, 'the overview shows the masked token');

-- the token acting: exactly the staff member's rights, through the same functions
select pg_temp.as_service();
select pg_temp.check((public.worker_api_auth(pg_temp.h((select tok from t_tok))) ->> 'staff_id')::uuid = (select ingrid from t_staff), 'the gateway resolves the token by its hash');
select pg_temp.check((public.api_exec(pg_temp.h((select tok from t_tok)), 'list', '{"entity":"deal","query":{"limit":5}}') ->> 'status') = '200', 'a token lists deals');
select pg_temp.check(app.me() = (select ingrid from t_staff), 'inside api_exec app.me() is the token''s staff member');
select pg_temp.check((select staff_id = (select ingrid from t_staff) and source = 'api' and principal_kind = 'token' and principal_id = (select id from t_tok)
                      from app.audit where action = 'record.listed' order by id desc limit 1), 'the read is audited with source api and the token as principal');
select pg_temp.expect_error($$select public.api_exec(pg_temp.h((select tok from t_tok)), 'get', jsonb_build_object('entity', 'deal', 'id', (select id from t_hidden)))$$,
                            'not_found', 'a record the staff member may not see is unreachable through the API (SEC-08)');
create temp table t_upd as select public.api_exec(pg_temp.h((select tok from t_tok)), 'update', jsonb_build_object('entity', 'deal', 'id', (select id from t_deal),
                      'values', jsonb_build_object('title', 'API title'))) r;
select pg_temp.check((select r ->> 'status' from t_upd) = '200'
                     and (select source from app.changelog where entity = 'deal' and record_id = (select id from t_deal) and field = 'title' order by id desc limit 1) = 'api',
                     'a token updates a deal it may edit; the changelog says api');
select pg_temp.check(not app.can('global', 'configure') and not app.can('global', 'security'), 'a token never reaches configure or security');
-- an admin's token is still limited
select set_config('app.api_principal', '', true);
insert into app.api_tokens (staff_id, name, token_sha256, last4) values ((select tor from t_staff), 'Admin', pg_temp.h('sk_live_admintokenforthetestsuite000000'), '0000');
select pg_temp.as_service();
select public.api_exec(pg_temp.h('sk_live_admintokenforthetestsuite000000'), 'search', '{"q":"lumio"}');
select pg_temp.check(app.me() = (select tor from t_staff) and app.can('deals', 'delete') and not app.can('global', 'configure') and not app.can('global', 'security'),
                     'an admin''s token has the admin''s record rights but never global:configure or global:security (SEC-07)');
-- scopes narrow: deals:read cannot create
select set_config('app.api_principal', '', true);
update app.api_tokens set scopes = '{deals:read}' where id = (select id from t_tok);
select pg_temp.as_service();
select pg_temp.expect_detail($$select public.api_exec(pg_temp.h((select tok from t_tok)), 'create', '{"entity":"deal","values":{"title":"x"}}')$$,
                             'forbidden', 'deals:add', 'a deals:read token cannot create');
select pg_temp.check((public.api_exec(pg_temp.h((select tok from t_tok)), 'list', '{"entity":"deal"}') ->> 'status') = '200', 'a deals:read token still lists');
select set_config('app.api_principal', '', true);
update app.api_tokens set scopes = '{*}' where id = (select id from t_tok);
-- idempotent create
select pg_temp.as_service();
create temp table t_idem as select public.api_exec(pg_temp.h((select tok from t_tok)), 'create', jsonb_build_object('entity', 'organization', 'values', jsonb_build_object('name', 'Idem AS'),
  'idempotency_key', 'idem-key-0001')) a;
select pg_temp.check((public.api_exec(pg_temp.h((select tok from t_tok)), 'create', jsonb_build_object('entity', 'organization', 'values', jsonb_build_object('name', 'Idem AS'),
                       'idempotency_key', 'idem-key-0001')) ->> 'replayed')::boolean
                     and (select count(*) from app.organizations where name = 'Idem AS') = 1, 'a create with the same idempotency key happens once');
-- ENT-01: a module off is off through the API too
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('deals', false);
select pg_temp.as_service();
select pg_temp.expect_error($$select public.api_exec(pg_temp.h((select tok from t_tok)), 'list', '{"entity":"deal"}')$$, 'module_off', 'a module switched off refuses the API (ENT-01)');
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('deals', true);
-- a forged principal: a client JWT with the setting is nobody
select pg_temp.as_staff('ingrid@orgpuls.no');
select set_config('app.api_principal', 'token:' || (select id from t_tok), true);
select pg_temp.check(app.me() is null, 'a client session that sets app.api_principal is nobody');
select pg_temp.expect_error($$select public.api_overview()$$, 'not_signed_in', 'a forged principal reaches nothing');
-- expiry and revocation (INT-02)
select set_config('app.api_principal', '', true);
update app.api_tokens set expires_at = now() - interval '1 minute' where id = (select id from t_tok);
select pg_temp.as_service();
select pg_temp.check(public.worker_api_auth(pg_temp.h((select tok from t_tok))) is null, 'an expired token is refused by the gateway');
select pg_temp.expect_error($$select public.api_exec(pg_temp.h((select tok from t_tok)), 'list', '{"entity":"deal"}')$$, 'not_signed_in', 'an expired token is refused by api_exec');
select pg_temp.check(app.principal_staff('token:' || (select id from t_tok)) is null, 'app.me() answers no one for an expired token');
select set_config('app.api_principal', '', true);
update app.api_tokens set expires_at = null where id = (select id from t_tok);
select pg_temp.as_mfa('ingrid@orgpuls.no');
create temp table t_rot as select r ->> 'token' tok, (r ->> 'id')::uuid id from (select public.api_token_rotate() r) x;
select pg_temp.as_service();
select pg_temp.check(public.worker_api_auth(pg_temp.h((select tok from t_tok))) is null and public.worker_api_auth(pg_temp.h((select tok from t_rot))) is not null
                     and (select revoke_reason from app.api_tokens where id = (select id from t_tok)) = 'rotated', 'rotation stops the old token at once and issues a new one');
select pg_temp.as_staff('eirik@orgpuls.no');
select pg_temp.expect_detail($$select public.api_token_revoke((select id from t_rot))$$, 'forbidden', 'global:security', 'another sales user cannot revoke the token');
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.api_token_revoke((select id from t_rot));
select pg_temp.as_service();
select pg_temp.check(public.worker_api_auth(pg_temp.h((select tok from t_rot))) is null, 'a revoked token is refused at once');
select pg_temp.expect_error($$select public.api_exec(pg_temp.h((select tok from t_rot)), 'list', '{"entity":"deal"}')$$, 'not_signed_in', 'api_exec refuses a revoked token');

-- the session check (0043's register): a revoked session is nobody before its JWT expires; no claim is checked as before
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_sess as select gen_random_uuid() live, gen_random_uuid() ended, gen_random_uuid() unknown;
insert into app.staff_sessions (session_id, staff_id, method) select live, (select tor from t_staff), 'password_totp' from t_sess;
insert into app.staff_sessions (session_id, staff_id, method) select ended, (select tor from t_staff), 'password_totp' from t_sess;
update app.staff_sessions set ended_at = now(), end_reason = 'forced' where session_id = (select ended from t_sess);
select pg_temp.as_mfa('tor@orgpuls.no', 30, (select live from t_sess));
select pg_temp.check(app.me() = (select tor from t_staff), 'a live session works');
select pg_temp.as_mfa('tor@orgpuls.no', 30, (select ended from t_sess));
select pg_temp.check(app.me() is null, 'an ended session is nobody at once (SEC-04)');
select pg_temp.expect_error($$select public.api_overview()$$, 'not_signed_in', 'an RPC with an ended session raises not_signed_in');
select pg_temp.as_mfa('tor@orgpuls.no', 30, (select unknown from t_sess));
select pg_temp.check(app.me() is null, 'a session the register does not know (and Auth did not just create) is nobody');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(app.me() = (select tor from t_staff), 'a JWT without a session claim is checked as before');

-- deactivation and a second-factor reset end tokens and grants (SEC-09)
select pg_temp.as_mfa('eirik@orgpuls.no');
create temp table t_etok as select (public.api_token_create('E') ->> 'id')::uuid id;
select pg_temp.as_staff('tor@orgpuls.no');
select public.staff_save((select eirik from t_staff), '{"active": false}');
select pg_temp.check((select revoke_reason from app.api_tokens where id = (select id from t_etok)) = 'staff_deactivated', 'deactivating a staff member revokes their token');
select public.staff_save((select eirik from t_staff), '{"active": true}');
select pg_temp.as_mfa('eirik@orgpuls.no');
create temp table t_etok2 as select (public.api_token_create('E2') ->> 'id')::uuid id;
select pg_temp.as_mfa('tor@orgpuls.no');
select public.staff_mfa_reset((select eirik from t_staff), 'lost phone');
select pg_temp.check((select revoke_reason from app.api_tokens where id = (select id from t_etok2)) = 'mfa_reset', 'a second-factor reset revokes the token');

-- owner and fresh second factor helpers
select pg_temp.as_mfa('sara@orgpuls.no');
select pg_temp.expect_detail($$select public.application_connect('{"key":"vaktbok"}')$$, 'forbidden', 'owner_only', 'connecting an application needs the owner');

-- ===========================================================================
-- webhooks (INT-04, SF-23, D-32): signed with a Vault secret, retried 3/30/150 s, banned, deleted; the log keeps no values
-- ===========================================================================
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.webhook_save(null, '{"event_kind":"deal.updated","url":"http://hooks.example.com/x"}')$$, 'invalid', 'url', 'a webhook URL must be https');
select pg_temp.expect_detail($$select public.webhook_save(null, '{"event_kind":"deal.updated","url":"https://10.0.4.2/internal"}')$$, 'invalid', 'url', 'a private address cannot be saved');
select pg_temp.expect_detail($$select public.webhook_save(null, '{"event_kind":"person.added","url":"https://hooks.example.com/x"}')$$, 'invalid', 'event_kind', 'person.added is not an event');
select pg_temp.expect_detail($$select public.webhook_save(null, '{"event_kind":"api_token.created","url":"https://hooks.example.com/x"}')$$, 'invalid', 'event_kind', 'an admin event is not webhookable');
create temp table t_wh as select (r ->> 'id')::uuid id, r ->> 'secret' secret from (select public.webhook_save(null, '{"event_kind":"deal.updated","url":"https://hooks.example.com/deals"}') r) x;
select pg_temp.check((select secret ~ '^whsec_' from t_wh) and (select s.decrypted_secret from vault.decrypted_secrets s join app.webhooks w on w.vault_secret_id = s.id where w.id = (select id from t_wh)) = (select secret from t_wh)
                     and (select s.name from vault.secrets s join app.webhooks w on w.vault_secret_id = s.id where w.id = (select id from t_wh)) = 'webhook:' || (select id from t_wh),
                     'the signing secret is shown once and kept in Vault as webhook:<id>');
select pg_temp.check(not exists (select 1 from app.webhooks w where to_jsonb(w)::text like '%' || (select secret from t_wh) || '%'), 'the webhook row holds no secret');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('count_limits', 'number', '', 1);
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.webhook_save(null, '{"event_kind":"deal.won","url":"https://hooks.example.com/won"}')$$, 'invalid', 'count_limit', 'count_limits caps webhooks per owner');
select pg_temp.check((public.webhooks_get() ->> 'limit')::int = 1, 'the screen reads the real limit');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('count_limits', 'unlimited');

-- an update to a deal Ingrid sees becomes one delivery; one only Tor sees becomes none
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.rec_save('deal', (select id from t_deal), '{"title":"Webhook title"}');
select app.sub_webhooks(e) from app.events e where e.kind = 'deal.updated' and e.subject_id = (select id from t_deal) order by e.id desc limit 1;
do $$ declare v bigint := app.emit('deal.updated', 'deal', (select id from t_hidden), '{"fields":["title"]}'::jsonb);
begin perform app.sub_webhooks(e) from app.events e where e.id = v; end $$;
select pg_temp.check((select count(*) from app.webhook_deliveries where webhook_id = (select id from t_wh)) = 1, 'one delivery for the visible deal, none for the hidden one');
select pg_temp.as_service();
create temp table t_claim as select pg_temp.claim() -> 0 c;
select pg_temp.check((select c ->> 'url' from t_claim) = 'https://hooks.example.com/deals' and (select (c ->> 'body')::jsonb ->> 'event' from t_claim) = 'deal.updated'
                     and (select (c ->> 'body')::jsonb #>> '{current,title}' from t_claim) = 'Webhook title'
                     and (select (c ->> 'body')::jsonb #>> '{previous,title}' from t_claim) = 'API title', 'the body carries current and previous state');
select pg_temp.check((select (c -> 'headers' ->> 'Sentral-Signature') = 't=' || substring(c -> 'headers' ->> 'Sentral-Signature' from '^t=(\d+),') || ',v1='
                      || encode(extensions.hmac(substring(c -> 'headers' ->> 'Sentral-Signature' from '^t=(\d+),') || '.' || (c ->> 'body'), (select secret from t_wh), 'sha256'), 'hex') from t_claim),
                     'the signature is HMAC-SHA256 of t.body with the webhook''s secret (D-32)');
select pg_temp.check((select body_sha256 = extensions.digest((select c ->> 'body' from t_claim), 'sha256') and envelope ->> 'event' = 'deal.updated'
                             and envelope -> 'fields' = '["title"]'::jsonb and not (envelope ? 'current') and envelope::text not like '%Webhook title%' and envelope::text not like '%API title%'
                      from app.webhook_deliveries where id = (select (c ->> 'delivery_id')::uuid from t_claim)), 'the log keeps the envelope and a hash, never the values');
-- retries after 3, 30 and 150 s: four attempts
select public.worker_webhook_done((select (c ->> 'delivery_id')::uuid from t_claim), 500, 120, 'http_500');
select pg_temp.check((select scheduled_at = now() + interval '3 seconds' from app.webhook_deliveries where webhook_id = (select id from t_wh) and attempt = 2), 'attempt 2 after 3 s');
select public.worker_webhook_done((pg_temp.claim() -> 0 ->> 'delivery_id')::uuid, 502, 80, 'http_502');
select pg_temp.check((select scheduled_at = now() + interval '30 seconds' from app.webhook_deliveries where webhook_id = (select id from t_wh) and attempt = 3), 'attempt 3 after 30 s');
select public.worker_webhook_done((pg_temp.claim() -> 0 ->> 'delivery_id')::uuid, null, 10000, 'timeout');
select pg_temp.check((select scheduled_at = now() + interval '150 seconds' from app.webhook_deliveries where webhook_id = (select id from t_wh) and attempt = 4), 'attempt 4 after 150 s');
select public.worker_webhook_done((pg_temp.claim() -> 0 ->> 'delivery_id')::uuid, 503, 90, 'http_503');
select pg_temp.check((select count(*) from app.webhook_deliveries where webhook_id = (select id from t_wh)) = 4
                     and (select first_attempt_failures from app.webhooks where id = (select id from t_wh)) = 1, 'four attempts, then no more; one first-attempt failure counted');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_dget as select public.webhook_delivery_get((select id from app.webhook_deliveries where webhook_id = (select id from t_wh) and attempt = 4)) r;
select pg_temp.check((select (r ->> 'attempts')::int = 4 and not (r ? 'body') from t_dget) and exists (select 1 from app.audit where action = 'webhook_delivery.read'),
                     'a delivery reads «n / 4», without a body, and the read is audited');
-- ten first-attempt failures in a row ban it for 30 minutes and tell the owner
select pg_temp.as_service();
do $$
declare i int; v_ev bigint; c jsonb;
begin
  for i in 2 .. 10 loop
    v_ev := app.emit('deal.updated', 'deal', (select id from t_deal), '{"fields":["title"]}'::jsonb);
    perform app.sub_webhooks(e) from app.events e where e.id = v_ev;
    update app.webhook_deliveries set scheduled_at = now() - interval '1 second' where state = 'queued' and attempt = 1;
    for c in select value from jsonb_array_elements(public.worker_webhook_claim(100)) loop
      perform public.worker_webhook_done((c ->> 'delivery_id')::uuid, 500, 10, 'http_500');
    end loop;
  end loop;
end $$;
select pg_temp.check((select state = 'banned' and banned_until = now() + interval '30 minutes' from app.webhooks where id = (select id from t_wh)),
                     'ten first-attempt failures ban the webhook for 30 minutes');
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select ingrid from t_staff) and key = 'webhook.banned')
                     and exists (select 1 from app.events where kind = 'webhook.banned' and subject_id = (select id from t_wh)), 'the owner hears of the ban; webhook.banned is emitted');
select pg_temp.check(jsonb_array_length(pg_temp.claim()) = 0, 'a banned webhook sends nothing');
update app.webhooks set banned_until = now() - interval '1 second' where id = (select id from t_wh);
select app.webhook_sweep();
select pg_temp.check((select state from app.webhooks where id = (select id from t_wh)) = 'active', 'the ban runs out');
-- three days without success delete it, its secret goes and the owner hears why
update app.webhooks set failing_since = now() - interval '2 days' where id = (select id from t_wh);
select app.webhook_sweep();
select pg_temp.check((select state from app.webhooks where id = (select id from t_wh)) = 'active', 'two days failing is not yet three');
update app.webhooks set failing_since = now() - interval '4 days' where id = (select id from t_wh);
select app.webhook_sweep();
select pg_temp.check((select state = 'deleted' and vault_secret_id is null from app.webhooks where id = (select id from t_wh))
                     and not exists (select 1 from vault.secrets where name = 'webhook:' || (select id from t_wh))
                     and exists (select 1 from app.notifications where staff_id = (select ingrid from t_staff) and key = 'webhook.deleted'),
                     'after three days without success it is deleted, its Vault secret gone, the owner told (SF-23 step 5)');
-- the policy settings in both states
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((app.webhook_policy() ->> 'timeout_s')::int = 10 and (app.webhook_policy() ->> 'ban_after')::int = 10, 'source values by default');
select public.setting_set('webhook_ban_after', 'custom', '', 2), public.setting_set('webhook_timeout_s', 'custom', '', 5),
       public.setting_set('webhook_ban_min', 'custom', '', 5), public.setting_set('webhook_delete_days', 'custom', '', 1);
select pg_temp.check((app.webhook_policy() ->> 'ban_after')::int = 10, 'the custom numbers are read only while safeguards is custom');
select public.setting_set('safeguards', 'custom', '', 1);
select pg_temp.check((app.webhook_policy() ->> 'ban_after')::int = 2 and (app.webhook_policy() ->> 'timeout_s')::int = 5 and (app.webhook_policy() ->> 'ban_min')::int = 5
                     and (app.webhook_policy() ->> 'delete_days')::int = 1, 'safeguards custom: the webhook_* numbers apply');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_wh2 as select (public.webhook_save(null, '{"event_kind":"deal.updated","url":"https://hooks.example.com/two"}') ->> 'id')::uuid id;
select pg_temp.as_service();
do $$
declare i int; v_ev bigint; c jsonb;
begin
  for i in 1 .. 2 loop
    v_ev := app.emit('deal.updated', 'deal', (select id from t_deal), '{"fields":["title"]}'::jsonb);
    perform app.sub_webhooks(e) from app.events e where e.id = v_ev;
    update app.webhook_deliveries set scheduled_at = now() - interval '1 second' where state = 'queued' and attempt = 1;
    for c in select value from jsonb_array_elements(public.worker_webhook_claim(100)) loop
      if (c ->> 'timeout_s')::int <> 5 then raise exception 'FAIL the custom timeout reaches the worker'; end if;
      perform public.worker_webhook_done((c ->> 'delivery_id')::uuid, 500, 10, 'http_500');
    end loop;
  end loop;
end $$;
select pg_temp.check((select state = 'banned' and banned_until = now() + interval '5 minutes' from app.webhooks where id = (select id from t_wh2)),
                     'custom: banned after 2 first-attempt failures for 5 minutes; the worker got the 5 s timeout');
update app.webhooks set state = 'active', banned_until = null, failing_since = now() - interval '2 days' where id = (select id from t_wh2);
select app.webhook_sweep();
select pg_temp.check((select state from app.webhooks where id = (select id from t_wh2)) = 'deleted', 'custom: deleted after 1 day failing');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('safeguards', 'off');
select pg_temp.check(app.webhook_policy() ->> 'ban_after' is null and app.webhook_policy() ->> 'delete_days' is null, 'safeguards off: no ban, no deletion');
select public.setting_set('safeguards', 'source_values');
-- a private address found at send time blocks; test and redeliver; rights
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_wh3 as select (public.webhook_save(null, '{"event_kind":"deal.updated","url":"https://hooks.example.com/three"}') ->> 'id')::uuid id;
select public.webhook_test((select id from t_wh3));
select pg_temp.as_service();
create temp table t_ping as select pg_temp.claim() -> 0 c;
select pg_temp.check((select (c ->> 'body')::jsonb ->> 'event' from t_ping) = 'ping', '«Send test» sends a ping');
select public.worker_webhook_done((select (c ->> 'delivery_id')::uuid from t_ping), null, 5, 'private_address');
select pg_temp.check((select state from app.webhooks where id = (select id from t_wh3)) = 'blocked', 'a public name resolving to a private address blocks the webhook');
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.webhook_set_state((select id from t_wh3), 'active');
select public.webhook_redeliver((select (c ->> 'delivery_id')::uuid from t_ping));
select pg_temp.check((select count(*) from app.webhook_deliveries where webhook_id = (select id from t_wh3) and redelivery = 1 and attempt = 1 and state = 'queued') = 1, 'redeliver queues a fresh attempt 1');
select pg_temp.as_staff('eirik@orgpuls.no');
select pg_temp.expect_detail($$select public.webhook_delete((select id from t_wh3))$$, 'forbidden', 'global:configure', 'another sales user cannot delete the webhook');
select pg_temp.check(jsonb_array_length(public.webhooks_get() -> 'webhooks') = 0, 'and does not see it');
select pg_temp.as_staff('tor@orgpuls.no');
select public.webhook_delete((select id from t_wh3));
select pg_temp.check((select state from app.webhooks where id = (select id from t_wh3)) = 'deleted', 'global:configure may delete any webhook');

-- ===========================================================================
-- the AI connector (MCP-01..03, UF-22): dynamic registration, PKCE, grants, the company switch
-- ===========================================================================
select pg_temp.as_service();
create temp table t_mcp as select public.worker_oauth_register('{"client_name":"Claude","redirect_uris":["https://claude.ai/api/mcp/auth_callback"]}') ->> 'client_id' client_id,
  'verifier-0123456789-0123456789-0123456789-abcdefgh'::text verifier;
select pg_temp.check((select kind = 'mcp' and dynamic and client_secret_sha256 is null from app.oauth_apps where client_id = (select client_id from t_mcp)),
                     'an assistant registers itself as a public client (PKCE)');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.oauth_authorize((select client_id from t_mcp), 'https://evil.example.com/cb', '{*}', app.pkce_s256((select verifier from t_mcp)))$$,
                             'invalid', 'redirect_uri', 'the redirect must match exactly');
select pg_temp.expect_detail($$select public.oauth_authorize((select client_id from t_mcp), 'https://claude.ai/api/mcp/auth_callback', '{*}', app.pkce_s256((select verifier from t_mcp)), 'plain')$$,
                             'invalid', 'code_challenge', 'PKCE is S256 only');
create temp table t_code as select public.oauth_authorize((select client_id from t_mcp), 'https://claude.ai/api/mcp/auth_callback', '{*}', app.pkce_s256((select verifier from t_mcp))) ->> 'code' code;
select pg_temp.check(not exists (select 1 from app.oauth_codes c where to_jsonb(c)::text like '%' || (select code from t_code) || '%'), 'the code is stored as a hash');
select pg_temp.as_service();
select pg_temp.expect_detail($$select public.worker_oauth_token(jsonb_build_object('grant_type', 'authorization_code', 'client_id', (select client_id from t_mcp), 'code', (select code from t_code),
                             'redirect_uri', 'https://claude.ai/api/mcp/auth_callback', 'code_verifier', 'wrong-verifier-0123456789-0123456789-0123'))$$, 'forbidden', 'code', 'a wrong verifier is refused');
create temp table t_grant as select r ->> 'access_token' access, r ->> 'refresh_token' refresh, (r ->> 'grant_id')::uuid id from (
  select public.worker_oauth_token(jsonb_build_object('grant_type', 'authorization_code', 'client_id', (select client_id from t_mcp), 'code', (select code from t_code),
         'redirect_uri', 'https://claude.ai/api/mcp/auth_callback', 'code_verifier', (select verifier from t_mcp))) r) x;
select pg_temp.check((select access is not null and refresh is not null from t_grant)
                     and (select access_sha256 = pg_temp.h((select access from t_grant)) and staff_id = (select ingrid from t_staff) from app.oauth_grants where id = (select id from t_grant)),
                     'the code becomes a grant; tokens stored as hashes');
select pg_temp.expect_detail($$select public.worker_oauth_token(jsonb_build_object('grant_type', 'authorization_code', 'client_id', (select client_id from t_mcp), 'code', (select code from t_code),
                             'redirect_uri', 'https://claude.ai/api/mcp/auth_callback', 'code_verifier', (select verifier from t_mcp)))$$, 'forbidden', 'code', 'a code is used once');
create temp table t_mupd as select public.api_exec(pg_temp.h((select access from t_grant)), 'update', jsonb_build_object('entity', 'deal', 'id', (select id from t_deal),
  'values', jsonb_build_object('title', 'Assistant title'))) r;
select pg_temp.check((select r ->> 'status' from t_mupd) = '200'
                     and (select source from app.changelog where entity = 'deal' and record_id = (select id from t_deal) and field = 'title' order by id desc limit 1) = 'assistant'
                     and (select source = 'mcp' and principal_kind = 'oauth' from app.audit where action = 'record.updated' order by id desc limit 1),
                     'an assistant call runs as the user: changelog source assistant, audit source mcp (UF-22)');
select pg_temp.expect_error($$select public.api_exec(pg_temp.h((select access from t_grant)), 'get', jsonb_build_object('entity', 'deal', 'id', (select id from t_hidden)))$$,
                            'not_found', 'an assistant sees only what its user sees (MCP-01)');
-- refresh rotates both tokens
create temp table t_ref as select public.worker_oauth_token(jsonb_build_object('grant_type', 'refresh_token', 'client_id', (select client_id from t_mcp),
  'refresh_token', (select refresh from t_grant))) r;
select pg_temp.check(public.worker_api_auth(pg_temp.h((select access from t_grant))) is null and public.worker_api_auth(pg_temp.h((select r ->> 'access_token' from t_ref))) is not null,
                     'a refresh rotates the access token');
-- the sync index: CRM records only, visibility at query time
select set_config('app.api_principal', '', true);
select app.mcp_index_refresh();
select pg_temp.check((select count(*) from app.mcp_index) > 0 and not exists (select 1 from app.mcp_index i where i.entity not in (select key from app.entities)),
                     'the index holds CRM records only');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_hidden_title as select title from app.deals where id = (select id from t_hidden);
select pg_temp.check(exists (select 1 from jsonb_array_elements(app.mcp_search((select split_part(title, ' ', 1) from t_hidden_title), 50)) x where (x ->> 'id')::uuid = (select id from t_hidden)),
                     'the owner finds the hidden deal in the index');
select pg_temp.as_service();
create temp table t_find as select public.api_exec(pg_temp.h((select r ->> 'access_token' from t_ref)), 'index_search',
  jsonb_build_object('q', (select split_part(title, ' ', 1) from t_hidden_title), 'limit', 50)) r;
select pg_temp.check((select r ->> 'status' from t_find) = '200'
                     and not exists (select 1 from jsonb_array_elements((select r -> 'body' from t_find)) x where (x ->> 'id')::uuid = (select id from t_hidden)),
                     'the assistant''s index search never returns the hidden deal (SEC-08)');
-- the company switch: off revokes every assistant grant, refuses new ones, and the per-call check holds even for a grant missed
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.mcp_set(false)$$, 'forbidden', 'global:configure', 'sales cannot switch the connector');
select pg_temp.as_staff('tor@orgpuls.no');
select public.mcp_set(false);
select pg_temp.check((select revoke_reason from app.oauth_grants where id = (select id from t_grant)) = 'mcp_off' and app.setting('mcp_access') = 'off'
                     and exists (select 1 from app.events where kind = 'mcp.switched'), 'off revokes the assistant grants (MCP-03)');
select pg_temp.check(public.worker_api_auth(pg_temp.h('sk_live_admintokenforthetestsuite000000')) is not null, 'personal tokens are untouched by the switch');
select pg_temp.as_service();
select pg_temp.expect_error($$select public.api_exec(pg_temp.h((select r ->> 'access_token' from t_ref)), 'list', '{"entity":"deal"}')$$, 'not_signed_in', 'after switch-off no assistant call succeeds');
select pg_temp.expect_detail($$select public.worker_oauth_register('{"client_name":"Other","redirect_uris":["https://x.example.com/cb"]}')$$, 'forbidden', 'mcp_off', 'no assistant registers while off');
select set_config('app.api_principal', '', true);
update app.oauth_grants set revoked_at = null, revoke_reason = null where id = (select id from t_grant);
select pg_temp.as_service();
select pg_temp.check(app.principal_staff('grant:' || (select id from t_grant)) is null, 'a grant the revocation missed still answers no one while mcp_access is off');
select pg_temp.expect_error($$select public.api_exec(pg_temp.h((select r ->> 'access_token' from t_ref)), 'list', '{"entity":"deal"}')$$, 'not_signed_in', 'and api_exec refuses it');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.oauth_authorize((select client_id from t_mcp), 'https://claude.ai/api/mcp/auth_callback', '{*}', app.pkce_s256((select verifier from t_mcp)))$$,
                             'forbidden', 'mcp_off', 'no consent while off');
-- the effect, called directly as the hook would, and the hook's registration with 0043's setting_set
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('mcp_access', 'on');
select pg_temp.check((select hook from app.settings_registry where key = 'mcp_access') = 'app.mcp_access_effect', 'mcp_access''s hook is app.mcp_access_effect');
select app.mcp_access_effect('mcp_access', 'on', 'on', '');
select pg_temp.check((select revoked_at is null from app.oauth_grants where id = (select id from t_grant)), 'switching on revokes nothing');
select app.mcp_access_effect('mcp_access', 'on', 'off', '');
select pg_temp.check((select revoke_reason from app.oauth_grants where id = (select id from t_grant)) = 'mcp_off', 'app.mcp_access_effect revokes on off');
select public.setting_set('mcp_access', 'on');
select pg_temp.check((public.mcp_get() ->> 'access') = 'on' and (public.mcp_get() ->> 'connected')::int = 0
                     and jsonb_array_length(public.mcp_get() -> 'tools') = (select count(*) * 5 + 3 from app.api_entities()), 'the connector reads its state and the generated tool list');
-- mcp_sync in both states
select public.mcp_sync_set(false);
select pg_temp.check((select count(*) from app.mcp_index) = 0, 'sync off empties the index');
select pg_temp.expect_detail($$select app.mcp_search('Lumio', 5)$$, 'not_available', 'mcp_sync', 'the index search is unavailable while sync is off');
select pg_temp.check(app.mcp_index_refresh() = 0, 'the index job does nothing while sync is off');
select public.mcp_sync_set(true);
select pg_temp.check(app.mcp_index_refresh() > 0, 'sync on fills it again');

-- OAuth apps for integrations: configure, a fresh second factor, the secret once; disabling revokes grants
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.oauth_app_save(null, '{"name":"Zapier","redirect_uris":["https://zapier.com/cb"],"allowed_scopes":["deals:read"]}')$$,
                             'forbidden', 'global:configure', 'registering an OAuth app needs global:configure');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.oauth_app_save(null, '{"name":"Zapier","redirect_uris":["https://zapier.com/cb"],"allowed_scopes":["deals:read"]}')$$,
                             'forbidden', 'fresh_mfa', 'and a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.oauth_app_save(null, '{"name":"Zapier","redirect_uris":["http://zapier.com/cb"],"allowed_scopes":["deals:read"]}')$$,
                             'invalid', 'redirect_uris', 'redirects are https');
select pg_temp.expect_detail($$select public.oauth_app_save(null, '{"name":"Zapier","redirect_uris":["https://zapier.com/cb"],"allowed_scopes":["global:security"]}')$$,
                             'invalid', 'allowed_scopes', 'no scope outside the list (never security)');
create temp table t_app as select r ->> 'client_id' client_id, r ->> 'client_secret' secret, (r ->> 'id')::uuid id from (
  select public.oauth_app_save(null, '{"name":"Zapier","redirect_uris":["https://zapier.com/cb"],"allowed_scopes":["deals:read"]}') r) x;
select pg_temp.check((select secret ~ '^cs_' from t_app) and (select client_secret_sha256 = pg_temp.h((select secret from t_app)) from app.oauth_apps where id = (select id from t_app)),
                     'a confidential app''s secret is returned once and stored as a hash');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.oauth_authorize((select client_id from t_app), 'https://zapier.com/cb', '{deals:write}', app.pkce_s256((select verifier from t_mcp)))$$,
                             'invalid', 'scopes', 'a grant cannot ask beyond the app''s scopes');
create temp table t_code2 as select public.oauth_authorize((select client_id from t_app), 'https://zapier.com/cb', '{deals:read}', app.pkce_s256((select verifier from t_mcp))) ->> 'code' code;
select pg_temp.as_service();
select pg_temp.expect_detail($$select public.worker_oauth_token(jsonb_build_object('grant_type', 'authorization_code', 'client_id', (select client_id from t_app), 'code', (select code from t_code2),
                             'redirect_uri', 'https://zapier.com/cb', 'code_verifier', (select verifier from t_mcp)))$$, 'forbidden', 'client', 'a confidential client must send its secret');
create temp table t_zap as select public.worker_oauth_token(jsonb_build_object('grant_type', 'authorization_code', 'client_id', (select client_id from t_app), 'code', (select code from t_code2),
  'redirect_uri', 'https://zapier.com/cb', 'code_verifier', (select verifier from t_mcp), 'client_secret', (select secret from t_app))) r;
select pg_temp.expect_detail($$select public.api_exec(pg_temp.h((select r ->> 'access_token' from t_zap)), 'create', '{"entity":"deal","values":{"title":"x"}}')$$,
                             'forbidden', 'deals:add', 'a deals:read grant cannot create');
select pg_temp.as_staff('tor@orgpuls.no');
select public.oauth_app_disable((select id from t_app));
select pg_temp.as_service();
select pg_temp.check(public.worker_api_auth(pg_temp.h((select r ->> 'access_token' from t_zap))) is null, 'disabling an app revokes its grants at once');

-- ===========================================================================
-- rate limits (INT-03): off by default; source values; custom budget, multiplier and bursts
-- ===========================================================================
select pg_temp.as_service();
select pg_temp.check((public.api_exec(pg_temp.h('sk_live_admintokenforthetestsuite000000'), 'get', jsonb_build_object('entity', 'deal', 'id', (select id from t_deal))) #>> '{rate,limit}') is null,
                     'api_rate off: no limit');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('api_rate', 'source_values');
create temp table t_n as select count(*)::bigint n from app.admins where active and not is_sample;
select pg_temp.as_service();
create temp table t_r1 as select public.api_exec(pg_temp.h('sk_live_admintokenforthetestsuite000000'), 'get', jsonb_build_object('entity', 'deal', 'id', (select id from t_deal))) r;
select pg_temp.check((select (r #>> '{rate,limit}')::bigint = 30000 * (select n from t_n) and (r #>> '{rate,remaining}')::bigint = 30000 * (select n from t_n) - 2 from t_r1),
                     'source values: 30 000 × 1 × active staff a day, a get costs 2 (Part F)');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('api_burst_token', 'custom', '', 2), public.setting_set('api_budget_base', 'custom', '', 100), public.setting_set('api_plan_multiplier', 'custom', '', 2);
select pg_temp.as_service();
select pg_temp.check(app.api_burst_limit('token', 'get') = 20 and app.api_budget() = 30000 * (select n from t_n), 'the custom keys are read only while api_rate is custom');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('api_rate', 'custom', '', null);
select pg_temp.as_service();
select pg_temp.check(app.api_budget() = 100 * 2 * (select n from t_n) and app.api_burst_limit('token', 'get') = 2 and app.api_burst_limit('grant', 'get') = 80
                     and app.api_burst_limit('token', 'search') = 10, 'custom: base × multiplier × seats; burst per token 2, OAuth and search at source values');
delete from app.api_burst;
select public.api_exec(pg_temp.h('sk_live_admintokenforthetestsuite000000'), 'get', jsonb_build_object('entity', 'deal', 'id', (select id from t_deal)));
select public.api_exec(pg_temp.h('sk_live_admintokenforthetestsuite000000'), 'get', jsonb_build_object('entity', 'deal', 'id', (select id from t_deal)));
create temp table t_r3 as select public.api_exec(pg_temp.h('sk_live_admintokenforthetestsuite000000'), 'get', jsonb_build_object('entity', 'deal', 'id', (select id from t_deal))) r;
select pg_temp.check((select r ->> 'status' = '429' and r ->> 'reason' = 'burst' and (r #>> '{rate,remaining}')::int = 0 and r #>> '{rate,reset}' is not null from t_r3),
                     'over the burst: 429 with limit, remaining and reset');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('api_burst_token', 'source_value'), public.setting_set('api_burst_search', 'custom', '', 1), public.setting_set('api_burst_oauth', 'custom', '', 3),
       public.setting_set('api_budget_base', 'custom', '', 1), public.setting_set('api_plan_multiplier', 'source_value');
select pg_temp.as_service();
select pg_temp.check(app.api_burst_limit('token', 'search') = 1 and app.api_burst_limit('grant', 'list') = 3, 'custom search and OAuth bursts');
delete from app.api_burst;
delete from app.api_budget_day;
create temp table t_r4 as select public.api_exec(pg_temp.h('sk_live_admintokenforthetestsuite000000'), 'list', '{"entity":"deal"}') r;
select pg_temp.check((select r ->> 'status' = '429' and r ->> 'reason' = 'budget' from t_r4) = ((select n from t_n) < 20), 'over the day''s budget: 429');
select pg_temp.check(((select n from t_n) >= 20) or exists (select 1 from app.notifications where key = 'api.budget_warning' and params ->> 'percent' = '100'
                                                                  and staff_id = (select tor from t_staff)), 'global:configure is told once when the budget is reached');
select set_config('app.api_principal', '', true);
select public.worker_api_usage(jsonb_build_array(jsonb_build_object('principal_kind', 'token', 'principal_id', (select id from app.api_tokens where name = 'Admin'), 'requests', 7, 'cost', 14)));
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select sum((x ->> 'requests')::int) from jsonb_array_elements(public.api_overview() -> 'usage') x) >= 7 and (public.api_overview() ->> 'usage_scope') = 'company',
                     'the gateway''s usage feeds the 24-hour chart');
select public.setting_set('api_rate', 'off');

-- ===========================================================================
-- offline sync (SF-31, MOB-05): idempotent mutation ids, latest change wins, the earlier value kept, refusals rejected
-- ===========================================================================
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_dev as select gen_random_uuid() dev, gen_random_uuid() m1, gen_random_uuid() m2, gen_random_uuid() m3, gen_random_uuid() m4, gen_random_uuid() m5,
  gen_random_uuid() m6, gen_random_uuid() m7, gen_random_uuid() m8;
create temp table t_v as select version v from app.deals where id = (select id from t_deal);
create temp table t_s1 as select public.sync_apply((select dev from t_dev), jsonb_build_array(jsonb_build_object('mutation_id', (select m1 from t_dev), 'op', 'update', 'entity', 'deal',
  'record_id', (select id from t_deal), 'base_version', (select v from t_v), 'fields', jsonb_build_object('value', 64000), 'client_at', now()))) r;
select pg_temp.check((select r -> 'results' -> 0 ->> 'result' from t_s1) = 'applied' and (select value from app.deals where id = (select id from t_deal)) = 64000
                     and (select source from app.changelog where entity = 'deal' and record_id = (select id from t_deal) and field = 'value' order by id desc limit 1) = 'mobile',
                     'a mutation at the base version applies through rec_save; the changelog says mobile');
create temp table t_v2 as select version v from app.deals where id = (select id from t_deal);
create temp table t_s2 as select public.sync_apply((select dev from t_dev), jsonb_build_array(jsonb_build_object('mutation_id', (select m1 from t_dev), 'op', 'update', 'entity', 'deal',
  'record_id', (select id from t_deal), 'base_version', (select v from t_v), 'fields', jsonb_build_object('value', 64000), 'client_at', now()))) r;
select pg_temp.check((select (r -> 'results' -> 0 ->> 'replayed')::boolean and r -> 'results' -> 0 ->> 'result' = 'applied' from t_s2)
                     and (select version from app.deals where id = (select id from t_deal)) = (select v from t_v2), 'a retried mutation id returns its stored result and changes nothing');
-- a change made on the web after the device's: the device's is superseded and gets the current row
select public.rec_save('deal', (select id from t_deal), '{"value": 70000}');
create temp table t_s3 as select public.sync_apply((select dev from t_dev), jsonb_build_array(jsonb_build_object('mutation_id', (select m2 from t_dev), 'op', 'update', 'entity', 'deal',
  'record_id', (select id from t_deal), 'base_version', (select v from t_v2), 'fields', jsonb_build_object('value', 50000), 'client_at', now() - interval '1 hour'))) r;
select pg_temp.check((select r -> 'results' -> 0 ->> 'result' = 'superseded' and (r -> 'results' -> 0 -> 'current' ->> 'value')::numeric = 70000 from t_s3)
                     and (select value from app.deals where id = (select id from t_deal)) = 70000, 'an older device change is superseded and the current row returned');
-- the device's change is later: it wins, and the web's value stays in the changelog
update app.deals set updated_at = now() - interval '10 minutes' where id = (select id from t_deal);
create temp table t_s4 as select public.sync_apply((select dev from t_dev), jsonb_build_array(jsonb_build_object('mutation_id', (select m3 from t_dev), 'op', 'update', 'entity', 'deal',
  'record_id', (select id from t_deal), 'base_version', (select v from t_v2), 'fields', jsonb_build_object('value', 55000), 'client_at', now() - interval '1 minute'))) r;
select pg_temp.check((select r -> 'results' -> 0 ->> 'result' = 'applied' and (r -> 'results' -> 0 ->> 'conflict')::boolean from t_s4)
                     and (select value from app.deals where id = (select id from t_deal)) = 55000
                     and (select old_value = '70000'::jsonb from app.changelog where entity = 'deal' and record_id = (select id from t_deal) and field = 'value' order by id desc limit 1),
                     'latest change wins; the earlier value is kept in the changelog');
-- a fast device clock never wins by itself
update app.deals set updated_at = now() where id = (select id from t_deal);
create temp table t_s5 as select public.sync_apply((select dev from t_dev), jsonb_build_array(jsonb_build_object('mutation_id', (select m4 from t_dev), 'op', 'update', 'entity', 'deal',
  'record_id', (select id from t_deal), 'base_version', (select v from t_v2), 'fields', jsonb_build_object('value', 1), 'client_at', now() + interval '1 day'))) r;
select pg_temp.check((select r -> 'results' -> 0 ->> 'result' from t_s5) = 'superseded', 'a device clock ahead of the server counts as now');
-- refusals, notes, done, stage moves, creates
create temp table t_s6 as select public.sync_apply((select dev from t_dev), jsonb_build_array(
  jsonb_build_object('mutation_id', (select m5 from t_dev), 'op', 'update', 'entity', 'deal', 'record_id', (select id from t_hidden), 'fields', '{"value": 1}'::jsonb),
  jsonb_build_object('mutation_id', (select m6 from t_dev), 'op', 'update', 'entity', 'deal', 'record_id', (select id from t_deal), 'fields', '{"seq": 1}'::jsonb),
  jsonb_build_object('mutation_id', (select m7 from t_dev), 'op', 'note', 'entity', 'deal', 'record_id', (select id from t_deal), 'fields', '{"body": "Notert på telefonen"}'::jsonb),
  jsonb_build_object('mutation_id', (select m8 from t_dev), 'op', 'create', 'entity', 'activity', 'fields',
                     jsonb_build_object('type_id', (select id from app.activity_types where key = 'call'), 'subject', 'Offline call', 'deal_id', (select id from t_deal))))) r;
select pg_temp.check((select r -> 'results' -> 0 ->> 'result' = 'rejected' and r -> 'results' -> 0 ->> 'error' = 'not_found'
                             and r -> 'results' -> 1 ->> 'result' = 'rejected' and r -> 'results' -> 1 ->> 'error' = 'invalid' and r -> 'results' -> 1 ->> 'detail' = 'seq'
                             and r -> 'results' -> 2 ->> 'result' = 'applied' and r -> 'results' -> 3 ->> 'result' = 'applied'
                             and (r ->> 'applied')::int = 2 and (r ->> 'rejected')::int = 2 from t_s6), 'refusals are rejected with their code; the rest of the batch applies');
select pg_temp.check(exists (select 1 from app.notes where entity = 'deal' and record_id = (select id from t_deal) and body = 'Notert på telefonen')
                     and (select c.source from app.activities a join app.changelog c on c.entity = 'activity' and c.record_id = a.id and c.field = '*created' where a.subject = 'Offline call') = 'mobile',
                     'an offline note and an offline activity arrive');
select pg_temp.check((select source = 'mobile' and detail ->> 'applied' = '2' from app.audit where action = 'sync.applied' order by id desc limit 1), 'the batch is audited with source mobile, counts only');
create temp table t_s7 as select public.sync_apply((select dev from t_dev), jsonb_build_array(
  jsonb_build_object('mutation_id', gen_random_uuid(), 'op', 'activity_done', 'record_id', (select a.id from app.activities a where a.subject = 'Offline call')),
  jsonb_build_object('mutation_id', gen_random_uuid(), 'op', 'stage_move', 'record_id', (select id from t_deal),
                     'fields', jsonb_build_object('stage_id', (select s.id from app.stages s join app.deals d on d.pipeline_id = s.pipeline_id where d.id = (select id from t_deal) and s.id <> d.stage_id order by s.ord limit 1))))) r;
select pg_temp.check((select r -> 'results' -> 0 ->> 'result' = 'applied' and r -> 'results' -> 1 ->> 'result' = 'applied' from t_s7)
                     and (select done from app.activities where subject = 'Offline call')
                     and (select source from app.deal_stage_history where deal_id = (select id from t_deal) order by id desc limit 1) = 'mobile', 'done and a stage move sync as mobile');
select pg_temp.expect_detail($$select public.sync_apply(gen_random_uuid(), (select jsonb_agg(jsonb_build_object('mutation_id', gen_random_uuid(), 'op', 'note')) from generate_series(1, 201)))$$,
                             'invalid', 'mutations', 'at most 200 mutations a call');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.sync_changes((select max(id) - 50 from app.events), 200) -> 'changes') x where (x ->> 'id')::uuid = (select id from t_deal))
                     and not exists (select 1 from jsonb_array_elements(public.sync_changes(0, 500) -> 'changes') x where (x ->> 'id')::uuid = (select id from t_hidden)),
                     'the pull lists what changed that the device may see');
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('mobile', false);
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.sync_apply(gen_random_uuid(), '[]')$$, 'module_off', 'mobile', 'the mobile module off turns sync off');
select pg_temp.as_staff('tor@orgpuls.no');
select public.module_set('mobile', true);

-- ===========================================================================
-- the sandbox loader (R-SETTINGS-03, CUS-08): only sample rows, never a live one
-- ===========================================================================
create temp table t_live as
  select e.key, x.n, x.sig from app.entities e,
  lateral (select null::bigint n, null::text sig) x where false;
do $$
declare e app.entities; v_n bigint; v_sig text;
begin
  for e in select * from app.entities loop
    execute format('select count(*), md5(coalesce(string_agg(t.id::text || '':'' || t.version || '':'' || coalesce(t.deleted_at::text, ''''), '','' order by t.id), '''')) from app.%I t where not t.is_sample', e.tbl)
      into v_n, v_sig;
    insert into t_live values (e.key, v_n, v_sig);
  end loop;
end $$;
create temp table t_live_notes as select count(*) n, md5(coalesce(string_agg(id::text, ',' order by id), '')) sig from app.notes where not is_sample;
select pg_temp.as_staff('tor@orgpuls.no');
select public.sandbox_set(true);
create temp table t_old_sample as select (public.rec_save('organization', null, '{"name":"Gammel prøve AS"}') ->> 'id')::uuid id;
select public.sandbox_set(false);
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.sandbox_reset()$$, 'forbidden', 'global:configure', 'sales cannot reset the sandbox');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_reset as select public.sandbox_reset() r;
do $$
declare e app.entities; v_n bigint; v_sig text;
begin
  for e in select * from app.entities loop
    execute format('select count(*), md5(coalesce(string_agg(t.id::text || '':'' || t.version || '':'' || coalesce(t.deleted_at::text, ''''), '','' order by t.id), '''')) from app.%I t where not t.is_sample', e.tbl)
      into v_n, v_sig;
    if not exists (select 1 from t_live l where l.key = e.key and l.n = v_n and l.sig = v_sig) then raise exception 'FAIL sandbox_reset touched live % rows', e.key; end if;
  end loop;
end $$;
select pg_temp.check(exists (select 1 from t_live_notes l, (select count(*) n, md5(coalesce(string_agg(id::text, ',' order by id), '')) sig from app.notes where not is_sample) x
                            where l.n = x.n and l.sig = x.sig),
                     'sandbox_reset leaves every live record, version and note exactly as it was');
select pg_temp.check(not exists (select 1 from app.organizations where id = (select id from t_old_sample)), 'an earlier sample record is cleared');
select pg_temp.check((select count(*) from app.organizations where is_sample and name = 'Lumio AS') = 1 and (select count(*) from app.people where is_sample and name = 'Kari Nordmann') = 1
                     and (select count(*) from app.deals where is_sample and title = 'Lumio AS — Expansion to Skiftly' and value = 64000) = 1
                     and (select count(*) from app.activities where is_sample) = 2 and (select count(*) from app.leads where is_sample) = 1
                     and (select count(*) from app.notes where is_sample) = 1, 'the demo tenant is loaded, every row a sample');
select pg_temp.check(exists (select 1 from app.audit where action = 'sandbox.reset') and (public.sandbox_counts() ->> 'last_reset') is not null
                     and (public.sandbox_counts() ->> 'organization')::int = 1, 'the reset is audited with counts and sandbox_counts reports it');
select public.sandbox_reset();
select pg_temp.check((select count(*) from app.organizations where is_sample) = 1, 'a second reset replaces the samples rather than adding to them');

-- ===========================================================================
-- revertable bulk changes (Contacts R-6)
-- ===========================================================================
create temp table t_orgs as select (public.rec_save('organization', null, jsonb_build_object('name', 'Bulk ' || i, 'industry', 'Retail')) ->> 'id')::uuid id, i
  from generate_series(1, 3) i;
create temp table t_bulk as select public.rec_bulk('organization', (select array_agg(id order by i) from t_orgs), '{"industry":"Energy","city":"Bergen"}') r;
select pg_temp.check((select (r ->> 'updated')::int = 3 and r ->> 'change_id' is not null from t_bulk)
                     and (select count(*) from app.bulk_change_items where change_id = (select (r ->> 'change_id')::uuid from t_bulk) and before = '{"industry":"Retail","city":null}'::jsonb) = 3,
                     'a bulk change records each record''s touched values before');
select public.rec_save('organization', (select id from t_orgs where i = 2), '{"industry":"Shipping"}');
create temp table t_rev as select public.bulk_change_revert((select (r ->> 'change_id')::uuid from t_bulk)) r;
select pg_temp.check((select (r ->> 'reverted')::int = 2 and (r ->> 'stale')::int = 1 from t_rev)
                     and (select industry = 'Retail' and city is null from app.organizations where id = (select id from t_orgs where i = 1))
                     and (select industry from app.organizations where id = (select id from t_orgs where i = 2)) = 'Shipping'
                     and (select outcome from app.bulk_change_items where record_id = (select id from t_orgs where i = 2)) = 'stale',
                     'revert restores the before-values and refuses a row changed since');
select pg_temp.expect_detail($$select public.bulk_change_revert((select (r ->> 'change_id')::uuid from t_bulk))$$, 'invalid', 'reverted', 'a change is reverted once');
select pg_temp.check((public.bulk_changes_get('organization') -> 0 ->> 'reverted_at') is not null, 'the Restore tab lists it as reverted');
select pg_temp.expect_error($$update app.bulk_change_items set before = '{}' where change_id = (select (r ->> 'change_id')::uuid from t_bulk)$$,
                            'a bulk change item cannot be changed', 'what a bulk change recorded cannot be changed');
select set_config('app.purging', '', true);   -- sandbox_reset above purged within this transaction
select pg_temp.expect_error($$delete from app.bulk_change_items where change_id = (select (r ->> 'change_id')::uuid from t_bulk)$$,
                            'a bulk change item is kept with its change', 'an item cannot be deleted on its own');
delete from app.bulk_changes where id = (select (r ->> 'change_id')::uuid from t_bulk);
select pg_temp.check(not exists (select 1 from app.bulk_change_items where change_id = (select (r ->> 'change_id')::uuid from t_bulk)),
                     'the cascade from its change still removes the items (referential maintenance)');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.rec_bulk('organization', (select array_agg(id) from t_orgs), '{"city":"Oslo"}')$$, 'forbidden', 'deals:bulk', 'bulk still needs its right');

-- ===========================================================================
-- notifications (MOB-07): an assignment once, chat requests, push to devices
-- ===========================================================================
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((public.push_devices_get() ->> 'push_ready')::boolean = false, 'push is not connected until the VAPID key is in Vault');
select pg_temp.expect_detail($$select public.push_device_register('http://push.example.com/x', repeat('a', 60), repeat('b', 20))$$, 'invalid', 'endpoint', 'a push endpoint is https');
create temp table t_pd as select (public.push_device_register('https://fcm.googleapis.com/fcm/send/abc123', repeat('a', 60), repeat('b', 22), 'Pixel') ->> 'id')::uuid id;
select pg_temp.check(public.push_devices_get()::text not like '%fcm.googleapis.com%', 'the endpoint is never returned');
select app.notify((select ingrid from t_staff), 'system', 'test.no_push', '{}'::jsonb);
select pg_temp.check(not exists (select 1 from app.push_deliveries where device_id = (select id from t_pd)), 'without a VAPID key nothing is pushed');
select vault.create_secret('test-vapid-private-key', 'vapid_private_key', 'test');
select set_config('app.event_id', 'e424242', true);
select app.notify((select ingrid from t_staff), 'system', 'assignment.assigned', '{"workflow":"Inbound — large orgs"}'::jsonb, '/leads', 'lead', (select id from app.leads limit 1));
select app.notify((select ingrid from t_staff), 'system', 'assignment.assigned', '{"workflow":"Inbound — large orgs"}'::jsonb, '/leads', 'lead', (select id from app.leads limit 1));
select set_config('app.event_id', '', true);
select pg_temp.check((select count(*) from app.notifications where staff_id = (select ingrid from t_staff) and key = 'assignment.assigned' and dedupe_key like 'assignment:e424242:%') = 1
                     and (select kind from app.notifications where dedupe_key like 'assignment:e424242:%') = 'assignment', 'an assignment handled twice is one notification of kind assignment');
select pg_temp.check((select count(*) from app.push_deliveries pd join app.notifications n on n.id = pd.notification_id where n.dedupe_key like 'assignment:e424242:%') = 1,
                     'and one push per device (MOB-07)');
select public.notification_prefs_set('system', '{in_app}');
select pg_temp.expect_detail($$select public.notification_prefs_set('system', '{push}')$$, 'invalid', 'channels', 'in-app cannot be switched off');
select app.notify((select ingrid from t_staff), 'system', 'test.pref_off', '{}'::jsonb);
select pg_temp.check(not exists (select 1 from app.push_deliveries pd join app.notifications n on n.id = pd.notification_id where n.key = 'test.pref_off'), 'a kind without push is not pushed');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('push_notifications', 'off');
select app.notify((select ingrid from t_staff), 'mention', 'test.setting_off', '{}'::jsonb);
select pg_temp.check(not exists (select 1 from app.push_deliveries pd join app.notifications n on n.id = pd.notification_id where n.key = 'test.setting_off'), 'push_notifications off: nothing pushed');
select public.setting_set('push_notifications', 'on');
select app.notify((select ingrid from t_staff), 'mention', 'test.setting_on', '{}'::jsonb);
select pg_temp.check(exists (select 1 from app.push_deliveries pd join app.notifications n on n.id = pd.notification_id where n.key = 'test.setting_on'), 'push_notifications on: pushed');
select pg_temp.as_service();
create temp table t_push as select public.worker_push_claim(100) r;
select pg_temp.check((select r -> 0 ->> 'endpoint' from t_push) = 'https://fcm.googleapis.com/fcm/send/abc123' and (public.worker_vapid_key() ->> 'private_key') = 'test-vapid-private-key',
                     'the push worker gets the endpoint, keys and the VAPID key');
select public.worker_push_done((select (r -> 0 ->> 'notification_id')::uuid from t_push), (select id from t_pd), 410);
select pg_temp.check((select revoked_at is not null from app.push_devices where id = (select id from t_pd)), 'a 410 from the push service revokes the device');
-- a chat waiting for a person reaches the staff online for chat (kind chat_request)
insert into app.chat_presence (staff_id, online_until) values ((select ingrid from t_staff), now() + interval '2 minutes') on conflict (staff_id) do update set online_until = excluded.online_until;
insert into app.chat_conversations (visitor_token_sha256, page_path) values (extensions.digest('visitor-test', 'sha256'), '/pris?utm=x');
update app.chat_conversations set state = 'queued', queued_at = now() where visitor_token_sha256 = extensions.digest('visitor-test', 'sha256');
select pg_temp.check((select kind = 'chat_request' and params ->> 'page' = '/pris' from app.notifications where staff_id = (select ingrid from t_staff) and key = 'chat.requested'),
                     'a queued chat notifies staff online for chat, once, with the page path only');

-- ===========================================================================
-- the job monitor: every schedule through app.run_job; failures alert once; retry
-- ===========================================================================
select pg_temp.check(not exists (select 1 from cron.job where (jobname like 'platform-%' or jobname like 'security-%') and jobname <> 'security-backup-poll'
                                 and command not like 'select app.run_job(%')
                     and exists (select 1 from cron.job where jobname = 'platform-purge' and command = 'select app.run_job(''purge'')')
                     and exists (select 1 from cron.job where jobname = 'security-alerts' and command = 'select app.run_job(''security_alerts'')')
                     and exists (select 1 from cron.job where jobname = 'platform-webhook-sweep'), 'every platform and security schedule runs through app.run_job, names unchanged');
select pg_temp.check(not exists (select 1 from app.job_defs d where d.source = 'cron' and not exists (
                       select 1 from pg_proc p where p.pronamespace = 'app'::regnamespace and 'app.' || p.proname = d.fn and p.pronargs = p.pronargdefaults)),
                     'every scheduled job names a function that exists and takes no argument');
create temp table t_run as select app.run_job('mcp_index') id;
select pg_temp.check((select state = 'succeeded' and (info ->> 'count')::int >= 0 from app.job_runs where id = (select id from t_run)), 'a run is recorded with counts only');
select pg_temp.check(app.run_job('api_burst_prune') is null or true, 'a quiet job that found nothing writes no row');
select pg_temp.check(not exists (select 1 from app.job_runs where job_key = 'api_burst_prune' and (info ->> 'count')::int = 0), 'no empty rows for every-minute jobs');
insert into app.job_defs (key, label_key, schedule, source, fn) values ('broken', 'jobs.broken', '0 0 * * *', 'cron', 'app.not_a_function');
create temp table t_fail as select app.run_job('broken') id;
select pg_temp.check((select state = 'failed' and error like '42883%' from app.job_runs where id = (select id from t_fail))
                     and (select count(*) from app.notifications where key = 'job.failed' and params ->> 'job' = 'broken' and staff_id = (select tor from t_staff)) = 1
                     and exists (select 1 from app.events where kind = 'job.failed' and payload ->> 'job' = 'broken'), 'a failure is recorded, global:configure is told, job.failed emitted');
select app.run_job('broken');
select pg_temp.check((select count(*) from app.notifications where key = 'job.failed' and params ->> 'job' = 'broken' and staff_id = (select tor from t_staff)) = 1,
                     'a failure streak alerts once');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.job_retry((select id from t_fail))$$, 'forbidden', 'global:configure', 'sales cannot retry');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_retry as select public.job_retry((select id from t_fail)) r;
select pg_temp.check((select retry_of = (select id from t_fail) and state = 'failed' from app.job_runs where id = (select (r ->> 'run')::bigint from t_retry))
                     and exists (select 1 from app.audit where action = 'job.retried'), 'a retry runs again, linked to the failed run, audited');
select pg_temp.as_service();
select public.worker_job_run('webhook_send', 'succeeded', '{"sent": 3, "host": "x.example.com"}');
select pg_temp.check((select info from app.job_runs where job_key = 'webhook_send' order by id desc limit 1) = '{"sent": 3}'::jsonb, 'a worker''s run keeps counts, never text');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((public.jobs_get() -> 'stats' ->> 'failed_24h')::int >= 2 and jsonb_array_length(public.jobs_get() -> 'jobs') = (select count(*) from app.job_defs),
                     'the monitor counts from job_runs and lists every job (read-only staff with global:see)');

-- ===========================================================================
-- applications (§1.1): health from integration_calls, the ping, connecting with an intake bound to the product
-- ===========================================================================
select pg_temp.as_service();
select public.worker_integration_call((select jsonb_agg(jsonb_build_object('product', 'orgpuls', 'direction', 'out', 'kind', 'orgs.list', 'duration_ms', 100 + i, 'ok', true, 'status', 200))
                                       from generate_series(1, 30) i));
select public.worker_application_ping('orgpuls', true, 87, 200, 'v2.14.0');
insert into app.events_in (product, source_id, kind, tenant_id, payload, occurred_at) values ('orgpuls', 9999001, 'usage.daily', null, '{}', now());
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((select x -> 'health' ->> 'status' = 'operational' and (x -> 'health' ->> 'calls_15m')::int = 31 and (x -> 'health' ->> 'calls_per_min')::numeric = 2.1
                      and jsonb_array_length(x -> 'spark') = 24 from jsonb_array_elements(public.applications_get()) x where x ->> 'key' = 'orgpuls'), 'Orgpuls is operational: calls per minute and p95 from integration_calls');
select pg_temp.as_service();
select public.worker_integration_call('[{"product":"orgpuls","direction":"out","kind":"orgs.get","duration_ms":900,"ok":false,"status":504,"error_code":"timeout"}]');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((select x -> 'health' ->> 'status' from jsonb_array_elements(public.applications_get()) x where x ->> 'key' = 'orgpuls') = 'degraded', 'over 1.5 % errors is degraded');
select pg_temp.as_service();
select public.worker_application_ping('orgpuls', false, 10000, 504);
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((select x -> 'health' ->> 'status' from jsonb_array_elements(public.applications_get()) x where x ->> 'key' = 'orgpuls') = 'unreachable', 'a failed ping is unreachable');
select pg_temp.check((public.application_get('orgpuls') -> 'connection' ->> 'api_version') = 'v2.14.0' and jsonb_array_length(public.application_get('orgpuls') -> 'commands') = 35
                     and public.application_get('orgpuls')::text not like '%decrypted%', 'one application: version from the ping, the 35 commands, secrets as booleans only');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.application_connect('{"key":"vaktbok"}')$$, 'forbidden', 'fresh_mfa', 'connecting needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
create temp table t_conn as select public.application_connect('{"key":"vaktbok","name":"Vaktbok","api_url":"https://api.vaktbok.no","public_key":"pk_test_0123456789abcdefghij",
  "region":"EU · Frankfurt","scopes":["orgs:read"],"stage":"beta"}') r;
select pg_temp.check((select r ->> 'product' = 'vaktbok' and r ->> 'intake_code' ~ '^[0-9a-f]{48}$' from t_conn)
                     and (select not enabled and scopes = '{orgs:read}' from app.installations where product = 'vaktbok') and (select stage from app.products where key = 'vaktbok') = 'beta',
                     'connecting creates the product, a disabled installation and an intake code bound to it — no secret typed by a person');
select pg_temp.as_service();
select pg_temp.expect_detail($$select public.store_product_secrets((select r ->> 'intake_code' from t_conn), '{"orgpuls_webhook_secret":"0123456789012345678901234567890123"}')$$,
                             'invalid', 'name', 'an intake bound to vaktbok cannot store Orgpuls'' secret');
select pg_temp.check((public.store_product_secrets((select r ->> 'intake_code' from t_conn), '{"vaktbok_token_secret":"0123456789012345678901234567890123",
                      "vaktbok_webhook_secret":"abcdefghij0123456789012345678901234"}') ->> 'ok')::boolean, 'the bound intake stores the product''s two secrets');
select pg_temp.check((select enabled from app.installations where product = 'vaktbok'), 'the installation is enabled once both secrets are there');
select pg_temp.check(public.store_product_secrets((select r ->> 'intake_code' from t_conn), '{"vaktbok_token_secret":"x"}') ->> 'error' = 'unauthorized', 'an intake code is used once');
select pg_temp.expect_detail($$select public.store_product_secrets(app.open_product_intake('vaktbok'), '{"vaktbok_token_secret":"9999999999999999999999999999999999"}')$$,
                             'forbidden', 'exists', 'a bound intake never overwrites a secret');

-- ===========================================================================
-- the catalog (INT-05..11, AIA-06)
-- ===========================================================================
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((select (x ->> 'match')::boolean from jsonb_array_elements(public.integration_catalog_get('send invoices when a deal is won') -> 'items') x where x ->> 'key' = 'acc')
                     and not (select (x ->> 'match')::boolean from jsonb_array_elements(public.integration_catalog_get('send invoices when a deal is won') -> 'items') x where x ->> 'key' = 'slack'),
                     'a described need finds the accounting entry');
select pg_temp.check(jsonb_array_length(public.integration_catalog_get() -> 'items') = 8 and not exists (select 1 from jsonb_array_elements(public.integration_catalog_get() -> 'items') x where (x ->> 'installed')::boolean),
                     'eight entries, none installed by default (the design''s «installed» is fabricated)');
select pg_temp.expect_detail($$select public.integration_install('acc')$$, 'forbidden', 'global:configure', 'installing needs global:configure');
select pg_temp.expect_detail($$select public.integration_recommend('send invoices')$$, 'not_connected', 'ai', 'recommendations need the AI provider');
select pg_temp.as_service();
select pg_temp.check(public.worker_integration_validate('["acc","made_up","slack","acc","gw","teams"]') = '["acc","slack","gw"]'::jsonb, 'the model''s answer keeps catalog keys only, at most three');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.integration_install('acc') ->> 'connect_required') = 'accounting', 'installing a company connector asks for its connection');
update app.integration_connections set status = 'connected', connected_by = (select tor from t_staff), connected_at = now(),
  vault_secret_id = vault.create_secret('accounting-token', 'integration:accounting:test', 'test') where provider = 'accounting';
select pg_temp.check((public.integration_remove('acc') -> 'preview' ->> 'company_connection')::boolean, 'removing shows a preview first');
select pg_temp.expect_detail($$select public.integration_remove('acc', 'wrong')$$, 'invalid', 'confirm', 'the confirmation is the key');
select public.integration_remove('acc', 'acc');
select pg_temp.check((select status = 'not_connected' and vault_secret_id is null from app.integration_connections where provider = 'accounting')
                     and not exists (select 1 from vault.secrets where name = 'integration:accounting:test')
                     and exists (select 1 from app.events where kind = 'integration.removed'), 'removing revokes access: the Vault secret goes, the connection is not connected (INT-11)');
select public.integration_install('gw');
update app.mailboxes set status = 'synced', vault_secret_id = vault.create_secret('gmail-token', 'mailbox:test', 'test')
where id = (select id from app.mailboxes where provider = 'google' and owner_id is not null and deleted_at is null limit 1);
create temp table t_mb as select id, owner_id from app.mailboxes where status = 'synced' and provider = 'google' limit 1;
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.integration_users('gw')) x where (x ->> 'staff_id')::uuid = (select owner_id from t_mb)), 'the users of an integration are listed');
select public.integration_user_revoke('gw', (select owner_id from t_mb));
select pg_temp.check((select status = 'disconnected' and vault_secret_id is null from app.mailboxes where id = (select id from t_mb))
                     and not exists (select 1 from vault.secrets where name = 'mailbox:test'), 'one person''s access is revoked');

-- ===========================================================================
-- status banner and flags (§1.7)
-- ===========================================================================
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.status_notice_set('orgpuls', 'Planlagt vedlikehold', null, true, 'orgpuls')$$, 'not_available', 'maintenance',
                             'maintenance mode waits for the product command (D-40)');
create temp table t_prob as select id from app.tickets where type = 'problem' and deleted_at is null limit 1;
create temp table t_notice as select (public.status_notice_set('orgpuls', 'Noen invitasjoner kommer forsinket frem.', (select id from t_prob)) ->> 'id')::uuid id;
select pg_temp.check((public.status_notice_get('orgpuls') -> 'current' ->> 'id')::uuid = (select id from t_notice)
                     and exists (select 1 from app.events where kind = 'status_notice.changed'), 'the banner is set through settings.set_notice and kept in the history');
update app.tickets set problem_status = 'resolved' where id = (select id from t_prob);
select pg_temp.check(app.status_notices_due() = 1, 'the job finds the notice of a resolved problem');
select pg_temp.check((public.status_notice_get('orgpuls') -> 'current') = 'null'::jsonb, 'a resolved problem clears its banner (Tickets R-4)');
select pg_temp.check((select (x ->> 'flags_command')::boolean from jsonb_array_elements(public.flags_get() -> 'products') x where x ->> 'key' = 'orgpuls')
                     and jsonb_array_length(public.flags_get() -> 'modules') = (select count(*) from app.modules), 'flags: the module switches and the product''s flag command');
select pg_temp.check((public.content_get('orgpuls') -> 'cards' -> 'question_set' ->> 'command') is null and (public.content_get('orgpuls') -> 'cards' -> 'legal' ->> 'command') = 'legal.reviews',
                     'content: cards without a product command have no figure');

-- ===========================================================================
-- the API definition (INT-01, MCP-02): generated from the registry
-- ===========================================================================
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_def as select public.api_definition() d;
select pg_temp.check((select d ->> 'openapi' = '3.1.0' and d -> 'paths' ? '/persons' and d -> 'paths' ? '/activities/{id}' and d -> 'paths' ? '/leads/{id}/convert'
                             and not (d -> 'paths' ? '/email_threads') from t_def)
                     and (select count(*) from app.api_entities() e where not ((select d -> 'components' -> 'schemas' from t_def) ? e.key)) = 0,
                     'every record type is in the OpenAPI document (mail threads excepted)');
select pg_temp.check((select (d #>> '{paths,/deals,get,x-cost}')::int = 20 and (d #>> '{paths,/search,get,x-cost}')::int = 40 and (d -> 'paths' -> '/deals/{id}' -> 'get' ->> 'x-cost')::int = 2 from t_def),
                     'costs are Part F''s (list 20, search 40, get 2)');
select pg_temp.check((select bool_and(t ? 'name' and t ? 'input_schema') and count(*) filter (where t ->> 'name' = 'convert_lead_to_deal') = 1
                      from jsonb_array_elements((select d -> 'tools' from t_def)) t), 'every tool has a name and a schema; convert_lead_to_deal is one (D-42)');
select pg_temp.as_staff('tor@orgpuls.no');
select public.field_save(null, '{"entity":"deal","key":"api_probe","label":"API probe","type":"text"}');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(public.api_definition() #> '{components,schemas,deal,properties,custom,properties}' ? 'api_probe', 'a new custom field appears in the definition');

-- ===========================================================================
-- mobile views (MOB-02, MOB-03, MOB-06, AIA-07)
-- ===========================================================================
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_focus as select public.mobile_focus() f;
select pg_temp.check((select (f ->> 'overdue_activities')::int from t_focus)
                     = (public.activities_get(jsonb_build_object('owner_ids', jsonb_build_array((select ingrid from t_staff)))) -> 'counts' ->> 'overdue')::int,
                     'Focus counts overdue activities with the web list''s own filter (MOB-02)');
select pg_temp.check((select (f ->> 'deals_past_close')::int from t_focus) = (select count(*) from app.deals d where d.owner_id = (select ingrid from t_staff) and d.status = 'open'
                       and d.deleted_at is null and d.archived_at is null and not d.is_sample and d.expected_close_date < (now() at time zone 'Europe/Oslo')::date),
                     'Focus counts deals past their close date');
select pg_temp.check((select f ->> 'nearby_10km' is null from t_focus), 'without the device''s position there is no nearby count');
-- places: a geocoded organisation near the device; the hidden one stays hidden
create temp table t_geo as select o.id from app.organizations o where o.owner_id = (select ingrid from t_staff) and o.deleted_at is null and not o.is_sample and o.visibility = 'all' limit 1;
update app.organizations set visibility = 'owner' where id = (select organization_id from app.deals where id = (select id from t_hidden)) and owner_id = (select tor from t_staff);
create temp table t_geo_hidden as select o.id from app.organizations o where o.owner_id = (select tor from t_staff) and o.visibility = 'owner' and o.deleted_at is null limit 1;
select pg_temp.as_service();
select public.worker_geocode_done('organization', (select id from t_geo), 'address', 59.9550, 11.0490);
insert into app.organizations (name, owner_id, visibility) select 'Skjult Nabo AS', (select tor from t_staff), 'owner' where not exists (select 1 from t_geo_hidden);
select public.worker_geocode_done('organization', coalesce((select id from t_geo_hidden), (select id from app.organizations where name = 'Skjult Nabo AS')), 'address', 59.9560, 11.0500);
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_near as select public.nearby(59.9561, 11.0485, 10, array['organization', 'person'], '{}') n;
select pg_temp.check(exists (select 1 from jsonb_array_elements((select n from t_near)) x where (x ->> 'id')::uuid = (select id from t_geo) and (x ->> 'km')::numeric < 1)
                     and not exists (select 1 from jsonb_array_elements((select n from t_near)) x where x ->> 'title' = 'Skjult Nabo AS'
                                     or (x ->> 'id')::uuid = (select id from t_geo_hidden)), 'Nearby lists what the user may see, with the distance (MOB-03)');
select pg_temp.check(((public.mobile_focus(59.9561, 11.0485)) ->> 'nearby_10km')::int >= 1, 'Focus counts customers within 10 km');
select pg_temp.check((select detail::text not like '%59.95%' and detail::text not like '%11.04%' from app.audit where action = 'record.listed' and detail ->> 'view' = 'nearby'
                      order by id desc limit 1), 'the device''s position is not logged');
select pg_temp.expect_detail($$select public.nearby(95, 11, 10)$$, 'invalid', 'coordinates', 'impossible coordinates are refused');
create temp table t_chk as select (public.checkin('organization', (select id from t_geo), 'Kaffe med daglig leder') ->> 'activity_id')::uuid id;
select pg_temp.check((select a.done and t.key = 'visit' and a.organization_id = (select id from t_geo) from app.activities a join app.activity_types t on t.id = a.type_id where a.id = (select id from t_chk))
                     and (select source from app.changelog where entity = 'activity' and record_id = (select id from t_chk) and field = '*created') = 'mobile',
                     'Check in logs a done visit, from the mobile source, with no coordinates');
-- capture: an audio note on a deal, transcription not connected
create temp table t_up as select (public.file_upload_begin('deal', (select id from t_deal), 'note.webm', 'audio/webm', 4000) ->> 'id')::uuid id;
select public.file_upload_done((select id from t_up));
select pg_temp.expect_detail($$select public.capture_save('deal', (select id from t_deal), (select id from t_up), 'photo')$$, 'invalid', 'mime', 'an audio file is not a photo');
select pg_temp.check((public.capture_save('deal', (select id from t_deal), (select id from t_up), 'audio') ->> 'transcription') = 'not_connected'
                     , 'an audio note is kept; transcription is not connected');
select pg_temp.check((public.captures_get('deal', (select id from t_deal)) -> 'items' -> 0 ->> 'kind') = 'audio', 'the record lists its captures');
select pg_temp.as_service();
select pg_temp.expect_detail($$select public.worker_capture_transcript((select id from t_up), 'tekst')$$, 'not_connected', 'transcription', 'no transcript without the provider');
-- the business card (AIA-07) under contact_rule
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_card as select public.card_draft_save('{"name":"Nora Berg","title":"HR-leder","email":"Nora.Berg@kystlinje.no","organization_name":"Kystlinje Transport AS"}') r;
select pg_temp.check((select name = 'Nora Berg' and email = 'nora.berg@kystlinje.no' and source = 'Card scan' and organization_id is not null from app.people
                      where id = (select (r ->> 'person_id')::uuid from t_card)), 'a reviewed card becomes a contact on its organisation');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('contact_rule', 'opt_in_only');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.card_draft_save('{"name":"Per Hansen"}')$$, 'invalid', 'contact_rule', 'opt_in_only refuses a card contact');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('contact_rule', 'source_and_basis');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.card_draft_save('{"name":"Per Hansen"}')$$, 'invalid', 'basis', 'source_and_basis needs a basis');

-- ---------------------------------------------------------------------------
-- 0049 (V-P8P-28): a webhook is an export; it needs the export right of its event's area
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.webhook_save(null, '{"event_kind":"deal.updated","url":"https://hooks.example.com/hanna"}')$$, 'forbidden', 'deals:export',
                             'without deals:export no webhook on deal events (0049)');
select pg_temp.check(not (public.webhooks_get() -> 'kinds') ? 'deal.updated', 'the event picker leaves out what the caller may not export');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((public.webhooks_get() -> 'kinds') ? 'deal.updated' and app.webhook_scope('deal.updated') = 'deals' and app.webhook_scope('note.created') = 'global',
                     'with deals:export the deal events are offered; an event without a record type is global');
create temp table t_wh_x as select (public.webhook_save(null, '{"event_kind":"deal.won","url":"https://hooks.example.com/export"}') ->> 'id')::uuid id;
-- the owner loses the right: the next attempt is written as skipped and never claimed
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'analyst') where email = 'ingrid@orgpuls.no';
select pg_temp.expect_detail(format($$select public.webhook_save(%L, '{"url":"https://hooks.example.com/elsewhere"}')$$, (select id from t_wh_x)), 'forbidden', 'deals:export',
                             're-pointing a webhook needs the export right too');
insert into app.webhook_deliveries (webhook_id, event_id, attempt)
  select (select id from t_wh_x), (select max(id) from app.events where kind <> 'webhook.ping'), 1;
select pg_temp.check((select state = 'skipped' and error_code = 'no_export' from app.webhook_deliveries where webhook_id = (select id from t_wh_x) order by scheduled_at desc limit 1),
                     'a delivery for an owner without the export right is skipped as no_export, never sent');
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'sales') where email = 'ingrid@orgpuls.no';

-- ---------------------------------------------------------------------------
-- 0051: the Mobile and Platform requests (R-MOBILE-03/05/06, R-PLATFORM-02/03/06)
create temp table t_rpcs51 as select unnest(array['public.push_vapid_public_key()', 'public.api_scopes_get()', 'public.problems_open()', 'public.webhook_rotate_secret(uuid)']) f;
select pg_temp.check(not exists (select 1 from t_rpcs51 r join pg_proc p on p.oid = r.f::regprocedure
                                 where not p.prosecdef or not ('search_path=""' = any (p.proconfig)) or not has_function_privilege('authenticated', r.f, 'execute')
                                    or has_function_privilege('anon', r.f, 'execute') or has_function_privilege('public', r.f, 'execute')),
                     'the 0051 functions are security definer, empty search path, for signed-in staff only');
select pg_temp.check((select provolatile from pg_proc where oid = 'public.webhook_rotate_secret(uuid)'::regprocedure) = 'v'
                     and (select provolatile from pg_proc where oid = 'public.nearby(numeric, numeric, numeric, text[], jsonb)'::regprocedure) = 'v',
                     'the writers (rotation, nearby''s audit) stay volatile');
-- R-MOBILE-05: a nearby row carries its organisation's place, never the device's
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_near51 as select public.nearby(59.9561, 11.0485, 10, array['organization', 'person'], '{}') n;
select pg_temp.check((select (x ->> 'lat')::numeric = 59.955 and (x ->> 'lng')::numeric = 11.049 from jsonb_array_elements((select n from t_near51)) x
                      where x ->> 'entity' = 'organization' and (x ->> 'id')::uuid = (select id from t_geo))
                     and not exists (select 1 from jsonb_array_elements((select n from t_near51)) x where (x ->> 'lat')::numeric = 59.9561 or (x ->> 'lng')::numeric = 11.0485)
                     and not exists (select 1 from jsonb_array_elements((select n from t_near51)) x where x ->> 'lat' is null or x ->> 'lng' is null),
                     'nearby rows carry the organisation''s place (R-MOBILE-05), not the device''s position');
-- the nearest of several places is the one returned
insert into app.record_geo (entity, record_id, field_key, lat, lng, source) values ('organization', (select id from t_geo), 'custom.branch', 59.9300, 11.0000, 'manual');
select pg_temp.check((select (x ->> 'lat')::numeric = 59.955 and (x ->> 'km')::numeric < 1 from jsonb_array_elements(public.nearby(59.9561, 11.0485, 10)) x where (x ->> 'id')::uuid = (select id from t_geo)),
                     'with several places, the one the distance was measured to');
delete from app.record_geo where entity = 'organization' and record_id = (select id from t_geo) and field_key = 'custom.branch';
-- R-MOBILE-06: today's activities carry their deal and organisation ids
create temp table t_d51 as select d.id, d.organization_id from app.deals d where d.owner_id = (select ingrid from t_staff) and d.deleted_at is null and d.archived_at is null
  and not d.is_sample and d.organization_id is not null limit 1;
create temp table t_chk51 as select (public.checkin('deal', (select id from t_d51)) ->> 'activity_id')::uuid id;
select pg_temp.check((select (x ->> 'deal_id')::uuid = (select id from t_d51) and (x ->> 'organization_id')::uuid = (select organization_id from t_d51)
                      from jsonb_array_elements(public.mobile_focus() -> 'today') x where (x ->> 'id')::uuid = (select id from t_chk51)),
                     'mobile_focus().today[] carries deal_id and organization_id (R-MOBILE-06)');
-- R-MOBILE-03: the public half of the VAPID key, only while push is configured; never the private key
select pg_temp.check(public.push_vapid_public_key() is null, 'no public key in Vault: null');
select vault.create_secret('BPublicKeyForTests_0123456789', 'vapid_public_key', 'test');
select pg_temp.check(public.push_vapid_public_key() = 'BPublicKeyForTests_0123456789', 'push configured: the public key');
select pg_temp.check(public.push_vapid_public_key() is distinct from (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_private_key'),
                     'never the private key');
delete from vault.secrets where name = 'vapid_private_key';
select pg_temp.check(public.push_vapid_public_key() is null and not app.push_ready(), 'without the private key push is not configured: null (a subscription could never be delivered to)');
select pg_temp.as_nobody();
select pg_temp.expect_error($$select public.push_vapid_public_key()$$, 'not_signed_in', 'nobody gets the key');
-- R-PLATFORM-02: the scopes an OAuth app may ask for are the registry's
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((select array_agg(x ->> 'scope' order by x ->> 'scope') from jsonb_array_elements(public.api_scopes_get()) x) = (select array_agg(scope order by scope) from app.api_scopes)
                     and public.api_scopes_get() @> '[{"scope":"*"},{"scope":"deals:read"},{"scope":"global:read"}]'::jsonb
                     and app.scopes_ok(array(select x ->> 'scope' from jsonb_array_elements(public.api_scopes_get()) x limit 20)),
                     'api_scopes_get lists app.api_scopes, every one accepted by scopes_ok (R-PLATFORM-02)');
-- R-PLATFORM-03: open problems for the banner's link
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_po51 as select public.problems_open() p;
select pg_temp.check((select array_agg((x ->> 'id')::uuid order by x ->> 'id') from jsonb_array_elements((select p from t_po51)) x)
                     is not distinct from (select array_agg(t.id order by t.id::text) from app.tickets t where t.type = 'problem' and t.deleted_at is null and t.problem_status <> 'resolved'
                                           and t.status not in ('resolved', 'closed') and not t.is_sample and app.queue_ok(t.queue_key) and app.visible(t.owner_id, t.visibility)),
                     'problems_open lists the open problems the caller may see');
select pg_temp.check(not exists (select 1 from jsonb_array_elements((select p from t_po51)) x join app.tickets t on t.id = (x ->> 'id')::uuid where t.problem_status = 'resolved'),
                     'a resolved problem is not offered');
update app.ticket_queues set permission_set_ids = array(select id from app.permission_sets where key = 'admin') where key = 'support';
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.problems_open()) x join app.tickets t on t.id = (x ->> 'id')::uuid where t.queue_key = 'support'),
                     'a problem in a queue the caller may not see is not offered');
update app.ticket_queues set permission_set_ids = null where key = 'support';
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail($$select public.problems_open()$$, 'forbidden', 'global:see', 'problems_open needs global:see, as the banner');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_po51_1 as select (x ->> 'id')::uuid id from jsonb_array_elements((select p from t_po51)) x limit 1;
select public.status_notice_set('orgpuls', 'Innlogging feiler for noen', (select id from t_po51_1)) from t_po51_1;
select pg_temp.check(not exists (select 1 from t_po51_1)
                     or (public.status_notice_get('orgpuls') -> 'current' ->> 'problem_ticket_id')::uuid = (select id from t_po51_1),
                     'a problem picked from the list links the banner');
-- R-PLATFORM-06: rotating a webhook's secret
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_whr as select (r ->> 'id')::uuid id, r ->> 'secret' secret from (select public.webhook_save(null, '{"event_kind":"deal.updated","url":"https://hooks.example.com/rotate"}') r) x;
create temp table t_whr_v as select vault_secret_id v, version from app.webhooks where id = (select id from t_whr);
create temp table t_rot51 as select public.webhook_rotate_secret((select id from t_whr)) r;
select pg_temp.check((select r ->> 'secret' ~ '^whsec_' and r ->> 'secret' <> (select secret from t_whr) and (r ->> 'version')::int = (select version from t_whr_v) + 1 from t_rot51)
                     and (select s.decrypted_secret from vault.decrypted_secrets s join app.webhooks w on w.vault_secret_id = s.id where w.id = (select id from t_whr)) = (select r ->> 'secret' from t_rot51)
                     and (select vault_secret_id from app.webhooks where id = (select id from t_whr)) = (select v from t_whr_v)
                     and (select count(*) from vault.secrets where name = 'webhook:' || (select id from t_whr)) = 1,
                     'rotation replaces the secret in Vault (webhook:<id>) and shows the new one once (R-PLATFORM-06)');
select pg_temp.check((select detail is null and target_id = (select id::text from t_whr) from app.audit where action = 'webhook.secret_rotated' order by id desc limit 1)
                     and not exists (select 1 from app.audit where detail::text like '%' || (select r ->> 'secret' from t_rot51) || '%')
                     and not exists (select 1 from app.webhooks w where to_jsonb(w)::text like '%' || (select r ->> 'secret' from t_rot51) || '%'),
                     'the rotation is audited without the secret; the row holds none');
select public.webhook_test((select id from t_whr));
select pg_temp.as_service();
create temp table t_rclaim as select c from jsonb_array_elements(pg_temp.claim()) c where c ->> 'url' = 'https://hooks.example.com/rotate';
select pg_temp.check((select (c -> 'headers' ->> 'Sentral-Signature') = 't=' || substring(c -> 'headers' ->> 'Sentral-Signature' from '^t=(\d+),') || ',v1='
                      || encode(extensions.hmac(substring(c -> 'headers' ->> 'Sentral-Signature' from '^t=(\d+),') || '.' || (c ->> 'body'), (select r ->> 'secret' from t_rot51), 'sha256'), 'hex') from t_rclaim),
                     'deliveries after the rotation are signed with the new secret');
-- a webhook whose secret was never created (as the seed's) reads has_secret false and gets one
select pg_temp.as_staff('ingrid@orgpuls.no');
delete from vault.secrets where id = (select v from t_whr_v);
update app.webhooks set vault_secret_id = gen_random_uuid() where id = (select id from t_whr);
select pg_temp.check((select (x ->> 'has_secret')::boolean = false and (x ->> 'can_export')::boolean from jsonb_array_elements(public.webhooks_get() -> 'webhooks') x where (x ->> 'id')::uuid = (select id from t_whr)),
                     'webhooks_get says when Vault holds no signing secret');
create temp table t_rot51b as select public.webhook_rotate_secret((select id from t_whr)) r;
select pg_temp.check((select (x ->> 'has_secret')::boolean from jsonb_array_elements(public.webhooks_get() -> 'webhooks') x where (x ->> 'id')::uuid = (select id from t_whr))
                     and (select s.decrypted_secret from vault.decrypted_secrets s join app.webhooks w on w.vault_secret_id = s.id where w.id = (select id from t_whr) and s.name = 'webhook:' || w.id)
                         = (select r ->> 'secret' from t_rot51b),
                     'rotating a webhook without a secret creates one in Vault');
-- rights: the owner or global:configure, and the export right of the event's area (0049)
select pg_temp.as_staff('eirik@orgpuls.no');
select pg_temp.expect_detail(format($$select public.webhook_rotate_secret(%L)$$, (select id from t_whr)), 'forbidden', 'global:configure', 'another sales user cannot rotate the secret');
select pg_temp.expect_detail(format($$select public.webhook_rotate_secret(%L)$$, gen_random_uuid()), 'not_found', null, 'an unknown webhook is not found');
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'analyst') where email = 'ingrid@orgpuls.no';
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format($$select public.webhook_rotate_secret(%L)$$, (select id from t_whr)), 'forbidden', 'deals:export', 'rotation needs the export right of the event''s area (0049)');
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'sales') where email = 'ingrid@orgpuls.no';
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.webhook_rotate_secret((select id from t_whr)) ->> 'secret') ~ '^whsec_', 'global:configure may rotate any webhook''s secret');
select public.webhook_delete((select id from t_whr));
select pg_temp.expect_detail(format($$select public.webhook_rotate_secret(%L)$$, (select id from t_whr)), 'not_found', null, 'a deleted webhook has no secret to rotate');

rollback;
