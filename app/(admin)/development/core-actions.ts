'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { aiRun } from '@/lib/ai/run'
import { handOverSecrets } from '@/lib/secrets/hand-over'
import { loadDrafts } from '@/lib/data/dev-core'
import { placeholders } from '../tickets/_components/merge'
import {
  AI_FEATURES, KINDS, LANES, NOTE_KINDS, SEVERITIES, SPEC_ROLES, SPEC_SECTIONS, SPEC_STATUSES, STATUSES,
  parseReleaseNotes, parseSpecDraft, parseTaskPlan,
} from './_components/core/logic'

/**
 * Development › the core half's writes (0079). Each action parses its input and answers `{ ok: true, … }` or
 * `{ ok: false, code, detail }`; the database checks the right and every value again. Nothing a person types reaches
 * Claude: «Ask Claude» sends a feature key and a roadmap item's id, and the feature's context function reads the records.
 */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode | string; detail?: string | null }

const uuid = z.string().uuid()
const product = z.string().regex(/^[a-z]{2,20}$/)
const version = z.number().int().min(1)
const title = z.string().trim().min(3).max(200)
const bad = { ok: false as const, code: 'invalid' as const }
const any = z.record(z.string(), z.unknown())
const done = () => revalidatePath('/development')

async function call<T extends z.ZodTypeAny>(fn: string, args: Record<string, unknown>, schema: T = any as unknown as T): Promise<Result<{ data: z.infer<T> }>> {
  const r = await rpc(fn, args, schema)
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true, data: r.data }
}
const plain = async (fn: string, args: Record<string, unknown>): Promise<Result> => {
  const r = await call(fn, args)
  return r.ok ? { ok: true } : r
}

// ---------------------------------------------------------------------------
// the roadmap
export async function addRoadmapItem(input: unknown): Promise<Result<{ id: string }>> {
  const p = z.object({ product, title, goal: z.string().trim().max(200), lane: z.enum(LANES) }).safeParse(input)
  if (!p.success) return bad
  const r = await call('dev_roadmap_add', { p_product: p.data.product, p_title: p.data.title, p_goal: p.data.goal || null, p_lane: p.data.lane }, z.object({ id: uuid }).passthrough())
  return r.ok ? { ok: true, id: r.data.id } : r
}

export async function setRoadmapItem(input: unknown): Promise<Result> {
  const p = z.object({
    id: uuid, version,
    patch: z.object({ title: title.optional(), goal: z.string().trim().max(200).optional(), status: z.enum(STATUSES).optional(), owner_id: uuid.nullable().optional() }).strict(),
  }).safeParse(input)
  if (!p.success || !Object.keys(p.data.patch).length) return bad
  return plain('dev_roadmap_set', { p_id: p.data.id, p_version: p.data.version, p_patch: p.data.patch })
}

export async function moveRoadmapItem(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, lane: z.enum(LANES), version }).safeParse(input)
  if (!p.success) return bad
  return plain('dev_roadmap_move', { p_id: p.data.id, p_lane: p.data.lane, p_version: p.data.version })
}

export async function archiveRoadmapItem(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, version }).safeParse(input)
  if (!p.success) return bad
  return plain('dev_roadmap_archive', { p_id: p.data.id, p_version: p.data.version })
}

export async function linkEvidence(input: unknown): Promise<Result> {
  const p = z.object({
    id: uuid, kind: z.enum(['feature_request', 'ticket', 'deal', 'experiment', 'seo_plan']), ref: uuid.nullable(),
    number: z.number().int().positive().max(9_999_999_999).nullable(), on: z.boolean(),
  }).safeParse(input)
  if (!p.success || (p.data.ref === null && (p.data.kind !== 'ticket' || p.data.number === null))) return bad
  return plain('dev_roadmap_link', { p_id: p.data.id, p_kind: p.data.kind, p_ref: p.data.ref, p_number: p.data.number, p_on: p.data.on })
}

