'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { countSegment, saveSegment } from '../../campaigns/actions'
import { ORG_STATUSES, listQuery } from '@/lib/data/simple-crm-shared'
import { Modal, field } from './Modal'

/**
 * «New list» (SimpleCRM.dc.html modal.isList): a name, a role (the titles people have) and an account status, with the
 * live number of people that match (segment_count). Saved as a shared campaign segment (segment_save), usable as a
 * campaign's audience.
 */
export function NewListModal({ roles, onClose, onSaved }: { roles: string[]; onClose: () => void; onSaved: (id: string) => void }) {
  const t = useTranslations('simpleCrm.modal.list')
  const ts = useTranslations('simpleCrm.orgStatus')
  const te = useTranslations('common.errors')
  const tc = useTranslations('common')
  const [name, setName] = useState('')
  const [role, setRole] = useState('')
  const [status, setStatus] = useState('')
  const [count, setCount] = useState<number | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const seq = useRef(0)

  // the count follows the form, a moment after the last change
  useEffect(() => {
    const n = ++seq.current
    const h = setTimeout(() => {
      void countSegment({ query: listQuery(role, status) }).then((r) => {
        if (n !== seq.current) return
        setCount(r.ok ? r.counts.matches : null)
      })
    }, 250)
    return () => clearTimeout(h)
  }, [role, status])

  const save = async () => {
    if (busy) return
    setBusy(true)
    setError(null)
    const r = await saveSegment({ id: null, name: name.trim() || t('fallback'), query: listQuery(role, status), shared: true })
    setBusy(false)
    if (!r.ok) { setError(te(r.code)); return }
    onSaved(r.id)
  }

  return (
    <Modal title={t('title')} cta={t('cta')} busy={busy} error={error} onClose={onClose} onSubmit={() => void save()}>
      <div className="flex flex-col gap-[10px]">
        <label className={field.label}>
          {t('name')}
          <input value={name} maxLength={80} onChange={(e) => setName(e.target.value)} placeholder={t('namePh')} className={field.input} />
        </label>
        <label className={field.label}>
          {t('role')}
          <select value={role} onChange={(e) => setRole(e.target.value)} className={field.select}>
            <option value="">{t('anyRole')}</option>
            {roles.map((r) => <option key={r} value={r}>{r}</option>)}
          </select>
        </label>
        <label className={field.label}>
          {t('status')}
          <select value={status} onChange={(e) => setStatus(e.target.value)} className={field.select}>
            <option value="">{t('anyStatus')}</option>
            {ORG_STATUSES.map((s) => <option key={s} value={s}>{ts(s)}</option>)}
          </select>
        </label>
        <span aria-live="polite" className="text-12 text-muted">{t('preview', { count: count === null ? tc('dash') : String(count) })}</span>
      </div>
    </Modal>
  )
}
