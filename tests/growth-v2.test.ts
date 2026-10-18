import { describe, expect, it } from 'vitest'
import { daysSince, durationParts, expectedCtr, funnelFix, intentOf, keywordAdvice, keywordRow, kwFilter, KW_SETTLE_DAYS, opportunities, pageOpportunity, pageTag, relChange } from '../lib/growth/calc'
import { growthHref, parseGrowth } from '../lib/growth/scope'

describe('growth scope in the address (Growth v2)', () => {
  it('reads every choice and falls back to the defaults', () => {
    const p = parseGrowth({ tab: 'funnel', range: '7d', day: '2026-10-09', hour: '14', src: 'organic_search', dev: 'mobile', step: '3', lf: 'stopped' })
    expect(p).toMatchObject({ tab: 'funnel', range: '7d', day: '2026-10-09', hour: 14, src: 'organic_search', dev: 'mobile', step: 3, lf: 'stopped' })
    expect(parseGrowth({ tab: 'nope', range: '12m', hour: '30', dev: 'phone', src: 'Bad!' })).toMatchObject({ tab: 'overview', range: '30d', hour: null, dev: null, src: null })
    // the old Analytics address opens the Overview; an hour needs a day (or «Today»)
    expect(parseGrowth({ tab: 'analytics' }).tab).toBe('overview')
    expect(parseGrowth({ hour: '9' }).hour).toBeNull()
    expect(parseGrowth({ range: 'today', hour: '9', day: '2026-10-01' })).toMatchObject({ day: null, hour: 9 })
  })

  it('writes the scope only on the scoped tabs, and leaves the defaults out', () => {
    const s = { range: '7d' as const, day: '2026-10-09', hour: 14, src: 'email', dev: null }
    expect(growthHref('overview', { range: '30d', day: null, hour: null, src: null, dev: null })).toBe('/growth')
    expect(growthHref('funnel', s, { step: 4, lf: 'all' })).toBe('/growth?tab=funnel&range=7d&day=2026-10-09&hour=14&src=email')
    expect(growthHref('integrations', s, { sub: 'gsc' })).toBe('/growth?tab=integrations&sub=gsc')
    expect(growthHref('pages', s, { page: '/pris', sort: 'visits' })).toBe('/growth?tab=pages&range=7d&day=2026-10-09&hour=14&src=email&page=%2Fpris&sort=visits')
  })
})

