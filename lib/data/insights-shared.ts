import { z } from 'zod'
import { formatNumber, money, percent, thousands, type NumberFormat } from '@/lib/format'

/**
 * Insights (Insights.dc.html): the report definition and result shapes shared by the screen, its server
 * actions and its loaders. A definition is what app.report_run (0024) compiles over its whitelist; the
 * schema here only bounds the shape, the database decides what is valid.
 */
/** The screen's tabs, in the design's order. */
export const TABS = ['dash', 'builder', 'goals', 'forecast', 'ai'] as const
export type Tab = (typeof TABS)[number]

export const ENTITIES = ['deal', 'activity', 'lead', 'person', 'organization', 'project', 'campaign'] as const
export type Entity = (typeof ENTITIES)[number]
export const TYPES = ['performance', 'conversion', 'duration', 'progress', 'products'] as const
export const CHARTS = ['column', 'bar', 'pie', 'scorecard', 'table', 'stacked'] as const
export type Chart = (typeof CHARTS)[number]
export const PERIODS = ['month', 'quarter', 'year', 'last_30', 'last_90', 'last_365', 'custom', 'all'] as const
export type PeriodKind = (typeof PERIODS)[number]
/** Measures: count, sum and avg over a field, and the ones a record type adds (report_fields.measures; 0040: project, campaign). */
export const MEASURE_FNS = ['count', 'sum', 'avg', 'weighted', 'cycle_days', 'duration_days', 'sent', 'open_rate', 'click_rate'] as const
/** The record-type measures the builder offers by name (a message key insights.measures.<fn>). */
export const NAMED_MEASURES = new Set<string>(['weighted', 'duration_days', 'sent', 'open_rate', 'click_rate'])
export const OPS = ['eq', 'neq', 'in', 'contains', 'ncontains', 'gt', 'gte', 'lt', 'lte', 'empty', 'notempty'] as const
export type Op = (typeof OPS)[number]

const col = z.string().regex(/^(custom\.)?[a-z_][a-z0-9_]{0,40}$/)
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
export const Cond = z.object({ f: col, op: z.enum(OPS), v: z.union([z.string().max(200), z.number(), z.boolean(), z.array(z.string().max(200)).max(50)]).optional() })
export type Cond = z.infer<typeof Cond>
export const Filter = z.union([Cond, z.object({ or: z.array(z.array(Cond).max(20)).min(1).max(10) })])
export type Filter = z.infer<typeof Filter>

/** The strict form: what a server action accepts from the browser. */
export const Definition = z.object({
  entity: z.enum(ENTITIES),
  type: z.enum(TYPES).optional(),
  measure: z.object({ fn: z.enum(MEASURE_FNS), field: col.optional() }).optional(),
  group_by: col.nullable().optional(),
  segment_by: col.nullable().optional(),
  filters: z.array(Filter).max(20).optional(),
  period: z.object({ kind: z.enum(PERIODS), field: col.optional(), from: day.optional(), to: day.optional() }).optional(),
  chart: z.enum(CHARTS).optional(),
  pipeline_id: z.string().uuid().optional(),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  sort: z.literal('label').optional(),
  include_archived: z.boolean().optional(),
})
export type Definition = z.infer<typeof Definition>

/** A stored definition as the database returns it: the same fields, other keys kept. */
export const StoredDefinition = z.object({
  entity: z.string(),
  type: z.string().optional(),
  measure: z.object({ fn: z.string(), field: z.string().optional() }).passthrough().optional(),
  group_by: z.string().nullable().optional(),
  segment_by: z.string().nullable().optional(),
  filters: z.array(z.unknown()).optional(),
  period: z.object({ kind: z.string(), field: z.string().optional(), from: z.string().optional(), to: z.string().optional() }).passthrough().optional(),
  chart: z.string().optional(),
  pipeline_id: z.string().optional(),
  color: z.string().optional(),
}).passthrough()
export type StoredDefinition = z.infer<typeof StoredDefinition>