export async function promote(input: unknown): Promise<Result<{ title: string }>> {
  const p = z.object({ kind: z.enum(['feature_request', 'experiment', 'seo_plan']), ref: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await call('dev_roadmap_promote', { p_kind: p.data.kind, p_ref: p.data.ref }, z.object({ title: z.string() }).passthrough())
  return r.ok ? { ok: true, title: r.data.title } : r
}

// ---------------------------------------------------------------------------
// the work board
export async function saveWorkItem(input: unknown): Promise<Result<{ key: string }>> {
  const p = z.object({
    id: uuid.nullable(), version: version.nullable(),
    values: z.object({
      product: product.optional(), kind: z.enum(KINDS).optional(), title: title.optional(), points: z.number().int().min(0).max(100).nullable().optional(),
      status: z.enum(STATUSES).optional(), roadmap_item_id: uuid.nullable().optional(), sprint_id: uuid.nullable().optional(),
      assignee_id: uuid.nullable().optional(), bug_id: uuid.nullable().optional(),
    }).strict(),
  }).safeParse(input)
  if (!p.success || (p.data.id === null) !== (p.data.version === null)) return bad
  const r = await call('dev_work_item_save', { p_id: p.data.id, p_version: p.data.version, p_values: p.data.values }, z.object({ key: z.string() }).passthrough())
  return r.ok ? { ok: true, key: r.data.key } : r
}

export async function moveWorkItem(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, status: z.enum(STATUSES), version }).safeParse(input)
  if (!p.success) return bad
  return plain('dev_work_item_move', { p_id: p.data.id, p_status: p.data.status, p_version: p.data.version })
}

export async function archiveWorkItem(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, version }).safeParse(input)
  if (!p.success) return bad
  return plain('dev_work_item_archive', { p_id: p.data.id, p_version: p.data.version })
}

export async function saveSprint(input: unknown): Promise<Result> {
  const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
  const p = z.object({ id: uuid.nullable(), name: z.string().trim().min(1).max(60), starts: day, ends: day }).safeParse(input)
  if (!p.success || p.data.ends < p.data.starts) return bad
  return plain('dev_sprint_save', { p_id: p.data.id, p_name: p.data.name, p_starts: p.data.starts, p_ends: p.data.ends })
}

// ---------------------------------------------------------------------------
// bug triage
const ticketNumbers = z.array(z.number().int().positive().max(9_999_999_999)).max(50)

export async function createBug(input: unknown): Promise<Result> {
  const p = z.object({
    product, title, severity: z.enum(SEVERITIES), source: z.enum(['ticket', 'internal']), problem: uuid.nullable(), tickets: ticketNumbers,
  }).safeParse(input)
  if (!p.success) return bad
  return plain('dev_bug_create', { p_product: p.data.product, p_title: p.data.title, p_severity: p.data.severity, p_source: p.data.source,
                                   p_problem: p.data.problem, p_tickets: p.data.tickets })
}

export async function setBug(input: unknown): Promise<Result> {
  const p = z.object({
    id: uuid, version,
    patch: z.object({ title: title.optional(), severity: z.enum(SEVERITIES).optional(), assignee_id: uuid.nullable().optional(), problem_id: uuid.nullable().optional() }).strict(),
  }).safeParse(input)
  if (!p.success || !Object.keys(p.data.patch).length) return bad
  return plain('dev_bug_set', { p_id: p.data.id, p_version: p.data.version, p_patch: p.data.patch })
}

export async function linkBugTicket(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, number: z.number().int().positive().max(9_999_999_999), on: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  return plain('dev_bug_link', { p_id: p.data.id, p_number: p.data.number, p_on: p.data.on })
}

export async function mergeBug(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, into: uuid, version }).safeParse(input)
  if (!p.success || p.data.id === p.data.into) return bad
  return plain('dev_bug_merge', { p_id: p.data.id, p_into: p.data.into, p_version: p.data.version })
}

/** «Mark fixed»: the message goes to the open incidents of a linked problem (problem_resolve); placeholders are refused */
export async function fixBug(input: unknown): Promise<Result<{ notified: number; resolved: boolean; mailReady: boolean | null }>> {
  const p = z.object({ id: uuid, version, body: z.string().trim().max(20000) }).safeParse(input)
  if (!p.success) return bad
  if (placeholders(p.data.body).length) return { ok: false, code: 'invalid', detail: 'placeholder' }
  const r = await call('dev_bug_fix', { p_id: p.data.id, p_version: p.data.version, p_body: p.data.body || null },
                       z.object({ notified: z.coerce.number(), problem_resolved: z.boolean(), mail_ready: z.boolean().nullable().optional() }).passthrough())
  return r.ok ? { ok: true, notified: r.data.notified, resolved: r.data.problem_resolved, mailReady: r.data.mail_ready ?? null } : r
}

// ---------------------------------------------------------------------------
// specs
const sections = z.object(Object.fromEntries(SPEC_SECTIONS.map((s) => [s, z.string().max(8000).optional()])) as Record<(typeof SPEC_SECTIONS)[number], z.ZodOptional<z.ZodString>>)

