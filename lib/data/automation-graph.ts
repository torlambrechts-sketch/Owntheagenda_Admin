/**
 * The workflow graph the engine stores (0021_engine.sql, app.wf_flatten / app.wf_validate):
 * `{steps: [{key, kind, config, then?, else?}]}`, where an if/else step holds two lists. These helpers are
 * pure, so the builder edits a copy and the database validates what is saved.
 */

export type Step = { key: string; kind: string; config: Record<string, unknown>; then?: Step[]; else?: Step[] }
export type Graph = { steps: Step[] }

/** Where a list lives: [] is the top level; [i, 'then'] is the then-list of the step at index i, and so on. */
export type ListRef = (number | 'then' | 'else')[]
export type Slot = { list: ListRef; index: number }

/** The step kinds a workflow may hold (app.wf_kinds, kind «workflow»). */
export const WORKFLOW_KINDS = [
  'condition', 'if_else', 'delay', 'wait_for', 'create_record', 'update_record', 'delete_record', 'create_activity', 'add_note',
  'notify', 'send_email', 'enroll_sequence', 'assign_owner', 'create_ticket', 'campaign_action', 'project_action', 'webhook',
  'slack', 'teams', 'accounting_invoice',
] as const
export type WorkflowKind = (typeof WORKFLOW_KINDS)[number]

/** The design's palette (Automation.dc.html, `palette`), in its order, then the engine's other actions. */
export const PALETTE: WorkflowKind[] = [
  'condition', 'if_else', 'delay', 'wait_for', 'create_record', 'update_record', 'delete_record', 'send_email', 'add_note',
  'campaign_action', 'project_action', 'webhook', 'slack', 'teams',
  'create_activity', 'notify', 'enroll_sequence', 'assign_owner', 'create_ticket', 'accounting_invoice',
]

/** Steps that cannot run yet in this platform: the phases that build them (campaigns 5, projects 6). */
export const NOT_AVAILABLE = new Set<string>(['campaign_action', 'project_action'])

/** The node family the canvas draws a step as (the design's K map). */
export function nodeFamily(kind: string): 'cond' | 'branch' | 'delay' | 'wait' | 'hook' | 'action' {
  if (kind === 'condition') return 'cond'
  if (kind === 'if_else') return 'branch'
  if (kind === 'delay') return 'delay'
  if (kind === 'wait_for') return 'wait'
  if (kind === 'webhook') return 'hook'
  return 'action'
}

/** A new step's configuration: what the step needs, empty where only the person can say what it is. */
export function defaultConfig(kind: string): Record<string, unknown> {
  switch (kind) {
    case 'condition':
    case 'if_else':
      return { groups: [[{ f: '', op: 'eq', v: '' }]] }
    case 'delay':
      return { amount: 1, unit: 'days', skip_weekends: false }
    case 'wait_for':
      return { event: 'email.replied', timeout_days: 7, then: 'continue' }
    case 'create_record':
      return { entity: 'deal', values: {} }
    case 'update_record':
      return { values: {} }
    case 'create_activity':
      return { type: 'task', subject: '', due_in_days: 0, owner: '@record_owner' }
    case 'add_note':
      return { body: '' }
    case 'notify':
      return { to: '@record_owner', message: '' }
    case 'send_email':
      return { template_id: '', from: '@record_owner' }
    case 'enroll_sequence':
      return { sequence_id: '' }
    case 'assign_owner':
      return { assignee: { kind: 'org_owner' } }
    case 'create_ticket':
      return { category_key: '', subject: '' }
    case 'webhook':
      return { method: 'POST', url: '', body: '' }
    case 'slack':
    case 'teams':
      return { channel: '', message: '' }
    default:
      return {}
  }
}

/** Every step, depth first, in the order the canvas draws them. */
export function allSteps(steps: Step[]): Step[] {
  const out: Step[] = []
  for (const s of steps) {
    out.push(s)
    if (s.kind === 'if_else') out.push(...allSteps(s.then ?? []), ...allSteps(s.else ?? []))
  }
  return out
}

