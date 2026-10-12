import { z } from 'zod'
import { AD_PROVIDERS, type AdProvider } from './ads'

/**
 * Growth v3 (GrowthMarketing.dc.html of 12 Oct 2026; 0083): what ad_campaign_detail, simple_sequence_results and
 * email_send_times return, and the stated rules the campaign card and Email and automation apply to them — the day bars,
 * the tips and the heatmap. Pure and tested (tests/v3-growth.test.ts). Nothing here invents a figure: a value the answer
 * does not hold stays null and is drawn as «—» or the design's empty treatment. The thresholds are logged as deviations
 * (docs/crm-enrichment/deviations/v3-growth.md).
 */
const n = z.number()
const nn = z.number().nullable()
const s = z.string()
const sn = z.string().nullable()
const uuid = z.string().uuid()
const status = z.enum(['live', 'paused', 'ended'])
const provider = z.enum(AD_PROVIDERS)

// ---------------------------------------------------------------------------
// the campaign card (ad_campaign_detail)
const RowBase = {
  id: s, provider, account: s, campaign: s, name: s, status, currency: sn,
  clicks: n, spend: n, conversions: nn,
  /** null when the campaign's links do not carry utm_content (ads) or utm_term (keywords) */
  signups: nn,
}
export const CampaignDetail = z.object({
  id: uuid,
  from: s,
  to: s,
  days_n: n,
  starts_on: sn,
  ends_on: sn,
  tracked: z.boolean(),
  spend_source: z.enum(['platform', 'typed']).nullable(),
  currency: sn,
  time_zones: z.array(s),
  utm_content: z.boolean(),
  utm_term: z.boolean(),
  platforms: z.array(z.object({ provider, account: s, campaign: s, name: s, status, bidding: sn })),
  days: z.array(z.object({ day: s, spend: nn, signups: n })),
  ads: z.array(z.object(RowBase)),
  keywords: z.array(z.object({ ...RowBase, ad_group: s, match_type: z.enum(['exact', 'phrase', 'broad']).nullable() })),
})
export type CampaignDetail = z.infer<typeof CampaignDetail>
export type AdRow = CampaignDetail['ads'][number] & { kind: 'ad' | 'keyword' }

/** The design's red cost per signup: more than 900 kr (kroner only). */
export const CPS_RED = 900
/** A tip looks at a row only after this many clicks in the window. */
export const TIP_MIN_CLICKS = 50
/** «Costs N× more per signup than the rest»: a row at least this many times the others' cost per signup. */
export const TIP_DEAR_RATIO = 3
/** «Converts best»: a keyword with at least this many signups, at most this share of the others' cost per signup. */
export const TIP_BEST_MIN_SIGNUPS = 3
export const TIP_BEST_SHARE = 0.5
/** Keyword bids are the advertiser's only under manual bidding; under smart bidding Google sets them. */
export const MANUAL_BIDDING = ['manual_cpc', 'enhanced_cpc']

export type Bar = {
  day: string
  /** an empty slot: before the campaign started, or a platform day with no row and no signups */
  empty: boolean
  /** the outer bar's height, % of the chart; null in signups-only mode (no spend bar is drawn) */
  h: number | null
  /** the signups bar's height: % of the outer bar (platform mode, as drawn), or % of the chart (signups only) */
  sh: number
  spend: number | null
  signups: number
}

/** How the bars are drawn: spend per day from the ad platform, or the signups alone (typed or no spend, or mixed currencies). */
export const barMode = (d: Pick<CampaignDetail, 'spend_source' | 'currency'>): 'platform' | 'signups' =>
  d.spend_source === 'platform' && d.currency ? 'platform' : 'signups'

/**
 * The 21 bars (the design: height = spend ÷ max × 96 % + 2 %, the signups bar inside it as a share of the day's most). A
 * day before the campaign's start is an empty slot; in platform mode so is a day the platform has no row for (and no
 * signups). Without platform days no spend bar is drawn (spend is typed per month and never spread over days): the signups
 * bars stand alone, and with no signups either every day is the design's 2 % stub.
 */
