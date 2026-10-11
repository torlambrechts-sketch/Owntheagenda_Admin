'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Seo } from '@/lib/data/simple-growth-shared'
import { addKeyword, removeKeyword } from '../actions'
import { colHead, emptyRow, mono, rowLine } from './kit'

const COLS = '[grid-template-columns:minmax(0,1.5fr)_80px_70px_70px_minmax(0,1.2fr)_26px]'

/**
 * «Tracked keywords» (SimpleGrowth.dc.html): add with Track, remove with × (an addition: seo_keyword_remove, V-SGR-07).
 * Search Console has no search volume, so the column shows impressions (V-SGR-08). «Ranking page» is the page Google showed
 * most for the query (0072), «Not ranking yet» once connected without impressions, otherwise «—».
 */
export function Keywords({ rows, connected, hasSite, app, product, nf, canAdd, editOthers }: {
  rows: Seo['keywords']; connected: boolean; hasSite: boolean; app: string; product: string; nf: NumberFormat; canAdd: boolean; editOthers: boolean
}) {
  const t = useTranslations('simpleGrowth.seo.keywords')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [kw, setKw] = useState('')
  const [pending, start] = useTransition()

  const add = () => {
    const q = kw.trim()
    if (!q) return
    start(async () => {
      const r = await addKeyword({ product, query: q })
      if (!r.ok) { flash(r.detail === 'duplicate' ? t('duplicate') : r.detail === 'limit' ? t('limit') : te(r.code)); return }
      setKw('')
      flash(connected ? t('tracked') : t('trackedNotConnected'))
      router.refresh()
    })
  }
  const remove = (id: string) => start(async () => {
    const r = await removeKeyword({ id })
    if (!r.ok) { flash(te(r.code)); return }
    flash(t('removed'))
    router.refresh()
  })
  const posTone = (p: number | null) => (p === null ? 'text-faint' : p <= 3 ? 'text-link' : p <= 10 ? 'text-warn-ink' : 'text-danger')

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-3">
        <b className="text-15">{t('title')}</b>
        {hasSite && canAdd ? (
          <form className="flex gap-[6px]" onSubmit={(e) => { e.preventDefault(); add() }}>
            <input
              value={kw}
              onChange={(e) => setKw(e.target.value)}
              placeholder={t('placeholder')}
              aria-label={t('placeholder')}
              maxLength={200}
              className="h-8 w-[220px] rounded-9 border border-line bg-canvas px-[10px] text-12.5"
            />
            <button type="submit" disabled={pending || !kw.trim()} className="h-8 flex-none cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-3 text-12 font-bold">
              {t('track')}
            </button>
          </form>
        ) : null}
      </div>
      <div className="overflow-x-auto">
        <div className="min-w-[520px]">
          <div className={`grid gap-[10px] ${rowLine} ${colHead} ${COLS}`}>
            <span>{t('cols.keyword')}</span><span>{t('cols.impressions')}</span><span>{t('cols.position')}</span><span>{t('cols.change')}</span><span>{t('cols.page')}</span><span />
          </div>
          {rows.map((k) => {
            const ch = k.position !== null && k.position_prev !== null ? Math.round((k.position_prev - k.position) * 10) / 10 : null
            const ranking = k.page ?? (connected && !k.impressions ? t('notRanking') : '—')
            const mayRemove = canAdd && (k.mine || editOthers)
            return (
              <div key={k.id} className={`grid items-center gap-[10px] ${rowLine} text-13 tabular-nums ${COLS}`}>
                <b className="[overflow-wrap:anywhere]">{k.query}</b>
                <span>{k.impressions === null ? '—' : formatNumber(k.impressions, nf)}</span>
                <b className={posTone(k.position)}>{k.position === null ? '—' : formatNumber(k.position, nf, 1)}</b>
                <span className={`font-bold ${ch === null || ch === 0 ? 'text-faint' : ch > 0 ? 'text-link' : 'text-danger'}`}>
                  {ch === null || ch === 0 ? '—' : `${ch > 0 ? '▲' : '▼'} ${formatNumber(Math.abs(ch), nf, 1)}`}
                </span>
                <span className={`overflow-hidden text-ellipsis whitespace-nowrap ${mono} text-11.5 text-muted`}>{ranking}</span>
                {mayRemove ? (
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => remove(k.id)}
                    aria-label={t('remove', { q: k.query })}
                    title={t('remove', { q: k.query })}
                    className="h-[18px] w-[26px] cursor-pointer rounded-6 border border-coral bg-transparent text-11 leading-none text-rust"
                  >
                    ×
                  </button>
                ) : <span />}
              </div>
            )
          })}
          {rows.length === 0 ? <div className={emptyRow}>{hasSite ? t('empty') : t('noSite', { app })}</div> : null}
        </div>
      </div>
    </div>
  )
}
