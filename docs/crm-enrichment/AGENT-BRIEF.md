# Brief for a screen build (phase B)

You build one screen area of the Sentral platform admin, in your own git worktree. Read, in this order:
`CLAUDE.md`, `docs/crm-enrichment/BUILD-GUIDE.md`, `docs/crm-enrichment/DEVIATIONS.md`, `docs/crm-enrichment/DECISIONS.md`
(skim), then the design file(s) for your screen in full, then the migrations your screen reads
(`supabase/migrations/0006`, `0009`–`0014`, and for phase 2 `0020`–`0023`, as named in your task). Then look at how the Overview is built:
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

## Phase 2 screens (Inbox, Feed, Automation)
- Your data spec is `docs/crm-enrichment/specs/inbox-feed-automation.md`: it names every value the design
  invents (FAB) and the real source for it. Read it before the design file.
- The functions are in `0020_mail.sql`, `0021_engine.sql`, `0022_feed_scoring.sql` and are proved by
  `supabase/tests/phase2_invariants.sql` — read the test to see how each is called.
- No provider is connected and no edge worker runs locally: the seeded mailboxes are «disconnected»
  (history only), sending is refused with `mailbox_not_connected`, AI is not configured, Slack/Teams/
  accounting/telephony/WhatsApp/contact data are not connected. Every such view shows its honest
  unconnected state in the design's language (D-41), never sample output.
- The seed holds the design's four mail threads and ten templates, the eight workflows, five assignment
  rules and three sequences as configuration (no runs), three scoring models with scores computed, and
  feed cards computed by `app.feed_checks()`.
- Deviations: `docs/crm-enrichment/deviations/<screen>.md` as before; the lead folds them in.

## Phase 4 screens (Insights, Analytics)
- Your data spec is `docs/crm-enrichment/specs/insights-analytics.md`. It marks every figure the prototype
  fabricates and gives the real formula. Read it before the design file.
- The functions are in `0024_insights.sql` (report_run/drill/export, reports, dashboards with four role
  templates, goals, forecasts) and `0025_analytics.sql` (analytics_business/activation/retention/usage/web/
  attribution/health, health_model_save, churn reasons, metric definitions, set_spend). They are proved by
  `supabase/tests/phase4_invariants.sql`; read the test to see how each is called and what it returns.
- Every analytics read takes a period. The prototype's range selector changes nothing; yours must.
- What has no source shows the honest empty state (D-41), never a number. Examples: web traffic before the
  tracker runs, Search Console before it is connected, marketing spend nobody has entered, a goal with no
  matching records. Money is NOK only; rows in other currencies are reported as `excluded_currency`, so say so.
- The public dashboard link waits for go.owntheagenda.com (D-28). PNG/PDF export needs a renderer that
  does not exist yet. Show those controls in their unavailable state and log a deviation.
- Deviations: `docs/crm-enrichment/deviations/<screen>.md` as before; the lead folds them in.

## Phase 5 screens (Lead capture and Web visitors, Documents)
- Your data spec is `docs/crm-enrichment/specs/marketing-documents.md` (§1 for Lead capture and Web visitors,
  §2 for Documents). It marks every figure the prototype invents. Read it before the design file
  (`Marketing.dc.html`: routes `leadgen` → `/lead-capture`, `visitors` → `/web-visitors`; `Documents.dc.html`).
  The Campaigns tab waits for phase 6 and keeps its Pending page.
- The functions are in `0031_capture.sql` and `0032_documents.sql`, proved by
  `supabase/tests/phase5_capture_invariants.sql` and `phase5_documents_invariants.sql`; read the tests to see
  how each is called. The schema's own departures are logged as V-P5-* in DEVIATIONS.md.
- Nothing public runs yet: go.owntheagenda.com (D-28), the email provider, IP-to-company, contact data,
  drives, e-signature and the PDF worker are not connected. Embed snippets, form links and document links are
  shown as what they will be, with the honest not-connected state where an action needs a provider (D-41).
- Seed: the design's fixtures for your screen go in your own module (`scripts/seed/phase5-capture.mjs` or
  `phase5-documents.mjs`) called from `scripts/seed/generate.mjs` with one line. Never seed an employee-list
  form (spec Q8) or copy claiming k = 5 (spec Q18). Regenerate `supabase/seed.sql`; do not reset the database
  (the lead does that after merging).
- Deviations: `docs/crm-enrichment/deviations/<screen>.md` as before; the lead folds them in.

## Phase 6 screens (Campaigns, Projects)
- Campaigns: `Marketing.dc.html`, route `campaigns` → `/campaigns` with its tabs Campaigns, Email builder, Audience
  and consent, Deliverability (`?tab=builder|audience|deliverability`, the links Lead capture already uses). Data spec
  `docs/crm-enrichment/specs/marketing-documents.md` §1 (those four tabs), §3, §10. Functions in
  `0037_campaigns.sql`; their contract (RPC signatures, return shapes, enums, error details) is
  `docs/crm-enrichment/deviations/campaigns-schema.md` — read it first; the suite is `phase6_campaigns_invariants.sql`.
  The pill row is the one in `app/(admin)/lead-capture/_components/CaptureTabs.tsx` (reuse the same visual; you may
  import it, not edit it). The email renderer is TypeScript (V-P6C-01): `campaign_schedule` receives the rendered HTML,
  which must carry `[Unsubscribe]` and the sender domain's postal address — build the renderer in `lib/data/campaigns-render.ts`.
- Projects: `Projects.dc.html`, route `projects` → `/projects`. Data spec `docs/crm-enrichment/specs/projects-meetings.md`
  §1 (Meetings is phase 7). Functions in `0038_projects.sql` (+ `0039` engine wiring); contract in
  `docs/crm-enrichment/deviations/projects-schema.md`; suite `phase6_projects_invariants.sql`.
- Not connected: the email provider (sending, test sends), DNS checks, the AI provider (summaries, briefs, report
  drafts), storage signers (file upload/download), the PDF worker. Show the honest not-connected state (D-41).
- Notification texts for `campaign.*` and `project.*` already exist in `shell.json`. Namespaces `campaigns` and
  `projects` are registered (empty files).
- Seed: the design's fixtures in your own module (`scripts/seed/phase6-campaigns.mjs` or `phase6-projects.mjs`), called
  from `scripts/seed/generate.mjs` with one line, rows that pass the schema's triggers (check them in a rolled-back
  `psql` session: `begin; … rollback;`). Regenerate `supabase/seed.sql`; never reset or write to the shared database.
- Deviations: `docs/crm-enrichment/deviations/<screen>.md`; requests: `docs/crm-enrichment/requests/<screen>.md`.
