'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Person } from '@/lib/data/automation'
import { transferWorkflow } from '../actions'
import { Modal, btnCancel, btnConfirm, field, fieldInput } from './Modal'
import { useErrorText } from './shared'

/** «Transfer» (AUT-10): a staff picker of the people who may own a workflow in its scope. Both are notified
 *  and the change is audited by workflow_transfer. */
export function TransferModal({ wf, people, onClose }: { wf: { id: string; name: string; owner: string | null }; people: Person[]; onClose: () => void }) {
  const t = useTranslations('automation.transfer')
  const flash = useToast()
  const err = useErrorText()
  const [to, setTo] = useState(people[0]?.id ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const submit = async () => {
    const person = people.find((p) => p.id === to)
    if (!person) return
    setBusy(true)
    const r = await transferWorkflow({ id: wf.id, to })
    setBusy(false)
    if (!r.ok) { setError(err(r.code, r.detail)); return }
    flash(t('done', { name: person.name }))
    onClose()
  }
  return (
    <Modal eyebrow={t('eyebrow')} title={wf.name} onClose={onClose}>
      <p className="m-0 text-13 leading-[1.5] text-muted">{t('body', { owner: wf.owner ?? '—' })}</p>
      {people.length ? (
        <label className={field}>
          {t('to')}
          <select value={to} onChange={(e) => setTo(e.target.value)} className={fieldInput}>
            {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
      ) : <p className="m-0 text-13 text-muted">{t('nobody')}</p>}
      {error ? <p role="alert" className="m-0 text-12.5 font-semibold text-danger">{error}</p> : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
        <button type="button" disabled={busy || !to} onClick={submit} className={btnConfirm}>{t('confirm')}</button>
      </div>
    </Modal>
  )
}
