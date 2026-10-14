/**
 * search-console-run — Google Search Console's figures into Growth › SEO (0064). The app holds no service role and no
 * Google key; this does.
 *
 * POST {"kind": "connect" | "run"}
 *   - "connect": the owner (own aal2 token; search_console_check_ready proves the owner). Signs in as the service account,
 *     lists the properties it may read, maps each site to one, reports the verdict, then imports what time allows.
 *   - "run": the nightly cron (header x-worker-key = Vault «search_console_worker_secret») or the owner. Maps a site that
 *     has no property yet (a market site added later, 0089), then imports each site's own pages (two market sites can
 *     share a domain property) since a little before its last imported day, thirty days at a time, oldest first, for about ninety
 *     seconds; the next run goes on from there. A window holds the day totals, the searches, the searches by page, and
 *     each page's, country's and device's own figures (0091). Then, until about two and a quarter minutes, it asks URL Inspection
 *     whether Google has each crawled page in its index (0074), the longest unchecked first.
 *
 * Logs carry kinds, counts and status codes. Never a query, an address or the key.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { sameText } from '../_shared/signing.ts'
import { accessToken, inspectUrl, listSites, pageFilter, parseKey, propertyFor, searchAnalytics, wholeProperty, windows } from '../_shared/google.ts'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const log = (s: string) => console.log(`[search-console-run] ${s}`)
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

async function secret(svc: SupabaseClient, name: string): Promise<string> {
  const { data, error } = await svc.rpc('product_secret', { p_name: name })
  return !error && typeof data === 'string' ? data : ''
}

async function rpc<T>(svc: SupabaseClient, fn: string, args: Record<string, unknown> = {}): Promise<T | null> {
  const { data, error } = await svc.rpc(fn, args)
  if (error) {
    log(`${fn} refused ${error.code ?? ''}`.trim())
    return null
  }
  return data as T
}

const arr = <T>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : [])

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 503)
  let body: { kind?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 1_000) return json({ error: 'too_large' }, 413)
    body = raw ? JSON.parse(raw) : {}
  } catch {
    return json({ error: 'body' }, 400)
  }
  const kind = body.kind
  if (kind !== 'run' && kind !== 'connect') return json({ error: 'invalid' }, 400)
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })

  // who: the cron (worker key, run only) or the owner (own token)
  const offered = req.headers.get('x-worker-key') ?? ''
  let me: string | null = null
  if (offered) {
    const key = await secret(svc, 'search_console_worker_secret')
    if (!key || !sameText(offered, key) || kind !== 'run') return json({ error: 'not_allowed' }, 403)
  } else {
    const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
    if (!token || token === serviceKey || !anonKey) return json({ error: 'unauthorized' }, 401)
    const asUser = createClient(url, anonKey, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } })
    const { data, error } = await asUser.rpc('search_console_check_ready')
    const d = data as { me?: string } | null
    if (error || !d?.me || !UUID.test(d.me)) return json({ error: 'not_allowed' }, 403)
    me = d.me
  }

  const key = parseKey(await secret(svc, 'search_console_key'))
  if (!key) return json({ ok: false, code: 'no_key' })
  const start = Date.now()
  const budget = kind === 'connect' ? 35_000 : 90_000
  const left = () => Date.now() - start < budget
  // URL Inspection after the import, while the run's time allows (0074)
  const inspectLeft = () => Date.now() - start < 135_000

  const tok = await accessToken(key)
  if (!tok.ok) {
    await rpc(svc, 'worker_search_console_result', { p_ok: false, p_info: { code: tok.code }, p_by: me })
    log(`${kind} refused ${tok.code}`)
    return json({ ok: false, code: tok.code })
  }

  let sites: Array<{ hostname: string; property: string | null }> = []
  const ours = arr<{ site_id: string; hostname: string; property?: string | null }>(await rpc(svc, 'worker_search_console_sites'))
  // «connect» maps every site to its property; the nightly run maps the sites that have none yet, a market site added
  // after the connection included (0089). A refusal of the listing stops a connect, not a run's import.
  const unmapped = kind === 'connect' ? ours : ours.filter((s) => !s.property)
  if (unmapped.length) {
    const listed = await listSites(tok.token)
    if (!listed.ok && kind === 'connect') {
      await rpc(svc, 'worker_search_console_result', { p_ok: false, p_info: { code: listed.code }, p_by: me })
      log(`connect refused ${listed.code}`)
      return json({ ok: false, code: listed.code })
    }
    if (listed.ok) {
      const mapped = unmapped.map((s) => ({ site_id: s.site_id, hostname: s.hostname, property: propertyFor(s.hostname, listed.sites) }))
      await rpc(svc, 'worker_search_console_result', { p_ok: true, p_info: { sites: mapped.map(({ site_id, property }) => ({ site_id, property })) }, p_by: me })
      if (kind === 'connect') sites = mapped.map(({ hostname, property }) => ({ hostname, property }))
      log(`${kind} mapping properties=${listed.sites.length} mapped=${mapped.filter((m) => m.property).length}/${mapped.length}`)
    } else log(`run mapping refused ${listed.code}`)
  }

  // the import: each site's windows, oldest first, while time allows
  let windowsDone = 0
  let rowsIn = 0
  let failed = 0
  for (const t of arr<{ site_id: string; property: string; from: string; to: string; hosts?: unknown; except?: unknown }>(await rpc(svc, 'worker_search_console_targets'))) {
    if (!left()) break
    if (t.from > t.to) continue
    // only the site's own pages: two market sites can share a domain property (0089). A property that is the site's
    // alone is read without a filter, so its figures are counted as Search Console counts them (0091)
    const filter = pageFilter(t.hosts, t.except)
    if (!filter) continue
    const only = wholeProperty(t.property, t.hosts, t.except) ? null : filter
    for (const w of windows(t.from, t.to, 30)) {
      if (!left()) break
      const [days, queries, pages, pageTotals, countries, devices] = await Promise.all([
        searchAnalytics(tok.token, t.property, w.from, w.to, 'day', fetch, only),
        searchAnalytics(tok.token, t.property, w.from, w.to, 'query', fetch, only),
        searchAnalytics(tok.token, t.property, w.from, w.to, 'page', fetch, only),
        searchAnalytics(tok.token, t.property, w.from, w.to, 'pageTotal', fetch, only),
        searchAnalytics(tok.token, t.property, w.from, w.to, 'country', fetch, only),
        searchAnalytics(tok.token, t.property, w.from, w.to, 'device', fetch, only),
      ])
      // a window is imported whole or not at all: its days are tried again by the next run (0091)
      if (!days.ok || !queries.ok || !pageTotals.ok || !countries.ok || !devices.ok) {
        const code = [days, queries, pageTotals, countries, devices].map((x) => (x.ok ? '' : x.code)).find(Boolean) ?? 'failed'
        await rpc(svc, 'worker_search_console_failed', { p_site: t.site_id, p_code: code })
        failed++
        log(`import refused ${code}`)
        break
      }
      if (queries.capped || pageTotals.capped) log('import capped at 100000 rows for one window')
      const r = await rpc<{ totals: number; rows: number }>(svc, 'worker_search_console_import', {
        p_site: t.site_id, p_totals: days.rows, p_rows: queries.rows, p_pages: pageTotals.rows, p_countries: countries.rows, p_devices: devices.rows,
      })
      if (!r) { failed++; break }
      // the page each query was seen on (0072): «Ranking page», split searches, content ideas. A refusal here keeps the
      // window's totals and queries; the pages come again with the next window that overlaps
      if (pages.ok) {
        if (pages.capped) log('pages capped at 100000 rows for one window')
        await rpc(svc, 'worker_search_console_pages', { p_site: t.site_id, p_from: w.from, p_to: w.to, p_rows: pages.rows })
      } else log(`pages refused ${pages.code}`)
      windowsDone++
      rowsIn += r.rows
    }
  }
  log(`${kind} windows=${windowsDone} rows=${rowsIn} failed=${failed}`)

  // index coverage: four pages at a time; a refusal for quota or access stops the site until the next run
  let inspected = 0
  if (kind === 'run') {
    for (const t of arr<{ site_id: string; property: string; origin: string; paths: string[] }>(await rpc(svc, 'worker_seo_index_targets'))) {
      if (!inspectLeft()) break
      const paths = arr<string>(t.paths).filter((p) => typeof p === 'string' && p.startsWith('/'))
      const rows: Array<{ path: string; coverage: string; last_crawl_at: string | null }> = []
      let stop = ''
      let i = 0
      await Promise.all(Array.from({ length: 4 }, async () => {
        while (i < paths.length && inspectLeft() && !stop) {
          const path = paths[i++]!
          const r = await inspectUrl(tok.token, t.property, t.origin + path)
          if (r.ok) rows.push({ path, coverage: r.coverage, last_crawl_at: r.lastCrawlAt })
          else if (/^http_(401|403|429)$/.test(r.code)) stop = r.code
        }
      }))
      if (rows.length) await rpc(svc, 'worker_seo_index_result', { p_site: t.site_id, p_rows: rows })
      inspected += rows.length
      log(`inspect pages=${rows.length}/${paths.length}${stop ? ` stopped ${stop}` : ''}`)
    }
  }
  return json({ ok: true, ...(kind === 'connect' ? { client_email: key.client_email, sites } : {}), windows: windowsDone, rows: rowsIn, failed, inspected })
})
