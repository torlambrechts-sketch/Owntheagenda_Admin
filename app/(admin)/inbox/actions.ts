'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { getShell } from '@/lib/shell'
import { PhoneMatch } from '@/lib/data/inbox'
import { SEND_AT, sendAtInstant } from '@/lib/data/inbox-shared'

/**
 * Server actions of the Inbox: each parses its input and answers `{ ok } | { ok: false, code }`. Codes the
 * shared catalogue has (common.errors) pass through, mailbox_not_connected among them; the screen words
 * some in its own way (inbox.errors): merge fields without a value or not in the registry, a missing
 * recipient or subject, the recipient limit.
 */
export type InboxCode = RpcCode | 'merge_missing' | 'merge_unknown' | 'no_recipient' | 'no_subject' | 'over_limit' | 'no_recipients' | 'no_inbound'
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: InboxCode; detail?: string | null }

const uuid = z.string().uuid()
const bad = { ok: false as const, code: 'invalid' as const }
const done = () => revalidatePath('/inbox')

// the mail functions name the field of an «invalid» in its detail; those with their own wording are told apart here
function refusal(r: { code: RpcCode; detail: string | null }): { ok: false; code: InboxCode; detail?: string | null } {
  if (r.code === 'invalid' && r.detail) {
    if (r.detail.startsWith('merge_missing:')) return { ok: false, code: 'merge_missing', detail: r.detail.slice(14) }
    if (r.detail.startsWith('merge:')) return { ok: false, code: 'merge_unknown', detail: r.detail.slice(6) }
    if (r.detail === 'to' || r.detail === 'recipients') return { ok: false, code: 'no_recipient' }
    if (r.detail === 'subject') return { ok: false, code: 'no_subject' }
    if (r.detail === 'limit') return { ok: false, code: 'over_limit' }
    if (r.detail === 'no_inbound') return { ok: false, code: 'no_inbound' }
  }
  return { ok: false, code: r.code, detail: r.detail }
}

const Addr = z.object({ address: z.string().trim().toLowerCase().email().max(254), name: z.string().max(200).nullable() })
const Entity = z.enum(['deal', 'lead', 'person', 'organization'])

