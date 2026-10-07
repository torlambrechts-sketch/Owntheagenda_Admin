import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import * as R from '../supabase/functions/_shared/mail-render'
import { brevoSend } from '../supabase/functions/_shared/brevo'
import { inboundItems, sortEvents } from '../supabase/functions/_shared/brevo-events'
// @ts-expect-error a plain .mjs script
import { mailTextsSource } from '../scripts/mail-texts.mjs'

describe('mail texts', () => {
  it('the functions carry exactly the texts in messages/{en,no}/mail.json', () => {
    expect(readFileSync(new URL('../supabase/functions/_shared/mail-texts.gen.ts', import.meta.url), 'utf8')).toBe(mailTextsSource())
  })
})

describe('mail rendering', () => {
  it('a ticket reply names the ticket, escapes the body and tells how to answer', () => {
    const m = R.ticketReply({ lang: 'no', ref: 'T-2329', subject: 'PDF <tregt>', body: 'Hei <script>\nlinje 2', agent: 'Sara', fromName: 'Orgpuls' })
    expect(m.subject).toBe('Sv: [T-2329] PDF <tregt>')
    expect(m.html).not.toContain('<script>')
    expect(m.html).toContain('Hei &lt;script&gt;<br>linje 2')
    expect(m.text).toContain('Svaret ditt legges til T-2329')
  })
  it('a customer hears from the application, never from «Sentral»', () => {
    const m = R.ticketReply({ lang: 'no', ref: 'T-1', subject: 's', body: 'b', agent: 'Sara', fromName: 'Orgpuls' })
    expect(m.text).toContain('Sendt av Orgpuls.')
    expect(`${m.subject}${m.html}${m.text}`).not.toContain('Sentral')
  })
  it('links stay on the saved public address', () => {
    expect(R.safeLink('https://admin.example', '/velkommen?token_hash=a&type=invite')).toBe('https://admin.example/velkommen?token_hash=a&type=invite')
    expect(() => R.safeLink('https://admin.example', 'https://evil.example/x')).toThrow()
    expect(() => R.safeLink('http://admin.example', '/x')).toThrow()
  })
  it('an invitation carries its link once, in both parts', () => {
    const m = R.invite({ lang: 'en', by: 'Tor', link: 'https://admin.example/velkommen?token_hash=x&type=invite', fromName: 'Orgpuls' })
    expect(m.subject).toBe('You are invited to Sentral')
    expect(m.html).toContain('href="https://admin.example/velkommen?token_hash=x&amp;type=invite"')
    expect(m.text).toContain('https://admin.example/velkommen?token_hash=x&type=invite')
  })
  it('an alert without a public address has no button', () => {
    const m = R.securityAlert({ lang: 'no', kind: 'user_invited', staff: 'Ny Ansatt', at: '2026-10-07T10:00:00Z', link: null, fromName: 'Orgpuls' })
    expect(m.subject).toBe('Sikkerhetsvarsel i Sentral: En ansatt ble invitert')
    expect(m.html).not.toContain('<a ')
  })
  it('a campaign gets the person\'s own unsubscribe link and a text part', () => {
    const html = R.campaignHtml('<p>Hei</p><a href="[Unsubscribe]">Meld deg av</a>', 'https://admin.example/u/abc')
    expect(html).toContain('href="https://admin.example/u/abc"')
    expect(R.htmlToText(html)).toBe('Hei\nMeld deg av (https://admin.example/u/abc)')
  })
})

describe('Brevo', () => {
  it('a refusal comes back as a code and a decision, never Brevo\'s words', async () => {
    const f = (async () => new Response(JSON.stringify({ message: 'bad address ola@x.no' }), { status: 400 })) as typeof fetch
    const r = await brevoSend('k', { sender: { email: 'a@x', name: 'A' }, to: { email: 'ola@x.no' }, subject: 's', html: 'h', text: 't', tag: 'sentral-test' }, f)
    expect(r).toEqual({ ok: false, retryable: false, auth: false, code: 'http_400' })
    expect(JSON.stringify(r)).not.toContain('@')
  })
  it('a revoked key is an auth failure, a busy Brevo a retry', async () => {
    const at = (status: number) => (async () => new Response('{}', { status })) as typeof fetch
    const m = { sender: { email: 'a@x', name: 'A' }, to: { email: 'b@x' }, subject: 's', html: 'h', text: 't', tag: 'sentral-test' as const }
    expect(await brevoSend('k', m, at(401))).toMatchObject({ auth: true, retryable: true })
    expect(await brevoSend('k', m, at(429))).toMatchObject({ auth: false, retryable: true })
  })
  it('the message carries the tag events are sorted by', async () => {
    let sent: Record<string, unknown> = {}
    const f = (async (_u: unknown, init?: RequestInit) => { sent = JSON.parse(String(init?.body)); return new Response(JSON.stringify({ messageId: '<m@x>' }), { status: 201 }) }) as typeof fetch
    expect(await brevoSend('k', { sender: { email: 'a@x', name: 'A' }, to: { email: 'b@x' }, subject: 's', html: 'h', text: 't', tag: 'sentral-ticket' }, f)).toEqual({ ok: true, id: '<m@x>' })
    expect(sent.tags).toEqual(['sentral-ticket'])
  })
})

