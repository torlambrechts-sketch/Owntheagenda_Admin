# Sentral v3 — plan (2026-10-12)

Source: the updated Claude Design handoff «Copy of Sentral Admin platform prototype» (design-reference/sentral-simple,
commit e8a5565). Evaluation: the seven files beside this one (dev-a-gap, dev-b-gap, support-gap, platform-gap,
growth-v3-gap, docs-instructions-digest, docs-crm-digest). Rules unchanged: CLAUDE.md security rules 1–7, never fabricate,
zod at every boundary, en + no, the design's rendering recreated exactly.

## What the design adds

| Area | New | Size |
|---|---|---|
| Shell | a fifth section, **Development** · Roadmap, bugs, releases | S |
| Development | 13 tabs: Roadmap, Work board, Bug triage, Releases, Integrations register, Code and environments, Delivery metrics, Spec documents, Markdown roadmap, Claude jobs, Vercel and Supabase, Release gate, Repo rules | XL |
| Customers | third pill **Help centre and support** with 7 sub-tabs: Support results, Help widget, Help centre, Contact form and email, Customer portal, AI assist, Status and changelog | XL |
| Platform | 7 tabs instead of 3: Applications, **Rollouts and announcements**, Plans and prices, **Billing portal**, **Customer success**, Team, **Roles and approvals** | L |
| Growth | campaign detail: daily spend and signups, ads and keywords, tips; email: results per step, tips, best time to send | M |
| Repo starter kit | CLAUDE.md, roadmap files, skills, agents, hooks, workflows, .mcp.json for a product repo | S |

Every figure in the prototype is a literal or a random generator. Of roughly 400 elements judged, about half can be built
on Sentral's own data now; the rest need a connector, an Orgpuls command or event, or a decision.

## Architecture decisions (lead, 2026-10-12)

1. **Development lives in Sentral's database.** Roadmap items, work items, bugs, specs with sign-offs, releases with
   checklists and the integrations register are Sentral records, linked to the real tickets, deals, feature requests,
   funnel steps, experiments and SEO items behind them. The Markdown roadmap is *generated* from these records (view and
   download), not read from a repo. GitHub becomes optional (Tor, 2026-10-12: «can we move some from github to vercel or
   other?»).
2. **Deploys come from Vercel, pushed.** Vercel's deployment webhooks (created, succeeded, error, canceled, promoted)
   arrive at a Sentral edge function `dev-events`: HMAC checked before the body is parsed, older than five minutes refused,
   the event id makes a repeat a duplicate (rule 4's pattern). Sentral holds a webhook secret, not a Vercel token (Vercel
   tokens cannot be read-only). Roll back stays in Vercel; Sentral links to it.
3. **Build facts come from the product's CI, pushed.** A signed POST from CI to `dev-events`: sha, suite names, pass and
   fail counts, migration file names pending. No Supabase Management token for a product project: that would be a key to
   its database (the platform holds none).
4. **Claude through one gateway.** An `ai-run` edge function with the key in Vault (intake purpose `anthropic`), every call
   in `ai_calls` (0042). Inputs are Sentral records and published help articles only; survey data never exists here
   (rule 6). Ticket text is never sent (X-V3-2). Code jobs (Implement, Review PR) need GitHub and stay disabled with a
   one-line reason.
5. **Honest states.** A control whose effect does not exist yet (no Orgpuls command, no connection, no decision) is shown
   disabled with one line saying why; a value with no source is «—» or the design's empty treatment. Each is logged in
   `docs/crm-enrichment/deviations/v3-<area>.md`.

## Production defects the evaluation found (fixed first, each with a test that fails before the fix)

| ID | Where | Defect |
|---|---|---|
| F-S1 | ticket intake | Orgpuls' `contact.submitted` topic is ignored: a privacy request lands in Sales with no 30-day clock |
| F-S2 | mail inbound | an auto-reply reopens a resolved ticket |
| F-P1 | Plans and prices | `plan_accounts` matches the band label, Orgpuls sends small/usual/group: every count is 0 on real data |
| F-P2 | Applications | the Status message says «shown at the top of the app»; it reaches Orgpuls' public website only |

## Team and waves

Lead (this session): foundation migration, merges, gates, database suites, deploys, production verification. Builders
work in their own worktrees on the shared local database (SIMPLE-BRIEF rules), one migration number each; a reviewer
checks each merged wave against the security rules and the design.

