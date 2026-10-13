'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { addKeyword, removeKeyword } from '../actions'

/** «Track a keyword» (the keyword table's head: input 170 px, height 32, and Track) */
export function KeywordTrack({ product, site = null, connected }: { product: string; site?: string | null; connected: boolean }) {
  const t = useTranslations('simpleGrowth.keywords')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [kw, setKw] = useState('')
  const [pending, start] = useTransition()
  const add = () => {
    const q = kw.trim()
    if (!q) return
    start(async () => {
      const r = await addKeyword({ product, site, query: q })
      if (!r.ok) { flash(r.detail === 'duplicate' ? t('duplicate') : r.detail === 'limit' ? t('limit') : te(r.code)); return }
      setKw('')
      flash(connected ? t('tracked') : t('trackedNotConnected'))
      router.refresh()
    })
  }
  return (
    <form className="flex gap-[6px]" onSubmit={(e) => { e.preventDefault(); add() }}>
      <input value={kw} onChange={(e) => setKw(e.target.value)} placeholder={t('placeholder')} aria-label={t('placeholder')} maxLength={200}
        className="h-8 w-[170px] rounded-9 border border-line bg-canvas px-[10px] text-12.5" />
      <button type="submit" disabled={pending || !kw.trim()}
        className="h-8 cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-3 text-12 font-bold">{t('track')}</button>
    </form>
  )
}

/** An addition (V-SGR-07): stop tracking the picked keyword */
export function StopTracking({ id, query }: { id: string; query: string }) {
  const t = useTranslations('simpleGrowth.keywords')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  return (
    <button type="button" disabled={pending} onClick={() => start(async () => {
      const r = await removeKeyword({ id })
      if (!r.ok) { flash(te(r.code)); return }
      flash(t('removed'))
      router.push('/growth?tab=seo&sub=keywords')
      router.refresh()
    })} className="self-start cursor-pointer rounded-8 border border-coral bg-transparent px-[9px] py-1 text-11.5 font-semibold text-rust">
      {t('remove', { q: query })}
    </button>
  )
}

/** Track a search Google already shows the site for (0084): it then stays in the list when it has no impressions */
export function TrackThis({ product, site = null, query }: { product: string; site?: string | null; query: string }) {
  const t = useTranslations('simpleGrowth.keywords')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  return (
    <button type="button" disabled={pending} onClick={() => start(async () => {
      const r = await addKeyword({ product, site, query })
      if (!r.ok) { flash(r.detail === 'duplicate' ? t('duplicate') : r.detail === 'limit' ? t('limit') : te(r.code)); return }
      flash(t('trackedThis', { q: query }))
      router.refresh()
    })} className="self-start cursor-pointer rounded-8 border border-ink bg-transparent px-[9px] py-1 text-11.5 font-semibold text-ink">
      {t('trackThis', { q: query })}
    </button>
  )
}
