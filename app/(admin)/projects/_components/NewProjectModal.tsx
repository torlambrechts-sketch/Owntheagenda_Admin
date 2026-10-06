'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { BoardRow, ProjectsBase, TemplateRow } from '@/lib/data/projects'
import type { Rights } from '@/lib/data/projects-shared'
import { createFromDeal, createProject, fetchTemplates, type Hit } from '../actions'
import type { NewProject } from './ProjectsScreen'
import { btnCancel, btnConfirm, field, fieldInput, Modal, note, Picker } from './kit'

type Props = {
  init: NewProject
  base: ProjectsBase
  boards: BoardRow[]
  boardId: string | null
  rights: Rights
  onClose: () => void
  onCreated: (id: string) => void
}

/**
 * ＋ Project (D-41, spec §1.6): name, board and phase, owner, dates, template, the deal(s), person and organisation.
 * «Create from deal» (PRJ-02) takes the deal's person and organisation with it (project_create_from_deal) and may ask
 * for an AI brief, which needs «projects:ai» and the AI connection. A template needs a start date (PRJ-05).
 */
export function NewProjectModal({ init, base, boards, boardId, rights, onClose, onCreated }: Props) {
  const t = useTranslations('projects.create')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [name, setName] = useState('')
  const [board, setBoard] = useState(init.template?.board_id && boards.some((b) => b.id === init.template?.board_id) ? init.template.board_id : boardId ?? boards[0]?.id ?? '')
  const phases = boards.find((b) => b.id === board)?.phases ?? []
  const [phase, setPhase] = useState('')
  const [owner, setOwner] = useState(rights.meId)
  const [starts, setStarts] = useState('')
  const [ends, setEnds] = useState('')
  const [templates, setTemplates] = useState<TemplateRow[]>(init.template ? [init.template] : [])
  const [template, setTemplate] = useState(init.template?.id ?? '')
  const [deals, setDeals] = useState<Hit[]>(init.deal ? [{ id: init.deal.id, label: init.deal.label, sub: null }] : [])
  const [fromDeal, setFromDeal] = useState(!!init.deal)
  const [brief, setBrief] = useState(false)
  const [person, setPerson] = useState<Hit | null>(null)
  const [org, setOrg] = useState<Hit | null>(null)
  const [description, setDescription] = useState('')
  const [picking, setPicking] = useState<'deal' | 'person' | 'organization' | null>(null)
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const aiReady = rights.ai && base.aiConnected

  useEffect(() => { void fetchTemplates().then((r) => { if (r.ok) setTemplates(r.templates) }) }, [])
  useEffect(() => { if (!phases.some((p) => p.id === phase)) setPhase(phases[0]?.id ?? '') }, [board]) // eslint-disable-line react-hooks/exhaustive-deps

  const needsStart = !!template && !starts
  const canSubmit = !busy && (fromDeal ? deals.length > 0 : name.trim().length > 0) && !needsStart && (!ends || !starts || ends >= starts)

  const submit = async () => {
    setBusy(true); setProblem(null)
    const common = {
      ...(name.trim() ? { name: name.trim() } : {}),
      ...(board ? { board_id: board } : {}),
      ...(phase ? { phase_id: phase } : {}),
      ...(owner ? { owner_id: owner } : {}),
      ...(starts ? { starts_on: starts } : {}),
      ...(ends ? { ends_on: ends } : {}),
      ...(template ? { template_id: template } : {}),
      ...(description.trim() ? { description: description.trim() } : {}),
    }
    const r = fromDeal && deals[0]
      ? await createFromDeal({ deal: deals[0].id, values: { ...common, ...(deals.length > 1 ? { deal_ids: deals.slice(1).map((d) => d.id) } : {}), ...(brief ? { draft_brief: true } : {}) } })
      : await createProject({ ...common, name: name.trim(), ...(person ? { person_id: person.id } : {}), ...(org ? { organization_id: org.id } : {}), ...(deals.length ? { deal_ids: deals.map((d) => d.id) } : {}) })
    setBusy(false)
    if (!r.ok) { setProblem(r.detail ?? null); return flash(te(r.code)) }
    flash(template ? t('createdFromTemplate', { name: templates.find((x) => x.id === template)?.name ?? '' }) : t('created'))
    onCreated(r.id)
  }

  const chosenTemplate = templates.find((x) => x.id === template) ?? null

  return (
    <Modal eyebrow={t('eyebrow')} title={chosenTemplate ? t('titleTemplate', { name: chosenTemplate.name }) : t('title')} onClose={onClose} width={600}>
      {rights.dealsSee ? (
        <div role="tablist" aria-label={t('mode')} className="flex rounded-11 bg-tile p-[3px]">
          {[false, true].map((m) => (
            <button key={String(m)} type="button" role="tab" aria-selected={fromDeal === m} onClick={() => setFromDeal(m)} className={`flex-1 cursor-pointer rounded-8 border-none px-[13px] py-[7px] text-12.5 ${fromDeal === m ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
              {t(m ? 'fromDeal' : 'blank')}
            </button>
          ))}
        </div>
      ) : null}

      {fromDeal ? (
        <div className={field}>
          {t('deal')}
          {deals[0] ? (
            <span className="flex items-center justify-between gap-2 rounded-10 border border-line bg-canvas px-3 py-2 text-13 font-medium text-ink">
              ◆ {deals[0].label}
              <button type="button" onClick={() => setDeals([])} className="cursor-pointer border-none bg-transparent p-0 text-12 font-semibold text-link">{t('change')}</button>
            </span>
          ) : picking === 'deal' ? (
            <Picker entity="deal" onCancel={() => setPicking(null)} onPick={(h) => { setDeals([h]); setPicking(null) }} />
          ) : (
            <button type="button" onClick={() => setPicking('deal')} className="h-9 cursor-pointer self-start rounded-10 border border-dashed border-line-strong bg-transparent px-3 text-12.5 font-semibold text-ink">{t('pickDeal')}</button>
          )}
          <span className="text-11.5 font-normal text-faint">{t('fromDealHint')}</span>
        </div>
      ) : null}

      <label className={field}>
        {fromDeal ? t('nameOptional') : t('name')}
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={200} placeholder={fromDeal ? deals[0]?.label ?? '' : ''} className={fieldInput} />
      </label>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className={field}>
          {t('board')}
          <select value={board} onChange={(e) => setBoard(e.target.value)} className={fieldInput}>
            {boards.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </label>
        <label className={field}>
          {t('phase')}
          <select value={phase} onChange={(e) => setPhase(e.target.value)} className={fieldInput}>
            {phases.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
        <label className={field}>
          {t('owner')}
          <select value={owner} onChange={(e) => setOwner(e.target.value)} className={fieldInput}>
            {base.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
        <label className={field}>
          {t('template')}
          <select value={template} onChange={(e) => setTemplate(e.target.value)} className={fieldInput}>
            <option value="">{t('noTemplate')}</option>
            {templates.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
          </select>
        </label>
        <label className={field}>
          {t('starts')}
          <input type="date" value={starts} onChange={(e) => setStarts(e.target.value)} className={fieldInput} />
        </label>
        <label className={field}>
          {t('ends')}
          <input type="date" value={ends} min={starts || undefined} onChange={(e) => setEnds(e.target.value)} className={fieldInput} />
        </label>
      </div>
      {needsStart ? <div className={note}>{t('templateNeedsStart')}</div> : null}

      {!fromDeal ? (
        <div className="grid gap-3 sm:grid-cols-2">
          {(['person', 'organization'] as const).map((k) => {
            const v = k === 'person' ? person : org
            return (
              <div key={k} className={field}>
                {t(k)}
                {v ? (
                  <span className="flex items-center justify-between gap-2 rounded-10 border border-line bg-canvas px-3 py-2 text-13 font-medium text-ink">
                    {v.label}
                    <button type="button" onClick={() => (k === 'person' ? setPerson(null) : setOrg(null))} className="cursor-pointer border-none bg-transparent p-0 text-12 font-semibold text-link">{t('remove')}</button>
                  </span>
                ) : picking === k ? (
                  <Picker entity={k} onCancel={() => setPicking(null)} onPick={(h) => { if (k === 'person') setPerson(h); else setOrg(h); setPicking(null) }} />
                ) : (
                  <button type="button" onClick={() => setPicking(k)} className="h-9 cursor-pointer self-start rounded-10 border border-dashed border-line-strong bg-transparent px-3 text-12.5 font-semibold text-ink">{t(`pick.${k}`)}</button>
                )}
              </div>
            )
          })}
          {rights.dealsSee ? (
            <div className={`${field} sm:col-span-2`}>
              {t('deals')}
              <span className="flex flex-wrap gap-[6px]">
                {deals.map((d, i) => (
                  <span key={d.id} className="flex items-center gap-[6px] rounded-999 border border-line bg-canvas px-[10px] py-1 text-12 font-semibold text-ink">
                    ◆ {d.label}{i === 0 ? ` · ${t('primary')}` : ''}
                    <button type="button" aria-label={t('remove')} onClick={() => setDeals((xs) => xs.filter((x) => x.id !== d.id))} className="cursor-pointer border-none bg-transparent p-0 text-12 text-faint">×</button>
                  </span>
                ))}
              </span>
              {picking === 'deal' ? (
                <Picker entity="deal" onCancel={() => setPicking(null)} onPick={(h) => { setDeals((xs) => (xs.some((x) => x.id === h.id) ? xs : [...xs, h])); setPicking(null) }} />
              ) : (
                <button type="button" onClick={() => setPicking('deal')} className="h-8 cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-3 text-12 font-semibold text-ink">{t('addDeal')}</button>
              )}
            </div>
          ) : null}
        </div>
      ) : (
        <label className={`flex items-start gap-2 text-12.5 ${aiReady ? 'text-ink' : 'text-faint'}`}>
          <input type="checkbox" disabled={!aiReady} checked={brief && aiReady} onChange={(e) => setBrief(e.target.checked)} className="mt-[2px] accent-ink" />
          <span>{t('brief')}<span className="block text-11.5 text-faint">{aiReady ? t('briefHint') : t(rights.ai ? 'briefNotConnected' : 'briefForbidden')}</span></span>
        </label>
      )}

      <label className={field}>
        {t('description')}
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} maxLength={20000} rows={3} className="rounded-10 border border-line bg-canvas px-3 py-2 text-13 font-medium text-ink" />
      </label>

      {problem ? <div className="rounded-12 bg-peach px-3 py-[9px] text-12 text-rust-ink">{t('problem', { field: problem })}</div> : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
        <button type="button" disabled={!canSubmit} onClick={() => void submit()} className={btnConfirm}>{t('submit')}</button>
      </div>
    </Modal>
  )
}
