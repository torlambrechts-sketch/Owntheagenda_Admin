'use client'

import { useFormatter, useTranslations } from 'next-intl'
import { formatNumber, thousands, type NumberFormat } from '@/lib/format'
import type { DealForecast, ProductForecast } from '@/lib/data/insights'
import type { Rights } from './shared'

type Res<T> = { ok: true; data: T } | { ok: false; code: string }

/**
 * Forecast (design: v.forecast). Deal revenue: open deals by expected close month for the next four
 * months, best case and weighted by stage probability (forecast_deals). Product revenue: subscription MRR
 * carried forward with recurring and instalment lines of won deals (forecast_products), twelve months.
 */
export function Forecast({ deals, products, rights, nf }: { deals: Res<DealForecast>; products: Res<ProductForecast>; rights: Rights; nf: NumberFormat }) {
  const t = useTranslations('insights')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const month = (ym: string) => format.dateTime(new Date(`${ym}-15T12:00:00Z`), { month: 'short' })
  const refused = (code: string) => <div className="py-6 text-center text-12.5 text-muted">{code === 'forbidden' ? t('noAccess') : te(code as 'failed')}</div>
  const empty = (text: string) => <div className="flex h-[190px] items-center justify-center rounded-14 border border-dashed border-line-strong px-4 text-center text-12.5 text-muted">{text}</div>

  let dealBody: React.ReactNode
  if (!rights.see) dealBody = refused('forbidden')
  else if (!deals.ok) dealBody = refused(deals.code)
  else if (deals.data.months.every((m) => m.count === 0)) dealBody = empty(t('forecast.noDeals'))
  else {
    const fmax = Math.max(...deals.data.months.map((f) => f.best), 1)
    dealBody = (
      <div className="flex h-[190px] items-end gap-[10px]">
        {deals.data.months.map((f) => (
          <div key={f.month} title={t('forecast.dealTip', { month: month(f.month), best: thousands(f.best, nf), weighted: thousands(f.weighted, nf), count: f.count })}
            className="flex h-full flex-1 flex-col items-center justify-end gap-1">
            <b className="text-11">{thousands(f.weighted, nf)}</b>
            <div className="flex w-full flex-col justify-end overflow-hidden rounded-[7px_7px_0_0] border border-dashed border-line-strong bg-tile" style={{ height: `${(f.best / fmax) * 90 + 4}%` }}>
              <div className="bg-primary" style={{ height: `${f.best ? (f.weighted / f.best) * 100 : 0}%` }} />
            </div>
            <span className="text-11 text-muted">{month(f.month)}</span>
          </div>
        ))}
      </div>
    )
  }

  let prodBody: React.ReactNode
  if (!rights.global) prodBody = refused('forbidden')
  else if (!products.ok) prodBody = refused(products.code)
  else {
    const rows = products.data.months.map((m) => ({ m: m.month, rec: m.subscriptions + m.recurring, inst: m.installments }))
    const max = Math.max(...rows.map((r) => r.rec + r.inst), 0)
    prodBody = max === 0 ? empty(t('forecast.noProducts')) : (
      <>
        <div className="flex h-[190px] items-end gap-[6px]">
          {rows.map((r) => (
            <div key={r.m} title={t('forecast.prodTip', { month: month(r.m), rec: formatNumber(r.rec, nf), inst: formatNumber(r.inst, nf) })} className="flex h-full flex-1 flex-col justify-end">
              <div className="bg-lilac" style={{ height: `${(r.inst / max) * 90}%` }} />
              <div className="rounded-[5px_5px_0_0] bg-sage" style={{ height: `${(r.rec / max) * 90}%` }} />
            </div>
          ))}
        </div>
        <div className="mt-1 flex gap-[6px]">
          {rows.map((r) => <span key={r.m} className="flex-1 text-center text-10.5 text-faint">{month(r.m)}</span>)}
        </div>
      </>
    )
  }

  return (
    <div className="grid gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
      <div className="rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('forecast.deal')}</b>
        <div className="mb-3 text-12 text-muted">{t('forecast.dealSub')}{rights.others ? '' : ` · ${t('forecast.ownOnly')}`}</div>
        {dealBody}
        <div className="mt-[10px] flex flex-wrap gap-[14px] text-11.5 text-muted">
          <span className="flex items-center gap-[6px]"><span className="h-[10px] w-[10px] rounded-3 bg-primary" />{t('forecast.weighted')}</span>
          <span className="flex items-center gap-[6px]"><span className="h-[10px] w-[10px] rounded-3 border border-dashed border-line-strong" />{t('forecast.best')}</span>
        </div>
        {deals.ok && deals.data.undated > 0 ? <div className="mt-2 text-11.5 text-muted">{t('forecast.undated', { count: deals.data.undated })}</div> : null}
        {deals.ok && deals.data.excluded_currency ? <div className="mt-1 text-11.5 text-muted">{t('forecast.excludedDeals', { count: deals.data.excluded_currency })}</div> : null}
      </div>
      <div className="rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('forecast.product')}</b>
        <div className="mb-3 text-12 text-muted">{t('forecast.productSub')}</div>
        {prodBody}
        <div className="mt-[10px] flex flex-wrap gap-[14px] text-11.5 text-muted">
          <span className="flex items-center gap-[6px]"><span className="h-[10px] w-[10px] rounded-3 bg-sage" />{t('forecast.recurring')}</span>
          <span className="flex items-center gap-[6px]"><span className="h-[10px] w-[10px] rounded-3 bg-lilac" />{t('forecast.installments')}</span>
        </div>
        {products.ok && products.data.excluded_currency ? <div className="mt-2 text-11.5 text-muted">{t('forecast.excludedSubs', { count: products.data.excluded_currency })}</div> : null}
      </div>
    </div>
  )
}
