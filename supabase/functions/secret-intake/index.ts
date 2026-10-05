/**
 * secret-intake — where a product's database hands over the secrets it shares with the platform (0002).
 *
 * POST {"nonce": "...", "secrets": {"orgpuls_token_secret": "...", "orgpuls_webhook_secret": "..."}}.
 * Without a live one-time number (app.open_intake, fifteen minutes, used once) nothing is stored; the
 * values go straight into this project's Vault. Nothing about them is logged, only the outcome.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  let input: { nonce?: unknown; secrets?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 10_000) return json({ error: 'too_large' }, 413)
    input = JSON.parse(raw)
  } catch {
    return json({ error: 'body' }, 400)
  }
  if (typeof input.nonce !== 'string' || typeof input.secrets !== 'object' || input.secrets === null) return json({ error: 'body' }, 400)
  const svc = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
    auth: { persistSession: false },
  })
  const { data, error } = await svc.rpc('store_product_secrets', { p_nonce: input.nonce, p_secrets: input.secrets })
  if (error) {
    console.error(`[secret-intake] refused: ${error.code ?? ''}`)
    return json({ error: 'invalid' }, 400)
  }
  const reply = data as { ok?: boolean; stored?: number }
  console.log(`[secret-intake] ${reply.ok ? `stored ${reply.stored}` : 'unauthorized'}`)
  return json(reply, reply.ok ? 200 : 403)
})
