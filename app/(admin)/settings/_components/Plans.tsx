import Link from 'next/link'
import { getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'

/**
 * Plans and usage (Settings.dc.html, v.plans): the real count of everything that could carry a limit, against
 * the limit the register sets (plan_gates: all on and unlimited by default). Nothing is sold (D-17): no plan
 * names, credits or invented usage. The design's bar for an unlimited limit is kept as it draws it.
 */
export async function Plans({ nf, perPlan, records, counts }: {
  nf: NumberFormat
  perPlan: boolean
  records: { key: string; n: number }[]
  counts: Record<'fields' | 'formula' | 'pipelines' | 'staff' | 'teams' | 'groups' | 'sets' | 'acttypes', number | null>
}) {
  const t = await getTranslations('settings')
  const rows: { n: string; v: number }[] = [
    ...records.map((r) => ({ n: t.has(`entities.${r.key}`) ? t(`entities.${r.key}`) : r.key, v: r.n })),
    ...(Object.keys(counts) as (keyof typeof counts)[]).flatMap((key) => (counts[key] === null ? [] : [{ n: t(`plans.rows.${key}`), v: counts[key]! }])),
  ]
  const lim = perPlan ? t('plans.perPlan') : t('plans.unlimited')
  return (
    <div className="flex flex-col gap-3">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex justify-between gap-3 border-b border-line px-[18px] py-3 max-md:flex-col">
          <b className="text-14">{t('plans.title')}</b>
          <span className="text-12 text-muted">{perPlan ? t('plans.subPerPlan') : t('plans.subAllOn')}</span>
        </div>
        {rows.map((r) => (
          <div key={r.n} className="grid items-center gap-3 border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:minmax(0,1.3fr)_minmax(0,1.6fr)_110px]">
            <span>{r.n}</span>
            <span className="h-2 overflow-hidden rounded-999 bg-tile">
              <span className="block h-full bg-teal-mid" style={{ width: `${Math.min(30, r.v / 15 + 4)}%` }} />
            </span>
            <span className="text-right">
              <b>{formatNumber(r.v, nf)}</b> <span className="text-muted">/ {lim}</span>
            </span>
          </div>
        ))}
        <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('plans.foot')}</div>
      </div>
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="border-b border-line px-[18px] py-3 text-14 font-bold">{t('plans.ents')}</div>
        <div className="px-[18px] py-[10px] text-12.5 text-muted">
          {t('plans.entsNone')} <Link href="/settings?sec=modules">{t('plans.entsLink')}</Link>.
        </div>
      </div>
    </div>
  )
}
