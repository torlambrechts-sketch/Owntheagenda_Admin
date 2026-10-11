/**
 * Growth v2's arithmetic and rules (SimpleGrowth.dc.html's renderVals, applied to real figures). Pure and tested. A rule
 * that lacks an input gives nothing rather than a guess; an estimate says it is one where it is shown.
 */

/** «+12 %», «−9 %»: the relative change the design prints beside a KPI; null without a base */
export function relChange(now: number | null | undefined, prev: number | null | undefined): number | null {
  if (now === null || now === undefined || prev === null || prev === undefined || prev === 0) return null
  return Math.round((now / prev - 1) * 100)
}

export const rate = (part: number | null | undefined, whole: number | null | undefined): number | null =>
  part === null || part === undefined || !whole ? null : part / whole

// ---------------------------------------------------------------------------
// Keywords (SEO › Keywords)

/** The expected click rate at a position (the design's ECTR): what a result there usually gets */
export function expectedCtr(pos: number): number {
  return pos <= 1 ? 0.28 : pos <= 2 ? 0.155 : pos <= 3 ? 0.1 : pos <= 5 ? 0.06 : pos <= 10 ? 0.025 : pos <= 20 ? 0.008 : 0.002
}

export type KwSegment = 'top3' | 'striking' | 'low' | 'new'
export type KwInput = { query: string; impressions: number | null; clicks: number | null; position: number | null; position_prev: number | null }
export type KwRow = KwInput & {
  ctr: number | null
  segment: KwSegment
  potential: number
  ctrGap: boolean
  losing: boolean
  change: number | null
}

export function keywordRow(k: KwInput): KwRow {
  const pos = k.position
  const impr = k.impressions ?? 0
  const clicks = k.clicks ?? 0
  const ctr = impr > 0 ? clicks / impr : null
  const segment: KwSegment = pos === null ? 'new' : pos <= 3 ? 'top3' : pos <= 20 ? 'striking' : 'low'
  // what reaching the top three (or holding the place) would add, at the usual click rate there
  const target = pos === null ? null : pos > 3 ? 3 : pos
  const potential = target === null ? 0 : Math.max(0, Math.round(impr * expectedCtr(target) - clicks))
  const ctrGap = pos !== null && ctr !== null && ctr < expectedCtr(pos) * 0.7
  const change = pos !== null && k.position_prev !== null ? Math.round((k.position_prev - pos) * 10) / 10 : null
  return { ...k, ctr, segment, potential, ctrGap, losing: pos !== null && k.position_prev !== null && pos > k.position_prev + 0.5, change }
}

export function kwFilter(tab: 'all' | 'top3' | 'striking' | 'low' | 'losing' | 'lowctr', r: KwRow): boolean {
  switch (tab) {
    case 'top3': return r.segment === 'top3'
    case 'striking': return r.segment === 'striking'
    case 'low': return r.segment === 'low'
    case 'losing': return r.losing
    case 'lowctr': return r.ctrGap
    default: return true
  }
}

export type Intent = 'brand' | 'transactional' | 'commercial' | 'informational'
/** What a search is after, by its words (a rule, shown as a label) */
export function intentOf(query: string, brands: string[]): Intent {
  const q = query.toLowerCase()
  if (brands.some((b) => b && q.includes(b.toLowerCase()))) return 'brand'
  if (/\b(pris|priser|kjøp|kjøpe|bestill|kostnad|koster|price|pricing|buy|app)\b/.test(q)) return 'transactional'
  if (/\b(mal|maler|beste|sammenlign|vs|gratis|verktøy|system|program|template|best|alternativ)\b/.test(q)) return 'commercial'
  return 'informational'
}

export type KwAdvice = 'new' | 'top3_ctr' | 'top3' | 'page1' | 'page2' | 'low'
/** The design's «Do this»: what the position and the click rate call for */
export function keywordAdvice(r: KwRow): KwAdvice {
  if (r.position === null) return 'new'
  if (r.position <= 3) return r.ctrGap ? 'top3_ctr' : 'top3'
  if (r.position <= 10) return 'page1'
  if (r.position <= 20) return 'page2'
  return 'low'
}

// ---------------------------------------------------------------------------
// Pages

