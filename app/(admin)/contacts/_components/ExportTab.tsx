'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { exportCsv } from '../actions'
import type { TabProps } from './ContactsScreen'
import { download, useError } from './util'

const ENTITIES = ['person', 'organization', 'lead', 'deal', 'activity', 'catalog_item'] as const
type E = (typeof ENTITIES)[number]
// the lists this screen draws; for the others «current list view» and the full set are the same rows
const HAS_VIEW: E[] = ['person', 'lead']

/** Export (Contacts.dc.html, v.export): the visible rows as CSV, recorded with export_log. */
export function ExportTab({ data, rights }: TabProps) {
  const t = useTranslations('contacts')
  const flash = useToast()
  const err = useError()
  const [entity, setEntity] = useState<E>('person')
  const [scope, setScope] = useState<'current' | 'full'>('current')
  const [busy, setBusy] = useState(false)

  async function run() {
    setBusy(true)
    const effective = HAS_VIEW.includes(entity) ? scope : 'full'
    const r = await exportCsv({ entity, scope: effective, query: data.query })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    download(`${t(`export.file.${entity}`)}-${new Date().toISOString().slice(0, 10)}.csv`, r.csv)
    flash(t('export.done', { entity: t(`export.entity.${entity}`), scope: t(`export.scopeDone.${effective}`), count: r.rows }))
  }

  return (
    <div className="flex max-w-[760px] flex-col gap-[14px] rounded-20 border border-line bg-surface px-[22px] py-5">
      <b className="text-15">{t('export.title')}</b>
      <div className="flex flex-wrap gap-[6px]">
        {ENTITIES.map((e) => (
          <button key={e} type="button" onClick={() => setEntity(e)} aria-pressed={entity === e}
            className={`cursor-pointer rounded-999 border px-[13px] py-[7px] text-12.5 ${entity === e ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
            {t(`export.entity.${e}`)}
          </button>
        ))}
      </div>
      <div className="flex self-start rounded-10 bg-tile p-[3px]">
        {(['current', 'full'] as const).map((s) => (
          <button key={s} type="button" onClick={() => setScope(s)} aria-pressed={scope === s} disabled={s === 'current' && !HAS_VIEW.includes(entity)}
            className={`cursor-pointer rounded-7 border-none px-3 py-[7px] text-12.5 disabled:cursor-default disabled:opacity-50 ${(HAS_VIEW.includes(entity) ? scope : 'full') === s ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
            {t(`export.scope.${s}`)}
          </button>
        ))}
      </div>
      <div className="text-12.5 leading-[1.55] text-ink-2">{t('export.note')}</div>
      {!HAS_VIEW.includes(entity) ? <div className="text-11.5 text-faint">{t('export.noView')}</div> : null}
      <div className="flex flex-wrap gap-2">
        <button type="button" disabled={busy || !rights.exp} onClick={run} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-4 text-13 font-bold disabled:cursor-default disabled:opacity-50">{t('export.csv')}</button>
        <button type="button" disabled={!rights.exp} onClick={() => flash(t('export.noXlsx'))} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-surface px-4 text-13 font-bold disabled:cursor-default disabled:opacity-50">{t('export.xlsx')}</button>
      </div>
      {!rights.exp ? <div className="text-11.5 text-faint">{t('export.noRight')}</div> : null}
    </div>
  )
}
