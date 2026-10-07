'use client'

import { useCallback, useMemo } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import type { LinkRef, State } from '@/lib/data/meetings'
import { weekdayDate } from './kit'

/** The labels the list, the header and the cards derive from a meeting's stored state (never prose from the database). */
export function useMeetingText() {
  const t = useTranslations('meetings')
  const f = useFormatter()

  const relDay = useCallback((iso: string | null | undefined) => {
    if (!iso) return t('dash')
    const d = new Date(iso)
    const days = Math.round((new Date(d.toDateString()).getTime() - new Date(new Date().toDateString()).getTime()) / 86400000)
    if (days === 0) return t('rel.today')
    if (days === 1) return t('rel.tomorrow')
    return weekdayDate(f, d)
  }, [f, t])

  /** The state label (§2.1, V-P7M-09); none → «Not recorded», never an invented state. */
  const state = useCallback((s: State | null, capture: string, short = false) => {
    if (!s) return capture === 'upload' ? t('state.uploaded') : t('state.none')
    switch (s.key) {
      case 'suggestions': return t('state.suggestions', { n: s.n ?? 0 })
      case 'notice_due': return t('state.notice_due', { day: relDay(s.at) })
      case 'recording_blocked': return short ? t('state.recording_blocked_short') : t('state.recording_blocked', { reason: t(`reason.${s.reason ?? 'other'}`) })
      case 'transcription_failed': return t('state.transcription_failed')
      default: return t(`state.${s.key}`)
    }
  }, [t, relDay])

  const via = useCallback((conference: string | null, capture: string) => {
    const parts = [conference ? t(`conference.${conference}`) : null, capture !== 'none' ? t(`via.${capture}`) : null].filter(Boolean)
    return parts.length ? parts.join(' · ') : t('dash')
  }, [t])

  const link = useCallback((l: LinkRef | null) => {
    if (!l) return null
    if (l.entity === 'lead') return t('linkLabel.lead', { seq: l.seq ?? 0, title: l.title ?? '' })
    return l.title ?? t('dash')
  }, [t])

  return useMemo(() => ({ state, via, link, relDay }), [state, via, link, relDay])
}
