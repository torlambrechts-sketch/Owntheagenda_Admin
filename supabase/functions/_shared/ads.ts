/**
 * The ad platforms, reduced to what Sentral reads (0077): the ad accounts the credentials may see, each account's campaigns
 * and ads, and their days (impressions, clicks, spend, conversions as the platform counts them, reach where reported).
 * Read only: nothing here changes anything on a platform. Web Crypto and fetch only, so the edge function (Deno) and the
 * tests (Node) run the same code; fetch is passed in. Nothing from a response body is logged or passed on beyond the
 * figures and names below: a refusal comes back as a code (the HTTP status, or a short word).
 *
 *   Google Ads    REST v25, a service account's access token, the developer token, an optional manager (login) account;
 *                 also each keyword (ad_group_criterion) with its days from keyword_view, and each campaign's bidding
 *                 strategy (0083). Never search_term_view: what people typed can carry a name
 *   LinkedIn Ads  the versioned REST API (Linkedin-Version 202609), a member's access token with r_ads and r_ads_reporting;
 *                 reach is not asked for by day (LinkedIn reports it for whole periods)
 *   Meta Ads      Graph API v26.0, a system user's token, appsecret_proof when the app secret is known
 */
import { hmacHex } from './signing.ts'

type Fetch = typeof fetch
export type Fail = { ok: false; code: string }
export type Status = 'live' | 'paused' | 'ended'
export type Account = { id: string; name: string; currency: string | null; time_zone: string | null; manager: boolean }
export type Campaign = { id: string; name: string; status: Status; kind: string | null; starts_on: string | null; ends_on: string | null; utm_campaign: string | null }
export type Ad = { id: string; campaign: string; name: string | null; headline: string | null; status: Status }
export type Daily = { level: 'campaign' | 'ad'; id: string; day: string; impressions: number; clicks: number; spend: number; conversions: number | null; reach: number | null }
/** a Google Ads keyword (the advertiser's own text, at most 80 characters) and its day; a criterion id is unique within its ad group */
export type Keyword = { id: string; ad_group: string; campaign: string; text: string; match_type: 'exact' | 'phrase' | 'broad' | null; status: Status }
export type KeywordDaily = { id: string; ad_group: string; day: string; impressions: number; clicks: number; spend: number; conversions: number | null }
/** a Google campaign's bidding strategy, lower case (manual_cpc, maximize_conversions …) */
export type Bidding = { id: string; bidding: string }
/** keywords and their days are null when Google refused them (the import goes on without them) */
export type Import = { campaigns: Campaign[]; ads: Ad[]; daily: Daily[]; keywords?: Keyword[] | null; keywordDaily?: KeywordDaily[] | null; bidding?: Bidding[] }

export const GOOGLE_API = 'https://googleads.googleapis.com/v25'
export const GOOGLE_SCOPE = 'https://www.googleapis.com/auth/adwords'
export const LINKEDIN_API = 'https://api.linkedin.com/rest'
export const LINKEDIN_VERSION = '202609'
export const LINKEDIN_TOKEN = 'https://www.linkedin.com/oauth/v2/accessToken'
export const LINKEDIN_AUTHORIZE = 'https://www.linkedin.com/oauth/v2/authorization'
export const META_API = 'https://graph.facebook.com/v26.0'

const ID = /^[0-9]{1,24}$/
const DAY = /^\d{4}-\d{2}-\d{2}$/
const num = (v: unknown): number => {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN
  return Number.isFinite(n) && n >= 0 ? n : 0
}
const numOrNull = (v: unknown): number | null => (v === undefined || v === null || v === '' ? null : num(v))
const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v.trim().slice(0, 300) : null)
const idOf = (v: unknown): string | null => {
  // a bare id, a LinkedIn URN (urn:li:sponsoredCampaign:123) or a Google resource name (customers/123)
  const s = typeof v === 'number' ? String(v) : typeof v === 'string' ? v.replace(/^.*[:/]/, '') : ''
  return ID.test(s) ? s : null
}
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {})
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : [])

