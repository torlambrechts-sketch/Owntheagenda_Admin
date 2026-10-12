# CRM-enrichment documents digest for the v3 design (part 2: gap analyses, questions, decisions, plans, deviations)

Evaluator: documents, part 2. Date: 12 Oct 2026. Evaluation only: no code, migration or other document was changed.
Part 1 (`docs-instructions-digest.md`) covers `INSTRUCTIONS.md`; this file covers everything the team wrote *after* it.

## Overview

### What was read, in full
| File | Size | Lines | How |
|---|---|---|---|
| `05-GAP-FEATURES.md` | 211 399 B | 1 362 | 11 sequential chunks, every line |
| `04-GAP-ADMIN-SPEC.md` | 17 324 B | 258 | whole |
| `06-QUESTIONS.md` | 14 475 B | 271 | whole |
| `DECISIONS.md` | 7 526 B | 51 | whole |
| `07-IMPLEMENTATION-PLAN.md` | 8 587 B | 99 | whole |
| `SIMPLE-PLAN.md` | 5 257 B | 69 | whole |
| `DEVIATIONS.md` | 227 075 B | 873 | 10 sequential chunks, every line |
| `deviations/campaigns-schema.md`, `growth-v2.md`, `meetings-schema.md`, `platform-schema.md`, `projects-schema.md`, `security-schema.md`, `simple-crm.md`, `simple-customers.md`, `simple-growth.md`, `simple-platform.md` | 184 155 B | 1 101 | each whole |

Also read, because the deviations point at them for the status of what was asked: `growth-v2-gap.md` (whole),
`requests/STATUS.md`, `requests/customers.md`, `tickets.md`, `platform.md`, `analytics.md`, `settings.md`, `security.md`,
`campaigns.md`, `automation.md` (all whole). From the specs I read only the sections these areas touch:
`specs/tickets-settings-coverage.md` §1 (tickets, help centre, CSAT, banner), `specs/platform-security-mobile.md` §1.6–§1.8, §4–§6
(jobs, flags, maintenance, content, conflicts, open questions) and `specs/customers-contacts.md` A3 (NPS, counts). To say what
exists today I grepped `supabase/migrations/0001…0077`, listed `supabase/functions/`, and ran read-only `SELECT`s against the local
database (`app.product_event_kinds`, `app.product_commands`, `app.help_articles`, `app.help_article_stats_daily`,
`app.plan_versions`, `app.modules`, `app.permission_sets`, `app.integration_connections`, `app.ticket_categories`).

### What these documents are, and what they say about the v3 areas
- **05 and 04** are the Phase A gap analyses of 6 Oct (repo at `8c01aec`, when only 0001–0002 existed). Their «Missing» status is
  historic; their value now is the *requirement* text per item and the dependency they name. 06 is the question list, DECISIONS
  holds Tor's answers (D-01–D-42, all «follow the recommendations», 6 Oct), 07 is the Phase B plan, SIMPLE-PLAN is the 7 Oct plan
  for the four-section Simple interface. DEVIATIONS and `deviations/*` record every place the build departed from a design and
  why, up to Growth v2 (0077, 11–12 Oct).
- **Development is not in any of them.** No roadmap, release, product changelog, vote, environment, delivery metric, spec
  sign-off, Claude job or release gate is a feature in 04/05/06/07. What the documents *do* hold that a Development section stands
  on: ticket categories `bug` and `feature_request` and the problem / known-error model (04 Ticketing; built in 0012), the Spec
  coverage screen (V-COVERAGE-01…06, a static copy of the 6 Oct gap status, «not live progress»), the job monitor
  (V-PLATFORM-15, V-P8P-09), `firewall_status` with an empty `ci` field (V-P8S-25: «nothing records a CI result yet»), the hosted
  deployment state of edge functions (V-JOBS-10, V-STORAGE-01: `jobs-run` and `storage-sign` not deployed), and Q-01 / D-02 / D-03
  (Supabase access, a dev project, Playwright and SQL suites).
- **Support** is covered in depth: Appendix 2 Ticketing (25 rows) and Communication and support in 04, D-20 (intake), the
  tickets build (V-TICKETS-01…23, R-1…R-7), the Simple customers build (V-SCU-01…24), mail (V-MAIL-01…15), support access
  (V-CUSTOMERS-23, R-CUSTOMERS-06) and the status banner (V-TICKETS-14, Tickets R-4, V-P8P-17, V-SPL-06).
- **Platform** is covered by 04 (System operations, Billing, Users and support access), ENT-01…04 and SEC-07 in 05, D-08, D-17,
  D-22, D-23, D-30, D-40, the Phase 8 build (V-PLATFORM-*, V-P8P-*) and Simple platform (V-SPL-01…18).
- **Growth** is covered by CMP-01…09 and AUT-12 in 05, the campaigns schema (V-P6C-*), Simple growth (V-SGR-*), Growth v2
  (V-GR2-01…46). The decisive v3 fact is in 0077 and V-GR2-42…46: the ad platforms are connected **read only**, by decision.

### Facts from the documents that the v3 design contradicts
1. **Ads are read only.** 0077's header: «Sentral never changes a campaign, a bid or an audience on a platform»; V-GR2-42:
   «pausing, budgets, audiences and conversions stay in the platform»; V-GR2-45: uploading contacts to an ad platform «is a decision
   about personal data nobody has made». The design's «Raise bid», «Pause keyword», «Move budget», «Add exclusion», «Limit
   audience» toast «applied via <platform> API».
2. **No keyword data is imported.** `app.ad_daily.level` is `campaign | ad` only (0077); no keyword or search-term level exists.
3. **Automated campaigns have no A/B test** (V-P6C-11), and the engine has **no send-time, frequency cap, quiet hours or priority**
   (V-GR2-41: «settings the engine would not enforce would change nothing»). The design offers «Create A/B test» and «Use best time».
4. **Stripe waits** (D-22, R-CUSTOMERS-04, V-CUSTOMERS-14/16/17/19). The Billing portal shows card payment, invoices, dunning and
   refunds.
5. **Public pages live on `go.owntheagenda.com`** (D-28), which does not run (V-INSIGHTS-19, V-CAPTURE-12, V-DOCUMENTS-09);
   unsubscribe was moved to Sentral's own host and `post.<domain>` hosts instead (V-MAIL-07, V-MAIL-14). The design names
   `status.orgpuls.no`, a public help centre with SEO, a customer portal and a public changelog.
6. **The «status message» reaches the public site only.** V-SPL-06 delivers Sentral's status message with Orgpuls'
   `settings.set_notice`; the platform evaluator found that command sets Orgpuls' *site notice*, never the signed-in product
   (`platform-gap.md`, finding F-1). Tickets R-4 (an in-app banner command) is still open. The design's «Announcement in the app»
   and the incident banner need a command that does not exist.
7. **Rollouts are not percentages.** Spec §1.7: «"Staged rollout 35 %" exists only if the product's command reports a
   percentage, otherwise the bar is omitted»; V-SPL-04: Orgpuls moves a module draft → published → retired, one way.
8. **Secrets are never shown or relayed** (V-SPL-05, V-PLATFORM-07, V-MAIL-01). Any token the Development section needs (GitHub,
   Vercel, Supabase Management, Sentry, Claude) goes through `secret-intake` into Vault. CLAUDE.md adds that the Management API token
   in cloud sessions belongs to Orgpuls and answers 403 here.
9. **The approvals queue was promised and never built.** 0011's header: a merge or bulk delete with `second_admin` on «is refused
   with approval_required until the approvals queue exists (phase 8)»; only privacy erasure has a two-person path
   (`privacy_approve`, V-P8S-23). The design's «Waiting for approval» is that missing queue.
10. **The four other products are names only.** Skiftly, Avvikspunkt and Kursrom have no command path (V-PLATFORM-05:
    «another product answers "no command path"»), so every design row about them is «cannot» until they exist.

