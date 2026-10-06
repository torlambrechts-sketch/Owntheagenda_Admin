'use client'

import { useCallback, useEffect, useRef, useTransition } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'

export const TABS = ['list', 'builder', 'templates', 'monitor', 'assign', 'sequences'] as const
export type Tab = (typeof TABS)[number]

/** Change the address (tab, workflow, sequence): the page reads it on the server. */
export function useGo() {
  const router = useRouter()
  const path = usePathname()
  const sp = useSearchParams()
  const [pending, start] = useTransition()
  const go = useCallback((patch: Record<string, string | null>, opts: { reset?: boolean } = {}) => {
    const next = new URLSearchParams(opts.reset ? '' : sp.toString())
    for (const [k, v] of Object.entries(patch)) if (v === null) next.delete(k); else next.set(k, v)
    const qs = next.toString()
    start(() => router.push((qs ? `${path}?${qs}` : path) as never, { scroll: false }))
  }, [router, path, sp])
  return { go, pending }
}

/** A refusal code as words: the screen's own message for a detail (a blocker), else the common one. */
export function useErrorText() {
  const t = useTranslations('automation.errors')
  const c = useTranslations('common.errors')
  return useCallback((code: string, detail?: string | null) => {
    const d = (detail ?? '').replace(':', '_')
    if (d && t.has(d)) return t(d)
    if (detail?.startsWith('graph.')) return t('graph')
    return c.has(code) ? c(code) : c('failed')
  }, [t, c])
}

/** A blocker from app.wf_blockers as a short phrase («Slack is not connected»). */
export function useBlockerText() {
  const t = useTranslations('automation.blockers')
  return useCallback((b: string) => { const k = b.replace(':', '_'); return t.has(k) ? t(k) : b }, [t])
}

const OPS: Record<string, string> = { eq: '=', neq: '≠', gt: '>', gte: '≥', lt: '<', lte: '≤' }

/** Labels for record types, events, fields and filters, from the messages (unknown keys read as words). */
export function useWords() {
  const t = useTranslations('automation.words')
  const human = (k: string) => k.replace(/^custom\./, '').replace(/_/g, ' ')
  const pick = useCallback((group: string, k: string) => (t.has(`${group}.${k}`) ? t(`${group}.${k}`) : human(k)), [t])
  const filter = useCallback((f: Record<string, unknown>, labels: Map<string, string>): string => {
    const field = String(f.f ?? '')
    const op = String(f.op ?? 'eq')
    const v = f.v
    if (field.startsWith('email.')) return t(`mailTest.${field.slice(6)}`, { days: Number(v ?? 7) })
    const val = (x: unknown) => (typeof x === 'string' && labels.has(x) ? labels.get(x)! : Array.isArray(x) ? x.map((y) => (typeof y === 'string' && labels.get(y)) || String(y)).join(', ') : String(x ?? ''))
    const name = (f.rel ? `${pick('fields', String(f.rel).replace(/_id$/, ''))} · ` : '') + pick('fields', field)
    if (op === 'empty' || op === 'notempty') return `${name} ${t(`ops.${op}`)}`
    if (OPS[op]) return `${name} ${OPS[op]} ${val(v)}`
    return `${name} ${t.has(`ops.${op}`) ? t(`ops.${op}`) : op} ${val(v)}`
  }, [t, pick])
  const groups = useCallback((g: unknown, labels: Map<string, string>): string[] => {
    if (!Array.isArray(g)) return []
    return g.map((grp) => (Array.isArray(grp) ? grp : [grp]).filter((x) => x && typeof x === 'object').map((x) => filter(x as Record<string, unknown>, labels)).join(` ${t('and')} `))
  }, [filter, t])
  return { t, pick, filter, groups }
}

/** A workflow's trigger in words, the way the design's list writes it («Deal updated · status = won»). */
export function useTriggerText() {
  const w = useWords()
  return useCallback((type: string, c: Record<string, unknown>, labels: Map<string, string> = new Map()) => {
    const parts: string[] = []
    if (type === 'event') {
      parts.push(w.t('trigger.event', { entity: w.pick('entity', String(c.entity ?? '')), event: w.pick('event', String(c.event ?? '')) }))
      if (Array.isArray(c.fields) && c.fields.length) parts.push(w.t('trigger.fields', { fields: c.fields.map((f) => w.pick('fields', String(f))).join(', ') }))
    } else if (type === 'date') {
      const off = Number(c.offset_days ?? 0)
      const date = w.pick('dates', String(c.date ?? ''))
      parts.push(w.t('trigger.date', { text: w.t('trigger.dateWhen', { n: Math.abs(off), date, when: off > 0 ? 'after' : off < 0 ? 'before' : 'on' }) }))
    } else if (type === 'product_event') {
      parts.push(w.t('trigger.product', { kind: String(c.kind ?? '') }))
      if (c.data && typeof c.data === 'object') for (const [k, v] of Object.entries(c.data)) parts.push(`${w.pick('fields', k)} = ${String(v)}`)
    } else {
      parts.push(w.t('trigger.enrollment'))
    }
    const g = w.groups(c.groups, labels)
    if (g.length) parts.push(g.join(` ${w.t('or')} `))
    return parts.join(' · ')
  }, [w])
}

/** Run a callback a moment after the last change (the assignment test as the form is typed). */
export function useDebounced<T>(value: T, ms: number, fn: (v: T) => void) {
  const f = useRef(fn)
  useEffect(() => { f.current = fn })
  useEffect(() => {
    const h = setTimeout(() => f.current(value), ms)
    return () => clearTimeout(h)
  }, [value, ms])
}

/** The design's pill tones: state chips and step chips. */
export const TONE = {
  ok: 'bg-ok-bg text-ok-ink',
  draft: 'bg-tile text-muted',
  fail: 'bg-salmon text-rust-ink',
  wait: 'bg-highlight text-amber-ink',
} as const

export type Rights = { deals: boolean; tickets: boolean; configure: boolean; seeDeals: boolean; bulk: boolean; editOthers: boolean }

/** The scope a workflow belongs to (app.wf_scope): that of the record type it runs on, deals otherwise. */
export const wfScope = (w: { trigger_type: string; trigger_config: Record<string, unknown> }) =>
  (w.trigger_type === 'event' || w.trigger_type === 'date') && w.trigger_config.entity === 'ticket' ? 'tickets' : 'deals'

/** May this staff member change the workflow? Its owner or a configurer, with «Manage workflows» in its scope. */
export const canChange = (w: { owner_id: string; trigger_type: string; trigger_config: Record<string, unknown> }, me: string, r: Rights) =>
  (w.owner_id === me || r.configure) && r[wfScope(w)]
