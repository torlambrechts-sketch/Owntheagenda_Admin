# CLAUDE.md — the platform (Owntheagenda Admin)

The platform is where the company runs its products: their customers, subscriptions, support and sales.
It stands outside every product. A product connects to it through a signed API, and the platform holds
no key to any product's database. Orgpuls is the first product (Orgpuls X-104/X-105/X-106).

Read `README.md`, then `docs/crm-enrichment/INSTRUCTIONS.md` before you build a feature.

## Stack (fixed)
- Next.js 15 (App Router) + TypeScript `strict` + Tailwind 3 + React 19, deployed on Vercel.
- Supabase project `zuvqbaejoktpekfsiyyr` (eu-central-1): Postgres, Auth with TOTP, Vault, edge functions.
- i18n: next-intl without locale routing. The locale comes from the `lang` cookie, and `no` is the
  source language. Every string a user sees comes from `messages/<lang>.json`.
- zod at every server boundary. An RPC result is parsed, never cast.

## Security rules: breaking one fails the change
1. **No client reads a table.** Every table lives in schema `app`, has RLS on, no policy and no grant.
   The UI reads through SECURITY DEFINER functions in `public` that first ask `app.is_admin()`: an
   active row in `app.admins`, a confirmed account, **and aal2**. A new table gets RLS in the same
   migration.
2. **An admin signs in with a second factor.** `middleware.ts` sends anybody without aal2 to `/mfa` and
   fails closed. Do not add a public path without a reason written beside it.
3. **A product is reached only by `product-command`.** It signs an HS256 token holding the actor, the one
   scope the command needs and a unique id, and lives two minutes. It writes `app.audit` with the
   argument *names*, never their values. Nothing else may hold or use a product's token secret.
4. **Events come in only through the product's events function.** The HMAC signature is checked before
   the body is parsed. Anything older than five minutes is refused. An event already received is a
   duplicate.
5. **Shared secrets live in this project's Vault.** They are read only through `public.product_secret`,
   which only the service role may call. They arrive through `secret-intake` with a one-time number
   (`app.open_intake()`, fifteen minutes). Never print a secret, write one into a tracked file, or pass
   one through a person.
6. **No respondent data, ever.** A product sends what its own event registry allows: customers, their
   users, billing and counts. It never sends answers, groups or comments. Logs carry kinds, counts and
   status codes, never a payload. Contact and support messages are a person's own words.
7. **Schema changes only through `supabase/migrations/`.** Never edit an applied migration; add a new one.
   0001's comment about function environment secrets is superseded by 0002.

## Design
- The design source is `design-reference/sentral/` (Claude Design handoff). Read
  `project/Sentral Admin.dc.html` in full, and follow its imports, before building a screen.
- Recreate its rendering exactly in React and Tailwind. Do not copy its internal structure.
- Tokens are transcribed from the bundle into `tailwind.config.ts`. They are not invented.
- Never fabricate data: a value the schema does not hold is not rendered as if it were real.

## Gates
`npm run typecheck`, `npm run lint`, `npm test`, `npm run verify:i18n`, `npm run functions:check`,
`npm run build`. CI runs them all on every push.

## Operating
- Database work and edge-function deploys go through the Supabase MCP. The Management API token in cloud
  sessions belongs to Orgpuls and returns 403 here.
- Edge functions deploy with `verify_jwt: false`, because each one does its own authentication. Upload
  `index.ts` together with the `_shared/*.ts` it imports and `deno.json`.
- A redeploy through the MCP needs `import_map_path: "deno.json"`.
