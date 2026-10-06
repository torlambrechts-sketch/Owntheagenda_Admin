'use client'

import { Fragment, useMemo, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Base, Pickers, WorkflowDetail } from '@/lib/data/automation'
import {
  errorTarget, findStep, insertStep, makeStep, nodeFamily, removeStep, sameSlot, setConfig, slotAfter, type Graph, type ListRef, type Slot, type Step,
} from '@/lib/data/automation-graph'
import { saveWorkflow, setWorkflowState } from '../actions'
import { BuilderPanel, type Trigger } from './BuilderPanel'
import { useNodeText } from './builder-text'
import { TONE, canChange, useBlockerText, useErrorText, useGo, useWords, type Rights } from './shared'

const FAMILY = {
  trigger: { g: '⚡', bg: 'bg-primary' },
  cond: { g: '⧩', bg: 'bg-blue-bg' },
  delay: { g: '◷', bg: 'bg-sand' },
  wait: { g: '⌛', bg: 'bg-sand' },
  branch: { g: '⑂', bg: 'bg-lilac' },
  action: { g: '▶', bg: 'bg-sage' },
  hook: { g: '⇢', bg: 'bg-apricot' },
} as const

/** The builder (Automation.dc.html, v.builder): the canvas drawn from the stored graph, the trigger node from
 *  trigger_type and trigger_config, and the configuration panel. Edits stay a draft until Save publishes a
 *  new version (workflow_save validates it; a refusal points at the step and field). */
