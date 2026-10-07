# Platform and Mobile schema (Phase 8): deviations, message keys, RPCs, workers

Migration `supabase/migrations/0044_platform.sql` (runs after 0043_security.sql, which it depends on), proved by
`supabase/tests/phase8_platform_invariants.sql` (234 checks) and `tests/product-commands.test.ts` (the command mirror).
Spec: `docs/crm-enrichment/specs/platform-security-mobile.md` §1, §3.2, §3.4–§3.12, §4–§8. Designs:
`design-reference/sentral/project/Platform.dc.html`, `Mobile.dc.html`. Also R-SETTINGS-03 (`sandbox_reset`) and Contacts R-6
(revertable bulk changes).

Nothing external is connected: no push provider (VAPID key), no OAuth client, no webhook target, no geocoder, no transcription,
no product ping. The `worker_*` functions and `api_exec` (service role) stand in for the edge workers. All 15 earlier suites and
0043's `phase8_security_invariants.sql` (213 checks) pass with 0044 applied.

## Deviations from the spec

| ID | Where | Spec | Built | Reason |
|---|---|---|---|---|
| V-P8P-01 | Webhook log (§1.3, §3.4) | `webhook_deliveries.request_body`, the payload as sent, an audited read | No body is stored. The log keeps `envelope` (event, object, id, occurred_at, meta, the **names** of the changed fields), `body_sha256` and `bytes`. The body is built when the attempt is claimed, so `current` is the record at that attempt's send time; `previous` is `current` overlaid with the changelog's old values as of the event. `webhook_delivery_get` returns the envelope and hash (audited read) | The task's rule: no payload bodies with customer free text in a log. The design's payload view can show the envelope and field names |
| V-P8P-02 | Webhook signing (§3.12.2) | The worker reads the secret through `worker_webhook_secret` | The secret never leaves the database. `worker_webhook_claim` returns the body with its header `Sentral-Signature: t=<unix>,v1=<hex HMAC-SHA256(secret, t.body)>`; the worker must send the body byte for byte. No `worker_webhook_secret` | Smaller exposure; signing is testable in SQL (D-32) |
| V-P8P-03 | `record_geo` (§3.5) | PostGIS `geography(Point)`, GiST | `lat`/`lng numeric(9,6)`, a (lat, lng) index, a bounding box then haversine (`app.km`, `app.orgs_near`). Only organisations' main address is geocoded; `field_key` already allows `custom.<key>` for address custom fields, but `worker_geocode_claim` offers only `address` | No extension for a back-office scale (hundreds of organisations). Address custom fields need the geocoder to exist first |
| V-P8P-04 | `files` (§3.5) | A new `files` table | 0038's `record_files` gains `capture_kind`, `transcript`, `transcript_at`; its MIME list and `file_upload_begin` (0038 body) add `image/webp`, `image/heic`, `audio/webm`, `audio/mp4`, `audio/mpeg` | One file table, one signer (R-PROJECTS-01) |
| V-P8P-05 | OAuth consent | `worker_oauth_authorize(...)` (service role) | `oauth_authorize(client_id, redirect_uri, scopes, code_challenge, method)` for a signed-in staff member (the consent page in the admin, aal2) | The code must be issued to the person who consents; only their session knows who that is |
| V-P8P-06 | Webhook policy (§3.6, Q6) | Five numeric keys incl. `webhook_retry_s` "3,30,150" | Four keys: `webhook_timeout_s`, `webhook_ban_after`, `webhook_ban_min`, `webhook_delete_days` (options `source_value`/`custom`), read only while `safeguards = custom`. Retries stay 3/30/150 s (4 attempts). `safeguards = off`: no ban, no deletion, retries kept | A list is not a `value_number` |
| V-P8P-07 | `api_rate` | off / source_values / custom | `off`: no limit. `source_values`: 30 000 × 1 × active staff, bursts 20/80/10, whatever the keys say. `custom`: the five `api_*` keys (each `source_value` or `custom`). `api_rate`'s own number is not read | One meaning per option |
| V-P8P-08 | Metering | Burst and budget in the gateway | `api_exec` meters in its transaction (`app.api_meter`); a call that raises rolls its metering back, so only answered calls count. Over a limit: `{status: 429, reason: burst|budget, rate:{limit, remaining, reset}}`, not an exception. Hourly usage comes from the gateway through `worker_api_usage`; no `api_usage_rollup` job | The gateway sees the HTTP outcome; the database sees the cost |
| V-P8P-09 | Job runs (§1.6, §3.11) | A row per run | Every-minute ("quiet") jobs write a row only when they did work or failed; `job_defs.last_run_at/last_state` always move. A cron run's row commits with its work, so «Running» for cron jobs is read from `cron.job_run_details`. A failure notifies `global:configure` once per failure streak | ~13 000 empty rows a day otherwise; a minutely failing job would alert 1 440 times |
| V-P8P-10 | Assignment notifications (MOB-07) | `app.notify(kind 'assignment', dedupe_key 'assignment:<event>:<staff>')` | `app.notify` (0007 signature) maps the key `assignment.assigned` (written by 0021/0039) to kind `assignment` with `dedupe_key = assignment:<e<event id>|r<run id>>:<record>:<staff>`; `app.dispatch_events` (0021 body) sets `app.event_id` per event. **`notifications_get(p_kind => 'system')` no longer returns assignments** | No change to the engine's bodies; the screen's notification filter must add `assignment` |
| V-P8P-11 | `notification_prefs` | channels in_app, push, email | `in_app` is always included (the notification row is the in-app record); `email` is refused until the email provider and a consumer exist. Reminders follow `reminder_prefs` and always push | Every stored value has an effect |
| V-P8P-12 | Push provider | "VAPID key in Vault" | Connected = Vault secrets `vapid_private_key` (and `vapid_public_key`). Without it no `push_deliveries` are created; `push_devices_get.push_ready` says so | No row in `integration_connections` needed |
| V-P8P-13 | `app_extensions` (INT-10) | Table | Not built | No writer and no extension app yet (wiring rule) |
| V-P8P-14 | Catalog RPC names | `catalog_get`, `catalog_install`, … | `integration_catalog_get`, `integration_install`, `integration_remove`, `integration_users`, `integration_user_revoke`, `integration_recommend`, `worker_integration_validate` | `public.catalog_get()` is the product catalog (0009) |
| V-P8P-15 | Catalog search / AIA-06 | Trigram and full text; recommendations via the gateway | `integration_catalog.terms` (English name and description) is searched: score = query words (≥ 4 letters) found + trigram similarity; the best-scoring entries are `match` («best matches»). `integration_recommend(need)` (global:ai, `ai` connected) returns the catalog and what is in use as the gateway's context; the need is neither stored nor logged; `worker_integration_validate` keeps existing keys only, at most three | Data, not code; no free text kept |
| V-P8P-16 | Integration removal | Revoke the app's grants | Company connector: Vault secret deleted, connection `not_connected`. Per-user (Google/Microsoft): every mailbox and calendar of that provider disconnected. Extension: all extension apps disabled and their grants revoked. Automation platforms (`zap`): personal tokens are not revoked by removal (they are personal); `integration_user_revoke` revokes one person's | The catalog does not link an entry to particular OAuth apps |
| V-P8P-17 | Status banner / maintenance (§1.7) | Maintenance: owner, fresh MFA, typed key | Refused `not_available` (detail `maintenance`) until `product_commands` has `settings.set_maintenance` (D-40); then owner, fresh MFA, `p_confirm = product key`. Setting a banner queues `{job: product_command, command: settings.set_notice, notice_id}`; `worker_status_notice_pushed` records the outcome; clearing writes a row with null text | Never fake a command the product lacks |
| V-P8P-18 | `sandbox_reset` (R-SETTINGS-03) | Re-create the seed generator's Lumio AS tenant | A compact demo tenant in SQL: Lumio AS, Kari Nordmann, the deal «Lumio AS — Expansion to Skiftly» (64 000 NOK, stage «Proposal sent» or the first stage), a lead, two activities, a note; every row `is_sample`. Uses `sandbox_clear` first and also clears sample notes | The hosted project never runs the JS seed; the full scenario stays local |
| V-P8P-19 | Bulk revert (R-6) | — | `rec_bulk` (0006 body) writes `bulk_changes` + `bulk_change_items(before, after_version)` and returns `change_id` (additive). `bulk_change_revert` goes row by row through `rec_save` with `p_version = after_version`: `reverted`, `stale` (changed since), `gone` (deleted), `forbidden`. Revert once; kept 90 days. Items are immutable except their one outcome; deletes only with the parent or under `app.purging` | Partial revert is honest; rights apply per row |
| V-P8P-20 | Session check (§3.9 item 1) | In `app.me()` | `app.me()` calls 0043's `app.session_ok(app.current_session())` only when the JWT names a session; a JWT with no session claim is checked as before | 0043 owns the register; the 15 suites' helper sets no claim |
| V-P8P-21 | Token revocation on MFA reset | `revoke_reason 'mfa_reset'` | Trigger `staff_mfa_reset_platform` on 0043's `security_events` (kind `mfa_reset`, both the owner's reset and a redeemed recovery code) revokes the person's token, grants and codes. `oauth_grants.revoke_reason` adds `mfa_reset`. Deactivation (trigger on `admins.active`) also revokes push devices | Not redefining 0043's functions |
| V-P8P-22 | Scopes (§3.8) | Examples | `<s>:read` = `<s>:see`; `<s>:write` = see, add, edit_others, delete, bulk — for deals, projects, campaigns, tickets; `global:read` = `global:see`; `*` = everything the staff member may. `global:security` and `global:configure` are refused for every principal. Narrowing an app's scopes revokes wider grants | — |
| V-P8P-23 | API operations | rec_*, search, lead_convert, records_merge | `list`, `get`, `create` (with `idempotency_key`), `update`, `delete`, `delete_list`, `search`, `index_search`, `convert`, `merge`. Mail threads are outside the API and the index. `api_costs` adds `convert`, `merge` (10) and `index_search` (40) | Part F gives no cost for these |
| V-P8P-24 | MCP index (MCP-01) | Filter at query time | Owned record types only; every hit is re-checked against the live row (module, scope, visibility, not deleted). `mcp_sync = off` empties the index and `index_search` raises `not_available` (detail `mcp_sync`) | A stale index row must never widen access |
| V-P8P-25 | Application status | operational / degraded / unreachable | Adds `no_data` (no calls and no events), `disabled`, `not_installed`. The expected push interval is 5 min for every product (no per-product column) | Honest states |
| V-P8P-26 | `event_catalog` | — | Adds `entity` and `event_catalog_get()` (staff): the automation trigger picker can read the kinds per record type (R-AUTOMATION-04's open part) | Small, and the same registry |
| V-P8P-27 | Jobs | Each platform cron job wrapped | All `platform-*` schedules and 0043's `security-*` schedules that call one function now run `select app.run_job('<key>')` under their old names (0043's `retention_rules` keep working). `security-backup-poll` (a `pgmq.send`) is left as is | — |
| V-P8P-28 | Webhook creation | Owner, count_limits | **Decided (Tor, 2026-10-07; 0049):** creating a webhook, changing its event or re-pointing its URL requires `<scope>:export` for the event's record type (`global` without one). The picker offers only exportable events; a delivery whose owner has lost the right is skipped as `no_export` | Spec §3.8 |
| V-P8P-29 | Chat request (MOB-07) | kind `chat_request` | Trigger on `chat_conversations` entering `queued` (0031's handoff) notifies staff online for chat (`chat_presence`), once per queueing; params `page` (path without query string) | LGN-02 exists since phase 5 |
| V-P8P-30 | Retention | Listed in §3.11 | `app.platform_prune` (daily): integration_calls 30 d, webhook deliveries 30 d, api hourly 90 d, idempotency 24 h, budget days 90 d, job runs 90 d, sync receipts 30 d, push deliveries 30 d, bulk changes 90 d, revoked devices 90 d, expired codes. Not yet rows in 0043's `retention_rules` | The lead may add rows naming `platform-platform-prune` |
| V-P8P-31 | Realtime (MOB-01, Q14) | Broadcast on `staff:<id>` | Not built: `sync_changes` gives the pull; the Broadcast trigger and the `realtime.messages` policy wait | Needs a policy outside `app`, to be decided with the lead |

### Redefined functions (merge order)

- `app.me()`: 0021 body + token branch + 0043's session check (when the JWT names a session).
- `app.can()`: 0003 body + scope intersection inside a token principal.
- `app.notify(...)`: 0007 signature; `assignment.assigned` → kind `assignment`, once per event/run.
- `app.dispatch_events()`: 0021 body + `app.event_id` per event.
- `public.rec_save`: 0042 body; source list adds `mobile`.
- `public.rec_bulk`: 0006 body + the bulk-change log, returns `change_id`.
- `public.file_upload_begin`: 0038 body + five MIME types.
- `public.sandbox_counts`: 0007 body + `last_reset`.
- `public.store_product_secrets`: 0002 body + the product binding.
- Constraints: `changelog_source_check` (0042's list + `mobile`), `notifications_kind_check` (+ `assignment`, `chat_request`), `record_files_mime_check`.
- Not touched: 0043's `app.log`, `audit_guard`, `setting_set`, `session_ok`, `require_fresh_mfa`, guards, security subscriber.
- 0051 (`0051_ops_requests.sql`): `public.nearby` (0044 body, volatile as 0046, + `lat`/`lng` of the organisation's nearest place), `public.mobile_focus` (+ `today[].deal_id`, `organization_id`), `public.webhooks_get` (0049 body + `has_secret`, `can_export`). New: `push_vapid_public_key`, `api_scopes_get`, `problems_open`, `webhook_rotate_secret`.

## Message keys the app must add

Notifications (params are ids, counts, codes and names of things, never record values):

| Key | Kind | Params | Route |
|---|---|---|---|
| `job.failed` | system | `job` | `/applications` |
| `webhook.banned` | system | `event`, `host`, `minutes` | `/api?webhook=<id>` |
| `webhook.deleted` | system | `event`, `host` | `/api?webhook=<id>` |
| `api.budget_warning` | system | `percent` (75, 100), `budget` | `/api` |
| `chat.requested` | chat_request | `page` | `/lead-capture?chat=<id>` |
| `capture.transcript_ready` | system | `file` | the record's route |
| `assignment.assigned` (exists) | **assignment** (was system) | `workflow` | as before |

Other keys:
- **Job labels:** `jobs.<key>` for every `job_defs.key` (`purge`, `mrr_snapshot`, `reminders`, `duplicates`, `mail_due`, `dispatch`, `workflow_resume`, `workflow_dates`, `feed_checks`, `scores`, `pipeline_snapshot`, `mrr_tenants`, `health`, `web_salt`, `web_prune`, `chat_fallback`, `capture_prune`, `signature_expire`, `campaign_due`, `campaign_ab`, `campaign_prune`, `dns_check`, `files_purge`, `meeting_*` (5), `webhook_sweep`, `api_burst_prune`, `mcp_index`, `status_notices`, `platform_prune`, `security_*` (0043's 9), and queue jobs `webhook_send`, `push_send`, `geocode`, `product_command`, `transcription`).
- **Events:** `events.<kind>` for every `event_catalog` row.
- **Event uses:** `platform.eventUse.<kind_with_underscores>`; use chips `crm | funnel | billing | health | activation | usage | tickets | leads | workflows | support_access`.
- **Catalog:** `catalog.<key>.name`, `catalog.<key>.description`, collections `productivity_mail | team_chat | close_paid | automate`, access chips (`contacts`, `calendar`, `mail`, `drive`, `files`, `deal_events`, `search`, `deals`, `products`, `invoices`, `documents`, `scoped_by_token`, `per_app`).
- **Health:** `operational | degraded | unreachable | no_data | disabled | not_installed`.
- **Webhook states:** `active | paused | banned | blocked | deleted`; delivery states `queued | sent | failed | skipped`; error codes from the worker (`http_<n>`, `timeout`, `private_address`, `not_visible`, `no_secret`, `webhook_deleted`).
- **Sync results:** `applied | superseded | rejected` (+ `error`, `detail`).
- **Settings:** labels for `api_budget_base`, `api_plan_multiplier`, `api_burst_token`, `api_burst_oauth`, `api_burst_search`, `webhook_timeout_s`, `webhook_ban_after`, `webhook_ban_min`, `webhook_delete_days` (options `source_value`, `custom`), `mcp_access`, `mcp_sync`, `push_notifications` (`on`, `off`).
- **Error details:** `fresh_mfa`, `owner_only`, `active_token`, `count_limit`, `event_kind`, `url`, `redirect_uris`, `allowed_scopes`, `scopes`, `code_challenge`, `client`, `code`, `refresh_token`, `mcp_off`, `confirm`, `installed`, `key_taken`, `exists` (intake), `maintenance`, `mcp_sync`, `missing_fields`, `reverted`, `coordinates`, `contact_rule`, `basis`, `mutations`, `channels`.

## RPCs

All return `jsonb`. Staff = `app.require_staff()` (aal2, live session); rights as listed. Errors: `forbidden`, `not_found`,
`invalid` (detail = field), `version_conflict`, `not_connected` (detail = provider), `not_available` (detail = what), plus the
existing `not_signed_in`, `module_off`, `reason_required`.

### Applications, flags, banner, content, jobs (global:see to read)
- `applications_get()` → `[{key, name, description, color, ink, stage, installed, region, health:{status, calls_15m, calls_per_min, p95_ms, error_rate, last_event_at, last_ping_*}, orgs, spark:[24 ints]}]`
- `application_get(p_product)` → `{key, name, stage, installed, health, connection:{api_url, api_version, region, enabled, scopes, token_secret:bool, webhook_secret:bool, event_kinds_30d, last_sync_at, connected_since, last_ping_*}, synced:{organizations, users, subscriptions, usage_events_24h, *_last, flags:null}, events:[{kind, count, uses, label_key}], commands:[{command, scope, used_by, destructive, allowed}]}`
- `application_connect(p_values {key, name, description?, api_url, public_key, region?, scopes[], stage?})` owner + fresh MFA → `{product, intake_code, expires_in}`
- `application_update(p_product, p_values)` owner → `{product}`
- `flags_get(p_product?)` → `{modules:[{key, enabled, updated_at}], products:[{key, name, flags_command, pilots_command, set_command, active_tenants}]}`
- `status_notice_get(p_product)` → `{notice_command, maintenance_command, current:{id, text, maintenance, problem_ticket_id, problem_number, set_at, pushed_at, push_error}|null, history:[…]}`
- `status_notice_set(p_product, p_text, p_problem uuid?, p_maintenance bool?, p_confirm text?)` global:configure → `{id}`
- `problems_open()` global:see (0051, R-PLATFORM-03) → `[{id, number, subject, problem_status}]`: open problem tickets (not resolved or closed) the caller may see under the tickets' own rules (queue, visibility, sandbox), newest first, at most 100
- `content_get(p_product)` → `{help:{articles, published, last_change, macros}, cards:{question_set|pulse_templates|tiltak|legal|templates|modules:{command}}, draft_command:false, rollback_command:false}`
- `jobs_get(p_filter {state?, job?})` → `{stats:{queued, running, failed_24h, succeeded_24h}, jobs:[{key, label_key, product, schedule, source, quiet, last_run_at, last_state, last_run}], runs:[…50]}`
- `job_retry(p_run bigint)` global:configure → `{run, state}`

### REST API, tokens, OAuth (staff)
- `api_overview()` → `{endpoints:[{method, path, op, entity, cost}], tokens:[{id, kind, name, staff, masked, scopes, created_at, last_used_at, expires_at, mine}], grants:[…], has_token, rate:{mode, budget_day, used_today, burst_token, burst_oauth, burst_search}, usage:[{hour, requests}×24], usage_scope: company|mine}`
- `api_definition()` → OpenAPI 3.1 `{openapi, info, servers, paths, components:{schemas, securitySchemes}, x-costs, tools:[{name, op, entity, input_schema}]}`
- `api_token_create(p_name, p_expires_at?)` fresh MFA → `{id, token (once), masked, expires_at}`
- `api_token_rotate()` fresh MFA → `{id, token (once), masked}`
- `api_token_revoke(p_id, p_reason?)` owner of token or global:security → `{id}`
- `api_scopes_get()` staff (0051, R-PLATFORM-02) → `[{scope}]` in `app.api_scopes` order: exactly what `app.scopes_ok` accepts
- `oauth_apps_get()` → `[{id, client_id, name, kind, redirect_uris, allowed_scopes, confidential, dynamic, owner, created_at, disabled_at, grants}]`
- `oauth_app_save(p_id, p_values {name, kind, redirect_uris[], allowed_scopes[], confidential?, rotate_secret?})` global:configure (+ fresh MFA to create or rotate) → `{id, client_id, client_secret (once)|null}`
- `oauth_app_disable(p_id)` global:configure → `{id, grants_revoked}`
- `oauth_grants_get()` → `[{id, app, kind, staff, scopes, created_at, last_used_at, mine}]`
- `oauth_grant_revoke(p_id)` self or global:security → `{id}`
- `oauth_authorize(p_client_id, p_redirect_uri, p_scopes[], p_code_challenge, p_method='S256')` staff (consent) → `{code (once), redirect_uri, expires_in}`
- `mcp_get()` → `{access, sync, connected, last_index_at, assistants:[{id, app, staff, last_used_at, created_at, mine}], tools, can_configure}`
- `mcp_set(p_enabled)`, `mcp_sync_set(p_on)` global:configure → `{access}` / `{sync}`

### Webhooks (owner; all with global:configure)
- `webhooks_get(p_filter {owner_id?})` → `{webhooks:[{id, owner_id, owner, event_kind, url, state, banned_until, retrying, last_success_at, failing_since, created_at, version, mine, has_secret, can_export}], deliveries:[{id, webhook_id, at, event, host, status, state, attempt, attempts:4, error}], kinds, limit, count_limits, policy, can_manage_all}`
- `webhook_save(p_id, p_values {event_kind, url}, p_version?)` → `{id, version, secret (once, on create)}`
- `webhook_rotate_secret(p_id)` (0051, R-PLATFORM-06) owner or global:configure, and `<scope>:export` of the event's area (0049) → `{id, version, secret (once)}`: replaces the Vault secret `webhook:<id>` (or creates it when the webhook had none), audited as `webhook.secret_rotated` without the secret
- `webhook_delete(p_id)`, `webhook_set_state(p_id, 'active'|'paused')`, `webhook_test(p_id)` → `{delivery_id}`, `webhook_redeliver(p_delivery)` → `{delivery_id}`
- `webhook_deliveries_get(p_webhook, p_cursor timestamptz?)` → `[{id, event_id, event, attempt, attempts, redelivery, state, scheduled_at, sent_at, status, duration_ms, error}]`
- `webhook_delivery_get(p_id)` (audited) → `{id, event, attempt, attempts, state, status, duration_ms, error, scheduled_at, sent_at, envelope, body_sha256, bytes, signature_header, signed_at}`
- `event_catalog_get()` staff → `[{kind, family, entity, webhookable, workflow_trigger, label_key}]`

### Integration catalog
- `integration_catalog_get(p_q?)` staff → `{query, items:[{key, collection, provider, connection, access, tags, first_party, installed, company_connected, mine, users, score, match}]}`
- `integration_install(p_key)` global:configure → `{key, connect_required: provider|null}`
- `integration_remove(p_key, p_confirm?)` global:configure → preview `{key, preview:{users, mailboxes, calendars, company_connection, workflows, grants}}` or `{key, removed, mailboxes, calendars, grants}`
- `integration_users(p_key)` global:configure → `[{staff_id, name, via: mailbox|calendar|token|company}]`
- `integration_user_revoke(p_key, p_staff)` global:configure → `{key, revoked}`
- `integration_recommend(p_need)` global:ai + `ai` connected → `{basis:'in_use', catalog:[{key, terms, tags, installed, connected}]}`

### Mobile (deals:see + module mobile)
- `mobile_focus(p_lat?, p_lng?)` → `{hour, name, overdue_activities, deals_past_close, today:[{id, subject, starts_at, done, type, organization, organization_id, deal, deal_id, km}], unread_threads, nearby_10km|null, closing_this_week:{count, value_nok, excluded_currency}, month:{won_value_nok, new_deals, goal}, tasks_due_today|null, chats_waiting|null, contact_rule}`
- `nearby(p_lat, p_lng, p_radius_km=10, p_entities=['organization'], p_filter {customers_only?, no_visit_days?})` → `[{entity, id, title, city|subtitle, km, lat, lng, deal, health, customer, last_visit_at, organization, organization_id}]` (`lat`/`lng`: the organisation's place the distance was measured to, never the device's; 0051)
- `checkin(p_entity, p_id, p_note?)` → `{activity_id}`
- `push_device_register(p_endpoint, p_p256dh, p_auth, p_label?)` → `{id}`; `push_device_revoke(p_id)` → `{id}`; `push_devices_get()` → `{push_ready, setting, module, devices:[{id, platform, label, created_at, last_used_at, failures}]}`; `push_vapid_public_key()` staff (0051, R-MOBILE-03) → the VAPID public key as text, or null while push is not configured (no `vapid_private_key` in Vault); never the private key
- `notification_prefs_get()` → `[{kind, channels}]`; `notification_prefs_set(p_kind, p_channels[])` → `{kind, channels}`
- `sync_apply(p_device, p_mutations [{mutation_id, op: create|update|note|activity_done|stage_move, entity, record_id, base_version, fields, client_at}] ≤ 200)` → `{results:[{mutation_id, result, entity, id, version, conflict?, current?, error?, detail?, replayed?}], applied, superseded, rejected}`
- `sync_changes(p_since bigint=0, p_limit=200)` → `{changes:[{entity, id, version, deleted}], cursor, more}`
- `capture_save(p_entity, p_id, p_file_id, p_kind: photo|audio|scan|card)` → `{id, kind, transcription: queued|not_connected|null}`; `captures_get(p_entity, p_id)` → `{transcription, items:[{id, kind, filename, mime, created_at, transcript, transcript_at}]}`
- `card_draft_save(p_values {name, title?, email?, phone?, organization_id?|organization_name?, basis?})` → `{person_id, organization_id}`
- `record_geo_set(p_entity='organization', p_id, p_lat, p_lng)` (edit right) → `{ok}`

### Bulk and sandbox
- `rec_bulk(...)` (changed) → `{updated, change_id}`
- `bulk_changes_get(p_entity?, p_limit=50)` → `[{id, entity, staff, at, fields, count, reverted_at, revert_result, can_revert}]`
- `bulk_change_revert(p_id, p_reason?)` scope:bulk → `{id, reverted, stale, gone, forbidden}`
- `sandbox_reset()` global:configure → `{removed, created:{organization, person, deal, lead, activity, note}}`; `sandbox_counts()` adds `last_reset`

### Service role only
`api_exec(p_hash bytea, p_op, p_args)` → `{status: 200|429, body, rate:{limit, remaining, reset}, replayed?, reason?}` ·
`worker_api_auth(p_hash)` → `{kind, id, staff_id, mcp, scopes, rate}|null` · `worker_api_usage(p_rows)` · `worker_oauth_token(p_values {grant_type, client_id, client_secret?, code, code_verifier, redirect_uri | refresh_token})` → `{access_token, refresh_token, token_type, expires_in, grant_id}` ·
`worker_oauth_register(p_values {client_name, redirect_uris})` → `{client_id, token_endpoint_auth_method:'none', redirect_uris}` ·
`worker_webhook_claim(p_limit)` → `[{delivery_id, url, body, attempt, timeout_s, headers}]` · `worker_webhook_done(p_delivery, p_status, p_ms, p_error?)` → `{state, next_at?, webhook?}` ·
`worker_integration_call(p_rows)` · `worker_application_ping(p_product, p_ok, p_ms, p_status, p_version?, p_kind?)` → health ·
`worker_status_notice_pushed(p_id, p_ok, p_error?)` · `worker_job_run(p_key, p_state, p_info, p_error?, p_run?)` → `{run}` ·
`worker_push_claim(p_limit)` → `[{notification_id, device_id, endpoint, p256dh, auth, payload}]` · `worker_push_done(p_notification, p_device, p_status)` → `{state}` · `worker_vapid_key()` ·
`worker_capture_transcript(p_file, p_text)` · `worker_geocode_claim(p_limit)` · `worker_geocode_done(p_entity, p_id, p_field, p_lat, p_lng)` · `worker_integration_validate(p_keys)` · `store_product_secrets(p_nonce, p_secrets)`.

## Edge workers still needed

| Worker | Calls | For |
|---|---|---|
| `api` (serves `/v2/*`, not a Next route) | `worker_api_auth`, `api_exec`, `worker_api_usage`; maps errors to HTTP and sets `X-RateLimit-*` | INT-01..03 |
| `mcp` (Streamable HTTP) + OAuth endpoints (`/register`, `/token`; the consent page is an admin page calling `oauth_authorize`) | `worker_oauth_register`, `worker_oauth_token`, `api_exec`, `api_definition` tools | MCP-01..03, UF-22 |
| `webhook-worker` (pgmq `webhook_send`) | `worker_webhook_claim`, DNS check (no private/link-local/metadata), POST 10 s no redirects, `worker_webhook_done`, `worker_job_run` | INT-04, SF-23 |
| `push-worker` (pgmq `push_send`, Web Push VAPID) | `worker_vapid_key`, `worker_push_claim`, `worker_push_done` | MOB-07 |
| `geocode-worker` (pgmq `geocode`, Geonorge) | `worker_geocode_claim`, `worker_geocode_done` | MOB-02/03 |
| transcription (pgmq `transcription`) | `worker_capture_transcript` (refused until `transcription` connected) | MOB-06 |
| `product-command` additions | ping → `worker_application_ping`; every call → `worker_integration_call`; queue job `product_command` (`settings.set_notice`) → `worker_status_notice_pushed`; refuse a command whose scope is not in `installations.scopes` | Applications, banner |
| `orgpuls-events` addition | each batch → `worker_integration_call` (direction `in`) | Applications health |
| AI gateway | `integration_recommend` context → model → `worker_integration_validate` | AIA-06 |
| card scanner (AI gateway, vision) | draft shown for review, then `card_draft_save` | AIA-07 |
| Realtime broadcast | trigger on `app.events` + `realtime.messages` policy (not built, V-P8P-31) | MOB-01 |

## Open

- V-P8P-28: decided — yes, the export right (0049).
- V-P8P-10: the shell's notification filter must include kind `assignment`.
- V-P8P-30: add `retention_rules` rows for `platform_prune` if Security's register should list them.
- D-40 product additions unblock: a ping/version reply, `settings.set_maintenance`, `jobs.retry`, `job.run` events, content read commands.
