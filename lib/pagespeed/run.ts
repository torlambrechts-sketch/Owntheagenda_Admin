import 'server-only'
import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'
import { accessToken } from '@/lib/storage/server'

/**
 * PageSpeed Insights (0073) as the app sees it. The owner's Google API key goes from the form straight on to secret-intake
 * (Vault) under a one-time number; «Measure now» is pagespeed-run's, called with the person's own token. Replies are
 * parsed, never cast; the key is never logged, stored or returned here.
 */
const Reply = z.object({
  ok: z.boolean(),
  code: z.string().regex(/^[a-z0-9_.:-]{1,60}$/).optional(),
  sites: z.array(z.object({ site_id: z.string(), pages: z.number(), error: z.string().optional() })).optional(),
})
export type PagespeedReply = { ok: true; pages: number; error: string | null } | { ok: false; code: string }

export async function pagespeedRun(site: string | null): Promise<PagespeedReply> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  const token = await accessToken()
  if (!token) return { ok: false, code: 'not_signed_in' }
  try {
    const res = await fetch(`${env.url}/functions/v1/pagespeed-run`, {
      method: 'POST',
      headers: { apikey: env.key, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify(site ? { site } : {}),
      cache: 'no-store',
      signal: AbortSignal.timeout(160_000),
    })
    if (res.status === 404 || res.status === 503) return { ok: false, code: 'not_deployed' }
    if (res.status === 403 || res.status === 401) return { ok: false, code: 'forbidden' }
    const parsed = Reply.safeParse(await res.json().catch(() => null))
    if (!parsed.success) return { ok: false, code: 'unexpected_reply' }
    if (!parsed.data.ok) return { ok: false, code: parsed.data.code ?? 'failed' }
    const all = parsed.data.sites ?? []
    const one = site ? all.find((s) => s.site_id === site) : undefined
    const pages = one ? one.pages : all.reduce((a, s) => a + s.pages, 0)
    return { ok: true, pages, error: (one ?? all.find((s) => s.error))?.error ?? null }
  } catch {
    return { ok: false, code: 'timeout' }
  }
}

/** The owner's API key, handed straight to secret-intake with the one-time number from pagespeed_intake */
export async function handOverPagespeedKey(intakeCode: string, key: string): Promise<{ ok: boolean; code: string | null }> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  try {
    const res = await fetch(`${env.url}/functions/v1/secret-intake`, {
      method: 'POST',
      headers: { apikey: env.key, 'content-type': 'application/json' },
      body: JSON.stringify({ nonce: intakeCode, secrets: { pagespeed_api_key: key } }),
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
