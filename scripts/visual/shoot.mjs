// Screenshots of the running app (default http://localhost:3000) as a seeded staff member, at the design's
// two widths. Usage: node scripts/visual/shoot.mjs [--as tor@orgpuls.no] [--out dir] [route ...]
import { chromium } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import { totp } from '../dev/totp.mjs'
import { DEV_PASSWORD, DEV_TOTP } from '../seed/dev-credentials.mjs'

const args = process.argv.slice(2)
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args.splice(i, 2)[1] : d }
const base = opt('--base', process.env.BASE_URL ?? 'http://localhost:3000')
const email = opt('--as', 'tor@orgpuls.no')
const out = opt('--out', 'screens/current')
const widths = opt('--widths', '1440,390').split(',').map(Number)
const routes = args.length ? args : ['/']
mkdirSync(out, { recursive: true })

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 })
const page = await ctx.newPage()
const errors = []
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()) })
page.on('pageerror', (e) => errors.push(String(e)))

await page.goto(`${base}/login`, { waitUntil: 'networkidle' })
await page.fill('input[name=email]', email)
await page.fill('input[name=password]', DEV_PASSWORD)
await page.click('button[type=submit]')
await page.waitForURL('**/mfa'); await page.waitForLoadState('networkidle')
await page.fill('input[name=code]', totp(DEV_TOTP))
await page.click('button[type=submit]')
await page.waitForURL((u) => !u.pathname.startsWith('/mfa'), { timeout: 30000 })

for (const r of routes) {
  for (const w of widths) {
    await page.setViewportSize({ width: w, height: 900 })
    await page.goto(base + r, { waitUntil: 'networkidle' })
    await page.evaluate(() => document.fonts.ready)
    const name = `${r === '/' ? 'home' : r.replace(/^\//, '').replace(/[/?=&]/g, '_')}-${w}.png`
    await page.screenshot({ path: `${out}/${name}`, fullPage: true })
    console.log(`${out}/${name}`)
  }
}
if (errors.length) console.log('console errors:\n' + errors.join('\n'))
await browser.close()
