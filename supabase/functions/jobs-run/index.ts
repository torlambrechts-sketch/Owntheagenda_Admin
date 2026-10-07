/**
 * jobs-run — runs the two jobs that need no outside provider, right after the action that made them runnable (0054;
 * R-MEETINGS-06 parser, R-SECURITY-03 worker). There is no cron and no new secret: the app's server calls this with the
 * person's own JWT after meeting_transcript_upload_done and after privacy_export, and again when the person presses «Read
 * now» / «Write package now». The app holds no service role; this does.
 *
 * POST {"kind": "transcript" | "privacy", "id": <uuid>} with the caller's own JWT:
 *   - the token must be one Auth accepts (getUser), at aal2, naming its session; the address is the account's own;
 *   - public.worker_jobs_claim(email, session, kind, id, 3) decides whether this caller may run this job — their own landed
 *     upload behind a transcript; an export they asked for or approved, with global:security — and claims it for five
 *     minutes, so a job already running or finished is not run twice. It may hand back up to three more jobs of the same
 *     kind that nobody's call ran (landed two minutes ago or more, unclaimed): they need no caller and are run the same way
 *     after the caller's own; their ids come from the database, never from the body, and nothing of them is answered but a
 *     count;
 *   - transcript: the original is read from meeting-files with the service role (5 MB at most), parsed by
 *     _shared/transcript.ts and handed to worker_upload_parsed, or to worker_upload_failed with a reason code; then the
 *     original is deleted, as the dialog promises. A file Storage could not hand over stays waiting (the claim lapses);
 *   - privacy: worker_privacy_package's rows become a ZIP of JSON files (_shared/privacy-package.ts), stored at
 *     privacy/<job>/access-package.zip in privacy-exports, and worker_privacy_done closes the job (24 h link). A package over
 *     50 MB fails the job («package_too_large»); a store that failed leaves it running for the next try.
 *
 * Answers:
 *   200 {ok: true, ran: true,  kind, state, reason, segments, others}   state: transcript ready | failed | processing,
 *                                                                        privacy done | failed | running; reason: the failure
 *                                                                        code, or why it is still waiting (storage, failed)
 *   200 {ok: true, ran: false, kind, state, reason, others: 0}          reason busy (another run has it) or done (finished)
 *   refused 400 {error: "invalid"} · 401 {error: "unauthorized"} · 403 {error: not_allowed | not_found} · 502 {error: "failed"}
 * Logs carry the kind, the outcome and counts, never a path, a file name, an address or a word of the file.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { formatFor, MAX_BYTES, parseTranscript } from '../_shared/transcript.ts'
import { buildPackage, PackageError, packagePath } from '../_shared/privacy-package.ts'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const MORE = 3

type Kind = 'transcript' | 'privacy'
type TranscriptJob = { kind: 'transcript'; own: boolean; transcript_id: string; upload_id: string; path: string; mime: string; size: number; stored: boolean }
type PrivacyJob = { kind: 'privacy'; own: boolean; job_id: string }
type Job = TranscriptJob | PrivacyJob
type Claim = { allowed?: boolean; reason?: string | null; state?: string | null; jobs?: unknown }
type Outcome = { state: string; reason: string | null; segments: number | null }

/** The claims of a token Auth has just accepted (getUser checked its signature and its session). */
function claims(token: string): { session_id?: string; aal?: string } {
  try {
    const part = token.split('.')[1] ?? ''
    return JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=')))
  } catch {
    return {}
  }
}

const log = (kind: string, outcome: string) => console.log(`[jobs-run] ${kind}: ${outcome}`)

/** The claim's jobs, checked field by field (the database wrote them, but nothing is cast). */
function jobsOf(raw: unknown, kind: Kind): Job[] {
  if (!Array.isArray(raw)) return []
  const out: Job[] = []
  for (const j of raw) {
    if (!j || typeof j !== 'object') continue
    const r = j as Record<string, unknown>
    if (kind === 'transcript' && r.kind === 'transcript' && typeof r.upload_id === 'string' && UUID.test(r.upload_id)
        && typeof r.transcript_id === 'string' && typeof r.path === 'string' && typeof r.mime === 'string' && typeof r.size === 'number') {
      out.push({ kind, own: r.own === true, transcript_id: r.transcript_id, upload_id: r.upload_id, path: r.path, mime: r.mime, size: r.size, stored: r.stored === true })
    } else if (kind === 'privacy' && r.kind === 'privacy' && typeof r.job_id === 'string' && UUID.test(r.job_id)) {
      out.push({ kind, own: r.own === true, job_id: r.job_id })
    }
  }
  return out
}

async function failUpload(svc: SupabaseClient, job: TranscriptJob, reason: string): Promise<Outcome> {
  const { error } = await svc.rpc('worker_upload_failed', { p_upload: job.upload_id, p_reason: reason })
  if (error) {
    log('transcript', `refused ${error.code ?? ''}`.trim())
    return { state: 'processing', reason: 'failed', segments: null }
  }
  return { state: 'failed', reason, segments: null }
}

