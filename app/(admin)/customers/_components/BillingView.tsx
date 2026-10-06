import Link from 'next/link'
import { getTranslations } from 'next-intl/server'
import type { Shell } from '@/lib/shell'
import { money } from '@/lib/format'
import { loadBilling } from '@/lib/data/customers'
import { LIFECYCLE_COLOR, LIFECYCLE_ORDER } from './tones'

const head = 'flex justify-between gap-3 border-b border-line px-[18px] py-[14px]'
const tableCard = 'overflow-hidden rounded-20 border border-line bg-surface'
const empty = 'px-[18px] py-[22px] text-center text-13 text-muted'

/** Customers › Subscriptions and billing (billing_overview): what Orgpuls reports, nothing more. */
export async function BillingView({ product, shell }: { product: string; shell: Shell }) {
  const t = await getTranslations('customers')
  const nf = shell.me.number_format
  const r = await loadBilling(product)
  if (!r.ok) {
    return <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center text-13 text-muted">{r.code === 'forbidden' ? t('detail.tabForbidden') : t('detail.tabFailed')}</div>
  }
  const b = r.data
  const prodName = (k: string) => shell.products.find((p) => p.key === k)?.name ?? k
  const pastDueOrgs = new Set(b.failed.filter((f) => f.state === 'past_due').map((f) => f.organization_id)).size
  const kpis = [
    { n: t('bill.kpi.mrr'), v: b.priced ? money(b.mrr, nf) : '—', s: t('bill.kpi.mrrSub') },
    { n: t('bill.kpi.pastDue'), v: money(b.past_due_mrr, nf), s: t('bill.kpi.pastDueSub', { n: pastDueOrgs }), danger: true },
    { n: t('bill.kpi.ehf'), v: String(b.ehf), s: t('bill.kpi.ehfSub') },
  ]
  const total = Object.values(b.lifecycle).reduce((a, x) => a + x, 0)
  const life = [...LIFECYCLE_ORDER, ...Object.keys(b.lifecycle).filter((k) => !LIFECYCLE_ORDER.includes(k))]
    .filter((k) => b.lifecycle[k] !== undefined)
    .map((k) => ({ k, n: t.has(`status.${k}`) ? t(`status.${k}`) : k, v: b.lifecycle[k] ?? 0, c: LIFECYCLE_COLOR[k] ?? '#C4BCA8' }))
  const notYet = t('notYet')

  return (
    <div className="flex flex-col gap-4">
      <div className="grid gap-[13px] [grid-template-columns:repeat(auto-fit,minmax(180px,1fr))]">
        {kpis.map((k) => (
          <div key={k.n} className="rounded-20 border border-line bg-surface px-[18px] py-4">
            <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{k.n}</div>
            <div className={`mt-[6px] font-serif text-26 font-semibold ${k.danger ? 'text-danger' : ''}`}>{k.v}</div>
            <div className="text-12 text-muted">{k.s}</div>
          </div>
        ))}
      </div>

      <div className="rounded-20 border border-line bg-surface px-[22px] py-[18px]">
        <div className="mb-3 text-15 font-bold">{t('bill.lifecycle')}</div>
        {total ? (
          <>
            <div className="flex h-[30px] overflow-hidden rounded-9 border border-line">
              {life.map((l) => <div key={l.k} title={l.n} className="border-r border-[rgba(25,21,16,.1)]" style={{ width: `${(l.v / total) * 100}%`, background: l.c }} />)}
            </div>
            <div className="mt-[10px] flex flex-wrap gap-4">
              {life.map((l) => (
                <span key={l.k} className="flex items-center gap-[6px] text-12">
                  <span className="h-[10px] w-[10px] rounded-3 border border-[rgba(25,21,16,.15)]" style={{ background: l.c }} />
                  {l.n} <b>{l.v}</b>
                </span>
              ))}
            </div>
            <div className="mt-[10px] text-11.5 text-faint">{t('bill.lifecycleNote')}</div>
          </>
        ) : (
          <div className="text-13 text-muted">{t('bill.noSubscriptions')}</div>
        )}
      </div>

      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={tableCard}>
          <div className={head}><span className="text-15 font-bold">{t('bill.failed')}</span></div>
          {b.failed.map((f, i) => (
            <div key={i} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-13 [grid-template-columns:minmax(0,1fr)_100px_110px_70px]">
              <span className="flex flex-col">
                <Link href={`/customers?org=${f.organization_id}` as never} className="font-bold text-ink hover:text-ink">{f.organization}</Link>
                <span className="text-11.5 text-muted">{prodName(f.product)}</span>
              </span>
              <b>{f.amount !== null ? money(f.amount, nf) : '—'}</b>
              <span className="text-12 text-danger">{t.has(`status.${f.state}`) ? t(`status.${f.state}`) : f.state}</span>
              <button type="button" disabled title={notYet} className="h-7 cursor-default rounded-9 border border-ink bg-primary text-12 font-bold opacity-55">{t('bill.retry')}</button>
            </div>
          ))}
          {b.failed.length === 0 ? <div className={empty}>{t('bill.noFailed')}</div> : null}
        </div>

        <div className={tableCard}>
          <div className={head}><span className="text-15 font-bold">{t('bill.bands')}</span><span className="text-12 text-muted">{t('bill.bandsSub')}</span></div>
          <div className={empty}>{t('bill.noBands')}</div>
        </div>

        <div className={tableCard}>
          <div className={`${head} items-center`}><span className="text-15 font-bold">{t('bill.plans')}</span><span className="text-12 text-muted">{t('bill.plansSub')}</span></div>
          <div className="grid gap-[10px] border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-label text-muted [grid-template-columns:90px_90px_100px_minmax(0,1fr)_80px]">
            <span>{t('bill.cols.band')}</span><span>{t('bill.cols.monthly')}</span><span>{t('bill.cols.annual')}</span><span>{t('bill.cols.product')}</span><span>{t('bill.cols.version')}</span>
          </div>
          {b.plans.map((p) => (
            <div key={p.id} className="grid gap-[10px] border-b border-line px-[18px] py-[10px] text-13 [grid-template-columns:90px_90px_100px_minmax(0,1fr)_80px]">
              <b>{p.band_label}</b>
              <span>{money(p.monthly_price, nf)}</span>
              <span>{p.annual_price !== null ? money(p.annual_price, nf) : '—'}</span>
              <span className="text-12 text-muted">{prodName(p.product)}</span>
              <span className="text-muted">{t('bill.version', { v: p.version })}</span>
            </div>
          ))}
          {b.plans.length === 0 ? <div className={empty}>{t('bill.noPlans')}</div> : null}
          <div className="px-[18px] py-[10px] text-12 text-muted">{t('bill.terms')}</div>
        </div>

        <div className={tableCard}>
          <div className={head}><span className="text-15 font-bold">{t('bill.coupons')}</span></div>
          {b.coupons.map((c) => (
            <div key={c.code} className="grid gap-[10px] border-b border-line px-[18px] py-[10px] text-13 [grid-template-columns:130px_minmax(0,1fr)_100px]">
              <b className="text-12 [font-family:ui-monospace,Menlo,monospace]">{c.code}</b>
              <span className="text-muted">{c.description ?? '—'}</span>
              <span className="text-right">—</span>
            </div>
          ))}
          {b.coupons.length === 0 ? <div className={empty}>{t('bill.noCoupons')}</div> : null}
          <div className="flex gap-2 px-[18px] py-3">
            <button type="button" disabled title={notYet} className="h-8 cursor-default rounded-9 border border-ink bg-surface px-[13px] text-12.5 font-bold opacity-55">{t('bill.exportAccounting')}</button>
            <button type="button" disabled title={notYet} className="h-8 cursor-default rounded-9 border border-line bg-transparent px-[13px] text-12.5 font-semibold opacity-55">{t('bill.newCoupon')}</button>
          </div>
        </div>
      </div>
    </div>
  )
}
