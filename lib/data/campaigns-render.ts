import type { Background, Design, Item, Row } from '@/lib/data/campaigns-shared'

/**
 * The one email renderer (V-P6C-01, SF-39): the stored design → email HTML, used by the builder's preview, the
 * test send and scheduling, so what is previewed is what is frozen and sent. The output is table-based with inline
 * styles only, because mail clients drop <style> and the database refuses it (app.doc_html_unsafe: no script,
 * style, meta, link, form or iframe, no on…= attribute, no javascript:). Every text is escaped; an HTML block is
 * passed as written, since the database sanitised it when it was saved.
 *
 * The footer is fixed (D-27): the sender's name and postal address and the one-click unsubscribe link, whose
 * href is the token [Unsubscribe] the send worker replaces per recipient. campaign_schedule refuses HTML without
 * both (V-P6C-23). Merge tokens such as [Person.fornavn] pass through untouched for app.merge_render.
 */

export type RenderInput = {
  /** the design, or hand-written HTML («Code your own HTML»), which is used as written inside the shell */
  design?: Design | null
  html?: string | null
  preheader?: string | null
  sender: { name: string; postalAddress: string | null }
  /** the brand the header prints (the campaign's product, else the sender's name) */
  brand: string
  /** appended to every http(s) link of the design's rows (spec: «The renderer appends the UTM to every tracked link») */
  utm?: { source: string; medium: string; campaign: string } | null
  /** the language of the email's own words (the footer); nb unless the content says otherwise */
  lang?: 'nb' | 'en'
}

export const UNSUBSCRIBE = '[Unsubscribe]'

/** The words the email itself prints (email content, not UI; V-CAMPAIGNS-07). */
export const EMAIL_WORDS = {
  nb: { reason: 'Du får denne e-posten fra {name}.', unsubscribe: 'Meld deg av med ett klikk', play: 'Se videoen' },
  en: { reason: 'You receive this email from {name}.', unsubscribe: 'Unsubscribe with one click', play: 'Watch the video' },
} as const
const WORDS = EMAIL_WORDS

const BG: Record<Background, string> = { card: '#FFFDF6', soft_yellow: '#FBEBBE', mint: '#CFE7E4', cream: '#FCF6E9' }
const INK = '#191510'
const MUTED = '#5F5849'
const LINE = '#E8DFC9'
const SANS = "'DM Sans',Arial,Helvetica,sans-serif"
const SERIF = "'Playfair Display',Georgia,'Times New Roman',serif"

/**
 * Escapes text for HTML, exactly as app.html_escape does (so the sender's postal address is found either raw or
 * escaped), and writes «=» and the colon after «javascript», «vbscript» or «data» as entities, so that ordinary words
 * such as «online = enkelt» never look like an event attribute or a script link to the database's check.
 */
export const escapeHtml = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
const text = (s: string) => escapeHtml(s).replace(/=/g, '&#61;').replace(/(javascript|vbscript|data)(\s*):/gi, '$1$2&#58;')
const multiline = (s: string) => text(s).replace(/\r?\n/g, '<br>')

