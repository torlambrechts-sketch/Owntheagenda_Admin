import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import { storageReady } from '@/lib/storage/server'
import { HEALTHS } from './projects-shared'

/**
 * Projects (Projects.dc.html): the board, the timeline, templates, reports and the drawer read through the 0038
 * functions (contract: docs/crm-enrichment/deviations/projects-schema.md). Every shape is parsed; nothing is cast.
 */
const num = z.coerce.number()
const id = z.guid()
const iso = z.string()
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
const health = z.enum(HEALTHS)

export const Phase = z.object({ id, name: z.string(), ord: num, color: z.string() })
export const BoardRow = z.object({ id, name: z.string(), ord: num, archived_at: iso.nullable(), phases: z.array(Phase.extend({ open_projects: num })) })
export type BoardRow = z.infer<typeof BoardRow>

export const Card = z.object({
  id,
  seq: num,
  name: z.string(),
  board_id: id,
  phase_id: id,
  phase_entered_at: iso,
  status: z.enum(['open', 'done', 'canceled']),
  closed_at: iso.nullable(),
  health: health.nullable(),
  health_source: z.enum(['manual', 'ai_suggestion']).nullable(),
  organization_id: id.nullable(),
  organization: z.string().nullable(),
  person_id: id.nullable(),
  person: z.string().nullable(),
  starts_on: day.nullable(),
  ends_on: day.nullable(),
  done: num,
  total: num,
  overdue: num,
  owner_id: id.nullable(),
  owner: z.object({ name: z.string().nullable(), initials: z.string().nullable() }).nullable(),
  deal: z.object({ id, title: z.string() }).nullable(),
  deals_more: num,
  labels: z.array(id),
  version: num,
  is_sample: z.boolean(),
  updated_at: iso,
})
export type Card = z.infer<typeof Card>

export const BoardView = z.object({
  board: z.object({ id, name: z.string(), archived_at: iso.nullable() }),
  phases: z.array(Phase.extend({ count: num })),
  cards: z.array(Card),
  workflow_hint: z.object({ id, name: z.string() }).nullable(),
})
export type BoardView = z.infer<typeof BoardView>

const Assignee = z.object({ staff_id: id.nullable(), person_id: id.nullable(), name: z.string().nullable() })
export const Item = z.object({
  id,
  kind: z.enum(['task', 'milestone', 'activity']),
  name: z.string().nullable(),
  parent_id: id.nullable(),
  group_id: id.nullable(),
  description: z.string().nullable(),
  owner_id: id.nullable(),
  owner: z.string().nullable(),
  assignees: z.array(Assignee),
  starts_on: day.nullable(),
  due_on: day.nullable(),
  done: z.boolean(),
  done_at: iso.nullable(),
  late_days: num.nullable(),
  depends_on: z.array(z.object({ id, name: z.string().nullable(), kind: z.string(), lag_days: num })),
  completes_with_subtasks: z.boolean(),
  source: z.string(),
  ord: num,
  version: num,
  activity: z.object({ id, subject: z.string(), starts_at: iso.nullable(), duration_min: num, type: z.object({ key: z.string(), glyph: z.string() }).nullable() }).nullable(),
  can_edit: z.boolean(),
})
export type Item = z.infer<typeof Item>

const TimelineEntry = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('note'), id, at: iso, author: z.string().nullable(), author_id: id.nullable(), body: z.string(), pinned: z.boolean() }),
  z.object({ kind: z.literal('email'), id, thread_id: id, at: iso, author: z.string().nullable(), direction: z.string(), subject: z.string().nullable(), excerpt: z.string().nullable() }),
])
export type TimelineEntry = z.infer<typeof TimelineEntry>

export const Detail = Card.extend({
  description: z.string().nullable(),
  brief_state: z.enum(['none', 'drafting', 'draft', 'reviewed', 'failed']),
  custom: z.record(z.string(), z.unknown()),
  visibility: z.enum(['owner', 'group', 'group_sub', 'all']),
  created_source: z.string(),
  health_set_at: iso.nullable(),
  health_set_by: z.string().nullable(),
  created_at: iso,
  can_edit: z.boolean(),
  board: z.object({ id, name: z.string() }).nullable(),
  phase: z.object({ id, name: z.string(), color: z.string() }).nullable(),
  template: z.object({ id, name: z.string() }).nullable(),
  deals: z.array(z.object({ id, title: z.string(), is_primary: z.boolean(), value: num.nullable(), currency: z.string().nullable(), status: z.string().nullable(), stage: z.string().nullable() })),
  groups: z.array(z.object({ id, name: z.string(), ord: num, phase_id: id.nullable() })),
  items: z.array(Item),
  timeline: z.array(TimelineEntry),
  files: z.array(z.object({ id, filename: z.string(), mime: z.string(), size_bytes: num, source: z.string(), created_at: iso })),
  sharing: z.object({ visibility: z.string(), group: z.string().nullable(), followers: z.array(z.object({ id, name: z.string() })), following: z.boolean() }),
  ai: z.object({
    enabled: z.boolean(),
    reason: z.string().nullable(),
    pending: z.boolean(),
    summary: z.object({ id, suggested_health: health.nullable(), summary: z.string().nullable(), recommendations: z.array(z.string()), generated_at: iso.nullable(), applied_at: iso.nullable() }).nullable(),
  }),
  status_reports: z.array(z.object({ id, state: z.enum(['requested', 'ready', 'failed']), requested_at: iso, ready_at: iso.nullable(), file_id: id.nullable(), ai_drafted: z.boolean() })),
})
export type Detail = z.infer<typeof Detail>

