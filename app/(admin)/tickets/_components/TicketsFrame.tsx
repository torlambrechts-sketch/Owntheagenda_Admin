'use client'

import { createContext, useCallback, useContext, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useGo } from './lib'
import { NewTicketModal, type NewTicketSeed } from './NewTicketModal'
import type { TicketConfig } from '@/lib/data/tickets'
import type { Tab } from '@/lib/data/tickets-shared'


const NewCtx = createContext<(seed?: NewTicketSeed) => void>(() => {})
/** Opens the new-ticket dialog from anywhere on the screen (the help widget's «Send to support»). */
export const useNewTicket = () => useContext(NewCtx)

/** The tab pills, «＋ New ticket» and the dialog (Tickets.dc.html, the top row and newOpen). */
export function TicketsFrame({ tab, tabs, config, product, canAdd, seed, children }: {
  tab: Tab
  tabs: Tab[]
  config: TicketConfig
  product: string
  canAdd: boolean
  seed: NewTicketSeed | null
  children: React.ReactNode
}) {
  const t = useTranslations('tickets')
  const { go } = useGo()
  const [open, setOpen] = useState<NewTicketSeed | null>(seed)
  const openNew = useCallback((s?: NewTicketSeed) => { if (canAdd) setOpen(s ?? {}) }, [canAdd])
  const close = () => {
    setOpen(null)
    // the address that opened it (?new=<organization>) is spent
    if (seed) go({ new: null })
  }

  return (
    <NewCtx.Provider value={openNew}>
      <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
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
                  onClick={() => go({ tab: k === 'inbox' ? null : k }, { reset: true, push: true })}
                  className={`cursor-pointer rounded-999 border px-[15px] py-2 text-12.5 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
                >
                  {t(`tabs.${k}`)}
                </button>
              )
            })}
          </div>
          {canAdd ? (
            <button type="button" onClick={() => openNew()} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-4 text-12.5 font-bold">
              {t('newTicket')}
            </button>
          ) : null}
        </div>
        {children}
      </div>
      {open ? <NewTicketModal seed={open} config={config} product={product} onClose={close} /> : null}
    </NewCtx.Provider>
  )
}
