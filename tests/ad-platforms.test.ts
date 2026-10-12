import { describe, expect, it } from 'vitest'
import {
  GOOGLE_API, LINKEDIN_API, META_API, days, googleAccounts, googleImport, googleStatus, liAnalyticsUrl, liDaily, liStatus, linkedinImport,
  linkedinToken, metaConversions, metaImport, metaStatus, utmFrom,
} from '../supabase/functions/_shared/ads'
import { connectionState, fatigue, missing, type GrowthAds } from '../lib/growth/ads'
import { parseGrowth, growthHref } from '../lib/growth/scope'

/** a fetch that answers by URL and records what was asked */
function fake(routes: Array<[RegExp, unknown | ((url: string, init?: RequestInit) => unknown), number?]>) {
  const calls: Array<{ url: string; init?: RequestInit }> = []
  const f = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input)
    calls.push({ url, init })
    const hit = routes.find(([re]) => re.test(url))
    if (!hit) return new Response('{}', { status: 404 })
    const body = typeof hit[1] === 'function' ? (hit[1] as (u: string, i?: RequestInit) => unknown)(url, init) : hit[1]
    return new Response(JSON.stringify(body), { status: hit[2] ?? 200 })
  }) as typeof fetch
  return { f, calls }
}

describe('Ad platforms: shared rules (0077)', () => {
  it('reads utm_campaign from a template, a suffix or url_tags, never a placeholder', () => {
    expect(utmFrom('{lpurl}?utm_source=google&utm_campaign=Lovkrav-Q4')).toBe('lovkrav-q4')
    expect(utmFrom(null, 'utm_medium=cpc&utm_campaign=hr%2Dmanagers')).toBe('hr-managers')
    expect(utmFrom('utm_campaign={campaignid}')).toBeNull()
    expect(utmFrom('utm_source=x')).toBeNull()
  })
  it('days run inclusive', () => {
    expect(days('2026-09-29', '2026-10-02')).toEqual(['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02'])
  })
  it('each platform\'s status is live, paused or ended', () => {
    expect(googleStatus('ENABLED')).toBe('live')
    expect(googleStatus('ENABLED', 'ENDED')).toBe('ended')
    expect(googleStatus('REMOVED')).toBe('ended')
    expect(liStatus('ACTIVE')).toBe('live')
    expect(liStatus('DRAFT')).toBe('paused')
    expect(liStatus('COMPLETED')).toBe('ended')
    expect(metaStatus('ADSET_PAUSED')).toBe('paused')
    expect(metaStatus('ARCHIVED')).toBe('ended')
  })
})

