'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { LostReason } from '@/lib/data/deals'
import { Modal } from './Modal'

/**
 * The reason a deal was lost, asked only when Settings requires one (lost_reason_required; the design marks lost at
 * once). The reasons are the configured ones (lost_reasons_get); deal_status refuses without one.
 */
export function LostModal({ reasons, onClose, onSubmit }: {
  reasons: LostReason[]
  onClose: () => void
  onSubmit: (reason: string) => Promise<boolean>
}) {
  const t = useTranslations('simpleCrm.modal.lost')
  const [reason, setReason] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    if (!reason) { setError(t('pick')); return }
    setBusy(true)
    const ok = await onSubmit(reason)
    setBusy(false)
    if (!ok) setError(null)
  }

  return (
    <Modal title={t('title')} cta={t('cta')} busy={busy} error={error} onClose={onClose} onSubmit={() => void submit()}>
      <span className="text-13 leading-[1.5] text-ink-2">{t('text')}</span>
      {reasons.length ? (
        <div role="radiogroup" aria-label={t('title')} className="flex flex-wrap gap-[6px]">
          {reasons.map((r) => (
            <button
              key={r.id}
              type="button"
              role="radio"
              aria-checked={reason === r.label}
              onClick={() => { setReason(r.label); setError(null) }}
              className={`cursor-pointer rounded-999 border px-3 py-[7px] text-12.5 ${reason === r.label ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}
            >
              {r.label}
            </button>
          ))}
        </div>
      ) : (
        <span className="text-12.5 text-warn-ink">{t('none')}</span>
      )}
    </Modal>
  )
}
