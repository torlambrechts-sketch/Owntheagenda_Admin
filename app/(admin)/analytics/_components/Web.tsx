import { getFormatter, getTranslations } from 'next-intl/server'
import type { Spend, Web as WebData } from '@/lib/data/analytics'
import { RANGE_DAYS, share, type RangeKey } from '@/lib/data/analytics-calc'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { Campaigns } from './Campaigns'
import { Empty, Kpi, cardChart, cardTable, colHead, sub, title } from './kit'

const SRC_COLS = '[grid-template-columns:minmax(0,1.3fr)_70px_70px_60px_60px]'
const PAGE_COLS = '[grid-template-columns:minmax(0,1.6fr)_70px_60px_70px]'
const SC_COLS = '[grid-template-columns:minmax(0,1.6fr)_80px_60px_60px]'

/**
 * Web analytics (Analytics.dc.html, v.web) on analytics_web: the in-house cookieless tracker (D-37). The
 * database keeps a daily-salted hash, never an address or a cookie, so «visitors» over a period is a sum of
 * daily uniques. Before the tracker sends anything the tab shows its empty state; Search Console shows its
 * connection state; campaign spend is what people entered.
 */
export async function Web({ d, spend, canSpend, range, nf, now }: {
  d: WebData; spend: Spend[]; canSpend: boolean; range: RangeKey; nf: NumberFormat; now: Date
}) {
  const t = await getTranslations('analytics')
  const format = await getFormatter()
  const sites = d.sites.map((s) => s.hostname).join(', ')
  const has = d.sessions > 0
  const pct = (n: number | null) => (n === null ? '—' : percent(n, nf))
  const channel = (c: string) => (t.has(`channels.${c}`) ? t(`channels.${c}`) : c)

  // the daily series over the range, a day without sessions drawn at zero
  const days = RANGE_DAYS[range]
  const daily = new Map(d.daily.map((x) => [x.day.slice(0, 10), x]))
  const dayKeys = Array.from({ length: days }, (_, i) => new Date(now.getTime() - (days - 1 - i) * 86_400_000).toISOString().slice(0, 10))
  const series = dayKeys.map((k) => daily.get(k)?.visitors ?? 0)
  const vmax = Math.max(1, ...series)
  const xy = (i: number, v: number) => `${((i * 600) / (days - 1)).toFixed(1)},${(156 - Math.min(1, v / vmax) * 146).toFixed(1)}`
  const pts = series.map((v, i) => xy(i, v)).join(' ')
  // signups × 20, drawn only on the days the read returns (a day with sessions)
  const hasSignups = d.daily.some((x) => typeof x.signups === 'number')
  const sign = dayKeys.flatMap((k, i) => { const x = daily.get(k); return typeof x?.signups === 'number' ? [xy(i, x.signups * 20)] : [] }).join(' ')
  const posTone = (p: number) => (p <= 3 ? 'text-link' : p <= 6 ? 'text-warn-ink' : 'text-danger')

  const ev = (name: string) => d.events.filter((e) => e.name === name).reduce((a, e) => a + e.count, 0)
  const funnel = [
    { key: 'visit', v: d.sessions },
    { key: 'kom_i_gang', v: ev('kom_i_gang') },
    { key: 'orgnr_entered', v: ev('orgnr_entered') },
    { key: 'account_created', v: d.signups },
  ]
  const personas = d.events.filter((e) => e.name === 'persona_click' && e.value)
  const persona = (v: string) => (t.has(`web.personas.names.${v}`) ? t(`web.personas.names.${v}`) : v)
  const monthLabel = Object.fromEntries(spend.map((s) => [s.month, format.dateTime(new Date(`${s.month}-15T12:00:00Z`), { month: 'short', year: 'numeric' })]))
  const thisMonth = now.toISOString().slice(0, 7)
  const connected = d.search_console === 'connected'

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-[10px] rounded-14 border border-dashed border-line-strong px-[14px] py-[10px] text-12 text-muted">{t('web.banner')}</div>

      {has ? (
        <>
          <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
            <Kpi size={24} label={t('web.kpi.visitors')} value={formatNumber(d.visitors, nf)} />
            <Kpi size={24} label={t('web.kpi.sessions')} value={formatNumber(d.sessions, nf)} />
            <Kpi size={24} label={t('web.kpi.pages')} value={formatNumber(d.pageviews / d.sessions, nf, 1)} />
            <Kpi size={24} label={t('web.kpi.bounce')} value={pct(share(d.bounces, d.sessions))} />
            <Kpi size={24} label={t('web.kpi.signups')} value={formatNumber(d.signups, nf)} />
          </div>

          <div className={cardChart}>
            <div className="mb-[10px] flex items-baseline justify-between gap-3">
              <span className={title}>{hasSignups ? t('web.chart.titleSignups', { sites }) : t('web.chart.title', { sites })}</span>
              <span className={sub}>{t(`usage.rangeLong.${range}`)}</span>
            </div>
            <svg viewBox="0 0 600 160" preserveAspectRatio="none" className="block h-[160px] w-full" role="img" aria-label={t('web.chart.visitors')}>
              <polygon points={`0,156 ${pts} 600,156`} fill="#E4EEEC" />
              <polyline points={pts} fill="none" stroke="#9DB8B3" strokeWidth="2" vectorEffect="non-scaling-stroke" />
              {hasSignups ? <polyline points={sign} fill="none" stroke="#2F5D2A" strokeWidth="2" strokeDasharray="5 4" vectorEffect="non-scaling-stroke" /> : null}
            </svg>
            <div className="mt-2 flex gap-[14px] text-11.5 text-muted">
              <span className="flex items-center gap-[6px]"><span className="h-[3px] w-[14px] bg-teal-mid" />{t('web.chart.visitors')}</span>
              {hasSignups ? <span className="flex items-center gap-[6px]"><span className="h-[3px] w-[14px] bg-link" />{t('web.chart.signups')}</span> : null}
            </div>
          </div>

          <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
            <div className={cardChart}>
              <div className={`${title} mb-3`}>{t('web.funnel.title')}</div>
              {funnel.map((f, i) => {
                const prev = i ? funnel[i - 1]!.v : f.v
                return (
                  <div key={f.key} className="grid items-center gap-[10px] py-[6px] text-12.5 [grid-template-columns:minmax(0,1.3fr)_minmax(0,1fr)_54px_54px]">
                    <span className="font-semibold">{t(`web.funnel.${f.key}`)}</span>
                    <span className="block h-5 overflow-hidden rounded-7 bg-tile"><span className="block h-full bg-blue-bg" style={{ width: `${Math.min(100, (f.v / Math.max(1, d.sessions)) * 100 + 2)}%` }} /></span>
                    <b className="text-right">{formatNumber(f.v, nf)}</b>
                    <span className="text-right text-12 font-bold text-danger">{i && prev ? `−${percent(Math.round(Math.max(0, 1 - f.v / prev) * 100), nf)}` : ''}</span>
                  </div>
                )
              })}
            </div>
            <div className={cardChart}>
              <div className={`${title} mb-3`}>{t('web.personas.title')}</div>
              {personas.length ? (
                <div className="grid grid-cols-2 gap-[10px]">
                  {personas.map((p) => (
                    <div key={p.value} className="rounded-15 border border-line bg-canvas px-[14px] py-3">
                      <b className="text-13">{persona(p.value!)}</b>
                      <div className="mt-1 font-serif text-24 font-semibold">{formatNumber(p.count, nf)}</div>
                      <div className="text-11.5 text-muted">{t('web.personas.sub')}</div>
                    </div>
                  ))}
                </div>
              ) : <Empty>{t('web.personas.empty')}</Empty>}
            </div>
          </div>

          <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
            <div className={`${cardTable} overflow-x-auto`}>
              <div className={`border-b border-line px-[18px] py-[14px] ${title}`}>{t('web.sources.title')}</div>
              <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] min-w-[420px] ${colHead} ${SRC_COLS}`}>
                <span>{t('web.sources.cols.source')}</span><span>{t('web.sources.cols.visits')}</span><span>{t('web.sources.cols.bounce')}</span>
                <span>{t('web.sources.cols.signups')}</span><span>{t('web.sources.cols.conv')}</span>
              </div>
              {d.channels.map((s) => (
                <div key={s.channel} className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] min-w-[420px] text-13 tabular-nums ${SRC_COLS}`}>
                  <b>{channel(s.channel)}</b><span>{formatNumber(s.sessions, nf)}</span>
                  <span className="text-muted">{s.bounce != null ? percent(s.bounce, nf) : '—'}</span>
                  <span>{s.signups != null ? formatNumber(s.signups, nf) : '—'}</span>
                  <b>{s.signups != null ? pct(share(s.signups, s.sessions)) : '—'}</b>
                </div>
              ))}
            </div>
            <div className={cardTable}>
              <div className={`border-b border-line px-[18px] py-[14px] ${title}`}>{t('web.pages.title')}</div>
              {d.landing.map((s) => (
                <div key={s.path ?? ''} className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-13 tabular-nums ${PAGE_COLS}`}>
                  <span className="truncate font-[ui-monospace,Menlo,monospace] text-12">{s.path ?? '—'}</span><span>{formatNumber(s.sessions, nf)}</span><span>—</span><b className="text-link">—</b>
                </div>
              ))}
            </div>
          </div>
        </>
      ) : (
        <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center">
          <div className="text-15 font-bold">{t('web.empty.title')}</div>
          <div className="mt-2 text-13 text-muted">{t('web.empty.body', { sites })}</div>
        </div>
      )}

      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
        <div className={cardTable}>
          <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
            <span className={title}>{t('web.campaigns.title')}</span><span className={sub}>{t('web.campaigns.sub')}</span>
          </div>
          <Campaigns rows={spend} figures={d.campaigns ?? []} canEdit={canSpend} nf={nf} thisMonth={thisMonth} monthLabel={monthLabel} />
        </div>
        <div className={cardTable}>
          <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
            <span className={title}>{t('web.search.title')}</span>
            <span className={sub}>{connected ? t('web.search.sub') : t('web.search.notConnected.tag')}</span>
          </div>
          {connected ? (
            <>
              <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] ${colHead} ${SC_COLS}`}>
                <span>{t('web.search.cols.query')}</span><span>{t('web.search.cols.impr')}</span><span>{t('web.search.cols.clicks')}</span><span>{t('web.search.cols.pos')}</span>
              </div>
              {d.search.map((s) => (
                <div key={s.query} className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-13 tabular-nums ${SC_COLS}`}>
                  <span>{s.query}</span><span>{formatNumber(s.impressions, nf)}</span><span>{formatNumber(s.clicks, nf)}</span>
                  {s.position != null ? <b className={posTone(s.position)}>{formatNumber(s.position, nf, 1)}</b> : <b>—</b>}
                </div>
              ))}
              {d.search.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{t('web.search.empty')}</div> : null}
            </>
          ) : (
            <div className="px-[18px] py-5">
              <div className="text-13.5 font-bold">{t('web.search.notConnected.title')}</div>
              <div className="mt-1 text-12.5 text-muted">{t('web.search.notConnected.body')}</div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
