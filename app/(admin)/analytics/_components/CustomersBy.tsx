'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { Empty, Track, softPill } from './kit'

type Row = { n: string; v: number }
const DIMS = ['industry', 'fylke', 'size'] as const

/** «Customers by» with its Industry / Fylke / Size toggle (Analytics.dc.html, dims): the top eight of each. */
export function CustomersBy({ rows }: { rows: Record<(typeof DIMS)[number], Row[]> }) {
  const t = useTranslations('analytics.business.dims')
  const [dim, setDim] = useState<(typeof DIMS)[number]>('industry')
  const list = rows[dim].slice(0, 8)
  const max = Math.max(1, ...list.map((r) => r.v))
  return (
    <div className="rounded-20 border border-line bg-surface px-[22px] py-[18px]">
      <div className="mb-[10px] flex items-baseline justify-between">
        <span className="text-15 font-bold">{t('title')}</span>
        <div className="flex gap-1">
          {DIMS.map((d) => (
            <button key={d} type="button" aria-pressed={d === dim} onClick={() => setDim(d)} className={softPill(d === dim)}>{t(d)}</button>
          ))}
        </div>
      </div>
      {list.length ? list.map((r) => (
        <div key={r.n} className="grid items-center gap-2 py-1 text-12.5 [grid-template-columns:130px_minmax(0,1fr)_30px]">
          <span className="overflow-hidden text-ellipsis whitespace-nowrap">{r.n}</span>
          <Track w={(r.v / max) * 100} fill="#E0A21F" />
          <b className="text-right">{r.v}</b>
        </div>
      )) : <Empty>{t('empty')}</Empty>}
      <div className="mt-2 text-11 text-faint">{dim === 'size' ? t('noteSize') : t('note')}</div>
    </div>
  )
}
