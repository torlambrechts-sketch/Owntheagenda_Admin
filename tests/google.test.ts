import { webcrypto } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { accessToken, pageFilter, pagePath, parseKey, propertyFor, searchAnalytics, serviceJwt, windows } from '../supabase/functions/_shared/google'

const subtle = webcrypto.subtle
async function testKey() {
  const pair = await subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify'])
  const der = Buffer.from(await subtle.exportKey('pkcs8', pair.privateKey)).toString('base64')
  const pem = `-----BEGIN PRIVATE KEY-----\n${der.match(/.{1,64}/g)!.join('\n')}\n-----END PRIVATE KEY-----\n`
  const raw = JSON.stringify({ type: 'service_account', client_email: 'seo@p.iam.gserviceaccount.com', private_key: pem, token_uri: 'https://oauth2.googleapis.com/token' })
  return { raw, pub: pair.publicKey }
}
const b64url = (s: string) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64')

describe('Google service account (0064)', () => {
  it('reads only a service account key', () => {
    expect(parseKey('{"type":"authorized_user"}')).toBeNull()
    expect(parseKey('not json')).toBeNull()
    expect(parseKey(JSON.stringify({ type: 'service_account', client_email: 'a@b', private_key: 'x' }))).toBeNull()
  })
  it('signs an RS256 assertion Google can verify with the account\'s public key', async () => {
    const { raw, pub } = await testKey()
    const key = parseKey(raw)!
    const jwt = await serviceJwt(key, 'https://www.googleapis.com/auth/webmasters.readonly', 1_760_000_000)
    const [h, b, s] = jwt.split('.') as [string, string, string]
    expect(JSON.parse(b64url(h).toString())).toEqual({ alg: 'RS256', typ: 'JWT' })
    expect(JSON.parse(b64url(b).toString())).toMatchObject({ iss: 'seo@p.iam.gserviceaccount.com', aud: 'https://oauth2.googleapis.com/token', iat: 1_760_000_000, exp: 1_760_003_600 })
    expect(await subtle.verify('RSASSA-PKCS1-v1_5', pub, b64url(s), new TextEncoder().encode(`${h}.${b}`))).toBe(true)
  })
  it('a refused sign-in is a code, never Google\'s words', async () => {
    const { raw } = await testKey()
    const f = (async () => new Response('{"error":"invalid_grant","error_description":"Invalid JWT for seo@p"}', { status: 400 })) as typeof fetch
    expect(await accessToken(parseKey(raw)!, f)).toEqual({ ok: false, code: 'token_400' })
  })
})

