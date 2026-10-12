# Development, second half — gap analysis (DevHub › Spec documents · DevClaude: Markdown roadmap, Claude jobs, Vercel and Supabase, Release gate, Repo rules)

Evaluator: dev-b, 12 Oct 2026. Design: `design-reference/sentral-simple/DevHub.dc.html` (tab `specs`) and
`DevClaude.dc.html` (views `md`, `jobs`, `env`, `gate`, `repo`, mounted by DevHub for those five tabs), plus every file in
`design-reference/sentral-simple/repo-starter/`. Both files were read in full, markup and `<script>`. Rendered at 1440 and
390 px, with the interactions pressed (Implement, task tick → commit banner, New feature file, Roll back, Approve for prod,
Sign off, Ask Claude to fix, Release, the four rules-check CTAs, spec sign-off). Screenshots:
`/tmp/claude-0/-home-user/ebb42717-a6b5-52e0-a1e8-4cdc6ef4f4f9/scratchpad/v3/dev-b/*.png`.

Legend for the Verdict column

| Verdict | Meaning |
|---|---|
| **build** | Real on the existing backend or with a new migration in this repo |
| **build+connector** | Real once a connection we can build here exists. Almost all of this area needs one: a **GitHub App** (read-only) |
| **needs-orgpuls** | Needs something on the Orgpuls side that does not exist: a product event or command, or a change in the Orgpuls repository (named) |
| **needs-decision** | A product decision only Tor can make (named, D-B-nn below) |
| **cannot** | Cannot be real (invented by nature, or forbidden by a rule). The honest rendering is named |

## Overview

**What the design is.** A developer's console around one convention: every feature and bug is a Markdown file in
`/roadmap/{features,bugs}/<ID>-<slug>.md` whose front matter (status, owner, product, priority, metric, flag, rollout, spec,
links) Sentral reads. A spec is `/docs/specs/RFC-nnn-<slug>.md`. Claude Code works in the product repository (skills `/start`,
`/ship`, `/triage`, `/plan-feature`; subagents `code-reviewer`, `anonymity-guard`), runs in GitHub Actions (`claude.yml`),
is started from Sentral («Ask Claude» → `repository_dispatch` with a free-text `prompt`) and reports back to Sentral with a
Stop hook (`POST https://sentral.orgpuls.no/api/dev/claude-log`, `Authorization: Bearer $SENTRAL_WEBHOOK_TOKEN`). Vercel and
Supabase panels show deploys and migrations; a release gate turns green from CI, Supabase, Vercel and the help centre and then
«Release v2.15.0» starts a production deploy, runs migrations and sets a flag to 5 %.

**What exists today: nothing in this area.** No section, route, table, RPC, edge function or connection is about source code,
GitHub, Vercel, Supabase Management or Claude jobs (grep over `app/`, `lib/`, `supabase/migrations/0001–0077`,
`supabase/functions/`; local DB `app` schema listed in full). The pieces this area can stand on:

| Exists | Where | Use here |
|---|---|---|
| Owner connects a third party, credentials into Vault by a one-time number, worker reads them via `product_secret` | 0060/0064/0073/0077 (`*_intake`, `store_product_secrets`, `app.vault_put`, `ads_oauth_states`, `ads-oauth`) | The same pattern for GitHub (better: the GitHub App manifest flow, so no secret ever passes through a person) |
| pg_cron → `app.*_tick` → edge function with a generated `*_worker_secret` | 0054 `job_defs`/`job_runs`, 0077 `ads_tick` | Nightly/periodic `dev-run` sync and the nightly rules check |
| HMAC-checked inbound with five-minute window and duplicate refusal | `orgpuls-events`, `_shared/signing.ts` `verifyWebhook` | Model for any inbound GitHub webhook (optional) |
| `app.help_articles` (+ `help_article_stats_daily`, `problem_id`) | 0012 | Release gate «Help-centre articles updated» |
| `app.notifications` | earlier migrations | «Request sign-off» |
| Staff (`app.admins`, 9 seeded incl. Eirik, Emma, Magnus, Jonas, Sara) | 0003+ | Sign-offs, owners; **no GitHub login** column — a mapping is needed |
| Rights `<scope>:<action>`, scopes `deals, projects, campaigns, tickets, global` | 0003/0012 `app.right_ok`, `lib/data/settings-matrix.ts` | A new scope `dev` (as 0012 added `tickets`) |
| `integration_connections` provider `ai` (Claude, D-07) | 0021/0077 | **not_connected**, no Anthropic key in Vault, no code calls api.anthropic.com |
| Sentral's own `supabase_migrations.schema_migrations` | this project | «Applied» for **Sentral's own** migrations needs no token |

**What the products have today** (read in `/home/user/orgpuls`, the Orgpuls repo `torlambrechts-sketch/orgpuls`):
no `/roadmap/`, no `/docs/specs/`, no `CHANGELOG.md`, no tags or version numbers (each push to `main` deploys through
Vercel; the playbook fast-forwards `main`), no staging environment, no Sentry, npm not pnpm. Flags are **booleans** in
`lib/flags.ts` (`FLAG_NAMES`) and `lib/flags.signed-off.json` (on in production once signed off) — there is no percentage
rollout anywhere. Its CI job «checks, security invariants and screens» has steps «Security invariants», «supabase db lint» and
«Security audit (catalog)»; `functions.yml` deploys edge functions with `SUPABASE_ACCESS_TOKEN`. Its `.claude/settings.json`
runs `bypassPermissions`; `.claude/skills/audit` exists; no agents, no hooks; `.mcp.json` holds only Playwright. Migrations
are applied to the hosted project by hand through the Supabase MCP (playbook step 2), not by a pipeline Sentral could gate.
Sentral's own repo deploys its database with `deploy-db.yml` on push to `main`.

**The three integration points the repo starter expects, judged against the rules**

1. *Sentral reads the roadmap through the GitHub API* — fine, **read-only GitHub App** (Metadata, Contents, Pull requests,
   Issues, Actions, Checks, Commit statuses, Deployments, Dependabot alerts: all *read*). Installation tokens live one hour
   and can be down-scoped per call to one repository and the permissions that call needs. The App's private key lives in
   Vault, read only by the worker through `product_secret`. No rule is touched.
