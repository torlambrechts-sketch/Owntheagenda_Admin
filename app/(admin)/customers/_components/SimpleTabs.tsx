import Link from 'next/link'

/**
 * The section's two pills (SimpleCustomers.dc.html, tabs): name and count. The design's buttons switch a state; here
 * they are links to `?tab=` so a tab has an address (control substitution, D-06).
 */
export function SimpleTabs({ tabs }: { tabs: { key: string; label: string; count: number | null; href: string; on: boolean }[] }) {
  return (
    <nav className="flex flex-wrap gap-[6px]">
      {tabs.map((t) => (
        <Link
          key={t.key}
          href={t.href as never}
          aria-current={t.on ? 'page' : undefined}
          className={`flex flex-none items-center gap-[7px] whitespace-nowrap rounded-999 border px-4 py-2 text-13 hover:no-underline ${t.on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'}`}
        >
          {t.label}
          {t.count !== null ? <span className="text-11 opacity-75">{t.count}</span> : null}
        </Link>
      ))}
    </nav>
  )
}
