'use client'

import { useCallback } from 'react'
import { useFormatter, useTranslations } from 'next-intl'

export type Product = { key: string; name: string; color: string }
export type Fail = { ok: false; code: string; detail?: string | null }

/**
 * A refusal in words: the screen's own message for a code and its detail when it has one (not_connected · pdf,
 * invalid · merge …), else the common message for the code.
 */
export function useError() {
  const t = useTranslations('documents.errors')
  const tc = useTranslations('common.errors')
  return useCallback((r: { code: string; detail?: string | null }) => {
    const key = r.detail ? `${r.code}_${r.detail.replace(/[^a-z_]/gi, '_')}` : r.code
    if (r.detail && t.has(key)) return t(key)
    if (t.has(r.code)) return t(r.code)
    return tc.has(r.code) ? tc(r.code) : tc('failed')
  }, [t, tc])
}

const DAY = 86_400_000

/** The design's view times: «Yesterday 18:40», «Today 09:12», «3 Oct 09:12». */
export function useWhen() {
  const t = useTranslations('documents.when')
  const f = useFormatter()
  return useCallback((iso: string) => {
    const d = new Date(iso)
    const now = new Date()
    const key = (x: Date) => f.dateTime(x, { year: 'numeric', month: '2-digit', day: '2-digit' })
    const time = f.dateTime(d, { hour: '2-digit', minute: '2-digit' })
    if (key(d) === key(now)) return t('today', { time })
    if (key(d) === key(new Date(now.getTime() - DAY))) return t('yesterday', { time })
    const sameYear = f.dateTime(d, { year: 'numeric' }) === f.dateTime(now, { year: 'numeric' })
    return `${f.dateTime(d, sameYear ? { day: 'numeric', month: 'short' } : { day: 'numeric', month: 'short', year: 'numeric' })} ${time}`
  }, [f, t])
}

/** A date in the staff member's language: «5 Oct 2026». */
export function useDate() {
  const f = useFormatter()
  return useCallback((iso: string) => f.dateTime(new Date(iso), { day: 'numeric', month: 'short', year: 'numeric' }), [f])
}

/** The URL a link path will have on the public host (D-28). */
export const publicUrl = (host: string, path: string) => `${host}${path}`

/** Writes to the clipboard; false where the browser refuses. */
export async function copyText(text: string) {
  try { await navigator.clipboard.writeText(text); return true } catch { return false }
}

export const mono = '[font-family:ui-monospace,Menlo,monospace]'
