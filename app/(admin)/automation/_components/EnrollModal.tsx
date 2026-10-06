'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Option, SequenceDetail } from '@/lib/data/automation'
import { enroll, searchRecords } from '../actions'
import { Modal, btnCancel, btnConfirm, field, fieldInput } from './Modal'
import { useDebounced, useErrorText } from './shared'

const check = 'flex cursor-pointer items-center gap-2 border-b border-line py-[7px] text-13 font-medium text-ink last:border-b-0'

/** «＋ Enroll a deal» (one record from a picker) and «Enroll in bulk» (a saved view, or several picked records). */
export function EnrollModal({ mode, seq, entity, views, onClose }: { mode: 'one' | 'bulk'; seq: SequenceDetail; entity: 'deal' | 'lead'; views: Option[]; onClose: () => void }) {
  const t = useTranslations('automation.enroll')
  const flash = useToast()
  const err = useErrorText()
  const [q, setQ] = useState('')
  const [rows, setRows] = useState<{ id: string; title: string }[]>([])
  const [picked, setPicked] = useState<Map<string, string>>(new Map())
  const [source, setSource] = useState<'view' | 'pick'>(views.length ? 'view' : 'pick')
  const [view, setView] = useState(views[0]?.id ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useDebounced(q, 200, async (v) => {
    const r = await searchRecords({ entity, q: v })
    if (r.ok) setRows(r.rows)
  })

  const submit = async (ids: string[] | null, viewId: string | null) => {
    setBusy(true)
    const r = await enroll({ id: seq.id, entity, ids, view: viewId })
    setBusy(false)
    if (!r.ok) { setError(err(r.code, r.detail)); return }
    flash(t('done', { n: r.enrolled, skipped: r.skipped }))
    onClose()
  }
  const toggle = (row: { id: string; title: string }) => {
    const m = new Map(picked)
    if (m.has(row.id)) m.delete(row.id); else m.set(row.id, row.title)
    setPicked(m)
  }

  const search = (
    <label className={field}>
      {t(`search.${entity}`)}
      <input type="search" value={q} onChange={(e) => setQ(e.target.value)} className={fieldInput} />
    </label>
  )

  return (
    <Modal eyebrow={seq.name} title={t(`${mode}.${entity}`)} onClose={onClose}>
      {mode === 'one' ? (
        <>
          {search}
          <div className="flex flex-col">
            {rows.length === 0 ? <span className="text-12.5 text-muted">{t('noMatch')}</span> : null}
            {rows.map((r) => (
              <button key={r.id} type="button" disabled={busy} onClick={() => submit([r.id], null)}
                className="cursor-pointer border-b border-line bg-transparent px-0 py-2 text-left text-13 font-semibold last:border-b-0">
                {r.title}
              </button>
            ))}
          </div>
        </>
      ) : (
        <>
          <div className="flex gap-4 text-13 font-medium">
            <label className="flex items-center gap-[6px]"><input type="radio" checked={source === 'view'} disabled={!views.length} onChange={() => setSource('view')} />{t('fromView')}</label>
            <label className="flex items-center gap-[6px]"><input type="radio" checked={source === 'pick'} onChange={() => setSource('pick')} />{t('fromPick')}</label>
          </div>
          {source === 'view' ? (
            views.length ? (
              <label className={field}>{t('view')}
                <select value={view} onChange={(e) => setView(e.target.value)} className={fieldInput}>{views.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}</select>
              </label>
            ) : <span className="text-12.5 text-muted">{t('noViews')}</span>
          ) : (
            <>
              {search}
              <div className="flex max-h-[240px] flex-col overflow-y-auto">
                {rows.length === 0 ? <span className="text-12.5 text-muted">{t('noMatch')}</span> : null}
                {rows.map((r) => (
                  <label key={r.id} className={check}><input type="checkbox" checked={picked.has(r.id)} onChange={() => toggle(r)} />{r.title}</label>
                ))}
              </div>
              <span className="text-12 text-muted">{t('picked', { n: picked.size })}</span>
            </>
          )}
        </>
      )}
      {error ? <p role="alert" className="m-0 text-12.5 font-semibold text-danger">{error}</p> : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
        {mode === 'bulk' ? (
          <button type="button" disabled={busy || (source === 'view' ? !view : picked.size === 0)} onClick={() => (source === 'view' ? submit(null, view) : submit([...picked.keys()], null))} className={btnConfirm}>
            {t('confirm')}
          </button>
        ) : null}
      </div>
    </Modal>
  )
}
