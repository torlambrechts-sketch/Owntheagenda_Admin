import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { getShell } from '@/lib/shell'
import { loadBugs } from '@/lib/data/dev-core'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { SENTRAL_COLOR } from './core/logic'
import { c, type ProductInfo } from './core/styles'
import { BugList } from './core/BugList'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Development › Bug triage (DevHub.dc.html, v.bugs): bugs on Sentral's tickets and problems, with severity, the due time
 * from the targets in Settings, the tickets and customers behind each, «Merge duplicate» and «Mark fixed» (which resolves
 * a linked problem through problem_resolve). It opens on the application chosen in the rail, so its KPIs agree with the
 * pill's count; the chips (links) show another one, Sentral's own or all.
 */
export async function BugsView({ product, nf, searchParams }: DevTabProps) {
  const t = await getTranslations('devCore')
  const shell = await getShell()
  const products: ProductInfo[] = [...shell.products.map((p) => ({ key: p.key, name: p.name, color: p.color })), { key: 'sentral', name: t('sentral'), color: SENTRAL_COLOR }]
  const asked = one(searchParams.prod)
  const filter = asked === 'all' ? null : asked && products.some((p) => p.key === asked) ? asked : product
  const data = await loadBugs(filter)
  const chips: { key: string; name: string }[] = [{ key: 'all', name: t('roadmap.all') }, ...products.map((p) => ({ key: p.key, name: p.name }))]
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-[6px]">
        <nav aria-label={t('roadmap.filter')} className="flex flex-wrap gap-[6px]">
          {chips.map((p) => {
            const on = (filter ?? 'all') === p.key
            return (
              <Link key={p.key} href={`/development?tab=bugs&prod=${p.key}` as Route} aria-current={on ? 'true' : undefined} className={c.chip(on)}>{p.name}</Link>
            )
          })}
        </nav>
      </div>
      <BugList data={data} products={products} filter={filter} nf={nf} timeZone={shell.me.time_zone} />
    </div>
  )
}
