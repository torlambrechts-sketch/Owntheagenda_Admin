'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useEffect, useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import { recordHref } from '@/lib/records-href'
import type { Definition, DrillRow } from '@/lib/data/insights-shared'
import { download, toXlsx } from '../../deals/_components/xlsx'
import { drillAction, exportAction } from '../actions'

export type DrillTarget = { def: Definition; segment: { key?: string | null; segment?: string | null }; title: string }

/**
 * The drill-down (design: drill): the rows behind a segment, re-run from the report's own definition with
 * the segment as one more filter (INS-08). Export rows writes the same rows as XLSX through report_export,
 * which checks the export right and records it.
 */
export function DrillModal({ target, onClose, nf, canExport }: { target: DrillTarget; onClose: () => void; nf: NumberFormat; canExport: boolean }) {
  const t = useTranslations('insights')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const [rows, setRows] = useState<DrillRow[] | null>(null)
  const [busy, setBusy] = useState(false)
  const closeRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    let live = true
    setRows(null)
    void drillAction({ def: target.def, segment: target.segment }).then((r) => {
      if (!live) return
      if (r.ok) setRows(r.rows)
      else { flash(te(r.code)); setRows([]) }
    })
    return () => { live = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- the rows depend on the target alone
  }, [target])

  const closeLatest = useRef(onClose)
  closeLatest.current = onClose
  useEffect(() => {
    const back = document.activeElement as HTMLElement | null
    closeRef.current?.focus()
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') closeLatest.current() }
    window.addEventListener('keydown', key)
    return () => { window.removeEventListener('keydown', key); back?.focus?.() }
  }, [])

  const exportRows = async () => {
    setBusy(true)
    const r = await exportAction({ def: target.def, segment: target.segment })
    setBusy(false)
    if (!r.ok) { flash(te(r.code)); return }
    const head = [t('drill.cols.title'), t('drill.cols.owner'), t('drill.cols.value'), t('drill.cols.currency'), t('drill.cols.created')]
    const body = r.rows.map((x) => [x.title ?? '', x.owner ?? '', x.value ?? '', x.currency ?? '', x.created_at.slice(0, 10)])
    download(toXlsx([head, ...body], t('drill.sheet')), `${target.title.replace(/[\\/:*?"<>|]+/g, ' ').slice(0, 80)}.xlsx`)
    flash(t('drill.exported'))
  }

  const entity = target.def.entity
  return (
    <div onClick={onClose} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div role="dialog" aria-modal="true" aria-label={target.title} onClick={(e) => e.stopPropagation()}
        className="flex max-h-[80vh] w-[620px] max-w-full flex-col gap-[10px] overflow-auto rounded-22 bg-surface px-[22px] py-5">
        <div className="flex items-center justify-between gap-3">
          <b className="font-serif text-20">{target.title}</b>
          <span className="flex flex-none gap-[6px]">
            <button type="button" onClick={exportRows} disabled={!canExport || busy || rows === null || rows.length === 0} title={canExport ? undefined : t('drill.noExport')}
              className="h-[30px] cursor-pointer rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold disabled:cursor-default disabled:opacity-55">{t('drill.export')}</button>
            <button ref={closeRef} type="button" onClick={onClose} aria-label={t('drill.close')} className="h-[30px] w-[30px] cursor-pointer rounded-999 border border-ink bg-transparent">×</button>
          </span>
        </div>
        {rows === null ? <div className="py-2 text-12.5 text-muted">{t('loading')}</div> : null}
        {rows !== null && rows.length === 0 ? <div className="py-2 text-12.5 text-muted">{t('drill.empty')}</div> : null}
        {(rows ?? []).map((r) => (
          <div key={r.id} className="grid gap-[10px] border-b border-line py-2 text-12.5 [grid-template-columns:minmax(0,1fr)_64px_92px] sm:[grid-template-columns:minmax(0,1.6fr)_110px_110px]">
            <b className="min-w-0"><Link href={recordHref(entity, r.id) as Route} className="text-ink hover:text-ink">{r.title ?? t('none')}</Link></b>
            <span className="text-muted">{r.owner ? r.owner.split(' ')[0] : '—'}</span>
            <span className="text-right" title={format.dateTime(new Date(r.created_at), { dateStyle: 'medium' })}>{r.value !== null ? money(r.value, nf, r.currency ?? 'NOK') : '—'}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
