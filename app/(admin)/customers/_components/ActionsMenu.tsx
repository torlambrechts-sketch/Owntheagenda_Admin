'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { runCustomerAction } from '../actions'
import { Modal, btnCancel, btnConfirm, field, fieldArea, fieldInput } from './Modal'
import { useErrorText } from './useErrorText'

type Key = 'trial' | 'plan' | 'discount' | 'comp' | 'suspend' | 'resync' | 'owner' | 'merge' | 'export' | 'delete'
const KEYS: Key[] = ['trial', 'plan', 'discount', 'comp', 'suspend', 'resync', 'owner', 'merge', 'export', 'delete']
// the actions that reach the product today (D-40); the rest wait for a product command
const LIVE = new Set<Key>(['trial', 'resync', 'delete'])

type Props = {
  org: { id: string; name: string; orgnr: string; suspended: boolean }
  hasOrgpuls: boolean
  previews: { trial: string; delete: string }
  rights: { trial: boolean; resync: boolean; delete: boolean }
  secondAdmin: boolean
}

/** The company's «Actions ▾» menu and the action dialog: preview, the one field, a typed reason (Customers.dc.html). */
export function ActionsMenu({ org, hasOrgpuls, previews, rights, secondAdmin }: Props) {
  const t = useTranslations('customers.actions')
  const tm = useTranslations('customers.modal')
  const err = useErrorText()
  const flash = useToast()
  const [open, setOpen] = useState(false)
  const [modal, setModal] = useState<Key | null>(null)
  const [reason, setReason] = useState('')
  const [value, setValue] = useState('')
  const [busy, setBusy] = useState(false)
  const box = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const close = (e: MouseEvent) => { if (!box.current?.contains(e.target as Node)) setOpen(false) }
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', close)
    document.addEventListener('keydown', esc)
    return () => { document.removeEventListener('mousedown', close); document.removeEventListener('keydown', esc) }
  }, [open])

  const blocked = (k: Key): string | null => {
    if (!LIVE.has(k)) return t('notYet')
    if (!hasOrgpuls) return t('noOrgpuls')
    if (!rights[k as 'trial' | 'resync' | 'delete']) return t(k === 'delete' ? 'superAdminOnly' : 'noRight')
    return null
  }
  const name = (k: Key) => (k === 'suspend' && org.suspended ? t('items.reactivate.n') : t(`items.${k}.n`))

  const digits = org.orgnr.replace(/\s/g, '')
  const days = Number(value)
  const cantConfirm = busy || !reason.trim()
    || (modal === 'trial' && !(Number.isInteger(days) && days >= 1 && days <= 60))
    || (modal === 'delete' && (!digits || value.replace(/\s/g, '') !== digits))

  const confirm = async () => {
    if (cantConfirm || !modal || !LIVE.has(modal)) return
    setBusy(true)
    const r = await runCustomerAction({
      org: org.id,
      action: modal as 'trial' | 'resync' | 'delete',
      reason: reason.trim(),
      ...(modal === 'trial' ? { days } : {}),
      ...(modal === 'delete' ? { confirm: value } : {}),
    })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    flash(t('done', { action: name(modal) }))
    setModal(null)
  }

  const danger = modal === 'delete'
  const hasField = modal === 'trial' || modal === 'delete'

  return (
    <div ref={box} className="relative">
      <button type="button" aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen(!open)} className="h-10 cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold">
        {t('button')}
      </button>
      {open ? (
        <div role="menu" className="absolute right-0 top-[46px] z-30 w-[270px] rounded-18 border border-line bg-surface p-[6px] shadow-pop">
          {KEYS.map((k) => {
            const why = blocked(k)
            return (
              <button
                key={k}
                type="button"
                role="menuitem"
                aria-disabled={why ? true : undefined}
                onClick={() => {
                  if (why) return
                  setOpen(false)
                  setReason('')
                  setValue('')
                  setModal(k)
                }}
                className={`flex w-full flex-col gap-px rounded-10 border-none bg-transparent px-[11px] py-2 text-left ${why ? 'cursor-default' : 'cursor-pointer'}`}
              >
                <span className={`text-13 font-semibold ${k === 'delete' ? 'text-danger' : 'text-ink'} ${why ? 'opacity-55' : ''}`}>{name(k)}</span>
                <span className="text-11 text-faint">{why ?? t(`items.${k}.s`)}</span>
              </button>
            )
          })}
        </div>
      ) : null}

      {modal ? (
        <Modal eyebrow={org.name} title={name(modal)} onClose={() => setModal(null)}>
          <div className="text-13 leading-[1.55] text-ink-2">{modal === 'trial' ? previews.trial : modal === 'delete' ? previews.delete : t('preview.resync')}</div>
          {hasField ? (
            <label className={field}>
              {t(`items.${modal}.field`)}
              <input
                value={value}
                onChange={(e) => setValue(e.target.value)}
                inputMode="numeric"
                placeholder={modal === 'delete' ? org.orgnr : '14'}
                className={fieldInput}
              />
            </label>
          ) : null}
          <label className={field}>
            {tm('reason')}
            <textarea value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} placeholder={tm('reasonPlaceholder')} className={fieldArea} />
          </label>
          {danger ? <div className="text-12 text-danger">{t(secondAdmin ? 'dangerNoteApproval' : 'dangerNote')}</div> : null}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setModal(null)} className={btnCancel}>{tm('cancel')}</button>
            <button type="button" onClick={confirm} disabled={cantConfirm} className={`${btnConfirm} ${danger ? 'bg-salmon' : 'bg-primary'} ${cantConfirm ? 'opacity-55' : ''}`}>
              {danger ? t('deleteCta') : tm('confirm')}
            </button>
          </div>
        </Modal>
      ) : null}
    </div>
  )
}
