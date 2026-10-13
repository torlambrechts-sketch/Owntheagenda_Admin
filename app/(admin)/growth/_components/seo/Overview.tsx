import { getLocale, getTranslations } from 'next-intl/server'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { relChange } from '@/lib/growth/calc'
import { visibility, type Coverage, type SeoOpp, type SeoOverview } from '@/lib/growth/seo'
import { Delta, Tile, card, cardTable, head } from '../v2kit'
import { PlanButton } from './controls'
import { oppTexts } from './text'

/** The index coverage bar's colours (ov.index[].c), and the design's palette for the states it does not draw */
export const COVERAGE_COLOR: Record<Coverage, string> = {
  indexed: '#5C9A55', crawled_not_indexed: '#E0A21F', duplicate: '#EC9B77', noindex: '#C4BCA8', not_found: '#D4633A',
  discovered_not_indexed: '#F0B9A0', redirect: '#9DB8B3', blocked: '#8F74B3', error: '#A33A16', unknown: '#6E8FB8', other: '#D9CFB8',
}

/**
 * SEO › SEO overview (SeoSuite.dc.html, v.overview) on seo_overview and seo_opportunities (0074): five KPIs, the top five
 * actions, index coverage from URL Inspection and the facts behind the figures. «Traffic value» is left out: it needs
 * cost-per-click data Sentral does not have (V-GR2-24).
 */
