'use client'

import { useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { ui } from '@/components/ui/styles'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { COUNT_OPS, CRIT_FIELDS, GROUPS, PAYMENT_STATES, type CritField, type Group } from '@/lib/data/feed-shared'
import type { PreviewRecord, ScoreModel, ScorePreview } from '@/lib/data/feed'
import { activateModel, addCriterion, createModel, removeCriterion, type CritSpec } from '../actions'
import { useErr, useGo } from './go'

const GROUP_TONE: Record<Group, string> = { high: 'bg-ok-bg text-ok-ink', slight: 'bg-teal-soft text-ok-ink', negative: 'bg-peach text-rust-ink' }
const signed = (n: number) => (n >= 0 ? `+${n}` : `−${Math.abs(n)}`)
const msgKey = (k: string) => k.replace(/[._](\w)/g, (_, c: string) => c.toUpperCase())

/** Feed › Scoring models (Feed.dc.html, v.scoring): models, their criteria by group, and a preview on a record. */
export function ScoringView({ models, limit, model, records, record, preview, pipelines, labels, canConfigure, nf }: {
  models: ScoreModel[]
  limit: number | null
  model: ScoreModel | null
  records: PreviewRecord[]
  record: string | null
  preview: ScorePreview | null
  pipelines: { id: string; name: string }[]
  labels: { id: string; name: string }[]
  canConfigure: boolean
  nf: NumberFormat
}) {
  const t = useTranslations('feed.scoring')
  const flash = useToast()
  const err = useErr()
  const { go } = useGo()
  const [busy, start] = useTransition()
  const [adding, setAdding] = useState<Group | null>(null)

  const sub = (m: ScoreModel) => [t(`entity.${m.entity}`), m.entity === 'deal' ? (m.pipeline ? t('pipeline', { name: m.pipeline }) : t('allPipelines')) : null, t(`state.${m.state}`)]
    .filter(Boolean).join(' · ')
  const hits = new Set(preview?.hits.map((h) => h.criterion) ?? [])
  const label = (c: ScoreModel['criteria'][number]) => c.label ?? t('unlabeled')

  const toggle = () => model && start(async () => {
    const r = await activateModel({ id: model.id, active: model.state !== 'active' })
    flash(r.ok ? t(model.state === 'active' ? 'toast.deactivated' : 'toast.activated') : err(r.code))
  })
  const remove = (id: string) => model && start(async () => {
    const r = await removeCriterion({ modelId: model.id, criterionId: id })
    flash(r.ok ? t('toast.removed') : err(r.code))
  })

  const score = preview?.score ?? null
  const scoreTone = score === null ? 'text-faint' : score >= 70 ? 'text-link' : score >= 40 ? 'text-warn-ink' : 'text-danger'

  return (
    <div className="grid items-start gap-[14px] lg:[grid-template-columns:minmax(220px,260px)_minmax(0,1fr)_minmax(260px,320px)]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        {models.map((m) => (
          <button
            key={m.id}
            type="button"
            aria-pressed={model?.id === m.id}
            onClick={() => { setAdding(null); go({ model: m.id, record: null }) }}
            className={`flex w-full cursor-pointer flex-col gap-[2px] border-b border-line px-[14px] py-3 text-left ${model?.id === m.id ? 'bg-highlight' : 'bg-transparent'}`}
          >
            <b className="text-13">{m.name}</b>
            <span className="text-11.5 text-muted">{sub(m)}</span>
          </button>
        ))}
        <div className="px-[14px] py-[10px] text-11.5 text-muted">
          {limit === null ? t('limitNone') : t('limit', { used: models.length, limit: formatNumber(limit, nf) })}
        </div>
        {canConfigure && (limit === null || models.length < limit) ? <NewModel pipelines={pipelines} /> : null}
      </div>

      <div className="flex min-w-0 flex-col gap-3">
        {model ? (
          <div className="flex flex-wrap items-center justify-between gap-2 text-12 text-muted">
            <span>{t('summary', { base: model.base, scored: model.scored })}</span>
            {canConfigure ? (
              <button type="button" disabled={busy} onClick={toggle} className={`${ui.btnSmall} disabled:opacity-50`}>
                {t(model.state === 'active' ? 'deactivate' : 'activate')}
              </button>
            ) : null}
          </div>
        ) : null}
        {model ? GROUPS.map((g) => {
          const crit = model.criteria.filter((c) => c.group === g)
          return (
            <div key={g} className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-4 py-[14px]">
              <div className="flex items-center justify-between">
                <b className="text-13.5">{t(`groups.${g}`)}</b>
                <span className={`rounded-999 px-[10px] py-[3px] text-12 font-bold ${GROUP_TONE[g]}`}>{signed(model.points[g])}</span>
              </div>
              {crit.map((c) => {
                const hit = hits.has(c.id)
                return (
                  <div key={c.id} className="flex items-center gap-2 rounded-10 border border-line bg-canvas px-[10px] py-[6px] text-12.5">
                    <span className="w-[30px] shrink-0 text-10.5 font-bold text-muted">{t('if')}</span>
                    <span className="flex-1">{label(c)}</span>
                    <span className={`font-bold ${hit ? (g === 'negative' ? 'text-danger' : 'text-link') : 'text-faint'}`}>{hit ? t('matches') : '—'}</span>
                    {canConfigure ? (
                      <button type="button" disabled={busy} onClick={() => remove(c.id)} aria-label={t('remove', { name: label(c) })} className="cursor-pointer border-none bg-transparent px-1 text-faint">×</button>
                    ) : null}
                  </div>
                )
              })}
              {adding === g ? (
                <CriterionPicker model={model} group={g} labels={labels} nf={nf} onDone={() => setAdding(null)} />
              ) : (
                <button
                  type="button"
                  disabled={!canConfigure}
                  title={canConfigure ? undefined : t('noRight')}
                  onClick={() => setAdding(g)}
                  className="h-7 cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-50"
                >
                  {t('addCriterion')}
                </button>
              )}
            </div>
          )
        }) : <div className="rounded-20 border border-dashed border-line-strong p-[34px] text-center text-13 text-muted">{t('noModels')}</div>}
      </div>

      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('preview')}</b>
        <select
          aria-label={t('previewRecord')}
          value={record ?? ''}
          disabled={records.length === 0}
          onChange={(e) => go({ record: e.target.value })}
          className="h-[34px] rounded-9 border border-line bg-canvas text-12.5"
        >
          {records.length === 0 ? <option value="">{t(model?.entity === 'lead' ? 'noLeads' : 'noDeals')}</option> : null}
          {records.map((r) => <option key={r.id} value={r.id}>{r.title}</option>)}
        </select>
        <div className="flex items-baseline gap-2">
          <span className={`font-serif text-48 font-semibold leading-none ${scoreTone}`}>{score ?? '—'}</span>
          <span className="text-12.5 text-muted">/ 100</span>
        </div>
        {model ? GROUPS.flatMap((g) => model.criteria.filter((c) => c.group === g)).map((c) => {
          const hit = hits.has(c.id)
          const tone = hit ? (c.group === 'negative' ? 'text-danger' : 'text-ok-ink') : 'text-faint'
          return (
            <div key={c.id} className="flex justify-between gap-2 text-12">
              <span className={tone}>{hit ? '✓' : '○'} {label(c)}</span>
              <b className={tone}>{signed(model.points[c.group])}</b>
            </div>
          )
        }) : null}
        <div className="text-11.5 text-faint">{t('healthNote')}</div>
      </div>
    </div>
  )
}