const num = z.coerce.number()
export const ResultRow = z.object({
  key: z.string().nullable(),
  label: z.string().nullable(),
  segment: z.string().nullable().optional(),
  segment_label: z.string().nullable().optional(),
  value: num.nullable(),
  entered: num.optional(),
})
export type ResultRow = z.infer<typeof ResultRow>
export const Unit = z.enum(['nok', 'count', 'days', 'percent'])
export type Unit = z.infer<typeof Unit>
export const ReportResult = z.object({
  rows: z.array(ResultRow),
  total: num.nullable().optional(),
  previous: num.nullable().optional(),
  excluded_currency: num.optional(),
  unit: Unit,
})
export type ReportResult = z.infer<typeof ReportResult>
export const TileResult = z.union([ReportResult, z.object({ error: z.string() })])
export type TileResult = z.infer<typeof TileResult>

export const DrillRow = z.object({
  id: z.string().uuid(),
  title: z.string().nullable(),
  owner: z.string().nullable(),
  value: num.nullable(),
  currency: z.string().nullable(),
  created_at: z.string(),
})
export type DrillRow = z.infer<typeof DrillRow>

export const Fields = z.object({
  dimensions: z.array(z.string()),
  numeric: z.array(z.string()),
  dates: z.array(z.string()),
  custom: z.array(z.object({ key: z.string(), label: z.string(), type: z.string() })),
  measures: z.array(z.string()).default([]),
})
export type Fields = z.infer<typeof Fields>

