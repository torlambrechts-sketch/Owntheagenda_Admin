'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import {
  Exported, loadBoard, loadBoards, loadProject, loadReports, loadTemplate, loadTemplates, loadTimeline, searchRecords,
  type BoardRow, type BoardView, type Exported as ExportedT, type ProjectBundle, type Reports, type TemplateDetail, type TemplateRow, type Timeline,
} from '@/lib/data/projects'
import { HEALTHS } from '@/lib/data/projects-shared'

/**
 * The Projects screen's server actions. Every input is parsed; every answer is `{ ok: true, … }` or
 * `{ ok: false, code, detail }`, and the screen shows `common.errors.<code>`. The database checks rights again.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.guid()
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
const version = z.number().int().optional()
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const okish = z.unknown()
const done = (r: { ok: true } | { ok: false; code: RpcCode; detail: string | null }): Res => (r.ok ? { ok: true } : fail(r))
const cond = z.object({ f: z.string().regex(/^(custom\.)?[a-z_][a-z0-9_]{0,40}$/), op: z.enum(['eq', 'neq', 'in', 'contains', 'gt', 'gte', 'lt', 'lte', 'empty', 'notempty', 'has', 'within_days']), v: z.unknown().optional() })

// ---------------------------------------------------------------------------
// reads
export async function fetchBoards(): Promise<Res<{ boards: BoardRow[] }>> {
  const r = await loadBoards()
  return r.ok ? { ok: true, boards: r.data } : fail(r)
}

export async function fetchBoard(input: unknown): Promise<Res<{ board: BoardView }>> {
  const p = z.object({ board: uuid, q: z.string().max(100).optional(), mine: z.boolean().optional(), closed: z.boolean().optional(), filters: z.array(cond).max(20).optional() }).safeParse(input)
  if (!p.success) return bad
  const { board, ...query } = p.data
  const r = await loadBoard(board, query)
  return r.ok ? { ok: true, board: r.data } : fail(r)
}

export async function fetchProject(input: unknown): Promise<Res<{ project: ProjectBundle }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await loadProject(p.data)
  return r.ok ? { ok: true, project: r.data } : fail(r)
}

export async function fetchTimeline(input: unknown): Promise<Res<{ timeline: Timeline }>> {
  const p = uuid.nullable().safeParse(input)
  if (!p.success) return bad
  const r = await loadTimeline(p.data)
  return r.ok ? { ok: true, timeline: r.data } : fail(r)
}

export async function fetchTemplates(): Promise<Res<{ templates: TemplateRow[] }>> {
  const r = await loadTemplates()
  return r.ok ? { ok: true, templates: r.data } : fail(r)
}

export async function fetchTemplate(input: unknown): Promise<Res<{ template: TemplateDetail }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await loadTemplate(p.data)
  return r.ok ? { ok: true, template: r.data } : fail(r)
}

export async function fetchReports(input: unknown): Promise<Res<{ reports: Reports }>> {
  const p = z.object({ board: uuid.nullable(), from: day.nullable(), to: day.nullable() }).safeParse(input)
  if (!p.success) return bad
  const r = await loadReports(p.data.board, p.data.from, p.data.to)
  return r.ok ? { ok: true, reports: r.data } : fail(r)
}

export type Hit = { id: string; label: string; sub: string | null }
export async function searchHits(input: unknown): Promise<Res<{ rows: Hit[] }>> {
  const p = z.object({ entity: z.enum(['person', 'organization', 'deal']), q: z.string().max(100) }).safeParse(input)
  if (!p.success) return bad
  const r = await searchRecords(p.data.entity, p.data.q)
  if (!r.ok) return fail(r)
  return { ok: true, rows: r.data.rows.map((h) => ({ id: h.id, label: (p.data.entity === 'deal' ? h.title : h.name) ?? h.name ?? h.title ?? '', sub: p.data.entity === 'deal' ? null : (h.title ?? h.city ?? null) })) }
}

/** Export of a board or one project (project_export, «projects:export», audited); the browser writes the file. */
export async function exportProjects(input: unknown): Promise<Res<{ data: ExportedT }>> {
  const p = z.object({ board: uuid.nullable(), project: uuid.nullable(), format: z.enum(['csv', 'xlsx']) }).refine((x) => x.board || x.project).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_export', { p_board: p.data.board, p_project: p.data.project, p_format: p.data.format }, Exported)
  return r.ok ? { ok: true, data: r.data } : fail(r)
}

