'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, money, type NumberFormat } from '@/lib/format'
import type { Goal } from '@/lib/data/insights'
import { deleteGoalAction, saveGoalAction } from '../actions'
import type { Pickers, Rights } from './shared'

type Kind = Goal['kind']
const KINDS: Kind[] = ['deals_added', 'deals_progressed', 'deals_won', 'activities_added', 'activities_completed', 'forecast_weighted']
const FREQS = ['weekly', 'monthly', 'quarterly', 'yearly'] as const
const isActivity = (k: Kind) => k === 'activities_added' || k === 'activities_completed'
// which targets a kind can have: a count, a value in NOK, or either
const UNITS: Record<Kind, ('count' | 'value')[]> = {
  deals_added: ['count', 'value'], deals_won: ['value', 'count'], deals_progressed: ['count'],
  activities_added: ['count'], activities_completed: ['count'], forecast_weighted: ['value'],
}

/**
 * Goals (design: v.goals): progress is the count or sum of the records that match in the current interval
 * (goals_get, INS-05); pace compares it with the share of the interval gone. The design draws no way to make
 * one, so «＋ Goal» and its dialog are built in the design's language (D-41).
 */
export function Goals({ goals, error, rights, pickers, nf }: { goals: Goal[]; error: string | null; rights: Rights; pickers: Pickers; nf: NumberFormat }) {
  const t = useTranslations('insights.goals')
  const tr = useTranslations('insights')
  const te = useTranslations('common.errors')
  const [edit, setEdit] = useState<Goal | 'new' | null>(null)

  if (!rights.see || error === 'forbidden') return <div className="rounded-20 border border-line bg-surface p-6 text-center text-13 text-muted">{tr('noAccess')}</div>
  if (error) return <div className="rounded-20 border border-line bg-surface p-6 text-center text-13 text-muted">{te(error as 'failed')}</div>

  const value = (g: Goal, v: number) => (g.by_value ? money(v, nf) : formatNumber(v, nf))
  return (
    <>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr))]">
        {goals.map((g) => {
          const cur = g.current ?? 0
          const w = g.target > 0 ? Math.min(100, (cur / g.target) * 100) : 0
          const onPace = w >= (g.elapsed_pct ?? 0)
          const c = w >= 75 ? 'bg-ok' : w >= 50 ? 'bg-warn' : 'bg-alert'
          const pipe = isActivity(g.kind)
            ? (pickers.activityTypes.find((x) => x.id === g.activity_type_id)?.name ?? '—')
            : (pickers.pipelines.find((x) => x.id === g.pipeline_id)?.name ?? t('allPipelines'))
          const editable = !!g.mine || rights.configure
          const body = (
            <>
              <div className="flex justify-between gap-2"><b className="text-14">{g.name}</b><span className="text-11.5 text-muted">{t(`freq.${g.frequency}`)}</span></div>
              <span className="text-12 text-muted">{g.assignee_kind === 'company' ? t('company') : (g.assignee ?? '—')} · {pipe}</span>
              <div className="flex items-baseline gap-2"><span className="font-serif text-26 font-semibold">{value(g, cur)}</span><span className="text-12.5 text-muted">{t('of', { target: value(g, g.target) })}</span></div>
              <div className="h-[10px] overflow-hidden rounded-999 bg-tile"><div className={`h-full ${c}`} style={{ width: `${w}%` }} /></div>
              <span className={`text-11.5 font-bold ${cur === 0 ? 'text-muted' : onPace ? 'text-link' : 'text-danger'}`}>
                {cur === 0 ? t('noMatches') : onPace ? t('onPace') : t('behind', { pct: formatNumber(Math.round(100 - w), nf) })}
              </span>
            </>
          )
          const cls = 'flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4'
          return editable
            ? <button key={g.id} type="button" onClick={() => setEdit(g)} aria-label={t('editNamed', { name: g.name })} className={`${cls} cursor-pointer text-left text-14`}>{body}</button>
            : <div key={g.id} className={cls}>{body}</div>
        })}
        {goals.length === 0 ? (
          <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4">
            <b className="text-14">{t('empty')}</b>
            <span className="text-12 text-muted">{t('emptyHint')}</span>
          </div>
        ) : null}
        <button type="button" onClick={() => setEdit('new')} className="flex min-h-[120px] cursor-pointer flex-col items-center justify-center gap-1 rounded-20 border border-dashed border-line-strong bg-transparent px-[18px] py-4 text-13 font-bold">
          {t('add')}
        </button>
      </div>
      {edit ? <GoalDialog goal={edit === 'new' ? null : edit} rights={rights} pickers={pickers} onClose={() => setEdit(null)} /> : null}
    </>
  )
}

const label = 'flex flex-col gap-1 text-11.5 font-semibold text-muted'
const control = 'h-9 rounded-9 border border-line bg-canvas px-2 text-12.5 text-ink'

