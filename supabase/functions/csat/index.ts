/**
 * csat — the customer's answer to «How satisfied are you with the help you got?» in the email that resolves their ticket
 * (0081). The email's five links open the public page /u/csat/<token> (app/u/csat), which asks this function.
 *
 * PUBLIC, and why: the customer has no account in Sentral and never will (rules 1–2 are for staff). The authority is the
 * single-use token: 32 random characters whose SHA-256 alone is stored on the ticket, valid for 30 days, spent by the first
 * score. It opens nothing but that ticket's score: no ticket, name or text is read or returned.
 *
 *   POST {"action": "peek", "token"}            is the token still open? (and the application's sender name, for the page)
 *   POST {"action": "answer", "token", "score"} records a score 1–5
 *
 * The token travels in the body, never in an address this function's platform logs. A database error is answered 503, so
 * the page says «try again» and never «already used». Logs carry the outcome only, never a token.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { parseCsat } from '../_shared/csat.ts'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-robots-tag': 'noindex' },
})
const log = (s: string) => console.log(`[csat] ${s}`)

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    await req.body?.cancel()
    return json({ error: 'method' }, 405)
  }
  if (Number(req.headers.get('content-length') ?? 0) > 1_000) {
    await req.body?.cancel()
    return json({ error: 'too_large' }, 413)
  }
  let raw: string
  try {
    raw = await req.text()
  } catch {
    return json({ error: 'body' }, 400)
  }
  const a = parseCsat(req.method, raw)
  if ('invalid' in a) {
    log('invalid')
    return json({ error: 'invalid' }, 400)
  }
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!url || !key) return json({ error: 'unavailable' }, 503)
  const svc = createClient(url, key, { auth: { persistSession: false } })

  if ('peek' in a) {
    const { data, error } = await svc.rpc('worker_csat_peek', { p_token: a.peek })
    const d = (data ?? {}) as { open?: unknown; from_name?: unknown }
    if (error || typeof d.open !== 'boolean') {
      log(`peek unavailable ${error?.code ?? ''}`.trim())
      return json({ error: 'unavailable' }, 503)
    }
    return json({ open: d.open, from_name: typeof d.from_name === 'string' ? d.from_name : null })
  }

  const { data, error } = await svc.rpc('worker_csat_submit', { p_token: a.answer.token, p_score: a.answer.score })
  const r = (data ?? {}) as { ok?: unknown; code?: unknown }
  if (error || typeof r.ok !== 'boolean') {
    log(`answer unavailable ${error?.code ?? ''}`.trim())
    return json({ error: 'unavailable' }, 503)
  }
  log(r.ok ? 'recorded' : typeof r.code === 'string' ? r.code : 'refused')
  return json(r.ok ? { recorded: true, score: a.answer.score } : { recorded: false, code: typeof r.code === 'string' ? r.code : 'refused' })
})
