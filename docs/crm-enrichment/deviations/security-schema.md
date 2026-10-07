# Security screen schema (Phase 8): deviations, message keys, RPCs

Migration `supabase/migrations/0043_security.sql` (runs after 0042, before 0044), proved by `supabase/tests/phase8_security_invariants.sql` (213 checks; one of them loops over all 38 client functions at aal1). All 15 earlier suites pass with 0043 applied.
Spec: `docs/crm-enrichment/specs/platform-security-mobile.md` §2, §3.1–§3.3, §3.6–§3.8, §3.10–§3.12, §4–§6, §8 (SEC-01..11, UF-15, SF-15, SF-27, SF-43). Design: `design-reference/sentral/project/Security.dc.html`.

Nothing is connected. There is no SSO provider in the Auth project, no email provider and no Slack. The schema models the whole configuration anyway. Turning SSO on raises `not_connected` (detail = provider). Alert email and Slack deliveries are recorded as `not_connected`. Alerts reach staff in the app.

**For 0044 (written in parallel):**
- `app.me()` should call `app.session_ok(app.current_session())`. That function returns false for a null session, so decide how to treat a JWT that has no `session_id` claim. Today's `_helpers.psql` `as_staff` sets none.
- Use `app.require_fresh_mfa(int)` as it is defined here. Do not redefine it.
- Register `mcp_access` through `settings_registry.hook`. `setting_set` calls the hook as `hook(key, old, new, scope_id)` before it writes.
- `app.log` reads `app.source`, `app.principal_kind` and `app.principal_id`. `api_exec` only has to set them.
- 0044 owns `job_defs`, `run_job` and api tokens. Retention, the issues list and the MFA reset leave hooks for them (see V-P8S-14, -15, -22).

## Deviations from the spec

