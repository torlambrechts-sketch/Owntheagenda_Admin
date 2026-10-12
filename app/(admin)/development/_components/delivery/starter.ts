/**
 * The repo starter kit (design-reference/sentral-simple/repo-starter), corrected where it contradicts the real rules, to be
 * copied into a product's repository. Each file lists the corrections made to it (message keys devDelivery.repo.fix.*);
 * a file the kit had that would break a rule is listed as removed, with why. The bodies are files, not interface text:
 * they stay in English, as the repositories do.
 *
 * Sentral does not read the repository (PLAN.md: no GitHub), so it cannot say whether a repository has drifted from
 * these files; the view says so instead of showing a check.
 */

export const STARTER_GROUPS = ['memory', 'roadmap', 'skills', 'agents', 'hooks', 'workflows', 'mcp'] as const
export type StarterGroup = (typeof STARTER_GROUPS)[number]
export const FIXES = ['k', 'npm', 'repos', 'forward', 'suites', 'stopHook', 'dispatch', 'auditPost', 'mcpProd', 'sentry', 'secrets', 'readsRepo', 'ciReport',
  'changelog', 'ids', 'rls', 'guard', 'protect', 'targets', 'rollout', 'roadmapGen'] as const
export type Fix = (typeof FIXES)[number]

export type StarterFile = {
  /** a key for messages (devDelivery.repo.what.<id>) and the address (?file=<id>) */
  id: string
  path: string
  group: StarterGroup
  status: 'as_designed' | 'corrected' | 'new' | 'removed'
  fixes: Fix[]
  /** the file to copy; empty for a removed one */
  body: string
}

const CLAUDE_MD = `# Orgpuls

## Repositories
- This repository is Orgpuls, the product: Next.js on Vercel, Supabase (eu-central-1).
- Sentral, the platform the company runs its products from, is a separate repository (Owntheagenda_Admin) and project.
  It reaches Orgpuls only through signed commands and receives Orgpuls' signed events. It holds no key to this database.

## Stack
- Next.js (App Router) on Vercel · Supabase: Postgres, Auth, Edge Functions (supabase/) · TypeScript strict · npm

## Hard rules
- NEVER read, join or export the survey answer tables (responses, answers, extra_answers, response_comments). They have
  RLS with no policy and no grant; results are read through SECURITY DEFINER functions that apply k per cell.
- k-anonymity: floor 3 (app.k_floor()), default 5 (app.k_min()), enforced in the database. A round freezes its k when it
  opens. Never lower it, and never add a column that could link an answer to a person.
- Every new feature ships behind the flag named in its feature file.
- Migrations are forward-only: never edit an applied migration — add one that supersedes it. Set objects aside (rename,
  revoke) instead of DROP. A new table gets RLS in the same migration.
- No secrets in code or in commits. Read them from the environment.

## Workflow
1. Read the feature or bug file in /roadmap before writing code.
2. Branch: \`<id>-<slug>\`. PR title: \`<id>: <title>\`. PR body links the file.
3. Tick tasks in the file as you finish them. Do not change \`status\` past \`review\` — humans do that.
4. Before opening a PR: \`npm run lint && npx tsc --noEmit && npx vitest run && npm run test:db\`.
5. Ask the \`anonymity-guard\` subagent to review any change touching supabase/ or exports. The SQL suites are the control.

## Commands
- \`npm run dev\` · \`npx vitest run\` · \`npm run test:db\` · \`supabase start\` · \`supabase migration new <name>\`
`

const README = `# Repo starter — Claude Code + Vercel + Supabase, reporting to Sentral

Copy these files into the root of a product's repository (Orgpuls; Sentral is a repository of its own). Sentral does not
read the repository: it learns about deploys from Vercel's deployment webhooks and about builds from the signed report the
CI posts (scripts/sentral-report.mjs).

| Path | Purpose |
|---|---|
| CLAUDE.md | Project memory and hard rules for every Claude session |
| roadmap/ROADMAP.md | Now / Next / Later — downloaded from Sentral › Development › Markdown roadmap |
| roadmap/features/_TEMPLATE.md | Template for a feature file |
| roadmap/features/OP-412-email-first-signup.md | Example feature file |
| roadmap/bugs/_TEMPLATE.md | Bug template |
| .claude/skills/{start,ship,triage,plan-feature}/SKILL.md | Slash-command workflows |
| .claude/agents/{code-reviewer,anonymity-guard}.md | Subagents with limited tools |
| .claude/settings.json + .claude/hooks/protect.sh | Hooks: protect files, lint after edits |
| .mcp.json | GitHub and Vercel MCP servers for developers |
| .github/workflows/claude.yml | @claude mentions on issues and pull requests |
| .github/workflows/roadmap-sync.yml | Front matter ⇄ GitHub Issues, nightly |
| .github/workflows/sentral-report.yml + scripts/sentral-report.mjs | Each CI run's counts to Sentral, signed |

## Secrets and variables in GitHub
- ANTHROPIC_API_KEY (secret) — the claude workflow
- SENTRAL_CI_SECRET (secret) — the same value the owner stores in Sentral › Development › Vercel and Supabase › CI results
- SENTRAL_EVENTS_URL (variable) — Sentral's dev-events address, shown on that card

## Status flow
backlog → spec → in-progress → review → staging → rollout → done
`

