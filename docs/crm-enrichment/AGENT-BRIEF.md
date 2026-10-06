# Brief for a screen build (phase B)

You build one screen area of the Sentral platform admin, in your own git worktree. Read, in this order:
`CLAUDE.md`, `docs/crm-enrichment/BUILD-GUIDE.md`, `docs/crm-enrichment/DEVIATIONS.md`, `docs/crm-enrichment/DECISIONS.md`
(skim), then the design file(s) for your screen in full, then the migrations your screen reads
(`supabase/migrations/0006`, `0009`–`0014` as named in your task). Then look at how the Overview is built:
`app/(admin)/page.tsx`, `lib/data/overview.ts`, `components/ui/styles.ts`, `components/ui/Toast.tsx`,
`components/ui/Switch.tsx`, `lib/format.ts`, `lib/rpc.ts`, `lib/records-href.ts`.

## Rules of the build
- Work only inside your worktree directory. Commit on your branch. Do not push. Do not merge.
- The database is shared with five other builders and is already migrated and seeded. Never run
  `supabase db reset`, `supabase stop`, never write to tables by SQL. Read it through the app or the RPCs.
- Do not write or apply migrations. If your screen needs a database change, leave the feature out (the
  design's empty treatment, or a disabled control with an honest message key) and describe the change in
  `docs/crm-enrichment/requests/<your-screen>.md` (create it). The lead builder adds it.
- Do not edit shared files: `components/shell/*`, `lib/*` (except new files under `lib/data/<your-screen>*.ts`),
  `components/ui/*` existing files, `tailwind.config.ts`, `app/globals.css`, `app/(admin)/layout.tsx`,
  `app/(admin)/page.tsx`, other screens' folders, `lib/i18n/messages.ts`, `supabase/*`, `scripts/*`.
  Put your components in your route folder (`app/(admin)/<route>/_components/…`), your loaders in
  `lib/data/<screen>.ts`, your server actions in `app/(admin)/<route>/actions.ts`.
- Your message namespace files already exist and are registered: `messages/en/<ns>.json` and
  `messages/no/<ns>.json` — put every string there under the top-level key `<ns>`. The English text is
  the design's own copy; bokmål a faithful translation. `npm run verify:i18n` must pass.
- Never fabricate data (see BUILD-GUIDE). The design computes many values from a random generator: where
  the database has no source, render «—», nothing, or the empty treatment, and add a row to
  `docs/crm-enrichment/deviations/<your-screen>.md` (create it; same columns as DEVIATIONS.md, IDs
  V-<SCREEN>-01 …). The lead builder folds them into DEVIATIONS.md.
- Every RPC call goes through `rpc()`/`rpcOrThrow()` with a zod schema; every server action parses its
  input with zod and returns `{ ok: true } | { ok: false, code }`; errors are shown with
  `common.errors.<code>` messages. Rights: hide or disable controls the staff member may not use
  (`getShell()` → `can(shell, scope, action)` from `lib/shell.ts`), the database refuses anyway.
- Visual fidelity: recreate the design's markup in Tailwind exactly (see BUILD-GUIDE «Visual»). There is
  no CSS preflight. Compare your screen with the design at 1440 and 390 px and fix differences you find.

## Running it
- Start your own dev server on your port (never stop processes you did not start; never use `pkill -f`):
  `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54421 NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0 npx next dev -p <port>`
  in the background (redirect output to a log file in your worktree).
- Screenshots of your screen: `node scripts/visual/shoot.mjs --base http://localhost:<port> --out screens/current /<route>`
  (signs in as tor@orgpuls.no; `--as ingrid@orgpuls.no` for a sales user, `ola@orgpuls.no` read-only).
  The design: `node scripts/visual/design.mjs --out screens/design <routeKey>`. Look at both images.
- Gates before you finish: `npx tsc --noEmit`, `npm run lint`, `npm run verify:i18n`, `npm test`. Do not run
  `next build` (disk is limited); the lead builder builds after merging.
- Commit when done with a clear message ending with the two attribution lines:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01U8NqjgPf4GAveNTnTAzZjT`.

## Your final answer
A short report: what you built (tabs/states), what you left out and why (with the deviation IDs), the
database requests you filed, gate results (exit codes), and any problem in the shared code you noticed.
