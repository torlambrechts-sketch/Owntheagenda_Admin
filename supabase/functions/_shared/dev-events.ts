/**
 * dev-events' pure part, in Web Crypto so the edge function (Deno) and the tests (Node) run the same code.
 *
 *   Vercel   a deployment webhook (X-V3-1): `x-vercel-signature` is the hex HMAC-SHA1 of the raw body under the webhook's
 *            secret (Vercel's own scheme). The event's `createdAt` (milliseconds) is inside the signed body, so the five
 *            minutes are checked right after the signature; its `id` is the delivery id.
 *   CI       a product's CI run (sentral-report.mjs in the repo starter kit): `x-sentral-timestamp` (unix seconds) and
 *            `x-sentral-signature: sha256=<hex HMAC-SHA256 of "<timestamp>.<body>">` under the CI secret — the same scheme
 *            as Orgpuls' events (signing.ts verifyWebhook); `delivery` in the body is the delivery id.
 *
 * Both are reduced here to ids, shas, states, counts and file names: a commit message is cut to its first line (200
 * characters); test output, logs, authors and everything else in the payload are dropped. The database checks it all again.
 */
import { sameText, toHex } from './signing.ts'

const enc = new TextEncoder()

/** the CI payload's version: a CI that sends another is refused */
export const CI_PAYLOAD_VERSION = 1
export const SUITE_KINDS = ['test', 'security', 'anonymity', 'lint', 'build', 'other'] as const
/** the deployment events Sentral uses (Vercel: Team settings › Webhooks); any other kind is acknowledged and ignored */
export const VERCEL_KINDS = ['deployment.created', 'deployment.succeeded', 'deployment.ready', 'deployment.error', 'deployment.canceled', 'deployment.promoted'] as const
/** an event older (or newer) than this is refused, as rule 4 asks */
export const TOLERANCE_SEC = 300

const DELIVERY = /^[A-Za-z0-9._:-]{6,120}$/
const SHA = /^[0-9a-f]{7,40}$/

export async function hmacSha1Hex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign'])
  return toHex(new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(body))))
}

export type Refusal<R extends string> = { ok: false; reason: R }

/** Vercel's signature over the raw body, before anything is parsed */
export async function verifyVercel(input: { secret: string; signature: string | null; body: string }): Promise<{ ok: true } | Refusal<'missing' | 'signature'>> {
  const { secret, signature, body } = input
  if (!secret || secret.length < 16 || !signature || !/^[0-9a-f]{40}$/i.test(signature)) return { ok: false, reason: 'missing' }
  return sameText(signature.toLowerCase(), await hmacSha1Hex(secret, body)) ? { ok: true } : { ok: false, reason: 'signature' }
}

/** the first line of a text from outside, without control characters, at most `max` characters; empty is null */
export function firstLine(v: unknown, max = 200): string | null {
  if (typeof v !== 'string') return null
  // eslint-disable-next-line no-control-regex
  const line = (v.split(/\r?\n/)[0] ?? '').replace(/[\u0000-\u001f\u007f]+/g, ' ').trim().slice(0, max).trim()
  return line || null
}

const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {})
const str = (v: unknown, re: RegExp): string | null => (typeof v === 'string' && re.test(v) ? v : null)

export type VercelDeployment = {
  id: string
  project_id: string
  project_name: string
  environment: string
  sha: string | null
  ref: string | null
  pr: number | null
  commit_title: string | null
  host: string | null
  inspector_url: string | null
}
export type VercelEvent = { ok: true; delivery: string; kind: string; at: string; deployment: VercelDeployment | null }

/**
 * A verified Vercel body reduced to what Sentral keeps. Both payload shapes are read: the current one (payload.deployment,
 * payload.project, payload.links) and the older flat one (payload.deploymentId, payload.projectId, payload.name, payload.url).
 * The commit comes from the Git integration's meta (GitHub, GitLab or Bitbucket). Not a deployment event: deployment null.
 */
