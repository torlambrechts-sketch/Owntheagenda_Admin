import { getFormatter, getTranslations } from 'next-intl/server'
import type { Business, Churns, Retention as RetentionData } from '@/lib/data/analytics'
import { addMonths, monthsEnding, revenueChurnByMonth, share, snapshotMonth } from '@/lib/data/analytics-calc'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { ChurnList } from './ChurnList'
import { GoButton } from './nav'
import { Empty, Swatch, cardChart, softPill, title } from './kit'

// the design's heat scale (Analytics.dc.html, heat)
const heat = (v: number) =>
  v >= 90 ? ['#B5DAD4', '#20431C'] : v >= 80 ? ['#CFE7E4', '#20431C'] : v >= 70 ? ['#F5DC96', '#5C4600'] : v >= 60 ? ['#EC9B77', '#5E1F09'] : ['#E38258', '#4A1706']
const GRID = '[grid-template-columns:90px_50px_repeat(12,minmax(0,1fr))]'

/**
 * Retention and churn (Analytics.dc.html, v.retention): cohorts by the month of first payment from the
 * nightly tenant snapshot, churn per month and the coded churn reasons. A month the snapshot does not reach
 * is blank, never a zero.
 */
export async function Retention({ d, biz, churns, canEdit, products, nf, now }: {
  d: RetentionData; biz: Business | null; churns: Churns | null; canEdit: boolean; products: Record<string, string>; nf: NumberFormat; now: Date
}) {
  const t = await getTranslations('analytics.retention')
  const format = await getFormatter()
  const date = (m: string) => new Date(`${m}-15T12:00:00Z`)
  const mon = (m: string) => format.dateTime(date(m), { month: 'short' })
  const monYear = (m: string) => format.dateTime(date(m), { month: 'short', year: '2-digit' })
  const first = snapshotMonth(d.first_snapshot ?? biz?.first_snapshot)
  const blanks = d.cohorts.some((c) => first === null || c.cohort < first)

  // churn per month: logos ÷ paying subscriptions at the month's start, revenue from the movements over the MRR the month before
  const months = monthsEnding(now, 12)
  const byMonth = new Map(d.churn_by_month.map((x) => [x.month, x]))
  const logos = new Map(months.map((m) => {
    const x = byMonth.get(m)
    return [m, x ? share(x.logos, x.paying_start) : first !== null && m >= first ? 0 : null]
  }))
  const mrrByMonth = new Map<string, number>()
  for (const r of biz?.mrr_by_product ?? []) mrrByMonth.set(r.month, (mrrByMonth.get(r.month) ?? 0) + (r.mrr ?? 0))
  const rev = biz ? revenueChurnByMonth(biz.movements, mrrByMonth, months, first) : new Map<string, number | null>()
  // both series are percentages, drawn on one scale
  const cmax = Math.max(0, ...months.map((m) => Math.max(logos.get(m) ?? 0, rev.get(m) ?? 0)))
  const rmaxReasons = Math.max(1, ...d.reasons.map((r) => r.count))

  return (
    <div className="flex flex-col gap-4">
      <div className="overflow-x-auto rounded-20 border border-line bg-surface px-6 py-5">
        <div className="mb-[14px] flex items-baseline justify-between gap-3">
          <span className="text-15 font-bold">{t('title')}</span>
          <div className="flex gap-1">
            {(['logos', 'revenue'] as const).map((m) => (
              <GoButton key={m} set={{ ret: m === 'logos' ? null : m }} on={d.mode === m} className={softPill(d.mode === m)}>{t(`modes.${m}`)}</GoButton>
            ))}
          </div>
        </div>
        {d.cohorts.length ? (
          <div className="flex min-w-[760px] flex-col gap-[3px]">
            <div className={`grid gap-[3px] text-10.5 font-bold uppercase tracking-[.06em] text-muted ${GRID}`}>
              <span>{t('cohort')}</span><span>{t('orgs')}</span>
              {Array.from({ length: 12 }, (_, i) => <span key={i} className="text-center">M{i}</span>)}
            </div>
            {d.cohorts.map((c) => (
              <div key={c.cohort} className={`grid gap-[3px] text-12 ${GRID}`}>
                <b>{monYear(c.cohort)}</b>
                <span className="text-muted">{c.size}</span>
                {Array.from({ length: 12 }, (_, k) => {
                  const cells = c.cells ?? []
                  if (k >= cells.length) return <span key={k} className="h-7" />
                  const at = addMonths(c.cohort, k)
                  const v = cells[k]
                  if (first === null || at < first || v === null || v === undefined) {
                    return <span key={k} title={t('noSnapshot')} className="flex h-7 items-center justify-center rounded-6 text-faint">—</span>
                  }
                  const [bg, ink] = heat(v)
                  return (
                    <span key={k} title={t('tip', { cohort: monYear(c.cohort), k })} className="flex h-7 items-center justify-center rounded-6 font-semibold tabular-nums" style={{ background: bg, color: ink }}>
                      {Math.round(v)}
                    </span>
                  )
                })}
              </div>
            ))}
          </div>
        ) : <Empty>{t('empty')}</Empty>}
        {d.cohorts.length && blanks ? (
          <div className="mt-[10px] text-11.5 text-faint">{first ? t('note', { month: format.dateTime(date(first), { month: 'long', year: 'numeric' }) }) : t('noteNone')}</div>
        ) : null}
      </div>

      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={cardChart}>
          <div className={`${title} mb-3`}>{t('churn.title')}</div>
          {cmax > 0 ? (
            <>
              <div className="flex h-[130px] items-end gap-2">
                {months.map((m) => {
                  const l = logos.get(m) ?? null
                  const r = rev.get(m) ?? null
                  return (
                    <div key={m} className="flex h-full flex-1 items-end gap-[2px]">
                      <div title={l === null ? t('churn.tipNone', { month: mon(m) }) : t('churn.tipLogo', { month: mon(m), pct: percent(l, nf), count: byMonth.get(m)?.logos ?? 0 })} className="flex-1 rounded-t-4 bg-coral-light" style={{ height: `${l !== null ? (l / cmax) * 100 : 0}%` }} />
                      <div title={r === null ? t('churn.tipNone', { month: mon(m) }) : t('churn.tipRevenue', { month: mon(m), pct: percent(r, nf) })} className="flex-1 rounded-t-4 bg-alert" style={{ height: `${r !== null ? (r / cmax) * 100 : 0}%` }} />
                    </div>
                  )
                })}
              </div>
              <div className="mt-1 flex gap-2">{months.map((m) => <span key={m} className="flex-1 text-center text-10.5 text-faint">{mon(m)}</span>)}</div>
              <div className="mt-[10px] flex gap-[14px] text-11.5 text-muted">
                <span className="flex items-center gap-[6px]"><Swatch color="#EC9B77" />{t('churn.logo')}</span>
                <span className="flex items-center gap-[6px]"><Swatch color="#D4633A" />{t('churn.revenue')}</span>
              </div>
            </>
          ) : <Empty>{t('churn.empty')}</Empty>}
        </div>

        <div className={cardChart}>
          <div className={`${title} mb-3`}>{t('reasons.title')}</div>
          {d.reasons.length ? d.reasons.map((r) => (
            <div key={r.code} className="grid items-center gap-2 py-[5px] text-12.5 [grid-template-columns:minmax(0,1fr)_140px_30px]">
              <span>{t.has(`reasons.codes.${r.code}`) ? t(`reasons.codes.${r.code}`) : r.code}</span>
              <span className="block h-2 overflow-hidden rounded-999 bg-tile"><span className="block h-full bg-alert" style={{ width: `${(r.count / rmaxReasons) * 100}%` }} /></span>
              <b className="text-right">{formatNumber(r.count, nf)}</b>
            </div>
          )) : <Empty>{t('reasons.empty')}</Empty>}
        </div>
      </div>

      {churns ? <ChurnList churns={churns} canEdit={canEdit} products={products} nf={nf} /> : null}
    </div>
  )
}
