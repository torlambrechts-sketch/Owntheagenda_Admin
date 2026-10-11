import { z } from 'zod'

/**
 * Growth › Marketing campaigns and Email and automation, the playbook (GrowthPlaybook.dc.html of 11 Oct 2026; 0076): the
 * shapes its reads return and the rules the views apply to them. Pure and tested (tests/growth-playbook.test.ts). A
 * figure that needs an input Sentral lacks is null and shown as «—».
 */
const n = z.number()
const nn = z.number().nullable()
const s = z.string()
const sn = z.string().nullable()
const uuid = z.string().uuid()

export const CAMP_VIEWS = ['base', 'outcomes', 'budget', 'experiments', 'audiences', 'creative', 'calendar'] as const
export type CampView = (typeof CAMP_VIEWS)[number]
export const EMAIL_VIEWS = ['base', 'trial', 'library', 'deliver'] as const
export type EmailView = (typeof EMAIL_VIEWS)[number]
export const BUDGET_CHANNELS = ['paid_search', 'paid_social', 'email', 'social', 'partner', 'organic_search'] as const
export type BudgetChannel = (typeof BUDGET_CHANNELS)[number]
export const AREAS = ['signup', 'landing_page', 'pricing', 'email', 'ads', 'content', 'referral', 'other'] as const
export type Area = (typeof AREAS)[number]
export const EXP_STAGES = ['backlog', 'ready', 'running', 'done'] as const
export type ExpStage = (typeof EXP_STAGES)[number]
export const OUTCOMES = ['win', 'no_effect', 'loss'] as const

// ---------------------------------------------------------------------------
// Shapes

export const Outcomes = z.object({
  model: z.enum(['first', 'last']),
  days: n,
  attributed: z.boolean(),
  arpa: nn,
  tracked_since: sn,
  channels: z.array(z.object({ channel: s, spend: nn, signups: nn, accounts: nn, paying: nn, mrr: nn })),
  journeys: z.array(z.object({ first: s, last: s, paying: n, days: nn })).nullable(),
})
export type Outcomes = z.infer<typeof Outcomes>

export const Budget = z.object({
  month: s, day: n, days: n, attributed: z.boolean(), arpa: nn,
  last_move: z.object({ from: s, to: s, amount: n, at: s }).nullable(),
  rows: z.array(z.object({ channel: z.enum(BUDGET_CHANNELS), budget: nn, spent: n, spend90: nn, paying90: nn })),
})
export type Budget = z.infer<typeof Budget>

export const Experiments = z.object({
  running: n, called_30: n,
  items: z.array(z.object({
    id: uuid, hypothesis: s, area: z.enum(AREAS), impact: n, confidence: n, ease: n, stage: z.enum(EXP_STAGES),
    outcome: z.enum(OUTCOMES).nullable(), note: sn, owner: sn, started_at: sn, ended_at: sn, created_at: s,
  })),
})
export type Experiments = z.infer<typeof Experiments>

export const Calendar = z.object({
  year: n, today: s,
  ads: z.array(z.object({ id: uuid, name: s, channel: s, from: s, to: s, state: s })),
  emails: z.array(z.object({ id: uuid, name: s, status: s, on: s })),
  blackouts: z.array(z.object({ id: uuid, name: s, from: s, to: s })),
})
export type Calendar = z.infer<typeof Calendar>

const Step = z.object({ kind: s, email: sn, amount: nn, unit: sn })
export const Trial = z.object({
  trials: z.object({ ended: n, converted: n, ended_prev: n, converted_prev: n }),
  first_survey: z.object({ days: nn, days_prev: nn, accounts: n }),
  abandoned: z.object({ n: n, n_prev: n }),
  tracked_since: sn,
  flows: z.array(z.object({
    id: uuid, name: s, kind: s, state: s, activated: z.boolean(), trigger: s, trigger_data: z.record(z.string(), z.unknown()).nullable(),
    steps: z.array(Step), in_flow: n, completed_90: n,
  })),
})
export type Trial = z.infer<typeof Trial>

export const Flows = z.array(z.object({
  id: uuid, name: s, description: sn, kind: s, state: s, activated: z.boolean(), trigger_type: s, trigger: sn, simple: z.boolean(),
  steps: n, blockers: z.array(s), in_flow: n,
  mail: z.object({ sent: n, opened: n, clicked: n, unsubscribed: n }),
}))
export type Flows = z.infer<typeof Flows>