export async function SeoOverviewView({ d, opps, priced, nf, product, site = null, app, canAdd }: {
  d: SeoOverview; opps: SeoOpp[]; priced: boolean; nf: NumberFormat; product: string; site?: string | null; app: string; canAdd: boolean
}) {
  const t = await getTranslations('simpleGrowth.seoSuite')
  const locale = await getLocale()
  const dash = '—'
  const kws = d.keywords ?? []
  const vis = visibility(kws.map((k) => ({ impressions: k.impressions, position: k.position })))
  const visPrev = visibility(kws.map((k) => ({ impressions: k.impressions_prev, position: k.position_prev })))
  const visDelta = vis !== null && visPrev !== null ? Math.round((vis - visPrev) * 10) / 10 : null
  const ix = d.index
  const excluded = ix ? ix.pages - ix.indexed : 0
  const date = (iso: string) => new Intl.DateTimeFormat(locale === 'no' ? 'nb-NO' : locale, { day: 'numeric', month: 'short', timeZone: 'Europe/Oslo' }).format(new Date(iso))
  const pts = (v: number) => `${v >= 0 ? '+' : '−'}${formatNumber(Math.abs(v), nf, Number.isInteger(v) ? 0 : 1)}`

  const tiles = [
    { label: t('overview.kpi.clicks'), value: d.clicks?.now != null ? formatNumber(d.clicks.now, nf) : dash,
      delta: <Delta change={relChange(d.clicks?.now, d.clicks?.prev)} nf={nf} />, note: t('overview.kpi.clicksNote') },
    { label: t('overview.kpi.signups'), value: d.signups.now !== null ? formatNumber(d.signups.now, nf) : dash,
      delta: <Delta change={relChange(d.signups.now, d.signups.prev)} nf={nf} />, note: t('overview.kpi.signupsNote') },
    { label: t('overview.kpi.mrr'), value: d.mrr_won ? money(d.mrr_won.now, nf) : dash,
      delta: d.mrr_won ? <Delta change={relChange(d.mrr_won.now, d.mrr_won.prev)} nf={nf} /> : null,
      note: d.mrr_won ? t('overview.kpi.mrrNote') : t('overview.kpi.mrrNone') },
    { label: t('overview.kpi.visibility'), value: vis !== null ? percent(vis, nf) : dash,
      delta: visDelta !== null ? <span className={`whitespace-nowrap text-12 font-bold ${visDelta >= 0 ? 'text-link' : 'text-danger'}`}>{pts(visDelta)}</span> : null,
      note: t('overview.kpi.visibilityNote') },
    { label: t('overview.kpi.indexed'), value: ix && ix.pages ? `${formatNumber(ix.indexed, nf)} / ${formatNumber(ix.pages, nf)}` : dash,
      delta: ix && ix.dropped ? <span className="whitespace-nowrap text-12 font-bold text-danger">{pts(-ix.dropped)}</span> : null,
      note: ix && ix.pages ? t('overview.kpi.indexedNote', { n: formatNumber(excluded, nf) }) : t('overview.kpi.indexedNone') },
  ]

  const top = opps.slice(0, 5)
  const texts = await oppTexts(top, nf)

  // the facts behind the figures, each one true of this site now
  const hidden = d.clicks?.now && d.clicks.named !== null ? Math.max(0, 1 - d.clicks.named / d.clicks.now) : null
  const facts = [
    d.connected ? (hidden !== null ? t('overview.facts.hidden', { share: percent(hidden * 100, nf) }) : t('overview.facts.hiddenPlain')) : t('notConnected'),
    d.tracked_since ? t('overview.facts.tracker', { date: date(d.tracked_since) }) : t('overview.facts.noTracker'),
    d.attributed ? t('overview.facts.revenue') : t('overview.facts.noRevenue', { app }),
    ix && ix.pages && ix.last_at ? t('overview.facts.index', { n: ix.pages, date: date(ix.last_at) }) : t('overview.facts.noIndex'),
  ]

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        {tiles.map((k) => <Tile key={k.label} label={k.label} value={k.value} delta={k.delta} note={k.note} size={23} />)}
      </div>
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
        <section className={cardTable}>
          <div className={head}>
            <b className="text-15">{t('overview.actions')}</b>
            <span className="text-12 text-muted">{priced ? t('overview.actionsNote') : t('overview.actionsNoteClicks')}</span>
          </div>
          {!d.connected ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('notConnected')}</p> : null}
          {d.connected && !top.length ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('overview.actionsEmpty')}</p> : null}
          {top.map((o, i) => (
            <div key={`${o.kind}:${o.query}`} className="flex items-center gap-3 border-b border-line px-[18px] py-[11px]">
              <span className="min-w-[76px] flex-none whitespace-nowrap font-serif text-16 font-semibold text-link">{texts[i]!.worth}</span>
              <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
                <b className="text-13 leading-[1.3] [overflow-wrap:anywhere]">{texts[i]!.line}</b>
                <span className="text-11.5 text-muted">{t('overview.actionSub', { type: texts[i]!.type, effort: texts[i]!.effort })}</span>
              </span>
              <PlanButton product={product} site={site} query={o.query} kind={o.kind} path={o.path} planned={o.planned} label={t('doIt')} disabled={!canAdd} />
            </div>
          ))}
        </section>
        <div className="flex flex-col gap-3">
          <section className={`${card} flex flex-col gap-2 px-[18px] py-4`}>
            <b className="text-15">{t('overview.index')}</b>
            {ix && ix.pages ? (
              <>
                <div className="flex h-4 overflow-hidden rounded-6">
                  {ix.buckets.map((b) => (
                    <span key={b.coverage} title={t(`overview.coverage.${b.coverage}`)} style={{ width: `${(b.count / ix.pages) * 100}%`, background: COVERAGE_COLOR[b.coverage] }} />
                  ))}
                </div>
                {ix.buckets.map((b) => (
                  <div key={b.coverage} className="flex justify-between text-12.5">
                    <span className="flex items-center gap-[7px]">
                      <span className="h-[10px] w-[10px] rounded-3" style={{ background: COVERAGE_COLOR[b.coverage] }} />
                      {t(`overview.coverage.${b.coverage}`)}
                    </span>
                    <b>{formatNumber(b.count, nf)}</b>
                  </div>
                ))}
              </>
            ) : <span className="text-12.5 text-muted">{t('overview.indexEmpty')}</span>}
          </section>
          <section className="flex flex-col gap-[6px] rounded-20 border border-dashed border-line-strong bg-canvas px-4 py-[14px]">
            <b className="text-13">{t('overview.confidence')}</b>
            {facts.map((f) => <span key={f} className="text-12 leading-[1.45] text-ink-2">· {f}</span>)}
          </section>
        </div>
      </div>
    </div>
  )
}
