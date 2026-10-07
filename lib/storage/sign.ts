import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'

/**
 * The app's side of the storage signer (supabase/functions/storage-sign, 0052). The server calls it with the staff member's
 * own access token and a path it just got from the RPC that checked the rights; the function asks the database again and
 * signs one upload or one download with the service role, which this app never holds. Answers are parsed, never cast.
 *
 * A signed URL is re-based onto NEXT_PUBLIC_SUPABASE_URL: the function signs with its own project URL, and the browser
 * reaches the same Storage through the origin the Content-Security-Policy already allows (connect-src).
 *
 * Refusals come back as the codes the screens have messages for (common.errors.<code>, common.storage.<detail>):
 *   function unreachable or not deployed → not_connected/storage · not_allowed → forbidden · not_found → not_found ·
 *   expired → not_available/expired · missing → not_available/missing · exists → invalid/exists · unauthorized → not_signed_in.
 */
export const BUCKETS = ['record-files', 'meeting-files', 'privacy-exports'] as const
export type Bucket = (typeof BUCKETS)[number]

export type SignRequest = { mode: 'upload' | 'download'; bucket: Bucket; path: string }
export type SignCode = 'not_connected' | 'forbidden' | 'not_found' | 'not_available' | 'invalid' | 'not_signed_in' | 'failed'
export type Signed = { ok: true; url: string } | { ok: false; code: SignCode; detail: string | null }

const Request = z.object({
  mode: z.enum(['upload', 'download']),
  bucket: z.enum(BUCKETS),
  path: z.string().min(3).max(500).refine((p) => !p.startsWith('/') && !p.includes('..') && !p.includes('//'), 'path'),
}).strict()
const UploadReply = z.object({ ok: z.literal(true), mode: z.literal('upload'), bucket: z.enum(BUCKETS), path: z.string(), token: z.string().min(1), url: z.string().url() })
const DownloadReply = z.object({ ok: z.literal(true), mode: z.literal('download'), url: z.string().url(), expires_in: z.number().int().positive() })
const StatusReply = z.object({ ok: z.literal(true), buckets: z.boolean() })
const Refusal = z.object({ error: z.string().max(40) })

const TIMEOUT_MS = 6_000

/** The signed URL on the app's own Supabase origin (same project, the origin the browser may reach). */
export function rebase(signed: string, base: string): string | null {
  try {
    const u = new URL(signed)
    if (!u.pathname.startsWith('/storage/v1/object/')) return null
    return `${base.replace(/\/$/, '')}${u.pathname}${u.search}`
  } catch {
    return null
  }
}

function refusal(status: number, error: string | null): { ok: false; code: SignCode; detail: string | null } {
  if (status === 404 || status === 503) return { ok: false, code: 'not_connected', detail: 'storage' }
  switch (error) {
    case 'unauthorized': return { ok: false, code: 'not_signed_in', detail: null }
    case 'not_allowed': return { ok: false, code: 'forbidden', detail: null }
    case 'not_found': return { ok: false, code: 'not_found', detail: null }
    case 'expired': return { ok: false, code: 'not_available', detail: 'expired' }
    case 'missing': return { ok: false, code: 'not_available', detail: 'missing' }
    case 'exists': return { ok: false, code: 'invalid', detail: 'exists' }
    case 'invalid': return { ok: false, code: 'invalid', detail: 'path' }
    default: return { ok: false, code: 'failed', detail: null }
  }
}

async function call(token: string, body: unknown): Promise<{ status: number; json: unknown } | null> {
  const env = supabaseEnv()
  if ('problem' in env) return null
  try {
    const res = await fetch(`${env.url}/functions/v1/storage-sign`, {
      method: 'POST',
      headers: { apikey: env.key, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify(body),
      cache: 'no-store',
      signal: AbortSignal.timeout(TIMEOUT_MS),
    })
    return { status: res.status, json: await res.json().catch(() => null) }
  } catch {
    return null
  }
}

/** Sign one upload (a PUT URL for this path) or one download (a short-lived GET) for the staff member behind `token`. */
export async function sign(token: string, request: SignRequest): Promise<Signed> {
  const req = Request.safeParse(request)
  if (!req.success || !token) return { ok: false, code: 'invalid', detail: 'path' }
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected', detail: 'storage' }
  const r = await call(token, req.data)
  if (!r) return { ok: false, code: 'not_connected', detail: 'storage' }
  if (r.status !== 200) {
    const why = Refusal.safeParse(r.json)
    return refusal(r.status, why.success ? why.data.error : null)
  }
  const parsed = req.data.mode === 'upload' ? UploadReply.safeParse(r.json) : DownloadReply.safeParse(r.json)
  if (!parsed.success) return { ok: false, code: 'failed', detail: null }
  if (parsed.data.mode === 'upload' && (parsed.data.bucket !== req.data.bucket || parsed.data.path !== req.data.path)) return { ok: false, code: 'failed', detail: null }
  const url = rebase(parsed.data.url, env.url)
  return url ? { ok: true, url } : { ok: false, code: 'failed', detail: null }
}

// Whether the signer runs and its buckets exist: a fact about the deployment, not the person, so one answer serves every
// request for a minute (a failure for fifteen seconds, so a deploy shows up quickly)
let cached: { ready: boolean; until: number } | null = null

/** Does upload and download work right now? The screens show their «not connected» state when it does not. */
export async function signerReady(token: string | null, now = Date.now()): Promise<boolean> {
  if (cached && cached.until > now) return cached.ready
  if (!token) return false
  const r = await call(token, { mode: 'status' })
  const parsed = r && r.status === 200 ? StatusReply.safeParse(r.json) : null
  // an unauthorised probe says nothing about the deployment: answer no, remember nothing
  if (r && r.status === 401) return false
  const ready = !!parsed?.success && parsed.data.buckets
  cached = { ready, until: now + (ready ? 60_000 : 15_000) }
  return ready
}

/** For tests: forget the remembered answer. */
export function resetSignerCache() {
  cached = null
}
