# Brief for a v3 builder

You build ONE area of Sentral v3 in your own git worktree. The lead (another session) has built the foundation (commit
d702fa9, `supabase/migrations/0078_v3_foundation.sql`) and merges your branch afterwards. Read, in order:
`CLAUDE.md`; `docs/crm-enrichment/v3/PLAN.md` (architecture, Tor's decisions X-V3-1..4, defaults — these are decided, do not
reopen them); your area's gap analysis in `docs/crm-enrichment/v3/` IN FULL (named in your task); `docs/crm-enrichment/
BUILD-GUIDE.md` (visual rules, no CSS preflight); your design file(s) in `design-reference/sentral-simple/` IN FULL (markup and
the `<script>` logic); `0078_v3_foundation.sql`; then the existing code your area reuses.

## Setting up the worktree
- `ln -s /home/user/Owntheagenda_Admin/node_modules node_modules` and `ln -s /home/user/Owntheagenda_Admin/.cache .cache`
  (both are git-ignored; never commit them).
- Dev server on YOUR port with YOUR build folder (never stop processes you did not start; never `pkill -f` a pattern):
  `NEXT_DIST_DIR=.next-<you> NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54421 NEXT_PUBLIC_SUPABASE_ANON_KEY=<the key in
  package.json's dev:local script> npx next dev -p <port>` in the background, output to a log file. Afterwards
  `git checkout tsconfig.json` (Next rewrites it).
- Screenshots of your screen: `node scripts/visual/shoot.mjs --base http://localhost:<port> --widths 1440,390 --out <dir> '/<route>?tab=…'`
  (signs in as tor@orgpuls.no; `--as hanna@orgpuls.no` Support, `ingrid@orgpuls.no` Sales, `jonas@orgpuls.no` Marketing,
  `sara@orgpuls.no` Read-only). The design: `node scripts/visual/design-simple.mjs --section <customers|crm|growth|platform|dev>
  --click "Tab>Sub tab" --out <file.png> [--width 390]`. Look at both with Read and compare; fix what differs.

## Rules
- Commit on your branch in your worktree; do not push, do not merge, do not touch `main`.
- Your files: the ones your task names. Never edit `components/shell/*`, `lib/nav.ts`, `lib/shell.ts`, `lib/rpc.ts`,
  `lib/i18n/messages.ts`, `tailwind.config.ts`, `app/globals.css`, `app/(admin)/layout.tsx`, `messages/*/common.json`,
  `messages/*/shell.json`, `0078`, or another builder's files. If you need a shared change, describe it in your final answer.
- Strings: only in your message file(s), under its top-level key (already registered). English is the design's own copy;
  Norwegian (bokmål) a faithful translation. Error texts for your own codes live in your namespace too. `npm run verify:i18n`.
- **Never fabricate data.** Every figure in the prototype is a literal or a random generator. Every figure you render comes
  from the database or is «—» / the design's empty treatment. A control whose effect does not exist yet (no Orgpuls command,
  no connection, a decision not made) is shown disabled with an honest one-line reason (`title` and visible text), never a
  toast that pretends it worked. Log each departure from the design in `docs/crm-enrichment/deviations/v3-<area>.md`
  (columns: ID | Where | Design | Built | Why; IDs V-V3<X>-NN with your letter).
- Security (CLAUDE.md rules 1–7): every table in `app`, RLS on, no policy, no grant, in the same migration; every reader and
  writer a SECURITY DEFINER function in `public` with `search_path = ''` that calls `app.require(scope, action)` (or
  `app.require_any`), revoked from public/anon, granted to authenticated; workers granted to service_role only; a function
  that writes is volatile; every UPDATE and DELETE has a WHERE clause (the hosted project refuses one without); audit
  actions match `^[a-z_]+\.[a-z_]+$` (no digits). Owner-only actions: `app.require_owner()`; dangerous ones also
  `app.require_fresh_mfa(10)`. No respondent data; logs and audit carry ids, kinds, counts and codes, never a payload or a
  person's words. Secrets only through secret-intake (0078's `v3_intake`, `lib/secrets/hand-over.ts`); never print one.
- Claude (X-V3-2): only through `ai-run` (`lib/ai/run.ts`). To add a feature, register a row in `app.ai_features` and write
  `app.ai_ctx_<key>(p_subject uuid) returns jsonb {system, prompt}` that reads ONLY Sentral's own records (never ticket
  messages or anything a customer wrote, never survey data). The drafts come back through `ai_outputs_get`; a person
  accepts a draft before it becomes anything (`ai_output_set`). Without a key, the button is disabled with a reason.
- zod at every boundary: every RPC through `rpc()`/`rpcOrThrow()` with a schema; server actions parse their input and return
  `{ ok: true } | { ok: false, code }`. Rights: hide or disable what the person may not do (`can(shell, scope, action)`);
  the database refuses anyway.
- Migrations: only your number, `supabase/migrations/00NN_<name>.sql`, never editing another. Prove it in a rolled-back
  session first (`(echo begin; cat file; echo rollback) | psql -v ON_ERROR_STOP=1 …`), then apply it once to the SHARED local
  database with `psql -v ON_ERROR_STOP=1 -1 -f <file>` and `insert into supabase_migrations.schema_migrations (version, name)
  values ('00NN', '<name>')`. If you must change it after applying, write `create or replace` statements and apply those —
  never reset, stop, truncate or restart anything shared. Database: postgresql://postgres:postgres@127.0.0.1:54422/postgres.
  It holds the seed plus the visual sample (scripts/visual/growth-sample.sql); with the sample loaded, phase4,
  search_console, seo_site_health and simple_growth suites fail by design — the lead runs every suite on a rebuilt database.
- Tests: a SQL suite `supabase/tests/v3_<area>_invariants.sql` (pattern: `v3_foundation_invariants.sql`; everything inside
  begin … rollback) that proves every new function's rights, refusals and effects; `node scripts/db/run-tests.mjs <file>`
  must pass, and so must `structure_invariants.sql`. Unit tests for pure logic in `tests/v3-<area>.test.ts`.
- Edge functions: put them in `supabase/functions/<name>/index.ts` (shared helpers in `_shared/`), add them to
  `scripts/functions.mjs` FUNCTIONS (and SHARED), and keep `npm run functions:check` green. The lead deploys; you do not.
- Visual fidelity: recreate the design's rendering exactly in Tailwind with the tokens in `tailwind.config.ts` (the design's
  hex values are tokens; radius scale 8/10/12/14/16/18/20/999). Pills, cards (radius 20, border line), KPI tiles (radius 18),
  the toast. Check 1440 and 390 px: no horizontal page scroll; tables that cannot fit get their own scroll wrapper.
  Keyboard and focus-visible work; a drag-and-drop has a keyboard alternative.
- Gates before you finish (read the exit codes): `npx tsc --noEmit`, `npm run lint` (no warnings), `npm run verify:i18n`,
  `npx vitest run`, `npm run functions:check` if you touched functions, your SQL suite and structure_invariants. Do not run
  `next build`.
- Commit message ends with the two lines:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Lg8nDoGoE8pN6XLqe7pbas`
- Before you finish, review your own diff adversarially against this brief (security, fabricated values, missing rights
  checks, missing WHERE, strings outside messages, missing deviations) and fix what you find.

## Final answer
Your branch name and last commit sha; what you built per tab/view; what is disabled or empty and why (deviation IDs); your
migration's functions and tables; edge functions; gate exit codes and SQL check counts; anything in shared code you need
the lead to change.
