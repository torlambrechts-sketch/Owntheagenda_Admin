'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { runCommand } from '@/lib/platform/command'
import {
  IMPACTS, LINK_KINDS, PRIORITIES, TICKET_STATUSES, TICKET_TYPES, URGENCIES, loadHelp, loadPickers, loadTicketDetail,
  type OrgOption, type PersonOption,
} from '@/lib/data/tickets'
import { placeholders } from './_components/merge'

/** Server actions of the Tickets screen: each parses its input and answers `{ ok } | { ok: false, code }`. */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode; detail?: string | null }

const uuid = z.string().uuid()
const done = () => revalidatePath('/tickets')
const bad = { ok: false as const, code: 'invalid' as const }

const Values = z.object({
  status: z.enum(TICKET_STATUSES),
  type: z.enum(TICKET_TYPES),
  queue_key: z.string().regex(/^[a-z_]{2,30}$/),
  assignee_id: uuid.nullable(),
  impact: z.enum(IMPACTS),
  urgency: z.enum(URGENCIES),
  category_key: z.string().regex(/^[a-z_]{2,40}$/),
  problem_id: uuid.nullable(),
  problem_status: z.enum(['investigating', 'known_error', 'resolved']).nullable(),
  root_cause: z.string().max(2000).nullable(),
  workaround: z.string().max(2000).nullable(),
  status_banner: z.boolean(),
  topic: z.string().max(80).nullable(),
}).partial().strict()

