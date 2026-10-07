// The jobs-run edge function end to end on the local stack (0054; R-MEETINGS-06 parser, R-SECURITY-03 worker): transcript
// uploads read into their meeting (.vtt, .srt, .docx, a broken file), and privacy export packages written, both through the
// API and in a browser. The local stack has no edge runtime, so run the functions under Deno and a proxy in front of them:
//
//   K=$(supabase status -o env)   # SERVICE_ROLE_KEY and ANON_KEY are the local demo keys
//   for f in jobs-run:8124 storage-sign:8125 session-report:8126; do
//     SUPABASE_URL=http://127.0.0.1:54421 SUPABASE_SERVICE_ROLE_KEY=… DENO_SERVE_ADDRESS=tcp:127.0.0.1:${f#*:} \
//       npx deno run --allow-net --allow-env --config supabase/functions/deno.json supabase/functions/${f%:*}/index.ts &
//   done
//   PORT=54431 node scripts/dev/functions-proxy.mjs &
//   NEXT_DIST_DIR=.next-jobs NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54431 NEXT_PUBLIC_SUPABASE_ANON_KEY=… npx next dev -p 3341 &
//   PROXY=http://127.0.0.1:54431 BASE=http://localhost:3341 NEXT_PUBLIC_SUPABASE_ANON_KEY=… SUPABASE_SERVICE_ROLE_KEY=… \
//     node scripts/dev/jobs-e2e.mjs
//
// It removes the meetings, jobs and objects it made (local only). Word files are built with Python's zipfile (deflated, as
// Word writes them), not with the reader's own ZIP code.
import { chromium } from '@playwright/test'
import { createClient } from '@supabase/supabase-js'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { totp } from './totp.mjs'
import { DEV_PASSWORD, DEV_TOTP } from '../seed/dev-credentials.mjs'

const DB = 'postgresql://postgres:postgres@127.0.0.1:54422/postgres'
const sql = (q) => execFileSync('psql', [DB, '-qtAc', q], { encoding: 'utf8' }).trim()
const PROXY = process.env.PROXY ?? 'http://127.0.0.1:54431'
const BASE = process.env.BASE ?? 'http://localhost:3341'
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const service = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!anon || !service) throw new Error('NEXT_PUBLIC_SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY (local demo keys) are needed')
const svc = createClient(PROXY, service, { auth: { persistSession: false } })
const work = mkdtempSync(join(tmpdir(), 'jobs-e2e-'))
let fails = 0
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) fails++ }
const cleanup = []

const TYPES = { vtt: 'text/vtt', srt: 'application/x-subrip', txt: 'text/plain', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }
const fn = async (name, token, body) => {
  const r = await fetch(`${PROXY}/functions/v1/${name}`, { method: 'POST', headers: { apikey: anon, 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify(body) })
  return { status: r.status, body: await r.json().catch(() => null) }
}
async function signIn(email) {
  const sb = createClient(PROXY, anon, { auth: { persistSession: false } })
  const { error } = await sb.auth.signInWithPassword({ email, password: DEV_PASSWORD })
  if (error) throw error
  const aal1 = (await sb.auth.getSession()).data.session.access_token
  const { data: f } = await sb.auth.mfa.listFactors()
  const { error: e2 } = await sb.auth.mfa.challengeAndVerify({ factorId: f.totp[0].id, code: totp(DEV_TOTP) })
  if (e2) throw e2
  const token = (await sb.auth.getSession()).data.session.access_token
  await fn('session-report', token, { kind: 'login', outcome: 'success' }) // the register knows the session (0055)
  return { sb, aal1, token }
}

/** A .docx with these paragraphs, zipped by Python (deflated). */
function docx(paragraphs, name) {
  const body = paragraphs.map((p) => `<w:p><w:r><w:t xml:space="preserve">${p.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</w:t></w:r></w:p>`).join('')
  const xml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body}<w:sectPr/></w:body></w:document>`
  const out = join(work, name)
  execFileSync('python3', ['-I', '-c', `import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED)
z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
z.writestr('word/document.xml', sys.stdin.read())
z.close()`, out], { input: xml })
  return readFileSync(out)
}
/** The files in a ZIP, read by Python: {name: text}. */
function unzip(buf) {
  const p = join(work, `pkg-${Date.now()}.zip`)
  writeFileSync(p, buf)
  return JSON.parse(execFileSync('python3', ['-I', '-c', `import sys, json, zipfile
