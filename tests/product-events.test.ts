import { createHmac } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { claimedProduct, readBatch } from '../supabase/functions/_shared/product-events'
import { verifyWebhook } from '../supabase/functions/_shared/signing'

/**
 * product-events (0090): one door for every product, signed per product. LeaderPact signs with Node's crypto
 * (its lib/platform/sentral.ts); the function checks with Web Crypto; both must agree on the same bytes.
 */
describe('product-events (0090)', () => {
  it("takes a product key of the registry's shape from the header, nothing else", () => {
    expect(claimedProduct('leaderpact')).toBe('leaderpact')
    for (const bad of [null, '', 'LeaderPact', 'x', 'leader-pact', 'leaderpact; drop', 'a'.repeat(40)]) expect(claimedProduct(bad)).toBeNull()
  })

  it('reads a batch only when the body names the product the header did', () => {
    const body = JSON.stringify({ product: 'leaderpact', events: [{ id: '1', kind: 'content.inventory', payload: {} }] })
    expect(readBatch(body, 'leaderpact')).toEqual({ ok: true, product: 'leaderpact', events: [{ id: '1', kind: 'content.inventory', payload: {} }] })
    expect(readBatch(body, 'orgpuls')).toEqual({ ok: false, error: 'product' })
    expect(readBatch('{"events": []}', 'leaderpact')).toEqual({ ok: false, error: 'product' })
    expect(readBatch('not json', 'leaderpact')).toEqual({ ok: false, error: 'body' })
    expect(readBatch(JSON.stringify({ product: 'leaderpact', events: {} }), 'leaderpact')).toEqual({ ok: false, error: 'body' })
    expect(readBatch(JSON.stringify({ product: 'leaderpact', events: Array(501).fill({}) }), 'leaderpact')).toEqual({ ok: false, error: 'body' })
  })

  it("verifies a signature made the way LeaderPact makes it, and refuses it under another product's secret", async () => {
    const secret = 'leaderpact-test-secret-of-at-least-32-chars'
    const body = JSON.stringify({ product: 'leaderpact', events: [] })
    const ts = String(Math.floor(Date.now() / 1000))
    const signature = `sha256=${createHmac('sha256', secret).update(`${ts}.${body}`).digest('hex')}`
    const nowSec = Number(ts)
    expect(await verifyWebhook({ secret, timestamp: ts, signature, body, nowSec })).toEqual({ ok: true })
    expect(await verifyWebhook({ secret: 'orgpuls-test-secret-of-at-least-32-characters', timestamp: ts, signature, body, nowSec })).toEqual({
      ok: false,
      reason: 'signature',
    })
    expect(await verifyWebhook({ secret, timestamp: ts, signature, body, nowSec: nowSec + 301 })).toEqual({ ok: false, reason: 'stale' })
  })
})
