import { z } from 'zod'

/**
 * Growth › the ad platforms (0077): what growth_ads returns and the rules the views apply to it. Pure and tested
 * (tests/ad-platforms.test.ts). Figures are the platform's own, in the ad account's currency.
 */
export const AD_PROVIDERS = ['google_ads', 'linkedin_ads', 'meta_ads'] as const
export type AdProvider = (typeof AD_PROVIDERS)[number]
const n = z.number()
const nn = z.number().nullable()
const s = z.string()
const sn = z.string().nullable()
const uuid = z.string().uuid()
const status = z.enum(['live', 'paused', 'ended'])

export const GrowthAds = z.object({
  today: s,
  can_manage: z.boolean(),
  oauth_redirect: sn,
  sentral_campaigns: z.array(z.object({ id: uuid, name: s, utm_campaign: s })),
  providers: z.array(z.object({
    provider: z.enum(AD_PROVIDERS), status: s, connected_at: sn, last_error: sn, last_check_at: sn,
    client_email: sn, login_customer_id: sn, key_source: z.enum(['own', 'search_console']), client_id: sn,
    token_expires_at: sn, refresh_expires_at: sn, stored: z.array(s),
  })),
  search_console_email: sn,
  accounts: z.array(z.object({
    id: uuid, provider: z.enum(AD_PROVIDERS), external_id: s, name: s, currency: sn, manager: z.boolean(), product: sn,
    last_import_at: sn, last_day: sn, last_error: sn, campaigns: n,
  })),
  campaigns: z.array(z.object({
    id: uuid, provider: z.enum(AD_PROVIDERS), account: s, currency: sn, name: s, status, kind: sn, utm_campaign: sn,
    ad_campaign_id: uuid.nullable(), linked_by_hand: z.boolean(), ad_campaign: sn,
    d30: z.object({ impressions: n, clicks: n, spend: n, conversions: nn }),
  })),
  ads: z.array(z.object({
    id: uuid, provider: z.enum(AD_PROVIDERS), currency: sn, name: sn, headline: sn, status, campaign: sn,
    last7: z.object({ impressions: n, clicks: n, spend: n, reach: nn, conversions: nn }),
    prev7: z.object({ impressions: n, clicks: n }),
  })),
})
export type GrowthAds = z.infer<typeof GrowthAds>
export type AdRow = GrowthAds['ads'][number]

/** clicks per impression, as a share; null without impressions */
export const ctr = (clicks: number, impressions: number) => (impressions > 0 ? clicks / impressions : null)

/** a week needs this many impressions before its click-through rate says anything */
export const FATIGUE_MIN_IMPRESSIONS = 1000

export type Fatigue = { state: 'fatigued' | 'healthy' | 'quiet'; ctr: number | null; prev: number | null; change: number | null; frequency: number | null }
/**
 * The design's fatigue rule, on what the platforms report: click-through down 30 % or more over the last seven days
 * against the seven before, when both weeks had enough impressions to tell. Frequency is impressions per person reached a
 * day (Meta reports reach by day; a week's own reach is not summed from days), shown, not judged.
 */
export function fatigue(a: Pick<AdRow, 'last7' | 'prev7'>): Fatigue {
  const now = ctr(a.last7.clicks, a.last7.impressions)
  const prev = ctr(a.prev7.clicks, a.prev7.impressions)
  const change = now !== null && prev ? (now - prev) / prev : null
  const frequency = a.last7.reach ? a.last7.impressions / a.last7.reach : null
  if (a.last7.impressions < FATIGUE_MIN_IMPRESSIONS || a.prev7.impressions < FATIGUE_MIN_IMPRESSIONS || change === null) return { state: 'quiet', ctr: now, prev, change, frequency }
  return { state: change <= -0.3 ? 'fatigued' : 'healthy', ctr: now, prev, change, frequency }
}

/** a connection's state as the card shows it: connected, an error, credentials stored but not checked, or nothing */
export function connectionState(p: GrowthAds['providers'][number]): 'connected' | 'error' | 'stored' | 'none' {
  if (p.status === 'connected') return 'connected'
  if (p.status === 'error') return 'error'
  return p.stored.length ? 'stored' : 'none'
}

/** the credentials a platform still needs before it can be checked */
export function missing(p: GrowthAds['providers'][number], searchConsoleKey: boolean): string[] {
  const has = (k: string) => p.stored.includes(k)
  if (p.provider === 'google_ads') {
    return [...(has('google_ads_developer_token') ? [] : ['developer_token']), ...(p.key_source === 'search_console' ? (searchConsoleKey ? [] : ['key']) : has('google_ads_key') ? [] : ['key'])]
  }
  if (p.provider === 'linkedin_ads') {
    return [...(p.client_id ? [] : ['client_id']), ...(has('linkedin_ads_client_secret') ? [] : ['client_secret']), ...(has('linkedin_ads_access_token') ? [] : ['sign_in'])]
  }
  return has('meta_ads_token') ? [] : ['token']
}