describe('Google Ads (v25)', () => {
  const auth = { token: 'tok', developerToken: 'dev-token-1234567890', loginCustomerId: null }
  it('lists the accounts the service account may open, with the developer token on every call', async () => {
    const { f, calls } = fake([
      [/customers:listAccessibleCustomers$/, { resourceNames: ['customers/1234567890', 'customers/bad'] }],
      [/customers\/1234567890\/googleAds:search$/, { results: [{ customer: { id: '1234567890', descriptiveName: 'Orgpuls', currencyCode: 'NOK', timeZone: 'Europe/Oslo', manager: false } }] }],
    ])
    const r = await googleAccounts(auth, f)
    expect(r).toEqual({ ok: true, accounts: [{ id: '1234567890', name: 'Orgpuls', currency: 'NOK', time_zone: 'Europe/Oslo', manager: false }] })
    expect(calls.every((c) => (c.init?.headers as Record<string, string>)['developer-token'] === 'dev-token-1234567890')).toBe(true)
    expect(calls[0]!.url.startsWith(GOOGLE_API)).toBe(true)
  })
  it('under a manager account: its clients, and the login-customer-id header', async () => {
    const { f, calls } = fake([[/customers\/1112223334\/googleAds:search$/, { results: [
      { customerClient: { id: '1112223334', descriptiveName: 'MCC', manager: true, status: 'ENABLED' } },
      { customerClient: { id: '5556667778', descriptiveName: 'Client', currencyCode: 'NOK', manager: false, status: 'ENABLED' } },
      { customerClient: { id: '9990001112', descriptiveName: 'Closed', manager: false, status: 'CANCELED' } }] }]])
    const r = await googleAccounts({ ...auth, loginCustomerId: '1112223334' }, f)
    expect(r.ok && r.accounts.map((a) => [a.id, a.manager])).toEqual([['1112223334', true], ['5556667778', false]])
    expect((calls[0]!.init?.headers as Record<string, string>)['login-customer-id']).toBe('1112223334')
  })
  it('imports campaigns, ads and days; cost in micros becomes kroner', async () => {
    const { f } = fake([[/googleAds:search$/, (_u: string, init?: RequestInit) => {
      const q = JSON.parse(String(init?.body)).query as string
      if (q.startsWith('SELECT campaign.id, campaign.name')) return { results: [{ campaign: { id: '111', name: 'Lovkrav', status: 'ENABLED', servingStatus: 'SERVING', advertisingChannelType: 'SEARCH', startDateTime: '2026-09-01 00:00:00', finalUrlSuffix: 'utm_source=google&utm_campaign=lovkrav-q4' } }] }
      if (q.includes('FROM campaign WHERE segments.date')) return { results: [{ campaign: { id: '111' }, segments: { date: '2026-10-01' }, metrics: { impressions: '1200', clicks: '80', costMicros: '412345678', conversions: 3.0 } }] }
      if (q.includes('ad_group_ad.ad.responsive_search_ad.headlines')) return { results: [{ campaign: { id: '111' }, adGroupAd: { status: 'ENABLED', ad: { id: '9001', responsiveSearchAd: { headlines: [{ text: 'Er dere dekket?' }] } } } }] }
      return { results: [{ campaign: { id: '111' }, adGroupAd: { ad: { id: '9001' } }, segments: { date: '2026-10-01' }, metrics: { impressions: '600', clicks: '40', costMicros: '200000000' } }] }
    }]])
    const r = await googleImport(auth, '1234567890', '2026-10-01', '2026-10-01', f)
    if (!r.ok) throw new Error(r.code)
    expect(r.campaigns).toEqual([{ id: '111', name: 'Lovkrav', status: 'live', kind: 'search', starts_on: '2026-09-01', ends_on: null, utm_campaign: 'lovkrav-q4' }])
    expect(r.ads).toEqual([{ id: '9001', campaign: '111', name: null, headline: 'Er dere dekket?', status: 'live' }])
    expect(r.daily).toEqual([
      { level: 'campaign', id: '111', day: '2026-10-01', impressions: 1200, clicks: 80, spend: 412.35, conversions: 3, reach: null },
      { level: 'ad', id: '9001', day: '2026-10-01', impressions: 600, clicks: 40, spend: 200, conversions: null, reach: null },
    ])
  })
  it('a refusal is the status as a code', async () => {
    const { f } = fake([[/googleAds:search$/, { error: { message: 'secret detail' } }, 403]])
    expect(await googleImport(auth, '1234567890', '2026-10-01', '2026-10-01', f)).toEqual({ ok: false, code: 'http_403' })
  })
})

