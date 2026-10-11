'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { AREAS, EXP_STAGES, OUTCOMES, ice, type Area, type Experiments, type ExpStage } from '@/lib/growth/playbook'
import { addExperiment, archiveExperiment, callExperiment, moveExperiment } from '../../playbook-actions'
import type { Result } from '../../actions'

/** the columns' head rules (expCols[].c) */
const RULE: Record<ExpStage, string> = { backlog: '#F2EAD6', ready: '#F3E2C9', running: '#FBEBBE', done: '#CFE7E4' }
const OUTCOME_TONE = { win: 'text-link', no_effect: 'text-muted', loss: 'text-danger' } as const
const SCORES = Array.from({ length: 10 }, (_, i) => i + 1)
const field = 'h-9 rounded-10 border border-line bg-canvas text-12.5 text-ink'

type Item = Experiments['items'][number]

/**
 * Marketing campaigns › Experiments (GrowthPlaybook.dc.html, v.experiments) on growth_experiments_get (0076): hypotheses
 * with ICE, Backlog → Ready → Running → Done. A running test shows when it started: lift, confidence and sample size need
 * a testing tool Sentral is not connected to (V-GR2-35). «Call result» records Win, No effect or Loss with a line on what
 * was seen. Adding and moving need Campaigns › Add; the database checks it.
 */