export function dailyBars(d: Pick<CampaignDetail, 'days' | 'starts_on' | 'spend_source' | 'currency'>): Bar[] {
  const mode = barMode(d)
  const started = (day: string) => !d.starts_on || day >= d.starts_on
  const maxSpend = Math.max(0, ...d.days.filter((x) => started(x.day)).map((x) => x.spend ?? 0))
  const maxSg = Math.max(1, ...d.days.filter((x) => started(x.day)).map((x) => x.signups))
  const anySg = d.days.some((x) => started(x.day) && x.signups > 0)
  return d.days.map((x) => {
    const spend = mode === 'platform' ? x.spend : null
    if (!started(x.day)) return { day: x.day, empty: true, h: null, sh: 0, spend: null, signups: x.signups }
    if (mode === 'platform') {
      if (x.spend === null && x.signups === 0) return { day: x.day, empty: true, h: null, sh: 0, spend: null, signups: 0 }
      return { day: x.day, empty: false, h: (maxSpend > 0 ? (x.spend ?? 0) / maxSpend : 0) * 96 + 2, sh: (x.signups / maxSg) * 100, spend, signups: x.signups }
    }
    // signups only: the bar is the signups bar; nothing at all is the design's stub
    return anySg
      ? { day: x.day, empty: false, h: null, sh: (x.signups / maxSg) * 100, spend: null, signups: x.signups }
      : { day: x.day, empty: false, h: 2, sh: 0, spend: null, signups: 0 }
  })
}

/** A row's own cost per signup: its spend over its signups; null without signups, without spend or without tracking. */
export const rowCps = (r: Pick<AdRow, 'spend' | 'signups'>): number | null =>
  r.signups !== null && r.signups > 0 && r.spend > 0 ? r.spend / r.signups : null

/** The ads and keywords block: keywords first (Google), then ads, each by clicks; at most `limit` of each. */
export function adRows(d: Pick<CampaignDetail, 'ads' | 'keywords'>, limit = 6): AdRow[] {
  return [
    ...d.keywords.slice(0, limit).map((k) => ({ ...k, kind: 'keyword' as const })),
    ...d.ads.slice(0, limit).map((a) => ({ ...a, kind: 'ad' as const })),
  ]
}

/** Where a tip's button goes: the place in the platform where the person makes the change (X-V3-3: Sentral writes nothing). */
export function platformUrl(p: AdProvider, account: string, campaign: string, level: 'ad' | 'keyword'): string {
  const a = encodeURIComponent(account)
  const c = encodeURIComponent(campaign)
  if (p === 'google_ads') return `https://ads.google.com/aw/${level === 'keyword' ? 'keywords' : 'ads'}?campaignId=${c}&__e=${a}`
  if (p === 'linkedin_ads') return `https://www.linkedin.com/campaignmanager/accounts/${a}/campaigns/${c}/creatives`
  return `https://adsmanager.facebook.com/adsmanager/manage/ads?act=${a}&selected_campaign_ids=${c}`
}

export type CampaignTip =
  | { key: string; kind: 'dear'; level: 'ad' | 'keyword'; name: string; provider: AdProvider; clicks: number; cps: number | null; restCps: number; ratio: number | null; url: string }
  | { key: string; kind: 'best'; level: 'keyword'; name: string; provider: AdProvider; cps: number; restCps: number; url: string }

/** the others' cost per signup: their spend over their signups (null when they have none) */
function restCps(rows: AdRow[], me: AdRow): number | null {
  let spend = 0
  let sg = 0
  for (const r of rows) {
    if (r === me || r.signups === null) continue
    spend += r.spend
    sg += r.signups
  }
  return sg > 0 && spend > 0 ? spend / sg : null
}

