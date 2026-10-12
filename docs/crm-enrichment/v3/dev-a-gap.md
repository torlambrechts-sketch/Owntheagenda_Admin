# Development section, first half — gap analysis (DevHub, 12 Oct 2026)

Design: `design-reference/sentral-simple/DevHub.dc.html` (read in full, markup and script), the shell change in
`Sentral Simple.dc.html` (fifth rail entry «Development · Roadmap, bugs, releases», `<dc-import name="DevHub">` with **no**
`product`, `go` or `tab` prop), `DevClaude.dc.html` (read in full for shared state; its five tabs are the second half's), the
repo starter kit `design-reference/sentral-simple/repo-starter/` (CLAUDE.md, README.md, roadmap/ROADMAP.md, the feature and
bug templates, OP-412 example), and `PlatformPlus.dc.html` «Feature requests» (the same votes, tickets, deals and MRR the
roadmap cards cite). Screens rendered with `scripts/visual/design-simple.mjs` into the scratchpad `v3/dev-a/` (roadmap,
roadmap-promoted, roadmap-orgpuls, roadmap-390, board, bugs, bugs-fixed, bugs-390, releases, releases-shipped, integrations,
integrations-renew, code, code-390, metrics).

Tabs evaluated here: **Roadmap · Work board · Bug triage · Releases · Integrations register · Code and environments ·
Delivery metrics**, plus the shell entry. «Spec documents» (DevHub) and «Markdown roadmap · Claude jobs · Vercel and Supabase
· Release gate · Repo rules» (DevClaude) belong to the second half (`dev-b`), but the objects proposed here are shaped so they
can share them (feature files, releases, sign-offs, integration register).

Verdicts: **build** (existing backend or a new migration here) · **build+connector** (real only after a connection built
here, credentials in Vault) · **needs-orgpuls** (an Orgpuls command, event or repo change that does not exist) ·
**needs-decision** (only Tor can decide) · **cannot** (fabricated by nature or forbidden; the honest rendering is named).

## Overview

### What the design is
A cross-product engineering cockpit: an outcome roadmap fed by customer evidence (votes, tickets, deals, funnel drop-offs),
a sprint board «synced with Linear», a bug triage list tied to tickets, Sentry and known problems, a release train with a
checklist and percentage rollout, a register of external APIs, a deploy matrix per environment, and DORA delivery metrics.
Every figure in the prototype is a literal in the script (`RM`, `BG`, `CK`, `IN`, `EN`, `dora`, `cycle`, `health`), including
constants that look computed: «Committed 34 pts», «1 S1 · 2 S2 · 2 S3» (does not change when a bug is fixed), «From 14 merged
pull requests», «Synced with Linear 2 min ago».

### What exists today
Sentral has **no development section** and no connection to GitHub, Vercel, Sentry, Linear or a Supabase Management API.
What can already feed it:

| Source | Where | Useful for |
|---|---|---|
| Tickets with category `bug` and `feature_request`; problem tickets (`type = 'problem'`, `problem_status` investigating / known_error / resolved), incidents linked by `problem_id`; organisations on tickets | 0012 `app.tickets`, `ticket_links`; `problem_resolve()` (resolves the problem, replies to every open incident, emits `problem.resolved`); `problems_open()` (0051) | Bug triage (tickets, known problem, customers affected, «Mark fixed»), roadmap evidence (tickets) |
| Status banner tied to a problem, pushed with Orgpuls `settings.set_notice` | 0044 `app.status_notices`, 0057 | «status page updated» on Mark fixed |
| Deals with value and recurring items; `app.deal_revenue(deal)` → `mrr` from recurring items | 0009 | «N deals · X kr MRR» evidence |
| Funnel step drop-offs: `growth_funnel(product, 30, step => n).stopped` | 0073 | «N signups/mo at stake · Funnel step n» |
| Growth experiments (hypothesis, ICE, stage, outcome) | 0076 `app.growth_experiments` | Promote from «Growth experiment» |
| SEO issues, content plan, opportunities | 0072 `seo_issues`, `seo_content_plan`; 0074 | Promote from «SEO» |
| Sentral's own integrations: status, connected time, last error, LinkedIn token and refresh expiry | 0021/0029/0060/0064/0073/0077 `app.integration_connections` (20 providers; `config.token_expires_at`, `refresh_expires_at`, `last_error`, `last_check_at`) | Integrations register: token expiry, state |
| Run outcomes per worker and per source | 0044 `app.job_defs`/`job_runs`; 0073 `app.growth_sync_log`; 0044 `app.integration_calls` (product-command / events calls; wired for Test connection) | Integrations register: failure rates |
| API versions Sentral pins | `_shared/ads.ts` (Google Ads REST v25, LinkedIn-Version 202609, Meta Graph v26.0), `_shared/google.ts` (webmasters v3, URL Inspection v1), `_shared/pagespeed.ts` (v5), `_shared/brevo.ts` (v3) | Integrations register: API version |
| Products with colours | 0001/0014 `app.products` (orgpuls #DCEBD3, skiftly #CFE0F5, avvik #F6D9C6, kurs #E7DAF2 — the first three are the design's chip colours) | Product filter and pills |
| Business-hours arithmetic | 0012 `app.business_add`, `business_minutes` | Bug due times |
| Help articles with `updated_at` | 0012 `app.help_articles` | Release check «Help centre articles updated» (helper count) |
| Sentral's own applied migrations | `supabase_migrations.schema_migrations` (72 rows, up to 0077) | Sentral's «migrations waiting for production» |

`app.modules` (0005) is Sentral's own module switch list, not product feature flags. The Projects module (0038: boards,
phases, items) is for customer delivery projects tied to deals; it has no estimates, sprints, PRs or CI and is not a fit for
the Work board.

### Facts the design's world does not match
- **Repositories.** Only two of the products have one: `torlambrechts-sketch/Orgpuls` and `Owntheagenda_Admin` (Sentral).
  Skiftly, Avvikspunkt and Kursrom have no repository, so no board cards, deploys, releases or PRs can exist for them.
- **How code ships.** Orgpuls has 9 PRs in its whole history (one open, #8) and no tags or releases; most work is pushed
  straight to `main`, which Vercel deploys to production (Orgpuls CLAUDE.md, playbook step 5). Sentral has **no** PRs, no tags,
  no releases. Both `package.json` say 0.1.0. There is no staging environment and no dev environment for either; Vercel
  previews exist per branch. There is no release train and no `CHANGELOG.md`.
- **Roadmap format.** Neither repo has `roadmap/` or the starter kit's files. Orgpuls records decisions in
  `docs/DECISION_LOG.md` (D-/X-entries) and `docs/DEVIATIONS.md`. The starter kit's front matter has `status` and `priority`
  but **no lane field**, so «Now / Next / Later» cannot be derived from the files alone; ROADMAP.md says it is «generated from
  front matter», and lists two Later items that have no file (no id) at all.
- **Tracker.** The board says «Synced with Linear», the starter kit and DevClaude say GitHub Issues + Projects through a
  `roadmap-sync` workflow. Nothing of either exists. Orgpuls and Sentral live in a **personal** GitHub account.
- **Feature flags.** Orgpuls' flags are code constants (`lib/flags.ts`, 22 names; `flags.signed-off.json` turns 7 on),
  on or off per deployment, with no creation date and **no percentage rollout**. «Rollout 5 %» does not exist.
- **Error tracking.** No repo uses Sentry (no SDK, no DSN). «Sentry 412 events» has no source.
- **Billing.** No product uses Stripe (D-22: «Stripe waits»). The register's Stripe row has no source.
- **People.** The design assigns work to Magnus, Eirik, Emma, Jonas; in the seed those are Support, Sales and Project staff.
  GitHub knows one human login (Tor) plus Claude sessions. A GitHub-login ↔ staff mapping does not exist.
- **Product scope.** The roadmap filter lists «Sentral» (not a row in `app.products`) and omits Kursrom (which is).

### Headline
About half of the first half can be built on Sentral's own data now: the Roadmap (outcomes with live evidence from tickets,
deals, funnel and requests), Bug triage (bugs tied to tickets and known problems, with Mark fixed through `problem_resolve`)
and the Integrations register for Sentral's own integrations. Code and environments, most of Releases and two DORA metrics
become real with a **read-only GitHub connection** (PRs, check runs and steps, Deployments that Vercel posts to GitHub,
Dependabot alerts, compare/commits, file contents). The Work board, sprints, points, release trains, percentage rollout,
Sentry, staging and coverage need Tor's decisions or Orgpuls work first; several prototype figures («Healthy», «Elite»,
«84 %», «Synced with Linear») cannot be shown as written.

