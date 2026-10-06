# 01 — Environment

Phase A, A3.1. Written 2026-10-06 against `main` at `8c01aec`. Every fact cites the file it comes from.

## The most important fact

The brief (`INSTRUCTIONS.md`) was written on 3 October 2026 for "the Orgpuls platform admin", which then
lived inside the Orgpuls product. On 5 October 2026 that admin was **deleted from Orgpuls** (Orgpuls
migration `0206_admin_leaves.sql`, decision X-105) and replaced by this separate platform: its own
repository, its own Supabase project (`zuvqbaejoktpekfsiyyr`, eu-central-1) and its own domain
(`www.owntheagenda.com`). The platform's first commit is `5830015` (2026-10-05).

So "the admin" the brief refers to as already existing (Part B, Appendix 2) **is not this code**. What
the brief calls the baseline — organisations, contacts, segments, campaigns, sequences, consent, tickets,
web analytics, CMS, staff roles — was partly built in Orgpuls and then removed with its data. In this
repository it is absent. Questions Q-01 and Q-02 in `06-QUESTIONS.md` ask how to treat that.

## Package manager, scripts and versions

| Fact | Value | Source |
|---|---|---|
| Package manager | npm (lockfile v3) | `package-lock.json` |
| Module type | ESM | `package.json` `"type": "module"` |
| Scripts | `dev`, `build`, `start`, `lint`, `typecheck`, `test`, `verify:i18n`, `functions:check`, `functions:deploy` | `package.json` |
| Next.js | 15.5.27 (App Router) | `package-lock.json` |
| React | 19.3.0 | `package-lock.json` |
| TypeScript | 5.9.3, `strict`, `noUncheckedIndexedAccess` | `package-lock.json`; `tsconfig.json:7-8` |
| next-intl | 4.14.9, no locale routing, locale from cookie `lang`, `no` default, time zone Europe/Oslo | `lib/i18n/request.ts` |
| Supabase | `@supabase/ssr` 0.12.7, `@supabase/supabase-js` 2.117.2 | `package-lock.json` |
| Validation | zod 4.6.5 | `package-lock.json`; e.g. `app/login/actions.ts:9` |
| Styling | Tailwind CSS 3.4.19, **placeholder config, no tokens** | `tailwind.config.ts` |
| Tests | vitest 2.1.9, `tests/**/*.test.ts` | `vitest.config.ts:6` |
| Lint | ESLint 8.57.1, `next/core-web-vitals` + `next/typescript` | `.eslintrc.json` |
| Edge functions | Deno, `deno check` via `npx -y deno` | `scripts/functions.mjs:21`; `supabase/functions/deno.json` |

## Where the admin lives and how it is separated from the products

- The whole repository is the admin. It is a separate Next.js app with a separate Supabase project.
  No product code is in it, and no product database is reachable from it except through signed commands
  (`supabase/functions/product-command/index.ts`). It holds no key to any product database.
- Products reach the platform only by posting signed events to a per-product function
  (`supabase/functions/orgpuls-events/index.ts`), verified by HMAC (`_shared/signing.ts:verifyWebhook`).
- The product's shared secrets are in this project's Vault (`supabase/migrations/0002_product_secrets.sql`).

## Sign-in, admin roles, MFA and the audit log

| Concern | How it works | Source |
|---|---|---|
| Sign-in | Email and password through Supabase Auth, server action | `app/login/actions.ts:12-19` |
| Second factor | TOTP: enrol (issuer «OwnTheAgenda Admin») and verify | `app/mfa/actions.ts`, `app/mfa/MfaForms.tsx` |
| Gate on every route | Middleware requires a user and aal2, else `/login` or `/mfa`. Public paths are `/login` and `/ingen-tilgang`. It fails closed, and Supabase calls are bounded to 5 s | `middleware.ts:10-50`; `lib/supabase/env.ts` |
| Who is an admin | `app.admins` (email primary key, role `owner`/`admin`, active). `app.is_admin()` = active row + confirmed account + `aal2` in the JWT | `0001_foundation.sql:18-36` |
| Roles | Only `owner` and `admin`, and **no code reads the difference**. Appendix 2's four roles (super-admin, support, finance, analyst) and the brief's sales, marketing and project roles do not exist | `0001_foundation.sql:21`; grep `role` in `app/`, `lib/` |
| Audit | `app.audit`: one row per product command (actor, product, command, argument names, ok, error), append-only by trigger. **Reads are not audited, and neither are writes to the platform's own tables** (there are none yet) | `0001_foundation.sql:136-154, 271-278` |
| Session timeout, IP allowlist, login alerts | None | grep in repository: no matches |

