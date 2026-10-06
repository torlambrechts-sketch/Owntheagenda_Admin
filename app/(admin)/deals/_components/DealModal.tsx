'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { DealsBase, Pipeline, SavedView } from '@/lib/data/deals'
import { createDeal, createProduct, moveDeal, saveActivity, saveView, setStatus, type MissingField } from '../actions'
import type { Cond, Modal } from './shared'

const inputCls = 'h-10 rounded-10 border border-line bg-canvas px-3 text-13'

const optionsOf = (f: MissingField) =>
  f.options.flatMap((o) => (typeof o === 'string' ? [{ key: o, label: o }] : o && typeof o === 'object' && 'key' in o ? [{ key: String((o as { key: unknown }).key), label: String((o as { label?: unknown }).label ?? (o as { key: unknown }).key) }] : []))

/** A required field's typed value as the custom-field check expects it (app.check_custom). */
function typed(f: MissingField, raw: string): unknown {
  const v = raw.trim()
  if (!v) return null
  if (f.type === 'numerical') { const n = Number(v.replace(',', '.')); return Number.isFinite(n) ? n : null }
  if (f.type === 'monetary') { const n = Number(v.replace(/\s/g, '').replace(',', '.')); return Number.isFinite(n) ? { amount: n, currency: 'NOK' } : null }
  if (f.type === 'multiple_options') return [v]
  return v
}