describe('LinkedIn Ads (202609)', () => {
  it('asks adAnalytics in Rest.li syntax, by day, for the account', () => {
    expect(liAnalyticsUrl('502840441', 'CAMPAIGN', '2026-09-28', '2026-10-02')).toBe(
      `${LINKEDIN_API}/adAnalytics?q=analytics&pivot=CAMPAIGN&timeGranularity=DAILY&dateRange=(start:(year:2026,month:9,day:28),end:(year:2026,month:10,day:2))`
      + '&accounts=List(urn%3Ali%3AsponsoredAccount%3A502840441)&fields=impressions,clicks,costInLocalCurrency,externalWebsiteConversions,dateRange,pivotValues')
  })
  it('reads a day per pivot; cost comes as a string', () => {
    expect(liDaily('campaign', [{ pivotValues: ['urn:li:sponsoredCampaign:123'], dateRange: { start: { year: 2026, month: 10, day: 1 }, end: { year: 2026, month: 10, day: 1 } },
      impressions: 165, clicks: 11, costInLocalCurrency: '19.91833', externalWebsiteConversions: 2 }])).toEqual(
      [{ level: 'campaign', id: '123', day: '2026-10-01', impressions: 165, clicks: 11, spend: 19.92, conversions: 2, reach: null }])
  })
  it('imports campaigns with their run schedule and creatives with their campaign, page by page', async () => {
    const { f, calls } = fake([
      [/adCampaigns\?q=search&pageSize=100$/, { elements: [{ id: 123, name: 'HR', status: 'ACTIVE', type: 'SPONSORED_UPDATES', runSchedule: { start: Date.UTC(2026, 8, 1) } }], metadata: { nextPageToken: 'p2' } }],
      [/adCampaigns\?q=search&pageSize=100&pageToken=p2$/, { elements: [{ id: 124, name: 'Old', status: 'COMPLETED' }], metadata: {} }],
      [/creatives\?q=criteria/, { elements: [{ id: 'urn:li:sponsoredCreative:777', campaign: 'urn:li:sponsoredCampaign:123', intendedStatus: 'ACTIVE', name: 'Video' }] }],
      [/pivot=CAMPAIGN/, { elements: [] }],
      [/pivot=CREATIVE/, { elements: [] }],
    ])
    const r = await linkedinImport('tok', '502840441', '2026-10-01', '2026-10-02', f)
    if (!r.ok) throw new Error(r.code)
    expect(r.campaigns.map((c) => [c.id, c.status, c.starts_on])).toEqual([['123', 'live', '2026-09-01'], ['124', 'ended', null]])
    expect(r.ads).toEqual([{ id: '777', campaign: '123', name: 'Video', headline: null, status: 'live' }])
    const h = calls[0]!.init?.headers as Record<string, string>
    expect(h['Linkedin-Version']).toBe('202609')
    expect(h['X-Restli-Protocol-Version']).toBe('2.0.0')
  })
  it('exchanges a code or a refresh token; no access token is a refusal', async () => {
    const ok = fake([[/accessToken$/, { access_token: 'a'.repeat(30), expires_in: 5184000, refresh_token: 'r'.repeat(30), refresh_token_expires_in: 31536000 }]])
    expect(await linkedinToken({ grant_type: 'authorization_code', code: 'c' }, ok.f)).toEqual({ ok: true, tokens: { access: 'a'.repeat(30), refresh: 'r'.repeat(30), expiresIn: 5184000, refreshExpiresIn: 31536000 } })
    expect(String(ok.calls[0]!.init?.body)).toBe('grant_type=authorization_code&code=c')
    const none = fake([[/accessToken$/, { error: 'x' }]])
    expect(await linkedinToken({ grant_type: 'refresh_token' }, none.f)).toEqual({ ok: false, code: 'token_empty' })
  })
})

