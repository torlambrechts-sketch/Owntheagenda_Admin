import { getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Seo } from '@/lib/data/simple-growth-shared'
import { signed, deltaTone } from '../../analytics/_components/kit'
import { Tile, pctDelta } from './kit'
import { Keywords } from './Keywords'
import { SearchConsoleCard } from './SearchConsole'
import { SiteHealth } from './SiteHealth'
import { ContentIdeas } from './ContentIdeas'

/**
 * Growth › SEO (SimpleGrowth.dc.html, v.seo) on seo_get. Until Search Console is connected (0064: a service account's key,
 * SearchConsoleCard) the KPIs give way to the «Connect Search Console» empty state and every position is «—»; keywords
 * can be tracked all the same. Connected, the KPIs are Search Console's own day totals and the card says the property.
 * 0072 adds the rest of the design: «Pages in Google» for «Indexed pages» (V-SGR-29), «Site health» from seo-crawl and
 * «Content ideas» from Search Console.
 */
export async function SeoTab({ d, nf, product, app, canAdd, editOthers }: {
  d: Seo; nf: NumberFormat; product: string; app: string; canAdd: boolean; editOthers: boolean
}) {
  const t = await getTranslations('simpleGrowth.seo')
  const s = d.totals
  const pos = (v: number | null) => (v === null ? '—' : formatNumber(v, nf, 1))
  // a lower position is better: the change is before − now
  const posDelta = s && s.position !== null && s.position_prev !== null
    ? (() => { const c = Math.round((s.position_prev - s.position) * 10) / 10; return { text: signed(formatNumber(Math.abs(c), nf, 1), c), tone: deltaTone(c) } })()
    : null
  const pagesDelta = s && s.pages != null && s.pages_prev != null && s.pages !== s.pages_prev
    ? (() => { const c = s.pages - s.pages_prev; return { text: signed(formatNumber(Math.abs(c), nf), c), tone: deltaTone(c) } })()
    : null

  return (
    <div className="flex flex-col gap-[14px]">
      {d.connected && s ? (
        <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
          <Tile label={t('kpi.clicks')} value={s.clicks === null ? '—' : formatNumber(s.clicks, nf)} delta={pctDelta(s.clicks, s.clicks_prev, nf)} />
          <Tile label={t('kpi.impressions')} value={s.impressions === null ? '—' : formatNumber(s.impressions, nf)} delta={pctDelta(s.impressions, s.impressions_prev, nf)} />
          <Tile label={t('kpi.position')} value={pos(s.position)} delta={posDelta} />
          <Tile label={t('kpi.pages')} value={s.pages == null ? '—' : formatNumber(s.pages, nf)} delta={pagesDelta} title={t('kpi.pagesHint')} />
        </div>
      ) : null}
      <SearchConsoleCard sc={d.search_console} site={d.site?.hostname ?? null} app={app} connected={d.connected} />
      <Keywords rows={d.keywords} connected={d.connected} hasSite={!!d.site} app={app} product={product} nf={nf} canAdd={canAdd} editOthers={editOthers} />
      {d.site && (d.health || d.ideas) ? (
        <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
          {d.health ? <SiteHealth health={d.health} site={d.site.id} product={product} nf={nf} canEdit={canAdd} /> : null}
          {d.ideas ? <ContentIdeas ideas={d.ideas} product={product} nf={nf} canEdit={canAdd} /> : null}
        </div>
      ) : null}
    </div>
  )
}
