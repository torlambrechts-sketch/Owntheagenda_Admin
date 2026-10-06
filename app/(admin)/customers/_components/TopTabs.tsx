import Link from 'next/link'
import { getTranslations } from 'next-intl/server'

export type TabKey = 'orgs' | 'users' | 'billing' | 'access' | 'privacy'
const TABS: TabKey[] = ['orgs', 'users', 'billing', 'access', 'privacy']

/** The screen's pill tabs. Design buttons that navigate become links with the same classes (V-01). */
export async function TopTabs({ current, counts }: { current: TabKey; counts: { orgs: number; access: number | null; privacy: number | null } }) {
  const t = await getTranslations('customers.tabs')
  const count: Record<TabKey, number | null> = { orgs: counts.orgs, users: null, billing: null, access: counts.access, privacy: counts.privacy }
  return (
    <nav className="flex flex-wrap items-center gap-[6px]" aria-label={t('label')}>
      {TABS.map((k) => {
        const on = k === current
        return (
          <Link
            key={k}
            href={(k === 'orgs' ? '/customers' : `/customers?tab=${k}`) as never}
            aria-current={on ? 'page' : undefined}
            className={`flex cursor-pointer items-center gap-[7px] rounded-999 border px-[15px] py-2 text-12.5 hover:no-underline ${
              on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'
            }`}
          >
            {t(k)}
            {count[k] ? <span className="text-11 opacity-75">{count[k]}</span> : null}
          </Link>
        )
      })}
    </nav>
  )
}