export async function saveSpec(input: unknown): Promise<Result<{ id: string }>> {
  const p = z.object({
    id: uuid.nullable(), version: version.nullable(),
    values: sections.extend({ product: product.optional(), title: title.optional(), roadmap_item_id: uuid.nullable().optional() }).strict(),
  }).safeParse(input)
  if (!p.success || (p.data.id === null) !== (p.data.version === null)) return bad
  const r = await call('dev_spec_save', { p_id: p.data.id, p_version: p.data.version, p_values: p.data.values }, z.object({ id: uuid }).passthrough())
  return r.ok ? { ok: true, id: r.data.id } : r
}

export async function setSpecStatus(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, status: z.enum(SPEC_STATUSES), version }).safeParse(input)
  if (!p.success) return bad
  return plain('dev_spec_status', { p_id: p.data.id, p_status: p.data.status, p_version: p.data.version })
}

export async function signSpec(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid, role: z.enum(SPEC_ROLES), on: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  return plain('dev_spec_sign', { p_id: p.data.id, p_role: p.data.role, p_on: p.data.on })
}

// ---------------------------------------------------------------------------
// Claude
/** «Ask Claude»: ai-run with the person's own token; the draft comes back to the item for Use or Discard */
export async function askClaude(input: unknown): Promise<Result<{ truncated: boolean }>> {
  const p = z.object({ feature: z.enum(AI_FEATURES), item: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await aiRun(p.data.feature, p.data.item)
  done()
  if (!r.ok) return { ok: false, code: 'failed', detail: r.code ?? 'error' }
  return { ok: true, truncated: !!r.truncated }
}

/** «Use»: the draft (read again from the database, never sent by the browser) becomes records for a person to edit */
export async function applyDraft(input: unknown): Promise<Result<{ created: number; feature: string }>> {
  const p = z.object({ id: uuid, feature: z.enum(AI_FEATURES), item: uuid }).safeParse(input)
  if (!p.success) return bad
  const draft = (await loadDrafts(p.data.item)).find((d) => d.id === p.data.id && d.feature === p.data.feature)
  if (!draft) return { ok: false, code: 'not_found' }
  let payload: Record<string, unknown>
  if (p.data.feature === 'spec_draft') payload = parseSpecDraft(draft.body)
  else if (p.data.feature === 'task_plan') {
    const tasks = parseTaskPlan(draft.body)
    if (!tasks.length) return { ok: false, code: 'invalid', detail: 'empty_draft' }
    payload = { tasks }
  } else {
    const notes = parseReleaseNotes(draft.body).filter((n) => NOTE_KINDS.includes(n.kind))
    if (!notes.length) return { ok: false, code: 'invalid', detail: 'empty_draft' }
    payload = { notes }
  }
  const r = await call('dev_ai_apply', { p_output: p.data.id, p_payload: payload }, z.object({ created: z.coerce.number(), feature: z.string() }).passthrough())
  return r.ok ? { ok: true, created: r.data.created, feature: r.data.feature } : r
}

export async function discardDraft(input: unknown): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  return plain('ai_output_set', { p_id: p.data.id, p_state: 'discarded' })
}

/** the owner connects Claude: an intake number (fresh second factor), then the key straight to secret-intake */
export async function connectClaude(input: unknown): Promise<Result> {
  const p = z.object({ key: z.string().trim().regex(/^sk-ant-[A-Za-z0-9_-]+$/).min(30).max(300) }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'bad_key' }
  const intake = await rpc('v3_intake', { p_purpose: 'anthropic' }, z.object({ intake_code: z.string().regex(/^[0-9a-f]{48}$/), expires_in: z.number() }))
  if (!intake.ok) return { ok: false, code: intake.code, detail: intake.detail }
  const handed = await handOverSecrets(intake.data.intake_code, { anthropic_api_key: p.data.key })
  done()
  return handed.ok ? { ok: true } : { ok: false, code: 'failed', detail: handed.code }
}

export async function setClaudeSettings(input: unknown): Promise<Result> {
  const p = z.object({ model: z.string().regex(/^claude-[a-z0-9-]{3,40}$/), effort: z.enum(['low', 'medium', 'high']) }).safeParse(input)
  if (!p.success) return bad
  return plain('ai_settings_set', { p_model: p.data.model, p_effort: p.data.effort })
}

export async function disconnectClaude(): Promise<Result> {
  return plain('v3_disconnect', { p_purpose: 'anthropic' })
}
