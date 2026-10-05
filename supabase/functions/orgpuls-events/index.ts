/**
 * orgpuls-events — Orgpuls' events in (its 0205: app.platform_emit, delivered by orgpuls-dispatch).
 *
 * One signed POST per dispatch run, `{"events": [{id, kind, org_id, payload, created_at}, ...]}`. The
 * signature is checked before the body is parsed; anything older than five minutes is refused, and an
 * event already received (by Orgpuls' own id) is a duplicate, so a retried delivery changes nothing.
 * A 2xx tells Orgpuls the batch is delivered; anything else, it retries the batch later.
 *
 * `verify_jwt` is off: Orgpuls holds no key to this project, only the shared webhook secret
 * (orgpuls_webhook_secret in this project's Vault, 0002). Logs carry counts and status codes, never a payload: a contact form's or
 * Hjelp's message is a person's own words.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { productSecret } from '../_shared/secrets.ts'
import { verifyWebhook } from '../_shared/signing.ts'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const length = Number(req.headers.get('content-length') ?? '0')
  if (length > 1_000_000) return json({ error: 'too_large' }, 413)
  const body = await req.text()
  if (body.length > 1_000_000) return json({ error: 'too_large' }, 413)

  const svc = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
    auth: { persistSession: false },
  })
  const check = await verifyWebhook({
    secret: await productSecret(svc, 'orgpuls_webhook_secret'),
    timestamp: req.headers.get('x-orgpuls-timestamp'),
    signature: req.headers.get('x-orgpuls-signature'),
    body,
    nowSec: Math.floor(Date.now() / 1000),
  })
  if (!check.ok) {
    console.error(`[orgpuls-events] refused: ${check.reason}`)
    return json({ error: 'unauthorized' }, 401)
  }

  let events: unknown
  try {
    events = (JSON.parse(body) as { events?: unknown }).events
  } catch {
    return json({ error: 'body' }, 400)
  }
  if (!Array.isArray(events) || events.length > 500) return json({ error: 'body' }, 400)

  const { data, error } = await svc.rpc('ingest_events', { p_product: 'orgpuls', p_events: events })
  if (error) {
    console.error(`[orgpuls-events] ingest failed: ${error.code ?? ''}`)
    return json({ error: 'ingest' }, error.code === '22023' ? 400 : 500)
  }
  console.log(`[orgpuls-events] ${JSON.stringify(data)}`)
  return json(data)
})
