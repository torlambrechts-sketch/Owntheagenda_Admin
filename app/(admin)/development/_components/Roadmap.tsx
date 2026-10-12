import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { getShell } from '@/lib/shell'
import { loadRoadmap } from '@/lib/data/dev-core'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { SENTRAL_COLOR } from './core/logic'
import { c, type ProductInfo } from './core/styles'
import { RoadmapBoard } from './core/RoadmapBoard'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Development › Roadmap (DevHub.dc.html, v.roadmap): outcomes in Now / Next / Later with their goal and the evidence
 * behind them, counted when read under the reader's own rights; ← and → move an item; «Promote from» makes a Later item
 * from a feature request, a winning experiment or an SEO plan item. The product filter starts at All (the design) and is
 * an address (?prod=), so the chips are links.
 */
export async function RoadmapView({ nf, searchParams }: DevTabProps) {
  const t = await getTranslations('devCore')
  const shell = await getShell()
  const products: ProductInfo[] = [...shell.products.map((p) => ({ key: p.key, name: p.name, color: p.color })), { key: 'sentral', name: t('sentral'), color: SENTRAL_COLOR }]
  const asked = one(searchParams.prod)
  const filter = asked && products.some((p) => p.key === asked) ? asked : null
  const data = await loadRoadmap(filter)
  const chips: { key: string | null; name: string }[] = [{ key: null, name: t('roadmap.all') }, ...products.map((p) => ({ key: p.key, name: p.name }))]
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-[6px]">
        <nav aria-label={t('roadmap.filter')} className="flex flex-wrap gap-[6px]">
          {chips.map((p) => (
            <Link key={p.key ?? 'all'} href={(p.key ? `/development?prod=${p.key}` : '/development') as Route} aria-current={filter === p.key ? 'true' : undefined}
              className={c.chip(filter === p.key)}>
              {p.name}
            </Link>
          ))}
        </nav>
        <span className="flex-1" />
        <span className="text-12 text-muted">{t('roadmap.note')}</span>
      </div>
      <RoadmapBoard data={data} products={products} filter={filter} nf={nf} />
    </div>
  )
}
