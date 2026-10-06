import Link from 'next/link'
import { getTranslations } from 'next-intl/server'
import type { Health as HealthData } from '@/lib/data/analytics'
import { SIGNALS, daysUntil, weightShares } from '@/lib/data/analytics-calc'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { HealthWeights } from './HealthWeights'
import { Empty, cardChart, cardTable, title } from './kit'

const BUCKETS = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90]
const tone = (b: number) => (b >= 70 ? '#5C9A55' : b >= 40 ? '#E0A21F' : '#D4633A')

/**
 * Health score (Analytics.dc.html, v.health) on analytics_health: the latest score per application, the
 * active model's weights, and paying applications below 40 whose renewal falls inside the renewal window
 * (setting renewal_window). The «why» is the model's own factors, largest loss first.
 */
export async function Health({ d, products, canEdit, nf, now }: {
  d: HealthData; products: Record<string, string>; canEdit: boolean; nf: NumberFormat; now: Date
}) {
  const t = await getTranslations('analytics.health')
  const counts = new Map(d.distribution.map((x) => [x.bucket, x.count]))
  const hist = BUCKETS.map((b) => ({ b, v: counts.get(b) ?? 0 }))
  const hmax = Math.max(1, ...hist.map((h) => h.v))
  const signal = (k: string) => (t.has(`signals.${k}`) ? t(`signals.${k}`) : k)
  const shares = weightShares(d.model?.weights ?? {}, SIGNALS).map((w) => ({ key: w.key, label: signal(w.key), pct: percent(Math.round(w.pct), nf) }))

  return (
    <div className="grid items-start gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={cardChart}>
        <div className={`${title} mb-3`}>{t('dist.title')}</div>
        {d.scored > 0 ? (
          <>
            <div className="flex h-[150px] items-end gap-[6px]">
              {hist.map((h) => (
                <div key={h.b} className="flex h-full flex-1 flex-col items-center justify-end gap-1" title={t('dist.tip', { count: h.v, from: h.b, to: h.b + 9 })}>
                  <b className="text-11">{h.v}</b>
                  <div className="w-full rounded-t-5" style={{ height: `${(h.v / hmax) * 85 + 2}%`, background: tone(h.b) }} />
                </div>
              ))}
            </div>
            <div className="mt-1 flex gap-[6px]">{hist.map((h) => <span key={h.b} className="flex-1 text-center text-10.5 text-faint">{h.b}</span>)}</div>
          </>
        ) : <Empty>{t('dist.empty')}</Empty>}
        <HealthWeights weights={d.model?.weights ?? {}} version={d.model?.version ?? null} canEdit={canEdit && d.model !== null} shares={shares} />
      </div>

      <div className={cardTable}>
        <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
          <span className={title}>{t('risk.title')}</span>
          <span className="text-12 text-muted">{t('risk.sub', { days: d.renewal_window })}</span>
        </div>
        {d.at_risk.map((r) => {
          const why = (r.factors ?? []).slice(0, 2).map((f) => t('risk.factor', { signal: signal(f.signal), points: formatNumber(f.loss, nf, Number.isInteger(f.loss) ? 0 : 1) })).join(' · ')
          return (
            <Link
              key={`${r.organization_id}-${r.product}`}
              href={`/customers?org=${r.organization_id}` as never}
              className="grid w-full cursor-pointer items-center gap-[10px] border-b border-line bg-transparent px-[18px] py-[11px] text-left text-13 text-ink [grid-template-columns:minmax(0,1fr)_46px_100px] hover:text-ink hover:no-underline"
            >
              <span className="flex min-w-0 flex-col">
                <b>{r.name}</b>
                <span className="text-11.5 text-muted">{[products[r.product] ?? r.product, why || null].filter(Boolean).join(' · ')}</span>
              </span>
              <b className="text-16 text-danger">{r.score}</b>
              <span className="text-12 text-muted">{r.renews_at ? t('risk.renews', { count: daysUntil(r.renews_at, now) }) : '—'}</span>
            </Link>
          )
        })}
        {d.at_risk.length === 0 ? <div className="px-[18px] py-6"><Empty>{d.scored ? t('risk.empty', { days: d.renewal_window }) : t('dist.empty')}</Empty></div> : null}
      </div>
    </div>
  )
}