// ---------------------------------------------------------------------------
// projects
const created = z.object({ id: uuid, version: z.coerce.number(), seq: z.coerce.number() })
const projectValues = z.object({
  name: z.string().trim().min(1).max(200),
  board_id: uuid.optional(),
  phase_id: uuid.optional(),
  owner_id: uuid.optional(),
  starts_on: day.optional(),
  ends_on: day.optional(),
  description: z.string().max(20000).optional(),
  person_id: uuid.optional(),
  organization_id: uuid.optional(),
  template_id: uuid.optional(),
  deal_ids: z.array(uuid).max(20).optional(),
}).strict()

export async function createProject(input: unknown): Promise<Res<{ id: string }>> {
  const p = projectValues.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_create', { p_values: p.data }, created)
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

/** «Create project from deal» (PRJ-02): the deal's person and organisation come with it; the brief needs the AI. */
export async function createFromDeal(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({ deal: uuid, values: projectValues.partial().extend({ draft_brief: z.boolean().optional() }).strict() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_create_from_deal', { p_deal: p.data.deal, p_values: p.data.values }, created)
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function moveProject(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, phase: uuid, version }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_move', { p_id: p.data.id, p_phase: p.data.phase, p_version: p.data.version ?? null }, okish))
}

export async function setHealth(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, health: z.enum(HEALTHS).nullable(), version, summary: uuid.optional() }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_health_set', { p_id: p.data.id, p_health: p.data.health, p_version: p.data.version ?? null, p_from_summary: p.data.summary ?? null }, okish))
}

export async function closeProject(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, status: z.enum(['open', 'done', 'canceled']), version }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_close', { p_id: p.data.id, p_status: p.data.status, p_version: p.data.version ?? null }, okish))
}

export async function linkDeal(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, deal: uuid, on: z.boolean(), primary: z.boolean().optional() }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_deal_link', { p_id: p.data.id, p_deal: p.data.deal, p_on: p.data.on, p_primary: p.data.primary ?? false }, okish))
}

export async function reviewBrief(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, version }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_brief_review', { p_id: p.data.id, p_version: p.data.version ?? null }, okish))
}

/** Plain fields through the generic record path (rec_save('project', …)): custom fields, labels and the rest. */
export async function saveProject(input: unknown): Promise<Res> {
  const p = z.object({
    id: uuid,
    version,
    values: z.object({
      name: z.string().trim().min(1).max(200).optional(),
      starts_on: day.nullable().optional(),
      ends_on: day.nullable().optional(),
      description: z.string().max(20000).nullable().optional(),
      person_id: uuid.nullable().optional(),
      organization_id: uuid.nullable().optional(),
      owner_id: uuid.optional(),
      visibility: z.enum(['owner', 'group', 'group_sub', 'all']).optional(),
      labels: z.array(uuid).max(50).optional(),
      custom: z.record(z.string().regex(/^[a-z][a-z0-9_]{1,40}$/), z.unknown()).optional(),
    }).strict(),
  }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('rec_save', { p_entity: 'project', p_id: p.data.id, p_values: p.data.values, p_version: p.data.version ?? null }, okish))
}

export async function deleteProject(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('rec_delete', { p_entity: 'project', p_ids: [p.data] }, okish))
}

export async function setFollow(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, on: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('follow_set', { p_entity: 'project', p_id: p.data.id, p_on: p.data.on }, okish))
}

/** A note with @mentions (note_save routes a mention to /projects?project=…, CRM-06). */
export async function saveNote(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, body: z.string().trim().min(1).max(10000), mentions: z.array(uuid).max(20) }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('note_save', { p_entity: 'project', p_id: p.data.id, p_note: null, p_body: p.data.body, p_mentions: p.data.mentions }, okish))
}