export function BuilderTab({ wf, base, pickers, me, rights }: { wf: WorkflowDetail | null; base: Base; pickers: Pickers; me: string; rights: Rights }) {
  const t = useTranslations('automation.builder')
  const w = useWords()
  const flash = useToast()
  const err = useErrorText()
  const blocker = useBlockerText()
  const { go } = useGo()
  const original = useMemo<Graph>(() => wf?.graph ?? { steps: [] }, [wf])
  const originalTrigger = useMemo<Trigger>(() => ({ type: wf?.trigger_type === 'date' || wf?.trigger_type === 'product_event' ? wf.trigger_type : 'event', config: wf?.trigger_config ?? {} }), [wf])
  const [graph, setGraph] = useState<Graph>(original)
  const [trigger, setTrigger] = useState<Trigger>(originalTrigger)
  const [selected, setSelected] = useState<string>('trigger')
  const [insertAt, setInsertAt] = useState<Slot | null>(null)
  const [bad, setBad] = useState<{ key: string; field: string | null } | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const labelMap = useMemo(() => new Map(pickers.orgLabels.map((l) => [l.id, l.name])), [pickers.orgLabels])
  const entity = trigger.type === 'product_event' ? 'organization' : String(trigger.config.entity ?? 'deal')
  const text = useNodeText(entity, base, pickers, labelMap)

  if (!wf) {
    return (
      <div className="rounded-20 border border-line bg-surface px-[18px] py-4 text-12.5 text-muted">
        {t('none')} <button type="button" onClick={() => go({ tab: 'templates' }, { reset: true })} className="cursor-pointer border-none bg-transparent p-0 text-12.5 font-bold text-link">{t('toTemplates')}</button>
      </div>
    )
  }

  const may = canChange(wf, me, rights)
  const dirty = JSON.stringify(graph) !== JSON.stringify(original) || JSON.stringify(trigger) !== JSON.stringify(originalTrigger)
  const active = wf.state === 'active'
  const shared = wf.activation_scope === 'everyone' ? t('sharedEveryone') : wf.activation_scope === 'owner' ? t('sharedOwner')
    : t('sharedWith', { names: wf.activation.map((a) => a.name).filter(Boolean).join(', ') || '—' })

  const add = (kind: string) => {
    const slot = insertAt ?? (selected === 'trigger' ? { list: [], index: 0 } : slotAfter(graph, selected)) ?? { list: [], index: graph.steps.length }
    const step = makeStep(graph, kind)
    setGraph(insertStep(graph, slot, step))
    setSelected(step.key)
    setInsertAt(null)
    flash(t('added'))
  }
  const save = async () => {
    setBusy(true); setError(null); setBad(null)
    const r = await saveWorkflow({ id: wf.id, version: wf.version, trigger: { trigger_type: trigger.type, trigger_config: trigger.config }, graph })
    setBusy(false)
    if (!r.ok) {
      const target = errorTarget(r.detail)
      if (target.key && findStep(graph, target.key)) { setSelected(target.key); setBad({ key: target.key, field: target.field }) }
      else if (r.detail?.startsWith('trigger')) { setSelected('trigger'); setBad({ key: 'trigger', field: r.detail.split('.')[1] ?? null }) }
      setError(err(r.code, r.detail))
      return
    }
    flash(t('saved', { n: r.graphVersion }))
  }
  const toggle = async () => {
    setBusy(true)
    const r = await setWorkflowState({ id: wf.id, state: active ? 'draft' : 'active' })
    setBusy(false)
    if (!r.ok) flash(t('refused', { reason: err(r.code, r.detail) }))
    else flash(t(active ? 'deactivated' : 'activated'))
  }

  const node = (s: Step | 'trigger', small = false) => {
    const key = s === 'trigger' ? 'trigger' : s.key
    const fam = s === 'trigger' ? FAMILY.trigger : FAMILY[nodeFamily(s.kind)]
    const kind = s === 'trigger' ? t('kinds.trigger') : t(`kinds.${nodeFamily(s.kind)}`)
    const tx = s === 'trigger' ? triggerNode() : text(s)
    const on = selected === key
    const wrong = bad?.key === key
    return (
      <button
        key={key}
        type="button"
        onClick={() => { setSelected(key); setInsertAt(null) }}
        aria-pressed={on}
        className={`flex cursor-pointer items-start text-left ${small ? 'mb-2 w-full gap-2 rounded-14 px-[11px] py-[10px]' : 'w-[min(380px,100%)] gap-[10px] rounded-16 px-[14px] py-3'} border-[1.5px] ${wrong ? 'border-danger' : on ? 'border-ink' : 'border-line'} ${on && !small ? 'bg-highlight' : 'bg-surface'}`}
      >
        <span className={`flex flex-none items-center justify-center ${small ? 'h-[26px] w-[26px] rounded-8 text-12' : 'h-[30px] w-[30px] rounded-9 text-13'} ${fam.bg}`}>{fam.g}</span>
        <span className={`flex min-w-0 flex-col ${small ? '' : 'gap-[2px]'}`}>
          <span className={`${small ? 'text-10' : 'text-10.5'} font-bold uppercase tracking-label text-muted`}>{kind}</span>
          <b className={small ? 'text-12.5' : 'text-13'}>{tx.title}</b>
          {tx.sub ? <span className={`${small ? 'text-11.5' : 'text-12'} text-muted`}>{tx.sub}</span> : null}
          {'warn' in tx && typeof tx.warn === 'string' ? <span className={`${small ? 'text-11.5' : 'text-12'} font-semibold text-danger`}>{tx.warn}</span> : null}
        </span>
      </button>
    )
  }
  function triggerNode() {
    const c = trigger.config
    const groups = w.groups(c.groups, labelMap).filter(Boolean).join(` ${w.t('or')} `)
    const ent = String(c.entity ?? '')
    if (trigger.type === 'event') {
      const fields = Array.isArray(c.fields) && c.fields.length ? w.t('trigger.fields', { fields: c.fields.map((f) => w.pick('fields', String(f))).join(', ') }) : ''
      return {
        title: w.t('trigger.event', { entity: w.pick('entity', ent), event: w.pick('event', String(c.event ?? '')) }),
        sub: [fields, groups].filter(Boolean).join(' · ') || t('anyRecord', { entity: w.pick('entityLower', ent) }),
      }
    }
    if (trigger.type === 'date') {
      const off = Number(c.offset_days ?? 0)
      return {
        title: t('triggerTitle.date', { entity: w.pick('entityLower', ent) }),
        sub: [w.t('trigger.dateWhen', { n: Math.abs(off), date: w.pick('dates', String(c.date ?? '')), when: off > 0 ? 'after' : off < 0 ? 'before' : 'on' }), groups].filter(Boolean).join(' · '),
      }
    }
    const data = c.data && typeof c.data === 'object' ? Object.entries(c.data).map(([k, v]) => `${w.pick('fields', k)} = ${String(v)}`) : []
    return { title: t('triggerTitle.product_event'), sub: [String(c.kind ?? '') || t('noKind'), ...data].join(' · ') }
  }
  const plus = (slot: Slot) => {
    const on = sameSlot(insertAt, slot)
    return (
      <div className="flex flex-col items-center">
        <span className="h-3 w-[1.5px] bg-line-strong" />
        <button type="button" disabled={!may} aria-label={t('insertHere')} aria-pressed={on} onClick={() => setInsertAt(on ? null : slot)}
          className={`h-6 w-6 cursor-pointer rounded-999 border p-0 text-13 leading-none disabled:cursor-default ${on ? 'border-ink bg-highlight' : 'border-line-strong bg-surface'}`}>＋</button>
        <span className="h-3 w-[1.5px] bg-line-strong" />
      </div>
    )
  }
  const branch = (s: Step, i: number, ref: ListRef) => {
    const cond = w.groups(s.config.groups, labelMap).filter(Boolean)
    const paths = [
      { side: 'then' as const, label: cond.length ? t('ifLabel', { cond: cond.join(` ${w.t('or')} `) }) : t('ifEmpty'), bg: 'bg-ok-bg' },
      { side: 'else' as const, label: t('elseLabel'), bg: 'bg-tile' },
    ]
    return (
      <div className="grid w-full grid-cols-1 gap-[14px] sm:grid-cols-2">
        {paths.map((p) => {
          const list = s[p.side] ?? []
          const slot = { list: [...ref, i, p.side], index: list.length }
          const on = sameSlot(insertAt, slot)
          return (
            <div key={p.side} className="flex flex-col items-center rounded-16 border border-dashed border-line-strong bg-[rgba(255,253,246,.7)] p-[10px]">
              <button type="button" onClick={() => { setSelected(s.key); setInsertAt(null) }}
                className={`mb-2 cursor-pointer rounded-999 border-none px-[10px] py-[3px] text-11 font-bold ${p.bg} ${selected === s.key ? 'outline outline-[1.5px] outline-ink' : ''} ${bad?.key === s.key ? 'outline outline-[1.5px] outline-danger' : ''}`}>
                {p.label}
              </button>
              {list.map((x, j) => (x.kind === 'if_else' ? <div key={x.key} className="mb-2 w-full">{branch(x, j, [...ref, i, p.side])}</div> : node(x, true)))}
              <button type="button" disabled={!may} aria-pressed={on} onClick={() => setInsertAt(on ? null : slot)}
                className={`h-[26px] cursor-pointer rounded-999 border border-dashed px-[10px] text-11.5 disabled:cursor-default ${on ? 'border-ink bg-highlight' : 'border-line-strong bg-surface'}`}>{t('plusStep')}</button>
            </div>
          )
        })}
      </div>
    )
  }

  const sel = selected === 'trigger' ? null : findStep(graph, selected)
  const selText = sel ? text(sel) : triggerNode()
  const selKind = sel ? (sel.kind === 'if_else' ? t('kinds.branch') : t(`kinds.${nodeFamily(sel.kind)}`)) : t('kinds.trigger')

  return (
    <div className="grid items-start gap-[14px] lg:[grid-template-columns:minmax(0,1fr)_330px]">
      <div className="min-h-[640px] rounded-20 border border-line bg-surface px-[18px] py-4 [background-image:radial-gradient(#E8DFC9_1px,transparent_1px)] [background-size:18px_18px]">
        <div className="mb-[14px] flex flex-wrap items-center justify-between gap-2 rounded-12 border border-line bg-surface px-[10px] py-2">
          <span className="flex min-w-0 flex-col">
            <b className="text-14">{wf.name}</b>
            <span className="text-11.5 text-muted">{t('sub', { owner: wf.owner ?? '—', shared })}</span>
            {!active && wf.blockers.length ? <span className="text-11.5 font-semibold text-danger">{wf.blockers.map(blocker).join(' · ')}</span> : null}
          </span>
          <span className="flex flex-wrap items-center gap-[6px]">
            <span className={`rounded-999 px-[10px] py-1 text-11.5 font-bold ${active ? TONE.ok : TONE.draft}`}>{t(active ? 'active' : 'draft')}</span>
            {may && dirty ? (
              <>
                <button type="button" disabled={busy} onClick={() => { setGraph(original); setTrigger(originalTrigger); setBad(null); setError(null); setSelected('trigger') }}
                  className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('discard')}</button>
                <button type="button" disabled={busy} onClick={save} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold">{t('save')}</button>
              </>
            ) : may ? (
              <button type="button" disabled={busy} onClick={toggle} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold">{t(active ? 'deactivate' : 'activate')}</button>
            ) : null}
          </span>
        </div>
        {error ? <div role="alert" className="mb-[10px] rounded-12 bg-salmon px-3 py-2 text-12 font-semibold text-rust-ink">{error}</div> : null}
        {dirty && !error ? <div className="mb-[10px] text-center text-11.5 text-muted">{t('unsaved')}</div> : null}
        <div className="flex flex-col items-center">
          <div className="flex w-full flex-col items-center">{node('trigger')}</div>
          {plus({ list: [], index: 0 })}
          {graph.steps.map((s, i) => (
            <Fragment key={s.key}>
              <div className="flex w-full flex-col items-center">{s.kind === 'if_else' ? branch(s, i, []) : node(s)}</div>
              {plus({ list: [], index: i + 1 })}
            </Fragment>
          ))}
        </div>
      </div>
      <BuilderPanel
        key={selected}
        step={sel}
        trigger={trigger}
        entity={entity}
        base={base}
        pickers={pickers}
        labels={pickers.orgLabels}
        kindLabel={selKind}
        title={selText.title}
        badField={bad && bad.key === selected ? bad.field : null}
        disabled={!may}
        onConfig={(c) => sel && setGraph(setConfig(graph, sel.key, c))}
        onTrigger={setTrigger}
        onRemove={() => { if (sel) { setGraph(removeStep(graph, sel.key)); setSelected('trigger') } }}
        onAdd={add}
      />
    </div>
  )
}