export const FileRow = z.object({ id, filename: z.string(), mime: z.string(), size_bytes: num, source: z.string(), uploaded_by: z.string().nullable(), created_at: iso, can_delete: z.boolean() })
export type FileRow = z.infer<typeof FileRow>

export const HistoryRow = z.object({ at: iso, field: z.string(), old: z.unknown(), new: z.unknown(), source: z.string(), actor: z.string().nullable() })
export type HistoryRow = z.infer<typeof HistoryRow>

export const Timeline = z.object({
  project: z.object({ id, seq: num, name: z.string(), starts_on: day.nullable(), ends_on: day.nullable(), status: z.string(), organization: z.string().nullable(), can_edit: z.boolean() }).nullable(),
  range: z.object({ from: day, to: day, days: num, months: z.array(day) }).nullable().optional(),
  today: day.optional(),
  today_pct: num.nullable().optional(),
  groups: z.array(z.object({ id, name: z.string(), ord: num, start: day.nullable(), end: day.nullable(), x: num.nullable(), w: num.nullable() })).optional(),
  rows: z.array(z.object({ id, kind: z.enum(['task', 'milestone', 'activity']), name: z.string().nullable(), parent_id: id.nullable(), group_id: id.nullable(), start: day.nullable(), end: day.nullable(), done: z.boolean(), overdue: z.boolean().nullable(), x: num.nullable(), w: num.nullable() })).optional(),
  dependencies: z.array(z.object({ predecessor: id, successor: id, lag_days: num, violated: z.boolean().nullable() })).optional(),
})
export type Timeline = z.infer<typeof Timeline>

export const TemplateRow = z.object({
  id,
  name: z.string(),
  description: z.string().nullable(),
  organized_by: z.enum(['phases', 'groups']),
  board_id: id.nullable(),
  source_project_id: id.nullable(),
  version: num,
  updated_at: iso,
  created_by: id.nullable(),
  creator: z.string().nullable(),
  groups: num,
  tasks: num,
  milestones: num,
  activities: num,
  dependencies: num,
  preview: z.array(z.object({ day: num.nullable(), kind: z.enum(['task', 'milestone', 'activity']), name: z.string() })),
  can_edit: z.boolean(),
})
export type TemplateRow = z.infer<typeof TemplateRow>

export const TemplateDetail = TemplateRow.extend({
  group_list: z.array(z.object({ key: z.string(), name: z.string(), ord: num, phase_id: id.nullable() })),
  items: z.array(z.object({
    key: z.string(),
    group: z.string().nullable(),
    parent: z.string().nullable(),
    kind: z.enum(['task', 'milestone', 'activity']),
    name: z.string(),
    start_offset_days: num.nullable(),
    due_offset_days: num.nullable(),
    activity_type: z.string().nullable(),
    activity_time: z.string().nullable(),
    activity_duration_min: num.nullable(),
    assignee: z.enum(['owner', 'unassigned']),
    completes_with_subtasks: z.boolean(),
    ord: num,
  })),
  dependency_list: z.array(z.object({ pred: z.string(), succ: z.string(), lag_days: num })),
})
export type TemplateDetail = z.infer<typeof TemplateDetail>

export const Reports = z.object({
  board_id: id.nullable(),
  from: day,
  to: day,
  own_only: z.boolean(),
  performance: z.array(z.object({ health: health.nullable(), n: num, w: num })),
  duration: z.array(z.object({ phase_id: id, phase: z.string(), board_id: id, board: z.string(), n: num, median_days: num.nullable() })),
  hooks: z.object({ triggers: z.array(z.string()), actions: z.array(z.string()), actions_available: z.boolean() }),
})
export type Reports = z.infer<typeof Reports>

export const Exported = z.object({
  format: z.enum(['csv', 'xlsx']),
  scope: z.enum(['board', 'project']),
  columns: z.array(z.string()),
  rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))),
})
export type Exported = z.infer<typeof Exported>

