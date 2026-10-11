import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { clusterVisibility, type SeoClusters, type Stage } from '@/lib/growth/seo'
import { growthHref, type Scope } from '@/lib/growth/scope'
import { Bar, label11, mono } from '../v2kit'
import { PlanButton } from './controls'
import { pos } from './text'

/**
 * SEO › Topic clusters (SeoSuite.dc.html, v.clusters) on seo_clusters (0074). A topic is the page Google shows most for a
 * set of tracked searches over 90 days; its visibility is the click share those searches' positions earn, week by week.
 * The design's MRR per topic and competitors' share of clicks have no source: the card shows the topic's clicks, and the
 * share block splits the topic's clicks between the site's own pages (V-GR2-26).
 */
export async function SeoClustersView({ d, sel, scope, nf, product, canAdd }: {
  d: SeoClusters; sel: string | null; scope: Scope; nf: NumberFormat; product: string; canAdd: boolean
}) {
  const t = await getTranslations('simpleGrowth.seoSuite')
  if (!d.connected) return <p className="m-0 rounded-20 border border-line bg-surface px-5 py-4 text-13 text-muted">{t('notConnected')}</p>
  if (!d.clusters.length) {
    return <p className="m-0 rounded-20 border border-line bg-surface px-5 py-4 text-13 text-muted">{t('clusters.empty')}</p>
  }
  const list = d.clusters.map((c) => ({ c, v: clusterVisibility(c.keywords) }))
  const cur = list.find((x) => x.c.main === sel) ?? list[0]!
  const C = cur.c
  const name = (c: (typeof d.clusters)[number]) => c.title ?? c.main
  const pts = (v: number) => `${v >= 0 ? '+' : '−'}${formatNumber(Math.abs(v), nf, Number.isInteger(v) ? 0 : 1)}`

  // the supporting pages: the topic's other pages, what the plan holds for it, and its searches no page reaches
  const planned = new Map(C.plan.map((p) => [p.query, p]))
  const stageName = (s: Stage) => t(`plan.stages.${s}`)
  const spokes = [
    ...C.pages.filter((p) => p.path !== C.main).map((p) => ({ key: `p:${p.path}`, title: p.title ?? p.path, url: p.path, state: t('clusters.published'), color: 'text-link', missing: null as null | { query: string } })),
    ...C.plan.filter((p) => p.stage === 'idea' || p.stage === 'writing').map((p) => ({ key: `i:${p.id}`, title: `«${p.query}»`, url: p.path ?? '—', state: `${t('clusters.inPlan')} · ${stageName(p.stage)}`, color: 'text-warn-ink', missing: null })),
    ...C.keywords.filter((k) => (k.position === null || k.position > 20) && !planned.has(k.query)).map((k) => ({
      key: `k:${k.query}`, title: `«${k.query}»`, url: t('clusters.missingSub', { pos: pos(k.position, nf) }), state: t('clusters.missing'), color: 'text-danger', missing: { query: k.query } })),
  ]
  const mainPage = C.pages.find((p) => p.path === C.main)
  const total = C.pages.reduce((a, p) => a + p.clicks, 0)

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
      <div className="flex flex-col gap-[10px]">
        {d.unclustered ? <p className="m-0 text-12 text-muted">{t('clusters.unclustered', { n: d.unclustered })}</p> : null}
        {list.map(({ c, v }) => {
          const on = c === C
          const vals = v.weeks.map((w, i) => ({ w, i })).filter((x): x is { w: number; i: number } => x.w !== null)
          const mx = Math.max(...vals.map((x) => x.w)) + 1
          const mn = Math.min(...vals.map((x) => x.w)) - 1
          const spark = vals.map((x) => `${((x.i * 160) / 11).toFixed(1)},${(34 - ((x.w - mn) / (mx - mn)) * 32).toFixed(1)}`).join(' ')
          const up = (v.trend ?? 0) >= 0
          const pages = new Set(c.pages.map((p) => p.path)).size
          return (
            <Link key={c.main} href={growthHref('seo', scope, { sub: 'clusters', cl: c.main }) as Route} aria-current={on ? 'true' : undefined}
              className={`flex cursor-pointer flex-col gap-2 rounded-18 border px-4 py-[14px] text-left text-ink hover:text-ink hover:no-underline ${on ? 'border-ink bg-highlight' : 'border-line bg-surface'}`}>
              <div className="flex items-baseline justify-between gap-[10px]">
                <b className="min-w-0 text-14">{name(c)}</b>
                <span className="whitespace-nowrap text-12 text-muted">{t('clusters.meta', { kws: c.keywords.length, pages })}</span>
              </div>
              <div className="flex items-center gap-[14px]">
                <span className="flex flex-col">
                  <span className="font-serif text-24 font-semibold">{v.now === null ? '—' : percent(v.now, nf)}</span>
                  <span className="text-11 text-muted">{t('clusters.visibility')}</span>
                </span>
                <svg viewBox="0 0 160 36" preserveAspectRatio="none" className="h-9 flex-1" aria-hidden>
                  {vals.length > 1 ? <polyline points={spark} fill="none" stroke={up ? '#5C9A55' : '#D4633A'} strokeWidth={2} vectorEffect="non-scaling-stroke" /> : null}
                </svg>
                <span className="flex flex-col items-end">
                  <b className={`text-14 ${up ? 'text-link' : 'text-danger'}`}>{v.trend === null ? '—' : t('clusters.pts', { v: pts(v.trend) })}</b>
                  <span className="whitespace-nowrap text-11 text-muted">{t('clusters.clicks', { n: formatNumber(c.clicks, nf) })}</span>
                </span>
              </div>
            </Link>
          )
        })}
      </div>
      <section className="flex flex-col gap-[11px] rounded-20 border border-ink bg-surface px-5 py-4">
        <b className="font-serif text-20">{name(C)}</b>
        <div className={label11}>{t('clusters.main')}</div>
        <div className="flex justify-between gap-[10px] rounded-12 border border-ink bg-highlight px-3 py-[10px] text-12.5">
          <span className={`${mono} min-w-0 [overflow-wrap:anywhere]`}>{C.main}</span>
          <b className="whitespace-nowrap">#{pos(mainPage?.position ?? null, nf)}</b>
        </div>
        {spokes.length ? <div className={label11}>{t('clusters.spokes')}</div> : null}
        {spokes.map((s) => (
          <div key={s.key} className="flex items-center justify-between gap-[10px] border-b border-tile py-[7px] text-12.5">
            <span className="flex min-w-0 flex-col">
              <b>{s.title}</b>
              <span className={`${mono} text-11 text-muted [overflow-wrap:anywhere]`}>{s.url}</span>
            </span>
            <span className="flex flex-none items-center gap-[6px]">
              <span className={`whitespace-nowrap text-11.5 font-bold ${s.color}`}>{s.state}</span>
              {s.missing ? <PlanButton product={product} query={s.missing.query} kind="gap" path={null} planned={false} label={t('clusters.plan')} small disabled={!canAdd} /> : null}
            </span>
          </div>
        ))}
        <div className={label11}>{t('clusters.share')}</div>
        {C.pages.map((p) => {
          const share = total ? (p.clicks / total) * 100 : 0
          return (
            <div key={p.path} className="grid items-center gap-2 text-12 [grid-template-columns:130px_minmax(0,1fr)_40px]">
              <span className={`truncate ${p.path === C.main ? 'font-bold' : 'font-medium'}`} title={p.path}>{p.path}</span>
              <Bar w={share} color={p.path === C.main ? '#F5C64A' : '#9DB8B3'} h={9} />
              <b className="whitespace-nowrap text-right">{percent(share, nf)}</b>
            </div>
          )
        })}
      </section>
    </div>
  )
}
