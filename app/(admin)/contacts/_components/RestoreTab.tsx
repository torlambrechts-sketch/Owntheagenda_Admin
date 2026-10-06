'use client'

import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { restoreRecord } from '../actions'
import type { TabProps } from './ContactsScreen'
import { useError, useNav } from './util'

const KNOWN = ['person', 'organization', 'lead', 'deal', 'activity', 'catalog_item', 'ticket'] as const

/** Restore (Contacts.dc.html, v.restore): records deleted in the last 30 days, restored with their links. */
export function RestoreTab({ data, rights, now }: TabProps) {
  const t = useTranslations('contacts')
  const format = useFormatter()
  const flash = useToast()
  const err = useError()
  const { refresh } = useNav()
  const rows = data.deleted ?? []
  const type = (e: string) => ((KNOWN as readonly string[]).includes(e) ? t(`restore.type.${e as (typeof KNOWN)[number]}`) : e)

  async function restore(entity: string, id: string, title: string) {
    const r = await restoreRecord({ entity, id })
    if (!r.ok) return flash(err(r.code))
    flash(t('restore.done', { name: title }))
    refresh()
  }

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-3">
          <b className="text-14">{t('restore.title')}</b>
          <span className="text-12 text-muted">{t('restore.purge')}</span>
        </div>
        <div className="overflow-x-auto">
          <div className="min-w-[640px]">
            {rows.map((r) => (
              <div key={`${r.entity}-${r.id}`} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:minmax(0,1.5fr)_100px_140px_110px_120px_90px]">
                <b className="truncate">{r.title ?? '—'}</b>
                <span>{type(r.entity)}</span>
                <span className="text-muted">{r.by ?? '—'}</span>
                <span className="text-muted">{format.relativeTime(new Date(r.deleted_at), new Date(now))}</span>
                <span className="text-muted">{r.source ? t(`restore.source.${r.source}` as 'restore.source.ui') : '—'}</span>
                {rights.del ? (
                  <button type="button" onClick={() => restore(r.entity, r.id, r.title ?? '')} className="h-7 cursor-pointer rounded-9 border border-ink bg-surface text-12 font-bold">{t('restore.restore')}</button>
                ) : <span />}
              </div>
            ))}
            {rows.length === 0 ? <div className="px-[18px] py-[30px] text-center text-13 text-muted">{t('restore.empty')}</div> : null}
          </div>
        </div>
      </div>
    </div>
  )
}
