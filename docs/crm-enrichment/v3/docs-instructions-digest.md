# INSTRUCTIONS.md digest for the v3 design (Development · Support · Platform · Growth)

Evaluator: documents, part 1. Date: 12 Oct 2026. Evaluation only. No code, migration or other document was changed.

## Overview

**What was read.** `docs/crm-enrichment/INSTRUCTIONS.md` was read in 17 sequential chunks, all 4,141 lines (332,825 bytes),
including the last line («End of file … 183 features, 29 user flows, 45 system flows …», L4141). `cmp` shows it is
byte-identical to the handoff copy `project/uploads/orgpuls-crm-enrichment-claude-code-instructions.md`, so the upload adds
nothing new. Context was also read: `DECISIONS.md` (D-01–D-42), `SIMPLE-PLAN.md`, the four sibling v3 gap files (headings and
cross-checks), the migrations (grep for tables, settings and commands), and the local database (read-only `SELECT`s:
`app.product_commands`, `app.product_event_kinds`, row counts).

**What the document is.** It is a CRM-enrichment brief: the Pipedrive feature set in Parts C–H and Appendix 1, written onto the
Orgpuls platform-admin specification in Appendix 2. **It does not mention a Development section.** Roadmap, release, product
changelog, feature vote, environment, delivery metric, release gate, repo rule and Claude job appear nowhere as product
features. What the v3 Development design shows has to be derived from three things the document does contain:
- its own engineering process: rules R1–R12, the DB, security and verification standards in A6–A8, the definition of done
  in A10, reporting in A11, and the phase plan in Part G;
- Appendix 2's ticket model: incidents, problems, the «bug» and «feature request» categories, and known errors;
- Appendix 2's System operations list: job monitor, integrations status, feature flags, errors, maintenance.

Support and Platform are covered directly and in detail by Appendix 2, under Ticketing, Users and support access,
Communication and support, System operations, Billing, Analytics and Data/privacy. Growth is covered by Appendix 2 (Web
analytics, Marketing CRM) and Part C (CMP, COM, AUT). The document does not cover **ad keywords, bid or budget changes on ad
platforms, or send-time optimisation**.

**Order of authority** (L81 and DECISIONS.md L3):
1. Tor's recorded decisions (D-01 to D-42);
2. rules A2;
3. Parts C–G;
4. the appendices.

CLAUDE.md wins on security everywhere. D-01 means «Where the brief says something "already exists in the admin", it is to be
built», so Appendix 2's «existing» items are requirements, not facts.

**How to read the tables.**
- *Source* gives the section heading and the line number(s) in INSTRUCTIONS.md.
- *Today* names the repo object that already serves the requirement, or «—».
- *Bearing / verdict* uses the v3 vocabulary: **build** (includes extending what exists), **build+connector**,
  **needs-orgpuls**, **needs-decision** and **cannot**. A **constraint** row is a rule that limits other rows; it is not
  built on its own.

Counts: Development 33 requirements, Support 37, Platform 36, Growth 23, plus 22 cross-cutting rules that apply to all four.

---

## 0. Cross-cutting rules that bind every v3 tab

| # | Requirement (quoted or closely paraphrased) | Source | Today | Bearing |
|---|---|---|---|---|
| X-01 | «No CRM code path may read survey responses or respondent identities … The site tracker and widgets never load in the survey flow.» | A2 R6 · L67 | CLAUDE.md rule 6; setting `survey_flow_block`; D-34 tests | constraint: the help widget, AI answers, search, exports and errors must never reach respondent data |
| X-02 | «Every limit, plan gate, quota, approval step and compliance rule is a setting, and each setting's default leaves the feature fully working and unrestricted.» | A2 R5 · L65; A9 · L243-253 | `settings_registry`, `setting_values`; D-16 | constraint: approvals, plan-limit gates and AI approval are settings that default to off or unlimited |
| X-03 | «No stubs, no TODO markers, no mock data, no placeholder screens and no "coming soon" in delivered work.» | A2 R4 · L63 | CLAUDE.md «never fabricate» | constraint: matches the honest «—» / empty / disabled-with-reason rendering |
| X-04 | «Every server entry point checks session, admin role, permission and visibility before touching data, and denies by default. Hiding something in the interface is never the control.» | A7.1 · L190 | `app.is_admin()` + aal2 | constraint |
| X-05 | Outbound calls «must block private and link-local addresses and metadata endpoints, use timeouts, and never follow redirects into them» | A7.7 · L196 | D-32 | constraint on every new connector: GitHub, Vercel, Sentry, Supabase Management, Claude, ad platforms |
| X-06 | «Encrypt provider tokens and credentials at rest using the mechanism the repository already has.» | A7.8 · L197 | Vault + `secret-intake` (CLAUDE.md rule 5, D-18) | constraint |
| X-07 | Public surfaces «use unguessable, revocable tokens. Abuse protection on them is a technical safeguard, built as settings…» | A7.9 · L198 | D-28 (go.owntheagenda.com) | constraint for the public help centre, status page, CSAT link, contact form and portal |
| X-08 | AI: «Treat all external content as untrusted … The AI gateway never lets such content trigger a write. AI output is never written without the user's approval where the specification requires approval.» | A7.10 · L199 | — | constraint for AI answers and Claude jobs |
| X-09 | «The audit log is append-only. Every write, and every read of customer-scoped data, writes an audit row. A typed reason is a setting, off by default.» | A7.11 · L200 | `app.audit` (D-12) | constraint |
| X-10 | «API and connector calls run with the calling user's permissions. Tokens can be rotated and revoked at once.» | A7.12 · L201 | api_tokens, oauth_grants | constraint |
| X-11 | «Logs and error reports contain no message bodies, no tokens and no personal data beyond identifiers.» | A7.13 · L202 | CLAUDE.md rule 6 | constraint: error tracking, AI-call logs and job logs |
| X-12 | Visual verification at 1440 and 390 px for every state; keyboard and accessibility pass | A8 · L225-237 | `scripts/visual` | constraint on every new screen |
| X-13 | DB standards: a product key on every table; created/updated/deleted columns; «The row, its changelog entry, its audit row and its event are written together or not at all»; 30-day soft delete; «Configuration as data … versioned rows» | A6 · L169-184 | repo conventions | constraint on every new table |
| X-14 | Rule settings: «The feature asks the settings registry … returns allow, warn or block … A block names the setting that caused it.» | SF-34 · L2256-2265 | `app.setting()` | constraint |
| X-15 | Data-model conventions: product ID on every row, owner/visibility/timestamps, versioned configuration, row + changelog + event in one transaction | Part F · L2391-2398 | — | constraint |
| X-16 | Principles: «Anonymity holds for staff too»; «Admin sees metadata (counts, dates, response rates, status) by default; content access requires customer consent»; least privilege; «Everything is audited»; «Data, not code»; «EU residency» | App2 › Purpose and principles · L3785-3792 | D-19 | constraint |
| X-17 | «Database, storage, logs, AI processing and sub-processors in the EU» | Part G NFR › Data residency · L2561 | eu-central-1 (D-35) | constraint on the Claude API and every SaaS connector; see Decisions |
| X-18 | «Alerts on failed jobs, sync lag, send failures and error rates, shown in the admin's job monitor» | Part G NFR › Monitoring · L2567 | `job_defs`, `job_runs` | constraint: new connectors report into the job monitor |
| X-19 | «Every third-party service behind an adapter» | Part G NFR › Provider independence · L2573 | `supabase/functions/_shared/*` | constraint |
| X-20 | «Survey respondents never become CRM contacts through any path that reads product data.» / Marketing CRM «Hard rule: respondents … are never contacts in the CRM» | R6 · L67; App2 › Marketing CRM · L4018 | — | constraint: NPS, feedback and widget users are *users*, never respondents |
| X-21 | «Do not copy Pipedrive's names, text, icons or screen layouts.» | A2 R12 · L79; open point 9 · L2596 | — | constraint: the Pipedrive release log, support tiers and marketplace are research only |
| X-22 | «Ask when unsure … Never choose silently» / record answers in DECISIONS.md | A2 R3 · L61; A11 · L272-274 | DECISIONS.md | process: every needs-decision below goes to Tor in one numbered message |

---

## 1. Development (roadmap, feature requests, votes, bugs, releases, changelog, integrations register, environments, delivery metrics, specs, Claude/AI jobs, release gates, repo rules)

The document has no Development module. The rows below are everything in it that bears on the DevHub and DevClaude tabs.

