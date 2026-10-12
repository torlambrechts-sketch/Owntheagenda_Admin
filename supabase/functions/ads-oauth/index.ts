/**
 * ads-oauth — where LinkedIn's sign-in comes back (0077). The redirect URI registered on the LinkedIn app.
 *
 * GET ?code=…&state=… (or ?error=…&state=…). The state is the owner's one-time number from ads_oauth_start (fifteen
 * minutes, used once); without it nothing happens. The code is exchanged here, with the client secret from Vault, and the
 * tokens go straight into Vault: no token passes through the browser or a person. Then the ad accounts the member may
 * read are listed, and the owner is sent back to Growth › Integrations on the address the sign-in began from (one of
 * the app's own, checked when the state was made).
 *
 * Logs carry the outcome as a word. Never a code, a token or a name.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { linkedinAccounts, linkedinToken } from '../_shared/ads.ts'

const log = (s: string) => console.log(`[ads-oauth] ${s}`)
const text = (body: string, status: number) => new Response(body, { status, headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' } })
const back = (origin: string, outcome: string) =>
  new Response(null, { status: 302, headers: { location: `${origin}/growth?tab=integrations&sub=linkedin_ads&oauth=${outcome}`, 'cache-control': 'no-store' } })

async function secret(svc: SupabaseClient, name: string): Promise<string> {
  const { data, error } = await svc.rpc('product_secret', { p_name: name })
  return !error && typeof data === 'string' ? data : ''
}

Deno.serve(async (req) => {
  if (req.method !== 'GET') return text('method', 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!url || !serviceKey) return text('not configured', 503)
  const q = new URL(req.url).searchParams
  const state = q.get('state') ?? ''
  if (!/^[0-9a-f]{48}$/.test(state)) return text('This sign-in link is not valid. Start again from Sentral.', 400)
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })

  const { data, error } = await svc.rpc('worker_ads_oauth_state', { p_state: state })
  const s = data as { staff_id?: string; origin?: string; client_id?: string | null; redirect_uri?: string } | null
  if (error || !s?.origin || !s.staff_id) {
    log('state refused')
    return text('This sign-in link has expired or was used already. Start again from Sentral.', 400)
  }
  const code = q.get('code') ?? ''
  if (q.get('error') || !code || code.length > 2000) {
    log('denied')
    return back(s.origin, 'denied')
  }
  const clientSecret = await secret(svc, 'linkedin_ads_client_secret')
  if (!s.client_id || !clientSecret || !s.redirect_uri) {
    log('not configured')
    return back(s.origin, 'not_configured')
  }
  const r = await linkedinToken({ grant_type: 'authorization_code', code, redirect_uri: s.redirect_uri, client_id: s.client_id, client_secret: clientSecret })
  if (!r.ok) {
    await svc.rpc('worker_ads_result', { p_provider: 'linkedin_ads', p_ok: false, p_code: r.code, p_by: s.staff_id })
    log(`exchange refused ${r.code}`)
    return back(s.origin, 'failed')
  }
  const stored = await svc.rpc('worker_ads_tokens', {
    p_access: r.tokens.access, p_refresh: r.tokens.refresh, p_expires_in: r.tokens.expiresIn, p_refresh_expires_in: r.tokens.refreshExpiresIn, p_by: s.staff_id,
  })
  if (stored.error) {
    log(`store refused ${stored.error.code ?? ''}`)
    return back(s.origin, 'failed')
  }
  // the accounts the member may read: the verdict on the connection
  const listed = await linkedinAccounts(r.tokens.access)
  if (listed.ok) await svc.rpc('worker_ads_accounts', { p_provider: 'linkedin_ads', p_accounts: listed.accounts })
  await svc.rpc('worker_ads_result', { p_provider: 'linkedin_ads', p_ok: listed.ok, p_code: listed.ok ? null : listed.code, p_by: s.staff_id })
  log(`signed in accounts=${listed.ok ? listed.accounts.length : 'refused'}${r.tokens.refresh ? ' refresh' : ''}`)
  return back(s.origin, listed.ok ? 'ok' : 'no_access')
})