const ROADMAP = `# Roadmap

Generated by Sentral (Development › Markdown roadmap) from its roadmap records. Change the records there, not this list.

## Now
- OP-412 Email-first signup — visit→account +25 %
- OP-401 Pulse surveys — pulse adoption 40 %
- BUG-118 Invitations to kommune.no — S1

## Next
- OP-427 Nynorsk survey — win municipal tenders
- OP-430 SSO with Entra ID — unblock 3 enterprise deals

## Later
- Two owners per tiltak
- Import employees from Visma
`

const FEATURE_TEMPLATE = `---
id: OP-000
title:
status: backlog        # backlog | spec | in-progress | review | staging | rollout | done
owner:
product: orgpuls       # orgpuls | skiftly | avvik | kurs | sentral
priority: P2           # P1 | P2 | P3
metric: ""             # the outcome this should move
flag:                  # feature flag key, or —
rollout: off           # off | internal | on — flags are on or off; a percentage needs a flag service that does not exist yet
spec:                  # RFC id, or —
links: []              # ids only: T-2316, PR #881, RFC-014 — never a customer's name, words or amounts
---

## Problem

## Acceptance criteria
-

## Tasks
- [ ]

## Log
`

const OP412 = `---
id: OP-412
title: Email-first signup
status: in-progress
owner: tor
product: orgpuls
priority: P1
metric: "visit→account +25 %"
flag: signup_email_first
rollout: internal
spec: RFC-014
links: [PR #881, RFC-014, funnel step 4]
---

## Problem
38 % of signup drop-offs happen at the org.nr step. Sole proprietorships fail the Brønnøysund lookup.

## Acceptance criteria
- Completion from step 1 to account created rises at least 15 % at 50 % rollout
- No rise in duplicate accounts
- No new read path to survey responses

## Tasks
- [x] Email + password step
- [x] Org.nr moved to step 2
- [x] Recovery email after 1 h
- [ ] Migration 0043_signup_email_first
- [ ] E2E test for both paths
- [ ] Help article updated

## Log
- 2026-10-12 claude: opened PR #881, 14 files, tests green
- 2026-10-11 tor: status → in-progress
`

const BUG_TEMPLATE = `---
id: BUG-000
title:
status: backlog
owner:
product: orgpuls
priority: S3           # S1 same business day 16:00 | S2 3 business days | S3 14 days
customers: 0           # a count, never names
links: []              # ids only: tickets (T-…), the known problem, the Sentral bug
---

## What happens

## Expected

## Steps to reproduce
1.

## Tasks
- [ ] Fix
- [ ] Regression test
- [ ] Close linked tickets and known problem
`

const START = `---
name: start
description: Start work on a roadmap item. Use when asked to begin a feature or bug by its id, e.g. "/start OP-412".
---
1. Find /roadmap/**/<id>-*.md and read it fully, plus the linked spec in /docs/specs.
2. Create branch \`<id>-<slug>\` from main.
3. Set front matter \`status: in-progress\`. Set \`owner: claude\` only if empty.
4. Commit \`<id>: start\` and open a draft PR whose body links the file and lists the tasks.
`

const SHIP = `---
name: ship
description: Prepare the current branch for review. Use when the work on a roadmap item is finished.
---
1. Run \`npm run lint\`, \`npx tsc --noEmit\`, \`npx vitest run\` and \`npm run test:db\`. Stop and report on any failure.
2. Run the code-reviewer and anonymity-guard subagents on the diff. Fix blocking findings.
3. Write the release note's draft in plain language in the PR body; the changelog is kept in Sentral › Development › Releases.
4. Tick finished tasks and set \`status: review\` in the feature file.
5. Mark the PR ready for review.
`

