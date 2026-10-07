# Brief for a Sentral Simple section build

You build ONE section of Sentral Simple in your own git worktree. Read, in order: `CLAUDE.md`, `docs/crm-enrichment/SIMPLE-PLAN.md`,
`docs/crm-enrichment/BUILD-GUIDE.md` (visual rules, no preflight), then your section's design file(s) in
`design-reference/sentral-simple/` IN FULL (markup and the logic in the `<script>`), then the existing code your section reuses.
The shell is already built (`components/shell/*`, `lib/nav.ts` SECTIONS/ACCESS, `lib/product.ts` `currentProduct(shell)`,
`app/(admin)/layout.tsx`). Look at it first; do not change it except where your brief says so.

## Rules
- Work only in your worktree; commit on your branch; do not push, do not merge.
- Your route is `app/(admin)/<section>/page.tsx` with `?tab=`; components in `app/(admin)/<section>/_components/`; actions in
  `app/(admin)/<section>/actions.ts`; loaders in `lib/data/simple-<section>.ts`. Reuse existing loaders, actions, RPCs and
  components (named in your brief) — import them, do not copy-paste them. Do not edit other sections' folders.
- Strings: `messages/en/simple-<section>.json` and `messages/no/simple-<section>.json`, top-level key `simple<Section>`
  (already registered). English is the design's own copy; Norwegian a faithful translation. `npm run verify:i18n` must pass.
- Recreate the design's rendering exactly in Tailwind (tokens in `tailwind.config.ts`; the design's hex values are tokens).
  Pills, cards (radius 20, border line), KPI tiles (radius 18), selects, the toast. Check 1440 and 390 px.
- **Never fabricate data.** The prototype hard-codes figures (e.g. «Trial → paid 31 %», «Median first reply 2 h», +312 000
  «won», +6/+2 counts, SEO positions, site-health issues, flag names, `sk_live_…`). Every figure comes from the database or
  is «—» / the honest empty state. A control whose effect does not exist yet (no Orgpuls command, no provider) is shown
  disabled with an honest one-line reason, never a toast that pretends it worked. Log each such departure in
  `docs/crm-enrichment/deviations/simple-<section>.md` (columns: ID V-S<X>-NN | Where | Design | Built | Why).
- zod at every boundary; every RPC through `rpc()`/`rpcOrThrow()` with a schema; server actions parse input and return
  `{ok:true}|{ok:false, code}`; errors via `common.errors.<code>`. Rights: hide/disable what the person may not do
  (`can(shell, scope, action)`); the database refuses anyway.
- Migrations: only the number given in your brief, in `supabase/migrations/`. SECURITY DEFINER public functions with
  `search_path=''`, rights checks, revoke from public/anon, grant to authenticated; a function that writes is volatile;
  never edit an applied migration (create or replace). SQL assertions for every new function in the relevant suite in
  `supabase/tests/` inside its begin…rollback.
- Database: the local stack is shared (postgres://postgres:postgres@127.0.0.1:54422/postgres; API http://127.0.0.1:54421).
  Never run supabase db reset/stop/start, never truncate, never restart Docker. If it is down, wait a minute and retry;
  report if it stays down. Prove your migration in a rolled-back session first; then you MAY apply it once with
  `psql -v ON_ERROR_STOP=1 -1 -f <file>` and insert its version into supabase_migrations.schema_migrations; then
  `node scripts/db/run-tests.mjs` must pass.
- Dev server: `NEXT_DIST_DIR=.next-<you>` + the env in AGENT-BRIEF.md on your port; stop only your own processes (exact
  PID, or your NEXT_DIST_DIR in /proc/<pid>/environ — never `pkill -f` a pattern that also matches your own shell);
  `git checkout tsconfig.json` afterwards. Screenshots: `node scripts/visual/shoot.mjs --base http://localhost:<port> --out
  <dir> /<section>?tab=...` (also `--as ingrid@orgpuls.no` sales, `hanna@orgpuls.no` support, `jonas@orgpuls.no`
  marketing, `ola@orgpuls.no` read-only). Look at every image and compare with the design.
- Gates: `npx tsc --noEmit`, `npm run lint`, `npm run verify:i18n`, `npx vitest run` (no failed files or tests). Do not run
  next build.
- Commit message ends with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01U8NqjgPf4GAveNTnTAzZjT

## Final answer
What you built per tab, what is disabled or empty and why (deviation IDs), migration functions, gate exit codes, and any
problem in shared code you noticed.
