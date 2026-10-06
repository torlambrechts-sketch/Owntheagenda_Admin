'use server'

import { cookies } from 'next/headers'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { ACTIONS, SCOPES } from '@/lib/data/settings'

/**
 * Settings' writes. Each parses its input with zod, calls one database function through rpc(), and answers
 * { ok: true } or { ok: false, code } with a code the screen has a message for (common.errors.<code>).
 */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode }

const uuid = z.string().uuid()
const key = z.string().regex(/^[a-z_]{2,40}$/)
const bad = { ok: false as const, code: 'invalid' as const }
const done = (layout = false) => revalidatePath(layout ? '/' : '/settings', layout ? 'layout' : 'page')

async function call<S extends z.ZodTypeAny>(fn: string, args: Record<string, unknown>, schema: S, layout = false): Promise<Result<{ data: z.infer<S> }>> {
  const r = await rpc(fn, args, schema)
  if (!r.ok) return { ok: false, code: r.code }
  done(layout)
  return { ok: true, data: r.data }
}
const strip = <T extends object>(r: Result<T>): Result => (r.ok ? { ok: true } : r)

// ---------------------------------------------------------------------------
// rules, modules
const SettingIn = z.object({
  key,
  value: z.string().regex(/^[a-z0-9_]{1,40}$/),
  scopeId: z.string().regex(/^[a-z0-9_-]{0,80}$/).default(''),
  number: z.number().min(0).max(1_000_000_000).nullable().default(null),
})
export async function setSetting(input: z.input<typeof SettingIn>): Promise<Result> {
  const p = SettingIn.safeParse(input)
  if (!p.success) return bad
  return strip(await call('setting_set', { p_key: p.data.key, p_value: p.data.value, p_scope_id: p.data.scopeId, p_number: p.data.number }, z.object({ key: z.string() }), true))
}

