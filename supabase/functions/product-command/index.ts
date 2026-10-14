/**
 * product-command — the platform's one way to act on a product (Orgpuls 0205, LeaderPact 0025: public.platform_command).
 *
 * POST {"product": "orgpuls" | "leaderpact", "command": "orgs.list", "args": {...}} (a product with a command registry in
 * _shared/commands.ts and an enabled installation, and a command from that registry) with the caller's own JWT:
 *   - an admin of this platform signed in with a second factor (public.admin_whoami says admin), acting
 *     as their own address; or
 *   - the service role, acting as «platform» (scheduled work: a nightly sync, never a person).
 * Before it signs for an admin it asks public.command_authorize with the admin's own token (0082, R-PL-1): the command's
 * action and the admin's role decide — allowed, refused, or (approvals switched on for that action) only under an approval
 * the admin decided and took, with exactly the approved arguments, once. The optional `approval` in the body names it.
 * The token it signs names that actor and only the scope the command needs, lives two minutes and is
 * used once, with the product as its audience. Every call that reaches the product is written to the audit with its
 * argument names, never their values. Each product's token secret is in this project's Vault (`<product>_token_secret`,
 * 0002), read by the service role only.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { commandClaims, isCommandProduct, isProductCommand } from '../_shared/commands.ts'
import { productSecret } from '../_shared/secrets.ts'
import { sameText, signJwt } from '../_shared/signing.ts'
import { readCapped } from '../_shared/body.ts'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
/** command_authorize's refusals, passed on as they are; anything else is «not_allowed» */
const REFUSALS = new Set(['forbidden', 'approval_required', 'not_signed_in', 'invalid'])

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token) return json({ error: 'unauthorized' }, 401)

  let input: { product?: unknown; command?: unknown; args?: unknown; approval?: unknown }
  try {
    const raw = await readCapped(req, 200_000)
    if (!raw.ok) return json({ error: 'too_large' }, 413)
    input = JSON.parse(raw.text)
  } catch {
    return json({ error: 'body' }, 400)
  }
  const args = input.args ?? {}
  const product = input.product
  if (!isCommandProduct(product) || !isProductCommand(product, input.command)
      || typeof args !== 'object' || args === null || Array.isArray(args) || Object.keys(args).length > 50) {
    return json({ error: 'invalid' }, 400)
  }
  const command = input.command
  const approval = input.approval ?? null
  if (approval !== null && (typeof approval !== 'string' || !UUID.test(approval))) return json({ error: 'invalid' }, 400)

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
    if (actor) {
      // may this admin run this command (their role's mode for its action), and under which approval
      const { error: refused } = await asUser.rpc('command_authorize', {
        p_product: product, p_command: command, p_approval: approval, p_args: approval ? args : null,
      })
      if (refused) {
        const code = REFUSALS.has(refused.message) ? refused.message : 'not_allowed'
        const svcAudit = createClient(url, serviceKey, { auth: { persistSession: false } })
        await svcAudit.rpc('record_command', {
          p_actor: actor, p_product: product, p_command: command, p_arg_names: Object.keys(args).sort(), p_ok: false, p_error: `refused:${code}`,
        })
        console.log(`[product-command] ${product} ${command} by admin: refused ${code}`)
        return json({ ok: false, error: code }, 403)
      }
    }
  }
  if (!actor) return json({ error: 'not_allowed' }, 403)

  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data: inst } = await svc.rpc('installation_of', { p_product: product })
  const installation = inst as { api_url?: string; public_key?: string } | null
  const secret = await productSecret(svc, `${product}_token_secret`)
  if (!installation?.api_url || !installation.public_key || !secret) return json({ error: 'not_installed' }, 503)

  const nowSec = Math.floor(Date.now() / 1000)
  const jwt = await signJwt(commandClaims(product, actor, command, nowSec, crypto.randomUUID()), secret)
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
    p_product: product,
    p_command: command,
    p_arg_names: Object.keys(args).sort(),
    p_ok: reply.ok === true,
    p_error: reply.ok === true ? null : String(reply.error ?? 'failed').slice(0, 200),
  })
  if (auditError) console.error(`[product-command] audit failed: ${auditError.code ?? ''}`)
  console.log(`[product-command] ${product} ${command} by ${actor === 'platform' ? 'platform' : 'admin'}: ${reply.ok === true ? 'ok' : reply.error}`)
  return json(reply, reply.ok === true ? 200 : 502)
})
