import { createHmac } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { commandClaims, isOrgpulsCommand, ORGPULS_COMMANDS } from '@/supabase/functions/_shared/orgpuls.ts'
import { hmacHex, signJwt, verifyWebhook } from '@/supabase/functions/_shared/signing.ts'

const SECRET = 'a'.repeat(64)
const body = JSON.stringify({ events: [{ id: 1, kind: 'org.created', org_id: 'x', payload: {}, created_at: '2026-10-05T00:00:00Z' }] })
const now = 1_790_000_000
// what Orgpuls' dispatcher sends (its orgpuls-dispatch/index.ts): sha256=<hex HMAC of "ts.body">
const sign = (ts: number, b = body) => `sha256=${createHmac('sha256', SECRET).update(`${ts}.${b}`).digest('hex')}`

describe('events in', () => {
  it('accepts what Orgpuls signs', async () => {
    expect(await verifyWebhook({ secret: SECRET, timestamp: String(now), signature: sign(now), body, nowSec: now + 10 })).toEqual({ ok: true })
    expect(await hmacHex(SECRET, `${now}.${body}`)).toBe(sign(now).slice(7))
  })

  it('refuses a changed body, another secret, an old or future timestamp and a missing header', async () => {
    const base = { secret: SECRET, timestamp: String(now), signature: sign(now), body, nowSec: now }
    expect(await verifyWebhook({ ...base, body: body.replace('org.created', 'org.deleted') })).toEqual({ ok: false, reason: 'signature' })
    expect(await verifyWebhook({ ...base, secret: 'b'.repeat(64) })).toEqual({ ok: false, reason: 'signature' })
    expect(await verifyWebhook({ ...base, nowSec: now + 301 })).toEqual({ ok: false, reason: 'stale' })
    expect(await verifyWebhook({ ...base, nowSec: now - 301 })).toEqual({ ok: false, reason: 'stale' })
    expect(await verifyWebhook({ ...base, signature: null })).toEqual({ ok: false, reason: 'missing' })
    expect(await verifyWebhook({ ...base, secret: '' })).toEqual({ ok: false, reason: 'missing' })
    expect(await verifyWebhook({ ...base, timestamp: 'soon' })).toEqual({ ok: false, reason: 'missing' })
  })
})

describe('commands out', () => {
  it('signs an HS256 token Orgpuls can verify, for one scope and two minutes', async () => {
    const claims = commandClaims('tor@example.com', 'billing.extend_trial', now, '0123456789abcdef')
    expect(claims).toEqual({ aud: 'orgpuls', sub: 'tor@example.com', scope: 'billing:write', jti: '0123456789abcdef', iat: now, exp: now + 120 })
    const jwt = await signJwt(claims, SECRET)
    const [h, b, s] = jwt.split('.')
    expect(JSON.parse(Buffer.from(h!, 'base64url').toString())).toEqual({ alg: 'HS256', typ: 'JWT' })
    expect(JSON.parse(Buffer.from(b!, 'base64url').toString())).toEqual(claims)
    expect(s).toBe(createHmac('sha256', SECRET).update(`${h}.${b}`).digest('base64url'))
  })

  it('knows only Orgpuls commands, each with a scope of the form Orgpuls checks', () => {
    expect(isOrgpulsCommand('orgs.list')).toBe(true)
    expect(isOrgpulsCommand('answers.export')).toBe(false)
    expect(isOrgpulsCommand('constructor')).toBe(false)
    for (const [command, scope] of Object.entries(ORGPULS_COMMANDS)) {
      expect(command).toMatch(/^[a-z]+\.[a-z_]+$/)
      expect(scope).toMatch(/^[a-z]+:(read|write)$/)
    }
  })
})
