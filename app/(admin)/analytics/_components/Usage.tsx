import { getFormatter, getTranslations } from 'next-intl/server'
import type { Usage as UsageData } from '@/lib/data/analytics'
import { monthsEnding, share, type RangeKey } from '@/lib/data/analytics-calc'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { Empty, Kpi, Swatch, cardChart, cardTable, signedPct, sub, title } from './kit'

const ROLES = ['daglig_leder', 'avdelingsleder', 'verneombud'] as const
type Product = { key: string; name: string; color: string; ink: string }

/**
 * Product usage (Analytics.dc.html, v.usage) on analytics_usage: survey rounds as counts and dates only
 * (D-19), logins by Orgpuls' three roles, and the counts each application reports. Groups hidden by the
 * threshold and comment counts wait for a decision with Orgpuls and are not shown.
 */
export async function Usage({ d, range, products, single, nf, now }: {
  d: UsageData; range: RangeKey; products: Product[]; single: boolean; nf: NumberFormat; now: Date
}) {
  const t = await getTranslations('analytics.usage')
  const tr = await getTranslations('analytics.ranges')
  const format = await getFormatter()
  const mon = (m: string) => format.dateTime(new Date(`${m}-15T12:00:00Z`), { month: 'short' })
  const pct = (n: number | null | undefined) => (n === null || n === undefined ? '—' : percent(n, nf))
  const metric = (k: string) => (t.has(`metrics.${k}`) ? t(`metrics.${k}`) : k.replace(/_/g, ' '))

  const rr = d.response_rate
  const overall = rr?.all ?? (rr?.main === null ? rr?.pulse : rr?.pulse === null ? rr?.main : null) ?? null
  const c = d.counts
  const kpis = [
    { label: t('kpi.surveys', { range: tr(range) }), value: formatNumber(d.rounds.main + d.rounds.pulse, nf), subText: t('kpi.surveysSub', { main: d.rounds.main, pulse: d.rounds.pulse }) },
    { label: t('kpi.response'), value: pct(overall), subText: t('kpi.responseSub', { main: pct(rr?.main), pulse: pct(rr?.pulse) }) },
    { label: t('kpi.reminder'), value: d.reminder_gain !== null ? signedPct(d.reminder_gain, nf) : '—', subText: t('kpi.reminderSub') },
    ...('tiltak_created' in c
      ? [{
          label: t('kpi.tiltak'), value: formatNumber(c.tiltak_created!, nf),
          subText: 'tiltak_with_owner_deadline' in c ? t('kpi.tiltakSub', { pct: pct(share(c.tiltak_with_owner_deadline, c.tiltak_created)) }) : t('kpi.tiltakSubNone'),
        }]
      : []),
    ...('tiltak_closed' in c && 'tiltak_closed_on_time' in c
      ? [{ label: t('kpi.closed'), value: pct(share(c.tiltak_closed_on_time, c.tiltak_closed)), subText: t('kpi.closedSub', { count: c.tiltak_closed! }) }]
      : []),
  ]

  const months = monthsEnding(now, 12)
  const rounds = new Map(d.rounds_by_month.map((x) => [x.month, x]))
  const smax = Math.max(1, ...d.rounds_by_month.map((x) => x.main + x.pulse))
  const logins = ROLES.map((r) => ({ r, v: d.logins[r] ?? 0 }))
  const lmax = Math.max(0, ...logins.map((x) => x.v))
  const appCounts = (p: Product): Record<string, number> | null => d.counts_by_product?.[p.key] ?? (single || Object.keys(d.counts).length === 0 ? d.counts : null)

  return (
    <div className="flex flex-col gap-4">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(170px,1fr))]">
        {kpis.map((k) => <Kpi key={k.label} {...k} size={24} />)}
      </div>

      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={cardChart}>
          <div className="mb-3 flex items-baseline justify-between">
            <span className={title}>{t('surveys.title')}</span>
            <span className="flex gap-[10px] text-11.5 text-muted">
              <span className="flex items-center gap-[5px]"><Swatch color="#D9CFB8" />{t('surveys.main')}</span>
              <span className="flex items-center gap-[5px]"><Swatch color="#A8D5D2" />{t('surveys.pulse')}</span>
            </span>
          </div>
          {d.rounds_by_month.length ? (
            <>
              <div className="flex h-[140px] items-end gap-2">
                {months.map((m) => {
                  const x = rounds.get(m)
                  return (
                    <div key={m} title={t('surveys.tip', { month: mon(m), main: x?.main ?? 0, pulse: x?.pulse ?? 0 })} className="flex h-full flex-1 flex-col justify-end">
                      <div className="rounded-t-5 bg-aqua" style={{ height: `${((x?.pulse ?? 0) / smax) * 100}%` }} />
                      <div className="bg-line-mid" style={{ height: `${((x?.main ?? 0) / smax) * 100}%` }} />
                    </div>
                  )
                })}
              </div>
              <div className="mt-1 flex gap-2">{months.map((m) => <span key={m} className="flex-1 text-center text-10.5 text-faint">{mon(m)}</span>)}</div>
            </>
          ) : <Empty>{t('surveys.empty')}</Empty>}
        </div>

        <div className={cardChart}>
          <div className={`${title} mb-3`}>{t('roles.title', { range: t(`rangeLong.${range}`) })}</div>
          {lmax > 0 ? logins.map((x) => (
            <div key={x.r} className="grid items-center gap-2 py-[6px] text-12.5 [grid-template-columns:170px_minmax(0,1fr)_50px]">
              <span>{t(`roles.${x.r}`)}</span>
              <span className="block h-[10px] overflow-hidden rounded-999 bg-tile"><span className="block h-full bg-teal-mid" style={{ width: `${(x.v / lmax) * 100}%` }} /></span>
              <b className="text-right">{formatNumber(x.v, nf)}</b>
            </div>
          )) : <Empty>{t('roles.empty')}</Empty>}
          <div className={`${title} mb-[10px] mt-4`}>{t('features.title')}</div>
          <Empty>{t('features.empty')}</Empty>
        </div>
      </div>

      <div className={cardTable}>
        <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
          <span className={title}>{t('apps.title')}</span><span className={sub}>{t('apps.sub')}</span>
        </div>
        {products.map((p) => {
          const counts = appCounts(p)
          const entries = counts ? Object.entries(counts).slice(0, 4) : []
          return (
            <div key={p.key} className="grid items-center gap-3 border-b border-line px-[18px] py-3 text-13 [grid-template-columns:30px_minmax(140px,1fr)_repeat(4,minmax(0,1fr))]">
              <span className="flex h-[26px] w-[26px] items-center justify-center rounded-8 font-serif font-bold" style={{ background: p.color, color: p.ink }}>{p.name[0]}</span>
              <b>{p.name}</b>
              {entries.length ? entries.map(([k, v]) => (
                <span key={k} className="flex flex-col"><b className="tabular-nums">{formatNumber(v, nf)}</b><span className="text-11.5 text-muted">{metric(k)}</span></span>
              )) : <span className="text-12 text-muted [grid-column:span_4]">{counts ? t('apps.none') : t('apps.combined')}</span>}
            </div>
          )
        })}
      </div>
    </div>
  )
}
