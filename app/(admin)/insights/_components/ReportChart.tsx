'use client'

import { useFormatter, useTranslations } from 'next-intl'
import type { NumberFormat } from '@/lib/format'
import { delta, figure, palette, type ReportResult, type ResultRow, type StoredDefinition } from '@/lib/data/insights-shared'

type Variant = 'tile' | 'preview'
export type Point = { row: ResultRow; label: string; v: number; vl: string; h: number; c: string }

/** A segment's label: first names for owners (design: name.split(' ')[0]), months written out, «(none)» for a missing value. */
export function useRowLabel() {
  const t = useTranslations('insights')
  const format = useFormatter()
  return (def: StoredDefinition, r: ResultRow) => {
    const dim = def.group_by ?? ''
    let l = r.label
    if (l && dim === 'owner') l = l.split(' ')[0] ?? l
    if (l && /_month$/.test(dim) && /^\d{4}-\d{2}$/.test(l)) l = format.dateTime(new Date(`${l}-15T12:00:00Z`), { month: 'short', year: 'numeric' })
    if (l && dim === 'status' && ['open', 'won', 'lost'].includes(l)) l = t(`status.${l}` as 'status.open')
    const base = l ?? (def.type === 'products' && r.key === null ? t('noItem') : t('none'))
    return r.segment_label ? `${base} · ${r.segment_label}` : base
  }
}

/**
 * One renderer per chart type (Insights.dc.html chartOf): column, bar, pie, scorecard and table, in the
 * tile size or the builder's larger preview. Every figure is the result's; a segment opens its rows.
 */
