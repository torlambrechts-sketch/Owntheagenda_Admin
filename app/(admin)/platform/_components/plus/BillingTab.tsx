'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { formatNumber, money, type NumberFormat } from '@/lib/format'
import type { Billing } from '@/lib/data/platform-plus'
import { p } from './kit'

const STATUSES = ['trial', 'active', 'past_due', 'suspended', 'cancelled', 'expired', 'free']

/**
 * Billing portal (PlatformPlus.dc.html, v.billing): what is real of it. One account at a time (an account picker, D-41): its
 * current plan as the product's catalogue names it, how it is billed, and its billing tickets; beside it the billing tickets of
 * the last 30 days. Orgpuls invoices by e-mail or EHF outside Sentral and holds no card: no invoice list, card payment,
 * refunds, failed-payment recovery or dunning is drawn (V-V3P deviations), and the plan buttons show the catalogue without
 * pretending to change it (there is no plan command yet).
 */
export function BillingTab({ billing, product, nf }: { billing: Billing; product: string; nf: NumberFormat }) {
  const t = useTranslations('platformPlus.billing')
  const format = useFormatter()
  const [id, setId] = useState(billing.accounts[0]?.id ?? '')
  const a = billing.accounts.find((x) => x.id === id) ?? null
  const status = a?.status && STATUSES.includes(a.status) ? a.status : null
  const openAccounts = billing.accounts.filter((x) => (x.open_tickets ?? 0) > 0)

  return (
    <div className={p.grid2}>
      <div className="overflow-hidden rounded-20 border border-ink bg-surface">
        <div className="flex justify-between gap-[10px] border-b border-line bg-canvas px-[18px] py-[14px]">
          <span className="flex min-w-0 flex-col">
            <b className={p.title}>{t('title', { name: a?.name ?? '—' })}</b>
            <span className={p.sub}>{t('sub', { product })}</span>
          </span>
          {status ? <span className="self-start whitespace-nowrap rounded-999 bg-highlight px-[10px] py-[3px] text-11 font-bold">{t(`status.${status}`)}</span> : null}
        </div>
        <div className="flex flex-col gap-[10px] px-[18px] py-[14px]">
          {billing.accounts.length === 0 ? <span className="text-12.5 text-muted">{t('none', { product })}</span> : (
            <label className="flex items-center justify-between gap-[10px] text-13">
              {t('account')}
              <select value={id} onChange={(e) => setId(e.target.value)} className="h-[30px] min-w-0 max-w-[60%] rounded-8 border border-line bg-canvas text-12 text-ink">
                {billing.accounts.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
              </select>
            </label>
          )}
          {a ? (
            <>
              <div className="flex justify-between gap-[10px] text-13">
                <span>{t('plan')}</span>
                <b className="text-right">
                  {a.band && a.monthly !== null ? t('planValue', { band: a.band, price: money(a.monthly, nf) })
                    : a.plan ? t('planUnknown', { plan: a.plan }) : '—'}
                </b>
              </div>
              <div className="flex justify-between gap-[10px] text-13">
                <span>{t('interval')}</span>
                <b>{a.interval === 'month' || a.interval === 'year' ? t(`intervalValue.${a.interval}`) : '—'}</b>
              </div>
              {status === 'trial' && a.trial_ends_at ? (
                <div className="flex justify-between gap-[10px] text-13">
                  <span>{t('trialEnds')}</span>
                  <b>{format.dateTime(new Date(a.trial_ends_at), { day: 'numeric', month: 'short', year: 'numeric' })}</b>
                </div>
              ) : null}
            </>
          ) : null}
          {billing.plans.length ? (
            <div className="flex gap-[6px]">
              {billing.plans.map((pl) => {
                const on = a?.band === pl.band
                return (
                  <button
                    key={pl.band}
                    type="button"
                    disabled
                    aria-pressed={on}
                    title={t('change', { product })}
                    className={`flex-1 cursor-default rounded-11 border px-[6px] py-[9px] text-12 text-ink ${on ? 'border-ink bg-highlight font-bold' : 'border-line bg-transparent font-medium'}`}
                  >
                    {pl.band}
                    <div className="text-11 font-medium text-muted">{money(pl.monthly, nf)}</div>
                  </button>
                )
              })}
            </div>
          ) : <span className="text-12.5 text-muted">{t('noPlans', { product })}</span>}
          <span className="text-11.5 text-muted">{t('change', { product })}</span>
          {a ? (
            <span className="text-11.5 text-muted">
              {billing.tickets && a.open_tickets !== null && a.tickets_30d !== null
                ? t('tickets', { open: formatNumber(a.open_tickets, nf), recent: formatNumber(a.tickets_30d, nf) })
                : t('noTicketsRight')}
            </span>
          ) : null}
        </div>
      </div>
      <div className={p.card}>
        <div className={`${p.head}`}>
          <b className={p.title}>{t('summary.title')}</b>
        </div>
        {billing.tickets && billing.tickets_30d !== null ? (
          <>
            <div className="flex items-baseline gap-[10px] px-[18px] py-[14px]">
              <span className="font-serif text-30 font-semibold text-link">{formatNumber(billing.tickets_30d, nf)}</span>
              <span className="text-12.5 text-muted">{t('summary.prev', { count: formatNumber(billing.tickets_prev_30d ?? 0, nf) })}</span>
            </div>
            {openAccounts.length === 0 ? <div className={`${p.empty} border-t`}>{t('summary.empty')}</div> : null}
            {openAccounts.map((x) => (
              <div key={x.id} className="flex justify-between gap-[10px] border-t border-line px-[18px] py-[10px] text-12.5">
                <b>{x.name}</b>
                <span className="text-muted">{t('summary.open', { count: x.open_tickets ?? 0 })}</span>
              </div>
            ))}
          </>
        ) : <div className={p.empty}>{t('noTicketsRight')}</div>}
      </div>
    </div>
  )
}