async function runTranscript(svc: SupabaseClient, job: TranscriptJob): Promise<Outcome> {
  if (!job.stored) return failUpload(svc, job, 'missing')
  const format = formatFor(job.mime)
  if (!format) return failUpload(svc, job, 'not_text')
  if (job.size > MAX_BYTES) return failUpload(svc, job, 'too_large')
  const { data: blob, error } = await svc.storage.from('meeting-files').download(job.path)
  if (error || !blob) {
    log('transcript', 'storage_failed')
    return { state: 'processing', reason: 'storage', segments: null }
  }
  if (blob.size > MAX_BYTES) return failUpload(svc, job, 'too_large')
  const parsed = await parseTranscript(new Uint8Array(await blob.arrayBuffer()), format)
  let out: Outcome
  if (!parsed.ok) {
    out = await failUpload(svc, job, parsed.reason)
  } else {
    const { data, error: e2 } = await svc.rpc('worker_upload_parsed', { p_upload: job.upload_id, p_segments: parsed.segments })
    if (e2) {
      // the database refused the segments (its own limits): the file cannot be read into this transcript
      log('transcript', `rejected ${e2.code ?? ''}`.trim())
      out = await failUpload(svc, job, 'rejected')
    } else {
      const n = typeof (data as { segments?: unknown })?.segments === 'number' ? (data as { segments: number }).segments : parsed.segments.length
      out = { state: 'ready', reason: null, segments: n }
    }
  }
  if (out.state !== 'processing') {
    // the original is deleted once read, as the upload dialog says (the queued files_purge is the fallback)
    const { error: e3 } = await svc.storage.from('meeting-files').remove([job.path])
    if (e3) log('transcript', 'original_kept')
  }
  return out
}

async function runPrivacy(svc: SupabaseClient, job: PrivacyJob): Promise<Outcome> {
  const { data, error } = await svc.rpc('worker_privacy_package', { p_job: job.job_id })
  if (error) {
    log('privacy', `refused ${error.code ?? ''}`.trim())
    return { state: 'running', reason: 'failed', segments: null }
  }
  let bytes: Uint8Array
  const path = packagePath(job.job_id)
  try {
    bytes = await buildPackage(job.job_id, data)
  } catch (e) {
    const code = e instanceof PackageError ? e.code : 'package_invalid'
    await svc.rpc('worker_privacy_done', { p_job: job.job_id, p_path: null, p_error: code })
    log('privacy', code)
    return { state: 'failed', reason: code, segments: null }
  }
  const { error: e2 } = await svc.storage.from('privacy-exports').upload(path, bytes, { contentType: 'application/zip', upsert: true })
  if (e2) {
    log('privacy', 'storage_failed')
    return { state: 'running', reason: 'storage', segments: null }
  }
  const { error: e3 } = await svc.rpc('worker_privacy_done', { p_job: job.job_id, p_path: path, p_error: null })
  if (e3) {
    log('privacy', `done_refused ${e3.code ?? ''}`.trim())
    return { state: 'running', reason: 'failed', segments: null }
  }
  return { state: 'done', reason: null, segments: null }
}

const run = (svc: SupabaseClient, job: Job): Promise<Outcome> =>
  (job.kind === 'transcript' ? runTranscript(svc, job) : runPrivacy(svc, job)).catch(() => {
    log(job.kind, 'crashed')
    return { state: job.kind === 'transcript' ? 'processing' : 'running', reason: 'failed', segments: null }
  })

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 503)

  let body: { kind?: unknown; id?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 1_000) return json({ error: 'too_large' }, 413)
    body = JSON.parse(raw)
  } catch {
    return json({ error: 'body' }, 400)
  }
  const kind = body.kind
  if ((kind !== 'transcript' && kind !== 'privacy') || typeof body.id !== 'string' || !UUID.test(body.id)) return json({ error: 'invalid' }, 400)

  // whose request: the caller's own aal2 session
  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token || token === serviceKey) return json({ error: 'unauthorized' }, 401)
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data: who, error: authError } = await svc.auth.getUser(token)
  const c = claims(token)
  if (authError || !who.user?.email || c.aal !== 'aal2' || typeof c.session_id !== 'string' || !UUID.test(c.session_id)) {
    log(kind, 'unauthorized')
    return json({ error: 'unauthorized' }, 401)
  }

  const { data, error } = await svc.rpc('worker_jobs_claim', {
    p_staff_email: who.user.email.toLowerCase(), p_session: c.session_id, p_kind: kind, p_id: body.id, p_more: MORE,
  })
  if (error) {
    log(kind, `claim_failed ${error.code ?? ''}`.trim())
    return json({ error: 'failed' }, 502)
  }
  const claim = (data ?? {}) as Claim
  if (claim.allowed !== true) {
    const reason = typeof claim.reason === 'string' ? claim.reason : 'not_allowed'
    if (reason === 'busy' || reason === 'done') {
      log(kind, reason)
      return json({ ok: true, ran: false, kind, state: typeof claim.state === 'string' ? claim.state : null, reason, segments: null, others: 0 })
    }
    log(kind, `refused ${reason}`)
    return json({ error: reason === 'invalid' ? 'invalid' : reason === 'not_found' ? 'not_found' : 'not_allowed' }, reason === 'invalid' ? 400 : 403)
  }

  const jobs = jobsOf(claim.jobs, kind)
  const own = jobs.find((j) => j.own)
  if (!own) {
    log(kind, 'claim_empty')
    return json({ error: 'failed' }, 502)
  }
  const result = await run(svc, own)
  log(kind, `${result.state}${result.reason ? ` ${result.reason}` : ''}${result.segments !== null ? ` ${result.segments} segments` : ''}`)

  // the others nobody's call ran: after the answer where the runtime allows it, else before
  const others = jobs.filter((j) => !j.own)
  if (others.length) {
    const rest = (async () => {
      for (const j of others) {
        const r = await run(svc, j)
        log(kind, `other ${r.state}${r.reason ? ` ${r.reason}` : ''}`)
      }
    })()
    if (typeof EdgeRuntime !== 'undefined' && EdgeRuntime?.waitUntil) EdgeRuntime.waitUntil(rest)
    else await rest
  }
  return json({ ok: true, ran: true, kind, state: result.state, reason: result.reason, segments: result.segments, others: others.length })
})