/** the dearest row of one kind: no signups after it already spent more than a signup costs elsewhere, or ≥ 3× the others */
function dearest(rows: AdRow[]): CampaignTip | null {
  let pick: { r: AdRow; rest: number; ratio: number | null; score: number } | null = null
  for (const r of rows) {
    if (r.signups === null || r.clicks < TIP_MIN_CLICKS || r.spend <= 0) continue
    const rest = restCps(rows, r)
    if (rest === null) continue
    const cps = rowCps(r)
    let ratio: number | null
    let score: number
    if (cps === null) {
      if (r.spend < rest) continue
      ratio = null
      score = Number.POSITIVE_INFINITY
    } else {
      ratio = cps / rest
      if (ratio < TIP_DEAR_RATIO) continue
      score = ratio
    }
    if (!pick || score > pick.score || (score === pick.score && r.spend > pick.r.spend)) pick = { r, rest, ratio, score }
  }
  if (!pick) return null
  const { r } = pick
  return { key: `dear:${r.kind}:${r.provider}:${r.campaign}:${r.id}`, kind: 'dear', level: r.kind, name: r.name, provider: r.provider, clicks: r.clicks,
    cps: rowCps(r), restCps: pick.rest, ratio: pick.ratio, url: platformUrl(r.provider, r.account, r.campaign, r.kind) }
}

/** the keyword that converts best, where its bid is the advertiser's to raise */
function bestKeyword(rows: AdRow[], bidding: Map<string, string | null>): CampaignTip | null {
  let pick: { r: AdRow; cps: number; rest: number } | null = null
  for (const r of rows) {
    if (r.signups === null || r.signups < TIP_BEST_MIN_SIGNUPS || !MANUAL_BIDDING.includes(bidding.get(`${r.account}:${r.campaign}`) ?? '')) continue
    const cps = rowCps(r)
    const rest = restCps(rows, r)
    if (cps === null || rest === null || cps > rest * TIP_BEST_SHARE) continue
    if (!pick || cps < pick.cps) pick = { r, cps, rest }
  }
  if (!pick) return null
  const { r } = pick
  return { key: `best:keyword:${r.provider}:${r.campaign}:${r.id}`, kind: 'best', level: 'keyword', name: r.name, provider: r.provider, cps: pick.cps,
    restCps: pick.rest, url: platformUrl(r.provider, r.account, r.campaign, 'keyword') }
}

/**
 * The card's tips, by stated rules on the rows' own figures (never the design's literals), at most two: the dearest
 * keyword, the keyword that converts best (only under manual bidding), the dearest ad. Rows in another currency than
 * the campaign's are left out; without signups per row (no utm_term / utm_content on the links) there is no tip.
 */
export function campaignTips(d: Pick<CampaignDetail, 'ads' | 'keywords' | 'currency' | 'platforms'>): CampaignTip[] {
  if (!d.currency) return []
  const same = (r: { currency: string | null }) => r.currency === d.currency
  const kws: AdRow[] = d.keywords.filter(same).map((k) => ({ ...k, kind: 'keyword' as const }))
  const ads: AdRow[] = d.ads.filter(same).map((a) => ({ ...a, kind: 'ad' as const }))
  const bidding = new Map(d.platforms.map((p) => [`${p.account}:${p.campaign}`, p.bidding]))
  return [dearest(kws), bestKeyword(kws, bidding), dearest(ads)].filter((t): t is CampaignTip => !!t).slice(0, 2)
}

