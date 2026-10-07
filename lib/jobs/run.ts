import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'

/**
 * The app's side of the jobs runner (supabase/functions/jobs-run, 0054). Right after the action that made a job runnable —
 * meeting_transcript_upload_done, privacy_export — or when the person presses «Read now» / «Write package now», the server
 * calls it with the staff member's own access token and the job's id; the function asks the database whether this person
 * may run it and runs it with the service role, which this app never holds. Answers are parsed, never cast.
 *
 * It never throws and never fails the action that called it: a function that cannot be reached, refuses, or could not
 * finish answers `pending` (the job stays waiting, and the screen says so), with a reason for the screen:
 *   not_connected (unreachable or not deployed) · not_signed_in · forbidden · not_found · busy (another run has it) ·
 *   storage / failed (the run could not finish now; the claim lapses and the next call tries again).
 * A finished run answers ready (a transcript read) / done (a package written) or failed with the reader's reason code.
 */
export type JobKind = 'transcript' | 'privacy'
export type JobRequest = { kind: JobKind; id: string }
export type JobState = 'ready' | 'done' | 'failed' | 'pending'
export type JobRun = { state: JobState; reason: string | null }

const Request = z.object({ kind: z.enum(['transcript', 'privacy']), id: z.guid() }).strict()
const code = z.string().regex(/^[a-z_]{1,80}$/)
const Reply = z.object({
  ok: z.literal(true),
  ran: z.boolean(),
  kind: z.enum(['transcript', 'privacy']),
  state: z.enum(['processing', 'ready', 'failed', 'approved', 'running', 'done']).nullable(),
  reason: code.nullable(),
  segments: z.number().int().nonnegative().nullable(),
  others: z.number().int().nonnegative(),
})
const Refusal = z.object({ error: z.string().max(40) })

// a 5 MB transcript or a privacy package is read and written in a few seconds; the action does not wait longer than this
const TIMEOUT_MS = 25_000

const pending = (reason: string): JobRun => ({ state: 'pending', reason })

function refusal(status: number, error: string | null): JobRun {
  if (status === 404 || status === 503) return pending('not_connected')
  switch (error) {
    case 'unauthorized': return pending('not_signed_in')
    case 'not_allowed': return pending('forbidden')
    case 'not_found': return pending('not_found')
    default: return pending('failed')
  }
}

/** Run one job for the staff member behind `token`. */
export async function runJob(token: string | null, request: JobRequest): Promise<JobRun> {
  const req = Request.safeParse(request)
  if (!req.success) return pending('failed')
  if (!token) return pending('not_signed_in')
  const env = supabaseEnv()
  if ('problem' in env) return pending('not_connected')
  let status: number
  let body: unknown
  try {
    const res = await fetch(`${env.url}/functions/v1/jobs-run`, {
      method: 'POST',
      headers: { apikey: env.key, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify(req.data),
      cache: 'no-store',
      signal: AbortSignal.timeout(TIMEOUT_MS),
    })
    status = res.status
    body = await res.json().catch(() => null)
  } catch {
    return pending('not_connected')
  }
  if (status !== 200) {
    const why = Refusal.safeParse(body)
    return refusal(status, why.success ? why.data.error : null)
  }
  const r = Reply.safeParse(body)
  if (!r.success || r.data.kind !== req.data.kind) return pending('failed')
  const s = r.data.state
  if (s === 'ready' || s === 'done') return { state: s, reason: null }
  if (s === 'failed') return { state: 'failed', reason: r.data.reason }
  return pending(r.data.ran ? r.data.reason ?? 'failed' : r.data.reason ?? 'busy')
}