| ID | Where | Spec | Built | Reason |
|---|---|---|---|---|
| V-P8S-01 | `audit.source`, `principal_kind` (§3.2) | `not null default 'web'` / `'staff'` | Nullable columns. A `NOT VALID` check, `audit_source_set`, requires both on every new row. A `before insert` trigger, `audit_stamp`, fills them for direct inserts (`record_command`, `customer_action_log`, the purge jobs). The fallback when no GUC is set is `workflow` inside a run (`app.run_id`), else `system` when nobody is signed in, else `web`/`staff`. `principal_id` falls back to the run's workflow | Legacy rows must not claim a source they never had: they read null and are shown as «—». A blanket default would mark every cron row as «Web» |
| V-P8S-02 | `audit_kind` | read/write/export/role, plus security for `security.*` and `session.*` | `security` also covers `security_rule.*`, `sso.*`, `recovery_codes.*` and `breakglass.*`. A product command row (`action` null) is `write` | These are the Security screen's own writes |
| V-P8S-03 | `audit_fixed` → `audit_guard` | Rename | New function `app.audit_guard()`. The triggers keep their names `audit_fixed` and `audit_no_truncate`, which `structure_invariants.sql` checks, and both now run `audit_guard`. `app.audit_fixed()` stays, because the changelog and other truncate guards use it. DELETE is allowed only while `app.purging = 'on'` and only for rows with `at < now() - 5 years`. It is used by `app.purge_audit()` (monthly) | Keeps the existing suite and the other tables' guards intact |
| V-P8S-04 | `setting_set` (0005 body) | Calls the hook | Also requires `global:security` for keys in the groups `security` and `security_alerts`, on top of `global:configure` | §3.8 says rules and alerts are written with `global:security` |
| V-P8S-05 | IPs (§3.3 `ip inet`, `last_ip inet`, `user_agent`) | Plain `inet`; a raw user agent | `ip_sealed` / `last_ip_sealed` hold `bytea` from `pgp_sym_encrypt`, with the Vault secret `security_ip_key` (created on first use, as 0041's web salt is). They are opened only by `login_history`, `my_sessions`, the rule preview and the enforcement functions. There is no `user_agent` column: `app.device_label(ua)` parses it to «Chrome on macOS» and drops it. A device is SHA-256 of the device cookie | The brief says never store an IP in clear. The design still shows the IP to `global:security`, which works because the seal can be opened |
| V-P8S-06 | IP enforcement on live sessions | `app.me()` refuses a session outside the rules | `app.session_ok` checks that the session has not ended, that it is not idle and that it is within the sign-in hours, all with one PK lookup. IP rules are enforced in three places: `worker_session_seen` (each request, throttled), `app.sessions_enforce_ip()` (when the allowlist is switched on or a range is edited or deleted), and `sessions_expire` (every 5 min) | The IP is sealed. Opening it on every RPC call would be costly, and so would storing it in clear |
| V-P8S-07 | Self-lockout (§2.2, §5.3) | «the caller's own current IP» | The last IP the middleware reported for the caller's current session (JWT `session_id`). An unknown IP (no session row, or no claim) is refused with `forbidden` / `self_lockout`. The same check runs after every rule save or delete while a rule is on, and the change rolls back. Sign-in hours apply the same rule to `now()` | Fail closed. The request headers that PostgREST sees come from the Next server, not from the person |
| V-P8S-08 | Enums | §3.3 lists | `login_log.outcome` adds `blocked_method`: an SSO method whose provider is off, or a domain that is not allowed. `security_events.kind` adds `admin_login`, raised only while `login_alerts` ≠ off | The SSO switch and `login_alerts` need an observable effect |
| V-P8S-09 | New device / new location | «new_device» | A person's first device and first city are not «new». Only a sign-in that adds a second one is | Otherwise every first sign-in would raise an alert |
| V-P8S-10 | Alert register keys (§3.6) | `alert_failed_logins` «+ number», `alert_large_export` «+ rows», `alert_digest_time` text HH:MM, `security_alert_recipients` role/list | Separate keys `alert_failed_logins_count` and `alert_large_export_rows` (`source_value` = 3 / 1 000, `custom` + number). `alert_digest_time` has 24 hourly options `00:00`..`23:00` (default `08:00`, Europe/Oslo). `list` uses a new table, `security_alert_recipients`, set by `alert_recipients_set`; each recipient must hold `global:security`, and an empty list falls back to the role | `numeric_option` is one option per key, and `setting_set` stores option keys, not free text |
| V-P8S-11 | Password rules (Q4) | `password_history` if built | Not built. `password_reuse` is registered (default off); its hook `app.password_reuse_guard` refuses any other value with `not_available` / `password_history`. `password_expiry` (`never` / `days` + number, default 90 when no number is given) is checked by `worker_login_event`, which returns `must_change_password`. The date comes from a new table, `password_changes` (dates only, the latest kept), written by `worker_password_changed`. Strength stays in the Auth config | Q4's recommendation. Every key keeps an effect that can be tested |
| V-P8S-12 | `sso_providers` | — | Adds `configured` (from `worker_sso_configured`, a build-time read of the Auth config) and `check (not enabled or configured)`. Un-configuring switches the provider off. `sso_set` needs `global:security` and a fresh second factor | The honest not-connected state (D-41) |
| V-P8S-13 | Sub-processors (Q8) | `region not null`; `subprocessors_public()` anon | `region` is nullable («not recorded»), and a public row needs one. Seed: Supabase (EU · Frankfurt, eu-central-1, D-35) public, and Vercel with no region, not public. Anthropic is not seeded, because the AI provider is not connected; Stripe waits for D-22. `subprocessors_public()` is service role only: the public host's server calls it and caches it | Never invent a contract region. `structure_invariants.sql` asserts that anon can call no platform function |
| V-P8S-14 | `retention_rules.job_key → job_defs` | FK | `job_key` is the `cron.job.jobname` (the suite asserts each platform rule's job exists and is active). New `setting_key` (recordings follow `rec_retention`) and a rule `erasure_tombstones` (13 months). `last_run_at` falls back to `cron.job_run_details`. The webhook-delivery, integration-call and API-usage rules are left to 0044 with their tables | `job_defs` is 0044's and does not exist when 0043 runs |
| V-P8S-15 | Jobs (§3.11) | Wrapped by `app.run_job` → `job_runs` | Scheduled directly with pg_cron: `security-alerts` (1 min), `security-digest` (15 min; acts once a day), `security-sessions-expire` (5 min), `security-login-prune` (daily), `security-incident-clock` (hourly), `security-access-review-due` (daily), `security-audit-purge` (monthly), `security-retention-tickets`, `security-retention-email` (daily), and `security-backup-poll` (hourly; queues `{job: 'ops_backup_poll'}` for the worker). `privacy_package` goes on the `jobs` queue | `run_job` is 0044's; it can re-wrap these |
| V-P8S-16 | `security_incidents` | — | Adds `notice_48_at` and `notice_66_at` (so each notice goes once). `notify_deadline` is generated through `app.plus_72h()`, an immutable wrapper | `timestamptz + interval` is only stable |
| V-P8S-17 | `user_invited` | Event | Raised by a trigger on `admins` insert, only when a signed-in staff member made the row (`staff_save`). The same trigger ends every open session when `active` goes false (SEC-09, SF-43.2) | Rows the fixture writes are not invitations |
| V-P8S-18 | Large exports and deletes | «Read from export_log and bulk deletes» | `sub_security_alerts` reads `export.created` (`rows` ≥ `alert_large_export_rows`) and `*.deleted` events with the same actor and transaction time (one `rec_bulk`) at or above the same threshold. Its cursor starts at the head of the outbox | Existing event payloads. Old exports are not news |
| V-P8S-19 | Failed logins (Q7) | «More than 3 in a row» | «In a row» means since the last success, within the last hour. One event, when the streak reaches the threshold. No platform lockout (Q7). Unknown addresses are logged and alerted by hash only | Q7's recommendation |
| V-P8S-20 | Delivery | One alert per trigger | In-app: a delivery row (`sent`) plus `notify(..., 'security', 'security.<kind>')`. Email: a delivery row, `not_connected` (or `queued` when the provider is connected; no mail claim exists yet). Slack: only for `admin_login`. Digest: one `security.digest` notification per recipient plus a delivery row per event, once a day (marked by the audit row `security.digest_sent`) | — |
| V-P8S-21 | `recovery_code_redeem` | Rate-limited | A wrong code returns `{ok: false, remaining_attempts}` and does not raise, so the attempt is counted (a raise would roll it back). The sixth attempt within the hour raises `forbidden` / `rate_limited`. The audit row is written with the staff id explicitly, because `app.me()` is null at aal1. New table: `recovery_attempts` | — |
| V-P8S-22 | `staff_mfa_reset` | — | Removes factors and recovery codes and ends sessions (`mfa_reset`). It does **not** revoke API tokens or grants (0044's tables). 0044 can do that on a `security_events` row of kind `mfa_reset`, or in its own trigger | Ownership split |
| V-P8S-23 | Erasure | §2.6 | The confirmation is the subject's address, or the name or title when there is none. One address per erasure (otherwise `invalid` / `subject`). An active product user is refused (`product_user`); inactive members have their name and email blanked. `privacy_approve` also needs a fresh second factor. A thread whose only outside participants are the person is deleted; elsewhere the address is removed from the participants, `from` and `to`/`cc`/`bcc`. Call logs on the person's activities are deleted. The tombstone trigger refuses re-creating the address in `people` by **any** path (`forbidden` / `erased`) for 13 months (Q9) | — |
| V-P8S-24 | Export link | «returns a signed URL» | `privacy_export_url` returns `{path, expires_at}`, and the server signs it for the remaining time. The worker neutralises formulas in the CSV (A7.6) | The database cannot sign storage URLs |
| V-P8S-25 | `firewall_status` | Plus the last CI result and commit | Six live checks. `ci` is null: nothing records a CI result yet | No writer exists. A table nobody writes would fail the wiring rule |
| V-P8S-26 | Extras | — | RPCs: `access_review_get`, `alert_recipients_set`, `privacy_export_url`, `worker_password_reset`, `worker_password_changed`, `worker_sso_configured`. Audit actions: `login_history.viewed`, `security.recipients_set`, `security.digest_sent`, `mfa.reminded`, `privacy.erase_requested`, `privacy_package.viewed`, `job.purged` (rule) | Each has a reader or an effect in the suite |
| V-P8S-27 | `typed_reason` | «every action here» | Applies where the spec's signature carries a reason: `session_revoke`, `staff_sessions_revoke_all`, `staff_mfa_reset`, `privacy_export`, `privacy_erase` (tested on `session_revoke`) | No `p_reason` in the other signatures |
| V-P8S-28 | Rules | — | Ranges no wider than /8 (IPv4) or /16 (IPv6). Rules are archived, not deleted, so the audit can name them. Editing or deleting a rule needs a fresh factor while its setting is on; adding a range only widens access and does not | Tightening = fresh MFA (§3.12.3) |
| V-P8S-29 | Design figures left out | — | The design shows several things with no source here. Okta and SAML, and «Email code», are left out (D-31, D-11). The guardrail panel is left out (D-19). For «Account locked 15 min» no lockout exists (Q7). For «12+ chars · mixed», password strength is Auth config. «Today 02:00» stays empty until the backup worker reports, and «14 Sep · passed» until a restore test is recorded | Never fabricate |
| V-P8S-30 | `app.require_fresh_mfa` | Named in §3.7 | Defined here: an `amr` entry with method `totp` within N minutes (default 10), else `forbidden` / `fresh_mfa` | 0044 needs it too; 0043 runs first |

### Redefined functions (merge order)

- `app.log(text, text, text, jsonb, uuid)`: 0004 body plus `source`, `principal_kind` and `principal_id`.
- `public.setting_set(text, text, text, numeric)`: 0005 body plus the hook and `global:security` for security keys.
- Triggers on `app.audit`: `audit_fixed` and `audit_no_truncate` now execute `app.audit_guard()`. A new trigger, `audit_stamp`, runs before insert.
- Register: `login_alerts` options become off/immediate/digest (group `security_alerts`; any stored `on` becomes `immediate`). `ip_allowlist` gets its hook. `second_admin.applies_to` gains SEC-11.
- New subscriber `('security_alerts', 'app.sub_security_alerts', 70)`. New triggers on `app.admins` (`admins_security_watch`) and `app.people` (`person_tombstoned`).
- Not touched: `app.me()`, `app.can()`, notifications, changelog sources, `activity_types`, and everything in 0044's list.
- 0051 (`0051_ops_requests.sql`): `security_dashboard` (+ `kpis.mfa.coverage_pct`), `alerts_get` (+ `eligible`), `retention_get` (a rule with `setting_key` reports the setting's period; + `default_keep`). New: `privacy_requests_get`.

## Settings (all with a consumer and a test of both states)

| Key | Group | Options (default) | Consumer |
|---|---|---|---|
| `session_idle` (exists) | security | on_30, off (on_30) | `app.session_ok`, `worker_session_seen`, `sessions_expire` |
| `ip_allowlist` (exists, hook) | security | off, on (off) | `worker_login_event` (`blocked_ip`), `worker_session_seen`, `sessions_expire`; hook `app.ip_allowlist_guard` |
| `signin_hours` (hook) | security | off, on (off) | `worker_login_event` (`blocked_time`), `app.session_ok`, `sessions_expire`; hook `app.signin_hours_guard` |
| `password_expiry` | security | never, days+n (never) | `worker_login_event` → `must_change_password` |
| `password_reuse` (hook) | security | off, number (off) | hook refuses anything else (`not_available`) |
| `access_review_interval` | security | quarterly, half_yearly (quarterly) | `app.access_review_next_due`, the issues list, `access_review_due` job |
| `login_alerts` | security_alerts | off, immediate, digest (off) | `admin_login` events, Slack delivery |
| `alert_new_device` | security_alerts | off, immediate, digest (off) | new device and new location events |
| `alert_user_invited` | security_alerts | (immediate) | `user_invited` |
| `alert_failed_logins` / `_count` | security_alerts | (immediate) / source_value 3, custom | `failed_logins` |
| `alert_password_reset` | security_alerts | (immediate) | `password_reset` |
| `alert_large_export` / `_rows` | security_alerts | (immediate) / source_value 1 000, custom | `large_export`, `large_delete` |
| `alert_digest_time` | security_alerts | 00:00..23:00 (08:00) | `app.security_digest_due` |
| `security_alert_recipients` | security_alerts | role, list (role) | `app.security_recipients` |
| `second_admin` (exists) | approvals_audit | off, on | `privacy_erase` → `privacy_approve` |
| `typed_reason` (exists) | approvals_audit | off, on | `app.take_reason` in the five functions above |

## Notification keys (kind `security`, rendered through `shell.json` → `notifications`)

`security.new_device`, `security.new_location`, `security.failed_logins`, `security.user_invited`, `security.password_reset`, `security.large_export`, `security.large_delete`, `security.admin_login` (params: `event`, `staff`, `actor` plus the event's detail: `count`, `rows`, `entity`, `threshold`, `device`, `city`, `country`, `method`), `security.digest` (`count`, `kinds`, `day`), `security.mfa_reminder` (`by`), `security.mfa_reset_by_owner`, `security.access_review_due` (`due_on`), `security.erasure_approval` (`job`, `by`), `security.incident_deadline` (`incident`, `hours` 48|66, `hours_left`).

## Message keys the screen needs (data → `security.*`)

- Error details: `fresh_mfa`, `self_lockout`, `owner_only`, `self`, `product_user`, `erased`, `rate_limited`, `open_review`, `undecided`, `enrolled`, `confirm`, `subject`, `cidr`, `window`, `days`, `domains`, `region`, `password_history` (not_available), `expired` (not_available), `google` / `microsoft` (not_connected).
- Issues: `mfa_not_enrolled`, `mailbox_reauth`, `api_tokens_old`, `access_review_due`, `ip_allowlist_empty`, `webhooks_banned`, `jobs_failed`. Actions: `send_reminder`, `reauthenticate`, `rotate`, `start_review`, `add_rule`, `open_webhooks`, `open_jobs`.
- Login outcomes: `success`, `failed_password`, `failed_mfa`, `blocked_ip`, `blocked_time`, `blocked_inactive`, `blocked_method`, `rate_limited`. Methods: `password_totp`, `google_totp`, `microsoft_totp`, `recovery_code`.
- Session end reasons: `signed_out`, `idle_timeout`, `forced`, `ip_rule`, `time_rule`, `deactivated`, `mfa_reset`, `recovery_code`, `expired`.
- Event kinds: as in `security_events.kind`. Severities: `info`, `low`, `high`, `critical`. Alert states: `none`, `queued`, `sent`, `digest`, `failed`.
- Firewall checks: `no_grants`, `no_references`, `aggregates_only`, `no_tracking_in_surveys`, `no_contacts_from_respondents`, `tested`.
- Platform facts: `db_region`, `hosting_region_label`, `encryption_in_transit`, `encryption_at_rest`, `isolation`, `rpo_minutes`, `rto_minutes`. Retention keys: `crm_soft_deleted`, `product_events_raw`, `login_log`, `tickets_closed`, `email_bodies`, `meeting_recordings`, `audit_log`, `erasure_tombstones`, `survey_responses`.
- Privacy counts: `people`, `leads`, `emails`, `email_participants`, `activities`, `activity_guests`, `deals`, `deal_participants`, `tickets`, `consent_events`, `form_submissions`, `chat_conversations`, `campaign_recipients`, `meetings`, `documents`, `signatures`, `bookings`, `product_events`, `enrichment_requests`, `history`.
- Incident states: `investigating`, `assessed_not_notifiable`, `notified`, `closed`. Audit kinds: `read`, `write`, `export`, `role`, `security`. Sources: `web`, `api`, `mcp`, `workflow`, `ticket`, `support_access`, `mobile`, `import`, `product`, `system`.

## RPCs (security definer, `search_path = ''`)

Errors use only: `forbidden` (detail = `scope:action` or a reason above), `not_found`, `invalid` (detail = field), `version_conflict` (detail = current version), `not_connected` (detail = provider), `not_available`. The existing codes `reason_required` and `not_signed_in` also occur.

**Signed-in staff (authenticated, aal2)**

| Function | Right | Returns |
|---|---|---|
| `security_dashboard()` | global:security | `{kpis: {signed_in_now, new_devices_7d: {count, staff: [{id, name}]}, new_locations_7d: {count, places: [{city, country}]}, security_events_7d: {count, critical}, forced_logouts_7d, mfa: {enrolled, active, coverage_pct (0051: rounded, null with no active staff)}}, settings: {session_idle, ip_allowlist, signin_hours, ip_rules}, live: [{session_id, staff_id, name, city, country, device, method, since, last_seen_at, current}], issues: [{key, severity, count?, staff?/mailboxes?/tokens?/webhooks?/runs?, due_on?, action}], issues_open, events: [{id, at, kind, severity, subject_id, subject, actor_id, actor, detail, alert_state}]}` |
| `session_revoke(p_session uuid, p_reason text default null)` | self, or global:security | `{ended}` |
| `staff_sessions_revoke_all(p_staff uuid, p_reason text default null)` | self (keeps the current session), or global:security | `{ended: n}` |
| `my_sessions()` | self | `[{session_id, created_at, last_seen_at, device, city, country, method, ip, current}]` |
| `login_history(p_staff uuid, p_days int default 60)` | self, or global:security; ≤ 60 days; audited | `[{at, outcome, method, device, new_device, city, country, new_location, ip, session_id, ended_at, end_reason, active}]` |
| `security_rules_get()` | global:security | `{ip_allowlist, signin_hours, session_idle, password_expiry, password_expiry_days, password_reuse, password_reuse_available: false, rules: [rule]}` |
| `security_rule_save(p_id uuid, p_values jsonb, p_version int default null)` | global:security; fresh MFA to edit a rule in force | rule `{id, kind, cidr, days, starts, ends, label, created_at, version}` |
| `security_rule_delete(p_id uuid)` | global:security; fresh MFA while in force | `{ok}` |
| `security_rule_preview(p_change jsonb)` | global:security | `{staff: [{staff_id, name, refused, sign_ins}], self_lockout}` |
| `alerts_get()` | global:security | `{settings: {alert_*, login_alerts, alert_digest_time, security_alert_recipients}, failed_logins_count, large_export_rows, recipients: [{id, name, email}], listed: [uuid], eligible: [{id, name}] (0051: the active holders of global:security that `alert_recipients_set` accepts), email, slack: 'connected'\|'not_connected', slack_channel}` |
| `alert_recipients_set(p_staff uuid[])` | global:security | `{count}` |
| `sso_get()` | global:security | `{providers: [{provider, enabled, configured, state: not_connected\|on\|off, allowed_domains, updated_at, users}], access_review_due, access_review_open}` |
| `sso_set(p_provider text, p_enabled boolean, p_domains text[] default null)` | global:security + fresh MFA | `{provider, enabled}` |
| `mfa_overview()` | global:security | `{enforced, active, authenticator, not_enrolled: [{id, name}], recovery_codes}` |
| `recovery_codes_generate()` | self + fresh MFA | `{codes: [10 × 'xxxxx-xxxxx']}`, shown once |
| `recovery_code_redeem(p_code text)` | **aal1 allowed**; 5/hour | `{ok: true, enrol: true}` or `{ok: false, remaining_attempts}` |
| `staff_mfa_reset(p_staff uuid, p_reason text)` | owner + fresh MFA, not self | `{factors_removed}` |
| `staff_mfa_reminder(p_staff uuid)` | global:security | `{in_app: true, email: 'queued'\|'not_connected'}` |
| `access_review_start()` / `access_review_get(p_review uuid default null)` / `access_review_decide(p_review uuid, p_staff uuid, p_decision text)` / `access_review_complete(p_review uuid)` | global:security | `{id, items}` / `{review, next_due, interval, items: [{staff_id, name, permission_set_id, permission_set, group_id, group, decision, decided_at}]}` / `{ok}` / `{ok, next_due}` |
| `firewall_status()` | global:see | `{ok, checks: [{key, ok}], ci: null}` |
| `protection_get()` | global:security | `{facts: {key: {value, source}}, last_backup, pitr, pitr_warning, last_restore_test: {at, ok, rpo_minutes, rto_minutes, meets_objectives}, objectives: {rpo_minutes, rto_minutes}}` |
| `restore_test_record(p_at timestamptz, p_ok boolean, p_rpo_min int, p_rto_min int, p_note text default null)` | global:security | `{id, meets_objectives}` |
| `privacy_find(p_q text)` | global:security; audited without the query | `{people: [{id, name, email, organization, deleted, leads}], members: [{product, tenant_id, active}], email_participants, tickets, consent_events, erased}` |
| `privacy_preview(p_subject jsonb)` | global:security; audited | `{counts: {...}, product_user, emails, confirm: 'email'\|'name', second_admin}` |
| `privacy_export(p_subject jsonb, p_request uuid default null, p_reason text default null)` | global:security | `{job, state: 'approved'}` |
| `privacy_export_url(p_job uuid)` | global:security; audited | `{path, expires_at}` |
| `privacy_erase(p_subject jsonb, p_request uuid, p_confirm text, p_reason text default null)` | global:security + fresh MFA | `{job, state: 'done', counts}`, or with `second_admin` on `{job, state: 'previewed', approval: 'required', counts}` |
| `privacy_approve(p_job uuid)` | another global:security holder + fresh MFA | `{job, state: 'done', counts}` |
| `privacy_requests_get()` (0051, R-SECURITY-05) | global:security | `[{id, kind, status: received\|in_progress, received_at, due_at, overdue, ticket_number, organization}]`, by due date; no requester text |
| `privacy_jobs_get()` | global:security | `[{id, kind, state, preview, request_id, created_at, created_by, approved_by, finished_at, url_expires_at, error}]` |
| `retention_get()` | global:security | `[{key, keep, default_keep, basis, job, setting: {key, value}?, in_force, last_run_at, last_purged}]`; 0051: for a rule with `setting_key` (`meeting_recordings` → `rec_retention`) `keep` is the setting's period in months (`'12 mons'`, the custom number, or null = kept until deleted) |
| `subprocessors_get()` / `subprocessor_save(p_id uuid, p_values jsonb, p_version int default null)` | global:security | rows / the saved row |
| `incidents_get()` / `incident_save(p_id uuid, p_values jsonb, p_version int default null)` | global:security | `[incident + {hours_left, elapsed_pct, logged_by_name}]` / one incident |
| `audit_search(p_filter jsonb default '{}', p_cursor bigint default null, p_limit int default 50)` | global:security; audited with filter keys only | `{rows: [{id, at, kind, action, command, ok, staff_id, who, principal_kind, principal_id, workflow, source, target_type, target_id, target: {state: ok\|hidden\|removed\|other, title?}, organization, account_id, reason}], next, typed_reason}` |
| `setting_set(...)` (redefined) | global:configure (+ global:security for security keys) | `{key, value}` |

**Service role only**

| Function | Called by | Returns |
|---|---|---|
| `worker_login_event(p_input jsonb)` | the sign-in action: `{email, outcome, session_id, method, ip, device_id, device_label \| user_agent, city, country}` | `{allowed, reason, must_change_password}` |
| `worker_session_seen(p_session uuid, p_ip inet, p_ua text default null)` | the middleware, at most once a minute | `{ok, reason?}` |
| `worker_password_reset(p_email text)` / `worker_password_changed(p_email text)` | the password-reset and password-change actions | `{ok}` |
| `worker_sso_configured(p_provider text, p_configured boolean)` | a build-time read of the Auth config | `{provider, configured}` |
| `worker_backup_seen(p_rows jsonb)` | the backup worker: `[{kind: backup\|pitr, at, ok}]` | `{recorded}` |
| `worker_privacy_package(p_job uuid)` / `worker_privacy_done(p_job uuid, p_path text, p_error text default null)` | the privacy worker (`privacy/<job>/<file>`) | the rows / `{state}` |
| `subprocessors_public()` | the public host's server, cached | `[{name, purpose, region, in_use_since}]` |

**Internal (no client grant):**
- `app.session_ok(uuid)`, used by 0044's `app.me()`.
- `app.require_fresh_mfa(int)`.
- The hooks `app.ip_allowlist_guard`, `app.signin_hours_guard` and `app.password_reuse_guard`.
- `app.sub_security_alerts`.
- The jobs: `app.security_alerts_run`, `app.security_digest_due`, `app.sessions_expire`, `app.security_prune`, `app.incident_clock`, `app.access_review_due`, `app.purge_audit`, `app.retention_tickets`, `app.retention_email_bodies`.

## Events

- Outbox (`app.events`): `incident.logged`, `incident.deadline_near`, `privacy.exported` (from the worker, when the package is done), `privacy.erased`.
- Security events stay in `security_events`. They are never in the outbox and never webhookable (§3.10).

## Left open

1. The session branch in `app.me()` (0044). Until it lands, a revoked session ends its Auth session and refresh tokens at once, but an access token that was already issued keeps working at the database until it expires.
2. The mail claim for alert emails. Delivery rows wait as `queued` once the email provider is connected.
3. A CI-result writer for `firewall_status.ci`.
4. The contract regions for Vercel (and Anthropic, once the AI provider is connected), to be entered with `subprocessor_save`.
5. Break-glass (Q3): no in-app bypass exists. The runbook entry (operator SQL that turns off `ip_allowlist`/`signin_hours` and writes `breakglass.used`) is not written.
