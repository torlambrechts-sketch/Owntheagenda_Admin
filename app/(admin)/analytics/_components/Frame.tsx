'use client'

import { useTranslations } from 'next-intl'
import { RANGES, type RangeKey, type Tab } from '@/lib/data/analytics-calc'
import { useGo } from './nav'

/**
 * The top row of Analytics.dc.html: the eight tab pills, the scope label and the range switch. The range
 * is passed to every read that takes a period; on a tab whose reads have their own period (a cohort, the
 * latest scores) the switch is shown disabled and says so.
 */
export function Frame({ tab, tabs, range, scope, ranged, children }: {
  tab: Tab
  tabs: readonly Tab[]
  range: RangeKey
  scope: string
  ranged: boolean
  children: React.ReactNode
}) {
  const t = useTranslations('analytics')
  const { go } = useGo()
  return (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center justify-between gap-[10px]">
        <div className="flex flex-wrap gap-[6px]" role="tablist">
          {tabs.map((k) => {
            const on = k === tab
            return (
              <button
                key={k}
                type="button"
                role="tab"
                aria-selected={on}
                onClick={() => go({ tab: k === 'business' ? null : k }, { keep: ['range'], push: true })}
                className={`cursor-pointer rounded-999 border px-[15px] py-2 text-12.5 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
              >
                {t(`tabs.${k}`)}
              </button>
            )
          })}
        </div>
        <div className="flex items-center gap-[6px]">
          <span className="text-12 text-muted">{scope}</span>
          <div className={`flex rounded-11 bg-tile p-[3px] ${ranged ? '' : 'opacity-50'}`} title={ranged ? undefined : t('rangeOwnPeriod')}>
            {RANGES.map((r) => (
              <button
                key={r}
                type="button"
                aria-pressed={r === range}
                disabled={!ranged}
                onClick={() => go({ range: r === '12m' ? null : r })}
                className={`rounded-8 border-0 px-[11px] py-[6px] text-12 text-ink ${ranged ? 'cursor-pointer' : 'cursor-default'} ${r === range ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
              >
                {t(`ranges.${r}`)}
              </button>
            ))}
          </div>
        </div>
      </div>
      {children}
    </div>
  )
}