describe('growth arithmetic and rules (Growth v2)', () => {
  it('changes and click rates', () => {
    expect(relChange(110, 100)).toBe(10)
    expect(relChange(5, 0)).toBeNull()
    expect(relChange(null, 3)).toBeNull()
    expect(expectedCtr(1)).toBe(0.28)
    expect(expectedCtr(7)).toBe(0.025)
    expect(expectedCtr(40)).toBe(0.002)
  })

  it('a keyword: segment, potential, low click rate, losing, the advice', () => {
    const k = keywordRow({ query: 'medarbeiderundersøkelse', impressions: 1000, clicks: 20, position: 4.2, position_prev: 5.5 })
    expect(k.segment).toBe('striking')
    expect(k.potential).toBe(80) // 1000 × 10 % − 20
    expect(k.ctrGap).toBe(true) // 2 % < 0,7 × 6 %
    expect(k.change).toBe(1.3)
    expect(keywordAdvice(k)).toBe('page1')
    expect(kwFilter('lowctr', k) && !kwFilter('top3', k)).toBe(true)
    const lost = keywordRow({ query: 'x', impressions: 10, clicks: 0, position: 12, position_prev: 9 })
    expect(lost.losing && kwFilter('losing', lost)).toBe(true)
    expect(keywordRow({ query: 'ny', impressions: null, clicks: null, position: null, position_prev: null })).toMatchObject({ segment: 'new', potential: 0 })
    expect(intentOf('orgpuls priser', ['orgpuls'])).toBe('brand')
    expect(intentOf('hms system pris', [])).toBe('transactional')
    expect(intentOf('medarbeiderundersøkelse mal gratis', [])).toBe('commercial')
    expect(intentOf('verneombud plikter', [])).toBe('informational')
  })

  it('below 20: one page asked for when Google splits the search, too early before eight weeks, the design after', () => {
    const low = keywordRow({ query: 'leadership team effectiveness', impressions: 2, clicks: 0, position: 58.5, position_prev: null })
    expect(keywordAdvice(low)).toBe('low') // no tracking date: the design's advice
    expect(keywordAdvice(low, { trackedDays: 4, pagesShown: 1 })).toBe('low_young')
    expect(keywordAdvice(low, { trackedDays: KW_SETTLE_DAYS - 1 })).toBe('low_young')
    expect(keywordAdvice(low, { trackedDays: KW_SETTLE_DAYS, pagesShown: 1 })).toBe('low')
    expect(keywordAdvice(low, { trackedDays: 4, pagesShown: 2 })).toBe('low_split')
    expect(keywordAdvice(low, { trackedDays: null, pagesShown: null })).toBe('low')
    // above 20 the age changes nothing
    const p2 = keywordRow({ query: 'x', impressions: 50, clicks: 0, position: 14, position_prev: null })
    expect(keywordAdvice(p2, { trackedDays: 1, pagesShown: 3 })).toBe('page2')
    const now = Date.parse('2026-10-18T12:00:00Z')
    expect(daysSince('2026-10-14T09:00:00Z', now)).toBe(4)
    expect(daysSince(null, now)).toBeNull()
    expect(daysSince('not a date', now)).toBeNull()
    expect(daysSince('2026-10-19T00:00:00Z', now)).toBe(0)
  })

  it('a page: its tag and what it would add at the site\'s rate', () => {
    expect(pageTag({ visits: 100, started: 5, bounce: 30, lcp_ms: 1200 }, 1000)).toBe('converts')
    expect(pageTag({ visits: 100, started: 1, bounce: 30, lcp_ms: 3100 }, 1000)).toBe('slow')
    expect(pageTag({ visits: 300, started: 2, bounce: 30, lcp_ms: null }, 1000)).toBe('weak')
    expect(pageTag({ visits: 50, started: 1, bounce: 70, lcp_ms: null }, 1000)).toBe('bounce')
    expect(pageOpportunity({ visits: 1000, started: 5, lcp_ms: null }, 0.015)).toBeCloseTo(10)
  })

  it('the funnel\'s fix: the strongest signal, or nothing', () => {
    const seg = [
      { kind: 'channel' as const, key: 'organic_search', entered: 100, continued: 40 },
      { kind: 'device' as const, key: 'desktop', entered: 60, continued: 30 },
      { kind: 'device' as const, key: 'mobile', entered: 40, continued: 10 },
    ]
    expect(funnelFix(seg, [], 60)).toMatchObject({ kind: 'device', key: 'mobile', other: 'desktop' })
    const even = seg.map((s) => (s.kind === 'device' ? { ...s, continued: Math.round(s.entered * 0.4) } : s))
    expect(funnelFix(even, [{ kind: 'error', value: 'brreg_not_found', count: 12 }], 60)).toMatchObject({ kind: 'error', value: 'brreg_not_found' })
    expect(funnelFix(even, [{ kind: 'exit', value: '/pris', count: 30 }], 60)).toMatchObject({ kind: 'exit', value: '/pris', share: 0.5 })
    expect(funnelFix(even, [{ kind: 'exit', value: '/pris', count: 5 }], 60)).toBeNull()
  })

  it('opportunities: only with their figures, per month, largest first', () => {
    const o = opportunities({
      days: 30, visitors: 10000, started: 150,
      devices: [{ device: 'desktop', visits: 6000, started: 120 }, { device: 'mobile', visits: 4000, started: 30 }],
      landing: [{ path: '/artikler/mal', visits: 1500, started: 6, lcp_ms: 2900 }, { path: '/pris', visits: 800, started: 30, lcp_ms: 1800 }],
      keywords: [keywordRow({ query: 'medarbeiderundersøkelse', impressions: 10000, clicks: 300, position: 4.2, position_prev: 5 })],
      errors: [{ value: 'brreg_not_found', count: 40 }],
      stepRate: 0.5,
    })
    expect(o.map((x) => x.kind)).toEqual(['mobile', 'error', 'page', 'keyword', 'slow'])
    expect(o.find((x) => x.kind === 'mobile')!.gain).toBe(50) // 4000 × (2 % − 0,75 %)
    expect(o.find((x) => x.kind === 'error')!.gain).toBe(20)
    expect(opportunities({ days: 30, visitors: null, started: null, devices: [], landing: [], keywords: [], errors: [], stepRate: null })).toEqual([])
  })

  it('a duration the way the step card writes it', () => {
    expect(durationParts(42)).toEqual({ unit: 's', value: 42 })
    expect(durationParts(130)).toEqual({ unit: 'min', value: 2, rest: 10 })
    expect(durationParts(86400 * 1.8)).toEqual({ unit: 'd', value: 1.8 })
  })
})

describe('the site in the address (0089: a site per market)', () => {
  it('reads a hostname, and nothing else', () => {
    expect(parseGrowth({ site: 'se.orgpuls.com' }).site).toBe('se.orgpuls.com')
    expect(parseGrowth({ site: 'empvibe.com' }).site).toBe('empvibe.com')
    expect(parseGrowth({}).site).toBeNull()
    expect(parseGrowth({ site: 'not a host' }).site).toBeNull()
    expect(parseGrowth({ site: 'localhost' }).site).toBeNull()
    expect(parseGrowth({ site: 'https://evil.example/' }).site).toBeNull()
  })
  it('travels with the scope to the scoped tabs, and is left behind elsewhere', () => {
    const scope = { range: '30d' as const, day: null, hour: null, src: null, dev: null, site: 'empvibe.com' }
    expect(growthHref('pages', scope)).toBe('/growth?tab=pages&site=empvibe.com')
    expect(growthHref('seo', scope, { sub: 'links' })).toBe('/growth?tab=seo&site=empvibe.com&sub=links')
    expect(growthHref('campaigns', scope)).toBe('/growth?tab=campaigns')
    expect(growthHref('overview', { ...scope, site: null })).toBe('/growth')
  })
})
