import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import type { Graph, Step } from './automation-graph'

/**
 * Automation (0021_engine.sql): workflows, the builder's graph, templates, monitoring, assignment rules and
 * sequences, all through the engine's public functions. Every row is parsed here, never cast.
 */
const num = z.coerce.number()
const id = z.string().uuid()
const obj = z.record(z.string(), z.unknown())

export const StepSchema: z.ZodType<Step> = z.lazy(() =>
  z.object({
    key: z.string(),
    kind: z.string(),
    config: obj.catch({}),
    then: z.array(StepSchema).optional(),
    else: z.array(StepSchema).optional(),
  }),
)
export const GraphSchema: z.ZodType<Graph> = z.object({ steps: z.array(StepSchema) })

export const WorkflowRow = z.object({
  id,
  kind: z.enum(['workflow', 'sequence', 'lifecycle', 'assignment']),
  name: z.string(),
  description: z.string().nullable(),
  state: z.enum(['draft', 'active']),
  trigger_type: z.enum(['event', 'date', 'product_event', 'enrollment']),
  trigger_config: obj,
  owner_id: id,
  owner: z.string().nullable(),
  activation_scope: z.enum(['owner', 'users', 'team', 'everyone']),
  activation: z.array(z.object({ staff_id: id.nullable(), team_id: id.nullable(), name: z.string().nullable() })),
  runs_7d: num,
  failed_7d: num,
  blockers: z.array(z.string()),
  template_key: z.string().nullable(),
  version: num,
  updated_at: z.string(),
  mine: z.boolean().nullable(),
  // an assignment rule carries its options (condition, assignee) and priority (0029); other kinds null
  options: obj.nullish(),
  priority: num.nullish(),
})
export type WorkflowRow = z.infer<typeof WorkflowRow>

export const WorkflowDetail = WorkflowRow.extend({
  options: obj,
  priority: num.nullable(),
  current_version: num,
  graph: GraphSchema.nullable(),
  versions: num,
})
export type WorkflowDetail = z.infer<typeof WorkflowDetail>

const Template = z.object({ key: z.string(), group: z.string(), kind: z.string(), trigger_type: z.string() })
export type WorkflowTemplate = z.infer<typeof Template>

const Named = z.object({ id, name: z.string(), count: num })
export const Monitor = z.object({
  today: z.object({ runs: num, completed: num, failed: num }),
  d7: z.object({ runs: num, failed: num, retried: num }),
  d14: z.object({ runs: num, prev7: num, last7: num }),
  loop_protection: z.string().nullable(),
  loop_protection_runs: num.nullable(),
  loop_blocked_7d: num,
  most_failed: z.array(Named),
  most_active: z.array(Named),
  never_run: z.array(z.object({ id, name: z.string(), state: z.string() })),
})
export type Monitor = z.infer<typeof Monitor>

export const Run = z.object({
  id,
  workflow_id: id,
  workflow: z.string(),
  state: z.enum(['running', 'waiting', 'completed', 'failed', 'stopped', 'loop_blocked']),
  error: z.string().nullable(),
  started_at: z.string(),
  finished_at: z.string().nullable(),
  retry_of: id.nullable(),
  subject_type: z.string().nullable(),
  subject_id: id.nullable(),
  subject_title: z.string().nullable(),
  retried: z.boolean(),
  steps: z.array(z.object({ key: z.string(), kind: z.string(), state: z.string(), error: z.string().nullable(), status: num.nullable() })),
})
export type Run = z.infer<typeof Run>

export const AssignTest = z.object({
  rule_id: id.nullable(),
  rule: z.string().optional(),
  assignee_kind: z.string().nullable().optional(),
  assignee_id: id.nullable().optional(),
  assignee: z.string().nullable().optional(),
})
export type AssignTest = z.infer<typeof AssignTest>

const History = z.array(z.object({ at: z.string(), rule: z.string().nullable(), entity: z.string(), record_id: id, assignee: z.string().nullable() }))
export type AssignHistory = z.infer<typeof History>

export const Enrollment = z.object({
  id,
  entity: z.enum(['deal', 'lead']),
  record_id: id,
  title: z.string().nullable(),
  step: num,
  step_key: z.string().nullable(),
  via: z.enum(['one', 'bulk', 'workflow']),
  state: z.enum(['in_progress', 'completed', 'failed', 'exited']),
  exit_reason: z.string().nullable(),
  error: z.string().nullable(),
  created_at: z.string(),
  enrolled_by: id.nullable(),
  mine: z.boolean().nullable(),
})
export type Enrollment = z.infer<typeof Enrollment>

export const SequenceDetail = WorkflowRow.extend({
  options: obj,
  graph: GraphSchema.nullable(),
  counts: z.object({ in_progress: num, completed: num, failed: num, exited: num }),
  enrolled: z.array(Enrollment),
})
export type SequenceDetail = z.infer<typeof SequenceDetail>

const Integrations = z.array(z.object({ provider: z.string(), status: z.string() }))

const Settings = z.array(z.object({ key: z.string(), default: z.string(), values: z.array(z.object({ scope_id: z.string(), value: z.string(), number: num.nullable() })) }))

const Staff = z.array(z.object({ id, name: z.string(), active: z.boolean(), permission_set_id: id, is_sample: z.boolean().catch(false) }))
const Access = z.object({
  permission_sets: z.array(z.object({ id, kind: z.string(), rights: z.array(z.string()) })),
  teams: z.array(z.object({ id, name: z.string(), members: z.array(z.object({ id, name: z.string() })) })),
})
const Labels = z.array(z.object({ id, name: z.string() }))
const EmailTemplates = z.array(z.object({ id, name: z.string() }))
const TicketCats = z.object({ categories: z.array(z.object({ key: z.string(), name: z.string() })) })
const ActivityTypes = z.array(z.object({ key: z.string(), name: z.string(), active: z.boolean() }))
const Views = z.object({ views: z.array(z.object({ id, name: z.string() })) })

