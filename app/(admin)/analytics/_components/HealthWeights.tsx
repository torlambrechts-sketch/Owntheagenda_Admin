'use client'

import { useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { SIGNALS } from '@/lib/data/analytics-calc'
import { saveHealthModel } from '../actions'

type Signal = (typeof SIGNALS)[number]

/**
 * «How the score is built» (Analytics.dc.html, weights): the active model's five weights as shares. Those
 * who may configure the platform edit them in place; saving makes a new model version and recomputes the
 * scores (health_model_save).
 */
export function HealthWeights({ weights, version, canEdit, shares }: {
  weights: Record<string, number>; version: number | null; canEdit: boolean; shares: { key: string; label: string; pct: string }[]
}) {
  const t = useTranslations('analytics.health.built')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [edit, setEdit] = useState(false)
  const [pending, start] = useTransition()
  const [draft, setDraft] = useState<Record<Signal, string>>(() => Object.fromEntries(SIGNALS.map((k) => [k, String(weights[k] ?? 0)])) as Record<Signal, string>)

  const submit = () => {
    const w = Object.fromEntries(SIGNALS.map((k) => [k, Number(draft[k])])) as Record<Signal, number>
    if (SIGNALS.some((k) => !Number.isInteger(w[k]) || w[k] < 0 || w[k] > 100) || SIGNALS.every((k) => w[k] === 0)) { flash(te('invalid')); return }
    start(async () => {
      const r = await saveHealthModel(w)
      if (!r.ok) { flash(te(r.code)); return }
      flash(t('saved'))
      setEdit(false)
    })
  }

  return (
    <>
      <div className="mb-[10px] mt-[18px] flex items-baseline justify-between gap-3">
        <span className="text-15 font-bold">{t('title')}</span>
        <span className="flex items-baseline gap-3 text-12 text-muted">
          {version !== null ? <span>{t('model', { version })}</span> : null}
          {canEdit && !edit ? <button type="button" onClick={() => setEdit(true)} className="cursor-pointer border-0 bg-transparent p-0 text-12.5 font-semibold text-link">{t('edit')}</button> : null}
        </span>
      </div>
      {edit ? (
        <form onSubmit={(e) => { e.preventDefault(); submit() }}>
          {SIGNALS.map((k) => (
            <label key={k} className="grid items-center gap-[10px] border-b border-line py-[5px] text-12.5 [grid-template-columns:minmax(0,1fr)_60px]">
              <span>{shares.find((s) => s.key === k)?.label ?? k}</span>
              <input
                type="number" min={0} max={100} step={1} value={draft[k]} disabled={pending}
                onChange={(e) => setDraft({ ...draft, [k]: e.target.value })}
                className="h-[28px] w-[60px] rounded-8 border border-line bg-canvas px-2 text-right text-12.5"
              />
            </label>
          ))}
          <div className="mt-2 text-11.5 text-muted">{t('hint')}</div>
          <div className="mt-3 flex gap-2">
            <button type="submit" disabled={pending} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold">{t('save')}</button>
            <button type="button" disabled={pending} onClick={() => setEdit(false)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('cancel')}</button>
          </div>
        </form>
      ) : shares.map((w) => (
        <div key={w.key} className="grid gap-[10px] border-b border-line py-[7px] text-12.5 [grid-template-columns:minmax(0,1fr)_60px]">
          <span>{w.label}</span><b className="text-right">{w.pct}</b>
        </div>
      ))}
    </>
  )
}
