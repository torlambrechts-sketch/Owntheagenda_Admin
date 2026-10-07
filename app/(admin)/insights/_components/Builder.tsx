'use client'

import type { Route } from 'next'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { NumberFormat } from '@/lib/format'
import {
  BOOL_COLS, DIMS, FILTER_COLS, FIXED_ROWS, NAMED_MEASURES, NUMERIC_COLS, segmentOf, toDefinition,
  type BuilderState, type Cond, type Entity, type Fields, type Op, type ReportResult, type ResultRow,
} from '@/lib/data/insights-shared'
import { fieldsAction, runReportAction, saveReportAction } from '../actions'
import { ReportChart } from './ReportChart'
import { useLabels, type Pickers, type Rights } from './shared'
import type { DrillTarget } from './DrillModal'

const field = 'flex flex-col gap-1 text-11.5 font-semibold text-muted'
const select = 'h-9 rounded-9 border border-line bg-canvas text-12.5 text-ink disabled:opacity-55'
const sentence = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

/**
 * The report builder (design: v.builder): a definition over the field registry (report_fields), previewed
 * live with report_run, saved as a report and a tile. A segment opens its rows, as the footnote promises.
 */
export function Builder({ state, setState, initialFields, rights, pickers, nf, target, onSaved, onDrill }: {
  state: BuilderState
  setState: (s: BuilderState) => void
  initialFields: Fields | null
  rights: Rights
  pickers: Pickers
  nf: NumberFormat
  target: { dashboard: string | null; newName: string }
  onSaved: () => void
  onDrill: (d: DrillTarget) => void
}) {
  const t = useTranslations('insights')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [fields, setFields] = useState<Partial<Record<Entity, Fields>>>(initialFields ? { deal: initialFields } : {})
  const [result, setResult] = useState<ReportResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const seq = useRef(0)
  const f = fields[state.entity]
  const { dim: baseDim, cond } = useLabels(f?.custom ?? [])
  // a campaign's «type» is the campaign type, not an activity type
  const dim = (k: string | null | undefined) => (state.entity === 'campaign' && k === 'type' ? t('dims.campaignType') : baseDim(k))
  // «See reports of others» in the record type's own scope
  const others = state.entity === 'project' ? rights.projectsOthers : state.entity === 'campaign' ? rights.campaignsOthers : rights.others

  useEffect(() => {
    if (fields[state.entity]) return
    void fieldsAction(state.entity).then((r) => { if (r.ok) setFields((x) => ({ ...x, [state.entity]: r.fields })); else setError(r.code) })
  }, [state.entity, fields])

  // the options the registry gives this record type
  const dims = useMemo(() => !f ? [] : [
    ...DIMS.filter((d) => f.dimensions.includes(d)),
    ...f.custom.map((c) => c.key),
  ], [f])
  const measures = useMemo(() => {
    // Products measures line items (0034): lines, quantity, or their value in NOK; Progress counts deals
    if (state.type === 'products') return [{ key: 'count', label: t('measures.lines') }, { key: 'qty', label: t('measures.quantity') }, { key: 'sum', label: t('measures.lineValue') }]
    if (state.type === 'progress') return [{ key: 'count', label: t('measures.dealsMoved') }]
    const out: { key: string; label: string }[] = [{ key: 'count', label: t('measures.count') }]
    if (f?.numeric.includes('value')) out.push({ key: 'sum', label: t('measures.sum') }, { key: 'avg', label: t('measures.avg') })
    for (const c of f?.custom ?? []) if (c.type === 'numerical') out.push({ key: `avg:${c.key}`, label: t('measures.avgCustom', { label: c.label }) })
    // the record type's own measures (report_fields.measures): weighted value for deals, duration for projects, a campaign's figures
    for (const m of f?.measures ?? []) if (NAMED_MEASURES.has(m)) out.push({ key: m, label: t(`measures.${m}` as 'measures.weighted') })
    return out
  }, [f, state.type, t])
  const filterCols = useMemo(() => !f ? [] : [
    ...FILTER_COLS.filter((c) => f.dimensions.includes(c) || f.numeric.includes(c)),
    ...f.custom.filter((c) => ['text', 'numerical', 'single_option', 'large_text'].includes(c.type)).map((c) => c.key),
  ], [f])

  // keep the state inside what the record type offers
  useEffect(() => {
    if (!f) return
    const next = { ...state }
    if (!dims.includes(next.group)) next.group = dims[0] ?? 'owner'
    if (!measures.some((m) => m.key === next.measure)) next.measure = 'count'
    if (next.entity !== 'deal' && next.type !== 'performance') next.type = 'performance'
    if (next.group !== state.group || next.measure !== state.measure || next.type !== state.type) setState(next)
  }, [f, dims, measures, state, setState])

  const def = toDefinition(state)
  const defKey = JSON.stringify(def)
  useEffect(() => {
    if (!def || !f || !rights.see) { setResult(null); return }
    const n = ++seq.current
    const timer = setTimeout(() => {
      void runReportAction(def).then((r) => {
        if (n !== seq.current) return
        if (r.ok) { setResult(r.result); setError(null) } else { setResult(null); setError(r.code) }
      })
    }, 250)
    return () => clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps -- defKey is the definition
  }, [defKey, !!f, rights.see])

  if (!rights.see) return <div className="rounded-20 border border-line bg-surface p-6 text-center text-13 text-muted">{t('noAccess')}</div>

  const set = <K extends keyof BuilderState>(k: K, v: BuilderState[K]) => setState({ ...state, [k]: v })
  // conversion needs a pipeline; progress may run over all of them
  const setType = (type: BuilderState['type']) => setState({ ...state, type, pipeline: type === 'conversion' && !state.pipeline ? (pickers.pipelines[0]?.id ?? '') : state.pipeline })
  const fixed = FIXED_ROWS.has(state.type)
  const periodLabel = t(`periods.${state.period}`)
  const measureLabel = state.type === 'duration' ? t('measures.cycle') : (measures.find((m) => m.key === state.measure)?.label ?? t('measures.count'))
  const title = state.type === 'conversion'
    ? t('builder.titleConv', { period: periodLabel.toLowerCase() })
    : state.type === 'progress' ? (state.chart === 'scorecard' ? t('builder.titleTotal', { measure: measureLabel, period: periodLabel.toLowerCase() }) : t('builder.titleProgress', { period: periodLabel.toLowerCase() }))
    : state.type === 'products' && state.chart !== 'scorecard' ? t('builder.titleProducts', { measure: measureLabel, period: periodLabel.toLowerCase() })
    : state.chart === 'scorecard' ? t('builder.titleTotal', { measure: measureLabel, period: periodLabel.toLowerCase() })
    : t('builder.title', { measure: measureLabel, dim: dim(state.group).toLowerCase(), period: periodLabel.toLowerCase() })

  const save = async () => {
    if (!def) return
    setSaving(true)
    const r = await saveReportAction({ name: sentence(title).slice(0, 120), def, dashboard: target.dashboard, newName: target.newName })
    setSaving(false)
    if (!r.ok) { flash(te(r.code)); return }
    flash(t('builder.saved', { name: r.name }))
    onSaved()
    router.push(`/insights?dashboard=${r.dashboard}` as Route)
    router.refresh()
  }

  const drill = (row: ResultRow, label: string) => {
    if (!def) return
    onDrill({ def, segment: segmentOf(row), title: t('drill.title', { report: sentence(title), segment: label }) })
  }

  // projects and campaigns need their own scope's «see» (and their module); revenue has no report entity yet
  const scoped = { project: rights.projects, campaign: rights.campaigns } as const
  const entityOpts = [...(['deal', 'activity', 'lead', 'person', 'organization'] as const).map((e) => ({ v: e, n: t(`entities.${e}`), off: false })),
    ...(['campaign', 'project'] as const).map((e) => ({ v: e, n: scoped[e] ? t(`entities.${e}`) : t('builder.noRight', { name: t(`entities.${e}`) }), off: !scoped[e] })),
    { v: 'revenue', n: t('builder.notYet', { name: t('entities.revenue') }), off: true }]
  const typeOpts = [
    { v: 'performance', n: t('types.performance'), off: false },
    { v: 'conversion', n: t('types.conversion'), off: state.entity !== 'deal' },
    { v: 'duration', n: t('types.duration'), off: state.entity !== 'deal' },
    { v: 'progress', n: t('types.progress'), off: state.entity !== 'deal' },
    { v: 'products', n: t('types.products'), off: state.entity !== 'deal' },
  ]

  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(260px,320px)_minmax(0,1fr)]">
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
        <label className={field}>{t('builder.entity')}
          <select value={state.entity} onChange={(e) => setState({ ...state, entity: e.target.value as Entity, filters: [] })} className={select}>
            {entityOpts.map((o) => <option key={o.v} value={o.v} disabled={o.off}>{o.n}</option>)}
          </select>
        </label>
        <label className={field}>{t('builder.type')}
          <select value={state.type} onChange={(e) => setType(e.target.value as BuilderState['type'])} className={select}>
            {typeOpts.map((o) => <option key={o.v} value={o.v} disabled={o.off}>{o.n}</option>)}
          </select>
        </label>
        {state.type === 'conversion' || state.type === 'progress' ? (
          <label className={field}>{t('builder.pipeline')}
            <select value={state.pipeline} onChange={(e) => set('pipeline', e.target.value)} className={select}>
              {state.type === 'progress' ? <option value="">{t('builder.allPipelines')}</option> : null}
              {pickers.pipelines.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
        ) : null}
        <label className={field}>{t('builder.groupBy')}
          <select value={fixed ? '' : state.group} disabled={fixed} onChange={(e) => set('group', e.target.value)} className={select}>
            {fixed ? <option value="">{state.type === 'products' ? t('builder.byProduct') : t('builder.byStage')}</option> : null}
            {dims.map((d) => <option key={d} value={d}>{dim(d)}</option>)}
          </select>
        </label>
        <label className={field}>{t('builder.measure')}
          <select value={state.type === 'duration' ? 'cycle' : state.measure} disabled={state.type !== 'performance' && state.type !== 'products'} onChange={(e) => set('measure', e.target.value)} className={select}>
            {state.type === 'duration' ? <option value="cycle">{t('measures.cycle')}</option> : null}
            {measures.map((m) => <option key={m.key} value={m.key}>{m.label}</option>)}
          </select>
        </label>
        <label className={field}>{t('builder.period')}
          <select value={state.period} onChange={(e) => set('period', e.target.value as BuilderState['period'])} className={select}>
            {(['month', 'quarter', 'year', 'custom'] as const).map((p) => <option key={p} value={p}>{t(`periods.${p}`)}</option>)}
          </select>
        </label>
        {state.period === 'custom' ? (
          <div className="grid grid-cols-2 gap-2">
            <label className={field}>{t('builder.from')}<input type="date" value={state.from} onChange={(e) => set('from', e.target.value)} className={`${select} px-2`} /></label>
            <label className={field}>{t('builder.to')}<input type="date" value={state.to} onChange={(e) => set('to', e.target.value)} className={`${select} px-2`} /></label>
          </div>
        ) : null}
        <div className="text-11.5 font-semibold text-muted">{t('builder.chart')}</div>
        <div className="flex flex-wrap gap-[5px]">
          {(['column', 'bar', 'pie', 'scorecard', 'table'] as const).map((c) => (
            <button key={c} type="button" onClick={() => set('chart', c)} aria-pressed={state.chart === c} disabled={state.type === 'conversion'}
              className={`cursor-pointer rounded-999 border px-[11px] py-[5px] text-12 disabled:cursor-default disabled:opacity-55 ${state.chart === c ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>{t(`charts.${c}`)}</button>
          ))}
        </div>
        <div className="text-11.5 font-semibold text-muted">{t('builder.filters')}</div>
        {state.filters.length === 0 ? <div className="rounded-9 border border-line bg-canvas px-[9px] py-[7px] text-12 text-muted">{t('filters.none')}</div> : null}
        {state.filters.map((c, i) => (
          <div key={i} className="flex items-center justify-between gap-2 rounded-9 border border-line bg-canvas px-[9px] py-[7px] text-12">
            <span className="min-w-0">{cond(c)}</span>
            <button type="button" onClick={() => set('filters', state.filters.filter((_, j) => j !== i))} aria-label={t('filters.remove', { filter: cond(c) })}
              className="h-5 w-5 flex-none cursor-pointer rounded-999 border-0 bg-transparent p-0 text-13 text-muted">×</button>
          </div>
        ))}
        <FilterAdd cols={filterCols} label={dim} onAdd={(c) => set('filters', [...state.filters, c])} />
        <div className="flex gap-[6px]">
          <input value={state.color} onChange={(e) => set('color', e.target.value)} aria-label={t('builder.colour')} maxLength={7}
            className="h-[30px] w-[90px] rounded-8 border border-line bg-canvas px-2 text-12 [font-family:ui-monospace,Menlo,monospace]" />
          <span className="self-center text-11.5 text-muted">{t('builder.colour')}</span>
        </div>
        <button type="button" onClick={save} disabled={!def || saving || !result} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary text-13 font-bold disabled:cursor-default disabled:opacity-55">{t('builder.save')}</button>
      </div>
      <div className="flex min-w-0 flex-col gap-3 rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-15">{title}</b>
        {error ? <div className="text-12.5 text-danger">{te(error as 'failed')}</div> : null}
        {!def ? <div className="text-12.5 text-muted">{state.type === 'conversion' ? t('builder.pickPipeline') : t('builder.pickRange')}</div> : null}
        {def && !result && !error ? <div className="flex h-[220px] items-center justify-center text-12.5 text-muted">{t('loading')}</div> : null}
        {def && result ? <ReportChart def={def} result={result} nf={nf} variant="preview" onDrill={drill} /> : null}
        {result?.excluded_currency ? <span className="text-11.5 text-muted">{t('tile.excluded', { count: result.excluded_currency })}</span> : null}
        {!others ? <span className="text-11.5 text-muted">{t(state.entity === 'project' || state.entity === 'campaign' ? `builder.own_${state.entity}` : 'builder.own')}</span> : null}
        <div className="text-11.5 text-faint">{t('builder.footnote')}</div>
      </div>
    </div>
  )
}

/** Add a filter: a column the registry offers, an operator for its kind, and a value. */
function FilterAdd({ cols, label, onAdd }: { cols: string[]; label: (k: string) => string; onAdd: (c: Cond) => void }) {
  const t = useTranslations('insights')
  const [col, setCol] = useState('')
  const [op, setOp] = useState<Op>('eq')
  const [val, setVal] = useState('')
  const numeric = NUMERIC_COLS.has(col)
  const bool = BOOL_COLS.has(col)
  const ops: Op[] = bool ? ['eq'] : numeric ? ['eq', 'neq', 'gt', 'lt', 'empty', 'notempty'] : ['eq', 'neq', 'contains', 'ncontains', 'in', 'empty', 'notempty']
  const needsValue = op !== 'empty' && op !== 'notempty'
  const ready = !!col && (!needsValue || (bool ? val === 'true' || val === 'false' : val.trim() !== '' && (!numeric || !Number.isNaN(Number(val)))))
  const add = () => {
    if (!ready) return
    const v = !needsValue ? undefined : bool ? val === 'true' : numeric ? Number(val) : op === 'in' ? val.split(',').map((x) => x.trim()).filter(Boolean) : val.trim()
    onAdd({ f: col, op, ...(v !== undefined ? { v } : {}) })
    setCol(''); setOp('eq'); setVal('')
  }
  const small = 'h-[30px] min-w-0 rounded-8 border border-line bg-canvas text-12'
  return (
    <div className="flex flex-wrap items-center gap-[6px]">
      <select aria-label={t('filters.field')} value={col} onChange={(e) => { setCol(e.target.value); setOp('eq'); setVal('') }} className={`${small} flex-1`}>
        <option value="">{t('filters.add')}</option>
        {cols.map((c) => <option key={c} value={c}>{label(c)}</option>)}
      </select>
      {col ? (
        <>
          <select aria-label={t('filters.op')} value={op} onChange={(e) => setOp(e.target.value as Op)} className={small}>
            {ops.map((o) => <option key={o} value={o}>{t(`ops.${o}`)}</option>)}
          </select>
          {needsValue ? (bool ? (
            <select aria-label={t('filters.value')} value={val} onChange={(e) => setVal(e.target.value)} className={small}>
              <option value="" />
              <option value="true">{t('filters.yes')}</option>
              <option value="false">{t('filters.no')}</option>
            </select>
          ) : (
            <input aria-label={t('filters.value')} value={val} onChange={(e) => setVal(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') add() }}
              inputMode={numeric ? 'decimal' : undefined} placeholder={op === 'in' ? t('filters.inHint') : t('filters.value')} className={`${small} w-[110px] px-2`} />
          )) : null}
          <button type="button" onClick={add} disabled={!ready} className="h-[30px] cursor-pointer rounded-8 border border-ink bg-surface px-[10px] text-12 font-bold disabled:cursor-default disabled:opacity-55">{t('filters.addBtn')}</button>
        </>
      ) : null}
    </div>
  )
}