2. *Stop-hook POST to `/api/dev/claude-log` with a bearer token* — **cannot as designed**, on five counts: (a) a Next route
   is a new public path past the aal2 middleware (rule 2) where inbound belongs in an edge function that checks a signature
   before parsing (rule 4's discipline); (b) a static bearer has no timestamp, so no five-minute window and no replay refusal,
   and the hook sends no id, so no duplicate detection; (c) the token must sit in every developer's shell
   (`$SENTRAL_WEBHOOK_TOKEN`) — a shared secret passed through people (rule 5); (d) the body carries
   `last_assistant_message` (400 characters of free text from a session that may have queried a database or read a
   comment) — free text Sentral may not receive (rule 6; Orgpuls invariant 7); (e) the URL is `sentral.orgpuls.no`, which is
   not Sentral (Sentral is `admin.owntheagenda.com`). **Replacement:** no inbound at all. Everything the work log shows is
   derivable from GitHub — commits touching the feature file (tasks ticked = checkbox diff), the PR, its checks and its
   Vercel deployment — which the read-only App polls. If Tor wants push instead of polling, the GitHub App's own webhook
   into an edge function `github-events`: `X-Hub-Signature-256` HMAC checked on the raw body before parsing, `X-GitHub-Delivery`
   stored and refused when seen, an event allowlist, size cap, and only ids/states kept (never comment or PR bodies). GitHub
   signs no timestamp, so the five-minute rule becomes «refuse a delivery id seen before» plus the event's own `updated_at`
   — a stated deviation from rule 4's wording that Tor accepts or not (D-B-12). The App manifest flow hands Sentral the
   webhook secret server-to-server, so it never passes through a person.
3. *«Ask Claude» as `repository_dispatch` carrying `client_payload.prompt`* — **cannot as designed**: (a) GitHub's
   `POST /repos/{o}/{r}/dispatches` needs **Contents: write**, i.e. write access to the product's source; (b) a free-text
   prompt composed by Sentral can carry whatever Sentral holds — a ticket's text (a person's own words), a customer's name,
   a deal's amount — to GitHub, to Anthropic and into a public-to-the-team PR, and it is a prompt-injection channel into a job
   that has `contents: write` and Bash. **Replacement:** `workflow_dispatch` on the product's `claude.yml`
   (`POST …/actions/workflows/claude.yml/dispatches`, needs only **Actions: write**), with typed inputs only:
   `kind` ∈ {spec, plan, implement, review, notes, fix} (enum), `item` matching `^[A-Z]{2,4}-[0-9]{1,6}$`, `job` (Sentral's
   job uuid, for linking). The workflow builds the prompt itself from the repository (`/start <item>`, `/plan-feature
   <item>`, …), so nothing written in Sentral ever leaves it. `run-name: claude ${{ inputs.job }}` lets Sentral find the run
   and the PR it opened. Whether Sentral may hold even Actions: write on a product repo is D-B-2.

**Credentials the second-half panels would need, and why most are refused by the rules**

| Source | Read-only possible? | What a credential can also do | Verdict |
|---|---|---|---|
| GitHub App | Yes — per-permission, per-repository, 1 h tokens | Nothing beyond the granted permissions | Use it. It also covers Vercel's deploys (Vercel's Git integration writes GitHub Deployments with environment and URL), CI results, Dependabot |
| Vercel REST API | No — an access token has the full rights of its scope (personal or team); there is no read-only token | Read non-sensitive env vars of the Orgpuls project (where its Supabase keys live unless marked Sensitive), redeploy, roll back, promote | Refuse: a Vercel token in Sentral can become a key to a product's database (CLAUDE.md: «the platform holds no key to any product's database»). Read deploys through GitHub instead. «Roll back» stays in Vercel's dashboard |
| Supabase Management API — Orgpuls' project | Not with a personal access token (account-wide, full rights: run SQL, read API keys incl. service_role) | Read every answer in `app.responses` — the one thing Orgpuls promises nobody can | Refuse. The facts come from Orgpuls as metadata (event `platform.schema_status`, below) or from Orgpuls' CI results on GitHub. The CLAUDE.md line about the Management API token belonging to Orgpuls is about this build session, and changes nothing here |
| Supabase Management API — Sentral's own project | Same token shape | Sentral already holds its own service role | Not needed: Sentral reads its own `schema_migrations` with a SECURITY DEFINER RPC; advisors run in CI |
| Anthropic Admin API (`GET /v1/organizations/cost_report`, `…/usage_report/messages`) | No — an Admin key (`sk-ant-admin…`) also manages members and API keys of the whole organisation | Create/revoke API keys, invite members | D-B-5. Cost report is USD, daily, groups by workspace (no per-key filter; the usage report filters by `api_key_ids[]`/`workspace_ids[]` but gives tokens, not money) |
| Sentry | — | Error payloads can carry request bodies (Orgpuls invariant 7) | Orgpuls has no Sentry. Out unless Tor adopts it (D-B-13) |

