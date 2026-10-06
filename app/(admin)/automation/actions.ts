'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { AssignTest, GraphSchema } from '@/lib/data/automation'

/** Server actions of the Automation screen: each parses its input and answers `{ ok } | { ok: false, code }`. */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode; detail?: string | null }

const uuid = z.string().uuid()
const bad = { ok: false as const, code: 'invalid' as const }
const done = () => revalidatePath('/automation')
const fail = (r: { code: RpcCode; detail: string | null }) => ({ ok: false as const, code: r.code, detail: r.detail })

export async function setWorkflowState(input: { id: string; state: 'draft' | 'active' }): Promise<Result> {
  const p = z.object({ id: uuid, state: z.enum(['draft', 'active']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('workflow_set_state', { p_id: p.data.id, p_state: p.data.state }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function transferWorkflow(input: { id: string; to: string }): Promise<Result> {
  const p = z.object({ id: uuid, to: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('workflow_transfer', { p_id: p.data.id, p_to: p.data.to }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function createFromTemplate(input: { key: string; name: string }): Promise<Result<{ id: string }>> {
  const p = z.object({ key: z.string().regex(/^[a-z_]{2,40}$/), name: z.string().trim().min(1).max(120) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('workflow_from_template', { p_key: p.data.key, p_name: p.data.name }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

const Trigger = z.object({
  trigger_type: z.enum(['event', 'date', 'product_event']),
  trigger_config: z.record(z.string(), z.unknown()),
})

/** Save the builder: the trigger and the graph. A changed graph publishes a new version (workflow_save). */
export async function saveWorkflow(input: { id: string; version: number; trigger: z.input<typeof Trigger>; graph: unknown }): Promise<Result<{ version: number; graphVersion: number }>> {
  const p = z.object({ id: uuid, version: z.number().int().positive(), trigger: Trigger, graph: GraphSchema }).safeParse(input)
  if (!p.success || JSON.stringify(p.data.graph).length > 200_000) return bad
  const r = await rpc('workflow_save', { p_id: p.data.id, p_values: p.data.trigger, p_graph: p.data.graph, p_version: p.data.version },
    z.object({ id: uuid, version: z.coerce.number(), graph_version: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, version: r.data.version, graphVersion: r.data.graph_version }
}

export async function retryRun(input: { id: string }): Promise<Result<{ state: string }>> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('workflow_run_retry', { p_run: p.data.id }, z.object({ id: uuid, state: z.string() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, state: r.data.state }
}

export async function reorderRules(input: { ids: string[] }): Promise<Result> {
  const p = z.object({ ids: z.array(uuid).min(1).max(200) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('assignment_rules_reorder', { p_ids: p.data.ids }, z.object({ ok: z.boolean() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

const TestInput = z.object({
  entity: z.enum(['lead', 'deal']),
  source: z.string().max(60),
  employees: z.number().int().min(0).max(10_000_000).nullable(),
  org_exists: z.boolean(),
  org_labels: z.array(uuid).max(20),
})

/** «Test a record»: read-only, nothing is assigned and the rotation does not move. */
export async function testAssignment(input: z.input<typeof TestInput>): Promise<Result<{ result: AssignTest }>> {
  const p = TestInput.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('assignment_test', { p_input: { ...p.data, employees: p.data.employees ?? undefined } }, AssignTest)
  if (!r.ok) return fail(r)
  return { ok: true, result: r.data }
}

const Condition = z.object({
  sources: z.array(z.string().trim().min(1).max(60)).max(20).optional(),
  employees_min: z.number().int().min(0).optional(),
  employees_max: z.number().int().min(0).optional(),
  org_exists: z.boolean().optional(),
  org_labels_any: z.array(uuid).max(20).optional(),
}).strict()
const Assignee = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('user'), staff_id: uuid }),
  z.object({ kind: z.literal('team_rr'), team_id: uuid }),
  z.object({ kind: z.literal('org_owner') }),
  z.object({ kind: z.literal('person_owner') }),
])
const Rule = z.object({
  id: uuid.nullable(),
  version: z.number().int().positive().nullable(),
  name: z.string().trim().min(1).max(120),
  entities: z.array(z.enum(['lead', 'deal'])).min(1),
  condition: Condition,
  assignee: Assignee,
  active: z.boolean(),
})

/** Create or change an assignment rule (an assignment workflow, 0021: options.condition and options.assignee). */
export async function saveRule(input: z.input<typeof Rule>): Promise<Result> {
  const p = Rule.safeParse(input)
  if (!p.success) return bad
  const d = p.data
  const r = await rpc('workflow_save', {
    p_id: d.id,
    p_values: { name: d.name, kind: 'assignment', trigger_type: 'event', trigger_config: { entities: d.entities }, options: { condition: d.condition, assignee: d.assignee } },
    p_graph: null,
    p_version: d.version,
  }, z.object({ id: uuid, version: z.coerce.number() }))
  if (!r.ok) return fail(r)
  const s = await rpc('workflow_set_state', { p_id: r.data.id, p_state: d.active ? 'active' : 'draft' }, z.object({ id: uuid }))
  done()
  if (!s.ok) return fail(s)
  return { ok: true }
}

export async function deleteRule(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('workflow_delete', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

/** Records a sequence can take, for the picker (title search, visible records only). */
export async function searchRecords(input: { entity: 'deal' | 'lead'; q: string }): Promise<Result<{ rows: { id: string; title: string }[] }>> {
  const p = z.object({ entity: z.enum(['deal', 'lead']), q: z.string().max(100) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_list', { p_entity: p.data.entity, p_query: { q: p.data.q.trim(), limit: 8, sort: { f: 'updated_at', dir: 'desc' } } },
    z.object({ rows: z.array(z.object({ id: uuid, title: z.string() }).passthrough()) }))
  if (!r.ok) return fail(r)
  return { ok: true, rows: r.data.rows.map((x) => ({ id: x.id, title: x.title })) }
}

export async function enroll(input: { id: string; entity: 'deal' | 'lead'; ids: string[] | null; view: string | null }): Promise<Result<{ enrolled: number; skipped: number }>> {
  const p = z.object({ id: uuid, entity: z.enum(['deal', 'lead']), ids: z.array(uuid).min(1).max(500).nullable(), view: uuid.nullable() })
    .refine((x) => (x.ids === null) !== (x.view === null)).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sequence_enroll', { p_id: p.data.id, p_entity: p.data.entity, p_ids: p.data.ids, p_view: p.data.view },
    z.object({ enrolled: z.coerce.number(), skipped: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, enrolled: r.data.enrolled, skipped: r.data.skipped }
}

export async function exitEnrollments(input: { ids: string[] }): Promise<Result<{ exited: number }>> {
  const p = z.object({ ids: z.array(uuid).min(1).max(500) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sequence_exit', { p_ids: p.data.ids }, z.object({ exited: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, exited: r.data.exited }
}

export async function skipStep(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sequence_skip_step', { p_enrollment: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}
