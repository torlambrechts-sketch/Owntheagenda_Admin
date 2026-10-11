import { describe, expect, it } from 'vitest'
import { SLOW_MS, brokenLinks, decode, issuesFrom, pageFacts, sitemapUrls, type PageFacts } from '../supabase/functions/_shared/seo-crawl'

const page = (path: string, p: Partial<PageFacts> = {}): PageFacts => ({
  path, status: 200, ms: 400, html: true, title: `T ${path}`, description: `D ${path}`, h1: 1, noindex: false, links: [], ...p,
})

describe('seo-crawl (0072)', () => {
  it('reads a sitemap and a sitemap index', () => {
    expect(sitemapUrls('<urlset><url><loc>https://www.orgpuls.com/</loc></url><url><loc> https://www.orgpuls.com/priser </loc><lastmod>x</lastmod></url></urlset>'))
      .toEqual({ pages: ['https://www.orgpuls.com/', 'https://www.orgpuls.com/priser'], sitemaps: [] })
    expect(sitemapUrls('<sitemapindex><sitemap><loc>https://www.orgpuls.com/sitemap-1.xml</loc></sitemap></sitemapindex>'))
      .toEqual({ pages: [], sitemaps: ['https://www.orgpuls.com/sitemap-1.xml'] })
  })

  it('reads what a search engine reads first, and only the site\'s own links', () => {
    const html = `<html><head><title> Orgpuls &amp; arbeidsmiljø </title>
      <meta content="Kartlegging &#8211; enkelt" name="description"><meta name="robots" content="index,follow"></head>
      <body><h1>A</h1><a href="/priser">p</a><a href='https://orgpuls.com/demo#x'>d</a><a href="https://www.linkedin.com/x">l</a>
      <a href="mailto:x@y.no">m</a><a href="#top">t</a><a href="artikler?a=1">r</a></body></html>`
    const f = pageFacts(html, new URL('https://www.orgpuls.com/'))
    expect(f.title).toBe('Orgpuls & arbeidsmiljø')
    expect(f.description).toBe('Kartlegging – enkelt')
    expect(f.h1).toBe(1)
    expect(f.noindex).toBe(false)
    expect(f.links.sort()).toEqual(['/artikler?a=1', '/demo', '/priser'])
    expect(pageFacts('<meta name="robots" content="noindex">', new URL('https://www.orgpuls.com/x')).noindex).toBe(true)
    expect(pageFacts('<p>no head</p>', new URL('https://www.orgpuls.com/x'))).toMatchObject({ title: null, description: null, h1: 0 })
    expect(decode('a&nbsp; b&#x27;s')).toBe("a b's")
  })

  it('turns pages into one issue per kind, most serious first, naming at most five paths', () => {
    const pages = [
      page('/'),
      page('/pris', { description: null }), page('/kom-i-gang', { description: null }), page('/bygg', { description: null }),
      page('/plattform', { ms: SLOW_MS + 1100 }),
      page('/artikler/a', { title: 'Orgpuls — artikler', h1: 0 }), page('/artikler/b', { title: 'Orgpuls — artikler' }),
      page('/gammel-side', { status: 404 }),
      page('/utkast', { noindex: true, description: null }),
    ]
    const issues = issuesFrom(pages, [{ path: '/borte', status: 404, from: ['/artikler/a'] }], true)
    expect(issues.map((i) => i.kind)).toEqual(['page_error', 'noindex', 'missing_description', 'slow_page', 'duplicate_title', 'missing_h1', 'broken_link'])
    expect(issues.find((i) => i.kind === 'missing_description')).toMatchObject({ severity: 'high', count: 3, paths: ['/bygg', '/kom-i-gang', '/pris'] })
    expect(issues.find((i) => i.kind === 'slow_page')).toMatchObject({ count: 1, paths: ['/plattform'], ms: SLOW_MS + 1100 })
    expect(issues.find((i) => i.kind === 'duplicate_title')).toMatchObject({ severity: 'medium', count: 2, value: 'Orgpuls — artikler' })
    expect(issues.find((i) => i.kind === 'broken_link')).toMatchObject({ count: 1, paths: ['/borte'], value: '/artikler/a' })
    // a noindexed page is not also counted for what an indexed page needs
    expect(issues.find((i) => i.kind === 'missing_description')!.paths).not.toContain('/utkast')
    const many = Array.from({ length: 8 }, (_, i) => page(`/p${i}`, { description: null }))
    expect(issuesFrom(many, [], true)[0]).toMatchObject({ count: 8, paths: ['/p0', '/p1', '/p2', '/p3', '/p4'] })
    expect(issuesFrom([page('/')], [], false)).toEqual([{ kind: 'sitemap_missing', severity: 'high', count: 1, paths: ['/sitemap.xml'] }])
    expect(issuesFrom([page('/')], [], true)).toEqual([])
  })

  it('finds the links that answer 4xx or 5xx, with the pages that make them', () => {
    const pages = [page('/', { links: ['/a', '/borte'] }), page('/a', { links: ['/borte', '/feil'] })]
    const status = new Map([['/', 200], ['/a', 200], ['/borte', 404], ['/feil', 500]])
    expect(brokenLinks(pages, status)).toEqual([
      { path: '/borte', status: 404, from: ['/', '/a'] },
      { path: '/feil', status: 500, from: ['/a'] },
    ])
  })
})
