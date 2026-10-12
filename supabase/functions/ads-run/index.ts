/**
 * ads-run — Google Ads, LinkedIn Ads and Meta Ads into Growth (0077). The app holds no service role and no platform
 * credential; this does. Read only: nothing is changed on a platform.
 *
 * POST {"kind": "connect" | "run", "provider"?: "google_ads" | "linkedin_ads" | "meta_ads"}
 *   - "connect": the owner (own aal2 token; ads_check_ready proves the owner). Signs in to the platform, lists the ad
 *     accounts the credentials may read and reports the verdict; then imports what time allows.
 *   - "run": the nightly cron (header x-worker-key = Vault «ads_worker_secret») or the owner. For every account linked to
 *     an application: its campaigns and ads, and its days from a week before the last imported day (ninety days the first
 *     time), thirty days at a time, while about two minutes allow. LinkedIn's access token is renewed with its refresh
 *     token when it has less than a week left. For Google Ads also its keywords and their days (keyword_view) and each
 *     campaign's bidding strategy (0083); never the search terms people typed.
 *
 * Logs carry kinds, counts and status codes. Never a name, a figure or a credential.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { sameText } from '../_shared/signing.ts'
import { accessToken, parseKey } from '../_shared/google.ts'
import {
  GOOGLE_SCOPE, googleAccounts, googleImport, linkedinAccounts, linkedinImport, linkedinToken, metaAccounts, metaImport,
  type Account, type Fail, type Import,
} from '../_shared/ads.ts'

type Provider = 'google_ads' | 'linkedin_ads' | 'meta_ads'
const PROVIDERS: Provider[] = ['google_ads', 'linkedin_ads', 'meta_ads']
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const log = (s: string) => console.log(`[ads-run] ${s}`)
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

async function secret(svc: SupabaseClient, name: string): Promise<string> {
  const { data, error } = await svc.rpc('product_secret', { p_name: name })
  return !error && typeof data === 'string' ? data : ''
}

async function rpc<T>(svc: SupabaseClient, fn: string, args: Record<string, unknown> = {}): Promise<T | null> {
  const { data, error } = await svc.rpc(fn, args)
  if (error) {
    log(`${fn} refused ${error.code ?? ''}`.trim())
    return null
  }
  return data as T
}

type Targets = {
  providers: Array<{ provider: Provider; status: string; login_customer_id: string | null; key_source: string; client_id: string | null; token_expires_at: string | null }>
  accounts: Array<{ id: string; provider: Provider; external_id: string; from: string; to: string }>
}

/** a platform's way in: how to list its accounts and import one, once signed in; or why it cannot be */
type Client = { accounts: () => Promise<{ ok: true; accounts: Account[] } | Fail>; importer: (account: string, from: string, to: string) => Promise<({ ok: true } & Import) | Fail> }

async function client(svc: SupabaseClient, p: Targets['providers'][number]): Promise<Client | Fail> {
  if (p.provider === 'google_ads') {
    const developerToken = await secret(svc, 'google_ads_developer_token')
    const key = parseKey(await secret(svc, p.key_source === 'search_console' ? 'search_console_key' : 'google_ads_key'))
    if (!developerToken || !key) return { ok: false, code: 'no_key' }
    const tok = await accessToken(key, fetch, Math.floor(Date.now() / 1000), GOOGLE_SCOPE)
    if (!tok.ok) return tok
    const auth = { token: tok.token, developerToken, loginCustomerId: p.login_customer_id }
    return { accounts: () => googleAccounts(auth), importer: (a, from, to) => googleImport(auth, a, from, to) }
  }
  if (p.provider === 'linkedin_ads') {
    let token = await secret(svc, 'linkedin_ads_access_token')
    if (!token) return { ok: false, code: 'not_signed_in' }
    // renew a token with less than a week left, when LinkedIn gave a refresh token
    const left = p.token_expires_at ? Date.parse(p.token_expires_at) - Date.now() : 0
    if (left < 7 * 86_400_000) {
      const refresh = await secret(svc, 'linkedin_ads_refresh_token')
      const clientSecret = await secret(svc, 'linkedin_ads_client_secret')
      let renewed = false
      if (refresh && clientSecret && p.client_id) {
        const r = await linkedinToken({ grant_type: 'refresh_token', refresh_token: refresh, client_id: p.client_id, client_secret: clientSecret })
        if (r.ok) {
          await rpc(svc, 'worker_ads_tokens', { p_access: r.tokens.access, p_refresh: r.tokens.refresh, p_expires_in: r.tokens.expiresIn, p_refresh_expires_in: r.tokens.refreshExpiresIn })
          token = r.tokens.access
          renewed = true
          log('linkedin token renewed')
        } else log(`linkedin renew refused ${r.code}`)
      }
      // expired and not renewed: the owner signs in with LinkedIn again
      if (left <= 0 && !renewed) return { ok: false, code: 'token_expired' }
    }
    const t = token
    return { accounts: () => linkedinAccounts(t), importer: (a, from, to) => linkedinImport(t, a, from, to) }
  }
  const token = await secret(svc, 'meta_ads_token')
  if (!token) return { ok: false, code: 'no_key' }
  const appSecret = (await secret(svc, 'meta_ads_app_secret')) || null
  const auth = { token, appSecret }
  return { accounts: () => metaAccounts(auth), importer: (a, from, to) => metaImport(auth, a, from, to) }
}

