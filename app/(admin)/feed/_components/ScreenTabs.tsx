'use client'

import { useTranslations } from 'next-intl'
import { SCREEN_TABS, type ScreenTab } from '@/lib/data/feed-shared'
import { useGo } from './go'

/** The three tab pills (Feed.dc.html, tabs): Feed, Scoring models, Enrichment. */
export function ScreenTabs({ tab }: { tab: ScreenTab }) {
  const t = useTranslations('feed.tabs')
  const { go } = useGo()
  return (
    <div className="flex flex-wrap gap-[6px]" role="tablist">
      {SCREEN_TABS.map((k) => {
        const on = k === tab
        return (
          <button
            key={k}
            type="button"
            role="tab"
            aria-selected={on}
            onClick={() => go({ tab: k === 'feed' ? null : k }, { reset: true })}
            className={`cursor-pointer rounded-999 border px-[14px] py-2 text-12.5 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
          >
            {t(k)}
          </button>
        )
      })}
    </div>
  )
}