export async function sendEmail(input: unknown): Promise<Result<{ threadId: string; state: string }>> {
  const p = z.object({
    threadId: uuid.nullable(),
    mailboxId: uuid,
    to: z.array(Addr).max(50),
    cc: z.array(Addr).max(50),
    subject: z.string().max(500),
    body: z.string().trim().min(1).max(50000),
    templateId: uuid.nullable(),
    track: z.boolean().nullable(),
    sendAt: z.enum(SEND_AT),
    entity: Entity.nullable(),
    recordId: uuid.nullable(),
  }).safeParse(input)
  if (!p.success) return bad
  const d = p.data
  if (!d.to.length) return { ok: false, code: 'no_recipient' }
  if (!d.subject.trim()) return { ok: false, code: 'no_subject' }
  const shell = await getShell()
  const at = sendAtInstant(d.sendAt, new Date(), shell.me.time_zone)
  const r = await rpc('email_send', {
    p_draft: {
      thread_id: d.threadId, mailbox_id: d.mailboxId, to: d.to, cc: d.cc, subject: d.subject, body: d.body, template_id: d.templateId,
      track: d.track, send_at: at ? at.toISOString() : null, entity: d.recordId ? d.entity : null, record_id: d.recordId,
    },
  }, z.object({ message_id: uuid, thread_id: uuid, state: z.string() }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true, threadId: r.data.thread_id, state: r.data.state }
}

/** The merge fields a draft uses that have no value for its record, or are not in the registry (COM-05). */
export async function mergeCheck(input: unknown): Promise<Result<{ missing: string[]; unknown: string[] }>> {
  const p = z.object({
    subject: z.string().max(500), body: z.string().max(50000), entity: Entity.nullable(), recordId: uuid.nullable(), personId: uuid.nullable(), mailboxId: uuid.nullable(),
  }).safeParse(input)
  if (!p.success) return bad
  const d = p.data
  const r = await rpc('merge_preview', {
    p_subject: d.subject, p_body: d.body, p_entity: d.recordId ? d.entity : null, p_record: d.recordId, p_person: d.personId, p_mailbox: d.mailboxId,
  }, z.object({ missing: z.array(z.string()), unknown: z.array(z.string()) }))
  if (!r.ok) return refusal(r)
  return { ok: true, missing: r.data.missing, unknown: r.data.unknown }
}

export async function archiveThread(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, archived: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('thread_archive', { p_id: p.data.id, p_archived: p.data.archived }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}

export async function threadToLead(input: unknown): Promise<Result<{ leadId: string }>> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('thread_to_lead', { p_id: p.data.id }, z.object({ lead_id: uuid, person_id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true, leadId: r.data.lead_id }
}

/** Label toggles: the thread is a record (entity email_thread) and takes labels through rec_save. */
export async function setThreadLabels(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, version: z.number().int().positive(), labels: z.array(uuid).max(50) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_save', { p_entity: 'email_thread', p_id: p.data.id, p_values: { labels: p.data.labels }, p_version: p.data.version }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}

export async function changeEmail(input: unknown): Promise<Result<{ state: string }>> {
  const p = z.object({ id: uuid, action: z.enum(['cancel', 'reschedule', 'send_now', 'retry']), at: z.string().datetime({ offset: true }).nullable() }).safeParse(input)
  if (!p.success) return bad
  if (p.data.action === 'reschedule' && (!p.data.at || new Date(p.data.at) <= new Date())) return bad
  const r = await rpc('email_change', { p_id: p.data.id, p_action: p.data.action, p_at: p.data.at }, z.object({ id: uuid, state: z.string() }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true, state: r.data.state }
}

const Source = z.union([
  z.object({ kind: z.literal('people'), ids: z.array(uuid).max(5000) }),
  z.object({ kind: z.literal('deals'), ids: z.array(uuid).max(5000) }),
  z.object({ kind: z.literal('view'), view_id: uuid }),
])

export async function groupSend(input: unknown): Promise<Result<{ total: number; excluded: number }>> {
  const p = z.object({ source: Source, mailboxId: uuid, templateId: uuid, track: z.boolean().nullable() }).safeParse(input)
  if (!p.success) return bad
  const tpl = await rpc('templates_get', {}, z.array(z.object({ id: uuid, subject: z.string(), body: z.string() })))
  if (!tpl.ok) return refusal(tpl)
  const t = tpl.data.find((x) => x.id === p.data.templateId)
  if (!t) return { ok: false, code: 'not_found' }
  const r = await rpc('group_send_start', {
    p_source: p.data.source, p_mailbox: p.data.mailboxId, p_subject: t.subject, p_body: t.body, p_template: t.id, p_track: p.data.track,
  }, z.object({ id: uuid, total: z.number(), excluded: z.number() }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true, total: r.data.total, excluded: r.data.excluded }
}

export async function phoneMatch(input: unknown): Promise<Result<{ matches: PhoneMatch }>> {
  const p = z.object({ number: z.string().trim().max(40) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('phone_match', { p_number: p.data.number }, PhoneMatch)
  if (!r.ok) return refusal(r)
  return { ok: true, matches: r.data }
}

export async function logCall(input: unknown): Promise<Result> {
  const p = z.object({
    personId: uuid.nullable(), dealId: uuid.nullable(), number: z.string().trim().max(40),
    direction: z.enum(['outbound', 'inbound']), outcome: z.enum(['connected', 'no_answer', 'missed', 'busy', 'voicemail']),
    minutes: z.number().int().min(0).max(1440).nullable(), note: z.string().trim().max(4000),
  }).safeParse(input)
  if (!p.success) return bad
  const d = p.data
  const r = await rpc('call_log_save', {
    p_values: {
      person_id: d.personId, deal_id: d.dealId, number: d.number || null, direction: d.direction, outcome: d.outcome,
      duration_s: d.minutes === null ? null : d.minutes * 60, note: d.note || null,
    },
  }, z.object({ activity_id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}

export async function saveTemplate(input: unknown): Promise<Result<{ id: string }>> {
  const p = z.object({
    id: uuid.nullable(),
    values: z.object({ name: z.string().trim().min(1).max(120), scope: z.enum(['private', 'shared']), subject: z.string().max(500), body: z.string().max(50000) }),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('template_save', { p_id: p.data.id, p_values: p.data.values }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true, id: r.data.id }
}

export async function deleteTemplate(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('template_delete', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}

export async function updateMailbox(input: unknown): Promise<Result> {
  const p = z.object({
    id: uuid,
    values: z.object({ display_name: z.string().trim().max(120), signature: z.string().max(4000), default_visibility: z.enum(['private', 'shared']) }),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('mailbox_update', { p_id: p.data.id, p_values: p.data.values }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}

export async function setMailboxMembers(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, members: z.array(z.object({ staff_id: uuid, can_reply: z.boolean() })).max(500) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('mailbox_members_set', { p_id: p.data.id, p_members: p.data.members }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}

export async function disconnectMailbox(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('mailbox_disconnect', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}

export async function addAlias(input: unknown): Promise<Result> {
  const p = z.object({ address: z.string().trim().toLowerCase().email().max(254), kind: z.enum(['send_as', 'bcc_accepted']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sender_alias_add', { p_address: p.data.address, p_kind: p.data.kind }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}

export async function removeAlias(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sender_alias_remove', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return refusal(r)
  done()
  return { ok: true }
}
