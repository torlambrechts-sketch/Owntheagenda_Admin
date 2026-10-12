'use server'

import { revalidatePath } from 'next/cache'
import { headers } from 'next/headers'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { adsRun, handOverAdSecrets } from '@/lib/ads/run'
import { AD_PROVIDERS, type AdProvider } from '@/lib/growth/ads'

/**
 * Growth › Integrations › the ad platforms (0077). The owner connects: settings that are not secret go to ads_settings_set;
 * the credentials go to secret-intake under an intake number (fresh second factor); then ads-run proves them and lists the
 * ad accounts. LinkedIn signs in instead: ads_oauth_start gives a one-time state and LinkedIn sends the code to ads-oauth.
 * Each action parses its input and answers `{ ok: true, … }` or `{ ok: false, code, detail }`; the database and the
 * functions decide (owner, fresh second factor, rights) again.
 */
type Fail = { ok: false; code: RpcCode | string; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const Intake = z.object({ intake_code: z.string().regex(/^[0-9a-f]{48}$/), expires_in: z.number() })
const provider = z.enum(AD_PROVIDERS)
const uuid = z.string().uuid()
const product = z.string().regex(/^[a-z][a-z0-9_]{1,40}$/)
const ok = z.record(z.string(), z.unknown())
const done = () => revalidatePath('/growth')

/** a Google service account's JSON key file, as Google hands it out */
const GoogleKey = z.string().max(6000).refine((s) => {
  try {
    const j = JSON.parse(s) as Record<string, unknown>
    return j.type === 'service_account' && typeof j.client_email === 'string' && /@[a-z0-9.-]+\.iam\.gserviceaccount\.com$/.test(j.client_email)
      && typeof j.private_key === 'string' && j.private_key.startsWith('-----BEGIN PRIVATE KEY-----')
  } catch {
    return false
  }
})

/** the credentials into Vault: an intake number for the platform, then secret-intake */
async function handOver(p: AdProvider, secrets: Record<string, string>): Promise<Res> {
  if (!Object.keys(secrets).length) return { ok: true }
  const intake = await rpc('ads_intake', { p_provider: p }, Intake)
  if (!intake.ok) return intake
  const handed = await handOverAdSecrets(intake.data.intake_code, secrets)
  return handed.ok ? { ok: true } : { ok: false, code: 'failed', detail: handed.code }
}

/** check the credentials and list the accounts; the reply's verdict for this platform */
async function check(p: AdProvider): Promise<Res<{ accounts: number; rows: number }>> {
  const r = await adsRun('connect', p)
  done()
  const mine = r.providers?.find((x) => x.provider === p)
  if (!r.ok || !mine?.ok) return { ok: false, code: 'not_connected', detail: mine?.code ?? r.code ?? 'failed' }
  return { ok: true, accounts: mine.accounts ?? 0, rows: r.rows ?? 0 }
}

/** Google Ads: the developer token, the service account (its own key, or Search Console's) and an optional manager account */
export async function connectGoogleAds(input: unknown): Promise<Res<{ accounts: number; rows: number }>> {
  const p = z.object({
    developerToken: z.string().trim().regex(/^[A-Za-z0-9_-]{15,64}$/).nullable(),
    loginCustomerId: z.string().trim().transform((s) => s.replace(/-/g, '')).pipe(z.string().regex(/^(\d{10})?$/)),
    keySource: z.enum(['own', 'search_console']),
    key: GoogleKey.nullable(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'bad_key' }
  const s = await rpc('ads_settings_set', { p_provider: 'google_ads', p_settings: { login_customer_id: p.data.loginCustomerId || null, key_source: p.data.keySource } }, ok)
  if (!s.ok) return s
  const handed = await handOver('google_ads', {
    ...(p.data.developerToken ? { google_ads_developer_token: p.data.developerToken } : {}),
    ...(p.data.keySource === 'own' && p.data.key ? { google_ads_key: p.data.key.trim() } : {}),
  })
  if (!handed.ok) return handed
  return check('google_ads')
}

/** LinkedIn Ads: the app's client id (kept in the open) and its client secret (Vault) */
export async function saveLinkedIn(input: unknown): Promise<Res> {
  const p = z.object({ clientId: z.string().trim().regex(/^[A-Za-z0-9]{8,40}$/), clientSecret: z.string().trim().regex(/^[A-Za-z0-9_.=-]{8,200}$/).nullable() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'bad_key' }
  const s = await rpc('ads_settings_set', { p_provider: 'linkedin_ads', p_settings: { client_id: p.data.clientId } }, ok)
  if (!s.ok) return s
  const handed = await handOver('linkedin_ads', p.data.clientSecret ? { linkedin_ads_client_secret: p.data.clientSecret } : {})
  done()
  return handed
}

/** LinkedIn's sign-in page, with a one-time state; LinkedIn returns to ads-oauth, which returns the owner here */
export async function startLinkedIn(): Promise<Res<{ url: string }>> {
  const h = await headers()
  const host = h.get('x-forwarded-host') ?? h.get('host') ?? ''
  const proto = h.get('x-forwarded-proto') ?? (host.startsWith('localhost') ? 'http' : 'https')
  const r = await rpc('ads_oauth_start', { p_origin: `${proto}://${host}` },
    z.object({ state: z.string().regex(/^[0-9a-f]{48}$/), client_id: z.string(), redirect_uri: z.string().url(), scope: z.string() }))
  if (!r.ok) return r
  const q = new URLSearchParams({ response_type: 'code', client_id: r.data.client_id, redirect_uri: r.data.redirect_uri, state: r.data.state, scope: r.data.scope })
  return { ok: true, url: `https://www.linkedin.com/oauth/v2/authorization?${q.toString()}` }
}

/** Meta Ads: a system user's access token, and the app secret when the app asks for appsecret_proof */
export async function connectMeta(input: unknown): Promise<Res<{ accounts: number; rows: number }>> {
  const p = z.object({ token: z.string().trim().regex(/^[A-Za-z0-9]{40,800}$/).nullable(), appSecret: z.string().trim().regex(/^[a-f0-9]{32}$/).nullable() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'bad_key' }
  const handed = await handOver('meta_ads', { ...(p.data.token ? { meta_ads_token: p.data.token } : {}), ...(p.data.appSecret ? { meta_ads_app_secret: p.data.appSecret } : {}) })
  if (!handed.ok) return handed
  return check('meta_ads')
}

/** Check again: the credentials and the accounts */
export async function checkAds(input: unknown): Promise<Res<{ accounts: number; rows: number }>> {
  const p = provider.safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  return check(p.data)
}

/** Import now instead of tonight */
export async function importAds(input: unknown): Promise<Res<{ rows: number; accounts: number }>> {
  const p = provider.safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await adsRun('run', p.data)
  done()
  const mine = r.providers?.find((x) => x.provider === p.data)
  if (!mine?.ok) return { ok: false, code: 'not_connected', detail: mine?.code ?? r.code ?? 'failed' }
  return { ok: true, rows: r.rows ?? 0, accounts: r.accounts ?? 0 }
}

export async function disconnectAds(input: unknown): Promise<Res> {
  const p = provider.safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await rpc('ads_disconnect', { p_provider: p.data }, ok)
  done()
  return r.ok ? { ok: true } : r
}

/** an ad account counts for an application, or for none */
export async function linkAdAccount(input: unknown): Promise<Res> {
  const p = z.object({ account: uuid, product: product.nullable() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await rpc('ads_account_link', { p_account: p.data.account, p_product: p.data.product }, ok)
  done()
  return r.ok ? { ok: true } : r
}

/** a platform campaign counts as another Sentral campaign, or as its own again */
export async function linkPlatformCampaign(input: unknown): Promise<Res> {
  const p = z.object({ campaign: uuid, adCampaign: uuid.nullable() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await rpc('ads_campaign_link', { p_campaign: p.data.campaign, p_ad_campaign: p.data.adCampaign }, ok)
  done()
  return r.ok ? { ok: true } : r
}
