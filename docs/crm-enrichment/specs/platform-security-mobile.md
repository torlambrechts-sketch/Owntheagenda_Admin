# Data-requirements spec: Platform, Security and Mobile (Sentral)

Sources read in full: `design-reference/sentral/project/Platform.dc.html`, `Security.dc.html` and `Mobile.dc.html` (markup and logic), `admin-data.js`, the shell's routing in `Sentral Admin.dc.html` (lines 286–293, 413–416), `docs/crm-enrichment/DECISIONS.md` (D-01..D-42), `05-GAP-FEATURES.md` Part 4, `requests/STATUS.md`, `06-QUESTIONS.md` (Q-11, Q-12, Q-23, Q-29..Q-38, Q-42), the other specs in this folder (for names already proposed, e.g. `push_devices`, `sandbox_reset`), migrations `0001`–`0026`, `supabase/functions/_shared/orgpuls.ts` (the command allow-list), `middleware.ts` and `app/login/actions.ts`.

**`coverage-data.js` was not read.** The session's permission policy refused the read. The feature, flow and acceptance texts below therefore come from `INSTRUCTIONS.md` Parts C–G and Appendix 2, which the bundle reproduces word for word for the flows (05, "Flows, settings…", checked by script). Before migrations are written, someone with access should diff the IDs and acceptance texts here against `coverage-data.js`.

Scope: SEC-01..11, INT-01..11, MCP-01..03, MOB-01..08, AIA-06, AIA-07, ENT-01 (the feature-flag tab), CUS-08 (the sandbox, as far as Platform touches it). Flows: UF-15, UF-16, UF-21, UF-22; SF-15, SF-22, SF-23, SF-26 (job alerts), SF-27, SF-31, SF-33 (capture files), SF-34, SF-41, SF-43, SF-44. Part G NFRs: anonymity firewall, access, audit, data residency, recovery, monitoring, privacy, destructive actions, job runtime, provider independence.

**Overall finding.** Every figure on all three screens is fabricated. Platform reads `admin-data.js`'s four demo products (only Orgpuls exists, in `app.products`) and seeds a PRNG (`s=5`) for the sparklines and the API usage bars. Security is literals from top to bottom, down to the IP addresses. Mobile is a showcase of six phone mock-ups filled with demo strings. Three things follow:

- **The database already has the skeleton.** It has the staff table with permission sets, the audit and outbox, the settings register (with `api_rate`, `safeguards`, `count_limits`, `session_idle`, `ip_allowlist`, `login_alerts`, and the fixed `mfa` and `firewall`), `app.modules`, `integration_connections` with Vault secrets, `privacy_requests` with the 30-day clock, `recovery_codes` (a table with no functions), pg_cron and pgmq, the dispatcher with its subscriber cursors, and `app.url_public`.
- **Nothing a user can act on here exists yet.** That covers the login log, sessions, API tokens, OAuth, webhooks, the catalog, MCP, job runs, incidents, sub-processors, erasure and push.
- **Two changes reach into code every RPC depends on.** API tokens and MCP grants must make `app.me()` answer for a token. Remote log-out must make `app.me()` refuse a revoked session. Both are the riskiest work in this spec (§5).

Several design texts conflict with accepted decisions. Each is named where it occurs and collected in §4.

---

## 1. Platform screen (routes `/applications` = tab `apps`, `/api` = tab `api`; Platform › Applications and Platform › API and integrations)

The shell imports the same component twice, with `tab="apps"` or `tab="api"` and `product={{ product }}`. **The component never reads `props.product`.** The selected application is local state that defaults to `orgpuls`. The real build preselects the shell's product when one is chosen and falls back to the first installed product.

### Views and states
Eight tabs: Applications, REST API and tokens, Webhooks, Integration catalog, AI connector, Job monitor, Feature flags, Content. Overlays: the "Connect an application" modal and a toast. The design has no loading, empty, error or no-permission states. Per D-41 they need building:
- Applications with only Orgpuls installed (a one-card grid), and with none installed.
- A product that does not answer the test call (error band on its card, "Last answer N min ago").
- No tokens; no webhooks; no deliveries yet; a catalog search with no match.
- MCP switched off. The design has this one: "Off — new connections are blocked and existing ones removed".
- No job runs in 24 h; no product flags (the product has no flag command).
- Content for a product without content commands.
- No permission: tabs whose right the staff member lacks are shown read-only with the Settings screen's "You can read these… Changing them needs the right …" line (V-SETTINGS-33). Tokens are always visible to their owner.

