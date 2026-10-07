import { afterEach, describe, expect, it, vi } from 'vitest'
import { originOf, report, sessionOf } from '@/lib/supabase/report'

const origin = { ip: null, city: null, country: null, userAgent: null }

// The middleware and the sign-in report through lib/supabase/report.ts (R-SECURITY-04)
describe('session reports', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.unstubAllEnvs()
  })

  it('reads the origin from Vercel\'s own headers, the first forwarded address and a decoded city', () => {
    const h = new Headers({ 'x-vercel-forwarded-for': '203.0.113.9, 10.0.0.1', 'x-vercel-ip-city': 'T%C3%B8nsberg', 'x-vercel-ip-country': 'NO', 'user-agent': 'UA' })
    expect(originOf(h)).toEqual({ ip: '203.0.113.9', city: 'Tønsberg', country: 'NO', userAgent: 'UA' })
    expect(originOf(new Headers({ 'x-vercel-ip-city': '%E0%A4%A' })).city).toBeNull()
  })

  it('takes the session id from an access token, and nothing from a broken one', () => {
    const payload = Buffer.from(JSON.stringify({ session_id: '7c1f4b5e-0000-4000-8000-000000000001', aal: 'aal2' })).toString('base64url')
    expect(sessionOf(`h.${payload}.s`)).toBe('7c1f4b5e-0000-4000-8000-000000000001')
    expect(sessionOf('not-a-token')).toBeNull()
  })

  it('never reports a failed password without the report key, and sends the key when it has one', async () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://example.supabase.co')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', 'anon')
    vi.stubEnv('SESSION_REPORT_KEY', '')
    const fetch = vi.fn(async () => new Response(JSON.stringify({ ok: false, reason: 'failed_password', must_change_password: false })))
    vi.stubGlobal('fetch', fetch)
    expect(await report({ kind: 'login', outcome: 'failed_password', email: 'a@b.no', origin, device: null })).toBeNull()
    expect(fetch).not.toHaveBeenCalled()

    vi.stubEnv('SESSION_REPORT_KEY', 'k'.repeat(40))
    expect(await report({ kind: 'login', outcome: 'failed_password', email: 'a@b.no', origin, device: null })).toEqual({ ok: false, reason: 'failed_password', must_change_password: false })
    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('https://example.supabase.co/functions/v1/session-report')
    expect((init.headers as Record<string, string>)['x-report-key']).toBe('k'.repeat(40))
    expect((init.headers as Record<string, string>).authorization).toBeUndefined()
  })

  it('answers null when the function cannot be reached or answers something else, so the caller carries on', async () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://example.supabase.co')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', 'anon')
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('down') }))
    expect(await report({ kind: 'seen', token: 't', origin, device: null })).toBeNull()
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{"error":"unauthorized"}', { status: 401 })))
    expect(await report({ kind: 'seen', token: 't', origin, device: null })).toBeNull()
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{"ok":"yes"}')))
    expect(await report({ kind: 'seen', token: 't', origin, device: null })).toBeNull()
  })
})
