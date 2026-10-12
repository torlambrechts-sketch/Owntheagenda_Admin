import 'server-only'
import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'

/**
 * Credentials typed by the owner, handed straight to secret-intake with a one-time intake number (ads_intake, v3_intake,
 * …). The values are not logged, stored or returned here; only the intake's verdict comes back (rule 5).
 */
export async function handOverSecrets(intakeCode: string, secrets: Record<string, string>): Promise<{ ok: boolean; code: string | null }> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  try {
    const res = await fetch(`${env.url}/functions/v1/secret-intake`, {
      method: 'POST',
      headers: { apikey: env.key, 'content-type': 'application/json' },
      body: JSON.stringify({ nonce: intakeCode, secrets }),
      cache: 'no-store',
      signal: AbortSignal.timeout(15_000),
    })
    const r = z.object({ ok: z.boolean().optional(), stored: z.number().optional() }).safeParse(await res.json().catch(() => null))
    if (res.ok && r.success && r.data.ok && r.data.stored === Object.keys(secrets).length) return { ok: true, code: null }
    if (res.status === 404 || res.status === 503) return { ok: false, code: 'not_deployed' }
    return { ok: false, code: res.status === 403 ? 'expired' : 'bad_key' }
  } catch {
    return { ok: false, code: 'not_connected' }
  }
}