**Prototype facts that are invented and must not be carried over** (each becomes a real value, «—», or nothing): every KPI
on Claude jobs (38 PRs, 27 %, 79 %, 11 min, 1 940 kr, 41/38/21 %, 2,3, 4,1); all job rows, deploy rows, migration rows
(`0042_pulse_templates` … are Orgpuls numbers that do not exist — Orgpuls is at 0230), «team orgpuls · 4 projects»,
«orgpuls-prod · eu-north-1» (the real region is eu-central-1), «128 passing», «send-invites v14 · brreg-lookup v6» (not
Orgpuls' functions), «types.ts up to date», «v2.14.0/v2.15.0», «Thu 15 Oct», the feature files, the spec texts, the work-log
rows, «synced 1 min ago», the rules-check findings, and the owner list (tor, eirik, magnus, emma, jonas, claude). Two
prototype defects to not copy: (1) **every spec shows the same body** (Email-first signup's Problem/Options/…; picking
RFC-016 shows it too) and sign-off defaults are derived from the status label; (2) the Markdown pane's «Acceptance criteria»
are generated from `metric` («… measured 14 days after 100 %», «No new read path to survey responses») rather than read from
the file. Also: «1 items blocking» (needs ICU plural), Jobs says the nightly check found 3, the gate card says 4; every
rules-check CTA toasts «commit opened as PR», including «Request sign-off»; «Ask Claude to fix» turns the gate item green at
once although the toast says it re-checks on merge; the Repo rules pane shows a `settings.json` with an `"type": "http"` Stop
hook while the starter's file uses the shell script.

**Shell notes.** DevHub is imported without `product` (`<dc-import name="DevHub">`), so the shell's application picker does
nothing in Development; the five DevClaude tabs share one mounted component, so a job queued on Markdown roadmap appears on
Claude jobs (state survives tab switches — keep that in the build by reading from the database). The prototype's shell does
not collapse at 390 px (rail stays 244 px); the real shell already handles mobile, but these grids need a phone treatment:
Markdown roadmap and Repo rules (`minmax(220px,300px) minmax(0,1fr)`), Claude jobs rows (five columns), Vercel rows (four),
Supabase rows (three), gate rows (`22px 1fr 110px`).

---

## Spec documents (DevHub `v.specs`)

| # | Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|---|
| S1 | Spec list rows | Button per spec: title, `RFC-0nn · author · N comments`; selected row #FBEBBE | `docs/specs/RFC-*.md` per repo: id, title, author (front matter or first commit's author → staff by GitHub login) | No GitHub connection; Orgpuls has no `docs/specs/` (its decisions live in `DECISION_LOG.md`) | build+connector | GitHub App (Contents read, Commits); `dev_specs` cache; staff↔GitHub login map. Empty state «No spec documents in /docs/specs» until the convention is adopted (D-B-3) |
| S2 | Status label (Approved green / In review amber / Draft grey) | Text from hard-coded data | A rule: front-matter `status`, or derived (Draft = no open PR and not all signed; In review = open PR touching the file; Approved = all four sign-offs on the current file version) | — | needs-decision | D-B-11 |
| S3 | Comments count | Hard-coded 12/7/2/4 | Where comments live: review comments on the PR that added/changed the spec, or comments kept in Sentral | — | needs-decision | D-B-11. If PR comments: count via Pull requests read; never their text |
| S4 | Selecting a spec | Highlights row, swaps the detail | — | — | build | — |
| S5 | Detail: title (Playfair 20) and id | From selected spec | Same as S1 | — | build+connector | — |
| S6 | Sections Problem · Options · Decision · Rollout | Five fixed paragraphs, the **same for every spec** (prototype defect) | The file's own `## Problem`, `## Options`, `## Decision`, `## Rollout` sections (the `plan-feature` skill writes them), fetched live from GitHub when opened, **not stored** in Sentral; rendered as text (no HTML) | — | build+connector | Edge function reads the file with an installation token; size cap (e.g. 64 kB); sections parsed by heading; unknown headings shown in order |
| S7 | «Privacy and anonymity» section in red | Fixed red heading | Same, heading matched case-insensitively | — | build+connector | Design gap: a spec without the section shows the red heading with «Not written» (a fact about the file, not invented) |
| S8 | Sign-off chips: Product · Engineering · Security and privacy · Support | Click toggles ✓/○ locally | Who signed which role, when, and on which file version (blob sha) — a sign-off lapses when the file changes after it | Nothing | build | New `dev_spec_signoffs`; RPC `dev_spec_signoff`; rights per role are D-B-11; audited (`app.log`, names only) |
| S9 | Sign-off defaults (all on if Approved, first two if In review) | Derived from the label | — | — | cannot | Invented. Render the recorded sign-offs only; none recorded → all ○ |
| S10 | Empty / not-connected state | Not in design | — | — | build | «Connect GitHub» for the owner, «No spec documents in this repository» otherwise (design gap, design's empty treatment) |

## Markdown roadmap (DevClaude `v.md`)

| # | Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|---|
| M1 | Header `/roadmap/features` · `main · synced 1 min ago` | Static text | Repo default branch; time of the last successful sync | — | build+connector | `dev_repos.last_sync_at`; «synced» from the real sync |
| M2 | Status filter chips: All N, backlog … done with counts | Counts over the in-memory list | Front matter `status` of every feature and bug file | — | build+connector | `dev_items` cache (front matter parsed with a YAML parser, validated by zod; unknown status → shown as «—», not coerced) |
| M3 | File list rows: path, title, status pill (colour per status) | Buttons; selection | Same | — | build+connector | Paths `roadmap/features/*.md`, `roadmap/bugs/*.md`, `_TEMPLATE.md` excluded |
| M4 | Bug files in the same list (`bugs/BUG-118-…`) | Mixed into features list | `roadmap/bugs/*.md` | — | build+connector | Bug template has `customers:` and S1–S3 priorities; shown as written |
| M5 | ＋ New feature file | Adds OP-431 from `_TEMPLATE.md`, selects it, toast | Next free id per prefix; a commit creating the file | — | needs-decision | Repo **write** (Contents: write or a PR), D-B-2. Without it: a link «Create on GitHub» opening GitHub's new-file page with the template (no write by Sentral) |
| M6 | Detail header: path, title, «last commit 2 h ago by claude[bot]» | Hard-coded | Last commit touching the path: sha, author login, time | — | build+connector | Commits API `?path=`; login → staff name when mapped, else the login |
| M7 | Status select | Changes front matter locally, marks dirty | A front-matter write | — | needs-decision | D-B-2 (write) and D-B-3 (who may move status: the starter's CLAUDE.md says humans move status past `review`) |
| M8 | Owner select (tor, eirik, magnus, emma, jonas, claude) | Hard-coded options | Staff with a GitHub login, plus the Claude bot login | No GitHub login on `app.admins` | needs-decision | D-B-2 (write); options from a staff↔login map, never a hard-coded list |
| M9 | Rollout select (off, internal, 5 %, 25 %, 50 %, 100 %) | Changes front matter | A rollout that exists: a flag service with percentages | Orgpuls flags are booleans (`lib/flags.ts`, `flags.signed-off.json`); no percentage anywhere | needs-orgpuls | A percentage flag service with command `flags.set_rollout` and event `flag.changed` — or Tor decides rollout is just `off`/`on` mapped to «signed off» (D-B-10). Writing `25%` into a file that nothing reads is a setting without an effect |
| M10 | Markdown pane (dark `<pre>`) | Synthesised: front matter + generated acceptance criteria + tasks + «(appended by the Stop hook)» | The file's own text | — | build+connector | Fetched live, not stored; shown verbatim as text. Never generate acceptance criteria |
| M11 | «Tasks · N of M» list (read) | Checkboxes from data | `- [ ]`/`- [x]` lines under `## Tasks` | — | build+connector | Stored in `dev_items.tasks` (text ≤ 200, ≤ 50 items) |
| M12 | Ticking a task | Toggles, marks dirty | A write to the file | — | needs-decision | D-B-2 |
| M13 | «Linked» chips | `links` array (PR #881, RFC-014, «38 drop-offs/mo», «flag signup_email_first») | Front matter `links` | — | build+connector | Ids resolved at render time to Sentral/GitHub (PR → GitHub, RFC → spec, T-nnnn → ticket, deal id → deal). Free text shown as the file's text. D-B-15: links carry ids only — no customer names or amounts in a repo (git history cannot be erased, D-24) |
| M14 | Ask Claude › Write spec | Logs a row, adds a Running job, toast «result arrives as a pull request» | Dispatch `kind=spec, item` | No dispatch, no workflow | needs-decision | D-B-2 (Actions: write), D-B-4 (kinds, who, cap). Needs-orgpuls too: `claude.yml` with `workflow_dispatch` inputs (repo change) |
| M15 | Ask Claude › Plan tasks | Same, «task list in the feature file» | `kind=plan` | — | needs-decision | Same |
| M16 | Ask Claude › Implement (primary, yellow) | Same, «draft PR on branch op-412-…» | `kind=implement` | — | needs-decision | Same; fresh second factor recommended (it starts code changes) |
| M17 | Ask Claude › Review PR | Same, «review comments on the PR» | `kind=review` + the item's open PR | — | needs-decision | Same |
| M18 | Ask Claude › Write release note | Same, «CHANGELOG.md entry» | `kind=notes` | Orgpuls has no CHANGELOG.md | needs-decision | Same + D-B-8 (release notes exist at all) |
| M19 | Dirty banner «Saving writes a commit to main as Tor Lambrechts» + Commit change | Clears dirty, logs, toast «roadmap-sync updates the GitHub issue» | A commit (optimistic on the file's blob sha) | — | needs-decision | D-B-2: a commit straight to `main` bypasses review and CI; recommended: a branch + PR, authored by the App with `Co-authored-by: <staff>` — never «as Tor» with Tor's token. `roadmap-sync` is a product-repo workflow (needs-orgpuls if wanted) |
| M20 | Work log row «Claude session ended · Stop hook appended 3 lines · 2 tasks ticked · tests green» | Hard-coded | Stop-hook POST | — | cannot | Inbound bearer + free text (see «integration points»). Honest replacement: a row per commit to the file by the Claude bot — «claude[bot] committed · 2 tasks ticked · CI ✓» from the checkbox diff and the commit's check runs |
| M21 | Work log «PR opened · PR #881 · Vercel preview ready · Supabase branch created» | Hard-coded | PR for the item (branch `<id>-<slug>` or title `<id>:`), its Vercel deployment status | — | build+connector | PRs, Deployments read. «Supabase branch created» only where Supabase branching posts a check; Orgpuls does not use it → omitted |
| M22 | Work log «Status → …», «Spec linked · RFC-…», «File created · from feature request · promoted in Sentral» | Hard-coded | Front-matter history: each commit's version of the file diffed for `status`, `spec`; first commit | — | build+connector | `dev_item_events` (kind, actor login, at, codes — no free text). «promoted in Sentral» only when Sentral made the commit (M5/M19, decision-gated) |
| M23 | Work log «Claude job queued: …» / «Committed front matter» rows | Prepended by Ask/Commit | Sentral's own job and write records | — | build | Follow M14–M19 decisions; rows from `dev_jobs` / `dev_item_events(source=sentral)` |
| M24 | Not connected / no `/roadmap` state | Not in design | — | — | build | «Connect GitHub» (owner) or «This repository has no /roadmap folder» with a link to the template (design gap) |

## Claude jobs (DevClaude `v.jobs`)

| # | Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|---|
| J1 | KPI «Claude PRs · 30 d» 38 · «27 % of all merged PRs» | Hard-coded | Merged PRs in 30 days whose author is the Claude bot login; all merged PRs | — | build+connector | `dev_pull_requests`; bot login per repo (`claude[bot]` by default, configurable) |
| J2 | KPI «Accepted» 79 % «merged with or without edits» | Hard-coded | Claude PRs closed in 30 d: merged ÷ (merged + closed unmerged) | — | build+connector | Same; «—» when none closed |
| J3 | KPI «Median time to PR» 11 min «from job start» | Hard-coded | Job start (run `run_started_at`) and the PR it opened | — | needs-orgpuls | Repo change in each product's `claude.yml`: `run-name` carries the Sentral job id and the PR body names it, so run↔PR is a fact, not a guess. Only for Sentral-dispatched jobs; @claude runs counted only if linkable |
| J4 | KPI «Spend» 1 940 kr «API usage this month» | Hard-coded | Cost of the Anthropic workspace/key the Action uses | No Anthropic credential anywhere | needs-decision | D-B-5: an Admin key in Vault (org-admin power) to read `cost_report` grouped by workspace (USD); a NOK figure needs a rate source (Norges Bank) or the KPI reads USD. If the Action runs on a subscription token, there is no cost API → «—» |
| J5 | Card header «GitHub Action «claude» · triggered from Sentral or by @claude» | Static | The workflow file name per repo | — | build+connector | Shown only when `.github/workflows/claude.yml` exists; otherwise «No Claude workflow in this repository» |
| J6 | Row title · item id · «by» | Hard-coded 5 rows + queued ones | Sentral jobs (`dev_jobs`: kind, item, requested by staff) and Actions runs of the claude workflow (event `workflow_dispatch`/`issue_comment`/`schedule`, triggering actor, display title) | — | build+connector | Runs not started by Sentral show the triggering actor and event («@claude on #412» from the run's display title and event) |
| J7 | Kind column `/implement`, `/review`, `/spec`, `/audit`, `/triage` | Hard-coded | Known for Sentral-dispatched jobs (input `kind`) | — | build+connector | For @claude mentions the kind is not knowable without reading the comment → «—» (never read comment text) |
| J8 | State pill Running / PR opened / Done / Failed | Colour map | Run `status`/`conclusion` + linked PR | — | build+connector | «PR opened» needs the J3 link; otherwise Done/Failed only |
| J9 | Output column «PR #881 · 14 files», «4 comments · 1 blocking», «3 findings», «missing Sentry token» | Hard-coded | PR number + `changed_files`; review comment count; reviews with CHANGES_REQUESTED; for failures the failed **step name** | — | build+connector | ≈: «blocking» = a CHANGES_REQUESTED review (stated). Failure reason = the failed step's name from the jobs API, **never log text** (logs can hold anything) |
| J10 | «when» column | Relative time | Run start | — | build+connector | — |
| J11 | Row «Nightly rules check · schedule 02:00 · /audit · 3 findings» | Hard-coded | Sentral's own nightly check (G16) | — | build | `job_runs` of job `dev_audit`; count = findings open after the run |
| J12 | Row «Triage Sentry issue · Sentry alert · Failed · missing Sentry token» | Hard-coded | A Sentry alert starting a job | Orgpuls has no Sentry | needs-decision | D-B-13. Until then no such row exists |
| J13 | Quality · «Merged without changes» 41 % | Bar + % | Claude PRs merged with no commit by anyone else after Claude's last commit | — | build+connector | PR commits list (author logins) |
| J14 | «Merged after review edits» 38 % | Bar + % | Claude PRs merged with at least one human commit | — | build+connector | Same |
| J15 | «Closed / rejected» 21 % | Bar + % | Claude PRs closed unmerged | — | build+connector | J13+J14+J15 = 100 % of Claude PRs closed in 30 d |
| J16 | «Review comments per PR» 2,3 | Bar (width = value × 10 %) | Review comments ÷ Claude PRs | — | build+connector | Count only |
| J17 | «Tests added per PR» 4,1 | Bar (width = value × 10 %) | Test cases added — not knowable without parsing diffs | — | build+connector | ≈ «Test files added or changed per PR» (files matching the repo's test globs); relabelled and logged as a deviation |
| J18 | Bar scale for J16/J17 | `w = v × 10` (arbitrary) | A defined scale | — | build | Design gap: scale against the highest of the last 90 days, stated in a hint |
| J19 | Empty state | Not in design | — | — | build | «No Claude jobs in the last 30 days» |

## Vercel and Supabase (DevClaude `v.env`)

| # | Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|---|
| E1 | «Pull request flow»: PR opened → Vercel preview + Supabase branch → CI + RLS tests → Claude + human review → Merge → Staging → Release gate → Prod + flag 5 % | Static strip | The flow each repo actually has | Orgpuls: PR → CI «checks, security invariants and screens» → merge to main → Vercel production; edge functions by `functions.yml`; migrations by hand through the MCP. No staging, no gate, no flag %, no Supabase branches | needs-decision | D-B-8. Rendering a process that does not exist is a claim, not data. Built as per-repo static steps once Tor says what the flow is |
| E2 | Vercel header «team orgpuls · 4 projects» | Static | Vercel team/projects | — | build+connector | ≈ from GitHub Deployments: the Vercel projects seen deploying the linked repos. A Vercel token is refused (table above) |
| E3 | Rows: project · PR #n / main, URL | Hard-coded 5 rows | GitHub Deployments written by Vercel's Git integration: environment, `environment_url`, ref, sha, created | — | build+connector | Deployments: read |
| E4 | Environment column Preview / Staging / Production | Hard-coded | Deployment environment | — | build+connector | Only environments that exist (Orgpuls: Preview, Production) |
| E5 | State Ready / Building / Rolled back | Colour | Latest deployment status (`success`, `in_progress`, `failure`, `inactive`) | — | build+connector | — |
| E6 | Version label «v2.14.0», «v1.9.3» | Hard-coded | Release versions | No versions or tags exist | cannot | Show the short sha and time of the production deployment |
| E7 | «Roll back» on production rows | Marks Rolled back, toast | Vercel instant rollback (`POST /v1/projects/{id}/rollback/{deployment}`) | — | needs-decision | D-B-6: needs a full-power Vercel token in Sentral and lets Sentral change a product's production (rule 3: a product is reached only by product-command). Recommended: no button; «Open in Vercel» link |
| E8 | Supabase header «project orgpuls-prod · eu-north-1» | Static (wrong region) | Project ref and region per repo | — | build | Owner types them in the repo settings (`dev_repos.supabase_ref`, `region`); Orgpuls is eu-central-1 |
| E9 | Migration rows: file name, linked item, note | Hard-coded 0042–0044 | `supabase/migrations/*.sql` on main and in open PRs; item from the PR title/branch id; note = the file's first comment line | — | build+connector | Contents read; the note is ≈ (Orgpuls' migrations open with a comment header) |
| E10 | Migration state Applied / Pending prod | Hard-coded | Which versions the **hosted** database has applied | No source without a key to the product | needs-orgpuls | Event `platform.schema_status` from Orgpuls (applied versions, latest at — metadata only). For Sentral's own repo: build (own `schema_migrations`) |
| E11 | «Approve for prod» | Marks Approved, feeds gate item | An approval that something consumes | Orgpuls applies migrations itself (build phase, X-108) | needs-decision | D-B-9. A write with no reader fails the wiring rule; until Orgpuls' pipeline waits for it, no button |
| E12 | «Branch databases · 2 open · PR #881, PR #884» | Hard-coded | Supabase branching | Orgpuls does not use branching | cannot | Omit the row (no source) |
| E13 | «RLS and anonymity tests · 128 passing» | Hard-coded | Result of Orgpuls CI step «Security invariants» for main's head; a count | — | build+connector | Pass/fail from the Actions jobs API (step conclusion). The count needs Orgpuls' CI to write it into the job summary/check output (repo change) → «—» until then |
| E14 | «Security advisor · 1 warning · function search_path» | Hard-coded | Hosted advisor results | — | needs-decision | Hosted advisors need a Management token on the product (refused). ≈ alternative: Orgpuls CI's «supabase db lint» and «Security audit (catalog)» step results via GitHub, labelled as CI checks (D-B-7) |
| E15 | «Edge Functions · send-invites v14 · brreg-lookup v6» | Hard-coded (not Orgpuls' functions) | Deployed functions and versions | — | build+connector | ≈ last `functions.yml` run on main: conclusion, sha, time (GitHub). Version numbers need the Management API → not shown |
| E16 | «Type generation · types.ts up to date» | Hard-coded | — | Orgpuls deliberately parses rows with zod; `gen types` does not cover its `app` schema | cannot | Omit |
| E17 | Not-connected state | Not in design | — | — | build | «Connect GitHub» / «Set this repository's Supabase project» |

## Release gate (DevClaude `v.gate`)

| # | Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|---|
| G1 | Title «Release gate · Orgpuls v2.15.0» | Static | What a «release» is | No versions, no release trains; every push to main deploys | needs-decision | D-B-8. Recommended: a gate per PR (head sha) and for «main since the last production deployment» |
| G2 | State «N items blocking» / «Ready» / «Released» | Computed | The items below | — | build | ICU plural («1 item blocking») |
| G3 | Subtitle «Filled automatically from CI, Supabase, Vercel and the help centre. Manual items need a named person.» | Static | — | — | build | i18n |
| G4 | ✓ CI: unit, integration and end-to-end tests · from GitHub Actions | Default ✓ | Check runs / combined status for the sha | — | build+connector | Checks read |
| G5 | Supabase migrations approved and reversible · from Supabase | ✓ only after two «Approve for prod» on the other tab | Approval (E11) and reversibility | Reversibility is not a property anyone records; Orgpuls sets objects aside instead of down-migrations | needs-decision | D-B-9. Until then the item is a manual sign-off at most, never «from Supabase» |
| G6 | RLS and anonymity tests pass · from Supabase · pgTAP | Default ✓ | Orgpuls CI step «Security invariants» | — | build+connector | Labelled «from GitHub Actions» (that is where it runs) |
| G7 | No high security findings · from Dependabot · Supabase advisor | Default ! | Open Dependabot alerts with severity high/critical; hosted advisor | — | build+connector | Dependabot alerts read. The advisor half is D-B-7 (CI lint ≈) |
| G8 | «Ask Claude to fix» (security) | Turns ✓ at once, toast «Claude opened a fix PR» | Dispatch `kind=fix` with the alert number | — | needs-decision | D-B-2/D-B-4. The item stays red until the alert closes |
| G9 | Preview checked by product · Sign off | Click → ✓ | The PR's preview URL (GitHub Deployments) and a named staff sign-off on that sha | — | build | `dev_gate_signoffs` (sha, item, staff, at); lapses on a new sha |
| G10 | New code behind a flag · from feature files | Default ✓ | Whether new code is behind a flag — not decidable | Flags exist as `FLAG_NAMES` | build+connector | ≈ «Each feature in this change names a flag that exists in `lib/flags.ts`» (stated rule; logged deviation) |
| G11 | Help-centre articles updated · from help centre | Default ! | Which help articles belong to the feature, and whether they changed after the work started | `app.help_articles` exists (0012) | build | A link item ↔ article (`dev_item_articles`), then `updated_at` vs the item's start |
| G12 | «Ask Claude to fix» (help) | Turns ✓ | A drafted article | Help centre is in Sentral's DB, not in a repo; `ai` provider not connected | build+connector | Claude API from Sentral (D-07 `ai` integration, key via intake) drafts a **draft** article from the feature file's text; a person publishes. No ticket or customer text in the prompt |
| G13 | Release note in CHANGELOG.md · from Claude /notes | Default ✓ | `CHANGELOG.md` `## Unreleased` section non-empty | Orgpuls has no CHANGELOG.md | build+connector | «No CHANGELOG.md in this repository» until it exists (D-B-8) |
| G14 | Rollback plan reviewed · Sign off | Click → ✓ | Named sign-off | — | build | `dev_gate_signoffs` |
| G15 | «Release v2.15.0» → «Vercel production deploy started · migrations run · flag at 5 %» | Enabled when all ✓ | A deploy, a migration run and a flag change done by Sentral | — | cannot | Reaches a product outside product-command (rule 3) and needs a Vercel token and a Management token (refused), and a flag % that does not exist. Honest rendering: the gate is a verdict («Ready to merge» / «N items blocking»), no release button |
| G16 | «Nightly rules check · ran 02:00 · N findings» | Static | Sentral's own nightly job over the synced data | — | build | Job `dev_audit` (pg_cron) inside `dev-run`; `dev_audit_findings`; the repo starter's `roadmap-audit.mjs` posting to Sentral is not needed |
| G17 | Finding «OP-401 says rollout 25 % but the flag is at 50 %» | Hard-coded | Flag service state | No percentages | needs-orgpuls | Flag service (M9). ≈ now: «file says rollout 100 % but the flag is not signed off» / «file names a flag that is not in FLAG_NAMES» (build+connector) |
| G18 | Finding «PR #876 has no feature file» | Hard-coded | Open PRs whose branch/title carries no item id with a file | — | build+connector | — |
| G19 | Finding «5 flags older than 90 days» | Hard-coded | When each flag name was added | — | build+connector | GraphQL blame of `lib/flags.ts` (Contents read) |
| G20 | Finding «RFC-017 not signed off but status is spec → in-progress soon» | Hard-coded | Spec sign-offs (S8) vs the item's status | — | build | — |
| G21 | CTAs «Update file», «Create file» | Toast «commit opened as PR» | A repo write | — | needs-decision | D-B-2; without write: link to the file on GitHub |
| G22 | CTA «Create cleanup tasks» | Same toast | Where tasks live (Work board / tracker — dev-a's area) | — | needs-decision | D-B-14 |
| G23 | CTA «Request sign-off» | Same toast (wrong) | A notification to the staff holding the missing role | `app.notifications` | build | Toast «Sign-off requested from …» |
| G24 | Clean state «Repository and roadmap agree.» | When no findings | — | — | build | — |

## Repo rules (DevClaude `v.repo`)

| # | Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|---|
| R1 | Groups Memory · Skills · Subagents · Hooks · Workflows · MCP with file paths | Hard-coded 11 files | Allowlisted paths: `CLAUDE.md`, `roadmap/*/_TEMPLATE.md`, `.claude/skills/*/SKILL.md`, `.claude/agents/*.md`, `.claude/settings.json`, `.claude/hooks/*`, `.github/workflows/*.yml`, `.mcp.json` | — | build+connector | Contents read; never `.env*` or anything outside the allowlist |
| R2 | «Tor · 2 Oct» per file | Hard-coded | Last commit per path: author, date | — | build+connector | Commits `?path=`; login → staff name when mapped |
| R3 | Selected file header: path, by | — | Same | — | build+connector | — |
| R4 | One-line «what» | Hard-coded | Skills/agents: front-matter `description`; others: a fixed sentence per path kind | — | build+connector | i18n for the fixed sentences |
| R5 | File body (dark `<pre>`, max-height 460) | Hard-coded text | The file, fetched live | — | build+connector | Not stored; size cap; text only |
| R6 | «Read-only here · edits go through a pull request with code-owner review» | Static | Whether CODEOWNERS/branch protection exist | — | build | Say «Edit on GitHub» (link) unless `CODEOWNERS` exists; do not claim a review that is not configured |
| R7 | Missing file / empty group | Not in design | — | Orgpuls has no agents or hooks today | build | «Not in this repository» row (design gap) |

## Integration points the repo starter expects

| # | Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|---|
| I1 | Sentral reads `/roadmap` through the GitHub API (README) | — | GitHub App read-only on the chosen repos | — | build+connector | Manifest flow (`dev-github-setup`), `_shared/github.ts`, `dev-run` |
| I2 | Stop hook `log-to-sentral.sh` → `POST /api/dev/claude-log`, bearer | Every Claude session posts `{id, branch, summary}` | — | — | cannot | Rules 2, 4, 5, 6 (see Overview). Replaced by reading GitHub; optional signed `github-events` |
| I3 | `claude.yml` `repository_dispatch` with `prompt: ${{ github.event.client_payload.prompt }}` | Sentral sends a prompt | — | — | cannot | Contents: write + free text out of Sentral. Replaced by `workflow_dispatch` with enum inputs (D-B-2, D-B-4) |
| I4 | `roadmap-sync.yml` (front matter ⇄ Issues/Projects, nightly) | Product-repo workflow | — | — | needs-orgpuls | Optional repo change; Sentral does not need it (it reads the files). Its second step posts to Sentral with `SENTRAL_WEBHOOK_TOKEN` → cannot (inbound bearer); Sentral runs the rules itself (G16) |
| I5 | `.mcp.json` with `supabase … ?read_only=true` for every developer **and CI** | — | — | Orgpuls `.mcp.json` has Playwright only | needs-decision | D-B-4: a read-only SQL connection to production can read `app.responses`; a Claude job dispatched from Sentral must never have it (Orgpuls invariant 1–2) |
| I6 | `.claude/settings.json` hooks (protect.sh, `pnpm lint`, Stop hook) | — | — | Orgpuls: `bypassPermissions`, npm | needs-decision | D-B-3: adopt per product, not verbatim |
| I7 | Starter `CLAUDE.md` («n >= 5», pnpm, monorepo `apps/web, apps/sentral`) | — | — | Orgpuls' CLAUDE.md: k floor 3, default 5 per round (D-198); npm; Sentral is a separate repo | needs-decision | D-B-3: the starter contradicts both real CLAUDE.md files; do not copy |
| I8 | GitHub secrets ANTHROPIC_API_KEY, SENTRAL_WEBHOOK_TOKEN, SUPABASE_ACCESS_TOKEN, VERCEL_TOKEN | — | — | Orgpuls already holds SUPABASE_ACCESS_TOKEN for `functions.yml` | needs-decision | SENTRAL_WEBHOOK_TOKEN not needed (I2/I4 replaced); VERCEL_TOKEN not needed for reading; ANTHROPIC_API_KEY is D-B-5 |
| I9 | `anonymity-guard` subagent as the privacy control | A prompt that greps diffs | — | Orgpuls' controls are structural (RLS without policy, `respondent_invariants.sql`) | cannot | A prompt is not a control. Sentral shows the CI result of the invariant suite (E13/G6), never «anonymity-guard passed» as a guarantee |

---

## Proposed database objects

One migration (number given by the planner, after 0077), all tables in `app`, RLS on, no policy, no grant; every public
function SECURITY DEFINER with `search_path=''`, revoked from public/anon; reads `stable`, writes `volatile`; SQL assertions in
the suite. Rights: a new scope **`dev`** (`app.right_ok` extended as 0012 did for `tickets`; `SCOPE_KEYS` in
`lib/data/settings-matrix.ts`), actions `see` (read the section), `add` (sign off, request sign-off, ask Claude),
`configure` (repos, bot login, Supabase ref). Connecting GitHub and repo writes: owner with a fresh second factor
(`require_owner` + `require_fresh_mfa(10)`). Which preset gets `dev:*` is D-B-1.

| Object | Kind | Columns / behaviour | Rights |
|---|---|---|---|
| `integration_connections` provider `github` | row | `config`: app id, slug, installation ids, `key_stored_at`, `last_error` (code) | owner |
| Vault names `github_app_private_key`, `github_app_webhook_secret`, `github_app_client_secret`, `dev_worker_secret` | Vault | `product_secret` allowlist extended; generated or delivered server-to-server by the manifest exchange | service_role only |
| `app.github_manifest_states` | table | hash, staff_id, origin (same regex as 0077), expires_at (15 min) | — |
| `app.dev_repos` | table | id, product (FK `products`, null = Sentral itself), owner, name, default_branch, installation_id, roadmap_path, specs_path, bot_login (default `claude[bot]`), supabase_ref, region, test_globs, last_sync_at, last_error code | `dev:configure` |
| `app.dev_people` | table | staff_id ↔ github_login (unique, `^[A-Za-z0-9-]{1,39}$`) | `dev:configure`; each person may set their own |
| `app.dev_items` | table | repo_id, item_id (`^[A-Z]{2,4}-[0-9]{1,6}$`), kind feature/bug, path, title ≤200, status enum (7) or null, owner_login, product, priority, metric ≤200, flag ≤60, rollout text ≤10, spec, links text[] (≤20 × ≤80), tasks jsonb (≤50 × {t ≤200, done}), file_sha, last_commit_{sha,at,login}, synced_at | read `dev:see` |
| `app.dev_item_events` | table | repo_id, item_id, at, kind enum (created, status, spec_linked, tasks_ticked, pr_opened, pr_merged, preview_ready, job_queued, job_done, committed_from_sentral), actor_login, detail jsonb (codes and counts only), source github/sentral | read `dev:see` |
| `app.dev_specs` | table | repo_id, spec_id (`^RFC-[0-9]{1,5}$`), path, title, author_login, file_sha, comments_count (per D-B-11), synced_at — **no body** | read `dev:see` |
| `app.dev_spec_signoffs` | table | repo_id, spec_id, role enum (product, engineering, security_privacy, support), staff_id, file_sha, signed_at; unique (repo, spec, role) | `dev:add` (+ role rule D-B-11) |
| `app.dev_pull_requests` | table | repo_id, number, title ≤300 (no body), author_login, is_bot, state, head_ref, head_sha, item_id, created/merged/closed_at, changed_files, review_comments, changes_requested, human_commits, test_files | read |
| `app.dev_checks` | table | repo_id, sha, name, step (nullable), conclusion, completed_at | read |
| `app.dev_deployments` | table | repo_id, environment, sha, ref, state, url, created_at | read |
| `app.dev_migrations` | table | repo_id, version, name, in_main, in_pr, note ≤200 (first comment line), applied (null = unknown), applied_source enum (own_db, orgpuls_event) | read |
| `app.dev_jobs` | table | id, repo_id, item_id, kind enum (spec, plan, implement, review, notes, fix), source (sentral, mention, schedule, other), requested_by, state (queued, dispatched, running, pr_opened, done, failed), run_id, run_url, pr_number, failed_step ≤100, requested/started/finished_at, error code; unique idempotency key | read `dev:see`; request `dev:add` (D-B-4) |
| `app.dev_gate_signoffs` | table | repo_id, sha, item enum (preview, rollback), staff_id, signed_at | `dev:add` |
| `app.dev_item_articles` | table | repo_id, item_id, article_id (FK `help_articles`) | `dev:add` |
| `app.dev_audit_findings` | table | id, repo_id, rule enum (flag_mismatch, pr_without_file, stale_flag, spec_unsigned), subject (ids only ≤80), detail jsonb (codes, counts), found_at, resolved_at | read |
| `app.dev_usage_daily` | table (only if D-B-5) | day, workspace, cost_usd | read `dev:see` |
| `job_defs` row `dev` | data | every 15 min (sync) + `dev_audit` 02:00 Oslo | — |

Public RPCs: `dev_overview(p_repo)`, `dev_items_list(p_repo, p_status)`, `dev_item_get(p_repo, p_item)` (front matter,
tasks, links resolved, events), `dev_specs_list(p_repo)`, `dev_spec_get(p_repo, p_spec)` (metadata + sign-offs),
`dev_spec_signoff(p_repo, p_spec, p_role, p_on)`, `dev_jobs_list(p_repo, p_days)`, `dev_claude_quality(p_repo, p_days)`,
`dev_env_get(p_repo)`, `dev_gate_get(p_repo, p_sha)`, `dev_gate_signoff(p_repo, p_sha, p_item)`,
`dev_findings(p_repo)`, `dev_request_signoff(p_repo, p_spec, p_role)`, `dev_rule_files(p_repo)`; owner/configure:
`dev_github_start(p_origin)`, `dev_repo_set(…)`, `dev_repo_remove(p_repo)`, `dev_disconnect()`, `dev_sync_now(p_repo)`;
decision-gated: `dev_job_request(p_repo, p_item, p_kind)`, `dev_item_write(p_repo, p_item, p_changes, p_expected_sha)`,
`dev_item_create(p_repo, p_kind, p_title)`. Worker-only (service_role): `worker_dev_ingest(p_repo, p_batch jsonb)` (zod-shaped
in the function, checked again in SQL), `worker_dev_job_update`, `worker_dev_file_ok(p_repo)` (the caller's own token
checked for `dev:see` before a live file fetch, like `ads_check_ready`). Every write goes through `app.log` with names only.
Nothing here is added to the external API or `mcp_index` until decided.

## Proposed edge functions and connectors

| Function | What it does | Auth |
|---|---|---|
| `_shared/github.ts` | App JWT (RS256 from the Vault key), installation token per call down-scoped to one repository and the permissions needed, REST + GraphQL (blame), rate-limit back-off, zod-parsed responses; logs carry endpoint kind and status code only | — |
| `dev-github-setup` | GitHub App **manifest** flow: owner (fresh MFA) starts from Sentral with a one-time state; GitHub returns a code; the function exchanges it (`POST /app-manifests/{code}/conversions`) and puts the private key, webhook secret and client secret into Vault itself. The owner then installs the App on the repositories they choose | `verify_jwt: false`; state hash, 15 min, used once |
| `dev-run` | Worker: sync files (front matter, tasks, specs metadata, rule files metadata), PRs, checks, deployments, Claude workflow runs, Dependabot alerts; nightly rules check; dispatch queued jobs (`workflow_dispatch`, decision-gated); live file read for a signed-in caller (specs, markdown pane, repo rules) without storing | worker secret from Vault; caller's JWT for live reads |
| `github-events` (optional, D-B-12) | GitHub App webhook: HMAC-SHA256 `X-Hub-Signature-256` on the raw body before parsing, `X-GitHub-Delivery` refused when seen, event allowlist (push, pull_request, check_run, deployment_status, workflow_run), 1 MB cap; stores ids/states only and pokes `dev-run` | webhook secret from Vault |
| Claude API (existing `ai` provider, D-07) | Draft a help article for G12 | key via intake (0077 pattern) |
| Anthropic Admin cost report (only if D-B-5) | `GET /v1/organizations/cost_report` daily into `dev_usage_daily` | Admin key via intake |
| **Not built** | `/api/dev/claude-log`; Vercel token; Supabase Management token for any product; Sentry | rules (see Overview) |

## Orgpuls commands and events needed

| Need | Kind | For | Contents (metadata only) |
|---|---|---|---|
| `platform.schema_status` | event (Orgpuls → `orgpuls-events`) | E10, G5 | applied migration versions (last 50), latest applied at. No row counts of answer tables |
| `flags.set_rollout` + `flag.changed` | command + event | M9, G17 | flag name, percentage — only if Tor wants percentage rollout (today flags are booleans) |
| `claude.yml` with `workflow_dispatch` inputs `kind` (enum), `item`, `job`; `run-name` with the job id; PR body naming the job | repo change | M14–M18, G8, J3, J8 | — |
| Invariant suite count in the CI job summary/check output | repo change | E13 | «N assertions passed» |
| `/roadmap/{features,bugs}`, `_TEMPLATE.md`, `/docs/specs/RFC-*`, `CHANGELOG.md` | repo convention | whole area | — |
| No Claude job with a production database connection (`.mcp.json` Supabase on prod) | repo rule | I5 | — |

The same applies to Skiftly, Avvikspunkt and Kursrom repositories if Tor links them (`app.products`: orgpuls, skiftly,
avvik, kurs; the starter's `product:` list matches these keys plus `sentral`).

## Product decisions for Tor

- **D-B-1** Who sees Development and who may act in it: a new right scope `dev` (see / add / configure) and which presets
  get it (owner and admin only? an «Engineering» preset?).
- **D-B-2** Sentral's GitHub access: **read-only App** (recommended), or also **Actions: write** (start Claude jobs), or also
  **Contents/Pull requests: write** (front-matter edits, new files, «Update/Create file»). If write: always a branch + PR
  (recommended) or straight to `main`; commits authored by the App with `Co-authored-by` the staff member, never «as Tor»
  with Tor's own token.
- **D-B-3** Adopt the roadmap-as-Markdown convention in Orgpuls (and other products) — it sits beside Orgpuls'
  `DECISION_LOG.md`/`IMPLEMENTATION_PLAN.md` practice — and which starter files to adopt. The starter's `CLAUDE.md`,
  `settings.json` and `.mcp.json` contradict Orgpuls' real ones (k floor 3 / default 5 per round vs «n >= 5»; npm vs pnpm;
  `bypassPermissions`; one monorepo vs two repos) and must not be copied verbatim. Who may move `status` past `review`.
- **D-B-4** Claude jobs: the allowed kinds; who may start them; a daily cap per repo; fresh second factor for «Implement»;
  that a dispatched job never gets a production database connection.
- **D-B-5** Spend: give Sentral an Anthropic **Admin** key (organisation-wide power) to read the cost report, or render «—».
  Currency: USD as reported, or NOK with a named rate source. Whether the Action runs on an API key at all (a subscription
  token has no cost API).
- **D-B-6** Vercel: accept that Sentral reads deploys through GitHub only (recommended), or hand Sentral a full-power Vercel
  token (needed for «Roll back», «4 projects»). Recommended: no rollback from Sentral.
- **D-B-7** Supabase facts for products: through an Orgpuls event and CI results (recommended), never a Management token
  on a product project. Accept CI lint results as the «advisor» row, labelled as such.
- **D-B-8** Release process: versions, release trains, staging, a CHANGELOG — or keep continuous deploys and make the gate a
  per-PR / per-main-sha verdict without a release button (recommended). Decides the PR-flow strip (E1) and the gate title.
- **D-B-9** Should Sentral approve production migrations for Orgpuls? Today Orgpuls applies them itself (build phase X-108).
  Without a consumer, «Approve for prod» cannot exist.
- **D-B-10** Feature rollout: build a percentage flag service in Orgpuls (command + event), or treat `rollout` as off/on
  mapped to «signed off» in `flags.signed-off.json`.
- **D-B-11** Specs: where they live (repo files, recommended), where comments live (PR review comments or Sentral), the status
  rule (front matter or derived), which staff may sign each role (Product, Engineering, Security and privacy, Support), and
  that a sign-off lapses when the file changes.
- **D-B-12** Polling only (recommended first), or also GitHub webhooks into `github-events` — with replay protection by
  delivery id instead of a signed timestamp, a stated departure from rule 4's five-minute wording.
- **D-B-13** Sentry: Orgpuls has none. Adopting it (for `/triage`) means error payloads leave Orgpuls; its invariant 7 then
  needs a scrubber decision. Until then no Sentry rows.
- **D-B-14** Where cleanup tasks go (Work board / Linear / GitHub Issues) — shared with dev-a's Work board.
- **D-B-15** Feature-file `links` carry ids only (tickets, deals, PRs), never customer names or amounts; Sentral resolves
  them. Git history cannot be erased (D-24).

## Risks against the security rules

| # | Risk | Rule | Mitigation |
|---|---|---|---|
| RB-1 | A Supabase Management token for a product (even «read-only») can run SQL and read API keys: a key to Orgpuls' database and to every answer | «holds no key to any product's database»; rule 6; Orgpuls invariants 1–2 | Never stored. Orgpuls event + CI results |
| RB-2 | A Vercel token reads the product's non-sensitive env vars (possibly its Supabase keys) and can deploy | same; rule 3 | Read deploys through GitHub Deployments; no Vercel token |
| RB-3 | GitHub Contents: write on a product repo = the power to change production code; Actions secrets of that repo (e.g. `SUPABASE_ACCESS_TOKEN` in `functions.yml`) are one workflow edit away | rule 3 spirit, rule 5 | Read-only App by default; writes only by D-B-2, PR-only, down-scoped tokens, audited |
| RB-4 | Stop-hook endpoint: public Next path, static bearer on laptops, no replay/idempotency, free text | rules 2, 4, 5, 6 | Not built; GitHub-derived log |
| RB-5 | Free-text prompt from Sentral carries tickets' words, names, amounts to GitHub/Anthropic; prompt injection into a job with write + Bash | rule 6 («a person's own words»), D-24 | Enum inputs only; the workflow builds the prompt from the repo |
| RB-6 | A Claude job with a production SQL connection writes answers or comments into a PR, a commit or a log that Sentral then syncs | rule 6; Orgpuls invariant 7 | D-B-4; Sentral syncs titles, ids, counts, states — never PR bodies, comment text, review text or logs; failure reason = step name |
| RB-7 | Repo text stored in Sentral could contain anything someone pasted | rule 6 | Store front matter, titles, task lines (length-capped, zod); fetch bodies live, do not store; allowlisted paths only |
| RB-8 | Markdown from a repo (Claude-written) rendered as HTML → XSS in an aal2 admin session | rule 1 (session power) | Render as text; no `dangerouslySetInnerHTML` |
| RB-9 | Secrets passing through a person when configuring GitHub | rule 5 | Manifest flow: key and webhook secret go GitHub → edge function → Vault |
| RB-10 | Invented figures carried from the prototype (KPIs, versions, counts) survive into screenshots as facts | Design rule «never fabricate» | Every value from a table above, else «—»; deviations logged in `deviations/dev.md` |
| RB-11 | A green «anonymity» item based on a prompt (`anonymity-guard`) presented as a guarantee | Orgpuls' central promise | Only the CI invariant suite's real result is shown |
| RB-12 | Customer data written into feature files via «Promote» (dev-a's Roadmap) cannot be erased from git history | D-24 erasure | D-B-15: ids only |
| RB-13 | Sentral starting production deploys / migrations / flag changes («Release») | rule 3 | Not built; the gate is a verdict |
| RB-14 | GitHub webhooks have no signed timestamp | rule 4 | Polling first; if webhooks, delivery-id dedupe and D-B-12 |

## Suggested build order

| Wave | Content | Depends on | Size |
|---|---|---|---|
| B0 | Section route `/development` (`?tab=`), the 13-tab strip, right scope `dev` (migration part), honest «Connect GitHub» states on all six tabs, i18n en/no | D-B-1 | S |
| B1 | GitHub App: `integration_connections.github`, manifest states, Vault names, `dev_repos`, `dev_people`, owner RPCs; `dev-github-setup`; `_shared/github.ts`; connect card on Platform › Integrations | D-B-2 (read-only is enough) | M |
| B2 | `dev-run` sync + caches (`dev_items`, `dev_item_events`, `dev_specs`, `dev_pull_requests`, `dev_checks`, `dev_deployments`, `dev_migrations` for Sentral's own repo); read RPCs; **Markdown roadmap read-only** (M1–M4, M6, M10, M11, M13, M20–M22, M24), **Repo rules** (all), **Spec documents** list/detail (S1, S4–S7, S10), **Vercel panel** via GitHub (E2–E5, E9, E13, E15, E17) | B1; D-B-3 for content to exist in Orgpuls | L |
| B3 | Sign-offs and the gate verdict: `dev_spec_signoffs` (S8), `dev_gate_signoffs` (G9, G14), gate items G2–G4, G6, G7, G10, G11, G13; nightly rules check G16, G18–G20, G23–G24 with `dev_audit_findings`; `dev_item_articles` | B2; D-B-11 | M |
| B4 | Claude jobs: `dev_jobs`, `workflow_dispatch`, run↔PR linking, jobs list and quality KPIs (J1–J19 except J4/J12), Ask Claude buttons (M14–M18, G8) | D-B-2 (Actions: write), D-B-4; Orgpuls `claude.yml` | M |
| B5 | Repo writes: front-matter commit via PR (M7, M8, M12, M19), new file (M5), Update/Create file (G21) | D-B-2 (Contents/PR write), D-B-3 | M |
| B6 | Orgpuls metadata: `platform.schema_status` → E10, G5 (as far as D-B-9 allows); CI invariant count → E13 | Orgpuls event + CI change | S |
| B7 | Optional: Claude API draft for help articles (G12); Anthropic cost (J4); `github-events` webhooks; flag rollout (M9, G17) | D-B-5, D-B-10, D-B-12; `ai` key | S–M each |
| — | Not built: Roll back (E7), Approve for prod (E11 until D-B-9), Release button (G15), branch databases (E12), type generation (E16), versions (E6), Sentry rows (J12), Stop-hook endpoint (I2), free-prompt dispatch (I3) | rules | — |

Counts per tab (elements · build · build+connector · needs-orgpuls · needs-decision · cannot): Spec documents 10 · 3 · 4 · 0 ·
2 · 1; Markdown roadmap 24 · 2 · 10 · 1 · 10 · 1; Claude jobs 19 · 3 · 13 · 1 · 2 · 0; Vercel and Supabase 17 · 2 · 7 · 1 · 4 · 3;
Release gate 24 · 9 · 8 · 1 · 5 · 1; Repo rules 7 · 2 · 5 · 0 · 0 · 0; Integration points 9 · 0 · 1 · 1 · 4 · 3.
