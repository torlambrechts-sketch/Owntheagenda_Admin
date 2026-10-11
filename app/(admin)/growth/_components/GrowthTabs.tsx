import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { growthHref, type Scope, type Tab } from '@/lib/growth/scope'

/**
 * The pill row (SimpleGrowth.dc.html, tabs: padding 8×15, radius 999, 13 px). The design's buttons become links so a tab
 * has an address (V-SGR-01); the scope travels with the scoped tabs.
 */
export async function GrowthTabs({ tab, tabs, scope }: { tab: Tab; tabs: readonly Tab[]; scope: Scope }) {
  const t = await getTranslations('simpleGrowth')
  return (
    <nav className="flex flex-wrap gap-[6px]" aria-label={t('tabs.label')}>
      {tabs.map((k) => {
        const on = k === tab
        return (
          <Link
            key={k}
            href={growthHref(k, scope) as Route}
            aria-current={on ? 'page' : undefined}
            className={`cursor-pointer whitespace-nowrap rounded-999 border px-[15px] py-2 text-13 hover:no-underline ${on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'}`}
          >
            {t(`tabs.${k}`)}
          </Link>
        )
      })}
    </nav>
  )
}

/** A view's sub-tabs (seoSubs, campSubs, emailSubs: a tile bar, padding 4, radius 13; pills 7×12, radius 9) */
export async function SubTabs({ items, current, label }: { items: { key: string; label: string; href: string }[]; current: string; label: string }) {
  return (
    <nav className="flex flex-wrap gap-1 self-start rounded-13 bg-tile p-1" aria-label={label}>
      {items.map((s) => {
        const on = s.key === current
        return (
          <Link key={s.key} href={s.href as Route} aria-current={on ? 'page' : undefined}
            className={`cursor-pointer whitespace-nowrap rounded-9 px-3 py-[7px] text-12.5 text-ink hover:text-ink hover:no-underline ${on ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
            {s.label}
          </Link>
        )
      })}
    </nav>
  )
}