/** thirty-day windows, oldest first */
function windows(from: string, to: string): Array<{ from: string; to: string }> {
  const out: Array<{ from: string; to: string }> = []
  let a = Date.parse(`${from}T00:00:00Z`)
  const end = Date.parse(`${to}T00:00:00Z`)
  while (a <= end && out.length < 14) {
    const b = Math.min(end, a + 29 * 86_400_000)
    out.push({ from: new Date(a).toISOString().slice(0, 10), to: new Date(b).toISOString().slice(0, 10) })
    a = b + 86_400_000
  }
  return out
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 503)
  let body: { kind?: unknown; provider?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 1_000) return json({ error: 'too_large' }, 413)
    body = raw ? JSON.parse(raw) : {}
  } catch {
    return json({ error: 'body' }, 400)
  }
  const kind = body.kind
  if (kind !== 'run' && kind !== 'connect') return json({ error: 'invalid' }, 400)
  const only = body.provider === undefined ? null : PROVIDERS.find((p) => p === body.provider) ?? 'bad'
  if (only === 'bad' || (kind === 'connect' && !only)) return json({ error: 'invalid' }, 400)
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })

  // who: the cron (worker key, run only) or the owner (own token)
  const offered = req.headers.get('x-worker-key') ?? ''
  let me: string | null = null
  if (offered) {
    const key = await secret(svc, 'ads_worker_secret')
    if (!key || !sameText(offered, key) || kind !== 'run') return json({ error: 'not_allowed' }, 403)
  } else {
    const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
    if (!token || token === serviceKey || !anonKey) return json({ error: 'unauthorized' }, 401)
    const asUser = createClient(url, anonKey, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } })
    const { data, error } = await asUser.rpc('ads_check_ready')
    const d = data as { me?: string } | null
    if (error || !d?.me || !UUID.test(d.me)) return json({ error: 'not_allowed' }, 403)
    me = d.me
  }

  const start = Date.now()
  const left = () => Date.now() - start < 120_000
  const first = await rpc<Targets>(svc, 'worker_ads_targets')
  if (!first) return json({ ok: false, code: 'targets' })
  const providers = first.providers.filter((p) => (only ? p.provider === only : kind === 'connect' || p.status === 'connected'))
  const report: Array<{ provider: Provider; ok: boolean; code?: string; accounts?: number }> = []
  const clients = new Map<Provider, Client>()

  for (const p of providers) {
    const c = await client(svc, p)
    if ('ok' in c && c.ok === false) {
      await rpc(svc, 'worker_ads_result', { p_provider: p.provider, p_ok: false, p_code: c.code, p_by: me })
      report.push({ provider: p.provider, ok: false, code: c.code })
      log(`${p.provider} refused ${c.code}`)
      continue
    }
    const cl = c as Client
    const listed = await cl.accounts()
    if (!listed.ok) {
      await rpc(svc, 'worker_ads_result', { p_provider: p.provider, p_ok: false, p_code: listed.code, p_by: me })
      report.push({ provider: p.provider, ok: false, code: listed.code })
      log(`${p.provider} accounts refused ${listed.code}`)
      continue
    }
    await rpc(svc, 'worker_ads_accounts', { p_provider: p.provider, p_accounts: listed.accounts })
    await rpc(svc, 'worker_ads_result', { p_provider: p.provider, p_ok: true, p_code: null, p_by: me })
    clients.set(p.provider, cl)
    report.push({ provider: p.provider, ok: true, accounts: listed.accounts.length })
    log(`${p.provider} accounts=${listed.accounts.length}`)
  }

  // the imports: each linked account's windows, oldest first, while time allows
  let rows = 0
  let imported = 0
  let failed = 0
  const targets = await rpc<Targets>(svc, 'worker_ads_targets')
  for (const t of targets?.accounts ?? []) {
    if (!left()) break
    const cl = clients.get(t.provider)
    if (!cl) continue
    for (const w of windows(t.from, t.to)) {
      if (!left()) break
      const r = await cl.importer(t.external_id, w.from, w.to)
      if (!r.ok) {
        await rpc(svc, 'worker_ads_failed', { p_account: t.id, p_code: r.code })
        failed++
        log(`${t.provider} import refused ${r.code}`)
        break
      }
      const done = await rpc<{ rows: number }>(svc, 'worker_ads_import', {
        p_account: t.id, p_from: w.from, p_to: w.to, p_campaigns: r.campaigns, p_ads: r.ads, p_daily: r.daily,
      })
      if (!done) { failed++; break }
      rows += done.rows
      // Google's keywords and their days (0083), read only; a refusal leaves the campaigns and ads imported
      if (t.provider === 'google_ads' && r.keywords && r.keywordDaily) {
        const kw = await rpc<{ rows: number }>(svc, 'worker_ads_keywords', {
          p_account: t.id, p_from: w.from, p_to: w.to, p_keywords: r.keywords, p_daily: r.keywordDaily, p_bidding: r.bidding ?? null,
        })
        if (kw) rows += kw.rows
      }
    }
    imported++
  }
  log(`${kind} accounts=${imported} rows=${rows} failed=${failed}`)
  return json({ ok: report.every((r) => r.ok), providers: report, accounts: imported, rows, failed })
})
