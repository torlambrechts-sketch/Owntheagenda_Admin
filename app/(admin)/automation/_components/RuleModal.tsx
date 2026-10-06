'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { Switch } from '@/components/ui/Switch'
import type { Option, Person, Team, WorkflowRow } from '@/lib/data/automation'
import { deleteRule, saveRule } from '../actions'
import { Modal, btnCancel, btnConfirm, field, fieldInput } from './Modal'
import { useErrorText } from './shared'

/** The record sources the design's test form offers (stored in English, shown through messages). */
export const SOURCES = ['Web form', 'Chatbot', 'Prospect search', 'Import'] as const

const check = 'flex items-center gap-[6px] text-12.5 font-medium text-ink'

/** One assignment rule: when, if and to whom (an assignment workflow's options, 0021). */
export function RuleModal({ rule, labels, people, teams, onClose }: { rule: WorkflowRow | null; labels: Option[]; people: Person[]; teams: Team[]; onClose: () => void }) {
  const t = useTranslations('automation.rule')
  const src = useTranslations('automation.sources')
  const flash = useToast()
  const err = useErrorText()
  const c = (rule?.options?.condition ?? {}) as Record<string, unknown>
  const a = (rule?.options?.assignee ?? { kind: 'org_owner' }) as Record<string, string>
  const ents = (Array.isArray(rule?.trigger_config.entities) ? rule!.trigger_config.entities : ['lead']) as string[]
  const [name, setName] = useState(rule?.name ?? '')
  const [entities, setEntities] = useState<string[]>(ents)
  const [sources, setSources] = useState<string[]>(Array.isArray(c.sources) ? (c.sources as string[]) : [])
  const [min, setMin] = useState(c.employees_min != null ? String(Number(c.employees_min) - 1) : '')
  const [max, setMax] = useState(c.employees_max != null ? String(c.employees_max) : '')
  const [exists, setExists] = useState(c.org_exists == null ? 'any' : c.org_exists ? 'yes' : 'no')
  const [labelIds, setLabelIds] = useState<string[]>(Array.isArray(c.org_labels_any) ? (c.org_labels_any as string[]) : [])
  const [kind, setKind] = useState(a.kind ?? 'org_owner')
  const [staff, setStaff] = useState(a.staff_id ?? people[0]?.id ?? '')
  const [team, setTeam] = useState(a.team_id ?? teams[0]?.id ?? '')
  const [active, setActive] = useState(rule ? rule.state === 'active' : true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const toggle = (list: string[], v: string) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v])

  const save = async () => {
    const condition: Record<string, unknown> = {}
    if (sources.length) condition.sources = sources
    if (min.trim() !== '') condition.employees_min = parseInt(min, 10) + 1
    if (max.trim() !== '') condition.employees_max = parseInt(max, 10)
    if (exists !== 'any') condition.org_exists = exists === 'yes'
    if (labelIds.length) condition.org_labels_any = labelIds
    const assignee = kind === 'user' ? { kind: 'user' as const, staff_id: staff } : kind === 'team_rr' ? { kind: 'team_rr' as const, team_id: team }
      : { kind: kind as 'org_owner' | 'person_owner' }
    setBusy(true)
    const r = await saveRule({ id: rule?.id ?? null, version: rule?.version ?? null, name, entities: entities as ('lead' | 'deal')[], condition, assignee, active })
    setBusy(false)
    if (!r.ok) { setError(err(r.code, r.detail)); return }
    flash(t('saved', { name }))
    onClose()
  }
  const remove = async () => {
    if (!rule) return
    setBusy(true)
    const r = await deleteRule({ id: rule.id })
    setBusy(false)
    if (!r.ok) { setError(err(r.code, r.detail)); return }
    flash(t('deleted', { name: rule.name }))
    onClose()
  }

  return (
    <Modal eyebrow={t('eyebrow')} title={rule ? rule.name : t('new')} onClose={onClose} width={560}>
      <label className={field}>{t('name')}<input value={name} maxLength={120} onChange={(e) => setName(e.target.value)} className={fieldInput} /></label>
      <fieldset className="m-0 flex flex-col gap-[6px] border-none p-0">
        <legend className="mb-[6px] p-0 text-12 font-semibold text-muted">{t('when')}</legend>
        <div className="flex flex-wrap gap-4">
          {(['lead', 'deal'] as const).map((e) => (
            <label key={e} className={check}><input type="checkbox" checked={entities.includes(e)} onChange={() => setEntities(toggle(entities, e))} />{t(`entity.${e}`)}</label>
          ))}
        </div>
      </fieldset>
      <fieldset className="m-0 flex flex-col gap-[6px] border-none p-0">
        <legend className="mb-[6px] p-0 text-12 font-semibold text-muted">{t('sources')}</legend>
        <div className="flex flex-wrap gap-4">
          {SOURCES.map((s) => <label key={s} className={check}><input type="checkbox" checked={sources.includes(s)} onChange={() => setSources(toggle(sources, s))} />{src(s)}</label>)}
        </div>
      </fieldset>
      <div className="grid grid-cols-2 gap-3">
        <label className={field}>{t('min')}<input inputMode="numeric" value={min} onChange={(e) => setMin(e.target.value.replace(/\D/g, ''))} className={fieldInput} /></label>
        <label className={field}>{t('max')}<input inputMode="numeric" value={max} onChange={(e) => setMax(e.target.value.replace(/\D/g, ''))} className={fieldInput} /></label>
      </div>
      <label className={field}>{t('exists')}
        <select value={exists} onChange={(e) => setExists(e.target.value)} className={fieldInput}>
          <option value="any">{t('any')}</option><option value="yes">{t('yes')}</option><option value="no">{t('no')}</option>
        </select>
      </label>
      {labels.length ? (
        <fieldset className="m-0 flex flex-col gap-[6px] border-none p-0">
          <legend className="mb-[6px] p-0 text-12 font-semibold text-muted">{t('labels')}</legend>
          <div className="flex flex-wrap gap-4">
            {labels.map((l) => <label key={l.id} className={check}><input type="checkbox" checked={labelIds.includes(l.id)} onChange={() => setLabelIds(toggle(labelIds, l.id))} />{l.name}</label>)}
          </div>
        </fieldset>
      ) : null}
      <div className="grid grid-cols-2 gap-3">
        <label className={field}>{t('assignee')}
          <select value={kind} onChange={(e) => setKind(e.target.value)} className={fieldInput}>
            {(['user', 'team_rr', 'org_owner', 'person_owner'] as const).map((k) => <option key={k} value={k}>{t(`kinds.${k}`)}</option>)}
          </select>
        </label>
        {kind === 'user' ? (
          <label className={field}>{t('user')}
            <select value={staff} onChange={(e) => setStaff(e.target.value)} className={fieldInput}>{people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select>
          </label>
        ) : kind === 'team_rr' ? (
          <label className={field}>{t('team')}
            <select value={team} onChange={(e) => setTeam(e.target.value)} className={fieldInput}>{teams.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}</select>
          </label>
        ) : null}
      </div>
      <div className="flex items-center gap-[10px] text-13 font-semibold"><Switch on={active} onChange={setActive} label={t('active')} />{t('active')}</div>
      {error ? <p role="alert" className="m-0 text-12.5 font-semibold text-danger">{error}</p> : null}
      <div className="flex flex-wrap justify-between gap-2">
        {rule ? <button type="button" disabled={busy} onClick={remove} className={`${btnCancel} text-danger`}>{t('delete')}</button> : <span />}
        <span className="flex gap-2">
          <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
          <button type="button" disabled={busy || !name.trim() || entities.length === 0} onClick={save} className={btnConfirm}>{t('save')}</button>
        </span>
      </div>
    </Modal>
  )
}
