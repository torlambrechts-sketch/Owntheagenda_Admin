# Owntheagenda Admin — the platform

The company's admin and CRM. It is the one place to see every customer across every product, act on a
product, and receive what products report. Orgpuls is the first installed product.

## What runs where

| Part | Where | What it does |
|---|---|---|
| Web app | Vercel (this repository) | Sign-in with TOTP; the screens |
| Database | Supabase `zuvqbaejoktpekfsiyyr` (eu-central-1) | `app.*` tables, RLS on, no client grants; admin-gated RPCs |
| `orgpuls-events` | edge function | Orgpuls' signed events in → `public.ingest_events` → customers, subscriptions, members, usage |
| `product-command` | edge function | an admin's (aal2) or the service role's command → signed token → Orgpuls `platform_command` → audit |
| `secret-intake` | edge function | a product's database hands over its shared secrets with a one-time number |

### The connection to Orgpuls
- **Commands:** HS256 JWT under `orgpuls_token_secret` with `aud=orgpuls`, the actor, the scope and a
  unique id, two minutes of life. The commands and their scopes are in
  `supabase/functions/_shared/orgpuls.ts` and must match Orgpuls' `app.platform_command_map`.
- **Events:** Orgpuls' dispatcher POSTs `{"events":[…]}` every five minutes. It signs them with
  `x-orgpuls-signature: sha256=HMAC(orgpuls_webhook_secret, "<ts>.<body>")`.
- **Catching up:** the `orgs.resync` command (Orgpuls 0207) re-sends what the platform should know about
  one organisation, or all of them. Use it after the platform database has been rebuilt.

## Getting started (owner's steps)

1. **Your account.** In Supabase → Authentication → Users, create a user for the address in `app.admins`
   and confirm it. A user who is not in `app.admins` gets no access, even when signed in.
2. **Turn sign-ups off.** Authentication → Sign In / Providers → turn off «Allow new users to sign up».
3. **Vercel.** Import this repository and set `NEXT_PUBLIC_SUPABASE_URL` and
   `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Both are public values; see `.env.example`.
4. **Auth URLs.** In Supabase → Authentication → URL Configuration, set the Site URL to the platform's
   domain (for example `https://admin.owntheagenda.com`).
5. **Sign in** and scan the QR code with an authenticator app. On the status page, «Test koblingen»
   runs `orgs.list` against Orgpuls.

## Development

```bash
npm ci
cp .env.example .env.local
npm run dev
npm run typecheck && npm run lint && npm test && npm run verify:i18n && npm run functions:check && npm run build
```

Database changes go in `supabase/migrations/`. They are applied with the Supabase MCP.

## Design and next phase
- The design is in `design-reference/sentral/` (21 screens, Claude Design).
- The CRM enrichment instructions are in `docs/crm-enrichment/INSTRUCTIONS.md`. Their Phase A, a gap
  analysis, comes before any screen is built.