| # | Requirement | Source | Today | Bearing / verdict |
|---|---|---|---|---|
| DEV-01 | «The build runs in nine phases ordered by dependency, each closed by a gate that names the user flows that must pass» (phases 0–8 with modules, size, exit gate) | Part G › Delivery plan · L2513, table L2515-2525 | phase reports in `docs/crm-enrichment/reports/`; no roadmap table | **needs-decision**: this is the only roadmap the document defines, and it is the platform's *own build plan*. It does not define a roadmap per product (Orgpuls, Skiftly…), or say what an item is, who sees it, or where it comes from |
| DEV-02 | «Each phase ends with a stop for your review before the next starts»; «Phases 5 to 7 are independent of each other after phase 4 and can be reordered by business priority»; features started in one phase and finished in a later one (table) | Part G · L2534, L2537, L2539-2547 | — | **build** once DEV-01 is decided: ordering, dependency («waits for») and a review stop per milestone are the roadmap mechanics the document actually describes |
| DEV-03 | Admin-spec phasing: «1 — Run the business … 2 — Get paid properly … 3 — Scale … 4 — Leverage the data», each with «Why now» | App2 › Phasing · L4113-4120 | — | a second build roadmap, the source for «why now» text; same verdict as DEV-01 |
| DEV-04 | «S up to 3 person-weeks, M 3 to 8, L 8 to 16, XL more than 16 … at least 169 person-weeks … with AI-assisted development, measure the real pace in phase 0 and re-size from that» | Part G › Delivery plan · L2527 | nothing measures pace | **build+connector** (GitHub: merged PRs and commits; Vercel: deployments) for «real pace». Which delivery metrics, and their definitions: **needs-decision** |
| DEV-05 | «Measure pipeline load, search, report queries and list views with a realistic seeded volume, report the timings, and ask Tor for targets»; NFR Performance «To decide» | A8 › Performance · L241; Part G NFR · L2566 | D-39 (targets from measurements); `page_vitals` covers marketing pages only | the delivery-metrics tab can show app timings only with a source (**build+connector**: Vercel); targets: **needs-decision** |
| DEV-06 | Ticket category «feature request» | App2 › Ticketing › Ticket fields and workflow · L4077 | `ticket_categories` row `feature_request` (0012 L43) | **build**: feature requests come from tickets. **Votes are not in the document: needs-decision.** The honest count available today is linked tickets or organisations per request |
| DEV-07 | «Top categories feed back into help articles and onboarding fixes»; «Close the loop on tickets … Every resolved incident or repeated question becomes a help article or product fix; track ticket-to-article rate» | App2 › Ticketing › Service levels · L4088; App2 › Best practices · L4111 | `help_articles.problem_id` (0012) | **build**: a link from request/bug to roadmap item and to help article; ticket-to-article rate as a metric |
| DEV-08 | Incident: «Something is broken for a customer»; Problem: «Root cause behind one or more incidents»; «Incidents can be linked to a problem; resolving the problem notifies all linked tickets»; priority «set from impact … × urgency …, not picked freely» | App2 › Ticketing › ITSM model · L4056-4060 | `tickets.type` ∈ question/service_request/incident/problem (0012 L125); `ticket_links` | **build**: bug triage = problems with linked incidents; severity = the impact × urgency priority |
| DEV-09 | «Known errors with a workaround are published to the help centre and an in-app status banner» | App2 › Ticketing · L4061 | `help_articles.problem_id`; `status_notices.problem_ticket_id` (0044); Orgpuls `settings.set_notice` registered | **build** (largely exists): bug → known error → article and banner |
| DEV-10 | «A changelog entry holds field, old value, new value, user, time and source»; SF-02 «The change, its changelog entry and an event are written in one transaction» | PIP-04 · L399; SF-02 · L1927; A6 · L179; Part F · L2398 | `app.changelog` (0004) | **naming collision**: «changelog» in the document is record history. A *release* changelog for customers is not specified (**needs-decision**). Do not reuse `app.changelog` for release notes |
| DEV-11 | «Every content change records author, date and version, and published content can be rolled back» | App2 › Content management · L3925 | `*_versions` pattern (`ticket_macro_versions`, `email_template_versions`, `document_template_versions`) | **build**: if release notes are written in Sentral they follow this versioning |
| DEV-12 | Pipedrive «Recent releases» monthly log (Nov 2025–Sep 2026) | App1 › Recent releases · L3462-3490 | — | research only (R12 · L79): not a requirement |
| DEV-13 | Integration catalog: «grouped in collections … what each can access, an install step, settings, per-user management and removal»; acceptance «Removing an integration revokes its access» | INT-11 · L1490-1494 | `integration_catalog`, `installed_apps` (0044) | **build** (exists in part): the base of the integrations register |
| DEV-14 | «The connector's status and error rate are reported to the admin's integrations status»; App2 «Integrations status — Brønnøysund API, e-mail provider, payment provider, SMS; last success and error rate» | SF-41 · L2335; App2 › System operations · L3983 | `integration_calls` (product commands and events, 0044), `growth_sync_log`, ads and Search Console sync logs | **build**: health per connection from the logs that exist. GitHub, Vercel, Sentry and Supabase entries: **build+connector** |
| DEV-15 | «Every third-party service behind an adapter»; open point 2 «Build or buy for providers … A choice per service» | Part G NFR · L2573; Part G risks #2 · L2589 | D-07 (providers per phase) | **build**: the register names the provider and adapter per service |
| DEV-16 | Subprocessor register «Supabase, Vercel, e-mail provider, payment provider, with region; source for the public list» | App2 › Data, privacy and compliance · L3937 | `app.subprocessors` (0043) | **build**: each new connector (GitHub, Sentry, Anthropic, Google Ads…) is also a subprocessor row with its region (X-17) |
| DEV-17 | «Never run against production. Never use real customer data. Work on a branch, against a local or development database, with the seeded demo tenant … The service-role key never reaches the browser.» | A2 R8 · L71; A3.2 «Do not connect to production» · L101 | D-02, D-33 | environments tab: **build+connector** (Vercel deployments; Supabase branches and projects through the Management API, whose cloud token returns 403 here per CLAUDE.md › Operating). See conflict C-16 |
| DEV-18 | Sandbox: «In the Orgpuls admin this is the seeded demo tenant. It holds configuration and demo data, never customer data»; «Seeded demo tenant … Lumio AS / Kari Nordmann»; NFR «Test data» | CUS-08 · L678-682; App2 › Best practices · L4108; Part G NFR · L2572 | `supabase/seed.sql`; `is_sample` columns | **build**: sandbox shown as an environment |
| DEV-19 | «Stated recovery point and recovery time, proven by restore tests»; «Backups — last successful backup, last restore test»; SEC-10 «A restore test meets the agreed objectives»; SF-43 «the last success is recorded» | Part G NFR › Recovery · L2564; App2 · L3939; SEC-10 · L1414-1418; SF-43 · L2359-2360 | `ops_checks` (backup, pitr, restore_test) (0043); D-35 RPO 1 h / RTO 4 h | **build** (exists); automatic backup status: **build+connector** (Supabase Management API) |
| DEV-20 | Spec format: «Every feature has one row: what it does, the rules that constrain it, and how to tell it is done. IDs are stable»; statuses Implemented · Partial · Missing · Conflict · Unknown; «Each specification's acceptance criterion becomes an automated test, and each user and system flow an end-to-end test» | Part C intro · L372; A3.5 · L113-133; Part G · L2532 | the specs are Markdown in `docs/` | spec-documents tab: **build** (from committed files, or **build+connector** GitHub); reuse the five-status vocabulary |
| DEV-21 | «Nothing is done until type check, lint, unit tests, database tests, end-to-end tests, visual verification and the security checklist all pass. A failing gate is fixed. It is never skipped, disabled, loosened or marked as expected to fail.» | A2 R10 · L75 | CLAUDE.md › Gates; CI on every push | release-gate tab: **build+connector** (GitHub Actions check runs for the commit) |
| DEV-22 | Definition of done: every sentence implemented, settings tested in both states, DB/unit/e2e tests pass, screens captured and inspected, security checklist recorded, audit/changelog/events tested, no stub, type check and lint pass | A10 · L255-270 | — | **build**: gate checklist items. Evidence per item needs a source (connector or committed report) |
| DEV-23 | Security checklist per package recorded in `docs/crm-enrichment/security/`: built output has no secret (A7.2), dependency audit (A7.14), «`supabase db lint` and … advisors after each migration» (A7.15), firewall tests after every migration (A7.16) | A7 · L186-205 | the `security/` folder is not established here | **build+connector**: advisors through the Supabase Management API (403 caveat), `npm audit` through CI |
| DEV-24 | «Quality gates on every merge: type check, lint, unit tests, and security tests proving that no CRM function can read survey responses and that each staff role sees only what it may» | Part G › How the team works · L2533 | SQL suites in CI | **build+connector** (CI results) |
| DEV-25 | Visual verification: list states, capture 1440 and 390, «Open every image and inspect it yourself», add to visual regression, record a table | A8 · L225-235 | `scripts/visual/*` | gate item «screens verified»: evidence source **needs-decision** (CI artefact vs committed report) |
| DEV-26 | The twelve rules R1–R12 (read in full, no assumptions, ask, skip nothing, no restrictions, firewall, never weaken, protect data, match code base, pass gates, report honestly, replicate functions only) | A2 · L53-79 | CLAUDE.md in both repos | repo-rules tab: **build** (rendered from the rule files; read-only, never edited from the UI) |
| DEV-27 | DB standards incl. «Never edit a migration that has been applied; add a new one»; RLS on every new table; firewall; seeds | A6 · L169-184 | CLAUDE.md rule 7 | **build** (repo rules) |
| DEV-28 | «Asking. One message. Numbered questions. For each: what you found …, the options you see, what each option changes, and which work is blocked»; phase report contents (IDs, migrations, tests, visual table, security result, settings, deviations, not done, open questions) | A11 · L272-286 | `docs/crm-enrichment/reports/` | Claude jobs: a job's output contract. **build** (job and result rows); running the job: **build+connector** |
| DEV-29 | «For Tor: how to start»: start Claude Code in plan mode with the given prompt; the correct check answer is 183 / 29 / 45 | For Tor · L23-37 | — | Claude jobs: a «read-in-full, confirm, plan, stop» job template. **build** (template rows) |
| DEV-30 | AI gateway: «The call is logged with feature, user and cost»; «output is validated against the expected structure»; «An invalid output is retried once»; NFR «every call logged»; open point 8 «a cost model before phase 7» | SF-24 · L2154-2163; Part G NFR › AI governance · L2568; Part G risks #8 · L2595 | `app.ai_calls` (feature, staff, provider, model, tokens, cost_micros) (0042) | **build** (cost and usage per job from `ai_calls`); executing jobs: **build+connector** (Claude API key in Vault) |
| DEV-31 | Job monitor: «scheduled sends, reminders, verneombud notices, result unlocks, retention jobs: queued, running, failed, with manual retry»; SF-26 «Each check records its run; a failed run raises an alert» | App2 › System operations · L3982; SF-26 · L2186; AUT-09 · L884-888 | `job_defs`, `job_runs` (0044) | **build** (exists) |
| DEV-32 | «Errors — link to error tracking, filtered by org» | App2 › System operations · L3985 | none | shared with PLT-08: **build+connector**; the tracker is unnamed (**needs-decision**) |
| DEV-33 | Developer surface: versioned API and reference (INT-01), personal token and OAuth (INT-02), rate limits off by default (INT-03), webhooks with retry and ban (INT-04); UF-16 «the webhook is banned and later removed; the developer sees this in the webhook list» | INT-01–04 · L1430-1452; UF-16 · L1751-1760; SF-23 · L2144-2152 | `api_tokens`, `oauth_apps`, `oauth_grants`, `webhooks`, `webhook_deliveries` | **build** (exists): webhooks and apps belong in the integrations register |

