# 02 — Database inventory

Phase A, A3.2. Source: both migrations read in full (`supabase/migrations/0001_foundation.sql`,
`0002_product_secrets.sql`). They were also applied to an empty local Supabase database (CLI, scratch
copy outside the repository, Postgres 17), and that database's catalog was introspected. The two agree.
The hosted project could not be introspected with the current tokens (Q-01), so drift against
production is **unverified**.

## Summary

| Item | Count |
|---|---|
| Schemas used | `app` (data, usage granted to `service_role` only), `public` (RPCs) |
| Tables | 11, all in `app` |
| Tables with RLS on | 11 of 11 |
| RLS policies | **0** (deny-all by design: no client role reaches a table) |
| Client grants on tables | none to `anon` or `authenticated`. `service_role` has full table privileges on 10 tables; `intake_nonces` has none |
| Functions | 11 (4 in `app`, 7 in `public`), all but one `SECURITY DEFINER` with `search_path = ''` |
| Triggers | 1 (`audit_fixed`) |
| Views, materialised views | 0 |
| Extensions | pgcrypto, uuid-ossp, supabase_vault, pg_stat_statements, plpgsql (Supabase defaults) |
| Scheduled jobs | 0 (no `cron` schema) |
| Storage buckets | 0 |
| Seed data in migrations | `app.products ('orgpuls','Orgpuls')` (`0001:329`) |

## Tables

Classification per A3.2: **admin** = the platform's own records; **product** = mirrored from a product;
**response-level** = survey answers or respondent identity; **CRM** = the brief's CRM records.

| Table | Class | Columns (type, null) | Keys and constraints | RLS / policies / client grants | Source |
|---|---|---|---|---|---|
| `app.admins` | admin | email text NN, role text NN default `admin`, active bool NN, created_at | PK email; email lower-case and format check; role ∈ {owner, admin} | on / 0 / none | `0001:18-23` |
| `app.products` | admin | key text NN, name text NN, created_at | PK key; key `^[a-z][a-z0-9_]{1,30}$`; name 1–80 | on / 0 / none | `0001:41-45` |
| `app.installations` | admin | product, api_url (https origin), public_key (20–2000), enabled, updated_at | PK product; FK products ON DELETE CASCADE | on / 0 / none | `0001:47-56` |
| `app.accounts` | admin (the customer company) | id uuid, name NN, org_number (9 digits, unique), created_at, updated_at | PK id; UNIQUE org_number | on / 0 / none | `0001:58-64` |
| `app.account_products` | product (tenant ↔ account) | product, tenant_id (1–100), account_id, status ∈ {active, deleted}, details jsonb, attribution jsonb, created_at, deleted_at | PK (product, tenant_id); FK account ON DELETE CASCADE; FK product; index on account_id | on / 0 / none | `0001:66-77` |
| `app.subscriptions` | product (billing mirror) | product, tenant_id, plan, billing_interval, trial/confirm/free/cancel/deletion timestamps, updated_at | PK (product, tenant_id); FK account_products ON DELETE CASCADE | on / 0 / none | `0001:80-96` |
| `app.members` | product (customer users) | product, tenant_id, user_id, role, email, name, active, updated_at | PK (product, tenant_id, user_id); FK account_products ON DELETE CASCADE | on / 0 / none | `0001:98-109` |
| `app.usage_daily` | product | product, tenant_id, day, data jsonb | PK (product, tenant_id, day); FK account_products ON DELETE CASCADE | on / 0 / none | `0001:111-120` |
| `app.events_in` | product (raw events) | id, product, source_id, kind (`a.b`), tenant_id, payload jsonb, occurred_at, received_at | PK id; UNIQUE (product, source_id); FK product; index (product, kind, received_at desc) | on / 0 / none | `0001:122-133` |
| `app.audit` | admin | id, at, actor (1–254), product, command (`a.b`), arg_names text[], ok, error (≤200) | PK id; append-only trigger | on / 0 / none | `0001:136-154` |
| `app.intake_nonces` | admin | hash bytea, expires_at | PK hash | on / 0 / **no grant at all** | `0002:9-14` |

