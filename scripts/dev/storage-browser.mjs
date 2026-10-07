// Upload and download in a browser through the storage signer (0052): a project file, a capture on the mobile preview, a
// meeting transcript and a privacy package. Needs the function running (see storage-sign-e2e.mjs), a proxy that sends
// /functions/v1/storage-sign to it and everything else to the local stack, and a dev server whose
// NEXT_PUBLIC_SUPABASE_URL is that proxy (BASE, default http://localhost:3323). SUPABASE_SERVICE_ROLE_KEY plays the
// privacy worker. It removes the rows and objects it made (local only).
import { chromium } from '@playwright/test'
import { createClient } from '@supabase/supabase-js'
import { execFileSync } from 'node:child_process'
import { totp } from './totp.mjs'
import { DEV_PASSWORD, DEV_TOTP } from '../seed/dev-credentials.mjs'

const DB = 'postgresql://postgres:postgres@127.0.0.1:54422/postgres'
const sql = (q) => execFileSync('psql', [DB, '-qtAc', q], { encoding: 'utf8' }).trim()
const base = process.env.BASE ?? 'http://localhost:3323'
const svc = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL ?? 'http://127.0.0.1:54421', process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })
let fails = 0
const check = (ok, w) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${w}`); if (!ok) fails++ }
const cleanup = []
const errors = []

const ctx = await browser.newContext({ acceptDownloads: true })
const page = await ctx.newPage()
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()) })
page.on('pageerror', (e) => errors.push(e.message))
async function signIn(email) {
  await page.goto(`${base}/login`, { waitUntil: 'networkidle' })
  await page.fill('input[name=email]', email); await page.fill('input[name=password]', DEV_PASSWORD)
  await page.click('button[type=submit]'); await page.waitForURL('**/mfa'); await page.waitForLoadState('networkidle')
  await page.fill('input[name=code]', totp(DEV_TOTP)); await page.click('button[type=submit]')
  await page.waitForURL((u) => !u.pathname.startsWith('/mfa'), { timeout: 30000 })
}
const toast = (re) => page.getByText(re).first().waitFor({ timeout: 20000 }).then(() => true, () => false)
async function downloaded(click) {
  const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 20000 }), click()])
  const chunks = []
  for await (const c of await dl.createReadStream()) chunks.push(c)
  return { name: dl.suggestedFilename(), body: Buffer.concat(chunks) }
}

// tor's own API session (for the export the privacy test starts), then the browser's
const api = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL ?? 'http://127.0.0.1:54421', process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } })
{
  const { error } = await api.auth.signInWithPassword({ email: 'tor@orgpuls.no', password: DEV_PASSWORD })
  if (error) throw error
  const { data: f } = await api.auth.mfa.listFactors()
  const { error: e2 } = await api.auth.mfa.challengeAndVerify({ factorId: f.totp[0].id, code: totp(DEV_TOTP) })
  if (e2) throw e2
}

try {
  await signIn('tor@orgpuls.no')

  // 1. Projects › Files and sharing: upload, then open it again
  const project = sql(`select id from app.projects where deleted_at is null and status = 'open' order by created_at limit 1`)
  await page.goto(`${base}/projects?project=${project}`, { waitUntil: 'networkidle' })
  const card = page.locator('div', { has: page.getByText('Files and sharing', { exact: true }) }).last()
  const upload = card.getByRole('button', { name: /Upload file/ })
  check(await upload.isEnabled(), 'Projects: «＋ Upload file» is enabled while the signer runs')
  check(await card.getByText(/storage signer, which is not connected/).count() === 0, 'Projects: the «not connected» line is gone')
  const pdf = Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n')
  await card.locator('input[type=file]').setInputFiles({ name: 'browser-e2e.pdf', mimeType: 'application/pdf', buffer: pdf })
  check(await toast(/browser-e2e\.pdf uploaded/), 'Projects: the upload lands and is confirmed')
  const fileId = sql(`select id from app.record_files where entity = 'project' and record_id = '${project}' and filename = 'browser-e2e.pdf' and ready_at is not null and deleted_at is null order by created_at desc limit 1`)
  const fpath = fileId ? sql(`select storage_path from app.record_files where id = '${fileId}'`) : ''
  cleanup.push(async () => { await svc.storage.from('record-files').remove([fpath]); sql(`update app.record_files set deleted_at = now() where id = '${fileId}'`) })
  check(!!fileId && sql(`select count(*) from storage.objects where bucket_id = 'record-files' and name = '${fpath}'`) === '1', 'Projects: the object is in the private bucket and the file is listed')
  const got = await downloaded(() => card.getByRole('button', { name: '▦ browser-e2e.pdf' }).click())
  check(got.name === 'browser-e2e.pdf' && got.body.equals(pdf), `Projects: clicking the file downloads the same bytes (${got.name}, ${got.body.length} bytes)`)

  // 2. Mobile › Capture: an audio note and a photo on the deal
  await page.goto(`${base}/mobile`, { waitUntil: 'networkidle' })
  const record = page.getByRole('button', { name: 'Record audio note' })
  if (await record.count()) {
    check(await record.isEnabled(), 'Mobile: «Record audio note» is enabled')
    const audioInput = page.locator('input[type=file][accept*="audio/webm"]')
    await audioInput.setInputFiles({ name: 'browser-note.webm', mimeType: 'audio/webm', buffer: Buffer.from('1a45dfa3', 'hex') })
    check(await toast(/Audio note attached to .* transcription not connected/), 'Mobile: the audio note is attached; the toast says transcription is not connected')
    const audio = sql(`select id || '|' || storage_path from app.record_files where filename = 'browser-note.webm' and capture_kind = 'audio' and deleted_at is null order by created_at desc limit 1`)
    check(!!audio, 'Mobile: capture_save marked it as an audio note')
    if (audio) { const [aid, ap] = audio.split('|'); cleanup.push(async () => { await svc.storage.from('record-files').remove([ap]); sql(`update app.record_files set deleted_at = now() where id = '${aid}'`) }) }
    check(await toast(/^browser-note\.webm$/), 'Mobile: the audio card shows the note')
    await page.locator('input[type=file][accept*="image/png"]').first().setInputFiles({ name: 'browser-photo.png', mimeType: 'image/png', buffer: Buffer.from('89504e470d0a1a0a', 'hex') })
    check(await toast(/Saved on /), 'Mobile: a photo is saved on the deal')
    const photo = sql(`select id || '|' || storage_path from app.record_files where filename = 'browser-photo.png' and capture_kind = 'photo' and deleted_at is null order by created_at desc limit 1`)
    check(!!photo, 'Mobile: capture_save marked it as a photo')
    if (photo) { const [pid, pp] = photo.split('|'); cleanup.push(async () => { await svc.storage.from('record-files').remove([pp]); sql(`update app.record_files set deleted_at = now() where id = '${pid}'`) }) }
  } else {
    check(false, 'Mobile: the staff member has a deal to capture on')
  }

  // 3. Meetings › Upload transcript
  await page.goto(`${base}/meetings`, { waitUntil: 'networkidle' })
  await page.getByRole('button', { name: 'Upload transcript' }).first().click()
  const dialog = page.getByRole('dialog')
  check(await dialog.getByRole('button', { name: 'Choose file' }).isEnabled(), 'Meetings: «Choose file» is enabled')
  const vtt = 'WEBVTT\n\n00:00.000 --> 00:02.000\n<v Tor>Hei fra nettleseren.\n'
  await dialog.locator('input[type=file]').setInputFiles({ name: 'browser-e2e.vtt', mimeType: '', buffer: Buffer.from(vtt) })
  check(await toast(/Transcript uploaded/), 'Meetings: «Transcript uploaded»')
  const mu = sql(`select meeting_id || '|' || storage_path || '|' || state from app.meeting_uploads where filename = 'browser-e2e.vtt' order by created_at desc limit 1`)
  const [mid, mpath, mstate] = mu.split('|')
  cleanup.push(async () => { await svc.storage.from('meeting-files').remove([mpath]); sql(`delete from app.meetings where id = '${mid}'`) })
  // with jobs-run behind the proxy (0054) the file is read at once and its original deleted; without it, it waits
  check((mstate === 'uploaded' && sql(`select count(*) from storage.objects where bucket_id = 'meeting-files' and name = '${mpath}'`) === '1') || mstate === 'parsed',
    `Meetings: the file landed in meeting-files and the upload is confirmed (${mstate})`)
  const shown = async () => (await page.getByText(mstate === 'parsed' ? /Hei fra nettleseren\./ : /Waiting to be read/).count()) > 0
  check(await shown() || (await page.waitForTimeout(1500), await shown()), `Meetings: the new meeting opens and shows ${mstate === 'parsed' ? 'the transcript' : 'that the file waits to be read'}`)

  // 4. Security › Privacy: a package the worker wrote downloads
  // the export as privacy_export makes it (the Finder's «Export» calls the same function), the worker's part by the service role
  const person = sql(`select id from app.people where deleted_at is null order by created_at limit 1`)
  const { data: exp, error: ee } = await api.rpc('privacy_export', { p_subject: { people: [person] }, p_request: null, p_reason: null })
  if (ee) throw ee
  const jobId = exp.job
  const ppath = `privacy/${jobId}/package.json`
  cleanup.push(async () => { await svc.storage.from('privacy-exports').remove([ppath]); sql(`delete from app.privacy_jobs where id = '${jobId}'`) })
  await svc.rpc('worker_privacy_package', { p_job: jobId })
  const pkg = Buffer.from(JSON.stringify({ people: 1, note: 'browser e2e' }))
  await svc.storage.from('privacy-exports').upload(ppath, new Blob([pkg], { type: 'application/json' }), { contentType: 'application/json' })
  await svc.rpc('worker_privacy_done', { p_job: jobId, p_path: ppath, p_error: null })
  await page.goto(`${base}/security?tab=privacy`, { waitUntil: 'networkidle' })
  const dl = page.getByRole('button', { name: 'Download package' }).first()
  check(await dl.count() > 0 && await page.getByText(/download link not available/).count() === 0, 'Security: a ready package offers «Download package», not «not connected»')
  const pk = await downloaded(() => dl.click())
  check(pk.name === 'package.json' && pk.body.equals(pkg), `Security: the package downloads (${pk.name}, ${pk.body.length} bytes)`)
  check(sql(`select count(*) from app.audit where action = 'privacy_package.viewed' and target_id = '${jobId}'`) === '1', 'Security: the read is audited once')

  check(errors.filter((e) => !/Download the React DevTools/.test(e)).length === 0, `no console errors${errors.length ? `: ${errors.slice(0, 3).join(' | ')}` : ''}`)
} finally {
  for (const c of cleanup.reverse()) await Promise.resolve().then(c).catch((e) => console.log(`cleanup: ${e.message}`))
  await browser.close()
}
console.log(fails ? `${fails} failed` : 'all passed'); process.exit(fails ? 1 : 0)
