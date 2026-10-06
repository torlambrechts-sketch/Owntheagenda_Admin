// Renders the design bundle's screens (design-reference/sentral/project) the way the prototype shows them:
// the shell with sa.route set, at the given widths. Usage: node scripts/visual/design.mjs [--out dir] [route ...]
import { chromium } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const args = process.argv.slice(2)
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args.splice(i, 2)[1] : d }
const out = opt('--out', 'screens/design')
const widths = opt('--widths', '1440,390').split(',').map(Number)
const routes = args.length ? args : ['home']
mkdirSync(out, { recursive: true })
// the prototype loads its imports over http, so it is served, not opened as a file
const root = fileURLToPath(new URL('../../design-reference/sentral/project/', import.meta.url))
const types = { '.html': 'text/html', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2', '.css': 'text/css' }
const server = createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^([/\\])+/, '')
  try { const body = await readFile(join(root, path)); res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' }); res.end(body) }
  catch { res.writeHead(404); res.end() }
}).listen(0)
const cache = fileURLToPath(new URL('../../.cache/design-runtime/', import.meta.url))
const file = `http://127.0.0.1:${server.address().port}/${encodeURIComponent('Sentral Admin.dc.html')}`

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' })
for (const r of routes) {
  for (const w of widths) {
    const ctx = await browser.newContext({ viewport: { width: w, height: 900 }, deviceScaleFactor: 1 })
    const page = await ctx.newPage()
    // the runtime's React and Babel come from unpkg; the browser has no route out, so they are served from
    // .cache/design-runtime (fetch once: curl the three URLs in support.js into that folder)
    await page.route('https://unpkg.com/**', async (route) => {
      const name = route.request().url().split('/').pop()
      try { await route.fulfill({ body: await readFile(join(cache, name)), contentType: 'text/javascript' }) } catch { await route.abort() }
    })
    await page.addInitScript((route) => { try { localStorage.setItem('sa.route', route); localStorage.setItem('sa.product', 'all') } catch {} }, r)
    await page.goto(file)
    await page.waitForTimeout(2500)
    await page.evaluate(() => document.fonts.ready)
    await page.screenshot({ path: `${out}/${r}-${w}.png`, fullPage: true })
    console.log(`${out}/${r}-${w}.png`)
    await ctx.close()
  }
}
await browser.close()
server.close()
