/**
 * mail-events — what comes back from Brevo, and the unsubscribe that every campaign email offers (0060).
 *
 *   POST ?key=<mail_events_secret>             Brevo's transactional events. Only events tagged «sentral-*» are read;
 *                                              everything else (Orgpuls's survey mail shares the account) is dropped
 *                                              unread. Campaign events go to worker_email_events, ticket replies' to
 *                                              worker_ticket_mail_event.
 *   POST ?key=<mail_events_secret>&inbound=1   Brevo's inbound parsing: a customer's answer to a ticket reply, threaded by its reference
 *                                              header or its [T-n] subject; an auto-reply never reopens a ticket (0081)
 *                                              (worker_ticket_inbound threads it only from the ticket's requester).
 *   POST ?u=<token>                            RFC 8058 one-click unsubscribe (List-Unsubscribe-Post).
 *   POST {"action": "peek" | "unsubscribe", "token": "..."}   the app's public /u/<token> page.
 *
 * Logs carry counts and status codes, never an address, a token or a body.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { sameText } from '../_shared/signing.ts'
import { inboundMail, sortEvents } from '../_shared/brevo-events.ts'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const log = (s: string) => console.log(`[mail-events] ${s}`)
const TOKEN = /^[A-Za-z0-9_-]{16,128}$/

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  const svc = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', { auth: { persistSession: false } })
  const params = new URL(req.url).searchParams

  // one-click unsubscribe: the token is the authority, and the answer says nothing about whether it existed
  const u = params.get('u')
  if (u !== null) {
    await req.body?.cancel()
    if (!TOKEN.test(u)) return json({ ok: true })
    const { error } = await svc.rpc('worker_unsubscribe', { p_token: u, p_scope: 'marketing', p_method: 'one_click' })
    log(`one_click ${error ? error.code ?? 'refused' : 'ok'}`)
    return json({ ok: true })
  }

  let raw: string
  try {
    raw = await req.text()
  } catch {
    return json({ error: 'body' }, 400)
  }
  if (raw.length > 2_000_000) return json({ error: 'too_large' }, 413)

  // Brevo
  const key = params.get('key')
  if (key !== null) {
    const { data } = await svc.rpc('product_secret', { p_name: 'mail_events_secret' })
    if (typeof data !== 'string' || !data || !sameText(key, data)) return json({ error: 'not_allowed' }, 403)
    let payload: unknown
    try {
      payload = JSON.parse(raw)
    } catch {
      return json({ error: 'body' }, 400)
    }
    if (params.get('inbound') === '1') {
      let matched = 0, dropped = 0, auto = 0
      for (const item of inboundMail(payload)) {
        // the reference headers thread an answer; an auto-reply is recognised and never reopens a ticket (0081, F-S2)
        const { data: r, error } = await svc.rpc('worker_ticket_inbound', {
          p_inbound_id: item.id, p_from: item.from, p_subject: item.subject, p_body: item.body, p_headers: item.headers,
        })
        const res = (r ?? {}) as { matched?: boolean; auto_reply?: boolean }
        if (!error && res.auto_reply) auto++
        else if (!error && res.matched) matched++
        else dropped++
      }
      log(`inbound matched=${matched} auto_reply=${auto} dropped=${dropped}`)
      return json({ ok: true })
    }
    const sorted = sortEvents(payload)
    let tickets = 0
    for (const t of sorted.ticket) {
      const { error } = await svc.rpc('worker_ticket_mail_event', { p_provider_message_id: t.message_id, p_kind: t.kind })
      if (!error) tickets++
    }
    let campaign: unknown = null
    if (sorted.campaign.length) {
      const { data: r, error } = await svc.rpc('worker_email_events', { p_batch: sorted.campaign })
      campaign = error ? `refused ${error.code ?? ''}` : r
    }
    log(`events campaign=${JSON.stringify(campaign)} tickets=${tickets} dropped=${sorted.dropped}`)
    // a 2xx keeps Brevo from retrying what was already recorded or deliberately dropped
    return json({ ok: true })
  }

  // the app's unsubscribe page
  let body: { action?: unknown; token?: unknown }
  try {
    body = JSON.parse(raw)
  } catch {
    return json({ error: 'body' }, 400)
  }
  if (typeof body.token !== 'string' || !TOKEN.test(body.token)) return json({ found: false })
  if (body.action === 'peek') {
    const { data, error } = await svc.rpc('worker_unsubscribe_peek', { p_token: body.token })
    return json(error ? { found: false } : data)
  }
  if (body.action === 'unsubscribe') {
    const { data, error } = await svc.rpc('worker_unsubscribe', { p_token: body.token, p_scope: 'marketing', p_method: 'link' })
    log(`link ${error ? error.code ?? 'refused' : 'ok'}`)
    return json(error ? { unsubscribed: false } : data)
  }
  return json({ error: 'invalid' }, 400)
})