Missing controls the flows require (D-41, built in the design's language):
- create, pause and delete a webhook, plus test and redeliver (UF-16 steps 3–4);
- register and remove an OAuth app (UF-16 step 2);
- create a personal token when none exists (the design shows only "Rotate my token");
- per-user management of an installed integration ("Settings · users" has no handler);
- confirmation with preview for maintenance mode and for removing an integration (D-30 pattern).

### 1.1 Applications

| Element | Prototype | Real source / formula |
|---|---|---|
| Cards (Orgpuls, Skiftly, Avvikspunkt, Kursrom) | `D.products`, four demo products | `app.products` ⋈ `app.installations`. Only `orgpuls` exists. The others appear when they are installed. |
| Initials, name, description | demo | `products.name`, `products.description` (0007). Initials = first letter. |
| Region | demo "EU · Stockholm" | NEW `installations.region`, entered at connection. **Conflict with D-35** for the platform's own region (§1.6). A product's region is that product's fact. |
| Status Operational / Degraded / Beta | demo | Operational / Degraded = derived: Degraded when the last 15 min of `integration_calls` show error rate > 1.5 % or p95 > 500 ms (the design's own colour thresholds), or when the last event is older than the product's expected push interval (Orgpuls pushes every 5 min, README) plus 5 min. **Unreachable** when the last ping failed (NEW state, D-41). Beta = NEW `products.stage` (`ga` / `beta`). |
| Sparkline (24 points) | **Fabricated** (PRNG `s=5`, plus a bump for "Degraded") | Requests per hour for the last 24 h from NEW `integration_calls` (both directions). |
| req/min | **Fabricated** (`p.rpm`) | `count(*) / 15` over the last 15 min of `integration_calls`. **Definition gap:** the platform sees only Sentral ↔ product traffic (commands out, event batches in), not the product's own API traffic. Label it "calls/min with Sentral" or have the product report its traffic (D-40). Recommendation in §6. |
| p95 | **Fabricated** | `percentile_cont(0.95)` of `duration_ms`, last 15 min, outbound calls. |
| errors | **Fabricated** | share of calls with `ok = false`, last 15 min. |
| orgs | demo orgs | `count(*) from account_products where product = p and status = 'active'`. |

**Connection panel**

| Row | Prototype | Real |
|---|---|---|
| Base URL | demo | `installations.api_url` (exists) |
| API version | demo "v2.14.0" | NEW `installations.api_version`, from the product's answer to the ping. Needs a version field in Orgpuls' reply (D-40). Until then "—". |
| Auth "OAuth 2.0 client credentials · 3 keys" | **Fabricated, and wrong.** | The real scheme is HS256 command tokens that live 2 minutes, signed with the product's token secret, and HMAC-verified inbound events (0002, `product-command`, `orgpuls-events`). Render "Signed commands · token secret ✓ · webhook secret ✓" from the existence of `vault.secrets` named `<product>_token_secret` / `<product>_webhook_secret` (through a definer function that returns booleans, never values). |
| Inbound webhooks "6 subscriptions · signed" | **Fabricated** | Inbound is one signed endpoint. Show "N event kinds · signed" = distinct `events_in.kind` in the last 30 days. |
| Product key | demo | `products.key` (exists) |
| Last sync | demo "40 s ago" | `max(events_in.received_at) where product = p` |
| Connected since | demo | NEW `installations.created_at` (0001 has only `updated_at`). Back-fill with `min(events_in.received_at)`. |

**Data synced** (the "org.nr is the shared customer key" header is true: 0001 links by `org_number`)

| Row | Prototype | Real |
|---|---|---|
| Organizations "two-way" | demo count, "40 s ago", Healthy | `count(account_products active)`. Last = latest `org.*` event. **"Two-way" is false today**: the product sends, and Sentral writes back only through commands. Say "app → Sentral · commands back". |
| Users and roles 1 240 | **Fabricated** | `count(*) from members where product = p and active` |
| Subscriptions "Stripe mirror → both" | demo count | `count(*) from subscriptions where app.sub_mrr(s) > 0`. **Conflict with D-22**: the source is the `billing.changed` mirror, one way. Copy: "billing.changed → Sentral". |
| Usage events "18 k/day" | **Fabricated** | `count(*) from events_in where product = p and received_at > now() - 1 day` |
| Feature flags 8 | **Fabricated** | the count returned by the product's `modules.list` command (§1.7), else "—" |
| State Healthy / Lagging 3 min | demo | Lagging = minutes since the last event of that family beyond the expected interval. |

**Events received.**
- The prototype's names (`orgpuls.org.signed_up`, `orgpuls.survey.sent`, `orgpuls.user.logged_in`, `orgpuls.payment.failed`, `orgpuls.trial.day_7`) are **fabricated** and do not exist. Real kinds are two-part `object.action` (D-14): `org.created`, `org.deleted`, `org.attribution`, `billing.changed`, `member.joined`, `member.left`, `usage.daily`, `survey.round`, `counts.updated`, `milestone.reached`, `member.state`, `logins.daily`, `support.requested`, `contact.submitted`, `demo.requested`.
- Counts = `count(*) group by kind` over 30 days. The design gives no window. Choose 30 days, as `platform_status` does, and log it in DEVIATIONS.
- The "use" column comes from NEW registry `product_event_kinds.uses` (data, not code).

**Remote actions Sentral may call.**
- The REST paths shown (`POST /orgs/{orgnr}/trial/extend` …) are **fabricated**.
- Real: the allow-list in `_shared/orgpuls.ts`: `orgs.list|get|deletions|delete_now|resync`, `billing.cancellation|extend_trial|cancel|cancel_withdraw`, `translations.*`, `overrides.*`, `modules.*`, `locales.*`, `legal.*`, `settings.notice|set_notice|set_indexing`.
- `suspend`, `export` and `support-access` do not exist. They are D-40 additions, shown only once present.
- The screen reads NEW `product_commands`, a mirror of the TS allow-list with `used_by`. A test asserts the two are equal. The TS list stays the authority; the edge function never reads the table.

**Footnote** "Response-level survey tables are never exposed through this API — aggregates with n ≥ 5 only".
- **Conflict with D-19 and with Orgpuls' k.** The platform receives no survey figures at all, only counts and dates. Orgpuls' threshold is per organisation (3..10), frozen per round, not 5.
- Copy: "Survey answers never reach Sentral — the products send counts and dates only."

**Actions**
- **Test connection.** Toast with demo latency. Real: `product-command` sends a harmless read (`orgs.list` with limit 1, or a D-40 `platform.ping`). It writes an `integration_calls` row and `installations.last_ping_*`, and reports "200 OK in N ms" or the error. It is audited, as every command is today.
- **Select a card.** Local selection only.
- **＋ Connect an application** (modal: name, base URL, client ID, client secret, product key, scopes). **Conflicts with 0002.** 0002 promises the product's secrets "never pass through a person". The modal has a person type a client secret. Real:
  - `application_connect` (owner only, fresh second factor, §3.9) inserts `products` and `installations` (name, api_url, public_key, region, scopes, stage).
  - It returns a **one-time intake code bound to that product key**. The product's operator posts the secrets to `secret-intake` with it.
  - The intake must refuse to overwrite an existing product's secrets. `store_product_secrets` today accepts any `<key>_(token|webhook)_secret`, so it needs `intake_nonces.product` and a check.
  - The modal loses the client ID and secret fields. Log the change in DEVIATIONS.
  - Scopes: the chips (`orgs:read`, `users:read`, `subscriptions:read`, `events:write`, `flags:read`, `support-access:write`) do not match the real command scopes (`orgs:read|write`, `billing:read|write`, `translations:*`, `modules:*`, `legal:*`, `settings:*`). Use the real vocabulary. A command whose scope is not in `installations.scopes` is refused by `product-command` before signing.
  - "Test and connect" = ping, then `orgs.resync`.

### 1.2 REST API and tokens (INT-01, INT-02, INT-03)

| Element | Prototype | Real |
|---|---|---|
| Endpoint list (8 rows) | literals | Generated from the registry (`app.entities`, `entity_columns`, `app.fields`) by `public.api_definition()`, which returns OpenAPI 3.1. INT-01: "generated from the same registry". Rows = method, path, cost. |
| Token cost per endpoint (1, 2, 2, 2, 1, 4, 1, 3) | **Fabricated**, and different from the spec | Part F reference values: get 2, list 20, update 10, delete 6, delete-list 10, search 40. Create is not given; use 10 (as update). Stored in NEW `api_costs`. Shown only while `api_rate` ≠ off; otherwise the column reads "—". **Conflict between design and spec:** follow Part F. |
| "API reference · client libraries · collections →" | `noop` | The OpenAPI document and a request-collection export generated from it. Client libraries are out of scope until asked (open question). |
| Footnote "Every entity incl. custom fields · cursor pagination · same permissions as the calling user" | text | True only if the gateway runs every call through the same definer RPCs as the user (§3.9). |
| Token rows: name, masked key, scope, last used | literals (`sk_live_…f3a9`, "Full · as user", "2 min ago") | NEW `api_tokens` (personal) and `oauth_grants` ⋈ `oauth_apps` (apps). Masked = `prefix || '…' || last4`. Scope: "Full · as user" = `{*}` for personal tokens; app grants list their scopes. Last used = `last_used_at`. A staff member sees their own rows; `global:security` sees all. |
| Rate limits badge "Off (setting)" | literal | `app.setting('api_rate')` (exists; default off) |
| Requests per hour · 24 bars | **Fabricated** (sine + PRNG) | NEW `api_requests_hourly`, last 24 h. The empty treatment when there are no calls. |
| "412 k total" | **Fabricated** | `sum(requests)` over the same 24 h |
| Budget text "base × plan multiplier × seats …" | text | Budget/day = `api_budget_base` (30 000) × `api_plan_multiplier` × active staff count. **D-17**: nothing is sold, so there is no plan. The multiplier is a setting (default 1), not a plan attribute. |

**Actions**
- **Rotate my token.** Toast only. Real (INT-02: "one active token at a time", "rotating invalidates the old one at once"): in one transaction, revoke the caller's active token (`revoke_reason = 'rotated'`) and insert a new one. The plaintext is returned **once** and never stored; the DB keeps `sha256(token)` only. It needs a fresh second factor.
- **Revoke** (per row). Toast "Revoked at once". Real: `revoked_at = now()`. Effect at once, because every call resolves the token by hash and checks `revoked_at is null` (INT-02 AC "a revoked token or grant is refused"). Revoking a grant deletes its refresh token too.
- **Create token / register OAuth app** (D-41, missing from the design). OAuth apps need `global:configure`. MCP clients register dynamically (§1.5).

**The API itself (INT-01, SF-22).**
- An edge function `api` serves `/v2/*`. It must not be a Next.js route under `/api`: `app/(admin)/api/page.tsx` already owns `/api`, and `middleware.ts` forces a cookie session with aal2 on every non-public path.
- Per call:
  1. Hash the bearer token and resolve it (`worker_api_auth`).
  2. If `api_rate` ≠ off: check the 2-second burst window for that principal, then deduct the endpoint's cost from the day's budget.
  3. Call `public.api_exec(p_token_hash, p_op, p_args)`. It sets the token principal for the transaction (§3.9) and dispatches to the existing definer RPCs (`rec_list`, `rec_get`, `rec_save`, `rec_delete`, `search`, `lead_convert`, `records_merge`). SF-01 runs unchanged.
  4. Respond with `X-RateLimit-Limit`, `X-RateLimit-Remaining` and `X-RateLimit-Reset`. Over either limit: HTTP 429 (INT-03 AC).
- Usage is written in batches to `api_requests_hourly`.
- At 75 % and 100 % of the daily budget, staff with `global:configure` are notified once per day per threshold (`api_budget_day.warned*_at`). Email goes out when the transactional provider exists (D-07); until then, in-app.
- Idempotency keys on create (Part F conventions): NEW `api_idempotency(principal_id, key, response, created_at)`, kept 24 h.

### 1.3 Webhooks (INT-04, SF-23, D-32)

| Element | Prototype | Real |
|---|---|---|
| Subscriptions (event, URL, state) | literals | NEW `webhooks`, scoped to the owner, or all for `global:configure` |
| Event names `deal.updated`, `person.added`, `deal.won`, `organization.deleted` | literals | Real outbox kinds (0004, 0006, 0009): `<entity>.created|updated|deleted|merged`, `deal.stage_changed|won|lost|reopened`, `activity.completed|reopened`, `lead.converted`, `note.created`, `consent.changed`, `ticket.created|replied`, `problem.resolved`. **`person.added` does not exist; the platform says `person.created`.** Part F's "added" naming was not followed. Keep `created` and say so in the API reference. Only kinds with `event_catalog.webhookable = true` may be subscribed. Security, export and audit events are never webhookable (they carry staff data). |
| State Active / Retrying / Blocked (private address) | literals | `webhooks.state`: active, retrying (has a delivery in backoff), banned (until `banned_until`), blocked, paused, deleted. **`http://10.0.4.2/internal` cannot be saved**: `app.url_public` refuses non-https and private hosts at save. Blocked arises only when the worker's DNS check resolves a public name to a private address at send time. |
| "Webhooks per user: unlimited (setting)" | literal | `app.count_limit()` (exists; `count_limits` applies to INT-04). The text renders the real value. |
| Deliveries (time, event, host, code, tries "3 / 5") | literals | NEW `webhook_deliveries`. **"3 / 5" contradicts INT-04**: retries after 3, 30 and 150 s make 4 attempts. Show "attempt n / 4". |
| Payload "current and previous state" | literal JSON | `webhook_deliveries.request_body`, as sent. Shape: `{event, object, id, occurred_at, meta:{actor_id, source, attempt, webhook_id}, current, previous}`. `meta.product_id` is dropped (CRM events have no product). Reading a payload is an audited read: it holds record values. |
| "Signature header: open decision (A4)" | text | **Conflict with D-32**: decided, HMAC-SHA256. Header `Sentral-Signature: t=<unix>,v1=<hex HMAC-SHA256(secret, t || '.' || body)>`. One secret per webhook in Vault, shown once at creation. |
| "Retry and ban policy: source values (safeguard)" | text | `app.setting('safeguards')` (exists). Source values: 10 s timeout; retries at 3, 30 and 150 s; a 30-minute ban after 10 consecutive first-attempt failures; deletion after 3 days without success, with the owner notified (SF-23 step 5). |

**Mechanics.**
- NEW event subscriber `webhooks` (`app.sub_webhooks`) in `event_subscribers` (0021 dispatcher, every minute). For each event with matching active webhooks it enqueues `webhook_deliveries`, attempt 1.
- **Visibility:** a delivery is made only if the webhook's owner may see the subject (`app.visible` under `app.acting_as = owner`). Fields hidden from the owner are left out.
- **Previous state:** outbox payloads hold only the changed field names (`{fields:[…]}`, 0006). `previous` = `current` overlaid with the changelog's `old_value` for those fields at the event's time. `current` = the row at dispatch (≤ 1 min later). Document it.
- The worker (`webhook-worker` edge function, pgmq job `webhook_send`):
  1. Claim the delivery and read the secret through a service-role function.
  2. Resolve DNS and refuse private, link-local and metadata addresses.
  3. POST with a 10 s timeout, following no redirects.
  4. Report back, then schedule the retry, the ban or the deletion.

**Actions (none in the design except picking a delivery; D-41 adds them):** create, edit, pause, delete, "Send test" (a synthetic `ping` event), "Redeliver" (a new attempt-1 delivery of a past event).

### 1.4 Integration catalog (INT-05..11, AIA-06, D-42)

| Element | Prototype | Real |
|---|---|---|
| Four collections, eight entries | literals | NEW `integration_catalog`, seeded with the eight entries (D-42: categories via first-party modules; named apps through this catalog and the automation platforms). |
| Installed / Available | **Fabricated** (`installed: {gw, m365, slack, acc}`) | NEW `installed_apps` (company-level install). Per-user state reads the existing grants: `mailboxes` (0020) and `calendar_connections` (0010) for Google and Microsoft; `integration_connections` (0021) for Slack, Teams and accounting; `api_tokens`/`oauth_grants` for automation platforms; `app_extensions` for extensions. |
| "Access: …" | literal | `integration_catalog.access` (scope labels) |
| Search box and "Recommendations by the assistant" | first-word substring match; the "assistant" is **fabricated** | Search: trigram and full text over name, description and tags (`pg_trgm` exists, 0011). AIA-06 recommendation: an AI-gateway call (SF-24) with the catalog as context that returns **catalog keys only**, Zod-validated against the table. "What similar companies use" has no data in a single-company back-office, so recommendations use only what is installed and connected. The hint changes to "Suggested from what you already use". |

**Actions**
- **Install.** Toast. Real: `catalog_install(key)` inserts `installed_apps`. For a company-level connector it starts the OAuth or credential flow; the token goes to Vault (D-18) and `integration_connections` becomes `connected`. For per-user connectors, install only makes "Connect" available to users.
- **Remove.** Toast "access revoked". Real (INT-11 AC "removing an integration revokes its access"):
  1. A preview: users connected, workflows using it (`app.wf_blockers` will now list them).
  2. Confirm.
  3. Delete the Vault secrets, set connections `not_connected`, revoke the app's grants, and disconnect per-user mailboxes and calendars of that provider. The preview names each effect, because this is destructive (D-30 pattern).
  4. Audit and emit `integration.removed`.
- **Settings · users** (no handler). Real: the list of staff connected to this integration, with per-user revoke.

### 1.5 AI connector (MCP-01..03, UF-22)

| Element | Prototype | Real |
|---|---|---|
| Company switch | local state | NEW setting `mcp_access` (`on`/`off`, default `on`: unrestricted, D-16) |
| State "On for the company · 3 assistants connected" | literal | `count(*)` of active `oauth_grants` whose app kind is `mcp` |
| URL `https://sentral.orgpuls.no/mcp · OAuth login` | literal host | The deployment's own host, from configuration, never a literal. `sentral.orgpuls.no` is not a host we own in the decisions (D-28 names `go.owntheagenda.com` for public pages). |
| Sync mode "On · last index 12 min ago" | literal | NEW setting `mcp_sync` (default on). Last index = the last succeeded `job_runs` row of `mcp_index`, every 30 min (MCP-01). |
| Connected assistants (Claude · Tor Lambrechts · 5 min ago …) | literals | `oauth_grants` ⋈ `oauth_apps` (kind `mcp`) ⋈ `admins`; `last_used_at`. A user sees their own; `global:configure` sees all. |
| Tool catalog (8 rows) | literals | Generated from `api_definition()` (MCP-02: names and schemas from the API definitions). The source documents 37 tools. D-42 adds `convert_lead_to_deal`. |
| Footnote "Calls run with the user's permissions · changelog source = connector · survey data unreachable" | text | True if MCP calls go through `api_exec` with source `assistant` (changelog source `assistant` exists, 0004). Audit `source = 'mcp'`. |

**Mechanics.**
- Edge function `mcp` (Streamable HTTP). It uses the same token path as the API (§3.9) and the same rate limits (MCP-01: "counts against API limits").
- Assistants connect through OAuth 2.1 with PKCE and dynamic client registration (RFC 7591), which current MCP clients use. Dynamically registered apps are `oauth_apps.kind = 'mcp'`, public (no secret), with https redirect URIs only.
- **Switch-off (MCP-03):**
  - `mcp_set(false)` writes the setting, revokes every `mcp` grant and refuses new authorisations.
  - Independently, the token path checks `mcp_access` on every call. Even a grant missed by the revocation fails (AC "after switch-off no assistant call succeeds").
  - It does not touch API tokens or other integrations.
- `setting_set('mcp_access', …)` must not bypass the revocation. Give the register a per-key validator/effect hook (§3.6) or refuse the key in `setting_set`.
- The sync index (NEW `mcp_index`) holds title and search text per record with `owner_id` and `visibility`. It is filtered by `app.visible` at query time, never at index time. It holds CRM records only; no product table is indexed.

### 1.6 Job monitor (Appendix 2 System operations; Part G Monitoring; SF-26 step 6)

| Element | Prototype | Real |
|---|---|---|
| Queued 18 / Running 4 / Failed (24 h) 3 / Succeeded (24 h) 2 914 | **Fabricated** | Queued = `pgmq.metrics('jobs').queue_length` plus `job_runs` in `queued`. Running, Failed and Succeeded = `job_runs` by state over 24 h. |
| Job rows (name, app, state, time, info) | literals | NEW `job_defs` (registry) and `job_runs`. Platform cron jobs are wrapped by `app.run_job(key)`, which writes the run row. Existing schedules: `platform-purge`, `-mrr-snapshot`, `-reminders`, `-duplicates`, `-mail-due`, `-dispatch`, `-workflow-resume`, `-workflow-dates`, `-feed-checks`, `-scores`, `-pipeline-snapshot`, `-mrr-tenants`, `-health`, `-web-salt`, `-web-prune`. `cron.job_run_details` is the fallback source for status and duration. |
| Orgpuls jobs (survey sends "41 orgs · 1 812 invitations", reminders, result unlocks "7 groups unlocked", retention purge "12 orgs") | literals | Not visible to the platform today. Needs a count-only `job.run` event from the product (D-40), projected into `job_runs` with `product = 'orgpuls'`. Info keys are counts only (D-19: "7 groups unlocked" is a count, allowed; never group names). |
| "Brønnøysund re-sync · Timeout", "Shift sync · Skiftly", "Search Console import", "MCP sync index" | literals | Brreg re-sync = `orgs.resync` and enrichment jobs. Skiftly is not installed, so the row does not exist. The Search Console import exists only as a table (0025); its job is a NEW `job_defs` row when the provider is connected. MCP index per §1.5. |
| **Retry** | sets local state | `job_retry(run)`: platform jobs re-run through `job_defs.retry_fn`, or a `pgmq.send`; product jobs through a D-40 `jobs.retry` command. Needs `global:configure`. Audited. |

A failed run notifies `global:configure` staff (notification kind `system`). This closes SF-26 step 6 ("a failed run raises an alert").

### 1.7 Feature flags and maintenance (ENT-01; Appendix 2 System operations)

| Element | Prototype | Real |
|---|---|---|
| Flag rows `orgpuls.nynorsk_survey` (Pilot · 6 orgs, 8 %) … | literals | Two real sources. (a) **Platform module switches**: `app.modules` (0005); `sentral.crm_deals` is `modules.deals`. (b) **Product flags** through the existing Orgpuls commands `modules.list`, `modules.set_status`, `modules.pilot`, `locales.pilots` and `locales.pilot` (D-23: product content and configuration stay in the product; the platform uses its commands). Skiftly, Avvikspunkt and Kursrom rows do not exist. |
| Scope and % bar | literals | % = pilot organisations ÷ active tenants of the product (computed from the command reply and `account_products`). "Staged rollout 35 %" exists only if the product's command reports a percentage, otherwise the bar is omitted. |
| Toggle | local state | Module: `module_set` (exists, `global:configure`). Product flag: `product-command` `modules.set_status`, with a reason. Audited by the existing command audit plus `customer_action_log`-style detail. |
| Maintenance mode · all applications | local toggle, no confirmation | Per product. Orgpuls has `settings.notice` / `settings.set_notice` for the banner. A maintenance switch is a D-40 addition. It is destructive (it stops the product for every customer), so it needs a preview, a typed confirmation (the product key), owner rights and a fresh second factor. |
| Banner text and preview | textarea pre-filled with a literal | Load the current notice with `settings.notice`. Save with `settings.set_notice`. History in NEW `status_notices`. |
| "Linked to known error T-2316 · shown until resolved" | literal | `status_notices.problem_ticket_id` → a problem ticket (0012). `problem_resolve` (exists) queues a job that clears the notice through the command. This closes Tickets R-4's banner half. |

### 1.8 Content (Appendix 2 Content management; D-23)

All six cards are **fabricated** (versions, authors, dates, counts).
- **D-23:** question set, pulse templates, tiltak library, legal references and the product's email and SMS templates stay in Orgpuls. Each card reads through existing commands where one exists:
  - legal references → `legal.reviews` (the "2 references not reviewed in 12 months" count comes from its reply);
  - translations and templates → `translations.list` / `translations.sources`;
  - published modules → `modules.list`.
- Question set, pulse templates and tiltak library have no read command. Those cards say "Managed in Orgpuls" with no number until D-40 adds the commands.
- **Edit draft** (no handler) and **Roll back** (toast) are disabled until the product offers draft and rollback commands. Never fake them.
- "Help texts and announcements" is platform data: `help_articles` and `ticket_macros` (0012, 0023 `help_get`). That card is real now.

---

## 2. Security screen (route `/security`; SEC-01..11, UF-15, SF-27, SF-15, SF-43)

### Views and states
Seven tabs: Security dashboard (default), Alerts and rules, Device and login history, SSO and two-factor, Data protection, Privacy compliance, Audit log. Toast only; no overlays. SEC-01: "Admin only". The whole screen needs `global:security`. Without it: the no-permission state (D-41), except the user's own sessions and recovery codes, which every staff member reaches from their profile.

Missing states (D-41):
- no live sessions besides your own;
- no security events in 7 days;
- no login history for a user;
- the email provider not connected, so alerts go in-app only (`not_connected` band);
- Slack not connected (the `#admin-logins` route greyed out);
- no IP rules;
- SSO not configured;
- no incidents;
- no audit match;
- the erase search with no hit;
- an erasure blocked because the person is a product user (§2.6).

Missing controls (D-41): add, edit and delete an IP rule or time window, with the preview SEC-03 demands; generate recovery codes; reset a person's second factor (owner, D-11); log an incident (the design's "＋ Log incident" only toasts); add and edit a sub-processor; complete an access review.

### 2.1 Security dashboard (SEC-01; AC "the figures match the login log")

| Figure | Prototype | Real source / formula |
|---|---|---|
| Signed in now | `live.length` of literals | `count(*) from staff_sessions where ended_at is null and last_seen_at > now() - idle_timeout` |
| New devices · 7 d "2 · Hanna Vik, Jonas Dahl" | **Fabricated** | `login_log where outcome = 'success' and new_device and at > now() - 7 d`; names from `admins` |
| New locations · 7 d "1 · Stockholm, SE" | **Fabricated** | same, `new_location` |
| Security events · 7 d "6 · 0 critical" | **Fabricated** | `count(*) from security_events` over 7 d; `count(*) filter (where severity = 'critical')` |
| Forced logouts · 7 d | `1 + loggedOut` | `staff_sessions where end_reason = 'forced' and ended_at > now() - 7 d` |
| MFA coverage "89 % · 8 of 9 enrolled" | **Fabricated** | active, non-sample staff with a verified TOTP factor (`auth.mfa_factors`, as `staff_list` already computes) ÷ active staff |
| "Session timeout 30 min idle · IP allowlist on" | literal | `app.setting('session_idle')` (default `on_30`), `app.setting('ip_allowlist')` (default **off**, D-29). **Conflict with D-29**: the design says "on". Render the real value. |
| Live session rows (name, place · device · browser, since) | literals | `staff_sessions` ⋈ `admins`: `city`, `country`, `device_label` (parsed from the user agent at sign-in), `created_at` |
| Assessment (4 issues, "N open") | literals | Derived on read by `app.security_issues()`, no table. Each rule is a query: staff invited more than N days ago with no verified factor; a mailbox in `reauth`/`error` or with `watch_expires_at` within 3 days (0020); personal API tokens older than 180 days; access review due (`access_reviews`); IP allowlist on with no rule; webhooks banned; jobs failed in 24 h. "N open" = the count. An issue disappears when its condition clears. The prototype's "resolve" just hides it, which would be fabrication. |
| Last 7 days (when, kind, text, outcome) | literals | `security_events` over 7 d. Text from a message key plus params (ids and counts; names resolved at read). Outcome from `alert_state` / `outcome`. |

**Actions**
- **Log out** (per live row). Toast. Real: `session_revoke(session_id)` sets `staff_sessions.ended_at`, `end_reason = 'forced'` and deletes the `auth.sessions` row (its refresh tokens go with it). AC "ends its session at once": `app.me()` refuses a JWT whose `session_id` claim has an ended `staff_sessions` row (§3.9). The access token would otherwise live until expiry.
- **Issue buttons:**
  - "Send reminder" → `staff_mfa_reminder` (email when D-07's provider exists, else `not_connected`; an in-app notification always);
  - "Re-authenticate" → navigates to the mailbox;
  - "Rotate" → navigates to the token;
  - "Start review" → `access_review_start`.

### 2.2 Alerts and rules (SEC-02, SEC-03; D-29)

| Element | Prototype | Real |
|---|---|---|
| Recipients "to security@orgpuls.no · and Slack #admin-logins" | literal | NEW setting `security_alert_recipients` (default: every active staff member with `global:security`). Slack channel = `integration_connections('slack').config.channel`. The header renders the real list, or "in-app only — no email provider" (`not_connected`). |
| Six alert toggles, all on | local state | One register key per trigger: `alert_new_device`, `alert_user_invited`, `alert_failed_logins` (numeric option, source value 3), `alert_password_reset`, `alert_large_export` (numeric option: rows), and the existing `login_alerts` for "Admin logins (all) to Slack". Options `off` / `immediate` / `digest`; digest time = NEW `alert_digest_time` (default 08:00 Europe/Oslo). **Conflict with D-29**: login alerts default off, and the design shows everything on. Defaults are in §3.6. |
| Password strength "12+ chars · mixed" | literal | A Supabase Auth project setting (`supabase/config.toml`, D-33), not a database value. Show it from a build-time read of `config.toml` and add a CI test that the hosted project matches (open question). |
| Password expiry "Never (MFA on)" | literal | NEW setting `password_expiry` (`never` / `days`, numeric), default `never` |
| Password reuse "5" | literal | NEW setting `password_reuse` (`off` / `number`), default **off**. "5" is the source value. Enforcement needs `password_history` (open question). |
| IP restriction "Office + VPN ranges · 3 rules" | literal | `ip_allowlist` (exists, default off) plus NEW `security_rules` (`kind = 'ip_range'`, `cidr`). Text = "N rules" or "Off". |
| Time restriction "Off" | literal | NEW setting `signin_hours` (`off` / `on`, default off) plus `security_rules` (`kind = 'time_window'`) |
| Session timeout "30 min" | literal | `session_idle` (exists) |

**Enforcement (SF-27; SEC-03 AC "a login from a blocked IP is refused").**
- The sign-in server action and `middleware.ts` call `worker_login_event` / `worker_session_seen` (service role). The trusted client IP is the one Vercel sets (`x-vercel-forwarded-for` / `x-real-ip`), never a header the client chose.
- When `ip_allowlist = on` and the IP is in no rule, or `signin_hours = on` and now is outside every window:
  - the sign-in is refused and logged (`outcome = 'blocked_ip'` / `'blocked_time'`);
  - a live session that moves outside is ended with that reason.
- `app.me()` reads the session row, so the database refuses too, even if a JWT is replayed outside the app.
- Idle timeout: `last_seen_at` older than the setting ends the session (`idle_timeout`).
- **Preview (SEC-03):** `security_rule_preview(change)` lists staff whose sign-ins in the last 30 days would have been refused. The register needs a validator (§3.6) so that switching `ip_allowlist` on **refuses when the caller's own current IP is outside every rule** (forbidden, detail `self_lockout`).

### 2.3 Device and login history (SEC-04)

| Element | Prototype | Real |
|---|---|---|
| Staff selector | `D.staff` | `staff_list` (exists) |
| Rows: login time, device, location, IP, method, session end | literals (IPs `84.208.12.40` …) | NEW `login_log` ⋈ `staff_sessions` for that staff member over the last 60 days. Method from `login_log.method`. Session end from `end_reason` and `ended_at`, "Active", or "Blocked — IP rule" (`outcome`). "· new" = `new_device`. |
| "SSO · Entra ID", "SSO + Face ID", "Password" methods | literals | **Conflicts with D-11/D-31**: TOTP only, SSO later (Google or Microsoft) and still followed by TOTP. No Face ID (WebAuthn is not a factor under D-11). Methods: `password_totp`, `google_totp`, `microsoft_totp`, `recovery_code`. |

**Log out of all devices** (toast only) → `staff_sessions_revoke_all(staff)`. It ends every open session of that person, as `session_revoke` does.

Retention: `login_log` and ended `staff_sessions` rows (they hold IPs) are purged after 60 days. New-device and new-location detection must outlive that, so NEW `staff_devices(staff_id, device_hash, first_seen_at, last_seen_at, label)` and `staff_locations(staff_id, country, city, first_seen_at)` keep no IP.

### 2.4 SSO and two-factor (SEC-05, SEC-06; D-11, D-31)

| Element | Prototype | Real |
|---|---|---|
| Microsoft Entra ID (SAML) "orgpuls.no · 9 users · Connected" | literals | **Conflict with D-31**: SSO comes later, as Google or Microsoft OAuth sign-in, still followed by TOTP. No SAML, no Okta. Real: NEW `sso_providers` (`google`, `microsoft`), `enabled` (default false), `allowed_domains`. "N users" = staff whose latest successful `login_log.method` used that provider. Provider credentials are Supabase Auth project configuration, not database rows. The row shows "Not configured" until the project has the provider. |
| Okta (SAML) "Available" | literal | Left out (D-31). Log in DEVIATIONS. |
| Sign in with Google "Allowed for @orgpuls.no · On" | literal | `sso_providers('google')` |
| "Admin identities are separate from customer logins · quarterly access review due 1 Jan · break-glass access logged" | literal | Separate identities: structural (0001, separate project). Review due = `access_reviews` (last `completed_at` + 3 months). Break-glass: open question (§6). |
| Badge "Enforced for everyone" | literal | True and fixed: the `mfa` register key is `fixed` (0005), and `app.is_admin`/`app.me` demand aal2. Render from the register. |
| Authenticator app "7 users" | literal | staff with a verified TOTP factor |
| Email code "1 user" | literal | **Conflict with D-11** (TOTP only). Row omitted; DEVIATIONS. |
| Not enrolled "1 user · Ola Nilsen" | literal | active staff without a verified factor, names listed |
| Recovery codes generated "8 of 9" | literal | staff with at least one unused `recovery_codes` row ÷ active staff |
| Footnote "Authenticator app or email code · account recovery codes · remembered login email" | literal | Copy fix: "Authenticator app · recovery codes · owner reset". A remembered login email is a browser concern, not data. |

**Gaps in existing data.**
- `app.recovery_codes` exists (0003, SHA-256, used once) but has **no function**. D-11 is not fully met until these exist:
  - `recovery_codes_generate()`: self; returns 10 codes once and replaces the old ones.
  - `recovery_code_redeem(code)`: callable at **aal1**, the one deliberate exception to aal2. It marks the code used, deletes the caller's TOTP factors and ends their other sessions, then the user enrols again.
  - `staff_mfa_reset(staff, reason)`: owner (`admins.role = 'owner'`) with a fresh second factor; deletes the target's factors and ends their sessions.
- SSO: a person signing in with Google still needs an `admins` row. No just-in-time provisioning; staff are invited (SEC-09 via `staff_save`). SEC-05 AC "a user provisioned at the identity provider can log in without a local password" holds for invited staff.

### 2.5 Data protection (SEC-10; Part G anonymity firewall, residency, recovery; D-35)

| Element | Prototype | Real |
|---|---|---|
| Firewall headline and six cards (No grants, No references, Aggregates only, No tracking in surveys, No contacts from respondents, Tested) | literals | Claims, not data. Back each with `firewall_status()`, which runs the structural assertions live: no table or column with response-level names in any schema; no FK or view referencing one; no grant to client roles on `app`; no product event kind with respondent fields in `events_in` (D-34). It shows the last CI result of `structure_invariants.sql` with its commit. **Copy conflicts**: "Admin reads go through views that enforce n ≥ 5" is wrong here. The platform has no survey data at all (D-19), and Orgpuls' k is 3..10 per organisation. Copy: "Sentral receives counts and dates only — no answers, no respondents". "No tracking in surveys" is true by D-37 (the tracker runs on marketing sites only). |
| Encryption in transit "TLS 1.3" / at rest "AES-256 · provider tokens encrypted" | literals | Provider facts: HSTS (`next.config.ts`), Supabase at-rest encryption, Vault for tokens (0002, 0020, 0021). Seed NEW `platform_facts` (key → value, source) by migration so the copy is a reviewed row, not a component literal. |
| Hosting "EU · Stockholm (eu-north-1)" | literal | **Conflict with D-35**: show the real region, eu-central-1 (Frankfurt). `platform_facts.db_region`. |
| Isolation | literal | true by structure (0001) |
| Last successful backup "Today 02:00" / last restore test "14 Sep 2026 · passed" | literals | NEW `ops_checks`. Backups are polled from the Supabase Management API by a worker (needs a management token as an environment secret; SF-43 step 4). Restore tests are recorded by staff with `restore_test_record` (SF-43 step 5; SEC-10 AC "a restore test meets the agreed objectives"). Until either exists: "No backup recorded" (never a time). |
| Recovery objectives "RPO 1 h · RTO 4 h" | literal | D-35 targets, `platform_facts`. D-35 also requires point-in-time recovery before CRM data is entered. Show a warning band until `ops_checks` records PITR on. |
| Anonymity guardrails (4 rows) | literals | **Conflict with D-19.** "Re-identification risk: Tveit Omsorg AS — Department «Natt» has 5 employees and 5 answers split by segment" names a group and its size. That is survey-structure data the platform must not hold, and it is itself a re-identification hint. "Differencing attacks blocked" and "Comment screening" are Orgpuls internals. Real: only a count-only status from Orgpuls (D-40, e.g. `guardrails.status` with `{paths_checked, suppressed, orgs_flagged}`, no names), shown as counts. Until then the panel is omitted and logged in DEVIATIONS. |

### 2.6 Privacy compliance (SEC-11; SF-15; D-24, D-27)

| Element | Prototype | Real |
|---|---|---|
| Search "Email or name" → hit card | `D.people` search, falling back to a **fabricated** "Ole Olsen" | `privacy_find(q)`: `people` (email exact, name trigram), `leads`, `members` (product users), email participants (0020), `tickets` requesters, `consent_events`. Every staff member can search, but the result needs `global:security`. The search itself is audited (`privacy.searched`, no query text stored). |
| "Found in: person record, 3 emails, 2 activities, 1 deal participant, campaign history, 1 ticket, meeting transcript mentions" | **Fabricated** | `privacy_preview(subject)`: counts per module from the real tables. Campaigns and meetings appear when those modules exist (module switches). |
| "Requests also arrive as personvern tickets with a 30-day clock" | text | True: `privacy_requests` (0012) with `due_at = received_at + 30 d`, fed by tickets in the Personvern queue |

**Actions**
- **Export (access request).** Toast "Export package created · logged". Real: `privacy_export(subject, request_id)`.
  - It creates `privacy_jobs` (kind `export`) and queues a worker. The worker writes a JSON (plus CSV) package with every row about the person, formula-neutralised (A7.6), to a private storage bucket.
  - `privacy_export_url(job)` returns a signed URL that lives 24 h.
  - Audited (`privacy.exported`), and the linked `privacy_request` becomes `done`.
- **Erase from every module.** Toast. Real (SEC-11 AC "removes the person from every module"; D-24: "deletes their rows and blanks name and email in stored events"):
  1. `privacy_preview`.
  2. `privacy_erase(subject, request_id, confirm, reason)`. It needs a typed confirmation (the email), a fresh second factor, and second-admin approval when `second_admin = on` (D-30 pattern).
  3. In one transaction, with `app.purging = on`:
     - hard-delete `people`/`leads` rows and their changelog rows;
     - remove them from deal participants, followers and activity guests;
     - delete email messages whose only external participant is the person, and redact the address elsewhere;
     - delete consent events after writing a tombstone (below);
     - blank `name`/`email`/`phone` keys in `events_in.payload` (D-24) and in `events.payload`;
     - delete enrichment requests and call logs for the person.
  4. Audit row `privacy.erased` with counts, never the email.
- **Product users conflict.** A person who is also a product user (`members`) is re-created by the next `member.joined`/`member.state` event. Erasure of a product user must happen in the product (a D-40 command), and the platform's erase is refused for an active member (detail `product_user`). NEW `erasure_tombstones(email_sha256)` stops imports, enrichment and form intake from re-creating an erased person (open question: retention of the hash).

| Retention rules | Prototype | Real |
|---|---|---|
| Six rows | literals | NEW `retention_rules`. Each row names the job that enforces it; a rule with no job is not shown as in force. The wiring audit requires every row to have an effect. Rows: CRM soft-deleted records 30 days (`app.purge`, exists). **Raw product events 13 months** (`app.purge`, exists, D-24; missing from the design's list, so add it). Login log 60 days (NEW). Tickets "3 years after close" (NEW purge job). Email bodies 5 years (NEW job on `email_messages`). Meeting recordings 12 months (with MTG). Webhook deliveries, integration calls and API usage 30/30/90 days (NEW). Audit log 5 years (NEW controlled purge, §3.2). "Raw survey responses — customer chooses, default 2 years" is an Orgpuls rule, shown as a product fact (`basis = 'product'`), never enforced here. |

| Sub-processor register | Prototype | Real |
|---|---|---|
| Seven rows "Source for the public list" | literals | NEW `subprocessors`. Seed only providers actually in use, with the region in their contract: Supabase (**eu-central-1**, D-35; the design says Stockholm), Vercel, Anthropic as the LLM (D-07). Stripe is listed only when it is used (**D-22**: Stripe waits). Telephony and transcription are chosen per phase (D-07), so add them then. "Source for the public list": an anon `subprocessors_public()` on the public host (D-28), or an export (open question). |

| Incident register | Prototype | Real |
|---|---|---|
| Two incidents, state, bar, "72-hour clock: 45 h left" | literals | NEW `security_incidents`. `notify_deadline = detected_at + 72 h`. Bar = elapsed ÷ 72 h while open (the prototype's 38 % ≈ 27 h of 72), 100 % when closed. Clock text: "N h left to decide on notification" while `state = 'investigating'`; "Logged d · closed d" when closed. At 48 h and 66 h without a decision, notify `global:security` staff (job). |
| ＋ Log incident | toast "72-hour clock started" | `incident_save(null, values)`. `detected_at` defaults to now and is editable, because the clock runs from awareness. Summary text is staff-written, ≤ 2 000 characters, and must hold no personal data beyond identifiers (A7.13). Each change is audited. |

### 2.7 Audit log (SEC-11; D-12; Appendix 2 Data, privacy and compliance)

| Element | Prototype | Real |
|---|---|---|
| Rows (When, Who, Kind, What, Organization, Source) | literals | `app.audit` (exists; 0004 added `action`, `target_type`, `target_id`, `account_id`, `staff_id`, `reason`, `detail`) |
| Kind chips All / Read / Write / Export / Role | literal mapping | NEW stored column `audit.kind`, generated by an immutable `app.audit_kind(action, command)`. `*.read`/`*.listed`/`*.viewed`/`*.searched` → read; `*.exported`/`export.*`/`privacy.exported` → export; `staff.*`, `permission_set.*`, `group.*`, `team.*`, `access_review.*`, `mfa.*` → role; `security.*`, `session.*` → security (a fifth chip, D-41); the rest → write. |
| Who: a staff name, "Workflow «Won → project»", "API · Zapier", "Claude (MCP) · Tor" | literals | `admins.name` via `staff_id`, plus NEW `audit.principal_kind` (`staff`, `token`, `oauth`, `workflow`, `system`, `product`) and `principal_id` (token, grant or workflow id). The label is composed at read. |
| What "Updated person ole.hansen@…" | literal | **D-12**: the audit holds names, ids and counts, never values. "What" = message key from `action` plus the target's **current** title, read at display time through `app.visible`. A deleted or erased target reads "(removed)". |
| Organization | literal | `account_id` → `organizations.name` |
| Source Web / Ticket / Automation / API / Support access / AI connector | literal | NEW `audit.source` (`web`, `api`, `mcp`, `workflow`, `ticket`, `support_access`, `mobile`, `import`, `product`, `system`), from `current_setting('app.source')`. The gateway, the executor and the ticket actions set it; `app.log` reads it. |
| Search box | `join(' ').includes` | `audit_search(filter, cursor)` over staff name, organisation name and action key, with kind, date range and staff filters, cursor-paginated. Indexes `(staff_id, at desc)`, `(account_id, at desc)`, `(kind, at desc)`. The search itself is audited (`audit.searched`, filter keys only). |
| Footnote "Append-only · every write and every read · typed reason: off (setting) · retained 5 years" | literal | Append-only and TRUNCATE-guarded (0001, 0004). Typed reason = `app.setting('typed_reason')`, rendered. **5 years needs a purge path**: today `audit_fixed` refuses every DELETE, so retention is "forever". Replace the trigger function with one that allows DELETE only when `app.purging = 'on'` and `at < now() - interval '5 years'`, called only from `app.purge_audit()` (§3.2). |

---

## 3. Data model and interfaces

Conventions: schema `app`, RLS on, **no policy, no client grant** (0001 pattern, D-09). Access goes only through `public` SECURITY DEFINER functions with `set search_path = ''`. Every write calls `app.log`. Reads of customer data are audited. `is_sample` exists on staff-created rows for the sandbox (CUS-08). Secrets are in Vault, one per value (D-18). Tests per D-03.

### 3.1 EXISTING objects these screens use (unchanged unless §3.2 says so)

| Object | Use here |
|---|---|
| `admins` (0001/0003), `permission_sets`, `visibility_groups`, `teams`, `app.me()`, `app.can()`, `app.require()`, `app.require_staff()`, `app.visible()` | Identity and rights. `global:security` and `global:configure` already exist in `app.right_ok`. |
| `recovery_codes` (0003) | Codes table; functions to add |
| `audit` (+ `app.log`, `app.take_reason`), `changelog` (source `assistant` exists), `events` (+ `app.emit`), `event_subscribers` / `event_cursors` / `event_failures`, `app.dispatch_events` | Audit log; changelog source for MCP; outbox for webhooks |
| `settings_registry` / `setting_values` / `app.setting()` / `setting_set` / `settings_log`; keys `api_rate`, `safeguards`, `count_limits`, `session_idle`, `ip_allowlist`, `login_alerts`, `typed_reason`, `second_admin`, `contact_rule`, `mfa` (fixed), `firewall` (fixed) | Rules and limits |
| `modules` (+ `module_set`, `app.require_module`), module `mobile` | Feature-flag tab; mobile switch |
| `products`, `installations`, `events_in`, `account_products`, `subscriptions`, `members`, `usage_daily` | Applications tab |
| `intake_nonces`, `app.open_intake`, `store_product_secrets`, `product_secret` (0002) | Product secrets |
| `integration_connections` (0021, Vault), `mailboxes` (0020, Vault), `calendar_connections` (0010) | Catalog state, grants, the mailbox-expiry issue |
| `app.url_public` (0021) | Webhook URL check at save |
| `app.count_limit()` (0021) | Webhooks per user |
| `pgmq` queue `jobs`, `cron.schedule` (0007) | Job runtime (D-05) |
| `notifications` (+ `app.notify`), `reminder_prefs`, `activity_reminders` (channel `push` exists) | Alerts in-app; mobile push |
| `privacy_requests` (0012), the Personvern queue | Privacy actions |
| `help_articles`, `ticket_macros` (0012) | Content card "Help texts" |
| `health_scores`, `goals`, `goal_progress`, `call_logs` + `phone_match` / `call_log_save`, `deal_detail`, `deal_move`, `activities_get`, `activity_done`, `notes_list` / `note_save`, `threads_get`, `search`, `rec_*` | Mobile views |
| `app.purge()` (0007) | Retention rows "CRM 30 days" and "product events 13 months" |

### 3.2 Changes to EXISTING objects (new migration; never edit an applied one)

```
-- products and installations
alter table app.products add column stage text not null default 'ga' check (stage in ('ga','beta'));
alter table app.installations
  add column region text check (region is null or char_length(region) <= 60),
  add column api_version text check (api_version is null or char_length(api_version) <= 40),
  add column scopes text[] not null default '{}' check (scopes <@ array['orgs:read','orgs:write','billing:read','billing:write',
      'translations:read','translations:write','modules:read','modules:write','legal:read','legal:write','settings:read','settings:write']),
  add column created_at timestamptz not null default now(),
  add column connected_by uuid references app.admins (id) on delete set null,
  add column last_ping_at timestamptz, add column last_ping_ms int check (last_ping_ms >= 0), add column last_ping_ok boolean;
alter table app.intake_nonces add column product text references app.products (key) on delete cascade;
  -- store_product_secrets: a nonce with product set accepts only <product>_(token|webhook)_secret and refuses
  -- to overwrite an existing secret of that name

-- audit
alter table app.audit
  add column kind text generated always as (app.audit_kind(action, command)) stored,   -- read|write|export|role|security
  add column source text not null default 'web' check (source in ('web','api','mcp','workflow','ticket','support_access','mobile','import','product','system')),
  add column principal_kind text not null default 'staff' check (principal_kind in ('staff','token','oauth','workflow','system','product')),
  add column principal_id uuid;
create index audit_staff_at on app.audit (staff_id, at desc);
create index audit_account_at on app.audit (account_id, at desc);
create index audit_kind_at on app.audit (kind, at desc);
-- app.log: source := coalesce(nullif(current_setting('app.source', true), ''), 'web'),
--          principal_kind/_id from current_setting('app.principal_kind'/'app.principal_id')
-- app.audit_fixed → app.audit_guard: allow DELETE only when current_setting('app.purging', true) = 'on'
--   and old.at < now() - interval '5 years'; everything else raises as today; TRUNCATE still refused

-- changelog: the mobile client as a source
alter table app.changelog drop constraint changelog_source_check,
  add constraint changelog_source_check check (source in ('ui','api','import','workflow','assistant','product','system','merge','mobile'));

-- notifications: two more kinds and once-only delivery (MOB-07 AC "a new assignment sends one push")
alter table app.notifications drop constraint notifications_kind_check,
  add constraint notifications_kind_check check (kind in ('mention','reminder','security','system','assignment','chat_request')),
  add column dedupe_key text unique check (dedupe_key is null or char_length(dedupe_key) <= 120);

-- settings register: a per-key validator/effect, so setting_set cannot bypass a key's rule
alter table app.settings_registry add column hook text check (hook is null or hook ~ '^app\.[a-z_]+$');
  -- setting_set calls the hook (key, old, new, scope_id) before writing; ip_allowlist → app.ip_allowlist_guard
  -- (self_lockout), mcp_access → app.mcp_access_effect (revoke grants), signin_hours → app.signin_hours_guard

-- app.me(): two new branches (§3.9). app.can(): token scope check.
-- event_subscribers: + ('webhooks', 'app.sub_webhooks', 60), ('security_alerts', 'app.sub_security_alerts', 70)
-- activity_types seed: + key 'visit' (Nearby "Check in")
```

### 3.3 NEW tables: Security

```
login_log(id bigint identity pk, at timestamptz not null default now(),
  staff_id uuid null → admins on delete cascade, email_sha256 bytea not null,           -- unknown addresses: hash only
  session_id uuid null, outcome text not null check (outcome in ('success','failed_password','failed_mfa','blocked_ip',
  'blocked_time','blocked_inactive','rate_limited')),
  method text null check (method in ('password_totp','google_totp','microsoft_totp','recovery_code')),
  ip inet null, user_agent text null check (char_length(user_agent) <= 300), device_label text null check (char_length(device_label) <= 120),
  device_hash bytea null, city text null check (char_length(city) <= 80), country char(2) null,
  new_device boolean not null default false, new_location boolean not null default false)
  index (staff_id, at desc), index (at desc); purged after 60 days

staff_sessions(session_id uuid pk,                                   -- = auth.sessions.id = JWT claim session_id
  staff_id uuid not null → admins on delete cascade, created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(), ip inet null, last_ip inet null, device_label text, device_hash bytea,
  city text, country char(2), method text not null,
  ended_at timestamptz null, end_reason text null check (end_reason in ('signed_out','idle_timeout','forced','ip_rule','time_rule',
  'deactivated','mfa_reset','recovery_code','expired')), ended_by uuid null → admins on delete set null,
  check ((ended_at is null) = (end_reason is null)))
  index (staff_id) where ended_at is null; purged 60 days after ended_at

staff_devices(staff_id uuid → admins cascade, device_hash bytea, label text, first_seen_at, last_seen_at, pk(staff_id, device_hash))
staff_locations(staff_id uuid → admins cascade, country char(2), city text, first_seen_at, pk(staff_id, country, city))

security_rules(id uuid pk, kind text not null check (kind in ('ip_range','time_window')),
  cidr cidr null, days smallint[] null check (days <@ array[1,2,3,4,5,6,7]::smallint[]), starts time null, ends time null,
  label text not null check (char_length(btrim(label)) between 1 and 80),
  created_by uuid → admins on delete set null, created_at, archived_at timestamptz null, version int not null default 1,
  check ((kind = 'ip_range') = (cidr is not null)),
  check ((kind = 'time_window') = (days is not null and starts is not null and ends is not null)))
  -- time windows use the platform time zone (Europe/Oslo, D-04)

security_events(id bigint identity pk, at timestamptz not null default now(),
  kind text not null check (kind in ('new_device','new_location','failed_logins','account_locked','user_invited','password_reset',
  'large_export','large_delete','session_revoked','mfa_reset','ip_blocked','time_blocked','api_token_old','webhook_banned','incident_logged')),
  severity text not null check (severity in ('info','low','high','critical')),
  subject_staff_id uuid null → admins on delete set null, actor_id uuid null → admins on delete set null,
  detail jsonb not null default '{}' check (jsonb_typeof(detail) = 'object'),   -- ids and counts only
  alert_state text not null default 'none' check (alert_state in ('none','queued','sent','digest','failed')))
  index (at desc)

security_alert_deliveries(event_id bigint → security_events on delete cascade, channel text check (channel in ('in_app','email','slack')),
  recipient_id uuid null → admins on delete cascade, sent_at timestamptz null, status text check (status in ('queued','sent','failed','not_connected')),
  unique (event_id, channel, recipient_id))                                       -- SEC-02 AC: one alert per trigger

access_reviews(id uuid pk, due_on date not null, started_at timestamptz, started_by uuid → admins on delete set null,
  completed_at timestamptz null, completed_by uuid null → admins on delete set null)
access_review_items(review_id uuid → access_reviews cascade, staff_id uuid → admins cascade,
  permission_set_id uuid, group_id uuid,                                          -- snapshot at start
  decision text null check (decision in ('keep','change','deactivate')), decided_by uuid null, decided_at timestamptz null,
  pk(review_id, staff_id))

sso_providers(provider text pk check (provider in ('google','microsoft')), enabled boolean not null default false,
  allowed_domains text[] not null default '{}', updated_by uuid → admins on delete set null, updated_at timestamptz)

password_history(staff_id uuid → admins cascade, hash text not null, changed_at timestamptz not null, pk(staff_id, changed_at))
  -- only if password_reuse is built (open question); keeps at most the setting's number

ops_checks(id bigint identity pk, kind text not null check (kind in ('backup','pitr','restore_test')), at timestamptz not null,
  ok boolean not null, rpo_minutes int null, rto_minutes int null, detail jsonb not null default '{}',
  recorded_by uuid null → admins on delete set null)                                -- null = the worker

platform_facts(key text pk check (key ~ '^[a-z_]{2,40}$'), value text not null, source text not null)  -- seeded, reviewed in PRs

security_incidents(id uuid pk, title text not null check (char_length(btrim(title)) between 1 and 200),
  summary text not null check (char_length(summary) <= 2000), detected_at timestamptz not null,
  logged_at timestamptz not null default now(), logged_by uuid → admins on delete set null,
  personal_data boolean not null default false,
  state text not null default 'investigating' check (state in ('investigating','assessed_not_notifiable','notified','closed')),
  notify_deadline timestamptz generated always as (detected_at + interval '72 hours') stored,
  notified_at timestamptz null, notified_ref text null check (char_length(notified_ref) <= 120), closed_at timestamptz null,
  ticket_id uuid null → tickets on delete set null, version int not null default 1,
  check (state <> 'notified' or notified_at is not null), check (state <> 'closed' or closed_at is not null))

subprocessors(id uuid pk, name text not null unique, purpose text not null check (char_length(purpose) <= 200),
  region text not null check (char_length(region) <= 60), in_use_since date not null, removed_at date null,
  public boolean not null default true, ord int not null default 0, version int not null default 1)

retention_rules(key text pk check (key ~ '^[a-z_]{2,40}$'), keep interval null, basis text not null check (basis in ('platform','product')),
  job_key text null → job_defs on delete restrict, last_run_at timestamptz, last_purged bigint,
  check (basis = 'product' or (keep is not null and job_key is not null)))      -- a platform rule always has its job

privacy_jobs(id uuid pk, request_id uuid null → privacy_requests on delete set null, kind text not null check (kind in ('export','erasure')),
  subject jsonb not null,                                                           -- {people:[uuid], leads:[uuid]}; no email
  preview jsonb not null,                                                           -- counts per module
  state text not null default 'previewed' check (state in ('previewed','approved','running','done','failed')),
  storage_path text null, url_expires_at timestamptz null, created_by uuid → admins on delete set null,
  approved_by uuid null → admins on delete set null, created_at, finished_at, error text null check (char_length(error) <= 300),
  check (approved_by is null or approved_by <> created_by))                       -- second admin, when the setting is on

erasure_tombstones(email_sha256 bytea pk, erased_at timestamptz not null, request_id uuid null)
```

### 3.4 NEW tables: Platform, API, webhooks, catalog, MCP, jobs

```
integration_calls(id bigint identity pk, product text not null → products, direction text not null check (direction in ('out','in')),
  kind text not null check (kind ~ '^[a-z_]+\.[a-z_]+$'), at timestamptz not null default now(),
  duration_ms int null check (duration_ms >= 0), ok boolean not null, status int null, error_code text null check (char_length(error_code) <= 60))
  index (product, at desc); purged after 30 days; written by product-command / orgpuls-events through worker_integration_call

product_event_kinds(product text → products cascade, kind text, uses text[] not null default '{}', label_key text not null, pk(product, kind))
product_commands(product text → products cascade, command text, scope text not null, used_by text[] not null default '{}',
  destructive boolean not null default false, pk(product, command))              -- mirror of _shared/orgpuls.ts, test-asserted equal
status_notices(id uuid pk, product text → products, text text null check (char_length(text) <= 500), maintenance boolean not null default false,
  problem_ticket_id uuid null → tickets on delete set null, set_by uuid → admins on delete set null, set_at, cleared_at)

event_catalog(kind text pk check (kind ~ '^[a-z_]+\.[a-z_]+$'), family text not null, webhookable boolean not null default false,
  workflow_trigger boolean not null default true, label_key text not null)       -- seeded from the kinds app.emit writes

api_tokens(id uuid pk, staff_id uuid not null → admins on delete cascade, name text not null check (char_length(btrim(name)) between 1 and 80),
  token_sha256 bytea not null unique, prefix text not null default 'sk_live_', last4 char(4) not null,
  scopes text[] not null default '{*}', created_at, last_used_at timestamptz null, expires_at timestamptz null,
  revoked_at timestamptz null, revoked_by uuid null → admins on delete set null,
  revoke_reason text null check (revoke_reason in ('rotated','revoked','staff_deactivated','mfa_reset')),
  is_sample boolean not null default false)
  unique (staff_id) where revoked_at is null                                     -- INT-02: one active token per user

api_scopes(scope text pk check (scope ~ '^[a-z_]+:(read|write)$|^\*$'), rights text[] not null check (app.rights_ok(rights)))
  -- e.g. deals:read → {deals:see}; deals:write → {deals:see, deals:add, deals:edit_others}; never grants global:security

oauth_apps(id uuid pk, client_id text not null unique check (client_id ~ '^client_[A-Za-z0-9]{16,40}$'), name text not null,
  kind text not null check (kind in ('integration','mcp','extension')), owner_id uuid null → admins on delete set null,
  redirect_uris text[] not null check (cardinality(redirect_uris) between 1 and 10),     -- each https (checked in RPC)
  client_secret_sha256 bytea null,                                                -- null = public client, PKCE required
  allowed_scopes text[] not null, dynamic boolean not null default false, created_at, disabled_at timestamptz null)
oauth_codes(code_sha256 bytea pk, app_id uuid → oauth_apps cascade, staff_id uuid → admins cascade, scopes text[] not null,
  redirect_uri text not null, code_challenge text not null, expires_at timestamptz not null, used_at timestamptz null)  -- S256 only, 10 min
oauth_grants(id uuid pk, app_id uuid not null → oauth_apps cascade, staff_id uuid not null → admins cascade, scopes text[] not null,
  access_sha256 bytea not null unique, access_expires_at timestamptz not null,
  refresh_sha256 bytea null unique, refresh_expires_at timestamptz null, created_at, last_used_at timestamptz null,
  revoked_at timestamptz null, revoke_reason text null check (revoke_reason in ('revoked','mcp_off','app_removed','staff_deactivated','rotated')))

api_costs(op text pk check (op in ('get','list','create','update','delete','delete_list','search','convert','merge')), cost int not null check (cost >= 0))
api_requests_hourly(hour timestamptz, principal_kind text check (principal_kind in ('token','grant')), principal_id uuid,
  requests int not null default 0, cost bigint not null default 0, throttled int not null default 0, pk(hour, principal_kind, principal_id))  -- 90 days
api_burst(principal_id uuid, second bigint, n int not null, pk(principal_id, second))   -- UNLOGGED; rows older than 10 s pruned
api_budget_day(day date pk, used bigint not null default 0, warned75_at timestamptz, warned100_at timestamptz)
api_idempotency(principal_id uuid, key text check (char_length(key) between 8 and 100), response jsonb not null, created_at, pk(principal_id, key))  -- 24 h

webhooks(id uuid pk, owner_id uuid not null → admins on delete cascade, event_kind text not null → event_catalog,
  url text not null check (app.url_public(url)), vault_secret_id uuid not null,
  state text not null default 'active' check (state in ('active','paused','banned','blocked','deleted')),
  banned_until timestamptz null, first_attempt_failures int not null default 0, last_success_at timestamptz null,
  failing_since timestamptz null, created_at, updated_at, deleted_at timestamptz null, version int not null default 1,
  is_sample boolean not null default false,
  check ((state = 'banned') = (banned_until is not null)))
  -- event_kind must have webhookable = true (trigger or RPC check); count per owner ≤ app.count_limit()
webhook_deliveries(id uuid pk, webhook_id uuid not null → webhooks on delete cascade, event_id bigint not null → events on delete cascade,
  attempt smallint not null check (attempt between 1 and 4), state text not null check (state in ('queued','sent','failed','skipped')),
  scheduled_at timestamptz not null, sent_at timestamptz null, duration_ms int null, response_status int null,
  error_code text null check (char_length(error_code) <= 60), request_body jsonb null, signed_at bigint null,
  unique (webhook_id, event_id, attempt))                                         -- 30 days

integration_catalog(key text pk check (key ~ '^[a-z_]{2,40}$'), collection text not null check (collection in ('productivity_mail','team_chat','close_paid','automate')),
  provider text null, connection text not null check (connection in ('company','per_user','api','extension')),
  access text[] not null, tags text[] not null default '{}', first_party boolean not null default true, ord int, active boolean not null default true)
installed_apps(key text pk → integration_catalog, installed_by uuid → admins on delete set null, installed_at timestamptz not null,
  settings jsonb not null default '{}', removed_at timestamptz null, removed_by uuid null)
app_extensions(id uuid pk, oauth_app_id uuid not null → oauth_apps cascade,
  placement text not null check (placement in ('deal_panel','person_panel','organization_panel','deal_action','person_action')),
  kind text not null check (kind in ('panel','link','dialog','embedded')), url text not null check (app.url_public(url)),
  label text not null check (char_length(label) <= 60))                           -- INT-10: sandboxed iframe, scopes of its app

mcp_index(entity text, record_id uuid, title text not null, body tsvector not null, owner_id uuid null, visibility text not null,
  updated_at timestamptz not null, pk(entity, record_id))                         -- GIN(body); visibility applied at query time

job_defs(key text pk check (key ~ '^[a-z_]{2,40}$'), product text null → products, label_key text not null,
  schedule text null, source text not null check (source in ('cron','queue','product')),
  retry_fn text null check (retry_fn ~ '^app\.[a-z_]+$'))
job_runs(id bigint identity pk, job_key text not null → job_defs, state text not null check (state in ('queued','running','succeeded','failed')),
  queued_at timestamptz not null default now(), started_at timestamptz null, finished_at timestamptz null,
  info jsonb not null default '{}' check (jsonb_typeof(info) = 'object'),        -- counts only
  error text null check (char_length(error) <= 300), retry_of bigint null → job_runs, requested_by uuid null → admins on delete set null)
  index (job_key, queued_at desc); 90 days
```

### 3.5 NEW tables: Mobile

```
push_devices(id uuid pk, staff_id uuid not null → admins on delete cascade, platform text not null default 'web_push' check (platform in ('web_push')),
  endpoint text not null unique check (endpoint ~ '^https://' and char_length(endpoint) <= 1000), p256dh text not null, auth_secret text not null,
  label text check (char_length(label) <= 120), created_at, last_used_at timestamptz null, failures int not null default 0, revoked_at timestamptz null)
  -- name as proposed in deals-activities.md; the endpoint is a capability URL: never returned after registration
push_deliveries(notification_id uuid → notifications cascade, device_id uuid → push_devices cascade, sent_at timestamptz,
  status int null, pk(notification_id, device_id))
notification_prefs(staff_id uuid → admins cascade, kind text check (kind in ('assignment','mention','chat_request','security','system')),
  channels text[] not null default array['in_app','push'] check (channels <@ array['in_app','push','email']), pk(staff_id, kind))
  -- reminders keep reminder_prefs (0010); MOB-07 "configurable per type"
sync_receipts(device_id uuid, mutation_id uuid, staff_id uuid not null → admins cascade, received_at timestamptz not null default now(),
  result text not null check (result in ('applied','superseded','rejected')), error_code text null, pk(device_id, mutation_id))  -- 30 days
record_geo(entity text not null, record_id uuid not null, field_key text not null default 'address',   -- address custom fields too (MOB-03)
  geo extensions.geography(Point, 4326) not null, source text not null check (source in ('geonorge','manual')), geocoded_at timestamptz not null,
  pk(entity, record_id, field_key))                                               -- GiST(geo); postgis in schema extensions
files(id uuid pk, entity text not null, record_id uuid not null, storage_path text not null unique,
  kind text not null check (kind in ('photo','audio','scan','card','document')), mime text not null, bytes int not null check (bytes between 1 and 26214400),
  transcript text null check (char_length(transcript) <= 50000), created_by uuid → admins on delete set null, created_at, deleted_at timestamptz null,
  is_sample boolean not null default false)                                       -- CRM-05/SF-33 dependency; private bucket, soft-deleted with its record
```

### 3.6 Settings (register rows; options are keys, labels are message keys)

| Key | Group | Options | Default | Applies to | Effect / hook |
|---|---|---|---|---|---|
| `api_rate` (exists) | limits | off, source_values, custom | off | INT-03 | Gateway budget and burst |
| `api_budget_base` NEW | limits | number | 30 000 | INT-03 | Used when `api_rate` ≠ off |
| `api_plan_multiplier` NEW | limits | number | 1 | INT-03 | D-17: not a plan attribute |
| `api_burst_token` / `api_burst_oauth` / `api_burst_search` NEW | limits | number | 20 / 80 / 10 (lowest source values) | INT-03 | Per 2 s |
| `safeguards` (exists) | safeguards | source_values, custom, off | source_values | AUT-09, INT-04 | Webhook policy. **One `value_number` cannot hold five numbers**: add `webhook_timeout_s`, `webhook_retry_s` (text "3,30,150"), `webhook_ban_after`, `webhook_ban_min`, `webhook_delete_days`, read only when `custom` (open question). |
| `count_limits` (exists) | limits | unlimited, number | unlimited | INT-04 (webhooks per user) | — |
| `mcp_access` NEW | integrations | on, off | on | MCP-03 | hook `app.mcp_access_effect` revokes `mcp` grants |
| `mcp_sync` NEW | integrations | on, off | on | MCP-01 | `mcp_index` job runs only when on |
| `session_idle` (exists) | security | on_30, off | on_30 | SEC-06 (D-29) | `worker_session_seen` and `app.me()` |
| `ip_allowlist` (exists) | security | off, on | off | SEC-03 (D-29) | hook `app.ip_allowlist_guard` (self_lockout) |
| `signin_hours` NEW | security | off, on | off | SEC-03 | hook `app.signin_hours_guard` |
| `password_expiry` NEW | security | never, days | never | SEC-03 | Checked at sign-in (forces a change) |
| `password_reuse` NEW | security | off, number | off | SEC-03 | `password_history` (if built) |
| `login_alerts` (exists) | security_alerts | off, on → **change to** off, immediate, digest | off | SEC-02 (D-29) | Admin logins to Slack and email |
| `alert_new_device` NEW | security_alerts | off, immediate, digest | off (it is a login alert, D-29) | SEC-02 | — |
| `alert_user_invited` NEW | security_alerts | off, immediate, digest | immediate | SEC-02 | Alerts never restrict anyone, so D-16 does not force off. Recommendation, §6 |
| `alert_failed_logins` NEW | security_alerts | off, immediate, digest (+ number, source 3) | immediate | SEC-02 | — |
| `alert_password_reset` NEW | security_alerts | off, immediate, digest | immediate | SEC-02 | — |
| `alert_large_export` NEW | security_alerts | off, immediate, digest (+ number of rows) | immediate, 1 000 | SEC-02 | Read from `export_log` (0011) and bulk deletes |
| `alert_digest_time` NEW | security_alerts | a time (text HH:MM) | 08:00 | SEC-02 | Digest job |
| `security_alert_recipients` NEW | security_alerts | role, list | role (`global:security` holders) | SEC-02 | — |
| `access_review_interval` NEW | security | quarterly, half_yearly | quarterly | Appendix 2 | Due-date issue |
| `push_notifications` NEW | mobile | on, off | on | MOB-07 | Master switch (also needs the `mobile` module on) |
| `second_admin` (exists) | approvals_audit | off, on | off | + SEC-11 erasure (add to applies_to) | `privacy_jobs.approved_by` |
| `typed_reason` (exists) | approvals_audit | off, on | off | every action here | `app.take_reason` |
| `contact_rule` (exists) | contacts_consent | — | no_rule | MOB-01, AIA-07 (card scanner) | Shown on Capture |

Every setting gets a test in both states (A9). Defaults leave every feature working.

### 3.7 Public RPCs (security definer, `set search_path = ''`, `grant execute … to authenticated` unless marked)

Error codes. Only these, with the existing patterns:
- `forbidden`: `insufficient_privilege`, detail = `scope:action` or a reason key (`self`, `owner_only`, `fresh_mfa`, `self_lockout`, `product_user`).
- `not_found`: `no_data_found`.
- `invalid`: `invalid_parameter_value`, detail = the field.
- `version_conflict`: `serialization_failure`, detail = the current version.
- `not_connected`: `invalid_parameter_value`, detail = the provider.

The existing `reason_required` and `module_off` stay as they are.

"Fresh MFA" = `app.require_fresh_mfa(10)`: the JWT `amr` claim holds a `totp` entry within the last 10 minutes, else forbidden/`fresh_mfa`. The UI then asks for the TOTP code again.

**Security**
- `security_dashboard()`: global:security. KPIs, live sessions, issues, 7-day events.
- `session_revoke(p_session uuid, p_reason text)`, `staff_sessions_revoke_all(p_staff uuid, p_reason text)`: global:security, or self for one's own sessions.
- `my_sessions()`: self.
- `login_history(p_staff uuid, p_days int default 60)`: global:security (self for one's own).
- `security_rules_get()`; `security_rule_save(p_id, p_values, p_version)`; `security_rule_delete(p_id)`: global:security, fresh MFA for saves that tighten.
- `security_rule_preview(p_change jsonb)`: global:security.
- `alerts_get()`: global:security. Settings and recipients; the toggles use `setting_set`.
- `sso_get()`, `sso_set(p_provider, p_enabled, p_domains)`: global:security plus fresh MFA.
- `mfa_overview()`: global:security.
- `recovery_codes_generate()`: self, fresh MFA; returns the codes once.
- `recovery_code_redeem(p_code text)`: **aal1 allowed** (`app.admin_email()` not null), rate-limited (5 per hour per staff member).
- `staff_mfa_reset(p_staff, p_reason)`: owner plus fresh MFA.
- `staff_mfa_reminder(p_staff)`: global:security.
- `access_review_start()`, `access_review_decide(p_review, p_staff, p_decision)`, `access_review_complete(p_review)`: global:security.
- `firewall_status()`: global:see. `protection_get()`: global:security.
- `restore_test_record(p_at, p_ok, p_rpo_min, p_rto_min, p_note)`: global:security.
- `privacy_find(p_q)`, `privacy_preview(p_subject jsonb)`: global:security.
- `privacy_export(p_subject, p_request, p_reason)`: global:security.
- `privacy_erase(p_subject, p_request, p_confirm, p_reason)`: global:security plus fresh MFA, plus a second admin's `privacy_approve(p_job)` when `second_admin = on`.
- `privacy_jobs_get()`: global:security.
- `retention_get()`: global:security.
- `subprocessors_get()`; `subprocessor_save(p_id, p_values, p_version)`: global:security. `subprocessors_public()`: **anon**, only `public and removed_at is null`.
- `incidents_get()`, `incident_save(p_id, p_values, p_version)`: global:security.
- `audit_search(p_filter jsonb, p_cursor bigint, p_limit int)`: global:security.

**Platform**
- `applications_get()`: global:see.
- `application_get(p_product)`: global:see. Connection, synced data, events, commands.
- `application_connect(p_values)`: owner plus fresh MFA. Returns `{product, intake_code}`.
- `application_update(p_product, p_values)`: owner.
- `api_overview()`: staff. Definition summary, own tokens and grants (all with global:security), rate status, 24 h usage.
- `api_definition()`: staff. OpenAPI JSON.
- `api_token_create(p_name)`: staff plus fresh MFA. Refused if an active token exists; use rotate.
- `api_token_rotate()`: staff plus fresh MFA.
- `api_token_revoke(p_id, p_reason)`: owner of the token, or global:security.
- `oauth_apps_get()`; `oauth_app_save(p_id, p_values)` (returns the client secret once); `oauth_app_disable(p_id)`: global:configure.
- `oauth_grants_get()`; `oauth_grant_revoke(p_id)`: self, or global:security.
- `webhooks_get(p_filter)`; `webhook_save(p_id, p_values, p_version)` (returns the signing secret once on create); `webhook_delete(p_id)`; `webhook_set_state(p_id, p_state)`; `webhook_test(p_id)`; `webhook_redeliver(p_delivery)`: owner, or global:configure.
- `webhook_deliveries_get(p_webhook, p_cursor)`; `webhook_delivery_get(p_id)` (audited read).
- `catalog_get(p_q)`: staff. `catalog_install(p_key)`, `catalog_remove(p_key, p_confirm)`, `catalog_users(p_key)`, `catalog_user_revoke(p_key, p_staff)`: global:configure.
- `catalog_recommend(p_need)`: staff with global:ai; goes through the AI gateway edge function.
- `mcp_get()`: staff. `mcp_set(p_enabled)`, `mcp_sync_set(p_on)`: global:configure.
- `jobs_get(p_filter)`: global:see. `job_retry(p_run)`: global:configure.
- `flags_get(p_product)`: global:see. Modules plus the product command's reply.
- `status_notice_get(p_product)`: global:see. `status_notice_set(p_product, p_text, p_problem, p_maintenance, p_confirm)`: global:configure, and owner plus fresh MFA when `p_maintenance`.
- `content_get(p_product)`: global:see. Assembled by the edge function from command replies.

**Mobile**
- `mobile_focus(p_lat numeric default null, p_lng numeric default null)`: staff, module `mobile`. Coordinates are used, never stored or logged.
- `nearby(p_lat, p_lng, p_radius_km, p_entities text[], p_filter jsonb)`.
- `checkin(p_entity, p_id, p_note)`: creates a done `visit` activity; no coordinates stored.
- `push_device_register(p_endpoint, p_p256dh, p_auth, p_label)`, `push_device_revoke(p_id)`, `push_devices_get()`: self.
- `notification_prefs_get()`, `notification_prefs_set(p_kind, p_channels)`: self.
- `sync_apply(p_device uuid, p_mutations jsonb)`: self; ≤ 200 mutations per call.
- `sync_changes(p_since bigint, p_limit int)`: self.
- `capture_save(p_entity, p_id, p_file_id, p_kind)`.
- `card_draft_save(p_values)`: applies `contact_rule`.

**Service role only** (`revoke … from public, anon, authenticated; grant execute … to service_role`, as the 0020/0021 workers)
- `worker_login_event(p_input jsonb)`: from the sign-in action. Returns `{allowed, reason}`; writes `login_log`, `staff_sessions`, devices, locations and `security_events`.
- `worker_session_seen(p_session, p_ip, p_ua)`: from middleware, throttled to once a minute.
- `worker_integration_call(p_rows jsonb)`.
- `worker_api_auth(p_hash bytea)`; `api_exec(p_hash bytea, p_op text, p_args jsonb)`; `worker_api_usage(p_rows jsonb)`.
- `worker_oauth_authorize(...)`; `worker_oauth_token(...)`; `worker_oauth_register(...)` (DCR, MCP only).
- `worker_webhook_claim(p_limit)`; `worker_webhook_secret(p_webhook)`; `worker_webhook_done(p_delivery, p_status, p_ms, p_error)`.
- `worker_job_run(p_key, p_state, p_info, p_error)`.
- `worker_backup_seen(p_rows)`.
- `worker_privacy_package(p_job)`; `worker_privacy_done(p_job, p_path)`.
- `worker_push_claim()`; `worker_push_done(...)`; `worker_vapid_key()`.
- `worker_geocode_claim()`; `worker_geocode_done(...)`.

### 3.8 Rights (scope:action, from `app.right_ok`)

| Area | Read | Write |
|---|---|---|
| Security screen, audit log, login history, rules, alerts, incidents, sub-processors, privacy | `global:security` | `global:security` (+ fresh MFA where marked; owner for MFA reset) |
| Own sessions, own recovery codes, own tokens, own grants, own push devices, own notification prefs | self | self |
| Applications, job monitor, flags, content | `global:see` | `global:configure`; connect and maintenance: owner + fresh MFA |
| OAuth apps, catalog install and remove, MCP switch | staff (read own) | `global:configure` |
| Webhooks | owner of the webhook; all with `global:configure` | owner; any webhook with `global:configure` |
| API calls (tokens, MCP) | the token's staff rights ∩ the token's scopes (`api_scopes.rights`); never `global:security` through a token | same |
| Mobile views | the same RPCs and rights as the web (MOB-01 "same permissions"), plus module `mobile` on | same |

### 3.9 Identity changes: `app.me()` and `app.can()` (the core of §5)

`app.me()` today has two branches: `acting_as` inside a database-internal session (0021), and an aal2 JWT. Add the following.
1. **Session check** on the JWT branch: refuse when `staff_sessions` has a row for `auth.jwt() ->> 'session_id'` with `ended_at is not null`, or when `session_idle = on_30` and `last_seen_at < now() - 30 min`. A missing row is allowed only during a grace window after sign-in, until `worker_login_event` has written it. One primary-key lookup per call.
2. **Token branch**: when `current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'service_role'` and `current_setting('app.api_principal', true)` is set (only by `api_exec`, within its transaction):
   - resolve the principal to an active `api_tokens` row or a live `oauth_grants` row (not revoked, not expired);
   - require the staff member to be active;
   - for `mcp` apps, require `mcp_access = on`;
   - return that staff id.

   Clients cannot set the GUC, and only the service role can call `api_exec`.

`app.can(scope, action)` intersects with the principal's scopes when the token branch is active. `global:security` and `global:configure` are never reachable through a token. `api_exec` sets `app.source` (`api` or `mcp`) and `app.principal_kind`/`app.principal_id` for the audit, and `changelog.source = 'api'`/`'assistant'`.

Tests: every existing invariant suite still passes. A revoked session, a revoked token, an expired grant and `mcp_access = off` each make an existing RPC raise `not_signed_in`. A token cannot reach `global:security`. A client JWT with a forged `app.api_principal` header gets nothing.

### 3.10 Events (outbox `app.events`) and workflow triggers

| Kind | Emitted by | Webhookable | Workflow trigger |
|---|---|---|---|
| `api_token.created`, `api_token.revoked`, `oauth.granted`, `oauth.revoked` | token and OAuth RPCs | no | yes (admin workflows) |
| `webhook.banned`, `webhook.deleted` | webhook worker | no | yes (notify owner) |
| `integration.installed`, `integration.removed` | catalog | no | yes |
| `mcp.switched` | `mcp_set` | no | no |
| `job.failed` | `app.run_job` / `worker_job_run` | no | yes (SF-26 alert) |
| `incident.logged`, `incident.deadline_near` | incidents, job | no | yes |
| `privacy.exported`, `privacy.erased` | privacy RPCs | no | yes (close the ticket) |
| `status_notice.changed` | `status_notice_set` | no | no |
| `usage.limit_warning`, `usage.limit_reached` (Part F names) | gateway at 75 % / 100 % | no | yes |
| `activity.created` (check-in, call log), record `*.updated` via `sync_apply` | mobile | per the entity | yes |

Security events (`login`, `login_failed`, `user_invited`, `password_reset_requested`: the Part F security family) go to `security_events`, **not** the outbox. They carry staff IPs and are never webhookable. `app.sub_security_alerts` reads `security_events`, not `events`. Part F's `export_run` is the existing `export.created` (0011); keep the existing name.

Audit actions (all via `app.log`): `session.revoked`, `session.revoked_all`, `security_rule.saved|deleted`, `sso.changed`, `mfa.reset`, `recovery_codes.generated|redeemed`, `access_review.started|decided|completed`, `restore_test.recorded`, `privacy.searched|previewed|exported|erased|approved`, `subprocessor.saved`, `incident.saved`, `audit.searched`, `application.connected|updated|pinged`, `api_token.created|rotated|revoked`, `oauth_app.saved|disabled`, `oauth_grant.revoked`, `webhook.saved|deleted|tested|redelivered`, `webhook_delivery.read`, `integration.installed|removed|user_revoked`, `mcp.switched`, `job.retried`, `status_notice.set`, `push_device.registered|revoked`, `sync.applied` (counts), and `setting.changed` (existing) for every register key.

### 3.11 Jobs (pg_cron + pgmq, D-05; each wrapped by `app.run_job` → `job_runs`)

- `security_alerts` (every minute; immediate) and `security_digest` (daily at `alert_digest_time`).
- `sessions_expire` (every 5 min): idle timeout, plus revoking sessions of deactivated staff (SF-43 step 2: "deactivating a user ends their sessions").
- `login_log_prune` (daily, 60 days).
- `incident_clock` (hourly: 48 h and 66 h notices).
- `access_review_due` (daily).
- `ops_backup_poll` (hourly; worker, Management API).
- `webhook_send` (queue) and `webhook_sweep` (every minute: retries, unban, 3-day deletion).
- `api_burst_prune` (every minute); `api_usage_rollup` (hourly); `api_budget_reset` (daily).
- `mcp_index` (every 30 min while `mcp_sync = on`).
- `audit_purge` (monthly, 5 years); `retention_tickets` (daily, 3 years after close); `retention_email_bodies` (daily, 5 years); `integration_calls_prune`, `webhook_deliveries_prune`, `job_runs_prune`, `sync_receipts_prune` (daily).
- `push_send` (queue; Web Push with VAPID; a 410 Gone answer revokes the device).
- `geocode` (queue; Geonorge address API for Norwegian addresses on organisations and address custom fields; re-run when an address changes).
- `privacy_package` (queue).
- `status_notice_clear` (on `problem.resolved`).

### 3.12 Security requirements (checklist for these screens)

1. **API tokens are stored only as SHA-256.**
   - `sk_live_` + 32 random bytes in base62. The plaintext is shown once, at create or rotate, and never logged.
   - Lookup is by hash, then a constant-time compare.
   - OAuth access, refresh and authorisation codes are handled the same way; codes live 10 minutes, are used once and require PKCE S256.
   - A client secret is shown once and stored as a hash.
2. **Webhook signing secrets are in Vault**, one per webhook (`vault.create_secret`, name `webhook:<id>`). They are read only by `worker_webhook_secret` (service role) and deleted with the webhook. Signing is HMAC-SHA256 over `t.body` (D-32). The outbound filter runs at save (`app.url_public`) and again at send (DNS resolve, no redirects, no private, link-local or metadata ranges; A7.7).
3. **aal2 for everything; a fresh second factor for sensitive actions.** These need a TOTP within 10 minutes: token create and rotate, OAuth app secrets, connecting an application, maintenance mode, SSO changes, tightening IP or time rules, generating recovery codes, MFA reset, and erasure. `recovery_code_redeem` is the only aal1 entry point.
4. **Every admin write is audited** through `app.log`, with source and principal. Reads of customer data are audited too: audit search, webhook payloads, privacy find and preview, the export package.
5. The audit keeps no values (D-12): no email, IP, URL path or payload in `audit.detail`. IPs live only in `login_log`/`staff_sessions` (60 days). Webhook URLs live in `webhooks`.
6. No respondent data on any path: the firewall assertions run live (`firewall_status`) and in CI. The MCP index and API definition cover CRM entities only. Product events projected to the outbox already drop name, email and phone keys (0021 `product_event_out`).
7. Device location in Nearby and Focus is a request parameter only. It is never stored, logged or sent to analytics. Check-in stores no coordinates.
8. Push endpoints are capability URLs: write-only from the client, never returned. The VAPID private key is in Vault.
9. Sessions: revocation and idle timeout are enforced in the database (`app.me()`), not only in middleware.
10. Erasure and maintenance mode: preview, typed confirmation, second admin when the setting is on, irreversible-action wording.
11. Exports (privacy packages, audit CSV) neutralise formulas (A7.6) and live in a private bucket behind signed URLs that last 24 h.
12. Public surfaces (`subprocessors_public`, the OAuth endpoints, the MCP endpoint) are served on configured hosts. They are rate-limited by the gateway safeguards, whose defaults never block legitimate use (A7.9).

---

## 4. Conflicts with decisions (named)

| Design element | Decision | Resolution |
|---|---|---|
| "Email code" factor; "Authenticator app or email code"; "SSO + Face ID" | **D-11** TOTP only | Rows and copy removed; DEVIATIONS |
| Entra ID SAML "Connected", Okta SAML, SSO logins without TOTP | **D-31** SSO later, Google or Microsoft, still TOTP | Google and Microsoft only, followed by TOTP; Okta and SAML left out |
| "IP allowlist on", "Office + VPN ranges · 3 rules", all six alerts on | **D-29** allowlist and login alerts off by default | Render real values; defaults off |
| "EU · Stockholm (eu-north-1)", Supabase sub-processor "EU · Stockholm" | **D-35** show eu-central-1 | `platform_facts.db_region` = eu-central-1 |
| "Signature header: open decision (A4)" | **D-32** HMAC-SHA256 | Header specified (§1.3) |
| "Stripe mirror → both", Stripe sub-processor | **D-22** Stripe waits | `billing.changed` mirror, one way; Stripe listed when used |
| "aggregates with n ≥ 5 only", "Monitoring n ≥ 5", guardrail naming a department with 5 employees | **D-19** (no survey figures) and Orgpuls' per-org k (3..10) | Copy changed; guardrail panel omitted until a count-only Orgpuls status exists |
| Content: Edit draft and Roll back on question set, tiltak, legal, templates | **D-23** content stays in Orgpuls; use existing commands | Read via commands; buttons disabled until commands exist |
| Remote actions as REST paths that do not exist | **D-40** commands added when needed | Show the real allow-list; additions listed in §6 |
| "iOS and Android", home-screen widget, Face ID, iOS call logging, incoming caller match, share-in | **D-38** PWA after the web modules | §7: what a PWA can and cannot do |
| Rate limit "plan multiplier" | **D-17** nothing is sold | A setting, default 1 |
| MCP URL `sentral.orgpuls.no` | **D-28** names our public host; no `orgpuls.no` subdomain is decided | Host from configuration |
| `orgpuls.org.signed_up` style event names | **D-14** `object.action` | Real kinds |
| Webhook `person.added` | Part F "added" vs the platform's `created` (0006) | Keep `created`; document it |
| Token costs 1–4 | Part F reference values | Part F (`api_costs`) |
| Tries "3 / 5" | INT-04 (3 retries = 4 attempts) | "n / 4" |
| "Connect an application" asks a person to type the client secret | 0002 (secrets never pass through a person) | Intake code bound to the product; secret fields removed |
| Audit row "Updated person ole.hansen@…" | **D-12** audit holds no values | Text composed at read from the target's current title |
| Retention list lacks raw product events | **D-24** 13 months | Row added |
| Design's `props.product` unused | — | Preselect the shell's product |

---

## 5. Riskiest points

1. **`app.me()` gains a session check and a token branch (§3.9).** Every RPC depends on it. A bug either locks everyone out or lets a token act beyond its scope. Ship it behind the full invariant suites plus the new negative tests, and benchmark it: it is now one primary-key lookup per call.
2. **Remote log-out "at once" (SEC-04 AC).** Supabase access tokens stay valid until expiry. Only the database check in `app.me()` makes revocation immediate. Middleware alone is not enough, because the JWT sits in a cookie readable by the client.
3. **Self-lockout through IP rules or time windows.** The `setting_set` hook must refuse switching the allowlist on when the caller's own IP is not covered. Break-glass must be decided (§6) before the switch is offered.
4. **The intake for new products.** Today `store_product_secrets` accepts any `<key>_*_secret`. Opening intakes from the UI without binding them to a new product would let a staff member replace Orgpuls' webhook secret and forge product events. Bind the nonce to the product; never overwrite.
5. **Erasure.** It is irreversible across many tables, members are re-created by product events, and the D-24 blanking reaches `events_in.payload`. Preview, fresh MFA, an optional second admin, a product-side command for product users, and a test per module (SEC-11 AC) are all required.
6. **The MCP OAuth surface.** Dynamic client registration means anyone can register a client. Safety rests on: the user's consent screen, exact https redirect matching, PKCE, short-lived codes, the `mcp_access` check per call, and scopes that never include `global:security`/`global:configure`.
7. **Audit retention needs a delete path.** Loosening `audit_fixed` must allow only rows older than 5 years and only under `app.purging`, with a test that a recent row still cannot be deleted or updated, and TRUNCATE is still refused.

---

## 6. Open questions (with a recommendation for each)

1. **What "req/min, p95, errors" measure on Applications.** *Recommendation:* Sentral ↔ product calls (what the platform can measure), labelled so. Ask Orgpuls for an optional traffic figure in a status reply later (D-40).
2. **Product-side additions (D-40):** a ping or version reply, `job.run` events, `jobs.retry`, a maintenance switch, `members.erase`, content read commands (question set, pulse templates, tiltak library) with draft and rollback, and a count-only guardrail status. *Recommendation:* add ping, `job.run` and `members.erase` first: they unblock Applications, the Job monitor and SEC-11. Leave content and guardrails disabled or omitted until Orgpuls offers them.
3. **Break-glass access** ("break-glass access logged"). *Recommendation:* no in-app bypass. Break-glass is an operator using the Supabase dashboard SQL editor (`app.open_intake`-style), which disables `ip_allowlist`/`signin_hours`, writes an `audit` row `breakglass.used`, and alerts every `global:security` holder. Document it in the runbook.
4. **Password reuse and expiry.** Enforcing reuse needs password hashes and a check at change time, and there is no password-change flow today. *Recommendation:* register both settings with defaults `never`/`off` (unrestricted, D-16) and build `password_history` only if Tor turns reuse on. Strength stays in Auth config (12+, mixed), checked in CI against `config.toml`.
5. **Alert defaults.** D-29 fixes login alerts off and says nothing of the others. *Recommendation:* new device and admin logins off (they are login alerts); invite, failed logins, password reset and large export immediate, because they restrict no one. Delivery is in-app until the email provider (D-07) exists.
6. **Webhook policy with one `value_number`.** *Recommendation:* add five numeric register keys read only when `safeguards = custom`. Do not overload `safeguards`.
7. **Lockout after failed logins** ("Account locked 15 min"). *Recommendation:* rely on Supabase Auth's own sign-in rate limits and record `rate_limited` outcomes. A platform lockout is a restriction, so it would be a setting defaulting off, and none is proposed.
8. **The sub-processor public list.** *Recommendation:* an anon `subprocessors_public()` served on `go.owntheagenda.com` (D-28), cached. The marketing site reads it.
9. **Erasure tombstones** keep an email hash forever. *Recommendation:* keep the hash 13 months (the D-24 horizon), long enough to stop re-imports and re-enrichment, then delete.
10. **Client libraries and request collections** (INT-01). *Recommendation:* publish OpenAPI and a generated request collection only. Client libraries wait until an external developer needs one.
11. **Rate-limit storage.** A 2-second burst window in Postgres (UNLOGGED `api_burst`) suits a back-office. *Recommendation:* use Postgres, and measure. Add a cache service only if measurements demand it (no new provider without a decision).
12. **MCP writes and the "human approval before any write" NFR (Part G AI governance).** *Recommendation:* MCP writes are user-initiated in the assistant, which asks the user before calling a tool. Record them with source `mcp` and allow them. Make a register key `mcp_writes` (on/off, default on) if Tor wants read-only assistants.
13. **The Mobile route in the admin** (six phone mock-ups, "Simulate offline", "Landscape"). *Recommendation:* the admin page shows the real PWA views for the signed-in user inside the phone frames (live previews), plus D-41 panels "Your devices" (`push_devices`) and "Notification types" (`notification_prefs`). Offline and landscape stay preview controls that only change the frames, labelled as preview.
14. **Realtime sync (MOB-01 AC "appears on the web without refresh").** RLS-closed tables cannot feed Supabase Realtime row changes. *Recommendation:* Realtime **Broadcast** on private topics `staff:<id>`, sent from a trigger on `app.events`. Payload = `{entity, id, version}` only, and the client re-reads through the RPC. It needs one RLS policy on `realtime.messages` (`topic = 'staff:' || app.me()`). That is Supabase's table, not an `app` table, so D-09 is unaffected, but name it in the security checklist.
15. **Session idle timeout on phones.** D-29's 30 minutes plus TOTP at every sign-in makes field use painful. *Recommendation:* keep D-29. If Tor wants it, offer a separate `session_idle_mobile` key later. Never a remembered second factor (D-11).
16. **Geocoding and map tiles** (MOB-03) are providers (D-07). *Recommendation:* Kartverket/Geonorge's open address API for geocoding and Kartverket's open WMTS tiles. Both are free and Norwegian, and they need no key.
17. **Card scanner and note scanner** (AIA-07, MOB-06; SF-44 says "read on the device"). *Recommendation:* the image is sent through the AI gateway (Claude vision, D-07). The output is validated against a contact-draft schema and shown for review; the user saves it (AIA-07 "reviews before saving"). The image is stored on the contact in a private bucket. On-device OCR is not dependable in a PWA.
18. **Audio notes** need a transcription provider (chosen with MTG, D-07). *Recommendation:* store the audio file now (`files.kind = 'audio'`). The transcript field fills in when the provider exists, and until then the card says "Transcription not connected" (`not_connected`).

---

## 7. Mobile screen (route `/mobile`; MOB-01..08, AIA-07, UF-21, SF-31, SF-44; D-38)

### What the screen is
A showcase: header ("iOS and Android · same API · real-time sync"), a "Simulate offline" toggle (pending counter, "N changes synced · latest change wins"), a Portrait/Landscape toggle, and six phone frames with a static tab bar (Focus, Deals, Activities, Nearby, More). Every string inside the frames is **fabricated** demo content, down to the clock ("09:41") and the network ("5G · 82 %").

**D-38 governs.** Mobile waits until the web modules are done, then ships as a **PWA**: the same Next.js app at `/m/*`, the same session, the same RPCs. "iOS and Android" native apps are out. Under D-41 the admin route becomes the live preview described in §6 Q13. The module switch `mobile` (0005) turns all of it off, and the screen then shows the module-off state.

### Responsive web view of existing screens vs genuinely new data

| Phone | Elements | Real source | Verdict |
|---|---|---|---|
| **Focus** (MOB-02; AC "counts match the same filters on the web") | "God morgen, Tor" | `admins.name`; greeting by the hour in `admins.time_zone`, as an i18n key (the Norwegian greeting in an English UI is a design slip) | View |
| | Overdue 3 · "2 activities · 1 deal past close date" | the activities overdue filter of `activities_get` for `owner = me` + `deal_list` with `expected_close_date < today`, open, owner me. The same filter definitions as the web lists | View |
| | Today: "10:00 Call Kari Nordmann · Lumio AS · Expansion to Skiftly"; "13:30 Site visit Bergheim Bygg · Lillestrøm · 24 min drive" | `activities_get` (today, me). The **drive time is fabricated**: it needs a routing provider. Show the straight-line distance when location is granted, else nothing | View (distance needs `record_geo`) |
| | "4 unread · 6 customers within 10 km" | unread = `app.thread_unread` over my threads (0020); nearby = `nearby(...)` count | View + **new** (`record_geo`) |
| | "Expected to close this week: 2 deals · 148 000 kr" | `deal_list` filter close date in this ISO week, open, me; Σ value (FX per SF-32 when currencies differ) | View |
| | Home-screen widget "Next: Call Kari · 10:00" | **Not possible in a PWA** (D-38). Substitute: the Badging API shows the unread count on the installed icon. DEVIATIONS | Omitted |
| **Nearby** (MOB-03; AC "tapping a pin opens the record") | Map with pins (positions fabricated) | `nearby(lat, lng, radius, entities, filter)` over `record_geo` (organisations, and people through their organisation, and address custom fields: "filters, including address custom fields"). Tiles from the open Kartverket WMTS (Q16) | **New data**: `record_geo`, geocode job, PostGIS |
| | "Bergheim Bygg AS · 1,8 km · Deal «Group agreement» · Negotiation" | distance from the request's coordinates; the open deal with the latest activity (`deal_list` by organisation) | View |
| | "Lyngvær Rør AS · Customer · health 71 · no visit in 90 days" | `health_scores` (0025, latest); the last done activity of type `visit`/`meeting` for the organisation | View |
| | Navigate / Check in | Navigate = a `geo:` or maps URL hand-off, no data. Check in = `checkin()` → a done `visit` activity (new seed row in `activity_types`), no coordinates | View + seed row |
| **Deal on the go** (MOB-01, MOB-04, MOB-05) | "64 000 kr · Proposal sent · score 86 · close 16 Oct" | `deal_detail` (0009/0026, includes the score breakdown) | View |
| | "Kari Nordmann · Daglig leder · +47 912 34 567" | the person on the deal | View |
| | Call → "Call logged as activity · 6 min" | `tel:` link. When the app regains focus it asks for the outcome and duration, then `call_log_save` (0022; source `manual`). **A PWA cannot observe calls**: iOS and Android call logging and incoming caller matching (MOB-04) are impossible (D-38). MOB-04 AC "a call from the app creates an activity" holds through the prompt. Incoming matching is reachable only through a telephony provider (COM-12, `phone_match`) | View; **conflict D-38** for automatic logging |
| | Text | `sms:` link with the number filled | View |
| | "Move to Negotiation · Decision maker is required from this stage" | `deal_move`; the requirement comes from `app.fields.quality` + `from_stage_id` (CUS-02), already enforced | View |
| | Notes | `notes_list` / `note_save` | View |
| **Capture** (MOB-06, AIA-07; AC "a scanned note is saved on the chosen record"; "a scanned card produces a correct, editable contact draft") | Audio note, transcribed, attached to a deal | MediaRecorder → upload → `files` (kind `audio`) → transcription job (provider pending, Q18) | **New data**: `files`, storage bucket, transcription |
| | Business card → "Nora Berg · HR-leder · 2 phones · 2 emails found" | camera capture → AI gateway vision → draft → review → `card_draft_save` (honours `contact_rule`); the image goes to `files` (kind `card`) on the contact | **New**: `files`; AI gateway |
| | Scan notes (handwritten → text) | same path, kind `scan`; the text becomes a note on the chosen record | **New**: `files` |
| | Photos and files; "share from other apps" | upload to `files`. Share-in = the Web Share Target API, **Android only**; on iOS, upload from the file picker. DEVIATIONS | **New**: `files`; partial (D-38) |
| | "Contact rule: no rule (setting) — cards create contacts directly" | `app.setting('contact_rule')` (exists) | View |
| **Notifications** (MOB-07; AC "a new assignment sends one push") | Reminder "Call Kari in 15 minutes" | `activity_reminders` (channel `push` exists, 0010) → `app.dispatch_reminders` → `notifications` → `push_send` | **New data**: `push_devices`, `push_deliveries` |
| | "Assigned to you · Lead L-503 · Rule «Inbound — large orgs»" | `assignment_evaluations` (0021) → `app.notify(kind 'assignment', dedupe_key 'assignment:<event_id>:<staff>')` → one push (the unique `dedupe_key` + `push_deliveries` pk) | **New**: kind `assignment`, dedupe |
| | Mention | `notifications` kind `mention` (0007) | View + push |
| | Chat request "Visitor on /pris wants to talk" | LGN-02 live chat (phase 5, not built) → kind `chat_request` | Omitted until LGN |
| | Per-type configuration | NEW `notification_prefs` (+ `reminder_prefs` for reminders) | **New** |
| **Extras** (MOB-08; AC "a rep can answer a live chat from the phone") | "This month 312 000 kr · Won · 62 % of goal · 14 new deals" | won value this month (the Insights formula), the goal progress of my active `deals_won` goal (`goal_progress`, 0024), `count(deals created this month, owner me)`. The 312 000 is the same **fabricated** literal as on Insights | View |
| | Live chat takeover | LGN-02 (not built). The card is hidden until the `leadgen` module and live chat exist | Omitted until LGN |
| | "Project tasks · 2 due today" | PRJ (phase 6, not built); hidden until the `projects` module has tasks | Omitted until PRJ |
| **Offline** (MOB-05, SF-31; AC "offline changes appear after reconnecting") | Banner "Offline · N changes waiting · Sync now", toast "latest change wins" | Service worker + IndexedDB outbox; N = queued mutations (real, on the device). "Sync now" = `sync_apply`. See below | **New data**: `sync_receipts`; changelog source `mobile` |
| **Status bar and tab bar** | "09:41", "5G · 82 %", "No network" | Device chrome. In the preview frames, the real time and `navigator.onLine` | View |
| **Portrait / landscape** (MOB-01) | frame size toggle | responsive layout of `/m/*` | View |
| **Sign-in on mobile** | (Security shows "iPhone · Sentral app", "SSO + Face ID") | The same sign-in with TOTP (D-11), the same 30-min idle (D-29). No Face ID | View; conflict D-11 |

### Offline sync, concretely (SF-31)
- Each mutation on the device: `{mutation_id uuid, op ('update'|'create'|'note'|'activity_done'|'stage_move'), entity, record_id, base_version int, fields jsonb, client_at timestamptz}`, kept in order in IndexedDB. Scope (MOB-05): deals, notes and activities.
- `sync_apply(device_id, mutations[])` handles each mutation in order, in its own savepoint:
  1. If `sync_receipts(device_id, mutation_id)` exists, return the stored result (idempotent retry).
  2. If the record's `version = base_version`, apply it through the normal RPC (`rec_save` / `note_save` / `activity_done` / `deal_move`), so visibility, field rules and settings all apply. Changelog source `mobile`.
  3. Else, **latest change wins** (MOB-05): compare `least(client_at, now())` with the record's `updated_at`.
     - If the device change is later, apply it over the current row. The earlier value stays in `changelog.old_value`, which the rule requires.
     - Otherwise mark it `superseded` and return the current row.
  4. A permission or validation refusal is `rejected` with the error code. The device shows it, and nothing is retried.
- Afterwards the device pulls with `sync_changes(since)`: ids and versions of records it may see that changed since its cursor (from `app.events` ids). It then re-reads them through the normal RPCs.
- Device clocks are distrusted beyond `now()`, so a fast clock cannot win every conflict.

### What genuinely needs new data (summary)
`push_devices`, `push_deliveries`, `notification_prefs` and the new notification kinds with `dedupe_key` (MOB-07); `sync_receipts` and changelog source `mobile` (MOB-05); `record_geo` with PostGIS and a geocode job (MOB-02 nearby count, MOB-03); `files` with a private storage bucket (MOB-06, AIA-07; CRM-05 is a dependency); the `visit` activity type (check-in); a VAPID key in Vault; the Realtime broadcast topic policy (MOB-01). Everything else is a responsive view over RPCs that already exist (`deal_detail`, `deal_move`, `activities_get`, `activity_done`, `notes_list`, `note_save`, `call_log_save`, `phone_match`, `threads_get`, `goals_get`, `health_scores` via `customer_detail`, `search`, `rec_*`).

---

## 8. Feature, flow and NFR coverage (acceptance test per ID)

Source: `INSTRUCTIONS.md` Parts C–G. Each acceptance criterion becomes an automated test (Part G delivery plan). "DB" = SQL invariant file; "E2E" = Playwright flow.

| ID | Acceptance criterion | Test (where) | Built by |
|---|---|---|---|
| SEC-01 | The figures match the login log | DB: seed `login_log`/`staff_sessions`, assert `security_dashboard()` KPIs equal direct counts | §2.1 |
| SEC-02 | Each trigger produces one alert to admins | DB: fire each trigger twice → exactly one `security_alert_deliveries` row per (event, channel, recipient) | §2.2, §3.3 |
| SEC-03 | A login from a blocked IP is refused | DB + E2E: `ip_allowlist = on`, `worker_login_event` with an outside IP → `allowed = false`, `login_log.outcome = 'blocked_ip'`; `app.me()` null for a session moved outside | §2.2 |
| SEC-04 | Logging out a device ends its session at once | DB: `session_revoke` → the next RPC with that JWT raises `not_signed_in` | §3.9 |
| SEC-05 | A user provisioned at the IdP can log in without a local password | E2E (when SSO ships, D-31): invited staff signs in with Google, then TOTP | §2.4 |
| SEC-06 | With enforcement on, no user can log in without the second factor | DB: every public RPC refuses aal1 except `recovery_code_redeem`; `mfa` key is fixed | existing + §2.4 |
| SEC-07 | A user cannot perform an action missing from their set, in the interface or the API | DB: a token for a sales user calling `api_exec` for `global:configure` → forbidden | §3.9 |
| SEC-08 | A user outside the group cannot read the row by any route | DB: through `api_exec`, `mcp_index` search and webhook delivery | §1.3, §1.5 |
| SEC-09 | A deactivated user cannot log in and their records keep an owner | DB: deactivate → sessions ended, tokens and grants revoked (`staff_deactivated`) | §3.11 |
| SEC-10 | A restore test meets the agreed objectives | `ops_checks` row with rpo ≤ 60, rto ≤ 240 (D-35), recorded by `restore_test_record` | §2.5 |
| SEC-11 | An erasure request removes the person from every module | DB: seed the person in every table, erase, assert zero rows and blanked event payloads | §2.6 |
| INT-01 | Every interface action on records is possible through the API | DB: each `rec_*`, `lead_convert`, `records_merge` reachable via `api_exec`; OpenAPI lists every entity and custom field | §1.2 |
| INT-02 | A revoked token or grant is refused | DB: revoke → `worker_api_auth` null, `api_exec` raises | §1.2 |
| INT-03 | A client over the burst limit gets 429 with limit headers | Edge test against the `api` function with `api_rate = source_values` | §1.2 |
| INT-04 | A failing endpoint is retried on schedule and then banned | DB: simulated failures → attempts at +3/+30/+150 s; 10 first-attempt failures → `banned`, 30 min; 3 days → deleted, owner notified | §1.3 |
| INT-05 / INT-06 | Each connection can be made and revoked by the user | E2E per provider (mailbox, calendar) | §1.4 |
| INT-07 | A won deal posts to the configured channel | DB: `deal.won` → workflow `slack` step queued (0021) | existing engine |
| INT-08 | An invoice created from a deal carries the deal's lines | Adapter contract test (with the accounting provider) | 0021 step |
| INT-09 | A new deal can trigger an external automation | DB: `deal.created` → webhook delivery queued | §1.3 |
| INT-10 | An installed extension shows its panel on the detail view | E2E: `app_extensions` row → sandboxed iframe on the deal | §3.4 |
| INT-11 | Removing an integration revokes its access | DB: `catalog_remove` → Vault secret gone, connections `not_connected`, grants revoked | §1.4 |
| MCP-01 | An assistant can only see and change what the user can | DB: grant for user A; records hidden from A unreachable via `api_exec` and `mcp_index` | §1.5 |
| MCP-02 | Every tool has a schema and returns structured results | Contract test over the generated tool list | §1.5 |
| MCP-03 | After switch-off no assistant call succeeds | DB: `mcp_access = off` → `app.me()` null for `mcp` grants even when not revoked | §3.9 |
| AIA-06 | Search returns catalog entries matching the described need | Unit: "send invoices when a deal is won" → `acc`; the model output is validated against catalog keys | §1.4 |
| AIA-07 | A scanned card produces a correct, editable contact draft | E2E with a fixture card image; the draft is shown, not saved, until confirmed | §7 |
| MOB-01 | A change on mobile appears on the web without refresh | E2E: two browsers; a mobile save → a broadcast → the web list re-reads | §6 Q14 |
| MOB-02 | Counts match the same filters on the web | DB: `mobile_focus` counts = `activities_get` / `deal_list` with the same filters | §7 |
| MOB-03 | Tapping a pin opens the record | E2E | §7 |
| MOB-04 | A call from the app creates an activity | E2E: the `tel:` return prompt → `call_log_save` | §7 |
| MOB-05 | Offline changes appear after reconnecting | E2E (service worker offline) + DB tests of `sync_apply` (idempotent, superseded, latest wins, changelog keeps the earlier value) | §7 |
| MOB-06 | A scanned note is saved on the chosen record | E2E | §7 |
| MOB-07 | A new assignment sends one push | DB: an assignment event twice → one `notifications` row (`dedupe_key`), one `push_deliveries` row per device | §3.5 |
| MOB-08 | A rep can answer a live chat from the phone | waits for LGN-02 | — |
| ENT-01 | A gated feature is unavailable through every channel | DB: module off → web RPC, `api_exec` and MCP all raise `module_off` | existing + §3.9 |
| CUS-08 | Changes in the sandbox never touch the live company | Existing; plus R-SETTINGS-03 `sandbox_reset` (open, owned by the Settings spec) | — |

| Flow | Steps that touch these screens | E2E |
|---|---|---|
| UF-15 | 1 dashboard and assessment; 2 SSO + enforced 2FA; 3 rules with preview; 4 alerts; 5 login history + device log-out; 6 export or erase | One Playwright flow per step, as a staff member holding `global:security` |
| UF-16 | 1 connect Google/Microsoft; 2 token / OAuth app + reference; 3 webhooks; 4 banned then removed, visible in the list; 5 catalog search, install, review access; 6 AI connector switch | Per step |
| UF-21 | Focus → Nearby + navigate → offline deal + notes → audio note, card, next activity → sync | Mobile viewport, offline emulation |
| UF-22 | Add connector + log in → find/create/update → tool calls under the user's permissions and API limits → refused when off → changelog source = connector | MCP client test harness |
| SF-15 step 5, SF-22, SF-23, SF-27, SF-31, SF-41, SF-43, SF-44 | as specified in Part E | DB tests per step where the result is observable |

| Part G NFR | Proof |
|---|---|
| Anonymity firewall | `firewall_status()` live and `structure_invariants.sql` in CI; MCP index and API definition cover CRM entities only |
| Access | aal2 everywhere, fresh MFA for sensitive actions, token scopes never reach `global:security` |
| Audit | `app.log` on every write here; audited reads listed in §3.10; `audit.source`/`principal_*`; 5-year purge path tested |
| Data residency | `platform_facts.db_region` = eu-central-1; sub-processor regions from contracts |
| Recovery | `ops_checks` (backup, PITR, restore test) against RPO 1 h / RTO 4 h (D-35) |
| Monitoring | `job_runs` + `job.failed` alerts; integration health on Applications |
| Privacy | erasure across modules (SEC-11 test), retention rules each with a job, sub-processor register |
| Destructive actions | preview + typed confirmation (+ second admin when on) for erasure, integration removal, maintenance mode |
| Job runtime | pg_cron + pgmq (D-05); workers as edge functions |
| Provider independence | geocoding, tiles, push, transcription, vision, backups behind adapters / workers |
