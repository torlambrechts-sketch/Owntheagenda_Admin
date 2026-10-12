/**
 * The transactional emails Sentral sends through Brevo (0060): a ticket reply, an invitation, an MFA reminder, a security
 * alert, an SEO alert (0074) and the owner's test. Plain, table-free HTML (one column, inline styles) with a text part; every text is escaped.
 * Pure functions: the edge functions and the tests (Node) run the same code. Texts come from messages/{en,no}/mail.json
 * through mail-texts.gen.ts.
 */
import { MAIL_TEXTS } from './mail-texts.gen.ts'

export type Lang = 'en' | 'no'
export type Rendered = { subject: string; html: string; text: string }

export const langOf = (l: string | null | undefined): Lang => (l === 'en' ? 'en' : 'no')

export const escapeHtml = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')

/** «{name}» placeholders, from a flat map; a missing value leaves nothing behind */
export const fill = (s: string, v: Record<string, string | null | undefined>) => s.replace(/\{(\w+)\}/g, (_, k) => v[k] ?? '')

const INK = '#191510'
const MUTED = '#5F5849'
const LINE = '#E8DFC9'

function page(blocks: string[], footer: string): string {
  return '<!doctype html><html><body style="margin:0;padding:0;background:#FCF6E9;">'
    + '<div style="max-width:560px;margin:0 auto;padding:28px 20px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.55;color:' + INK + ';">'
    + blocks.join('')
    + '<p style="margin:28px 0 0;padding-top:14px;border-top:1px solid ' + LINE + ';font-size:12px;color:' + MUTED + ';">' + escapeHtml(footer) + '</p>'
    + '</div></body></html>'
}
const para = (s: string, muted = false) =>
  `<p style="margin:0 0 14px;${muted ? `color:${MUTED};font-size:13px;` : ''}">${escapeHtml(s).replace(/\r?\n/g, '<br>')}</p>`
const button = (label: string, href: string | null) => !href ? '' :
  `<p style="margin:20px 0;"><a href="${escapeHtml(href)}" style="display:inline-block;padding:11px 18px;border-radius:10px;border:1px solid ${INK};background:#F5C64A;color:${INK};font-weight:bold;text-decoration:none;">${escapeHtml(label)}</a></p>`

/** a link Sentral builds must stay on the public address the owner saved */
export function safeLink(base: string, path: string): string {
  const u = new URL(path, base.endsWith('/') ? base : `${base}/`)
  if (u.origin !== new URL(base).origin || u.protocol !== 'https:') throw new Error('link_outside_base')
  return u.toString()
}

export function ticketReply(m: { lang: Lang; ref: string; subject: string; body: string; agent: string | null; fromName: string; csat?: string[] | null }): Rendered {
  const t = MAIL_TEXTS[m.lang]
  const subject = fill(t.ticketReply.subject, { ref: m.ref, subject: m.subject }).slice(0, 250)
  const sig = fill(t.ticketReply.signature, { agent: m.agent ?? m.fromName, from_name: m.fromName })
  const answer = fill(t.ticketReply.answer, { ref: m.ref })
  // the customer hears from the application only; Sentral is not named to them
  const footer = fill(t.ticketReply.footer, { from_name: m.fromName })
  const csat = m.csat && m.csat.length === 5 ? csatBlock(m.lang, m.csat) : null
  return {
    subject,
    html: page([para(m.body), para(sig), ...(csat ? [csat.html] : []), para(answer, true)], footer),
    text: [m.body, sig, csat?.text, answer, `— ${footer}`].filter(Boolean).join('\n\n'),
  }
}

/**
 * The CSAT question on the reply that resolves a ticket (0081): five links, one per score, each opening the csat function
 * with the ticket's single-use token. The links are built by the caller; this only lays them out.
 */
function csatBlock(lang: Lang, links: string[]): { html: string; text: string } {
  const c = MAIL_TEXTS[lang].csat.mail
  const cell = (href: string, n: number) =>
    `<a href="${escapeHtml(href)}" style="display:inline-block;width:38px;padding:9px 0;margin:0 6px 6px 0;border-radius:10px;border:1px solid ${INK};background:#FFFDF6;color:${INK};font-weight:bold;text-align:center;text-decoration:none;">${n}</a>`
  const html = `<div style="margin:22px 0 14px;padding:14px 16px;border-radius:14px;border:1px solid ${LINE};background:#FFFDF6;">`
    + `<p style="margin:0 0 6px;font-weight:bold;">${escapeHtml(c.question)}</p>`
    + `<p style="margin:0 0 12px;color:${MUTED};font-size:13px;">${escapeHtml(c.scale)}</p>`
    + `<div>${links.map((l, i) => cell(l, i + 1)).join('')}</div>`
    + `<p style="margin:4px 0 0;color:${MUTED};font-size:12px;">1 = ${escapeHtml(c.low)} · 5 = ${escapeHtml(c.high)}</p>`
    + '</div>'
  const text = [c.question, c.scale, ...links.map((l, i) => `${i + 1}: ${l}`)].join('\n')
  return { html, text }
}

/** the five CSAT links for one token: the csat function's address, the score and the email's language */
export function csatLinks(functionsUrl: string, token: string, lang: Lang): string[] | null {
  if (!/^[A-Za-z0-9_-]{32}$/.test(token)) return null
  let base: URL
  try {
    base = new URL('/functions/v1/csat', functionsUrl)
  } catch {
    return null
  }
  if (base.protocol !== 'https:' && base.protocol !== 'http:') return null
  return [1, 2, 3, 4, 5].map((s) => {
    const u = new URL(base)
    u.searchParams.set('t', token)
    u.searchParams.set('s', String(s))
    u.searchParams.set('l', lang)
    return u.toString()
  })
}

