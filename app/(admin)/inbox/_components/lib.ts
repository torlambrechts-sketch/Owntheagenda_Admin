'use client'

import { useCallback, useMemo, useTransition } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'

/** Moves the screen's state in the address (folder, label, thread, compose, group source) without a scroll jump. */
export function useGo() {
  const router = useRouter()
  const path = usePathname()
  const params = useSearchParams()
  const [pending, start] = useTransition()
  const go = useCallback((next: Record<string, string | null>, opts: { reset?: boolean } = {}) => {
    const sp = new URLSearchParams(opts.reset ? '' : params.toString())
    for (const [k, v] of Object.entries(next)) {
      if (v === null || v === '') sp.delete(k)
      else sp.set(k, v)
    }
    const qs = sp.toString()
    start(() => router.replace((qs ? `${path}?${qs}` : path) as never, { scroll: false }))
  }, [params, path, router])
  return { go, pending }
}

const INBOX_CODES = new Set(['mailbox_not_connected', 'merge_missing', 'merge_unknown', 'no_recipient', 'no_subject', 'over_limit', 'no_recipients', 'no_inbound'])

/** A refusal as words: the mail-specific codes have their own messages, the rest are the shared ones. */
export function useFail() {
  const t = useTranslations('inbox.errors')
  const tc = useTranslations('common.errors')
  const flash = useToast()
  const text = useCallback((code: string, detail?: string | null) =>
    INBOX_CODES.has(code) ? t(code as 'mailbox_not_connected', { token: detail ?? '' }) : tc(code as 'failed'), [t, tc])
  const fail = useCallback((code: string, detail?: string | null) => flash(text(code, detail)), [flash, text])
  return { fail, text }
}

/**
 * Times the way the design writes them, in the staff member's time zone: the list says «18:42» today,
 * «Mon» this week and «28 Sep» before; a message says «Today 14:05», «Yesterday 18:42» or «Fri 2 Oct 10:14».
 */
export function useWhen(nowIso: string) {
  const format = useFormatter()
  const t = useTranslations('inbox.when')
  return useMemo(() => {
    const now = new Date(nowIso)
    const day = (d: Date) => format.dateTime(d, { year: 'numeric', month: '2-digit', day: '2-digit' })
    const today = day(now)
    const yesterday = day(new Date(now.getTime() - 86_400_000))
    const time = (d: Date) => format.dateTime(d, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    const short = (iso: string | null) => {
      if (!iso) return ''
      const d = new Date(iso)
      if (day(d) === today) return time(d)
      if (now.getTime() - d.getTime() < 6 * 86_400_000 && d < now) return format.dateTime(d, { weekday: 'short' })
      return t('dayMonth', { day: format.dateTime(d, { day: 'numeric' }), mon: format.dateTime(d, { month: 'short' }) })
    }
    const long = (iso: string | null) => {
      if (!iso) return ''
      const d = new Date(iso)
      const k = day(d)
      if (k === today) return t('today', { time: time(d) })
      if (k === yesterday) return t('yesterday', { time: time(d) })
      // built from parts: Node's and the browser's ICU join a weekday and a date differently («Fri 2 Oct» / «Fri, 2 Oct»)
      return t('date', { wd: format.dateTime(d, { weekday: 'short' }), day: format.dateTime(d, { day: 'numeric' }), mon: format.dateTime(d, { month: 'short' }), time: time(d) })
    }
    return { short, long }
  }, [format, nowIso, t])
}

/** The provider's name as the design writes it. */
export const providerKey = (p: 'google' | 'microsoft') => (p === 'google' ? 'gmail' : 'microsoft')
