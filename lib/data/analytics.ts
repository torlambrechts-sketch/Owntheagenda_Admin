import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import type { RangeKey } from './analytics-calc'
import { RANGE_DAYS } from './analytics-calc'

/**
 * What the Analytics screen reads (0025_analytics.sql). Every analytics read takes the period the range
 * selector names (30 / 90 / 365 days) and the product the shell's switcher names; every result is parsed.
 * A value the database does not hold stays null and the screen renders «—» or its empty treatment.
 */
const n = z.number()
const nn = z.number().nullable()
const month = z.string().regex(/^\d{4}-\d{2}$/)

const KeyCount = z.object({ key: z.string(), count: n })

export const Business = z.object({
  mrr: nn,
  mrr_prev: nn,
  paying_accounts: n,
  customers: n,
  trials: n,
  trials_ending_7: n,
  trial_conversion: z.object({ trials: nn, converted: nn }).nullable(),
  movements: z.array(z.object({ month, new: n, expansion: n, contraction: n, churn: n, net: n })),
  mrr_by_product: z.array(z.object({ month, product: z.string(), mrr: nn })),
  trials_by_source: z.array(z.object({ channel: z.string(), trials: n, converted: n })),
  bands: z.array(z.object({ band: z.string(), accounts: n, mrr: nn })),
  by_industry: z.array(KeyCount),
  by_fylke: z.array(KeyCount),
  // customers by the price list's employee bands; '' = employees unknown or outside every band (0034)
  by_size: z.array(KeyCount).optional(),
  activated_after_result: z.object({ paying: n, tiltak_30d: n }).nullable(),
  // paying_start: paying subscriptions on the day mrr_prev is read (0034)
  churn: z.object({ logos: n, mrr_lost: n, paying_start: nn.optional() }).nullable(),
  // paying subscriptions in another currency than NOK, left out of the sums (0034)
  excluded_currency: n.optional(),
  // the earliest nightly tenant snapshot in scope; movements are measured from it (0033/0034)
  first_snapshot: z.string().nullable().optional(),
})
export type Business = z.infer<typeof Business>

export const Activation = z.object({
  cohort: month,
  cohorts: z.array(month).nullable(),
  target_min: nn,
  // medians from account created (0034)
  first_send_median_min: nn.optional(),
  paid_median_min: nn.optional(),
  steps: z.array(z.object({ key: z.string(), count: n, median_min: nn })),
})
export type Activation = z.infer<typeof Activation>

export const Retention = z.object({
  mode: z.enum(['logos', 'revenue']),
  cohorts: z.array(z.object({ cohort: month, size: n, cells: z.array(nn).nullable() })),
  churn_by_month: z.array(z.object({ month, logos: n, mrr_lost: nn.optional(), paying_start: nn.optional() })),
  reasons: z.array(z.object({ code: z.string(), count: n })),
  first_snapshot: z.string().nullable().optional(),
})
export type Retention = z.infer<typeof Retention>

export const Churns = z.object({
  churns: z.array(z.object({
    product: z.string(), tenant_id: z.string(), organization_id: z.string().uuid().nullable(), organization: z.string().nullable(),
    // passed back to analytics_set_churn_reason exactly as read
    churned_at: z.string(), mrr_lost: n, currency: z.string().nullable(), payment_failure: z.boolean(), reason: z.string().nullable(),
  })),
  reasons: z.array(z.string()),
})
export type Churns = z.infer<typeof Churns>

export const Usage = z.object({
  rounds: z.object({ main: n, pulse: n }),
  response_rate: z.object({ main: nn, pulse: nn, all: nn.optional() }).nullable(),
  reminder_gain: nn,
  rounds_by_month: z.array(z.object({ month, main: n, pulse: n })),
  logins: z.record(z.string(), n),
  counts: z.record(z.string(), n),
  // change of each count over the range; null while a tenant has no count from the range's start (0034)
  counts_delta: z.record(z.string(), nn).optional(),
  // requested (R-5): the counts per application, for «Usage across applications» under All applications
  counts_by_product: z.record(z.string(), z.record(z.string(), n)).optional(),
})
export type Usage = z.infer<typeof Usage>

