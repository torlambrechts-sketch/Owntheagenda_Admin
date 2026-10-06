'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'

export type TimelineRow = { key: string; when: string; title: string; sub: string; filter: string; dot: string }
const FILTERS = ['all', 'activation', 'billing', 'support', 'logins', 'crm'] as const

/** The company's timeline with the design's kind filter (Customers.dc.html, d.timeline). */
export function TimelineList({ rows }: { rows: TimelineRow[] }) {
  const t = useTranslations('customers.timeline')
  const [f, setF] = useState<(typeof FILTERS)[number]>('all')
  const shown = rows.filter((r) => f === 'all' || r.filter === f)
  return (
    <div className="rounded-20 border border-line bg-surface px-6 py-5">
      <div className="mb-4 flex flex-wrap gap-[6px]">
        {FILTERS.map((k) => (
          <button
            key={k}
            type="button"
            aria-pressed={f === k}
            onClick={() => setF(k)}
            className={`cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${f === k ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
          >
            {t(`filters.${k}`)}
          </button>
        ))}
      </div>
      <div className="flex flex-col">
        {shown.map((e) => (
          <div key={e.key} className="grid items-start gap-3 pb-4 [grid-template-columns:110px_22px_minmax(0,1fr)]">
            <span className="pt-[2px] text-right text-12 text-muted">{e.when}</span>
            <span className="flex flex-col items-center self-stretch">
              <span className="h-3 w-3 rounded-999 border-[1.5px] border-ink" style={{ background: e.dot }} />
              <span className="w-px flex-1 bg-line" />
            </span>
            <span className="flex flex-col gap-[2px]">
              <span className="text-13.5 font-semibold">{e.title}</span>
              <span className="text-12 text-muted">{e.sub}</span>
            </span>
          </div>
        ))}
        {shown.length === 0 ? <div className="py-4 text-center text-13 text-muted">{t('empty')}</div> : null}
      </div>
    </div>
  )
}
