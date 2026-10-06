'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Lead, Pipeline } from '@/lib/data/contacts'
import { convertLead } from '../actions'
import { dialog, fieldInput, fieldLabel, overlay, useError, useNav } from './util'

/** Convert to deal (Contacts.dc.html, convert): pipeline and stage, then lead_convert. */
export function ConvertModal({ lead, pipelines, onClose }: { lead: Lead; pipelines: Pipeline[]; onClose: () => void }) {
  const t = useTranslations('contacts')
  const flash = useToast()
  const err = useError()
  const { go } = useNav()
  const [pl, setPl] = useState(pipelines[0]!.id)
  const stages = pipelines.find((p) => p.id === pl)?.stages ?? []
  const [stage, setStage] = useState(stages[0]?.id ?? '')
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    const k = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', k)
    return () => window.removeEventListener('keydown', k)
  }, [onClose])

  async function run() {
    setBusy(true)
    const r = await convertLead({ lead: lead.id, pipeline: pl, stage })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    flash(t('convert.done', { pipeline: pipelines.find((p) => p.id === pl)?.name ?? '' }))
    onClose()
    go({ lead: null })
  }

  return (
    <div className={overlay} onClick={onClose}>
      <div role="dialog" aria-modal="true" aria-labelledby="convert-title" className={dialog} onClick={(e) => e.stopPropagation()}>
        <div id="convert-title" className="font-serif text-21 font-semibold">{t('convert.title')}</div>
        <label className={fieldLabel}>
          {t('convert.pipeline')}
          <select autoFocus value={pl} onChange={(e) => { setPl(e.target.value); setStage(pipelines.find((p) => p.id === e.target.value)?.stages[0]?.id ?? '') }} className={fieldInput}>
            {pipelines.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
        <label className={fieldLabel}>
          {t('convert.stage')}
          <select value={stage} onChange={(e) => setStage(e.target.value)} className={fieldInput}>
            {stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
        <div className="text-12.5 text-ink-2">{t('convert.note')}</div>
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
          <button type="button" disabled={busy || !stage} onClick={run} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:opacity-60">{t('convert.go')}</button>
        </div>
      </div>
    </div>
  )
}
