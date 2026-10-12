import 'server-only'
import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'
import { accessToken } from '@/lib/storage/server'
import type { AdProvider } from '@/lib/growth/ads'
import { handOverSecrets } from '@/lib/secrets/hand-over'

/**
 * The ad platforms (0077) as the app sees them. The app never holds a platform credential: the owner's values go from the
 * form straight on to secret-intake (Vault), and every check or import is ads-run's, called with the owner's own token.
 * Replies are parsed, never cast.
 */
const code = z.string().regex(/^[a-z0-9_.:-]{1,60}$/)
const Reply = z.object({
  ok: z.boolean(), code: code.optional(),
  providers: z.array(z.object({ provider: z.string(), ok: z.boolean(), code: code.optional(), accounts: z.number().optional() })).optional(),
  accounts: z.number().optional(), rows: z.number().optional(), failed: z.number().optional(),
})
export type AdsReply = z.infer<typeof Reply>

export async function adsRun(kind: 'connect' | 'run', provider: AdProvider): Promise<AdsReply> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  const token = await accessToken()
  if (!token) return { ok: false, code: 'not_signed_in' }
  try {
    const res = await fetch(`${env.url}/functions/v1/ads-run`, {
      method: 'POST',
      headers: { apikey: env.key, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ kind, provider }),
      cache: 'no-store',
      signal: AbortSignal.timeout(130_000),
    })
    if (res.status === 404 || res.status === 503) return { ok: false, code: 'not_deployed' }
    if (res.status === 403 || res.status === 401) return { ok: false, code: 'forbidden' }
    const parsed = Reply.safeParse(await res.json().catch(() => null))
    return parsed.success ? parsed.data : { ok: false, code: 'unexpected_reply' }
  } catch {
    return { ok: false, code: 'not_connected' }
  }
}

/** The owner's credentials for one platform, handed straight to secret-intake (lib/secrets/hand-over.ts). */
export const handOverAdSecrets = handOverSecrets
