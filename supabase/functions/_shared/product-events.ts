/**
 * What product-events reads from a signed batch (0090), in plain TypeScript so the edge function (Deno) and
 * the tests (Node) run the same code.
 *
 * The product is named twice: in `x-platform-product`, which picks the secret the signature is checked with,
 * and in the body's `product`, which the signature covers. They must agree, so a valid signature for one
 * product can never be replayed as another's.
 */
export const PRODUCT_KEY = /^[a-z][a-z0-9_]{1,30}$/

export type Batch = { ok: true; product: string; events: unknown[] } | { ok: false; error: 'product' | 'body' }

/** The product a request claims, before its signature is checked: a key of the right shape, or null */
export const claimedProduct = (header: string | null): string | null => (header && PRODUCT_KEY.test(header) ? header : null)

/** The signed body, once the signature holds: `{"product": <the header's product>, "events": [...]}`, at most 500 events */
export function readBatch(body: string, product: string): Batch {
  let parsed: unknown
  try {
    parsed = JSON.parse(body)
  } catch {
    return { ok: false, error: 'body' }
  }
  if (!parsed || typeof parsed !== 'object') return { ok: false, error: 'body' }
  const b = parsed as { product?: unknown; events?: unknown }
  if (b.product !== product) return { ok: false, error: 'product' }
  if (!Array.isArray(b.events) || b.events.length > 500) return { ok: false, error: 'body' }
  return { ok: true, product, events: b.events }
}
