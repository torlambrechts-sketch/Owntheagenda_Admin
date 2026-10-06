'use client'

import { useEffect, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import type { Card, Deleted } from '@/lib/data/deals'
import { archiveDeals, fetchArchive, restoreDeals } from '../actions'
import { canEditDeal, type Rights } from './shared'

const DAY = 86_400_000

/** Archive and restore (Deals.dc.html v.archive): archived deals and the 30-day trash. */
export function ArchiveView({ rights, nf, rev, refresh, stageName }: { rights: Rights; nf: NumberFormat; rev: number; refresh: () => void; stageName: Map<string, string> }) {
  const t = useTranslations('deals.archive')
  const tf = useTranslations('deals.flash')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const [data, setData] = useState<{ archived: Card[]; deleted: Card[]; by: Deleted[] } | null>(null)

  useEffect(() => {
    void fetchArchive().then((r) => {
      if (r.ok) setData({ archived: r.archived, deleted: r.deleted, by: r.by })
      else flash(te(r.code))
    })
  }, [rev, flash, te])

  const unarchive = async (d: Card) => {
    const r = await archiveDeals({ ids: [d.id], archived: false })
    if (!r.ok) return flash(te(r.code))
    flash(tf('unarchived'))
    refresh()
  }
  const restore = async (d: Card) => {
    const r = await restoreDeals({ ids: [d.id] })
    if (!r.ok) return flash(te(r.code))
    flash(tf('restored', { stage: stageName.get(d.stage_id) ?? '' }))
    refresh()
  }
  const byOf = new Map((data?.by ?? []).map((x) => [x.id, x.by]))
  const row = 'flex items-center justify-between gap-[10px] border-b border-line px-[18px] py-[10px] text-13'

  return (
    <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex justify-between border-b border-line px-[18px] py-[14px]">
          <b className="text-15">{t('archived')}</b>
          <span className="text-12 text-muted">{t('archivedSub')}</span>
        </div>
        {(data?.archived ?? []).map((d) => (
          <div key={d.id} className={row}>
            <span className="flex flex-col">
              <b>{d.title}</b>
              <span className="text-11.5 text-muted">
                {money(d.value, nf)} · {t('archivedWhen', { when: d.archived_at ? format.dateTime(new Date(d.archived_at), { day: 'numeric', month: 'short' }) : '—' })}
              </span>
            </span>
            {canEditDeal(rights, d) ? (
              <button type="button" onClick={() => void unarchive(d)} className="h-7 cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold">{t('unarchive')}</button>
            ) : null}
          </div>
        ))}
        {data && data.archived.length === 0 ? <div className="p-6 text-center text-13 text-muted">{t('noArchived')}</div> : null}
      </div>
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex justify-between border-b border-line px-[18px] py-[14px]">
          <b className="text-15">{t('deleted')}</b>
          <span className="text-12 text-muted">{t('deletedSub')}</span>
        </div>
        {(data?.deleted ?? []).map((d) => {
          const left = Math.max(0, 30 - Math.floor((Date.now() - new Date(d.deleted_at ?? d.updated_at).getTime()) / DAY))
          const by = byOf.get(d.id)
          return (
            <div key={d.id} className={row}>
              <span className="flex flex-col">
                <b>{d.title}</b>
                <span className="text-11.5 text-muted">
                  {stageName.get(d.stage_id) ?? '—'} · {by ? t('deletedBy', { by }) + ' · ' : ''}{t('daysLeft', { count: left })}
                </span>
              </span>
              {rights.del ? (
                <button type="button" onClick={() => void restore(d)} className="h-7 cursor-pointer rounded-9 border border-ink bg-primary px-[10px] text-12 font-bold">{t('restore')}</button>
              ) : null}
            </div>
          )
        })}
        {data && data.deleted.length === 0 ? <div className="p-6 text-center text-13 text-muted">{t('noDeleted')}</div> : null}
      </div>
    </div>
  )
}