---

## 2. Support (help widget, help centre / knowledge base, contact form and email, customer portal, AI answers, support access, status page and changelog, CSAT / effort)

| # | Requirement | Source | Today | Bearing / verdict |
|---|---|---|---|---|
| SUP-01 | «Ticketing is built in-house as a simple ITSM module … so every request lands in one queue linked to the org and user it concerns. The site promises you talk to the people who build the product, so the tool should make fast, personal replies easy.» (decided) | App2 › Ticketing · L4048; Open decisions · L4137 | `tickets` and related (0012) | **build** (exists) |
| SUP-02 | Ticket types: Question, Service request, Incident, Problem, with examples | App2 › Ticketing › ITSM model · L4052-4057 | `tickets.type` | exists |
| SUP-03 | Priority from impact (one user / one org / many orgs) × urgency; «urgent = survey send failing, data concern, security» | L4059; L4076 | 0012 / 0056 | exists |
| SUP-04 | «Service requests map to admin actions (extend trial, export, plan change) that can be executed from the ticket and are logged in the audit trail» | L4062 (examples L4055) | `tickets.request` (0056); approve «extend trial» (`billing.extend_trial`) | **build** for extend trial; plan change and export: **needs-orgpuls** (`billing.change_plan`, an export command; see SUP-35) |
| SUP-05 | «Queues: Support, Billing, Sales, Personvern; routing by category, manual reassignment, escalation to super-admin» | L4063 | `ticket_queues`, `ticket_categories` (0012 L30-43) | exists |
| SUP-06 | Data model `tickets`, `ticket_messages`, `ticket_links` (org, user, survey, invoice, problem), `ticket_events`; «RLS with support/super-admin roles only» | L4064 | first three exist; **no `ticket_events` table** (timeline is built elsewhere) | see conflict C-12: per CLAUDE.md rule 1 / D-09 access is through definer functions, not RLS policies |
| SUP-07 | Channel: «Contact form on orgpuls.com … creates a ticket and a CRM prospect if consented»; LGN-03 «forms reuse that path»; SF-17 step 3; D-20 | L4068; LGN-03 · L1273; SF-17 · L2084 | Orgpuls event `contact.submitted` → ticket and lead | **build** (exists through the Orgpuls event). A Sentral-hosted form: **needs-decision** (public path, D-28) |
| SUP-08 | Channel: «In-app help button — captures user, org, role, current page and browser automatically» | L4069 | event `support.requested`; ticket context fields (see support-gap.md) | the widget renders inside Orgpuls: **needs-orgpuls** (widget, article search through a signed read). Storage and analytics: **build** |
| SUP-09 | Channel: «E-mail to support@ / kontakt@ — converted to tickets, replies threaded» | L4070 | 0060 (Brevo): answers naming `[T-1234]` from the requester are threaded; `mail_settings.inbound_domain` | **build+connector** (Brevo inbound exists). Whether a new mail without a ticket reference opens a ticket was not established here (see support-gap.md) |
| SUP-10 | «No separate channel for respondents: anonymity questions go via their employer … who can raise a ticket» (decided) | L4071; Open decisions · L4135 | — | **constraint**: no widget, contact form or AI answer in the survey flow (X-01, SUP-36) |
| SUP-11 | Status new · open · waiting on customer · waiting on us · resolved · closed; priorities; categories (getting started, survey delivery, results and anonymity, tiltak, billing, bug, feature request, sales, personvern request) | L4075-4077 | 0012 | exists |
| SUP-12 | «Assignee, internal notes, @mentions, attachments»; linked org, user, survey or invoice; «ticket history shown on the org detail page» | L4078-4079 | 0012 | exists |
| SUP-13 | «Canned replies (macros) in Norwegian, editable in Content management» | L4080 | `ticket_macros`, `ticket_macro_versions` | exists |
| SUP-14 | «Personvern-category tickets flow into the personvern request queue with its 30-day clock»; App2 «Personvern requests — a queue … with due dates (30 days) and status» | L4081; App2 › Users and support access · L3911 | `privacy_requests` (0012) | exists |
| SUP-15 | First response (business hours): urgent 4 h, high 1 day, normal 2 days, low 5 days; resolution (business days): 2 / 5 / 10 / 20; «overdue highlighting» (decided) | L4085; Open decisions · L4136 | `ticket_sla_policies` (240/960/2400 min…), `business_hours` | exists |
| SUP-16 | «Volume by category and by lifecycle stage (trial vs. customer), time to first response, time to resolve, reopen rate» | L4086 | `ticket_reports` (0012, 0023) | **build** (exists in part) |
| SUP-17 | «CSAT (one-click rating) after resolution» | L4087; Phase 2 · L4118 | `tickets.csat_score` 1–5, `csat_requested_at`, `csat_at`, `csat_token_hash` (0012 L153-156); no worker requests CSAT today (support-gap.md) | **build** (the request mail and a public one-click page; the public path needs a reason, rule 2). **Effort score (CES) is not in the document: needs-decision** |
| SUP-18 | «Self-service — a help centre with articles managed in the admin; the help widget suggests articles before a ticket is created»; Phase 3 «help centre with article suggestions» | L4090; Phasing · L4119 | `help_articles` (slug, title, body, category, locale nb/nn/en, draft/published, version, problem_id) + `help_article_stats_daily` (0012); 6 rows locally | **build**. A public help centre site: **needs-decision** (host and public path, D-28 / rule 2) |
| SUP-19 | «Tickets can contain sensitive work-environment details. Restrict ticket content to support and super-admin roles, apply the same retention and deletion rules as other customer data, and never attach survey answers to a ticket.» | App2 › Ticketing › Privacy · L4092 | ticket queue permission sets (0012 L31) | **constraint** on AI answers, search and widget analytics |
| SUP-20 | Content management: «Help texts and in-app announcements», versioned, «published content can be rolled back» | App2 › Content management · L3923, L3925 | — (D-23: product content stays in Orgpuls) | in-app help texts in Orgpuls: **needs-orgpuls**; help-centre articles in Sentral: **build** |
| SUP-21 | Support access «instead of free impersonation»: customer grants from their own settings or approves a request; «Time-boxed (e.g. 24 or 72 hours), read-only by default»; «Visible banner in the customer's app … listed in their own audit log»; «Inherits the 5-answer threshold and role scope»; «Every page view during the session is logged». Decided: «admin requests, customer approves» | App2 › Users and support access · L3903-3909; Access model (Support role) · L3801; Open decisions · L4126; Phasing (phase 2) · L4118 | `support_access_grants` (hours 24/72, state pending/active/expired/revoked/denied, `page_views`) (0013) | requesting and listing: **build**. Approval, banner, the customer's audit log, page-view counting and the session itself: **needs-orgpuls** (a request command plus `support_access.*` events). See C-03 and C-04 |
| SUP-22 | User actions: «resend invite / magic link, reset MFA, change e-mail, deactivate, remove from org, mark as admin contact for billing»; Support role «Resend invites, extend trial, reset MFA, request support access» | App2 › User search and detail · L3895; Access model · L3801 | only `billing.extend_trial`; `users.send_login_link` missing (SIMPLE-PLAN L65) | **needs-orgpuls** |
| SUP-23 | Respondents: «Per survey: invited, delivered, bounced, answered (count only)»; «Fix bounced addresses only via the customer»; «No lookup from respondent to answer, ever» | App2 › Respondents · L3897-3901 | D-19, D-21 | **constraint** (counts only) |
| SUP-24 | «E-mail/SMS log per org — every invitation, reminder and notice: sent, delivered, opened (if tracked), bounced, spam-complained. Most survey support tickets are "people didn't get it".» | App2 › Communication and support · L3973 | Sentral's own mail (ticket replies, campaigns); `mail-events` drops events not tagged by Sentral (0060 header) | Sentral's mail log: **build**. A per-recipient log of survey invitations: **cannot** (recipients are respondents, rule 6). Honest form: delivery *counts* per round from Orgpuls (**needs-orgpuls** if `survey.round` lacks them) |
| SUP-25 | «Deliverability overview — bounce and complaint rates per sending domain; alert on spikes»; CMP-08 | L3974; CMP-08 · L1184-1188 | `growth_deliverability` (0076), `sender_domains` | **build** (exists in part) |
| SUP-26 | «Support inbox link — from the org detail to the ticket thread … and vice versa» | L3977 | tickets on the account | exists |
| SUP-27 | «Feedback capture — in-app feedback and NPS stored per org, visible in the admin» | L3978 | none (no nps or feedback object or event) | **needs-orgpuls**: `feedback.submitted` / `nps.answered` from *users* only (X-20) |
| SUP-28 | «Maintenance mode and status banner» | App2 › System operations · L3986 | `status_notices` (text, maintenance, problem_ticket_id, pushed_at) (0044); Orgpuls `settings.set_notice` registered | banner: **build** (exists); maintenance: **needs-orgpuls** (`settings.set_maintenance` not registered) |
| SUP-29 | Public status page and release changelog | not in the document (only the in-app banner, L3986 and L4061) | — | **needs-decision** (components, who declares incidents, public host and path rules: X-07, rule 2) |
| SUP-30 | AI answers: AIA-01 «answers questions … explains how features work … Answers cite the records used. Survey responses are outside its reach, and its reads of customer data are audited»; UF-27 «A question about survey answers is refused»; SF-24 «Context is retrieved under the user's permissions, and never from survey response tables … no-training agreement»; NFR «human approval before any write»; D-07 «Claude as the LLM» | AIA-01 · L1022-1026; UF-27 · L1879; SF-24 · L2154-2163; Part G NFR › AI governance · L2568; A7.10 · L199 | `ai_calls` (0042) | **build+connector** (Claude API, key in Vault). The corpus (published articles only?), whether customer-facing answers need agent approval, and EU processing (X-17): **needs-decision** |
| SUP-31 | Agent assist: AIA-03 draft «inserted for editing, never sent automatically»; AIA-04 thread summary, sentiment, action items, suggested replies | AIA-03 · L1034-1038; AIA-04 · L1040-1044 | `email_thread_insights` | **build+connector**: drafts only, never auto-send |
| SUP-32 | «It is not the customer-facing admin (daglig leder / HR settings) — that stays in the product.» | App2 › Purpose and principles · L3783 | — | a customer **portal is not defined: needs-decision**. Portal functions the document names (approve support access, confirm band upgrade, re-accept DPA, deletion confirmation) live in Orgpuls: **needs-orgpuls** |
| SUP-33 | «Databehandleravtale (DPA) — per org: version accepted, date, by whom; prompt re-acceptance when the DPA changes» | App2 › Data, privacy and compliance · L3931; Phasing · L4118 | none (no DPA object found) | **needs-orgpuls** (acceptance event) + **build** (register) |
| SUP-34 | «Deletion queue — org and user deletions with grace period, execution log and confirmation sent to the customer»; «Delete org — scheduled with a grace period, confirmed by typing org.nr, super-admin only» | L3933; App2 › Organisations › Actions · L3884; D-30 | Orgpuls `orgs.deletions`, `orgs.delete_now`; event `org.deleted` | **build** (exists in part) |
| SUP-35 | «Exports — customer data export on request (aggregates, tiltak, comments without identity), logged»; org action «Export org data (for the customer, on request)» | L3934; L3883 | — | the export runs inside Orgpuls and goes straight to the customer: **needs-orgpuls**. Sentral receiving its content: **cannot** (rule 6). See C-05 |
| SUP-36 | Widgets never in the survey flow: R6; LGN-05 «No widget ever appears on a survey page»; SF-17 «It never loads in the survey flow»; App2 «never track respondents in the survey flow» | R6 · L67; LGN-05 · L1285-1286; SF-17 · L2082; App2 › Web analytics · L4011 | setting `survey_flow_block` | **constraint** on the help widget (Orgpuls must load it only on signed-in user pages) |
| SUP-37 | Pipedrive's «help center, chatbot support, 24/7 live chat support, personalized onboarding», «its support tiers are not carried over» | Part B › Goal and scope · L307; App1 › What each plan adds · L3538 | — | not a requirement (R12) |

