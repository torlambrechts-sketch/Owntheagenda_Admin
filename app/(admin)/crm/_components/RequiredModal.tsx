'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { moveDeal, type MissingField } from '../../deals/actions'
import { Modal, field } from './Modal'

const SUPPORTED = ['text', 'large_text', 'numerical', 'monetary', 'date', 'single_option', 'multiple_options', 'phone', 'autocomplete']

const optionsOf = (f: MissingField) =>
  f.options.flatMap((o) => (typeof o === 'string' ? [{ key: o, label: o }]
    : o && typeof o === 'object' && 'key' in o ? [{ key: String((o as { key: unknown }).key), label: String((o as { label?: unknown }).label ?? (o as { key: unknown }).key) }] : []))

/** A typed value the custom-field check accepts (app.check_custom), or null when the input is not one. */
function typed(f: MissingField, raw: string): unknown {
  const v = raw.trim()
  if (!v) return null
  if (f.type === 'numerical') { const n = Number(v.replace(',', '.')); return Number.isFinite(n) ? n : null }
  if (f.type === 'monetary') { const n = Number(v.replace(/\s/g, '').replace(',', '.')); return Number.isFinite(n) ? { amount: n, currency: 'NOK' } : null }
  if (f.type === 'multiple_options') return [v]
  return v
}

/**
 * A stage that needs fields first (deal_move answers with the missing ones): fill them and move in the same call.
 * The design has no such stage; the database's rule is shown rather than a move that silently did not happen.
 */
export function RequiredModal({ deal, stage, stageName, missing, onClose, onMoved }: {
  deal: { id: string; version: number }
  stage: string
  stageName: string
  missing: MissingField[]
  onClose: () => void
  onMoved: (stillMissing: MissingField[] | null) => void
}) {
  const t = useTranslations('simpleCrm.modal.required')
  const te = useTranslations('common.errors')
  const [values, setValues] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    const fields: Record<string, unknown> = {}
    for (const f of missing) fields[f.key] = typed(f, values[f.key] ?? '')
    if (missing.some((f) => !SUPPORTED.includes(f.type)) || Object.values(fields).some((v) => v === null)) { setError(t('fill')); return }
    setBusy(true)
    const r = await moveDeal({ id: deal.id, stage, fields })
    setBusy(false)
    if (!r.ok) { setError(te(r.code)); return }
    onMoved(r.missing && r.missing.length ? r.missing : null)
  }

  return (
    <Modal title={t('title', { stage: stageName })} cta={t('cta')} busy={busy} error={error} onClose={onClose} onSubmit={() => void submit()}>
      <span className="text-13 leading-[1.5] text-ink-2">{t('text', { stage: stageName })}</span>
      <div className="flex flex-col gap-[10px]">
        {missing.map((f) => (
          !SUPPORTED.includes(f.type) ? (
            <span key={f.key} className="text-12.5 text-warn-ink">{t('unsupported', { field: f.label })}</span>
          ) : (
            <label key={f.key} className={field.label}>
              {f.label}
              {f.type === 'single_option' || f.type === 'multiple_options' ? (
                <select value={values[f.key] ?? ''} onChange={(e) => setValues({ ...values, [f.key]: e.target.value })} className={field.select}>
                  <option value="" />
                  {optionsOf(f).map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}
                </select>
              ) : (
                <input
                  type={f.type === 'date' ? 'date' : 'text'}
                  inputMode={f.type === 'numerical' || f.type === 'monetary' ? 'decimal' : undefined}
                  value={values[f.key] ?? ''}
                  onChange={(e) => setValues({ ...values, [f.key]: e.target.value })}
                  className={field.input}
                />
              )}
            </label>
          )
        ))}
      </div>
    </Modal>
  )
}
