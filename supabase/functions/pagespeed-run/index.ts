/**
 * pagespeed-run — Core Web Vitals for Growth › Pages and links and Technical SEO (0073). Asks PageSpeed Insights, with the
 * owner's Google API key from Vault, about each application site's most visited landing pages (and its home page), and
 * hands LCP, INP, CLS and the performance score to worker_pagespeed_result. The nightly job knocks with the worker key;
 * a person who may manage the site («Measure now») with their own token (pagespeed_check_ready).
 *
 * Logs carry counts and status codes, never an address or the key.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { sameText } from '../_shared/signing.ts'
import { psiUrl, refusalOf, vitalsOf, type Vitals } from '../_shared/pagespeed.ts'

const log = (s: string) => console.log(`[pagespeed-run] ${s}`)
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } })
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const BUDGET_MS = 140_000

async function secret(svc: SupabaseClient, name: string): Promise<string> {
  const { data, error } = await svc.rpc('product_secret', { p_name: name })
  return !error && typeof data === 'string' ? data : ''
}

/** one page: its vitals, or why Google would not say */
async function measure(url: string, key: string): Promise<{ v: Vitals | null; code: string | null }> {
  try {
    const res = await fetch(psiUrl(url, key, 'mobile'), { signal: AbortSignal.timeout(60_000) })
    const body = await res.json().catch(() => null)
    if (!res.ok) return { v: null, code: refusalOf(res.status, body) }
    const v = vitalsOf(body)
    return { v, code: v ? null : 'no_reading' }
  } catch {
    return { v: null, code: 'timeout' }
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 503)
  let body: { site?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 1_000) return json({ error: 'too_large' }, 413)
    body = raw ? JSON.parse(raw) : {}
  } catch {
    return json({ error: 'body' }, 400)
  }
  const only = typeof body.site === 'string' && UUID.test(body.site) ? body.site : null
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })

  const offered = req.headers.get('x-worker-key') ?? ''
  if (offered) {
    const key = await secret(svc, 'pagespeed_worker_secret')
    if (!key || !sameText(offered, key)) return json({ error: 'not_allowed' }, 403)
  } else {
    const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
    if (!token || token === serviceKey || !anonKey) return json({ error: 'unauthorized' }, 401)
    const asUser = createClient(url, anonKey, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } })
    const { data, error } = await asUser.rpc('pagespeed_check_ready')
    const d = data as { me?: string } | null
    if (error || !d?.me || !UUID.test(d.me)) return json({ error: 'not_allowed' }, 403)
  }

  const key = await secret(svc, 'pagespeed_api_key')
  if (!key) return json({ ok: false, code: 'no_key' })

  const { data: listed } = await svc.rpc('worker_pagespeed_targets')
  const sites = (Array.isArray(listed) ? listed : []).filter((s): s is { site_id: string; hostname: string; paths: string[] } =>
    typeof s?.site_id === 'string' && UUID.test(s.site_id) && typeof s?.hostname === 'string' && Array.isArray(s?.paths) && (!only || s.site_id === only))
  const start = Date.now()
  const left = () => Date.now() - start < BUDGET_MS
  const out: Array<{ site_id: string; pages: number; error?: string }> = []
  for (const s of sites) {
    if (!left()) break
    const rows: Array<Vitals & { path: string; strategy: 'mobile' }> = []
    const codes: string[] = []
    const paths = s.paths.filter((p) => typeof p === 'string' && p.startsWith('/')).slice(0, 12)
    // three at a time: PageSpeed runs a full Lighthouse per page
    for (let i = 0; i < paths.length && left(); i += 3) {
      const batch = await Promise.all(paths.slice(i, i + 3).map(async (p) => ({ p, r: await measure(`https://${s.hostname}${p}`, key) })))
      for (const { p, r } of batch) {
        if (r.v) rows.push({ path: p, strategy: 'mobile', ...r.v })
        else if (r.code) codes.push(r.code)
      }
      // a refused key refuses every page: stop asking
      if (codes.includes('key_refused')) break
    }
    const error = codes.includes('key_refused') ? 'key_refused' : codes.includes('quota') ? 'quota' : !left() ? 'partial' : codes[0] ?? null
    const { error: rpcError } = await svc.rpc('worker_pagespeed_result', { p_site: s.site_id, p_rows: rows, p_error: error })
    if (rpcError) log(`result refused ${rpcError.code ?? ''}`)
    out.push({ site_id: s.site_id, pages: rows.length, ...(error ? { error } : {}) })
    log(`site pages=${rows.length} failed=${codes.length}${error ? ` code=${error}` : ''}`)
  }
  return json({ ok: true, sites: out })
})
