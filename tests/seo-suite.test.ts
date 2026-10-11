import { describe, expect, it } from 'vitest'
import { changeResult, clusterVisibility, seoOpportunities, stageStep, valuePerClick, visibility, type SeoOpps } from '../lib/growth/seo'
import { growthHref, parseGrowth } from '../lib/growth/scope'
import { coverageKey, inspectUrl } from '../supabase/functions/_shared/google'
import { anchorsOf, contentText, mentionsIn, pageFacts } from '../supabase/functions/_shared/seo-crawl'
import * as R from '../supabase/functions/_shared/mail-render'

const econ = { since: '2026-07-13', clicks: 10000, signups: 100, accounts: 50, paying: 10, mrr: 20000, paying_now: 25 }
const base: SeoOpps = { connected: true, econ, queries: [], cannibal: [], decay: [], planned: [] }

describe('SEO suite: visibility (0074)', () => {
  it('is the click share the positions earn against #1, weighted by impressions', () => {
    expect(visibility([{ impressions: 100, position: 1 }])).toBe(100)
    // #3 earns 0,1 of the 0,28 at #1
    expect(visibility([{ impressions: 100, position: 3 }])).toBeCloseTo(35.71, 1)
    expect(visibility([{ impressions: 100, position: 1 }, { impressions: 100, position: 40 }])).toBeCloseTo(50.36, 1)
    expect(visibility([{ impressions: null, position: 2 }, { impressions: 10, position: null }])).toBeNull()
  })
  it('a topic: week by week, the last four weeks and the change against the first four', () => {
    const weeks = (pos: number[]) => pos.map((p) => ({ impressions: 100, clicks: 0, position: p }))
    const v = clusterVisibility([{ weeks: weeks([10, 10, 10, 10, 5, 5, 5, 5, 1, 1, 1, 1]) }])
    expect(v.weeks).toHaveLength(12)
    expect(v.now).toBe(100)
    expect(v.trend).toBeCloseTo(100 - 8.93, 1)
    expect(clusterVisibility([{ weeks: weeks([1, 1, 1]) }]).trend).toBeNull()
  })
})

describe('SEO suite: opportunities, typed and priced (0074)', () => {
  it('a click is worth signups per click × paying per account × revenue per paying account, or nothing', () => {
    expect(valuePerClick(econ).perClick).toBeCloseTo(0.01 * 0.2 * 800)
    expect(valuePerClick({ ...econ, signups: 0 }).perClick).toBeNull()
    expect(valuePerClick({ ...econ, paying_now: null }).perClick).toBeNull()
    expect(valuePerClick(null).perClick).toBeNull()
  })

  it('reads striking distance, low click rate and content gaps from the searches', () => {
    const o = seoOpportunities({ ...base, queries: [
      { query: 'striking', impressions: 2800, clicks: 28, position: 6.2, page: '/a', tracked: true },
      { query: 'lowctr', impressions: 2800, clicks: 280, position: 1.4, page: '/b', tracked: false },
      { query: 'fine top', impressions: 2800, clicks: 800, position: 1.2, page: '/c', tracked: false },
      { query: 'gap', impressions: 280, clicks: 0, position: 31, page: '/d', tracked: false },
      { query: 'far striking', impressions: 280, clicks: 0, position: 15, page: '/e', tracked: false },
    ] })
    const by = Object.fromEntries(o.map((x) => [x.query, x]))
    // 2 800 impressions over 28 days, 30 days a month: (10 % − 1 %) × 3 000 = 270 clicks; × 0,75 × 1,6 kr
    expect(by.striking).toMatchObject({ kind: 'striking', clicks: 270, chance: 0.75, value: 324, effort: 'medium', path: '/a' })
    expect(by.lowctr).toMatchObject({ kind: 'low_ctr', clicks: 165, chance: 0.95, effort: 'small' })
    expect(by['fine top']).toBeUndefined()
    expect(by.gap).toMatchObject({ kind: 'gap', clicks: 18, chance: 0.5, effort: 'large' })
    expect(by['far striking']?.chance).toBe(0.6)
    expect(o.map((x) => x.query)).toEqual(['striking', 'lowctr', 'far striking', 'gap'])
  })

  it('cannibalization assumes one place up; decay is the clicks lost; the plan marks what is in it', () => {
    const o = seoOpportunities({ ...base,
      cannibal: [{ query: 'mal', impressions: 2800, clicks: 70, position: 5.6, pages: [{ page: '/a', impressions: 1960, clicks: 60 }, { page: '/b', impressions: 840, clicks: 10 }] }],
      decay: [{ path: '/old', clicks: 30, clicks_before: 86, impressions: 900, query: 'gammel' }, { path: '/none', clicks: 0, clicks_before: 50, impressions: 0, query: null }],
      planned: [{ query: 'mal', stage: 'idea' }] })
    const c = o.find((x) => x.kind === 'cannibal')!
    expect(c).toMatchObject({ clicks: 105, path: '/a', planned: true })
    expect(c.pages).toEqual([{ page: '/a', share: 0.7 }, { page: '/b', share: 0.3 }])
    expect(o.find((x) => x.kind === 'decay')).toMatchObject({ query: 'gammel', path: '/old', clicks: 60, before: 86, now: 30, planned: false })
    expect(o.filter((x) => x.kind === 'decay')).toHaveLength(1)
  })

  it('without the economics, no value is shown and the order is by likely clicks', () => {
    const o = seoOpportunities({ ...base, econ: { ...econ, paying: 0 }, queries: [
      { query: 'a', impressions: 280, clicks: 0, position: 31, page: null, tracked: false },
      { query: 'b', impressions: 280, clicks: 0, position: 6, page: null, tracked: false },
    ] })
    expect(o.every((x) => x.value === null)).toBe(true)
    expect(o.map((x) => x.query)).toEqual(['b', 'a'])
  })
})

