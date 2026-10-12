'use client'

import { Fragment, useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import {
  CONDITIONS, CONDITIONS_AVAILABLE, EXITS, TRIGGERS, TRIGGERS_AVAILABLE, daysFrom, firstBlocker, moveStep, openRate, seqState,
  type CondKey, type ExitKey, type Sequence, type SimpleModel, type SimpleStep, type TriggerKey,
} from '@/lib/data/simple-growth-shared'
import type { RpcCode } from '@/lib/rpc'
import { windowDays, hourText, type SendTimes, type SequenceResults } from '@/lib/growth/v3'
import { saveSequence, setSequenceState } from '../actions'
import { sequenceResults, setSendWindow } from '../v3-actions'
import { EmailInsights } from './v3/EmailInsights'
import { InsertCondition } from './v3/InsertCondition'

type Draft = { id: string | null; version: number | null; name: string; model: SimpleModel }
const fromSeq = (s: Sequence): Draft => ({ id: s.id, version: s.version, name: s.name, model: s.simple })

const KIND = {
  email: { glyph: '✉', tile: 'bg-blue-bg', border: 'border-line' },
  wait: { glyph: '◷', tile: 'bg-sand', border: 'border-tile' },
  cond: { glyph: '⑂', tile: 'bg-lilac', border: 'border-tile' },
  task: { glyph: '✓', tile: 'bg-sage', border: 'border-tile' },
} as const
const select = 'h-9 rounded-9 border border-line bg-canvas text-12.5 text-ink disabled:opacity-60'
const fieldLabel = 'flex flex-col gap-1 text-11.5 font-semibold text-muted'
const stateTone = { active: 'text-link', paused: 'text-warn-ink', draft: 'text-muted' } as const

/**
 * Growth › Email and automation (GrowthMarketing.dc.html, v.email). A campaign here is a workflow of the one engine,
 * compiled by simple_sequence_save: emails are automated campaign drafts, waits are delays, conditions and «stop when» are
 * engine conditions, tasks are activities. The design edits in place, so each change is saved as it is made (a field
 * when it is left). What the engine cannot express is offered disabled with the reason; Activate stays off while
 * something blocks it — first of all, no email provider is connected. Figures are the runs and the emails' recipients.
 */
export function EmailTab({ sequences, stage, lists, emailConnected, nf, rights, product, initialResults = null, sendTimes = null }: {
  sequences: Sequence[]
  stage: { id: string; name: string } | null
  lists: { id: string; name: string }[]
  emailConnected: boolean
  nf: NumberFormat
  rights: { edit: boolean; configure: boolean }
  /** the application the best send time is computed for (0083) */
  product: string
  /** the first sequence's last 30 days per step, read with the page */
  initialResults?: SequenceResults | null
  sendTimes?: SendTimes | null
}) {
  const t = useTranslations('simpleGrowth.email')
  const t3 = useTranslations('simpleGrowth.v3')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [selId, setSelId] = useState<string | null>(sequences[0]?.id ?? null)
  const seq = sequences.find((s) => s.id === selId) ?? sequences[0] ?? null

  const [draft, setDraft] = useState<Draft | null>(seq ? fromSeq(seq) : null)
  const latest = useRef(draft)
  latest.current = draft
  const changes = useRef(0)
  const queue = useRef<Promise<void>>(Promise.resolve())

  // a new read (after a save, a refresh or another selection) replaces the draft unless an edit is on its way
  useEffect(() => {
    if (!seq) { setDraft(null); return }
    setDraft((d) => (d && d.id === seq.id && changes.current > 0 ? d : fromSeq(seq)))
  }, [seq])

  const editable = !!seq && rights.edit && (!!seq.mine || rights.configure)

  // each sequence's last 30 days per step (simple_sequence_results), read when it is first chosen; a refresh reads again
  const [results, setResults] = useState<Record<string, SequenceResults | 'failed'>>(initialResults ? { [initialResults.id]: initialResults } : {})
  const wantResults = seq && !results[seq.id] ? seq.id : null
  useEffect(() => {
    if (!wantResults) return
    let live = true
    sequenceResults({ id: wantResults }).then((r) => { if (live) setResults((m) => ({ ...m, [wantResults]: r.ok ? r.data : 'failed' })) },
      () => { if (live) setResults((m) => ({ ...m, [wantResults]: 'failed' })) })
    return () => { live = false }
  }, [wantResults])
  useEffect(() => { setResults(initialResults ? { [initialResults.id]: initialResults } : {}) }, [sequences, initialResults])
  const res = seq ? results[seq.id] ?? null : null
  // «Add condition»: the step (by index) the editor offers the condition above
  const [insertAt, setInsertAt] = useState<{ step: number; email: number } | null>(null)
  const dow = (d: number) => t3(`dow.${d}`)

  /** «Send all steps at the best time» / «Use best time»: the window the database derives, or none */
  const setWindow = (on: boolean) => {
    if (!seq) return
    const id = seq.id
    start(async () => {
      const r = await setSendWindow({ id, product, on })
      if (!r.ok) { flash(r.detail === 'no_best_time' ? t3('best.notYet', { min: sendTimes?.min ?? 20, days: sendTimes?.days ?? 90 }) : te(r.code)); return }
      setResults((m) => { const x = m[id]; return x && x !== 'failed' ? { ...m, [id]: { ...x, send_window: r.window } } : m })
      flash(r.window ? t3('best.toastOn', { days: windowDays(r.window.days, dow), hour: hourText(r.window.hour) }) : t3('best.toastOff'))
      router.refresh()
    })
  }
  const errorText = (r: { code: RpcCode; detail?: string | null }) =>
    r.detail === 'trigger.not_available' ? t('errors.trigger') : te(r.code)

  /** Save the latest draft after the saves before it; adopt the campaign ids of new emails from the answer. */
  const commit = (next: Draft) => {
    setDraft(next)
    latest.current = next
    changes.current += 1
    queue.current = queue.current.then(async () => {
      const d = latest.current
      if (!d) return
      const mine = changes.current
      const r = await saveSequence({ id: d.id, version: d.version, name: d.name, trigger: d.model.trigger, stage_id: d.model.stage_id ?? null,
        list: d.model.list ?? null, exit: d.model.exit, steps: d.model.steps })
      if (!r.ok) {
        changes.current = 0
        flash(errorText(r))
        router.refresh()
        return
      }
      const cur = latest.current
      const merged: Draft = mine === changes.current || !cur
        ? { id: r.id, version: r.version, name: d.name, model: r.simple }
        : { ...cur, id: r.id, version: r.version, model: { ...cur.model, steps: cur.model.steps.map((s, i) => {
            const got = r.simple.steps[i]
            return s.kind === 'email' && !s.campaign_id && got?.kind === 'email' ? { ...s, campaign_id: got.campaign_id } : s
          }) } }
      latest.current = merged
      setDraft(merged)
      if (mine === changes.current) changes.current = 0
      router.refresh()
    })
  }
  const setModel = (patch: Partial<SimpleModel>) => draft && commit({ ...draft, model: { ...draft.model, ...patch } })
  const setSteps = (steps: SimpleStep[]) => setModel({ steps })

  const newSequence = () => start(async () => {
    const r = await saveSequence({ id: null, version: null, name: t('defaults.name'), trigger: 'form_submitted', stage_id: null, list: null, exit: 'reply_unsub',
      steps: [{ kind: 'email', text: t('defaults.firstEmail') }] })
    if (!r.ok) { flash(errorText(r)); return }
    setSelId(r.id)
    setDraft({ id: r.id, version: r.version, name: t('defaults.name'), model: r.simple })
    router.refresh()
  })

  const toggleActive = () => {
    if (!seq) return
    const active = seq.state === 'active'
    start(async () => {
      const r = await setSequenceState({ id: seq.id, state: active ? 'draft' : 'active' })
      if (!r.ok) { flash(r.detail && t.has(`blockers.${r.detail}`) ? t(`blockers.${r.detail}`) : te(r.code)); return }
      flash(active ? t('toast.paused') : t('toast.active'))
      router.refresh()
    })
  }

  const blocker = seq ? firstBlocker(seq.blockers) : null
  const active = seq?.state === 'active'
  const canActivate = editable && (active || !blocker)
  const reason = !seq ? null
    : !editable ? t('readOnly')
    : blocker ? (active ? t('runningBlocked', { reason: t(`blockers.${t.has(`blockers.${blocker}`) ? blocker : 'other'}`) }) : t(`blockers.${t.has(`blockers.${blocker}`) ? blocker : 'other'}`))
    : null
  const listName = (id: string | null | undefined) => (id ? lists.find((l) => l.id === id)?.name ?? t('lists.unknown') : null)

  return (
    <>
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr))]">
      <div className="flex flex-col gap-[10px]">
        <button
          type="button"
          onClick={newSequence}
          disabled={!rights.edit || pending}
          title={rights.edit ? undefined : t('readOnly')}
          className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary text-13 font-bold disabled:cursor-not-allowed disabled:opacity-50"
        >
          {t('new')}
        </button>
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          {sequences.map((s) => {
            const st = seqState(s)
            const open = openRate(s.emails)
            return (
              <button
                key={s.id}
                type="button"
                onClick={() => { setSelId(s.id); changes.current = 0; setDraft(fromSeq(s)); setInsertAt(null) }}
                aria-pressed={seq?.id === s.id}
                className={`flex w-full cursor-pointer flex-col gap-[3px] border-0 border-b border-line px-[14px] py-3 text-left ${seq?.id === s.id ? 'bg-highlight' : 'bg-transparent'}`}
              >
                <span className="flex justify-between gap-2">
                  <b className="text-13">{s.name}</b>
                  <span className={`text-11 font-bold ${stateTone[st]}`}>{t(`states.${st}`)}</span>
                </span>
                <span className="text-11.5 text-muted">
                  {t('row', { steps: s.simple.steps.length, enrolled: formatNumber(s.enrolled, nf), open: open === null ? '—' : percent(Math.round(open), nf) })}
                </span>
              </button>
            )
          })}
          {sequences.length === 0 ? <div className="px-[14px] py-4 text-12.5 text-muted">{t('empty')}</div> : null}
        </div>
      </div>

      <div className="flex min-w-0 flex-col gap-3 min-[874px]:[grid-column:span_2]">
        {seq && draft ? (
          <>
            <div className="flex flex-col gap-3 rounded-20 border border-line bg-surface px-[18px] py-4">
              <div className="flex flex-wrap items-center justify-between gap-[10px]">
                <NameInput value={draft.name} label={t('name')} disabled={!editable} onCommit={(name) => commit({ ...draft, name })} />
                <button
                  type="button"
                  onClick={toggleActive}
                  disabled={!canActivate || pending}
                  aria-describedby={reason ? 'seq-reason' : undefined}
                  className={`h-9 flex-none cursor-pointer whitespace-nowrap rounded-10 border border-ink px-[14px] text-12.5 font-bold disabled:cursor-not-allowed disabled:opacity-50 ${active ? 'bg-surface' : 'bg-primary'}`}
                >
                  {active ? t('pause') : t('activate')}
                </button>
              </div>
              {reason ? <div id="seq-reason" className="-mt-1 text-12 text-muted">{reason}</div> : null}
              <div className="grid gap-[10px] [grid-template-columns:repeat(auto-fit,minmax(200px,1fr))]">
                <label className={fieldLabel}>{t('trigger')}
                  <select
                    value={draft.model.trigger}
                    disabled={!editable}
                    onChange={(e) => {
                      const k = TRIGGERS.find((x) => x === e.target.value)
                      if (k) setModel({ trigger: k, stage_id: k === 'deal_stage' ? draft.model.stage_id ?? stage?.id ?? null : null })
                    }}
                    className={select}
                  >
                    {TRIGGERS.map((k: TriggerKey) => {
                      const off = !TRIGGERS_AVAILABLE.includes(k) || (k === 'deal_stage' && !stage && !draft.model.stage_id)
                      const name = t(`triggers.${k}`, { stage: stage?.name ?? t('proposalSent') })
                      return <option key={k} value={k} disabled={off}>{off ? t('unavailable', { name, reason: t(`triggerWhy.${k}`) }) : name}</option>
                    })}
                  </select>
                </label>
                <label className={fieldLabel}>{t('list')}
                  <select
                    value={draft.model.list ?? ''}
                    disabled={!editable}
                    onChange={(e) => setModel({ list: e.target.value || null, steps: e.target.value ? draft.model.steps : draft.model.steps.filter((s) => !(s.kind === 'cond' && s.cond === 'on_list')) })}
                    className={select}
                  >
                    <option value="">{t('lists.anyone')}</option>
                    {draft.model.list && !lists.some((l) => l.id === draft.model.list) ? <option value={draft.model.list}>{listName(draft.model.list)}</option> : null}
                    {lists.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
                  </select>
                </label>
                <label className={fieldLabel}>{t('exit')}
                  <select
                    value={draft.model.exit}
                    disabled={!editable}
                    onChange={(e) => { const k = EXITS.find((x) => x === e.target.value); if (k) setModel({ exit: k }) }}
                    className={select}
                  >
                    {EXITS.map((k: ExitKey) => <option key={k} value={k}>{t(`exits.${k}`)}</option>)}
                  </select>
                </label>
              </div>
            </div>

            <div className="flex flex-col items-stretch">
              {draft.model.steps.map((s, i) => (
                <Fragment key={`${i}-${s.kind}-${s.kind === 'email' ? s.campaign_id ?? '' : ''}`}>
                {insertAt && insertAt.step === i && s.kind === 'email' && editable ? (
                  <InsertCondition
                    email={insertAt.email}
                    condition={t('conditions.employees_missing')}
                    onCancel={() => setInsertAt(null)}
                    onAdd={() => {
                      setInsertAt(null)
                      if (draft.model.steps.length >= 30) { flash(te('invalid')); return }
                      setSteps([...draft.model.steps.slice(0, i), { kind: 'cond', cond: 'employees_missing' }, ...draft.model.steps.slice(i)])
                      flash(t3('insert.added', { n: insertAt.email }))
                    }}
                  />
                ) : null}
                <StepCard
                  step={s}
                  i={i}
                  count={draft.model.steps.length}
                  editable={editable}
                  hasList={!!draft.model.list}
                  stats={s.kind === 'email' ? seq.emails.find((e) => e.campaign_id === s.campaign_id)?.stats ?? null : null}
                  nf={nf}
                  onChange={(next) => setSteps(draft.model.steps.map((x, j) => (j === i ? next : x)))}
                  onMove={(by) => setSteps(moveStep(draft.model.steps, i, by))}
                  onDelete={() => { if (draft.model.steps.length > 1) setSteps(draft.model.steps.filter((_, j) => j !== i)); else flash(t('lastStep')) }}
                />
                </Fragment>
              ))}
              {editable ? (
                <div className="flex flex-wrap justify-center gap-[6px] pb-[14px] pt-1">
                  {(['email', 'wait', 'cond', 'task'] as const).map((k) => (
                    <button
                      key={k}
                      type="button"
                      disabled={draft.model.steps.length >= 30}
                      onClick={() => setSteps([...draft.model.steps,
                        k === 'email' ? { kind: 'email', text: t('defaults.newEmail') }
                          : k === 'wait' ? { kind: 'wait', days: 2 }
                            : k === 'cond' ? { kind: 'cond', cond: 'not_paying' }
                              : { kind: 'task', text: t('defaults.task') }])}
                      className="h-8 flex-none cursor-pointer whitespace-nowrap rounded-999 border border-dashed border-ink bg-surface px-[13px] text-12 font-semibold"
                    >
                      ＋ {t(`kinds.${k}`)}
                    </button>
                  ))}
                </div>
              ) : null}
            </div>
            {!emailConnected ? <div className="text-12 text-muted">{t('nothingSends')}</div> : null}
          </>
        ) : (
          <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center text-13 text-muted">
            {rights.edit ? t('emptyEditor') : t('emptyEditorNoRight')}
          </div>
        )}
      </div>
    </div>
    {seq && draft ? (
      <EmailInsights
        name={draft.name}
        results={res && res !== 'failed' ? res : null}
        loading={!res}
        steps={draft.model.steps}
        times={sendTimes}
        nf={nf}
        editable={editable}
        pending={pending}
        onAddCondition={(step, email) => setInsertAt({ step, email })}
        onWindow={setWindow}
      />
    ) : null}
    </>
  )
}

