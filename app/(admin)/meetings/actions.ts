'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { getShell } from '@/lib/shell'
import {
  loadControls, loadMailboxOptions, loadMeeting, loadMySettings, loadTranscript, loadWorkspace, searchLinkable,
  type Controls, type MailboxOption, type MeetingBundle, type MySettings, type Transcript, type Workspace,
} from '@/lib/data/meetings'

/**
 * The Meetings screen's server actions. Every input is parsed; every answer is `{ ok: true, … }` or
 * `{ ok: false, code, detail }`, shown as `common.errors.<code>` (or a meetings message for a known detail).
 * The database checks the workspace, the meeting's visibility and the rights again. Worker functions are never
 * called from here: they are the service role's.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.guid()
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const any = z.unknown()
const done = (r: { ok: true } | { ok: false; code: RpcCode; detail: string | null }): Res => (r.ok ? { ok: true } : fail(r))

// ---------------------------------------------------------------------------
// reads
export async function fetchWorkspace(input: unknown): Promise<Res<{ workspace: Workspace }>> {
  const p = z.object({ history_before: z.string().datetime({ offset: true }).optional() }).safeParse(input ?? {})
  if (!p.success) return bad
  const r = await loadWorkspace(p.data)
  return r.ok ? { ok: true, workspace: r.data } : fail(r)
}

export async function fetchMeeting(input: unknown): Promise<Res<{ meeting: MeetingBundle }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await loadMeeting(p.data)
  return r.ok ? { ok: true, meeting: r.data } : fail(r)
}

export async function fetchTranscriptPage(input: unknown): Promise<Res<{ page: Transcript }>> {
  const p = z.object({ id: uuid, cursor: z.number().int().min(0) }).safeParse(input)
  if (!p.success) return bad
  const r = await loadTranscript(p.data.id, p.data.cursor)
  return r.ok ? { ok: true, page: r.data } : fail(r)
}

export async function fetchControls(): Promise<Res<{ controls: Controls }>> {
  const r = await loadControls()
  return r.ok ? { ok: true, controls: r.data } : fail(r)
}

export async function fetchMySettings(): Promise<Res<{ settings: MySettings; mailboxes: MailboxOption[] }>> {
  const shell = await getShell()
  const [s, m] = await Promise.all([loadMySettings(), loadMailboxOptions(shell.me.id)])
  if (!s.ok) return fail(s)
  return { ok: true, settings: s.data, mailboxes: m.ok ? m.data : [] }
}

export type Hit = { id: string; label: string }
export async function searchHits(input: unknown): Promise<Res<{ rows: Hit[] }>> {
  const p = z.object({ entity: z.enum(['deal', 'lead', 'person', 'organization']), q: z.string().max(100) }).safeParse(input)
  if (!p.success) return bad
  const r = await searchLinkable(p.data.entity, p.data.q)
  if (!r.ok) return fail(r)
  return {
    ok: true,
    rows: r.data.rows.map((x) => ({ id: x.id, label: p.data.entity === 'lead' && x.seq ? `L-${x.seq} · ${x.title ?? ''}` : (x.title ?? x.name ?? '—') })),
  }
}

// ---------------------------------------------------------------------------
// writes on one meeting
export async function linkMeeting(input: unknown): Promise<Res> {
  const v = uuid.nullable()
  const p = z.object({
    id: uuid,
    values: z.object({ deal_id: v, lead_id: v, person_id: v, organization_id: v }).partial().refine((x) => Object.keys(x).length > 0),
    version: z.number().int().optional(),
  }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_link', { p_id: p.data.id, p_values: p.data.values, p_version: p.data.version ?? null }, any))
}

export async function setCapture(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, capture: z.enum(['bot', 'none']) }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_capture_set', { p_id: p.data.id, p_capture: p.data.capture }, any))
}

export async function removeBot(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_bot_remove', { p_id: p.data }, any))
}

export async function deleteRecording(input: unknown): Promise<Res<{ recordings: number; transcripts: number }>> {
  const p = z.object({ id: uuid, withTranscript: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('meeting_recording_delete', { p_id: p.data.id, p_with_transcript: p.data.withTranscript }, z.object({ recordings: z.coerce.number(), transcripts: z.coerce.number() }))
  return r.ok ? { ok: true, ...r.data } : fail(r)
}

export async function checkBriefItem(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, key: z.string().regex(/^[a-z]{3}:[A-Za-z0-9:_.-]{1,76}$/), checked: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_brief_check', { p_id: p.data.id, p_item_key: p.data.key, p_checked: p.data.checked }, any))
}

export async function regenerateBrief(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_brief_regenerate', { p_id: p.data }, any))
}

export async function retryTranscript(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_transcript_retry', { p_transcript: p.data }, any))
}

export async function mapSpeaker(input: unknown): Promise<Res> {
  const p = z.object({
    transcript: uuid,
    label: z.string().min(1).max(120),
    values: z.union([z.object({ staff_id: uuid }), z.object({ person_id: uuid }), z.object({ email: z.string().email().max(254) }), z.object({}).strict()]),
  }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_speaker_map', { p_transcript: p.data.transcript, p_label: p.data.label, p_values: p.data.values }, any))
}

export async function regenerateRecap(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_recap_regenerate', { p_transcript: p.data }, any))
}

export async function saveRecapNote(input: unknown): Promise<Res<{ entity: string; already: boolean }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('meeting_recap_save_note', { p_id: p.data, p_entity: null, p_record: null }, z.object({ note_id: uuid, entity: z.string(), record_id: uuid, already: z.boolean() }))
  return r.ok ? { ok: true, entity: r.data.entity, already: r.data.already } : fail(r)
}

export async function planNextStep(input: unknown): Promise<Res<{ activityId: string }>> {
  const p = z.object({
    id: uuid,
    step: z.number().int().min(0).max(19),
    type: z.enum(['task', 'call', 'email', 'meeting']),
    startsAt: z.string().datetime({ offset: true }),
    durationMin: z.number().int().min(0).max(1440),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('meeting_next_step_activity', {
    p_id: p.data.id, p_step: p.data.step, p_values: { type: p.data.type, starts_at: p.data.startsAt, duration_min: p.data.durationMin },
  }, z.object({ activity_id: uuid, step: z.coerce.number() }))
  return r.ok ? { ok: true, activityId: r.data.activity_id } : fail(r)
}

export type Decision = { id: string; state: string | null; error?: string | null; detail?: string | null }
export async function decideSuggestions(input: unknown): Promise<Res<{ results: Decision[]; written: number }>> {
  const p = z.object({ ids: z.array(uuid).min(1).max(100), decision: z.enum(['accept', 'reject']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('meeting_suggestion_decide', { p_ids: p.data.ids, p_decision: p.data.decision }, z.object({
    results: z.array(z.object({ id: uuid, state: z.string().nullable(), error: z.string().nullish(), detail: z.string().nullish() })),
    written: z.coerce.number(),
  }))
  return r.ok ? { ok: true, ...r.data } : fail(r)
}

export async function recordObjection(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, email: z.string().email().max(254), always: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_opt_out_staff', { p_id: p.data.id, p_email: p.data.email, p_always: p.data.always }, any))
}

// ---------------------------------------------------------------------------
// settings: the per-user switch (global:configure), my own choices, the recording notice and retention
export async function setUser(input: unknown): Promise<Res> {
  const p = z.object({
    staff: uuid,
    values: z.object({ enabled: z.boolean(), bot_auto_join: z.enum(['external', 'all', 'off']), mailbox_id: uuid.nullable() }).partial().refine((x) => Object.keys(x).length > 0),
  }).safeParse(input)
  if (!p.success) return bad
  return done(await rpc('meeting_user_set', { p_staff: p.data.staff, p_values: p.data.values }, any))
}

export async function setMySettings(input: unknown): Promise<Res> {
  const p = z.object({
    bot_auto_join: z.enum(['external', 'all', 'off']),
    brief_instructions: z.string().max(2000).nullable(),
    mailbox_id: uuid.nullable(),
  }).partial().refine((x) => Object.keys(x).length > 0).safeParse(input)
  if (!p.success) return bad
  const values = { ...p.data, ...(p.data.brief_instructions !== undefined ? { brief_instructions: p.data.brief_instructions?.trim() || null } : {}) }
  return done(await rpc('meeting_my_settings_set', { p_values: values }, any))
}

export async function setRecordingSetting(input: unknown): Promise<Res> {
  const p = z.discriminatedUnion('key', [
    z.object({ key: z.literal('rec_notice'), value: z.enum(['on_24h', 'custom', 'off']), number: z.number().int().min(0).max(168).nullable() }),
    z.object({ key: z.literal('rec_retention'), value: z.enum(['12_months', 'custom', 'keep']), number: z.number().int().min(1).max(120).nullable() }),
  ]).safeParse(input)
  if (!p.success) return bad
  const n = p.data.value === 'custom' ? p.data.number : null
  if (p.data.value === 'custom' && n === null) return bad
  return done(await rpc('setting_set', { p_key: p.data.key, p_value: p.data.value, p_scope_id: '', p_number: n }, any))
}
