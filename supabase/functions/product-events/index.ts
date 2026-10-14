/**
 * product-events — every product's events in, by one door (0090; LeaderPact's REUSE_EVALUATION E2).
 *
 * One signed POST per batch, `{"product": "<key>", "events": [{id, kind, org_id, payload, created_at}, ...]}`, with
 * `x-platform-product`, `x-platform-timestamp` (unix seconds) and `x-platform-signature: sha256=<hex HMAC-SHA256 of
 * "<timestamp>.<body>">` under the product's own webhook secret (`<key>_webhook_secret` in this project's Vault, stored
 * through secret-intake). The signature is checked before the body is parsed; anything older than five minutes is refused;
 * the body must name the product the header did; an event already received (by the product's own id) is a duplicate.
 *
 * `ingest_product_events` takes a lead request (template, demo, contact) five times an hour from one address and passes
 * the rest to ingest_events; when every event was refused the answer is 429. A product is refused until its
 * installation is enabled, which happens when both its secrets are stored.
 *
 * Orgpuls keeps orgpuls-events and its own headers; LeaderPact is the first product on this door. `verify_jwt` is off:
 * a product holds no key to this project, only its shared webhook secret. Logs carry the product, counts and status
 * codes, never a payload: a request carries a person's name and address.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { claimedProduct, readBatch } from '../_shared/product-events.ts'
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

  const product = claimedProduct(req.headers.get('x-platform-product'))
  if (!product) return json({ error: 'unauthorized' }, 401)
  const svc = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
    auth: { persistSession: false },
  })
  const check = await verifyWebhook({
    secret: await productSecret(svc, `${product}_webhook_secret`),
    timestamp: req.headers.get('x-platform-timestamp'),
    signature: req.headers.get('x-platform-signature'),
    body,
    nowSec: Math.floor(Date.now() / 1000),
  })
  if (!check.ok) {
    console.error(`[product-events] ${product} refused: ${check.reason}`)
    return json({ error: 'unauthorized' }, 401)
  }

  const batch = readBatch(body, product)
  if (!batch.ok) return json({ error: batch.error }, 400)

  const { data, error } = await svc.rpc('ingest_product_events', { p_product: product, p_events: batch.events })
  if (error) {
    console.error(`[product-events] ${product} ingest failed: ${error.code ?? ''}`)
    return json({ error: 'ingest' }, error.code === '22023' ? 400 : 500)
  }
  const result = data as { received?: number; duplicate?: number; refused?: number }
  console.log(`[product-events] ${product} ${JSON.stringify(result)}`)
  const allRefused = (result.refused ?? 0) > 0 && (result.received ?? 0) === 0 && (result.duplicate ?? 0) === 0
  return json(result, allRefused ? 429 : 200)
})
