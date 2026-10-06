import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import type { Shell } from '@/lib/shell'

/**
 * Loaders for Settings (Settings.dc.html). Every value comes from a database function and is parsed; a
 * section whose source the staff member may not read comes back null and the section says so.
 */

export const SECTIONS = ['rules', 'modules', 'fields', 'pipelines', 'acttypes', 'locale', 'users', 'perms', 'groups', 'plans', 'sandbox'] as const
export type Section = (typeof SECTIONS)[number]

/** The design's groups of «Rules and limits», in its order; the register's other groups live elsewhere. */
export const RULE_GROUPS = ['contacts_consent', 'tracking', 'approvals_audit', 'limits', 'safeguards', 'meetings', 'platform_constant'] as const

/** The record types in the design's order (Deals, Leads, People, Organizations, Products, Activities), then the rest. */
const ENTITY_ORDER = ['deal', 'lead', 'person', 'organization', 'catalog_item', 'project', 'activity', 'ticket']
export const sortEntities = (keys: string[]) =>
  [...keys].sort((a, b) => (ENTITY_ORDER.indexOf(a) + 1 || 99) - (ENTITY_ORDER.indexOf(b) + 1 || 99) || a.localeCompare(b))

export { SCOPE_KEYS as SCOPES, ACTION_KEYS as ACTIONS } from './settings-matrix'

/** May the staff member do this? (Mirrors app.can, including the tickets scope; the database decides.) */
export const allowed = (shell: Shell, scope: string, action: string) =>
  shell.me.permission_kind === 'admin' || shell.me.rights.includes(`${scope}:${action}`)

const num = z.coerce.number()

// ---------------------------------------------------------------------------
// the register
export const Setting = z.object({
  key: z.string(),
  group: z.string(),
  options: z.array(z.string()),
  default: z.string(),
  scope: z.enum(['platform', 'entity', 'pipeline']),
  applies_to: z.string(),
  fixed: z.boolean(),
  numeric_option: z.string().nullable(),
  values: z.array(z.object({ scope_id: z.string(), value: z.string(), number: num.nullable(), updated_at: z.string() })),
})
export type Setting = z.infer<typeof Setting>
export const loadSettings = () => rpcOrThrow('settings_get', {}, z.array(Setting))

/** The effective value of a setting for a scope: its stored value, else the default. */
export const effective = (s: Setting, scopeId = '') => {
  const v = s.values.find((x) => x.scope_id === scopeId)
  return { value: v?.value ?? s.default, number: v?.number ?? null }
}

export const LogEntry = z.object({
  at: z.string(),
  actor: z.string().nullable(),
  key: z.string().nullable(),
  scope_id: z.string().nullable(),
  from: z.string().nullable(),
  to: z.string().nullable(),
})
export type LogEntry = z.infer<typeof LogEntry>
export const loadSettingsLog = () => rpcOrThrow('settings_log', { p_limit: 50 }, z.array(LogEntry))

// ---------------------------------------------------------------------------
// modules
export const Module = z.object({ key: z.string(), enabled: z.boolean() })
export const loadModules = () => rpcOrThrow('modules_get', {}, z.array(Module))

// ---------------------------------------------------------------------------
// fields
export const FieldOption = z.object({ key: z.string(), label: z.string().optional() }).passthrough()
export const Field = z.object({
  id: z.string().uuid(),
  entity: z.string(),
  key: z.string(),
  label: z.string(),
  type: z.string(),
  options: z.array(z.union([FieldOption, z.string()])),
  quality: z.enum(['optional', 'important', 'required']),
  from_stage_id: z.string().uuid().nullable(),
  pipeline_ids: z.array(z.string().uuid()).nullable(),
  hidden_for: z.array(z.string().uuid()),
  readonly_for: z.array(z.string().uuid()),
  description: z.string().nullable(),
  formula: z.string().nullable(),
  activity_type_ids: z.array(z.string().uuid()).nullable().optional(),
  ord: num,
})
export type Field = z.infer<typeof Field>
export const loadFields = (entity: string | null) => rpcOrThrow('fields_get', { p_entity: entity }, z.array(Field))

/** The record types in the registry (app.entities), read through the sandbox counts, which list every one. */
export const SandboxCounts = z.record(z.string(), z.union([z.number(), z.string(), z.null()]))
export async function loadSandboxCounts() {
  const raw = await rpcOrThrow('sandbox_counts', {}, SandboxCounts)
  const counts: Record<string, number> = {}
  for (const [k, v] of Object.entries(raw)) if (k !== 'last_cleared' && typeof v === 'number') counts[k] = v
  const last = typeof raw.last_cleared === 'string' ? raw.last_cleared : null
  return { counts, entities: sortEntities(Object.keys(counts)), lastCleared: last }
}

// ---------------------------------------------------------------------------
// pipelines and activity types
export const Stage = z.object({ id: z.string().uuid(), name: z.string(), ord: num, probability: num, rot_days: num.nullable(), open_deals: num })
export const Pipeline = z.object({
  id: z.string().uuid(),
  name: z.string(),
  ord: num,
  visibility_group_ids: z.array(z.string().uuid()).nullable(),
  stages: z.array(Stage),
})
export type Pipeline = z.infer<typeof Pipeline>
/** Null when the deals module is off or the staff member may not see deals. */
export const loadPipelines = async () => {
  const r = await rpc('pipelines_get', {}, z.array(Pipeline), { quiet: true })
  return r.ok ? r.data : null
}

export const ActivityType = z.object({ id: z.string().uuid(), key: z.string(), name: z.string(), glyph: z.string(), ord: num, active: z.boolean(), is_system: z.boolean() })
export type ActivityType = z.infer<typeof ActivityType>
export const loadActivityTypes = () => rpcOrThrow('activity_types_get', {}, z.array(ActivityType))

// ---------------------------------------------------------------------------
// staff and access
export const Staff = z.object({
  id: z.string().uuid(),
  name: z.string(),
  initials: z.string().nullable(),
  title: z.string().nullable(),
  email: z.string().nullable(),
  active: z.boolean(),
  permission_set_id: z.string().uuid(),
  permission_set: z.string(),
  group_id: z.string().uuid(),
  group: z.string(),
  team_id: z.string().uuid().nullable(),
  last_seen_at: z.string().nullable(),
  is_sample: z.boolean(),
})
export type Staff = z.infer<typeof Staff>
export const loadStaff = () => rpcOrThrow('staff_list', {}, z.array(Staff))

export const AccessModel = z.object({
  permission_sets: z.array(z.object({ id: z.string().uuid(), key: z.string().nullable(), name: z.string(), kind: z.enum(['admin', 'regular', 'custom']), rights: z.array(z.string()), members: num })),
  groups: z.array(z.object({ id: z.string().uuid(), name: z.string(), parent_id: z.string().uuid().nullable(), members: num })),
  teams: z.array(
    z.object({
      id: z.string().uuid(),
      name: z.string(),
      manager_id: z.string().uuid().nullable(),
      manager: z.string().nullable(),
      members: z.array(z.object({ id: z.string().uuid(), name: z.string() })),
    }),
  ),
})
export type AccessModel = z.infer<typeof AccessModel>
export const loadAccessModel = () => rpcOrThrow('access_model', {}, AccessModel)

// ---------------------------------------------------------------------------
// plans and usage: real counts only
/** The number of live records of a type the staff member can see, or null when they may not list it. */
export async function countRecords(entity: string): Promise<number | null> {
  const r = await rpc('rec_list', { p_entity: entity, p_query: { limit: 1 } }, z.object({ total: num }), { quiet: true })
  return r.ok ? r.data.total : null
}