export function ExperimentsView({ d, nf, product, canAdd }: { d: Experiments; nf: NumberFormat; product: string; canAdd: boolean }) {
  const t = useTranslations('simpleGrowth.playbook.experiments')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [h, setH] = useState('')
  const [area, setArea] = useState<Area>('signup')
  const [score, setScore] = useState({ impact: 5, confidence: 5, ease: 5 })

  const add = () => {
    if (h.trim().length < 3) return
    start(async () => {
      const r = await addExperiment({ product, hypothesis: h.trim(), area, ...score })
      if (!r.ok) { flash(te(r.code)); return }
      setH('')
      flash(t('added'))
      router.refresh()
    })
  }

  return (
    <div className="flex flex-col gap-3">
      <form className="flex flex-wrap items-center gap-2 rounded-16 border border-line bg-surface px-3 py-[10px]" onSubmit={(e) => { e.preventDefault(); add() }}>
        <input value={h} onChange={(e) => setH(e.target.value)} placeholder={t('placeholder')} aria-label={t('hypothesis')} maxLength={300} disabled={!canAdd}
          className={`${field} min-w-0 flex-[1_1_300px] px-[11px] text-13`} />
        <select value={area} onChange={(e) => setArea(e.target.value as Area)} aria-label={t('area')} disabled={!canAdd} className={`${field} px-2`}>
          {AREAS.map((a) => <option key={a} value={a}>{t(`areas.${a}`)}</option>)}
        </select>
        {(['impact', 'confidence', 'ease'] as const).map((k) => (
          <label key={k} className="flex items-center gap-1 text-11.5 font-bold text-muted" title={t(`ice.${k}`)}>
            {t(`ice.${k}Short`)}
            <select value={score[k]} onChange={(e) => setScore({ ...score, [k]: Number(e.target.value) })} aria-label={t(`ice.${k}`)} disabled={!canAdd}
              className={`${field} px-1`}>
              {SCORES.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </label>
        ))}
        <button type="submit" disabled={pending || !canAdd || h.trim().length < 3}
          className="h-9 cursor-pointer whitespace-nowrap rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold text-ink disabled:cursor-default">
          {t('add')}
        </button>
        <span className="text-12 text-muted">{t('pace', { running: d.running, called: d.called_30 })}</span>
      </form>

      <div className="flex items-start gap-[10px] overflow-x-auto pb-[6px]">
        {EXP_STAGES.map((stage) => {
          const cards = d.items.filter((x) => x.stage === stage)
          return (
            <section key={stage} className="flex min-h-[240px] flex-[1_0_240px] flex-col gap-2 rounded-18 bg-tile p-2" aria-label={t(`stages.${stage}`)}>
              <div className="flex justify-between px-[6px] pb-2 pt-[6px]" style={{ borderBottom: `3px solid ${RULE[stage]}` }}>
                <b className="text-13">{t(`stages.${stage}`)}</b>
                <span className="text-12 text-muted">{cards.length}</span>
              </div>
              {stage === 'backlog' && !d.items.length ? <p className="m-0 px-[6px] text-12 leading-[1.45] text-muted">{t('empty')}</p> : null}
              {cards.map((x) => <ExpCard key={x.id} x={x} nf={nf} canAdd={canAdd} />)}
            </section>
          )
        })}
      </div>
    </div>
  )
}

function ExpCard({ x, nf, canAdd }: { x: Item; nf: NumberFormat; canAdd: boolean }) {
  const t = useTranslations('simpleGrowth.playbook.experiments')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [calling, setCalling] = useState(false)
  const [outcome, setOutcome] = useState<(typeof OUTCOMES)[number]>('win')
  const [note, setNote] = useState('')
  const run = (f: () => Promise<Result>, done: string) => start(async () => {
    const r = await f()
    if (!r.ok) { flash(te(r.code)); return }
    setCalling(false)
    flash(done)
    router.refresh()
  })
  const back: ExpStage | null = x.stage === 'ready' ? 'backlog' : x.stage === 'running' ? 'ready' : x.stage === 'done' ? 'running' : null
  const fwd = () => {
    if (x.stage === 'backlog') run(() => moveExperiment({ id: x.id, stage: 'ready' }), t('movedTo', { stage: t('stages.ready') }))
    else if (x.stage === 'ready') run(() => moveExperiment({ id: x.id, stage: 'running' }), t('movedTo', { stage: t('stages.running') }))
    else if (x.stage === 'running') setCalling(true)
    else run(() => archiveExperiment({ id: x.id }), t('archived'))
  }
  const day = (iso: string) => format.dateTime(new Date(iso), { day: 'numeric', month: 'short', timeZone: 'Europe/Oslo' })
  const days = x.started_at ? Math.max(1, Math.floor((Date.now() - Date.parse(x.started_at)) / 86_400_000) + 1) : null
  const btn = 'h-6 cursor-pointer rounded-7 text-11 text-ink disabled:cursor-default disabled:opacity-40'
  return (
    <div className="flex flex-col gap-[6px] rounded-14 border border-line bg-surface px-[11px] py-[10px]">
      <b className="text-12.5 leading-[1.35] [overflow-wrap:anywhere]">{x.hypothesis}</b>
      <span className="text-11.5 text-muted">{t(`areas.${x.area}`)}{x.owner ? ` · ${x.owner}` : ''}</span>
      <span className="flex flex-wrap gap-1">
        {(['impact', 'confidence', 'ease'] as const).map((k) => (
          <span key={k} className="rounded-6 bg-tile px-[7px] py-[2px] text-10.5 font-bold" title={t(`ice.${k}`)}>{t(`ice.${k}Short`)} {x[k]}</span>
        ))}
        <span className="rounded-6 bg-ink px-[7px] py-[2px] text-10.5 font-bold text-highlight">{t('iceScore', { n: formatNumber(ice(x), nf, Number.isInteger(ice(x)) ? 0 : 1) })}</span>
      </span>
      {x.stage === 'running' && x.started_at && days !== null ? <span className="text-11.5">{t('runningSince', { date: day(x.started_at), days })}</span> : null}
      {x.stage === 'done' && x.outcome ? (
        <span className={`text-11.5 font-bold ${OUTCOME_TONE[x.outcome]}`}>{t(`outcomes.${x.outcome}`)}{x.note ? ` · ${x.note}` : ''}</span>
      ) : null}
      {calling ? (
        <form className="flex flex-col gap-[6px] rounded-10 bg-canvas p-2"
          onSubmit={(e) => { e.preventDefault(); run(() => callExperiment({ id: x.id, outcome, note }), t('called')) }}>
          <span className="flex flex-wrap gap-1" role="radiogroup" aria-label={t('callLabel')}>
            {OUTCOMES.map((o) => (
              <button key={o} type="button" role="radio" aria-checked={outcome === o} onClick={() => setOutcome(o)}
                className={`${btn} border px-2 ${outcome === o ? 'border-ink bg-highlight font-bold' : 'border-line bg-surface'}`}>{t(`outcomes.${o}`)}</button>
            ))}
          </span>
          <input value={note} onChange={(e) => setNote(e.target.value)} maxLength={200} placeholder={t('notePlaceholder')} aria-label={t('notePlaceholder')}
            className="h-[30px] min-w-0 rounded-8 border border-line bg-surface px-2 text-12 text-ink" />
          <span className="flex justify-end gap-1">
            <button type="button" onClick={() => setCalling(false)} className={`${btn} border border-line bg-transparent px-[9px]`}>{t('cancel')}</button>
            <button type="submit" disabled={pending} className={`${btn} border border-ink bg-primary px-[9px] font-bold`}>{t('save')}</button>
          </span>
        </form>
      ) : (
        <div className="flex justify-end gap-1">
          <button type="button" aria-label={t('back')} title={t('back')} disabled={pending || !back || !canAdd}
            onClick={() => back && run(() => moveExperiment({ id: x.id, stage: back }), t('movedTo', { stage: t(`stages.${back}`) }))}
            className={`${btn} w-[26px] border border-line bg-transparent`}>←</button>
          <button type="button" disabled={pending || !canAdd} onClick={fwd}
            className={`${btn} whitespace-nowrap border border-ink bg-surface px-[9px] font-bold`}>
            {x.stage === 'running' ? t('call') : x.stage === 'done' ? t('archive') : t('next')}
          </button>
        </div>
      )}
    </div>
  )
}
