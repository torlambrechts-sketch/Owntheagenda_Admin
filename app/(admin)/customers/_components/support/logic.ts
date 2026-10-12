/**
 * Pure rules for Customers › Help centre and support (0081), shared by the views and tests/v3-support.test.ts. Nothing here
 * reads the database or the clock; every figure it shapes comes from a parsed RPC result.
 */

export const SUBS = ['metrics', 'widget', 'center', 'channels', 'portal', 'assist', 'proactive'] as const
export type Sub = (typeof SUBS)[number]

// the values the database knows (0081); lib/data/support-hub.ts parses with them
export const LOCALES = ['nb', 'nn', 'en'] as const
export type Locale = (typeof LOCALES)[number]
export const CHANNELS = ['in_app', 'contact_form', 'email', 'staff'] as const
export const COMPONENT_STATES = ['operational', 'degraded', 'partial_outage', 'maintenance'] as const
export const INCIDENT_STATES = ['investigating', 'identified', 'monitoring', 'resolved'] as const

/**
 * A change in tickets created against the previous period: a percentage only when the previous period was fully collected
 * and had tickets; fewer tickets count as good (the design's «fewer than last month»).
 */
export function ticketsDelta(created: number, previous: number, complete: boolean): { pct: number; direction: 'fewer' | 'more' | 'same'; good: boolean } | null {
  if (!complete || previous <= 0) return null
  const pct = Math.round(((created - previous) / previous) * 100)
  const direction = created < previous ? 'fewer' : created > previous ? 'more' : 'same'
  return { pct, direction, good: direction !== 'more' }
}

/** CSAT against the previous period: one decimal, higher is good; none without both averages */
export function csatDelta(avg: number | null, previous: number | null): { diff: number; good: boolean } | null {
  if (avg === null || previous === null) return null
  const diff = Math.round((avg - previous) * 10) / 10
  return { diff, good: diff >= 0 }
}

/** shares of a total in whole percent; an empty total gives no shares */
export function shares(counts: number[]): (number | null)[] {
  const total = counts.reduce((a, b) => a + b, 0)
  return counts.map((c) => (total > 0 ? Math.round((c / total) * 100) : null))
}

/**
 * Claude's answer from published articles (app.ai_ctx_help_answer_preview asks for this shape): the text, then a last line
 * «SOURCE: <title>», or exactly NO_ARTICLE. A source counts only when it names one of the product's published articles.
 */
export type ParsedAnswer = { kind: 'answer'; text: string; source: string | null } | { kind: 'none' }
export function parseAnswer(body: string, titles: string[]): ParsedAnswer {
  const trimmed = body.trim()
  if (!trimmed || /^NO_ARTICLE\.?$/i.test(trimmed)) return { kind: 'none' }
  const lines = trimmed.split(/\r?\n/)
  let source: string | null = null
  const last = lines[lines.length - 1] ?? ''
  const m = /^\s*(?:SOURCE|KILDE)\s*:\s*(.+?)\s*$/i.exec(last)
  if (m) {
    lines.pop()
    const named = m[1]!.replace(/^[«"']|[»"']$/g, '').trim().toLowerCase()
    source = titles.find((t) => t.trim().toLowerCase() === named) ?? null
  }
  const text = lines.join('\n').trim()
  if (!text || /^NO_ARTICLE\.?$/i.test(text)) return { kind: 'none' }
  return { kind: 'answer', text, source }
}

/** a search snippet with its hits marked ⟦…⟧ by ts_headline, split into plain and highlighted runs */
export function snippetRuns(s: string): { text: string; hit: boolean }[] {
  const out: { text: string; hit: boolean }[] = []
  const re = /⟦([^⟧]*)⟧/g
  let at = 0
  for (let m = re.exec(s); m; m = re.exec(s)) {
    if (m.index > at) out.push({ text: s.slice(at, m.index), hit: false })
    out.push({ text: m[1]!, hit: true })
    at = m.index + m[0].length
  }
  if (at < s.length) out.push({ text: s.slice(at), hit: false })
  return out
}

/** an app path an article may be suggested on: the same rule as app.help_path_ok (never a respondent page) */
export const helpPathOk = (p: string) => /^\/[a-z0-9/_-]{0,120}$/.test(p) && !/^\/s(\/|$)/.test(p)

/** the articles suggested on one app page, newest first, at most three (the design's «Suggested for this page») */
export function suggestedFor(page: string, articles: { id: string; title: string; app_pages: string[] }[], max = 3) {
  return articles.filter((a) => a.app_pages.includes(page)).slice(0, max)
}

/** the status select's colour, by state (SupportHub.dc.html: Operational, Maintenance, the rest) */
export const componentTone = (state: string) =>
  state === 'operational' ? 'bg-ok-bg' : state === 'maintenance' ? 'bg-teal-soft' : 'bg-amber-bg'

/** a changelog row's kind chip (New, Improved, Fixed) */
export const kindTone = (kind: string) => (kind === 'new' ? 'bg-ok-bg' : kind === 'improved' ? 'bg-teal-soft' : 'bg-highlight')
