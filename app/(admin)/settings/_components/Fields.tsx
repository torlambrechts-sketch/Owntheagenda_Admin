'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Field, Pipeline } from '@/lib/data/settings'
import { saveField } from '../actions'
import { k, useRun } from './kit'

// the design's sixteen types (TY), then formula (CUS-04), which the database keeps as a type of its own
const TYPES = ['text', 'large_text', 'single_option', 'multiple_options', 'autocomplete', 'numerical', 'monetary', 'user', 'organization', 'person', 'phone',
  'time', 'time_range', 'date', 'date_range', 'address', 'formula'] as const
type FieldType = (typeof TYPES)[number]
const OPTION_TYPES = ['single_option', 'multiple_options', 'autocomplete']

type Opt = { key: string; label: string }
type Draft = {
  label: string
  type: FieldType
  options: Opt[]
  quality: 'optional' | 'important' | 'required'
  from_stage_id: string | null
  pipeline_ids: string[] | null
  readonly_for: string[]
  hidden_for: string[]
  description: string
  formula: string
}

/** A key the database accepts (^[a-z][a-z0-9_]{1,40}$), from a label, not yet taken. */
function slug(label: string, taken: string[], prefix = 'f') {
  let s = label.toLowerCase().replace(/æ/g, 'ae').replace(/ø/g, 'o').replace(/å/g, 'a').normalize('NFD').replace(/[̀-ͯ]/g, '')
  s = s.replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 36)
  if (!/^[a-z]/.test(s)) s = `${prefix}_${s}`.replace(/_+$/, '')
  if (s.length < 2) s = `${prefix}_x`
  let out = s
  for (let i = 2; taken.includes(out); i++) out = `${s}_${i}`
  return out
}

const optsOf = (f: Field): Opt[] => f.options.map((o) => (typeof o === 'string' ? { key: o, label: o } : { key: o.key, label: o.label ?? o.key }))

