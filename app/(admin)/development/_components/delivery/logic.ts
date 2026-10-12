/**
 * Development › the delivery half: what the views compute from the database's rows. Pure, so the tests run it and the
 * server and client views share it. Nothing here invents a value: a figure without rows is null and the view shows «—».
 */

/** the integrations register's rows (0080 app.dev_integrations) */
export const INTEGRATION_KEYS = ['search_console', 'pagespeed', 'google_ads', 'linkedin_ads', 'meta_ads', 'email', 'ai', 'orgpuls_api', 'vercel', 'ci'] as const
export type IntegrationKey = (typeof INTEGRATION_KEYS)[number]

/**
 * The API version each integration is pinned to in the edge functions' code (tests/v3-dev-delivery.test.ts proves each
 * against the constant it names). Null: not versioned in code — Orgpuls' version comes from its installation row, and
 * Vercel's webhook payload carries none.
 */
export const API_VERSIONS: Record<IntegrationKey, string | null> = {
  search_console: 'v3 · v1', // Search Analytics webmasters/v3 (_shared/google.ts API), URL Inspection v1 (INSPECT)
  pagespeed: 'v5', // _shared/pagespeed.ts PSI
  google_ads: 'v25', // _shared/ads.ts GOOGLE_API
  linkedin_ads: '202609', // _shared/ads.ts LINKEDIN_VERSION
  meta_ads: 'v26.0', // _shared/ads.ts META_API
  email: 'v3', // _shared/brevo.ts API
  ai: 'sdk 0.133.0', // ai-run/index.ts imports @anthropic-ai/sdk@0.133.0
  orgpuls_api: null,
  vercel: null,
  ci: 'v1', // _shared/dev-events.ts CI_PAYLOAD_VERSION
}

/** where «Renew token» goes: the real reconnection, in Growth › Integrations (0077 LinkedIn sign-in) */
export const RENEW_HREF: Partial<Record<IntegrationKey, string>> = { linkedin_ads: '/growth?tab=integrations&sub=linkedin_ads' }

export const SUITE_KINDS = ['test', 'security', 'anonymity', 'lint', 'build', 'other'] as const

/** the checklist (0080 app.delivery_release_checks), in the order each view lists it */
export const CHECK_KEYS = ['tests', 'migrations', 'rls', 'deps', 'deploy', 'notes', 'flag', 'anonymity', 'preview', 'rollback', 'help'] as const
export type CheckKey = (typeof CHECK_KEYS)[number]
/** Releases (DevHub «checks»): the design's eight in its order, then the gate's three it lacks */
export const RELEASE_ORDER: CheckKey[] = ['tests', 'migrations', 'deps', 'flag', 'anonymity', 'rollback', 'help', 'notes', 'rls', 'preview', 'deploy']
/** Release gate (DevClaude «gate»): the design's nine in its order, then the two from the release checklist */
export const GATE_ORDER: CheckKey[] = ['tests', 'migrations', 'rls', 'deps', 'preview', 'flag', 'help', 'notes', 'rollback', 'anonymity', 'deploy']
export const MANUAL: CheckKey[] = ['flag', 'anonymity', 'preview', 'rollback', 'help']

export type CheckState = 'pass' | 'fail' | 'unknown'
export function verdict(items: { state: CheckState }[]): { done: number; total: number; blocking: number; ready: boolean } {
  const done = items.filter((i) => i.state === 'pass').length
  return { done, total: items.length, blocking: items.length - done, ready: items.length > 0 && done === items.length }
}

export function orderChecks<T extends { key: CheckKey }>(items: T[], order: CheckKey[]): T[] {
  return [...items].sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key))
}

export const shortSha = (sha: string | null | undefined) => (sha ? sha.slice(0, 7) : null)

/** failed ÷ all runs, in per cent; null without runs */
export function errorRate(runs: { total: number; failed: number } | null): number | null {
  if (!runs || runs.total <= 0) return null
  return (100 * runs.failed) / runs.total
}

/** whole days from now until an instant (negative when past); null without one */
export function daysUntil(isoTime: string | null, nowMs: number): number | null {
  if (!isoTime) return null
  const t = Date.parse(isoTime)
  return Number.isNaN(t) ? null : Math.floor((t - nowMs) / 86_400_000)
}

/**
 * The DORA performance levels from the named report, for the metrics where its bands do not overlap. Source: DORA,
 * «Accelerate State of DevOps 2019», the software delivery performance table (Elite / High / Medium / Low):
 *   deployment frequency  Elite on demand (multiple deploys per day) · High once per day to once per week ·
 *                         Medium once per week to once per month · Low once per month to once every six months
 *   lead time for changes Elite less than one day · High one day to one week · Medium one week to one month ·
 *                         Low one month to six months
 *   time to restore       Elite less than one hour · High less than one day · Medium less than one day · Low one week to
 *                         one month — High and Medium share a band, so only Elite (and Low) are named
 *   change failure rate   Elite, High and Medium 0–15 % · Low 46–60 % — no level is named
 * Logged as V-V3E-22. Outside every band (e.g. a restore between one day and one week): no badge.
 */