export async function setModule(input: { key: string; enabled: boolean }): Promise<Result> {
  const p = z.object({ key, enabled: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  return strip(await call('module_set', { p_key: p.data.key, p_enabled: p.data.enabled }, z.object({ key: z.string() }), true))
}

// ---------------------------------------------------------------------------
// fields
const FIELD_TYPES = ['text', 'large_text', 'single_option', 'multiple_options', 'autocomplete', 'numerical', 'monetary', 'user', 'organization', 'person',
  'phone', 'time', 'time_range', 'date', 'date_range', 'address', 'formula'] as const
const FieldIn = z.object({
  id: uuid.nullable(),
  values: z
    .object({
      entity: key,
      key: z.string().regex(/^[a-z][a-z0-9_]{1,40}$/),
      label: z.string().trim().min(1).max(80),
      type: z.enum(FIELD_TYPES),
      options: z.array(z.object({ key: z.string().regex(/^[a-z0-9_]{1,40}$/), label: z.string().trim().min(1).max(80) })).max(1000),
      quality: z.enum(['optional', 'important', 'required']),
      from_stage_id: uuid.nullable(),
      pipeline_ids: z.array(uuid).nullable(),
      hidden_for: z.array(uuid),
      readonly_for: z.array(uuid),
      description: z.string().max(300).nullable(),
      formula: z.string().trim().min(1).max(500).nullable(),
      archived: z.boolean(),
    })
    .partial(),
})
/** A new field's key may still belong to an archived field (keys stay unique per record type): refused as invalid, detail key. */
export async function saveField(input: z.input<typeof FieldIn>): Promise<({ ok: true; id: string }) | { ok: false; code: RpcCode; detail?: 'key' }> {
  const p = FieldIn.safeParse(input)
  if (!p.success) return bad
  if (!p.data.id && (!p.data.values.entity || !p.data.values.label || !p.data.values.type)) return bad
  const r = await rpc('field_save', { p_id: p.data.id, p_values: p.data.values }, z.object({ id: uuid }))
  if (!r.ok) return { ok: false, code: r.code, ...(r.detail === 'key' ? { detail: 'key' as const } : {}) }
  done()
  return { ok: true, id: r.data.id }
}

// ---------------------------------------------------------------------------
// pipelines and stages
export async function savePipeline(input: { id: string | null; name: string }): Promise<Result<{ id: string }>> {
  const p = z.object({ id: uuid.nullable(), name: z.string().trim().min(1).max(80) }).safeParse(input)
  if (!p.success) return bad
  const r = await call('pipeline_save', { p_id: p.data.id, p_values: { name: p.data.name } }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : r
}

const StageIn = z.object({
  id: uuid.nullable(),
  pipeline: uuid,
  values: z.object({ name: z.string().trim().min(1).max(60), probability: z.number().int().min(0).max(100), rot_days: z.number().int().min(1).max(3650).nullable() }).partial(),
})
export async function saveStage(input: z.input<typeof StageIn>): Promise<Result> {
  const p = StageIn.safeParse(input)
  if (!p.success) return bad
  const v = { ...p.data.values, ...(p.data.values.rot_days !== undefined ? { rot_days: p.data.values.rot_days === null ? '' : String(p.data.values.rot_days) } : {}) }
  return strip(await call('stage_save', { p_id: p.data.id, p_pipeline: p.data.pipeline, p_values: v }, z.object({ id: uuid })))
}

export async function reorderStages(input: { pipeline: string; ids: string[] }): Promise<Result> {
  const p = z.object({ pipeline: uuid, ids: z.array(uuid).min(1).max(100) }).safeParse(input)
  if (!p.success) return bad
  return strip(await call('stages_reorder', { p_pipeline: p.data.pipeline, p_ids: p.data.ids }, z.object({ ok: z.boolean() })))
}

export async function deleteStage(input: { stage: string; target: string }): Promise<Result<{ moved: number }>> {
  const p = z.object({ stage: uuid, target: uuid }).safeParse(input)
  if (!p.success || p.data.stage === p.data.target) return bad
  const r = await call('stage_delete', { p_stage: p.data.stage, p_target: p.data.target }, z.object({ moved: z.number() }))
  return r.ok ? { ok: true, moved: r.data.moved } : r
}

// ---------------------------------------------------------------------------
// activity types
const ActTypeIn = z.object({
  id: uuid.nullable(),
  values: z.object({ name: z.string().trim().min(1).max(40), glyph: z.string().trim().min(1).max(3), active: z.boolean() }).partial(),
})
export async function saveActivityType(input: z.input<typeof ActTypeIn>): Promise<Result> {
  const p = ActTypeIn.safeParse(input)
  if (!p.success || (!p.data.id && !p.data.values.name)) return bad
  return strip(await call('activity_type_save', { p_id: p.data.id, p_values: p.data.values }, z.object({ id: uuid })))
}

// ---------------------------------------------------------------------------
// my language, time zone and number format (as the account menu does: profile and the lang cookie)
const ProfileIn = z
  .object({ locale: z.enum(['en', 'no']), time_zone: z.string().regex(/^[A-Za-z0-9_+\-/]{3,60}$/), number_format: z.enum(['space_comma', 'comma_dot', 'dot_comma']) })
  .partial()
export async function setProfile(input: z.input<typeof ProfileIn>): Promise<Result> {
  const p = ProfileIn.safeParse(input)
  if (!p.success || Object.keys(p.data).length === 0) return bad
  const r = await call('profile_set', { p_values: p.data }, z.object({ ok: z.boolean() }), true)
  if (r.ok && p.data.locale) {
    ;(await cookies()).set('lang', p.data.locale, { httpOnly: true, sameSite: 'lax', secure: process.env.NODE_ENV === 'production', path: '/', maxAge: 60 * 60 * 24 * 365 })
  }
  return strip(r)
}

// ---------------------------------------------------------------------------
// staff, teams, permission sets, groups
const StaffIn = z.object({
  id: uuid.nullable(),
  values: z
    .object({
      email: z.string().trim().toLowerCase().email().max(200),
      name: z.string().trim().min(1).max(120),
      title: z.string().trim().max(60),
      permission_set_id: uuid,
      group_id: uuid,
      team_id: uuid.nullable(),
      active: z.boolean(),
    })
    .partial(),
})
export async function saveStaff(input: z.input<typeof StaffIn>): Promise<Result> {
  const p = StaffIn.safeParse(input)
  if (!p.success || (!p.data.id && (!p.data.values.email || !p.data.values.name))) return bad
  return strip(await call('staff_save', { p_id: p.data.id, p_values: p.data.values }, z.object({ id: uuid })))
}

export async function copyAccess(input: { from: string; to: string }): Promise<Result> {
  const p = z.object({ from: uuid, to: uuid }).safeParse(input)
  if (!p.success || p.data.from === p.data.to) return bad
  return strip(await call('staff_copy_access', { p_from: p.data.from, p_to: p.data.to }, z.object({ ok: z.boolean() })))
}

export async function replaceStaff(input: { old: string; next: string }): Promise<Result<{ reassigned: number }>> {
  const p = z.object({ old: uuid, next: uuid }).safeParse(input)
  if (!p.success || p.data.old === p.data.next) return bad
  const r = await call('staff_replace', { p_old: p.data.old, p_new: p.data.next }, z.object({ reassigned: z.number() }))
  return r.ok ? { ok: true, reassigned: r.data.reassigned } : r
}

export async function saveTeam(input: { id: string | null; name: string; manager: string | null; members: string[] }): Promise<Result> {
  const p = z.object({ id: uuid.nullable(), name: z.string().trim().min(1).max(80), manager: uuid.nullable(), members: z.array(uuid).max(500) }).safeParse(input)
  if (!p.success) return bad
  return strip(await call('team_save', { p_id: p.data.id, p_name: p.data.name, p_manager: p.data.manager, p_members: p.data.members }, z.object({ id: uuid })))
}

const RIGHT = z.string().refine((r) => {
  const [s, a, ...rest] = r.split(':')
  return rest.length === 0 && (SCOPES as readonly string[]).includes(s ?? '') && (ACTIONS as readonly string[]).includes(a ?? '')
})
export async function savePermissionSet(input: { id: string | null; name: string; rights: string[] }): Promise<Result<{ id: string }>> {
  const p = z.object({ id: uuid.nullable(), name: z.string().trim().min(1).max(80), rights: z.array(RIGHT).max(SCOPES.length * ACTIONS.length) }).safeParse(input)
  if (!p.success) return bad
  const r = await call('permission_set_save', { p_id: p.data.id, p_name: p.data.name, p_rights: [...new Set(p.data.rights)] }, z.object({ id: uuid }), true)
  return r.ok ? { ok: true, id: r.data.id } : r
}

export async function saveGroup(input: { id: string | null; name: string; parent: string | null }): Promise<Result> {
  const p = z.object({ id: uuid.nullable(), name: z.string().trim().min(1).max(80), parent: uuid.nullable() }).safeParse(input)
  if (!p.success) return bad
  return strip(await call('group_save', { p_id: p.data.id, p_name: p.data.name, p_parent: p.data.parent }, z.object({ id: uuid })))
}

// ---------------------------------------------------------------------------
// sandbox
export async function clearSandbox(): Promise<Result<{ removed: number }>> {
  const r = await call('sandbox_clear', {}, z.object({ removed: z.number() }), true)
  return r.ok ? { ok: true, removed: r.data.removed } : r
}

export async function switchSandbox(on: boolean): Promise<Result> {
  const p = z.boolean().safeParse(on)
  if (!p.success) return bad
  return strip(await call('sandbox_set', { p_on: p.data }, z.object({ sandbox: z.boolean() }), true))
}
