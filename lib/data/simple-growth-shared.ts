import { z } from 'zod'
import type { CHANNELS } from './analytics-calc'

/**
 * Sentral Simple › Growth (SimpleGrowth.dc.html, GrowthMarketing.dc.html), shared by the server page and its client parts:
 * the tabs and ranges in the address, the shapes 0058/0059 return, and the pure helpers (tracking links, the email
 * editor's model). Nothing here invents a value; the database checks everything again.
 */

export const GROWTH_TABS = ['analytics', 'seo', 'campaigns', 'email'] as const
export type GrowthTab = (typeof GROWTH_TABS)[number]
export const GROWTH_RANGES = ['7d', '30d', '90d'] as const
export type GrowthRange = (typeof GROWTH_RANGES)[number]
export const RANGE_DAYS: Record<GrowthRange, 7 | 30 | 90> = { '7d': 7, '30d': 30, '90d': 90 }
/** Tabs with the range control (the design's showRange). */
export const RANGED: readonly GrowthTab[] = ['analytics', 'seo']

/** The address of a tab and range: the defaults (Analytics, 30 d) are left out; a tab without the range carries none. */
export function growthHref(tab: GrowthTab, range: GrowthRange): string {
  const q = new URLSearchParams()
  if (tab !== 'analytics') q.set('tab', tab)
  if (RANGED.includes(tab) && range !== '30d') q.set('range', range)
  const s = q.toString()
  return s ? `/growth?${s}` : '/growth'
}

const n = z.number()
const nn = z.number().nullable()
const uuid = z.string().uuid()
const Site = z.object({ id: uuid, hostname: z.string() }).nullable()

// ---------------------------------------------------------------------------
// Analytics (growth_overview)
export const FUNNEL_KEYS = ['visited', 'viewed_pricing', 'started_signup', 'account_created', 'survey_sent', 'paying'] as const
export const Overview = z.object({
  days: n,
  site: Site,
  tracked: z.boolean(),
  // the tracker's first day (0067): visitors and the visit → signup share mean nothing before it
  tracked_since: z.string().nullable().catch(null),
  kpis: z.object({
    visitors: nn,
    visitors_prev: nn,
    signups: n,
    signups_prev: n,
    signups_tracked: nn.catch(null),
    trial_conversion: z.object({ trials: nn, converted: nn }).nullable(),
    spend: nn,
    spend_excluded_currency: n,
    spend_from: z.string(),
    paying_new: n,
  }),
  daily: z.array(z.object({ day: z.string(), signups: n, visitors: nn })),
  funnel: z.array(z.object({ key: z.enum(FUNNEL_KEYS), count: nn })),
  sources: z.array(z.object({ channel: z.string(), visits: nn, signups: n })),
  pages: z.array(z.object({ path: z.string(), visits: n })),
})
export type Overview = z.infer<typeof Overview>

/** The design's swatch per source (sources[].c), on channel_rules' keys; paid social has none in the design. */
export const CHANNEL_COLOR: Record<string, string> = {
  organic_search: '#5C9A55', paid_search: '#E0A21F', direct: '#C4BCA8', social: '#6E8FB8', partner: '#8F74B3', email: '#D4633A', paid_social: '#E38258',
}
/** The funnel's bar colours (F[].c). */
export const FUNNEL_COLOR: Record<(typeof FUNNEL_KEYS)[number], string> = {
  visited: '#E4EEEC', viewed_pricing: '#CFE0F5', started_signup: '#F3E2C9', account_created: '#DCEBD3', survey_sent: '#CFE7E4', paying: '#F5C64A',
}

// ---------------------------------------------------------------------------
// SEO (seo_get)
export const ISSUE_KINDS = ['sitemap_missing', 'page_error', 'noindex', 'missing_title', 'missing_description', 'slow_page',
  'duplicate_title', 'duplicate_description', 'missing_h1', 'broken_link'] as const