describe('Brevo events', () => {
  it('drops every event without a Sentral tag (Orgpuls\'s survey mail shares the account)', () => {
    const s = sortEvents([
      { event: 'delivered', email: 'respondent@x.no', 'message-id': '<a>', tag: 'orgpuls-invitation' },
      { event: 'delivered', email: 'x@y', 'message-id': '<b>' },
    ])
    expect(s).toEqual({ campaign: [], ticket: [], dropped: 2 })
  })
  it('maps Brevo\'s names to Sentral\'s and never keeps the address', () => {
    const s = sortEvents([
      { event: 'hard_bounce', email: 'a@x', 'message-id': '<c1>', tags: ['sentral-campaign'], ts_event: 1760000000 },
      { event: 'soft_bounce', email: 'a@x', 'message-id': '<c2>', tags: ['sentral-campaign'], ts_event: 1760000001 },
      { event: 'spam', email: 'a@x', 'message-id': '<c3>', tags: ['sentral-campaign'] },
      { event: 'proxy_open', email: 'a@x', 'message-id': '<c4>', tags: ['sentral-campaign'] },
      { event: 'click', email: 'a@x', 'message-id': '<c5>', tags: ['sentral-campaign'], link: 'https://orgpuls.com/x' },
      { event: 'delivered', email: 'b@x', 'message-id': '<t1>', tag: 'sentral-ticket' },
      { event: 'opened', email: 'b@x', 'message-id': '<t2>', tag: 'sentral-ticket' },
    ])
    expect(s.campaign.map((e) => [e.kind, e.bounce_kind ?? null, e.client_class ?? null])).toEqual([
      ['bounced', 'hard', null], ['bounced', 'soft', null], ['complained', null, null], ['opened', null, 'prefetch'], ['clicked', null, 'unknown'],
    ])
    expect(s.campaign[4]?.url).toBe('https://orgpuls.com/x')
    expect(s.ticket).toEqual([{ message_id: '<t1>', kind: 'delivered' }])
    expect(s.dropped).toBe(1)
    expect(JSON.stringify(s)).not.toContain('a@x')
  })
  it('reads an inbound answer: id, sender, subject and the new text only', () => {
    const items = inboundItems({ items: [
      { Uuid: ['u-1'], MessageId: '<in@x>', From: { Address: 'kunde@firma.no', Name: 'Kunde' }, Subject: 'Sv: [T-2329] PDF', ExtractedMarkdownMessage: 'Takk!', RawTextBody: 'Takk!\n> sitat' },
      { Uuid: ['u-2'], From: {}, Subject: 'x', RawTextBody: 'y' },
    ] })
    expect(items).toEqual([{ id: 'u-1', from: 'kunde@firma.no', subject: 'Sv: [T-2329] PDF', body: 'Takk!' }])
  })
})

describe('link addresses (0063)', () => {
  it('an application\'s post. host serves the unsubscribe page and nothing else', async () => {
    const { servedOnHost, isLinkHost } = await import('../lib/mail/link-host')
    expect(isLinkHost('post.orgpuls.com')).toBe(true)
    expect(servedOnHost('post.orgpuls.com', '/u/abcdefghijklmnop')).toBe(true)
    expect(servedOnHost('post.orgpuls.com', '/login')).toBe(false)
    expect(servedOnHost('post.orgpuls.com', '/')).toBe(false)
    expect(servedOnHost('post.orgpuls.com', '/uu')).toBe(false)
    expect(servedOnHost('sentral.orgpuls.no', '/login')).toBe(true)
    expect(servedOnHost('postkontor.example', '/login')).toBe(true)
    expect(servedOnHost(null, '/')).toBe(true)
  })
})
