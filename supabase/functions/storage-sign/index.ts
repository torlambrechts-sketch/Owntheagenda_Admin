/**
 * storage-sign — signs one upload or one download in a private bucket, after the database said yes (0052; R-PROJECTS-01,
 * R-MOBILE-04, R-MEETINGS-06, R-SECURITY-03). The app holds no service role; this does.
 *
 * POST {"mode": "upload" | "download" | "status", "bucket"?, "path"?} with the caller's own JWT:
 *   - the token must be one Auth accepts (getUser), at aal2, naming its session; the address is the account's own, never
 *     the body's;
 *   - upload / download: public.worker_storage_check(email, session, bucket, path, mode) decides. The path is the one the
 *     app's server got from the RPC that checked the rights (file_upload_begin, file_download_url,
 *     meeting_transcript_upload_begin, privacy_export_url); the database finds the row behind it again — the caller's own
 *     pending upload, or a file the caller asked for (and the audit recorded) under two minutes ago — so a path from the
 *     browser alone signs nothing;
 *   - status: whether the three private buckets exist, so a screen shows upload and download only where they work.
 *
 * Answers:
 *   upload   200 {ok, mode, bucket, path, token, url}       url = Storage's signed upload URL (PUT the file, Content-Type =
 *                                                          the type the upload began with); it serves this one path once
 *   download 200 {ok, mode, url, expires_in}               a signed GET that names the file as an attachment; 60 seconds
 *   status   200 {ok, buckets}
 *   refused  400 {error: "invalid"} · 401 {error: "unauthorized"} · 403 {error: <reason>} with reason not_allowed,
 *            not_found, expired, exists (an upload already landed) or missing (the object is not in the bucket)
 * Logs carry the mode and the outcome, never a path, a file name or an address.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const BUCKETS = ['record-files', 'meeting-files', 'privacy-exports'] as const
const DOWNLOAD_SECONDS = 60

type Body = { mode?: unknown; bucket?: unknown; path?: unknown }
type Check = { allowed?: boolean; reason?: string | null; filename?: string | null }

/** The claims of a token Auth has just accepted (getUser checked its signature and its session). */
function claims(token: string): { session_id?: string; aal?: string } {
  try {
    const part = token.split('.')[1] ?? ''
    return JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=')))
  } catch {
    return {}
  }
}

const log = (mode: string, outcome: string) => console.log(`[storage-sign] ${mode}: ${outcome}`)

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 503)

  let body: Body
  try {
    const raw = await req.text()
    if (raw.length > 2_000) return json({ error: 'too_large' }, 413)
    body = JSON.parse(raw)
  } catch {
    return json({ error: 'body' }, 400)
  }
  const mode = body.mode
  if (mode !== 'upload' && mode !== 'download' && mode !== 'status') return json({ error: 'invalid' }, 400)
  const bucket = typeof body.bucket === 'string' && (BUCKETS as readonly string[]).includes(body.bucket) ? body.bucket : null
  const path = typeof body.path === 'string' && body.path.length >= 3 && body.path.length <= 500 ? body.path : null
  if (mode !== 'status' && (!bucket || !path)) return json({ error: 'invalid' }, 400)

  // whose request: the caller's own aal2 session
  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token || token === serviceKey) return json({ error: 'unauthorized' }, 401)
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data: who, error: authError } = await svc.auth.getUser(token)
  const c = claims(token)
  if (authError || !who.user?.email || c.aal !== 'aal2' || typeof c.session_id !== 'string' || !UUID.test(c.session_id)) {
    log(mode, 'unauthorized')
    return json({ error: 'unauthorized' }, 401)
  }

  if (mode === 'status') {
    const { data, error } = await svc.storage.listBuckets()
    const ready = !error && BUCKETS.every((b) => (data ?? []).some((x) => x.id === b && !x.public))
    log(mode, ready ? 'ready' : 'not_ready')
    return json({ ok: true, buckets: ready })
  }

  const { data, error } = await svc.rpc('worker_storage_check', {
    p_staff_email: who.user.email.toLowerCase(), p_session: c.session_id, p_bucket: bucket, p_path: path, p_mode: mode,
  })
  if (error) {
    log(mode, `failed ${error.code ?? ''}`.trim())
    return json({ error: 'failed' }, 502)
  }
  const check = data as Check
  if (check.allowed !== true) {
    const reason = check.reason === 'invalid' ? 'invalid' : check.reason ?? 'not_allowed'
    log(mode, `refused ${reason}`)
    return json({ error: reason }, reason === 'invalid' ? 400 : 403)
  }

  const store = svc.storage.from(bucket!)
  if (mode === 'upload') {
    const { data: signed, error: signError } = await store.createSignedUploadUrl(path!)
    if (signError || !signed) {
      log(mode, 'sign_failed')
      return json({ error: 'failed' }, 502)
    }
    log(mode, 'signed')
    return json({ ok: true, mode, bucket, path: signed.path, token: signed.token, url: signed.signedUrl })
  }

  const filename = typeof check.filename === 'string' && check.filename ? check.filename : undefined
  const { data: signed, error: signError } = await store.createSignedUrl(path!, DOWNLOAD_SECONDS, { download: filename ?? true })
  if (signError || !signed?.signedUrl) {
    log(mode, 'sign_failed')
    return json({ error: 'failed' }, 502)
  }
  log(mode, 'signed')
  return json({ ok: true, mode, url: signed.signedUrl, expires_in: DOWNLOAD_SECONDS })
})