const TRIAGE = `---
name: triage
description: Turn a Sentral bug and its ticket numbers into a bug file. Use with the bug's id from Sentral › Development › Bug triage.
---
1. Take the bug's id, severity and ticket numbers from the person who asks. Never paste a ticket's text or a customer's name
   into the repository: git history cannot be erased.
2. Severity: S1 if survey invitations, signup or payments fail; S2 if one product area is blocked; else S3.
3. Create /roadmap/bugs/BUG-<n>-<slug>.md from _TEMPLATE.md with the ids as links and the steps to reproduce in your own words.
4. If a bug file already covers it, add the new ids there instead.
`

const PLAN = `---
name: plan-feature
description: Turn a feature request into a spec and task list. Use with a feature id.
---
1. Read the feature file and the ids it links (tickets, deals). Never copy a customer's name, words or amounts into the repository.
2. Write /docs/specs/RFC-<next>-<slug>.md: problem, options, decision, privacy and anonymity impact, rollout plan with flag.
3. Fill the Tasks list in the feature file with small, testable steps.
4. Set \`spec:\` and \`status: spec\`. Open a PR for review.
`

const REVIEWER = `---
name: code-reviewer
description: Reviews a diff for bugs, missing tests and convention breaks. Use proactively before /ship.
tools: Read, Grep, Glob, Bash
model: sonnet
---
Review the diff against main.
Report blocking issues first (bugs, security, missing tests for new logic), then suggestions.
Check that every new table has RLS enabled in the same migration, and that the answer tables (responses, answers,
extra_answers, response_comments) gain no policy and no grant. Check that no applied migration was edited. Never edit files.
`

const GUARD = `---
name: anonymity-guard
description: Checks that a change cannot expose survey answers or weaken k-anonymity (floor 3, default 5). Use on any change to supabase/ or to exports.
tools: Read, Grep, Glob
---
Search the diff for: a policy or a grant on responses, answers, extra_answers or response_comments; a column that could link
an answer to a person; a results read that does not apply app.k_round(); any change to app.k_floor() or app.k_min(); new
exports, logs or analytics events that include free text from surveys.
Fail with file and line for each finding. Pass only if none are found. This is a review aid: the SQL suites
(respondent_invariants.sql) are the control.
`

const SETTINGS = `{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": ".claude/hooks/protect.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "npm run lint --silent" }] }
    ]
  }
}
`

const PROTECT = `#!/usr/bin/env bash
# Blocks edits to files only humans may change, and edits to a migration that exists already (migrations are
# forward-only: add a new one). Exit 2 = block with message.
path=$(jq -r '.tool_input.file_path // empty')
case "$path" in
  *.env*|*.github/workflows/*|*CLAUDE.md)
    echo "Protected file: $path — open a PR by hand instead." >&2; exit 2 ;;
  *supabase/migrations/*)
    if [ -f "$path" ]; then echo "Migrations are forward-only: add a new one instead of editing $path." >&2; exit 2; fi ;;
esac
exit 0
`

const CLAUDE_YML = `name: claude
on:
  issue_comment: { types: [created] }
  pull_request_review_comment: { types: [created] }
  issues: { types: [opened, assigned] }
permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
jobs:
  claude:
    if: contains(github.event.comment.body, '@claude') || contains(github.event.issue.body, '@claude')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: \${{ secrets.ANTHROPIC_API_KEY }}
`

const ROADMAP_SYNC = `name: roadmap-sync
on:
  push: { branches: [main], paths: ["roadmap/**"] }
  issues: { types: [edited, closed, reopened] }
  pull_request: { types: [opened, closed] }
  schedule: [{ cron: "0 2 * * *" }]
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: node scripts/roadmap-sync.mjs     # front matter <-> GitHub issue + Project fields
        env: { GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }} }
`

const SENTRAL_REPORT_YML = `name: sentral-report
# Runs the gates and posts their counts to Sentral (Development › Releases, Code and environments, Delivery metrics).
# Ids, shas, counts and file names only — never test output or logs. In a repository that already has a CI job, add the
# last step to that job instead, after its gates.
on:
  push: { branches: [main] }
  pull_request:
jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm }
      - run: npm ci && mkdir -p reports
      - run: npx vitest run --reporter=json --outputFile=reports/vitest.json
        continue-on-error: true
      - run: npm audit --json > reports/audit.json
        continue-on-error: true
      # migrations not yet applied to production, one file name per line (e.g. from \`supabase migration list\`)
      - run: touch reports/pending-migrations.txt
      - run: >
          node scripts/sentral-report.mjs --product orgpuls
          --vitest unit=reports/vitest.json --audit reports/audit.json --pending reports/pending-migrations.txt
        env:
          SENTRAL_EVENTS_URL: \${{ vars.SENTRAL_EVENTS_URL }}
          SENTRAL_CI_SECRET: \${{ secrets.SENTRAL_CI_SECRET }}
          SENTRAL_PR: \${{ github.event.pull_request.number }}
`