/** Data fields (Settings.dc.html, v.fields): record-type chips, the field table and the field editor. */
export function Fields({ entities, fields, pipelines, sets, optionLimit, canEdit }: {
  entities: string[]
  fields: Field[]
  pipelines: Pipeline[]
  sets: { id: string; name: string }[]
  optionLimit: number | null
  canEdit: Record<string, boolean>
}) {
  const t = useTranslations('settings')
  const [entity, setEntity] = useState(entities.includes('deal') ? 'deal' : entities[0] ?? 'deal')
  const list = fields.filter((f) => f.entity === entity)
  const editable = !!canEdit[entity]
  const [sel, setSel] = useState<string | null>(list[0]?.id ?? null)
  const current = list.find((f) => f.id === sel) ?? null
  const mode: 'edit' | 'new' | 'none' = current ? 'edit' : editable ? 'new' : 'none'

  const stages = new Map(pipelines.flatMap((p) => p.stages.map((s) => [s.id, s.name] as const)))
  const setName = (ids: string[]) => ids.map((id) => sets.find((s) => s.id === id)?.name ?? '—').join(', ')
  const ruleOf = (f: Field) => {
    if (f.type === 'formula') return { text: t('fields.rule.formula'), c: 'text-muted' }
    const stage = f.from_stage_id ? stages.get(f.from_stage_id) : null
    const text = stage && f.quality !== 'optional' ? t(`fields.rule.${f.quality}From`, { stage }) : t(`fields.rule.${f.quality}`)
    return { text, c: f.quality === 'required' ? 'text-danger' : f.quality === 'important' ? 'text-warn-ink' : 'text-muted' }
  }
  const accessOf = (f: Field) => {
    const parts = [
      f.hidden_for.length ? t('fields.hiddenFrom', { sets: setName(f.hidden_for) }) : null,
      f.readonly_for.length ? t('fields.readOnlyForSets', { sets: setName(f.readonly_for) }) : null,
      f.pipeline_ids?.length ? t('fields.only', { names: f.pipeline_ids.map((id) => pipelines.find((p) => p.id === id)?.name ?? '—').join(', ') }) : null,
    ].filter(Boolean)
    return parts.length ? parts.join(' · ') : t('fields.everyone')
  }

  const pickEntity = (e: string) => {
    setEntity(e)
    setSel(fields.find((f) => f.entity === e)?.id ?? null)
  }

  const cols = '[grid-template-columns:minmax(0,1.4fr)_120px_minmax(0,1.2fr)_minmax(0,1fr)]'
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap gap-[6px]">
        {entities.map((e) => (
          <button key={e} type="button" aria-pressed={entity === e} onClick={() => pickEntity(e)} className={k.chip(entity === e)}>
            {t.has(`entities.${e}`) ? t(`entities.${e}`) : e}
          </button>
        ))}
        {editable ? (
          <button type="button" onClick={() => setSel(null)} className={k.dashedChip}>
            {t('fields.add')}
          </button>
        ) : null}
      </div>
      <div className="grid items-start gap-[14px] lg:[grid-template-columns:minmax(0,1fr)_minmax(280px,340px)]">
        <div className={`${k.card} overflow-x-auto`}>
          <div className={`grid min-w-[560px] gap-[10px] border-b border-line px-4 py-[9px] ${k.colHead} ${cols}`}>
            <span>{t('fields.cols.field')}</span>
            <span>{t('fields.cols.type')}</span>
            <span>{t('fields.cols.rule')}</span>
            <span>{t('fields.cols.access')}</span>
          </div>
          {list.map((f) => {
            const r = ruleOf(f)
            return (
              <button
                key={f.id}
                type="button"
                aria-pressed={sel === f.id}
                onClick={() => setSel(f.id)}
                className={`grid w-full min-w-[560px] cursor-pointer items-center gap-[10px] border-0 border-b border-solid border-line px-4 py-[9px] text-left text-12.5 text-ink ${cols} ${sel === f.id ? 'bg-highlight' : 'bg-transparent'}`}
              >
                <span className="flex flex-col">
                  <b>{f.label}</b>
                  <span className="text-11 text-faint">{f.key}</span>
                </span>
                <span>{t(`fields.types.${f.type}`)}</span>
                <span className={r.c}>{r.text}</span>
                <span className="text-muted">{accessOf(f)}</span>
              </button>
            )
          })}
          {list.length === 0 ? (
            <div className="min-w-[560px] px-4 py-[18px] text-12.5 text-muted">{t('fields.empty', { entity: t.has(`entities.${entity}`) ? t(`entities.${entity}`) : entity })}</div>
          ) : null}
        </div>
        {mode !== 'none' ? (
          <Editor
            key={`${entity}-${current?.id ?? 'new'}`}
            entity={entity}
            field={current}
            taken={list.map((f) => f.key)}
            pipelines={entity === 'deal' ? pipelines : []}
            sets={sets}
            optionLimit={optionLimit}
            editable={editable}
            onCreated={(id) => setSel(id)}
            onArchived={() => setSel(list.find((f) => f.id !== current?.id)?.id ?? null)}
          />
        ) : null}
      </div>
    </div>
  )
}

