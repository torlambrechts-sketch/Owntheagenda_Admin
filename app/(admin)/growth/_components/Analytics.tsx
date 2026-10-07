import { getFormatter, getTranslations } from 'next-intl/server'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { share } from '@/lib/data/analytics-calc'
import { CHANNEL_COLOR, FUNNEL_COLOR, type Overview } from '@/lib/data/simple-growth-shared'
import { Tile, card, cardHead, cardTable, colHead, emptyRow, mono, pctDelta, rowLine } from './kit'

const SRC_COLS = '[grid-template-columns:minmax(0,1.3fr)_70px_60px_60px]'
const PAGE_COLS = '[grid-template-columns:minmax(0,1.8fr)_80px_70px_70px]'

/**
 * Growth › Analytics (SimpleGrowth.dc.html, v.analytics) on growth_overview. Signups, trial → paid, signups by source and
 * the funnel's bottom come from the products' events. Visitors, the funnel's top and landing pages wait for the website
 * tracker (D-37): «—» and the empty treatment, never a number. Cost per customer is spend typed in ÷ new paying customers
 * of the same months, «—» without spend.
 */
export async function Analytics({ d, nf, app }: { d: Overview; nf: NumberFormat; app: string }) {
  const t = await getTranslations('simpleGrowth.analytics')
  const format = await getFormatter()
  const k = d.kpis
  const dash = '—'
  const num = (v: number | null) => (v === null ? dash : formatNumber(v, nf))
  const pct = (v: number | null) => (v === null ? dash : percent(v, nf))
  const conv = share(k.trial_conversion?.converted, k.trial_conversion?.trials)
  const cac = k.spend !== null && k.paying_new > 0 ? k.spend / k.paying_new : null
  const channel = (c: string) => (t.has(`channels.${c}`) ? t(`channels.${c}`) : c)
  const noTracker = d.site ? t('tracker.waiting', { site: d.site.hostname }) : t('tracker.noSite', { app })

  // the chart: visitors as the area, signups dashed — scaled to the visitors when there are any (the design's «scaled»)
  const n = d.daily.length
  const visitors = d.daily.map((x) => x.visitors)
  const hasVisitors = d.tracked && visitors.some((v) => v !== null)
  const vmax = Math.max(1, ...visitors.map((v) => v ?? 0))
  const smax = Math.max(1, ...d.daily.map((x) => x.signups))
  const x = (i: number) => (n > 1 ? (i * 600) / (n - 1) : 300).toFixed(1)
  const y = (v: number, max: number) => (166 - (v / max) * 154).toFixed(1)
  const line = visitors.map((v, i) => `${x(i)},${y(v ?? 0, vmax)}`).join(' ')
  const sign = d.daily.map((p, i) => `${x(i)},${y(p.signups, smax)}`).join(' ')

  // the funnel's bars against its largest known step; a step without a source reads «—» and draws no bar
  const top = Math.max(1, ...d.funnel.map((f) => f.count ?? 0))
  const funnel = d.funnel.map((f, i) => {
    const prev = i > 0 ? d.funnel[i - 1]!.count : null
    const drop = f.count !== null && prev !== null && prev > 0 ? Math.round((1 - f.count / prev) * 100) : null
    return { ...f, w: f.count === null ? 0 : Math.max(2, (f.count / top) * 100), drop }
  })
  const funnelTopMissing = d.funnel.some((f) => f.count === null)

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        <Tile label={t('kpi.visitors')} value={num(k.visitors)} delta={pctDelta(k.visitors, k.visitors_prev, nf)} title={k.visitors === null ? noTracker : undefined} />
        <Tile label={t('kpi.signups')} value={formatNumber(k.signups, nf)} delta={pctDelta(k.signups, k.signups_prev, nf)} />
        <Tile label={t('kpi.visitSignup')} value={pct(k.visitors ? share(k.signups, k.visitors) : null)} title={k.visitors === null ? noTracker : undefined} />
        <Tile label={t('kpi.trialPaid')} value={pct(conv === null ? null : Math.round(conv))} title={t('kpi.trialPaidTip')} />
        <Tile label={t('kpi.cost')} value={cac === null ? dash : money(cac, nf)}
          title={k.spend === null ? t('kpi.costNone') : t('kpi.costTip', { from: format.dateTime(new Date(`${k.spend_from.slice(0, 7)}-15T12:00:00Z`), { month: 'long', year: 'numeric' }), customers: k.paying_new })} />
      </div>

      <div className={`${card} px-[22px] py-[18px]`}>
        <div className="mb-[10px] flex flex-wrap items-baseline justify-between gap-[10px]">
          <b className="text-15">{t('chart.title')}</b>
          <span className="flex gap-[14px] text-11.5 text-muted">
            {hasVisitors ? <span className="flex items-center gap-[6px]"><span className="h-[3px] w-[14px] bg-teal-mid" />{t('chart.visitors')}</span> : null}
            <span className="flex items-center gap-[6px]"><span className="h-[3px] w-[14px] bg-link" />{hasVisitors ? t('chart.signupsScaled') : t('chart.signups')}</span>
          </span>
        </div>
        <svg viewBox="0 0 600 170" preserveAspectRatio="none" className="block h-[170px] w-full" role="img" aria-label={t('chart.title')}>
          {hasVisitors ? (
            <>
              <polygon points={`0,166 ${line} 600,166`} fill="#E4EEEC" />
              <polyline points={line} fill="none" stroke="#9DB8B3" strokeWidth="2" vectorEffect="non-scaling-stroke" />
            </>
          ) : null}
          <polyline points={sign} fill="none" stroke="#2F5D2A" strokeWidth="2" strokeDasharray="5 4" vectorEffect="non-scaling-stroke" />
        </svg>
        {hasVisitors ? null : <div className="mt-2 text-12 text-muted">{noTracker}</div>}
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={`${card} px-[22px] py-[18px]`}>
          <b className="text-15">{t('funnel.title')}</b>
          <div className="mt-3 flex flex-col gap-2">
            {funnel.map((f) => (
              <div key={f.key} className="grid items-center gap-[10px] text-12.5 [grid-template-columns:150px_minmax(0,1fr)_64px_50px]">
                <span className="font-semibold">{t(`funnel.${f.key}`)}</span>
                <span className="h-[22px] overflow-hidden rounded-7 bg-tile">
                  <span className="block h-full" style={{ width: `${f.w}%`, background: FUNNEL_COLOR[f.key] }} />
                </span>
                <b className="text-right">{num(f.count)}</b>
                <span className="text-right text-11.5 font-bold text-danger">{f.drop !== null && f.drop > 0 ? `−${percent(f.drop, nf)}` : ''}</span>
              </div>
            ))}
          </div>
          {funnelTopMissing ? <div className="mt-3 text-12 text-muted">{t('funnel.topMissing')}</div> : null}
        </div>

        <div className={cardTable}>
          <div className="border-b border-line px-[18px] py-[14px] text-15 font-bold">{t('sources.title')}</div>
          <div className={`grid gap-[10px] ${rowLine} ${colHead} ${SRC_COLS}`}>
            <span>{t('sources.source')}</span><span>{t('sources.visits')}</span><span>{t('sources.signups')}</span><span>{t('sources.conv')}</span>
          </div>
          {d.sources.map((s) => (
            <div key={s.channel} className={`grid items-center gap-[10px] ${rowLine} text-13 tabular-nums ${SRC_COLS}`}>
              <span className="flex items-center gap-2"><span className="h-[9px] w-[9px] flex-none rounded-3" style={{ background: CHANNEL_COLOR[s.channel] ?? '#C4BCA8' }} /><b>{channel(s.channel)}</b></span>
              <span>{num(s.visits)}</span>
              <span>{formatNumber(s.signups, nf)}</span>
              <b>{s.visits ? pct(share(s.signups, s.visits)) : dash}</b>
            </div>
          ))}
          {d.sources.length === 0 ? <div className={emptyRow}>{t('sources.empty')}</div> : null}
          {!d.tracked && d.sources.length > 0 ? <div className="px-[18px] py-[10px] text-12 text-muted">{t('sources.visitsMissing')}</div> : null}
        </div>
      </div>

      <div className={cardTable}>
        <div className={cardHead}><b className="text-15">{t('pages.title')}</b><span className="text-12 text-muted">{t('pages.sub')}</span></div>
        {d.pages.map((p) => (
          <div key={p.path} className={`grid gap-[10px] ${rowLine} text-13 tabular-nums ${PAGE_COLS}`}>
            <span className={`overflow-hidden text-ellipsis whitespace-nowrap ${mono} text-12`}>{p.path}</span>
            <span>{formatNumber(p.visits, nf)}</span>
            <span>{dash}</span>
            <b className="text-link">{dash}</b>
          </div>
        ))}
        {d.pages.length === 0 ? <div className={emptyRow}>{d.tracked ? t('pages.none') : noTracker}</div> : null}
        {d.pages.length > 0 ? <div className="px-[18px] py-[10px] text-12 text-muted">{t('pages.signupsMissing')}</div> : null}
      </div>
    </div>
  )
}