const SENTRAL_REPORT_MJS = `#!/usr/bin/env node
// Posts this CI run's results to Sentral's dev-events, signed with SENTRAL_CI_SECRET:
//   x-sentral-timestamp: <unix seconds>
//   x-sentral-signature: sha256=<hex HMAC-SHA256 of "<timestamp>.<body>">
// Sentral refuses a post older than five minutes and keeps a delivery id once. It sends ids, shas, counts and file names:
// never test output, logs, or a commit message beyond its first line.
//
//   node scripts/sentral-report.mjs --product orgpuls \\
//     --vitest unit=reports/vitest.json          a vitest --reporter=json file, as a suite of kind "test"
//     --suite respondent_invariants:anonymity:21:0   name:kind:passed:failed (kinds: test security anonymity lint build other)
//     --audit reports/audit.json                 npm audit --json: the findings by severity
//     --coverage coverage/coverage-summary.json  istanbul json-summary: total lines in per cent
//     --pending reports/pending-migrations.txt   migration file names not yet applied to production
import { createHmac, randomUUID } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const url = process.env.SENTRAL_EVENTS_URL
const secret = process.env.SENTRAL_CI_SECRET
if (!url || !secret) {
  console.log('sentral-report: SENTRAL_EVENTS_URL or SENTRAL_CI_SECRET is not set; nothing sent')
  process.exit(0)
}
const args = process.argv.slice(2)
const all = (k) => args.flatMap((a, i) => (a === k && args[i + 1] ? [args[i + 1]] : []))
const one = (k) => all(k)[0] ?? null
const read = (p) => JSON.parse(readFileSync(p, 'utf8'))
const git = (...a) => execFileSync('git', a, { encoding: 'utf8' }).trim()

const product = one('--product')
const sha = process.env.GITHUB_SHA ?? git('rev-parse', 'HEAD')
const suites = []
for (const v of all('--vitest')) {
  const [name, path] = v.split('=')
  const r = read(path)
  suites.push({ name, kind: 'test', passed: r.numPassedTests ?? 0, failed: r.numFailedTests ?? 0, skipped: (r.numPendingTests ?? 0) + (r.numTodoTests ?? 0) })
}
for (const v of all('--suite')) {
  const [name, kind, passed, failed] = v.split(':')
  suites.push({ name, kind, passed: Number(passed), failed: Number(failed), skipped: 0 })
}
const audit = one('--audit') ? read(one('--audit')).metadata?.vulnerabilities ?? null : null
const coverage = one('--coverage') ? read(one('--coverage')).total?.lines?.pct ?? null : null
const pending = one('--pending') ? readFileSync(one('--pending'), 'utf8').split(/\\s+/).filter((f) => /^[0-9]{3,14}_[a-z0-9_]+\\.sql$/.test(f)) : []
const run = process.env.GITHUB_RUN_ID

const body = JSON.stringify({
  v: 1,
  delivery: \`\${run ?? randomUUID()}-\${process.env.GITHUB_RUN_ATTEMPT ?? '1'}-\${product}\`,
  product,
  sha,
  ref: process.env.GITHUB_HEAD_REF || process.env.GITHUB_REF_NAME || git('rev-parse', '--abbrev-ref', 'HEAD'),
  pr: process.env.SENTRAL_PR ? Number(process.env.SENTRAL_PR) : null,
  commit_at: git('show', '-s', '--format=%cI', sha),
  commit_title: git('show', '-s', '--format=%s', sha).slice(0, 200),
  run_url: run ? \`\${process.env.GITHUB_SERVER_URL}/\${process.env.GITHUB_REPOSITORY}/actions/runs/\${run}\` : null,
  finished_at: new Date().toISOString(),
  suites,
  migrations_pending: pending,
  dependencies: audit ? { critical: audit.critical ?? 0, high: audit.high ?? 0, moderate: audit.moderate ?? 0, low: audit.low ?? 0 } : null,
  coverage,
})
const ts = String(Math.floor(Date.now() / 1000))
const signature = 'sha256=' + createHmac('sha256', secret).update(\`\${ts}.\${body}\`).digest('hex')
const res = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', 'x-sentral-timestamp': ts, 'x-sentral-signature': signature }, body })
console.log(\`sentral-report: HTTP \${res.status}\`)
process.exit(res.ok ? 0 : 1)
`

