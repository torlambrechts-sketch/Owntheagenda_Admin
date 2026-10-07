import 'server-only'
import { z } from 'zod'
import { rpc, type RpcResult } from '@/lib/rpc'
import { PREF_KINDS, type Coords, type DealPreview, type Preview, type PushState } from './mobile-shared'

/**
 * Mobile (Mobile.dc.html) reads through the 0044 functions (contract: docs/crm-enrichment/deviations/platform-schema.md,
 * Mobile) and the web's own (deal_detail, notes_list, fields_get, activities_get, deal_list, notifications_get). Every
 * shape is parsed, never cast. The device's coordinates are request parameters only: passed to mobile_focus and nearby,
 * never stored, logged or returned. The worker_* functions are the service role's and are never called from here.
 */
const num = z.coerce.number()
const nnum = z.coerce.number().nullable()
const id = z.guid()
const str = z.string()
const nstr = z.string().nullable()

export const FocusSchema = z.object({
  hour: num,
  name: str,
  overdue_activities: num,
  deals_past_close: nnum,
  // deal_id and organization_id (R-MOBILE-06): null when the record is gone or hidden from the caller
  today: z.array(z.object({ id, subject: str, starts_at: nstr, done: z.boolean(), type: nstr, organization: nstr, organization_id: id.nullable(), deal: nstr, deal_id: id.nullable(), km: nnum })),
  unread_threads: num,
  nearby_10km: nnum,
  closing_this_week: z.object({ count: num, value_nok: num, excluded_currency: num }).nullable(),
  month: z.object({
    won_value_nok: num,
    new_deals: num,
    goal: z.object({ id, name: str, progress: nnum, target_value: nnum, target_count: nnum }).nullable(),
  }).nullable(),
  tasks_due_today: nnum,
  chats_waiting: nnum,
  contact_rule: str,
})

export const NearbySchema = z.array(z.object({
  entity: z.enum(['organization', 'person']),
  id,
  title: str,
  city: nstr.optional().transform((v) => v ?? null),
  km: num,
  // the organisation's place the distance was measured to (R-MOBILE-05), never the device's; a pin is drawn only where known
  lat: nnum.optional().transform((v) => v ?? null),
  lng: nnum.optional().transform((v) => v ?? null),
  deal: z.object({ id, title: str, stage: nstr }).nullable().optional().transform((v) => v ?? null),
  health: nnum.optional().transform((v) => v ?? null),
  customer: z.boolean().optional().transform((v) => v ?? false),
  last_visit_at: nstr.optional().transform((v) => v ?? null),
}))

const DealDetail = z.object({
  id, title: str, value: num, currency: str, version: num, stage_id: id, expected_close_date: nstr, score: nnum,
  organization: nstr, organization_id: id.nullable(), custom: z.record(z.string(), z.unknown()),
  person_detail: z.object({ id, name: str, title: nstr, phone: nstr }).nullable(),
  stages: z.array(z.object({ id, name: str })).nullable(),
})
const Field = z.object({ key: str, label: str, quality: str, from_stage_id: id.nullable() })
const Note = z.object({ body: str, pinned: z.boolean(), author: nstr })
const DealRow = z.object({ id })

const Notifications = z.object({
  unread: num,
  items: z.array(z.object({
    id, kind: str, key: str, params: z.record(z.string(), z.union([z.string(), z.number()]).catch('')), route: nstr, created_at: str, read: z.boolean(),
  })),
})
const Push = z.object({
  push_ready: z.boolean(), setting: str, module: z.boolean(),
  devices: z.array(z.object({ id, platform: str, label: nstr, created_at: str, last_used_at: nstr, failures: num })),
})
const Prefs = z.array(z.object({ kind: z.enum(PREF_KINDS), channels: z.array(str) }))
const Types = z.array(z.object({ id, key: str, active: z.boolean() }))

const coordArgs = (c: Coords | null) => ({ p_lat: c?.lat ?? null, p_lng: c?.lng ?? null })

export const loadFocus = (c: Coords | null) => rpc('mobile_focus', coordArgs(c), FocusSchema)

export const loadNearby = (c: Coords) =>
  rpc('nearby', { p_lat: c.lat, p_lng: c.lng, p_radius_km: 10, p_entities: ['organization'], p_filter: {} }, NearbySchema)

/**
 * «Deal on the go»: the deal of the staff member's next activity today (mobile_focus().today carries its deal_id,
 * R-MOBILE-06), else their open deal closing soonest. The next stage's required fields come from the field register
 * (quality «required» from a stage at or before it), the note is the deal's latest (pinned first, as notes_list orders them).
 */