| Wave | Who | Migration | Content |
|---|---|---|---|
| 0 | lead | 0078 | foundation: right scope `dev`; `feature_requests` (+ votes, links) shared by Development and Customer success; `release_notes` shared by Releases, Status and changelog and Customer success; intake purposes `anthropic`, `vercel_webhook`, `ci_webhook`; the fifth rail section and the new tab strips with honest shells; messages `simple-dev` |
| 1 | builder **dev-core** | 0079 | Roadmap (lanes, live evidence, promote), Work board (Sentral work items, sprints, points, keyboard move), Bug triage (on tickets and problems, Mark fixed via problem_resolve), Integrations register (Sentral's own), Spec documents (sections, sign-offs that lapse on edit) |
| 1 | builder **dev-delivery** | 0080 | Releases (records, checklist, changelog via release_notes), Release gate (auto rows from CI and Vercel, manual sign-offs, no deploy button), Code and environments + Delivery metrics (from `dev-events`), Vercel and Supabase (Vercel rows; Supabase rows from CI posts), Markdown roadmap (generated), Claude jobs (spec draft, task plan, release note through `ai-run`), Repo rules (the starter kit corrected to the real rules) |
| 1 | builder **support** | 0081 | F-S1, F-S2; Help centre editor on expanded `help_articles` with search; Support results from tickets and CSAT; Contact form and email channels; Status components, incidents, changelog; AI assist through `ai-run`; portal preview (read-only); widget preview and settings; CSAT one-click page as an edge function |
| 1 | builder **platform** | 0082 | F-P1, F-P2; seven tabs, Team; Roles and approvals (action registry, policies, approval queue that executes, approver ≠ requester, fresh MFA, `command_authorize` in product-command); Customer success (onboarding from usage, feature requests, renewal signals, deal and task); Rollouts and announcements (Sentral half: composer and reach, near-limit list, errors Sentral knows); Billing portal (what is real) |
| 1 | builder **growth** | 0083 | campaign daily bars and day line, ads per campaign, rule-based tips (links, not writes); Google Ads keyword import (read only, extends ads-run); email results per step, tips, best-time heatmap, send window setting (default off) |
| 2 | lead + reviewer | — | merge, gates, all SQL suites on a rebuilt database, visual walk at 1440 and 390 against the design, security review, deploy (database, functions, app), production checks |

Orgpuls (separate repository, not in this session's scope) — each Sentral control stays disabled until its command or
event exists: `flags.list` / `flags.set_stage` / `flags.daily` (percentage rollouts), `announcements.publish`,
`errors.hourly`, `platform.schema_status`, help-widget embed and `help_session_id` on `support.requested`,
`support access` grants (needs an X-entry), `billing.change_plan`, NPS, onboarding milestones.

## Defaults taken (Tor may override; each is logged)

| Question | Default |
|---|---|
| Who sees Development | new scope `dev`: Admin all; Support see + add (Bug triage); Read-only see |
| Tracker | none outside Sentral; sprints and points are Sentral records |
| Products in Development | app.products plus «Sentral» for the platform's own work |
| Votes on feature requests | staff record a request on behalf of an organisation; one vote per organisation |
| Bug targets | S1 same business day 16:00, S2 3 business days, S3 14 days (settings) |
| Release model | continuous deploys stay; a release is a named record with checklist and changelog; no deploy button |
| Staging | Preview and Production only until a staging environment exists |
| Sentry | not adopted; bug evidence is tickets and customers affected |
| Role set | Team's five (Admin, Sales, Support, Marketing, Read-only); the matrix shows those |
| Approvals | off by default (D-30); the queue exists and is switched on per action |
| Help-centre content | authored in Sentral per product; public hosting waits for a host decision (admin preview only) |
| Typed help-search questions | not stored; gaps come from tickets |
| CSAT | the design's wording, one click, after resolution; effort score not asked |
| Customer portal, support access | read-only admin preview only; the rest waits for Orgpuls |
| Ad-platform writes | none: tips link to the platform (0077's read-only stance stands) |
| Best time to send | 90 days of opens, Oslo time, at least 20 sends per cell; a sequence setting, default off |
| Billing portal | current plan per account and billing tickets; invoices, cards, dunning, discounts not shown (Orgpuls invoices by e-mail/EHF; D-22) |

## Tor's decisions (2026-10-12)

| ID | Question | Decision |
|---|---|---|
| X-V3-1 | How Sentral learns about deploys | **Vercel webhooks**, signed, pushed to `dev-events`; no Vercel token (needs a Pro or Enterprise plan; history starts at connection) |
| X-V3-2 | Claude API, Anthropic as subprocessor | **Yes, without ticket text.** Claude reads Sentral's own records and published help articles only. Support reply drafts and summaries stay disabled («Ticket text is not sent to AI») until Tor allows ticket text |
| X-V3-3 | Writes to Google Ads, LinkedIn, Meta | **No.** Tips link to the right place in the platform; 0077 stays read-only |
| X-V3-4 | Role set | **Today's five**: Admin, Sales, Support, Marketing, Read-only; the Roles matrix shows those |

The other open questions in the gap files affect later waves only and are listed there.
