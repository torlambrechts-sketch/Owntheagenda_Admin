import 'server-only'
import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'
import { accessToken } from '@/lib/storage/server'

/**
 * Site health's «Check now» (0072): seo-crawl, called with the person's own token; the function asks the database whether
 * they may (seo_crawl_check_ready). The reply is parsed, never cast.
 */
const Reply = z.object({
  ok: z.boolean(),
  sites: z.array(z.object({ site_id: z.string(), pages: z.number(), issues: z.number(), error: z.string().optional() })).optional(),
})
export type CrawlReply = { ok: true; pages: number; issues: number; error: string | null } | { ok: false; code: string }

export async function seoCrawl(site: string): Promise<CrawlReply> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  const token = await accessToken()
  if (!token) return { ok: false, code: 'not_signed_in' }
  try {
    const res = await fetch(`${env.url}/functions/v1/seo-crawl`, {
      method: 'POST',
      headers: { apikey: env.key, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ site }),
      cache: 'no-store',
      signal: AbortSignal.timeout(130_000),
    })
    if (res.status === 404 || res.status === 503) return { ok: false, code: 'not_deployed' }
    if (res.status === 403 || res.status === 401) return { ok: false, code: 'forbidden' }
    const parsed = Reply.safeParse(await res.json().catch(() => null))
    const one = parsed.success ? parsed.data.sites?.find((s) => s.site_id === site) : undefined
    if (!one) return { ok: false, code: 'unexpected_reply' }
    return { ok: true, pages: one.pages, issues: one.issues, error: one.error ?? null }
  } catch {
    return { ok: false, code: 'timeout' }
  }
}
