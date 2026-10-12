import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import { AI_FEATURES, KINDS, LANES, SEVERITIES, SPEC_ROLES, SPEC_STATUSES, STATUSES } from '@/app/(admin)/development/_components/core/logic'

/**
 * Development › the core half (0079): Roadmap, Work board, Bug triage, Spec documents, Markdown roadmap and Claude jobs.
 * Every read goes through its database function and is parsed here, never cast. A part the reader may not see comes back
 * absent or null from the database, and the view leaves it out.
 */

const uuid = z.string().uuid()
const num = z.coerce.number()
const Staff = z.object({ id: uuid, name: z.string(), initials: z.string().nullable() })
const Person = z.object({ id: uuid, name: z.string().nullable() })
const LogEntry = z.object({ at: z.string(), by: z.string().nullable(), action: z.string(), detail: z.record(z.string(), z.unknown()).nullable() })

// ---------------------------------------------------------------------------
// the roadmap
export const LINK_KINDS = ['feature_request', 'ticket', 'deal', 'experiment', 'seo_plan'] as const
const Evidence = z.object({
  requests: num.optional(),
  votes: num.optional(),
  tickets: num.optional(),
  deals: z.object({ n: num, mrr: num.nullable(), currency: z.string().nullable() }).optional(),
  experiments: z.array(z.object({ stage: z.string(), outcome: z.string().nullable() })).optional(),
  seo: z.array(z.object({ stage: z.string() })).optional(),
})
const ItemLink = z.object({ kind: z.enum(LINK_KINDS), ref: uuid, label: z.string().nullable(), title: z.string().nullable() })
export const RoadmapItem = z.object({
  id: uuid,
  key: z.string(),
  product: z.string(),
  title: z.string(),
  goal: z.string().nullable(),
  lane: z.enum(LANES),
  ord: num,
  status: z.enum(STATUSES),
  owner: Person.nullable(),
  source: z.enum(['feature_request', 'experiment', 'seo_plan']).nullable(),
  version: num,
  created_at: z.string(),
  updated_at: z.string(),
  evidence: Evidence,
  links: z.array(ItemLink),
  work: z.object({ total: num, done: num }),
  spec: z.object({ id: uuid, ref: z.string(), status: z.enum(SPEC_STATUSES) }).nullable(),
})
export type RoadmapItem = z.infer<typeof RoadmapItem>
const Candidate = z.object({ id: uuid, title: z.string(), product: z.string() }).nullable()
export const Roadmap = z.object({
  items: z.array(RoadmapItem),
  candidates: z.object({ feature_request: Candidate, experiment: Candidate, seo_plan: Candidate }),
  requests: z.array(z.object({ id: uuid, label: z.string(), title: z.string(), product: z.string() })),
  deals: z.array(z.object({ id: uuid, label: z.string(), title: z.string() })).nullable(),
  staff: z.array(Staff),
  can_add: z.boolean(),
})
export type Roadmap = z.infer<typeof Roadmap>
export const loadRoadmap = (product: string | null) => rpcOrThrow('dev_roadmap_get', { p_product: product }, Roadmap)

// ---------------------------------------------------------------------------
// the work board
export const WorkItem = z.object({
  id: uuid,
  key: z.string(),
  product: z.string(),
  kind: z.enum(KINDS),
  title: z.string(),
  points: num.nullable(),
  status: z.enum(STATUSES),
  ord: num,
  sprint_id: uuid.nullable(),
  version: num,
  done_at: z.string().nullable(),
  roadmap: z.object({ id: uuid, key: z.string(), title: z.string() }).nullable(),
  assignee: z.object({ id: uuid, name: z.string(), initials: z.string().nullable() }).nullable(),
  bug: z.object({ id: uuid, number: num, state: z.string() }).nullable(),
})
export type WorkItem = z.infer<typeof WorkItem>
const Sprint = z.object({ id: uuid, name: z.string(), starts_on: z.string(), ends_on: z.string() })
export const Board = z.object({
  today: z.string(),
  sprint: Sprint.extend({ days: num, day: num, committed: num, done: num }).nullable(),
  sprints: z.array(Sprint),
  items: z.array(WorkItem),
  roadmap: z.array(z.object({ id: uuid, key: z.string(), title: z.string(), product: z.string() })),
  bugs: z.array(z.object({ id: uuid, number: num, title: z.string(), product: z.string() })),
  staff: z.array(Staff),
  can_add: z.boolean(),
})
export type Board = z.infer<typeof Board>
export const loadBoard = () => rpcOrThrow('dev_board_get', {}, Board)