z = zipfile.ZipFile(sys.argv[1])
assert z.testzip() is None
print(json.dumps({n: z.read(n).decode('utf-8') for n in z.namelist()}))`, p], { encoding: 'utf8' }))
}

/** begin → storage-sign → PUT → done, as the meetings screen does it; returns the ids (the job is not run). */
async function upload(who, filename, bytes) {
  const ext = filename.split('.').pop()
  const { data: begun, error } = await who.sb.rpc('meeting_transcript_upload_begin', { p_meeting: null, p_filename: filename, p_mime: TYPES[ext], p_size: bytes.length })
  if (error) throw error
  cleanup.push(async () => { await svc.storage.from('meeting-files').remove([begun.path]); sql(`delete from app.meetings where id = '${begun.meeting_id}'`) })
  const signed = await fn('storage-sign', who.token, { mode: 'upload', bucket: 'meeting-files', path: begun.path })
  if (signed.status !== 200) throw new Error(`sign ${signed.status} ${JSON.stringify(signed.body)}`)
  const put = await fetch(signed.body.url, { method: 'PUT', headers: { 'content-type': TYPES[ext], 'x-upsert': 'false' }, body: bytes })
  if (!put.ok) throw new Error(`put ${put.status}`)
  const { data: done, error: de } = await who.sb.rpc('meeting_transcript_upload_done', { p_upload: begun.id })
  if (de) throw de
  return { upload: begun.id, meeting: begun.meeting_id, path: begun.path, transcript: done.transcript_id }
}
const stored = (bucket, path) => sql(`select count(*) from storage.objects where bucket_id = '${bucket}' and name = '${path}'`) === '1'
const segments = (t) => JSON.stringify(JSON.parse(sql(`select coalesce(jsonb_agg(jsonb_build_object('s', start_ms, 'e', end_ms, 'who', speaker_label, 'text', text) order by seq), '[]') from app.transcript_segments where transcript_id = '${t}'`))
  .map((x) => ({ s: x.s, e: x.e, who: x.who, text: x.text })))

const tor = await signIn('tor@orgpuls.no')
const ingrid = await signIn('ingrid@orgpuls.no')
const ola = await signIn('ola@orgpuls.no')
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })

try {
  // ---------------------------------------------------------------------------
  // API: who may ask
  const someId = '00000000-0000-4000-8000-000000000000'
  check((await fn('jobs-run', tor.aal1, { kind: 'transcript', id: someId })).status === 401, 'a token without the second factor is refused')
  check((await fn('jobs-run', anon, { kind: 'transcript', id: someId })).status === 401, 'the anon key is nobody')
  check((await fn('jobs-run', service, { kind: 'transcript', id: someId })).status === 401, 'the service role is not a caller')
  check((await fn('jobs-run', tor.token, { kind: 'recap', id: someId })).status === 400 && (await fn('jobs-run', tor.token, { kind: 'transcript', id: '../x' })).status === 400,
    'an unknown kind or an id that is not a uuid is invalid')
  check((await fn('jobs-run', tor.token, { kind: 'transcript', id: someId })).body?.error === 'not_found', 'an unknown transcript is not found')

  // a .vtt: only its uploader runs it; it is read once; the original is deleted
  const vtt = 'WEBVTT\n\nNOTE e2e\n\n1\n00:00:01.000 --> 00:00:03.000 align:start\n<v Ingrid Berg>Hei &amp; velkommen.</v>\n\n00:00:03.500 --> 00:00:05.000\n<v Tor>Takk.\n'
  const a = await upload(ingrid, 'jobs-e2e.vtt', Buffer.from(vtt))
  let r = await fn('jobs-run', ola.token, { kind: 'transcript', id: a.transcript })
  check(r.status === 403 && r.body.error === 'not_found', 'someone else cannot run another person\'s upload')
  r = await fn('jobs-run', ingrid.token, { kind: 'transcript', id: a.transcript })
  check(r.status === 200 && r.body.ran === true && r.body.state === 'ready' && r.body.segments === 2, `the uploader's call reads the .vtt (${JSON.stringify(r.body)})`)
  check(segments(a.transcript) === JSON.stringify([{ s: 1000, e: 3000, who: 'Ingrid Berg', text: 'Hei & velkommen.' }, { s: 3500, e: 5000, who: 'Tor', text: 'Takk.' }]),
    'the segments are stored with times, voices and decoded text')
  check(sql(`select state || '|' || coalesce(speaker_count::text, '') from app.meeting_transcripts where id = '${a.transcript}'`) === 'ready|2'
    && sql(`select state from app.meeting_uploads where id = '${a.upload}'`) === 'parsed', 'the transcript is ready with two speakers; the upload is parsed')
  check(!stored('meeting-files', a.path), 'the original file is deleted once read')
  r = await fn('jobs-run', ingrid.token, { kind: 'transcript', id: a.transcript })
  check(r.status === 200 && r.body.ran === false && r.body.reason === 'done' && r.body.state === 'ready', 'a second call does not read it again')

  // a .docx (Teams-style header lines) and an .srt
  const d = await upload(tor, 'jobs-e2e.docx', docx(['Tor Lambrechts  0:03', 'Velkommen til gjennomgangen.', '', 'Ingrid Berg: Takk, æ ø å.'], 'a.docx'))
  r = await fn('jobs-run', tor.token, { kind: 'transcript', id: d.transcript })
  check(r.body?.state === 'ready' && segments(d.transcript) === JSON.stringify([{ s: 3000, e: null, who: 'Tor Lambrechts', text: 'Velkommen til gjennomgangen.' }, { s: 3000, e: null, who: 'Ingrid Berg', text: 'Takk, æ ø å.' }]),
    `a Word file is read paragraph by paragraph (${JSON.stringify(r.body)})`)
  const s = await upload(tor, 'jobs-e2e.srt', Buffer.from('1\r\n00:00:01,000 --> 00:00:02,000\r\n<i>Tor:</i> Hallo\r\n\r\n2\r\n00:00:02,500 --> 00:00:04,000\r\nIngrid: Hei\r\n'))
  r = await fn('jobs-run', tor.token, { kind: 'transcript', id: s.transcript })
  check(r.body?.state === 'ready' && r.body.segments === 2, 'an .srt with CRLF and tags is read')

  // a broken file fails with a reason code, and is deleted too
  const b = await upload(tor, 'jobs-e2e-broken.docx', Buffer.from('PK\u0003\u0004 this is not a Word file'))
  r = await fn('jobs-run', tor.token, { kind: 'transcript', id: b.transcript })
  check(r.body?.state === 'failed' && r.body.reason === 'docx_invalid', `a broken Word file fails with docx_invalid (${JSON.stringify(r.body)})`)
  check(sql(`select state || '|' || error_code from app.meeting_transcripts where id = '${b.transcript}'`) === 'failed|docx_invalid' && !stored('meeting-files', b.path),
    'the transcript carries the reason; the original is deleted')

  // two calls at once: one reads, the other is told it is busy (or already done)
  const c = await upload(tor, 'jobs-e2e-twice.vtt', Buffer.from('WEBVTT\n\n00:01.000 --> 00:02.000\nEn gang\n'))
  const both = await Promise.all([fn('jobs-run', tor.token, { kind: 'transcript', id: c.transcript }), fn('jobs-run', tor.token, { kind: 'transcript', id: c.transcript })])
  check(both.filter((x) => x.body?.ran === true).length === 1 && both.some((x) => x.body?.ran === false && ['busy', 'done'].includes(x.body.reason))
    && sql(`select count(*) from app.transcript_segments where transcript_id = '${c.transcript}'`) === '1', 'two calls at once read the file once')

  // an upload nobody's call ran (two minutes old) comes along with the next caller's own
  const o = await upload(tor, 'jobs-e2e-orphan.vtt', Buffer.from('WEBVTT\n\n00:01.000 --> 00:02.000\n<v Tor>Glemt\n'))
  sql(`update app.meeting_uploads set created_at = now() - interval '3 minutes' where id = '${o.upload}'`)
  const n = await upload(ingrid, 'jobs-e2e-next.vtt', Buffer.from('WEBVTT\n\n00:01.000 --> 00:02.000\nNeste\n'))
  r = await fn('jobs-run', ingrid.token, { kind: 'transcript', id: n.transcript })
  check(r.body?.state === 'ready' && r.body.others >= 1 && sql(`select state from app.meeting_transcripts where id = '${o.transcript}'`) === 'ready',
    `an orphaned upload is read along with the next one (others ${r.body?.others})`)

  // ---------------------------------------------------------------------------
  // API: a privacy package
  const person = sql(`select id from app.people where deleted_at is null and not is_sample order by created_at limit 1`)
  const { data: exp, error: ee } = await tor.sb.rpc('privacy_export', { p_subject: { people: [person] }, p_request: null, p_reason: null })
  if (ee) throw ee
  const job = exp.job
  cleanup.push(async () => { await svc.storage.from('privacy-exports').remove([`privacy/${job}/access-package.zip`]); sql(`delete from app.privacy_jobs where id = '${job}'`) })
  r = await fn('jobs-run', ola.token, { kind: 'privacy', id: job })
  check(r.status === 403 && r.body.error === 'not_allowed', 'without global:security no package is written')
  r = await fn('jobs-run', tor.token, { kind: 'privacy', id: job })
  check(r.body?.ran === true && r.body.state === 'done', `the requester's call writes the package (${JSON.stringify(r.body)})`)
  const path = sql(`select storage_path from app.privacy_jobs where id = '${job}' and state = 'done'`)
  check(path === `privacy/${job}/access-package.zip` && stored('privacy-exports', path), 'the package is in privacy-exports at privacy/<job>/access-package.zip and the job is done')
  check(sql(`select metadata ->> 'mimetype' from storage.objects where bucket_id = 'privacy-exports' and name = '${path}'`) === 'application/zip', 'stored as application/zip')
  const { data: where } = await tor.sb.rpc('privacy_export_url', { p_job: job })
  const signed = await fn('storage-sign', tor.token, { mode: 'download', bucket: 'privacy-exports', path: where.path })
  const files = unzip(Buffer.from(await (await fetch(signed.body.url)).arrayBuffer()))
  const about = JSON.parse(files['about.json'])
  check(about.job === job && about.sections.people === 1 && JSON.parse(files['people.json'])[0].id === person && 'email_messages.json' in files,
    `the package downloads and holds about.json and one JSON file per section (${Object.keys(files).length} files)`)
  r = await fn('jobs-run', tor.token, { kind: 'privacy', id: job })
  check(r.body?.ran === false && r.body.reason === 'done', 'a written package is not written again')

  // ---------------------------------------------------------------------------
  // the browser: the screens call the function after the action, and show the result
  const ctx = await browser.newContext({ acceptDownloads: true })
  const page = await ctx.newPage()
  const errors = []
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()) })
  page.on('pageerror', (e) => errors.push(e.message))
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' })
  await page.fill('input[name=email]', 'tor@orgpuls.no'); await page.fill('input[name=password]', DEV_PASSWORD)
  await page.click('button[type=submit]'); await page.waitForURL('**/mfa'); await page.waitForLoadState('networkidle')
  await page.fill('input[name=code]', totp(DEV_TOTP)); await page.click('button[type=submit]')
  await page.waitForURL((u) => !u.pathname.startsWith('/mfa'), { timeout: 30000 })
  const seen = (re, timeout = 20000) => page.getByText(re).first().waitFor({ timeout }).then(() => true, () => false)
  const track = (filename) => {
    const row = sql(`select meeting_id || '|' || storage_path from app.meeting_uploads where filename = '${filename}' order by created_at desc limit 1`)
    if (row) { const [mid, p] = row.split('|'); cleanup.push(async () => { await svc.storage.from('meeting-files').remove([p]); sql(`delete from app.meetings where id = '${mid}'`) }) }
    return row.split('|')[0]
  }
  const uploadInBrowser = async (name, buffer) => {
    await page.goto(`${BASE}/meetings`, { waitUntil: 'networkidle' })
    await page.getByRole('button', { name: 'Upload transcript' }).first().click()
    const dialog = page.getByRole('dialog')
    check(await dialog.getByText(/read into it as soon as it has been sent/).count() === 1, `Meetings (${name}): the dialog says the file is read at once`)
    await dialog.locator('input[type=file]').setInputFiles({ name, mimeType: '', buffer })
  }

  await uploadInBrowser('browser-jobs.vtt', Buffer.from('WEBVTT\n\n00:00:01.000 --> 00:00:04.000\n<v Tor Lambrechts>Hei fra nettleseren.\n\n00:00:05.000 --> 00:00:06.000\n<v Ingrid>Og svar.\n'))
  check(await seen(/Transcript uploaded and read/), 'Meetings: .vtt — «Transcript uploaded and read»')
  track('browser-jobs.vtt')
  check(await seen(/Hei fra nettleseren\./) && await seen(/Og svar\./), 'Meetings: the meeting opens on its transcript with the parsed segments')
  check(await page.getByText(/Waiting to be read/).count() === 0, 'Meetings: it no longer waits to be read')

  await uploadInBrowser('browser-jobs.docx', docx(['Kari Nordmann: Dette kommer fra Word.', 'Ola: Og dette også.'], 'b.docx'))
  check(await seen(/Transcript uploaded and read/), 'Meetings: .docx — «Transcript uploaded and read»')
  track('browser-jobs.docx')
  check(await seen(/Dette kommer fra Word\./) && await seen(/Og dette også\./), 'Meetings: the Word paragraphs appear as segments')

  await uploadInBrowser('browser-jobs-empty.vtt', Buffer.from('WEBVTT\n\nNOTE nothing said\n'))
  check(await seen(/the file could not be read/), 'Meetings: a file with no cues — «Transcript uploaded, but the file could not be read»')
  track('browser-jobs-empty.vtt')
  check(await seen(/No speech was found in the file/), 'Meetings: the transcript says why, in words, not a code')

  // «Read now»: an upload the reader did not get to (made through the API, not run) waits, and the button reads it
  const w = await upload(tor, 'browser-jobs-wait.srt', Buffer.from('1\n00:00:01,000 --> 00:00:02,000\nTor: Venter på å bli lest.\n'))
  await page.goto(`${BASE}/meetings?meeting=${w.meeting}`, { waitUntil: 'networkidle' })
  check(await seen(/Waiting to be read/), 'Meetings: an upload not yet read says «Waiting to be read …»')
  await page.getByRole('button', { name: 'Read now' }).click()
  check(await seen(/Venter på å bli lest\./), 'Meetings: «Read now» reads it and the segment appears')

  // Security › Privacy: find, export, and the package is ready to download at once
  const email = sql(`select email from app.people where id = '${person}'`)
  await page.goto(`${BASE}/security?tab=privacy`, { waitUntil: 'networkidle' })
  await page.getByPlaceholder('Email or name').fill(email)
  await page.getByPlaceholder('Email or name').press('Enter')
  await page.getByRole('button', { name: 'Export (access request)' }).click()
  const reason = page.getByRole('dialog').locator('textarea, input[type=text]')
  if (await reason.count().catch(() => 0)) { await reason.first().fill('Innsynsbegjæring (e2e)'); await page.getByRole('dialog').getByRole('button').last().click() }
  check(await seen(/Export ready · logged/), 'Security: «Export ready · logged» right after the export')
  const pjob = sql(`select id from app.privacy_jobs where kind = 'export' and created_by = (select id from app.admins where email = 'tor@orgpuls.no') order by created_at desc limit 1`)
  cleanup.push(async () => { await svc.storage.from('privacy-exports').remove([`privacy/${pjob}/access-package.zip`]); sql(`delete from app.privacy_jobs where id = '${pjob}'`) })
  check(sql(`select state from app.privacy_jobs where id = '${pjob}'`) === 'done', 'Security: the job is done')
  // the list is newest first; load it again so the first button is this export's (the earlier API package is still listed)
  await page.goto(`${BASE}/security?tab=privacy`, { waitUntil: 'networkidle' })
  const dl = page.getByRole('button', { name: 'Download package' }).first()
  await dl.waitFor({ timeout: 15000 }).catch(() => {})
  const [download] = await Promise.all([page.waitForEvent('download', { timeout: 20000 }), dl.click()])
  const chunks = []
  for await (const ch of await download.createReadStream()) chunks.push(ch)
  const got = unzip(Buffer.concat(chunks))
  check(download.suggestedFilename() === 'access-package.zip' && JSON.parse(got['about.json']).job === pjob, `Security: «Download package» downloads the ZIP (${download.suggestedFilename()}, job ${JSON.parse(got['about.json']).job === pjob ? 'this export' : 'another export'})`)

  // «Write package now»: an export the runner did not get to (made through the API) waits in the list with the button
  const { data: exp2 } = await tor.sb.rpc('privacy_export', { p_subject: { people: [person] }, p_request: null, p_reason: null })
  cleanup.push(async () => { await svc.storage.from('privacy-exports').remove([`privacy/${exp2.job}/access-package.zip`]); sql(`delete from app.privacy_jobs where id = '${exp2.job}'`) })
  await page.goto(`${BASE}/security?tab=privacy`, { waitUntil: 'networkidle' })
  check(await seen(/waiting to be written/), 'Security: an export not yet written says «waiting to be written»')
  await page.getByRole('button', { name: 'Write package now' }).first().click()
  check(await seen(/Package written · ready to download/), 'Security: «Write package now» writes it')
  check(sql(`select state from app.privacy_jobs where id = '${exp2.job}'`) === 'done', 'Security: and the job is done')

  check(errors.filter((e) => !/Download the React DevTools/.test(e)).length === 0, `no console errors${errors.length ? `: ${errors.slice(0, 3).join(' | ')}` : ''}`)
  await ctx.close()
} finally {
  for (const c of cleanup.reverse()) await Promise.resolve().then(c).catch((e) => console.log(`cleanup: ${e.message}`))
  await browser.close()
}
console.log(fails ? `${fails} failed` : 'all passed'); process.exit(fails ? 1 : 0)