export const Deliverability = z.object({
  sends: z.object({ sent: n, delivered: n, bounced: n, hard: n, complained: n, unsubscribed: n }),
  suppressions: z.record(z.string(), n),
  signals: z.object({ engaged: n, replied: n, unsubscribed: n, hard_bounce: n, complaint: n }),
})
export type Deliverability = z.infer<typeof Deliverability>

// ---------------------------------------------------------------------------
// Rules

const per = (a: number | null | undefined, b: number | null | undefined) => (a && b ? a / b : null)

/** a channel's costs: per signup, per account, per paying customer (CAC), and the months a customer takes to pay it back */
export function outcomeRow(r: Outcomes['channels'][number], arpa: number | null) {
  const cac = per(r.spend, r.paying)
  return { cps: per(r.spend, r.signups), cpa: per(r.spend, r.accounts), cac, payback: per(cac, arpa) }
}

export type Pace = { state: 'none' | 'on' | 'ahead' | 'under'; share: number; runsOut: number | null }
/** this month's spend against its budget, measured against the share of the month gone (the design's ±15 % / −20 %) */
export function pace(budget: number | null, spent: number, day: number, days: number): Pace {
  if (!budget) return { state: 'none', share: 0, runsOut: null }
  const share = spent / budget
  const ratio = share / (day / days)
  if (spent > 0 && ratio > 1.15) return { state: 'ahead', share, runsOut: Math.min(days, Math.max(day, Math.floor(budget / (spent / day)))) }
  return { state: ratio < 0.8 ? 'under' : 'on', share, runsOut: null }
}

/** the cost of one paying customer a channel showed over 90 days; null without spend or paying customers */
export const observedCac = (r: { spend90: number | null; paying90: number | null }) => per(r.spend90, r.paying90)

export type Move = { from: BudgetChannel; to: BudgetChannel; amount: number; gain: number; fromCac: number; toCac: number }
/**
 * The suggested move: when the dearest channel's observed cost per paying customer is at least half again the cheapest's,
 * move 30 % of the dearest's budget (in whole hundreds) to the cheapest; the gain is what the two costs say it buys.
 */
export function suggestedMove(rows: Budget['rows']): Move | null {
  const priced = rows.map((r) => ({ r, cac: observedCac(r) })).filter((x): x is { r: Budget['rows'][number]; cac: number } => x.cac !== null && !!x.r.budget)
  if (priced.length < 2) return null
  const sorted = [...priced].sort((a, b) => a.cac - b.cac)
  const best = sorted[0]!
  const worst = sorted[sorted.length - 1]!
  if (worst.cac < best.cac * 1.5) return null
  const amount = Math.floor((worst.r.budget! * 0.3) / 100) * 100
  if (amount <= 0) return null
  return { from: worst.r.channel, to: best.r.channel, amount, gain: Math.round((amount / best.cac - amount / worst.cac) * 10) / 10, fromCac: worst.cac, toCac: best.cac }
}

/** «If we add N kr to the best channels»: at the cheapest observed cost per paying customer, and MRR at today's ARPA */
export function scenario(extra: number, rows: Budget['rows'], arpa: number | null): { paying: number; mrr: number | null } | null {
  const cacs = rows.map(observedCac).filter((x): x is number => x !== null)
  if (!cacs.length || extra <= 0) return null
  const paying = Math.round((extra / Math.min(...cacs)) * 10) / 10
  return { paying, mrr: arpa !== null ? Math.round(paying * arpa) : null }
}

/** ICE: the mean of impact, confidence and ease, to one decimal */
export const ice = (e: { impact: number; confidence: number; ease: number }) => Math.round(((e.impact + e.confidence + e.ease) / 3) * 10) / 10

/** where a period sits on a year line, in per cent: its start and its width (at least a day) */
export function yearSpan(from: string, to: string, year: number): { x: number; w: number } | null {
  const y0 = Date.UTC(year, 0, 1)
  const y1 = Date.UTC(year + 1, 0, 1)
  const a = Math.max(y0, Date.parse(`${from.slice(0, 10)}T00:00:00Z`))
  const b = Math.min(y1, Date.parse(`${to.slice(0, 10)}T00:00:00Z`) + 86_400_000)
  if (b <= a) return null
  return { x: ((a - y0) / (y1 - y0)) * 100, w: ((b - a) / (y1 - y0)) * 100 }
}