// ---------------------------------------------------------------------------
// bug triage
export const Bug = z.object({
  id: uuid,
  number: num,
  product: z.string(),
  title: z.string(),
  severity: z.enum(SEVERITIES),
  source: z.enum(['ticket', 'internal']),
  state: z.enum(['open', 'fixed', 'duplicate']),
  due_at: z.string(),
  fixed_at: z.string().nullable(),
  created_at: z.string(),
  version: num,
  assignee: Person.nullable(),
  duplicate_of: z.object({ id: uuid, number: num }).nullable(),
  problem: z.object({ id: uuid, status: z.string().nullable(), number: num.nullable(), open_incidents: num }).nullable(),
  tickets: num.nullable(),
  ticket_numbers: z.array(num).nullable(),
  customers: num.nullable(),
  work: z.object({ id: uuid, key: z.string(), status: z.enum(STATUSES) }).nullable(),
})
export type Bug = z.infer<typeof Bug>
export const Bugs = z.object({
  now: z.string(),
  targets: z.object({ s1: z.union([z.literal('same_day'), num]), s2: num, s3: num, escaped_goal: num }),
  bugs: z.array(Bug),
  kpi: z.object({
    open: num, s1: num, s2: num, s3: num, fixed_30: num, within_30: num, escaped_30: num,
    median_h: num.nullable(), median_s1_h: num.nullable(), median_s2_h: num.nullable(),
  }),
  staff: z.array(Staff),
  problems: z.array(z.object({ id: uuid, number: num, subject: z.string(), status: z.string() })).nullable(),
  can_add: z.boolean(),
  can_resolve: z.boolean(),
})
export type Bugs = z.infer<typeof Bugs>
export const loadBugs = (product: string | null) => rpcOrThrow('dev_bugs_get', { p_product: product }, Bugs)

// ---------------------------------------------------------------------------
// specs
export const Spec = z.object({
  id: uuid,
  number: num,
  ref: z.string(),
  product: z.string(),
  title: z.string(),
  status: z.enum(SPEC_STATUSES),
  revision: num,
  version: num,
  updated_at: z.string(),
  created_at: z.string(),
  author: Person.nullable(),
  roadmap: z.object({ id: uuid, key: z.string(), title: z.string() }).nullable(),
  sections: z.object({ problem: z.string().nullable(), options: z.string().nullable(), decision: z.string().nullable(), privacy: z.string().nullable(), rollout: z.string().nullable() }),
  signoffs: z.array(z.object({ role: z.enum(SPEC_ROLES), by: z.string().nullable(), at: z.string(), revision: num, current: z.boolean() })),
})
export type Spec = z.infer<typeof Spec>
export const Specs = z.object({
  specs: z.array(Spec),
  roadmap: z.array(z.object({ id: uuid, key: z.string(), title: z.string(), product: z.string() })),
  can_add: z.boolean(),
})
export type Specs = z.infer<typeof Specs>
export const loadSpecs = () => rpcOrThrow('dev_specs_get', {}, Specs)

// ---------------------------------------------------------------------------
// the Markdown roadmap's records
const Task = z.object({ key: z.string(), title: z.string(), done: z.boolean() })
export const Files = z.object({
  items: z.array(RoadmapItem.extend({ problem: z.string().nullable(), tasks: z.array(Task), log: z.array(LogEntry) })),
  bugs: z.array(Bug.extend({ tasks: z.array(Task), updated_at: z.string(), log: z.array(LogEntry) })),
  staff: z.array(Staff),
  can_add: z.boolean(),
})
export type Files = z.infer<typeof Files>
export const loadFiles = () => rpcOrThrow('dev_files_get', {}, Files)

// ---------------------------------------------------------------------------
// Claude jobs
export const Jobs = z.object({
  rows: z.array(z.object({
    id: num,
    feature: z.enum(AI_FEATURES),
    at: z.string(),
    state: z.string(),
    error: z.string().nullable(),
    model: z.string().nullable(),
    input_tokens: num.nullable(),
    output_tokens: num.nullable(),
    latency_ms: num.nullable(),
    by: z.string().nullable(),
    item: z.object({ id: uuid, key: z.string(), title: z.string() }).nullable(),
    output: z.object({ id: uuid, state: z.enum(['ready', 'used', 'discarded']), chars: num }).nullable(),
  })),
  kpi: z.object({
    calls: num, failed: num, drafts: num, used: num, discarded: num, median_ms: num.nullable(), tokens_month: num, cost_micros_month: num.nullable(),
  }),
})
export type Jobs = z.infer<typeof Jobs>
export const loadJobs = () => rpcOrThrow('dev_jobs_get', {}, Jobs)

/** the ready drafts of the three features for one roadmap item (ai_outputs_get, 0078: the newest five per feature) */
const Draft = z.object({ id: uuid, body: z.string(), state: z.enum(['ready', 'used', 'discarded']), created_at: z.string(), by: z.string().nullable() })
export type Draft = z.infer<typeof Draft> & { feature: (typeof AI_FEATURES)[number] }
export async function loadDrafts(item: string): Promise<Draft[]> {
  const all = await Promise.all(AI_FEATURES.map(async (feature) => {
    const r = await rpc('ai_outputs_get', { p_feature: feature, p_subject: item }, z.array(Draft), { quiet: true })
    return r.ok ? r.data.map((d) => ({ ...d, feature })) : []
  }))
  return all.flat().filter((d) => d.state === 'ready').sort((a, b) => b.created_at.localeCompare(a.created_at))
}
