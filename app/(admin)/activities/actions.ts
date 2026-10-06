'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'

/**
 * The Activities screen's writes. Each parses its input, calls one database function (or a short
 * sequence on the same record), and answers { ok } or { ok: false, code } — the codes have messages in
 * common.errors. The database checks the rights and the version again.
 */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode | 'invalid'; detail?: string | null }

const uuid = z.string().uuid()
const iso = z.iso.datetime({ offset: true })
const Priority = z.enum(['high', 'medium', 'low'])
const Channel = z.enum(['app', 'email', 'desktop', 'push'])
const Saved = z.object({ id: uuid, version: z.coerce.number() }).passthrough()
const done = () => revalidatePath('/activities')
const bad = (detail?: string): Result<never> => ({ ok: false, code: 'invalid', detail: detail ?? null })

const Values = z.object({
  type_id: uuid,
  subject: z.string().trim().min(1).max(200),
  starts_at: iso.nullable(),
  all_day: z.boolean(),
  duration_min: z.number().int().min(0).max(1440),
  priority: Priority,
  note: z.string().max(10000).nullable(),
  deal_id: uuid.nullable(),
  person_id: uuid.nullable(),
  organization_id: uuid.nullable(),
  video_provider: z.enum(['meet', 'teams', 'zoom']).nullable(),
  video_url: z.string().trim().max(500).nullable(),
  owner_id: uuid.nullable(),
  custom: z.record(z.string(), z.union([z.string(), z.null()])),
})
const SaveInput = z.object({
  id: uuid.nullable(),
  version: z.number().int().nullable(),
  values: Values,
  guests: z.array(z.object({ email: z.email().max(254), name: z.string().max(200).nullable(), person_id: uuid.nullable() })).max(100),
  reminders: z.array(z.object({ channel: Channel, offset_min: z.number().int().min(0).max(10080) })).max(20),
})
export type SaveInput = z.infer<typeof SaveInput>

/** Create or edit one activity, then replace its guests and reminders as sets. */
export type SaveResult = { ok: true; id: string } | { ok: false; code: RpcCode | 'invalid'; detail?: string | null; part?: 'guests' | 'reminders'; id?: string }
export async function saveActivity(input: SaveInput): Promise<SaveResult> {
  const p = SaveInput.safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path.join('.') ?? ''))
  const { id, version, values, guests, reminders } = p.data
  const { custom, ...cols } = values
  const v: Record<string, unknown> = { ...cols, video_url: cols.video_url || null }
  if (Object.keys(custom).length) v.custom = custom
  if (id === null && v.owner_id === null) delete v.owner_id
  const r = await rpc('rec_save', { p_entity: 'activity', p_id: id, p_values: v, p_version: version }, Saved)
  if (!r.ok) return r
  // the activity is saved; a refusal of its guests or reminders (owner or deals:edit_others, R-ACT-03) is reported as such
  const g = await rpc('activity_guests_set', { p_id: r.data.id, p_guests: guests }, z.array(z.unknown()))
  if (!g.ok) { done(); return { ok: false, code: g.code, detail: g.detail, part: 'guests', id: r.data.id } }
  const m = await rpc('activity_reminders_set', { p_id: r.data.id, p_reminders: reminders }, z.array(z.unknown()))
  done()
  if (!m.ok) return { ok: false, code: m.code, detail: m.detail, part: 'reminders', id: r.data.id }
  return { ok: true, id: r.data.id }
}