export async function loadDealPreview(me: string, today: z.infer<typeof FocusSchema>['today']): Promise<DealPreview | null> {
  let dealId = today.find((r) => r.deal_id && !r.done)?.deal_id ?? today.find((r) => r.deal_id)?.deal_id ?? null
  if (!dealId) {
    const list = await rpc('deal_list', {
      p_query: { status: 'open', limit: 1, filters: [{ f: 'owner_id', op: 'eq', v: me }], sort: [{ f: 'expected_close_date', dir: 'asc' }] },
    }, z.object({ rows: z.array(DealRow) }))
    dealId = list.ok ? (list.data.rows[0]?.id ?? null) : null
  }
  if (!dealId) return null
  const [detail, fields, notes] = await Promise.all([
    rpc('deal_detail', { p_id: dealId }, DealDetail),
    rpc('fields_get', { p_entity: 'deal' }, z.array(Field)),
    rpc('notes_list', { p_entity: 'deal', p_id: dealId }, z.array(Note)),
  ])
  if (!detail.ok) return null
  const d = detail.data
  const stages = d.stages ?? []
  const at = stages.findIndex((s) => s.id === d.stage_id)
  const next = at >= 0 ? stages[at + 1] : undefined
  const nextIdx = next ? at + 1 : -1
  const requires = next && fields.ok
    ? fields.data.filter((f) => f.quality === 'required' && f.from_stage_id && stages.findIndex((s) => s.id === f.from_stage_id) >= 0
        && stages.findIndex((s) => s.id === f.from_stage_id) <= nextIdx && (d.custom[f.key] === undefined || d.custom[f.key] === null || d.custom[f.key] === ''))
        .map((f) => f.label)
    : []
  const note = notes.ok ? (notes.data[0] ?? null) : null
  return {
    id: d.id, title: d.title, value: d.value, currency: d.currency, version: d.version, stage_id: d.stage_id, expected_close_date: d.expected_close_date,
    score: d.score, organization: d.organization, organization_id: d.organization_id,
    person: d.person_detail ? { id: d.person_detail.id, name: d.person_detail.name, title: d.person_detail.title, phone: d.person_detail.phone } : null,
    stages, next_requires: requires, note: note ? { body: note.body, author: note.author } : null,
  }
}

export const loadNotifications = () => rpc('notifications_get', { p_kind: null, p_limit: 4 }, Notifications)
/**
 * The staff member's push devices and state, with the Web Push public key a browser subscribes with
 * (push_vapid_public_key, R-MOBILE-03: the public half only, null while push is not configured).
 */
export async function loadPush(): Promise<RpcResult<PushState>> {
  const [push, key] = await Promise.all([rpc('push_devices_get', {}, Push), rpc('push_vapid_public_key', {}, z.string().min(1).nullable())])
  if (!push.ok) return push
  return { ok: true, data: { ...push.data, public_key: key.ok ? key.data : null } }
}
export const loadPrefs = () => rpc('notification_prefs_get', {}, Prefs)

/** Everything the six phones and the panels show, for the signed-in staff member (and the device's position, if sent). */
export async function loadPreview(me: string, c: Coords | null): Promise<RpcResult<Preview>> {
  const focus = await loadFocus(c)
  if (!focus.ok) return focus
  const [deal, notifications, push, prefs, types] = await Promise.all([
    loadDealPreview(me, focus.data.today), loadNotifications(), loadPush(), loadPrefs(), rpc('activity_types_get', {}, Types),
  ])
  const typeId = (k: string) => (types.ok ? (types.data.find((t) => t.key === k && t.active)?.id ?? null) : null)
  return {
    ok: true,
    data: {
      focus: focus.data,
      deal,
      notifications: notifications.ok ? notifications.data : null,
      push: push.ok ? push.data : null,
      prefs: prefs.ok ? prefs.data : null,
      types: { call: typeId('call'), visit: typeId('visit') },
    },
  }
}

// ---------------------------------------------------------------------------
// offline sync
export const SyncApplySchema = z.object({
  results: z.array(z.object({
    mutation_id: id,
    result: z.enum(['applied', 'superseded', 'rejected']),
    id: z.union([id, z.null()]).optional().transform((v) => v ?? null),
    version: nnum.optional().transform((v) => v ?? null),
    conflict: z.boolean().optional().transform((v) => v ?? false),
    error: nstr.optional().transform((v) => v ?? null),
    detail: nstr.optional().transform((v) => v ?? null),
    replayed: z.boolean().optional().transform((v) => v ?? false),
  })),
  applied: num,
  superseded: num,
  rejected: num,
})

export const SyncChangesSchema = z.object({
  changes: z.array(z.object({ entity: str, id, version: nnum, deleted: z.boolean().nullable() })),
  cursor: num,
  more: z.boolean(),
})
