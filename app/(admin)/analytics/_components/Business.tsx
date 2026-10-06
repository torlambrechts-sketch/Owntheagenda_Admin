import { getFormatter, getTranslations } from 'next-intl/server'
import type { Business as BusinessData, MetricDef } from '@/lib/data/analytics'
import {
  RANGE_DAYS, firstSnapshotMonth, monthsEnding, movementsInRange, pctChange, share, trialCohortSpan, verdict, type RangeKey,
} from '@/lib/data/analytics-calc'
import { formatNumber, money, percent, thousands, type NumberFormat } from '@/lib/format'
import { CustomersBy } from './CustomersBy'
import { Empty, Kpi, Swatch, Track, cardChart, deltaTone, signedPct, sub, title } from './kit'

// the design's palettes (Analytics.dc.html: nnLegend, colors, tiers)
const NN = { new: '#5C9A55', expansion: '#B5DAD4', contraction: '#F5DC96', churn: '#D4633A' } as const
const LINE: Record<string, string> = { orgpuls: '#5C9A55', skiftly: '#6E8FB8', avvik: '#D4633A', kurs: '#8F74B3' }
const TIER = ['#F6D9C6', '#DCEBD3', '#CFE0F5', '#E7DAF2']

type Product = { key: string; name: string; color: string }

