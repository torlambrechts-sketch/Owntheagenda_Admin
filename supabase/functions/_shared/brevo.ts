/**
 * Brevo's API, reduced to what Sentral needs (0060): send one transactional email, read the account, read a sending
 * domain's authentication, and register the two webhooks. Nothing from a response body is passed on or logged: Brevo's
 * error messages can quote an address. The caller gets the HTTP status as a code and two decisions made from it.
 */

export type BrevoMessage = {
  sender: { email: string; name: string }
  to: { email: string; name?: string | null }
  subject: string
  html: string
  text: string
  /** routes Brevo's events back: only «sentral-*» tags are read by mail-events */
  tag: SentralTag
  replyTo?: { email: string; name?: string }
  headers?: Record<string, string>
}

export const SENTRAL_TAGS = ['sentral-ticket', 'sentral-campaign', 'sentral-invite', 'sentral-alert', 'sentral-mfa', 'sentral-test'] as const
export type SentralTag = (typeof SENTRAL_TAGS)[number]

export type SendResult = { ok: true; id: string } | { ok: false; retryable: boolean; auth: boolean; code: string }

const API = 'https://api.brevo.com/v3'

type Fetch = typeof fetch

export async function brevoSend(key: string, m: BrevoMessage, f: Fetch = fetch): Promise<SendResult> {
  const body: Record<string, unknown> = {
    sender: m.sender,
    to: [m.to.name ? { email: m.to.email, name: m.to.name } : { email: m.to.email }],
    subject: m.subject,
    htmlContent: m.html,
    textContent: m.text,
    tags: [m.tag],
  }
  if (m.replyTo) body.replyTo = m.replyTo
  if (m.headers && Object.keys(m.headers).length) body.headers = m.headers
  let res: Response
  try {
    res = await f(`${API}/smtp/email`, {
      method: 'POST',
      headers: { 'api-key': key, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    })
  } catch {
    return { ok: false, retryable: true, auth: false, code: 'network' }
  }
  if (res.ok) {
    const json = (await res.json().catch(() => ({}))) as { messageId?: string }
    return json.messageId ? { ok: true, id: json.messageId } : { ok: false, retryable: false, auth: false, code: 'no_message_id' }
  }
  await res.body?.cancel()
  const code = `http_${res.status}`
  if (res.status === 401 || res.status === 403) return { ok: false, retryable: true, auth: true, code }
  if (res.status === 429 || res.status >= 500) return { ok: false, retryable: true, auth: false, code }
  return { ok: false, retryable: false, auth: false, code }
}

/** the account behind the key: whether it answers, and the plan's name (no address, no company details) */
export async function brevoAccount(key: string, f: Fetch = fetch): Promise<{ ok: true; plan: string | null } | { ok: false; code: string }> {
  try {
    const res = await f(`${API}/account`, { headers: { 'api-key': key, accept: 'application/json' }, signal: AbortSignal.timeout(10_000) })
    if (!res.ok) {
      await res.body?.cancel()
      return { ok: false, code: `http_${res.status}` }
    }
    const json = (await res.json().catch(() => ({}))) as { plan?: Array<{ type?: string }> }
    const plan = (json.plan ?? []).map((p) => p.type).find((t) => typeof t === 'string' && t !== 'sms') ?? null
    return { ok: true, plan: plan && /^[a-zA-Z0-9_ -]{1,40}$/.test(plan) ? plan : null }
  } catch {
    return { ok: false, code: 'network' }
  }
}

/** a sending domain as Brevo sees it: authenticated (DKIM and Brevo's code record) and verified */
export async function brevoDomain(key: string, domain: string, f: Fetch = fetch): Promise<
  { ok: true; known: boolean; verified: boolean; authenticated: boolean; dkim: boolean; code: boolean; dmarc: boolean } | { ok: false; code: string }
> {
  try {
    const res = await f(`${API}/senders/domains/${encodeURIComponent(domain)}`, { headers: { 'api-key': key, accept: 'application/json' }, signal: AbortSignal.timeout(10_000) })
    if (res.status === 404) {
      await res.body?.cancel()
      return { ok: true, known: false, verified: false, authenticated: false, dkim: false, code: false, dmarc: false }
    }
    if (!res.ok) {
      await res.body?.cancel()
      return { ok: false, code: `http_${res.status}` }
    }
    const j = (await res.json().catch(() => ({}))) as {
      verified?: boolean; authenticated?: boolean
      dns_records?: Record<string, { status?: boolean } | undefined>
    }
    const rec = j.dns_records ?? {}
    const st = (k: string) => rec[k]?.status === true
    return { ok: true, known: true, verified: j.verified === true, authenticated: j.authenticated === true,
             dkim: st('dkim_record') || st('dkim1Record') || st('dkim2Record'), code: st('brevo_code'), dmarc: st('dmarc_record') }
  } catch {
    return { ok: false, code: 'network' }
  }
}

/** the DMARC policy published for a domain (DNS over HTTPS); null when there is none */
export async function dmarcPolicy(domain: string, f: Fetch = fetch): Promise<'none' | 'quarantine' | 'reject' | null> {
  try {
    const res = await f(`https://cloudflare-dns.com/dns-query?name=_dmarc.${encodeURIComponent(domain)}&type=TXT`, {
      headers: { accept: 'application/dns-json' }, signal: AbortSignal.timeout(8_000),
    })
    if (!res.ok) return null
    const j = (await res.json().catch(() => ({}))) as { Answer?: Array<{ data?: string }> }
    const txt = (j.Answer ?? []).map((a) => (a.data ?? '').replace(/"/g, '')).find((d) => /^v=DMARC1/i.test(d))
    const p = txt?.match(/;\s*p=(none|quarantine|reject)/i)?.[1]?.toLowerCase()
    return p === 'none' || p === 'quarantine' || p === 'reject' ? p : null
  } catch {
    return null
  }
}

/**
 * Make sure Brevo posts to mail-events: the transactional events (delivered, bounces, complaints, unsubscribes, opens and
 * clicks: campaigns count them when tracked) and, with a reply domain, inbound email. Idempotent: an existing registration
 * for the same address is kept, or its events brought up to date. The address carries the events key, so it is compared
 * and sent, never returned.
 */
export async function brevoWebhooks(key: string, target: string, inboundDomain: string | null, f: Fetch = fetch): Promise<{ events: boolean; inbound: boolean | null }> {
  const h = { 'api-key': key, accept: 'application/json', 'content-type': 'application/json' }
  const events = ['delivered', 'hardBounce', 'softBounce', 'blocked', 'spam', 'invalid', 'unsubscribed', 'opened', 'click']
  const list = await f(`${API}/webhooks?type=transactional`, { headers: h }).catch(() => null)
  if (!list?.ok) {
    await list?.body?.cancel()
    return { events: false, inbound: inboundDomain ? false : null }
  }
  const hooks = ((await list.json().catch(() => ({}))) as { webhooks?: Array<{ id: number; url?: string; events?: string[] }> }).webhooks ?? []
  const base = target.split('?')[0] ?? target
  const ours = hooks.find((w) => (w.url ?? '').startsWith(base) && !(w.url ?? '').includes('inbound=1'))
  let okEvents = false
  if (ours) {
    if (events.some((e) => !(ours.events ?? []).includes(e))) {
      const upd = await f(`${API}/webhooks/${ours.id}`, { method: 'PUT', headers: h, body: JSON.stringify({ events, url: target }) }).catch(() => null)
      await upd?.body?.cancel()
      okEvents = upd?.ok === true
    } else okEvents = (ours.url ?? '') === target
    if (!okEvents && (ours.url ?? '') !== target) {
      const upd = await f(`${API}/webhooks/${ours.id}`, { method: 'PUT', headers: h, body: JSON.stringify({ url: target, events }) }).catch(() => null)
      await upd?.body?.cancel()
      okEvents = upd?.ok === true
    }
  } else {
    const made = await f(`${API}/webhooks`, {
      method: 'POST', headers: h,
      body: JSON.stringify({ url: target, description: 'Sentral mail events', type: 'transactional', events }),
    }).catch(() => null)
    await made?.body?.cancel()
    okEvents = made?.ok === true
  }
  if (!inboundDomain) return { events: okEvents, inbound: null }
  const inboundTarget = `${target}&inbound=1`
  const ilist = await f(`${API}/webhooks?type=inbound`, { headers: h }).catch(() => null)
  const ihooks = ilist?.ok ? (((await ilist.json().catch(() => ({}))) as { webhooks?: Array<{ id: number; url?: string; domain?: string }> }).webhooks ?? []) : []
  if (!ilist?.ok) await ilist?.body?.cancel()
  const iours = ihooks.find((w) => (w.url ?? '').startsWith(base) && w.domain === inboundDomain)
  if (iours && iours.url === inboundTarget) return { events: okEvents, inbound: true }
  const res = iours
    ? await f(`${API}/webhooks/${iours.id}`, { method: 'PUT', headers: h, body: JSON.stringify({ url: inboundTarget }) }).catch(() => null)
    : await f(`${API}/webhooks`, {
        method: 'POST', headers: h,
        body: JSON.stringify({ url: inboundTarget, description: 'Sentral ticket answers', type: 'inbound', events: ['inboundEmailProcessed'], domain: inboundDomain }),
      }).catch(() => null)
  await res?.body?.cancel()
  return { events: okEvents, inbound: res?.ok === true }
}
