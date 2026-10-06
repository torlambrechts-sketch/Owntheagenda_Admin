'use client'

import { useTranslations } from 'next-intl'
import type { SavedView } from '@/lib/data/deals'
import type { Cond, CondField, CondOp } from './shared'

const FIELDS: CondField[] = ['value', 'source', 'label']
const OPS: CondOp[] = ['is', 'gt', 'lt', 'contains']
const select = 'h-8 rounded-9 border border-line bg-canvas text-12.5 text-ink'

const isCond = (x: unknown): x is Cond =>
  !!x && typeof x === 'object' && FIELDS.includes((x as Cond).field) && OPS.includes((x as Cond).op) && typeof (x as Cond).val === 'string'

/** The advanced filter popover (Deals.dc.html advOpen): AND conditions, saved filters. */
export function AdvancedFilter({ open, setOpen, conds, setConds, saved, onSave }: {
  open: boolean
  setOpen: (v: boolean) => void
  conds: Cond[]
  setConds: (c: Cond[]) => void
  saved: SavedView[]
  onSave: () => void
}) {
  const t = useTranslations('deals.filter')
  const set = (i: number, patch: Partial<Cond>) => setConds(conds.map((c, j) => (j === i ? { ...c, ...patch } : c)))
  const active = conds.length > 0
  return (
    <div className="relative">
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen(!open)}
        className={`h-[34px] cursor-pointer rounded-10 border px-3 text-12.5 font-semibold ${active ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`}
      >
        {t('button')}{active ? ` · ${conds.length}` : ''}
      </button>
      {open ? (
        <div className="absolute left-0 top-[42px] z-30 flex w-[520px] max-w-[calc(100vw-32px)] flex-col gap-[10px] rounded-18 border border-line bg-surface p-[14px] shadow-pop">
          <div className="flex items-center justify-between">
            <b className="text-13.5">{t('title')}</b>
            <span className="text-11.5 text-muted">{t('same')}</span>
          </div>
          {conds.map((c, i) => (
            <div key={i} className="flex items-center gap-[6px]">
              <span className="w-11 text-11 font-bold uppercase text-muted">{i === 0 ? t('where') : t('and')}</span>
              <select aria-label={t('field')} value={c.field} onChange={(e) => set(i, { field: e.target.value as CondField })} className={`${select} flex-1`}>
                {FIELDS.map((f) => <option key={f} value={f}>{t(`fields.${f}`)}</option>)}
              </select>
              <select aria-label={t('op')} value={c.op} onChange={(e) => set(i, { op: e.target.value as CondOp })} className={`${select} w-[90px]`}>
                {OPS.map((o) => <option key={o} value={o}>{t(`ops.${o}`)}</option>)}
              </select>
              <input aria-label={t('value')} value={c.val} onChange={(e) => set(i, { val: e.target.value })} className={`${select} w-[120px] px-2`} />
              <button type="button" aria-label={t('remove')} onClick={() => setConds(conds.filter((_, j) => j !== i))} className="h-7 w-7 cursor-pointer rounded-999 border border-line bg-transparent">×</button>
            </div>
          ))}
          <div className="flex gap-[6px]">
            <button type="button" onClick={() => setConds([...conds, { field: 'value', op: 'gt', val: '50000' }])} className="h-[30px] cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">
              {t('addAnd')}
            </button>
            <span className="flex-1" />
            <button type="button" disabled={!active} onClick={onSave} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-60">
              {t('save')}
            </button>
          </div>
          <div className="flex flex-wrap items-center gap-[6px] border-t border-line pt-[10px]">
            <span className="text-11 font-bold uppercase tracking-label text-muted">{t('saved')}</span>
            {saved.map((s) => {
              const cs = Array.isArray(s.query.conds) ? s.query.conds.filter(isCond) : []
              return (
                <button key={s.id} type="button" onClick={() => setConds(cs)} className="cursor-pointer rounded-999 border border-line-strong bg-transparent px-[10px] py-1 text-11.5">
                  {s.name}
                </button>
              )
            })}
            {saved.length === 0 ? <span className="text-11.5 text-faint">{t('noneSaved')}</span> : null}
          </div>
        </div>
      ) : null}
    </div>
  )
}