/** Business KPIs (Analytics.dc.html, v.business) on analytics_business for the chosen range and product. */
export async function Business({ d, defs, range, products, scope, nf, now }: {
  d: BusinessData; defs: MetricDef[]; range: RangeKey; products: Product[]; scope: string; nf: NumberFormat; now: Date
}) {
  const t = await getTranslations('analytics')
  const format = await getFormatter()
  const mon = (m: string) => format.dateTime(new Date(`${m}-15T12:00:00Z`), { month: 'short' })
  const monYear = (m: string) => format.dateTime(new Date(`${m}-15T12:00:00Z`), { month: 'long' })
  const monYy = (m: string) => format.dateTime(new Date(`${m}-15T12:00:00Z`), { month: 'short', year: '2-digit' })
  const def = (key: string) => {
    const x = defs.find((r) => r.key === key)
    return x ? t('defs.tip', { view: x.view, version: t('defs.version', { migration: x.migration, version: x.version }), text: t(`defs.rows.${key}`) }) : undefined
  }
  const pct = (n: number | null) => (n === null ? '—' : percent(n, nf))

  // headline: a sentence of the two figures the first question asks about
  const conv = share(d.trial_conversion?.converted, d.trial_conversion?.trials)
  const tiltak = share(d.activated_after_result?.tiltak_30d, d.activated_after_result?.paying)
  const v = verdict(conv, tiltak)
  const headline = v ? t(`business.headline.${v}`, { conv: pct(conv), tiltak: pct(tiltak) }) : t('business.headline.noData')

  // KPIs
  const mrrDelta = pctChange(d.mrr, d.mrr_prev)
  const mv = movementsInRange(d.movements, now, range)
  const lost = -(mv.churn + mv.contraction)
  const revChurn = mv.months ? share(lost, d.mrr_prev) : null
  const netChurn = mv.months ? share(lost - mv.expansion, d.mrr_prev) : null
  const [from, to] = trialCohortSpan(now, RANGE_DAYS[range])
  const arpa = d.mrr !== null && d.paying_accounts > 0 ? d.mrr / d.paying_accounts : null
  const kpis = [
    { label: t('business.kpi.mrr'), value: d.mrr !== null ? money(d.mrr, nf) : '—', delta: mrrDelta !== null ? signedPct(mrrDelta, nf) : null, tone: deltaTone(mrrDelta ?? 0), subText: scope, tip: def('mrr') },
    { label: t('business.kpi.arr'), value: d.mrr !== null ? money(d.mrr * 12, nf) : '—', subText: t('business.kpi.arrSub') },
    { label: t('business.kpi.netNew'), value: mv.months ? money(mv.net, nf) : '—', subText: t(`business.kpi.netNewSub.${range}`), tip: def('net_new_mrr') },
    { label: t('business.kpi.paying'), value: formatNumber(d.paying_accounts, nf), subText: t('business.kpi.payingSub') },
    { label: t('business.kpi.trials'), value: formatNumber(d.trials, nf), delta: t('business.kpi.trialsEnding', { count: d.trials_ending_7 }), tone: 'text-warn-ink', subText: t('business.kpi.trialsSub') },
    {
      label: t('business.kpi.conversion'), value: pct(conv), tip: def('trial_conversion'),
      subText: conv === null ? t('business.kpi.conversionNone') : from === to ? t('business.kpi.conversionSub', { from: monYear(from) }) : t('business.kpi.conversionSpan', from.slice(0, 4) === to.slice(0, 4) ? { from: mon(from), to: mon(to) } : { from: monYy(from), to: monYy(to) }),
    },
    { label: t('business.kpi.logoChurn'), value: d.churn ? formatNumber(d.churn.logos, nf) : '—', subText: t(`business.kpi.logoChurnSub.${range}`), tip: def('logo_churn') },
    {
      label: t('business.kpi.revenueChurn'), value: pct(revChurn), tip: def('revenue_churn'),
      subText: netChurn !== null ? t('business.kpi.revenueChurnSub', { net: signedPct(netChurn, nf) }) : t('business.kpi.revenueChurnNoBase'),
    },
    { label: t('business.kpi.arpa'), value: arpa !== null ? money(arpa, nf) : '—', subText: t('business.kpi.arpaSub') },
    { label: t('business.kpi.customers'), value: formatNumber(d.customers, nf), subText: t('business.kpi.customersSub') },
  ]

  // net new MRR, twelve months
  const months = monthsEnding(now, 12)
  const byMonth = new Map(d.movements.map((m) => [m.month, m]))
  const up = Math.max(0, ...d.movements.map((m) => m.new + m.expansion))
  const down = Math.max(0, ...d.movements.map((m) => -(m.contraction + m.churn)))
  const k = Math.min(up ? 120 / up : Infinity, down ? 60 / down : Infinity)
  const px = (x: number) => (Number.isFinite(k) ? Math.round(Math.abs(x) * k) : 0)
  const first = firstSnapshotMonth(d.movements)

  // MRR by application, twelve months
  const lines = products.map((p) => {
    const rows = new Map(d.mrr_by_product.filter((r) => r.product === p.key && r.mrr !== null).map((r) => [r.month, r.mrr as number]))
    return { ...p, rows, last: rows.get(months[11]!) ?? null }
  }).filter((l) => [...l.rows.values()].some((x) => x > 0))
  const lmax = Math.max(1, ...lines.flatMap((l) => [...l.rows.values()]))

  // trial → paid by source
  const sources = d.trials_by_source
    .map((s) => ({ ...s, pct: share(s.converted, s.trials) ?? 0 }))
    .sort((a, b) => b.pct - a.pct)
  const channel = (c: string) => (t.has(`channels.${c}`) ? t(`channels.${c}`) : c)

  const tmax = Math.max(1, ...d.bands.map((b) => b.accounts))
  const dimRow = (r: { key: string; count: number }) => ({ n: r.key || t('business.dims.unknown'), v: r.count })

  return (
    <div className="flex flex-col gap-4">
      <div className="rounded-20 border border-line bg-surface px-6 py-5">
        <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('business.eyebrow')}</div>
        <div className="mt-[6px] font-serif text-24 font-semibold leading-[1.2] [text-wrap:balance]">{headline}</div>
      </div>

      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(160px,1fr))]">
        {kpis.map((x) => <Kpi key={x.label} {...x} />)}
      </div>
      {d.excluded_currency ? <div className="-mt-2 text-12 text-muted">{t('excludedCurrency', { count: d.excluded_currency })}</div> : null}

      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
        <div className={cardChart}>
          <div className="flex items-baseline justify-between"><span className={title}>{t('business.nn.title')}</span><span className={sub}>{t('business.nn.sub')}</span></div>
          <div className="mb-2 mt-[10px] flex gap-3">
            {(Object.keys(NN) as (keyof typeof NN)[]).map((key) => (
              <span key={key} className="flex items-center gap-[6px] text-11.5 text-muted"><Swatch color={NN[key]} />{t(`business.nn.legend.${key}`)}</span>
            ))}
          </div>
          {d.movements.length ? (
            <>
              <div className="flex h-[200px] gap-2">
                {months.map((m) => {
                  const x = byMonth.get(m)
                  return (
                    <div
                      key={m}
                      className="flex flex-1 flex-col"
                      title={x ? t('business.nn.tip', {
                        month: mon(m), new: formatNumber(x.new, nf), expansion: formatNumber(x.expansion, nf),
                        contraction: formatNumber(x.contraction, nf), churn: formatNumber(x.churn, nf),
                      }) : t('business.nn.noData', { month: mon(m) })}
                    >
                      <div className="flex h-[120px] flex-col justify-end">
                        <div className="rounded-t-5 bg-teal-light" style={{ height: px(x?.expansion ?? 0) }} />
                        <div className="bg-ok" style={{ height: px(x?.new ?? 0) }} />
                      </div>
                      <div className="h-px bg-ink" />
                      <div className="flex h-[60px] flex-col">
                        <div className="bg-amber-bg" style={{ height: px(x?.contraction ?? 0) }} />
                        <div className="rounded-b-5 bg-alert" style={{ height: px(x?.churn ?? 0) }} />
                      </div>
                      <div className="mt-1 text-center text-10.5 text-faint">{mon(m)}</div>
                    </div>
                  )
                })}
              </div>
              {first && months.includes(first) ? <div className="mt-2 text-11 text-faint">{t('business.nn.baseline', { month: monYear(first) })}</div> : null}
            </>
          ) : <Empty className="flex h-[200px] items-center justify-center">{t('business.nn.empty')}</Empty>}
        </div>

        <div className={cardChart}>
          <div className="flex items-baseline justify-between"><span className={title}>{t('business.byApp.title')}</span><span className={sub}>{t('business.byApp.sub')}</span></div>
          <div className="mb-2 mt-[10px] flex flex-wrap gap-3">
            {lines.map((l) => (
              <span key={l.key} className="flex items-center gap-[6px] text-11.5 text-muted">
                <Swatch color={LINE[l.key] ?? l.color} line />{l.name} <b className="text-ink">{l.last !== null ? thousands(l.last, nf) : '—'}</b>
              </span>
            ))}
          </div>
          {lines.length ? (
            <>
              <svg viewBox="0 0 600 180" preserveAspectRatio="none" className="block h-[180px] w-full" role="img" aria-label={t('business.byApp.title')}>
                <line x1="0" y1="179" x2="600" y2="179" stroke="#C4BCA8" strokeWidth="1" />
                <line x1="0" y1="90" x2="600" y2="90" stroke="#E8DFC9" strokeWidth="1" strokeDasharray="4 4" />
                {lines.map((l) => (
                  <polyline
                    key={l.key}
                    points={months.flatMap((m, i) => (l.rows.has(m) ? [`${((i * 600) / 11).toFixed(1)},${(176 - ((l.rows.get(m) ?? 0) / lmax) * 166).toFixed(1)}`] : [])).join(' ')}
                    fill="none" stroke={LINE[l.key] ?? l.color} strokeWidth="2.5" strokeLinejoin="round" vectorEffect="non-scaling-stroke"
                  />
                ))}
              </svg>
              <div className="mt-1 flex justify-between text-10.5 text-faint">{months.map((m) => <span key={m}>{mon(m)}</span>)}</div>
            </>
          ) : <Empty className="flex h-[180px] items-center justify-center">{t('business.byApp.empty')}</Empty>}
        </div>
      </div>

      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,330px),1fr))]">
        <div className={cardChart}>
          <div className={`${title} mb-3`}>{t('business.bySource.title')}</div>
          {sources.length ? sources.map((s) => (
            <div key={s.channel} className="grid items-center gap-2 py-[5px] text-12.5 [grid-template-columns:110px_minmax(0,1fr)_46px_40px]" title={t('business.bySource.tip', { converted: s.converted, trials: s.trials })}>
              <span>{channel(s.channel)}</span>
              <Track w={s.pct} fill="#5C9A55" />
              <b className="text-right">{percent(s.pct, nf)}</b>
              <span className="text-right text-faint">{s.trials}</span>
            </div>
          )) : <Empty>{t('business.bySource.empty')}</Empty>}
        </div>

        <div className={cardChart}>
          <div className={`${title} mb-1`}>{t('business.tiers.title')}</div>
          <div className="mb-3 text-12 text-muted">
            {t.rich('business.tiers.sub', { arpa: arpa !== null ? money(arpa, nf) : '—', b: (c) => <b className="text-ink">{c}</b> })}
          </div>
          {d.bands.length ? (
            <div className="flex h-[130px] items-end gap-3">
              {d.bands.map((b, i) => (
                <div key={b.band} className="flex flex-1 flex-col items-center gap-[5px]">
                  <b className="text-12">{b.accounts}</b>
                  <div className="w-full rounded-t-7 border border-[rgba(25,21,16,.1)]" style={{ height: Math.round((b.accounts / tmax) * 100), background: TIER[i % TIER.length] }} />
                  <span className="text-11 text-muted">{b.band}</span>
                </div>
              ))}
            </div>
          ) : <Empty>{t('business.tiers.empty')}</Empty>}
        </div>

        <CustomersBy
          rows={{
            industry: d.by_industry.map(dimRow),
            fylke: d.by_fylke.map(dimRow),
            size: d.bands.map((b) => ({ n: t('business.dims.employees', { band: b.band }), v: b.accounts })),
          }}
        />
      </div>
    </div>
  )
}