export const findStep = (g: Graph, key: string) => allSteps(g.steps).find((s) => s.key === key) ?? null

/** A key no step uses yet (app.wf_validate: ^[a-z0-9_]{1,24}$, unique in the graph). */
export function newKey(g: Graph): string {
  const used = new Set(allSteps(g.steps).map((s) => s.key))
  let i = used.size + 1
  while (used.has(`s${i}`)) i++
  return `s${i}`
}

function mapList(steps: Step[], ref: ListRef, fn: (list: Step[]) => Step[]): Step[] {
  if (ref.length === 0) return fn(steps)
  const [i, side, ...rest] = ref
  return steps.map((s, j) => (j === i && (side === 'then' || side === 'else') ? { ...s, [side]: mapList(s[side] ?? [], rest, fn) } : s))
}

export function insertStep(g: Graph, slot: Slot, step: Step): Graph {
  return { steps: mapList(g.steps, slot.list, (list) => [...list.slice(0, slot.index), step, ...list.slice(slot.index)]) }
}

function removeIn(steps: Step[], key: string): Step[] {
  return steps
    .filter((s) => s.key !== key)
    .map((s) => (s.kind === 'if_else' ? { ...s, then: removeIn(s.then ?? [], key), else: removeIn(s.else ?? [], key) } : s))
}
export const removeStep = (g: Graph, key: string): Graph => ({ steps: removeIn(g.steps, key) })

function patchIn(steps: Step[], key: string, config: Record<string, unknown>): Step[] {
  return steps.map((s) => {
    if (s.key === key) return { ...s, config }
    return s.kind === 'if_else' ? { ...s, then: patchIn(s.then ?? [], key, config), else: patchIn(s.else ?? [], key, config) } : s
  })
}
export const setConfig = (g: Graph, key: string, config: Record<string, unknown>): Graph => ({ steps: patchIn(g.steps, key, config) })

/** The slot right after a step (where the palette adds when a step is selected). */
export function slotAfter(g: Graph, key: string): Slot | null {
  const walk = (steps: Step[], ref: ListRef): Slot | null => {
    for (let i = 0; i < steps.length; i++) {
      const s = steps[i]!
      if (s.key === key) return { list: ref, index: i + 1 }
      if (s.kind === 'if_else') {
        const a = walk(s.then ?? [], [...ref, i, 'then'])
        if (a) return a
        const b = walk(s.else ?? [], [...ref, i, 'else'])
        if (b) return b
      }
    }
    return null
  }
  return walk(g.steps, [])
}

export const sameSlot = (a: Slot | null, b: Slot | null) =>
  !!a && !!b && a.index === b.index && a.list.length === b.list.length && a.list.every((x, i) => x === b.list[i])

/** A new step of a kind; an if/else starts with two empty paths. */
export function makeStep(g: Graph, kind: string): Step {
  const s: Step = { key: newKey(g), kind, config: defaultConfig(kind) }
  if (kind === 'if_else') { s.then = []; s.else = [] }
  return s
}

/** Delay days the way the engine sums them (app.wf_path_counts): minutes and hours as fractions of a day. */
export function delayDays(config: Record<string, unknown>): number {
  const n = Number(config.amount ?? 0)
  const unit = String(config.unit ?? 'days')
  return unit === 'minutes' ? n / 1440 : unit === 'hours' ? n / 24 : n
}

/** The step a key names in a validation error detail («graph.<key>.<field>»), and the field. */
export function errorTarget(detail: string | null | undefined): { key: string | null; field: string | null } {
  const m = /^graph\.([a-z0-9_]+)(?:\.([a-z_.]+))?$/.exec(detail ?? '')
  if (!m || m[1] === 'steps' || m[1] === 'key' || m[1] === 'limit') return { key: null, field: null }
  return { key: m[1]!, field: m[2] ?? null }
}
