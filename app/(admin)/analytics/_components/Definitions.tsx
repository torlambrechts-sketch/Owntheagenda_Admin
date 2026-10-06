import { getTranslations } from 'next-intl/server'
import type { MetricDef } from '@/lib/data/analytics'
import { Empty, cardTable, title } from './kit'

/**
 * Metric definitions (Analytics.dc.html, v.defs) from analytics_metric_definitions: the views reports and
 * the CRM read, with the migration that defines them and its version.
 */
export async function Definitions({ defs }: { defs: MetricDef[] }) {
  const t = await getTranslations('analytics.defs')
  return (
    <div className={cardTable}>
      <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
        <span className={title}>{t('title')}</span>
        <span className="text-12 text-muted">{t('sub')}</span>
      </div>
      {defs.map((d) => (
        <div key={d.key} className="grid gap-[14px] border-b border-line px-[18px] py-3 text-13 md:[grid-template-columns:220px_minmax(0,1fr)_120px]">
          <b className="font-[ui-monospace,Menlo,monospace] text-12">{d.view}</b>
          <span className="leading-[1.5] text-ink-2">{t.has(`rows.${d.key}`) ? t(`rows.${d.key}`) : '—'}</span>
          <span className="text-12 text-muted">{t('version', { migration: d.migration, version: d.version })}</span>
        </div>
      ))}
      {defs.length === 0 ? <div className="px-[18px] py-6"><Empty>{t('empty')}</Empty></div> : null}
    </div>
  )
}
