import { z } from 'zod'
import { expectedCtr } from './calc'

/**
 * Growth › SEO, the suite (SeoSuite.dc.html of 11 Oct 2026; 0074): the shapes its reads return, parsed at the boundary,
 * and the rules that turn their raw figures into what the views show. Pure and tested (tests/seo-suite.test.ts). An
 * estimate rests only on figures Sentral holds; when one is missing the estimate is null and the view says «—».
 */
const n = z.number()
const nn = z.number().nullable()
const s = z.string()
const sn = z.string().nullable()
const uuid = z.string().uuid()

export const SEO_VIEWS = ['overview', 'clusters', 'opps', 'keywords', 'plan', 'links', 'serp', 'changes', 'alerts'] as const
export type SeoView = (typeof SEO_VIEWS)[number]
export const OPP_KINDS = ['striking', 'low_ctr', 'gap', 'cannibal', 'decay'] as const
export type OppKind = (typeof OPP_KINDS)[number]
export const STAGES = ['idea', 'writing', 'published', 'measuring'] as const
export type Stage = (typeof STAGES)[number]
export const CHANGE_KINDS = ['title_meta', 'content', 'links', 'schema', 'speed', 'new_page', 'merge'] as const
export type ChangeKind = (typeof CHANGE_KINDS)[number]
export const RULES = ['rank', 'deindex', 'traffic', 'cwv'] as const
export type Rule = (typeof RULES)[number]
export const CHANNELS = ['app', 'email'] as const
export const COVERAGE = ['indexed', 'crawled_not_indexed', 'discovered_not_indexed', 'duplicate', 'noindex', 'not_found', 'redirect',
  'blocked', 'error', 'unknown', 'other'] as const
export type Coverage = (typeof COVERAGE)[number]

// ---------------------------------------------------------------------------
// Shapes

const Kw = z.object({ query: s, impressions: nn, position: nn, impressions_prev: nn, position_prev: nn })
/** a country (ISO 3166-1 alpha-3 as Google writes it) or a device, the last 30 days and the impressions of the 30 before (0091) */
const Segment = z.object({ key: s, impressions: n, clicks: n, position: nn, impressions_prev: n })
export type Segment = z.infer<typeof Segment>
export const DEVICES = ['desktop', 'mobile', 'tablet'] as const
export const SeoOverview = z.object({
  connected: z.boolean(),
  site: z.object({ id: uuid, hostname: s }).nullable(),
  last_import_at: sn,
  last_day: sn,
  tracked_since: sn,
  clicks: z.object({ now: nn, prev: nn, named: nn }).nullable(),
  signups: z.object({ now: nn, prev: nn }),
  attributed: z.boolean(),
  mrr_won: z.object({ now: n, prev: n }).nullable(),
  keywords: z.array(Kw).nullable(),
  index: z.object({
    pages: n, indexed: n, dropped: n, last_at: sn, crawled: n,
    buckets: z.array(z.object({ coverage: z.enum(COVERAGE), count: n })),
  }).nullable(),
  // the countries and devices the searches came from (0091); null without a connection and a property
  segments: z.object({
    imported: z.boolean(),
    countries: z.array(Segment),
    countries_other: z.object({ countries: n, impressions: n, clicks: n }).nullable(),
    devices: z.array(Segment.extend({ key: z.enum(DEVICES) })),
  }).nullable().optional(),
})
export type SeoOverview = z.infer<typeof SeoOverview>

export const Econ = z.object({ since: sn, clicks: nn, signups: nn, accounts: n, paying: n, mrr: nn, paying_now: nn })
export type Econ = z.infer<typeof Econ>
export const SeoOpps = z.object({
  connected: z.boolean(),
  econ: Econ.nullable(),
  queries: z.array(z.object({ query: s, impressions: n, clicks: n, position: nn, page: sn, tracked: z.boolean() })).nullable(),
  cannibal: z.array(z.object({ query: s, impressions: n, clicks: n, position: nn, pages: z.array(z.object({ page: s, impressions: n, clicks: n })) })).nullable(),
  decay: z.array(z.object({ path: s, clicks: n, clicks_before: n, impressions: n, query: sn })).nullable(),
  planned: z.array(z.object({ query: s, stage: z.enum(STAGES) })),
})
export type SeoOpps = z.infer<typeof SeoOpps>

export const SeoClusters = z.object({
  connected: z.boolean(),
  unclustered: n,
  clusters: z.array(z.object({
    main: s,
    title: sn,
    clicks: n,
    keywords: z.array(z.object({ query: s, position: nn, weeks: z.array(z.object({ impressions: n, clicks: n, position: nn })) })),
    pages: z.array(z.object({ path: s, title: sn, clicks: n, impressions: n, position: nn })),
    plan: z.array(z.object({ id: uuid, query: s, stage: z.enum(STAGES), path: sn })),
  })),
})
export type SeoClusters = z.infer<typeof SeoClusters>

