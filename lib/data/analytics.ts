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
  activated_after_result: z.object({ paying: n, tiltak_30d: n }).nullable(),
  churn: z.object({ logos: n, mrr_lost: n }).nullable(),
  // requested (requests/analytics.md R-1): rows in another currency left out of the sums
  excluded_currency: n.optional(),
})
export type Business = z.infer<typeof Business>

export const Activation = z.object({
  cohort: month,
  cohorts: z.array(month).nullable(),
  target_min: nn,
  steps: z.array(z.object({ key: z.string(), count: n, median_min: nn })),
})
export type Activation = z.infer<typeof Activation>

export const Retention = z.object({
  mode: z.enum(['logos', 'revenue']),
  cohorts: z.array(z.object({ cohort: month, size: n, cells: z.array(nn).nullable() })),
  churn_by_month: z.array(z.object({ month, logos: n })),
  reasons: z.array(z.object({ code: z.string(), count: n })),
})
export type Retention = z.infer<typeof Retention>

export const Usage = z.object({
  rounds: z.object({ main: n, pulse: n }),
  response_rate: z.object({ main: nn, pulse: nn, all: nn.optional() }).nullable(),
  reminder_gain: nn,
  rounds_by_month: z.array(z.object({ month, main: n, pulse: n })),
  logins: z.record(z.string(), n),
  counts: z.record(z.string(), n),
  // requested (R-5): the counts per application, for «Usage across applications» under All applications
  counts_by_product: z.record(z.string(), z.record(z.string(), n)).optional(),
})
export type Usage = z.infer<typeof Usage>

export const Web = z.object({
  sites: z.array(z.object({ id: z.string().uuid(), hostname: z.string() })),
  search_console: z.string().nullable(),
  visitors: n,
  sessions: n,
  pageviews: n,
  bounces: n,
  signups: n,
  daily: z.array(z.object({ day: z.string(), visitors: n, sessions: n })),
  channels: z.array(z.object({ channel: z.string(), sessions: n })),
  landing: z.array(z.object({ path: z.string().nullable(), sessions: n, bounce: nn })),
  events: z.array(z.object({ name: z.string(), value: z.string().nullable(), count: n })),
  companies: n,
  search: z.array(z.object({ query: z.string(), impressions: n, clicks: n })),
})
export type Web = z.infer<typeof Web>

export const Spend = z.object({ campaign: z.string(), month, channel: z.string().nullable(), amount: n })
export type Spend = z.infer<typeof Spend>

export const Attribution = z.object({
  touch: z.enum(['first', 'last']),
  has_last_touch: z.boolean(),
  channels: z.array(z.object({ channel: z.string(), signups: n, activated: n, paid: n, mrr: n, spend: nn })),
  spend: z.array(Spend),
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
export const loadAttribution = (touch: 'first' | 'last', range: RangeKey) =>
  rpc('analytics_attribution', { p_touch: touch, p_days: RANGE_DAYS[range] }, Attribution)
export const loadHealth = (product: string) => rpc('analytics_health', { p_product: scope(product) }, Health)
export const loadMetricDefs = () => rpc('analytics_metric_definitions', {}, z.array(MetricDef))
