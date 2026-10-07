import { getFormatter, getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { SimplePlan } from '@/lib/data/simple-platform'

/**
 * The annual discount the catalogue implies: whole months free when the annual price is a whole number of monthly prices
 * short of twelve, else the percentage off; null when a band has no annual price.
 */
function discountOf(p: SimplePlan): { months: number } | { percent: number } | 'none' | null {
  if (p.annual_price === null || p.monthly_price <= 0) return null
  const months = 12 - p.annual_price / p.monthly_price
  if (Math.abs(months) < 1e-9) return 'none'
  if (Math.abs(months - Math.round(months)) < 1e-9) return { months: Math.round(months) }
  return { percent: Math.round((1 - p.annual_price / (12 * p.monthly_price)) * 1000) / 10 }
}

/**
 * Plans and prices (SimplePlatform.dc.html, v.plans), read-only: the product's plan catalogue (plan_versions) with the live
 * accounts per band. Orgpuls owns checkout and Sentral has no command to change a price, the trial or the discount (D-40), so
 * nothing here pretends to save (V-SPL-07). The design's plan names and «included» lines have no source (V-SPL-08).
 */
export async function PlansTab({ plans, name, nf }: { plans: SimplePlan[]; name: string; nf: NumberFormat }) {
  const t = await getTranslations('simplePlatform.plans')
  const format = await getFormatter()
  const discounts = plans.map(discountOf)
  const first = JSON.stringify(discounts[0] ?? null)
  const same = discounts.length > 0 && discounts.every((d) => JSON.stringify(d) === first)
  const d = same ? discounts[0] ?? null : null
  const discount = !plans.length ? '—'
    : !same ? t('discountVaries')
    : d === null ? '—'
    : d === 'none' ? t('discountNone')
    : 'months' in d ? t('monthsFree', { count: d.months })
    : t('percentOff', { percent: formatNumber(d.percent, nf, Number.isInteger(d.percent) ? 0 : 1) })
  const box = 'flex h-[34px] items-center rounded-9 border border-line bg-canvas px-2 text-13 font-bold'
  const since = plans.length ? plans.reduce((a, b) => (a.valid_from > b.valid_from ? a : b)).valid_from : null

  return (
    <div className="flex flex-col gap-[14px]">
      {plans.length === 0 ? (
        <div className="rounded-20 border border-line bg-surface px-[18px] py-[14px] text-12.5 text-muted">{t('none', { name })}</div>
      ) : (
        <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,220px),1fr))]">
          {plans.map((p) => (
            <div key={p.band_label} className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface p-[18px]">
              <div className="flex items-baseline justify-between gap-2">
                <b className="text-15">{t('band', { band: p.band_label })}</b>
                <span className="text-11.5 text-muted">{p.accounts === null ? '—' : t('accounts', { count: p.accounts })}</span>
              </div>
              <span className="text-12 text-muted">{p.annual_price === null ? t('noAnnual') : t('annual', { price: formatNumber(p.annual_price, nf) })}</span>
              <div className="flex items-center gap-[6px] text-12 text-muted">
                <span className="flex h-[38px] w-[90px] items-center rounded-10 border border-line bg-canvas px-[10px] font-serif text-20 font-semibold text-ink">
                  {formatNumber(p.monthly_price, nf)}
                </span>
                {t('perMonth')}
              </div>
            </div>
          ))}
        </div>
      )}
      <div className="flex flex-wrap items-center gap-[14px] rounded-20 border border-line bg-surface px-[18px] py-[14px]">
        <span className="flex items-center gap-2 text-13">{t('trial')}<span className={box}>—</span>{t('days')}</span>
        <span className="flex items-center gap-2 text-13">{t('discount')}<span className={box}>{discount}</span></span>
        <span className="flex-1" />
        <button
          type="button"
          disabled
          title={t('readOnly')}
          className="h-9 flex-none cursor-default whitespace-nowrap rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold opacity-60"
        >
          {t('save')}
        </button>
      </div>
      <span className="text-12 text-muted">
        {t('readOnly')}
        {since ? ` ${t('since', { date: format.dateTime(new Date(since), { day: 'numeric', month: 'long', year: 'numeric' }) })}` : ''}
      </span>
    </div>
  )
}
