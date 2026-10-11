import Link from 'next/link'
import type { Route } from 'next'
import { getLocale, getTranslations } from 'next-intl/server'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { relChange, rate, type Opportunity } from '@/lib/growth/calc'
import { growthHref, type Metric, type Scope } from '@/lib/growth/scope'
import type { GrowthScope } from '@/lib/growth/types'
import { Delta, Tile, card, cardTable, channelColor, colHead, dayLabel, head, hh } from './v2kit'

const KEY: Record<Metric, 'visitors' | 'started' | 'accounts' | 'paying'> = { visitors: 'visitors', signups: 'started', accounts: 'accounts', paying: 'paying' }
const CH_COLS = '[grid-template-columns:minmax(0,1.3fr)_70px_60px_60px_70px]'

/**
 * Growth › Overview (SimpleGrowth.dc.html, v.overview) on growth_scope. A KPI picks the chart's metric; a day opens its
 * hours, an hour opens the signup log of that hour (the design's drill). Account figures are «—» under a device filter
 * (an account has no device); visitors are «—» before the tracker's first day.
 */
export async function OverviewTab({ d, scope, metric, nf, opps }: { d: GrowthScope; scope: Scope; metric: Metric; nf: NumberFormat; opps: Opportunity[] }) {
  const t = await getTranslations('simpleGrowth.overview')
  const tc = await getTranslations('simpleGrowth.channels')
  const locale = await getLocale()
  const k = d.kpis
  const dash = '—'
  const num = (v: number | null) => (v === null ? dash : formatNumber(v, nf))
  const conv = rate(k.started, k.visitors)
  const convPrev = rate(k.started_prev, k.visitors_prev)
  const cpp = k.spend !== null && k.paying ? k.spend / k.paying : null
  const cppPrev = k.spend_prev !== null && k.paying_prev ? k.spend_prev / k.paying_prev : null
  const channelName = (c: string) => (tc.has(c) ? tc(c) : c)
  const metricName = t(`metrics.${metric}`)

  const kpis: { key: Metric | null; label: string; value: string; change: number | null; lower?: boolean; title?: string }[] = [
    { key: 'visitors', label: t('kpi.visitors'), value: num(k.visitors), change: relChange(k.visitors, k.visitors_prev), title: k.visitors === null ? t('kpi.notTracked') : undefined },
    { key: 'signups', label: t('kpi.signups'), value: num(k.started), change: relChange(k.started, k.started_prev) },
    { key: null, label: t('kpi.conversion'), value: conv === null ? dash : percent(conv * 100, nf), change: conv !== null && convPrev ? Math.round((conv / convPrev - 1) * 100) : null },
    { key: 'accounts', label: t('kpi.accounts'), value: num(k.accounts), change: relChange(k.accounts, k.accounts_prev), title: k.accounts === null ? t('kpi.noDevice') : undefined },
    { key: 'paying', label: t('kpi.paying'), value: num(k.paying), change: relChange(k.paying, k.paying_prev), title: k.paying === null ? t('kpi.noDevice') : undefined },
    { key: null, label: t('kpi.cost'), value: cpp === null ? dash : money(cpp, nf), change: relChange(cpp, cppPrev), lower: true,
      title: k.spend === null ? (scope.dev ? t('kpi.noDevice') : scope.day || scope.range === 'today' ? t('kpi.costNoDay') : t('kpi.costNone')) : t('kpi.costTip') },
  ]

  // the chart: the period's days, or the chosen day's hours
  const hourly = d.day !== null
  const key = KEY[metric]
  const values = d.series.map((x) => x[key])
  const mx = Math.max(1, ...values.map((v) => v ?? 0))
  const n = d.series.length
  const gap = hourly ? 4 : n > 60 ? 1 : n > 20 ? 3 : 8
  const dayName = d.day ? dayLabel(d.day, locale) : ''
  const bars = d.series.map((x, i) => {
    const v = x[key]
    const h = v === null ? 0 : (v / mx) * 96 + 1
    // the inner bar: signups begun as a share of the visitors, ×8 so it shows (the design's scale); visitors only
    const sh = metric === 'visitors' && x.visitors ? Math.min(100, ((x.started ?? 0) / x.visitors) * 800) : 0
    if (hourly) {
      const hr = Number(x.at)
      return {
        h, sh, color: d.hour === hr ? '#F5C64A' : '#CFE0F5', label: hr % 3 === 0 ? String(hr).padStart(2, '0') : '', on: d.hour === hr,
        tip: t('chart.tipHour', { hour: hh(hr), visitors: num(x.visitors), signups: num(x.started) }),
        // an hour opens its signup log (the design moves to the funnel tab)
        href: growthHref('funnel', { ...scope, day: scope.range === 'today' ? null : d.day, hour: hr }),
      }
    }
    const date = new Date(`${x.at}T12:00:00Z`)
    const weekend = date.getUTCDay() === 0 || date.getUTCDay() === 6
    const label = n <= 31 ? (n <= 7 ? dayLabel(x.at, locale).split(' ').slice(0, 2).join(' ') : i % 3 === 0 ? String(date.getUTCDate()) : '')
      : i % 10 === 0 ? `${date.getUTCDate()}/${date.getUTCMonth() + 1}` : ''
    return {
      h, sh, color: weekend ? '#E4EEEC' : '#CFE0F5', label, on: false,
      tip: t('chart.tipDay', { day: dayLabel(x.at, locale), visitors: num(x.visitors), signups: num(x.started), paying: num(x.paying) }),
      href: growthHref('overview', { ...scope, day: x.at, hour: null }, { metric }),
    }
  })
  const title = hourly ? t('chart.byHour', { metric: metricName, day: dayName }) : t('chart.perDay', { metric: metricName, days: d.days })

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        {kpis.map((x) => (
          <Tile key={x.label} label={x.label} value={x.value} title={x.title}
            delta={<Delta change={x.value === dash ? null : x.change} lowerIsBetter={x.lower} nf={nf} />}
            href={x.key ? growthHref('overview', scope, { metric: x.key }) : undefined} on={x.key === metric} />
        ))}
      </div>

      <div className={`${card} px-5 py-4`}>
        <div className="mb-3 flex flex-wrap items-baseline justify-between gap-[10px]">
          <b className="text-15">{title}</b>
          <span className="text-12 text-muted">{hourly ? t('chart.hintHour') : t('chart.hintDay')}</span>
        </div>
        <div className="flex h-[190px] items-end border-b border-line-strong" style={{ gap: `${gap}px` }}>
          {bars.map((b, i) => (
            <Link key={i} href={b.href as Route} title={b.tip} aria-label={b.tip}
              className="flex h-full min-w-0 flex-1 cursor-pointer flex-col items-stretch justify-end border-none bg-transparent p-0">
              <span className="relative block rounded-t-5" style={{ height: `${b.h}%`, background: b.color }}>
                {b.sh > 0 ? <span className="absolute bottom-0 left-[20%] right-[20%] rounded-t-3 bg-link" style={{ height: `${b.sh}%` }} /> : null}
              </span>
            </Link>
          ))}
        </div>
        <div className="mt-[5px] flex" style={{ gap: `${gap}px` }}>
          {bars.map((b, i) => (
            <span key={i} className={`min-w-0 flex-1 overflow-hidden whitespace-nowrap text-center text-10 ${b.on ? 'text-ink' : 'text-faint'}`}>{b.label}</span>
          ))}
        </div>
        <div className="mt-[10px] flex flex-wrap gap-[14px] text-11.5 text-muted">
          <span className="flex items-center gap-[6px]"><span className="h-[10px] w-[10px] rounded-3 bg-blue-bg" />{metricName}</span>
          {metric === 'visitors' ? <span className="flex items-center gap-[6px]"><span className="h-[10px] w-[10px] rounded-3 bg-link" />{t('chart.inner')}</span> : null}
          {d.peak_hour !== null ? <span>{t('chart.peak', { from: hh(d.peak_hour), to: hh((d.peak_hour + 1) % 24) })}</span> : null}
        </div>
        {d.tracked_since === null ? <div className="mt-2 text-12 text-muted">{d.site ? t('chart.waiting', { site: d.site.hostname }) : t('chart.noSite')}</div> : null}
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={cardTable}>
          <div className={head}><b className="text-15">{t('opps.title')}</b><span className="text-12 text-muted">{t('opps.sub')}</span></div>
          {opps.map((o, i) => {
            const text = oppText(o, t, nf)
            return (
              <div key={i} className="flex items-center gap-3 border-b border-line px-[18px] py-[11px]">
                <span className="w-11 flex-none text-center font-serif text-19 font-semibold text-link">+{o.gain}</span>
                <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
                  <b className="text-13 leading-[1.3]">{text.title}</b>
                  <span className="text-11.5 text-muted">{text.sub} · {t('opps.effort', { effort: t(`opps.efforts.${o.effort}`) })}</span>
                </span>
                <Link href={oppHref(o, scope) as Route}
                  className="flex h-[30px] flex-none cursor-pointer items-center whitespace-nowrap rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold text-ink hover:text-ink hover:no-underline">
                  {t(`opps.cta.${o.kind}`)}
                </Link>
              </div>
            )
          })}
          {opps.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{t('opps.none')}</div> : null}
        </div>

        <div className={cardTable}>
          <div className={head}><b className="text-15">{t('channels.title')}</b><span className="text-12 text-muted">{t('channels.sub')}</span></div>
          <div className="overflow-x-auto"><div className="min-w-[400px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] ${colHead} ${CH_COLS}`}>
            <span>{t('channels.source')}</span><span>{t('channels.visits')}</span><span>{t('channels.signups')}</span><span>{t('channels.conv')}</span><span>{t('channels.paying')}</span>
          </div>
          {d.channels.map((c) => {
            const on = scope.src === c.channel
            const cv = rate(c.started, c.visits)
            return (
              <Link key={c.channel} href={growthHref('overview', { ...scope, src: on ? null : c.channel }, { metric }) as Route} aria-current={on ? 'true' : undefined}
                className={`grid w-full cursor-pointer items-center gap-[10px] border-b border-line px-[18px] py-[9px] text-left text-13 tabular-nums text-ink hover:text-ink hover:no-underline ${CH_COLS} ${on ? 'bg-highlight' : 'bg-transparent'}`}>
                <span className="flex min-w-0 items-center gap-2">
                  <span className="h-[9px] w-[9px] flex-none rounded-3" style={{ background: channelColor(c.channel) }} />
                  <b className="overflow-hidden text-ellipsis whitespace-nowrap">{channelName(c.channel)}</b>
                </span>
                <span>{num(c.visits)}</span>
                <span>{num(c.started)}</span>
                <b>{cv === null ? dash : percent(cv * 100, nf)}</b>
                <span>{num(c.paying)}</span>
              </Link>
            )
          })}
          {d.channels.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{t('channels.none')}</div> : null}
          </div></div>
        </div>
      </div>
    </div>
  )
}