function NewModel({ pipelines }: { pipelines: { id: string; name: string }[] }) {
  const t = useTranslations('feed.scoring.new')
  const flash = useToast()
  const err = useErr()
  const { go } = useGo()
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [entity, setEntity] = useState<'deal' | 'lead'>('deal')
  const [pipeline, setPipeline] = useState<string>(pipelines[0]?.id ?? '')
  const [busy, start] = useTransition()
  const create = () => start(async () => {
    const r = await createModel({ name, entity, pipelineId: entity === 'deal' && pipeline ? pipeline : null })
    if (!r.ok) { flash(err(r.code)); return }
    setOpen(false); setName('')
    flash(t('created'))
    go({ model: r.id, record: null })
  })
  if (!open) {
    return (
      <div className="px-[14px] pb-3">
        <button type="button" onClick={() => setOpen(true)} className="h-7 cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{t('button')}</button>
      </div>
    )
  }
  return (
    <div className="flex flex-col gap-2 border-t border-line px-[14px] py-3">
      <input aria-label={t('name')} placeholder={t('name')} value={name} maxLength={120} onChange={(e) => setName(e.target.value)} className={`${ui.select} px-2`} />
      <select aria-label={t('entity')} value={entity} onChange={(e) => setEntity(e.target.value === 'lead' ? 'lead' : 'deal')} className={`${ui.select} px-1`}>
        <option value="deal">{t('deals')}</option>
        <option value="lead">{t('leads')}</option>
      </select>
      {entity === 'deal' ? (
        <select aria-label={t('pipeline')} value={pipeline} onChange={(e) => setPipeline(e.target.value)} className={`${ui.select} px-1`}>
          <option value="">{t('allPipelines')}</option>
          {pipelines.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
      ) : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={() => setOpen(false)} className={ui.btnSmall}>{t('cancel')}</button>
        <button type="button" disabled={busy || !name.trim()} onClick={create} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-50">{t('create')}</button>
      </div>
    </div>
  )
}

/** «＋ Criterion»: a field picker over the tests app.wf_match makes. Not wired in the prototype; built in its language. */
function CriterionPicker({ model, group, labels, nf, onDone }: { model: ScoreModel; group: Group; labels: { id: string; name: string }[]; nf: NumberFormat; onDone: () => void }) {
  const t = useTranslations('feed.scoring.picker')
  const flash = useToast()
  const err = useErr()
  const fields = CRIT_FIELDS.filter((f) => f.entities.includes(model.entity) && (f.key !== 'participant_label' || labels.length > 0))
  const [key, setKey] = useState<CritField['key']>(fields[0]!.key)
  const [days, setDays] = useState('7')
  const [labelId, setLabelId] = useState(labels[0]?.id ?? '')
  const [op, setOp] = useState<(typeof COUNT_OPS)[number]>('gte')
  const [n, setN] = useState('2')
  const [state, setState] = useState<(typeof PAYMENT_STATES)[number]>('past_due')
  const [list, setList] = useState('')
  const [min, setMin] = useState('')
  const [max, setMax] = useState('')
  const [text, setText] = useState('')
  const [busy, start] = useTransition()
  const field = fields.find((f) => f.key === key)!

  const toNum = (s: string) => (s.trim() === '' || Number.isNaN(Number(s)) ? null : Number(s))
  // the spec and the label it is shown with, in the staff member's language
  const build = (): { spec: CritSpec; label: string } | null => {
    switch (field.input) {
      case 'days': {
        const d = toNum(days)
        if (d === null || d < 1 || d > 365 || !Number.isInteger(d)) return null
        return { spec: { key: field.key, days: d }, label: t(`label.${msgKey(field.key)}`, { days: d }) }
      }
      case 'label': {
        const l = labels.find((x) => x.id === labelId)
        return l ? { spec: { key: 'participant_label', label: l.id }, label: t('label.participantLabel', { label: l.name }) } : null
      }
      case 'count': {
        const c = toNum(n)
        if (c === null || c < 0 || !Number.isInteger(c)) return null
        return { spec: { key: 'org_products', op, n: c }, label: t('label.orgProducts', { op, n: c }) }
      }
      case 'payment':
        return { spec: { key: 'org_payment', state }, label: t('label.orgPayment', { state: t(`payment.${state}`) }) }
      case 'list': {
        const values = list.split(',').map((x) => x.trim()).filter(Boolean)
        return values.length ? { spec: { key: 'source', values }, label: t('label.source', { list: values.join(t('or')) }) } : null
      }
      case 'range': {
        const a = toNum(min), b = toNum(max)
        if ((a === null && b === null) || (a !== null && a < 0) || (b !== null && b < 0)) return null
        const which = a !== null && b !== null ? 'between' : a !== null ? 'atLeast' : 'atMost'
        const fmt = (v: number | null) => (v === null ? '' : formatNumber(v, nf))
        return { spec: { key: field.key, min: a, max: b }, label: t(`label.${msgKey(field.key)}.${which}`, { min: fmt(a), max: fmt(b) }) }
      }
      case 'text':
        return text.trim() ? { spec: { key: field.key, text: text.trim() }, label: t('label.orgText', { field: t(`fields.${msgKey(field.key)}`), text: text.trim() }) } : null
    }
  }
  const b = build()
  const add = () => b && start(async () => {
    const r = await addCriterion({ modelId: model.id, group, label: b.label.slice(0, 120), spec: b.spec })
    if (!r.ok) { flash(err(r.code)); return }
    flash(t('added'))
    onDone()
  })
  const input = `${ui.select} px-2`
  return (
    <div className="flex flex-col gap-2 rounded-10 border border-line bg-canvas px-[10px] py-2 text-12.5">
      <div className="flex flex-wrap items-center gap-2">
        <span className="w-[30px] shrink-0 text-10.5 font-bold text-muted">{t('if')}</span>
        <select aria-label={t('field')} value={key} onChange={(e) => setKey(e.target.value as CritField['key'])} className={`${ui.select} bg-surface px-1`}>
          {fields.map((f) => <option key={f.key} value={f.key}>{t(`fields.${msgKey(f.key)}`)}</option>)}
        </select>
        {field.input === 'days' ? (
          <label className="flex items-center gap-1">{t('within')}<input type="number" min={1} max={365} value={days} onChange={(e) => setDays(e.target.value)} className={`${input} w-[64px] bg-surface`} />{t('days')}</label>
        ) : null}
        {field.input === 'label' ? (
          <select aria-label={t('personLabel')} value={labelId} onChange={(e) => setLabelId(e.target.value)} className={`${ui.select} bg-surface px-1`}>
            {labels.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </select>
        ) : null}
        {field.input === 'count' ? (
          <>
            <select aria-label={t('op')} value={op} onChange={(e) => setOp(e.target.value as (typeof COUNT_OPS)[number])} className={`${ui.select} bg-surface px-1`}>
              {COUNT_OPS.map((o) => <option key={o} value={o}>{t(`ops.${o}`)}</option>)}
            </select>
            <input aria-label={t('count')} type="number" min={0} max={100} value={n} onChange={(e) => setN(e.target.value)} className={`${input} w-[64px] bg-surface`} />
          </>
        ) : null}
        {field.input === 'payment' ? (
          <select aria-label={t('paymentState')} value={state} onChange={(e) => setState(e.target.value as (typeof PAYMENT_STATES)[number])} className={`${ui.select} bg-surface px-1`}>
            {PAYMENT_STATES.map((s) => <option key={s} value={s}>{t(`payment.${s}`)}</option>)}
          </select>
        ) : null}
        {field.input === 'list' ? (
          <input aria-label={t('values')} placeholder={t('valuesHint')} value={list} maxLength={400} onChange={(e) => setList(e.target.value)} className={`${input} min-w-[180px] flex-1 bg-surface`} />
        ) : null}
        {field.input === 'range' ? (
          <>
            <input aria-label={t('min')} placeholder={t('min')} type="number" min={0} value={min} onChange={(e) => setMin(e.target.value)} className={`${input} w-[90px] bg-surface`} />
            <span>–</span>
            <input aria-label={t('max')} placeholder={t('max')} type="number" min={0} value={max} onChange={(e) => setMax(e.target.value)} className={`${input} w-[90px] bg-surface`} />
          </>
        ) : null}
        {field.input === 'text' ? (
          <input aria-label={t('text')} placeholder={t('contains')} value={text} maxLength={80} onChange={(e) => setText(e.target.value)} className={`${input} min-w-[140px] flex-1 bg-surface`} />
        ) : null}
      </div>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-11.5 text-muted">{b ? b.label : t('incomplete')}</span>
        <span className="flex gap-2">
          <button type="button" onClick={onDone} className={ui.btnSmall}>{t('cancel')}</button>
          <button type="button" disabled={busy || !b} onClick={add} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-50">{t('add')}</button>
        </span>
      </div>
    </div>
  )
}
