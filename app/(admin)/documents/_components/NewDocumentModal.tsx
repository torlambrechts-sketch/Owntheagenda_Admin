'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { DealOption, StorageState, Template } from '@/lib/data/documents-shared'
import { createDocumentAction, dealOptionsAction } from '../actions'
import { Modal, btnCancel, btnConfirm, field, fieldInput, note } from './Modal'
import { useError } from './util'

/**
 * «＋ Document from template»: a template and a deal, then document_create. Missing values are listed here; they
 * block sending, not creation (DOC-01). A drive template needs the drive adapter and is refused as not connected.
 */
export function NewDocumentModal({ templates, storage, onClose, onCreated }: { templates: Template[]; storage: StorageState | null; onClose: () => void; onCreated: (id: string) => void }) {
  const t = useTranslations('documents.new')
  const ts = useTranslations('documents.storage')
  const tc = useTranslations('common')
  const flash = useToast()
  const err = useError()
  const usable = templates.filter((x) => x.source === 'platform')
  const [template, setTemplate] = useState(usable[0]?.id ?? templates[0]?.id ?? '')
  const [deals, setDeals] = useState<DealOption[] | null>(null)
  const [deal, setDeal] = useState('')
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<{ id: string; missing: string[]; unknown: string[] } | null>(null)

  useEffect(() => {
    let live = true
    void dealOptionsAction().then((r) => { if (live && r.ok) { setDeals(r.deals); setDeal(r.deals[0]?.id ?? '') } })
    return () => { live = false }
  }, [])

  const chosen = templates.find((x) => x.id === template)
  // a new document is stored on the platform; a drive default gets a copy only once the drive adapter makes one (0032)
  const where = ts('platformLong')
  const driveDefault = storage && storage.default.provider !== 'platform' ? ts(storage.default.provider) : null

  async function create() {
    if (!template || !deal) return
    setBusy(true); setError(null)
    const r = await createDocumentAction({ template, deal, name: name.trim() || undefined })
    setBusy(false)
    if (!r.ok) return setError(err(r))
    if (r.missing.length || r.unknown.length) { setResult(r); return }
    flash(t('done', { template: chosen?.name ?? '', where }))
    onCreated(r.id)
    onClose()
  }

  if (result) {
    return (
      <Modal eyebrow={t('eyebrow')} title={t('createdTitle')} onClose={() => { onCreated(result.id); onClose() }}>
        <div className={note}>
          {result.missing.length ? <div>{t('missing', { tokens: result.missing.map((x) => `[${x}]`).join(' ') })}</div> : null}
          {result.unknown.length ? <div>{t('unknown', { tokens: result.unknown.map((x) => `[${x}]`).join(' ') })}</div> : null}
        </div>
        <span className="text-12.5 text-ink-2">{t('blocks')}</span>
        <div className="flex justify-end">
          <button type="button" onClick={() => { onCreated(result.id); onClose() }} className={btnConfirm}>{t('open')}</button>
        </div>
      </Modal>
    )
  }

  return (
    <Modal eyebrow={t('eyebrow')} title={t('title')} onClose={onClose}>
      {templates.length ? (
        <>
          <label className={field}>{t('template')}
            <select value={template} onChange={(e) => setTemplate(e.target.value)} className={fieldInput}>
              {templates.map((x) => <option key={x.id} value={x.id}>{x.source === 'platform' ? x.name : t('driveTemplate', { name: x.name })}</option>)}
            </select>
          </label>
          <label className={field}>{t('deal')}
            <select value={deal} onChange={(e) => setDeal(e.target.value)} disabled={!deals || !deals.length} className={fieldInput}>
              {deals === null ? <option value="">{tc('loading')}</option> : deals.length ? deals.map((d) => <option key={d.id} value={d.id}>{d.title}</option>) : <option value="">{t('noDeals')}</option>}
            </select>
          </label>
          <label className={field}>{t('name')}
            <input value={name} maxLength={200} placeholder={chosen?.name ?? ''} onChange={(e) => setName(e.target.value)} className={fieldInput} />
          </label>
          <span className="text-12 text-muted">{t('hint', { where })}{driveDefault ? ` ${t('driveCopy', { drive: driveDefault })}` : ''}</span>
        </>
      ) : (
        <div className={note}>{t('noTemplates')}</div>
      )}
      {error ? <div className={note}>{error}</div> : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{tc('cancel')}</button>
        <button type="button" disabled={busy || !template || !deal} onClick={create} className={btnConfirm}>{t('go')}</button>
      </div>
    </Modal>
  )
}