const MCP = `{
  "mcpServers": {
    "github": { "type": "http", "url": "https://api.githubcopilot.com/mcp/" },
    "vercel": { "type": "http", "url": "https://mcp.vercel.com" }
  }
}
`

export const STARTER: StarterFile[] = [
  { id: 'claude_md', path: 'CLAUDE.md', group: 'memory', status: 'corrected', fixes: ['repos', 'npm', 'k', 'forward', 'suites'], body: CLAUDE_MD },
  { id: 'readme', path: 'README.md', group: 'memory', status: 'corrected', fixes: ['readsRepo', 'secrets', 'ciReport', 'repos'], body: README },
  { id: 'roadmap', path: 'roadmap/ROADMAP.md', group: 'roadmap', status: 'corrected', fixes: ['roadmapGen'], body: ROADMAP },
  { id: 'feature_template', path: 'roadmap/features/_TEMPLATE.md', group: 'roadmap', status: 'corrected', fixes: ['ids', 'rollout', 'sentry'], body: FEATURE_TEMPLATE },
  { id: 'op412', path: 'roadmap/features/OP-412-email-first-signup.md', group: 'roadmap', status: 'as_designed', fixes: [], body: OP412 },
  { id: 'bug_template', path: 'roadmap/bugs/_TEMPLATE.md', group: 'roadmap', status: 'corrected', fixes: ['targets', 'ids', 'sentry'], body: BUG_TEMPLATE },
  { id: 'start', path: '.claude/skills/start/SKILL.md', group: 'skills', status: 'as_designed', fixes: [], body: START },
  { id: 'ship', path: '.claude/skills/ship/SKILL.md', group: 'skills', status: 'corrected', fixes: ['npm', 'suites', 'changelog'], body: SHIP },
  { id: 'triage', path: '.claude/skills/triage/SKILL.md', group: 'skills', status: 'corrected', fixes: ['sentry', 'ids'], body: TRIAGE },
  { id: 'plan_feature', path: '.claude/skills/plan-feature/SKILL.md', group: 'skills', status: 'corrected', fixes: ['ids'], body: PLAN },
  { id: 'code_reviewer', path: '.claude/agents/code-reviewer.md', group: 'agents', status: 'corrected', fixes: ['rls', 'forward'], body: REVIEWER },
  { id: 'anonymity_guard', path: '.claude/agents/anonymity-guard.md', group: 'agents', status: 'corrected', fixes: ['k', 'guard'], body: GUARD },
  { id: 'settings', path: '.claude/settings.json', group: 'hooks', status: 'corrected', fixes: ['npm', 'stopHook'], body: SETTINGS },
  { id: 'protect', path: '.claude/hooks/protect.sh', group: 'hooks', status: 'corrected', fixes: ['protect', 'forward'], body: PROTECT },
  { id: 'log_to_sentral', path: '.claude/hooks/log-to-sentral.sh', group: 'hooks', status: 'removed', fixes: ['stopHook'], body: '' },
  { id: 'claude_yml', path: '.github/workflows/claude.yml', group: 'workflows', status: 'corrected', fixes: ['dispatch'], body: CLAUDE_YML },
  { id: 'roadmap_sync', path: '.github/workflows/roadmap-sync.yml', group: 'workflows', status: 'corrected', fixes: ['auditPost', 'npm'], body: ROADMAP_SYNC },
  { id: 'sentral_report_yml', path: '.github/workflows/sentral-report.yml', group: 'workflows', status: 'new', fixes: ['ciReport'], body: SENTRAL_REPORT_YML },
  { id: 'sentral_report_mjs', path: 'scripts/sentral-report.mjs', group: 'workflows', status: 'new', fixes: ['ciReport'], body: SENTRAL_REPORT_MJS },
  { id: 'mcp', path: '.mcp.json', group: 'mcp', status: 'corrected', fixes: ['mcpProd', 'sentry'], body: MCP },
]

export const starterFile = (id: string | null | undefined) => STARTER.find((f) => f.id === id) ?? STARTER[0]!
