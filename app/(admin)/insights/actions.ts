'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { drillReport, exportReport, loadDashboard, loadFields, runReport } from '@/lib/data/insights'
import { Definition, ENTITIES, type DrillRow, type Fields, type ReportResult } from '@/lib/data/insights-shared'

/**
 * The Insights screen's server actions. Every input is parsed; every answer is `{ ok: true, … }` or
 * `{ ok: false, code }`, and the screen shows `common.errors.<code>`. The database checks rights again.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.string().uuid()
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const Segment = z.object({ key: z.string().max(200).nullable().optional(), segment: z.string().max(200).nullable().optional() }).strict()
const Id = z.object({ id: uuid })
const name = z.string().trim().min(1).max(120)

// ---------------------------------------------------------------------------
// reports
export async function runReportAction(input: unknown): Promise<Res<{ result: ReportResult }>> {
  const p = Definition.safeParse(input)
  if (!p.success) return bad
  const r = await runReport(p.data)
  return r.ok ? { ok: true, result: r.data } : fail(r)
}

export async function fieldsAction(input: unknown): Promise<Res<{ fields: Fields }>> {
  const p = z.enum(ENTITIES).safeParse(input)
  if (!p.success) return bad
  const r = await loadFields(p.data)
  return r.ok ? { ok: true, fields: r.data } : fail(r)
}

export async function drillAction(input: unknown): Promise<Res<{ rows: DrillRow[] }>> {
  const p = z.object({ def: Definition, segment: Segment }).safeParse(input)
  if (!p.success) return bad
  const r = await drillReport(p.data.def, p.data.segment)
  return r.ok ? { ok: true, rows: r.data } : fail(r)
}

/** The rows behind a segment for an XLSX the browser writes; the database checks the export right and audits it. */
export async function exportAction(input: unknown): Promise<Res<{ rows: DrillRow[] }>> {
  const p = z.object({ def: Definition, segment: Segment }).safeParse(input)
  if (!p.success) return bad
  const r = await exportReport(p.data.def, p.data.segment)
  return r.ok ? { ok: true, rows: r.data } : fail(r)
}

/**
 * Save to dashboard: the report, then a tile at the end of the dashboard (dashboard_save replaces the
 * layout, so the current tiles are carried). Without a dashboard the staff member may change, a new one is
 * made with the given name.
 */
export async function saveReportAction(input: unknown): Promise<Res<{ dashboard: string; name: string }>> {
  const p = z.object({ name, def: Definition, dashboard: uuid.nullable(), newName: name }).safeParse(input)
  if (!p.success) return bad
  const saved = await rpc('report_save', { p_id: null, p_name: p.data.name, p_def: p.data.def, p_source: 'builder' }, Id)
  if (!saved.ok) return fail(saved)
  const tile = (position: number) => ({ report_id: saved.data.id, position, span: 6 })
  if (p.data.dashboard) {
    const d = await loadDashboard(p.data.dashboard)
    if (d.ok && (d.data.role === 'owner' || d.data.role === 'editor')) {
      const tiles = d.data.tiles.map((t, i) => ({ report_id: t.report_id, position: i, span: t.span }))
      const r = await rpc('dashboard_save', { p_id: d.data.id, p_name: null, p_tiles: [...tiles, tile(tiles.length)] }, Id)
      return r.ok ? { ok: true, dashboard: d.data.id, name: d.data.name } : fail(r)
    }
  }
  const r = await rpc('dashboard_save', { p_id: null, p_name: p.data.newName, p_tiles: [tile(0)] }, Id)
  return r.ok ? { ok: true, dashboard: r.data.id, name: p.data.newName } : fail(r)
}

// ---------------------------------------------------------------------------
// dashboards
export async function saveLayoutAction(input: unknown): Promise<Res> {
  const p = z.object({
    dashboard: uuid,
    tiles: z.array(z.object({ report_id: uuid, position: z.number().int().min(0).max(500), span: z.number().int().min(3).max(12) })).max(200),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('dashboard_save', { p_id: p.data.dashboard, p_name: null, p_tiles: p.data.tiles }, Id)
  return r.ok ? { ok: true } : fail(r)
}

export async function duplicateDashboardAction(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({ dashboard: uuid, name }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('dashboard_duplicate', { p_id: p.data.dashboard, p_name: p.data.name }, Id)
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function shareDashboardAction(input: unknown): Promise<Res> {
  const p = z.object({ dashboard: uuid, kind: z.enum(['staff', 'team', 'group']), grantee: uuid, role: z.enum(['viewer', 'editor']).nullable() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('dashboard_share', { p_id: p.data.dashboard, p_kind: p.data.kind, p_grantee: p.data.grantee, p_role: p.data.role }, z.unknown())
  return r.ok ? { ok: true } : fail(r)
}

// ---------------------------------------------------------------------------
// goals
const GoalValues = z.object({
  name,
  kind: z.enum(['deals_added', 'deals_progressed', 'deals_won', 'activities_added', 'activities_completed', 'forecast_weighted']),
  assignee_kind: z.enum(['staff', 'team', 'company']),
  assignee_id: uuid.nullable(),
  pipeline_id: uuid.nullable(),
  activity_type_id: uuid.nullable(),
  frequency: z.enum(['weekly', 'monthly', 'quarterly', 'yearly']),
  target_count: z.number().int().positive().max(1_000_000_000).nullable(),
  target_value: z.number().positive().max(1e12).nullable(),
}).refine((v) => (v.target_count === null) !== (v.target_value === null))
  .refine((v) => (v.assignee_kind === 'company') === (v.assignee_id === null))

export async function saveGoalAction(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({ id: uuid.nullable(), values: GoalValues }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('goal_save', { p_id: p.data.id, p_values: p.data.values }, Id)
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function deleteGoalAction(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('goal_delete', { p_id: p.data }, Id)
  return r.ok ? { ok: true } : fail(r)
}
