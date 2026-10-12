import { createHmac } from 'node:crypto'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { GOOGLE_API, LINKEDIN_VERSION, META_API } from '../supabase/functions/_shared/ads'
import { PSI } from '../supabase/functions/_shared/pagespeed'
import { verifyWebhook } from '../supabase/functions/_shared/signing'
import {
  CI_PAYLOAD_VERSION, SUITE_KINDS as EDGE_SUITE_KINDS, TOLERANCE_SEC, ciReport, firstLine, hmacSha1Hex, vercelEvent, verifyVercel,
} from '../supabase/functions/_shared/dev-events'
import {
  API_VERSIONS, CHECK_KEYS, CI_EXAMPLE, GATE_ORDER, INTEGRATION_KEYS, MANUAL, RELEASE_ORDER, SUITE_KINDS, daysUntil, doraFrequency, doraLeadTime,
  doraRestore, durationParts, environments, errorRate, orderChecks, verdict,
} from '../app/(admin)/development/_components/delivery/logic'
import { FIXES, STARTER, starterFile } from '../app/(admin)/development/_components/delivery/starter'

const read = (p: string) => readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
const migration = read('supabase/migrations/0080_dev_delivery.sql')

// ---------------------------------------------------------------------------
describe('the API version registry matches the edge functions', () => {
  it('pins each version the code calls', () => {
    expect(GOOGLE_API.endsWith(`/${API_VERSIONS.google_ads}`)).toBe(true)
    expect(API_VERSIONS.linkedin_ads).toBe(LINKEDIN_VERSION)
    expect(META_API.endsWith(`/${API_VERSIONS.meta_ads}`)).toBe(true)
    expect(PSI).toContain(`/pagespeedonline/${API_VERSIONS.pagespeed}/`)
    const google = read('supabase/functions/_shared/google.ts')
    const [sa, inspect] = API_VERSIONS.search_console!.split(' · ')
    expect(google).toMatch(new RegExp(`const API = 'https://www\\.googleapis\\.com/webmasters/${sa}'`))
    expect(google).toMatch(new RegExp(`searchconsole\\.googleapis\\.com/${inspect}/urlInspection`))
    expect(read('supabase/functions/_shared/brevo.ts')).toContain(`const API = 'https://api.brevo.com/${API_VERSIONS.email}'`)
    expect(read('supabase/functions/ai-run/index.ts')).toContain(`npm:@anthropic-ai/sdk@${API_VERSIONS.ai!.replace('sdk ', '')}'`)
    expect(API_VERSIONS.ci).toBe(`v${CI_PAYLOAD_VERSION}`)
  })

  it('has a row for exactly the integrations the migration seeds', () => {
    const block = migration.slice(migration.indexOf('insert into app.dev_integrations'), migration.indexOf('on conflict (key) do nothing'))
    const seeded = [...block.matchAll(/\('([a-z_]+)', \d+, '(?:out|in)'/g)].map((m) => m[1])
    expect(seeded).toEqual([...INTEGRATION_KEYS])
  })

  it('knows the same suite kinds as dev-events and the database', () => {
    expect([...SUITE_KINDS]).toEqual([...EDGE_SUITE_KINDS])
    expect(migration).toContain(`not in (${SUITE_KINDS.map((k) => `'${k}'`).join(', ')})`)
  })
})

// ---------------------------------------------------------------------------
describe('the checklist', () => {
  it('lists every item once in each view, and the manual ones are the database\'s', () => {
    expect([...RELEASE_ORDER].sort()).toEqual([...CHECK_KEYS].sort())
    expect([...GATE_ORDER].sort()).toEqual([...CHECK_KEYS].sort())
    expect(migration).toContain(`item in (${MANUAL.map((k) => `'${k}'`).join(', ')})`)
    // the design's eight come first on Releases, the design's nine first on the gate
    expect(RELEASE_ORDER.slice(0, 8)).toEqual(['tests', 'migrations', 'deps', 'flag', 'anonymity', 'rollback', 'help', 'notes'])
    expect(GATE_ORDER.slice(0, 9)).toEqual(['tests', 'migrations', 'rls', 'deps', 'preview', 'flag', 'help', 'notes', 'rollback'])
  })

  it('is ready only when every item passes; unknown is not a pass', () => {
    expect(verdict([{ state: 'pass' }, { state: 'pass' }])).toEqual({ done: 2, total: 2, blocking: 0, ready: true })
    expect(verdict([{ state: 'pass' }, { state: 'unknown' }])).toMatchObject({ done: 1, blocking: 1, ready: false })
    expect(verdict([])).toMatchObject({ ready: false })
    expect(orderChecks([{ key: 'deploy' as const }, { key: 'tests' as const }], GATE_ORDER).map((c) => c.key)).toEqual(['tests', 'deploy'])
  })
})

// ---------------------------------------------------------------------------
describe('metrics', () => {
  it('names DORA levels only where the 2019 bands do not overlap', () => {
    expect(doraFrequency(4.2)).toBe('elite')
    expect(doraFrequency(1)).toBe('high')
    expect(doraFrequency(1 / 7)).toBe('high')
    expect(doraFrequency(1 / 10)).toBe('medium')
    expect(doraFrequency(1 / 60)).toBe('low')
    expect(doraFrequency(1 / 400)).toBeNull()
    expect(doraFrequency(0)).toBeNull()
    expect(doraLeadTime(5)).toBe('elite')
    expect(doraLeadTime(38)).toBe('high')
    expect(doraLeadTime(24 * 20)).toBe('medium')
    expect(doraLeadTime(24 * 90)).toBe('low')
    expect(doraLeadTime(null)).toBeNull()
    expect(doraRestore(48)).toBe('elite')
    expect(doraRestore(60 * 5)).toBeNull() // High and Medium share «less than one day»
    expect(doraRestore(60 * 24 * 3)).toBeNull() // no band
    expect(doraRestore(60 * 24 * 10)).toBe('low')
  })

  it('writes durations as the design does and refuses what is not one', () => {
    expect(durationParts(48)).toEqual({ n: 48, unit: 'min' })
    expect(durationParts(330)).toEqual({ n: 5.5, unit: 'hours' })
    expect(durationParts(1.6 * 1440)).toEqual({ n: 1.6, unit: 'days' })
    expect(durationParts(null)).toBeNull()
    expect(durationParts(-1)).toBeNull()
  })

  it('has no error rate without runs and counts days to an expiry', () => {
    expect(errorRate(null)).toBeNull()
    expect(errorRate({ total: 0, failed: 0 })).toBeNull()
    expect(errorRate({ total: 250, failed: 2 })).toBeCloseTo(0.8)
    const now = Date.parse('2026-10-12T10:00:00Z')
    expect(daysUntil('2026-10-18T12:00:00Z', now)).toBe(6)
    expect(daysUntil('2026-10-11T12:00:00Z', now)).toBe(-1)
    expect(daysUntil(null, now)).toBeNull()
  })

  it('shows Preview and Production, and another column only when Vercel reports one', () => {
    expect(environments([{ environment: 'production' }])).toEqual(['preview', 'production'])
    expect(environments([{ environment: 'production' }, { environment: 'staging' }, { environment: 'preview' }])).toEqual(['preview', 'staging', 'production'])
  })
})

// ---------------------------------------------------------------------------
describe('Vercel in', () => {
  const secret = 'abcdefghijklmnopqrstuvwx'
  const now = 1_790_000_000_000
  const event = (over: Record<string, unknown> = {}) => ({
    id: 'evt_abc123', type: 'deployment.succeeded', createdAt: now - 1000, region: 'arn1',
    payload: {
      target: 'production', project: { id: 'prj_abcdef12' },
      deployment: { id: 'dpl_abcdef12', name: 'orgpuls-web', url: 'Orgpuls-Web-abc.vercel.app',
        meta: { githubCommitSha: 'A'.repeat(40), githubCommitRef: 'main', githubCommitMessage: 'Fix reminders\n\nThe body names a customer', githubCommitAuthorName: 'Tor', githubPrId: '881' } },
      links: { deployment: 'https://vercel.com/team/orgpuls-web/dpl_abcdef12' },
    },
    ...over,
  })

  it('checks Vercel\'s own signature (HMAC-SHA1 of the raw body) before anything is parsed', async () => {
    const body = JSON.stringify(event())
    const sig = createHmac('sha1', secret).update(body).digest('hex')
    expect(await hmacSha1Hex(secret, body)).toBe(sig)
    expect(await verifyVercel({ secret, signature: sig, body })).toEqual({ ok: true })
    expect(await verifyVercel({ secret, signature: sig.toUpperCase(), body })).toEqual({ ok: true })
    expect(await verifyVercel({ secret, signature: sig, body: body.replace('succeeded', 'error') })).toEqual({ ok: false, reason: 'signature' })
    expect(await verifyVercel({ secret: 'x'.repeat(24), signature: sig, body })).toEqual({ ok: false, reason: 'signature' })
    expect(await verifyVercel({ secret: 'short', signature: sig, body })).toEqual({ ok: false, reason: 'missing' })
    expect(await verifyVercel({ secret, signature: null, body })).toEqual({ ok: false, reason: 'missing' })
    expect(await verifyVercel({ secret, signature: 'sha1=' + sig, body })).toEqual({ ok: false, reason: 'missing' })
  })

  it('keeps ids, a commit, a branch, a PR number and the first line of the message', () => {
    const r = vercelEvent(event(), now)
    expect(r).toEqual({
      ok: true, delivery: 'evt_abc123', kind: 'deployment.succeeded', at: new Date(now - 1000).toISOString(),
      deployment: { id: 'dpl_abcdef12', project_id: 'prj_abcdef12', project_name: 'orgpuls-web', environment: 'production', sha: 'a'.repeat(40), ref: 'main',
        pr: 881, commit_title: 'Fix reminders', host: 'orgpuls-web-abc.vercel.app', inspector_url: 'https://vercel.com/team/orgpuls-web/dpl_abcdef12' },
    })
    expect(JSON.stringify(r)).not.toContain('customer')
    expect(JSON.stringify(r)).not.toContain('Tor')
  })

  it('refuses an event older or newer than five minutes', () => {
    expect(vercelEvent(event({ createdAt: now - (TOLERANCE_SEC + 1) * 1000 }), now)).toEqual({ ok: false, reason: 'stale' })
    expect(vercelEvent(event({ createdAt: now + (TOLERANCE_SEC + 1) * 1000 }), now)).toEqual({ ok: false, reason: 'stale' })
    expect(vercelEvent(event({ createdAt: '1790000000000' }), now)).toEqual({ ok: false, reason: 'body' })
  })

  it('reads a preview, the older flat payload, and leaves other kinds alone', () => {
    const preview = vercelEvent(event({ payload: { ...event().payload, target: null } }), now)
    expect(preview.ok && preview.deployment?.environment).toBe('preview')
    const flat = vercelEvent({ id: 'evt_flat01', type: 'deployment.created', createdAt: now, payload: { deploymentId: 'dpl_flat0001', projectId: 'prj_flat0001', name: 'sentral', url: 'sentral-x.vercel.app', meta: {} } }, now)
    expect(flat.ok && flat.deployment).toMatchObject({ id: 'dpl_flat0001', project_id: 'prj_flat0001', project_name: 'sentral', sha: null, inspector_url: null })
    expect(vercelEvent({ id: 'evt_proj01', type: 'project.created', createdAt: now, payload: {} }, now)).toMatchObject({ ok: true, deployment: null })
    const evil = vercelEvent(event({ payload: { ...event().payload, links: { deployment: 'https://evil.example/x' } } }), now)
    expect(evil.ok && evil.deployment?.inspector_url).toBeNull()
  })

  it('cuts a text to its first line without control characters', () => {
    expect(firstLine('One\r\nTwo')).toBe('One')
    expect(firstLine('a\u0007b')).toBe('a b')
    expect(firstLine('x'.repeat(300))?.length).toBe(200)
    expect(firstLine('   ')).toBeNull()
    expect(firstLine(42)).toBeNull()
  })
})

// ---------------------------------------------------------------------------
describe('CI in', () => {
  // the card's example with its placeholders filled in
  const example = () => JSON.parse(CI_EXAMPLE.replace('<the full commit sha>', 'a'.repeat(40)).replace(/<the commit message[^>]*>/, 'Fix reminders')
    .replace(/<unique per post[^>]*>/, 'run-123-1-orgpuls').replace('<owner>/<repo>', 'o/r').replace('<id>', '1'))

  it('accepts the documented example and keeps only its documented fields', () => {
    const body = { ...example(), run_url: 'https://github.com/o/r/actions/runs/1', output: 'test output never kept', log: 'never kept' }
    const r = ciReport(body)
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(Object.keys(r.run).sort()).toEqual(['commit_at', 'commit_title', 'coverage', 'dependencies', 'finished_at', 'migrations_pending', 'pr', 'product', 'ref', 'run_url', 'sha', 'suites', 'v'])
    expect(r.run.suites[1]).toEqual({ name: 'respondent_invariants', kind: 'anonymity', passed: 21, failed: 0, skipped: 0 })
    expect(r.run.migrations_pending).toEqual(['0231_retry_queue.sql'])
    expect(JSON.stringify(r)).not.toContain('never kept')
  })

  it('refuses another version, an unknown kind, a path for a migration, a bad sha', () => {
    expect(ciReport({ ...example(), v: 2 })).toEqual({ ok: false, reason: 'version' })
    expect(ciReport({ ...example(), suites: [{ name: 'unit', kind: 'vibes', passed: 1, failed: 0 }] })).toEqual({ ok: false, reason: 'body' })
    expect(ciReport({ ...example(), migrations_pending: ['../../etc/passwd'] })).toEqual({ ok: false, reason: 'body' })
    expect(ciReport({ ...example(), sha: 'main' })).toEqual({ ok: false, reason: 'body' })
    expect(ciReport({ ...example(), delivery: 'x' })).toEqual({ ok: false, reason: 'body' })
    expect(ciReport({ ...example(), dependencies: { high: -1 } })).toEqual({ ok: false, reason: 'body' })
  })

  it('is signed the way the starter kit\'s script signs it, and checked like the products\' events', async () => {
    const script = starterFile('sentral_report_mjs').body
    expect(script).toContain("'x-sentral-timestamp': ts")
    expect(script).toContain("'x-sentral-signature': signature")
    expect(script).toContain("createHmac('sha256', secret).update(`${ts}.${body}`).digest('hex')")
    const secret = 'c'.repeat(64)
    const body = JSON.stringify(example())
    const ts = 1_790_000_000
    const signature = 'sha256=' + createHmac('sha256', secret).update(`${ts}.${body}`).digest('hex')
    expect(await verifyWebhook({ secret, timestamp: String(ts), signature, body, nowSec: ts + 5 })).toEqual({ ok: true })
    expect(await verifyWebhook({ secret, timestamp: String(ts), signature, body, nowSec: ts + TOLERANCE_SEC + 1 })).toEqual({ ok: false, reason: 'stale' })
  })
})

// ---------------------------------------------------------------------------
describe('the repo starter kit', () => {
  const files = (dir: string): string[] => readdirSync(dir).flatMap((f) => (statSync(join(dir, f)).isDirectory() ? files(join(dir, f)) : [join(dir, f)]))
  const root = new URL('../design-reference/sentral-simple/repo-starter/', import.meta.url).pathname

  it('serves every file of the design\'s kit, plus the CI report', () => {
    const design = files(root).map((f) => f.slice(root.length)).sort()
    const ours = STARTER.map((f) => f.path)
    for (const p of design) expect(ours).toContain(p)
    expect(STARTER.filter((f) => f.status === 'new').map((f) => f.path)).toEqual(['.github/workflows/sentral-report.yml', 'scripts/sentral-report.mjs'])
  })

  it('carries none of the contradictions it corrects', () => {
    const all = STARTER.map((f) => f.body).join('\n')
    for (const bad of ['pnpm', 'n >= 5', 'apps/sentral', 'monorepo', 'repository_dispatch', 'client_payload', 'SENTRAL_WEBHOOK_TOKEN', 'VERCEL_TOKEN',
      'mcp.supabase.com', 'sentry.dev', 'Sentry MCP', 'reversible', 'log-to-sentral', 'supabase test db']) {
      expect(all, bad).not.toContain(bad)
    }
    expect(starterFile('claude_md').body).toContain('floor 3 (app.k_floor()), default 5 (app.k_min())')
    expect(starterFile('log_to_sentral')).toMatchObject({ status: 'removed', body: '' })
  })

  it('lists each correction against the files it changed, and every correction is used', () => {
    const used = new Set(STARTER.flatMap((f) => f.fixes))
    expect([...used].sort()).toEqual([...FIXES].sort())
    for (const f of STARTER) expect(f.status === 'as_designed' ? f.fixes.length === 0 : f.fixes.length > 0, f.path).toBe(true)
  })

  it('has the words for every file and correction in both languages', () => {
    for (const lang of ['en', 'no']) {
      const m = JSON.parse(read(`messages/${lang}/dev-delivery.json`)).devDelivery.repo
      for (const f of STARTER) expect(m.what[f.id], `${lang} what.${f.id}`).toBeTruthy()
      for (const k of FIXES) expect(m.fix[k], `${lang} fix.${k}`).toBeTruthy()
    }
  })
})