export const SeoPlan = z.object({
  last_day: sn,
  items: z.array(z.object({
    id: uuid, query: s, kind: z.enum(OPP_KINDS), path: sn, stage: z.enum(STAGES), owner: sn, created_at: s, published_at: sn, measure_on: sn,
    measured: z.object({ clicks_before: n, clicks_after: n, position_before: nn, position_after: nn }).nullable(),
  })),
  brief: z.object({ id: uuid, terms: z.array(s), questions: z.array(s), links: z.array(z.object({ from: s, anchor: s })) }).nullable(),
})
export type SeoPlan = z.infer<typeof SeoPlan>

export const SeoLinks = z.object({
  crawled_at: sn,
  links: n,
  suggestions: z.array(z.object({ from: s, anchor: s, to: s, decision: z.enum(['added', 'skipped']).nullable() })),
  orphans: z.array(z.object({ path: s, visits: n })),
  hubs: z.array(z.object({ path: s, inlinks: n, anchor: sn })),
})
export type SeoLinks = z.infer<typeof SeoLinks>

const Window = z.object({ clicks: n, impressions: n, position: nn, days: n })
export const SeoChanges = z.object({
  last_day: sn,
  daily: z.array(z.object({ day: s, clicks: n })),
  pages: z.array(s),
  changes: z.array(z.object({
    id: uuid, day: s, path: sn, query: sn, kind: z.enum(CHANGE_KINDS), note: sn, source: z.enum(['manual', 'plan', 'link']), by: sn,
    ready: z.boolean(), before: Window, after: Window,
  })),
})
export type SeoChanges = z.infer<typeof SeoChanges>

export const SeoAlerts = z.object({
  mail_ready: z.boolean(),
  rules: z.array(z.object({ rule: z.enum(RULES), enabled: z.boolean(), channels: z.array(z.enum(CHANNELS)) })),
  open: n,
  history: z.array(z.object({ id: uuid, rule: z.enum(RULES), params: z.record(z.string(), z.union([z.string(), z.number(), z.null()])), at: s, acknowledged_at: sn })),
})
export type SeoAlerts = z.infer<typeof SeoAlerts>

// ---------------------------------------------------------------------------
// Visibility: the click share the site's positions earn against holding #1 for every tracked search (the expected click
// rate at each position, weighted by its impressions), in per cent

export function visibility(rows: { impressions: number | null; position: number | null }[]): number | null {
  let num = 0
  let den = 0
  for (const r of rows) {
    if (!r.impressions || r.position === null) continue
    num += r.impressions * expectedCtr(r.position)
    den += r.impressions * expectedCtr(1)
  }
  return den > 0 ? (num / den) * 100 : null
}

/** A cluster's visibility per week (twelve), its level over the last four and the change against the first four, in points */
export function clusterVisibility(keywords: { weeks: { impressions: number; position: number | null }[] }[]): {
  weeks: (number | null)[]
  now: number | null
  trend: number | null
} {
  const n = Math.max(0, ...keywords.map((k) => k.weeks.length))
  const week = (from: number, to: number) => visibility(keywords.flatMap((k) => k.weeks.slice(from, to)))
  const weeks = Array.from({ length: n }, (_, i) => week(i, i + 1))
  const now = week(Math.max(0, n - 4), n)
  const then = week(0, Math.min(4, n))
  return { weeks, now, trend: now !== null && then !== null && n >= 8 ? Math.round((now - then) * 10) / 10 : null }
}

// ---------------------------------------------------------------------------
// Opportunities, typed and priced (the design's «Value = volume × click-rate gain × signup rate × paid rate × ARPA ×
// chance of winning»)

/** what one click is worth a month: signups per click × paying per account × revenue per paying account; null without any */
export function valuePerClick(e: Econ | null): { signup: number | null; paid: number | null; arpa: number | null; perClick: number | null } {
  if (!e) return { signup: null, paid: null, arpa: null, perClick: null }
  const signup = e.clicks && e.signups ? e.signups / e.clicks : null
  const paid = e.accounts && e.paying ? e.paying / e.accounts : null
  const arpa = e.paying_now && e.mrr ? e.mrr / e.paying_now : null
  return { signup, paid, arpa, perClick: signup !== null && paid !== null && arpa !== null ? signup * paid * arpa : null }
}

export type Effort = 'small' | 'medium' | 'large'
/** the design's chances of winning and the effort each kind of work takes */
export const CHANCE: Record<OppKind, number> = { striking: 0.75, low_ctr: 0.95, gap: 0.5, cannibal: 0.8, decay: 0.85 }
export const EFFORT: Record<OppKind, Effort> = { striking: 'medium', low_ctr: 'small', gap: 'large', cannibal: 'small', decay: 'medium' }

