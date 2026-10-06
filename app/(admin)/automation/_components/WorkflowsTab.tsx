'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Person, WorkflowRow } from '@/lib/data/automation'
import { setWorkflowState } from '../actions'
import { TONE, canChange, useBlockerText, useErrorText, useGo, useTriggerText, wfScope, type Rights } from './shared'
import { TransferModal } from './TransferModal'

const GRID = '[grid-template-columns:minmax(200px,1.6fr)_minmax(160px,1.3fr)_110px_90px_70px_70px_minmax(120px,1fr)_160px]'
const btn = 'h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-50'

/** «Active for»: the activation scope in words (Everyone, the teams or people it is active for, the owner). */
export function useScopeText() {
  const t = useTranslations('automation.scope')
  return (w: WorkflowRow) =>
    w.activation_scope === 'everyone' ? t('everyone') : w.activation_scope === 'owner' ? t('owner') : w.activation.map((a) => a.name).filter(Boolean).join(', ') || t('nobody')
}

/** The workflow list (Automation.dc.html, v.list): runs and failures over seven days from the engine's runs. */
export function WorkflowsTab({ rows, people, me, rights }: { rows: WorkflowRow[]; people: Person[]; me: string; rights: Rights }) {
  const t = useTranslations('automation.list')
  const flash = useToast()
  const err = useErrorText()
  const blocker = useBlockerText()
  const trigger = useTriggerText()
  const scope = useScopeText()
  const { go } = useGo()
  const [busy, setBusy] = useState<string | null>(null)
  const [transfer, setTransfer] = useState<WorkflowRow | null>(null)

  const toggle = async (w: WorkflowRow) => {
    setBusy(w.id)
    const r = await setWorkflowState({ id: w.id, state: w.state === 'active' ? 'draft' : 'active' })
    setBusy(null)
    if (!r.ok) flash(t('refused', { reason: err(r.code, r.detail) }))
    else flash(w.state === 'active' ? t('deactivated', { name: w.name }) : t('activated', { name: w.name }))
  }

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="overflow-x-auto">
        <div className="min-w-[1000px]">
          <div className={`grid ${GRID} gap-[10px] border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted`}>
            <span>{t('cols.workflow')}</span><span>{t('cols.trigger')}</span><span>{t('cols.owner')}</span><span>{t('cols.state')}</span>
            <span>{t('cols.runs')}</span><span>{t('cols.failed')}</span><span>{t('cols.activeFor')}</span><span />
          </div>
          {rows.length === 0 ? <div className="px-4 py-[14px] text-12.5 text-muted">{t('empty')}</div> : null}
          {rows.map((w) => {
            const active = w.state === 'active'
            const may = canChange(w, me, rights)
            return (
              <div key={w.id} className={`grid ${GRID} items-center gap-[10px] border-b border-line px-4 py-[10px] text-12.5 last:border-b-0`}>
                <button type="button" onClick={() => go({ tab: 'builder', wf: w.id }, { reset: true })} className="flex cursor-pointer flex-col border-none bg-transparent p-0 text-left text-12.5">
                  <b>{w.name}</b>
                  {w.description ? <span className="text-11.5 text-muted">{w.description}</span> : null}
                  {!active && w.blockers.length ? <span className="text-11.5 text-danger">{w.blockers.map(blocker).join(' · ')}</span> : null}
                </button>
                <span className="text-ink-2">{trigger(w.trigger_type, w.trigger_config)}</span>
                <span>{w.owner?.split(' ')[0] ?? '—'}</span>
                <span><span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${active ? TONE.ok : TONE.draft}`}>{t(active ? 'active' : 'draft')}</span></span>
                <span>{w.runs_7d}</span>
                <span className={`font-bold ${w.failed_7d ? 'text-danger' : 'text-muted'}`}>{w.failed_7d}</span>
                <span className="text-muted">{scope(w)}</span>
                <span className="flex justify-end gap-[6px]">
                  {may ? (
                    <>
                      <button type="button" disabled={busy === w.id} onClick={() => toggle(w)} className={btn}>{t(active ? 'deactivate' : 'activate')}</button>
                      <button type="button" onClick={() => setTransfer(w)} className={btn}>{t('transfer')}</button>
                    </>
                  ) : null}
                </span>
              </div>
            )
          })}
        </div>
      </div>
      {transfer ? <TransferModal wf={transfer} people={people.filter((p) => p.id !== transfer.owner_id && p.canWorkflows.includes(wfScope(transfer)))} onClose={() => setTransfer(null)} /> : null}
    </div>
  )
}