### Verdict vocabulary
**build** (on today's backend or with a new migration here) · **build+connector** (real once an external read with credentials
in Vault exists; named) · **needs-orgpuls** (an Orgpuls command or event that does not exist; named) · **needs-decision** (Tor
decides; named) · **cannot** (fabricated by nature or forbidden; the honest rendering is named). «Today» cites the migration,
function or deviation that already serves the element.

## 0. Cross-cutting decisions and deviations that bind every v3 tab

| ID | Rule | Bearing on v3 |
|---|---|---|
| D-01 | Everything is built new in the platform; «already exists in the admin» means «to build» | Support, Platform and Growth extend Sentral's own tables; no other system is a source |
| D-04 | English default, bokmål available, per staff member | Every new string in `messages/en` and `messages/no` |
| D-05 | Job runtime: pg_cron + pgmq, edge functions as workers | Connector imports (GitHub, Vercel, Sentry) run as cron → edge function, like `search-console-run` and `ads-run` |
| D-07 | Providers per phase; Claude is the LLM; one email provider (now Brevo, V-MAIL-01…15) | AI assist, widget answers and Claude jobs use Claude; email notices use Brevo |
| D-08, 0057 | Roles are permission sets; five offered (Admin, Sales, Support, Marketing, Read-only), finance and project kept but not offered (V-SPL-11) | Roles and approvals tab; a Development right needs a scope or a rule (no `dev` scope exists; scopes are deals, projects, campaigns, tickets, global — V-SETTINGS-22) |
| D-09 | Visibility enforced inside security-definer functions; RLS on, no policy, no grant | Every new table |
| D-11 | MFA always on, TOTP only | Deploy, roll back, commit, approve: fresh second factor (`app.require_fresh_mfa`, V-P8S-30) |
| D-12 | Audit every write and every read of customer data; typed reason is a setting | Approvals, deploys, sign-offs, portal actions all audited; no values in the audit |
| D-16 | Every rule defaults to unrestricted; the source number is only a reference | Approval policies, plan limits and send-time default off |
| D-17 | ENT means Sentral's own module switches and counters; nothing is sold | Platform «plan limits» are Orgpuls customers' bands (`plan_versions`), not Sentral's ENT |
| D-19, D-34 | No survey figures; tests prove no response-level table or respondent field exists | No help, AI or status feature may pull answers, groups or comments |
| D-20 | `support.requested` → ticket; `contact.submitted` → ticket and lead; `demo.requested` → lead | Built (0031 `app.ticket_intake`, 0056 structured request). Contact form is real |
| D-21 | Orgpuls adds count-only events (survey scheduled/sent, result unlocked, results viewed, tiltak created, logins by role) | Sentral's registry already expects `survey.round`, `counts.updated`, `milestone.reached`, `member.state`, `logins.daily` (local `app.product_event_kinds`); Orgpuls has not added them (`platform-gap.md`) |
| D-22 | Price, currency and seats on `billing.changed`; Stripe waits | Billing portal, refunds, dunning blocked |
| D-23 | Product content stays in Orgpuls; the platform uses the existing commands | Rollouts and content go through `modules.*`, `locales.*`, `legal.*`, `translations.*` |
| D-27 | Unsubscribe link, sender identity, no mail to unsubscribed people, no send from an unauthenticated domain are fixed; a legal review precedes go-live | Every customer email (CSAT, status subscribers, announcements by email, NPS invitations) |
| D-28 | Public pages on `go.owntheagenda.com`, unguessable revocable tokens | Status page, help centre, portal, CSAT link, public changelog |
| D-30 | Destructive product commands: preview always, org.nr typed to delete, second admin a setting (off) | Approvals queue; deploy / roll back in Development |
| D-37 | Tracker on marketing sites only; IP never stored; cookieless | Help-widget session analytics follow the same rule; the widget never loads in a survey (V-SETTINGS-37 `survey_flow_block`, fixed) |
| D-40 | Integration details the design shows are targets; Orgpuls commands and events are added when a feature needs them | Every «needs-orgpuls» below |
| D-41 | Gaps in the design are built in the design's language | Missing controls (create, edit, empty states) |
| Never fabricate (CLAUDE.md; V-03, V-07, V-10 …) | A value without a source is «—», an empty treatment or a disabled control with a reason | Every literal in the v3 scripts |

---

## 1. Development (DevHub, DevClaude; repo-starter)