/** the utm_campaign a tracking template, a final URL suffix or Meta's url_tags carry; not a placeholder ({…}) */
export function utmFrom(...texts: Array<string | null | undefined>): string | null {
  for (const t of texts) {
    if (!t) continue
    const m = /(?:^|[?&#;\s])utm_campaign=([^&#;\s]+)/i.exec(t)
    if (!m) continue
    let v = m[1]!
    try { v = decodeURIComponent(v) } catch { /* as it is */ }
    v = v.toLowerCase()
    if (/^[a-z0-9_-]{1,60}$/.test(v)) return v
  }
  return null
}

/** one day after another, inclusive */
export function days(from: string, to: string): string[] {
  const out: string[] = []
  for (let t = Date.parse(`${from}T00:00:00Z`); t <= Date.parse(`${to}T00:00:00Z`) && out.length < 400; t += 86_400_000) out.push(new Date(t).toISOString().slice(0, 10))
  return out
}

async function getJson(f: Fetch, url: string, init: RequestInit): Promise<{ ok: true; body: unknown } | Fail> {
  try {
    const res = await f(url, { ...init, signal: AbortSignal.timeout(30_000) })
    if (!res.ok) {
      await res.body?.cancel()
      return { ok: false, code: `http_${res.status}` }
    }
    return { ok: true, body: await res.json().catch(() => null) }
  } catch {
    return { ok: false, code: 'network' }
  }
}

// ---------------------------------------------------------------------------
// Google Ads
export type GoogleAuth = { token: string; developerToken: string; loginCustomerId: string | null }

const googleHeaders = (a: GoogleAuth) => ({
  authorization: `Bearer ${a.token}`, 'developer-token': a.developerToken, 'content-type': 'application/json',
  ...(a.loginCustomerId ? { 'login-customer-id': a.loginCustomerId } : {}),
})

/** a GAQL query against one customer, page by page (at most ten pages of 10 000 rows) */
export async function googleSearch(a: GoogleAuth, customer: string, query: string, f: Fetch = fetch): Promise<{ ok: true; rows: Record<string, unknown>[] } | Fail> {
  const rows: Record<string, unknown>[] = []
  let pageToken: string | undefined
  for (let i = 0; i < 10; i++) {
    const r = await getJson(f, `${GOOGLE_API}/customers/${customer}/googleAds:search`, {
      method: 'POST', headers: googleHeaders(a), body: JSON.stringify(pageToken ? { query, pageToken } : { query }),
    })
    if (!r.ok) return r
    const b = obj(r.body)
    for (const x of arr(b.results)) rows.push(obj(x))
    pageToken = typeof b.nextPageToken === 'string' && b.nextPageToken ? b.nextPageToken : undefined
    if (!pageToken) break
  }
  return { ok: true, rows }
}

export function googleStatus(status: unknown, serving?: unknown): Status {
  if (status === 'ENABLED') return serving === 'ENDED' ? 'ended' : 'live'
  if (status === 'PAUSED') return 'paused'
  return 'ended'
}

/** the accounts: under the manager account when one is set, else every account the service account may open */
export async function googleAccounts(a: GoogleAuth, f: Fetch = fetch): Promise<{ ok: true; accounts: Account[] } | Fail> {
  const fromRow = (c: Record<string, unknown>, manager: boolean): Account | null => {
    const id = idOf(c.id)
    return id ? { id, name: str(c.descriptiveName) ?? id, currency: str(c.currencyCode), time_zone: str(c.timeZone), manager } : null
  }
  if (a.loginCustomerId) {
    const r = await googleSearch(a, a.loginCustomerId,
      'SELECT customer_client.id, customer_client.descriptive_name, customer_client.currency_code, customer_client.time_zone, customer_client.manager, customer_client.status FROM customer_client WHERE customer_client.level <= 1', f)
    if (!r.ok) return r
    const accounts = r.rows.map((x) => obj(x.customerClient)).filter((c) => c.status === undefined || c.status === 'ENABLED')
      .map((c) => fromRow(c, c.manager === true)).filter((x): x is Account => !!x)
    return { ok: true, accounts }
  }
  const listed = await getJson(f, `${GOOGLE_API}/customers:listAccessibleCustomers`, { method: 'GET', headers: googleHeaders(a) })
  if (!listed.ok) return listed
  const ids = arr(obj(listed.body).resourceNames).map((n) => idOf(n)).filter((x): x is string => !!x).slice(0, 20)
  const accounts: Account[] = []
  for (const id of ids) {
    const r = await googleSearch(a, id, 'SELECT customer.id, customer.descriptive_name, customer.currency_code, customer.time_zone, customer.manager FROM customer LIMIT 1', f)
    if (!r.ok) continue
    const c = obj(r.rows[0]?.customer)
    const acc = fromRow(c, c.manager === true)
    if (acc) accounts.push(acc)
  }
  return { ok: true, accounts }
}

/** an account's campaigns, ads and days in the window */
export async function googleImport(a: GoogleAuth, customer: string, from: string, to: string, f: Fetch = fetch): Promise<{ ok: true } & Import | Fail> {
  const between = `segments.date BETWEEN '${from}' AND '${to}'`
  const [cs, cd, as, ad, ks, kd] = await Promise.all([
    googleSearch(a, customer, 'SELECT campaign.id, campaign.name, campaign.status, campaign.serving_status, campaign.advertising_channel_type, campaign.start_date_time, campaign.end_date_time, campaign.final_url_suffix, campaign.tracking_url_template, campaign.bidding_strategy_type FROM campaign', f),
    googleSearch(a, customer, `SELECT campaign.id, segments.date, metrics.impressions, metrics.clicks, metrics.cost_micros, metrics.conversions FROM campaign WHERE ${between}`, f),
    googleSearch(a, customer, "SELECT campaign.id, ad_group_ad.status, ad_group_ad.ad.id, ad_group_ad.ad.name, ad_group_ad.ad.responsive_search_ad.headlines FROM ad_group_ad WHERE ad_group_ad.status != 'REMOVED'", f),
    googleSearch(a, customer, `SELECT campaign.id, ad_group_ad.ad.id, segments.date, metrics.impressions, metrics.clicks, metrics.cost_micros, metrics.conversions FROM ad_group_ad WHERE ${between}`, f),
    googleSearch(a, customer, GOOGLE_KEYWORDS, f),
    googleSearch(a, customer, `${GOOGLE_KEYWORD_DAYS} WHERE ${between}`, f),
  ])
  if (!cs.ok) return cs
  if (!cd.ok) return cd
  const campaigns: Campaign[] = []
  for (const r of cs.rows) {
    const c = obj(r.campaign)
    const id = idOf(c.id)
    if (!id) continue
    const d = (v: unknown) => (typeof v === 'string' && DAY.test(v.slice(0, 10)) ? v.slice(0, 10) : null)
    campaigns.push({ id, name: str(c.name) ?? id, status: googleStatus(c.status, c.servingStatus), kind: typeof c.advertisingChannelType === 'string' ? c.advertisingChannelType.toLowerCase().slice(0, 40) : null,
      starts_on: d(c.startDateTime), ends_on: d(c.endDateTime), utm_campaign: utmFrom(str(c.trackingUrlTemplate), str(c.finalUrlSuffix)) })
  }
  const daily: Daily[] = []
  const pushDay = (level: Daily['level'], id: string | null, r: Record<string, unknown>) => {
    const m = obj(r.metrics)
    const day = obj(r.segments).date
    if (!id || typeof day !== 'string' || !DAY.test(day)) return
    daily.push({ level, id, day, impressions: num(m.impressions), clicks: num(m.clicks), spend: Math.round(num(m.costMicros) / 10_000) / 100, conversions: numOrNull(m.conversions), reach: null })
  }
  for (const r of cd.rows) pushDay('campaign', idOf(obj(r.campaign).id), r)
  // ads are worth having, not worth failing the import for
  const ads: Ad[] = []
  if (as.ok) {
    for (const r of as.rows) {
      const g = obj(r.adGroupAd)
      const x = obj(g.ad)
      const id = idOf(x.id)
      const campaign = idOf(obj(r.campaign).id)
      if (!id || !campaign) continue
      const headline = str(obj(arr(obj(x.responsiveSearchAd).headlines)[0]).text)
      ads.push({ id, campaign, name: str(x.name), headline, status: googleStatus(g.status) })
    }
  }
  if (ad.ok) for (const r of ad.rows) pushDay('ad', idOf(obj(obj(r.adGroupAd).ad).id), r)
  const bidding: Bidding[] = []
  for (const r of cs.rows) {
    const c = obj(r.campaign)
    const id = idOf(c.id)
    const b = typeof c.biddingStrategyType === 'string' ? c.biddingStrategyType.toLowerCase() : ''
    if (id && /^[a-z0-9_]{1,40}$/.test(b) && b !== 'unspecified' && b !== 'unknown') bidding.push({ id, bidding: b })
  }
  // keywords, like ads, are worth having and not worth failing the import for: both lists or neither
  const kw = ks.ok && kd.ok ? googleKeywords(ks.rows, kd.rows) : null
  return { ok: true, campaigns, ads, daily, keywords: kw?.keywords ?? null, keywordDaily: kw?.daily ?? null, bidding }
}

/** the keywords (not negatives, not removed) of every ad group; read only */
export const GOOGLE_KEYWORDS = "SELECT campaign.id, ad_group.id, ad_group_criterion.criterion_id, ad_group_criterion.keyword.text, ad_group_criterion.keyword.match_type, ad_group_criterion.status FROM ad_group_criterion WHERE ad_group_criterion.type = 'KEYWORD' AND ad_group_criterion.negative = FALSE AND ad_group_criterion.status != 'REMOVED'"
/** each keyword's days (keyword_view); never search_term_view */
export const GOOGLE_KEYWORD_DAYS = 'SELECT campaign.id, ad_group.id, ad_group_criterion.criterion_id, segments.date, metrics.impressions, metrics.clicks, metrics.cost_micros, metrics.conversions FROM keyword_view'

/** Google's keyword rows and keyword_view's days, reduced to what Sentral keeps */
export function googleKeywords(rows: Record<string, unknown>[], dayRows: Record<string, unknown>[]): { keywords: Keyword[]; daily: KeywordDaily[] } {
  const keywords: Keyword[] = []
  for (const r of rows) {
    const k = obj(r.adGroupCriterion)
    const id = idOf(k.criterionId)
    const group = idOf(obj(r.adGroup).id)
    const campaign = idOf(obj(r.campaign).id)
    const text = typeof obj(k.keyword).text === 'string' ? (obj(k.keyword).text as string).trim().slice(0, 80) : ''
    if (!id || !group || !campaign || !text) continue
    const m = obj(k.keyword).matchType
    keywords.push({ id, ad_group: group, campaign, text, match_type: m === 'EXACT' ? 'exact' : m === 'PHRASE' ? 'phrase' : m === 'BROAD' ? 'broad' : null, status: googleStatus(k.status) })
  }
  const daily: KeywordDaily[] = []
  for (const r of dayRows) {
    const id = idOf(obj(r.adGroupCriterion).criterionId)
    const group = idOf(obj(r.adGroup).id)
    const day = obj(r.segments).date
    if (!id || !group || typeof day !== 'string' || !DAY.test(day)) continue
    const m = obj(r.metrics)
    daily.push({ id, ad_group: group, day, impressions: num(m.impressions), clicks: num(m.clicks), spend: Math.round(num(m.costMicros) / 10_000) / 100, conversions: numOrNull(m.conversions) })
  }
  return { keywords, daily }
}

// ---------------------------------------------------------------------------
// LinkedIn Ads
const liHeaders = (token: string) => ({ authorization: `Bearer ${token}`, 'Linkedin-Version': LINKEDIN_VERSION, 'X-Restli-Protocol-Version': '2.0.0' })

/** Rest.li's date: (year:2026,month:10,day:1) */
export const liDate = (day: string) => `(year:${Number(day.slice(0, 4))},month:${Number(day.slice(5, 7))},day:${Number(day.slice(8, 10))})`

/** a finder's pages (pageToken), at most twenty */
async function liPages(token: string, url: string, f: Fetch): Promise<{ ok: true; elements: Record<string, unknown>[] } | Fail> {
  const out: Record<string, unknown>[] = []
  let next: string | null = null
  for (let i = 0; i < 20; i++) {
    const r = await getJson(f, next ? `${url}&pageToken=${encodeURIComponent(next)}` : url, { method: 'GET', headers: liHeaders(token) })
    if (!r.ok) return r
    const b = obj(r.body)
    for (const e of arr(b.elements)) out.push(obj(e))
    const t = obj(b.metadata).nextPageToken
    next = typeof t === 'string' && t ? t : null
    if (!next) break
  }
  return { ok: true, elements: out }
}

export function liStatus(s: unknown): Status {
  if (s === 'ACTIVE') return 'live'
  if (s === 'PAUSED' || s === 'DRAFT' || s === 'PENDING_DELETION') return 'paused'
  return 'ended'
}

export async function linkedinAccounts(token: string, f: Fetch = fetch): Promise<{ ok: true; accounts: Account[] } | Fail> {
  const r = await liPages(token, `${LINKEDIN_API}/adAccounts?q=search&search=(status:(values:List(ACTIVE,DRAFT)))&pageSize=100`, f)
  if (!r.ok) return r
  return { ok: true, accounts: r.elements.map((e): Account | null => {
    const id = idOf(e.id)
    return id ? { id, name: str(e.name) ?? id, currency: str(e.currency), time_zone: null, manager: false } : null
  }).filter((x): x is Account => !!x) }
}

/** the adAnalytics finder by one pivot, daily, for an account */
export function liAnalyticsUrl(account: string, pivot: 'CAMPAIGN' | 'CREATIVE', from: string, to: string): string {
  const urn = encodeURIComponent(`urn:li:sponsoredAccount:${account}`)
  return `${LINKEDIN_API}/adAnalytics?q=analytics&pivot=${pivot}&timeGranularity=DAILY&dateRange=(start:${liDate(from)},end:${liDate(to)})`
    + `&accounts=List(${urn})&fields=impressions,clicks,costInLocalCurrency,externalWebsiteConversions,dateRange,pivotValues`
}

const liDay = (d: unknown) => {
  const s = obj(obj(d).start)
  const y = num(s.year), m = num(s.month), day = num(s.day)
  return y && m && day ? `${y}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}` : null
}

export function liDaily(level: Daily['level'], elements: Record<string, unknown>[]): Daily[] {
  const out: Daily[] = []
  for (const e of elements) {
    const id = idOf(arr(e.pivotValues)[0])
    const day = liDay(e.dateRange)
    if (!id || !day) continue
    out.push({ level, id, day, impressions: num(e.impressions), clicks: num(e.clicks), spend: Math.round(num(e.costInLocalCurrency) * 100) / 100,
      conversions: numOrNull(e.externalWebsiteConversions), reach: null })
  }
  return out
}

export async function linkedinImport(token: string, account: string, from: string, to: string, f: Fetch = fetch): Promise<{ ok: true } & Import | Fail> {
  const [cs, cr, cd, ad] = await Promise.all([
    liPages(token, `${LINKEDIN_API}/adAccounts/${account}/adCampaigns?q=search&pageSize=100`, f),
    liPages(token, `${LINKEDIN_API}/adAccounts/${account}/creatives?q=criteria&pageSize=100`, f),
    getJson(f, liAnalyticsUrl(account, 'CAMPAIGN', from, to), { method: 'GET', headers: liHeaders(token) }),
    getJson(f, liAnalyticsUrl(account, 'CREATIVE', from, to), { method: 'GET', headers: liHeaders(token) }),
  ])
  if (!cs.ok) return cs
  if (!cd.ok) return cd
  const day = (ms: unknown) => (typeof ms === 'number' && ms > 0 ? new Date(ms).toISOString().slice(0, 10) : null)
  const campaigns: Campaign[] = cs.elements.map((e): Campaign | null => {
    const id = idOf(e.id)
    const run = obj(e.runSchedule)
    return id ? { id, name: str(e.name) ?? id, status: liStatus(e.status), kind: typeof e.type === 'string' ? e.type.toLowerCase().slice(0, 40) : null,
      starts_on: day(run.start), ends_on: day(run.end), utm_campaign: null } : null
  }).filter((x): x is Campaign => !!x)
  const ads: Ad[] = cr.ok ? cr.elements.map((e): Ad | null => {
    const id = idOf(e.id)
    const campaign = idOf(e.campaign)
    return id && campaign ? { id, campaign, name: str(e.name), headline: null, status: liStatus(e.intendedStatus ?? e.status) } : null
  }).filter((x): x is Ad => !!x) : []
  const daily = [...liDaily('campaign', arr(obj(cd.body).elements).map(obj)), ...(ad.ok ? liDaily('ad', arr(obj(ad.body).elements).map(obj)) : [])]
  return { ok: true, campaigns, ads, daily }
}

/** the authorization code from LinkedIn's sign-in, or a refresh token, exchanged for tokens */
export type LiTokens = { access: string; refresh: string | null; expiresIn: number; refreshExpiresIn: number }
export async function linkedinToken(form: Record<string, string>, f: Fetch = fetch): Promise<{ ok: true; tokens: LiTokens } | Fail> {
  const r = await getJson(f, LINKEDIN_TOKEN, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(form).toString() })
  if (!r.ok) return r
  const b = obj(r.body)
  if (typeof b.access_token !== 'string' || !b.access_token) return { ok: false, code: 'token_empty' }
  return { ok: true, tokens: { access: b.access_token, refresh: typeof b.refresh_token === 'string' && b.refresh_token ? b.refresh_token : null,
    expiresIn: num(b.expires_in), refreshExpiresIn: num(b.refresh_token_expires_in) } }
}

// ---------------------------------------------------------------------------
// Meta Ads
export type MetaAuth = { token: string; appSecret: string | null }

async function metaQuery(a: MetaAuth, extra: Record<string, string>): Promise<string> {
  const q = new URLSearchParams({ ...extra, access_token: a.token })
  if (a.appSecret) q.set('appsecret_proof', await hmacHex(a.appSecret, a.token))
  return q.toString()
}

/** an edge's pages (paging.next), at most twenty */
async function metaPages(a: MetaAuth, path: string, params: Record<string, string>, f: Fetch): Promise<{ ok: true; data: Record<string, unknown>[] } | Fail> {
  const out: Record<string, unknown>[] = []
  let url: string | null = `${META_API}/${path}?${await metaQuery(a, params)}`
  for (let i = 0; i < 20 && url; i++) {
    const r = await getJson(f, url, { method: 'GET' })
    if (!r.ok) return r
    const b = obj(r.body)
    for (const d of arr(b.data)) out.push(obj(d))
    const next = obj(b.paging).next
    // the next page keeps Meta's own address; only Graph API addresses are followed
    url = typeof next === 'string' && next.startsWith(`${META_API}/`) ? next : null
  }
  return { ok: true, data: out }
}

export function metaStatus(s: unknown): Status {
  if (s === 'ACTIVE') return 'live'
  if (s === 'ARCHIVED' || s === 'DELETED' || s === 'COMPLETED') return 'ended'
  return 'paused'
}

/** the conversions Meta reports as leads and completed registrations (its own totals of each kind, so nothing twice) */
export function metaConversions(actions: unknown): number | null {
  const list = arr(actions).map(obj)
  if (!list.length) return null
  const hit = list.filter((x) => x.action_type === 'lead' || x.action_type === 'complete_registration')
  return hit.length ? hit.reduce((s, x) => s + num(x.value), 0) : 0
}

export async function metaAccounts(a: MetaAuth, f: Fetch = fetch): Promise<{ ok: true; accounts: Account[] } | Fail> {
  const r = await metaPages(a, 'me/adaccounts', { fields: 'account_id,name,currency,timezone_name,account_status', limit: '100' }, f)
  if (!r.ok) return r
  return { ok: true, accounts: r.data.map((d): Account | null => {
    const id = idOf(d.account_id)
    return id ? { id, name: str(d.name) ?? id, currency: str(d.currency), time_zone: str(d.timezone_name), manager: false } : null
  }).filter((x): x is Account => !!x) }
}

export function metaDaily(level: Daily['level'], rows: Record<string, unknown>[]): Daily[] {
  const out: Daily[] = []
  for (const r of rows) {
    const id = idOf(level === 'campaign' ? r.campaign_id : r.ad_id)
    const day = typeof r.date_start === 'string' && DAY.test(r.date_start) ? r.date_start : null
    if (!id || !day) continue
    out.push({ level, id, day, impressions: num(r.impressions), clicks: num(r.clicks), spend: Math.round(num(r.spend) * 100) / 100,
      conversions: metaConversions(r.actions), reach: numOrNull(r.reach) })
  }
  return out
}

export async function metaImport(a: MetaAuth, account: string, from: string, to: string, f: Fetch = fetch): Promise<{ ok: true } & Import | Fail> {
  const range = JSON.stringify({ since: from, until: to })
  const [cs, as, cd, ad] = await Promise.all([
    metaPages(a, `act_${account}/campaigns`, { fields: 'id,name,effective_status,objective,start_time,stop_time', limit: '200' }, f),
    metaPages(a, `act_${account}/ads`, { fields: 'id,name,effective_status,campaign_id,creative{title,url_tags}', limit: '200' }, f),
    metaPages(a, `act_${account}/insights`, { level: 'campaign', fields: 'campaign_id,impressions,clicks,spend,reach,actions', time_increment: '1', time_range: range, limit: '500' }, f),
    metaPages(a, `act_${account}/insights`, { level: 'ad', fields: 'ad_id,impressions,clicks,spend,reach,actions', time_increment: '1', time_range: range, limit: '500' }, f),
  ])
  if (!cs.ok) return cs
  if (!cd.ok) return cd
  // a campaign's utm_campaign: the first of its ads' url_tags that carries one
  const utmByCampaign = new Map<string, string>()
  if (as.ok) for (const d of as.data) {
    const c = idOf(d.campaign_id)
    const u = utmFrom(str(obj(d.creative).url_tags))
    if (c && u && !utmByCampaign.has(c)) utmByCampaign.set(c, u)
  }
  const day = (v: unknown) => (typeof v === 'string' && DAY.test(v.slice(0, 10)) ? v.slice(0, 10) : null)
  const campaigns: Campaign[] = cs.data.map((d): Campaign | null => {
    const id = idOf(d.id)
    return id ? { id, name: str(d.name) ?? id, status: metaStatus(d.effective_status), kind: typeof d.objective === 'string' ? d.objective.toLowerCase().slice(0, 40) : null,
      starts_on: day(d.start_time), ends_on: day(d.stop_time), utm_campaign: utmByCampaign.get(id) ?? null } : null
  }).filter((x): x is Campaign => !!x)
  const ads: Ad[] = as.ok ? as.data.map((d): Ad | null => {
    const id = idOf(d.id)
    const campaign = idOf(d.campaign_id)
    return id && campaign ? { id, campaign, name: str(d.name), headline: str(obj(d.creative).title), status: metaStatus(d.effective_status) } : null
  }).filter((x): x is Ad => !!x) : []
  const daily = [...metaDaily('campaign', cd.data), ...(ad.ok ? metaDaily('ad', ad.data) : [])]
  return { ok: true, campaigns, ads, daily }
}