export async function saveTicket(input: { id: string; version: number; values: z.input<typeof Values> }): Promise<Result<{ version: number }>> {
  const p = z.object({ id: uuid, version: z.number().int().positive(), values: Values }).safeParse(input)
  if (!p.success) return bad
  const v = { ...p.data.values }
  // a problem carries a problem status and no parent problem; anything else carries neither
  if (v.type === 'problem') { v.problem_status ??= 'investigating'; v.problem_id = null }
  else if (v.type) v.problem_status = null
  const r = await rpc('rec_save', { p_entity: 'ticket', p_id: p.data.id, p_values: v, p_version: p.data.version }, z.object({ id: uuid, version: z.number() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true, version: r.data.version }
}

export async function sendMessage(input: {
  id: string; kind: 'reply' | 'note'; body: string; after: 'waiting_customer' | 'resolved' | null; macroId: string | null; mentions: string[]
}): Promise<Result> {
  const p = z.object({
    id: uuid,
    kind: z.enum(['reply', 'note']),
    body: z.string().trim().min(1).max(20000),
    after: z.enum(['waiting_customer', 'resolved']).nullable(),
    macroId: uuid.nullable(),
    mentions: z.array(uuid).max(20),
  }).safeParse(input)
  if (!p.success) return bad
  if (p.data.kind === 'reply' && placeholders(p.data.body).length) return { ok: false, code: 'invalid', detail: 'placeholder' }
  const r = await rpc('ticket_message', {
    p_id: p.data.id, p_kind: p.data.kind, p_body: p.data.body, p_after: p.data.kind === 'reply' ? p.data.after : null,
    p_macro: p.data.macroId, p_mentions: p.data.kind === 'note' ? p.data.mentions : [],
  }, z.object({ id: uuid }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}

export async function linkTicket(input: { id: string; kind: string; ref: string; label: string | null; on: boolean }): Promise<Result> {
  const p = z.object({
    id: uuid, kind: z.enum(LINK_KINDS), ref: z.string().trim().min(1).max(100), label: z.string().trim().max(200).nullable(), on: z.boolean(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('ticket_link', { p_id: p.data.id, p_kind: p.data.kind, p_ref: p.data.ref, p_label: p.data.label || null, p_on: p.data.on }, z.object({ ok: z.boolean() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}

export async function resolveProblem(input: { id: string; body: string }): Promise<Result<{ notified: number }>> {
  const p = z.object({ id: uuid, body: z.string().trim().min(1).max(20000) }).safeParse(input)
  if (!p.success) return bad
  if (placeholders(p.data.body).length) return { ok: false, code: 'invalid', detail: 'placeholder' }
  const r = await rpc('problem_resolve', { p_problem: p.data.id, p_body: p.data.body }, z.object({ notified: z.number() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true, notified: r.data.notified }
}

export async function createTicket(input: {
  category_key: string; subject: string; description: string; organization_id: string | null; person_id: string | null; product: string | null
}): Promise<Result<{ id: string; ref: string; queue_key: string }>> {
  const p = z.object({
    category_key: z.string().regex(/^[a-z_]{2,40}$/),
    subject: z.string().trim().min(1).max(200),
    description: z.string().trim().max(20000),
    organization_id: uuid.nullable(),
    person_id: uuid.nullable(),
    product: z.string().regex(/^[a-z][a-z0-9_]{1,30}$/).nullable(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'subject' }
  const values: Record<string, unknown> = { category_key: p.data.category_key, subject: p.data.subject }
  if (p.data.description) values.description = p.data.description
  if (p.data.organization_id) values.organization_id = p.data.organization_id
  if (p.data.person_id) values.person_id = p.data.person_id
  if (p.data.product) values.product = p.data.product
  const r = await rpc('ticket_create', { p_values: values }, z.object({ id: uuid, ref: z.string(), queue_key: z.string() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true, ...r.data }
}

/** What the new-ticket dialog picks from, fetched when it opens: companies, people, published article titles. */
export async function newTicketData(): Promise<Result<{ orgs: OrgOption[]; people: PersonOption[]; articles: string[] }>> {
  const [pk, help] = await Promise.all([loadPickers(), loadHelp().catch(() => null)])
  if (!pk) return { ok: false, code: 'failed' }
  return { ok: true, ...pk, articles: help ? help.articles.filter((a) => a.status === 'published').map((a) => a.title) : [] }
}

/**
 * Service request › Extend trial 14 days: the only request that reaches the product today. Orgpuls'
 * billing.extend_trial (admin_extend_trial(p_org, p_days, p_reason)) with the T-number as the reason; the
 * outcome is written to the company's audit trail with the same reason.
 */
export async function extendTrial(input: { ticketId: string }): Promise<Result<{ error?: string }>> {
  const p = z.object({ ticketId: uuid }).safeParse(input)
  if (!p.success) return bad
  const t = await loadTicketDetail(p.data.ticketId)
  if (!t) return { ok: false, code: 'not_found' }
  if (!t.organization_id || t.type !== 'service_request') return bad
  const detail = await rpc('customer_detail', { p_org: t.organization_id }, z.object({
    subscriptions: z.array(z.object({ product: z.string(), tenant_id: z.string(), status: z.string().nullable() })),
  }))
  if (!detail.ok) return { ok: false, code: detail.code }
  const sub = detail.data.subscriptions.find((s) => s.product === 'orgpuls' && s.status === 'trial')
  if (!sub) return { ok: false, code: 'invalid', detail: 'not_in_trial' }
  const reply = await runCommand('billing.extend_trial', { p_org: sub.tenant_id, p_days: 14, p_reason: t.ref })
  const result = z.object({ ok: z.boolean().optional(), error: z.string().optional() }).catch({}).parse(reply.result ?? {})
  const ok = reply.ok && result.ok !== false
  const log = await rpc('customer_action_log', { p_org: t.organization_id, p_action: 'billing.extend_trial', p_reason: t.ref, p_ok: ok }, z.object({ ok: z.boolean() }))
  done()
  if (!ok) return { ok: true, error: (reply.error ?? result.error ?? 'failed').slice(0, 40) }
  if (!log.ok) return { ok: false, code: log.code }
  return { ok: true }
}

export async function saveArticle(input: { id: string | null; values: { title?: string; body?: string; status?: 'draft' | 'published'; category_key?: string | null; problem_id?: string | null } }): Promise<Result<{ id: string }>> {
  const p = z.object({
    id: uuid.nullable(),
    values: z.object({
      title: z.string().trim().min(1).max(200), body: z.string().max(20000), status: z.enum(['draft', 'published']),
      category_key: z.string().regex(/^[a-z_]{2,40}$/).nullable(), problem_id: uuid.nullable(),
    }).partial().strict(),
  }).safeParse(input)
  if (!p.success) return bad
  if (!p.data.id && !p.data.values.title) return bad
  let r = await rpc('help_article_save', { p_id: p.data.id, p_values: p.data.values }, z.object({ id: uuid }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  // a new article is created as a draft; publishing it is a second save
  if (!p.data.id && p.data.values.status === 'published') {
    r = await rpc('help_article_save', { p_id: r.data.id, p_values: { status: 'published' } }, z.object({ id: uuid }))
    if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  }
  done()
  return { ok: true, id: r.data.id }
}

export async function publishMacro(input: { id: string | null; name: string; category: string | null; locale: 'nb' | 'nn' | 'en'; body: string }): Promise<Result<{ version: number }>> {
  const p = z.object({
    id: uuid.nullable(), name: z.string().trim().min(1).max(120), category: z.string().regex(/^[a-z_]{2,40}$/).nullable(),
    locale: z.enum(['nb', 'nn', 'en']), body: z.string().trim().min(1).max(10000),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('macro_publish', { p_id: p.data.id, p_name: p.data.name, p_category: p.data.category, p_locale: p.data.locale, p_body: p.data.body },
    z.object({ id: uuid, version: z.number() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true, version: r.data.version }
}

export async function saveSla(input: { priority: string; firstResponseMin: number; resolutionMin: number }): Promise<Result> {
  const p = z.object({
    priority: z.enum(PRIORITIES), firstResponseMin: z.number().int().min(1).max(100_000), resolutionMin: z.number().int().min(1).max(500_000),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sla_policy_save', { p_priority: p.data.priority, p_first_response_min: p.data.firstResponseMin, p_resolution_min: p.data.resolutionMin }, z.object({ ok: z.boolean() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}

export async function routeCategory(input: { category: string; queue: string }): Promise<Result> {
  const p = z.object({ category: z.string().regex(/^[a-z_]{2,40}$/), queue: z.string().regex(/^[a-z_]{2,30}$/) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('category_route', { p_category: p.data.category, p_queue: p.data.queue }, z.object({ ok: z.boolean() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}