What the documents say: nothing names this section. They settle the *process* it would show (gates, CI, migrations through
`supabase/migrations/`, edge functions deployed with `verify_jwt: false`, DB first then code, no destructive migration
statements), and they record that several workers are written but **not deployed** hosted (V-JOBS-10, V-STORAGE-01, V-STORAGE-07,
`STATUS.md`: «the function is not deployed»). The two Sentral objects a Development section can start from are tickets of category
`bug` / `feature_request` (0012 seed: `('bug', 'Bug', 'support', 70)`, `('feature_request', 'Feature request', 'support', 90)`) and
problems (V-TICKETS-14).

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Fifth rail section «Development · Roadmap, bugs, releases» | Shell entry, 13 tab pills | Route, rights rule | Shell with four sections (SIMPLE-PLAN, V-SS-01…05); menu shows an item only to someone with a right that opens it (V-NAV-01) | build | A right: no scope fits (V-SETTINGS-22 has deals, projects, campaigns, tickets, global). Tor: who sees Development (owner only, `global:configure`, or a new `dev` scope) |
| Tab pills (Roadmap … Repo rules) | Buttons in local state | `?tab=` | Pattern V-01 / V-SGR-01 / V-GR2-01 (links with addresses) | build | — |
| Roadmap lanes, product filter, ←/→ | Moves cards between lanes | `roadmap_items` (product, lane, ord, title, evidence) | Nothing | build | New table; products limited to `app.products` rows with an installation (V-PLATFORM-02) |
| «Added to Later with its evidence» | Promotes a request to the roadmap | Link roadmap item ↔ tickets of category `feature_request` / `bug` | Tickets with those categories (0012), `ticket_links` (0012/0023) | build | A link kind `roadmap` in `ticket_links` or a join table |
| Votes / «MRR asking» on an item | Numbers per item | Count of distinct accounts behind linked tickets; their MRR | `app.sub_mrr` / `customers_get` MRR (V-SCU-01), tickets per organisation | build | Counted from linked requests only; MRR NOK only (Analytics R-1) |
| Votes cast inside the product | Implied by vote counts | A vote event per customer user | No event kind | needs-orgpuls | A count-only `feature.voted` event (no free text, V-P5-02) or none: votes stay «requests linked» |
| Work board, «Task created on the work board» | Tasks in columns | `dev_tasks` (or GitHub issues) | Nothing; `projects` tasks exist but are customer delivery (0038) | build | Sentral table now; GitHub issue sync is a connector (see Markdown roadmap) |
| Bug triage list and KPIs | Open bugs, severity, age | Tickets `category = bug` with priority (impact × urgency), problems | `tickets_get`, `ticket_reports` (0012/0023), priority generated (V-SCU-09) | build | — |
| «Mark fixed», «Merge duplicate» | Toasts | Resolve the problem and notify linked incidents; merge tickets | `problem_resolve` sends the reply on each incident (V-TICKETS-14); ticket merge «not in the design … build only if wanted (D-41)» (tickets spec §1.3) | build | A `ticket_merge` with changelog source `merge` |
| Error count / affected customers per bug | Figures beside bugs | Error events per release and organisation | Appendix 2 «Errors link»: Miss (04 System operations); `integration_calls` only measure Sentral ↔ product (V-PLATFORM-03) | build+connector | Sentry (or the product's own error counts, count-only); token via `secret-intake` |
| Releases list and «Generated changelog» | Changelog from merged work | Merged PRs / commits per release tag | Nothing | build+connector | GitHub (read) |
| Ship: «Released · changelog published · rollout started at 5 %» | One click ships, publishes and starts a rollout | Release record; product flag with a percentage | Modules move draft → published → retired, one way (V-SPL-04); no percentage (spec §1.7) | needs-orgpuls | A staged-rollout command with a percentage (`flags.set_rollout` or similar) — Orgpuls has none |
| Public changelog | «changelog published» | A public page | No public host runs (D-28, V-INSIGHTS-19) | needs-decision | Where it is served (`go.owntheagenda.com`, a `post.`-style host V-MAIL-14, or Orgpuls' own site) |
| Integrations register | List of integrations and their state | `integration_connections`, `integration_catalog`, installations | Built: Applications (V-PLATFORM-02…06), catalog (V-P8P-14…16), Growth › Integrations (V-GR2-20) | build | A read over what exists; GA4, Stripe, Slack etc. are «not built» (V-GR2-20) |
| Code and environments: open PRs, deploys per environment | Lists and badges | PRs, deployments | Nothing | build+connector | GitHub + Vercel (read) |
| Security, dependencies and migrations | Alerts, outdated packages, pending migrations | Dependabot/code-scanning; migration list per environment | Hosted migrations go through the Supabase MCP (CLAUDE.md); no Sentral read | build+connector | GitHub; Supabase Management API with **Sentral's own** token (the cloud token is Orgpuls' and answers 403, CLAUDE.md) |
| Delivery metrics (DORA, cycle time, health) | Charts | Deploy frequency, lead time, change-failure, MTTR | Nothing; Part G performance targets «set from measurements» (D-39) | build+connector | GitHub + Vercel; every figure «—» until measured |
| Spec documents with sections and «Sign off» | Sign-off per section | Repo files (`docs/crm-enrichment/specs/*.md` exist, 8 files), sign-off rows | Decisions recorded with date in DECISIONS (R3); items awaiting Tor's confirmation (V-P7M-01, V-P7M-04) | build+connector | GitHub contents read; `spec_signoffs` (staff, section hash, at), audited |
| Markdown roadmap: feature files, status filter, «＋ New feature file», «Commit change» → «Committed to main · roadmap-sync updates the GitHub issue» | Writes to the repository | GitHub write | Nothing | needs-decision | Writing to `main` from the admin bypasses the gates (CLAUDE.md «Gates»: CI on every push) and the playbook (branch, then fast-forward). Tor: may Sentral commit, and to which branch |
| Claude jobs: start a job, outputs, «Quality of Claude's work · 30 days» | Starts an agent run, shows results | Claude API (or Claude Code sessions), job log | `ai_calls` log (0042) refuses any state but `not_connected` while `ai` is not connected (V-P7M-22); AI gateway not built (SF-24, V-05) | build+connector | Claude key via `secret-intake`; the quality figure is «—» until runs exist |
| «Ask Claude to fix» → «Claude opened a fix PR» | Agent writes code | GitHub write + Claude | Nothing | needs-decision | Agent authority over the repo (spec Q12's «human approval before any write» NFR applies) |
| «Nightly rules check» | A nightly check of repo rules | CI result | `firewall_status().ci` is null: «nothing records a CI result yet» (V-P8S-25); `structure_invariants`, `node scripts/audit/wiring.mjs` (Orgpuls) | build+connector | GitHub Actions read; a writer for `firewall_status.ci` |
| Vercel and Supabase panels | Project, region, functions, last deploy | Vercel API; Supabase Management | Real region is eu-central-1 (D-35, V-02); functions listed in repo, several not deployed (V-JOBS-10) | build+connector | Vercel + Supabase Management tokens in Vault |
| «Approve for prod», «Roll back», deploy that «runs migrations · flag at 5 %» | Production deploy from the admin | Vercel deploy API; migrations | Migrations only through committed files and the MCP (CLAUDE.md rule 7); production phase «stop and ask» list (Orgpuls CLAUDE.md) | needs-decision | Tor: may Sentral deploy and roll back production, with which guard (owner, fresh MFA, typed key as V-PLATFORM-07/V-P8P-17) |
| Release gate checks | Pass/fail per gate | The six gates (typecheck, lint, test, verify:i18n, functions:check, build) per commit | CI runs them (CLAUDE.md «Gates»); nothing reads them in Sentral | build+connector | GitHub Actions check runs |
| Release gate «Sign off» | Person signs a release | `release_signoffs` | Nothing | build | Audited, fresh MFA |
| Repo rules | The rules list | CLAUDE.md / repo-starter files | Files in the repo | build | Read at build time or via GitHub |
| Design literals: DORA numbers, quality %, votes, MRR asking, sample features for Skiftly/Avvikspunkt/Kursrom | Hard-coded | — | — | cannot | «—» or empty treatments; rows for products without a command path are not drawn (V-PLATFORM-05) |

**Decided, deferred or logged for Development:** nothing decided. Deferred: CI-result writer (V-P8S-25, Security left open 3);
deploying `jobs-run`, `storage-sign` (V-JOBS-10, V-STORAGE-01, `STATUS.md`). Logged: V-COVERAGE-02 (the coverage screen shows the
6 Oct analysis, not live progress) — the nearest thing to a spec tracker that exists.

---

## 2. Support (Customers › «Help centre and support»; SupportHub)

What the documents decided: D-20 (intake), D-27 (fixed email rules), D-28 (public host), D-40 (product commands). What was built:
tickets with queues, categories, SLA in business minutes, priority from impact × urgency, macros with versions, problems with
`status_banner`, help articles with daily stats, CSAT columns, personvern queue with 30-day clock, support access grants (0012,
0013, 0023, 0031, 0056), ticket replies by email through Brevo with reply threading (V-MAIL-06, V-MAIL-10).

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Customers third pill «Help centre and support» | New tab | `?tab=support` | Customers has two pills (V-SCU-19); the old Tickets tabs (problems, help centre, macros, reports) stay at `/tickets` (V-SS-04) | build | — |
| SupportHub sub-tabs (7) | Local state | `&sub=` | Pattern V-01 | build | — |
| Support results: volume, first reply, resolution, SLA | KPIs with deltas | `ticket_reports` (30 days, business time) | Built; previous period by product fixed (Tickets R-3); median first reply in Simple (V-SCU-02) | build | — |
| CSAT score and response rate | KPI | `tickets.csat_score`, `csat_requested_at`, `csat_at` | Columns and the average exist (R-6 done); **nothing writes `csat_requested_at` or `csat_token_hash`**, and the spec's anon `csat_submit` is not built | build | A CSAT request in the resolution email (mail-run, Brevo) and a one-click page on Sentral's host through an edge function (anon cannot call any platform function, V-P8S-13; pattern `/u/<token>`, V-MAIL-07) |
| Effort (CES) | KPI | An effort score per ticket | No column, no question | needs-decision | Tor: the question wording and when it is asked (with or instead of CSAT); then a column like `csat_score` |
| Self-service sessions, deflection, «Where help sessions end» | KPIs, split 41/30/9/20 | Widget sessions and outcomes | `help_article_stats_daily` (views, deflections) exists with **no writer** (only readers in 0012/0023); spec: «Views and deflections are P count-only events from the Orgpuls help widget (to be added per D-40)» | needs-orgpuls | Count-only widget events (`help.viewed`, `help.deflected`, session end kind) through `orgpuls-events` |
| AI acceptance | KPI | Accepted / shown AI answers | `ai` not connected (local `integration_connections`) | build+connector | Claude; logged in `ai_calls` |
| «Top questions without a good article» | Gaps list | Tickets per topic without a published article | Spec: «needs a topic or tag on tickets (N `tickets.topic`), or clustering» — not built; ticket-to-article rate exists (`help_get.article_rate`, R-5) | build | `tickets.topic` (staff-set or category-based); AI clustering only with the connector |
| Help widget inside the product | Embedded panel | The product renders it | Lives in Orgpuls (Appendix 2 «In-app help button»; 04 Ticketing Miss) | needs-orgpuls | Orgpuls embeds the widget and posts `support.requested` (exists) |
| Help widget on the public site | Embed snippet | A script, article search, ticket submit | No public host (D-28); the tracker's edge function shows the pattern (`web-collect`, V-WEB-01) | build | An edge function serving search and submit with an origin check; never on a survey host (`survey_flow_block`, V-SETTINGS-37). A public path needs a written reason (CLAUDE.md rule 2) |
| «Sent with every ticket from the widget» (user, org, role, page, browser, app version) | Captured context | `tickets.context` | Stored at intake when the product sends it; app version «—» otherwise (V-TICKETS-07, R-7) | needs-orgpuls | `support.requested` payload fields; never free text beyond the message (V-SCU-24 keeps only `days`, `plan`) |
| Widget article search | Suggests articles | Full-text over published articles | Spec: `to_tsvector('norwegian', …)`; widget preview in Tickets opens a new-ticket dialog (V-TICKETS-16) | build | Search RPC; public variant via the edge function |
| Widget AI answer | Answers by substring from a fixed list | Claude over published articles only | Not built | build+connector | Context = published articles; never tickets of other customers, never survey data (D-34, SF-24.2, UF-27 step 2) |
| Widget settings (colour, position, languages) | Form | `help_widget_settings` per product | Nothing | build | — |
| «Still need help? Send to support» | Creates a ticket from the widget | `ticket_create` with the query as subject | Built in Tickets › Help centre's widget preview (V-TICKETS-16); `ticket_create` takes the person (V-TICKETS-21) | build | From the public widget through the edge function; in the product it is `support.requested` (exists) |
| Help centre editor (articles, categories, languages, publish, versions) | Table and editor | `help_articles` | Built: slug, title, body, category, locale **nb/nn/en only**, status draft/published, version, `problem_id` (0012); publish via the problem toggle (V-TICKETS-14) | build | More locales is a decision (see Tor); version history is a counter, not rows |
| Articles by results (views, solved, helpful) | Table | Per-article counts | `help_get` returns 30-day views and deflections (zero, no writer, V-TICKETS-15) | needs-orgpuls | The same widget events; «helpful» needs a vote event |
| Public help centre with SEO | Public pages | Public host | None (D-28) | needs-decision | Host and indexing (Orgpuls' `settings.set_indexing` governs Orgpuls' site only) |
| «AI: improve from tickets», draft article from tickets | Appends a paragraph | Claude over ticket threads | Spec: «Draft article … creates a `help_articles` draft prefilled from the ticket cluster» | build+connector | Ticket text is the customer's own words: may be sent to the model, never logged (rule 6, V-P7M-22 refuses `prompt`) |
| Contact form `orgpuls.com/kontakt` → ticket and lead | Card | `contact.submitted` | Built (0031 `app.ticket_intake`: queue sales, channel `contact_form`, lead created; D-20). Orgpuls validates the form (honeypot, 3/hour per address, 60/hour; 05 SF-17.2) | build | — |
| Org.nr matching on the form | «matches» by digit | `accounts.org_number` (unique), Brønnøysund | Match by org.nr exists at ingest (0001 l.216, D-13); no Brønnøysund client (V-CUSTOMERS-27) | build | Match on `org_number`; Brønnøysund lookup only with its adapter (D-07) |
| Email threading of replies | Settings card | Reply domain, Brevo inbound | Built: Reply-To `support@<reply domain>`, an answer naming `[T-1234]` from the requester is threaded (V-MAIL-06); per-application sender (V-MAIL-10) | build | — |
| New mail to `support@` becomes a ticket | Implied by «Email» channel | Inbound parse → ticket | V-MAIL-06: «Anything else is dropped unread»; spec: «Inbound support@ / kontakt@ e-mail → ticket» | build | Extend `mail-events` to open a ticket for unknown threads from known or new people; spam handling |
| Channel shares | Bars | `tickets.channel` | Column exists (in_app, contact_form, email …); staff channel noted in spec | build | — |
| Customer portal «Kundeportal · Lumio AS» | Customer-facing tickets and approvals | Customer identity, public pages | Staff identities are separate from customer logins (05 Part F identity); every Sentral path needs a staff session with aal2 (CLAUDE.md rule 2) | needs-decision | Where the portal lives: inside Orgpuls (customer logins exist there) or on `go.owntheagenda.com` with magic links (D-28) |
| Portal: support access approval | Approve / deny | Grant state, expiry, page views | `support_access_grants` (0013) recorded by `access_request`; nothing delivers it (V-CUSTOMERS-23) | needs-orgpuls | `access.request` command; `access.approved` / `access.denied` / `access.page_view` events; an expiry job (R-CUSTOMERS-06); banner in the customer app (04) |
| Portal: deletion approvals | Approve | Deletion queue | `orgs.deletions` (read) exists; no projection (V-CUSTOMERS-24) | needs-orgpuls | An event or a read projection (R-CUSTOMERS-07) |
| Portal: band-change approvals | Approve | Plan change | No `billing.change_plan` (R-CUSTOMERS-01, V-SCU-06) | needs-orgpuls | `billing.change_plan` |
| AI assist for agents (summary, suggested reply, draft) | Panel | Claude over the thread | Inbox pattern: «AI not configured» while `ai` is not connected (V-INBOX-09, V-INBOX-13); `thread_insight_request` needs the connection (V-P7M-20) | build+connector | Claude; per-feature AI right (`global:ai` exists, V-P8P-15) |
| AI usage · 30 days | Counts | `ai_calls` | Table exists, append-only (0042) | build | Shows zero while not connected |
| Status page components | Six components with state | Application health | `applications_get` health: operational, degraded, unreachable, no_data, disabled (V-P8P-25); degraded after 26 h without events (V-PLATFORM-HEALTH-01) | build | Components beyond the products need their own checks |
| Public status page `status.orgpuls.no`, subscribers | Public page and email | Public host, subscriber list with consent | None | needs-decision | Host (D-28 vs a product domain); subscribers are an email list under D-27 |
| Incident in the product (banner) | Banner | In-app banner command | `status_banner` stored, toggle disabled «Reaches customers when Orgpuls adds a status-banner command (D-40)» (V-TICKETS-14); `status_notices` with problem link (V-PLATFORM-17) | needs-orgpuls | An in-app banner command (Tickets R-4); `settings.set_notice` is the public site notice |
| Public changelog | List | Releases | See Development | needs-decision | As above |
| Design literals: six KPIs and deltas, session-end split, gaps, article stats, AI answers by substring, contact form org match by a digit | Hard-coded | — | — | cannot | «—», empty treatments, real matches only |

**Decided:** D-20 intake; D-27 fixed rules for any customer email; D-28 host (not running); per-queue access for personvern
(V-TICKETS-23, Tickets R-2 done). **Deferred / open:** Tickets R-4 (status banner, change plan, export, EHF), R-7 (app version,
attachments: «Attachments arrive with file storage», V-TICKETS-02), R-CUSTOMERS-06 (support access delivery), R-CUSTOMERS-07
(deletion queue, DPAs). **Logged:** V-TICKETS-04 / V-SCU-11 superseded by Brevo delivery (V-MAIL-03, V-MAIL-10); V-TICKETS-20
(«the CRM prospect arrives with lead capture», since built in 0031).

---

## 3. Platform (SimplePlatform: Applications · Rollouts and announcements · Plans and prices · Billing portal · Customer success · Team · Roles and approvals)

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Seven tab pills | Local state | `?tab=` | Three tabs as links (V-SPL-01) | build | — |
| Applications | Cards, test, flags, status message, API key | — | Built (V-SPL-02…06, V-PLATFORM-01…07); p95 and errors «—» until `product-command` and `orgpuls-events` log calls (R-PLATFORM-04 open) | build | R-PLATFORM-04 (edge) |
| Gradual rollouts: which features are piloting where | Four rollouts in three products | Product flags and pilots | `modules.list`, `modules.pilot`, `locales.pilots`, `locales.pilot` in the allow-list (local `app.product_commands`, 35 commands); V-SPL-04 shows modules | build | Real names only; other products have no command path |
| Rollout percentage, per-organisation targeting, adoption and error % per rollout | Bars and figures | A percentage-capable flag store and counts | Spec §1.7: percentage only if the command reports one; reply shapes of `modules.list` / `locales.pilots` not agreed (R-PLATFORM-05) | needs-orgpuls | A runtime flag store with staged targeting and count-only adoption metrics |
| Announcement in the app (text, audience, schedule) | Composer and preview | In-app announcement command | `status_notice_set` + `settings.set_notice` (V-SPL-06) reach the public site notice, not the app (platform-gap F-1); Appendix 2 «Help texts and in-app announcements» Miss (04) | needs-orgpuls | An `announcements.set` command (audience by role, start/end), result recorded like `status_notice_push_result` |
| Announcement reach («372 users») | Count | Users in the audience | `members` per tenant with role and state (0013, `member.state` expected) | build | Audience size from `members`; «seen by» needs a count event (Orgpuls) |
| Accounts near a plan limit | Four accounts with % of band | Employees per tenant vs band | `plan_versions` bands (0013); `usage_daily.data` carries employees (04 Organisations); R-CUSTOMERS-03 still asks for `employees` in `counts.updated`; Band reconciliation left out (V-CUSTOMERS-20) | build | Read `usage_daily` employees against the band; Orgpuls sends `small`/`usual`/`group` while the seed uses band labels (platform-gap F-2) |
| «Raise limit» / band change | Action | Plan change | No command (R-CUSTOMERS-01, V-SCU-06) | needs-orgpuls | `billing.change_plan` |
| «Notify customer» about the band | Action | Email to the billing contact | V-CUSTOMERS-15 left it out «needs … a notify command»; Brevo now sends transactional mail (V-MAIL-03) | build | A transactional template from the application's own sender (V-MAIL-10); D-27 sender identity |
| Errors per customer · last 24 h | Table | Errors per organisation | Appendix 2 «Errors link» Miss (04); Sentral's own delivery errors exist (ticket reply bounces, campaign bounces, V-MAIL-05) | build+connector | Sentry (tagged by tenant, counts only) or a count-only Orgpuls event |
| Plans and prices | Cards, edit prices | `plan_versions` | Built read-only (V-SPL-07…09) | build | — |
| Saving prices, trial length, discount | Inputs | Price command | Orgpuls owns checkout (V-SPL-07); `billing.set_prices` «later» (SIMPLE-PLAN) | needs-orgpuls | `billing.set_prices`, `billing.discount` (R-CUSTOMERS-01) |
| Billing portal «Self-service billing · Lumio AS» (plan, card, invoices) | Customer view | Payment method, invoices | No invoice or payment mirror; Stripe waits (D-22, R-CUSTOMERS-04, V-CUSTOMERS-14, V-CUSTOMERS-16) | needs-decision | Tor: a payment provider and an accounting connector (EHF via PEPPOL is Miss in 04); the portal's place (see Support) |
| Failed payments recovered · 30 days, dunning | KPI and funnel | Payment events, retries | `subscriptions.payment_state` (ok, past_due, suspended) exists but is not fed (platform-gap); Retry disabled (V-CUSTOMERS-19) | needs-decision | Same provider decision |
| Refunds and credit notes | Table | Credit notes | No source (V-CUSTOMERS-17 «Refunds left out») | needs-decision | Same provider / accounting decision |
| «38 % fewer billing tickets» | Claim | Causal measurement | — | cannot | Show billing-ticket counts per period only, no causal claim |
| Onboarding checklist | Seven steps with completion | Milestones per tenant | `activation_milestones` keys account_created, employees_uploaded, survey_scheduled, survey_sent, result_unlocked, results_viewed, first_tiltak, converted (0013); filled only from what Orgpuls reports (V-CUSTOMERS-07) | build | Steps without a milestone key need Orgpuls (D-21) |
| NPS | Score and answers | Customer admins' NPS | Spec proposed `product_feedback(account_product_id, member_id, kind, score, created_at)`, not built; V-CUSTOMERS-06 «—»; Orgpuls' eNPS is respondent data and must never come (platform-gap) | needs-orgpuls | A `feedback.submitted` event from customer admins only |
| Feature requests with votes and «MRR asking» | Table | Requests per account × MRR | Tickets category `feature_request` (0012); MRR per account (V-SCU-01) | build | Same model as the Development roadmap evidence |
| Renewal and expansion | Signals | Renewal date, health, seats, cross-sell | `subscriptions.current_period_end` (0025), `renewal_window` setting (V-ANALYTICS-29), `health_scores` (0025), seats (V-CUSTOMERS-08), cross-sell rule (V-18) | build | `current_period_end` is not sent by Orgpuls today (platform-gap): «—» until it is |
| Team | List, role, invite, remove | — | Built (V-SPL-11…14); invitations by email now (V-MAIL-08) | build | — |
| Admin roles matrix | 12 × 6 matrix | Permission sets and rights | Five offered roles (0057); matrix with scopes deals, projects, campaigns, tickets, global (V-SETTINGS-22/23) | build | — |
| «Waiting for approval» queue | Approve / decline | Pending approvals with the action, requester and preview | Only privacy erasure has a two-person path (`privacy_approve`, V-P8S-23); merges and bulk deletes refuse with `approval_required` «until the approvals queue exists (phase 8)» (0011); org delete refuses when `second_admin` is on (V-CUSTOMERS-29) | build | An `approvals` table that executes the approved action; approver ≠ requester, fresh MFA, audited |
| Which actions need a second person | Policy per role | — | One switch `second_admin`, default off (D-30, D-16) | needs-decision | Tor: the list of actions and the default (D-16 says off) |

**Decided:** D-08 (roles), D-17 (nothing sold in Sentral), D-22 (Stripe waits), D-23 (content via commands), D-30 (second admin
off), V-P8P-28 (webhook needs the export right). **Open:** R-PLATFORM-04, R-PLATFORM-05, R-CUSTOMERS-01…07, SIMPLE-PLAN «Needs
outside the app» 1 (`billing.change_plan`, `billing.suspend`/`reactivate`, `users.send_login_link`, `settings.set_maintenance`,
later `billing.set_prices`). **Logged:** V-SPL-03 (maintenance disabled), V-SPL-05 (secret presence only), V-SPL-06 (status message
via `settings.set_notice`, to be corrected: it is the site notice), V-SPL-07 (prices read-only).

---

## 4. Growth (GrowthMarketing: Marketing campaigns › Campaigns; Email and automation › Email campaigns)

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Campaign list: Spent, Signups, Per signup | Table | Spend, first-touch signups by UTM | Built (V-SGR-12, V-GR2-43: imported months replace typed spend) | build | — |
| Campaign card stats and «Budget used» | Four tiles and a bar | Budget, spend | Built; budget used «—» without a budget (V-SGR-12) | build | — |
| «Daily spend and signups · click a day» | Bars per day, day info | Spend per day; signups per day by utm | `ad_daily` per day for imported campaigns (0077); typed spend is per month and «never pro-rated» in campaigns (V-SGR-09) though Overview spreads it evenly (V-GR2-04) | build | Imported days real; typed months shown as a month, not split into fake days (or the V-GR2-04 rule, stated) |
| «Ads … in this campaign» (clicks, signups, cost per signup) | Rows | Ad-level spend and clicks; signups by `utm_content` | `ad_platform_ads` and `ad_daily` level `ad` (0077, V-GR2-44 shows ad variants) | build | Per-ad spend from the import; the design splits spend by clicks (`c.spent * cl / Σcl`), which is invented |
| «… and keywords in this campaign» | Rows | Keyword and search-term reports | No keyword level in 0077; `utm_term` table lives in Analytics › Web (V-GR2-22, 0068) | build+connector | Extend `ads-run`: Google Ads keyword and search-term reports (read); LinkedIn and Meta have no keywords (targeting facets instead) |
| Recommendation texts («costs 4× more …», «converts best …») | Fixed sentences | Rules on the figures | Pattern: rules on real figures only (V-GR2-06, V-GR2-10, V-GR2-34 suggested move) | build | Rules stated; no box when no signal is strong enough |
| «Pause keyword», «Raise bid», «Move budget», «Add exclusion», «Limit audience» «applied via <platform> API» | Writes to the ad platform | Write scopes on Google Ads, LinkedIn, Meta | Read only by design (0077 header, V-GR2-42, V-GR2-43: the Pause button is off for platform campaigns); audience upload undecided (V-GR2-45) | needs-decision | Tor: write access to ad platforms (and an exclusion list built from CRM lists = personal data to the platform) |
| «Enroll» (webinar attendees into a flow) | Action | Sequence enrolment | `sequence_enroll` (V-AUTOMATION-29); engine triggers (V-SGR-17) | build | Only from a saved list or picked people |
| «Set time» (newsletter at the best slot) | Action | Campaign schedule | `campaign_schedule(p_id, p_at, …)` (V-P6C-01) | build | The slot computed, not «Tuesday 08:00» |
| Pause / Live toggle | Toggles | Record state | Changes the record only; toast tells the person to pause on the platform (V-SGR-13) | build | — |
| Tracking link, «Copy link» | Link | UTM | Built (V-SGR-11) | build | — |
| New campaign modal | Form | — | Built (V-SGR-10) | build | — |
| Email campaigns list and step editor | List, steps, triggers | Engine | Built (V-SGR-16…25) | build | Marketing edits read-only (V-SGR-25, V-SS-05) |
| «Results per step · last 30 days» (Sent, Open, Click, Unsub., Signups) | Table | Per-step campaign figures | Each email step is an automated campaign draft (V-SGR-24); `app.campaign_stats` gives sent, open and click rates over delivered, unsubscribe rate, signups by UTM from `started_at` (V-P6C-07, V-P6C-09); per-email Sent/opened/clicked already shown (V-SGR-23) | build | Open figures only for tracked campaigns (V-P6C-29) and approximate (COM-06 prefetch caveat, V-INBOX-10) |
| Tip «Create A/B test» | Action | A/B on an automated step | Refused: «no A/B (`subject_b` refused)» for automated campaigns (V-P6C-11) | needs-decision | Tor: A/B on flow steps (needs a split rule in the engine and a decision rule over a running audience) |
| Tip «Add condition» (skip email 2 if employees uploaded) | Action | Engine condition | «If the employee list is not uploaded» exists (V-SGR-20) | build | — |
| «Best time to send» heatmap (open rate by weekday × hour) | Heatmap | First human opens by local weekday and hour | `campaign_events` / `campaign_recipients.last_open_at` (V-P6C-05, V-P6C-22) | build | Enough tracked opens per cell, else «—»; Europe/Oslo (no recipient zone); prefetch caveat |
| «Use best time» / «Send all steps at the best time» | Toggle | Engine send window | The engine has no send-time, frequency cap, quiet hours or priority (V-GR2-41) | build | An engine delay «until the next weekday-hour window», a setting defaulting off (D-16) |
| Design literals: `ADS` clicks, cost split by clicks, step open % `[61, 48, 52, 39]`, heat values, «applied via API» toasts | Hard-coded | — | — | cannot | Real figures or «—»; toasts only for what happened (V-PROJECTS-23 rule) |

**Decided:** read-only ads (0077, V-GR2-42…46); no conversions sent back (V-GR2-46); spend one source per month (V-GR2-43);
D-27 for every send. **Open:** audience sync (V-GR2-45), click ids at signup (V-GR2-46), a segment as a workflow condition
(campaigns-schema «Left open»), the subscriber allowance (V-P6C-16).

---

## Orgpuls commands and events: requested in the documents, and their status

The allow-list today (local `app.product_commands`, 35 rows, = `_shared/orgpuls.ts`): `orgs.list|get|deletions|delete_now|resync`,
`billing.cancellation|extend_trial|cancel|cancel_withdraw`, `translations.*` (8), `overrides.*` (3), `modules.list|set_status|
set_validation|sync|pilot`, `locales.pilots|pilot`, `legal.reviews|approvals|review|set|auto_record`,
`settings.notice|set_notice|set_indexing`. Event kinds Sentral expects (local `app.product_event_kinds`): `billing.changed`,
`contact.submitted`, `counts.updated`, `demo.requested`, `logins.daily`, `member.joined`, `member.left`, `member.state`,
`milestone.reached`, `org.attribution`, `org.created`, `org.deleted`, `support.requested`, `survey.round`, `usage.daily`.

| Requested | Where | For (v3 area) | Status |
|---|---|---|---|
| `billing.change_plan` | R-CUSTOMERS-01, SIMPLE-PLAN 1, Tickets R-4 | Portal band changes, «Raise limit», service requests | Open |
| `billing.discount`, `billing.complimentary` | R-CUSTOMERS-01 | Billing portal, plans | Open |
| `billing.suspend` / `reactivate` (`orgs.suspend`) | R-CUSTOMERS-01, SIMPLE-PLAN 1 | Accounts | Open |
| `orgs.transfer_owner`, `orgs.merge` (+ preview), `orgs.export` | R-CUSTOMERS-01, Tickets R-4 | Accounts, service requests | Open |
| `members.resend_invite`, `magic_link` (`users.send_login_link`), `reset_mfa`, `change_email`, `set_billing_contact`, `remove`, `deactivate` | R-CUSTOMERS-02, SIMPLE-PLAN 1 | Accounts › users | Open |
| `members.erase` | spec §6 Q2 | Privacy (SEC-11) | Open |
| `access.request` + events `access.approved`, `access.denied`, `access.page_view` | R-CUSTOMERS-06 | Portal support access | Open |
| Deletion queue projection / event; `dpa.accepted` | R-CUSTOMERS-07 | Portal deletions, DPAs | Open |
| `settings.set_maintenance` | V-P8P-17, V-SPL-03, SIMPLE-PLAN 1 | Applications | Open |
| In-app status banner / announcement command | Tickets R-4, V-TICKETS-14 | Status and changelog, Announcement in the app | Open (`settings.set_notice` is the public site notice) |
| Switch to EHF invoice | Tickets R-4 | Billing | Open |
| `billing.set_prices` | SIMPLE-PLAN 1 («later») | Plans and prices | Open |
| `jobs.retry`, count-only `job.run` events | R-PLATFORM-05, V-PLATFORM-15 | Job monitor | Open (`job.run` not in the registry) |
| Ping / version reply | spec §6 Q2, V-SPL-16 | Applications, status page components | Open |
| Reply shapes of `modules.list`, `locales.pilots`, `legal.reviews`, `translations.list` | R-PLATFORM-05 | Rollouts, content | Open |
| Content read commands (question set, pulse templates, tiltak library) with draft and rollback | spec §1.8, V-PLATFORM-18 | Content | Open |
| Count-only guardrail status | V-SECURITY-12, spec §4 | Data protection | Open |
| D-21 counts: survey scheduled/sent, result unlocked, results viewed, tiltak created, logins by role (`survey.round`, `milestone.reached`, `counts.updated`, `logins.daily`) | D-21, R-CUSTOMERS-03 | Onboarding checklist, health, plan limits | Decided; Sentral side built (0013, 0044 registry); **Orgpuls has not added them** (platform-gap) |
| `member.state` (last login, MFA, auth method, invite state) | R-CUSTOMERS-02 | Accounts, announcement reach | Registry expects it; not sent (V-CUSTOMERS-10) |
| Price, currency, seats on `billing.changed`; `current_period_end` | D-22, spec insights §2 | MRR, renewal | Decided; consumer built (0025, 0067); Orgpuls' event still carries no price, seats, payment state or period end (platform-gap) |
| Help widget counts (views, deflections) | tickets spec §1.2 («to be added per D-40») | Support results, Articles by results | Not requested of Orgpuls yet; `help_article_stats_daily` has no writer |
| `context.app_version` and context fields on `support.requested` | Tickets R-7, V-TICKETS-07 | Widget captured context | Open |
| Feature-use keys (adoption) | Analytics R-5 | Rollout adoption % | Open |
| `signup.lookup_failed` | V-ANALYTICS-21, Analytics R-7 | Development sample feature «Org.nr lookup accepts ENK» | No source |
| Last touch on attribution | V-ANALYTICS-25 | Growth outcomes | Product to send (`has_last_touch`) |
| NPS / in-app feedback from customer admins | customers spec A3 (`product_feedback`) | Customer success NPS | Not requested formally; no source (V-CUSTOMERS-06) |
| Signup role (persona), click ids (gclid, li_fat_id, fbclid) | V-GR2-36, V-GR2-46 | Growth | Left out on purpose |

---

## Proposed database objects already named in the documents (and whether they exist)

| Object | Named in | Status |
|---|---|---|
| `tickets`, `ticket_messages`, `ticket_links`, `ticket_macros` + `ticket_macro_versions`, `help_articles`, `help_article_stats_daily`, `ticket_queues`, `ticket_categories`, `ticket_sla_policies`, `privacy_requests` | 07 (Support row), tickets spec §4 | Built 0012 / 0023; `help_article_stats_daily` has readers only |
| `ticket_events` (status transitions, reopen rate) | 07, tickets spec §1.2 | **Not built** (no `app.ticket_events`); changelog serves history |
| `ticket_attachments` (staff-only bucket) | tickets spec §1.3, R-7 | Not built (V-TICKETS-02); `record-files` signer exists (0052) |
| `tickets.topic`, `tickets.org_stage_at_open` | tickets spec §1.2 | Not built |
| `csat_submit(token, score)` (anon) | tickets spec §1.3 | Not built; must be an edge function (anon calls nothing, V-P8S-13) |
| `support_access_grants` | 0013, R-CUSTOMERS-06 | Built; not delivered |
| `plan_versions`, `plan_accounts`, `coupons`, `campaign_coupons()` | 0013, 0057, 0040 | Built; `coupon_save` + usage counts open (R-CUSTOMERS-05) |
| Invoice / payment mirror (number, date, amount, status, method, dunning step, reason) | R-CUSTOMERS-04 | Open (D-22) |
| `product_feedback(account_product_id, member_id, kind 'nps'\|'feedback', score, created_at)` | customers spec A3 | Not built |
| `product_counts`, `activation_milestones`, `product_survey_rounds` | customers spec A3 | Built 0013 |
| `health_models`, `health_scores`, `subscriptions.current_period_end` | insights spec, 0025 | Built |
| `status_notices`, `product_commands`, `job_defs`, `job_runs`, `integration_calls`, `integration_catalog`, `integration_connections` | platform-schema | Built 0044 (+0077 providers); `integration_calls` has no writer from `product-command` (R-PLATFORM-04) |
| `app_extensions` (INT-10) | platform-schema V-P8P-13 | Not built (no writer) |
| Realtime broadcast trigger + `realtime.messages` policy | V-P8P-31, spec Q14 | Not built |
| `ai_calls` (AI gateway log) | 07, meetings-schema V-P7M-22 | Built 0042 |
| Approvals queue | 0011 header, D-30 | Not built (only `privacy_jobs` approvals) |
| `currencies`, `exchange_rates` + Norges Bank job | R-SETTINGS-01 | Open |
| Event kinds per record type | R-AUTOMATION-04 | Partly (`event_catalog_get`, V-P8P-26) |
| `asana_task`, `trello_card` step kinds | R-AUTOMATION-06 | Open |
| `marketing_budgets`, `growth_experiments`, `growth_blackouts` | 0076 | Built |
| `ad_accounts`, `ad_platform_campaigns`, `ad_platform_ads`, `ad_daily`, `ads_oauth_states` | 0077 | Built (no keyword level) |
| `campaigns`, `campaign_recipients`, `campaign_links`, `campaign_events`, `app.campaign_stats` | 0037 | Built |
| `password_history` | spec §6 Q4 | Only if Tor turns reuse on |
| Register keys `mcp_writes`, `session_idle_mobile` | spec §6 Q12, Q15 | Proposed only |

New objects these areas need that no document names (for the planners): `roadmap_items`, `dev_tasks`, `release_*` and
`spec_signoffs`; connector mirrors for GitHub / Vercel / Supabase Management / Sentry; `help_widget_settings`; `announcements`;
`approvals` with an action registry; a CES column; an engine send window.

## Proposed edge functions and connectors in the documents

| Worker / connector | Named in | Status |
|---|---|---|
| `product-command` additions: `worker_integration_call`, `worker_application_ping`, scope check against `installations.scopes`, queued `settings.set_notice` | R-PLATFORM-04, platform-schema | Open (edge) |
| `orgpuls-events` batch report (`worker_integration_call`, direction in) | platform-schema | Open |
| AI gateway (Claude): context → model → `worker_ai_call` → `worker_*_ready`, one retry | D-07, SF-24, meetings-schema | Not built; `ai` not connected |
| Mail: `mail-run`, `mail-events` (Brevo) | V-MAIL-01…15 | Built; inbox mail via staff mailboxes, e-signature, meeting notices, double opt-in still wait (V-MAIL-04) |
| `web-collect` (tracker) | V-WEB-01 | Built |
| `search-console-run`, `seo-crawl`, `pagespeed-run`, `ads-run`, `ads-oauth` | V-SGR-12, V-SGR-31, V-GR2-42 | Built |
| `storage-sign`, `jobs-run` | V-STORAGE-*, V-JOBS-* | Built; not deployed hosted |
| API gateway, MCP + OAuth, webhook worker, push worker, geocode worker, transcription, card scanner | platform-schema «Edge workers still needed» | Not built |
| PDF worker, record-files purge consumer | projects-schema, R-PROJECTS-02 | Not built |
| Norges Bank FX worker | R-SETTINGS-01 | Not built |
| CI-result writer for `firewall_status.ci` | security-schema left open 3 | Not built |
| Backup worker (`worker_backup_seen`) | security-schema | Not built |
| Public host `go.owntheagenda.com` | D-28 | Not running |

Connectors v3 needs that no document names: GitHub (read, and write only if Tor allows), Vercel, Supabase Management (Sentral's
own token), Sentry, Google Ads keyword/search-term reports (read), and ad-platform write scopes (only if Tor allows).

## Product decisions for Tor that the documents leave open

1. **Legal review owner** (Q-27: «Who does it?»): the D-27 review precedes go-live and now also covers CSAT/CES mail, status
   subscribers and announcement email; V-P7M-19 (an opt-out after a call keeps the recording) and the DPIA are in it.
2. **Meetings rights scope and visibility** (V-P7M-01, V-P7M-04: «Tor should confirm»).
3. **Marketing and deal workflows** (V-SS-05: «decide with the owner»): Marketing edits email flows read-only.
4. **Ad platforms**: write access (bids, budgets, keywords, exclusions) against 0077's read-only rule; audience upload of hashed
   addresses (V-GR2-45); conversions sent back with click ids (V-GR2-46).
5. **Payment provider** (D-22 «Stripe waits until Orgpuls takes payments»): the Billing portal, dunning, refunds and invoices hang
   on it, and on an accounting connector (EHF via PEPPOL, 04).
6. **Public host** (D-28): `go.owntheagenda.com` does not run; the v3 design names `status.orgpuls.no` and public help, portal and
   changelog pages. Which host serves what.
7. **Customer portal**: inside Orgpuls (customer logins exist there) or a Sentral public page with magic links.
8. **Effort score (CES)**: whether to ask it, the wording, and when (with CSAT or instead).
9. **Help-centre languages**: `help_articles.locale` allows nb, nn, en only.
10. **Approval policy**: which actions need a second person (D-30 / D-16 default off); the queue that 0011 promised.
11. **Development section**: who may open it (no scope fits), whether Sentral may commit to the repository, trigger or roll back
    production deploys and run migrations from the UI, and what a Claude job may do (open PRs?) and spend.
12. **A/B tests and send-time in flows**: lift V-P6C-11 (no A/B on automated campaigns) and add an engine send window (V-GR2-41).
13. **Subscriber allowance** for campaigns (V-P6C-16: «waits for a number in the register»; D-17 nothing sold).
14. **Point-in-time recovery** before CRM data (D-35); the Security screen still shows the PITR warning (V-SECURITY-14).
15. **XLSX library** (Contacts R-3: «needs a library decision (exceljs)»).
16. **First day of the week** (R-SETTINGS-06, left out).
17. **Break-glass runbook** (spec §6 Q3; security-schema left open 5: not written) and **Vercel's contract region** for the
    sub-processor register (left open 4).
18. **SLA clocks in «Waiting on customer»** (tickets spec §1.4: «unspecified. Decide and log it»).
19. **Read-only AI assistants** (`mcp_writes`, spec §6 Q12) and **password reuse** (spec §6 Q4), only if wanted.
20. **Realtime broadcast policy** on `realtime.messages` (V-P8P-31: «to be decided with the lead»).

## Risks against the security rules (from the documents)

1. **Rule 1, public pages.** Status page, public help centre, widget search, CSAT/CES links and a portal need anonymous access;
   `structure_invariants` asserts anon can call no platform function (V-P8S-13). Every public read or write must go through a
   service-role edge function with token hashes (patterns: `web-collect`, `/u/<token>` → `worker_unsubscribe`, V-MAIL-07), never
   a grant to `anon`. CLAUDE.md rule 2 requires a written reason beside each new public path.
2. **Rule 3, `product-command` authorises any admin for any command.** The docs planned «refuse a command whose scope is not in
   `installations.scopes`» (platform-schema) and noted that command scopes are «not staff permissions» (05 SF-01.2). New commands
   (change plan, announcements, maintenance, rollouts) make this gap larger; the rights check must sit inside the function.
3. **Rule 4.** Widget counts, votes, NPS and access approvals must arrive as events through `orgpuls-events` (HMAC before parse,
   five-minute window, duplicates refused), never as calls into Sentral's API from the product.
4. **Rule 5.** GitHub, Vercel, Supabase Management, Sentry and Claude tokens only through `secret-intake` (V-MAIL-01, V-GR2-42
   pattern), never shown (V-SPL-05), never relayed by a person; the Management token in cloud sessions is Orgpuls' (CLAUDE.md).
5. **Rule 6, respondent data.** AI answers, AI assist, Claude jobs and Sentry imports must not carry survey answers, groups or
   comments (D-19, D-34, SF-24.2, UF-27 step 2); no free text in event payloads (V-P5-02); ticket bodies never in audit, events or
   notifications (tickets spec §1.3); `ai_calls` refuses a `prompt` (V-P7M-22). The widget never loads on a survey host
   (`survey_flow_block`, fixed). Error trackers must be configured to send kinds and counts, not payloads.
6. **Rule 2 and D-11.** Deploy, roll back, commit, approve and price changes need the owner or a named right plus a fresh second
   factor (V-PLATFORM-07, V-P8P-17 pattern); an approver must not be the requester (V-P8S-23).
7. **Rule 7.** «Runs migrations» from a Vercel/Supabase tab must apply only committed files (Orgpuls playbook: `apply_migration`
   with the file verbatim; destructive statements are cancelled by the connector).
8. **Personal data to third parties.** Ad exclusions from CRM lists (V-GR2-45) and AI calls are sub-processor matters: the
   sub-processor register shows only providers in use (V-P8S-13); Anthropic is added when the AI provider is connected.
9. **Never fabricate.** Every v3 literal (votes, MRR asking, DORA, AI acceptance, 372 users, 38 % fewer tickets, heat values,
   step open rates) must render as «—» or an empty treatment until a source exists.

## Suggested build order (sizes: S ≈ ½–1 day, M ≈ 2–3 days, L ≈ 4–6 days, XL > 1 week)

1. **Shell and rights** (S): fifth rail section, new pills in Customers and Platform, a Development right (after decision 11).
2. **Growth on data Sentral already holds** (M): results per step from `campaign_stats`, best-time heatmap from tracked opens,
   daily spend from `ad_daily`, ads per campaign, rule-based tips, «Enroll», «Set time», «Add condition».
3. **Engine send window** (M): «Use best time» as a delay to the next weekday-hour window, setting default off.
4. **Support on the existing tickets backend** (M): Support results from `ticket_reports`, help-centre editor over `help_articles`,
   channel shares, inbound `support@` → ticket in `mail-events`, `tickets.topic` for gaps.
5. **CSAT request and one-click page** (M): resolution email through `mail-run`, token page on Sentral's host, then CES after
   decision 8.
6. **Platform: Roles and approvals** (L): `approvals` queue with an action registry, executing approved actions, fresh MFA; plus
   the rights check inside `product-command` (risk 2).
7. **Platform: Customer success on Sentral data** (M): onboarding checklist from `activation_milestones`, feature requests from
   tickets × MRR, renewal and expansion from `current_period_end`, health, seats; accounts near a plan limit from `usage_daily`
   employees with «Notify» by email.
8. **Development on Sentral tables** (M): roadmap, work board, bug triage from `bug`/`feature_request` tickets, release records,
   sign-offs, repo rules, integrations register.
9. **Development connectors, read only** (L): GitHub, Vercel, Supabase Management, Sentry mirrors through cron → edge function;
   release gate from check runs; `firewall_status.ci` writer; delivery metrics.
10. **Google Ads keyword and search-term import** (M): extend `ads-run` (read only).
11. **AI** (L): Claude through `secret-intake`, AI assist for agents, widget answers over published articles, «improve from
    tickets», Claude jobs (writes only after decision 11).
12. **Public widget endpoint** (M) and **public pages** (XL, after decision 6): status page, help centre, changelog, portal.
13. **Orgpuls side** (outside this repo, D-40/D-21): in-app announcement and banner command, help-widget embed and count events,
    support access, `billing.change_plan`, staged rollout store, NPS from customer admins, D-21 counts, `member.state`, price and
    seats on `billing.changed`.
14. **Billing portal** (blocked on decision 5).

### Element counts per area (this digest's tables)

| Area | Elements | build | build+connector | needs-orgpuls | needs-decision | cannot |
|---|---|---|---|---|---|---|
| Development | 28 | 11 | 10 | 2 | 4 | 1 |
| Support | 35 | 17 | 4 | 8 | 5 | 1 |
| Platform | 24 | 13 | 1 | 5 | 4 | 1 |
| Growth | 19 | 15 | 1 | 0 | 2 | 1 |