function Editor({ entity, field, taken, pipelines, sets, optionLimit, editable, onCreated, onArchived }: {
  entity: string
  field: Field | null
  taken: string[]
  pipelines: Pipeline[]
  sets: { id: string; name: string }[]
  optionLimit: number | null
  editable: boolean
  onCreated: (id: string) => void
  onArchived: () => void
}) {
  const t = useTranslations('settings')
  const { run, pending } = useRun()
  const [d, setD] = useState<Draft>(() =>
    field
      ? {
          label: field.label, type: (TYPES as readonly string[]).includes(field.type) ? (field.type as FieldType) : 'text', options: optsOf(field), quality: field.quality,
          from_stage_id: field.from_stage_id, pipeline_ids: field.pipeline_ids, readonly_for: field.readonly_for, hidden_for: field.hidden_for,
          description: field.description ?? '', formula: field.formula ?? '',
        }
      : { label: '', type: 'text', options: [], quality: 'optional', from_stage_id: null, pipeline_ids: null, readonly_for: [], hidden_for: [], description: '', formula: '' },
  )
  const [newOpt, setNewOpt] = useState('')
  const up = (p: Partial<Draft>) => setD((x) => ({ ...x, ...p }))
  const isNew = !field
  const hasOptions = OPTION_TYPES.includes(d.type)
  const atLimit = optionLimit !== null && d.options.length >= optionLimit
  const valid = d.label.trim().length > 0 && (d.type !== 'formula' || d.formula.trim().length > 0)
  const sel = 'h-[30px] max-w-[62%] rounded-8 border border-line bg-canvas text-12 text-ink'
  const row = 'flex items-center justify-between gap-3 text-12.5'

  const setSelect = (ids: string[], label: string, value: string, onChange: (ids: string[]) => void) => (
    <select aria-label={label} value={ids.length > 1 ? '__many' : ids[0] ?? ''} disabled={!editable} onChange={(e) => e.target.value !== '__many' && onChange(e.target.value ? [e.target.value] : [])} className={sel}>
      <option value="">{value}</option>
      {ids.length > 1 ? <option value="__many">{ids.map((id) => sets.find((s) => s.id === id)?.name ?? '—').join(', ')}</option> : null}
      {sets.map((s) => (
        <option key={s.id} value={s.id}>{s.name}</option>
      ))}
    </select>
  )

  const save = () => {
    if (!valid) return
    const values = {
      label: d.label.trim(),
      options: hasOptions ? d.options : [],
      quality: d.quality,
      ...(entity === 'deal' ? { from_stage_id: d.from_stage_id, pipeline_ids: d.pipeline_ids } : {}),
      readonly_for: d.readonly_for,
      hidden_for: d.hidden_for,
      description: d.description.trim() || null,
      ...(d.type === 'formula' ? { formula: d.formula.trim() } : {}),
    }
    if (isNew) {
      run(() => saveField({ id: null, values: { ...values, entity, type: d.type, key: slug(d.label, taken) } }), (r) => {
        onCreated(r.id)
        return t('fields.created', { name: values.label })
      })
    } else {
      run(() => saveField({ id: field.id, values }), () => t('fields.saved', { name: values.label }))
    }
  }

  return (
    <div className="flex flex-col gap-[9px] rounded-20 border border-ink bg-surface px-[18px] py-4">
      <b className="text-14">{isNew ? t('fields.newTitle') : field.label}</b>
      <label className={k.label}>
        {t('fields.label')}
        <input value={d.label} maxLength={80} disabled={!editable} onChange={(e) => up({ label: e.target.value })} className="h-[34px] rounded-9 border border-line bg-canvas px-[9px] text-12.5 font-normal text-ink" />
      </label>
      <div className="text-11.5 font-semibold text-muted">{t('fields.typeCount', { count: TYPES.length })}</div>
      <div className="flex flex-wrap gap-1" role={isNew ? 'group' : undefined} aria-label={t('fields.cols.type')}>
        {TYPES.map((ty) => {
          const on = ty === d.type
          const cls = `rounded-999 border px-2 py-[3px] text-11 text-ink ${on ? 'border-ink bg-highlight font-bold' : 'border-line bg-transparent font-medium'}`
          return isNew && editable ? (
            <button key={ty} type="button" aria-pressed={on} onClick={() => up({ type: ty })} className={`cursor-pointer ${cls}`}>
              {t(`fields.types.${ty}`)}
            </button>
          ) : (
            <span key={ty} className={cls}>{t(`fields.types.${ty}`)}</span>
          )
        })}
      </div>
      {d.type === 'formula' ? (
        <label className={k.label}>
          {t('fields.formula')}
          <input
            value={d.formula}
            maxLength={500}
            disabled={!editable}
            onChange={(e) => up({ formula: e.target.value })}
            placeholder="[deal.value] * [deal.probability] / 100"
            className="h-[34px] rounded-9 border border-line bg-canvas px-[9px] font-mono text-12 font-normal text-ink [font-family:ui-monospace,Menlo,monospace]"
          />
        </label>
      ) : null}
      {hasOptions ? (
        <div className="flex flex-col gap-1">
          <div className="text-11.5 font-semibold text-muted">{t('fields.options')}</div>
          <div className="flex flex-wrap gap-1">
            {d.options.map((o) => (
              <span key={o.key} className="flex items-center gap-1 rounded-999 border border-line px-2 py-[3px] text-11">
                {o.label}
                {editable ? (
                  <button
                    type="button"
                    aria-label={t('fields.optionRemove', { name: o.label })}
                    onClick={() => up({ options: d.options.filter((x) => x.key !== o.key) })}
                    className="cursor-pointer border-none bg-transparent p-0 text-11 leading-none text-muted"
                  >
                    ×
                  </button>
                ) : null}
              </span>
            ))}
            {d.options.length === 0 ? <span className="text-11 text-faint">{t('fields.optionsEmpty')}</span> : null}
          </div>
          {editable && !atLimit ? (
            <form
              className="flex gap-1"
              onSubmit={(e) => {
                e.preventDefault()
                const label = newOpt.trim()
                if (!label) return
                up({ options: [...d.options, { key: slug(label, d.options.map((o) => o.key), 'o'), label }] })
                setNewOpt('')
              }}
            >
              <input aria-label={t('fields.optionPlaceholder')} placeholder={t('fields.optionPlaceholder')} value={newOpt} maxLength={80} onChange={(e) => setNewOpt(e.target.value)} className="h-[30px] min-w-0 flex-1 rounded-8 border border-line bg-canvas px-[9px] text-12 text-ink" />
              <button type="submit" disabled={!newOpt.trim()} className={k.ghost}>{t('fields.optionAdd')}</button>
            </form>
          ) : null}
        </div>
      ) : null}
      <label className={row}>
        {t('fields.quality')}
        <select value={d.quality} disabled={!editable || d.type === 'formula'} onChange={(e) => up({ quality: e.target.value as Draft['quality'] })} className={sel}>
          {(['optional', 'important', 'required'] as const).map((q) => (
            <option key={q} value={q}>{t(`fields.qualityOptions.${q}`)}</option>
          ))}
        </select>
      </label>
      {pipelines.length ? (
        <>
          <label className={row}>
            {t('fields.fromStage')}
            <select value={d.from_stage_id ?? ''} disabled={!editable} onChange={(e) => up({ from_stage_id: e.target.value || null })} className={sel}>
              <option value="">{t('fields.anyStage')}</option>
              {pipelines.map((p) => (
                <optgroup key={p.id} label={p.name}>
                  {p.stages.map((s) => (
                    <option key={s.id} value={s.id}>{s.name}</option>
                  ))}
                </optgroup>
              ))}
            </select>
          </label>
          <label className={row}>
            {t('fields.pipelines')}
            <select
              value={!d.pipeline_ids?.length ? '' : d.pipeline_ids.length > 1 ? '__many' : d.pipeline_ids[0]}
              disabled={!editable}
              onChange={(e) => e.target.value !== '__many' && up({ pipeline_ids: e.target.value ? [e.target.value] : null })}
              className={sel}
            >
              <option value="">{t('fields.allPipelines')}</option>
              {d.pipeline_ids && d.pipeline_ids.length > 1 ? (
                <option value="__many">{t('fields.only', { names: d.pipeline_ids.map((id) => pipelines.find((p) => p.id === id)?.name ?? '—').join(', ') })}</option>
              ) : null}
              {pipelines.map((p) => (
                <option key={p.id} value={p.id}>{t('fields.pipelineOnly', { name: p.name })}</option>
              ))}
            </select>
          </label>
        </>
      ) : null}
      <label className={row}>
        {t('fields.readOnlyFor')}
        {setSelect(d.readonly_for, t('fields.readOnlyFor'), t('fields.nobody'), (ids) => up({ readonly_for: ids }))}
      </label>
      <label className={row}>
        {t('fields.hiddenFor')}
        {setSelect(d.hidden_for, t('fields.hiddenFor'), t('fields.nobody'), (ids) => up({ hidden_for: ids }))}
      </label>
      <label className={k.label}>
        {t('fields.description')}
        <textarea
          value={d.description}
          maxLength={300}
          disabled={!editable}
          onChange={(e) => up({ description: e.target.value })}
          className="min-h-[56px] rounded-10 border border-line bg-canvas px-[10px] py-2 text-12.5 font-normal text-ink"
        />
      </label>
      <span className="text-11.5 text-faint">{optionLimit !== null ? t('fields.noteLimited', { count: optionLimit }) : t('fields.note')}</span>
      {editable ? (
        <div className="flex flex-wrap gap-2 pt-1">
          <button type="button" disabled={!valid || pending} onClick={save} className={k.primary}>
            {isNew ? t('fields.create') : t('fields.save')}
          </button>
          {!isNew ? (
            <button
              type="button"
              disabled={pending}
              onClick={() => run(() => saveField({ id: field.id, values: { archived: true } }), () => {
                onArchived()
                return t('fields.archived', { name: field.label })
              })}
              className="h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-coral bg-transparent px-3 text-12 font-semibold text-rust disabled:cursor-default disabled:opacity-60"
            >
              {t('fields.archive')}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
