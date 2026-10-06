# Build guide — how a screen is built in the platform

Phase B conventions. Every screen of `design-reference/sentral/` is built the same way. Read this, the
platform `CLAUDE.md`, `DECISIONS.md` and `07-IMPLEMENTATION-PLAN.md` before building a screen.

## Running it locally

```bash
supabase start -x studio,realtime,analytics,vector,imgproxy,edge-runtime,logflare,supavisor,postgres-meta
npm run db:reset                      # regenerates supabase/seed.sql from the design data, rebuilds the database
npm run dev:local                     # Next on :3000 against the local stack (the shell may carry other URLs)
node scripts/db/run-tests.mjs         # every SQL suite
node scripts/visual/shoot.mjs /customers           # the app at 1440 and 390 → screens/current
node scripts/visual/design.mjs customers           # the design's own rendering → screens/design
```

Seeded staff sign in with the password and TOTP secret in `scripts/seed/dev-credentials.mjs`
(tor = Admin, ingrid/eirik = Sales, magnus/hanna = Support, sara = Finance, jonas = Marketing,
emma = Project, ola = Read-only). The development data is the design's own scenario (Lumio AS).

## Data: one path

- Every table is in `app`, RLS on, no policy, no grant. The UI calls `public` security-definer functions.
- Business records go through the generic functions: `rec_list(entity, query)`, `rec_get`, `rec_save`,
  `rec_bulk`, `rec_delete`, `rec_restore`, `rec_history`, `rec_group`. A record type is registered in
  `app.entities` and its writable/filterable columns in `app.entity_columns`. They check the right in the
  record type's scope (`app.require(scope, action)`), visibility (`app.visible`), the version, write the
  history and the audit, and emit `<entity>.created|updated|deleted`.
- An operation that is more than a field write (move a deal's stage, convert a lead, merge, reply to a
  ticket) is its own function, named for what it does, which uses the same helpers (`app.require`,
  `app.log`, `app.emit`, the changelog) and raises the same codes: `forbidden`, `not_found`,
  `version_conflict`, `invalid` (detail = field), `reason_required`, `module_off`, `not_signed_in`.
- Server code calls them only through `rpc()` / `rpcOrThrow()` in `lib/rpc.ts` with a zod schema. Data
  loaders live in `lib/data/<area>.ts`; server actions in the route folder (`actions.ts`), each parsing its
  input with zod and returning `{ ok } | { ok: false, code, detail }`.
- A migration is never edited after it is applied to the hosted project. Number new ones after the last.
- Every new table: RLS + revoke in the same migration, a check in a suite under `supabase/tests/`.
- Demo rows come only from `scripts/seed/generate.mjs` (from `admin-data.js`). Never insert by hand.

## Never fabricate

The design's scripts compute many values from a seeded random generator (health parts, NPS, invoice
numbers, "2 days ago" logins). A value the database does not hold is not rendered as if it were real:
render the real state, `—` (the design's own null), nothing, or the design's empty treatment. Where a block
cannot be backed yet, leave it out and note it in `docs/crm-enrichment/DEVIATIONS.md` with the reason.
Survey answers and respondents never exist here (the firewall); Orgpuls sends counts and dates only.

## Visual: transcribe, do not restyle

- Read the screen's `.dc.html` fully. Recreate its markup in React with Tailwind using the tokens in
  `tailwind.config.ts` (colours by name, `rounded-<px>`, `text-<px>`), and arbitrary values where the design
  uses a one-off (`px-[22px]`, `gap-[13px]`, `[grid-template-columns:…]`). Never copy `sc-if`/`sc-for` or
  inline style strings; never "improve" spacing, colour or copy.
- There is no CSS preflight: the browser's defaults apply as in the prototype. A `<button>` keeps the UA
  font size (13.333px) unless the design sets one; set what the design sets. Borders need a colour and a
  width class (`border border-line`).
- Recurring control strings are in `components/ui/styles.ts` (`ui.card`, `ui.btnPrimary`, `ui.pill` …).
- A design button that navigates becomes a `<Link>` with the same classes (control substitution, logged).
- Compare with the design: `scripts/visual/design.mjs <route>` and `scripts/visual/shoot.mjs /<path>`, at
  1440 and 390. The design's route keys: home, customers, analytics, tickets, feed, leads, deals, contacts,
  activities, inbox, meetings, projects, documents, campaigns, leadgen, visitors, automation, insights,
  apps, platform, settings, security, mobile, coverage.
- Every state the design draws is reachable (tabs, drawers, modals, empty, warning), keyboard reachable,
  with the design's focus style (global `:focus-visible`).

## Language

- English is the default, bokmål available (`messages/en/<ns>.json`, `messages/no/<ns>.json`, one file per
  screen namespace, both registered in `lib/i18n/messages.ts`). `npm run verify:i18n` must pass.
- The English strings are the design's own copy, verbatim. Bokmål is a faithful translation.
- Data-driven labels (setting options, statuses, types) are keys rendered through messages.
- Numbers through `lib/format.ts` in the staff member's number format; dates through next-intl's
  formatter (locale en-GB / nb, the staff member's time zone).

## Gates for a screen

`npm run typecheck`, `npm run lint`, `npm test`, `npm run verify:i18n`, `npm run build`,
`node scripts/db/run-tests.mjs` on a database rebuilt with `npm run db:reset`, the screen shot at 1440
and 390 and compared with the design, no console errors.