## Migrations, types and seeds

| Concern | Fact | Source |
|---|---|---|
| Migrations | Plain SQL in `supabase/migrations/NNNN_name.sql`. Applied to the hosted project through the Supabase MCP `apply_migration` (the Management API token used in cloud sessions has no access to this project) | `CLAUDE.md` «Operating»; `README.md` |
| Local database | **No `supabase/config.toml` in the repository**, so the repository's own commands cannot start one. For this phase a scratch copy (`supabase init` outside the repo, the two migrations copied in) was started with the Supabase CLI. Both migrations apply cleanly to an empty database | outside the repository; see `02-DATABASE.md` |
| Generated types | None: zod parses every RPC result instead | `lib/platform/read.ts:6, 17-27` |
| Seeds | None. **No demo tenant** (the brief's R8 names Lumio AS and Kari Nordmann) | repository has no `seed.sql` |

## Background jobs, email, billing, feature flags

| Concern | Fact | Source |
|---|---|---|
| Scheduled jobs | None (no pg_cron schema in the database, no Vercel cron) | `02-DATABASE.md` «cron» |
| Background work | Product events arrive by push (Orgpuls' dispatcher, every 5 min). There is no job runner | `orgpuls-events/index.ts` |
| Email provider | None | grep: no provider SDK or key |
| Billing mirror | `app.subscriptions`, projected from Orgpuls' `billing.changed` events. Read-only mirror, no Stripe | `0001_foundation.sql:80-96, 236-248` |
| Feature flags | None | grep: no flag registry |

## Component library, design tokens and layout shell

- No component library and no shadcn/ui; the brief's Part B "target stack" names shadcn/ui (Q-05).
- No design tokens: `tailwind.config.ts` is a placeholder whose comment says the platform's design replaces it.
- The layout is a plain shell (`app/layout.tsx:11-24`). There is no navigation, no sidebar and no themes.
- The target design is the Claude Design handoff in `design-reference/sentral/` (21 screens). It uses its
  own fonts (DM Sans, Playfair, in `project/fonts/`).

## Tests and CI

| Kind | Exists? | Source |
|---|---|---|
| Unit | Yes: 4 vitest tests of the signing helpers | `tests/signing.test.ts` |
| Database | **No** database tests | no `supabase/tests` content |
| End-to-end | **No** tool configured (Playwright is available on the machine but not in `package.json`) | `package.json` |
| Visual regression | No | — |
| Accessibility | No | — |
| CI | GitHub Actions: `npm ci`, typecheck, lint, test, verify:i18n, functions:check, build | `.github/workflows/ci.yml` |

## Hosted environment (read-only facts, not used for analysis)

- Vercel project `owntheagenda-com`, connected to this repository after 2026-10-06 (its Git connection
  had pointed at another repository). Domains: `owntheagenda.com` (308 to www) and `www.owntheagenda.com`.
- Environment: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (both public), Production only.
- Since 2026-10-06 the Supabase access tokens available in cloud sessions are refused for every project
  ("FGA Authentication Error"), probably after the projects moved organisation. The hosted catalog could
  therefore **not** be compared with the repository (Q-03).

## Facts that could not be established (→ questions)

- Q-01: whether the Orgpuls admin the brief describes should be treated as the baseline (it no longer exists).
- Q-03: hosted-database drift. The hosted project could not be reached with the current tokens.
- Q-04: the demo tenant (Lumio AS, Kari Nordmann) does not exist in the platform.
- Q-05: component library (shadcn/ui per Part B) against the design bundle's own components.
- Q-06: the repository cannot start a local database by its own commands. Adding `supabase/config.toml` needs approval.
