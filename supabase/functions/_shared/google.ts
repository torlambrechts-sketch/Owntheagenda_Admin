/**
 * Google Search Console, reduced to what Sentral needs (0064): sign in as a service account (an RS256 JWT exchanged for
 * an access token), list the properties the account may read, find a site's property, and read Search Analytics by day,
 * or by day and query. Web Crypto only, so the edge function (Deno) and the tests (Node) run the same code. Nothing from
 * a response body is passed on or logged: the caller gets the HTTP status as a code.
 */
import { toBase64Url } from './signing.ts'

export type ServiceKey = { client_email: string; private_key: string; token_uri: string }
export type GoogleSite = { siteUrl: string; permissionLevel: string }
export type DayRow = { day: string; impressions: number; clicks: number; position: number | null }
export type QueryRow = DayRow & { query: string }
/** a day × query × page row; the page is its path (and query string), never the host */
export type PageRow = QueryRow & { page: string }
type Fetch = typeof fetch
type Fail = { ok: false; code: string }

export const SCOPE = 'https://www.googleapis.com/auth/webmasters.readonly'
const API = 'https://www.googleapis.com/webmasters/v3'
const enc = new TextEncoder()

/** the JSON key file Google hands out for a service account; null when it is not one */
export function parseKey(raw: string): ServiceKey | null {
  try {
    const j = JSON.parse(raw) as Record<string, unknown>
    if (j.type !== 'service_account' || typeof j.client_email !== 'string' || typeof j.private_key !== 'string') return null
    if (!/^-----BEGIN PRIVATE KEY-----/.test(j.private_key)) return null
    const tokenUri = typeof j.token_uri === 'string' && /^https:\/\/oauth2\.googleapis\.com\/token$/.test(j.token_uri) ? j.token_uri : 'https://oauth2.googleapis.com/token'
    return { client_email: j.client_email, private_key: j.private_key, token_uri: tokenUri }
  } catch {
    return null
  }
}

function pemToDer(pem: string): Uint8Array {
  const b64 = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '')
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

/** the signed assertion Google exchanges for an access token (one hour) */
export async function serviceJwt(key: ServiceKey, scope: string, nowSec: number): Promise<string> {
  const head = toBase64Url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))
  const body = toBase64Url(enc.encode(JSON.stringify({ iss: key.client_email, scope, aud: key.token_uri, iat: nowSec, exp: nowSec + 3600 })))
  const der = pemToDer(key.private_key)
  const k = await crypto.subtle.importKey('pkcs8', der.buffer.slice(der.byteOffset, der.byteOffset + der.byteLength) as ArrayBuffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', k, enc.encode(`${head}.${body}`)))
  return `${head}.${body}.${toBase64Url(sig)}`
}

/** an access token for the service account, for Search Console unless another scope is asked for (Google Ads, 0077) */
export async function accessToken(key: ServiceKey, f: Fetch = fetch, nowSec = Math.floor(Date.now() / 1000), scope = SCOPE): Promise<{ ok: true; token: string } | Fail> {
  let assertion: string
  try {
    assertion = await serviceJwt(key, scope, nowSec)
  } catch {
    return { ok: false, code: 'bad_key' }
  }
  try {
    const res = await f(key.token_uri, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
      signal: AbortSignal.timeout(15_000),
    })
    if (!res.ok) {
      await res.body?.cancel()
      return { ok: false, code: `token_${res.status}` }
    }
    const j = (await res.json().catch(() => ({}))) as { access_token?: string }
    return j.access_token ? { ok: true, token: j.access_token } : { ok: false, code: 'token_empty' }
  } catch {
    return { ok: false, code: 'network' }
  }
}

