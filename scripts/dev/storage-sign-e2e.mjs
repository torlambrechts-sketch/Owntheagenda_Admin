// The storage-sign edge function against the local stack (0052; R-PROJECTS-01, R-MOBILE-04, R-MEETINGS-06, R-SECURITY-03).
// Run the function first (the local stack has no edge runtime):
//   SUPABASE_URL=http://127.0.0.1:54421 SUPABASE_SERVICE_ROLE_KEY=<local service key> DENO_SERVE_ADDRESS=tcp:127.0.0.1:8123 \
//     npx deno run --allow-net --allow-env --config supabase/functions/deno.json supabase/functions/storage-sign/index.ts
// then: NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54421 NEXT_PUBLIC_SUPABASE_ANON_KEY=… SUPABASE_SERVICE_ROLE_KEY=… \
//   node scripts/dev/storage-sign-e2e.mjs        (FN=http://127.0.0.1:8123 by default)
// It uploads and downloads through Storage for real: a record file, a meeting transcript and a privacy package (the service
// role plays the privacy worker). It removes its own rows and objects again (local only).
import { createClient } from '@supabase/supabase-js'
import { execFileSync } from 'node:child_process'
import { totp } from './totp.mjs'
import { DEV_PASSWORD, DEV_TOTP } from '../seed/dev-credentials.mjs'

const DB = 'postgresql://postgres:postgres@127.0.0.1:54422/postgres'
const sql = (q) => execFileSync('psql', [DB, '-qtAc', q], { encoding: 'utf8' }).trim()
const FN = process.env.FN ?? 'http://127.0.0.1:8123'
const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const service = process.env.SUPABASE_SERVICE_ROLE_KEY
let fails = 0
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) fails++ }
const fn = async (token, body) => {
  const r = await fetch(FN, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify(body) })
  return { status: r.status, body: await r.json().catch(() => null) }
}
async function signIn(email) {
  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { error } = await sb.auth.signInWithPassword({ email, password: DEV_PASSWORD })
  if (error) throw error
  const aal1 = (await sb.auth.getSession()).data.session.access_token
  const { data: f } = await sb.auth.mfa.listFactors()
  const { error: e2 } = await sb.auth.mfa.challengeAndVerify({ factorId: f.totp[0].id, code: totp(DEV_TOTP) })
  if (e2) throw e2
  return { sb, aal1, token: (await sb.auth.getSession()).data.session.access_token }
}
const tor = await signIn('tor@orgpuls.no')
const ola = await signIn('ola@orgpuls.no')
const svc = createClient(url, service, { auth: { persistSession: false } })
const cleanup = []

