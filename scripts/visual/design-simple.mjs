// Renders the Sentral Simple design (design-reference/sentral-simple, falling back to sentral/project for its shared
// fonts, data and runtime) the way the prototype shows it: the shell with a section open, then the buttons named in
// --click pressed in turn (exact accessible names, «>» between them).
// Usage: node scripts/visual/design-simple.mjs --section dev --click "Bugs>Ask Claude" --out screens/design/dev-bugs.png [--width 1440]
// Sections: customers, crm, growth, platform, dev.
import { chromium } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { dirname, extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const args = process.argv.slice(2)
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args.splice(i, 2)[1] : d }
const section = opt('--section', 'customers')
const clicks = opt('--click', '').split('>').map((s) => s.trim()).filter(Boolean)
const out = opt('--out', `screens/design/${section}.png`)
const width = Number(opt('--width', '1440'))
mkdirSync(dirname(out), { recursive: true })

const repo = fileURLToPath(new URL('../../', import.meta.url))
const roots = [join(repo, 'design-reference/sentral-simple/'), join(repo, 'design-reference/sentral/project/')]
const types = { '.html': 'text/html', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2', '.css': 'text/css' }
const server = createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^([/\\])+/, '')
  for (const r of roots) {
    try { const b = await readFile(join(r, path)); res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' }); res.end(b); return } catch { /* next root */ }
  }
  res.writeHead(404); res.end()
}).listen(0)

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })
const ctx = await browser.newContext({ viewport: { width, height: 900 }, deviceScaleFactor: 1 })
const page = await ctx.newPage()
page.on('pageerror', (e) => console.log('design error:', String(e)))
// the runtime's React and Babel come from unpkg; the browser has no route out, so they are served from .cache/design-runtime
await page.route('https://unpkg.com/**', async (route) => {
  try { await route.fulfill({ body: await readFile(join(repo, '.cache/design-runtime/', route.request().url().split('/').pop())), contentType: 'text/javascript' }) } catch { await route.abort() }
})
await page.addInitScript((s) => { try { localStorage.setItem('ss.section', s) } catch { /* private mode */ } }, section)
await page.goto(`http://127.0.0.1:${server.address().port}/${encodeURIComponent('Sentral Simple.dc.html')}`)
await page.waitForTimeout(3500)
for (const name of clicks) {
  await page.getByRole('button', { name, exact: true }).first().click()
  await page.waitForTimeout(700)
}
await page.evaluate(() => document.fonts.ready)
await page.screenshot({ path: out, fullPage: true })
console.log(out)
await browser.close()
server.close()