describe('Meta Ads (v26.0)', () => {
  it('counts leads and completed registrations, Meta\'s own totals, once', () => {
    expect(metaConversions([{ action_type: 'lead', value: '3' }, { action_type: 'offsite_conversion.fb_pixel_lead', value: '3' }, { action_type: 'complete_registration', value: '2' }, { action_type: 'link_click', value: '40' }])).toBe(5)
    expect(metaConversions([{ action_type: 'link_click', value: '40' }])).toBe(0)
    expect(metaConversions(undefined)).toBeNull()
  })
  it('imports with appsecret_proof, follows only Graph API pages, and takes a campaign\'s utm from its ads', async () => {
    const { f, calls } = fake([
      [/act_987\/campaigns/, { data: [{ id: '211', name: 'Retargeting', effective_status: 'ACTIVE', objective: 'OUTCOME_TRAFFIC', start_time: '2026-09-01T10:00:00+0200' }],
                              paging: { next: 'https://evil.example/next' } }],
      [/act_987\/ads/, { data: [{ id: '8001', name: 'Ad', effective_status: 'ACTIVE', campaign_id: '211', creative: { title: 'Prøv gratis', url_tags: 'utm_source=facebook&utm_campaign=meta-retarget' } }] }],
      [/level=campaign/, { data: [{ campaign_id: '211', date_start: '2026-10-01', impressions: '1000', clicks: '11', spend: '120.50', reach: '700', actions: [{ action_type: 'lead', value: '1' }] }] }],
      [/level=ad/, { data: [{ ad_id: '8001', date_start: '2026-10-01', impressions: '1000', clicks: '11', spend: '120.50', reach: '700' }] }],
    ])
    const r = await metaImport({ token: 'tok', appSecret: 'abc' }, '987', '2026-10-01', '2026-10-01', f)
    if (!r.ok) throw new Error(r.code)
    expect(r.campaigns).toEqual([{ id: '211', name: 'Retargeting', status: 'live', kind: 'outcome_traffic', starts_on: '2026-09-01', ends_on: null, utm_campaign: 'meta-retarget' }])
    expect(r.ads[0]).toEqual({ id: '8001', campaign: '211', name: 'Ad', headline: 'Prøv gratis', status: 'live' })
    expect(r.daily).toContainEqual({ level: 'campaign', id: '211', day: '2026-10-01', impressions: 1000, clicks: 11, spend: 120.5, conversions: 1, reach: 700 })
    expect(calls.every((c) => c.url.startsWith(META_API) && /appsecret_proof=[0-9a-f]{64}/.test(c.url))).toBe(true)
    expect(calls.some((c) => c.url.includes('evil.example'))).toBe(false)
  })
})

describe('Ad platforms in the app (0077)', () => {
  const ad = (last: [number, number], prev: [number, number], reach: number | null = null) =>
    ({ last7: { impressions: last[0], clicks: last[1], spend: 0, reach, conversions: null }, prev7: { impressions: prev[0], clicks: prev[1] } })
  it('fatigued when click-through fell 30 % or more on enough impressions in both weeks', () => {
    expect(fatigue(ad([2000, 10], [2000, 20])).state).toBe('fatigued')
    expect(fatigue(ad([2000, 15], [2000, 20])).state).toBe('healthy')
    expect(fatigue(ad([500, 1], [2000, 20])).state).toBe('quiet')
    expect(fatigue(ad([2000, 10], [2000, 0])).state).toBe('quiet')
    expect(fatigue(ad([2100, 10], [2000, 20], 1500)).frequency).toBeCloseTo(1.4)
  })
  const provider = (over: Partial<GrowthAds['providers'][number]>): GrowthAds['providers'][number] => ({
    provider: 'google_ads', status: 'not_connected', connected_at: null, last_error: null, last_check_at: null, client_email: null, login_customer_id: null,
    key_source: 'own', client_id: null, token_expires_at: null, refresh_expires_at: null, stored: [], ...over,
  })
  it('says what a platform still needs', () => {
    expect(missing(provider({}), false)).toEqual(['developer_token', 'key'])
    expect(missing(provider({ key_source: 'search_console', stored: ['google_ads_developer_token'] }), true)).toEqual([])
    expect(missing(provider({ provider: 'linkedin_ads', client_id: 'abc12345', stored: ['linkedin_ads_client_secret'] }), false)).toEqual(['sign_in'])
    expect(missing(provider({ provider: 'meta_ads', stored: ['meta_ads_token'] }), false)).toEqual([])
    expect(connectionState(provider({ stored: ['google_ads_developer_token'] }))).toBe('stored')
    expect(connectionState(provider({ status: 'error' }))).toBe('error')
  })
  it('an ad platform\'s setup has an address', () => {
    expect(parseGrowth({ tab: 'integrations', sub: 'linkedin_ads' }).sub).toBe('linkedin_ads')
    expect(parseGrowth({ tab: 'integrations', sub: '_x' }).sub).toBeNull()
    expect(growthHref('integrations', {}, { sub: 'meta_ads' })).toBe('/growth?tab=integrations&sub=meta_ads')
  })
})
