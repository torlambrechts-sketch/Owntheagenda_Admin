/**
 * mail-run — Sentral's mail goes out through Brevo here (0060). The app holds no service role and no Brevo key; this does.
 *
 * POST {"kind": "run" | "connect" | "test"}
 *   - "run": the cron's call (app.mail_tick, header x-worker-key = Vault «mail_worker_secret») or the owner's. Sends what
 *     waits: ticket replies, staff invitations, security and SEO alert emails, then the mail jobs on the queue (MFA reminders,
 *     campaign test sends, campaign batches, sending-domain checks). Stops at about forty seconds; the next tick goes on.
 *   - "connect": the owner (own aal2 token; email_provider_check_ready proves the owner). Proves the Brevo key, registers
 *     Brevo's webhooks to mail-events, checks every sending domain against Brevo, and reports the verdict.
 *   - "test": the owner. One email to the owner's own address from the transactional sender.
 *
 * Logs carry kinds, counts and status codes. Never an address, a subject or a body (security rule 6), and never the key.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { sameText } from '../_shared/signing.ts'
import { brevoAccount, brevoDomain, brevoSend, brevoWebhooks, dmarcPolicy, type BrevoMessage, type SendResult } from '../_shared/brevo.ts'
import * as R from '../_shared/mail-render.ts'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const log = (s: string) => console.log(`[mail-run] ${s}`)
const BUDGET_MS = 40_000
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

type Sender = { from: string; from_name: string; reply_to: string | null }
type Config = { inbound_domain: string | null; public_base: string | null; functions_url: string }

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

const arr = <T>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : [])

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 503)
  let body: { kind?: unknown }
  try {
    const raw = await req.text()
    if (raw.length > 1_000) return json({ error: 'too_large' }, 413)
    body = raw ? JSON.parse(raw) : {}
  } catch {
    return json({ error: 'body' }, 400)
  }
  const kind = body.kind
  if (kind !== 'run' && kind !== 'connect' && kind !== 'test') return json({ error: 'invalid' }, 400)
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } })

  // who: the cron (worker key, run only) or the owner (own token)
  const offered = req.headers.get('x-worker-key') ?? ''
  let owner: { me: string; email: string; locale: string | null } | null = null
  if (offered) {
    const key = await secret(svc, 'mail_worker_secret')
    if (!key || !sameText(offered, key) || kind !== 'run') return json({ error: 'not_allowed' }, 403)
  } else {
    const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
    if (!token || token === serviceKey || !anonKey) return json({ error: 'unauthorized' }, 401)
    const asUser = createClient(url, anonKey, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } })
    const { data, error } = await asUser.rpc('email_provider_check_ready')
    const d = data as { me?: string; email?: string; locale?: string | null } | null
    if (error || !d?.me || !UUID.test(d.me) || !d.email) return json({ error: 'not_allowed' }, 403)
    owner = { me: d.me, email: d.email, locale: d.locale ?? null }
  }

  const key = await secret(svc, 'brevo_api_key')
  if (!key) return json({ ok: false, code: 'no_key' })
  const config = (await rpc<Config>(svc, 'worker_mail_config')) ?? { inbound_domain: null, public_base: null, functions_url: url }

  if (kind === 'connect') return json(await connect(svc, key, config, owner!.me, url))
  if (kind === 'test') return json(await test(svc, key, owner!))
  const counts = await run(svc, key, config, url)
  await rpc(svc, 'worker_mail_run_done', { p_info: counts, p_error: counts.auth_failed ? 'brevo_auth' : null })
  log(`run ${Object.entries(counts).map(([k, v]) => `${k}=${v}`).join(' ')}`)
  return json({ ok: true, ...counts })
})

// ---------------------------------------------------------------------------
async function connect(svc: SupabaseClient, key: string, config: Config, me: string, url: string) {
  const acc = await brevoAccount(key)
  if (!acc.ok) {
    await rpc(svc, 'worker_email_provider_result', { p_ok: false, p_info: { code: acc.code }, p_by: me })
    log(`connect refused ${acc.code}`)
    return { ok: false, code: acc.code }
  }
  const eventsKey = await secret(svc, 'mail_events_secret')
  const hooks = eventsKey
    ? await brevoWebhooks(key, `${url.replace(/\/+$/, '')}/functions/v1/mail-events?key=${encodeURIComponent(eventsKey)}`, config.inbound_domain)
    : { events: false, inbound: null }
  await rpc(svc, 'worker_email_provider_result', {
    p_ok: true, p_by: me,
    p_info: { account: { plan: acc.plan }, webhook_ok: hooks.events, ...(hooks.inbound !== null ? { inbound_ok: hooks.inbound } : {}) },
  })
  const domains = arr<{ id: string; domain: string }>(await rpc(svc, 'worker_sender_domains'))
  const checked = []
  for (const d of domains) checked.push({ domain: d.domain, ...(await checkDomain(svc, key, d.id, d.domain)) })
  log(`connect ok webhook=${hooks.events} inbound=${hooks.inbound} domains=${checked.length}`)
  return { ok: true, plan: acc.plan, webhook: hooks.events, inbound: hooks.inbound, domains: checked }
}

async function checkDomain(svc: SupabaseClient, key: string, id: string, domain: string) {
  const [b, dmarc] = await Promise.all([brevoDomain(key, domain), dmarcPolicy(domain)])
  if (!b.ok) return { verified: false, code: b.code }
  const r = await rpc<{ authenticated: boolean; verified: boolean }>(svc, 'worker_sender_domain_status', {
    p_id: id,
    p_checks: {
      spf_ok: b.code || b.authenticated, dkim_ok: b.dkim || b.authenticated, dmarc_policy: dmarc, verified: b.verified && b.authenticated,
      detail: { brevo_known: b.known, brevo_verified: b.verified, brevo_authenticated: b.authenticated, brevo_code: b.code, brevo_dkim: b.dkim, dmarc_found: dmarc !== null },
    },
  })
  return { verified: r?.verified === true, authenticated: r?.authenticated === true, known: b.known }
}

async function test(svc: SupabaseClient, key: string, owner: { email: string; locale: string | null }) {
  const sender = await rpc<Sender | null>(svc, 'worker_mail_sender')
  if (!sender) return { ok: false, code: 'no_sender' }
  const m = R.testMail({ lang: R.langOf(owner.locale), from: sender.from, fromName: sender.from_name })
  const r = await brevoSend(key, { sender: { email: sender.from, name: sender.from_name }, to: { email: owner.email }, subject: m.subject, html: m.html, text: m.text, tag: 'sentral-test' })
  log(`test ${r.ok ? 'sent' : r.code}`)
  return r.ok ? { ok: true } : { ok: false, code: r.code }
}

// ---------------------------------------------------------------------------
async function run(svc: SupabaseClient, key: string, config: Config, url: string) {
  const start = Date.now()
  const left = () => Date.now() - start < BUDGET_MS
  const c = { tickets: 0, invites: 0, alerts: 0, reminders: 0, campaign_mails: 0, tests: 0, domains: 0, failed: 0, auth_failed: 0 }
  let authDown = false
  const send = async (m: BrevoMessage): Promise<SendResult> => {
    if (authDown) return { ok: false, retryable: true, auth: true, code: 'brevo_auth' }
    const r = await brevoSend(key, m)
    if (!r.ok && r.auth) {
      authDown = true
      c.auth_failed = 1
      await rpc(svc, 'worker_email_provider_result', { p_ok: false, p_info: { code: r.code } })
    }
    if (!r.ok) c.failed++
    return r
  }
  const base = config.public_base
  const link = (path: string) => (base ? R.safeLink(base, path) : null)

  // 1. ticket replies; the one that resolves a ticket carries the CSAT question with its single-use token (0081)
  for (const t of arr<{ id: string; ref: string; subject: string; body: string; to: string; to_name: string | null; agent: string | null; from: string; from_name: string; reply_to: string; locale: string; csat_token?: string | null }>(
    await rpc(svc, 'worker_ticket_mail_claim', { p_limit: 20 }))) {
    if (!left() || authDown) break
    const lang = R.langOf(t.locale)
    const csat = t.csat_token ? R.csatLinks(config.functions_url || url, t.csat_token, lang) : null
    const m = R.ticketReply({ lang, ref: t.ref, subject: t.subject, body: t.body, agent: t.agent, fromName: t.from_name, csat })
    const r = await send({ sender: { email: t.from, name: t.from_name }, to: { email: t.to, name: t.to_name }, replyTo: { email: t.reply_to },
                           subject: m.subject, html: m.html, text: m.text, tag: 'sentral-ticket' })
    await rpc(svc, 'worker_ticket_mail_done', r.ok ? { p_message: t.id, p_provider_message_id: r.id } : { p_message: t.id, p_provider_message_id: null, p_code: r.code, p_retry: r.retryable })
    if (r.ok) c.tickets++
  }

  // 2. invitations: a one-time link from Auth, opened on Sentral's own address
  for (const a of arr<{ id: string; email: string; name: string | null; locale: string; by_name: string | null; public_base: string; from: string; from_name: string; reply_to: string | null }>(
    await rpc(svc, 'worker_invite_claim', { p_limit: 10 }))) {
    if (!left() || authDown) break
    let gen = await svc.auth.admin.generateLink({ type: 'invite', email: a.email })
    let type: 'invite' | 'recovery' = 'invite'
    if (gen.error) {
      // the address already has an Auth user without a password: a recovery link sets one the same way
      gen = await svc.auth.admin.generateLink({ type: 'recovery', email: a.email })
      type = 'recovery'
    }
    const hashed = gen.data?.properties?.hashed_token
    if (gen.error || !hashed) {
      await rpc(svc, 'worker_invite_done', { p_staff: a.id, p_code: 'auth_link' })
      c.failed++
      continue
    }
    const m = R.invite({ lang: R.langOf(a.locale), by: a.by_name, fromName: a.from_name,
                         link: R.safeLink(a.public_base, `/velkommen?token_hash=${encodeURIComponent(hashed)}&type=${type}`) })
    const r = await send({ sender: { email: a.from, name: a.from_name }, to: { email: a.email, name: a.name }, ...(a.reply_to ? { replyTo: { email: a.reply_to } } : {}),
                           subject: m.subject, html: m.html, text: m.text, tag: 'sentral-invite' })
    await rpc(svc, 'worker_invite_done', { p_staff: a.id, p_code: r.ok ? null : r.code })
    if (r.ok) c.invites++
  }

  // 3. security alerts
  for (const x of arr<{ event: number; recipient: string; kind: string; at: string; staff: string | null; to: string; locale: string; from: string; from_name: string }>(
    await rpc(svc, 'worker_alert_mail_claim', { p_limit: 50 }))) {
    if (!left() || authDown) break
    const m = R.securityAlert({ lang: R.langOf(x.locale), kind: x.kind, staff: x.staff, at: x.at, link: link('/security'), fromName: x.from_name })
    const r = await send({ sender: { email: x.from, name: x.from_name }, to: { email: x.to }, subject: m.subject, html: m.html, text: m.text, tag: 'sentral-alert' })
    await rpc(svc, 'worker_alert_mail_done', { p_event: x.event, p_recipient: x.recipient, p_ok: r.ok })
    if (r.ok) c.alerts++
  }

  // 3b. SEO alerts (0074): to everybody who may read Growth's reports, when the rule sends email
  for (const x of arr<{ alert: string; recipient: string; rule: string; params: Record<string, unknown>; at: string; site: string; to: string; locale: string; from: string; from_name: string }>(
    await rpc(svc, 'worker_seo_alert_mail_claim', { p_limit: 50 }))) {
    if (!left() || authDown) break
    const m = R.seoAlert({ lang: R.langOf(x.locale), rule: x.rule, params: x.params ?? {}, site: x.site, at: x.at, link: link('/growth?tab=seo&sub=alerts'), fromName: x.from_name })
    const r = await send({ sender: { email: x.from, name: x.from_name }, to: { email: x.to }, subject: m.subject, html: m.html, text: m.text, tag: 'sentral-alert' })
    await rpc(svc, 'worker_seo_alert_mail_done', { p_alert: x.alert, p_recipient: x.recipient, p_ok: r.ok })
    if (r.ok) c.alerts++
  }

  // 4. the queue's mail jobs
  if (left() && !authDown) {
    const sender = await rpc<Sender | null>(svc, 'worker_mail_sender')
    for (const j of arr<Record<string, unknown>>(await rpc(svc, 'worker_mail_take', { p_limit: 20 }))) {
      if (!left() || authDown) break
      switch (j.job) {
        case 'mfa_reminder': {
          const s = await rpc<{ email: string; name: string | null; locale: string; active: boolean; mfa: boolean; by_name: string | null } | null>(
            svc, 'worker_staff_mail', { p_staff: j.staff, p_by: typeof j.by === 'string' ? j.by : null })
          if (!s || !s.active || s.mfa || !sender) break
          const m = R.mfaReminder({ lang: R.langOf(s.locale), by: s.by_name, link: link('/login'), fromName: sender.from_name })
          const r = await send({ sender: { email: sender.from, name: sender.from_name }, to: { email: s.email, name: s.name }, subject: m.subject, html: m.html, text: m.text, tag: 'sentral-mfa' })
          if (r.ok) c.reminders++
          break
        }
        case 'campaign_test': {
          const subjects = arr<string | null>(j.subjects).filter((s): s is string => typeof s === 'string' && s.trim() !== '')
          if (typeof j.to !== 'string' || typeof j.from !== 'string' || typeof j.html !== 'string') break
          // the test opens where the campaign's own links will: its application's link address, else Sentral's
          const testBase = typeof j.campaign_id === 'string' && UUID.test(j.campaign_id) ? await rpc<string | null>(svc, 'worker_campaign_base', { p_campaign: j.campaign_id }) : null
          const html = R.campaignHtml(j.html, testBase ? R.safeLink(testBase, '/u/test') : (link('/u/test') ?? '#'))
          for (const subject of [...new Set(subjects)].slice(0, 2)) {
            const r = await send({ sender: { email: j.from, name: String(j.from_name ?? '') }, to: { email: j.to }, subject: `[Test] ${subject}`,
                                   ...(typeof j.reply_to === 'string' ? { replyTo: { email: j.reply_to } } : {}),
                                   html, text: R.htmlToText(html), tag: 'sentral-test' })
            if (r.ok) c.tests++
          }
          break
        }
        case 'campaign_send':
          if (typeof j.campaign === 'string' || typeof j.campaign_id === 'string') {
            c.campaign_mails += await campaign(svc, String(j.campaign ?? j.campaign_id), base, url, send, left)
          }
          break
        case 'dns_check': {
          const id = typeof j.sender_domain_id === 'string' ? j.sender_domain_id : null
          const d = arr<{ id: string; domain: string }>(await rpc(svc, 'worker_sender_domains')).find((x) => x.id === id)
          if (d) { await checkDomain(svc, key, d.id, d.domain); c.domains++ }
          break
        }
      }
    }
  }
  return c
}

// one campaign's batches: each recipient's own unsubscribe link (page and RFC 8058 one-click), on the campaign's
// application's link address when it has one (0063), else on Sentral's public address
async function campaign(svc: SupabaseClient, id: string, fallback: string | null, url: string, send: (m: BrevoMessage) => Promise<SendResult>, left: () => boolean) {
  const base = (await rpc<string | null>(svc, 'worker_campaign_base', { p_campaign: id })) ?? fallback
  if (!base) {
    log('campaign held no_public_base')
    return 0
  }
  let sent = 0
  while (left()) {
    const batch = await rpc<{ campaign: { from: string; from_name: string; reply_to: string | null }; recipients: unknown[] }>(svc, 'worker_campaign_batch', { p_campaign: id, p_limit: 50 })
    const list = arr<{ id: string; email: string; name: string | null; subject: string; html: string; unsub_token: string }>(batch?.recipients)
    if (!batch || list.length === 0) break
    for (const r of list) {
      const unsub = R.safeLink(base, `/u/${encodeURIComponent(r.unsub_token)}`)
      const html = R.campaignHtml(r.html, unsub)
      const res = await send({
        sender: { email: batch.campaign.from, name: batch.campaign.from_name }, to: { email: r.email, name: r.name },
        ...(batch.campaign.reply_to ? { replyTo: { email: batch.campaign.reply_to } } : {}),
        subject: r.subject, html, text: R.htmlToText(html), tag: 'sentral-campaign',
        headers: {
          'List-Unsubscribe': `<${url.replace(/\/+$/, '')}/functions/v1/mail-events?u=${encodeURIComponent(r.unsub_token)}>`,
          'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
        },
      })
      if (res.ok) {
        await rpc(svc, 'worker_campaign_sent', { p_recipient: r.id, p_provider_message_id: res.id })
        sent++
      } else if (!res.retryable) {
        await rpc(svc, 'worker_campaign_failed', { p_recipient: r.id, p_code: res.code })
      }
      // a retryable failure keeps the lease; campaign_due offers the recipient again after fifteen minutes
      if (res.ok === false && res.auth) return sent
    }
  }
  return sent
}
