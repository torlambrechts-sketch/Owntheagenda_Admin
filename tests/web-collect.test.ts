import { describe, expect, it } from 'vitest'
import { isBot, item, parseBeacon, siteFor, visitorHash } from '../supabase/functions/_shared/web-collect'

describe('web-collect (0066)', () => {
  const sites = ['orgpuls.com', 'www.owntheagenda.com']
  it('reads only an origin that belongs to a registered site', () => {
    expect(siteFor('https://www.orgpuls.com', sites)).toBe('orgpuls.com')
    expect(siteFor('https://en.orgpuls.com', sites)).toBe('orgpuls.com')
    expect(siteFor('https://orgpuls.com', sites)).toBe('orgpuls.com')
    expect(siteFor('https://notorgpuls.com', sites)).toBeNull()
    expect(siteFor('http://www.orgpuls.com', sites)).toBeNull()
    expect(siteFor(null, sites)).toBeNull()
  })
  it('drops bots and empty browser strings', () => {
    expect(isBot('Mozilla/5.0 (compatible; Googlebot/2.1)')).toBe(true)
    expect(isBot('Mozilla/5.0 HeadlessChrome/120')).toBe(true)
    expect(isBot(null)).toBe(true)
    expect(isBot('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15')).toBe(false)
  })
  it('never records a page that carries a capability token', () => {
    for (const p of ['/s/abcdef', '/bli-med/tok', '/r/slug', '/inn/123456', '/auth/callback', '/api/x']) {
      expect(parseBeacon(JSON.stringify({ k: 'view', p }))).toBeNull()
    }
    expect(parseBeacon(JSON.stringify({ k: 'view', p: '/priser?orgnr=123#x' }))).toEqual({ k: 'view', p: '/priser' })
  })
  it('keeps only the five utm keys, a host as referrer, and known events', () => {
    const b = parseBeacon(JSON.stringify({ k: 'view', p: '/', r: 'Google.com', u: { utm_source: 'li', email: 'a@b.no' } }))
    expect(b).toEqual({ k: 'view', p: '/', r: 'google.com', u: { utm_source: 'li' } })
    expect(parseBeacon(JSON.stringify({ k: 'cta', p: '/', l: 'kom-i-gang' }))).toEqual({ k: 'event', p: '/', e: 'cta', l: 'kom-i-gang' })
    expect(parseBeacon(JSON.stringify({ k: 'event', p: '/registrer', e: 'signup_started' }))).toEqual({ k: 'event', p: '/registrer', e: 'signup_started' })
    expect(parseBeacon(JSON.stringify({ k: 'event', p: '/', e: 'anything_else' }))).toBeNull()
    expect(parseBeacon('x'.repeat(2001))).toBeNull()
  })
  it('hashes to 128 bits that change with the salt, and the item carries no address', async () => {
    const a = await visitorHash('salt1', 'orgpuls.com', '203.0.113.7', 'UA')
    const b = await visitorHash('salt2', 'orgpuls.com', '203.0.113.7', 'UA')
    expect(a).toMatch(/^[0-9a-f]{32}$/)
    expect(a).not.toBe(b)
    const it2 = item({ k: 'view', p: '/' }, 'orgpuls.com', a)
    expect(JSON.stringify(it2)).not.toContain('203.0.113.7')
    expect(it2).toEqual({ site: 'orgpuls.com', visitor_hash: a, path: '/', utm: {} })
  })
})