// ---------------------------------------------------------------------------
// work items
const assignee = z.union([z.object({ staff_id: uuid }).strict(), z.object({ person_id: uuid }).strict()])
export async function saveItem(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({
    project: uuid,
    id: uuid.nullable(),
    version,
    values: z.object({
      kind: z.enum(['task', 'milestone']).optional(),
      name: z.string().trim().min(1).max(300).optional(),
      description: z.string().max(10000).nullable().optional(),
      owner_id: uuid.nullable().optional(),
      starts_on: day.nullable().optional(),
      due_on: day.nullable().optional(),
      group_id: uuid.nullable().optional(),
      parent_id: uuid.nullable().optional(),
      completes_with_subtasks: z.boolean().optional(),
      assignees: z.array(assignee).max(50).optional(),
    }).strict(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_item_save', { p_project: p.data.project, p_id: p.data.id, p_values: p.data.values, p_version: p.data.version ?? null }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function itemDone(input: unknown): Promise<Res<{ parentCompleted: boolean }>> {
  const p = z.object({ id: uuid, done: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_item_done', { p_id: p.data.id, p_done: p.data.done }, z.object({ parent_completed: z.boolean().nullable().optional() }))
  return r.ok ? { ok: true, parentCompleted: !!r.data.parent_completed } : fail(r)
}

export async function addItems(input: unknown): Promise<Res<{ count: number }>> {
  const p = z.object({
    project: uuid,
    group: uuid.nullable(),
    items: z.array(z.object({ name: z.string().trim().min(1).max(300), due_on: day.optional() }).strict()).min(1).max(200),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_items_add', { p_project: p.data.project, p_group: p.data.group, p_items: p.data.items }, z.object({ count: z.coerce.number() }))
  return r.ok ? { ok: true, count: r.data.count } : fail(r)
}

export async function bulkItems(input: unknown): Promise<Res<{ updated: number }>> {
  const p = z.object({
    project: uuid,
    ids: z.array(uuid).min(1).max(500),
    values: z.object({ owner_id: uuid.nullable().optional(), shift_days: z.number().int().min(-3650).max(3650).optional(), group_id: uuid.nullable().optional(), done: z.boolean().optional() }).strict(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_items_bulk', { p_project: p.data.project, p_ids: p.data.ids, p_values: p.data.values }, z.object({ updated: z.coerce.number() }))
  return r.ok ? { ok: true, updated: r.data.updated } : fail(r)
}

export async function deleteItems(input: unknown): Promise<Res<{ deleted: number }>> {
  const p = z.array(uuid).min(1).max(500).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_items_delete', { p_ids: p.data }, z.object({ deleted: z.coerce.number() }))
  return r.ok ? { ok: true, deleted: r.data.deleted } : fail(r)
}

export async function reorderItems(input: unknown): Promise<Res> {
  const p = z.object({ project: uuid, ids: z.array(uuid).min(1).max(1000) }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_items_reorder', { p_project: p.data.project, p_ids: p.data.ids }, okish))
}

export async function addActivity(input: unknown): Promise<Res> {
  const p = z.object({
    project: uuid,
    group: uuid.nullable(),
    values: z.object({ type: z.string().regex(/^[a-z_]{1,40}$/), subject: z.string().trim().min(1).max(200), starts_at: z.string().datetime({ offset: true }), owner_id: uuid, duration_min: z.number().int().min(0).max(1440).optional() }).strict(),
  }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_activity_add', { p_project: p.data.project, p_group: p.data.group, p_values: p.data.values }, okish))
}

export async function setDependency(input: unknown): Promise<Res<{ violated: boolean }>> {
  const p = z.object({ pred: uuid, succ: uuid, on: z.boolean(), lag: z.number().int().min(-365).max(365).optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_dependency_set', { p_pred: p.data.pred, p_succ: p.data.succ, p_on: p.data.on, p_lag: p.data.lag ?? 0 }, z.object({ violated: z.boolean().nullable().optional() }))
  return r.ok ? { ok: true, violated: !!r.data.violated } : fail(r)
}

export async function saveGroup(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({ project: uuid, id: uuid.nullable(), name: z.string().trim().min(1).max(80), ord: z.number().int().optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_group_save', { p_project: p.data.project, p_id: p.data.id, p_name: p.data.name, p_ord: p.data.ord ?? null }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function deleteGroup(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_group_delete', { p_id: p.data }, okish))
}

export async function shiftGroup(input: unknown): Promise<Res<{ shifted: number; flagged: number }>> {
  const p = z.object({ project: uuid, group: uuid, days: z.number().int().min(-3650).max(3650).refine((d) => d !== 0) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_group_shift', { p_project: p.data.project, p_group: p.data.group, p_days: p.data.days }, z.object({ shifted: z.coerce.number(), flagged: z.array(z.unknown()) }))
  return r.ok ? { ok: true, shifted: r.data.shifted, flagged: r.data.flagged.length } : fail(r)
}

// ---------------------------------------------------------------------------
// templates and configuration
const tplItem = z.object({
  key: z.string().min(1).max(64),
  group: z.string().max(64).nullable(),
  parent: z.string().max(64).nullable(),
  kind: z.enum(['task', 'milestone', 'activity']),
  name: z.string().trim().min(1).max(300),
  start_offset_days: z.number().int().min(0).max(3650).nullable(),
  due_offset_days: z.number().int().min(0).max(3650).nullable(),
  activity_type: z.string().max(40).nullable(),
  activity_time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).nullable(),
  activity_duration_min: z.number().int().min(0).max(1440).nullable(),
  assignee: z.enum(['owner', 'unassigned']),
  completes_with_subtasks: z.boolean(),
  ord: z.number().int(),
}).strict()
export async function saveTemplate(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({
    id: uuid.nullable(),
    version,
    values: z.object({
      name: z.string().trim().min(1).max(120),
      description: z.string().max(500).nullable(),
      organized_by: z.enum(['phases', 'groups']),
      board_id: uuid.nullable(),
      groups: z.array(z.object({ key: z.string().min(1).max(64), name: z.string().trim().min(1).max(80), ord: z.number().int(), phase_id: uuid.nullable() }).strict()).max(100),
      items: z.array(tplItem).max(500),
      dependencies: z.array(z.object({ pred: z.string().min(1).max(64), succ: z.string().min(1).max(64), lag_days: z.number().int().min(-365).max(365) }).strict()).max(1000),
    }).strict(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_template_save', { p_id: p.data.id, p_values: p.data.values, p_version: p.data.version ?? null }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function templateFromProject(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({ project: uuid, name: z.string().trim().min(1).max(120) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_template_from_project', { p_project: p.data.project, p_name: p.data.name }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function deleteTemplate(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_template_delete', { p_id: p.data }, okish))
}

const color = z.string().regex(/^#[0-9A-Fa-f]{6}$/)
export async function saveBoard(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({
    id: uuid.nullable(),
    values: z.object({ name: z.string().trim().min(1).max(80).optional(), archived: z.boolean().optional(), phases: z.array(z.object({ name: z.string().trim().min(1).max(60), color }).strict()).max(20).optional() }).strict(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_board_save', { p_id: p.data.id, p_values: p.data.values }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function savePhase(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid.nullable(), board: uuid.nullable(), values: z.object({ name: z.string().trim().min(1).max(60).optional(), color: color.optional() }).strict() }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_phase_save', { p_id: p.data.id, p_board: p.data.board, p_values: p.data.values }, okish))
}

export async function reorderPhases(input: unknown): Promise<Res> {
  const p = z.object({ board: uuid, ids: z.array(uuid).min(1).max(50) }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_phases_reorder', { p_board: p.data.board, p_ids: p.data.ids }, okish))
}

export async function deletePhase(input: unknown): Promise<Res<{ moved: number }>> {
  const p = z.object({ phase: uuid, target: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('project_phase_delete', { p_phase: p.data.phase, p_target: p.data.target }, z.object({ moved: z.coerce.number() }))
  return r.ok ? { ok: true, moved: r.data.moved } : fail(r)
}

export async function deleteFile(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('file_delete', { p_id: p.data }, okish))
}

export async function setPref(input: unknown): Promise<Res> {
  const p = z.object({ key: z.enum(['board', 'tab', 'closed']), value: z.union([uuid, z.enum(['board', 'timeline', 'templates', 'reports', 'setup']), z.boolean()]) }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('pref_set', { p_screen: 'projects', p_key: p.data.key, p_value: p.data.value }, okish))
}

// ---------------------------------------------------------------------------
// AI (project_ai, «projects:ai», the AI connection): offered only while ai.enabled holds; the database refuses
// otherwise (forbidden:setting:project_ai, not_connected:ai)
export async function requestSummary(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_ai_summary_request', { p_id: p.data }, okish))
}

export async function requestBrief(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('project_brief_request', { p_id: p.data }, okish))
}
