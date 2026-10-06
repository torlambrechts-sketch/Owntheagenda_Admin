'use client'

import { useTranslations } from 'next-intl'
import { TABS, useGo, type Tab } from './shared'

/** The tab pills and the engine line (Automation.dc.html, the top row). */
export function AutomationFrame({ tab, loopOn, children }: { tab: Tab; loopOn: boolean; children: React.ReactNode }) {
  const t = useTranslations('automation')
  const { go } = useGo()
  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-[6px]" role="tablist">
          {TABS.map((k) => {
            const on = k === tab
            return (
              <button
                key={k}
                type="button"
                role="tab"
                aria-selected={on}
                onClick={() => go({ tab: k === 'list' ? null : k }, { reset: true })}
                className={`cursor-pointer rounded-999 border px-[14px] py-2 text-12.5 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
              >
                {t(`tabs.${k}`)}
              </button>
            )
          })}
        </div>
        <span className="flex-1" />
        <span className="text-12 text-muted">{t('engine', { on: loopOn ? 'on' : 'off' })}</span>
      </div>
      {children}
    </div>
  )
}