describe('SEO suite: the plan and the change log (0074)', () => {
  it('a plan item steps between the four stages', () => {
    expect(stageStep('idea', -1)).toBeNull()
    expect(stageStep('idea', 1)).toBe('writing')
    expect(stageStep('measuring', 1)).toBeNull()
  })
  it('a change: «Measuring» until 28 days are reported, then clicks, places and CTR against the 28 days before', () => {
    const w = (clicks: number, impressions: number, position: number | null, days = 28) => ({ clicks, impressions, position, days })
    expect(changeResult({ ready: false, before: w(100, 1000, 5), after: w(0, 0, null) }).verdict).toBe('measuring')
    expect(changeResult({ ready: true, before: w(100, 1000, 6.1), after: w(138, 1100, 4.2) })).toEqual({ clicks: 38, position: 1.9, ctr: 2.5, verdict: 'win' })
    expect(changeResult({ ready: true, before: w(100, 1000, 5), after: w(104, 1000, 5) }).verdict).toBe('small')
    expect(changeResult({ ready: true, before: w(100, 1000, 5), after: w(97, 1000, 5.4) })).toMatchObject({ clicks: -3, position: -0.4, verdict: 'none' })
    expect(changeResult({ ready: true, before: w(100, 1000, 5), after: w(60, 1000, 8) }).verdict).toBe('loss')
    expect(changeResult({ ready: true, before: w(0, 0, null, 0), after: w(10, 100, 4) }).verdict).toBeNull()
  })
  it('the suite\'s choices live in the address', () => {
    expect(parseGrowth({ tab: 'seo', sub: 'clusters', cl: '/lovkrav', ot: 'decay', brief: 'b9d1b1f1-1111-4111-8111-111111111111' }))
      .toMatchObject({ sub: 'clusters', cl: '/lovkrav', ot: 'decay', brief: 'b9d1b1f1-1111-4111-8111-111111111111' })
    expect(parseGrowth({ cl: 'lovkrav', ot: 'nope', brief: 'x' })).toMatchObject({ cl: null, ot: 'all', brief: null })
    expect(growthHref('seo', { range: '30d', day: null, hour: null, src: null, dev: null }, { sub: 'opps', ot: 'all' })).toBe('/growth?tab=seo&sub=opps')
  })
})