export function invite(m: { lang: Lang; by: string | null; link: string; fromName: string }): Rendered {
  const t = MAIL_TEXTS[m.lang].invite
  const lead = m.by ? fill(t.lead, { by: m.by }) : t.leadNoName
  const footer = fill(MAIL_TEXTS[m.lang].common.footer, { from_name: m.fromName })
  return {
    subject: t.subject,
    html: page([para(lead), para(t.body), button(t.button, m.link), para(t.expiry, true)], footer),
    text: `${lead}\n\n${t.body}\n\n${t.button}: ${m.link}\n\n${t.expiry}\n\n— ${footer}`,
  }
}

export function mfaReminder(m: { lang: Lang; by: string | null; link: string | null; fromName: string }): Rendered {
  const t = MAIL_TEXTS[m.lang].mfa
  const lead = m.by ? fill(t.lead, { by: m.by }) : t.leadNoName
  const footer = fill(MAIL_TEXTS[m.lang].common.footer, { from_name: m.fromName })
  return {
    subject: t.subject,
    html: page([para(lead), para(t.body), button(t.button, m.link)], footer),
    text: [lead, t.body, m.link ? `${t.button}: ${m.link}` : null, `— ${footer}`].filter(Boolean).join('\n\n'),
  }
}

export function securityAlert(m: { lang: Lang; kind: string; staff: string | null; at: string; link: string | null; fromName: string }): Rendered {
  const t = MAIL_TEXTS[m.lang].alert
  const kinds = t.kinds as Record<string, string>
  const title = kinds[m.kind] ?? m.kind
  const when = fill(t.when, { at: new Date(m.at).toLocaleString(m.lang === 'en' ? 'en-GB' : 'nb-NO', { timeZone: 'Europe/Oslo', dateStyle: 'medium', timeStyle: 'short' }) })
  const about = m.staff ? fill(t.about, { staff: m.staff }) : null
  const footer = fill(MAIL_TEXTS[m.lang].common.footer, { from_name: m.fromName })
  const blocks = [para(fill(t.lead, { title })), ...(about ? [para(about)] : []), para(when, true), para(t.body), button(t.button, m.link)]
  return {
    subject: fill(t.subject, { title }),
    html: page(blocks, footer),
    text: [fill(t.lead, { title }), about, when, t.body, m.link ? `${t.button}: ${m.link}` : null, `— ${footer}`].filter(Boolean).join('\n\n'),
  }
}

/** an SEO alert (0074): the rule's sentence with its figures, the site, when, and a link to Growth › SEO › Alerts */
export function seoAlert(m: { lang: Lang; rule: string; params: Record<string, unknown>; site: string; at: string; link: string | null; fromName: string }): Rendered {
  const t = MAIL_TEXTS[m.lang].seoAlert
  const titles = t.titles as Record<string, string>
  const num = (v: unknown) => (typeof v === 'number' ? v.toLocaleString(m.lang === 'en' ? 'en-GB' : 'nb-NO', { maximumFractionDigits: 1 }) : typeof v === 'string' ? v : '')
  const p = Object.fromEntries(Object.entries(m.params ?? {}).map(([k, v]) => [k, num(v)]))
  const key = m.rule === 'cwv' ? (p.metric === 'inp' ? 'cwv_inp' : 'cwv_lcp') : m.rule
  const title = fill(titles[key] ?? m.rule, p)
  const when = fill(t.when, { at: new Date(m.at).toLocaleString(m.lang === 'en' ? 'en-GB' : 'nb-NO', { timeZone: 'Europe/Oslo', dateStyle: 'medium', timeStyle: 'short' }) })
  const footer = fill(MAIL_TEXTS[m.lang].common.footer, { from_name: m.fromName })
  return {
    subject: fill(t.subject, { site: m.site, title }),
    html: page([para(fill(t.lead, { title })), para(when, true), para(t.body), button(t.button, m.link)], footer),
    text: [fill(t.lead, { title }), when, t.body, m.link ? `${t.button}: ${m.link}` : null, `— ${footer}`].filter(Boolean).join('\n\n'),
  }
}

export function testMail(m: { lang: Lang; from: string; fromName: string }): Rendered {
  const t = MAIL_TEXTS[m.lang].test
  const body = fill(t.body, { from: m.from })
  const footer = fill(MAIL_TEXTS[m.lang].common.footer, { from_name: m.fromName })
  return { subject: t.subject, html: page([para(body), para(t.note, true)], footer), text: `${body}\n\n${t.note}\n\n— ${footer}` }
}

/** a campaign's frozen HTML for one recipient: the [Unsubscribe] token becomes the person's own page */
export function campaignHtml(html: string, unsubscribeUrl: string): string {
  return html.split('[Unsubscribe]').join(escapeHtml(unsubscribeUrl))
}

/** a plain-text part for a campaign's HTML: links kept as «text (url)», tags dropped, entities read */
export function htmlToText(html: string): string {
  return html
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, '')
    .replace(/<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, (_, href: string, label: string) => `${label.replace(/<[^>]+>/g, '').trim()} (${href})`)
    .replace(/<br\s*\/?>(?!\n)/gi, '\n').replace(/<\/(p|div|tr|h[1-6]|li|table)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#(\d+);/g, (_, n: string) => String.fromCharCode(Number(n))).replace(/&amp;/g, '&')
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()
}