export type DoraLevel = 'elite' | 'high' | 'medium' | 'low'
export function doraFrequency(perDay: number | null): DoraLevel | null {
  if (perDay === null || perDay <= 0) return null
  if (perDay > 1) return 'elite'
  if (perDay >= 1 / 7) return 'high'
  if (perDay >= 1 / 30) return 'medium'
  if (perDay >= 1 / 182) return 'low'
  return null
}
export function doraLeadTime(hours: number | null): DoraLevel | null {
  if (hours === null || hours < 0) return null
  if (hours < 24) return 'elite'
  if (hours <= 24 * 7) return 'high'
  if (hours <= 24 * 30) return 'medium'
  if (hours <= 24 * 182) return 'low'
  return null
}
export function doraRestore(minutes: number | null): DoraLevel | null {
  if (minutes === null || minutes < 0) return null
  if (minutes < 60) return 'elite'
  if (minutes >= 60 * 24 * 7 && minutes <= 60 * 24 * 30) return 'low'
  return null
}

/** a duration as the design writes it: «48 min», «5,5 h», «1,6 days» — the unit is a message key, the number formatted */
export function durationParts(minutes: number | null): { n: number; unit: 'min' | 'hours' | 'days' } | null {
  if (minutes === null || !Number.isFinite(minutes) || minutes < 0) return null
  if (minutes < 60) return { n: Math.round(minutes), unit: 'min' }
  if (minutes < 60 * 24) return { n: Math.round(minutes / 6) / 10, unit: 'hours' }
  return { n: Math.round(minutes / 144) / 10, unit: 'days' }
}

// ---------------------------------------------------------------------------
// Code and environments: one row per Vercel project, a cell per environment
export type DeploymentLite = {
  id: string; project_id: string; environment: string; state: 'building' | 'ready' | 'error' | 'canceled'; sha: string | null
  seen_at: string; ready_at: string | null; failed_at: string | null; promoted_at: string | null; rolled_back_at: string | null
}
export type ProjectLite = { id: string; name: string; product: string | null }

/** the environments as columns: Preview, any custom environment Vercel reported (e.g. Staging), Production */
export function environments(latest: { environment: string }[]): string[] {
  const custom = [...new Set(latest.map((d) => d.environment).filter((e) => e !== 'preview' && e !== 'production'))].sort()
  return ['preview', ...custom, 'production']
}

/** the dot's tone: ready green, building amber, failed or rolled back red, canceled grey */
export function deployTone(d: Pick<DeploymentLite, 'state' | 'rolled_back_at'>): 'ok' | 'warn' | 'alert' | 'muted' {
  if (d.rolled_back_at) return 'alert'
  return d.state === 'ready' ? 'ok' : d.state === 'building' ? 'warn' : d.state === 'error' ? 'alert' : 'muted'
}

/** when it last changed: rolled back, ready, failed, or first seen */
export const deployedAt = (d: DeploymentLite) => d.rolled_back_at ?? d.ready_at ?? d.failed_at ?? d.seen_at

export function envRows<D extends DeploymentLite>(projects: ProjectLite[], latest: D[]): { project: ProjectLite; cells: Record<string, D | undefined> }[] {
  return projects.map((p) => ({
    project: p,
    cells: Object.fromEntries(latest.filter((d) => d.project_id === p.id).map((d) => [d.environment, d])) as Record<string, D | undefined>,
  }))
}

// ---------------------------------------------------------------------------
// the CI card: the exact request a product's CI sends (the starter kit's scripts/sentral-report.mjs builds it). The
// repository is GitHub's owner/name; the owner binds it to its product in Sentral, or the post is refused (0080).
export const CI_HEADERS = `content-type: application/json
x-sentral-timestamp: <unix seconds>
x-sentral-signature: sha256=<hex HMAC-SHA256 of "<timestamp>.<body>" under SENTRAL_CI_SECRET>`

export const CI_EXAMPLE = `{
  "v": 1,
  "delivery": "<unique per post, e.g. \${GITHUB_RUN_ID}-\${GITHUB_RUN_ATTEMPT}-orgpuls>",
  "product": "orgpuls",
  "repository": "<owner>/<repo>",
  "sha": "<the full commit sha>",
  "ref": "main",
  "pr": null,
  "commit_at": "2026-10-12T09:41:07Z",
  "commit_title": "<the commit message's first line, at most 200 characters>",
  "run_url": "https://github.com/<owner>/<repo>/actions/runs/<id>",
  "finished_at": "2026-10-12T09:52:30Z",
  "suites": [
    { "name": "unit", "kind": "test", "passed": 412, "failed": 0, "skipped": 0 },
    { "name": "respondent_invariants", "kind": "anonymity", "passed": 21, "failed": 0 },
    { "name": "rls", "kind": "security", "passed": 64, "failed": 0 }
  ],
  "migrations_pending": ["0231_retry_queue.sql"],
  "dependencies": { "critical": 0, "high": 0, "moderate": 6, "low": 2 },
  "coverage": 81.5
}`
