'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Base, Pickers } from '@/lib/data/automation'
import { NOT_AVAILABLE, PALETTE, type Step } from '@/lib/data/automation-graph'
import { DATES, EVENTS, FILTER_FIELDS, NUMERIC, WAIT_EVENTS } from './builder-text'
import { useWords } from './shared'

export type Trigger = { type: 'event' | 'date' | 'product_event'; config: Record<string, unknown> }
type Cfg = Record<string, unknown>

const label = 'flex flex-col gap-1 text-11.5 font-semibold text-muted'
const input = 'h-[34px] rounded-9 border bg-canvas px-[9px] text-12.5 font-medium text-ink disabled:opacity-70'
const code = 'min-h-[110px] rounded-10 border bg-canvas px-[10px] py-[9px] font-mono text-11.5 text-ink [font-family:ui-monospace,Menlo,monospace] disabled:opacity-70'
const tiny = 'h-6 cursor-pointer rounded-999 border border-line-strong bg-transparent px-2 text-11 disabled:cursor-default disabled:opacity-50'
const border = (bad: boolean) => (bad ? 'border-danger' : 'border-line')

function Text({ k, v, onChange, bad, disabled, numeric }: { k: string; v: unknown; onChange: (v: string) => void; bad?: boolean; disabled: boolean; numeric?: boolean }) {
  return <label className={label}>{k}<input inputMode={numeric ? 'numeric' : undefined} disabled={disabled} value={v == null ? '' : String(v)} onChange={(e) => onChange(e.target.value)} className={`${input} ${border(!!bad)}`} /></label>
}
function Pick({ k, v, options, onChange, bad, disabled }: { k: string; v: unknown; options: { id: string; name: string }[]; onChange: (v: string) => void; bad?: boolean; disabled: boolean }) {
  const t = useTranslations('automation.builder')
  const has = options.some((o) => o.id === v)
  return (
    <label className={label}>{k}
      <select disabled={disabled} value={has ? String(v) : ''} onChange={(e) => onChange(e.target.value)} className={`${input} ${border(!!bad)}`}>
        {!has ? <option value="">{v ? String(v) : t('choose')}</option> : null}
        {options.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
      </select>
    </label>
  )
}

/** A JSON object typed as raw text; it is applied only while it parses. */
function Json({ k, v, onChange, bad, disabled }: { k: string; v: unknown; onChange: (v: Cfg) => void; bad?: boolean; disabled: boolean }) {
  const t = useTranslations('automation.builder')
  const [text, setText] = useState(() => JSON.stringify(v ?? {}, null, 2))
  const [broken, setBroken] = useState(false)
  return (
    <label className={label}>{k}
      <textarea disabled={disabled} value={text} onChange={(e) => {
        setText(e.target.value)
        try { const o = JSON.parse(e.target.value || '{}'); if (o && typeof o === 'object' && !Array.isArray(o)) { onChange(o as Cfg); setBroken(false) } else setBroken(true) } catch { setBroken(true) }
      }} className={`${code} ${border(!!bad || broken)}`} />
      {broken ? <span className="font-medium text-danger">{t('jsonBroken')}</span> : null}
    </label>
  )
}

/** Condition groups (AND inside a group, OR between groups, app.wf_match): «Group 1», «Group 2 (OR)». */
function Groups({ entity, groups, onChange, bad, disabled, labels }: { entity: string; groups: unknown; onChange: (g: unknown[][]) => void; bad?: boolean; disabled: boolean; labels: { id: string; name: string }[] }) {
  const t = useTranslations('automation.builder')
  const w = useWords()
  const gs = (Array.isArray(groups) ? groups : []).map((g) => (Array.isArray(g) ? g : [g])) as Cfg[][]
  const set = (gi: number, fi: number, patch: Cfg) => onChange(gs.map((g, i) => (i === gi ? g.map((f, j) => (j === fi ? { ...f, ...patch } : f)) : g)))
  const fields = FILTER_FIELDS[entity] ?? []
  const ops = ['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'contains', 'empty', 'notempty']
  return (
    <div className="flex flex-col gap-2">
      {gs.map((g, gi) => (
        <div key={gi} className="flex flex-col gap-[6px]">
          <span className="text-11.5 font-semibold text-muted">{gi === 0 ? t('group1') : t('groupOr', { n: gi + 1 })}</span>
          {g.map((f, fi) => {
            const field = String(f.f ?? '')
            const mail = field.startsWith('email.')
            const opts = field && !fields.includes(field) ? [field, ...fields] : fields
            return (
              <div key={fi} className="flex flex-wrap items-center gap-1">
                <select aria-label={t('field')} disabled={disabled} value={field} onChange={(e) => set(gi, fi, { f: e.target.value, op: e.target.value.startsWith('email.') ? 'eq' : f.op ?? 'eq', v: e.target.value.startsWith('email.') ? 7 : '' })}
                  className={`${input} ${border(!!bad && !field)} min-w-0 flex-1`}>
                  {!field ? <option value="">{t('choose')}</option> : null}
                  {opts.map((o) => <option key={o} value={o}>{o.startsWith('email.') ? w.t(`mailTest.${o.slice(6)}`, { days: 'N' }) : w.pick('fields', o)}</option>)}
                </select>
                {!mail ? (
                  <select aria-label={t('op')} disabled={disabled} value={String(f.op ?? 'eq')} onChange={(e) => set(gi, fi, { op: e.target.value })} className={`${input} border-line w-[74px]`}>
                    {ops.map((o) => <option key={o} value={o}>{w.t(`opNames.${o}`)}</option>)}
                  </select>
                ) : null}
                {f.op !== 'empty' && f.op !== 'notempty' ? (
                  field === 'labels' ? (
                    <select aria-label={t('value')} disabled={disabled} value={Array.isArray(f.v) ? String(f.v[0] ?? '') : String(f.v ?? '')} onChange={(e) => set(gi, fi, { op: 'has', v: [e.target.value] })} className={`${input} border-line w-[110px]`}>
                      <option value="">{t('choose')}</option>
                      {labels.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
                    </select>
                  ) : (
                    <input aria-label={mail ? t('days') : t('value')} disabled={disabled} value={f.v == null ? '' : String(f.v)}
                      onChange={(e) => set(gi, fi, { v: NUMERIC.has(field) && e.target.value.trim() !== '' && !Number.isNaN(Number(e.target.value)) ? Number(e.target.value) : e.target.value })}
                      className={`${input} border-line w-[90px]`} />
                  )
                ) : null}
                <button type="button" aria-label={t('removeFilter')} disabled={disabled} onClick={() => onChange(gs.map((x, i) => (i === gi ? x.filter((_, j) => j !== fi) : x)).filter((x) => x.length))} className={tiny}>×</button>
              </div>
            )
          })}
          <span><button type="button" disabled={disabled} onClick={() => onChange(gs.map((x, i) => (i === gi ? [...x, { f: '', op: 'eq', v: '' }] : x)))} className={tiny}>{t('and')}</button></span>
        </div>
      ))}
      <span><button type="button" disabled={disabled} onClick={() => onChange([...gs, [{ f: '', op: 'eq', v: '' }]])} className={tiny}>{t('orGroup')}</button></span>
    </div>
  )
}

/** The configuration panel (Automation.dc.html, the sticky card): the selected node's fields, its note, and
 *  «Add a step» with the palette. Every field edits the draft graph; Save publishes it. */
export function BuilderPanel({ step, trigger, entity, base, pickers, labels, kindLabel, title, badField, disabled, onConfig, onTrigger, onRemove, onAdd }: {
  step: Step | null
  trigger: Trigger
  entity: string
  base: Base
  pickers: Pickers
  labels: { id: string; name: string }[]
  kindLabel: string
  title: string
  badField: string | null
  disabled: boolean
  onConfig: (c: Cfg) => void
  onTrigger: (t: Trigger) => void
  onRemove: () => void
  onAdd: (kind: string) => void
}) {
  const t = useTranslations('automation.builder')
  const w = useWords()
  const c = step?.config ?? {}
  const set = (patch: Cfg) => onConfig({ ...c, ...patch })
  const bad = (f: string) => badField === f || (badField?.startsWith(`${f}.`) ?? false)
  const owners = [{ id: '@record_owner', name: t('owners.record') }, { id: '@workflow_owner', name: t('owners.workflow') }]
  const entities = ['deal', 'lead', 'person', 'organization'].map((e) => ({ id: e, name: w.pick('entity', e) }))

  let fields: React.ReactNode = null
  let note = t('notes.limits', { limit: base.countLimits.value === 'number' ? String(base.countLimits.number ?? '') : t('unlimited') })
  if (!step) {
    const tc = trigger.config
    const ent = String(tc.entity ?? 'deal')
    const setT = (patch: Cfg) => onTrigger({ ...trigger, config: { ...tc, ...patch } })
    note = t('notes.trigger')
    fields = (
      <>
        <Pick k={t('f.triggerType')} v={trigger.type} disabled={disabled} options={(['event', 'date', 'product_event'] as const).map((x) => ({ id: x, name: t(`triggerTypes.${x}`) }))}
          onChange={(v) => onTrigger(v === 'product_event' ? { type: 'product_event', config: { kind: '' } } : v === 'date' ? { type: 'date', config: { entity: ent, date: DATES[ent]?.[0] ?? 'created_at', offset_days: 0 } } : { type: 'event', config: { entity: ent, event: 'created' } })} />
        {trigger.type !== 'product_event' ? (
          <Pick k={t('f.object')} v={ent} disabled={disabled} bad={bad('entity')} options={Object.keys(EVENTS).map((e) => ({ id: e, name: w.pick('entity', e) }))}
            onChange={(v) => onTrigger({ ...trigger, config: trigger.type === 'date' ? { entity: v, date: DATES[v]?.[0] ?? 'created_at', offset_days: Number(tc.offset_days ?? 0) } : { entity: v, event: 'created' } })} />
        ) : null}
        {trigger.type === 'event' ? (
          <>
            <Pick k={t('f.event')} v={tc.event} disabled={disabled} options={[...new Set([...(EVENTS[ent] ?? []), String(tc.event ?? '')])].filter(Boolean).map((e) => ({ id: e, name: w.pick('eventTitle', e) }))} onChange={(v) => setT({ event: v })} />
            {tc.event === 'updated' ? (
              <Text k={t('f.fieldChanged')} v={Array.isArray(tc.fields) ? tc.fields.join(', ') : ''} disabled={disabled}
                onChange={(v) => setT({ fields: v.split(',').map((x) => x.trim()).filter(Boolean) })} />
            ) : null}
          </>
        ) : null}
        {trigger.type === 'date' ? (
          <>
            <Pick k={t('f.date')} v={tc.date} disabled={disabled} options={(DATES[ent] ?? []).map((d) => ({ id: d, name: w.pick('dates', d) }))} onChange={(v) => setT({ date: v })} />
            <Text k={t('f.offset')} v={tc.offset_days} numeric disabled={disabled} onChange={(v) => setT({ offset_days: Number(v.replace(/[^\d-]/g, '')) || 0 })} />
          </>
        ) : null}
        {trigger.type === 'product_event' ? (
          <Text k={t('f.productEvent')} v={tc.kind} bad={bad('kind')} disabled={disabled} onChange={(v) => setT({ kind: v.trim() })} />
        ) : null}
        {trigger.type !== 'product_event' ? <Groups entity={ent} groups={tc.groups ?? []} labels={labels} disabled={disabled} onChange={(g) => setT({ groups: g })} /> : null}
      </>
    )
  } else {
    switch (step.kind) {
      case 'condition':
      case 'if_else':
        note = t('notes.condition')
        fields = <Groups entity={entity} groups={c.groups} labels={labels} bad={bad('groups')} disabled={disabled} onChange={(g) => set({ groups: g })} />
        break
      case 'delay':
        fields = (
          <>
            <Text k={t('f.amount')} v={c.amount} numeric bad={bad('amount')} disabled={disabled} onChange={(v) => set({ amount: Number(v.replace(/\D/g, '')) || 0 })} />
            <Pick k={t('f.unit')} v={c.unit ?? 'days'} disabled={disabled} options={['minutes', 'hours', 'days'].map((u) => ({ id: u, name: t(`units.${u}`) }))} onChange={(v) => set({ unit: v })} />
            <label className="flex items-center gap-2 text-12 font-semibold text-muted"><input type="checkbox" disabled={disabled} checked={!!c.skip_weekends} onChange={(e) => set({ skip_weekends: e.target.checked })} />{t('f.skipWeekends')}</label>
          </>
        )
        break
      case 'wait_for':
        note = t('notes.wait')
        fields = (
          <>
            <Pick k={t('f.waitEvent')} v={c.event} bad={bad('event')} disabled={disabled} options={WAIT_EVENTS.map((e) => ({ id: e, name: w.pick('waitEvent', e) }))} onChange={(v) => set({ event: v })} />
            <Text k={t('f.timeout')} v={c.timeout_days} numeric disabled={disabled} onChange={(v) => set({ timeout_days: Number(v.replace(/\D/g, '')) || 0 })} />
            <Pick k={t('f.then')} v={c.then ?? 'continue'} disabled={disabled} options={['continue', 'stop'].map((x) => ({ id: x, name: t(`then.${x}`) }))} onChange={(v) => set({ then: v })} />
          </>
        )
        break
      case 'create_record':
        fields = (
          <>
            <Pick k={t('f.object')} v={c.entity} bad={bad('entity')} disabled={disabled} options={entities} onChange={(v) => set({ entity: v })} />
            <Json k={t('f.values')} v={c.values} bad={bad('values')} disabled={disabled} onChange={(v) => set({ values: v })} />
          </>
        )
        break
      case 'update_record':
        fields = <Json k={t('f.values')} v={c.values} bad={bad('values')} disabled={disabled} onChange={(v) => set({ values: v })} />
        note = t('notes.values')
        break
      case 'delete_record':
        note = t('notes.delete')
        break
      case 'create_activity':
        fields = (
          <>
            <Pick k={t('f.activityType')} v={c.type} disabled={disabled} options={pickers.activityTypes} onChange={(v) => set({ type: v })} />
            <Text k={t('f.subject')} v={c.subject} bad={bad('subject')} disabled={disabled} onChange={(v) => set({ subject: v })} />
            <Text k={t('f.dueIn')} v={c.due_in_days} numeric disabled={disabled} onChange={(v) => set({ due_in_days: Number(v.replace(/\D/g, '')) || 0 })} />
            <Pick k={t('f.assignedTo')} v={c.owner ?? '@record_owner'} disabled={disabled} options={owners} onChange={(v) => set({ owner: v })} />
          </>
        )
        note = t('notes.merge')
        break
      case 'add_note':
        fields = <Text k={t('f.body')} v={c.body} bad={bad('body')} disabled={disabled} onChange={(v) => set({ body: v })} />
        note = t('notes.merge')
        break
      case 'notify':
        fields = (
          <>
            <Pick k={t('f.to')} v={c.to ?? '@record_owner'} disabled={disabled} options={owners} onChange={(v) => set({ to: v })} />
            <Text k={t('f.message')} v={c.message} bad={bad('message')} disabled={disabled} onChange={(v) => set({ message: v })} />
          </>
        )
        note = t('notes.merge')
        break
      case 'send_email':
        fields = (
          <>
            <Pick k={t('f.template')} v={c.template_id} bad={bad('template_id')} disabled={disabled} options={pickers.emailTemplates} onChange={(v) => set({ template_id: v })} />
            <Pick k={t('f.from')} v={c.from ?? '@record_owner'} disabled={disabled} options={owners} onChange={(v) => set({ from: v })} />
          </>
        )
        note = t('notes.email')
        break
      case 'enroll_sequence':
        fields = <Pick k={t('f.sequence')} v={c.sequence_id} bad={bad('sequence_id')} disabled={disabled} options={pickers.sequences} onChange={(v) => set({ sequence_id: v })} />
        break
      case 'assign_owner': {
        const a = (c.assignee ?? {}) as Record<string, string>
        fields = (
          <>
            <Pick k={t('f.assignee')} v={a.kind} disabled={disabled} options={['user', 'team_rr', 'org_owner', 'person_owner'].map((k) => ({ id: k, name: t(`assignee.${k}`) }))}
              onChange={(v) => set({ assignee: v === 'user' ? { kind: v, staff_id: base.people[0]?.id } : v === 'team_rr' ? { kind: v, team_id: base.teams[0]?.id } : { kind: v } })} />
            {a.kind === 'user' ? <Pick k={t('f.user')} v={a.staff_id} disabled={disabled} options={base.people} onChange={(v) => set({ assignee: { kind: 'user', staff_id: v } })} /> : null}
            {a.kind === 'team_rr' ? <Pick k={t('f.team')} v={a.team_id} disabled={disabled} options={base.teams} onChange={(v) => set({ assignee: { kind: 'team_rr', team_id: v } })} /> : null}
          </>
        )
        break
      }
      case 'create_ticket':
        fields = (
          <>
            <Pick k={t('f.category')} v={c.category_key} bad={bad('category_key')} disabled={disabled} options={pickers.ticketCategories} onChange={(v) => set({ category_key: v })} />
            <Text k={t('f.subject')} v={c.subject} bad={bad('subject')} disabled={disabled} onChange={(v) => set({ subject: v })} />
          </>
        )
        note = t('notes.merge')
        break
      case 'webhook':
        fields = (
          <>
            <Pick k={t('f.method')} v={c.method ?? 'POST'} bad={bad('method')} disabled={disabled} options={['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].map((m) => ({ id: m, name: m }))} onChange={(v) => set({ method: v })} />
            <Text k={t('f.url')} v={c.url} bad={bad('url')} disabled={disabled} onChange={(v) => set({ url: v.trim() })} />
            <label className={label}>{t('f.rawBody')}
              <textarea disabled={disabled} value={String(c.body ?? '')} onChange={(e) => set({ body: e.target.value })} className={`${code} ${border(bad('body'))}`} />
            </label>
          </>
        )
        note = t('notes.webhook')
        break
      case 'slack':
      case 'teams':
        fields = (
          <>
            <Text k={t('f.channel')} v={c.channel} disabled={disabled} onChange={(v) => set({ channel: v })} />
            <Text k={t('f.message')} v={c.message} disabled={disabled} onChange={(v) => set({ message: v })} />
          </>
        )
        note = base.connected.includes(step.kind) ? t('notes.merge') : t('notes.notConnected', { provider: t(`providers.${step.kind}`) })
        break
      case 'accounting_invoice':
        note = base.connected.includes('accounting') ? t('notes.invoice') : t('notes.notConnected', { provider: t('providers.accounting') })
        break
      case 'campaign_action':
      case 'project_action':
        note = t(`notes.${step.kind}`)
        break
    }
  }

  return (
    <div className="flex flex-col gap-[10px] rounded-20 border border-ink bg-surface px-[18px] py-4 lg:sticky lg:top-[76px]">
      <span className="text-10.5 font-bold uppercase tracking-label text-muted">{kindLabel}</span>
      <b className="text-15">{title}</b>
      {fields}
      <div className="text-11.5 leading-[1.5] text-faint">{note}</div>
      {step && !disabled ? <span><button type="button" onClick={onRemove} className={`${tiny} text-danger`}>{t('remove')}</button></span> : null}
      <div className="border-t border-line pt-[10px] text-11 font-bold uppercase tracking-label text-muted">{t('addStep')}</div>
      <div className="flex flex-wrap gap-[5px]">
        {PALETTE.map((k) => {
          const off = disabled || NOT_AVAILABLE.has(k)
          return (
            <button key={k} type="button" disabled={off} title={NOT_AVAILABLE.has(k) ? t('nodes.notAvailable') : undefined} onClick={() => onAdd(k)}
              className="cursor-pointer rounded-999 border border-line-strong bg-transparent px-[10px] py-[5px] text-11.5 disabled:cursor-default disabled:opacity-50">
              {t(`palette.${k}`)}
            </button>
          )
        })}
      </div>
    </div>
  )
}