describe('URL Inspection (0074)', () => {
  it('reduces Google\'s verdict and coverage sentence to the design\'s buckets', () => {
    expect(coverageKey('PASS', 'Submitted and indexed')).toBe('indexed')
    expect(coverageKey('NEUTRAL', 'Crawled - currently not indexed')).toBe('crawled_not_indexed')
    expect(coverageKey('NEUTRAL', 'Discovered - currently not indexed')).toBe('discovered_not_indexed')
    expect(coverageKey('NEUTRAL', 'Duplicate without user-selected canonical')).toBe('duplicate')
    expect(coverageKey('NEUTRAL', 'Alternate page with proper canonical tag')).toBe('duplicate')
    expect(coverageKey('NEUTRAL', 'Excluded by ‘noindex’ tag')).toBe('noindex')
    expect(coverageKey('FAIL', 'Not found (404)', 'NOT_FOUND')).toBe('not_found')
    expect(coverageKey('FAIL', 'Soft 404')).toBe('error')
    expect(coverageKey('NEUTRAL', 'Page with redirect')).toBe('redirect')
    expect(coverageKey('FAIL', 'Blocked by robots.txt')).toBe('blocked')
    expect(coverageKey('NEUTRAL', 'URL is unknown to Google')).toBe('unknown')
    expect(coverageKey('PARTIAL', 'Indexed, not submitted in sitemap')).toBe('indexed')
    expect(coverageKey(undefined, 'Something new')).toBe('other')
  })
  it('asks for one page under the property and keeps only the verdict, never the body', async () => {
    let sent: { url: string; body: unknown } | null = null
    const f = (async (url: string, init: RequestInit) => {
      sent = { url, body: JSON.parse(String(init.body)) }
      return new Response(JSON.stringify({ inspectionResult: { indexStatusResult: { verdict: 'PASS', coverageState: 'Submitted and indexed', lastCrawlTime: '2026-10-09T03:12:00Z', googleCanonical: 'x' } } }), { status: 200 })
    }) as unknown as typeof fetch
    const r = await inspectUrl('tok', 'sc-domain:orgpuls.com', 'https://www.orgpuls.com/pris', f)
    expect(r).toEqual({ ok: true, coverage: 'indexed', lastCrawlAt: '2026-10-09T03:12:00Z' })
    expect(sent).toEqual({ url: 'https://searchconsole.googleapis.com/v1/urlInspection/index:inspect', body: { inspectionUrl: 'https://www.orgpuls.com/pris', siteUrl: 'sc-domain:orgpuls.com' } })
    const quota = (async () => new Response('{}', { status: 429 })) as unknown as typeof fetch
    expect(await inspectUrl('tok', 'p', 'u', quota)).toEqual({ ok: false, code: 'http_429' })
  })
})

describe('the crawler\'s link graph and mentions (0074)', () => {
  const html = `<html><head><title>Lovkrav</title></head><body>
    <nav><a href="/">Orgpuls</a><a href="/pris">Priser</a> medarbeiderundersøkelse i menyen</nav>
    <main><p>Slik gjennomfører du en Medarbeiderundersøkelse som oppfyller lovkravet.</p>
      <a href="/artikler/mal?x=1#top"><span>Last ned</span> malen</a><a href="https://www.orgpuls.com/pris" aria-label="Se priser"><img alt=""></a>
      <a href="https://example.com/">ute</a><a href="mailto:x@y.no">post</a></main>
    <footer>verneombud plikter</footer><script>var t = "qps nordic"</script></body></html>`
  const url = new URL('https://www.orgpuls.com/lovkrav')
  it('the content text leaves out navigation, footer and scripts', () => {
    const t = contentText(html)
    expect(t).toContain('slik gjennomfører du en medarbeiderundersøkelse')
    expect(t).not.toContain('i menyen')
    expect(t).not.toContain('verneombud plikter')
    expect(t).not.toContain('qps nordic')
  })
  it('a term is mentioned as whole words only', () => {
    const t = contentText(html)
    expect(mentionsIn(t, ['Medarbeiderundersøkelse', 'undersøkelse', 'verneombud plikter', 'qps nordic', 'lovkravet'])).toEqual(['lovkravet', 'medarbeiderundersøkelse'])
  })
  it('each own-site link keeps its first anchor text, or its label', () => {
    expect(anchorsOf(html, url)).toEqual([
      { to: '/', text: 'Orgpuls' }, { to: '/pris', text: 'Priser' }, { to: '/artikler/mal?x=1', text: 'Last ned malen' },
    ])
    const labelled = anchorsOf('<a href="/pris" aria-label="Se priser"><img alt=""></a>', url)
    expect(labelled).toEqual([{ to: '/pris', text: 'Se priser' }])
  })
  it('pageFacts adds anchors and mentions only when asked for terms', () => {
    expect(pageFacts(html, url).anchors).toBeUndefined()
    expect(pageFacts(html, url, ['lovkravet']).mentions).toEqual(['lovkravet'])
  })
})

describe('the SEO alert email (0074)', () => {
  it('names the rule with its figures in the reader\'s language and links to the alerts', () => {
    const m = R.seoAlert({ lang: 'no', rule: 'rank', params: { query: 'verneombud plikter', from: 6.1, to: 9.4 }, site: 'orgpuls.com', at: '2026-10-11T05:00:00Z',
                            link: 'https://admin.example/growth?tab=seo&sub=alerts', fromName: 'Orgpuls' })
    expect(m.subject).toBe('SEO-varsel for orgpuls.com: «verneombud plikter» falt fra plass 6,1 til 9,4 i Google')
    expect(m.html).toContain('href="https://admin.example/growth?tab=seo&amp;sub=alerts"')
    const c = R.seoAlert({ lang: 'en', rule: 'cwv', params: { path: '/plattform', metric: 'inp', value: 340 }, site: 'orgpuls.com', at: '2026-10-11T05:00:00Z', link: null, fromName: 'Orgpuls' })
    expect(c.subject).toContain('/plattform responds slowly on mobile: INP 340 ms')
    expect(c.html).not.toContain('<script')
  })
})