try {
  // who may ask
  check((await fn(tor.aal1, { mode: 'status' })).status === 401, 'a token without the second factor is refused')
  check((await fn(anon, { mode: 'status' })).status === 401, 'the anon key is nobody')
  check((await fn(service, { mode: 'status' })).status === 401, 'the service role is not a caller')
  let r = await fn(tor.token, { mode: 'status' })
  check(r.status === 200 && r.body.buckets === true, 'status: the signer runs and its private buckets exist')
  check((await fn(tor.token, { mode: 'upload', bucket: 'avatars', path: 'x/y.png' })).status === 400, 'an unknown bucket is invalid')

  // a record file: begin → sign → PUT → done → read → sign → GET
  const deal = sql(`select id from app.deals where deleted_at is null order by created_at limit 1`)
  const text = `storage-sign e2e ${new Date().toISOString()}\n`
  const { data: begun, error: be } = await tor.sb.rpc('file_upload_begin', { p_entity: 'deal', p_id: deal, p_filename: 'storage-e2e.txt', p_mime: 'text/plain', p_size: Buffer.byteLength(text) })
  if (be) throw be
  cleanup.push(async () => { await tor.sb.rpc('file_delete', { p_id: begun.id }); await svc.storage.from('record-files').remove([begun.path]) })
  r = await fn(ola.token, { mode: 'upload', bucket: 'record-files', path: begun.path })
  check(r.status === 403 && r.body.error === 'not_found', 'nobody but the uploader gets an upload URL for the pending path')
  r = await fn(tor.token, { mode: 'upload', bucket: 'record-files', path: `deal/${deal}/00000000-0000-4000-8000-000000000000/x.txt` })
  check(r.status === 403 && r.body.error === 'not_found', 'a path no pending upload names signs nothing')
  r = await fn(tor.token, { mode: 'upload', bucket: 'record-files', path: begun.path })
  check(r.status === 200 && typeof r.body.url === 'string' && r.body.path === begun.path, 'the uploader gets a signed upload URL for their path')
  const put = await fetch(r.body.url, { method: 'PUT', headers: { 'content-type': 'text/plain', 'x-upsert': 'false' }, body: text })
  check(put.ok, `the file is sent to the signed URL (HTTP ${put.status})`)
  const again = await fetch(r.body.url, { method: 'PUT', headers: { 'content-type': 'text/plain', 'x-upsert': 'false' }, body: 'other' })
  check(!again.ok, `the URL does not take a second file (HTTP ${again.status})`)
  check((await fn(tor.token, { mode: 'upload', bucket: 'record-files', path: begun.path })).body?.error === 'exists', 'an upload that landed is not signed again')
  const { error: de } = await tor.sb.rpc('file_upload_done', { p_id: begun.id })
  check(!de, 'file_upload_done lists the file')
  r = await fn(tor.token, { mode: 'download', bucket: 'record-files', path: begun.path })
  check(r.status === 403 && r.body.error === 'not_allowed', 'a download without the audited read just now is refused')
  const { data: where } = await tor.sb.rpc('file_download_url', { p_id: begun.id })
  r = await fn(tor.token, { mode: 'download', bucket: where.bucket, path: where.path })
  check(r.status === 200 && r.body.expires_in === 60, 'after file_download_url the download is signed for a minute')
  const got = await fetch(r.body.url)
  check(got.ok && (await got.text()) === text && /attachment/.test(got.headers.get('content-disposition') ?? '') && /storage-e2e\.txt/.test(got.headers.get('content-disposition') ?? ''),
    'the signed URL returns the same bytes, as an attachment named after the file')
  check((await fetch(`${url}/storage/v1/object/record-files/${begun.path}`, { headers: { apikey: anon, authorization: `Bearer ${tor.token}` } })).status >= 400,
    'the object cannot be read with the staff member\'s own token (no storage policy)')
  check((await fetch(`${url}/storage/v1/object/public/record-files/${begun.path}`)).status >= 400, 'the bucket is not public')
  r = await fn(ola.token, { mode: 'download', bucket: 'record-files', path: begun.path })
  check(r.status === 403, 'another staff member without their own read gets no download')

  // a meeting transcript
  const vtt = 'WEBVTT\n\n00:00.000 --> 00:02.000\n<v Tor>Hei, dette er en test.\n'
  const { data: mu, error: me } = await tor.sb.rpc('meeting_transcript_upload_begin', { p_meeting: null, p_filename: 'storage-e2e.vtt', p_mime: 'text/vtt', p_size: Buffer.byteLength(vtt) })
  if (me) throw me
  cleanup.push(async () => { await svc.storage.from('meeting-files').remove([mu.path]); sql(`delete from app.meetings where id = '${mu.meeting_id}'`) })
  r = await fn(tor.token, { mode: 'upload', bucket: 'meeting-files', path: mu.path })
  check(r.status === 200, 'the transcript upload is signed for its uploader')
  check((await fetch(r.body.url, { method: 'PUT', headers: { 'content-type': 'text/vtt' }, body: vtt })).ok, 'the transcript is sent')
  check((await tor.sb.rpc('meeting_transcript_upload_done', { p_upload: mu.id })).data?.state === 'processing', 'meeting_transcript_upload_done queues it for the parser')
  check((await fn(tor.token, { mode: 'download', bucket: 'meeting-files', path: mu.path })).body?.error === 'not_allowed', 'a transcript original is never downloaded')

  // a privacy package: the service role plays the worker, a security holder downloads
  const person = sql(`select id from app.people where deleted_at is null order by created_at limit 1`)
  const { data: exp, error: ee } = await tor.sb.rpc('privacy_export', { p_subject: { people: [person] }, p_request: null, p_reason: null })
  if (ee) throw ee
  const ppath = `privacy/${exp.job}/package.json`
  cleanup.push(async () => { await svc.storage.from('privacy-exports').remove([ppath]); sql(`delete from app.privacy_jobs where id = '${exp.job}'`) })
  const { data: rows } = await svc.rpc('worker_privacy_package', { p_job: exp.job })
  const pkg = JSON.stringify({ people: rows.people.length })
  const { error: ue } = await svc.storage.from('privacy-exports').upload(ppath, new Blob([pkg], { type: 'application/json' }), { contentType: 'application/json' })
  check(!ue, 'the worker (service role) writes the package into the private bucket')
  await svc.rpc('worker_privacy_done', { p_job: exp.job, p_path: ppath, p_error: null })
  check((await fn(tor.token, { mode: 'upload', bucket: 'privacy-exports', path: ppath })).body?.error === 'not_allowed', 'nobody uploads into the privacy bucket from outside')
  const { data: pu } = await tor.sb.rpc('privacy_export_url', { p_job: exp.job })
  r = await fn(tor.token, { mode: 'download', bucket: 'privacy-exports', path: pu.path })
  check(r.status === 200 && (await (await fetch(r.body.url)).text()) === pkg, 'after privacy_export_url the package downloads')
  r = await fn(ola.token, { mode: 'download', bucket: 'privacy-exports', path: pu.path })
  check(r.status === 403, 'without global:security there is no package')
} finally {
  for (const c of cleanup.reverse()) await Promise.resolve(c()).catch((e) => console.log(`cleanup: ${e.message}`))
}
console.log(fails ? `${fails} failed` : 'all passed')
process.exit(fails ? 1 : 0)
