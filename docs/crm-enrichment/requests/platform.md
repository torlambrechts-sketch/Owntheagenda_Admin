# Requests: Platform (Phase 8 screen build)

## Status

| Request | Status |
|---|---|
| R-01 | Done: the `job.*`, `webhook.*`, `api.*`, `security.*` and `capture.*` texts are in `shell.json`; the bell knows kind `assignment` (`lib/notification-kinds.ts`) |
| R-02..R-06 | Open: an API scopes read, an open-problems list, product-command recording (edge), the Orgpuls reply contracts (D-40), webhook secret rotation |

What the Platform screens need beyond `0044_platform.sql`. None of it blocks the screens: each item is left out or shown in
its honest state until the change exists (`deviations/platform.md`).

| ID | What | Why | Until then |
|---|---|---|---|
| R-PLATFORM-01 | Shell (shared files): notification texts for `job.failed` (`job`), `webhook.banned` (`event`, `host`, `minutes`), `webhook.deleted` (`event`, `host`), `api.budget_warning` (`percent`, `budget`) in `shell.json`, with the routes in the contract; the notification filter must include kind `assignment` (V-P8P-10) | The database emits them (0044); the shell renders notification texts | Those notifications show whatever the shell's fallback is (V-PLATFORM-21) |
| R-PLATFORM-02 | A read of `app.api_scopes` for staff (e.g. `api_scopes_get()` → `[{scope}]`, or a `scopes` key in `api_overview`) | The OAuth app dialog's scope chips should be data, not a client list | `API_SCOPES` in `lib/data/platform-shared.ts` mirrors 0044's seed; `app.scopes_ok` refuses anything else |
| R-PLATFORM-03 | A list of open problem tickets for staff with `global:see` (`problems_open()` → `[{id, number, subject}]`), or reuse of the Tickets › Problems read | `status_notice_set` takes `p_problem`, but the banner has no source to pick a problem from | A banner keeps the problem it already has (Save passes it on); a new link cannot be made from this screen (V-PLATFORM-17) |
| R-PLATFORM-04 | Edge: `product-command` calls `worker_application_ping` for «Test connection» (with the product's version when its reply has one) and `worker_integration_call` for every call; `orgpuls-events` reports each batch | Health, sparklines, p95, errors and the last answer are read from these rows | The test answer is toasted, not stored; every card reads «No data» |
| R-PLATFORM-05 | D-40 product contracts: the reply shapes of `modules.list`, `locales.pilots`, `legal.reviews`, `translations.list`; `settings.set_maintenance`; `jobs.retry`; count-only `job.run` events | Product flags, content counts, maintenance mode, product jobs | Named, not drawn; maintenance answers not_available (V-PLATFORM-16..18, -15) |
| R-PLATFORM-06 | `webhook_rotate_secret(p_id)` (owner or global:configure) → `{secret (once)}` | A webhook's signing secret can only be had at creation; a leaked or missing one (the seeded subscriptions have none) means delete and re-create, losing the delivery history | Delete and re-create |
