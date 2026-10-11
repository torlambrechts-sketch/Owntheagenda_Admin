/**
 * seo-crawl — Growth › SEO › Site health (0072). Reads each application's public site the way a search engine starts to:
 * its sitemap, then every page in it (at most 150), then the links between them (at most 200 more addresses), and hands
 * the issues it finds to worker_seo_crawl_result. The nightly job knocks with the worker key; a person who may manage the
 * application's SEO knocks with their own token («Check now», seo_crawl_check_ready).
 *
 * A whole crawl also hands over the link graph (which page links to which, with its anchor) and which of the site's
 * searches each page's content mentions (0074, worker_seo_links), for SEO › Internal links and the content brief.
 *
 * It only reads public pages, sends no cookie, and keeps no page body: what goes to the database is a count, a few paths,
 * a duplicated title, a time, the anchors and the searches mentioned. Logs carry counts and status codes.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { sameText } from '../_shared/signing.ts'
import { brokenLinks, issuesFrom, pageFacts, sameSite, sitemapUrls, type PageFacts } from '../_shared/seo-crawl.ts'

const log = (s: string) => console.log(`[seo-crawl] ${s}`)
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } })
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const UA = 'OwnTheAgenda-SiteHealth/1.0 (+https://www.owntheagenda.com)'
const MAX_PAGES = 150
const MAX_LINKS = 200
const MAX_BYTES = 2_000_000
const BUDGET_MS = 110_000

async function secret(svc: SupabaseClient, name: string): Promise<string> {
  const { data, error } = await svc.rpc('product_secret', { p_name: name })
  return !error && typeof data === 'string' ? data : ''
}

/** run `work` over `items`, `n` at a time, while time allows */
async function pool<T>(items: T[], n: number, left: () => boolean, work: (t: T) => Promise<void>): Promise<void> {
  let i = 0
  await Promise.all(Array.from({ length: n }, async () => {
    while (i < items.length && left()) await work(items[i++]!)
  }))
}

async function get(url: string, method: 'GET' | 'HEAD' = 'GET'): Promise<{ res: Response | null; ms: number }> {
  const t = Date.now()
  try {
    const res = await fetch(url, { method, redirect: 'follow', headers: { 'user-agent': UA, accept: method === 'GET' ? 'text/html,application/xml;q=0.9,*/*;q=0.5' : '*/*' }, signal: AbortSignal.timeout(15_000) })
    return { res, ms: Date.now() - t }
  } catch {
    return { res: null, ms: Date.now() - t }
  }
}

/** the body as text, at most 2 MB */
async function text(res: Response): Promise<string> {
  const reader = res.body?.getReader()
  if (!reader) return ''
  const chunks: Uint8Array[] = []
  let n = 0
  while (n < MAX_BYTES) {
    const { done, value } = await reader.read()
    if (done) break
    chunks.push(value)
    n += value.length
  }
  await reader.cancel().catch(() => {})
  const all = new Uint8Array(n)
  let o = 0
  for (const c of chunks) { all.set(c, o); o += c.length }
  return new TextDecoder().decode(all.slice(0, MAX_BYTES))
}

