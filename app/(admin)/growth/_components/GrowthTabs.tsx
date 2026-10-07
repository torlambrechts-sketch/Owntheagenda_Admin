import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { GROWTH_RANGES, growthHref, type GrowthRange, type GrowthTab } from '@/lib/data/simple-growth-shared'

/**
 * The pill row and the range control (SimpleGrowth.dc.html, tabs and ranges). The design's buttons become links, so a tab
 * and a range have an address (control substitution, V-SGR-01); the range shows on Analytics and SEO only.
 */
export async function GrowthTabs({ tab, range, tabs, showRange }: { tab: GrowthTab; range: GrowthRange; tabs: readonly GrowthTab[]; showRange: boolean }) {
  const t = await getTranslations('simpleGrowth')
  return (
    <div className="flex flex-wrap items-center gap-2">
      <nav className="flex flex-wrap gap-[6px]" aria-label={t('tabs.label')}>
        {tabs.map((k) => {
          const on = k === tab
          return (
            <Link
              key={k}
              href={growthHref(k, range) as Route}
              aria-current={on ? 'page' : undefined}
              className={`flex-none cursor-pointer whitespace-nowrap rounded-999 border px-4 py-2 text-13 hover:no-underline ${on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'}`}
            >
              {t(`tabs.${k}`)}
            </Link>
          )
        })}
      </nav>
      <span className="flex-1" />
      {showRange ? (
        <div className="flex rounded-11 bg-tile p-[3px]" role="group" aria-label={t('range.label')}>
          {GROWTH_RANGES.map((r) => {
            const on = r === range
            return (
              <Link
                key={r}
                href={growthHref(tab, r) as Route}
                aria-current={on ? 'true' : undefined}
                className={`cursor-pointer rounded-8 px-3 py-[6px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
              >
                {t(`range.${r}`)}
              </Link>
            )
          })}
        </div>
      ) : null}
    </div>
  )
}