function GoalDialog({ goal, rights, pickers, onClose }: { goal: Goal | null; rights: Rights; pickers: Pickers; onClose: () => void }) {
  const t = useTranslations('insights.goals')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [name, setName] = useState(goal?.name ?? '')
  const [kind, setKind] = useState<Kind>(goal?.kind ?? 'deals_won')
  const [who, setWho] = useState(goal ? (goal.assignee_kind === 'company' ? 'company' : `${goal.assignee_kind}:${goal.assignee_id}`) : `staff:${rights.meId}`)
  const [pipeline, setPipeline] = useState(goal?.pipeline_id ?? '')
  const [type, setType] = useState(goal?.activity_type_id ?? '')
  const [freq, setFreq] = useState<Goal['frequency']>(goal?.frequency ?? 'monthly')
  const [unit, setUnit] = useState<'count' | 'value'>(goal ? (goal.by_value ? 'value' : 'count') : 'value')
  const [target, setTarget] = useState(goal ? String(goal.target) : '')
  const [busy, setBusy] = useState(false)
  const first = useRef<HTMLInputElement>(null)
  const units = UNITS[kind]
  const u = units.includes(unit) ? unit : units[0]!

  const closeLatest = useRef(onClose)
  closeLatest.current = onClose
  useEffect(() => {
    first.current?.focus()
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') closeLatest.current() }
    window.addEventListener('keydown', key)
    return () => window.removeEventListener('keydown', key)
  }, [])

  const n = Number(target.replace(',', '.'))
  const ok = name.trim().length > 0 && Number.isFinite(n) && n > 0 && (u === 'value' || Number.isInteger(n))
  const save = async () => {
    if (!ok) return
    const [ak, aid] = who === 'company' ? ['company', null] : (who.split(':') as ['staff' | 'team', string])
    setBusy(true)
    const r = await saveGoalAction({
      id: goal?.id ?? null,
      values: {
        name: name.trim(), kind, assignee_kind: ak, assignee_id: aid, frequency: freq,
        pipeline_id: !isActivity(kind) && pipeline ? pipeline : null,
        activity_type_id: isActivity(kind) && type ? type : null,
        target_count: u === 'count' ? n : null, target_value: u === 'value' ? n : null,
      },
    })
    setBusy(false)
    if (!r.ok) { flash(te(r.code)); return }
    flash(t('saved', { name: name.trim() }))
    onClose()
    router.refresh()
  }
  const remove = async () => {
    if (!goal) return
    setBusy(true)
    const r = await deleteGoalAction(goal.id)
    setBusy(false)
    if (!r.ok) { flash(te(r.code)); return }
    flash(t('deleted'))
    onClose()
    router.refresh()
  }

  return (
    <div onClick={onClose} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div role="dialog" aria-modal="true" aria-label={goal ? t('edit') : t('new')} onClick={(e) => e.stopPropagation()}
        className="flex max-h-[80vh] w-[520px] max-w-full flex-col gap-[10px] overflow-auto rounded-22 bg-surface px-[22px] py-5">
        <div className="flex items-center justify-between">
          <b className="font-serif text-20">{goal ? t('edit') : t('new')}</b>
          <button type="button" onClick={onClose} aria-label={t('close')} className="h-[30px] w-[30px] cursor-pointer rounded-999 border border-ink bg-transparent">×</button>
        </div>
        <label className={label}>{t('name')}<input ref={first} value={name} maxLength={120} onChange={(e) => setName(e.target.value)} className={control} /></label>
        <div className="grid gap-[10px] sm:grid-cols-2">
          <label className={label}>{t('kind')}
            <select value={kind} onChange={(e) => setKind(e.target.value as Kind)} className={control}>{KINDS.map((k) => <option key={k} value={k}>{t(`kinds.${k}`)}</option>)}</select>
          </label>
          <label className={label}>{t('assignee')}
            <select value={who} onChange={(e) => setWho(e.target.value)} className={control}>
              <option value={`staff:${rights.meId}`}>{t('me', { name: rights.meName })}</option>
              {rights.configure ? (
                <>
                  <optgroup label={t('people')}>{pickers.staff.filter((s) => s.id !== rights.meId).map((s) => <option key={s.id} value={`staff:${s.id}`}>{s.name}</option>)}</optgroup>
                  <optgroup label={t('teams')}>{pickers.teams.map((s) => <option key={s.id} value={`team:${s.id}`}>{s.name}</option>)}</optgroup>
                  <option value="company">{t('company')}</option>
                </>
              ) : null}
            </select>
          </label>
          {isActivity(kind) ? (
            <label className={label}>{t('activityType')}
              <select value={type} onChange={(e) => setType(e.target.value)} className={control}>
                <option value="">{t('allTypes')}</option>
                {pickers.activityTypes.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
              </select>
            </label>
          ) : (
            <label className={label}>{t('pipeline')}
              <select value={pipeline} onChange={(e) => setPipeline(e.target.value)} className={control}>
                <option value="">{t('allPipelines')}</option>
                {pickers.pipelines.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
              </select>
            </label>
          )}
          <label className={label}>{t('frequency')}
            <select value={freq} onChange={(e) => setFreq(e.target.value as Goal['frequency'])} className={control}>{FREQS.map((f) => <option key={f} value={f}>{t(`freq.${f}`)}</option>)}</select>
          </label>
          <label className={label}>{t('unit')}
            <select value={u} disabled={units.length < 2} onChange={(e) => setUnit(e.target.value as 'count' | 'value')} className={control}>
              {units.map((x) => <option key={x} value={x}>{x === 'count' ? t('byCount') : t('byValue')}</option>)}
            </select>
          </label>
          <label className={label}>{t('target')}<input value={target} inputMode="decimal" onChange={(e) => setTarget(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void save() }} className={control} /></label>
        </div>
        <div className="mt-1 flex flex-wrap gap-2">
          <button type="button" onClick={save} disabled={!ok || busy} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-4 text-12.5 font-bold disabled:cursor-default disabled:opacity-55">{t('save')}</button>
          <button type="button" onClick={onClose} className="h-9 cursor-pointer rounded-10 border border-line bg-transparent px-4 text-12.5 font-semibold">{t('cancel')}</button>
          <span className="flex-1" />
          {goal ? <button type="button" onClick={remove} disabled={busy} className="h-9 cursor-pointer rounded-10 border border-coral bg-transparent px-4 text-12.5 font-semibold text-rust disabled:opacity-55">{t('delete')}</button> : null}
        </div>
      </div>
    </div>
  )
}
