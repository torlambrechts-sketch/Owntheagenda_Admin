'use client'

import { useCallback, useTransition } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'

/** The design's priority tones (Tickets.dc.html, ptone): chip background, chip ink, list bar. */
export const PTONE = {
  urgent: { bg: 'bg-salmon', ink: 'text-rust-ink', bar: 'bg-alert' },
  high: { bg: 'bg-amber-bg', ink: 'text-amber-ink', bar: 'bg-warn' },
  normal: { bg: 'bg-teal-soft', ink: 'text-ok-ink', bar: 'bg-teal-mid' },
  low: { bg: 'bg-[rgba(25,21,16,.06)]', ink: 'text-muted', bar: 'bg-line-strong' },
} as const

/** The design's company status tones (statusTone). */
export const STATUS_TONE: Record<string, string> = {
  active: 'bg-ok-bg text-ok-ink',
  trial: 'bg-highlight text-amber-ink',
  past_due: 'bg-salmon text-rust-ink',
  suspended: 'bg-peach text-rust-ink',
  cancelled: 'bg-[rgba(25,21,16,.06)] text-muted',
  free: 'bg-[rgba(25,21,16,.06)] text-muted',
  expired: 'bg-[rgba(25,21,16,.06)] text-muted',
}

/** The priority that impact × urgency gives (app.ticket_priority, 0012): shown at once, stored by the database. */
export const priorityOf = (impact: string, urgency: string) =>
  impact === 'many_orgs' && urgency === 'blocking' ? 'urgent' : impact === 'many_orgs' || urgency === 'blocking' ? 'high' : impact === 'one_org' ? 'normal' : 'low'

/** A business day is eight hours (business_hours, Mon–Fri 08–16). */
export const DAY_MIN = 480

/** Durations the way the design writes them: «40 min», «3 h», «1 h 40 min»; `short` drops the minutes over an hour. */
export function useDur() {
  const t = useTranslations('tickets.dur')
  return useCallback((min: number, short = false) => {
    const m = Math.max(0, Math.round(Math.abs(min)))
    if (m < 60) return t('m', { m })
    const h = Math.floor(m / 60)
    const r = m % 60
    return short || r === 0 ? t('h', { h }) : t('hm', { h, m: r })
  }, [t])
}

/** A target as the SLA policy states it: whole business days as days, else hours. */
export function useTarget() {
  const t = useTranslations('tickets.dur')
  return useCallback((min: number, business = false) =>
    min % DAY_MIN === 0 ? t(business ? 'bdays' : 'days', { n: min / DAY_MIN }) : t('h', { h: Math.round((min / 60) * 10) / 10 }), [t])
}

/** A label for a key the database owns (category, queue): the message when there is one, else the stored name. */
export function useLabel(ns: 'categories' | 'queues') {
  const t = useTranslations(`tickets.${ns}`)
  return useCallback((key: string, fallback?: string | null) => (t.has(key) ? t(key) : fallback ?? key), [t])
}

/** Moves the screen's state in the address (tab, view, filter, sort, the open ticket) without a scroll jump. */
export function useGo() {
  const router = useRouter()
  const path = usePathname()
  const params = useSearchParams()
  const [pending, start] = useTransition()
  const go = useCallback((next: Record<string, string | null>, opts: { reset?: boolean; push?: boolean } = {}) => {
    const sp = new URLSearchParams(opts.reset ? '' : params.toString())
    for (const [k, v] of Object.entries(next)) {
      if (v === null || v === '') sp.delete(k)
      else sp.set(k, v)
    }
    const qs = sp.toString()
    start(() => {
      const href = (qs ? `${path}?${qs}` : path) as never
      if (opts.push) router.push(href, { scroll: false })
      else router.replace(href, { scroll: false })
    })
  }, [params, path, router])
  return { go, pending }
}

/** Two letters for an avatar when the database has no initials. */
export const initialsOf = (name: string | null | undefined) =>
  (name ?? '?').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join('') || '?'

export const orgNumber = (n: string | null | undefined) => (n ? n.replace(/^(\d{3})(\d{3})(\d{3})$/, '$1 $2 $3') : null)