// ---------------------------------------------------------------------------
// Email and automation (simple_sequence_results, email_send_times)
const Figures = z.object({
  tracking: z.boolean(), sent: n, delivered: n, opens: nn, clicks: nn, unsubscribed: n, with_org: n, past_employees: n, signups: n,
})
export const SendWindow = z.object({ days: z.array(z.number().int().min(1).max(7)), hour: z.number().int().min(0).max(23), set_at: s })
export type SendWindow = z.infer<typeof SendWindow>
export const SequenceResults = z.object({
  id: uuid,
  days: n,
  send_window: SendWindow.nullable(),
  emails: z.array(z.object({ step: n, campaign_id: uuid.nullable(), subject: s, figures: Figures.nullable() })),
})
export type SequenceResults = z.infer<typeof SequenceResults>
export const SendTimes = z.object({
  days: n,
  min: n,
  cells: z.array(z.object({ dow: z.number().int().min(1).max(7), hour: z.number().int().min(0).max(23), delivered: n, opened: n })),
  best: z.object({ dow: n, hour: n, delivered: n, opened: n, days: z.array(z.number().int().min(1).max(7)) }).nullable(),
})
export type SendTimes = z.infer<typeof SendTimes>

/** The design's open-rate colour turns red under 45 %, the click rate under 10 %. */
export const OPEN_LOW = 45
export const CLICK_LOW = 10
/** An email tip looks at an email only after this many delivered in the window. */
export const TIP_MIN_DELIVERED = 20
/** «Add condition»: at least this share of an email's delivered sends (with an organisation) had already uploaded employees. */
export const TIP_PAST_SHARE = 0.25

export type EmailRow = {
  step: number
  subject: string
  /** null: the figures are another person's (no right to their reports) */
  sent: number | null
  open: number | null
  click: number | null
  unsub: number | null
  signups: number | null
  openLow: boolean
  clickLow: boolean
}

const pct = (a: number | null, b: number) => (a === null || b <= 0 ? null : (a / b) * 100)

/** One row per email step. Rates are over delivered; «—» (null) when nothing was delivered or opens are not tracked. */
export function emailRows(r: Pick<SequenceResults, 'emails'>): EmailRow[] {
  return r.emails.map((e) => {
    const f = e.figures
    if (!f) return { step: e.step, subject: e.subject, sent: null, open: null, click: null, unsub: null, signups: null, openLow: false, clickLow: false }
    const open = f.tracking ? pct(f.opens, f.delivered) : null
    const click = f.tracking ? pct(f.clicks, f.delivered) : null
    return {
      step: e.step, subject: e.subject, sent: f.sent, open, click, unsub: pct(f.unsubscribed, f.delivered), signups: f.sent > 0 ? f.signups : null,
      openLow: open !== null && open < OPEN_LOW, clickLow: click !== null && click < CLICK_LOW,
    }
  })
}

export type EmailTip =
  | { kind: 'ab'; email: number; rate: number }
  | { kind: 'cond'; email: number; step: number; share: number }
  | { kind: 'time'; days: number[]; hour: number }

type StepKind = { kind: string; cond?: string }

/**
 * The three email tips, by stated rules on the sequence's own last 30 days:
 *  - «Create A/B test»: the first email with 20 delivered whose click rate is under 10 % (the button stays off: an
 *    automated email cannot carry subject B, V-P6C-11);
 *  - «Add condition»: the first email after the first whose delivered sends (to someone with an organisation, at least 20)
 *    went for a quarter or more to organisations that had already uploaded their employee list, with no «employee list is
 *    not uploaded» condition between it and the email before;
 *  - «Use best time»: a best send time is known and the sequence has no send window yet.
 * `email` is the email's number among the emails (1-based), `step` its index among the steps.
 */
