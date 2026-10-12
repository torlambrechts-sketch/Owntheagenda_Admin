import 'server-only'
import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'
import { accessToken } from '@/lib/storage/server'
import { rpc } from '@/lib/rpc'

/**
 * Claude through ai-run (0078, X-V3-2), called with the person's own token. The app sends a feature key and a subject id
 * only; the feature's context function in the database decides what Claude reads. Replies are parsed, never cast.
 */
const Reply = z.object({ ok: z.boolean(), code: z.string().regex(/^[a-z0-9_]{1,40}$/).optional(), output: z.string().uuid().nullable().optional(), truncated: z.boolean().optional() })
export type AiReply = z.infer<typeof Reply>

export async function aiRun(feature: string, subject: string): Promise<AiReply> {
  if (!/^[a-z][a-z_]{2,39}$/.test(feature) || !z.string().uuid().safeParse(subject).success) return { ok: false, code: 'invalid' }
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  const token = await accessToken()
  if (!token) return { ok: false, code: 'not_signed_in' }
  try {
    const res = await fetch(`${env.url}/functions/v1/ai-run`, {
      method: 'POST',
      headers: { apikey: env.key, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ feature, subject }),
      cache: 'no-store',
      signal: AbortSignal.timeout(150_000),
    })
    if (res.status === 404 && !res.headers.get('content-type')?.includes('json')) return { ok: false, code: 'not_deployed' }
    const parsed = Reply.safeParse(await res.json().catch(() => null))
    return parsed.success ? parsed.data : { ok: false, code: 'unexpected_reply' }
  } catch {
    return { ok: false, code: 'not_connected' }
  }
}

/** the connection and the features, for the views that offer a Claude button (never the key) */
export const AiStatus = z.object({
  connected: z.boolean(),
  key_stored_at: z.string().nullable(),
  can_manage: z.boolean(),
  model: z.string(),
  effort: z.enum(['low', 'medium', 'high']),
  features: z.array(z.object({ key: z.string(), enabled: z.boolean(), allowed: z.boolean() })),
  calls_30d: z.number(),
  failed_30d: z.number(),
  tokens_30d: z.number(),
})
export type AiStatus = z.infer<typeof AiStatus>

export async function loadAiStatus(): Promise<AiStatus | null> {
  const r = await rpc('ai_status', {}, AiStatus)
  return r.ok ? r.data : null
}

/** the drafts made for one subject, newest first (at most five) */
export const AiOutputs = z.array(z.object({ id: z.string().uuid(), body: z.string(), state: z.enum(['ready', 'used', 'discarded']), created_at: z.string(), by: z.string().nullable() }))
export async function loadAiOutputs(feature: string, subject: string) {
  const r = await rpc('ai_outputs_get', { p_feature: feature, p_subject: subject }, AiOutputs)
  return r.ok ? r.data : []
}
