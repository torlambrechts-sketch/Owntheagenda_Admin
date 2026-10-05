/**
 * product-command — the platform's one way to act on a product (Orgpuls 0205: public.platform_command).
 *
 * POST {"product": "orgpuls", "command": "orgs.list", "args": {...}} with the caller's own JWT:
 *   - an admin of this platform signed in with a second factor (public.admin_whoami says admin), acting
 *     as their own address; or
 *   - the service role, acting as «platform» (scheduled work: a nightly sync, never a person).
 * The token it signs names that actor and only the scope the command needs, lives two minutes and is
 * used once. Every call that reaches the product is written to the audit with its argument names, never
 * their values. The token secret is in this project's Vault (orgpuls_token_secret, 0002), read by the
 * service role only.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { commandClaims, isOrgpulsCommand } from '../_shared/orgpuls.ts'
import { productSecret } from '../_shared/secrets.ts'
import { sameText, signJwt } from '../_shared/signing.ts'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token) return json({ error: 'unauthorized' }, 401)

  let input: { product?: unknown; command?: unknown; args?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 200_000) return json({ error: 'too_large' }, 413)
    input = JSON.parse(raw)
  } catch {
    return json({ error: 'body' }, 400)
  }
  const args = input.args ?? {}
  if (input.product !== 'orgpuls' || typeof input.command !== 'string' || !isOrgpulsCommand(input.command)
      || typeof args !== 'object' || args === null || Array.isArray(args) || Object.keys(args).length > 50) {
    return json({ error: 'invalid' }, 400)
  }
  const command = input.command

  // who is asking
  let actor: string | null = null
  if (serviceKey && sameText(token, serviceKey)) {
    actor = 'platform'
  } else {
    const asUser = createClient(url, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    })
    const { data } = await asUser.rpc('admin_whoami')
    const who = data as { admin?: boolean; email?: string | null } | null
    if (who?.admin === true && typeof who.email === 'string') actor = who.email
  }
  if (!actor) return json({ error: 'not_allowed' }, 403)

  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data: inst } = await svc.rpc('installation_of', { p_product: 'orgpuls' })
  const installation = inst as { api_url?: string; public_key?: string } | null
  const secret = await productSecret(svc, 'orgpuls_token_secret')
  if (!installation?.api_url || !installation.public_key || !secret) return json({ error: 'not_installed' }, 503)

  const nowSec = Math.floor(Date.now() / 1000)
  const jwt = await signJwt(commandClaims(actor, command, nowSec, crypto.randomUUID()), secret)
  let reply: { ok?: boolean; error?: string; result?: unknown } = { ok: false, error: 'unreachable' }
  try {
    const res = await fetch(`${installation.api_url}/rest/v1/rpc/platform_command`, {
      method: 'POST',
      headers: {
        apikey: installation.public_key,
        authorization: `Bearer ${installation.public_key}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ p_token: jwt, p_command: command, p_args: args }),
      signal: AbortSignal.timeout(20_000),
    })
    reply = res.ok ? await res.json() : { ok: false, error: `http_${res.status}` }
  } catch (e) {
    reply = { ok: false, error: (e as Error).name === 'TimeoutError' ? 'timeout' : 'unreachable' }
  }

  const { error: auditError } = await svc.rpc('record_command', {
    p_actor: actor,
    p_product: 'orgpuls',
    p_command: command,
    p_arg_names: Object.keys(args).sort(),
    p_ok: reply.ok === true,
    p_error: reply.ok === true ? null : String(reply.error ?? 'failed').slice(0, 200),
  })
  if (auditError) console.error(`[product-command] audit failed: ${auditError.code ?? ''}`)
  console.log(`[product-command] ${command} by ${actor === 'platform' ? 'platform' : 'admin'}: ${reply.ok === true ? 'ok' : reply.error}`)
  return json(reply, reply.ok === true ? 200 : 502)
})
