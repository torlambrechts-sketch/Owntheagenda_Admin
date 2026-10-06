import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { DrillRow, Fields, ReportResult, StoredDefinition, TileResult, type Definition, type Entity } from '@/lib/data/insights-shared'

/**
 * Insights (Insights.dc.html) reads through the 0024 functions: dashboards with their tiles run for the
 * viewer, reports, goals with progress computed, and the two forecasts. Every shape is parsed; nothing is cast.
 */
const id = z.string().uuid()
const num = z.coerce.number()

export const DashboardRef = z.object({
  id,
  name: z.string(),
  template_role: z.enum(['default', 'sales_manager', 'sales_rep', 'marketing']).nullable(),
  role: z.enum(['owner', 'editor', 'viewer']),
  owner: z.string().nullable(),
})
export type DashboardRef = z.infer<typeof DashboardRef>

export const Tile = z.object({
  report_id: id,
  name: z.string(),
  definition: StoredDefinition,
  position: num,
  span: num,
  result: TileResult,
})
export type Tile = z.infer<typeof Tile>

export const Share = z.object({ kind: z.enum(['staff', 'team', 'group']), id, role: z.enum(['viewer', 'editor']), name: z.string().nullable() })
export type Share = z.infer<typeof Share>

export const Dashboard = DashboardRef.omit({ owner: true }).extend({
  tiles: z.array(Tile),
  shares: z.array(Share).nullable(),
})
export type Dashboard = z.infer<typeof Dashboard>

export const Goal = z.object({
  id,
  name: z.string(),
  kind: z.enum(['deals_added', 'deals_progressed', 'deals_won', 'activities_added', 'activities_completed', 'forecast_weighted']),
  assignee_kind: z.enum(['staff', 'team', 'company']),
  assignee_id: id.nullable(),
  assignee: z.string().nullable(),
  pipeline_id: id.nullable(),
  activity_type_id: id.nullable(),
  frequency: z.enum(['weekly', 'monthly', 'quarterly', 'yearly']),
  starts_on: z.string(),
  ends_on: z.string().nullable(),
  target: num,
  by_value: z.boolean(),
  current: num.nullable(),
  interval_start: z.string(),
  interval_end: z.string(),
  elapsed_pct: num.nullable(),
  mine: z.boolean().nullable(),
})
export type Goal = z.infer<typeof Goal>

export const DealForecast = z.object({
  months: z.array(z.object({ month: z.string(), best: num, weighted: num, count: num })),
  undated: num,
})
export type DealForecast = z.infer<typeof DealForecast>

export const ProductForecast = z.object({
  months: z.array(z.object({ month: z.string(), subscriptions: num, recurring: num, installments: num })),
})
export type ProductForecast = z.infer<typeof ProductForecast>

const PipelineRow = z.object({ id, name: z.string(), stages: z.array(z.object({ id, name: z.string() }).passthrough()) }).passthrough()
const TypeRow = z.object({ id, name: z.string(), active: z.boolean() }).passthrough()
const StaffRow = z.object({ id, name: z.string(), active: z.boolean() }).passthrough()
const AccessModel = z.object({
  teams: z.array(z.object({ id, name: z.string() }).passthrough()),
  groups: z.array(z.object({ id, name: z.string() }).passthrough()),
}).passthrough()
const SettingRow = z.object({ key: z.string(), default: z.string(), values: z.array(z.object({ scope_id: z.string(), value: z.string(), number: num.nullable() }).passthrough()) }).passthrough()

export type Option = { id: string; name: string }
export type Pickers = { pipelines: (Option & { stages: Option[] })[]; activityTypes: Option[]; staff: Option[]; teams: Option[]; groups: Option[] }

export const loadDashboards = () => rpc('dashboards_get', {}, z.array(DashboardRef))
export const loadDashboard = (dashboard: string) => rpc('dashboard_get', { p_id: dashboard, p_period: null }, Dashboard)
export const loadGoals = () => rpc('goals_get', {}, z.array(Goal))
export const loadDealForecast = (months = 4) => rpc('forecast_deals', { p_months: months, p_pipeline: null, p_owner: null }, DealForecast)
export const loadProductForecast = (months = 12) => rpc('forecast_products', { p_months: months }, ProductForecast)
export const loadFields = (entity: Entity) => rpc('report_fields', { p_entity: entity }, Fields)
export const runReport = (def: Definition) => rpc('report_run', { p_def: def, p_extra: null }, ReportResult)
export const drillReport = (def: Definition, segment: Record<string, string | null>) => rpc('report_drill', { p_def: def, p_segment: segment, p_limit: 200 }, z.array(DrillRow))
export const exportReport = (def: Definition, segment: Record<string, string | null>) => rpc('report_export', { p_def: def, p_segment: segment, p_format: 'xlsx' }, z.array(DrillRow))

/** The pickers the screen needs (pipelines, activity types, people, teams, visibility groups); a refused list is empty. */
export async function loadPickers(): Promise<Pickers> {
  const [p, t, s, a] = await Promise.all([
    rpc('pipelines_get', {}, z.array(PipelineRow), { quiet: true }),
    rpc('activity_types_get', {}, z.array(TypeRow), { quiet: true }),
    rpc('staff_list', {}, z.array(StaffRow), { quiet: true }),
    rpc('access_model', {}, AccessModel, { quiet: true }),
  ])
  return {
    pipelines: p.ok ? p.data.map((x) => ({ id: x.id, name: x.name, stages: x.stages.map((st) => ({ id: st.id, name: st.name })) })) : [],
    activityTypes: t.ok ? t.data.filter((x) => x.active).map((x) => ({ id: x.id, name: x.name })) : [],
    staff: s.ok ? s.data.filter((x) => x.active).map((x) => ({ id: x.id, name: x.name })) : [],
    teams: a.ok ? a.data.teams.map((x) => ({ id: x.id, name: x.name })) : [],
    groups: a.ok ? a.data.groups.map((x) => ({ id: x.id, name: x.name })) : [],
  }
}

/** Reports per user (ENT-02, setting count_limits): null when unlimited, the default (D-17). */
export async function loadReportLimit(): Promise<number | null> {
  const r = await rpc('settings_get', {}, z.array(SettingRow), { quiet: true })
  if (!r.ok) return null
  const s = r.data.find((x) => x.key === 'count_limits')
  const v = s?.values.find((x) => x.scope_id === '')
  return (v?.value ?? s?.default) === 'number' ? (v?.number ?? null) : null
}
