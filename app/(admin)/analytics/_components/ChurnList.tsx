'use client'

import Link from 'next/link'
import { useTransition } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Churns } from '@/lib/data/analytics'
import { money, type NumberFormat } from '@/lib/format'
import { setChurnReason } from '../actions'

const COLS = '[grid-template-columns:minmax(0,1.4fr)_110px_100px_minmax(180px,1fr)]'

/**
 * The churned subscriptions of the last twelve months (analytics_churns) with their coded reason, which
 * those with Global › Edit others set with analytics_set_churn_reason. Not drawn in the design: built in its
 * table language (D-41), because the reasons above need someone to record them.
 */
export function ChurnList({ churns, canEdit, products, nf }: { churns: Churns; canEdit: boolean; products: Record<string, string>; nf: NumberFormat }) {
  const t = useTranslations('analytics.retention')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const [pending, start] = useTransition()
  const reason = (code: string | null) => (code ? (t.has(`reasons.codes.${code}`) ? t(`reasons.codes.${code}`) : code) : t('reasons.codes.unknown'))

  const save = (c: Churns['churns'][number], code: string) => start(async () => {
    const r = await setChurnReason({ product: c.product, tenant: c.tenant_id, churnedAt: c.churned_at, code })
    flash(r.ok ? t('list.saved') : te(r.code))
  })

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
        <span className="text-15 font-bold">{t('list.title')}</span>
        <span className="text-12 text-muted">{t('list.sub')}</span>
      </div>
      <div className="overflow-x-auto">
        <div className="min-w-[620px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${COLS}`}>
            <span>{t('list.cols.org')}</span><span>{t('list.cols.date')}</span><span>{t('list.cols.lost')}</span><span>{t('list.cols.reason')}</span>
          </div>
          {churns.churns.map((c) => (
            <div key={`${c.product}-${c.tenant_id}-${c.churned_at}`} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-13 tabular-nums ${COLS}`}>
              <span className="flex min-w-0 flex-col">
                {c.organization_id
                  ? <Link href={`/customers?org=${c.organization_id}` as never} className="truncate font-bold text-ink hover:text-ink">{c.organization ?? c.tenant_id}</Link>
                  : <b className="truncate">{c.organization ?? c.tenant_id}</b>}
                <span className="text-11.5 text-muted">{[products[c.product] ?? c.product, c.payment_failure ? t('list.paymentFailure') : null].filter(Boolean).join(' · ')}</span>
              </span>
              <span className="text-muted">{format.dateTime(new Date(c.churned_at), { day: 'numeric', month: 'short', year: 'numeric' })}</span>
              <b>{money(c.mrr_lost, nf, c.currency ?? 'NOK')}</b>
              {canEdit ? (
                <select
                  value={c.reason ?? ''}
                  disabled={pending}
                  aria-label={t('list.reasonFor', { org: c.organization ?? c.tenant_id })}
                  onChange={(e) => save(c, e.target.value)}
                  className="h-[30px] rounded-8 border border-line bg-canvas px-1 text-12"
                >
                  {c.reason ? null : <option value="" disabled>{reason(null)}</option>}
                  {churns.reasons.map((code) => <option key={code} value={code}>{reason(code)}</option>)}
                </select>
              ) : <span className="text-12.5">{reason(c.reason)}</span>}
            </div>
          ))}
          {churns.churns.length === 0 ? <div className="px-[18px] py-5 text-12.5 text-muted">{t('list.empty')}</div> : null}
        </div>
      </div>
    </div>
  )
}
