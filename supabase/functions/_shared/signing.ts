/**
 * The two signatures between the platform and a product, in Web Crypto so the edge functions (Deno)
 * and the tests (Node) run the same code.
 *
 *   events in    the product POSTs `{"events": [...]}` with `x-orgpuls-timestamp` (unix seconds) and
 *                `x-orgpuls-signature: sha256=<hex HMAC-SHA256 of "<timestamp>.<body>">` under the
 *                product's webhook secret. Older than five minutes, or from the future, is refused.
 *   commands out an HS256 JWT under the product's token secret: audience, the admin, the one scope the
 *                command needs, a unique id, and at most five minutes of life (Orgpuls 0205 checks all
 *                of it, and refuses an id it has seen).
 */
const enc = new TextEncoder()

export const toHex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')

export const toBase64Url = (bytes: Uint8Array) => {
  let s = ''
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function hmac(secret: string, message: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(message)))
}

export async function hmacHex(secret: string, message: string): Promise<string> {
  return toHex(await hmac(secret, message))
}

/** equal strings in time that does not depend on where they first differ */
export function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

export type WebhookCheck = { ok: true } | { ok: false; reason: 'missing' | 'stale' | 'signature' }

export async function verifyWebhook(input: {
  secret: string
  timestamp: string | null
  signature: string | null
  body: string
  nowSec: number
  toleranceSec?: number
}): Promise<WebhookCheck> {
  const { secret, timestamp, signature, body, nowSec } = input
  const tolerance = input.toleranceSec ?? 300
  if (!secret || !timestamp || !signature || !/^\d{1,12}$/.test(timestamp) || !signature.startsWith('sha256=')) {
    return { ok: false, reason: 'missing' }
  }
  const ts = Number(timestamp)
  if (Math.abs(nowSec - ts) > tolerance) return { ok: false, reason: 'stale' }
  const expected = await hmacHex(secret, `${timestamp}.${body}`)
  return sameText(signature.slice('sha256='.length).toLowerCase(), expected) ? { ok: true } : { ok: false, reason: 'signature' }
}

export type CommandClaims = { aud: string; sub: string; scope: string; jti: string; iat: number; exp: number }

export async function signJwt(claims: CommandClaims, secret: string): Promise<string> {
  const head = toBase64Url(enc.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })))
  const body = toBase64Url(enc.encode(JSON.stringify(claims)))
  const sig = toBase64Url(await hmac(secret, `${head}.${body}`))
  return `${head}.${body}.${sig}`
}