/** Drag on the week grid, or the edit dialog's date: a new start, same duration. */
export async function reschedule(input: { id: string; version: number; starts_at: string }): Promise<Result> {
  const p = z.object({ id: uuid, version: z.number().int(), starts_at: iso }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('rec_save', { p_entity: 'activity', p_id: p.data.id, p_values: { starts_at: p.data.starts_at, all_day: false }, p_version: p.data.version }, Saved)
  done()
  return r.ok ? { ok: true } : r
}

export async function setPriority(input: { id: string; version: number; priority: string }): Promise<Result> {
  const p = z.object({ id: uuid, version: z.number().int(), priority: Priority }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('rec_save', { p_entity: 'activity', p_id: p.data.id, p_values: { priority: p.data.priority }, p_version: p.data.version }, Saved)
  done()
  return r.ok ? { ok: true } : r
}

/** Done or open again; the answer says whether to ask for the next step. */
export async function markDone(input: { id: string; done: boolean }): Promise<Result<{ prompt: boolean }>> {
  const p = z.object({ id: uuid, done: z.boolean() }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('activity_done', { p_id: p.data.id, p_done: p.data.done }, z.object({ id: uuid, prompt: z.boolean() }))
  done()
  return r.ok ? { ok: true, prompt: r.data.prompt } : r
}

const Ids = z.array(uuid).min(1).max(500)

export async function bulkDone(ids: string[]): Promise<Result<{ n: number }>> {
  const p = Ids.safeParse(ids)
  if (!p.success) return bad()
  const r = await rpc('activities_done_bulk', { p_ids: p.data }, z.object({ done: z.coerce.number() }))
  done()
  return r.ok ? { ok: true, n: r.data.done } : r
}

export async function bulkPriority(ids: string[], priority: string): Promise<Result<{ n: number }>> {
  const p = z.object({ ids: Ids, priority: Priority }).safeParse({ ids, priority })
  if (!p.success) return bad()
  const r = await rpc('rec_bulk', { p_entity: 'activity', p_ids: p.data.ids, p_values: { priority: p.data.priority } }, z.object({ updated: z.coerce.number() }))
  done()
  return r.ok ? { ok: true, n: r.data.updated } : r
}

/**
 * «Move to tomorrow»: activities_shift moves by whole days and keeps each one's time of day in one transaction
 * (R-ACT-05). The selection is grouped by how many days each activity is from tomorrow (usually one group);
 * activities without a time become all-day items tomorrow.
 */
export async function bulkMove(input: { shifts: { ids: string[]; days: number }[]; undated: { ids: string[]; starts_at: string } | null }): Promise<Result<{ n: number }>> {
  const p = z.object({
    shifts: z.array(z.object({ ids: Ids, days: z.number().int().min(-365).max(365) })).max(50),
    undated: z.object({ ids: Ids, starts_at: iso }).nullable(),
  }).safeParse(input)
  if (!p.success) return bad()
  let n = 0
  for (const g of p.data.shifts) {
    const r = await rpc('activities_shift', { p_ids: g.ids, p_days: g.days }, z.object({ moved: z.coerce.number() }))
    if (!r.ok) { done(); return r }
    n += r.data.moved
  }
  if (p.data.undated) {
    const r = await rpc('rec_bulk', { p_entity: 'activity', p_ids: p.data.undated.ids, p_values: { starts_at: p.data.undated.starts_at, all_day: true } }, z.object({ updated: z.coerce.number() }))
    if (!r.ok) { done(); return r }
    n += r.data.updated
  }
  done()
  return { ok: true, n }
}

/** The next-step prompt: a new activity on the same deal, person and organization. */
export async function planNext(input: { type_id: string; subject: string; starts_at: string; deal_id: string | null; person_id: string | null; organization_id: string | null }): Promise<Result> {
  const p = z.object({ type_id: uuid, subject: z.string().trim().min(1).max(200), starts_at: iso, deal_id: uuid.nullable(), person_id: uuid.nullable(), organization_id: uuid.nullable() }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('rec_save', { p_entity: 'activity', p_id: null, p_values: { ...p.data, duration_min: 30, priority: 'medium' } }, Saved)
  done()
  return r.ok ? { ok: true } : r
}

export async function setReminderPrefs(input: { channels?: string[]; default_offset?: number }): Promise<Result> {
  const p = z.object({ channels: z.array(Channel).max(4).optional(), default_offset: z.number().int().min(0).max(10080).optional() }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('reminder_prefs_set', { p_values: p.data }, z.object({ ok: z.boolean() }))
  done()
  return r.ok ? { ok: true } : r
}

export async function setAvailability(cells: { weekday: number; hour: number }[]): Promise<Result> {
  const p = z.array(z.object({ weekday: z.number().int().min(1).max(7), hour: z.number().int().min(0).max(23) })).max(168).safeParse(cells)
  if (!p.success) return bad()
  const r = await rpc('availability_set', { p_cells: p.data }, z.object({ ok: z.boolean() }))
  done()
  return r.ok ? { ok: true } : r
}

export async function createBookingLink(input: { title: string; duration_min: number; kind: 'general' | 'proposed'; proposed_times: string[] }): Promise<Result> {
  const p = z.object({
    title: z.string().trim().min(1).max(120),
    duration_min: z.number().int().min(5).max(480),
    kind: z.enum(['general', 'proposed']),
    proposed_times: z.array(iso).max(10),
  }).refine((v) => v.kind === 'general' || v.proposed_times.length > 0, { path: ['proposed_times'] }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path[0] ?? 'title'))
  const values = { title: p.data.title, duration_min: p.data.duration_min, kind: p.data.kind, ...(p.data.kind === 'proposed' ? { proposed_times: p.data.proposed_times } : {}) }
  const r = await rpc('booking_link_save', { p_id: null, p_values: values }, z.object({ id: uuid }))
  done()
  return r.ok ? { ok: true } : r
}

/** The calendar choice, stored while no provider is connected (R-ACT-01); the status stays not connected. */
export async function saveCalendar(input: { provider?: string; mode?: string; calendar_id?: string | null; sync_type_ids?: string[] }): Promise<Result> {
  const p = z.object({
    provider: z.enum(['google', 'microsoft']).optional(),
    mode: z.enum(['one_way', 'two_way']).optional(),
    calendar_id: z.string().max(200).nullable().optional(),
    sync_type_ids: z.array(uuid).max(50).optional(),
  }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('calendar_connection_save', { p_values: p.data }, z.object({ provider: z.string() }).passthrough())
  done()
  return r.ok ? { ok: true } : r
}