export const SeoIssue = z.object({
  kind: z.enum(ISSUE_KINDS), severity: z.enum(['high', 'medium']), count: n, paths: z.array(z.string()),
  value: z.string().nullable(), ms: nn, first_seen_at: z.string(), reopened: z.boolean(),
})
export type SeoIssue = z.infer<typeof SeoIssue>
export const Seo = z.object({
  connected: z.boolean(),
  days: n,
  site: Site,
  /** the Search Console connection (0064): who may manage it, the account to give access to, the site's property, the last import */
  search_console: z.object({
    status: z.enum(['not_connected', 'connected', 'error']), can_manage: z.boolean(), key_stored: z.boolean(),
    client_email: z.string().nullable(), last_error: z.string().nullable(), property: z.string().nullable(),
    site_error: z.string().nullable(), last_import_at: z.string().nullable(), last_day: z.string().nullable(),
  }),
  totals: z.object({
    clicks: nn, clicks_prev: nn, impressions: nn, impressions_prev: nn, position: nn, position_prev: nn,
    // pages Google showed in search (0072), null before pages are imported for the period
    pages: nn.optional(), pages_prev: nn.optional(),
  }).nullable(),
  keywords: z.array(z.object({
    id: uuid, query: z.string(), created_at: z.string(), mine: z.boolean().nullable(),
    impressions: nn, clicks: nn, position: nn, position_prev: nn,
    // the page Google showed most for it (0072)
    page: z.string().nullable().optional(),
  })),
  // Site health (0072): the last crawl and its open issues
  health: z.object({
    last_crawl_at: z.string().nullable(), last_error: z.string().nullable(), pages: nn, awaiting_check: n,
    issues: z.array(SeoIssue),
  }).nullable().optional(),
  // Content ideas (0072): searches the site is seen for outside the top ten, not tracked
  ideas: z.array(z.object({ query: z.string(), impressions: n, position: nn, days: n, page: z.string().nullable(), planned: z.boolean() })).nullable().optional(),
  // Technical SEO beyond the crawl (0073): searches split over two or more pages, and pages measured slow
  cannibal: z.array(z.object({ query: z.string(), pages: z.array(z.object({ page: z.string(), impressions: n })) })).nullable().optional(),
  slow: z.array(z.object({ path: z.string(), lcp_ms: nn, inp_ms: nn, field: z.boolean() })).nullable().optional(),
})
export type Seo = z.infer<typeof Seo>

// ---------------------------------------------------------------------------
// Marketing campaigns (ad_campaigns_get)
export const AD_CHANNELS = ['google_ads', 'linkedin', 'facebook', 'newsletter', 'webinar', 'other'] as const
export type AdChannel = (typeof AD_CHANNELS)[number]
export const AD_STATES = ['scheduled', 'live', 'paused', 'ended'] as const
export type AdState = (typeof AD_STATES)[number]
/** The status pill's tone (tone[]: Live, Scheduled, Paused, Ended). */
export const AD_TONE: Record<AdState, string> = {
  live: 'bg-ok-bg text-ok-ink', scheduled: 'bg-highlight text-amber-ink', paused: 'bg-tile text-muted', ended: 'bg-[rgba(25,21,16,.06)] text-muted',
}
/** The utm a channel's links carry and the spend channel (channel_rules' key) its spend is entered under: app.ad_utm. */
export const AD_UTM: Record<AdChannel, { source: string; medium: string; spend: (typeof CHANNELS)[number] | null }> = {
  google_ads: { source: 'google-ads', medium: 'cpc', spend: 'paid_search' },
  linkedin: { source: 'linkedin', medium: 'paid_social', spend: 'paid_social' },
  facebook: { source: 'facebook', medium: 'paid_social', spend: 'paid_social' },
  newsletter: { source: 'newsletter', medium: 'email', spend: 'email' },
  webinar: { source: 'webinar', medium: 'event', spend: null },
  other: { source: 'other', medium: 'referral', spend: null },
}

export const AdCampaign = z.object({
  id: uuid,
  name: z.string(),
  channel: z.enum(AD_CHANNELS),
  landing_path: z.string(),
  utm: z.object({ source: z.string(), medium: z.string(), campaign: z.string() }),
  budget: nn,
  currency: z.string(),
  starts_on: z.string().nullable(),
  ends_on: z.string().nullable(),
  state: z.enum(AD_STATES),
  version: n,
  created_at: z.string(),
  mine: z.boolean().nullable(),
  figures: z.object({
    spend: z.array(z.object({ month: z.string(), amount: n, currency: z.string() })),
    spent: nn,
    visits: nn,
    signups: n,
    paid: n,
  }).nullable(),
})
export type AdCampaign = z.infer<typeof AdCampaign>
export const AdCampaigns = z.object({ site: Site, tracked: z.boolean(), rows: z.array(AdCampaign) })
export type AdCampaigns = z.infer<typeof AdCampaigns>

/** app.slug: lower case, æ ø å spelled out, anything else a dash, at most 40 characters. */
export const slug = (s: string) =>
  s.toLowerCase().replace(/æ/g, 'ae').replace(/ø/g, 'o').replace(/å/g, 'a').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40).replace(/-+$/, '')

/** The tracking link: the application's site, the landing path and the three utm parameters (null without a site). */
export function trackingUrl(host: string | null | undefined, path: string, utm: { source: string; medium: string; campaign: string }): string | null {
  if (!host) return null
  const q = new URLSearchParams({ utm_source: utm.source, utm_medium: utm.medium, utm_campaign: utm.campaign })
  return `https://${host}${path.startsWith('/') ? path : `/${path}`}?${q.toString()}`
}

