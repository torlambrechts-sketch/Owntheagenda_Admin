import { getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Seo } from '@/lib/data/simple-growth-shared'
import { signed, deltaTone } from '../../analytics/_components/kit'
import { Tile, pctDelta } from './kit'
import { Keywords } from './Keywords'

/**
 * Growth › SEO (SimpleGrowth.dc.html, v.seo) on seo_get. Search Console is not connected and no sign-in for it exists, so
 * the KPIs give way to the «Connect Search Console» empty state and every position is «—»; keywords can be tracked all
 * the same. «Indexed pages», «Site health» and «Content ideas» have no source and are left out (V-SGR-06).
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

  return (
    <div className="flex flex-col gap-[14px]">
      {d.connected && s ? (
        <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
          <Tile label={t('kpi.clicks')} value={s.clicks === null ? '—' : formatNumber(s.clicks, nf)} delta={pctDelta(s.clicks, s.clicks_prev, nf)} />
          <Tile label={t('kpi.impressions')} value={s.impressions === null ? '—' : formatNumber(s.impressions, nf)} delta={pctDelta(s.impressions, s.impressions_prev, nf)} />
          <Tile label={t('kpi.position')} value={pos(s.position)} delta={posDelta} />
        </div>
      ) : (
        <div className="flex flex-wrap items-center gap-3 rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-[18px]">
          <div className="min-w-[240px] flex-1">
            <b className="text-15">{t('connect.title')}</b>
            <div className="mt-1 text-12.5 text-muted">{d.site ? t('connect.body', { site: d.site.hostname }) : t('connect.noSite', { app })}</div>
          </div>
          <button type="button" disabled aria-describedby="sc-reason" className="h-9 cursor-not-allowed whitespace-nowrap rounded-10 border border-ink bg-primary px-4 text-12.5 font-bold opacity-50">
            {t('connect.button')}
          </button>
          <div id="sc-reason" className="w-full text-11.5 text-muted">{t('connect.reason')}</div>
        </div>
      )}
      <Keywords rows={d.keywords} connected={d.connected} hasSite={!!d.site} app={app} product={product} nf={nf} canAdd={canAdd} editOthers={editOthers} />
    </div>
  )
}