describe('Search Console properties and figures (0064)', () => {
  const sites = (...u: string[]) => u.map((siteUrl) => ({ siteUrl, permissionLevel: 'siteFullUser' }))
  it('finds the property that covers a site: domain first, then the exact address, then its www twin', () => {
    expect(propertyFor('orgpuls.com', sites('https://orgpuls.com/', 'sc-domain:orgpuls.com'))).toBe('sc-domain:orgpuls.com')
    expect(propertyFor('en.orgpuls.com', sites('sc-domain:orgpuls.com'))).toBe('sc-domain:orgpuls.com')
    expect(propertyFor('orgpuls.com', sites('https://www.orgpuls.com/'))).toBe('https://www.orgpuls.com/')
    expect(propertyFor('www.owntheagenda.com', sites('https://owntheagenda.com/'))).toBe('https://owntheagenda.com/')
    expect(propertyFor('orgpuls.com', sites('sc-domain:notorgpuls.com', 'https://other.example/'))).toBeNull()
  })
  it('reads rows by day and by day and query, keeping counts and positions only', async () => {
    let asked: Record<string, unknown> = {}
    const f = (async (_u: unknown, init?: RequestInit) => {
      asked = JSON.parse(String(init?.body))
      return new Response(JSON.stringify({ rows: [
        { keys: ['2026-10-01', 'arbeidsmiljø'], impressions: 10, clicks: 2, ctr: 0.2, position: 3.4 },
        { keys: ['2026-10-01', ''], impressions: 5, clicks: 0, position: 9 },
        { keys: ['not a day', 'x'], impressions: 1, clicks: 1, position: 1 },
      ] }), { status: 200 })
    }) as typeof fetch
    const r = await searchAnalytics('t', 'sc-domain:orgpuls.com', '2026-10-01', '2026-10-01', 'query', f)
    expect(asked).toMatchObject({ dimensions: ['date', 'query'], rowLimit: 25000, startRow: 0 })
    expect(r).toEqual({ ok: true, capped: false, rows: [{ day: '2026-10-01', query: 'arbeidsmiljø', impressions: 10, clicks: 2, position: 3.4 }] })
    const refused = await searchAnalytics('t', 'sc-domain:orgpuls.com', '2026-10-01', '2026-10-01', 'day', (async () => new Response('{"error":{"message":"User does not have sufficient permission"}}', { status: 403 })) as typeof fetch)
    expect(refused).toEqual({ ok: false, code: 'http_403' })
  })
  it('reads day × query × page rows with the page as its path, never the host (0072)', async () => {
    let asked: Record<string, unknown> = {}
    const f = (async (_u: unknown, init?: RequestInit) => {
      asked = JSON.parse(String(init?.body))
      return new Response(JSON.stringify({ rows: [
        { keys: ['2026-10-01', 'anonym medarbeiderundersøkelse', 'https://www.orgpuls.com/artikler/anonym-medarbeiderundersokelse'], impressions: 8, clicks: 0, position: 15.6 },
        { keys: ['2026-10-01', 'x', 'not a url'], impressions: 1, clicks: 0, position: 3 },
      ] }), { status: 200 })
    }) as typeof fetch
    const r = await searchAnalytics('t', 'sc-domain:orgpuls.com', '2026-10-01', '2026-10-01', 'page', f)
    expect(asked).toMatchObject({ dimensions: ['date', 'query', 'page'] })
    expect(r).toEqual({ ok: true, capped: false, rows: [{ day: '2026-10-01', query: 'anonym medarbeiderundersøkelse', page: '/artikler/anonym-medarbeiderundersokelse', impressions: 8, clicks: 0, position: 15.6 }] })
    expect(pagePath('https://www.orgpuls.com/')).toBe('/')
    expect(pagePath('https://se.orgpuls.com/priser?x=1')).toBe('/priser?x=1')
    expect(pagePath('javascript:alert(1)')).toBeNull()
  })
  it('splits a period into windows, oldest first', () => {
    expect(windows('2026-01-01', '2026-03-05', 30)).toEqual([
      { from: '2026-01-01', to: '2026-01-30' }, { from: '2026-01-31', to: '2026-03-01' }, { from: '2026-03-02', to: '2026-03-05' },
    ])
    expect(windows('2026-01-02', '2026-01-01', 30)).toEqual([])
  })
})

describe('one site\'s pages in a shared property (0089)', () => {
  const re = (x: string) => new RegExp(x)
  it('keeps the site\'s hosts and their subdomains, and leaves out the other sites inside them', () => {
    const f = pageFilter(['orgpuls.com'], ['se.orgpuls.com'])!
    const keep = (u: string) => re(f.include).test(u) && !f.exclude.some((x) => re(x).test(u))
    expect(keep('https://www.orgpuls.com/priser')).toBe(true)
    expect(keep('https://orgpuls.com/')).toBe(true)
    expect(keep('https://en.orgpuls.com/pricing')).toBe(true)
    expect(keep('https://se.orgpuls.com/registrera')).toBe(false)
    expect(keep('https://www.empvibe.com/')).toBe(false)
    expect(keep('https://evilorgpuls.com/')).toBe(false)
    expect(keep('https://orgpuls.com.example.net/')).toBe(false)
  })
  it('reads a www host as its domain, ignores what is not a host, and keeps nothing without one', () => {
    expect(pageFilter(['www.empvibe.com'], [])!.include).toBe(pageFilter(['empvibe.com'], [])!.include)
    expect(pageFilter(['bad host', 42, '..'], [])).toBeNull()
    expect(pageFilter(null, null)).toBeNull()
  })
  it('asks Google for those pages only', async () => {
    let body: Record<string, unknown> = {}
    const f = (async (_u: string, init?: RequestInit) => {
      body = JSON.parse(String(init?.body))
      return new Response('{"rows":[]}', { status: 200 })
    }) as typeof fetch
    await searchAnalytics('t', 'sc-domain:orgpuls.com', '2026-10-01', '2026-10-01', 'day', f, pageFilter(['orgpuls.com'], ['se.orgpuls.com']))
    expect(body.dimensionFilterGroups).toEqual([{ groupType: 'and', filters: [
      { dimension: 'page', operator: 'includingRegex', expression: '^https?://([a-z0-9-]+\\.)*(orgpuls\\.com)/' },
      { dimension: 'page', operator: 'excludingRegex', expression: '^https?://([a-z0-9-]+\\.)*(se\\.orgpuls\\.com)/' },
    ] }])
    await searchAnalytics('t', 'sc-domain:orgpuls.com', '2026-10-01', '2026-10-01', 'day', f)
    expect(body.dimensionFilterGroups).toBeUndefined()
  })
})