export function vercelEvent(json: unknown, nowMs: number): VercelEvent | Refusal<'body' | 'stale'> {
  const e = obj(json)
  const delivery = str(e.id, DELIVERY)
  const kind = str(e.type, /^[a-z][a-z_.-]{1,59}$/)
  const created = typeof e.createdAt === 'number' && Number.isFinite(e.createdAt) ? e.createdAt : null
  if (!delivery || !kind || created === null) return { ok: false, reason: 'body' }
  if (Math.abs(nowMs - created) > TOLERANCE_SEC * 1000) return { ok: false, reason: 'stale' }
  const at = new Date(created).toISOString()
  if (!kind.startsWith('deployment.')) return { ok: true, delivery, kind, at, deployment: null }

  const p = obj(e.payload)
  const d = obj(p.deployment)
  const meta = obj(d.meta ?? p.meta)
  const id = str(d.id ?? p.deploymentId, /^dpl_[A-Za-z0-9]{6,64}$/)
  const projectId = str(obj(p.project).id ?? p.projectId, /^prj_[A-Za-z0-9]{6,64}$/)
  const projectName = str(d.name ?? p.name, /^[A-Za-z0-9._-]{1,100}$/)
  if (!id || !projectId || !projectName) return { ok: false, reason: 'body' }
  const git = (k: string) => meta[`github${k}`] ?? meta[`gitlab${k}`] ?? meta[`bitbucket${k}`]
  const target = typeof p.target === 'string' && p.target ? p.target : null
  const host = str(d.url ?? p.url, /^[A-Za-z0-9.-]{3,253}$/)
  const pr = Number(meta.githubPrId ?? meta.bitbucketPrId ?? meta.gitlabMergeRequestIid ?? NaN)
  return {
    ok: true, delivery, kind, at,
    deployment: {
      id,
      project_id: projectId,
      project_name: projectName,
      environment: target && /^[a-z][a-z0-9-]{0,39}$/.test(target) ? target : 'preview',
      sha: str(typeof git('CommitSha') === 'string' ? (git('CommitSha') as string).toLowerCase() : null, SHA),
      ref: firstLine(git('CommitRef'), 200),
      pr: Number.isInteger(pr) && pr > 0 && pr < 1e8 ? pr : null,
      commit_title: firstLine(git('CommitMessage'), 200),
      host: host ? host.toLowerCase() : null,
      inspector_url: str(obj(p.links).deployment ?? d.inspectorUrl, /^https:\/\/vercel\.com\/[A-Za-z0-9._~/-]{1,250}$/),
    },
  }
}

export type CiSuite = { name: string; kind: (typeof SUITE_KINDS)[number]; passed: number; failed: number; skipped: number }
export type CiRun = {
  v: 1
  product: string
  sha: string
  ref: string | null
  pr: number | null
  commit_at: string | null
  commit_title: string | null
  run_url: string | null
  finished_at: string | null
  suites: CiSuite[]
  migrations_pending: string[]
  dependencies: { critical: number; high: number; moderate: number; low: number } | null
  coverage: number | null
}

const count = (v: unknown) => (typeof v === 'number' && Number.isInteger(v) && v >= 0 && v < 1e7 ? v : null)
const iso = (v: unknown) => (typeof v === 'string' && v.length <= 40 && !Number.isNaN(Date.parse(v)) ? new Date(v).toISOString() : null)

/** A verified CI body reduced to the documented fields (see the CI card and sentral-report.mjs); anything else is dropped. */
export function ciReport(json: unknown): { ok: true; delivery: string; run: CiRun } | Refusal<'body' | 'version'> {
  const b = obj(json)
  const delivery = str(b.delivery, DELIVERY)
  if (!delivery) return { ok: false, reason: 'body' }
  if (b.v !== CI_PAYLOAD_VERSION) return { ok: false, reason: 'version' }
  const product = str(b.product, /^[a-z][a-z0-9_]{1,30}$/)
  const sha = str(typeof b.sha === 'string' ? b.sha.toLowerCase() : null, SHA)
  if (!product || !sha) return { ok: false, reason: 'body' }
  const suitesIn = Array.isArray(b.suites) ? b.suites : []
  if (suitesIn.length > 40) return { ok: false, reason: 'body' }
  const suites: CiSuite[] = []
  for (const s of suitesIn) {
    const o = obj(s)
    const name = str(o.name, /^[A-Za-z0-9 ._:/()-]{1,60}$/)
    const kind = (SUITE_KINDS as readonly string[]).includes(o.kind as string) ? (o.kind as CiSuite['kind']) : null
    const passed = count(o.passed)
    const failed = count(o.failed)
    const skipped = o.skipped === undefined ? 0 : count(o.skipped)
    if (!name || !kind || passed === null || failed === null || skipped === null) return { ok: false, reason: 'body' }
    suites.push({ name, kind, passed, failed, skipped })
  }
  const pendingIn = Array.isArray(b.migrations_pending) ? b.migrations_pending : []
  if (pendingIn.length > 100 || pendingIn.some((f) => typeof f !== 'string' || !/^[0-9]{3,14}_[a-z0-9_]{1,80}\.sql$/.test(f))) return { ok: false, reason: 'body' }
  const dep = b.dependencies && typeof b.dependencies === 'object' ? obj(b.dependencies) : null
  const dependencies = dep ? { critical: count(dep.critical ?? 0), high: count(dep.high ?? 0), moderate: count(dep.moderate ?? 0), low: count(dep.low ?? 0) } : null
  if (dependencies && Object.values(dependencies).some((v) => v === null)) return { ok: false, reason: 'body' }
  const pr = count(b.pr)
  const coverage = typeof b.coverage === 'number' && b.coverage >= 0 && b.coverage <= 100 ? Math.round(b.coverage * 100) / 100 : null
  return {
    ok: true, delivery,
    run: {
      v: CI_PAYLOAD_VERSION,
      product, sha,
      ref: firstLine(b.ref, 200),
      pr: pr && pr > 0 ? pr : null,
      commit_at: iso(b.commit_at),
      commit_title: firstLine(b.commit_title, 200),
      run_url: str(b.run_url, /^https:\/\/[A-Za-z0-9.-]{3,100}\/[A-Za-z0-9._~/-]{1,250}$/),
      finished_at: iso(b.finished_at),
      suites,
      migrations_pending: pendingIn as string[],
      dependencies: dependencies as CiRun['dependencies'],
      coverage,
    },
  }
}