---

## 0. Shell change («Sentral Simple.dc.html»)

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Rail entry «Development · Roadmap, bugs, releases», code icon `M8 8l-4 4 4 4M16 8l4 4-4 4M13.5 5l-3 14`, fifth after Platform | `go('dev')`, stored in `ss.section` | Section key, route, access right | `lib/nav.ts` has four `SECTIONS`; no `dev` route, no right | build | `SectionKey` += `dev`, `ROUTES.dev = /development` (or `/dev`), `ACCESS.dev = ['dev:see']`, `shell.section.dev` messages; the right `dev:see` (new scope, see rights) |
| Header: product name + description, «API operational» dot | Follows the application picker, although DevHub ignores the picker (no `product` prop) | `currentProduct(shell)` | Built for the other sections | build | Keep as is; the roadmap's own product filter starts at «All» (design). Decision D-DEV-04 whether the picker should preselect the filter |
| Tab strip: 13 pills wrapping (`Roadmap, Work board, Bug triage, Releases, Integrations register, Code and environments, Delivery metrics, Spec documents, Markdown roadmap, Claude jobs, Vercel and Supabase, Release gate, Repo rules`) | Local state | — | — | build | Pills as links `?tab=` (control substitution, as V-SPL-01); first 8 from DevHub, last 5 from DevClaude (dev-b) |
| Bug triage badge (orange, count) | `5 − fixed`; a bug merged as duplicate still counts | Open bugs | — | build | Count = bugs not fixed and not duplicate (the prototype's count is wrong after «Merge duplicate») |
| Toast (bottom centre, 2.4 s) | Every action toasts success | — | Toast exists in other sections | build | Only on a confirmed outcome; a queued write says «queued», never «synced» |
| Phone (390 px) | The prototype's 244 px rail never collapses, so its 390 px render is unusable (roadmap-390, code-390, bugs-390) | — | Sentral's shell already collapses the rail | build | Judge phone layout per card (see Code and environments) |

## 1. Roadmap

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Product filter chips All · Orgpuls · Skiftly · Avvikspunkt · Sentral | Filters the lanes | Product list | `app.products` (orgpuls, skiftly, avvik, kurs); no `sentral` | build | Chips from `app.products` (Kursrom appears) plus «Sentral» only if D-DEV-04 makes Sentral a roadmap product |
| Note «Roadmap = outcomes · tasks live in the tracker» | Static | — | — | build | i18n copy |
| Three lanes Now (green rule) · Next (amber) · Later (grey), count each | Items by lane; filter applied | Lane per item | Nothing | build | `app.roadmap_items.lane` (D-DEV-03: lane lives in Sentral, because the front matter has no lane field and Later items have no file) |
| Card title | Literal | Title | — | build | Typed, or the promoted source's title |
| Product pill with product colour | `PC[prod]` | Product colour | `products.color` matches three of four | build | «Sentral» colour #F3E2C9 as a token only if D-DEV-04 |
| «Goal: …» line | Literal («Visit → account +25 %») | Target outcome text | — | build | `roadmap_items.goal` (≤ 200), typed; not measured (the design does not measure it). The design has no control to set it: an inline edit is a gap filled in the design's language (D-41) |
| Evidence chip «48 votes» | Literal | Votes per request | No vote store | needs-decision | D-DEV-05 (who votes, per organisation or per person); then `feature_requests` + `feature_request_votes`, shared with PlatformPlus «Feature requests» |
| Evidence chip «6 tickets», «312 tickets/mo» | Literal | Tickets linked to the item / ticket volume of a category per 30 days | `app.tickets` (category `feature_request` exists), `ticket_links` (kinds survey, invoice, deal, lead, article) | build | `roadmap_evidence(kind 'ticket' / 'ticket_volume')`; counts computed in the read under the tickets' own visibility (`app.queue_ok`, `app.visible`) |
| Evidence chip «2 deals · 8 680 kr MRR» | Literal | Open deals linked to the item; MRR of each | `app.deals`, `app.deal_revenue(deal).mrr` | build | `roadmap_evidence(kind 'deal')`; sum only deals the viewer may see; a deal valued by hand (`value_source = 'manual'`) has no MRR → «N deals · —» |
| Evidence chips «38 signups/mo at stake», «Funnel step 4» | Literal | Sessions that stopped at step n in 30 days | `growth_funnel(product, 30, step => n).stopped` (0073) | build | `roadmap_evidence(kind 'funnel_step', ref n)`; computed with the same window; shown only to holders of a marketing reports right (as `app.require_marketing_reports()`), else omitted |
| Evidence chip «Promoted» | Added on promote | Source of the item | — | build | Name the source instead: «From feature request», «From experiment», «From SEO» |
| Progress bar «62 %» (Now lane only) | Literal per item; hidden in Next/Later | Share of tasks done | Nothing | build+connector | GitHub: `- [x]` / `- [ ]` in the linked feature file(s) (`roadmap/features/<id>-*.md`), or linked issues closed / total. No link or no connector → no bar (never 0 %) |
| ← / → buttons (move lane) | Local state; no accessible names | Lane write | — | build | `roadmap_item_move(id, lane, version)`, audited; `aria-label` «Move to Next» etc. (keyboard reachable) |
| Promote from «Feature request: Import from Visma» | Adds to Later, chip turns «✓ Import employees from Visma», toast «Added to Later with its evidence» | Request + its votes, tickets, deals | Tickets of category `feature_request` only | build | `roadmap_item_promote('feature_request', id)` copies the request's links as evidence; until the request store exists, promote a `feature_request` ticket |
| Promote from «Growth experiment: Price calculator» | Same | Experiment | `app.growth_experiments` (0076) | build | `roadmap_item_promote('experiment', id)`; product from the experiment (the prototype hard-codes Orgpuls) |
| Promote from «SEO: FAQ schema everywhere» | Same | SEO item | `seo_issues` (0072), content plan, opportunities (0074); no FAQ-schema detector | build | Candidates are real SEO issues/plan items only; «FAQ schema» is not produced by any check, so it is never offered |
| Promote row content | Three fixed chips | Candidates | — | build | The top unpromoted candidate per source (by votes, ICE score, issue severity); a source with none is left out; nothing at all → the row is hidden |
| Empty lane / no items | Not designed | — | — | build | The lane shows its header and count 0 (design's own treatment of a lane) |

## 2. Work board

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| «Sprint 41 · 6–17 Oct · day 5 of 10» | Literal | Current iteration, dates, working day | Nothing; neither repo works in sprints | needs-decision | D-DEV-01/02; then GitHub Projects Iteration field or Linear cycle (build+connector). Until then the line is omitted |
| «Committed 34 pts» | Literal constant (equals the seed's sum) | Estimates per item at iteration start | Nothing | needs-decision | D-DEV-01 (points); snapshot of points at iteration start |
| «done N pts» | Sum of cards in Rollout + Done | Estimates; which columns count as done | — | needs-decision | Points (D-DEV-01); «Rollout» counted as done is a definition Tor confirms |
| «Synced with Linear 2 min ago» | Literal | Last successful tracker sync | — | needs-decision | D-DEV-02 (Linear or GitHub); then the mirror's last sync from `dev_sync_log` («Synced with GitHub 4 min ago») |
| Seven columns Backlog · Spec · In progress · Review · Staging · Rollout · Done, coloured rule, count | Cards by `col` | Status per work item (the starter kit's status flow) | — | build+connector | GitHub Projects v2 «Status» single-select with these seven options, or front matter `status` (roadmap-sync keeps both); mirror `dev_work_items` |
| Card id (OP-412, SK-112) | Literal | Item id | — | build+connector | Front matter `id` / issue title prefix `<id>:` (starter kit convention) |
| Card kind (Story · Bug · Task · Spike) | Literal | Type | — | build+connector | Issue labels (`kind:story` …); GitHub issue types exist only for organisations |
| Card points («3 pt») | Literal | Estimate | — | needs-decision | D-DEV-01; Projects Number field «Points» or Linear estimate |
| Card title | Literal | Issue title | — | build+connector | Issue / front matter title |
| Card epic («Signup v2») | Literal | Grouping | — | build+connector | Milestone or parent issue; could also be the Sentral roadmap item it serves |
| Assignee initials | Literal | Assignee → person | No GitHub-login mapping | build+connector | `admins.github_login` (or `staff_identities`); an unmapped login shows its first two letters, an agent («claude[bot]») shows «AI» |
| PR number + CI ✓ / ✗ | Literal | Linked PR, check runs on its head | — | build+connector | PR closing/linked references; check runs (`checks:read`) |
| Bug card orange border | `kind === 'Bug'` | Kind | — | build+connector | From the kind label |
| Drag-and-drop to another column, toast «<id> → <col> · synced to Linear» | Local state, HTML5 drag only | Write the status back | — | needs-decision | D-DEV-09 (may Sentral write to the tracker). If yes: queued write (`dev_board_move` → `dev-write` worker → Projects field update), card shows «moving…» until the next sync confirms. Keyboard alternative required (status select on the card): drag-only fails «keyboard works» (DoD) |
| Horizontal scroll, columns 210 px | `overflow-x:auto` | — | — | build | As designed; works at 390 px |
| Cards from products without a repository (SK-112 Skiftly) | Literal | — | No Skiftly repo | cannot | Only connected repositories' items are shown; a product with none is absent, not empty-faked |

## 3. Bug triage

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| KPI «Open bugs 5», red above 3, sub-line «1 S1 · 2 S2 · 2 S3» | Count `5 − fixed`; sub-line literal and never updates | Open bugs by severity | — | build | `dev_bugs` where state not in (fixed, duplicate, wont_fix); sub-line computed |
| KPI «Within target 86 % · last 30 days» | Literal | Bugs fixed in 30 days; share with `fixed_at ≤ due_at` | — | build | Computed from `dev_bugs`; «—» with no fixed bug in the window |
| KPI «Escaped to production 4 · per month · goal under 3» | Literal | Bugs found in production per 30 days; the goal | — | build | `found_in = 'production'`; the goal is a setting `dev.escaped_goal` (default 3 from the design, D-DEV-06) |
| KPI «Median time to fix 1,9 days · S1 4 h · S2 2 d» | Literal | `fixed_at − created_at` per severity | — | build | Business or calendar time per D-DEV-06; «—» per severity without data |
| Header line «Severity × customers affected · targets S1 same day · S2 3 days · S3 next sprint» | Literal | Targets | — | needs-decision | D-DEV-06: targets as settings (`dev.bug_target_*`); «next sprint» needs sprints (D-DEV-01) or a day count |
| Severity chip S1 / S2 / S3 (design's three colour pairs) | Literal | Severity | Tickets have impact × urgency → priority, not severity | build | `dev_bugs.severity`; suggested from the linked tickets' priority (urgent → S1) but set by a person |
| Title | Literal | Title | — | build | Typed or from the problem ticket's subject (staff-written) |
| Due label «Due today 16:00» / «2 days left» / «3 days left» / «Next sprint»; red for S1, amber else; «Fixed» green | Literal | Due time from the target | `app.business_add` | build | `due_at` set on create and severity change; «Next sprint» only with sprints |
| Link chip «3 tickets» / «1 ticket» | Literal | Incident tickets linked | `tickets.problem_id`, ticket categories | build | Tickets attached to the bug's known problem plus `dev_bug_tickets`; counted under the tickets' visibility |
| Link chip «Sentry 412 events» | Literal | Events per Sentry issue | No product uses Sentry | needs-decision | D-DEV-11 (adopt Sentry in Orgpuls, with scrubbing); then a read-only Sentry connector, counts only |
| Link chip «Known problem T-2316», «Problem T-2329» | Literal | Problem ticket | `tickets.type = 'problem'`, `problem_status`, number from 2300 | build | `dev_bugs.problem_id`; label from `problem_status` (known_error → «Known problem», investigating → «Problem») |
| Link chip «3 customers» | Literal | Distinct organisations behind the linked tickets | `tickets.organization_id` | build | Count only, never names in this list |
| Link chip «Found internally» | Literal | Source | — | build | `dev_bugs.source = 'internal'` (also sets `found_in = 'internal'`) |
| State «Assigned Magnus · PR #888 in review» | Literal | Assignee; linked PR state | — | build+connector | Assignee is a Sentral staff member (build); PR state from GitHub (connector). Without the connector: «Assigned Magnus» only |
| State «Assigned Magnus · CI failing on PR #212» | Literal | Check runs on the PR head | — | build+connector | GitHub check runs |
| State «Duplicate of OP-427?» | Literal suggestion | A duplicate guess | — | needs-decision | D-DEV-12: an AI duplicate suggestion (Claude API over bug titles only) or none; until then no suggestion text |
| Button «Merge duplicate» | Sets the row to «Merged into OP-427» (target hard-coded) | Target bug | — | build | `dev_bug_merge(keep, duplicate)`: a target select (gap in the design), tickets move to the kept bug, the duplicate is closed; GitHub issue closed as duplicate only with D-DEV-09 |
| Button «Mark fixed» → «Fixed in v2.15.0 · tickets resolved, known problem closed, status page updated», toast «Fixed · 3 tickets notified» | Local state | Resolve problem, reply to incidents, clear banner | `problem_resolve(problem, body)` replies to each open incident and resolves it; a linked `status_notices` row is cleared and `settings.set_notice` exists | build | `dev_bug_fixed(id, reply)` → `problem_resolve` (needs `tickets:edit_others`), banner cleared through product-command. «in v2.15.0» only with releases (D-DEV-07), else the date and production commit when known. «N tickets notified» = replies queued; they are e-mailed only while Brevo is connected, and the toast says which. Confirm step: «Customers will be told it is fixed» (see risk R-10) |
| Fixed row background #F2F7EF, actions removed | Local state | — | — | build | As designed |
| How a bug enters the list | Not in the design | Intake | Tickets and problems exist | build | «Create bug» from a problem/bug ticket (Customers › Tickets) and a small «New bug» form here (gap filled in the design's language, D-41); never from Sentry payloads |

## 4. Releases

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Title «Orgpuls v2.15.0» (Playfair 20) | Literal | Release name / version | No tags, no versions (0.1.0) | needs-decision | D-DEV-07: versioned releases or not; if yes, tag names `vX.Y.Z` |
| «Release train · Thu 15 Oct» | Literal | Planned date | Continuous deploy from `main` | needs-decision | D-DEV-07 |
| «Release checklist · 5 of 8» | Count of ticked items | Items and states | — | build | Computed from auto results and sign-offs |
| «Tests pass (unit, integration, end-to-end)» · auto · CI | Toggle (prototype lets you untick) | CI result on the release commit | Orgpuls CI job «checks, security invariants and screens» (unit tests, i18n, db lint, security audit, build, smoke); Sentral CI `gates` and `database` | build+connector | GitHub check runs on `to_sha` (read-only) |
| «Database migrations reviewed and reversible» · auto · Supabase | Toggle | Migrations in the release; review | Orgpuls migrations are forward-only by rule («superseded, never edited»; set aside instead of DROP); no Management API access to Orgpuls (forbidden, R-3) | needs-decision | D-DEV-08: «reversible» contradicts the products' own migration rules; propose «Migrations reviewed» as a **named sign-off**, listing the migration files in the release from GitHub compare |
| «Security scan has no high findings» · auto · Snyk | Toggle | Open high/critical advisories | No Snyk | build+connector | Dependabot alerts (severity high/critical, state open) on the release's repo; label «auto · Dependabot» |
| «New code behind a feature flag» · manual | Toggle | Sign-off | — | build | `dev_release_signoffs` (named person, time); `flags.list` could make it a helper later (needs-orgpuls) |
| «Anonymity check: no new path to survey data» · manual | Toggle | Sign-off | Orgpuls CI step «Security invariants» (respondent_invariants.sql) | build | Named sign-off; beside it the CI step's conclusion from the Actions jobs API (connector) as evidence, never as the sign-off |
| «Rollback plan written» · manual | Toggle | Sign-off (+ text) | — | build | Sign-off with a short text field |
| «Help centre articles updated» · manual | Toggle | Sign-off | `help_articles.updated_at` | build | Sign-off; helper «N articles updated since the last release» |
| «Release note written» · manual | Toggle | Notes present | — | build | Ticked when the release has notes (from the changelog card), not by hand |
| «auto · CI» / «manual» tags | Literal | Kind per item | — | build | From the item definition |
| Ticking an auto item by hand | Allowed in the prototype | — | — | cannot | An auto item shows its source's result and is read-only; «—» when the source is not connected |
| Button «Complete the checklist to release» (disabled, 50 %) → «Release and start rollout» → «✓ Released · rolling out to 5 %», toast «Released · changelog published · rollout started at 5 %» | Local state | Release action; rollout percentage | Orgpuls flags are on/off per deployment; push to `main` already deployed the code | needs-orgpuls | Percentage rollout needs Orgpuls support (`flags.set_rollout`) and D-DEV-07. Honest button: «Record release» (stores the release, publishes notes per D-DEV-13, creates a GitHub Release only with D-DEV-09), no rollout claim |
| Card «Generated changelog · From 14 merged pull requests · edit before publishing» | Literal | Merged PRs / commits since the previous release | Orgpuls: mostly direct commits; Sentral: commits only | build+connector | GitHub compare `from_sha…to_sha`: merged PRs, else commit subjects; the count says which («From 23 commits») |
| Changelog lines with kind chips New / Improved / Fixed | Literal | Classification and customer wording | — | build+connector | Kind from PR labels or a commit prefix; text editable (the design says «edit before publishing» but has no editor: inline edit, gap per D-41); engineering text is a draft, not customer copy |
| Publishing the changelog | Implied by the toast | Destination | PlatformPlus has a changelog/announcements idea; Orgpuls has no changelog page | needs-decision | D-DEV-13: where customers read it, in which languages (no/en), who approves |
| «Recent releases»: name, date, «N PRs» | Literal | Past releases | None exist | build+connector | GitHub releases/tags after D-DEV-07; with continuous deploy the honest list is production deploys by day |
| «Healthy» / «Rolled back once» (green / amber) | Literal | Post-release health | No definition | build+connector | Rollbacks counted from production deployments (GitHub Deployments; Vercel rollbacks may not post one, R-2); wording «No rollback» / «Rolled back 1×», never «Healthy» (no health measure exists) |
| Skiftly v1.9.3, Avvikspunkt v1.3.1 | Literal | — | No repositories | cannot | Not shown |

## 5. Integrations register

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Card «Integrations register · Every external API we depend on» | Static | — | — | build | Copy |
| The rows (which integrations) | Eight literal rows | A register | `integration_connections` holds Sentral's 20 providers (4 connected locally: google_ads, meta_ads, search_console, and LinkedIn configurable) | build | `app.dev_integrations`, seeded with what Sentral really calls: Search Console (+ URL Inspection), PageSpeed Insights, Google Ads, LinkedIn Ads, Meta Ads, Brevo (email), Claude API (`ai`, not connected), Orgpuls product API (product-command). Product-side dependencies typed by hand (D-DEV-15) |
| Name + use line | Literal | Name, use | — | build | Register columns; i18n for Sentral's own rows |
| Owner | Literal (Tor, Sara, Jonas, Ingrid, Magnus) | Responsible person | — | build | `owner_id` → staff; set in a small edit |
| API version (monospace) | Literal | Version pinned | Constants in `_shared/*.ts` | build | A version registry in code returned by the read and asserted equal to the constants by a test (as `product_commands` mirrors `_shared/orgpuls.ts`); Orgpuls: `installations.api_version` from the ping |
| Errors % (red above 1 %) — Sentral's own integrations | Literal | Failed calls or runs ÷ all, 30 days | `job_runs` (state per job), `growth_sync_log` (ok/warning/failed per source), `integration_calls` (product calls), `config.last_error` | build | Computed per integration from its own log; the header says «Failed runs, 30 days» where the unit is a run, not a call; «—» with no runs |
| Errors % — product-side dependencies (Brønnøysund in Orgpuls' signup `lib/brreg/lookup.ts`, Orgpuls' own mail, Skiftly calendar sync) | Literal | The product's own call counts | Nothing reported | needs-orgpuls | Event `integrations.daily` (counts only); Skiftly does not exist → no row |
| Token expires («in 6 days» red under 10 days, «—») | Literal | Expiry | LinkedIn `token_expires_at` / `refresh_expires_at`; service-account keys and the Brevo key do not expire → «—» | build | Read from `integration_connections.config` |
| Upcoming change («v18 sunset 27 Jan — upgrade to v20», «None», «None announced») | Literal | Provider deprecations | No API announces them | build | Typed record (text, due date, link) per integration; «None» only when someone recorded it, else «—» |
| CTA «Renew token» | Toast «Task created on the work board for <owner>» (same as Plan upgrade) | — | LinkedIn OAuth connect exists (0077 `ads_oauth_start`) | build | Links to Growth › Integrations' LinkedIn reconnect (the real renew), not a task |
| CTA «Plan upgrade» → «✓ Planned» | Toast «Task created on the work board for <owner>» | A work item | — | build+connector | Creates a GitHub issue (Issues write, D-DEV-09); without it, a Sentral-side planned flag with the owner and date («Planned by Tor, 12 Oct») and no claim of a board task |
| CTA «—» (an empty outlined button) | Clickable, does nothing | — | — | build | Nothing rendered (deviation: a button that does nothing is a fake control) |
| Colour rules (errors > 1 % red, token < 10 days red, change amber) | `parseFloat`, regex `/in [0-9] days/` | — | — | build | Same thresholds as stated rules (`days < 10`) |
| Rows «Stripe — billing and invoices» and «Sentry — error tracking» | Literal | — | Neither is used anywhere (D-22) | cannot | Not listed until used |
| Table min-width 860 px inside horizontal scroll | `overflow-x:auto` | — | — | build | As designed |

## 6. Code and environments

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Card «Deploys per environment · Vercel · Supabase · GitHub Actions» | Static | — | — | build+connector | Subtitle names only connected sources |
| Rows per app (Orgpuls, Skiftly, Avvikspunkt, Sentral admin) | Literal | Connected repos | None | build+connector | Orgpuls and Sentral via `dev_repos`; Skiftly, Avvikspunkt, Kursrom have no repo → not listed |
| Production cell: dot + short sha + «1 Oct» | Literal | Latest production deployment | — | build+connector | GitHub Deployments that Vercel's Git integration creates (environment «Production – <project>», `sha`, statuses, `environment_url`): no Vercel token needed (R-2) |
| Dev and Staging columns | Literal | Those environments | Neither product has dev or staging | needs-decision | D-DEV-10; until then the columns read «Preview» (latest preview deployment) and «Staging —» with «not set up» |
| Status dot colours (green / amber / red) | Literal | Deployment state | — | build | success → green, in progress → amber, failure/error → red |
| «Open pull requests · Preview link per PR»: «#888 Retry policy…», «Magnus · 2 approvals · CI ✓», «waiting for review 2 days» | Literal | Open PRs, reviews, check runs, requested reviewers | — | build+connector | GitHub pulls + reviews + check runs; author via the login mapping. Orgpuls has one open PR (#8), Sentral none: the honest list is short or empty («No open pull requests») |
| «Preview →» link (`href="#"`) | Dead link | Preview URL | — | build+connector | `environment_url` of the PR head's preview deployment; no URL → no link |
| «1 high: next.js image optimizer advisory · Dependabot PR #890 ready · auto-merge after CI» | Literal | Open high/critical alerts; Dependabot PRs and their auto-merge state | — | build+connector | Dependabot alerts (free for private repos once enabled; verify enabled) + PRs by `dependabot[bot]` with `auto_merge` |
| «6 moderate dependency updates · Grouped weekly PR» | Literal | Moderate alerts / open Dependabot PRs | No `dependabot.yml` in either repo | build+connector | Counts from alerts; «grouped weekly» only if the repo configures grouping (repo work) |
| «2 database migrations waiting for production» — Sentral | Literal file names | Repo migration files vs applied | Own `supabase_migrations.schema_migrations` (readable by a definer function) | build+connector | File list of `supabase/migrations/` on `main` (GitHub contents) minus applied versions |
| «… waiting for production» — Orgpuls | Literal | Orgpuls' applied migrations | Nothing; a Management API token for Orgpuls would be a key to its database | needs-orgpuls | `platform.version` command (latest applied migration) |
| «Secrets scan clean · No credentials in the repository» | Literal | Secret scanning alerts | Personal private repos: secret scanning needs paid Secret Protection (verify) | needs-decision | D-DEV-14 (enable/buy, or move repos to an organisation); else «—, not available for these repositories» |
| «Row-level security tests pass · Includes the anonymity firewall tests» | Literal | CI step result on `main` | Orgpuls step «Security invariants»; Sentral job `database` | build+connector | Actions jobs API, step conclusions, latest `main` run |
| Phone width | Deploy grid (name + 3 × min 130 px) has no scroll wrapper and overflows at 390 px (code-390) | — | — | build | Horizontal scroll wrapper around the deploy table (deviation); the PR and security cards stack |

## 7. Delivery metrics

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| «Deploy frequency 4,2 / day · production deploys, all apps» | Literal | Production deployments per day, 30 days | — | build+connector | Count of successful production Deployments ÷ days, Orgpuls + Sentral |
| «Lead time for changes 1,6 days · commit → production» | Literal | Commit time → its first production deployment | — | build+connector | GitHub compare between consecutive production shas; median of (deploy time − commit time) |
| «Change failure rate 6 % · deploys needing rollback or fix» | Literal | Failed deploys ÷ deploys | — | needs-decision | D-DEV-12 definition (rollback, revert commit, or a fix within 24 h); then build+connector |
| «Time to restore 48 min · median in 90 days» | Literal | Failure start → restored | Problem tickets (created → resolved), status notices | needs-decision | D-DEV-12 (what a failure is: S1 bug / problem ticket, or a failed deploy → next good one) |
| Level badges Elite / High / Medium | Literal | Benchmark bands | — | needs-decision | D-DEV-12: name the benchmark (a DORA report year) and keep its bands as data with the source, or leave badges out |
| Sub-lines («production deploys, all apps», «commit → production», …) | Static | — | — | build | Copy matching the real definition |
| «Where time goes · median cycle time»: Coding, Waiting for review, In review (bar + legend in days) | Literal widths | PR timeline: first commit → opened → first review → merged | — | build+connector | Pull request timeline; with few PRs (Orgpuls 9 in total, Sentral 0) the segments read «—» and the bar is not drawn rather than drawn from noise |
| Segments «Staging and QA», «Rollout» | Literal | Merge → staging → 100 % | No staging, no percentage rollout | needs-decision | D-DEV-10 and the rollout question (needs-orgpuls); until then «—» |
| Health «Bugs escaped to production 4 / month» | Literal | Bugs found in production / 30 days | — | build | From `dev_bugs` (same as the Bug triage KPI) |
| Health «Feature flags 23 · 5 older than 90 days» | Literal | Flag names and age | Code constants without dates | needs-orgpuls | `flags.list` (names, on in production, since) |
| Health «Capacity vs planned 34 / 38 pts» | Literal | Capacity and committed points | — | needs-decision | Sprints, points and capacity (D-DEV-01) |
| Health «Unplanned work 18 %» | Literal | Items added after iteration start ÷ all | — | needs-decision | D-DEV-01 and its definition |
| Health «Test coverage (critical paths) 84 %» | Literal | A coverage report | Neither repo produces coverage | cannot | «—» until a product's CI publishes coverage (repo work, then readable as a CI artifact or check) |
| Value colours (green / amber / red) | Literal | Thresholds | — | build | Stated rules beside the value (e.g. escaped vs the goal setting) |

---

## Proposed database objects

One migration for the Sentral-only part (number assigned by the planner; 0078 is the next free) and one for the mirrors when
the GitHub connector is built. Every table in `app`, RLS on, no policy, `revoke all … from public, anon, authenticated`, in
the same migration as its table; every public function SECURITY DEFINER, `set search_path = ''`, asks `app.require('dev', …)`
(which includes `app.is_admin()`'s aal2 rule), revoked from public/anon, granted to authenticated; writes volatile, audited with
`app.log` (field names, never values); SQL assertions in a new `supabase/tests/dev_invariants.sql`.

### Rights
- `app.right_ok` (redefined from 0012): scope list += `dev`. Rights used: `dev:see`, `dev:add`, `dev:edit_others`,
  `dev:configure`.
- Permission sets (D-DEV-16): Admin += all four; Read-only += `dev:see`; Support += `dev:see`, `dev:add` (to file and triage
  bugs) — proposal only.
- Evidence inside a roadmap read respects the source's own rights: deal sums use `app.visible` on deals the caller can see;
  funnel counts require `app.require_marketing_reports()`; ticket counts use `app.queue_ok` + `app.visible`. A caller without
  the right gets the chip omitted, not a total that leaks.

### Tables (Sentral data, no connector)
| Table | Columns (essentials) | Written by | Read by |
|---|---|---|---|
| `app.roadmap_items` | id, ref (`^[A-Z]{2,5}-[0-9]{1,6}$`, unique, null), product (product key, or `sentral` per D-DEV-04), title 1..200, goal ≤ 200, lane now/next/later, ord, source_kind, source_ref, feature_paths text[] (repo paths of linked feature files), created_by/at, updated_at, archived_at, version | `roadmap_item_add/set/move/promote/archive` | `dev_roadmap` |
| `app.roadmap_evidence` | item_id → roadmap_items cascade, kind (feature_request, ticket, ticket_volume, deal, funnel_step, experiment, seo_issue, seo_plan), ref, added_by, added_at; PK (item_id, kind, ref). **No stored figures**: counts and MRR are computed in the read | `roadmap_evidence_link`, promote | `dev_roadmap` |
| `app.feature_requests`, `app.feature_request_votes`, `app.feature_request_links` | request: product, title, status (under_review, planned, in_progress, shipped, not_planned), roadmap_item_id; vote: request, organization_id, person_id null, source (staff, product), voted_by, at, unique per D-DEV-05; link: tickets and deals | Platform section (PlatformPlus «Feature requests») and promote | Roadmap evidence. **Shared with the Platform evaluator; one definition, built once** |
| `app.dev_bugs` | id, ref (`BUG-n` from a sequence), product, title, severity S1/S2/S3, source (ticket, sentry, internal), found_in (production, internal), problem_id → tickets (type problem) set null, assignee_id → admins set null, due_at, state (open, in_progress, fixed, duplicate, wont_fix), duplicate_of → self, fixed_at, fixed_by, fixed_ref (sha or release id), github_issue int, pr_number int, sentry_issue text (id only), created_by/at, updated_at, version | `dev_bug_create/set/merge/fixed` | `dev_bugs`, `dev_metrics`, badge |
| `app.dev_bug_tickets` | bug_id, ticket_id, linked_by, linked_at; PK | `dev_bug_link` | counts (tickets, customers) |
| `app.dev_integrations` | key, name, use_text, product null, owner_id, connection (integration_connections.provider) null, job_key (job_defs.key) null, sync_source (growth_sync_log.source) null, change_text ≤ 200, change_due_on, change_url, planned_at, planned_by, updated_* | `dev_integration_set`, `dev_integration_plan` | `dev_integrations` |
| `app.dev_releases`, `app.dev_release_signoffs` | release: product, name/tag, planned_on, from_sha, to_sha, notes jsonb `[{kind, text}]`, state planned/released, released_at/by, github_release_id; sign-off: release_id, item_key, signed_by, signed_at, note | `dev_release_add/sign/notes_set/record` | `dev_releases` (shared with Release gate, dev-b) |
| Settings rows (`settings_registry`, scope platform) | `dev.bug_target_s1`, `dev.bug_target_s2_days`, `dev.bug_target_s3_days`, `dev.escaped_goal` (defaults from the design) | Settings | due times, KPIs |
| `admins.github_login` (or `app.staff_identities(provider, login, staff_id)`) | unique login | Team / profile | board, PRs, bugs |

### Tables (mirrors of connected sources; written only by `worker_*` functions under the service role)
`app.dev_repos` (product, owner, name, default_branch, last_sync_at, last_error code), `app.dev_pulls` (number, title,
author_login, state, draft, created/merged/first_review_at, approvals, head_sha, merge_sha, labels, auto_merge, ci_state),
`app.dev_checks` (sha, workflow, job, step, conclusion, completed_at), `app.dev_deployments` (repo, environment, sha, state,
created_at, ready_at, environment_url, is_production), `app.dev_alerts` (Dependabot: ecosystem, severity, state, package,
advisory id, created/fixed_at; never code excerpts), `app.dev_refs` (tags, releases), `app.dev_roadmap_files` (path,
front matter validated to the starter kit's keys and enums, tasks_done, tasks_total, commit_sha, committed_at),
`app.dev_migration_files` (repo, version, name), `app.dev_work_items` + `app.dev_iterations` (tracker, after D-DEV-02),
`app.dev_sync_log` (source, at, rows, state ok/warning/failed, code; as `growth_sync_log`). Rows hold names, numbers, states and
times only.

### RPCs
Reads: `dev_roadmap(p_product)`, `dev_board(p_product)`, `dev_bugs(p_product)`, `dev_releases(p_product)`,
`dev_integrations()`, `dev_code()`, `dev_metrics(p_days)`, `dev_shell_badge()` (open bugs).
Writes: `roadmap_item_add`, `roadmap_item_set`, `roadmap_item_move(id, lane, ord, version)`, `roadmap_item_promote(kind, ref)`,
`roadmap_item_archive`, `roadmap_evidence_link(item, kind, ref, on)`; `dev_bug_create(values)` (from a ticket or typed),
`dev_bug_set`, `dev_bug_link(bug, ticket, on)`, `dev_bug_merge(keep, duplicate)`, `dev_bug_fixed(id, reply)` (calls
`problem_resolve` under `tickets:edit_others`; queues the banner clear through product-command); `dev_release_add`,
`dev_release_sign(release, item, on)`, `dev_release_notes_set`, `dev_release_record`; `dev_integration_set`,
`dev_integration_plan`; `dev_board_move(item, status)` (queues only); `dev_intake(provider)` (owner, fresh second factor, opens
a one-time intake number for `github` / `sentry`); `dev_disconnect(provider)`.
Workers (service role only, never granted to authenticated): `worker_dev_targets()`, `worker_dev_sync(source, kind, rows)`
per mirror (validates every field, caps sizes), `worker_dev_write_result(...)`, `app.dev_tick()` (cron, `job_defs` key
`dev_sync`, quiet).

## Proposed edge functions and connectors

| Function | Does | Credentials | Notes |
|---|---|---|---|
| `dev-sync` + `_shared/github.ts` (Node-testable like `ads.ts`) | Every 15 min (cron through `app.dev_tick`, `x-worker-key` from Vault) and on «Sync now»: per connected repo reads PRs + reviews, check runs and Actions job steps for `main` and PR heads, Deployments + statuses (Vercel's), Dependabot alerts, tags/releases, compare between release shas, `roadmap/**` front matter and task counts, `supabase/migrations/` file names. Writes mirrors through `worker_dev_sync`; logs counts and status codes only | GitHub App (app id + private key in Vault, installed on the two repos) with **read** permissions: metadata, contents, pull requests, checks, actions, deployments, Dependabot alerts. Arrives through `secret-intake` (new purpose `github`, `intake_nonces.purpose` check extended, `store_product_secrets` branch) | Read-only first. Never stores file bodies beyond parsed front matter and task counts |
| `dev-sync` (tracker part) | Projects v2 iteration, Status, Points, assignees — or Linear cycles/estimates | Per D-DEV-02. **Verify:** Projects owned by a personal account are not reachable by a GitHub App or a fine-grained token; only a classic token with `project` (+ `repo`) scope, which is all-repos write (R-6). Linear: an API key, read | After decisions |
| `dev-write` (queue `dev_write`, pgmq) | Applies writes the screen queued: move a Projects item, create an issue («Plan upgrade»), close an issue as duplicate, create a GitHub Release with notes. Each audited with argument names | Issues: write; Projects: write; Contents: write only for releases/tags | Only after D-DEV-09; never Contents write for code, never Actions dispatch, never Vercel promote/rollback |
| `github-events` (optional) | Webhook receiver for freshness: HMAC `X-Hub-Signature-256` checked before the body is parsed; `X-GitHub-Delivery` as the duplicate key; the body only names what to re-fetch | Webhook secret in Vault | GitHub sends no signed timestamp, so the five-minute rule is replaced by delivery-id dedupe and re-fetching through the API |
| Sentry (part of `dev-sync`) | Issue id, level, event count, users count, first/last seen for the issues linked to bugs | Sentry token (`event:read`, `project:read`) through intake purpose `sentry` | Only after D-DEV-11. Never titles, messages, stack frames or event payloads (R-4) |
| Vercel API | — | — | **Not proposed** (R-2): deployments come from GitHub Deployments |

## Orgpuls commands and events needed

| Need | Kind | Scope / payload | For |
|---|---|---|---|
| `platform.version` | command | `platform:read` → `{commit_sha, deployed_at, latest_migration, app_version}` | Orgpuls «migrations waiting for production», release checks, cross-check of production sha |
| `flags.list` | command | `flags:read` → `[{name, on_in_production, signed_off_on}]` from `lib/flags.ts` + `flags.signed-off.json` (dates from DECISION_LOG) | Health «Feature flags», release item «behind a flag» helper |
| `integrations.daily` | event | `{day, provider, calls, failures, p95_ms}` for brreg, mail, entra, slack, teams — counts only | Integrations register rows for product-side dependencies |
| Percentage rollout + `flags.set_rollout` | product feature + command | `flags:write` | «Rollout 5 %», «Prod + flag 5 %» (only if D-DEV-07 wants it) |
| `feedback.voted` / `feature.requested` | event | organisation, request key, at — no free text | Customer votes, if D-DEV-05 lets customers vote in the product |
| Repo work in Orgpuls (not commands) | repo | `roadmap/` with the starter kit's front matter (+ a lane field if D-DEV-03 chooses files), kind labels, `dependabot.yml` with grouping, CI coverage output, Sentry SDK with scrubbing (if adopted), `roadmap-sync` workflow (if GitHub Projects) | Board, progress, security rows, coverage, Sentry |

## Product decisions for Tor

| ID | Decision | Why it matters | Recommendation |
|---|---|---|---|
| D-DEV-01 | Is Development for Tor + Claude sessions, or for a team with sprints, story points and capacity? | Sprint line, committed/done points, capacity, unplanned work, «S3 next sprint» | Without a team: no sprints or points; the board shows status columns only |
| D-DEV-02 | The tracker: GitHub Issues + Projects (starter kit), Linear (board copy), or none | Every board element and its credentials | GitHub; if Projects is needed, move the repos to a GitHub organisation (see R-6) |
| D-DEV-03 | Where an outcome's lane lives: in Sentral (`roadmap_items`) or in a new front-matter field in the repo | The front matter has no lane; Later items have no file; one outcome spans several files (OP-412 + OP-418) | Sentral; feature files linked to outcomes |
| D-DEV-04 | Is «Sentral» a roadmap product (it is not in `app.products`)? Is Kursrom in the filter? Should the application picker preselect the filter? | Filter chips, colours | Sentral yes (roadmap-only value), Kursrom yes (it exists), picker does not filter (design) |
| D-DEV-05 | Votes: staff on behalf of customers, or customers in the product / help centre; one per organisation or per person | Evidence «N votes», PlatformPlus «Feature requests» | Staff-recorded, one per organisation, until a product event exists |
| D-DEV-06 | Bug targets (S1 same day by 16:00, S2 3 days, S3 next sprint), business or calendar time, the escaped-bug goal (< 3/month), what «escaped» means | Due labels, KPIs | Business time; S3 = 10 business days without sprints; escaped = found_in production |
| D-DEV-07 | Release model: continuous deploy (today) or versioned release trains; what «Release» does; percentage rollout | Releases tab, Recent releases, «Fixed in v…», rollout | Versioned releases as records + GitHub Release; no rollout claim until Orgpuls has it |
| D-DEV-08 | Checklist content: «reversible migrations» contradicts the products' forward-only rule; Snyk vs Dependabot; which items need which role's sign-off | Release checklist | «Migrations reviewed» (sign-off); Dependabot; anonymity sign-off by the owner |
| D-DEV-09 | May Sentral write to GitHub (issues, project fields, releases) at all? Never code, never workflows? | Board drag, Plan upgrade, Merge duplicate, Release | Read-only first; then issues + project fields only |
| D-DEV-10 | Environments: introduce staging (Vercel custom environment + a second Supabase project) or show Preview / Production only | Dev/Staging columns, cycle segments | Preview / Production only |
| D-DEV-11 | Adopt Sentry in Orgpuls (with scrubbing), and may Sentral show issue titles | Sentry chips, triage | Adopt; counts only in Sentral |
| D-DEV-12 | Metric definitions: change failure, time to restore, DORA benchmark for badges; AI duplicate suggestions | Delivery metrics, «Duplicate of …?» | Define failure = rollback or revert within 24 h; restore = S1 bug open → fixed; badges left out; no AI suggestion for now |
| D-DEV-13 | Where the customer changelog is published, in which languages, who approves | Changelog card, «changelog published» | With PlatformPlus' announcements, no + en, the release owner approves |
| D-DEV-14 | Secret scanning on private repos (paid) or not | «Secrets scan clean» row | Leave the row out until available |
| D-DEV-15 | Owners per integration; register product-side dependencies by hand until `integrations.daily` exists | Integrations register | Yes, typed rows with «—» errors |
| D-DEV-16 | Who sees Development (new `dev` scope): Admin only, Support for Bug triage, Read-only? | Rail entry, writes | Admin all; Support see + add; Read-only see |

## Risks against the security rules

| ID | Rule | Risk | Mitigation |
|---|---|---|---|
| R-1 | 3 (a product is reached only by product-command) | A GitHub credential with Contents or Actions write can push to `main`, which Vercel deploys to Orgpuls production: a path that changes the product outside product-command | Read-only GitHub App; writes limited to issues/project fields/releases by D-DEV-09; no Contents write for code, no workflow dispatch; every write queued and audited with argument names |
| R-2 | Opening paragraph («holds no key to any product's database»), 3 and 5 | A Vercel token reads decrypted environment variables of the Orgpuls project (its Supabase service role key and token secret) and can promote/roll back production | No Vercel token; deployments from GitHub Deployments. Rollbacks that post no GitHub deployment stay unknown («—») |
| R-3 | Same | A Supabase Management API token for Orgpuls is administrative access to its database | Never; Orgpuls reports its migration state through `platform.version` |
| R-4 | 6 (no respondent data) | Sentry events, exception messages and breadcrumbs can carry respondent free text despite Orgpuls' invariant 7; issue titles too | Store and show Sentry ids and counts only; never messages, titles, frames or payloads; never feed them to the Claude API |
| R-5 | 6 and D-24 (erasure) | Bug files and issues created from tickets would copy customers' words and names into git history, which cannot be erased | Bug files and issues carry Sentral references only (BUG-n, T-numbers, counts); the starter kit's `/triage` skill must not paste ticket text |
| R-6 | 5 (secrets) and least privilege | Projects v2 on a personal account needs a classic token with `repo` scope (write to every private repo) | Prefer a GitHub organisation + GitHub App; else no Projects board. Every credential arrives through `secret-intake` with a one-time number, lives in Vault, is read only by the worker through `product_secret` |
| R-7 | 4 (events: signature before parse, five minutes, duplicates) | GitHub webhooks are not product events but are inbound; GitHub sends no signed timestamp | HMAC before parse, delivery-id dedupe, payload used only as «what to re-fetch» |
| R-8 | 1 (no client reads a table) and visibility | The roadmap would sum deal values and funnel counts for people without those rights | Evidence computed inside the definer read under each source's own right; omitted otherwise; tested per role |
| R-9 | Never fabricate | «Healthy», «Elite», «Synced with Linear», «Fixed in v2.15.0», «rolling out to 5 %», «3 tickets notified», «Committed 34 pts» | Each shown only from a real source with its real wording; «—» or omitted otherwise (deviations V-DEV-xx) |
| R-10 | Never fabricate (to customers) | «Mark fixed» replies to every incident ticket; done before the fix reaches production it tells customers something untrue | Confirm dialog naming who is told; with GitHub connected, offer Mark fixed only when a production deployment contains the fix's commit, else say «not yet in production» |

## Suggested build order

| Wave | Content | Depends on | Size |
|---|---|---|---|
| 0 | Tor answers D-DEV-01…16 (at least 02, 03, 05, 06, 07, 09, 16 before wave 1) | — | — |
| 1 | Shell entry + `dev` rights; Roadmap on Sentral data (items, lanes, evidence from tickets, deals, funnel, experiments, SEO; promote; move); Bug triage on tickets and problems (bugs, links, KPIs, due times, merge, Mark fixed via `problem_resolve`); Integrations register for Sentral's own integrations (owners, versions, failure rates, token expiry, typed changes, Renew → LinkedIn reconnect). One migration (~900 lines + tests), three tab UIs, en + no | D-DEV-03/04/05/06/16; feature_requests with the Platform evaluator | L (≈ 4–5 days) |
| 2 | Read-only GitHub connector: intake purpose `github`, `dev-sync`, mirrors, sync log; Code and environments (production + preview deploys, open PRs with preview links, Dependabot, Sentral's pending migrations, invariant steps); roadmap progress; PR/CI state on bugs; Delivery metrics: deploy frequency, lead time, PR cycle segments, escaped bugs | GitHub App installed on both repos | L (≈ 4–5 days) |
| 3 | Releases: records, checklist with auto items (CI, Dependabot) and named sign-offs, generated changelog with edit, Record release, Recent releases; «Fixed in» on bugs | D-DEV-07/08/13; wave 2 | M (≈ 2–3 days) |
| 4 | Work board read (tracker mirror, status columns, cards, kinds, epics, assignees, PR/CI) then queued write-back with keyboard move | D-DEV-01/02/09 (and an organisation if Projects) | M–L (≈ 3–4 days) |
| 5 | Orgpuls: `platform.version`, `flags.list`, `integrations.daily` (and Sentry, rollout, coverage if decided) → Orgpuls migrations row, flags health, product-side error rates, Sentry chips, change failure/restore, rollout | Orgpuls repo work | M per item, in the Orgpuls repo |

Deviations to log when built (`deviations/development.md`, V-DEV-nn): tabs as links; ← → with accessible names; keyboard
alternative to drag; «—» CTA not rendered; auto checklist items read-only; «Record release» instead of «Release and start
rollout»; «No rollback» instead of «Healthy»; Dev/Staging columns; deploy table scroll wrapper at 390 px; Stripe, Sentry,
Skiftly/Avvikspunkt rows absent; source-named evidence instead of «Promoted»; target picker on Merge duplicate.
