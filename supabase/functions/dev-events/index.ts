/**
 * dev-events — deploys and build facts in (0080, PLAN.md X-V3-1): Vercel's deployment webhooks and the products' CI runs.
 *
 * Rule 4's discipline for both. The signature is checked on the raw body before it is parsed: Vercel's
 * `x-vercel-signature` (HMAC-SHA1 under vercel_signing_secret), or the CI's `x-sentral-timestamp` and
 * `x-sentral-signature` (HMAC-SHA256 of "<timestamp>.<body>" under ci_signing_secret). Anything older than five minutes is
 * refused (Vercel's signed createdAt, the CI's signed timestamp), and the delivery id (Vercel's event id, the CI's
 * `delivery`) makes a repeat a duplicate. Both secrets live in this project's Vault and are read here only; Sentral holds
 * no Vercel token and no product's Supabase token.
 *
 * What reaches the database is reduced first (_shared/dev-events.ts): ids, shas, states, a branch, a PR number, counts,
 * migration file names and a commit's first line. Logs carry the source, the kind and the outcome, never a payload.
 * `verify_jwt` is off: the callers are Vercel and a CI, which hold only their signing secret.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { verifyWebhook } from '../_shared/signing.ts'
import { ciReport, vercelEvent, verifyVercel } from '../_shared/dev-events.ts'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const log = (s: string) => console.log(`[dev-events] ${s}`)
const LIMIT = 256_000

/** the database's refusal as a status: stale and malformed are final (4xx), anything else may be retried (5xx) */
const status = (message: string | undefined) => (message === 'stale' ? 401 : message === 'invalid' ? 400 : 500)

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  if (Number(req.headers.get('content-length') ?? '0') > LIMIT) return json({ error: 'too_large' }, 413)
  const body = await req.text()
  if (body.length > LIMIT) return json({ error: 'too_large' }, 413)

  const svc = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', { auth: { persistSession: false } })
  const secret = async (name: string) => {
    const { data } = await svc.rpc('product_secret', { p_name: name })
    return typeof data === 'string' ? data : ''
  }

  // Vercel
  const vercelSignature = req.headers.get('x-vercel-signature')
  if (vercelSignature !== null) {
    const check = await verifyVercel({ secret: await secret('vercel_signing_secret'), signature: vercelSignature, body })
    if (!check.ok) {
      log(`vercel refused: ${check.reason}`)
      return json({ error: 'unauthorized' }, 401)
    }
    let parsed: unknown
    try {
      parsed = JSON.parse(body)
    } catch {
      return json({ error: 'body' }, 400)
    }
    const ev = vercelEvent(parsed, Date.now())
    if (!ev.ok) {
      log(`vercel refused: ${ev.reason}`)
      return json({ error: ev.reason }, ev.reason === 'stale' ? 401 : 400)
    }
    if (!ev.deployment) {
      log(`vercel ${ev.kind}: ignored`)
      return json({ ignored: true })
    }
    const { data, error } = await svc.rpc('worker_dev_vercel', { p_delivery: ev.delivery, p_kind: ev.kind, p_at: ev.at, p_d: ev.deployment })
    if (error) {
      log(`vercel ${ev.kind}: refused by the database (${error.message === 'stale' || error.message === 'invalid' ? error.message : error.code ?? 'error'})`)
      return json({ error: 'ingest' }, status(error.message))
    }
    const r = (data ?? {}) as { duplicate?: boolean; ignored?: boolean }
    log(`vercel ${ev.kind}: ${r.duplicate ? 'duplicate' : r.ignored ? 'ignored' : 'applied'}`)
    return json(data)
  }

  // a product's CI
  const ciSignature = req.headers.get('x-sentral-signature')
  if (ciSignature !== null) {
    const timestamp = req.headers.get('x-sentral-timestamp')
    const ci = await secret('ci_signing_secret')
    const check = await verifyWebhook({ secret: ci.length >= 32 ? ci : '', timestamp, signature: ciSignature, body, nowSec: Math.floor(Date.now() / 1000) })
    if (!check.ok) {
      log(`ci refused: ${check.reason}`)
      return json({ error: 'unauthorized' }, 401)
    }
    let parsed: unknown
    try {
      parsed = JSON.parse(body)
    } catch {
      return json({ error: 'body' }, 400)
    }
    const rep = ciReport(parsed)
    if (!rep.ok) {
      log(`ci refused: ${rep.reason}`)
      return json({ error: rep.reason }, 400)
    }
    const at = new Date(Number(timestamp) * 1000).toISOString()
    const { data, error } = await svc.rpc('worker_dev_ci', { p_delivery: rep.delivery, p_at: at, p_run: rep.run })
    if (error) {
      log(`ci: refused by the database (${error.message === 'stale' || error.message === 'invalid' ? `${error.message} ${error.details ?? ''}`.trim() : error.code ?? 'error'})`)
      return json({ error: 'ingest', detail: error.message === 'invalid' ? error.details : undefined }, status(error.message))
    }
    const r = (data ?? {}) as { duplicate?: boolean; suites?: number }
    log(`ci ${rep.run.product}: ${r.duplicate ? 'duplicate' : `applied, ${r.suites ?? 0} suites`}`)
    return json(data)
  }

  return json({ error: 'unauthorized' }, 401)
})