export const Staff = z.object({ id, name: z.string(), initials: z.string().nullable(), active: z.boolean() })
export type Staff = z.infer<typeof Staff>
export const Label = z.object({ id, name: z.string(), bg: z.string(), ink: z.string() })
export type Label = z.infer<typeof Label>
const FieldOption = z.union([z.string(), z.object({ key: z.string(), label: z.string().optional() })])
export const Field = z.object({
  id,
  key: z.string(),
  label: z.string(),
  type: z.string(),
  options: z.array(FieldOption),
  quality: z.enum(['optional', 'important', 'required']),
  readonly: z.boolean(),
})
export type Field = z.infer<typeof Field>
export const ActivityType = z.object({ id, key: z.string(), name: z.string(), glyph: z.string(), active: z.boolean() })
export type ActivityType = z.infer<typeof ActivityType>
export const Views = z.object({ views: z.array(z.unknown()), prefs: z.record(z.string(), z.unknown()) })

export const Hit = z.object({ id, name: z.string().optional(), title: z.string().nullable().optional(), city: z.string().nullable().optional() })
export type Hit = z.infer<typeof Hit>

// ---------------------------------------------------------------------------
// what the screen needs before a board is chosen
export async function loadProjectsBase() {
  const [boards, staff, labels, fields, views, activityTypes, integrations] = await Promise.all([
    rpc('project_boards_get', { p_archived: true }, z.array(BoardRow)),
    rpcOrThrow('staff_list', {}, z.array(Staff)),
    rpcOrThrow('labels_get', { p_entity: 'project' }, z.array(Label)),
    rpcOrThrow('fields_get', { p_entity: 'project' }, z.array(Field)),
    rpcOrThrow('views_get', { p_screen: 'projects' }, Views),
    rpcOrThrow('activity_types_get', {}, z.array(ActivityType)),
    // whether the AI provider is connected (provider «ai», V-P6P-03): the brief offered when creating from a deal
    rpc('integrations_get', {}, z.array(z.object({ provider: z.string(), status: z.string() })), { quiet: true }),
  ])
  return {
    boards, staff: staff.filter((s) => s.active), labels, fields, prefs: views.prefs, activityTypes: activityTypes.filter((a) => a.active),
    aiConnected: integrations.ok && integrations.data.some((i) => i.provider === 'ai' && i.status === 'connected'),
  }
}
export type ProjectsBase = Omit<Awaited<ReturnType<typeof loadProjectsBase>>, 'boards'> & { boards: BoardRow[] }

export type Filter = { f: string; op: string; v?: unknown }

export const loadBoards = () => rpc('project_boards_get', { p_archived: true }, z.array(BoardRow))
export const loadBoard = (board: string, query: { q?: string; mine?: boolean; closed?: boolean; filters?: Filter[] }) =>
  rpc('projects_board', { p_board: board, p_query: query }, BoardView)
export const loadTimeline = (project: string | null) => rpc('project_timeline', { p_id: project }, Timeline)
export const loadTemplates = () => rpc('project_templates_get', {}, z.array(TemplateRow))
export const loadTemplate = (tid: string) => rpc('project_template_get', { p_id: tid }, TemplateDetail)
export const loadReports = (board: string | null, from: string | null, to: string | null) =>
  rpc('project_reports', { p_board: board, p_from: from, p_to: to }, Reports)

/**
 * The drawer: the project, its history, its files (files_list carries who uploaded and may delete), whether the PDF
 * worker runs (project_pdf_status, provider «pdf», 0040): «Create PDF» follows it, and whether the storage signer runs
 * (storage-sign, 0052): upload and download follow it.
 */
export async function loadProject(pid: string) {
  const detail = await rpc('project_detail', { p_id: pid }, Detail)
  if (!detail.ok) return detail
  const [history, files, pdf, storage] = await Promise.all([
    rpc('rec_history', { p_entity: 'project', p_id: pid, p_limit: 100 }, z.array(HistoryRow)),
    rpc('files_list', { p_entity: 'project', p_id: pid }, z.array(FileRow)),
    rpc('project_pdf_status', {}, z.object({ pdf_connected: z.boolean() }), { quiet: true }),
    storageReady(),
  ])
  return {
    ok: true as const,
    data: { detail: detail.data, history: history.ok ? history.data : [], files: files.ok ? files.data : [], pdfConnected: pdf.ok && pdf.data.pdf_connected,
            storageReady: storage },
  }
}
export type ProjectBundle = { detail: Detail; history: HistoryRow[]; files: FileRow[]; pdfConnected: boolean; storageReady: boolean }

/** A deal's title for «Create project from deal» opened by address (rec_get checks deals:see and visibility). */
export const loadDealTitle = (dealId: string) => rpc('rec_get', { p_entity: 'deal', p_id: dealId }, z.object({ id, title: z.string() }))

export const searchRecords = (entity: 'person' | 'organization' | 'deal', q: string) =>
  rpc('rec_list', { p_entity: entity, p_query: { q, limit: 6, sort: { f: entity === 'deal' ? 'title' : 'name', dir: 'asc' } } },
    z.object({ rows: z.array(z.object({ id, name: z.string().optional(), title: z.string().nullable().optional(), city: z.string().nullable().optional(), status: z.string().optional() })) }))
