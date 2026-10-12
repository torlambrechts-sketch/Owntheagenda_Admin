/**
 * ai-run — the one way Sentral reaches Claude (0078, X-V3-2). The app holds no Claude key; this does, read from Vault.
 *
 * POST {"feature": "<key>", "subject": "<uuid>"} with the staff member's own token.
 *   1. ai_prepare, called as that person: their right for the feature, the key stored, the hourly cap; then the feature's
 *      registered context function (app.ai_ctx_*) builds the input from Sentral's own records. Nothing the caller sends
 *      but the feature key and the subject id reaches Claude: never ticket text, never survey data (rule 6).
 *   2. One Messages API call through the official SDK, with the server-side refusal fallback.
 *   3. worker_ai_record: the call (model, tokens, latency, a state and a code) and the draft, if any.
 *
 * Logs carry kinds, counts and status codes. Never a prompt, a draft or a key.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import Anthropic from 'npm:@anthropic-ai/sdk@0.133.0'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const log = (s: string) => console.log(`[ai-run] ${s}`)
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const FEATURE = /^[a-z][a-z_]{2,39}$/

type Prepared = { feature: string; subject: string; staff: string; model: string; effort: 'low' | 'medium' | 'high'; max_tokens: number; system: string; prompt: string }

/** the database's refusal, reduced to a code the app knows */
function refusal(message: string | undefined): { code: string; status: number } {
  if (message === 'forbidden' || message === 'not_signed_in') return { code: 'forbidden', status: 403 }
  if (message === 'not_connected') return { code: 'not_connected', status: 409 }
  if (message === 'rate_limited') return { code: 'rate_limited', status: 429 }
  if (message === 'not_found') return { code: 'not_found', status: 404 }
  return { code: 'invalid', status: 400 }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  if (!url || !serviceKey || !anonKey) return json({ ok: false, code: 'not_configured' }, 503)

  let body: { feature?: unknown; subject?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 500) return json({ ok: false, code: 'too_large' }, 413)
    body = JSON.parse(raw)
  } catch {
    return json({ ok: false, code: 'invalid' }, 400)
  }
  const feature = typeof body.feature === 'string' && FEATURE.test(body.feature) ? body.feature : null
  const subject = typeof body.subject === 'string' && UUID.test(body.subject) ? body.subject : null
  if (!feature || !subject) return json({ ok: false, code: 'invalid' }, 400)

  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token || token === serviceKey) return json({ ok: false, code: 'forbidden' }, 401)
  const asUser = createClient(url, anonKey, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } })
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })

  const prep = await asUser.rpc('ai_prepare', { p_feature: feature, p_subject: subject })
  if (prep.error) {
    const r = refusal(prep.error.message)
    log(`${feature} refused ${r.code}`)
    return json({ ok: false, code: r.code }, r.status)
  }
  const p = prep.data as Prepared
  const { data: key } = await svc.rpc('product_secret', { p_name: 'anthropic_api_key' })
  if (typeof key !== 'string' || !key) return json({ ok: false, code: 'not_connected' }, 409)

  const record = (state: string, error: string | null, text: string | null, input = 0, output = 0, latency = 0, model = p.model) =>
    svc.rpc('worker_ai_record', { p_feature: p.feature, p_subject: p.subject, p_staff: p.staff, p_body: text, p_model: model,
                                  p_input: input, p_output: output, p_latency: latency, p_state: state, p_error: error })

  const client = new Anthropic({ apiKey: key, maxRetries: 2, timeout: 120_000 })
  const started = Date.now()
  try {
    const msg = await client.beta.messages.create({
      model: p.model,
      max_tokens: p.max_tokens,
      system: p.system,
      messages: [{ role: 'user', content: p.prompt }],
      output_config: { effort: p.effort },
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
    })
    const latency = Date.now() - started
    const usage = { input: msg.usage.input_tokens ?? 0, output: msg.usage.output_tokens ?? 0 }
    if (msg.stop_reason === 'refusal') {
      await record('invalid', 'refusal', null, usage.input, usage.output, latency, msg.model)
      log(`${p.feature} refusal`)
      return json({ ok: false, code: 'refused' }, 422)
    }
    const text = msg.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('\n').trim()
    if (!text) {
      await record('invalid', 'empty', null, usage.input, usage.output, latency, msg.model)
      return json({ ok: false, code: 'empty' }, 502)
    }
    const truncated = msg.stop_reason === 'max_tokens'
    const { data: rec, error } = await record('ok', null, text, usage.input, usage.output, latency, msg.model)
    if (error) {
      log(`${p.feature} record refused ${error.code ?? ''}`.trim())
      return json({ ok: false, code: 'record' }, 500)
    }
    log(`${p.feature} ok in=${usage.input} out=${usage.output} ms=${latency}${truncated ? ' truncated' : ''}`)
    return json({ ok: true, output: (rec as { output: string | null }).output, truncated })
  } catch (e) {
    const latency = Date.now() - started
    const status = e instanceof Anthropic.APIError ? e.status ?? 0 : 0
    const code = e instanceof Anthropic.AuthenticationError ? 'bad_key'
      : e instanceof Anthropic.RateLimitError ? 'provider_rate_limited'
      : e instanceof Anthropic.BadRequestError ? 'provider_invalid'
      : e instanceof Anthropic.APIConnectionError ? 'network'
      : status >= 500 ? 'provider_unavailable' : 'error'
    await record(code === 'bad_key' ? 'not_connected' : 'error', code, null, 0, 0, latency)
    log(`${p.feature} failed ${code}`)
    return json({ ok: false, code }, code === 'bad_key' ? 409 : 502)
  }
})
