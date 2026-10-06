'use client'

import { useMemo, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { AssignHistory, AssignTest, Option, Person, Team, WorkflowDetail } from '@/lib/data/automation'
import { reorderRules, testAssignment } from '../actions'
import { TONE, useDebounced, useErrorText } from './shared'
import { RuleModal, SOURCES } from './RuleModal'

type Cond = { sources?: string[]; employees_min?: number; employees_max?: number; org_exists?: boolean; org_labels_any?: string[] }
type Assignee = { kind?: string; staff_id?: string; team_id?: string }

const sel = 'h-[34px] rounded-9 border border-line bg-canvas text-12.5'

/** The words of a rule: «When lead added · if employees > 100 → Ingrid Solberg». */
export function useRuleText(people: Person[], teams: Team[], labels: Option[]) {
  const t = useTranslations('automation.assign')
  const src = useTranslations('automation.sources')
  return useMemo(() => {
    const when = (r: WorkflowDetail) => {
      const e = (Array.isArray(r.trigger_config.entities) ? r.trigger_config.entities : ['lead', 'deal']) as string[]
      return t(`when.${e.includes('lead') && e.includes('deal') ? 'both' : e.includes('deal') ? 'deal' : 'lead'}`)
    }
    const cond = (c: Cond) => {
      const parts: string[] = []
      if (c.sources?.length) parts.push(t('cond.sources', { list: c.sources.map((s) => (src.has(s) ? src(s) : s).toLowerCase()).join(` ${t('or')} `) }))
      if (c.employees_min != null) parts.push(t('cond.min', { n: c.employees_min - 1 }))
      if (c.employees_max != null) parts.push(t('cond.max', { n: c.employees_max }))
      if (c.org_exists != null) parts.push(t(c.org_exists ? 'cond.orgExists' : 'cond.orgNew'))
      if (c.org_labels_any?.length) parts.push(t('cond.labels', { list: c.org_labels_any.map((id) => labels.find((l) => l.id === id)?.name ?? '—').join(` ${t('or')} `) }))
      return parts.length ? parts.join(` ${t('and')} `) : t('cond.else')
    }
    const to = (a: Assignee) =>
      a.kind === 'user' ? people.find((p) => p.id === a.staff_id)?.name ?? '—'
        : a.kind === 'team_rr' ? t('to.team', { team: teams.find((x) => x.id === a.team_id)?.name ?? '—' })
          : a.kind === 'org_owner' ? t('to.orgOwner') : a.kind === 'person_owner' ? t('to.personOwner') : '—'
    return { when, cond, to }
  }, [t, src, people, teams, labels])
}

/** Assignment rules (Automation.dc.html, v.assign): the rules in priority order with ▲▼, and «Test a record»,
 *  a read-only evaluation (assignment_test) whose form can reach every rule, the label rule included. */
export function AssignTab({ rules, labels, history, people, teams, canEdit }: {
  rules: WorkflowDetail[]
  labels: Option[]
  history: AssignHistory
  people: Person[]
  teams: Team[]
  canEdit: boolean
}) {
  const t = useTranslations('automation.assign')
  const src = useTranslations('automation.sources')
  const flash = useToast()
  const err = useErrorText()
  const format = useFormatter()
  const words = useRuleText(people, teams, labels)
  const [order, setOrder] = useState(rules.map((r) => r.id))
  const [edit, setEdit] = useState<WorkflowDetail | 'new' | null>(null)
  const byId = new Map(rules.map((r) => [r.id, r]))
  const list = [...order.filter((id) => byId.has(id)), ...rules.filter((r) => !order.includes(r.id)).map((r) => r.id)].map((id) => byId.get(id)!)

  const move = async (pos: number, d: number) => {
    const j = pos + d
    if (j < 0 || j >= list.length) return
    const ids = list.map((r) => r.id)
    ;[ids[pos], ids[j]] = [ids[j]!, ids[pos]!]
    setOrder(ids)
    const r = await reorderRules({ ids })
    if (!r.ok) { setOrder(list.map((x) => x.id)); flash(err(r.code, r.detail)) }
  }

  // «Test a record»
  const [form, setForm] = useState({ entity: 'lead' as 'lead' | 'deal', source: 'Web form', employees: '140', orgExists: false, label: '' })
  const [result, setResult] = useState<AssignTest | null>(null)
  const [testFailed, setTestFailed] = useState(false)
  useDebounced(form, 250, async (f) => {
    const emp = parseInt(f.employees, 10)
    const r = await testAssignment({ entity: f.entity, source: f.source, employees: Number.isFinite(emp) && emp >= 0 ? emp : null, org_exists: f.orgExists, org_labels: f.label ? [f.label] : [] })
    setTestFailed(!r.ok)
    if (r.ok) setResult(r.result)
  })
  const who = (r: AssignTest) => {
    if (!r.rule_id) return t('result.none')
    if (r.assignee_kind === 'team_rr') return r.assignee ? t('result.next', { name: r.assignee }) : t('result.noMember')
    if (r.assignee_kind === 'org_owner') return r.assignee ? t('result.orgOwnerNamed', { name: r.assignee }) : t('result.orgOwner')
    if (r.assignee_kind === 'person_owner') return r.assignee ? t('result.personOwnerNamed', { name: r.assignee }) : t('result.personOwner')
    return r.assignee ? t('result.user', { name: r.assignee }) : t('result.inactive')
  }

  return (
    <div className="grid items-start gap-[14px] lg:[grid-template-columns:minmax(0,1fr)_320px]">
      <div className="flex flex-col gap-[10px]">
        {list.length === 0 ? <div className="text-12.5 text-muted">{t('empty')}</div> : null}
        {list.map((r, pos) => {
          const c = (r.options.condition ?? {}) as Cond
          return (
            <div key={r.id} className="flex items-center gap-3 rounded-18 border border-line bg-surface px-4 py-[13px]">
              <span className="flex h-[26px] w-[26px] flex-none items-center justify-center rounded-999 bg-ink text-11.5 font-bold text-highlight">{pos + 1}</span>
              <span className="flex min-w-0 flex-1 flex-col gap-[3px]">
                <span className="flex flex-wrap items-center gap-[6px]">
                  {canEdit ? (
                    <button type="button" onClick={() => setEdit(r)} className="cursor-pointer border-none bg-transparent p-0 text-left text-13 font-bold">{r.name}</button>
                  ) : <b className="text-13">{r.name}</b>}
                  {r.state !== 'active' ? <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${TONE.draft}`}>{t('draft')}</span> : null}
                </span>
                <span className="text-12 text-muted">{t('line', { when: words.when(r), cond: words.cond(c) })}</span>
              </span>
              <span className="rounded-999 bg-highlight px-[11px] py-[5px] text-12 font-bold">→ {words.to((r.options.assignee ?? {}) as Assignee)}</span>
              {canEdit ? (
                <span className="flex flex-col gap-[2px]">
                  <button type="button" aria-label={t('up', { name: r.name })} disabled={pos === 0} onClick={() => move(pos, -1)} className="h-5 w-6 cursor-pointer rounded-6 border border-line bg-transparent p-0 text-10">▲</button>
                  <button type="button" aria-label={t('down', { name: r.name })} disabled={pos === list.length - 1} onClick={() => move(pos, 1)} className="h-5 w-6 cursor-pointer rounded-6 border border-line bg-transparent p-0 text-10">▼</button>
                </span>
              ) : null}
            </div>
          )
        })}
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="text-12 text-muted">{t('footer')}</div>
          {canEdit ? <button type="button" onClick={() => setEdit('new')} className="h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('add')}</button> : null}
        </div>
      </div>
      <div className="flex flex-col gap-[14px]">
        <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
          <b className="text-14">{t('test.title')}</b>
          <label className="flex flex-col gap-1 text-12 text-muted">{t('test.entity')}
            <select value={form.entity} onChange={(e) => setForm({ ...form, entity: e.target.value === 'deal' ? 'deal' : 'lead' })} className={sel}>
              <option value="lead">{t('test.lead')}</option><option value="deal">{t('test.deal')}</option>
            </select>
          </label>
          <label className="flex flex-col gap-1 text-12 text-muted">{t('test.source')}
            <select value={form.source} onChange={(e) => setForm({ ...form, source: e.target.value })} className={sel}>
              {SOURCES.map((s) => <option key={s} value={s}>{src(s)}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-12 text-muted">{t('test.employees')}
            <input inputMode="numeric" value={form.employees} onChange={(e) => setForm({ ...form, employees: e.target.value })} className={`${sel} px-[9px]`} />
          </label>
          <label className="flex flex-col gap-1 text-12 text-muted">{t('test.orgExists')}
            <select value={form.orgExists ? 'yes' : 'no'} onChange={(e) => setForm({ ...form, orgExists: e.target.value === 'yes' })} className={sel}>
              <option value="no">{t('test.no')}</option><option value="yes">{t('test.yes')}</option>
            </select>
          </label>
          <label className="flex flex-col gap-1 text-12 text-muted">{t('test.label')}
            <select value={form.label} onChange={(e) => setForm({ ...form, label: e.target.value })} className={sel}>
              <option value="">{t('test.noLabel')}</option>
              {labels.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
            </select>
          </label>
          <div aria-live="polite" className="rounded-14 bg-ok-bg px-[14px] py-3 text-12.5 text-ok-ink">
            {testFailed ? t('test.failed') : result ? (
              <><b>{result.rule_id ? t('result.matches', { rule: result.rule ?? '' }) : t('result.noRule')}</b><br /><br />{who(result)}</>
            ) : <span>&nbsp;</span>}
          </div>
        </div>
        <div className="flex flex-col gap-[6px] rounded-20 border border-line bg-surface px-[18px] py-4">
          <b className="text-14">{t('history.title')}</b>
          {history.length === 0 ? <div className="text-12.5 text-muted">{t('history.empty')}</div> : null}
          {history.map((h, i) => (
            <div key={i} className="flex justify-between gap-2 border-b border-line py-1 text-12.5 last:border-b-0">
              <span className="min-w-0">{h.rule ?? '—'} → {h.assignee ?? '—'}</span>
              <span className="flex-none text-muted">{format.dateTime(new Date(h.at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</span>
            </div>
          ))}
        </div>
      </div>
      {edit ? <RuleModal rule={edit === 'new' ? null : edit} labels={labels} people={people} teams={teams} onClose={() => setEdit(null)} /> : null}
    </div>
  )
}