// the session counts a row carries (0068): visits, one-page visits in percent, the signup form opened, the
// organisation number sent and the site's own «done»
const Funnelled = { sessions: n, bounce: nn, started: n, completed: n }
export const WebStep = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('view'), path: z.string(), seconds: n }),
  z.object({ kind: z.literal('event'), name: z.string(), value: z.string().nullable(), seconds: n }),
])
export const WebAttempt = z.object({
  at: z.string(), channel: z.string(), source: z.string().nullable(), device: z.string(), entry: z.string().nullable(),
  seconds: nn, outcome: z.enum(['opened', 'started', 'completed']), steps: z.array(WebStep),
})
export type WebAttempt = z.infer<typeof WebAttempt>
export const Web = z.object({
  sites: z.array(z.object({ id: z.string().uuid(), hostname: z.string() })),
  search_console: z.string().nullable(),
  visitors: n,
  sessions: n,
  pageviews: n,
  bounces: n,
  signups: n,
  // the previous period (null before the tracker ran then) and the average length of a visit with a second hit (0068)
  visitors_prev: nn.optional(),
  sessions_prev: nn.optional(),
  avg_seconds: nn.optional(),
  daily: z.array(z.object({ day: z.string(), visitors: n, sessions: n, pageviews: n.optional(), signups: n.optional() })),
  channels: z.array(z.object({ channel: z.string(), sessions: n, bounce: nn.optional(), signups: n.optional(), started: n.optional(), completed: n.optional() })),
  // per utm_campaign; sessions null while nothing was tracked in the period (0034)
  campaigns: z.array(z.object({ campaign: z.string(), sessions: nn, signups: n, paid: n })).optional(),
  landing: z.array(z.object({ path: z.string().nullable(), sessions: n, bounce: nn, pages: nn.optional(), opened: n.optional(), started: n.optional(), completed: n.optional() })),
  events: z.array(z.object({ name: z.string(), value: z.string().nullable(), count: n })),
  companies: n,
  search: z.array(z.object({ query: z.string(), impressions: n, clicks: n, position: nn.optional(), ctr: nn.optional() })),
  // 0068
  sources: z.array(z.object({ source: z.string().nullable(), medium: z.string().nullable(), campaign: z.string().nullable(), channel: z.string(), ...Funnelled })).default([]),
  top_pages: z.array(z.object({ path: z.string(), views: n, sessions: n })).default([]),
  exits: z.array(z.object({ path: z.string(), exits: n, sessions: n, rate: n })).default([]),
  devices: z.array(z.object({ device: z.string(), opened: n, ...Funnelled })).default([]),
  paid_terms: z.array(z.object({ term: z.string(), ...Funnelled })).default([]),
  signup: z.object({
    cta: n, opened: n, started: n, completed: n,
    ctas: z.array(z.object({ value: z.string(), sessions: n })),
    steps: z.array(z.object({ value: z.string(), sessions: n })),
    errors: z.array(z.object({ value: z.string(), count: n, sessions: n })),
  }).nullable().default(null),
  attempts: z.array(WebAttempt).default([]),
})
export type Web = z.infer<typeof Web>

export const Spend = z.object({ campaign: z.string(), month, channel: z.string().nullable(), amount: n, currency: z.string().optional() })
export type Spend = z.infer<typeof Spend>

export const Attribution = z.object({
  touch: z.enum(['first', 'last']),
  has_last_touch: z.boolean(),
  channels: z.array(z.object({ channel: z.string(), signups: n, activated: n, paid: n, mrr: n, spend: nn })),
  spend: z.array(Spend),
  excluded_currency: n.optional(),
})
export type Attribution = z.infer<typeof Attribution>

export const Factor = z.object({ signal: z.string(), weight: n, value: n, loss: n })
export const Health = z.object({
  model: z.object({ id: z.string().uuid(), version: n, weights: z.record(z.string(), n) }).nullable(),
  distribution: z.array(z.object({ bucket: n, count: n })),
  scored: n,
  renewal_window: n,
  at_risk: z.array(
    z.object({
      organization_id: z.string().uuid(), name: z.string(), product: z.string(), score: n,
      factors: z.array(Factor).nullable(), renews_at: z.string().nullable(),
    }),
  ),
})
export type Health = z.infer<typeof Health>

export const MetricDef = z.object({ key: z.string(), view: z.string(), migration: z.string(), version: n })
export type MetricDef = z.infer<typeof MetricDef>

const scope = (product: string) => (product === 'all' ? null : product)

export const loadBusiness = (product: string, range: RangeKey) =>
  rpc('analytics_business', { p_product: scope(product), p_days: RANGE_DAYS[range] }, Business)
export const loadActivation = (product: string, cohort: string | null) =>
  rpc('analytics_activation', { p_product: scope(product), p_cohort: cohort ? `${cohort}-01` : null }, Activation)
export const loadRetention = (product: string, mode: 'logos' | 'revenue') =>
  rpc('analytics_retention', { p_product: scope(product), p_mode: mode }, Retention)
export const loadUsage = (product: string, range: RangeKey) =>
  rpc('analytics_usage', { p_product: scope(product), p_days: RANGE_DAYS[range] }, Usage)
export const loadWeb = (range: RangeKey) => rpc('analytics_web', { p_site: null, p_days: RANGE_DAYS[range] }, Web)
/** One site's web figures over 7, 30, 90 or 365 days: Growth › Analytics, scoped to the application's site (0069). */
export const loadWebSite = (site: string, days: 7 | 30 | 90 | 365) => rpc('analytics_web', { p_site: site, p_days: days }, Web)
export const loadAttribution = (touch: 'first' | 'last', range: RangeKey) =>
  rpc('analytics_attribution', { p_touch: touch, p_days: RANGE_DAYS[range] }, Attribution)
export const loadChurns = (product: string, range: RangeKey) =>
  rpc('analytics_churns', { p_product: scope(product), p_days: RANGE_DAYS[range] }, Churns)
export const loadHealth = (product: string) => rpc('analytics_health', { p_product: scope(product) }, Health)
export const loadMetricDefs = () => rpc('analytics_metric_definitions', {}, z.array(MetricDef))