export function emailTips(r: Pick<SequenceResults, 'emails' | 'send_window'>, steps: StepKind[], best: SendTimes['best']): EmailTip[] {
  const out: EmailTip[] = []
  const ab = r.emails.findIndex((e) => e.figures && e.figures.tracking && e.figures.delivered >= TIP_MIN_DELIVERED && e.figures.clicks !== null
    && (e.figures.clicks / e.figures.delivered) * 100 < CLICK_LOW)
  if (ab >= 0) {
    const f = r.emails[ab]!.figures!
    out.push({ kind: 'ab', email: ab + 1, rate: ((f.clicks ?? 0) / f.delivered) * 100 })
  }
  for (let i = 1; i < r.emails.length; i++) {
    const e = r.emails[i]!
    const f = e.figures
    if (!f || f.with_org < TIP_MIN_DELIVERED || f.past_employees / f.with_org < TIP_PAST_SHARE) continue
    const prev = r.emails[i - 1]!.step
    const guarded = steps.slice(prev + 1, e.step).some((x) => x.kind === 'cond' && x.cond === 'employees_missing')
    if (guarded) continue
    out.push({ kind: 'cond', email: i + 1, step: e.step, share: (f.past_employees / f.with_org) * 100 })
    break
  }
  if (best && !r.send_window && r.emails.length > 0) out.push({ kind: 'time', days: best.days, hour: best.hour })
  return out
}

/** The heatmap's columns: the design's twelve hours. */
export const HEAT_HOURS = [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20] as const
export const HEAT_DAYS = [1, 2, 3, 4, 5, 6, 7] as const
export type HeatBand = 'none' | 'low' | 'mid' | 'midhigh' | 'high'
export type HeatCell = { dow: number; hour: number; delivered: number; opened: number; rate: number | null; band: HeatBand; best: boolean }

/**
 * The grid: each cell's open rate over delivered, banded against the best cell as the design bands its formula (> 85 %
 * of the best: high, > 60 %: medium, > 40 %: light, else low). A cell under the minimum has no rate and no fill (`none`,
 * the empty treatment): a low fill would claim a low rate. `outside` counts delivered sends at hours the grid has no
 * column for.
 */
export function heatGrid(t: SendTimes): { rows: { dow: number; cells: HeatCell[] }[]; outside: number } {
  const at = new Map(t.cells.map((c) => [`${c.dow}:${c.hour}`, c]))
  const bestRate = t.best && t.best.delivered > 0 ? t.best.opened / t.best.delivered : null
  const rows = HEAT_DAYS.map((dow) => ({
    dow,
    cells: HEAT_HOURS.map((hour): HeatCell => {
      const c = at.get(`${dow}:${hour}`)
      const delivered = c?.delivered ?? 0
      const opened = c?.opened ?? 0
      if (delivered < t.min) return { dow, hour, delivered, opened, rate: null, band: 'none', best: false }
      const rate = opened / delivered
      const v = bestRate ? rate / bestRate : 0
      const band: HeatBand = v > 0.85 ? 'high' : v > 0.6 ? 'midhigh' : v > 0.4 ? 'mid' : 'low'
      return { dow, hour, delivered, opened, rate: rate * 100, band, best: !!t.best && t.best.dow === dow && t.best.hour === hour }
    }),
  }))
  const outside = t.cells.filter((c) => !(HEAT_HOURS as readonly number[]).includes(c.hour)).reduce((a, c) => a + c.delivered, 0)
  return { rows, outside }
}

/** «08:00» */
export const hourText = (h: number) => `${String(h).padStart(2, '0')}:00`

/** «Tue–Thu», «Mon, Wed», «Mon–Wed, Fri»: runs of three or more days with a dash. */
export function windowDays(days: number[], dayName: (dow: number) => string): string {
  const sorted = [...new Set(days)].sort((a, b) => a - b)
  const parts: string[] = []
  for (let i = 0; i < sorted.length;) {
    let j = i
    while (j + 1 < sorted.length && sorted[j + 1] === sorted[j]! + 1) j++
    if (j - i >= 2) parts.push(`${dayName(sorted[i]!)}–${dayName(sorted[j]!)}`)
    else for (let k = i; k <= j; k++) parts.push(dayName(sorted[k]!))
    i = j + 1
  }
  return parts.join(', ')
}

/** «Tue–Thu 08:00» */
export const windowText = (days: number[], hour: number, dayName: (dow: number) => string) => `${windowDays(days, dayName)} ${hourText(hour)}`
