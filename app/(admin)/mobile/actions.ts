'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { getShell } from '@/lib/shell'
import { loadNearby, loadPreview, SyncApplySchema, SyncChangesSchema } from '@/lib/data/mobile'
import { CALL_OUTCOMES, PREF_KINDS, SYNC_OPS, type NearbyRow, type Preview, type SyncResult } from '@/lib/data/mobile-shared'

/**
 * The Mobile screen's server actions. Every input is parsed; every answer is `{ ok: true, … }` or `{ ok: false, code, detail }`,
 * shown as `common.errors.<code>` (or a mobile message for a known detail). The database checks the module, the rights and
 * visibility again. Coordinates are passed through to mobile_focus and nearby and go nowhere else: not logged, not stored,
 * not returned. The worker_* functions are the service role's and are never called from here.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.guid()
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const Coords = z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) })
const any = z.unknown()

export async function fetchPreview(input: unknown): Promise<Res<{ preview: Preview }>> {
  const p = z.object({ coords: Coords.nullable() }).safeParse(input ?? { coords: null })
  if (!p.success) return bad
  const shell = await getShell()
  const r = await loadPreview(shell.me.id, p.data.coords)
  return r.ok ? { ok: true, preview: r.data } : fail(r)
}

export async function fetchNearby(input: unknown): Promise<Res<{ rows: NearbyRow[] }>> {
  const p = Coords.safeParse(input)
  if (!p.success) return bad
  const r = await loadNearby(p.data)
  return r.ok ? { ok: true, rows: r.data } : fail(r)
}

/** Check in (MOB-03): a done «visit» on the organisation; no coordinates are sent. */
export async function checkIn(input: unknown): Promise<Res<{ activity_id: string }>> {
  const p = z.object({ entity: z.enum(['organization', 'person', 'deal', 'lead']), id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('checkin', { p_entity: p.data.entity, p_id: p.data.id, p_note: null }, z.object({ activity_id: uuid }))
  return r.ok ? { ok: true, activity_id: r.data.activity_id } : fail(r)
}

/** Move the deal to a stage from the phone (source mobile). A stage that needs fields answers with their labels. */
export async function moveStage(input: unknown): Promise<Res<{ missing: string[] | null }>> {
  const p = z.object({ id: uuid, stage: uuid, version: z.number().int() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_move', { p_id: p.data.id, p_stage: p.data.stage, p_version: p.data.version, p_fields: null, p_source: 'mobile' },
    z.object({ id: uuid, missing: z.array(z.object({ label: z.string() })).optional() }))
  return r.ok ? { ok: true, missing: r.data.missing ? r.data.missing.map((m) => m.label) : null } : fail(r)
}

/** The call's outcome and length, asked when the person comes back from the phone app (MOB-04 through the prompt; D-38). */
export async function logCall(input: unknown): Promise<Res<{ activity_id: string }>> {
  const p = z.object({
    person_id: uuid, deal_id: uuid.nullable(), outcome: z.enum(CALL_OUTCOMES), minutes: z.number().int().min(0).max(600),
    subject: z.string().min(1).max(200), number: z.string().max(40).nullable(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('call_log_save', {
    p_values: { person_id: p.data.person_id, deal_id: p.data.deal_id, outcome: p.data.outcome, direction: 'outbound', duration_s: p.data.minutes * 60, subject: p.data.subject, number: p.data.number },
  }, z.object({ activity_id: uuid }))
  return r.ok ? { ok: true, activity_id: r.data.activity_id } : fail(r)
}

/** The reviewed card (AIA-07): typed or corrected by the staff member, saved under the contact rule. */
export async function saveCard(input: unknown): Promise<Res<{ person_id: string }>> {
  const t = (n: number) => z.string().trim().max(n).optional().transform((v) => (v ? v : undefined))
  const p = z.object({
    name: z.string().trim().min(1).max(200), title: t(200), email: z.string().trim().max(254).email().optional().or(z.literal('').transform(() => undefined)),
    phone: t(40), organization_name: t(200), basis: t(500),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: String(p.error.issues[0]?.path[0] ?? '') }
  const r = await rpc('card_draft_save', { p_values: p.data }, z.object({ person_id: uuid, organization_id: uuid.nullable() }))
  return r.ok ? { ok: true, person_id: r.data.person_id } : fail(r)
}

// ---------------------------------------------------------------------------
// offline sync (SF-31): the device's outbox, in order, at most 200 per call. A mutation id is made once on the device,
// so sending the same batch again returns the stored results (sync_receipts) and changes nothing.
const MutationSchema = z.object({
  mutation_id: uuid,
  op: z.enum(SYNC_OPS),
  entity: z.enum(['deal', 'activity']).optional(),
  record_id: uuid.optional(),
  base_version: z.number().int().optional(),
  fields: z.record(z.string(), any),
  client_at: z.string().datetime({ offset: true }),
})

export async function syncApply(input: unknown): Promise<Res<{ results: SyncResult[]; applied: number; superseded: number; rejected: number }>> {
  const p = z.object({ device: uuid, mutations: z.array(MutationSchema).min(1).max(200) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sync_apply', { p_device: p.data.device, p_mutations: p.data.mutations }, SyncApplySchema)
  return r.ok ? { ok: true, ...r.data } : fail(r)
}

export async function syncChanges(input: unknown): Promise<Res<{ count: number; cursor: number; more: boolean }>> {
  const p = z.object({ since: z.number().int().min(0) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sync_changes', { p_since: p.data.since, p_limit: 200 }, SyncChangesSchema)
  return r.ok ? { ok: true, count: r.data.changes.length, cursor: r.data.cursor, more: r.data.more } : fail(r)
}

// ---------------------------------------------------------------------------
// push devices and notification types (self)
export async function setPushPref(input: unknown): Promise<Res> {
  const p = z.object({ kind: z.enum(PREF_KINDS), push: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('notification_prefs_set', { p_kind: p.data.kind, p_channels: p.data.push ? ['in_app', 'push'] : ['in_app'] },
    z.object({ kind: z.string(), channels: z.array(z.string()) }))
  return r.ok ? { ok: true } : fail(r)
}

/**
 * This browser's push subscription (R-MOBILE-03): the endpoint and keys the browser made with the provider's public key.
 * Write-only: push_device_register never returns the endpoint. The database checks the module and the shapes again.
 */
export async function registerDevice(input: unknown): Promise<Res> {
  const p = z.object({
    endpoint: z.string().max(1000).url().startsWith('https://'),
    p256dh: z.string().regex(/^[A-Za-z0-9_=-]{40,200}$/),
    auth: z.string().regex(/^[A-Za-z0-9_=-]{16,60}$/),
    label: z.string().trim().max(120).nullable(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: String(p.error.issues[0]?.path[0] ?? '') }
  const r = await rpc('push_device_register', { p_endpoint: p.data.endpoint, p_p256dh: p.data.p256dh, p_auth: p.data.auth, p_label: p.data.label || null }, z.object({ id: uuid }))
  return r.ok ? { ok: true } : fail(r)
}

export async function revokeDevice(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('push_device_revoke', { p_id: p.data }, z.object({ id: uuid }))
  return r.ok ? { ok: true } : fail(r)
}

/**
 * A file uploaded to the record (lib/storage/actions: begin → signed upload → done) marked as what was captured (MOB-06):
 * an audio note, a photo or a scanned note. capture_save checks that the file is the caller's own on that record and that its
 * type fits the kind; an audio note is queued for transcription only while that provider is connected.
 */
export async function saveCapture(input: unknown): Promise<Res<{ transcription: string | null }>> {
  const p = z.object({ entity: z.enum(['deal', 'person', 'organization', 'lead']), id: uuid, file: uuid, kind: z.enum(['photo', 'audio', 'scan']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('capture_save', { p_entity: p.data.entity, p_id: p.data.id, p_file_id: p.data.file, p_kind: p.data.kind },
    z.object({ id: uuid, kind: z.string(), transcription: z.string().nullable().optional() }))
  return r.ok ? { ok: true, transcription: r.data.transcription ?? null } : fail(r)
}
