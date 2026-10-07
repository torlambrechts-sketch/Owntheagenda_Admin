import { z } from 'zod'
import { supabaseEnv } from './env'

/**
 * Reports to the session register through the session-report edge function (R-SECURITY-04): a sign-in, a failed
 * second factor, a failed password and, from the middleware, that a session is still in use. The function holds
 * the service role; the app sends the person's own token. Where the request came from is read from Vercel's own
 * headers and only believed by the function when the app also sends SESSION_REPORT_KEY, which the browser never
 * sees. A report that cannot be delivered answers `null`: the caller carries on, since the database still checks
 * every session itself (app.session_ok).
 */
const Reply = z.object({ ok: z.boolean(), reason: z.string().nullable(), must_change_password: z.boolean() })
export type ReportReply = z.infer<typeof Reply>

export type Origin = { ip: string | null; city: string | null; country: string | null; userAgent: string | null }

export type Report =
  | { kind: 'login'; outcome: 'success' | 'failed_mfa'; token: string; origin: Origin; device: string | null }
  | { kind: 'login'; outcome: 'failed_password'; email: string; origin: Origin; device: string | null }
  | { kind: 'seen'; token: string; origin: Origin; device: string | null }

/** Where a request came from, as Vercel saw it (its own headers; a client cannot set them on Vercel). */
export function originOf(headers: Headers): Origin {
  const forwarded = headers.get('x-vercel-forwarded-for') ?? headers.get('x-real-ip') ?? headers.get('x-forwarded-for')
  const city = headers.get('x-vercel-ip-city')
  let decoded: string | null = null
  try {
    decoded = city ? decodeURIComponent(city) : null
  } catch {
    decoded = null
  }
  return {
    ip: forwarded?.split(',')[0]?.trim() || null,
    city: decoded,
    country: headers.get('x-vercel-ip-country'),
    userAgent: headers.get('user-agent'),
  }
}

/** The session id a Supabase access token names (the token is the person's own; the function checks it). */
export function sessionOf(token: string): string | null {
  try {
    const part = token.split('.')[1] ?? ''
    const json = JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=')))
    return typeof json.session_id === 'string' ? json.session_id : null
  } catch {
    return null
  }
}

export const DEVICE_COOKIE = 'ota_device'
export const SEEN_COOKIE = 'ota_seen'

export async function report(r: Report): Promise<ReportReply | null> {
  const env = supabaseEnv()
  if ('problem' in env) return null
  const key = process.env.SESSION_REPORT_KEY?.trim()
  // a failed password names an address with no session behind it: only the keyed server may report one
  if (r.kind === 'login' && r.outcome === 'failed_password' && !key) return null
  const headers: Record<string, string> = { apikey: env.key, 'content-type': 'application/json' }
  if ('token' in r) headers.authorization = `Bearer ${r.token}`
  if (key) headers['x-report-key'] = key
  try {
    const res = await fetch(`${env.url}/functions/v1/session-report`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        kind: r.kind,
        outcome: r.kind === 'login' ? r.outcome : undefined,
        email: 'email' in r ? r.email : undefined,
        ip: r.origin.ip, city: r.origin.city, country: r.origin.country, user_agent: r.origin.userAgent,
        device_id: r.device,
      }),
      cache: 'no-store',
      signal: AbortSignal.timeout(4_000),
    })
    if (!res.ok) return null
    const parsed = Reply.safeParse(await res.json().catch(() => null))
    return parsed.success ? parsed.data : null
  } catch {
    return null
  }
}