export type Person = { id: string; name: string; canWorkflows: string[] }
export type Team = { id: string; name: string }
export type Option = { id: string; name: string }

/** What every tab needs: the safeguard and limit settings, integrations, staff and teams. */
export async function loadBase() {
  const [settings, integrations, staff, access] = await Promise.all([
    rpcOrThrow('settings_get', {}, Settings),
    rpcOrThrow('integrations_get', {}, Integrations),
    rpcOrThrow('staff_list', {}, Staff),
    rpcOrThrow('access_model', {}, Access),
  ])
  const setting = (key: string) => {
    const s = settings.find((x) => x.key === key)
    const v = s?.values.find((x) => x.scope_id === '')
    return { value: v?.value ?? s?.default ?? '', number: v?.number ?? null }
  }
  const sets = new Map(access.permission_sets.map((p) => [p.id, p]))
  const people: Person[] = staff.filter((s) => s.active && !s.is_sample).map((s) => {
    const p = sets.get(s.permission_set_id)
    // who may own a workflow in a scope: an admin set, or the scope's «workflows» right (workflow_transfer)
    const canWorkflows = p?.kind === 'admin' ? ['deals', 'tickets'] : (p?.rights ?? []).filter((r) => r.endsWith(':workflows')).map((r) => r.split(':')[0]!)
    return { id: s.id, name: s.name, canWorkflows }
  })
  return {
    safeguards: setting('safeguards'),
    countLimits: setting('count_limits'),
    connected: integrations.filter((i) => i.status === 'connected').map((i) => i.provider),
    people,
    teams: access.teams.map((t) => ({ id: t.id, name: t.name })) as Team[],
  }
}
export type Base = Awaited<ReturnType<typeof loadBase>>

export const loadWorkflows = (kind: 'workflow' | 'assignment' | 'sequence') => rpcOrThrow('workflows_get', { p_filter: { kind } }, z.array(WorkflowRow))
export const loadWorkflow = (wf: string) => rpc('workflow_get', { p_id: wf }, WorkflowDetail)
export const loadTemplates = () => rpcOrThrow('workflow_templates_get', {}, z.array(Template))
export const loadMonitor = () => rpcOrThrow('workflow_monitor', {}, Monitor)
export const loadHistory = () => rpc('assignment_history', { p_limit: 10 }, History)
export const loadSequence = (seq: string) => rpc('sequence_get', { p_id: seq }, SequenceDetail)

/** Run history, newest first; each run names its record (subject_title, null when it is not visible). */
export const loadRuns = () => rpcOrThrow('workflow_runs_get', { p_filter: { limit: 50 } }, z.array(Run))

const Columns = z.array(z.object({ col: z.string(), kind: z.string(), writable: z.boolean(), required: z.boolean(), ref: z.string().nullable() }))
export type Column = z.infer<typeof Columns>[number]
export const RECORD_TYPES = ['deal', 'lead', 'person', 'organization', 'activity', 'ticket'] as const

/** The pickers the builder's configuration panel offers. Each is read as the staff member, so a list they
 *  may not see comes back empty rather than failing the page. */
export async function loadPickers() {
  const [labels, templates, cats, types, sequences, ...cols] = await Promise.all([
    rpc('labels_get', { p_entity: 'organization' }, Labels, { quiet: true }),
    rpc('templates_get', {}, EmailTemplates, { quiet: true }),
    rpc('ticket_config', {}, TicketCats, { quiet: true }),
    rpc('activity_types_get', {}, ActivityTypes, { quiet: true }),
    rpc('workflows_get', { p_filter: { kind: 'sequence' } }, z.array(WorkflowRow), { quiet: true }),
    // the columns a condition, a date trigger or an update step may use, per record type (entity_columns_get)
    ...RECORD_TYPES.map((e) => rpc('entity_columns_get', { p_entity: e }, Columns, { quiet: true })),
  ])
  return {
    orgLabels: labels.ok ? labels.data : [],
    emailTemplates: templates.ok ? templates.data : [],
    ticketCategories: cats.ok ? cats.data.categories.map((c) => ({ id: c.key, name: c.name })) : [],
    activityTypes: types.ok ? types.data.filter((x) => x.active).map((x) => ({ id: x.key, name: x.name })) : [],
    sequences: sequences.ok ? sequences.data.map((s) => ({ id: s.id, name: s.name })) : [],
    columns: Object.fromEntries(RECORD_TYPES.map((e, i) => { const r = cols[i]!; return [e, r.ok ? r.data : []] })) as Record<string, Column[]>,
  }
}
export type Pickers = Awaited<ReturnType<typeof loadPickers>>

export async function loadOrgLabels(): Promise<Option[]> {
  const r = await rpc('labels_get', { p_entity: 'organization' }, Labels, { quiet: true })
  return r.ok ? r.data : []
}

export async function loadEmailTemplates(): Promise<Option[]> {
  const r = await rpc('templates_get', {}, EmailTemplates, { quiet: true })
  return r.ok ? r.data : []
}

/** Saved views a bulk enrolment can draw from (the Deals and Leads screens' views). */
export async function loadViews(entity: 'deal' | 'lead'): Promise<Option[]> {
  const r = await rpc('views_get', { p_screen: entity === 'deal' ? 'deals' : 'leads' }, Views, { quiet: true })
  return r.ok ? r.data.views : []
}
