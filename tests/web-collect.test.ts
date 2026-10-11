import { describe, expect, it } from 'vitest'
import { deviceOf, isBot, item, parseBeacon, siteFor, visitorHash } from '../supabase/functions/_shared/web-collect'

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
  it('takes the signup form\'s steps and errors and the persona cards as codes, never a typed value (0068)', () => {
    expect(parseBeacon(JSON.stringify({ k: 'event', p: '/registrer', e: 'signup_step', l: 'step2' }))).toEqual({ k: 'event', p: '/registrer', e: 'signup_step', l: 'step2' })
    expect(parseBeacon(JSON.stringify({ k: 'event', p: '/registrer', e: 'signup_error', l: 'lookup_not_found' }))).toEqual({ k: 'event', p: '/registrer', e: 'signup_error', l: 'lookup_not_found' })
    expect(parseBeacon(JSON.stringify({ k: 'event', p: '/', e: 'persona_click', l: 'verneombud' }))).toEqual({ k: 'event', p: '/', e: 'persona_click', l: 'verneombud' })
    // an organisation number or an address typed into the form is not a code and is not kept
    expect(parseBeacon(JSON.stringify({ k: 'event', p: '/registrer', e: 'signup_error', l: 'ola@firma.no' }))).toEqual({ k: 'event', p: '/registrer', e: 'signup_error' })
    expect(parseBeacon(JSON.stringify({ k: 'event', p: '/registrer', e: 'signup_error', l: '923 456 789' }))).toEqual({ k: 'event', p: '/registrer', e: 'signup_error' })
  })
  it('reads only the device class from the browser string (0068)', () => {
    expect(deviceOf('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148')).toBe('mobile')
    expect(deviceOf('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36')).toBe('mobile')
    expect(deviceOf('Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15')).toBe('tablet')
    expect(deviceOf('Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 Chrome/120 Safari/537.36')).toBe('tablet')
    expect(deviceOf('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36')).toBe('desktop')
    expect(deviceOf(null)).toBeNull()
    const it3 = item({ k: 'view', p: '/' }, 'orgpuls.com', 'ab'.repeat(16), 'mobile')
    expect(it3).toEqual({ site: 'orgpuls.com', visitor_hash: 'ab'.repeat(16), path: '/', utm: {}, device: 'mobile' })
  })
})
