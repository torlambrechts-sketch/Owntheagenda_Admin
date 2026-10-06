'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { ChatDetail, ChatQueue, DAYS, Draft, FORM_KINDS, FORM_LANGS, PALETTES, BUTTONS, Step, TEMPLATES } from '@/lib/data/capture-shared'

/** Server actions of Lead capture: each parses its input and answers `{ ok } | { ok: false, code, detail }`. */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode; detail?: string | null }

const uuid = z.string().uuid()
const bad = { ok: false as const, code: 'invalid' as const }
const fail = (r: { code: RpcCode; detail: string | null }) => ({ ok: false as const, code: r.code, detail: r.detail })
const done = () => revalidatePath('/lead-capture')
const Id = z.object({ id: uuid })
const Saved = z.object({ id: uuid, version: z.coerce.number() })

// ---------------------------------------------------------------------------
// forms (campaigns:add; publish and activate campaigns:configure)
export async function createForm(input: { kind: string; name: string; language: string }): Promise<Result<{ id: string }>> {
  const p = z.object({ kind: z.enum(FORM_KINDS), name: z.string().trim().min(1).max(120), language: z.enum(FORM_LANGS) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('form_create', { p_kind: p.data.kind, p_name: p.data.name, p_language: p.data.language }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

const SaveInput = z.object({ id: uuid, draft: Draft, version: z.number().int(), name: z.string().trim().min(1).max(120).optional() })
export async function saveForm(input: z.input<typeof SaveInput>): Promise<Result<{ version: number }>> {
  const p = SaveInput.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('form_save', { p_id: p.data.id, p_draft: p.data.draft, p_version: p.data.version, p_name: p.data.name ?? null }, Saved)
  if (!r.ok) return fail(r)
  done()
  return { ok: true, version: r.data.version }
}

/** Publish: the draft as shown is saved first, then frozen as the next version. */
export async function publishForm(input: z.input<typeof SaveInput>): Promise<Result<{ current: number }>> {
  const p = SaveInput.safeParse(input)
  if (!p.success) return bad
  const s = await rpc('form_save', { p_id: p.data.id, p_draft: p.data.draft, p_version: p.data.version, p_name: p.data.name ?? null }, Saved)
  if (!s.ok) return fail(s)
  const r = await rpc('form_publish', { p_id: p.data.id }, z.object({ current_version: z.coerce.number() }))
  done()
  if (!r.ok) return fail(r)
  return { ok: true, current: r.data.current_version }
}

export async function setFormStatus(input: { id: string; status: 'active' | 'inactive' }): Promise<Result> {
  const p = z.object({ id: uuid, status: z.enum(['active', 'inactive']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('form_set_status', { p_id: p.data.id, p_status: p.data.status }, z.object({ status: z.string() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function deleteForm(input: { id: string; reason?: string }): Promise<Result> {
  const p = z.object({ id: uuid, reason: z.string().trim().max(500).optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('form_delete', { p_id: p.data.id, p_reason: p.data.reason || null }, z.object({ deleted: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

/** A new version of a consent wording (campaigns:configure); earlier versions stay as the proof of what was shown. */
export async function saveConsentText(input: { key: string; locale: string; body: string }): Promise<Result<{ version: number }>> {
  const p = z.object({ key: z.string().regex(/^[a-z_]{2,40}$/), locale: z.enum(FORM_LANGS), body: z.string().trim().min(1).max(2000) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('consent_text_save', { p_key: p.data.key, p_locale: p.data.locale, p_body: p.data.body }, z.object({ id: uuid, version: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, version: r.data.version }
}

// ---------------------------------------------------------------------------
// chat playbooks
const PlaybookValues = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  template: z.enum(TEMPLATES).optional(),
  pages: z.array(z.string().regex(/^\/[A-Za-z0-9/_.~%-]{0,199}\*?$/)).max(50).optional(),
  theme: z.object({ palette: z.enum(PALETTES), button: z.enum(BUTTONS) }).optional(),
  profile: z.object({ name: z.string().trim().max(60), avatar: z.string().max(20).optional(), language: z.enum(FORM_LANGS) }).optional(),
  steps: z.array(Step).max(30).optional(),
  creates: z.enum(['lead', 'deal']).optional(),
  pipeline_id: uuid.nullable().optional(),
  stage_id: uuid.nullable().optional(),
  queue_wait_seconds: z.number().int().min(10).max(900).optional(),
  offline_message: z.string().max(500).optional(),
})
export async function savePlaybook(input: { id: string | null; values: z.input<typeof PlaybookValues>; version: number | null }): Promise<Result<{ id: string }>> {
  const p = z.object({ id: uuid.nullable(), values: PlaybookValues, version: z.number().int().nullable() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('playbook_save', { p_id: p.data.id, p_values: p.data.values, p_version: p.data.version }, Saved)
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

const Time = z.string().regex(/^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$/)
export async function setPlaybookHours(input: { id: string; hours: Partial<Record<(typeof DAYS)[number], [string, string]>> | null; version: number }): Promise<Result> {
  const p = z.object({
    id: uuid,
    hours: z.partialRecord(z.enum(DAYS), z.tuple([Time, Time]).refine(([a, b]) => a < b)).nullable(),
    version: z.number().int(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('playbook_hours_set', { p_id: p.data.id, p_hours: p.data.hours, p_version: p.data.version }, z.object({ id: z.string() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function publishPlaybook(input: { id: string }): Promise<Result> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('playbook_publish', { p_id: p.data.id }, z.object({ current_version: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function setPlaybookState(input: { id: string; state: 'draft' | 'live' }): Promise<Result> {
  const p = z.object({ id: uuid, state: z.enum(['draft', 'live']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('playbook_set_state', { p_id: p.data.id, p_state: p.data.state }, z.object({ state: z.string() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// live chat (deals:see; claim, send and close deals:add). Polled every few seconds while the tab is open (Q10).
export async function pollChats(input: { id: string | null }): Promise<Result<{ queue: ChatQueue; chat: ChatDetail | null }>> {
  const p = z.object({ id: uuid.nullable() }).safeParse(input)
  if (!p.success) return bad
  const q = await rpc('chats_queue', {}, ChatQueue)
  if (!q.ok) return fail(q)
  const id = p.data.id && q.data.rows.some((r) => r.id === p.data.id) ? p.data.id : (q.data.rows[0]?.id ?? null)
  if (!id) return { ok: true, queue: q.data, chat: null }
  const c = await rpc('chat_get', { p_id: id }, ChatDetail)
  return { ok: true, queue: q.data, chat: c.ok ? c.data : null }
}

export async function claimChat(input: { id: string }): Promise<Result> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('chat_claim', { p_id: p.data.id }, z.object({ state: z.string() }))
  return r.ok ? { ok: true } : fail(r)
}

export async function sendChat(input: { id: string; body: string }): Promise<Result> {
  const p = z.object({ id: uuid, body: z.string().trim().min(1).max(4000) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('chat_send', { p_id: p.data.id, p_body: p.data.body }, z.object({ id: z.coerce.number() }))
  return r.ok ? { ok: true } : fail(r)
}

export async function closeChat(input: { id: string }): Promise<Result<{ leadId: string | null }>> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('chat_close', { p_id: p.data.id }, z.object({ state: z.string(), lead_id: uuid.nullable().optional() }))
  return r.ok ? { ok: true, leadId: r.data.lead_id ?? null } : fail(r)
}

/** Presence lasts two minutes; the screen renews it while the staff member is online and the tab is open. */
export async function setPresence(input: { online: boolean }): Promise<Result> {
  const p = z.object({ online: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('chat_presence_set', { p_online: p.data.online }, z.object({ online: z.boolean() }))
  return r.ok ? { ok: true } : fail(r)
}

// ---------------------------------------------------------------------------
// tracked sites and the embed (campaigns:configure)
export async function saveSite(input: { id: string | null; values: { hostname?: string; active?: boolean; chat_enabled?: boolean } }): Promise<Result> {
  const p = z.object({
    id: uuid.nullable(),
    values: z.object({ hostname: z.string().trim().toLowerCase().min(3).max(253).regex(/^[a-z0-9.-]+$/).optional(), active: z.boolean().optional(), chat_enabled: z.boolean().optional() }),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('web_site_save', { p_id: p.data.id, p_values: p.data.values }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// prospect search: the filter is saved as a view (0009); the search itself needs the provider (not connected)
export async function saveProspectFilter(input: { name: string; query: Record<string, string> }): Promise<Result> {
  const p = z.object({ name: z.string().trim().min(1).max(80), query: z.record(z.string().regex(/^[a-z]{2,20}$/), z.string().max(200)) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('view_save', { p_id: null, p_screen: 'prospect_search', p_name: p.data.name, p_query: p.data.query, p_shared: false }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}