/** The design's dialog (Deals.dc.html modal): new deal, lost with reasons, required field, next step; and save filter, new product. */
export function DealModal({ modal, setModal, base, pipeline, conds, onCreated, onSaved, onChanged }: {
  modal: Modal
  setModal: (m: Modal | null) => void
  base: DealsBase
  pipeline: Pipeline
  conds: Cond[]
  onCreated: (id: string) => void
  onSaved: (v: SavedView) => void
  onChanged: () => void
}) {
  const t = useTranslations('deals.modal')
  const tf = useTranslations('deals.flash')
  const te = useTranslations('common.errors')
  const tc = useTranslations('common')
  const flash = useToast()
  const [input, setInput] = useState('')
  const [price, setPrice] = useState('')
  const [reason, setReason] = useState<string | null>(null)
  const [fields, setFields] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const first = useRef<HTMLInputElement | HTMLSelectElement | null>(null)
  const close = () => setModal(null)

  useEffect(() => { first.current?.focus() }, [modal.kind])

  const supported = (f: MissingField) => ['text', 'large_text', 'numerical', 'monetary', 'date', 'single_option', 'multiple_options', 'phone', 'autocomplete'].includes(f.type)

  const copy = (() => {
    switch (modal.kind) {
      case 'new': return { title: t('new.title'), text: t('new.text'), ph: t('new.ph'), cta: t('new.cta') }
      case 'lost': return { title: t('lost.title'), text: t('lost.text'), ph: t('lost.ph'), cta: t('lost.cta') }
      case 'required': return {
        title: t('required.title', { stage: modal.stageName }),
        text: t('required.text', { fields: modal.missing.map((f) => `«${f.label}»`).join(', '), stage: modal.stageName, count: modal.missing.length }),
        ph: '', cta: t('required.cta'),
      }
      case 'next': return { title: t('next.title'), text: t('next.text', { subject: modal.subject }), ph: t('next.ph'), cta: t('next.cta') }
      case 'saveFilter': return { title: t('saveFilter.title'), text: t('saveFilter.text'), ph: t('saveFilter.ph'), cta: t('saveFilter.cta') }
      case 'product': return { title: t('product.title'), text: t('product.text'), ph: t('product.ph'), cta: t('product.cta') }
    }
  })()

  const ok = async () => {
    setBusy(true)
    setError(null)
    try {
      switch (modal.kind) {
        case 'new': {
          if (!input.trim()) { setError(t('new.titleRequired')); return }
          const r = await createDeal({ title: input, pipeline_id: pipeline.id, stage_id: pipeline.stages[0]?.id })
          if (!r.ok) { setError(te(r.code)); return }
          flash(tf('created'))
          close()
          onCreated(r.id)
          return
        }
        case 'lost': {
          const r = await setStatus({ id: modal.id, status: 'lost', reason: reason ?? undefined, comment: input.trim() || undefined, version: modal.version })
          if (!r.ok) { setError(r.detail === 'lost_reason:required' ? t('lost.reasonRequired') : te(r.code)); return }
          flash(tf('lost'))
          close()
          onChanged()
          return
        }
        case 'required': {
          const values: Record<string, unknown> = {}
          for (const f of modal.missing) values[f.key] = typed(f, fields[f.key] ?? '')
          if (Object.values(values).some((v) => v === null)) { setError(t('required.fill')); return }
          const r = await moveDeal({ id: modal.id, stage: modal.stage, version: modal.version, fields: values })
          if (!r.ok) { setError(te(r.code)); return }
          if (r.missing && r.missing.length) { setModal({ ...modal, missing: r.missing }); return }
          flash(tf('moved', { stage: modal.stageName }))
          close()
          onChanged()
          return
        }
        case 'next': {
          const type = base.activityTypes.find((a) => a.key === 'task') ?? base.activityTypes[0]
          if (!type) { setError(te('failed')); return }
          const r = await saveActivity({ deal: modal.dealId, type_id: type.id, subject: input.trim() || t('next.fallback'), starts_at: null })
          if (!r.ok) { setError(te(r.code)); return }
          flash(tf('nextPlanned'))
          close()
          onChanged()
          return
        }
        case 'saveFilter': {
          if (!input.trim()) { setError(t('saveFilter.nameRequired')); return }
          const r = await saveView({ name: input, query: { conds } })
          if (!r.ok) { setError(te(r.code)); return }
          onSaved({ id: r.id, name: input.trim(), query: { conds }, shared: false, mine: true })
          flash(tf('filterSaved'))
          close()
          return
        }
        case 'product': {
          if (!input.trim()) { setError(t('product.nameRequired')); return }
          const n = price.trim() ? Number(price.replace(/\s/g, '').replace(',', '.')) : null
          if (n !== null && (!Number.isFinite(n) || n < 0)) { setError(t('product.priceInvalid')); return }
          const r = await createProduct({ name: input, price: n })
          if (!r.ok) { setError(te(r.code)); return }
          flash(tf('productAdded'))
          close()
          onChanged()
          return
        }
      }
    } finally {
      setBusy(false)
    }
  }

  const setRef = (i: number) => (el: HTMLInputElement | HTMLSelectElement | null) => { if (i === 0) first.current = el }

  return (
    <div onClick={close} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="deal-modal-title"
        onClick={(e) => e.stopPropagation()}
        className="flex w-[460px] max-w-full flex-col gap-3 rounded-22 bg-surface px-6 py-[22px] shadow-modal"
      >
        <div id="deal-modal-title" className="font-serif text-21 font-semibold">{copy.title}</div>
        <div className="text-13 leading-[1.5] text-ink-2">{copy.text}</div>
        {modal.kind === 'lost' ? (
          <div className="flex flex-wrap gap-[6px]">
            {base.lostReasons.map((r) => (
              <button
                key={r.id}
                type="button"
                aria-pressed={reason === r.label}
                onClick={() => setReason(reason === r.label ? null : r.label)}
                className={`cursor-pointer rounded-999 border px-3 py-[7px] text-12.5 ${reason === r.label ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}
              >
                {r.label}
              </button>
            ))}
          </div>
        ) : null}
        {modal.kind === 'required' ? (
          modal.missing.map((f, i) =>
            !supported(f) ? (
              <div key={f.key} className="text-12.5 text-warn-ink">{t('required.unsupported', { field: f.label })}</div>
            ) : f.type === 'single_option' || f.type === 'multiple_options' ? (
              <select key={f.key} ref={setRef(i)} aria-label={f.label} value={fields[f.key] ?? ''} onChange={(e) => setFields({ ...fields, [f.key]: e.target.value })} className={`${inputCls} text-ink`}>
                <option value="">{f.label}</option>
                {optionsOf(f).map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}
              </select>
            ) : (
              <input
                key={f.key}
                ref={setRef(i)}
                aria-label={f.label}
                type={f.type === 'date' ? 'date' : 'text'}
                inputMode={f.type === 'numerical' || f.type === 'monetary' ? 'decimal' : undefined}
                value={fields[f.key] ?? ''}
                placeholder={f.label}
                onChange={(e) => setFields({ ...fields, [f.key]: e.target.value })}
                onKeyDown={(e) => { if (e.key === 'Enter') void ok() }}
                className={inputCls}
              />
            ),
          )
        ) : (
          <input
            ref={setRef(0)}
            aria-label={copy.ph}
            value={input}
            placeholder={copy.ph}
            maxLength={modal.kind === 'lost' ? 10000 : 200}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') void ok() }}
            className={inputCls}
          />
        )}
        {modal.kind === 'product' ? (
          <input aria-label={t('product.price')} value={price} inputMode="decimal" placeholder={t('product.price')} onChange={(e) => setPrice(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void ok() }} className={inputCls} />
        ) : null}
        {error ? <div role="alert" className="text-12.5 font-semibold text-danger">{error}</div> : null}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={close} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{tc('cancel')}</button>
          <button type="button" disabled={busy} onClick={() => void ok()} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60">
            {copy.cta}
          </button>
        </div>
      </div>
    </div>
  )
}