/** the properties the account may read (an unverified user's are left out: Search Analytics refuses them) */
export async function listSites(token: string, f: Fetch = fetch): Promise<{ ok: true; sites: GoogleSite[] } | Fail> {
  try {
    const res = await f(`${API}/sites`, { headers: { authorization: `Bearer ${token}`, accept: 'application/json' }, signal: AbortSignal.timeout(15_000) })
    if (!res.ok) {
      await res.body?.cancel()
      return { ok: false, code: `http_${res.status}` }
    }
    const j = (await res.json().catch(() => ({}))) as { siteEntry?: Array<{ siteUrl?: string; permissionLevel?: string }> }
    const sites = (j.siteEntry ?? [])
      .filter((s): s is GoogleSite => typeof s.siteUrl === 'string' && typeof s.permissionLevel === 'string' && s.permissionLevel !== 'siteUnverifiedUser')
      .map((s) => ({ siteUrl: s.siteUrl.toLowerCase(), permissionLevel: s.permissionLevel }))
    return { ok: true, sites }
  } catch {
    return { ok: false, code: 'network' }
  }
}

/**
 * The property that covers a site: a domain property first (it counts every subdomain and both schemes), then the exact
 * https address, its www twin, and the http ones. Null when the account may read none of them.
 */
export function propertyFor(hostname: string, sites: GoogleSite[]): string | null {
  const host = hostname.toLowerCase().replace(/\.$/, '')
  const bare = host.replace(/^www\./, '')
  const urls = new Set(sites.map((s) => s.siteUrl))
  const domains = sites.map((s) => s.siteUrl).filter((u) => u.startsWith('sc-domain:')).map((u) => u.slice('sc-domain:'.length))
  // the most specific domain property that covers the host
  const domain = domains.filter((d) => host === d || host.endsWith(`.${d}`)).sort((a, b) => b.length - a.length)[0]
  if (domain) return `sc-domain:${domain}`
  for (const u of [`https://${host}/`, `https://${host === bare ? `www.${bare}` : bare}/`, `http://${host}/`, `http://${host === bare ? `www.${bare}` : bare}/`]) {
    if (urls.has(u)) return u
  }
  return null
}

const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0)
const DAY = /^\d{4}-\d{2}-\d{2}$/

/** the path of a page Search Console names by its full address; null for anything that is not one */
export function pagePath(url: unknown): string | null {
  if (typeof url !== 'string') return null
  try {
    const u = new URL(url)
    if (u.protocol !== 'https:' && u.protocol !== 'http:') return null
    return (u.pathname + u.search).slice(0, 300) || '/'
  } catch {
    return null
  }
}

type Rows<D> = D extends 'day' ? DayRow[] : D extends 'query' ? QueryRow[] : PageRow[]
const DIMS = { day: ['date'], query: ['date', 'query'], page: ['date', 'query', 'page'] } as const

/** Search Analytics for one property and period: by day, by day and query, or by day, query and page (0072); pages of
 *  25 000 rows, at most four */
export async function searchAnalytics<D extends 'day' | 'query' | 'page'>(token: string, property: string, from: string, to: string, by: D, f: Fetch = fetch):
  Promise<{ ok: true; rows: Rows<D>; capped: boolean } | Fail> {
  const rows: PageRow[] = []
  const shape = (): Rows<D> => (by === 'day' ? rows.map(({ query: _q, page: _p, ...d }) => d) : by === 'query' ? rows.map(({ page: _p, ...q }) => q) : rows) as Rows<D>
  const PAGE = 25_000
  for (let page = 0; page < 4; page++) {
    let res: Response
    try {
      res = await f(`${API}/sites/${encodeURIComponent(property)}/searchAnalytics/query`, {
        method: 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', accept: 'application/json' },
        body: JSON.stringify({ startDate: from, endDate: to, dimensions: DIMS[by], rowLimit: PAGE, startRow: page * PAGE, dataState: 'final' }),
        signal: AbortSignal.timeout(30_000),
      })
    } catch {
      return { ok: false, code: 'network' }
    }
    if (!res.ok) {
      await res.body?.cancel()
      return { ok: false, code: `http_${res.status}` }
    }
    const j = (await res.json().catch(() => ({}))) as { rows?: Array<{ keys?: unknown[]; impressions?: unknown; clicks?: unknown; position?: unknown }> }
    const got = j.rows ?? []
    for (const r of got) {
      const day = typeof r.keys?.[0] === 'string' ? r.keys[0] : ''
      if (!DAY.test(day)) continue
      const query = typeof r.keys?.[1] === 'string' ? r.keys[1] : ''
      if (by !== 'day' && !query.trim()) continue
      const pg = by === 'page' ? pagePath(r.keys?.[2]) : ''
      if (pg === null) continue
      const position = num(r.position)
      rows.push({ day, query, page: pg, impressions: Math.max(0, Math.round(num(r.impressions))), clicks: Math.max(0, Math.round(num(r.clicks))), position: position > 0 ? position : null })
    }
    if (got.length < PAGE) return { ok: true, rows: shape(), capped: false }
  }
  return { ok: true, rows: shape(), capped: true }
}