---

## 3. Platform (rollouts and feature flags, in-app announcements, plan limits and usage, errors per customer, billing portal, customer success, roles and approvals)

| # | Requirement | Source | Today | Bearing / verdict |
|---|---|---|---|---|
| PLT-01 | «Feature flags — global and per org, for staged rollouts and pilots»; «Data, not code. Plans, … feature flags are rows managed in the admin»; Super-admin «Manage … feature flags»; Part B «feature flags (global and per organization) … module switches use the feature flags»; Phase 3 | App2 › System operations · L3984; Purpose · L3791; Access model · L3800; Part B · L348; Phasing · L4119 | Sentral `app.modules` (its *own* modules, 0005); Orgpuls commands `modules.pilot` and `locales.pilot` (question-module and language pilots); Orgpuls runtime flags are code constants (platform-gap.md) | **needs-orgpuls**: `flags.list`, `flags.set_stage`, `flags.pilot` and a runtime flag store in Orgpuls |
| PLT-02 | CUS-07: «A switched-off module disappears from navigation and its API returns a disabled error … Changes to settings are logged» | CUS-07 · L672-676 | `app.modules`, `app.module_on()` | exists (Sentral's own modules) |
| PLT-03 | ENT-01 «Each feature is switched on per plan and add-on from an entitlement table … Checked in the interface, the API and the workflow engine»; D-17 «ENT means the platform's own module switches and usage counters … nothing is sold» | ENT-01 · L1552-1556 | none | **build** only for Sentral itself. Gating Orgpuls features per customer plan is Orgpuls's |
| PLT-04 | ENT-02 usage limits «unlimited until an admin sets a value»; ENT-04 «A page showing consumption against every limit … Warnings before the limit is reached … nothing is deleted»; SF-16; UF-28; events `usage.limit_warning`, `usage.limit_reached` | ENT-02 · L1558-1562; ENT-04 · L1570-1574; SF-16 · L2066-2075; UF-28 · L1884-1891; Part F event catalog · L2438 | `usage.limit_warning` / `limit_reached` emitted for the API budget (0044 L1419); product `usage_daily` | **build** (Sentral's own counters) |
| PLT-05 | Orgpuls's real plan limit is the employee band: «Pricing is per employee band (from 265 kr/month; 565 kr for 26–100 employees)»; plan catalogue «bands (min/max employees) … Price changes create a new price version»; «Band reconciliation — the employee list size decides the band. When an org crosses a band, flag it in the admin and notify the customer» (decided: «notify the customer, who confirms before the price changes») | App2 › Billing and payments · L3945, L3947, L3958; Open decisions · L4125 | `plan_versions` (band_label, min/max_employees, version) (0013); employees from subscription details / Brreg; D-22 (seats on `billing.changed`) | «accounts near a plan limit» = employee count vs band max: **build** while the counts arrive. «Near» threshold: **needs-decision**. Customer notification and confirmation: **needs-orgpuls**. Prices are rendered only from `plan_versions`, never from this text |
| PLT-06 | In-app announcements as versioned content; «Broadcasts — send an in-app banner or e-mail to a segment (all daglig ledere, all trials, one industry)»; campaign type «product announcement»; Phase 3 broadcasts | App2 › Content management · L3923, L3925; Communication and support · L3976; Marketing CRM · L4032; Phasing · L4119 | `campaigns.type` includes `product_announcement` (email, 0037); `status_notices` = one banner per product | email: **build** (exists). In-app banner to a *segment*: **needs-orgpuls** (an announcement command with an audience; D-23). Versioning and rollback: **build** |
| PLT-07 | «Maintenance mode and status banner» | L3986 | `status_notices.maintenance`; `settings.set_maintenance` not registered | **needs-orgpuls** |
| PLT-08 | «Errors — link to error tracking, filtered by org»; NFR alerts on «error rates» | L3985; Part G NFR › Monitoring · L2567 | `integration_calls` (per product, no organisation) | **build+connector** (a tracker; unnamed, so **needs-decision**) or **needs-orgpuls** (a count-only `errors.daily` per org). Error payloads: **cannot** (rule 6; Orgpuls invariant 7). See C-15 |
| PLT-09 | Subscription lifecycle: trial (30 days, no payment method), active, past due (dunning), suspended (read-only results), cancelled (to end of paid period), deleted | App2 › Billing › Subscription lifecycle · L3949-3956 | `subscriptions` from `billing.changed` | exists through events |
| PLT-10 | Plan catalogue: bands, monthly and optional annual price, «MVA 25 %», included features, active/archived; price versions | L3947 | `plan_versions` (read-only) | saving prices: **needs-orgpuls** (`billing.set_prices`, SIMPLE-PLAN L66) |
| PLT-11 | Admin billing: subscription view (plan, band, next invoice, payment method status); «Invoice list, status, PDF, resend»; «Failed payments and dunning status; manual retry»; «Credits, refunds, one-off discounts, coupon codes»; «Complimentary / partner accounts»; «Revenue reports and export to the accounting system» | App2 › Billing › Admin features · L3960-3967 | `coupons` (0013), `mrr_daily`, `mrr_movements`; no invoices or dunning objects | coupons and revenue: **build** (exists). Invoices, PDFs, dunning, retry, refunds: **build+connector** (Stripe) or **needs-orgpuls**, depending on PLT-12 |
| PLT-12 | «Norwegian B2B reality — … invoice (EHF via PEPPOL) rather than card … Support both»; «Stripe as billing source of truth — Mirror Stripe into the database via webhooks; EHF customers get a Stripe subscription with invoice collection, so there is one ledger» (decided: «Stripe + EHF invoice via the accounting system») | L3969; App2 › Best practices · L4104; Open decisions · L4124 | D-22 «Stripe waits; Orgpuls' current terms apply» | **needs-decision**: when Stripe comes. Until then a billing portal cannot show invoices as real |
| PLT-13 | Finance role «Change plan, credits, refunds, discounts»; org actions «Change plan, apply discount, mark as complimentary», «Suspend / reactivate» | Access model · L3802; App2 › Organisations › Actions · L3878-3879 | `billing.change_plan`, `billing.suspend`, `billing.reactivate` missing (SIMPLE-PLAN L65) | **needs-orgpuls** |
| PLT-14 | Business KPIs: MRR, ARR, net new MRR (new, expansion, contraction, churn); paying orgs, trials, trials expiring in 7 days; trial → paid by cohort and source; logo and revenue churn; ARPA by tier; customers by NACE, size, fylke | App2 › Analytics › Business KPIs · L3830-3837 | `mrr_daily`, `mrr_movements`, `account_churns` | exists |
| PLT-15 | «Health score per org (feeds the org list): last admin login, survey cadence vs. årshjul, response rate trend, tiltak activity, payment status. Flag at-risk orgs before renewal.»; Part B «uses it as a scoring criterion»; PRO-03 | App2 › Analytics · L3850; Part B · L335; PRO-03 · L992 | `health_models` v1 weights exactly these five (0025 L129); `health_scores` (89 rows locally); setting `renewal_window` 60 days | exists |
| PLT-16 | Activation funnel: account created → employee list uploaded → first survey scheduled → sent → result unlocked → results viewed → first tiltak → converted; «"20 minutes to first send" … becomes a tracked metric» | App2 › Analytics › Activation funnel · L3817-3828 | `activation_milestones` keys (0013 L53); event `milestone.reached`; D-21 | onboarding checklist: **build** (the data exists) |
| PLT-17 | «Lifecycle messaging — trial onboarding and nudges (e.g. day 2 "upload your employee list", day 7 "no survey sent yet"), driven by funnel events, editable in the admin»; one engine | App2 › Communication and support · L3975; Marketing CRM · L4034; AUT intro · L834; D-06 | workflow engine (0021), sequences (0059), Brevo (0060) | **build** (exists) |
| PLT-18 | Org list filters (status, tier, band, industry, fylke, source, trial days left, health score); «Saved views, e.g. "trials expiring this week without a survey sent"» | App2 › Organisations › List view · L3858-3861 | `saved_views` | CS lists: **build** |
| PLT-19 | Renewals: AUT-03 «A workflow set to 30 days before a renewal date fires on that day»; but pricing has «no binding», and a cancelled subscription «runs to end of paid period» | AUT-03 · L848-852; Billing · L3945, L3955 | `renewal_window` setting | what a renewal date is for month-to-month customers: **needs-decision** |
| PLT-20 | QBRs, customer-success playbooks, a dedicated CSM | not in the document. Pipedrive's «dedicated customer success manager» and «personalized onboarding» are support tiers «not carried over»; AUT-08 «the starting set is a product decision» | Part B · L307; App1 · L3538, L3550; AUT-08 · L881 | **needs-decision** (define, or leave out) |
| PLT-21 | «In-app feedback and NPS stored per org» | L3978 | none | **needs-orgpuls** (see SUP-27) |
| PLT-22 | Post-sale delivery: projects on boards and phases, templates with «due dates relative to the start date»; UF-20 «Hand over a won deal to delivery» | PRJ-01–09 · L1196-1252; PRJ-05 · L1224-1228; UF-20 · L1796-1805 | `project_*` tables (0038) | an onboarding project per new customer: **build** |
| PLT-23 | Roles: Super-admin, Support, Finance, Read-only/analyst («Can see / Can do»); `platform_admins` (user_id, role, mfa_enforced, created_by) «admin role is never derivable from a customer role»; SEC-07 permission sets; open point 10 | App2 › Access model · L3796-3807; SEC-07 · L1396-1400; Part G risks #10 · L2597 | `app.admins`, `permission_sets` (D-08 presets; 0057 five roles) | exists; the role sets differ between App2 (4), D-08 (7) and 0057 (5), so reconcile in the design |
| PLT-24 | «RLS stays on for all customer tables; admin access is a named policy path (`is_platform_admin(role)`), not a bypass»; A6 «write explicit policies» | App2 › Access model · L3809; A6 · L174 | D-09: definer functions, no policy | **conflict** with CLAUDE.md rule 1 (C-01): follow CLAUDE.md |
| PLT-25 | «Session timeout (e.g. 30 min idle), optional IP allowlist, and admin logins alerted to a Slack/e-mail channel» | L3811 | settings `session_idle`, `ip_allowlist`, `login_alerts` (D-29) | exists |
| PLT-26 | SEC-07 «A user cannot perform an action missing from their set, in the interface or the API» | SEC-07 · L1400 | `permission_sets` | exists |
| PLT-27 | «Safe destructive actions — Preview the effect of deletes and bulk actions, require a second admin to approve, soft delete during the grace period» versus Part B «Preview and soft delete always; second-admin approval is a setting, off by default»; register row «Second-admin approval for bulk deletes and merges — Off» | App2 › Best practices · L4106; Part B · L362; settings register · L694; A9 · L246; CRM-12 · L611; UF-24 · L1851 | setting `second_admin` (off) (0005 L41); approval logic for privacy (0043 L2012-2034); D-30 | «waiting for approval» list: **build** (empty while the setting is off). Resolved by D-30 |
| PLT-28 | Org «Actions (each requires a reason, all audited)» versus «Typed reason for CRM actions — Off» | App2 › Organisations · L3875; settings register · L700; Part B · L361 | setting `typed_reason`; D-12 | resolved by D-12 (the audit row always, the reason a setting) |
| PLT-29 | «Separate admin identities — Admin accounts separate from customer logins, quarterly access review, logged break-glass access for emergencies»; «Admin user management — invite, role, MFA status, deactivate (super-admin only)» | App2 › Best practices · L4107; System operations · L3987 | `access_reviews`, `access_review_items` (0043); audit family `breakglass.*` classified (0043 L34); a break-glass flow was not traced | **build** (exists in part) |
| PLT-30 | Security dashboard and alerts (new device or location, invites, failed logins, password reset, large exports) | SEC-01 · L1360-1364; SEC-02 · L1366-1370 | `security_events`, `security_alert_*`, alert settings | exists |
| PLT-31 | «Audit log — append-only, searchable by admin, org, action and date; covers admin actions, support-access sessions, role changes and exports. Retain longer than product data.» | App2 › Data, privacy and compliance · L3935 | `app.audit` | exists; support-access page views arrive only through Orgpuls events |
| PLT-32 | «Incident register — log of security incidents and personal data breaches with the 72-hour notification clock» | L3938 | `security_incidents` (0043) | exists |
| PLT-33 | «Retention — each customer chooses how long raw responses are kept before reduction to aggregates, default 2 years; a job report showing what was purged and when» (decided) | L3932; Open decisions · L4127 | Sentral `retention_rules` (its own data) | Orgpuls's purge report: **needs-orgpuls** (counts only) |
| PLT-34 | «Anonymity guardrails — monitoring that no query path returns n < 5; alert if an org's structure makes groups re-identifiable»; Best practices «Block differencing attacks», «Screen free-text comments» | L3936; App2 › Best practices · L4100-4101 | — | **cannot** in Sentral (needs groups and answers; rule 6). Orgpuls-side only; at most a count-only flag event |
| PLT-35 | Cross-customer benchmarks: «need an explicit legal basis … Treat as a later phase» (decided: «add to terms now, use later») | L3941; Phasing · L4120; Open decisions · L4128 | — | **cannot** here (survey figures, D-19) |
| PLT-36 | Organisation detail: «Structure: … groups below threshold»; «Surveys: metadata only»; «Tiltak: count open/closed/overdue (titles only with support access)» | App2 › Organisations › Detail view · L3867-3869 | D-19, D-21 count events | counts: **build** (via events). Tiltak titles in Sentral: **cannot** (product content, D-23); visible only inside an Orgpuls support-access session |

---

## 4. Growth (ad keywords, bid/budget changes, daily spend, email per-step results, send-time optimisation)

| # | Requirement | Source | Today | Bearing / verdict |
|---|---|---|---|---|
| GRO-01 | «Marketing attribution — store UTM source/medium/campaign and referrer on signup, and report signups, activation and paid conversion per channel, so the monthly marketing spend can be judged by paid customers, not clicks»; «First-touch and last-touch source stored on the org at signup» | App2 › Analytics · L3848; Web analytics › Conversion · L4006 | event `org.attribution`; `growth_outcomes` (0076) | exists |
| GRO-02 | «Campaign view: spend (entered manually per channel), visits, signups, activated orgs, paid orgs, cost per paid customer» | App2 › Web analytics › Traffic and sources · L3997 | `marketing_spend` (manual, 0025); `ad_daily` (imported impressions, clicks, spend, conversions, reach per day, 0077) | **daily spend: build** (exists). The document expects manual entry; imported spend goes further than the document, so label each figure's source |
| GRO-03 | «Search Console data: queries, impressions, position for key terms (medarbeiderundersøkelse, arbeidsmiljøkartlegging)»; «Search Console imported nightly via API» | L3999; L4010 | `search_console_*` (0064) | exists. These are *organic* queries, not ad keywords |
| GRO-04 | **Ad keywords: not in the document.** The nearest mentions: Web Visitors filter «Google AdWords campaign» (research); WEB-03 filter by «campaign»; «Google Ads via Make»; reviews «no native LinkedIn Ads link» | App1 · L3354; WEB-03 · L1307; App1 · L3024; App1 › Reviews · L3742 | `ad_platform_campaigns`, `ad_platform_ads` (0077); no keyword object | **build+connector** (Google Ads keyword view on the 0077 OAuth connection). The document is silent, so confirm the scope with Tor (decision 18) |
| GRO-05 | **Bid and budget changes on ad platforms: not in the document.** What binds them: every write audited with who, what and when (Part B rule L361, A7.11); «API and connector calls run with the calling user's permissions» (A7.12); outbound rules (A7.7); approvals are settings, off by default (R5); AUT-07's action list has no ad action | Part B · L361; A7 · L196, L200-201; R5 · L65; AUT-07 · L872-876 | `marketing_budgets` and `marketing_budget_set/move` (planning inside Sentral, 0076); no write to any platform | **needs-decision** (write scopes, approval setting, limits), then **build+connector** |
| GRO-06 | Budget judged by paid customers (as GRO-01) | L3848 | `growth_budget`, `marketing_budget_*` (0076) | exists |
| GRO-07 | CMP-06 per campaign: «delivered, bounced, unsubscribed, spam reports, total and unique opens and clicks, open rate, click rate, click-through rate and top locations … A hard bounce or five soft bounces set the address to bounced» | CMP-06 · L1172-1176 | `campaign_events` kinds sent … complained, `bounce_kind`, `client_class` (0037 L199-210) | exists for campaigns |
| GRO-08 | «Opens are unreliable where mail clients prefetch images, so reports must say so» | COM-06 · L781 | `campaign_events.client_class` human / prefetch / unknown | **build**: every per-step open rate states the prefetch caveat, or counts human opens only |
| GRO-09 | Sequences: «Each enrolled record shows its current step and status: in progress, completed or failed»; SF-05 steps; AUT-09 «A history of every run with each step's result. An overview shows most failed, most active and never-run workflows and a health trend for today, 7 and 14 days» | AUT-12 · L902-906; SF-05 · L1956-1964; AUT-09 · L884-888 | `sequence_enrollments.current_ord` / `current_key`; `workflow_run_steps` (state, error) (0021) | **email per-step results: build**, provided each sent mail carries its step key. Whether 0059/0060 tag sequence mail per step was not established here |
| GRO-10 | Event catalog: Email «received, sent, opened, link_clicked, replied, send_failed»; Campaign «sent, delivered, bounced, unsubscribed, complained» | Part F › Event catalog · L2431, L2434 | `app.events`, `event_catalog` | **build** (per-step rollups read these) |
| GRO-11 | SF-19 campaign send; SF-39 «Provider events are rolled up per campaign. Insights reads the rollups» | SF-19 · L2099-2108; SF-39 · L2311-2319 | `mail-events` function, 0037 rollups | exists |
| GRO-12 | CMP-06 «top locations» | CMP-06 · L1174 | D-37: the IP is never stored | **needs-decision** (country resolved at ingest from the provider event, or omit) |
| GRO-13 | **Send-time optimisation: not in the document.** Nearest: COM-08 scheduling; CMP-05 «Send now or at a set time»; AUT-05 delays that «skip weekends»; App2 «Scheduling, A/B test on subject line»; «warm up the marketing stream gradually» | COM-08 · L790-794; CMP-05 · L1166-1170; AUT-05 · L860-864; App2 › Marketing CRM · L4033; Best practices · L4109 | campaign scheduling (0037) | **needs-decision** (method; whether it is a setting under R5). The data would be human-classified open times (GRO-08) |
| GRO-14 | «Automated sequences triggered by events (signup, trial day X, conversion, churn) — the same engine as lifecycle messaging» | App2 › Marketing CRM · L4034; L3975 | 0059 sequences on the engine | exists |
| GRO-15 | «A/B test on subject line»; CMP-09 «a comparison of two or more campaigns in one chart» | L4033; CMP-09 · L1190-1194 | `growth_experiments` (0076) | **build** (exists in part) |
| GRO-16 | Consent: «prior consent for e-mail marketing to individuals …»; «Unsubscribe link and sender identity in every marketing e-mail; one-click unsubscribe honoured immediately»; separate streams; «Suppression list across all sends»; CMP-01 footer cannot be removed; CMP-04; CMP-08 «An unauthenticated domain cannot send» | App2 › Marketing CRM › Consent · L4037-4042; CMP-01 · L1145; CMP-04 · L1160-1164; CMP-08 · L1188; D-27 | `consent_*`, `suppressions`, `sender_domains` | exists; every per-step send respects it (fixed rules by D-27) |
| GRO-17 | «SPF, DKIM and DMARC on both sending subdomains; warm up the marketing stream gradually»; «Double opt-in for newsletter signups; stop mailing contacts with no engagement for 6–12 months» | App2 › Best practices · L4109-4110 | settings `double_opt_in`, `list_hygiene`; `growth_deliverability` | exists |
| GRO-18 | Register: «Email open and click tracking — On»; «Consent and suppression checks on sales email — Off»; «Form tracking fields — On»; «Web visitor identification — On» | Part C settings register · L690-693 | `settings_registry` | exists |
| GRO-19 | Web analytics: «Build in-house and cookieless: page views go to a web_events table …, unique visitors via an IP + user-agent hash with a daily rotating salt, bot filtering … Confirm legally that this needs no consent banner»; sources; landing pages; website funnel; «Drop-off on the signup form, including failed Brønnøysund lookups»; persona cards | App2 › Web analytics · L3989-4012 | `web_*` (0066–0070), `web-collect` | exists |
| GRO-20 | Segments as saved filters; «promotion (with coupon code from Billing)»; Part B «no second discount model» | App2 › Marketing CRM · L4027, L4032; Part B · L349 | segments, `coupons` | exists |
| GRO-21 | «Build vs. buy — the contact store, segments and consent belong in Orgpuls' own database; the sending and editor can be a provider» (decided: one provider with separate streams; build the campaign editor in-house) | L4044; Open decisions · L4133-4134 | Brevo (0060, 0061) | exists |
| GRO-22 | «Metric definitions in code — MRR, activated, churned etc. defined once as SQL views versioned in git»; INS-01 «Business figures reuse the admin's SQL views, so each metric has one definition» | App2 › Best practices · L4103; INS-01 · L915 | `metric_definitions` | **build**: per-step, keyword and spend metrics defined once |
| GRO-23 | Connector duties: tokens in Vault (A7.8); outbound rules (A7.7); «Removing an integration revokes its access» (INT-11); «The connector's status and error rate are reported to the admin's integrations status» (SF-41) | A7 · L196-197; INT-11 · L1494; SF-41 · L2335 | `ad_accounts`, `ads_oauth_states`, `ads-oauth`, `ads-run` (0077) | exists; keyword and bid extensions inherit these duties |

---

## Data objects the document defines (bearing on these areas)

| Object (document name) | Source | Today in repo |
|---|---|---|
| `tickets`, `ticket_messages`, `ticket_links` (org, user, survey, invoice, problem), `ticket_events` | App2 › Ticketing · L4064 | first three exist (0012); `ticket_events` absent |
| Help-centre articles | L4090 | `help_articles`, `help_article_stats_daily` |
| Help texts and in-app announcements, versioned with rollback | L3923, L3925 | none (Orgpuls content, D-23) |
| Broadcasts (in-app banner or e-mail to a segment) | L3976 | email only (`campaigns.type = product_announcement`) |
| Feature flags, global and per org, as rows | L3791, L3984 | none (Orgpuls flags are code) |
| Feedback and NPS per org | L3978 | none |
| Support-access sessions (time-boxed, read-only, page views) | L3903-3909 | `support_access_grants` |
| Personvern request queue (30 days) | L3911 | `privacy_requests` |
| DPA acceptance per org (version, date, by whom) | L3931 | none |
| Deletion queue, export log, audit log, subprocessor register, incident register, backups | L3933-3939 | `orgs.deletions` command, `app.audit`, `subprocessors`, `security_incidents`, `ops_checks`; no export log for Orgpuls exports |
| Plan catalogue with price versions; subscription lifecycle; invoices; dunning; credits/refunds/discounts/coupons; complimentary/partner | L3947-3967 | `plan_versions`, `subscriptions`, `coupons`; invoices and dunning absent |
| Health score per org | L3850 | `health_models`, `health_scores` |
| Job monitor; integrations status; maintenance mode and status banner | L3982-3986 | `job_defs`/`job_runs`; `integration_calls`; `status_notices` |
| Part F › Platform: `entitlement`, `usage_counter`, `integration`, `installed_app`, `webhook`, `webhook_delivery`, `api_token`, `oauth_app`, `oauth_grant`, `setting`, `event`, `notification` | Part F · L2419 | all except `entitlement` / `usage_counter` (D-17: module switches plus counters) |
| Event families Usage (`limit_warning`, `limit_reached`) and Product (existing): «signup, trial day, conversion, churn, payment status, organization-level survey aggregates» | Part F › Event catalog · L2438-2439 | usage events exist; «survey aggregates» conflict with D-19 (C-02) |
| AI gateway call log (feature, user, cost) | SF-24 · L2162 | `ai_calls` |
| Marketing: `campaign`, `campaign_recipient`, `campaign_event`, `sender_domain`; Automation: `workflow_run`, `workflow_step_run`, `sequence`, `sequence_step`, `enrollment` | Part F · L2410, L2413 | exist (`campaign_*`, `workflow_*`, `sequence_enrollments`) |
| Projects (`board`, `phase`, `project`, `task`, `milestone`, `dependency`, `project_template`) | Part F · L2414 | `project_*` |
| `web_events` | App2 › Web analytics · L4010 | `web_events` |
| Settings register (every rule a setting with default) | Part C · L684-702; A9 | `settings_registry`, `setting_values` |

## Edge functions / connectors the document implies

- **Mail provider** with separate transactional and marketing streams (L4041, L4133), inbound to tickets (L4070): Brevo (0060) exists.
- **AI gateway** to one model provider under a no-training agreement, EU processing (SF-24 L2160; NFR L2561): Claude (D-07). Needed for AI answers, agent assist and Claude jobs.
- **Error tracking** filtered by org (L3985): provider unnamed.
- **Payment provider** Stripe with webhooks mirrored, EHF through the accounting system (L4104, L4124): waiting (D-22).
- **Brønnøysund** and the **SMS** provider in integrations status (L3983).
- Nothing in the document names GitHub, Vercel or the Supabase Management API as connectors. Vercel and Supabase appear only as subprocessors (L3937). Those connectors are implied by the v3 design, not by this document.

## Orgpuls commands and events the document implies (none exist today unless marked)

Registered today (local DB): `billing.*` (extend_trial, cancel, cancel_withdraw, cancellation), `orgs.*`, `modules.*` incl.
`modules.pilot`, `locales.pilot`, `legal.*`, `overrides.*`, `translations.*`, `settings.notice`, `settings.set_notice`,
`settings.set_indexing`. Events: `billing.changed`, `contact.submitted`, `counts.updated`, `demo.requested`, `logins.daily`,
`member.*`, `milestone.reached`, `org.attribution`, `org.created`, `org.deleted`, `support.requested`, `survey.round`,
`usage.daily`.

Implied and missing:
- **Rollouts**: `flags.list`, `flags.set_stage`, `flags.pilot` (PLT-01).
- **In-app announcement** to a segment (PLT-06).
- `settings.set_maintenance` (PLT-07 / SUP-28).
- **Support access**: a request command, plus `support_access.approved/denied/ended/page_viewed` events (SUP-21).
- **User actions**: `users.send_login_link`, reset MFA, change e-mail, deactivate, remove from org (SUP-22).
- **Billing**: `billing.change_plan`, `billing.suspend` / `reactivate`, `billing.set_prices`, discount and complimentary (PLT-10, PLT-13).
- `feedback.submitted` / `nps.answered` from users (SUP-27).
- **DPA**: `dpa.accepted`, and a re-acceptance prompt (SUP-33).
- A customer export command that never returns content (SUP-35).
- **Survey-invitation delivery counts** per round, if `survey.round` lacks them (SUP-24).
- `errors.daily`, count-only per org (PLT-08).
- **Retention purge report**, counts only (PLT-33).
- **Band crossing**: customer notification and confirmation (PLT-05).
- Embedding the **help widget** on signed-in pages only (SUP-08, SUP-36).

## Decisions the document leaves open for Tor

1. **Roadmap.** The document defines only build roadmaps (Part G L2511-2537, App2 Phasing L4113-4120). Decide what a product roadmap item is, who sees it (staff only, or customers), and where it comes from (Sentral rows or GitHub).
2. **Feature-request votes** are undefined (only the ticket category, L4077). Decide who votes, and whether the honest count is the number of linked tickets or organisations.
3. **Release changelog** is undefined. «Changelog» in the document is record history (L399). Decide where release notes come from and where they are published: in-app needs Orgpuls; a public page needs a public-path reason.
4. **Delivery metrics.** The document has only the S/M/L/XL sizes and «measure the real pace» (L2527). Decide which metrics, their definitions and their source.
5. **Error tracker** for «link to error tracking, filtered by org» (L3985). It is unnamed. Decide between a SaaS tracker and Orgpuls sending count-only error events.
6. **Customer portal.** App2 keeps the customer-facing admin in the product (L3783). Decide whether there is a portal, where it lives (Orgpuls or go.owntheagenda.com, D-28) and how it authenticates.
7. **Public help centre and status page** (A7.9 L198; CLAUDE.md rule 2). Decide the host, the components, who declares incidents, and the abuse-protection defaults.
8. **AI answers.** Decide the corpus (published articles only?), whether ticket text may go to Claude, whether a customer-facing answer needs agent approval, and confirm that «AI processing … in the EU» (L2561) is met.
9. **Effort score (CES)** is undefined. CSAT is «one-click» (L4087), and the repo uses 1–5.
10. **NPS.** Decide the event from Orgpuls, which users are asked, and how often (L3978).
11. **Feature flags.** Orgpuls must move rollable flags to a runtime store with stages (L3984).
12. **In-app announcements to segments** (L3976): their audiences, versioning and rollback (L3925).
13. **«Near a plan limit»** for Orgpuls bands (L3958). Decide the threshold and whether the customer is notified automatically (decided L4125: notify, the customer confirms).
14. **Stripe timing** (L4104 / L4124 versus D-22). Until it is decided, invoices, PDFs and dunning are not real.
15. **Renewals** for month-to-month plans with «no binding» (L3945): what a renewal date is.
16. **QBRs, CS playbooks and a CSM** are not in the brief (L307, L3538). Define them or leave them out.
17. **Roles.** App2 has four (L3798), D-08 seven presets, 0057 five. Also decide which actions enter «waiting for approval» when `second_admin` is on (L694, L4106, D-30).
18. **Ad keywords** (absent from the document): whether to read paid keywords from Google Ads or Microsoft Ads.
19. **Bid and budget writes** to ad platforms (absent): whether to allow them, the scopes, and an approval setting (off by default under R5).
20. **Send-time optimisation** (absent): the method, and whether it is a setting.
21. **«Top locations»** in campaign reports (CMP-06 L1174) when the IP is never stored (D-37).
22. **Interface language.** CUS-05, the NFR and D-04 say English by default, while CLAUDE.md makes `no` the source language. Confirm the display default.
23. **Help widget scope.** Confirm that Orgpuls never shows it on respondent (survey) pages (R6, LGN-05).

## Conflicts with CLAUDE.md's security rules, and other tensions

| # | Document says | CLAUDE.md / decisions say | Resolution |
|---|---|---|---|
| C-01 | «admin access is a named policy path (`is_platform_admin(role)`)» (L3809); A6 «write explicit policies» (L174) | Rule 1: RLS on, **no policy, no grant**; definer functions check `app.is_admin()` with aal2 | follow CLAUDE.md (D-09) |
| C-02 | «admins query only aggregate views that enforce n ≥ 5» (L3810); event catalog «organization-level survey aggregates» (L2439); NFR «survey data appears only as organization-level aggregates of at least 5 answers» (L2557) | The platform holds no key to any product database; rule 6 (counts, never answers or groups); D-19 (metadata only) | no survey aggregates arrive in Sentral; counts and dates only |
| C-03 | «The 5-answer threshold applies to every admin view, export and impersonation session. It is a platform constant» (L3787); support access «Inherits the 5-answer threshold» (L3908) | Orgpuls: floor 3, default 5, org threshold 3..10, frozen per round | Sentral copy must not promise «5». The session inherits the round's k inside Orgpuls |
| C-04 | Support access lets staff view the customer's app, with every page view logged (L3903-3909) | Rule 3: a product is reached only by `product-command`; rule 6 | the session is an Orgpuls session. Sentral only requests, records and receives count events, and never proxies screens |
| C-05 | Exports include «comments without identity» (L3934) | Rule 6: never «answers, groups or comments» | the export runs in Orgpuls and goes straight to the customer; Sentral logs only the command and argument names |
| C-06 | «E-mail/SMS log per org — every invitation, reminder …» (L3973) | Rule 6: invitation recipients are respondents | survey-invitation delivery as counts only; `mail-events` already drops non-Sentral events |
| C-07 | Anonymity guardrails, differencing and free-text screening (L3936, L4100-4101) | Rule 6: no groups or comments | Orgpuls-side only |
| C-08 | «groups below threshold» (L3867), «Share of groups hidden by the threshold» (L3842), «Comments posted and share answered» (L3845) | Rule 6 | counts only, sent by Orgpuls (D-21) |
| C-09 | «Tiltak: … (titles only with support access)» (L3869); Content management of the question set, tiltak library, legal references, help texts and announcements (L3915-3925) | D-23: product content stays in Orgpuls; rule 3 | visible or edited only through Orgpuls commands or sessions |
| C-10 | E-mail and SMS templates for survey invitations as admin content (L3921) | rule 3, D-23 | Orgpuls `translations.*` / `legal.*` commands only |
| C-11 | Feedback and NPS «per org» (L3978) | Rule 6, X-20 | users only, never respondents |
| C-12 | Ticketing «RLS with support/super-admin roles only» (L4064) | Rule 1 | definer functions with permission-set checks |
| C-13 | Public surfaces with tokens (A7.9 L198): help centre, status page, CSAT link, contact form, portal | Rule 2: «Do not add a public path without a reason written beside it» | each public route carries its reason (D-28 host) |
| C-14 | AI over support content (AIA-01, SF-24); tickets «can contain sensitive work-environment details» (L4092); AI processing in the EU (L2561) | Rule 6 (no payload in logs; a person's own words only); Orgpuls invariant 7 | the AI context excludes anything survey-derived, `ai_calls` logs kinds and counts only, and EU processing needs confirming |
| C-15 | «Errors — link to error tracking, filtered by org» (L3985) | Rule 6; Orgpuls invariant 7 (no respondent free text in error payloads) | read error counts per org only; never pull event bodies or breadcrumbs |
| C-16 | R8 «Never run against production» and A3.2 «Do not connect to production» (L71, L101) | CLAUDE.md › Operating: database work and deploys go through the Supabase MCP on the hosted project | process tension, not a security breach; D-02 defines a separate development project or branch |
| C-17 | «Interface language: English» (L2571), CUS-05 (L663) | CLAUDE.md: `no` is the source language | display default (D-04) versus the message source; both ship |
| C-18 | «Every admin read … is logged with who, what, when and a reason» (L3790) | D-12: the reason is a setting, off | audit always; reason optional |
| C-19 | «Tokens can be rotated and revoked at once» (A7.12 L201) | Rule 5: shared secrets only through `secret-intake`, never passed through a person; SIMPLE-PLAN «rotate API key in one click» breaks rule 5 | a product-token rotation is the owner intake flow, never a one-click secret display |
| C-20 | Widgets «never load in the survey flow» (R6, LGN-05) | Rule 6 | consistent; it binds the help widget |

## Suggested build order (from the document's own phasing, mapped to v3)

1. **Support on existing tables** (M):
   - the CSAT request worker and its public one-click page (with a reason);
   - article suggestions before a ticket;
   - ticket-to-article rate;
   - problem → known error → banner.

   This is App2 phases 2–3 (L4118-4119) and needs no Orgpuls work.
2. **Development register from existing data** (S): integrations register from `integration_catalog`, `integration_calls` and `subprocessors`; job monitor; `ai_calls` cost; `ops_checks` backups.
3. **Bugs and feature requests on tickets** (M): link tables to roadmap items and articles. Votes wait for decision 2.
4. **Platform customer success from existing data** (M): health (L3850), activation checklist (L3817-3828), CS saved views (L3861), onboarding projects (PRJ-05). Renewals wait for decision 15.
5. **Connectors** (L), all with Vault, the outbound rules, a subprocessor row each, and integrations-status reporting:
   - GitHub (roadmap, releases, gates, specs, repo rules);
   - Vercel (environments, deploys);
   - Supabase Management (advisors, backups; the cloud token returns 403, so it needs its own token through intake);
   - Claude API (AI answers, agent assist, jobs).
6. **Growth** (M, plus L for writes):
   - email per-step results, once mail carries the step key (M);
   - Google Ads keyword read on the 0077 connection (M, after decision 18);
   - bid and budget writes only after decision 19 (L).
7. **Orgpuls asks** (in the Orgpuls repo; order by value): `flags.*`, segment announcements, `settings.set_maintenance`, support-access approval events, users and billing commands, feedback/NPS, DPA, `errors.daily`. Until each exists, its Sentral control is disabled with a one-line reason.
8. **Public surfaces** (M): help centre and status page on go.owntheagenda.com, after decisions 6–7.
