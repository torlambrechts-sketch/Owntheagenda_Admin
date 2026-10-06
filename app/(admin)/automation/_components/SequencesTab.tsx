'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Option, SequenceDetail } from '@/lib/data/automation'
import { delayDays, type Step } from '@/lib/data/automation-graph'
import { exitEnrollments, setWorkflowState, skipStep } from '../actions'
import { TONE, canChange, useBlockerText, useErrorText, useGo, useWords, type Rights } from './shared'
import { EnrollModal } from './EnrollModal'

const btn = 'h-[30px] cursor-pointer rounded-9 px-[11px] text-12 disabled:cursor-default disabled:opacity-50'
const small = 'h-[26px] cursor-pointer rounded-9 border border-line bg-transparent px-2 text-11.5 font-semibold disabled:opacity-50'
const STATE_TONE = { in_progress: TONE.wait, failed: TONE.fail, completed: TONE.ok, exited: TONE.draft } as const

/** Sequences (Automation.dc.html, v.sequences): the list with enrolment counts, the selected sequence's steps
 *  from its graph, and who is enrolled. Records are enrolled through a picker or a saved view. */
export function SequencesTab({ list, selected, entity, templates, views, me, rights }: {
  list: SequenceDetail[]
  selected: SequenceDetail | null
  entity: 'deal' | 'lead'
  templates: Option[]
  views: Option[]
  me: string
  rights: Rights
}) {
  const t = useTranslations('automation.seq')
  const w = useWords()
  const flash = useToast()
  const err = useErrorText()
  const blocker = useBlockerText()
  const { go } = useGo()
  const [modal, setModal] = useState<'one' | 'bulk' | null>(null)
  const [busy, setBusy] = useState(false)

  if (!selected) return <div className="rounded-20 border border-line bg-surface px-[18px] py-4 text-12.5 text-muted">{t('none')}</div>

  const steps: Step[] = selected.graph?.steps ?? []
  const tpl = (id: unknown) => templates.find((x) => x.id === id)?.name ?? '—'
  let day = 0
  const strip = steps.map((s) => {
    const d = day
    if (s.kind === 'delay') day += delayDays(s.config)
    const kind = t(`kinds.${s.kind}`)
    if (s.kind === 'delay') {
      const n = Number(s.config.amount ?? 0)
      return { s, kind, title: t(`units.${String(s.config.unit ?? 'days')}`, { n }), sub: s.config.skip_weekends ? t('skipsWeekends') : '' }
    }
    if (s.kind === 'activity') return { s, kind, title: String(s.config.subject ?? ''), sub: t('activitySub', { type: w.pick('activity', String(s.config.type ?? 'task')) }) }
    return { s, kind, title: tpl(s.config.template_id), sub: s.kind === 'email_manual' ? t('queued') : t('day', { n: Math.round(d) }) }
  })
  const stepLabel = (n: number) => {
    const s = steps[n - 1]
    if (!s) return t('finished')
    const k = s.kind === 'activity' ? w.pick('activity', String(s.config.type ?? 'task')) : t(`short.${s.kind}`)
    return t('stepN', { n, kind: k })
  }
  const active = selected.state === 'active'
  const mayChange = canChange(selected, me, rights)
  // skipping and exiting are for the person who enrolled the record, or someone who may edit others' deals (0021)
  const mayAct = (e: SequenceDetail['enrolled'][number]) => e.state === 'in_progress' && rights.seeDeals && (!!e.mine || rights.editOthers)
  const anyLive = selected.enrolled.some(mayAct)
  const grid = anyLive
    ? '[grid-template-columns:minmax(0,1.5fr)_minmax(0,1fr)_120px_110px_150px]'
    : '[grid-template-columns:minmax(0,1.5fr)_minmax(0,1fr)_120px_110px]'

  const activate = async () => {
    setBusy(true)
    const r = await setWorkflowState({ id: selected.id, state: active ? 'draft' : 'active' })
    setBusy(false)
    if (!r.ok) flash(t('refused', { reason: err(r.code, r.detail) }))
    else flash(t(active ? 'deactivated' : 'activated', { name: selected.name }))
  }
  const act = async (fn: () => Promise<{ ok: boolean; code?: string; detail?: string | null }>, ok: string) => {
    setBusy(true)
    const r = await fn()
    setBusy(false)
    flash(r.ok ? ok : err(r.code ?? 'failed', r.detail))
  }

  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(220px,260px)_minmax(0,1fr)]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        {list.map((s) => {
          const on = s.id === selected.id
          const ents = (Array.isArray(s.trigger_config.entities) ? s.trigger_config.entities : ['deal']) as string[]
          return (
            <button
              key={s.id}
              type="button"
              onClick={() => go({ tab: 'sequences', seq: s.id }, { reset: true })}
              className={`flex w-full cursor-pointer flex-col gap-[2px] border-b border-line px-[14px] py-3 text-left ${on ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <b className="text-13">{s.name}</b>
              <span className="text-11.5 text-muted">{t('sub', { what: s.description ?? t(`entities.${ents.includes('lead') ? 'lead' : 'deal'}`), n: s.counts.in_progress })}</span>
            </button>
          )
        })}
      </div>
      <div className="flex min-w-0 flex-col gap-3">
        <div className="overflow-x-auto rounded-20 border border-line bg-surface px-[18px] py-4">
          {strip.length === 0 ? <div className="text-12.5 text-muted">{t('noSteps')}</div> : null}
          <div className="flex min-w-max items-center">
            {strip.map((x, i) => (
              <div key={x.s.key} className="flex items-center">
                <div className={`flex w-[170px] flex-col gap-1 rounded-15 border-[1.5px] px-3 py-[11px] ${x.s.kind === 'email_manual' ? 'border-warn' : 'border-line'} ${x.s.kind === 'delay' ? 'bg-canvas' : x.s.kind === 'activity' ? 'bg-teal-soft' : 'bg-surface'}`}>
                  <span className="text-10 font-bold uppercase tracking-label text-muted">{x.kind}</span>
                  <b className="text-12.5 leading-[1.3]">{x.title}</b>
                  <span className="text-11 text-muted">{x.sub}</span>
                </div>
                {i < strip.length - 1 ? <span className="h-[1.5px] w-[26px] bg-line-strong" /> : null}
              </div>
            ))}
          </div>
        </div>
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-3">
            <b className="text-14">{t('enrolled')}</b>
            <div className="flex gap-[6px]">
              <button type="button" disabled={!active || !rights.seeDeals} onClick={() => setModal('one')} className={`${btn} border border-line bg-transparent font-semibold`}>{t(`enrollOne.${entity}`)}</button>
              <button type="button" disabled={!active || !rights.bulk} onClick={() => setModal('bulk')} className={`${btn} border border-ink bg-surface font-bold`}>{t('enrollBulk')}</button>
            </div>
          </div>
          {!active ? (
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-[10px] text-12.5">
              <span className="flex flex-wrap items-center gap-2">
                <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${TONE.draft}`}>{t('draft')}</span>
                <span className="text-muted">{t('draftNote')}{selected.blockers.length ? ` ${selected.blockers.map(blocker).join(' · ')}` : ''}</span>
              </span>
              {mayChange ? <button type="button" disabled={busy} onClick={activate} className={small}>{t('activate')}</button> : null}
            </div>
          ) : null}
          {selected.enrolled.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('nobody')}</div> : null}
          <div className="overflow-x-auto">
            {selected.enrolled.map((e) => (
              <div key={e.id} className={`grid min-w-[560px] items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 last:border-b-0 ${grid}`}>
                <b>{e.title ?? '—'}</b>
                <span className="text-muted">{e.state === 'completed' ? t('finished') : stepLabel(e.step)}</span>
                <span className="text-muted">{t('by', { via: t(`via.${e.via}`) })}</span>
                <span>
                  <span title={e.error ?? (e.exit_reason ? t(`exit.${e.exit_reason}`) : undefined)} className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${STATE_TONE[e.state]}`}>{t(`state.${e.state}`)}</span>
                </span>
                {anyLive ? (
                  <span className="flex justify-end gap-1">
                    {mayAct(e) ? (
                      <>
                        <button type="button" disabled={busy} onClick={() => act(() => skipStep({ id: e.id }), t('skipped'))} className={small}>{t('skip')}</button>
                        <button type="button" disabled={busy} onClick={() => act(() => exitEnrollments({ ids: [e.id] }), t('exited'))} className={small}>{t('exitOne')}</button>
                      </>
                    ) : null}
                  </span>
                ) : null}
              </div>
            ))}
          </div>
        </div>
      </div>
      {modal ? <EnrollModal mode={modal} seq={selected} entity={entity} views={views} onClose={() => setModal(null)} /> : null}
    </div>
  )
}