/** The campaign's name: typed locally, saved when the field is left (a refresh meanwhile does not undo the typing). */
function NameInput({ value, label, disabled, onCommit }: { value: string; label: string; disabled: boolean; onCommit: (v: string) => void }) {
  const [text, setText] = useState(value)
  useEffect(() => setText(value), [value])
  return (
    <input
      value={text}
      disabled={disabled}
      aria-label={label}
      maxLength={120}
      onChange={(e) => setText(e.target.value)}
      onBlur={() => { if (text.trim() && text.trim() !== value) onCommit(text.trim()); else setText(value) }}
      onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
      className="h-[38px] min-w-0 flex-[1_1_240px] rounded-10 border border-line bg-canvas px-[11px] font-serif text-18 font-semibold"
    />
  )
}

function StepCard({ step, i, count, editable, hasList, stats, nf, onChange, onMove, onDelete }: {
  step: SimpleStep; i: number; count: number; editable: boolean; hasList: boolean
  stats: Sequence['emails'][number]['stats']; nf: NumberFormat
  onChange: (s: SimpleStep) => void; onMove: (by: -1 | 1) => void; onDelete: () => void
}) {
  const t = useTranslations('simpleGrowth.email')
  const flash = useToast()
  const k = KIND[step.kind]
  const shown = step.kind === 'wait' ? t('waitText', { n: step.days }) : step.kind === 'cond' ? '' : step.text
  const [text, setText] = useState(shown)
  useEffect(() => setText(shown), [shown])
  const input = 'h-[34px] rounded-9 border border-line bg-canvas px-[10px] text-13 font-semibold disabled:opacity-70'
  const leave = () => {
    if (text === shown) return
    if (step.kind === 'wait') {
      const d = daysFrom(text)
      if (d === null) { flash(t('waitInvalid')); setText(shown); return }
      if (d !== step.days) onChange({ kind: 'wait', days: d }); else setText(shown)
    } else if (step.kind === 'email' || step.kind === 'task') {
      if (!text.trim()) { setText(shown); return }
      onChange({ ...step, text: text.trim() })
    }
  }
  const small = 'h-[22px] w-[26px] cursor-pointer rounded-6 border bg-transparent text-10 disabled:cursor-not-allowed disabled:opacity-40'

  return (
    <div className="flex flex-col items-center">
      <div className={`flex w-full items-start gap-3 rounded-16 border-[1.5px] bg-surface px-[14px] py-3 ${k.border}`}>
        <span className={`flex h-[34px] w-[34px] flex-none items-center justify-center rounded-10 text-14 ${k.tile}`} aria-hidden="true">{k.glyph}</span>
        <div className="flex min-w-0 flex-1 flex-col gap-[6px]">
          <span className="text-10.5 font-bold uppercase tracking-label text-muted">{t('stepLabel', { i: i + 1, kind: t(`kinds.${step.kind}`) })}</span>
          {step.kind === 'cond' ? (
            <select
              value={step.cond}
              disabled={!editable}
              aria-label={t('stepLabel', { i: i + 1, kind: t('kinds.cond') })}
              onChange={(e) => { const c = CONDITIONS.find((x) => x === e.target.value); if (c) onChange({ kind: 'cond', cond: c }) }}
              className={input}
            >
              {CONDITIONS.map((c: CondKey) => {
                const off = !CONDITIONS_AVAILABLE.includes(c) || (c === 'on_list' && !hasList)
                return <option key={c} value={c} disabled={off}>{off ? t('unavailable', { name: t(`conditions.${c}`), reason: t(`conditionWhy.${c === 'on_list' ? 'on_list' : 'opened_last'}`) }) : t(`conditions.${c}`)}</option>
              })}
            </select>
          ) : (
            <input
              value={text}
              disabled={!editable}
              aria-label={t('stepLabel', { i: i + 1, kind: t(`kinds.${step.kind}`) })}
              maxLength={200}
              onChange={(e) => setText(e.target.value)}
              onBlur={leave}
              onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
              className={input}
            />
          )}
          {step.kind === 'email' ? (
            <span className="text-11.5 text-muted">
              {t('emailStats', {
                sent: formatNumber(stats?.sent ?? 0, nf),
                open: stats ? (stats.unique_opens === null ? '—' : formatNumber(stats.unique_opens, nf)) : formatNumber(0, nf),
                click: stats ? (stats.unique_clicks === null ? '—' : formatNumber(stats.unique_clicks, nf)) : formatNumber(0, nf),
              })}
            </span>
          ) : null}
        </div>
        {editable ? (
          <span className="flex flex-col gap-[3px]">
            <button type="button" onClick={() => onMove(-1)} disabled={i === 0} aria-label={t('up', { i: i + 1 })} className={`${small} border-line`}>▲</button>
            <button type="button" onClick={() => onMove(1)} disabled={i === count - 1} aria-label={t('down', { i: i + 1 })} className={`${small} border-line`}>▼</button>
            <button type="button" onClick={onDelete} aria-label={t('remove', { i: i + 1 })} className={`${small} border-coral text-11 text-rust`}>×</button>
          </span>
        ) : null}
      </div>
      <span className="h-[14px] w-[1.5px] bg-line-strong" />
    </div>
  )
}
