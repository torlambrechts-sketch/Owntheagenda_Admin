'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import type { CatalogItem } from '@/lib/data/deals'
import { fetchCatalog } from '../actions'
import type { Rights } from './shared'

const GRID = '[grid-template-columns:minmax(0,1.6fr)_110px_80px_100px_90px_90px_70px_110px_minmax(0,1fr)]'

/** The billing column: a recurring item by its frequency, otherwise one-off or installments. */
export const billingKey = (b: Pick<CatalogItem, 'billing' | 'billing_frequency'>) =>
  b.billing === 'recurring' ? (b.billing_frequency ?? 'monthly') : b.billing

/** The product catalog (Deals.dc.html v.products). Only prices that exist in catalog_prices are shown. */
export function ProductsView({ rights, nf, rev, onAdd }: { rights: Rights; nf: NumberFormat; rev: number; onAdd: () => void }) {
  const t = useTranslations('deals.products')
  const tb = useTranslations('deals.billing')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [catalog, setCatalog] = useState<CatalogItem[] | null>(null)

  useEffect(() => {
    void fetchCatalog().then((r) => (r.ok ? setCatalog(r.catalog) : flash(te(r.code))))
  }, [rev, flash, te])

  const price = (p: CatalogItem, cur: 'NOK' | 'EUR' | 'SEK') => {
    const v = p.prices[cur]
    if (v === undefined) return '—'
    return cur === 'NOK' ? money(v, nf) : cur === 'EUR' ? `€ ${formatNumber(v, nf, Number.isInteger(v) ? 0 : 2)}` : `${formatNumber(v, nf, Number.isInteger(v) ? 0 : 2)} SEK`
  }

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-[14px]">
        <b className="text-15">{t('title')}</b>
        <div className="flex items-center gap-2">
          <span className="text-12 text-muted">{t('currency')}</span>
          {rights.add ? (
            <button type="button" onClick={onAdd} className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold">{t('add')}</button>
          ) : null}
        </div>
      </div>
      <div className="overflow-x-auto">
        <div className="min-w-[980px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${GRID}`}>
            {(['product', 'code', 'unit', 'nok', 'eur', 'sek', 'tax', 'billing', 'variations'] as const).map((k) => <span key={k}>{t(`cols.${k}`)}</span>)}
          </div>
          {(catalog ?? []).map((p) => (
            <div key={p.id} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 ${GRID}`}>
              <span className="flex items-center gap-2">
                <span className="h-[10px] w-[10px] flex-none rounded-3 border border-[rgba(25,21,16,.15)]" style={{ background: p.color ?? '#F2EAD6' }} />
                <b>{p.name}</b>
              </span>
              <span className="text-11.5 [font-family:ui-monospace,Menlo,monospace]">{p.code ?? '—'}</span>
              <span>{p.unit ?? '—'}</span>
              <b>{price(p, 'NOK')}</b>
              <span>{price(p, 'EUR')}</span>
              <span>{price(p, 'SEK')}</span>
              <span>{percent(p.tax_rate, nf)}</span>
              <span>{tb(billingKey(p))}</span>
              <span className="text-12 text-muted">{p.description ?? '—'}</span>
            </div>
          ))}
          {catalog && catalog.length === 0 ? <div className="p-6 text-center text-13 text-muted">{t('empty')}</div> : null}
        </div>
      </div>
    </div>
  )
}