export type PageTag = 'converts' | 'slow' | 'weak' | 'bounce' | null
export function pageTag(p: { visits: number; started: number; bounce: number; lcp_ms: number | null }, totalVisits: number): PageTag {
  const cv = p.visits ? (p.started / p.visits) * 100 : 0
  if (cv >= 4 && p.visits >= 10) return 'converts'
  if (p.lcp_ms !== null && p.lcp_ms > 2500) return 'slow'
  if (totalVisits > 0 && p.visits > totalVisits * 0.1 && cv < 1.5) return 'weak'
  if (p.bounce > 60) return 'bounce'
  return null
}

/** The signups a page would add at the site's own rate, and a little for a slow page (the design's opp) */
export function pageOpportunity(p: { visits: number; started: number; lcp_ms: number | null }, siteRate: number): number {
  const cv = p.visits ? p.started / p.visits : 0
  return p.visits * Math.max(0, siteRate - cv) + (p.lcp_ms !== null && p.lcp_ms > 2500 ? p.visits * 0.004 : 0)
}

export type PageAdvice = 'converts' | 'slow' | 'informational' | 'headline'
export function pageAdvice(tag: PageTag, conv: number | null): PageAdvice {
  if (tag === 'converts') return 'converts'
  if (tag === 'slow') return 'slow'
  if (conv !== null && conv < 0.01) return 'informational'
  return 'headline'
}

// ---------------------------------------------------------------------------
// The funnel

export type Segment = { kind: 'channel' | 'device'; key: string; entered: number; continued: number }
export type Reason = { kind: 'exit' | 'error'; value: string; count: number }
export type FixRule =
  | { kind: 'device'; key: string; rate: number; other: string; otherRate: number }
  | { kind: 'error'; value: string; count: number }
  | { kind: 'exit'; value: string; count: number; share: number }
  | { kind: 'channel'; key: string; rate: number; overall: number }

/** The step card's «Fix»: the strongest signal in the figures shown, or nothing when none is strong enough */
export function funnelFix(segments: Segment[], reasons: Reason[], stopped: number | null): FixRule | null {
  const total = segments.filter((s) => s.kind === 'channel').reduce((a, s) => a + s.entered, 0)
  const cont = segments.filter((s) => s.kind === 'channel').reduce((a, s) => a + s.continued, 0)
  const overall = total ? cont / total : null
  const dev = segments.filter((s) => s.kind === 'device' && s.entered >= 10).map((s) => ({ ...s, r: s.continued / s.entered }))
  const best = [...dev].sort((a, b) => b.r - a.r)[0]
  const worst = [...dev].sort((a, b) => a.r - b.r)[0]
  if (best && worst && best.key !== worst.key && best.r > 0 && worst.r < best.r * 0.8) {
    return { kind: 'device', key: worst.key, rate: worst.r, other: best.key, otherRate: best.r }
  }
  const err = reasons.filter((r) => r.kind === 'error').sort((a, b) => b.count - a.count)[0]
  if (err && stopped && err.count >= Math.max(3, stopped * 0.1)) return { kind: 'error', value: err.value, count: err.count }
  const exit = reasons.filter((r) => r.kind === 'exit').sort((a, b) => b.count - a.count)[0]
  if (exit && stopped && exit.count / stopped >= 0.4) return { kind: 'exit', value: exit.value, count: exit.count, share: exit.count / stopped }
  if (overall !== null) {
    const weak = segments.filter((s) => s.kind === 'channel' && s.entered >= 10).map((s) => ({ ...s, r: s.continued / s.entered }))
      .sort((a, b) => a.r - b.r)[0]
    if (weak && weak.r < overall * 0.6) return { kind: 'channel', key: weak.key, rate: weak.r, overall }
  }
  return null
}

// ---------------------------------------------------------------------------
// Overview › Biggest opportunities

export type Opportunity =
  | { kind: 'error'; gain: number; value: string; count: number; effort: 'small' }
  | { kind: 'keyword'; gain: number; query: string; position: number; potential: number; effort: 'medium' }
  | { kind: 'page'; gain: number; path: string; conv: number; effort: 'small' }
  | { kind: 'mobile'; gain: number; mobileRate: number; desktopRate: number; share: number; effort: 'medium' }
  | { kind: 'slow'; gain: number; path: string; lcp_ms: number; share: number; effort: 'small' }