async function crawl(hostname: string, left: () => boolean, terms: string[]) {
  // the site's own address after its redirects (orgpuls.com → www.orgpuls.com)
  const home = await get(`https://${hostname}/`)
  if (!home.res) return { error: 'unreachable' as const }
  await home.res.body?.cancel()
  const base = new URL(home.res.url || `https://${hostname}/`)
  const origin = base.origin

  // the sitemap, or a sitemap index's sitemaps
  let urls: string[] = []
  let sitemap = false
  const sm = await get(`${origin}/sitemap.xml`)
  if (sm.res?.ok) {
    const first = sitemapUrls(await text(sm.res))
    urls = first.pages
    for (const child of first.sitemaps.slice(0, 5)) {
      const c = await get(child)
      if (c.res?.ok) urls.push(...sitemapUrls(await text(c.res)).pages)
      else await c.res?.body?.cancel()
    }
    sitemap = urls.length > 0
  } else await sm.res?.body?.cancel()
  const paths = [...new Set(urls.flatMap((u) => {
    try {
      const x = new URL(u)
      return sameSite(x.hostname, base.hostname) ? [(x.pathname || '/') + x.search] : []
    } catch {
      return []
    }
  }))]
  if (!paths.includes('/')) paths.unshift('/')

  // every page in it
  const pages: PageFacts[] = []
  await pool(paths.slice(0, MAX_PAGES), 6, left, async (path) => {
    const t0 = Date.now()
    const { res, ms } = await get(origin + path)
    if (!res) { pages.push({ path, status: 0, ms, html: false, title: null, description: null, h1: 0, noindex: false, links: [], anchors: [], mentions: [] }); return }
    const html = (res.headers.get('content-type') ?? '').includes('text/html')
    const body = html && res.ok ? await text(res) : (await res.body?.cancel(), '')
    // the time to the last byte, as a search engine waits for it
    const total = Date.now() - t0
    const facts = html && res.ok ? pageFacts(body, new URL(origin + path), terms) : { title: null, description: null, h1: 0, noindex: false, links: [], anchors: [], mentions: [] }
    if (/\bnoindex\b/i.test(res.headers.get('x-robots-tag') ?? '')) facts.noindex = true
    pages.push({ path, status: res.status, ms: total, html, ...facts })
  })

  // the links between them: the pages' own statuses, then the other addresses they point to
  const status = new Map(pages.map((p) => [p.path, p.status]))
  const others = [...new Set(pages.flatMap((p) => p.links))].filter((l) => !status.has(l)).slice(0, MAX_LINKS)
  await pool(others, 6, left, async (path) => {
    let { res } = await get(origin + path, 'HEAD')
    if (res && (res.status === 405 || res.status === 501)) ({ res } = await get(origin + path))
    await res?.body?.cancel()
    if (res) status.set(path, res.status)
  })

  return { pages, issues: issuesFrom(pages, brokenLinks(pages, status), sitemap), origin }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 503)
  let body: { site?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 1_000) return json({ error: 'too_large' }, 413)
    body = raw ? JSON.parse(raw) : {}
  } catch {
    return json({ error: 'body' }, 400)
  }
  const only = typeof body.site === 'string' && UUID.test(body.site) ? body.site : null
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })

  // who: the nightly job (worker key) or a person who may manage the site's SEO (own token)
  const offered = req.headers.get('x-worker-key') ?? ''
  if (offered) {
    const key = await secret(svc, 'seo_crawl_worker_secret')
    if (!key || !sameText(offered, key)) return json({ error: 'not_allowed' }, 403)
  } else {
    const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
    if (!token || token === serviceKey || !anonKey) return json({ error: 'unauthorized' }, 401)
    const asUser = createClient(url, anonKey, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } })
    const { data, error } = await asUser.rpc('seo_crawl_check_ready')
    const d = data as { me?: string } | null
    if (error || !d?.me || !UUID.test(d.me)) return json({ error: 'not_allowed' }, 403)
  }

  const { data: listed } = await svc.rpc('worker_seo_crawl_sites')
  const sites = (Array.isArray(listed) ? listed : []).filter((s): s is { site_id: string; hostname: string; terms?: unknown } =>
    typeof s?.site_id === 'string' && UUID.test(s.site_id) && typeof s?.hostname === 'string' && (!only || s.site_id === only))
  const start = Date.now()
  const left = () => Date.now() - start < BUDGET_MS
  const out: Array<{ site_id: string; pages: number; issues: number; error?: string }> = []
  for (const s of sites) {
    if (!left()) break
    const t = Date.now()
    const terms = (Array.isArray(s.terms) ? s.terms : []).filter((x): x is string => typeof x === 'string').slice(0, 200)
    const r = await crawl(s.hostname, left, terms)
    const ms = Date.now() - t
    if ('error' in r) {
      await svc.rpc('worker_seo_crawl_result', { p_site: s.site_id, p_pages: 0, p_ms: ms, p_issues: [], p_error: r.error })
      out.push({ site_id: s.site_id, pages: 0, issues: 0, error: r.error })
      log(`site failed ${r.error}`)
      continue
    }
    const whole = left()
    const { error } = await svc.rpc('worker_seo_crawl_result', { p_site: s.site_id, p_pages: r.pages.length, p_ms: ms, p_issues: r.issues, p_error: whole ? null : 'partial' })
    if (error) log(`result refused ${error.code ?? ''}`)
    // what each page said about itself, for Pages and links (0073): no body, no links
    const facts = r.pages.map((p) => ({ path: p.path.slice(0, 300), title: p.title, description: p.description, h1: p.h1, status: p.status, ms: p.ms, noindex: p.noindex }))
    const { error: pagesError } = await svc.rpc('worker_seo_pages', { p_site: s.site_id, p_pages: facts })
    if (pagesError) log(`pages refused ${pagesError.code ?? ''}`)
    // the link graph and the mentions (0074), only from a whole crawl: a partial one would make pages look orphaned
    if (whole) {
      const links = r.pages.flatMap((p) => (p.anchors ?? []).map((a) => ({ from: p.path.slice(0, 300), to: a.to.slice(0, 300), anchor: a.text }))).slice(0, 40_000)
      const mentions = r.pages.flatMap((p) => (p.mentions ?? []).map((term) => ({ path: p.path.slice(0, 300), term }))).slice(0, 20_000)
      const { error: linksError } = await svc.rpc('worker_seo_links', { p_site: s.site_id, p_origin: r.origin, p_links: links, p_mentions: mentions })
      if (linksError) log(`links refused ${linksError.code ?? ''}`)
      else log(`links=${links.length} mentions=${mentions.length}`)
    }
    out.push({ site_id: s.site_id, pages: r.pages.length, issues: r.issues.length })
    log(`site pages=${r.pages.length} issues=${r.issues.length} ms=${ms}`)
  }
  return json({ ok: true, sites: out })
})
