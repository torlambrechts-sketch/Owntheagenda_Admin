'use client'

import { useState, useTransition } from 'react'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import type { NumberFormat } from '@/lib/format'
import type { CrmDeal, CrmDeals, CrmLists } from '@/lib/data/simple-crm'
import { CRM_TABS, type CrmRights, type CrmTab } from '@/lib/data/simple-crm-shared'
import { DealsTab } from './DealsTab'
import { ListsTab } from './ListsTab'

type Props = {
  tab: CrmTab
  rights: CrmRights
  nf: NumberFormat
  tz: string
  deals?: CrmDeals | null
  dealsBlocked?: 'moduleOff' | 'failed' | null
  initialDeal?: CrmDeal | null
  lists?: CrmLists | null
  listsBlocked?: 'moduleOff' | 'noRight' | 'failed' | null
}

/**
 * Sentral Simple › CRM (SimpleCRM.dc.html): the tab pills, the section's primary action («＋ New deal» / «＋ New list»)
 * and the tab below. The pills are buttons, as in the design; the tab lives in the address (?tab=lists).
 */
export function CrmScreen({ tab, rights, nf, tz, deals, dealsBlocked, initialDeal, lists, listsBlocked }: Props) {
  const t = useTranslations('simpleCrm')
  const router = useRouter()
  const [pending, start] = useTransition()
  const [shown, setShown] = useState<CrmTab>(tab)
  const [creating, setCreating] = useState(false)
  if (shown !== tab && !pending) setShown(tab)

  const pick = (k: CrmTab) => {
    if (k === tab) return
    setShown(k)
    setCreating(false)
    start(() => router.push((k === 'deals' ? '/crm' : '/crm?tab=lists') as Route, { scroll: false }))
  }
  // the primary action is offered only where it can work: the right, and a pipeline (deals) or the lists themselves
  const primary = tab === 'deals' ? rights.add && !!deals?.pipeline : rights.addList && !!lists

  return (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
      <div className="flex min-h-[38px] flex-wrap items-center gap-2">
        <div role="tablist" aria-label={t('tabs.label')} className="flex flex-wrap gap-[6px]">
          {CRM_TABS.map((k) => {
            const on = shown === k
            return (
              <button
                key={k}
                type="button"
                role="tab"
                aria-selected={on}
                onClick={() => pick(k)}
                className={`flex-none cursor-pointer whitespace-nowrap rounded-999 border px-4 py-2 text-13 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
              >
                {t(`tabs.${k}`)}
              </button>
            )
          })}
        </div>
        <span className="flex-1" />
        {primary && shown === tab ? (
          <button
            type="button"
            onClick={() => setCreating(true)}
            className="h-[38px] flex-none cursor-pointer whitespace-nowrap rounded-10 border border-ink bg-primary px-4 text-13 font-bold"
          >
            {t(tab === 'deals' ? 'newDeal' : 'newList')}
          </button>
        ) : null}
      </div>

      <div className={pending ? 'opacity-60 transition-opacity' : undefined}>
        {tab === 'deals' ? (
          <DealsTab rights={rights} nf={nf} tz={tz} data={deals ?? null} blocked={dealsBlocked ?? null} initialDeal={initialDeal ?? null} creating={creating} setCreating={setCreating} />
        ) : (
          <ListsTab rights={rights} data={lists ?? null} blocked={listsBlocked ?? null} creating={creating} setCreating={setCreating} />
        )}
      </div>
    </div>
  )
}
