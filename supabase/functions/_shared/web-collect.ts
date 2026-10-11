/**
 * The website tracker's rules (0066), pure so the edge function (Deno) and the tests (Node) run the same code: which
 * site an origin belongs to, which requests are bots, which paths must never be recorded, what a beacon may say, and
 * the visitor hash. The hash is SHA-256 of the day's salt, the site, the address and the browser string, cut to 128
 * bits; neither the address nor the browser string goes any further than this function.
 */
import { toHex } from './signing.ts'

/** a page that carries a capability token (a respondent's or member's link, a results page, a QR entry) or is not the site */
const NEVER = /^\/(s|bli-med|r|inn|auth|admin|api|logg-inn|nytt-passord)(\/|$)/
const BOT = /(bot|crawl|spider|slurp|headless|lighthouse|pagespeed|preview|facebookexternalhit|embedly|curl|wget|python|axios|node-fetch|undici|go-http|java\/|okhttp|monitor|pingdom|uptime|scan|httpclient|phantom|selenium|playwright|puppeteer)/i
const UTM_KEYS = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content'] as const
// signup_step and signup_error say where the signup form was left (a step's key, an error's code, never a typed value);
// persona_click is a press on one of the «Who are you?» cards (0068)
const EVENTS = new Set(['cta', 'signup_started', 'signup_completed', 'pricing_viewed', 'signup_step', 'signup_error', 'persona_click'])
export type Device = 'mobile' | 'tablet' | 'desktop'

export type Beacon = { k: 'view' | 'event'; p: string; r?: string; u?: Record<string, string>; e?: string; l?: string }

/** the registered site an origin belongs to: the host itself, without www., or the site it is a subdomain of */
export function siteFor(origin: string | null, sites: string[]): string | null {
  if (!origin) return null
  let host: string
  try {
    const u = new URL(origin)
    if (u.protocol !== 'https:' && u.hostname !== 'localhost') return null
    host = u.hostname.toLowerCase()
  } catch {
    return null
  }
  const bare = host.replace(/^www\./, '')
  if (sites.includes(host)) return host
  if (sites.includes(bare)) return bare
  return sites.filter((s) => bare.endsWith(`.${s}`)).sort((a, b) => b.length - a.length)[0] ?? null
}

export const isBot = (ua: string | null) => !ua || ua.length < 12 || BOT.test(ua)

export function parseBeacon(text: string): Beacon | null {
  if (text.length > 2000) return null
  let j: Record<string, unknown>
  try {
    j = JSON.parse(text)
  } catch {
    return null
  }
  if (!j || typeof j !== 'object') return null
  const k = j.k === 'cta' ? 'event' : j.k
  if (k !== 'view' && k !== 'event') return null
  const p = typeof j.p === 'string' ? j.p.split(/[?#]/)[0]!.slice(0, 200) : ''
  if (!p.startsWith('/') || NEVER.test(p)) return null
  const out: Beacon = { k, p }
  if (typeof j.r === 'string' && /^[a-z0-9.-]{1,253}$/i.test(j.r)) out.r = j.r.toLowerCase()
  if (j.u && typeof j.u === 'object') {
    const u: Record<string, string> = {}
    for (const key of UTM_KEYS) {
      const v = (j.u as Record<string, unknown>)[key]
      if (typeof v === 'string' && v.trim()) u[key] = v.trim().slice(0, 80)
    }
    if (Object.keys(u).length) out.u = u
  }
  if (k === 'event') {
    const e = j.k === 'cta' ? 'cta' : j.e
    if (typeof e !== 'string' || !EVENTS.has(e)) return null
    out.e = e
    if (typeof j.l === 'string' && /^[a-z0-9_-]{1,40}$/i.test(j.l)) out.l = j.l
  }
  return out
}

export async function visitorHash(salt: string, site: string, ip: string, ua: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${salt}|${site}|${ip}|${ua}`))
  return toHex(new Uint8Array(d)).slice(0, 32)
}

/** the device class read from the browser string before it is hashed (0068); the string itself goes no further */
export function deviceOf(ua: string | null): Device | null {
  if (!ua) return null
  if (/ipad|tablet|kindle|silk|playbook|(android(?!.*mobile))/i.test(ua)) return 'tablet'
  if (/mobi|iphone|ipod|android|windows phone|blackberry|opera mini/i.test(ua)) return 'mobile'
  return 'desktop'
}

/** the item worker_web_track takes */
export function item(b: Beacon, site: string, hash: string, device: Device | null = null) {
  return {
    site, visitor_hash: hash, path: b.p, ...(b.r ? { referrer_host: b.r } : {}), utm: b.u ?? {}, ...(device ? { device } : {}),
    ...(b.k === 'event' ? { event: { name: b.e, ...(b.l ? { value: b.l } : {}) } } : {}),
  }
}
