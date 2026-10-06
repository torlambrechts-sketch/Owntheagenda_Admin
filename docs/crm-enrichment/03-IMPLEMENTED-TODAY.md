# 03 — What is implemented today

Phase A, A3.3. The whole platform as of `main` `8c01aec` (2026-10-06). Run locally: production build
(`next build && next start`) against the scratch local database from `02-DATABASE.md`. Two seeded
accounts were used: one admin (`kari@lumio.example`, in `app.admins` as owner) and one account that is
not an admin. They exist in the local database only. One local-only adaptation was needed, outside the
repository: TOTP enabled in the scratch `config.toml`, and an https proxy in front of the local API,
because `lib/supabase/env.ts` accepts only an `https://` origin. Baseline screenshots are in
`screens/baseline/`.

## Routes and pages

| Route | What it does | Reads / writes | Role check | Tests | Screenshots |
|---|---|---|---|---|---|
| `/` (`app/page.tsx`) | Status page: installations, customers count, events (total, last, by kind, recent), recent commands, «Test koblingen» button | `public.admin_whoami`, `public.platform_status` (read) | Middleware: user + aal2. Page: `!account` → `/ingen-tilgang`, `!admin` → `/mfa` (`app/page.tsx:14-15`). The RPC itself checks `app.is_admin()` | none | `status-1440/390.png`, `status-test-result-1440/390.png`, `root-redirect-login-*` |
| `/login` (`app/login/*`) | Email + password | Supabase Auth sign-in | public | none | `login-error-1440/390.png` |
| `/mfa` (`app/mfa/*`) | Enrol a TOTP factor (QR + key) or verify a code | Supabase Auth MFA | Middleware: user required (not aal2). **No admin check**: a non-admin account can enrol a factor and then reaches `/ingen-tilgang` | none | `mfa-start-*`, `mfa-enrol-1440`, `mfa-wrong-code-1440`, `mfa-verify-390`, `non-admin-after-login-*` |
| `/ingen-tilgang` | «Ingen tilgang» with a sign-out button | Supabase Auth sign-out | public | none | `ingen-tilgang-1440/390.png` |

There is no layout shell, navigation, list view, detail view or settings screen (`app/layout.tsx:11-24`).

## Server actions and route handlers

| Action | File | What it does | Validation | Role check |
|---|---|---|---|---|
| `signIn` | `app/login/actions.ts:12` | Password sign-in, then `/mfa` | zod (`:9`) | — |
| `signOut` | `app/login/actions.ts:21` | Local sign-out | — | — |
| `enroll` | `app/mfa/actions.ts` | Removes unverified TOTP factors, enrols a new one | — | signed-in user |
| `verify` | `app/mfa/actions.ts` | challengeAndVerify, then `/` | zod (uuid + 6 digits) | signed-in user |
| `testConnection` | `app/actions.ts:10` | Runs `orgs.list` through `runCommand` and counts the result | zod on the reply | `whoami().admin` (`:12`), and again in `product-command` |

No route handlers (`app/**/route.ts`): none exist.

## Edge functions

| Function | Auth | Reads / writes | Tests |
|---|---|---|---|
| `orgpuls-events` | HMAC over `<ts>.<body>` with the Vault webhook secret, 5-minute window | `public.ingest_events` → `events_in` and projections | signing helpers only (`tests/signing.test.ts`) |
| `product-command` | Caller's JWT must be an admin (aal2) via `admin_whoami`, or the service-role key | `installation_of`, `product_secret`, Orgpuls `platform_command`, `record_command` | signing helpers only |
| `secret-intake` | One-time nonce | `store_product_secrets` → Vault | none |

## Jobs, email templates, feature flags

None of any of these.

## Runtime observations (local run)

| # | Observation | Evidence | Note |
|---|---|---|---|
| R-1 | With TOTP disabled on the Auth server, «Sett opp autentiseringsapp» does nothing visible. `enroll()` returns `{ok:false}`, and `MfaForms` shows the button again with no message | `app/mfa/MfaForms.tsx:66-69`; first run's `mfa-start` stayed unchanged | Missing error state |
| R-2 | The connection test shows a raw code: «Kommandoen feilet: http_503» | `status-test-result-1440.png`; `app/TestButton.tsx:23`, `lib/platform/command.ts:31` | Error text is not a translated message |
| R-3 | At 390 px the header's «Logg ut» reaches the right edge | `status-390.png` | Header has no gutter on the right at that width |
| R-4 | One console error at 1440 px: a 404, most likely `/favicon.ico` | Playwright console log | No favicon |
| R-5 | A non-admin account is sent to `/mfa` and may enrol a factor before learning it has no access | `non-admin-after-login-*.png`; `middleware.ts` | Spec question (SEC) |
| R-6 | Locally «Orgpuls: Ikke installert», «0 kunder», «Ingen hendelser mottatt ennå», «Ingen kommandoer sendt ennå»: the empty states render | `status-1440.png` | — |

No fix was made: Phase A changes no application code. R-1 to R-4 are carried into the Phase B plan.

## Hosted state (from the owner's own screen, 2026-10-06)

The owner signed in on `www.owntheagenda.com` with TOTP. The status page showed: Orgpuls «På»; the
connection test «2 organisasjoner i Orgpuls»; 2 customers; 10 events received (org.created 2,
usage.daily 4, member.joined 3, billing.changed 1), the latest the nightly `usage.daily`. This is the
same code path as the local run, against production data.
