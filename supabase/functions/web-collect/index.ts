/**
 * web-collect — the application's public site counts its own visits in Sentral (0066). The browser posts a small
 * beacon (text/plain, so no preflight) for a page view or a press; this answers 204 whatever happens, since a beacon
 * has nobody to tell and a different answer would tell a prober what was kept.
 *
 * Only an origin that belongs to a registered site is read. Bots, a browser that asks not to be tracked (the site does
 * not send then), and every page that carries a capability token are dropped. The address and the browser string are
 * hashed with the day's salt and go no further (the device class, mobile, tablet or desktop, is read from the browser
 * string first, 0068); the host the origin names is kept beside its site (0070); logs carry counts only.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { deviceOf, hostOf, isBot, item, parseBeacon, siteFor, visitorHash } from '../_shared/web-collect.ts'

const log = (s: string) => console.log(`[web-collect] ${s}`)
let sites: { at: number; list: string[] } | null = null
let salt: { day: string; value: string } | null = null

const reply = (origin: string | null) => new Response(null, {
  status: 204,
  headers: {
    ...(origin ? { 'access-control-allow-origin': origin, vary: 'origin' } : {}),
    'access-control-allow-methods': 'POST', 'access-control-allow-headers': 'content-type', 'access-control-max-age': '86400',
  },
})

async function knownSites(svc: SupabaseClient): Promise<string[]> {
  if (sites && Date.now() - sites.at < 300_000) return sites.list
  const { data, error } = await svc.rpc('worker_web_sites')
  const list = !error && Array.isArray(data) ? (data as unknown[]).filter((s): s is string => typeof s === 'string') : []
  sites = { at: Date.now(), list }
  return list
}

async function todaysSalt(svc: SupabaseClient): Promise<string> {
  const day = new Date().toISOString().slice(0, 10)
  if (salt?.day === day) return salt.value
  const { data, error } = await svc.rpc('worker_web_salt')
  if (error || typeof data !== 'string' || !data) return ''
  salt = { day, value: data }
  return data
}

Deno.serve(async (req) => {
  const origin = req.headers.get('origin')
  if (req.method === 'OPTIONS') return reply(origin)
  if (req.method !== 'POST') return new Response(null, { status: 405 })
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!url || !key) return reply(null)
  const svc = createClient(url, key, { auth: { persistSession: false } })

  const site = siteFor(origin, await knownSites(svc))
  if (!site) return reply(null)
  const ua = req.headers.get('user-agent')
  if (isBot(ua)) return reply(origin)
  const beacon = parseBeacon(await req.text().catch(() => ''))
  if (!beacon) return reply(origin)
  const s = await todaysSalt(svc)
  if (!s) { log('no salt'); return reply(origin) }
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0]?.trim() || req.headers.get('x-real-ip') || ''
  const hash = await visitorHash(s, site, ip, ua ?? '')
  const { error } = await svc.rpc('worker_web_track', { p_item: item(beacon, site, hash, deviceOf(ua), hostOf(origin)) })
  if (error) log(`refused ${error.code ?? ''}`.trim())
  return reply(origin)
})