**Response-level tables: none.** By design, the platform holds no survey answer, respondent or group
data. Orgpuls' event registry permits no respondent field (Orgpuls `app.platform_event_kinds`, 0205), and
the platform has no foreign key, view or function that could reach Orgpuls' tables. The firewall list
for R6 is therefore empty here; it lives in Orgpuls. A database test that keeps it that way does not
exist yet (see 05, SEC and Part F).

**CRM tables: none.** There is no table for contacts, leads, deals, pipelines, activities, campaigns,
segments, consent, tickets or settings.

Notable gaps in the conventions A6 asks for:
- No `created_by`/`updated_by`, `deleted_at` (except `account_products`), `version` or owner/visibility columns.
- `app.admins` keys on email with no link to `auth.users` (`0001:18`).
- Every admin table carries a product key only where the row is product-scoped (`account_products`,
  `subscriptions`, `members`, `usage_daily`, `events_in`, `audit`). `admins` and `accounts` are cross-product
  by design. Appendix 2 says "every admin table carries a product ID" (Q-25).

## Functions

| Function | Security | Executable by | What it does | Source |
|---|---|---|---|---|
| `app.admin_email()` | definer | owner only | Email of the signed-in user if an active admin with a confirmed account | `0001:25-30` |
| `app.is_admin()` | definer | owner only | `admin_email()` not null and JWT `aal = aal2` | `0001:32-36` |
| `app.audit_fixed()` | invoker | none | Trigger function: rejects every update and delete on `app.audit` | `0001:148-154` |
| `app.open_intake()` | definer | owner only | Creates a 15-minute one-time nonce (sha256 stored) | `0002:16-25` |
| `public.ingest_events(text, jsonb)` | definer | service_role | Stores events once and projects them onto accounts, subscriptions, members, usage | `0001:173-268` |
| `public.record_command(...)` | definer | service_role | Inserts an `app.audit` row | `0001:271-278` |
| `public.installation_of(text)` | definer | service_role | Installation URL and public key for a product | `0001:281-288` |
| `public.admin_whoami()` | definer | authenticated, service_role | {account, aal2, admin, email} for the caller | `0001:292-299` |
| `public.platform_status()` | definer | authenticated, service_role | Admin-gated: installations, counts, events by kind, recent events and commands | `0001:302-327` |
| `public.store_product_secrets(text, jsonb)` | definer | service_role | Consumes a nonce and writes product secrets to Vault | `0002:27-56` |
| `public.product_secret(text)` | definer | service_role | Reads a product secret from Vault | `0002:58-65` |

## Triggers

| Table | Trigger | Rule | Source |
|---|---|---|---|
| `app.audit` | `audit_fixed` BEFORE UPDATE OR DELETE | Rejects all. `app.audit` has no foreign keys, so the referential-maintenance problem the Orgpuls rules warn about cannot arise here today | `0001:148-154` |

## Grants at schema level

- `app`: usage for `postgres` and `service_role` only (`0001:13-14`). `anon` and `authenticated` cannot
  even resolve `app.*` names.
- `public`: Supabase defaults. Only the two functions in the table above are executable by `authenticated`.

## Drift

- Repository ⇄ fresh local database: none. Both migrations apply cleanly in order, and the catalog matches the files.
- Repository ⇄ hosted project: **not checked** (Q-01). On 2026-10-05 both migrations were applied to the hosted
  project through the Supabase MCP, and the hosted security advisor reported only the expected notices:
  RLS without policy on every table, two definer functions callable by `authenticated`, and leaked-password
  protection off. Some rows on the hosted project were created outside migrations: the installation row,
  the owner row in `app.admins`, and a deactivated test user. They are not reproducible from the repository
  (Q-02).