// ---------------------------------------------------------------------------
// Email and automation (simple_sequences_get, simple_sequence_save; 0059)
export const TRIGGERS = ['trial_started', 'trial_ending', 'list_added', 'account_cancels', 'deal_stage', 'form_submitted', 'send_now'] as const
export type TriggerKey = (typeof TRIGGERS)[number]
/** What the engine can start a campaign on (a record with a person to email); the others are offered disabled. */
export const TRIGGERS_AVAILABLE: readonly TriggerKey[] = ['deal_stage', 'form_submitted']
export const EXITS = ['reply_unsub', 'paying', 'never'] as const
export type ExitKey = (typeof EXITS)[number]
export const CONDITIONS = ['not_paying', 'employees_missing', 'on_list', 'opened_last'] as const
export type CondKey = (typeof CONDITIONS)[number]
/** Campaign opens are not a condition the engine has (wf_match tests sales mail only). */
export const CONDITIONS_AVAILABLE: readonly CondKey[] = ['not_paying', 'employees_missing', 'on_list']
/** The stage the design's «Deal moves to Proposal sent» names, looked up by name among the pipelines' stages. */
export const PROPOSAL_STAGE = 'proposal sent'

export const SimpleStep = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('email'), text: z.string(), campaign_id: uuid.nullish() }),
  z.object({ kind: z.literal('wait'), days: z.number().int() }),
  z.object({ kind: z.literal('cond'), cond: z.enum(CONDITIONS) }),
  z.object({ kind: z.literal('task'), text: z.string() }),
])
export type SimpleStep = z.infer<typeof SimpleStep>
export const SimpleModel = z.object({
  trigger: z.enum(TRIGGERS),
  stage_id: uuid.nullable().optional(),
  list: uuid.nullable().optional(),
  exit: z.enum(EXITS),
  steps: z.array(SimpleStep),
})
export type SimpleModel = z.infer<typeof SimpleModel>

const Stats = z.object({ sent: n, delivered: n, unique_opens: nn, unique_clicks: nn, open_rate: nn }).passthrough()
export const Sequence = z.object({
  id: uuid,
  name: z.string(),
  state: z.enum(['draft', 'active']),
  activated: z.boolean(),
  version: n,
  owner: z.string().nullable(),
  mine: z.boolean().nullable(),
  blockers: z.array(z.string()),
  simple: SimpleModel,
  enrolled: n,
  emails: z.array(z.object({ campaign_id: uuid, status: z.string(), stats: Stats.nullable() })),
})
export type Sequence = z.infer<typeof Sequence>

/** Draft that was once active reads «Paused» (the engine has draft and active only). */
export const seqState = (s: Pick<Sequence, 'state' | 'activated'>): 'active' | 'paused' | 'draft' =>
  s.state === 'active' ? 'active' : s.activated ? 'paused' : 'draft'

/** The blocker the Activate button explains, the provider first. */
const BLOCKER_ORDER = ['not_connected:email', 'sender_domain_unverified', 'campaign_inactive']
export const firstBlocker = (blockers: string[]) =>
  [...blockers].sort((a, b) => (BLOCKER_ORDER.indexOf(a) + 1 || 99) - (BLOCKER_ORDER.indexOf(b) + 1 || 99))[0] ?? null

/** Opens over delivered across a campaign's emails (null until something was delivered with tracking). */
export function openRate(emails: Sequence['emails']): number | null {
  let delivered = 0, opens = 0, tracked = false
  for (const e of emails) {
    if (!e.stats || e.stats.unique_opens === null) continue
    tracked = true
    delivered += e.stats.delivered
    opens += e.stats.unique_opens
  }
  return tracked && delivered > 0 ? (opens / delivered) * 100 : null
}

/** «Wait 2 days» read back as a number of days: the first whole number in the text (null when there is none). */
export function daysFrom(text: string): number | null {
  const m = /\d+/.exec(text)
  if (!m) return null
  const d = Number(m[0])
  return d >= 1 && d <= 365 ? d : null
}

/** Move a step up (−1) or down (+1); out of range leaves the list as it was. */
export function moveStep<T>(list: T[], i: number, by: -1 | 1): T[] {
  const j = i + by
  if (j < 0 || j >= list.length) return list
  const out = [...list]
  ;[out[i], out[j]] = [out[j]!, out[i]!]
  return out
}

/** An amount typed in the staff member's number format (group separators dropped, the decimal sign read): null when
 *  empty, NaN when it is not a number with at most two decimals (as analytics' Campaigns spend entry). */
export function parseAmount(s: string, nf: 'space_comma' | 'comma_dot' | 'dot_comma'): number | null {
  const [group, dec] = nf === 'comma_dot' ? [',', '.'] : nf === 'dot_comma' ? ['.', ','] : [' ', ',']
  const x = s.replace(/[\s  ]/g, '').split(group).join('').replace(dec, '.')
  return x === '' ? null : /^\d+(\.\d{0,2})?$/.test(x) ? Number(x) : NaN
}
