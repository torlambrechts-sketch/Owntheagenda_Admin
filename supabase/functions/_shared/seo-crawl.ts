/**
 * Growth › SEO › Site health (0072): the crawler's rules, pure so the edge function (Deno) and the tests (Node) run the
 * same code. A page is read for what a search engine reads first: its status, how long it took, its title, its meta
 * description, its H1s, a robots noindex, and its links to its own site. Nothing a visitor typed or saw is read; the
 * site's public pages are all there is.
 */

export const KINDS = [
  'sitemap_missing', 'page_error', 'noindex', 'missing_title', 'missing_description', 'slow_page',
  'duplicate_title', 'duplicate_description', 'missing_h1', 'broken_link',
] as const
export type IssueKind = (typeof KINDS)[number]
export type Severity = 'high' | 'medium'
/** the design's two tones: what keeps a page out of search or loses its click is high; what weakens it is medium */
export const SEVERITY: Record<IssueKind, Severity> = {
  sitemap_missing: 'high', page_error: 'high', noindex: 'high', missing_title: 'high', missing_description: 'high', slow_page: 'high',
  duplicate_title: 'medium', duplicate_description: 'medium', missing_h1: 'medium', broken_link: 'medium',
}

export type PageFacts = {
  path: string
  status: number
  ms: number
  html: boolean
  title: string | null
  description: string | null
  h1: number
  noindex: boolean
  links: string[]
}
export type Issue = { kind: IssueKind; severity: Severity; count: number; paths: string[]; value?: string; ms?: number }
export type Broken = { path: string; status: number; from: string[] }

/** at most this many paths are named per issue; the count says how many there are */
export const NAMED = 5
/** a page slower than this, from the request to its last byte, is slow */
export const SLOW_MS = 3000

const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' }
export function decode(s: string): string {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&([a-z]+);/gi, (m, n) => ENTITIES[n.toLowerCase()] ?? m)
    .replace(/\s+/g, ' ')
    .trim()
}

/** the <loc>s of a sitemap: pages, or the sitemaps of a sitemap index */
export function sitemapUrls(xml: string): { pages: string[]; sitemaps: string[] } {
  const locs = (block: string) => [...xml.matchAll(new RegExp(`<${block}\\b[\\s\\S]*?<loc>\\s*([^<\\s]+)\\s*</loc>`, 'gi'))].map((m) => decode(m[1]!))
  return { pages: locs('url'), sitemaps: locs('sitemap') }
}

/** a tag's attributes, names lower-cased */
function attrs(tag: string): Record<string, string> {
  const out: Record<string, string> = {}
  for (const m of tag.matchAll(/([a-zA-Z_:-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))/g)) out[m[1]!.toLowerCase()] = m[3] ?? m[4] ?? m[5] ?? ''
  return out
}

/** two hosts are the same site when they differ only by www. */
export const sameSite = (a: string, b: string) => a.replace(/^www\./, '') === b.replace(/^www\./, '')

