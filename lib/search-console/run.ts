import 'server-only'
import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'
import { accessToken } from '@/lib/storage/server'

/**
 * Search Console (0064) as the app sees it. The app never holds the Google key: the owner's JSON key goes from the form
 * straight on to secret-intake (Vault), and every check or import is search-console-run's, called with the owner's own
 * token. Replies are parsed, never cast.
 */
const code = z.string().regex(/^[a-z0-9_.:-]{1,60}$/)
const Reply = z.object({
  ok: z.boolean(), code: code.optional(), client_email: z.string().optional(),
  sites: z.array(z.object({ hostname: z.string(), property: z.string().nullable() })).optional(),
  windows: z.number().optional(), rows: z.number().optional(), failed: z.number().optional(),
})
export type SearchConsoleReply = z.infer<typeof Reply>

export async function searchConsoleRun(kind: 'connect' | 'run'): Promise<SearchConsoleReply> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  const token = await accessToken()
  if (!token) return { ok: false, code: 'not_signed_in' }
  try {
    const res = await fetch(`${env.url}/functions/v1/search-console-run`, {
      method: 'POST',
      headers: { apikey: env.key, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ kind }),
      cache: 'no-store',
      signal: AbortSignal.timeout(55_000),
    })
    if (res.status === 404 || res.status === 503) return { ok: false, code: 'not_deployed' }
    if (res.status === 403 || res.status === 401) return { ok: false, code: 'forbidden' }
    const parsed = Reply.safeParse(await res.json().catch(() => null))
    return parsed.success ? parsed.data : { ok: false, code: 'unexpected_reply' }
  } catch {
    return { ok: false, code: 'not_connected' }
  }
}

/**
 * The owner's JSON key, handed straight to secret-intake with the one-time number from search_console_intake. The value
 * is not logged, stored or returned here; only the intake's verdict comes back.
 */
export async function handOverGoogleKey(intakeCode: string, key: string): Promise<{ ok: boolean; code: string | null }> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  try {
    const res = await fetch(`${env.url}/functions/v1/secret-intake`, {
      method: 'POST',
      headers: { apikey: env.key, 'content-type': 'application/json' },
      body: JSON.stringify({ nonce: intakeCode, secrets: { search_console_key: key } }),
      cache: 'no-store',
      signal: AbortSignal.timeout(15_000),
    })
    const r = z.object({ ok: z.boolean().optional(), stored: z.number().optional() }).safeParse(await res.json().catch(() => null))
    if (res.ok && r.success && r.data.ok && r.data.stored === 1) return { ok: true, code: null }
    if (res.status === 404 || res.status === 503) return { ok: false, code: 'not_deployed' }
    return { ok: false, code: res.status === 403 ? 'expired' : 'bad_key' }
  } catch {
    return { ok: false, code: 'not_connected' }
  }
}
