// The sign-in journey with session reports, in a browser (R-SECURITY-04): signing out ends the row as «signed out»,
// and a session the register ends is signed out at the next page with the reason. Needs the function running
// (see session-report-e2e.mjs), a proxy sending /functions/v1/session-report to it, and a dev server on :3311
// whose NEXT_PUBLIC_SUPABASE_URL is that proxy (the local stack has no edge runtime).
import { chromium } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import { totp } from './totp.mjs'
import { DEV_PASSWORD, DEV_TOTP } from '../seed/dev-credentials.mjs'
const DB = 'postgresql://postgres:postgres@127.0.0.1:54422/postgres'
const sql = (q) => execFileSync('psql', [DB, '-qtAc', q], { encoding: 'utf8' }).trim()
const base = 'http://localhost:3311'
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })
let fails = 0
const check = (ok, w) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${w}`); if (!ok) fails++ }
async function signIn(email) {
  const ctx = await browser.newContext()
  const page = await ctx.newPage()
  await page.goto(`${base}/login`, { waitUntil: 'networkidle' })
  await page.fill('input[name=email]', email); await page.fill('input[name=password]', DEV_PASSWORD)
  await page.click('button[type=submit]'); await page.waitForURL('**/mfa'); await page.waitForLoadState('networkidle')
  await page.fill('input[name=code]', totp(DEV_TOTP)); await page.click('button[type=submit]')
  await page.waitForURL((u) => !u.pathname.startsWith('/mfa'), { timeout: 30000 })
  const sid = sql(`select s.session_id from app.staff_sessions s join app.admins a on a.id = s.staff_id where a.email = '${email}' and s.ended_at is null order by s.created_at desc limit 1`)
  return { ctx, page, sid }
}
// 1. sign out ends the row as signed_out
{
  const { ctx, page, sid } = await signIn('ingrid@orgpuls.no')
  check(!!sid, 'the sign-in is in the register')
  await page.locator('header button[aria-haspopup], header [aria-label*="ccount"], header button').last().click().catch(() => {})
  const form = page.locator('form button', { hasText: /Sign out|Logg ut/ })
  if (await form.count()) await form.first().click()
  else await page.evaluate(() => { const f = [...document.querySelectorAll('form')].find((x) => /Sign out|Logg ut/.test(x.textContent)); f?.requestSubmit() })
  await page.waitForURL('**/login', { timeout: 15000 }).catch(() => {})
  check(sql(`select end_reason from app.staff_sessions where session_id = '${sid}'`) === 'signed_out', `signing out ends the row as signed_out (now at ${new URL(page.url()).pathname})`)
  await ctx.close()
}
// 2. a session the register ends (idle past 30 minutes) is signed out at the next report, with the reason
{
  const { ctx, page, sid } = await signIn('ola@orgpuls.no')
  sql(`update app.staff_sessions set last_seen_at = now() - interval '45 minutes' where session_id = '${sid}'`)
  await ctx.clearCookies({ name: 'ota_seen' })
  await page.goto(`${base}/security`, { waitUntil: 'networkidle' })
  const u = new URL(page.url())
  check(u.pathname === '/login' && u.searchParams.get('ended') === 'idle_timeout', `an idle session is signed out with its reason (${u.pathname}${u.search})`)
  check(sql(`select end_reason from app.staff_sessions where session_id = '${sid}'`) === 'idle_timeout', 'the register ended it as idle_timeout')
  check(await page.getByText(/30 minutes|30 minutter/).count() > 0, 'the sign-in page says why')
  await ctx.close()
}
await browser.close()
console.log(fails ? `${fails} failed` : 'all passed'); process.exit(fails ? 1 : 0)
