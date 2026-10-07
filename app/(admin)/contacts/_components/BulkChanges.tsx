'use client'

import { useCallback, useEffect, useState, useTransition } from 'react'
import { useFormatter, useNow, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { BulkChange } from '@/lib/data/platform-bulk'
import { fetchBulkChanges, revertBulk } from '../bulk-actions'

/**
 * «Bulk changes — revertable» (Contacts.dc.html, v.restore; Contacts R-6). The changes come from the bulk-change log that
 * every rec_bulk call writes; «Revert» sets each record back to its before-values while it is still at the version the change
 * left it, and reports the rows it could not (changed since, deleted, not allowed). A change is reverted once. Built by the
 * Platform builder, with its own messages (platform.bulk), so the Contacts screen's files change by one line (V-PLATFORM-14).
 */
export function BulkChanges() {
  const t = useTranslations('platform.bulk')
  const tc = useTranslations('common.errors')
  const te = useTranslations('platform.entities')
  const format = useFormatter()
  const now = useNow()
  const flash = useToast()
  const [rows, setRows] = useState<BulkChange[] | null>(null)
  const [failed, setFailed] = useState(false)
  const [pick, setPick] = useState<BulkChange | null>(null)
  const [reason, setReason] = useState('')
  const [pending, start] = useTransition()
  const load = useCallback(() => { void fetchBulkChanges().then((r) => { if (r.ok) setRows(r.rows); else setFailed(true) }) }, [])
  useEffect(load, [load])

  const field = (f: string) => (t.has(`fields.${f}`) ? t(`fields.${f}`) : f)
  const revert = (c: BulkChange) => start(async () => {
    const r = await revertBulk({ id: c.id, reason })
    if (!r.ok) { flash(tc.has(r.code) ? tc(r.code) : tc('failed')); return }
    flash(t('done', { reverted: r.reverted, skipped: r.stale + r.gone + r.forbidden }))
    setPick(null)
    setReason('')
    load()
  })

  if (failed) return null
  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="border-b border-line px-[18px] py-3 text-14 font-bold">{t('title')}</div>
      <div className="overflow-x-auto">
        <div className="min-w-[560px]">
          {rows === null ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('loading')}</div> : null}
          {rows && rows.length === 0 ? <div className="px-[18px] py-[30px] text-center text-13 text-muted">{t('empty')}</div> : null}
          {rows?.map((c) => (
            <div key={c.id} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:minmax(0,1.5fr)_140px_120px_90px]">
              <span className="flex min-w-0 flex-col">
                <b className="truncate">{t('change', { fields: c.fields.map(field).join(', '), count: c.count, entity: te.has(c.entity) ? te(c.entity) : c.entity })}</b>
                {c.revert_result ? (
                  <span className="text-11.5 text-muted">{t('result', { reverted: c.revert_result.reverted, stale: c.revert_result.stale, gone: c.revert_result.gone, forbidden: c.revert_result.forbidden })}</span>
                ) : null}
              </span>
              <span className="truncate text-muted">{c.staff ?? '—'}</span>
              <span className="text-muted">{format.relativeTime(new Date(c.at), now)}</span>
              {c.reverted_at ? (
                <span className="text-12 font-semibold text-muted">{t('reverted')}</span>
              ) : c.can_revert ? (
                <button type="button" onClick={() => setPick(c)} className="h-7 cursor-pointer rounded-9 border border-coral bg-transparent text-12 font-semibold text-rust">{t('revert')}</button>
              ) : <span />}
            </div>
          ))}
        </div>
      </div>
      {pick ? (
        <div onClick={() => setPick(null)} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
          <div role="dialog" aria-modal="true" aria-label={t('confirmTitle')} onClick={(e) => e.stopPropagation()} onKeyDown={(e) => { if (e.key === 'Escape') setPick(null) }}
            className="flex w-[480px] max-w-full flex-col gap-[11px] rounded-22 bg-surface px-6 py-[22px] shadow-modal">
            <b className="font-serif text-21">{t('confirmTitle')}</b>
            <span className="text-12.5 leading-[1.55]">{t('confirmBody', { count: pick.count })}</span>
            <label className="flex flex-col gap-1 text-11.5 font-semibold text-muted">
              {t('reason')}
              <input autoFocus value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} className="h-[38px] rounded-10 border border-line bg-canvas px-[11px] text-13 text-ink" />
            </label>
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setPick(null)} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
              <button type="button" disabled={pending} onClick={() => revert(pick)} className="h-[38px] cursor-pointer rounded-11 border border-coral bg-transparent px-[15px] text-13 font-semibold text-rust disabled:opacity-60">{t('revert')}</button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
