import { getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Segment } from '@/lib/data/campaigns-shared'
import { cardTable, head } from '../v2kit'

/**
 * Marketing campaigns › Audiences (GrowthPlaybook.dc.html, v.audiences) on segments_get (0037): the CRM's lists with how
 * many people match and how many can receive email. No ad platform is connected, so nothing is synced and the platform
 * pills and match rates are left out; results by persona need a role the product does not report (V-GR2-36).
 */
export async function AudiencesView({ lists, nf, app }: { lists: Segment[]; nf: NumberFormat; app: string }) {
  const t = await getTranslations('simpleGrowth.playbook.audiences')
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('lists')}</b>
          <span className="text-12 text-muted">{t('listsNote')}</span>
        </div>
        {!lists.length ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('empty')}</p> : null}
        {lists.map((a) => (
          <div key={a.id} className="flex flex-col gap-[7px] border-b border-line px-[18px] py-[11px]">
            <div className="flex items-center justify-between gap-[10px]">
              <span className="flex min-w-0 flex-col">
                <b className="text-13 [overflow-wrap:anywhere]">{a.name}</b>
                <span className="text-11.5 text-muted">
                  {t('size', { count: a.matches, n: formatNumber(a.matches, nf), r: formatNumber(a.receivable, nf) })}
                  {' · '}{a.shared ? t('shared') : a.owner ? t('owner', { name: a.owner }) : t('private')}
                </span>
              </span>
              <span className="whitespace-nowrap rounded-999 bg-teal-soft px-[9px] py-[2px] text-11 font-bold">{t('kind')}</span>
            </div>
            {a.description ? <span className="text-12 leading-[1.45] text-muted [overflow-wrap:anywhere]">{a.description}</span> : null}
          </div>
        ))}
        <p className="m-0 px-[18px] py-[11px] text-12 text-muted">{t('noSync')}</p>
      </section>
      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('personas')}</b>
        </div>
        <p className="m-0 px-[18px] py-[14px] text-12.5 leading-[1.5] text-muted">
          {t('personasNone', { app })}
        </p>
      </section>
    </div>
  )
}