/** what a search engine reads first on a page, and its links to its own site as paths (no fragment) */
export function pageFacts(html: string, url: URL): Pick<PageFacts, 'title' | 'description' | 'h1' | 'noindex' | 'links'> {
  const head = html.slice(0, 400_000)
  const t = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(head)
  let description: string | null = null
  let noindex = false
  for (const m of head.matchAll(/<meta\b[^>]*>/gi)) {
    const a = attrs(m[0])
    const name = (a.name ?? a.property ?? '').toLowerCase()
    if (name === 'description' && description === null) description = decode(a.content ?? '') || null
    if ((name === 'robots' || name === 'googlebot') && /\bnoindex\b/i.test(a.content ?? '')) noindex = true
  }
  const links = new Set<string>()
  for (const m of html.matchAll(/<a\b[^>]*>/gi)) {
    const href = attrs(m[0]).href
    if (!href || /^(mailto:|tel:|javascript:|data:|#)/i.test(href.trim())) continue
    try {
      const u = new URL(decode(href), url)
      if ((u.protocol === 'https:' || u.protocol === 'http:') && sameSite(u.hostname, url.hostname)) links.add((u.pathname || '/') + u.search)
    } catch {
      // not an address
    }
  }
  return { title: t ? decode(t[1]!) || null : null, description, h1: (html.match(/<h1\b/gi) ?? []).length, noindex, links: [...links] }
}

const named = (paths: string[]) => [...new Set(paths)].sort().slice(0, NAMED)

/** pages sharing one value (a title, a description): the pages in groups of two or more, and the most shared value */
function duplicates(pages: PageFacts[], pick: (p: PageFacts) => string | null): { paths: string[]; value: string } | null {
  const by = new Map<string, string[]>()
  for (const p of pages) {
    const v = pick(p)
    if (v) by.set(v, [...(by.get(v) ?? []), p.path])
  }
  const groups = [...by.entries()].filter(([, ps]) => ps.length > 1).sort((a, b) => b[1].length - a[1].length)
  if (!groups.length) return null
  return { paths: groups.flatMap(([, ps]) => ps), value: groups[0]![0] }
}

/** the issues one crawl found, one per kind, most serious first */
export function issuesFrom(pages: PageFacts[], broken: Broken[], sitemap: boolean): Issue[] {
  const out: Issue[] = []
  const add = (kind: IssueKind, paths: string[], extra: Partial<Issue> = {}) => {
    if (paths.length) out.push({ kind, severity: SEVERITY[kind], count: new Set(paths).size, paths: named(paths), ...extra })
  }
  if (!sitemap) out.push({ kind: 'sitemap_missing', severity: 'high', count: 1, paths: ['/sitemap.xml'] })
  const ok = pages.filter((p) => p.status >= 200 && p.status < 300 && p.html)
  add('page_error', pages.filter((p) => p.status === 0 || p.status >= 400).map((p) => p.path))
  add('noindex', ok.filter((p) => p.noindex).map((p) => p.path))
  const indexable = ok.filter((p) => !p.noindex)
  add('missing_title', indexable.filter((p) => !p.title).map((p) => p.path))
  add('missing_description', indexable.filter((p) => !p.description).map((p) => p.path))
  const slow = ok.filter((p) => p.ms > SLOW_MS).sort((a, b) => b.ms - a.ms)
  add('slow_page', slow.map((p) => p.path), slow.length ? { ms: slow[0]!.ms } : {})
  const dt = duplicates(indexable, (p) => p.title)
  if (dt) add('duplicate_title', dt.paths, { value: dt.value.slice(0, 120) })
  const dd = duplicates(indexable, (p) => p.description)
  if (dd) add('duplicate_description', dd.paths, { value: dd.value.slice(0, 120) })
  add('missing_h1', indexable.filter((p) => p.h1 === 0).map((p) => p.path))
  if (broken.length) {
    out.push({ kind: 'broken_link', severity: 'medium', count: broken.length, paths: named(broken.map((b) => b.path)),
               value: named(broken.flatMap((b) => b.from)).join(' · ').slice(0, 200) })
  }
  const order = (i: Issue) => (i.severity === 'high' ? 0 : 1) * 100 + KINDS.indexOf(i.kind)
  return out.sort((a, b) => order(a) - order(b))
}

/** the links pages make to addresses that answered 4xx or 5xx, with the pages that make them */
export function brokenLinks(pages: PageFacts[], status: Map<string, number>): Broken[] {
  const from = new Map<string, string[]>()
  for (const p of pages) for (const l of p.links) from.set(l, [...(from.get(l) ?? []), p.path])
  return [...from.entries()]
    .filter(([path]) => (status.get(path) ?? 0) >= 400)
    .map(([path, f]) => ({ path, status: status.get(path)!, from: [...new Set(f)] }))
    .sort((a, b) => a.path.localeCompare(b.path))
}