type T = Awaited<ReturnType<typeof getTranslations<'simpleGrowth.overview'>>>
function oppText(o: Opportunity, t: T, nf: NumberFormat): { title: string; sub: string } {
  switch (o.kind) {
    case 'error': return { title: t('opps.error.title', { value: o.value }), sub: t('opps.error.sub', { count: o.count }) }
    case 'keyword': return { title: t('opps.keyword.title', { query: o.query }), sub: t('opps.keyword.sub', { position: formatNumber(o.position, nf, 1), clicks: formatNumber(o.potential, nf) }) }
    case 'page': return { title: t('opps.page.title', { path: o.path }), sub: t('opps.page.sub', { conv: percent(o.conv * 100, nf) }) }
    case 'mobile': return { title: t('opps.mobile.title'), sub: t('opps.mobile.sub', { mobile: percent(o.mobileRate * 100, nf), desktop: percent(o.desktopRate * 100, nf), share: percent(Math.round(o.share * 100), nf) }) }
    case 'slow': return { title: t('opps.slow.title', { path: o.path }), sub: t('opps.slow.sub', { lcp: formatNumber(o.lcp_ms / 1000, nf, 1), share: percent(Math.round(o.share * 100), nf) }) }
  }
}

function oppHref(o: Opportunity, scope: Scope): string {
  switch (o.kind) {
    case 'error': return growthHref('funnel', scope, { step: 4 })
    case 'keyword': return growthHref('seo', scope, { sub: 'keywords', kw: o.query })
    case 'page': return growthHref('pages', scope, { page: o.path })
    case 'mobile': return growthHref('funnel', { ...scope, dev: 'mobile' }, { step: 3 })
    case 'slow': return growthHref('pages', scope, { page: o.path })
  }
}
