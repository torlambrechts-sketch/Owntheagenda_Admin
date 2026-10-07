import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { TABS, tabHref, type Tab } from '@/lib/data/security-shared'

/** The design's seven pills (Security.dc.html, tabs). Its buttons switch local state; here each tab has an address (V-SECURITY-01). */
export async function SecurityTabs({ current }: { current: Tab }) {
  const t = await getTranslations('security.tabs')
  return (
    <nav className="flex flex-wrap gap-[6px]" aria-label={t('label')}>
      {TABS.map((k) => {
        const on = k === current
        return (
          <Link
            key={k}
            href={tabHref(k) as Route}
            aria-current={on ? 'page' : undefined}
            className={`cursor-pointer rounded-999 border border-solid px-[13px] py-[7px] text-12.5 hover:no-underline ${on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'}`}
          >
            {t(k)}
          </Link>
        )
      })}
    </nav>
  )
}
