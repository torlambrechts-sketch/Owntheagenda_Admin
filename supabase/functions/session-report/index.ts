/**
 * session-report — the sign-in, the second factor and the middleware tell the session register what happened
 * (0043: worker_login_event, worker_session_seen; R-SECURITY-04). The app holds no service role; this does.
 *
 * POST {"kind": "login" | "seen", "outcome"?, "email"?, "ip"?, "user_agent"?, "device_id"?, "city"?, "country"?}
 *   - kind "login", outcome "success": the caller's own JWT at aal2. The session is the JWT's own session claim
 *     and the address the account's own, never the body's. A session already in the register is not logged twice.
 *   - kind "login", outcome "failed_mfa": the caller's own JWT at aal1 (the password was right, the code was not).
 *   - kind "login", outcome "failed_password": there is no session to vouch for it, so only a call carrying the
 *     report key may name an address; without the key it is refused rather than letting anyone fill the log.
 *   - kind "seen": the caller's own JWT at aal2. A session missing from the register (signed in before reports
 *     existed, or its sign-in report was lost) is entered as a sign-in, so it is never refused for being unknown.
 *
 * Where the request came from (IP, city, country) is only believed when the call carries the report key
 * (`x-report-key`, Vault secret `session_report_token_secret`): only the app's server knows it, and the app
 * reads those values from Vercel's own headers. Without the key they are recorded as unknown. An unknown IP
 * never passes an IP rule, and the rules' self-lockout guard refuses to turn the allowlist on, so the allowlist
 * can only be used once the key is in place. Logs carry the kind and the outcome, never an address or an IP.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { productSecret } from '../_shared/secrets.ts'
import { sameText } from '../_shared/signing.ts'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const IP = /^(\d{1,3}(\.\d{1,3}){3}|[0-9a-f:]{2,39})$/i

type Body = {
  kind?: unknown; outcome?: unknown; email?: unknown; ip?: unknown; user_agent?: unknown
  device_id?: unknown; city?: unknown; country?: unknown
}

const text = (v: unknown, max: number) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : null)

/** The claims of a token Auth has just accepted (getUser checked its signature and its session). */
function claims(token: string): { session_id?: string; aal?: string } {
  try {
    const part = token.split('.')[1] ?? ''
    return JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=')))
  } catch {
    return {}
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  let body: Body
  try {
    const raw = await req.text()
    if (raw.length > 4_000) return json({ error: 'too_large' }, 413)
    body = JSON.parse(raw)
  } catch {
    return json({ error: 'body' }, 400)
  }
  const kind = body.kind
  const outcome = kind === 'seen' ? null : body.outcome
  if ((kind !== 'login' && kind !== 'seen')
      || (kind === 'login' && outcome !== 'success' && outcome !== 'failed_mfa' && outcome !== 'failed_password')) {
    return json({ error: 'invalid' }, 400)
  }

  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })

  // the app's server, or anybody else
  const offered = req.headers.get('x-report-key') ?? ''
  let trusted = false
  if (offered) {
    const key = await productSecret(svc, 'session_report_token_secret')
    if (!key || !sameText(offered, key)) return json({ error: 'not_allowed' }, 403)
    trusted = true
  }

  // whose session
  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  let email: string | null = null
  let session: string | null = null
  if (outcome === 'failed_password') {
    if (!trusted) return json({ error: 'not_allowed' }, 403)
    email = text(body.email, 254)?.toLowerCase() ?? null
    if (!email) return json({ error: 'invalid' }, 400)
  } else {
    if (!token || token === serviceKey) return json({ error: 'unauthorized' }, 401)
    const { data, error } = await svc.auth.getUser(token)
    if (error || !data.user?.email) return json({ error: 'unauthorized' }, 401)
    const c = claims(token)
    const needed = outcome === 'failed_mfa' ? 'aal1' : 'aal2'
    if (typeof c.session_id !== 'string' || !UUID.test(c.session_id) || c.aal !== needed) return json({ error: 'unauthorized' }, 401)
    email = data.user.email.toLowerCase()
    session = c.session_id
  }

  const ipText = trusted ? text(body.ip, 45) : null
  const ip = ipText && IP.test(ipText) ? ipText : null
  const country = trusted ? text(body.country, 2)?.toUpperCase() ?? null : null
  const city = trusted ? text(body.city, 80) : null
  const ua = text(body.user_agent, 400)
  const device = text(body.device_id, 200)

  const signIn = async (result: string) => {
    const { data, error } = await svc.rpc('worker_login_event', {
      p_input: {
        email, outcome: result, session_id: session, method: result === 'failed_password' ? null : 'password_totp',
        ip, device_id: device, user_agent: ua, city, country,
      },
    })
    if (error) {
      console.error(`[session-report] login ${result}: refused ${error.code ?? ''}`)
      return json({ error: 'refused' }, 400)
    }
    const r = data as { allowed?: boolean; reason?: string | null; must_change_password?: boolean }
    console.log(`[session-report] login ${result}: ${r.allowed ? 'allowed' : r.reason ?? 'recorded'}`)
    return json({ ok: r.allowed === true, reason: r.reason ?? null, must_change_password: r.must_change_password === true })
  }

  if (outcome === 'failed_password' || outcome === 'failed_mfa') return await signIn(outcome)

  // success or seen: a session already in the register is only seen again; one that is not is entered as a sign-in
  const { data, error } = await svc.rpc('worker_session_seen', { p_session: session, p_ip: ip, p_ua: ua })
  if (error) {
    console.error(`[session-report] ${kind}: refused ${error.code ?? ''}`)
    return json({ error: 'refused' }, 400)
  }
  const seen = data as { ok?: boolean; reason?: string | null }
  if (seen.reason === 'pending') return await signIn('success')
  console.log(`[session-report] ${kind}: ${seen.ok ? 'ok' : seen.reason ?? 'ended'}`)
  return json({ ok: seen.ok === true, reason: seen.ok ? null : seen.reason ?? null, must_change_password: false })
})
