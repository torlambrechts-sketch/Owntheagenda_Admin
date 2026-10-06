/**
 * The Analytics screen's arithmetic on what the database returns (0025). Pure functions, shared by the
 * server page and its client parts, and tested in tests/analytics-calc.test.ts. Nothing here invents a
 * value: where an input is missing the result is null and the screen renders «—» or its empty state.
 */

export const RANGES = ['30d', '90d', '12m'] as const
export type RangeKey = (typeof RANGES)[number]
export const RANGE_DAYS: Record<RangeKey, 30 | 90 | 365> = { '30d': 30, '90d': 90, '12m': 365 }
/** Calendar months a range covers when a figure is kept per month (movements): this month, three, twelve. */
export const RANGE_MONTHS: Record<RangeKey, number> = { '30d': 1, '90d': 3, '12m': 12 }

/** The five signals of the health model, in the design's order (health_model_save accepts these keys). */
export const SIGNALS = ['admin_login', 'survey_cadence', 'response_trend', 'tiltak_activity', 'payment'] as const

/** The channel keys of channel_rules (0025); spend is entered against one of them. */
export const CHANNELS = ['paid_search', 'paid_social', 'email', 'organic_search', 'social', 'partner', 'direct'] as const

export const TABS = ['business', 'activation', 'retention', 'usage', 'web', 'attribution', 'health', 'defs'] as const
export type Tab = (typeof TABS)[number]
/** Tabs whose reads take the range; the others have their own period (a cohort, the latest scores). */
export const RANGED_TABS: readonly Tab[] = ['business', 'usage', 'web', 'attribution']

const ym = (d: Date) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`

/** «2026-10» plus k months (k may be negative). */
export function addMonths(month: string, k: number): string {
  const [y, m] = month.split('-').map(Number) as [number, number]
  return ym(new Date(Date.UTC(y, m - 1 + k, 1)))
}

/** The `count` months ending with the month of `now`, oldest first. */
export function monthsEnding(now: Date, count: number): string[] {
  const last = ym(now)
  return Array.from({ length: count }, (_, i) => addMonths(last, i - count + 1))
}

/** The signup cohorts analytics_business counts for trial conversion: month(now − (d + 45) days) … month(now − 45 days). */
export function trialCohortSpan(now: Date, days: number): [string, string] {
  const back = (d: number) => ym(new Date(now.getTime() - d * 86_400_000))
  return [back(days + 45), back(45)]
}

export type Movement = { month: string; new: number; expansion: number; contraction: number; churn: number; net: number }

/** The movements of the calendar months the range covers, summed (contraction and churn are negative). */
export function movementsInRange(movements: Movement[], now: Date, range: RangeKey) {
  const months = new Set(monthsEnding(now, RANGE_MONTHS[range]))
  const sum = { new: 0, expansion: 0, contraction: 0, churn: 0, net: 0, months: 0 }
  for (const m of movements) {
    if (!months.has(m.month)) continue
    sum.new += m.new; sum.expansion += m.expansion; sum.contraction += m.contraction; sum.churn += m.churn; sum.net += m.net
    sum.months += 1
  }
  return sum
}

/** The first month the nightly tenant snapshot holds: movements start there (the first snapshot is the baseline). */
export const firstSnapshotMonth = (movements: Movement[]): string | null =>
  movements.reduce<string | null>((a, m) => (a === null || m.month < a ? m.month : a), null)

/** Percent change, or null without a base. */
export const pctChange = (now: number | null, prev: number | null): number | null =>
  now === null || prev === null || prev === 0 ? null : (now / prev - 1) * 100

/** a ÷ b as a percent, or null when b is zero or missing. */
export const share = (a: number | null | undefined, b: number | null | undefined): number | null =>
  a === null || a === undefined || !b ? null : (a / b) * 100

/**
 * The first question's answer follows the figures: «yes» when at least a quarter of trials convert and half
 * of the paying customers act on their first result within 30 days, «partly» when one of the two holds,
 * «not yet» when neither does, and no verdict when either figure is missing.
 */
export function verdict(conversion: number | null, tiltak: number | null): 'yes' | 'partly' | 'no' | null {
  if (conversion === null || tiltak === null) return null
  const hits = Number(conversion >= 25) + Number(tiltak >= 50)
  return hits === 2 ? 'yes' : hits === 1 ? 'partly' : 'no'
}

/** A median duration in minutes as the design writes it: «6 min», «4 h», «2 days». */
export function duration(min: number): { unit: 'min' | 'h' | 'days'; n: number } {
  const m = Math.max(0, Math.round(min))
  if (m < 60) return { unit: 'min', n: m }
  if (m < 1440) return { unit: 'h', n: Math.round(m / 60) }
  return { unit: 'days', n: Math.round(m / 1440) }
}

export type Step = { key: string; count: number; median_min: number | null }

/** The step with the largest share lost from the step before it (index of the later step), or null. */
export function biggestDrop(steps: Step[]): { index: number; drop: number } | null {
  let best: { index: number; drop: number } | null = null
  for (let i = 1; i < steps.length; i++) {
    const prev = steps[i - 1]!.count
    if (prev <= 0) continue
    const drop = 1 - steps[i]!.count / prev
    if (drop > 0 && (best === null || drop > best.drop)) best = { index: i, drop }
  }
  return best
}

/** The model's weights as shares of their sum, in the order given (the score scales the weights it uses). */
export function weightShares(weights: Record<string, number>, order: readonly string[]): { key: string; weight: number; pct: number }[] {
  const keys = order.filter((k) => k in weights)
  const sum = keys.reduce((a, k) => a + (weights[k] ?? 0), 0)
  return keys.map((k) => ({ key: k, weight: weights[k] ?? 0, pct: sum ? ((weights[k] ?? 0) / sum) * 100 : 0 }))
}

/**
 * Revenue churn per month: MRR lost to churn and contraction ÷ the MRR at the end of the month before
 * (v_revenue_churn over v_mrr_monthly). Null when the month before has no MRR on record.
 */
export function revenueChurnByMonth(movements: Movement[], mrrByMonth: Map<string, number>, months: string[]): Map<string, number | null> {
  const lost = new Map(movements.map((m) => [m.month, -(m.churn + m.contraction)]))
  const from = firstSnapshotMonth(movements)
  return new Map(months.map((m) => {
    const base = mrrByMonth.get(addMonths(m, -1))
    // a month after the first snapshot without a movement lost nothing; before it, nothing is known
    const l = lost.get(m) ?? (from !== null && m >= from ? 0 : undefined)
    return [m, l === undefined || !base ? null : (l / base) * 100]
  }))
}

/** Whole days from now until an instant (never negative). */
export const daysUntil = (iso: string, now: Date) => Math.max(0, Math.ceil((new Date(iso).getTime() - now.getTime()) / 86_400_000))