/** A link the design may carry: http(s), mailto or a merge token; anything else is dropped. */
export function safeHref(href: string | undefined | null): string | null {
  const h = (href ?? '').trim()
  if (!h) return null
  if (/^(https?:\/\/|mailto:)[^\s"<>]+$/i.test(h) || /^\[[A-Za-z][\w.]*\]$/.test(h)) return h
  return null
}

/** The UTM parameters added to an http(s) link (existing parameters and the fragment are kept; set ones win). */
export function withUtm(href: string, utm: RenderInput['utm']): string {
  if (!utm || !/^https?:\/\//i.test(href)) return href
  const [base, hash] = href.split('#', 2) as [string, string | undefined]
  const [path, query] = base.split('?', 2) as [string, string | undefined]
  const params = (query ?? '').split('&').filter(Boolean)
  const has = (k: string) => params.some((p) => p.split('=')[0] === k)
  for (const [k, v] of [['utm_source', utm.source], ['utm_medium', utm.medium], ['utm_campaign', utm.campaign]] as const) {
    if (!has(k)) params.push(`${k}=${encodeURIComponent(v)}`)
  }
  return `${path}?${params.join('&')}${hash !== undefined ? `#${hash}` : ''}`
}

/** An attribute value: a link or source already validated (no quote, angle bracket or space), kept as written so
 * the frozen links match what the send worker rewrites; any other attribute text is escaped like text. */
const attr = (s: string) => s.replace(/"/g, '%22').replace(/</g, '%3C').replace(/>/g, '%3E')

function pad(r: Row): string {
  if (r.kind === 'divider') return `6px ${r.padding ?? 22}px`
  const p = r.padding ?? 22
  return `${Math.max(0, p - 6)}px ${p}px`
}

function cell(r: Row, inner: string, fallbackBg: Background): string {
  const bg = BG[r.bg ?? fallbackBg]
  const border = r.border === 'hairline' ? `border-top:1px solid ${LINE};border-bottom:1px solid ${LINE};` : ''
  return `<tr><td style="padding:${pad(r)};background:${bg};${border}font-family:${SANS};color:${INK};">${inner}</td></tr>`
}

function link(href: string | null, label: string, style: string, utm: RenderInput['utm']): string {
  if (!href) return `<span style="${style}">${text(label)}</span>`
  return `<a href="${attr(withUtm(href, utm))}" style="${style}">${text(label)}</a>`
}

function items(r: Row): Item[] {
  return (r.items ?? []).filter((x) => (typeof x === 'string' ? x.trim() : x.label.trim()))
}
const label = (x: Item) => (typeof x === 'string' ? x : x.label)
const href = (x: Item) => (typeof x === 'string' ? null : safeHref(x.href))

function row(r: Row, input: RenderInput): string {
  const utm = input.utm
  const w = WORDS[input.lang ?? 'nb']
  switch (r.kind) {
    case 'header':
      return cell(r, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>`
        + `<td style="font-family:${SERIF};font-size:17px;font-weight:700;color:${INK};">${text(input.brand)}</td>`
        + `<td align="right" style="font-family:${SANS};font-size:11px;color:${MUTED};">${text(r.text ?? '')}</td></tr></table>`, 'card')
    case 'title':
      if (!r.text?.trim()) return ''
      return cell(r, `<h1 style="margin:0;font-family:${SERIF};font-size:${r.fs ?? 22}px;font-weight:600;line-height:1.15;color:${INK};">${multiline(r.text)}</h1>`, 'card')
    case 'paragraph':
      if (!r.text?.trim()) return ''
      return cell(r, `<p style="margin:0;font-size:13.5px;line-height:1.65;color:#3A342A;">${multiline(r.text)}</p>`, 'card')
    case 'list': {
      const xs = items(r)
      if (!xs.length) return ''
      return cell(r, xs.map((x) => `<p style="margin:0 0 6px 0;font-size:13px;line-height:1.5;color:${INK};">&#10003; ${text(label(x))}</p>`).join(''), 'card')
    }
    case 'image': {
      const src = r.src && /^https:\/\/[^\s"<>]+$/.test(r.src.trim()) ? r.src.trim() : null
      if (!src) return ''
      const img = `<img src="${attr(src)}" alt="${text(r.alt ?? '')}" width="556" style="display:block;width:100%;max-width:556px;height:auto;border:0;border-radius:10px;">`
      const h = safeHref(r.href)
      return cell(r, h ? `<a href="${attr(withUtm(h, utm))}">${img}</a>` : img, 'card')
    }
    case 'video': {
      const h = safeHref(r.href)
      if (!h) return ''
      const src = r.src && /^https:\/\/[^\s"<>]+$/.test(r.src.trim()) ? r.src.trim() : null
      const inner = src
        ? `<img src="${attr(src)}" alt="${text(r.alt ?? w.play)}" width="556" style="display:block;width:100%;max-width:556px;height:auto;border:0;border-radius:10px;">`
        : `<span style="font-size:14px;font-weight:700;color:${INK};">&#9654; ${text(r.text?.trim() || w.play)}</span>`
      return cell(r, `<a href="${attr(withUtm(h, utm))}" style="text-decoration:none;color:${INK};">${inner}</a>`, 'card')
    }
    case 'button': {
      if (!r.text?.trim()) return ''
      const h = safeHref(r.href)
      const style = `display:inline-block;padding:12px 20px;border-radius:12px;border:1px solid ${INK};background:#F5C64A;font-family:${SANS};font-size:14px;font-weight:700;color:${INK};text-decoration:none;`
      return cell(r, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td align="center">${link(h, r.text, style, utm)}</td></tr></table>`, 'card')
    }
    case 'divider':
      return cell(r, `<div style="height:1px;line-height:1px;font-size:1px;background:${LINE};">&nbsp;</div>`, 'card')
    case 'social':
    case 'menu': {
      const xs = items(r)
      if (!xs.length) return ''
      const style = `font-family:${SANS};font-size:12px;font-weight:700;color:${INK};text-decoration:none;`
      return cell(r, `<p style="margin:0;text-align:center;">${xs.map((x) => link(href(x), label(x), style, utm)).join('&nbsp;&nbsp;&nbsp;')}</p>`, 'card')
    }
    case 'icons': {
      const xs = items(r)
      if (!xs.length) return ''
      const style = `font-family:${SANS};font-size:12.5px;color:${INK};text-decoration:none;`
      return cell(r, `<p style="margin:0;text-align:center;">${xs.map((x) => `&#9679;&nbsp;${link(href(x), label(x), style, utm)}`).join('&nbsp;&nbsp;&nbsp;')}</p>`, 'card')
    }
    case 'html':
      if (!r.html?.trim()) return ''
      return cell(r, r.html, 'card')
    case 'footer':
      return footer(r.bg ?? 'cream', input)
  }
}

function footer(bg: Background, input: RenderInput): string {
  const w = WORDS[input.lang ?? 'nb']
  // the postal address is escaped exactly as app.html_escape does (no «=» entity), so campaign_schedule finds it
  const address = input.sender.postalAddress ? escapeHtml(input.sender.postalAddress) : ''
  const who = text(input.sender.name)
  const reason = text(w.reason.replace('{name}', '\u0000')).replace('\u0000', who)
  return `<tr><td style="padding:16px 22px;background:${BG[bg]};font-family:${SANS};font-size:11px;line-height:1.6;color:${MUTED};text-align:center;">`
    + `${address ? `${address}<br>` : ''}${reason}<br>`
    + `<a href="${UNSUBSCRIBE}" style="color:${MUTED};text-decoration:underline;">${text(w.unsubscribe)}</a></td></tr>`
}

/** The email: a centred 600 px card (360 px on a phone, the same HTML), the preheader hidden at the top. */
export function renderEmail(input: RenderInput): string {
  const pre = input.preheader?.trim()
    ? `<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${text(input.preheader.trim())}</div>`
    : ''
  let body: string
  if (input.html && input.html.trim()) {
    body = `<tr><td style="font-family:${SANS};color:${INK};">${input.html}</td></tr>`
  } else {
    const rows = input.design?.rows ?? []
    const hasFooter = rows.some((r) => r.kind === 'footer')
    body = rows.map((r) => row(r, input)).join('') + (hasFooter ? '' : footer('cream', input))
  }
  return `<!DOCTYPE html><html lang="${input.lang ?? 'nb'}"><body style="margin:0;padding:0;background:#FCF6E9;">${pre}`
    + `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#FCF6E9;"><tr><td align="center" style="padding:24px 12px;">`
    + `<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;background:#FFFDF6;border:1px solid ${LINE};border-radius:14px;border-collapse:separate;overflow:hidden;">`
    + body
    + `</table></td></tr></table></body></html>`
}

/** What campaign_schedule will check, so the builder can say it before the database refuses (V-P6C-23). */
export function footerProblems(html: string, postalAddress: string | null): ('unsubscribe' | 'address')[] {
  const out: ('unsubscribe' | 'address')[] = []
  if (!html.includes(UNSUBSCRIBE)) out.push('unsubscribe')
  if (!postalAddress || !(html.includes(postalAddress) || html.includes(escapeHtml(postalAddress)))) out.push('address')
  return out
}