export function ReportChart({ def, result, nf, variant, onDrill }: {
  def: StoredDefinition
  result: ReportResult
  nf: NumberFormat
  variant: Variant
  onDrill?: (row: ResultRow, label: string) => void
}) {
  const t = useTranslations('insights')
  const rowLabel = useRowLabel()
  const big = variant === 'preview'
  const chart = def.chart ?? 'column'
  const viz = palette(def.color)
  const conversion = def.type === 'conversion'

  if (chart === 'scorecard' && !conversion) {
    const d = delta(result.unit, result.total, result.previous, nf)
    return (
      <>
        <div className="flex items-baseline gap-[10px]">
          <span className={`font-serif font-semibold ${big ? 'text-56' : 'text-34'}`}>{figure(result.unit, result.total, nf)}</span>
          {d ? <span className={`font-bold ${big ? 'text-14' : 'text-13'} ${d.good ? 'text-link' : 'text-danger'}`}>{d.text}</span> : null}
        </div>
        {!big ? (
          <span className="text-11.5 text-muted">
            {d ? (def.period ? t('tile.vsPrevious') : t('tile.vs30'))
              : result.previous !== null && result.previous !== undefined ? t('tile.previousWas', { value: figure(result.unit, result.previous, nf) })
              : def.period ? t('tile.noPrevious') : t('tile.noSnapshot')}
          </span>
        ) : null}
      </>
    )
  }

  // stage conversion: «Qualified → Discovery», the share of the deals that entered a stage and reached the next
  if (conversion) {
    if (result.rows.length === 0) return <Empty variant={variant} />
    return (
      <div className="flex flex-col">
        {result.rows.map((r, i) => {
          const next = result.rows[i + 1]
          const label = t('conv.step', { from: r.label ?? t('none'), to: next ? (next.label ?? t('none')) : t('conv.won') })
          const cls = `flex justify-between gap-[10px] border-b border-line text-12.5 ${big ? 'py-[7px]' : 'py-[6px]'}`
          const body = <><span>{label}</span><b>{figure('percent', r.value, nf)}</b></>
          // a row opens the deals that entered the stage in the period (0034)
          return onDrill
            ? <button key={r.key ?? i} type="button" onClick={() => onDrill(r, r.label ?? t('none'))} title={t('conv.entered', { count: r.entered ?? 0 })}
                className={`${cls} cursor-pointer bg-transparent px-0 text-left`}>{body}</button>
            : <div key={r.key ?? i} className={cls} title={t('conv.entered', { count: r.entered ?? 0 })}>{body}</div>
        })}
      </div>
    )
  }

  if (result.rows.length === 0) return <Empty variant={variant} />
  const values = result.rows.map((r) => r.value ?? 0)
  const max = Math.max(...values, 1)
  const tot = values.reduce((a, b) => a + b, 0) || 1
  const pts: Point[] = result.rows.map((r, i) => ({
    row: r, label: rowLabel(def, r), v: values[i]!, vl: figure(result.unit, r.value, nf, chart !== 'table'), h: (values[i]! / max) * 88 + 2, c: viz[i % viz.length]!,
  }))
  const drill = (p: Point) => (onDrill ? () => onDrill(p.row, p.label) : undefined)
  const plain = 'border-0 bg-transparent p-0'

  if (chart === 'bar') {
    return (
      <div className={`flex flex-col ${big ? 'gap-[7px]' : 'gap-[6px]'}`}>
        {pts.map((p, i) => (
          <button key={i} type="button" onClick={drill(p)} title={`${p.label}: ${p.vl}`}
            className={`${plain} grid cursor-pointer items-center gap-2 text-left ${big ? 'text-12.5 [grid-template-columns:140px_minmax(0,1fr)_70px]' : 'text-12 [grid-template-columns:110px_minmax(0,1fr)_60px]'}`}>
            <span className="overflow-hidden text-ellipsis whitespace-nowrap">{p.label}</span>
            <span className={`overflow-hidden rounded-5 bg-tile ${big ? 'h-4' : 'h-[14px]'}`}><span className="block h-full" style={{ width: `${p.h}%`, background: p.c }} /></span>
            <b className="text-right">{p.vl}</b>
          </button>
        ))}
      </div>
    )
  }

  if (chart === 'pie') {
    let acc = 0
    const conic = `conic-gradient(${pts.map((p) => { const a0 = acc; acc += (p.v / tot) * 360; return `${p.c} ${a0}deg ${acc}deg` }).join(',')})`
    return (
      <div className={`flex items-center ${big ? 'gap-[18px]' : 'gap-4'}`}>
        <span className={`flex-none rounded-999 ${big ? 'h-[180px] w-[180px]' : 'h-[120px] w-[120px] border border-line'}`} style={{ background: conic }} />
        <div className={`flex flex-col ${big ? 'gap-[6px]' : 'gap-[5px]'}`}>
          {pts.map((p, i) => (
            <button key={i} type="button" onClick={drill(p)} className={`${plain} flex cursor-pointer items-center gap-[7px] text-left ${big ? 'text-12.5' : 'text-12'}`}>
              <span className="h-[10px] w-[10px] flex-none rounded-3" style={{ background: p.c }} />{p.label} <b>{p.vl}</b>
            </button>
          ))}
        </div>
      </div>
    )
  }

  if (chart === 'table') {
    return (
      <div className="flex flex-col">
        {pts.map((p, i) => (
          <button key={i} type="button" onClick={drill(p)} className={`flex cursor-pointer justify-between gap-[10px] border-b border-line bg-transparent px-0 text-left text-12.5 ${big ? 'py-[7px]' : 'py-[6px]'}`}>
            <span>{p.label}</span><b>{p.vl}</b>
          </button>
        ))}
      </div>
    )
  }

  // column (and a stacked definition, drawn as its columns)
  return (
    <div className={`flex items-end ${big ? 'h-[220px] gap-2' : 'h-[150px] gap-[6px]'}`}>
      {pts.map((p, i) => (
        <button key={i} type="button" onClick={drill(p)} title={`${p.label}: ${p.vl}`}
          className={`${plain} flex h-full min-w-0 flex-1 cursor-pointer flex-col items-center justify-end gap-1`}>
          <b className={big ? 'text-11' : 'text-10.5'}>{p.vl}</b>
          <span className={`w-full rounded-[6px_6px_0_0] ${big ? '' : 'border border-[rgba(25,21,16,.1)]'}`} style={{ height: `${p.h}%`, background: p.c }} />
          <span className={`max-w-full overflow-hidden text-ellipsis whitespace-nowrap text-muted ${big ? 'text-10.5' : 'text-10'}`}>{p.label}</span>
        </button>
      ))}
    </div>
  )
}

/** A report with no rows: the period holds no matching records (D-41, in the design's muted text). */
function Empty({ variant }: { variant: Variant }) {
  const t = useTranslations('insights')
  return (
    <div className={`flex items-center justify-center rounded-14 border border-dashed border-line-strong px-4 text-center text-12.5 text-muted ${variant === 'preview' ? 'h-[220px]' : 'min-h-[96px]'}`}>
      {t('tile.noRows')}
    </div>
  )
}