/**
 * Each estimate is extra signups begun per month if one thing improved to what the site already does elsewhere: an error
 * fixed (its stopped visits at the rate the step continues), a keyword in the top three (its potential clicks at the
 * site's rate), a page at the site's rate, mobile at desktop's rate. «Slow» has no estimate of its own and is listed only
 * with a measured LCP. Nothing is shown without the figures behind it.
 */
export function opportunities(input: {
  days: number
  visitors: number | null
  started: number | null
  devices: { device: string; visits: number; started: number }[]
  landing: { path: string; visits: number; started: number; lcp_ms: number | null }[]
  keywords: KwRow[]
  errors: { value: string; count: number }[]
  stepRate: number | null
}): Opportunity[] {
  const perMonth = (x: number) => x * (30 / Math.max(1, input.days))
  const siteRate = rate(input.started, input.visitors)
  const out: Opportunity[] = []
  if (input.stepRate !== null) {
    for (const e of input.errors.slice(0, 2)) {
      const gain = Math.round(perMonth(e.count * input.stepRate))
      if (gain >= 1) out.push({ kind: 'error', gain, value: e.value, count: e.count, effort: 'small' })
    }
  }
  if (siteRate !== null) {
    const kw = input.keywords.filter((k) => k.segment === 'striking' && k.potential > 0).sort((a, b) => b.potential - a.potential)[0]
    if (kw && kw.position !== null) {
      const gain = Math.round(perMonth(kw.potential * siteRate))
      if (gain >= 1) out.push({ kind: 'keyword', gain, query: kw.query, position: kw.position, potential: kw.potential, effort: 'medium' })
    }
    const total = input.landing.reduce((a, p) => a + p.visits, 0)
    const weak = input.landing.filter((p) => total > 0 && p.visits >= total * 0.05)
      .map((p) => ({ p, gain: p.visits * Math.max(0, siteRate - p.started / Math.max(1, p.visits)) }))
      .sort((a, b) => b.gain - a.gain)[0]
    if (weak) {
      const gain = Math.round(perMonth(weak.gain))
      if (gain >= 1) out.push({ kind: 'page', gain, path: weak.p.path, conv: weak.p.started / Math.max(1, weak.p.visits), effort: 'small' })
    }
    const mob = input.devices.find((d) => d.device === 'mobile')
    const desk = input.devices.find((d) => d.device === 'desktop')
    const devTotal = input.devices.reduce((a, d) => a + d.visits, 0)
    if (mob && desk && mob.visits >= 50 && desk.visits >= 50) {
      const mr = mob.started / mob.visits
      const dr = desk.started / desk.visits
      const gain = Math.round(perMonth(mob.visits * Math.max(0, dr - mr)))
      if (mr < dr * 0.75 && gain >= 1) out.push({ kind: 'mobile', gain, mobileRate: mr, desktopRate: dr, share: devTotal ? mob.visits / devTotal : 0, effort: 'medium' })
    }
    const slow = input.landing.filter((p) => p.lcp_ms !== null && p.lcp_ms > 2500 && total > 0 && p.visits >= total * 0.03)
      .sort((a, b) => b.visits - a.visits)[0]
    if (slow && slow.lcp_ms !== null) {
      // the design's small allowance for a slow page: 0,4 % of its visits
      const gain = Math.round(perMonth(slow.visits * 0.004))
      if (gain >= 1) out.push({ kind: 'slow', gain, path: slow.path, lcp_ms: slow.lcp_ms, share: slow.visits / total, effort: 'small' })
    }
  }
  return out.sort((a, b) => b.gain - a.gain).slice(0, 6)
}

/** A median duration the way the step card prints it: seconds, minutes, or days */
export function durationParts(seconds: number): { unit: 's' | 'min' | 'h' | 'd'; value: number; rest?: number } {
  if (seconds < 60) return { unit: 's', value: Math.round(seconds) }
  if (seconds < 3600) return { unit: 'min', value: Math.floor(seconds / 60), rest: Math.round(seconds % 60) }
  if (seconds < 86400 * 1.5) return { unit: 'h', value: Math.round((seconds / 3600) * 10) / 10 }
  return { unit: 'd', value: Math.round((seconds / 86400) * 10) / 10 }
}