export type SeoOpp = {
  kind: OppKind
  /** the search the work is for (the plan's key) */
  query: string
  /** the page concerned, when one exists */
  path: string | null
  impressions: number
  position: number | null
  ctr: number | null
  /** extra clicks a month if it works out */
  clicks: number
  /** kroner a month (clicks × chance × value per click), null without the economics */
  value: number | null
  effort: Effort
  chance: number
  planned: boolean
  /** cannibalization: the pages and their share of the impressions; decay: clicks before and now */
  pages?: { page: string; share: number }[]
  before?: number
  now?: number
}

const MONTH = 30 / 28

export function seoOpportunities(d: SeoOpps): SeoOpp[] {
  const { perClick } = valuePerClick(d.econ)
  const planned = new Set(d.planned.map((p) => p.query))
  const out: SeoOpp[] = []
  const push = (o: Omit<SeoOpp, 'value' | 'effort' | 'planned' | 'chance'> & { chance?: number }) => {
    const chance = o.chance ?? CHANCE[o.kind]
    const clicks = Math.round(o.clicks)
    if (clicks < 1) return
    out.push({ ...o, clicks, chance, effort: EFFORT[o.kind], planned: planned.has(o.query), value: perClick === null ? null : Math.round(clicks * chance * perClick) })
  }
  for (const q of d.queries ?? []) {
    if (q.position === null || q.impressions <= 0) continue
    const ctr = q.clicks / q.impressions
    const base = { query: q.query, path: q.page, impressions: q.impressions, position: q.position, ctr }
    if (q.position > 3 && q.position <= 20) {
      push({ ...base, kind: 'striking', clicks: q.impressions * MONTH * Math.max(0, expectedCtr(3) - ctr), chance: q.position <= 10 ? 0.75 : 0.6 })
    } else if (q.position <= 3 && ctr < expectedCtr(q.position) * 0.7) {
      push({ ...base, kind: 'low_ctr', clicks: q.impressions * MONTH * (expectedCtr(q.position) - ctr) })
    } else if (q.position > 20) {
      push({ ...base, kind: 'gap', clicks: q.impressions * MONTH * Math.max(0, expectedCtr(5) - ctr) })
    }
  }
  for (const c of d.cannibal ?? []) {
    if (c.position === null || c.impressions <= 0) continue
    // one page instead of two: assumed to climb one place
    const gain = Math.max(0, expectedCtr(Math.max(1, c.position - 1)) - expectedCtr(c.position))
    push({ kind: 'cannibal', query: c.query, path: c.pages[0]?.page ?? null, impressions: c.impressions, position: c.position, ctr: c.clicks / c.impressions,
           clicks: c.impressions * MONTH * gain, pages: c.pages.map((p) => ({ page: p.page, share: p.impressions / c.impressions })) })
  }
  for (const x of d.decay ?? []) {
    if (!x.query) continue
    push({ kind: 'decay', query: x.query, path: x.path, impressions: x.impressions, position: null, ctr: null,
           clicks: (x.clicks_before - x.clicks) * MONTH, before: x.clicks_before, now: x.clicks })
  }
  // by value; without the economics, by the clicks they would likely bring
  return out.sort((a, b) => (b.value ?? 0) - (a.value ?? 0) || b.clicks * b.chance - a.clicks * a.chance || a.query.localeCompare(b.query))
}

// ---------------------------------------------------------------------------
// The content plan, the change log

/** a change's result once 28 days are reported: clicks in per cent, position in places (positive = better), CTR in points */
export type ChangeResult = { clicks: number | null; position: number | null; ctr: number | null; verdict: 'win' | 'small' | 'none' | 'loss' | 'measuring' | null }
export function changeResult(c: { ready: boolean; before: { clicks: number; impressions: number; position: number | null; days: number }; after: { clicks: number; impressions: number; position: number | null } }): ChangeResult {
  if (!c.ready) return { clicks: null, position: null, ctr: null, verdict: 'measuring' }
  // no baseline: nothing was reported for the page in the 28 days before
  if (c.before.days === 0 || c.before.impressions === 0) return { clicks: null, position: null, ctr: null, verdict: null }
  const clicks = c.before.clicks > 0 ? Math.round((c.after.clicks / c.before.clicks - 1) * 100) : null
  const position = c.before.position !== null && c.after.position !== null ? Math.round((c.before.position - c.after.position) * 10) / 10 : null
  const ctr = c.after.impressions > 0 ? Math.round(((c.after.clicks / c.after.impressions) - (c.before.clicks / c.before.impressions)) * 1000) / 10 : null
  const verdict = clicks === null ? null : clicks >= 10 ? 'win' : clicks > 0 ? 'small' : clicks <= -10 ? 'loss' : 'none'
  return { clicks, position, ctr, verdict }
}

/** the next and the previous stage of a plan item */
export function stageStep(stage: Stage, dir: -1 | 1): Stage | null {
  const i = STAGES.indexOf(stage) + dir
  return i >= 0 && i < STAGES.length ? STAGES[i]! : null
}