// ---------------------------------------------------------------------------
// the design's chart palette (Insights.dc.html chartOf: viz)
export const VIZ = ['#F5C64A', '#DCEBD3', '#CFE0F5', '#F6D9C6', '#E7DAF2', '#F3E2C9', '#B5DAD4', '#EC9B77']
export const palette = (color?: string) => (color && /^#[0-9A-Fa-f]{6}$/.test(color) ? [color, ...VIZ.slice(1)] : VIZ)

/** The dimensions the builder offers, in its order, each with a message key (others in the registry are not offered). */
export const DIMS = ['owner', 'stage', 'board', 'phase', 'source', 'lost_reason', 'label', 'pipeline', 'type', 'status', 'health', 'product', 'created_month', 'won_month',
  'close_month', 'done_month', 'priority', 'contact_type', 'marketing_status', 'industry', 'fylke', 'city', 'country', 'currency'] as const
/** Columns a filter can test, with a message key: text and numbers (references need a picker the design does not draw). */
export const FILTER_COLS = ['status', 'health', 'source', 'lost_reason', 'product', 'currency', 'value', 'score', 'priority', 'done', 'contact_type',
  'marketing_status', 'industry', 'fylke', 'city', 'country', 'employees', 'duration_min', 'title', 'name', 'subject'] as const
export const NUMERIC_COLS = new Set(['value', 'score', 'employees', 'duration_min'])
export const BOOL_COLS = new Set(['done'])

/** Tile spans run 3–12 in steps of 2 (design: rs). Listed whole so the classes exist. */
export const SPAN: Record<number, string> = {
  3: 'md:col-span-3', 4: 'md:col-span-4', 5: 'md:col-span-5', 6: 'md:col-span-6', 7: 'md:col-span-7', 8: 'md:col-span-8',
  9: 'md:col-span-9', 10: 'md:col-span-10', 11: 'md:col-span-11', 12: 'md:col-span-12',
}

/** A figure the way the design writes it: chart labels short («1 849k»), cards and tables whole («312 000 kr»). */
export function figure(unit: Unit, v: number | null | undefined, nf: NumberFormat, short = false): string {
  if (v === null || v === undefined || Number.isNaN(v)) return '—'
  switch (unit) {
    case 'nok': return short ? thousands(v, nf) : money(v, nf)
    case 'days': return `${formatNumber(v, nf, Number.isInteger(v) ? 0 : 1)} d`
    case 'percent': return percent(v, nf)
    default: return formatNumber(v, nf, Number.isInteger(v) ? 0 : 1)
  }
}

/** The change against the previous period: a percent for amounts and counts, days for a duration. Null when there is nothing to compare. */
export function delta(unit: Unit, total: number | null | undefined, previous: number | null | undefined, nf: NumberFormat): { text: string; good: boolean } | null {
  if (total === null || total === undefined || previous === null || previous === undefined) return null
  if (unit === 'days') {
    const d = Math.round((total - previous) * 10) / 10
    // a shorter cycle is the better one
    return { text: `${d > 0 ? '+' : d < 0 ? '−' : '±'}${formatNumber(Math.abs(d), nf, Number.isInteger(d) ? 0 : 1)} d`, good: d <= 0 }
  }
  if (previous === 0) return null
  const p = Math.round(((total - previous) / Math.abs(previous)) * 100)
  return { text: `${p > 0 ? '+' : p < 0 ? '−' : '±'}${formatNumber(Math.abs(p), nf)} %`, good: p >= 0 }
}

/** A row's key and segment, as report_drill takes them. */
export const segmentOf = (r: ResultRow) => ({ key: r.key, ...(r.segment !== undefined && r.segment !== null ? { segment: r.segment } : {}) })

// ---------------------------------------------------------------------------
// the builder's state and the definition it describes
type Period = 'month' | 'quarter' | 'year' | 'custom'
type Kind = 'performance' | 'conversion' | 'duration' | 'progress' | 'products'
type ChartKind = 'column' | 'bar' | 'pie' | 'scorecard' | 'table'
export type BuilderState = {
  entity: Entity; type: Kind; group: string; measure: string; period: Period; from: string; to: string
  chart: ChartKind; filters: Cond[]; color: string; pipeline: string
}
const DEFAULT_COLOR = '#F5C64A'
export const initialBuilder = (pipeline: string): BuilderState => ({
  entity: 'deal', type: 'performance', group: 'owner', measure: 'sum', period: 'quarter', from: '', to: '', chart: 'column', filters: [], color: DEFAULT_COLOR, pipeline,
})

/** Types that report one row per stage or catalog item rather than by a chosen dimension (0034). */
export const FIXED_ROWS = new Set(['conversion', 'progress', 'products'])

/** The definition the state describes, or null while a custom range is incomplete. */
export function toDefinition(s: BuilderState): Definition | null {
  if (s.period === 'custom' && (!s.from || !s.to || s.from > s.to)) return null
  // the period runs on the created date; on the won date for Duration and Products; Progress on the stage change; a
  // campaign's figures on the day it was sent (sent, open and click rates)
  const sentFigures = s.entity === 'campaign' && ['sent', 'open_rate', 'click_rate'].includes(s.measure)
  const field = s.type === 'duration' || s.type === 'products' ? 'won_at' : sentFigures ? 'sent_at' : 'created_at'
  const period = { kind: s.period, ...(s.type === 'progress' ? {} : { field }), ...(s.period === 'custom' ? { from: s.from, to: s.to } : {}) }
  const color = /^#[0-9A-Fa-f]{6}$/.test(s.color) && s.color.toUpperCase() !== DEFAULT_COLOR ? { color: s.color } : {}
  if (s.type === 'conversion') {
    if (!s.pipeline) return null
    return { entity: 'deal', type: 'conversion', pipeline_id: s.pipeline, period, chart: 'table', filters: s.filters, ...color }
  }
  if (s.type === 'progress') {
    return { entity: 'deal', type: 'progress', measure: { fn: 'count' }, ...(s.pipeline ? { pipeline_id: s.pipeline } : {}), period, chart: s.chart, filters: s.filters, ...color }
  }
  if (s.type === 'products') {
    const measure = s.measure === 'qty' ? { fn: 'sum' as const, field: 'quantity' } : s.measure === 'sum' ? { fn: 'sum' as const, field: 'value' } : { fn: 'count' as const }
    return { entity: 'deal', type: 'products', measure, period, chart: s.chart, filters: s.filters, ...color }
  }
  const measure = s.type === 'duration' ? { fn: 'cycle_days' as const }
    : s.measure === 'count' ? { fn: 'count' as const }
    : s.measure === 'weighted' ? { fn: 'weighted' as const }
    : NAMED_MEASURES.has(s.measure) ? { fn: s.measure as 'duration_days' | 'sent' | 'open_rate' | 'click_rate' }
    : s.measure.startsWith('avg:') ? { fn: 'avg' as const, field: s.measure.slice(4) }
    : { fn: s.measure as 'sum' | 'avg', field: 'value' }
  return { entity: s.entity, type: s.type, measure, group_by: s.group, period, chart: s.chart, filters: s.filters, ...color }
}