/** a period as windows of at most `days` days, oldest first (dates as YYYY-MM-DD, UTC) */
export function windows(from: string, to: string, days: number): Array<{ from: string; to: string }> {
  const out: Array<{ from: string; to: string }> = []
  const end = Date.parse(`${to}T00:00:00Z`)
  for (let t = Date.parse(`${from}T00:00:00Z`); t <= end; t += days * 86_400_000) {
    const stop = Math.min(t + (days - 1) * 86_400_000, end)
    out.push({ from: new Date(t).toISOString().slice(0, 10), to: new Date(stop).toISOString().slice(0, 10) })
  }
  return out
}

// ---------------------------------------------------------------------------
// URL Inspection (0074): whether Google has a page in its index, for SEO › Overview's index coverage and the deindex
// alert. One call per page; Google allows 2 000 a day and 600 a minute per property.

export const COVERAGE = ['indexed', 'crawled_not_indexed', 'discovered_not_indexed', 'duplicate', 'noindex', 'not_found', 'redirect',
  'blocked', 'error', 'unknown', 'other'] as const
export type Coverage = (typeof COVERAGE)[number]

/** Google's verdict and coverage sentence («Crawled - currently not indexed») reduced to the design's buckets */
export function coverageKey(verdict: unknown, state: unknown, fetchState?: unknown): Coverage {
  const s = typeof state === 'string' ? state.toLowerCase() : ''
  if (verdict === 'PASS') return 'indexed'
  if (/unknown to google/.test(s)) return 'unknown'
  if (/crawled/.test(s) && /not indexed/.test(s)) return 'crawled_not_indexed'
  if (/discovered/.test(s)) return 'discovered_not_indexed'
  if (/duplicate|alternate|canonical/.test(s)) return 'duplicate'
  if (/noindex/.test(s)) return 'noindex'
  if (/soft 404|server error|5xx|unauthori[sz]ed|forbidden|40[13]/.test(s)) return 'error'
  if (fetchState === 'NOT_FOUND' || /not found|404/.test(s)) return 'not_found'
  if (/redirect/.test(s)) return 'redirect'
  if (/robots\.txt|blocked/.test(s)) return 'blocked'
  if (/indexed/.test(s) && !/not indexed/.test(s)) return 'indexed'
  return 'other'
}

const INSPECT = 'https://searchconsole.googleapis.com/v1/urlInspection/index:inspect'

/** one page's index status; the property is the one Search Console reads the site under */
export async function inspectUrl(token: string, property: string, url: string, f: Fetch = fetch):
  Promise<{ ok: true; coverage: Coverage; lastCrawlAt: string | null } | Fail> {
  let res: Response
  try {
    res = await f(INSPECT, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ inspectionUrl: url, siteUrl: property }),
      signal: AbortSignal.timeout(20_000),
    })
  } catch {
    return { ok: false, code: 'network' }
  }
  if (!res.ok) {
    await res.body?.cancel()
    return { ok: false, code: `http_${res.status}` }
  }
  const j = (await res.json().catch(() => ({}))) as {
    inspectionResult?: { indexStatusResult?: { verdict?: unknown; coverageState?: unknown; pageFetchState?: unknown; lastCrawlTime?: unknown } }
  }
  const r = j.inspectionResult?.indexStatusResult
  if (!r) return { ok: false, code: 'empty' }
  const crawled = typeof r.lastCrawlTime === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(r.lastCrawlTime) ? r.lastCrawlTime : null
  return { ok: true, coverage: coverageKey(r.verdict, r.coverageState, r.pageFetchState), lastCrawlAt: crawled }
}
