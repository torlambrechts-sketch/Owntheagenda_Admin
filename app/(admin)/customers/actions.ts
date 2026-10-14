'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { getShell } from '@/lib/shell'
import { runCommand } from '@/lib/platform/command'
import { loadCustomer, settingValue } from '@/lib/data/customers'
import { loadTicket } from '@/lib/data/simple-customers'
import { approvalBlock, requestDays } from '@/lib/data/simple-customers-shared'

/**
 * The Customers screen's writes. Each parses its input, calls one database function (or one product
 * command) and returns `{ ok: true }` or `{ ok: false, code }`; the screen shows the code's message.
 */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: string }

const id = z.string().uuid()
const fail = (code: string) => ({ ok: false as const, code })
const done = () => revalidatePath('/customers')

export async function saveNote(input: { org: string; body: string; mentions: string[] }): Promise<Result> {
  const p = z.object({ org: id, body: z.string().trim().min(1).max(10000), mentions: z.array(id).max(20) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('note_save', { p_entity: 'organization', p_id: p.data.org, p_note: null, p_body: p.data.body, p_pinned: null, p_parent: null, p_mentions: p.data.mentions }, z.object({ id: z.string() }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

export async function deleteNote(input: { note: string }): Promise<Result> {
  const p = z.object({ note: id }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('note_delete', { p_note: p.data.note }, z.object({ ok: z.boolean() }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

/** The company's tags (record labels), with the version the screen last saw. */
export async function setTags(input: { org: string; labels: string[]; version: number }): Promise<Result<{ version: number }>> {
  const p = z.object({ org: id, labels: z.array(id).max(50), version: z.number().int().positive() }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('rec_save', { p_entity: 'organization', p_id: p.data.org, p_values: { labels: p.data.labels }, p_version: p.data.version }, z.object({ id: z.string(), version: z.number() }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true, version: r.data.version }
}

/**
 * Bulk «Add tag»: rec_bulk writes the same values to every record, so the companies are grouped by the
 * tags they already carry and each group gets its own tags plus the new one. Nothing is taken away.
 */
export async function bulkAddLabel(input: { items: { id: string; labels: string[] }[]; label: string }): Promise<Result<{ updated: number }>> {
  const p = z.object({ items: z.array(z.object({ id, labels: z.array(id).max(50) })).min(1).max(500), label: id }).safeParse(input)
  if (!p.success) return fail('invalid')
  const groups = new Map<string, { labels: string[]; ids: string[] }>()
  for (const it of p.data.items) {
    const labels = [...new Set([...it.labels, p.data.label])].sort()
    const key = labels.join(',')
    const g = groups.get(key) ?? { labels, ids: [] }
    g.ids.push(it.id)
    groups.set(key, g)
  }
  let updated = 0
  for (const g of groups.values()) {
    const r = await rpc('rec_bulk', { p_entity: 'organization', p_ids: g.ids, p_values: { labels: g.labels }, p_reason: null }, z.object({ updated: z.number() }))
    if (!r.ok) {
      done()
      return fail(r.code)
    }
    updated += r.data.updated
  }
  done()
  return { ok: true, updated }
}

export async function bulkOwner(input: { ids: string[]; owner: string }): Promise<Result<{ updated: number }>> {
  const p = z.object({ ids: z.array(id).min(1).max(500), owner: id }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('rec_bulk', { p_entity: 'organization', p_ids: p.data.ids, p_values: { owner_id: p.data.owner }, p_reason: null }, z.object({ updated: z.number() }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true, updated: r.data.updated }
}

/** An export is built in the browser from the visible rows; this records it first (SEC-02). */
export async function logExport(input: { rows: number }): Promise<Result> {
  const p = z.object({ rows: z.number().int().min(0).max(100000) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('export_log', { p_entity: 'organization', p_rows: p.data.rows, p_format: 'csv', p_scope: 'customers' }, z.object({ ok: z.boolean() }))
  return r.ok ? { ok: true } : fail(r.code)
}

const ViewQuery = z.record(z.enum(['q', 'view', 'status', 'plan', 'industry', 'fylke', 'source', 'uses']), z.string().max(200))

export async function saveView(input: { name: string; query: Record<string, string> }): Promise<Result> {
  const p = z.object({ name: z.string().trim().min(1).max(80), query: ViewQuery }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('view_save', { p_id: null, p_screen: 'customers', p_name: p.data.name, p_query: p.data.query, p_shared: false }, z.object({ id: z.string() }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

export async function requestAccess(input: { org: string; product: string; hours: number; reason: string }): Promise<Result> {
  const p = z.object({ org: id, product: z.string().regex(/^[a-z][a-z0-9_]{1,30}$/), hours: z.union([z.literal(24), z.literal(72)]), reason: z.string().trim().min(1).max(300) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('access_request', { p_org: p.data.org, p_product: p.data.product, p_hours: p.data.hours, p_reason: p.data.reason }, z.object({ id: z.string() }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

const ACTION_LOG = { trial: 'customer.extend_trial', resync: 'customer.resync', delete: 'customer.delete' } as const

/**
 * The actions that reach Orgpuls today (D-40): extend a trial, re-sync, delete (preview and the typed
 * org.nr, D-30). The command goes through product-command, which audits it by argument name; the company
 * and the typed reason are written beside it with customer_action_log.
 */
export async function runCustomerAction(input: { org: string; action: 'trial' | 'resync' | 'delete'; reason: string; days?: number; confirm?: string }): Promise<Result> {
  const p = z.object({
    org: id,
    action: z.enum(['trial', 'resync', 'delete']),
    reason: z.string().trim().min(1).max(300),
    days: z.number().int().min(1).max(60).optional(),
    confirm: z.string().max(40).optional(),
  }).safeParse(input)
  if (!p.success) return fail('invalid')
  const { org, action, reason } = p.data

  const detail = await loadCustomer(org)
  if (!detail.ok) return fail(detail.code)
  const tenant = detail.data.subscriptions.find((s) => s.product === 'orgpuls')?.tenant_id
  if (!tenant) return fail('no_orgpuls')

  let reply: { ok: boolean; error?: string; result?: unknown }
  if (action === 'trial') {
    if (!p.data.days) return fail('invalid')
    reply = await runCommand('orgpuls', 'billing.extend_trial', { p_org: tenant, p_days: p.data.days, p_reason: reason })
  } else if (action === 'resync') {
    reply = await runCommand('orgpuls', 'orgs.resync', { p_org: tenant })
  } else {
    const shell = await getShell()
    if (shell.me.permission_kind !== 'admin') return fail('forbidden')
    if ((await settingValue('second_admin')) === 'on') return fail('approval_required')
    const typed = (p.data.confirm ?? '').replace(/\s/g, '')
    if (!detail.data.org_number || typed !== detail.data.org_number) return fail('confirm_mismatch')
    reply = await runCommand('orgpuls', 'orgs.delete_now', { p_org: tenant, p_confirm: typed, p_reason: reason })
  }

  // the operation itself answers inside the reply ({ ok: true, result: { ok: false, error } })
  const inner = z.object({ ok: z.literal(false), error: z.string().max(60).optional() }).safeParse(reply.result)
  const ok = reply.ok && !inner.success
  const logged = await rpc('customer_action_log', { p_org: org, p_action: ACTION_LOG[action], p_reason: reason, p_ok: ok }, z.object({ ok: z.boolean() }))
  done()
  if (!ok) return fail((inner.success ? inner.data.error : reply.error) ?? 'failed')
  if (!logged.ok) return fail(logged.code)
  return { ok: true }
}

/**
 * Sentral Simple › Tickets and requests › «Approve and apply»: a service request whose kind a product command applies.
 * Today that is a trial extension (Orgpuls' billing.extend_trial through runCustomerAction, with the request's days and
 * the T-number as the reason). The outcome becomes a line in the thread (ticket_action_note, accepted only after the
 * audit row), and a request that was applied is resolved. The customer is not told: no mail provider is connected.
 */
export async function approveRequest(input: { ticketId: string }): Promise<Result<{ resolved: boolean }>> {
  const p = z.object({ ticketId: id }).safeParse(input)
  if (!p.success) return fail('invalid')
  const t = await loadTicket(p.data.ticketId)
  if (!t) return fail('not_found')
  if (t.type !== 'service_request' || t.status === 'resolved' || t.status === 'closed') return fail('invalid')
  const block = approvalBlock({ request: t.request, product: t.product, organizationId: t.organization_id, subscriptionStatus: t.subscription?.status ?? null }, true)
  if (block || !t.organization_id) return fail(block === 'notTrial' ? 'not_in_trial' : 'invalid')
  const r = await runCustomerAction({ org: t.organization_id, action: 'trial', days: requestDays(t.request), reason: t.ref })
  // the thread line; refused when nothing reached the audit (the command never ran), which leaves the thread as it was
  await rpc('ticket_action_note', { p_id: t.id, p_action: 'billing.extend_trial', p_ok: r.ok }, z.object({ id }), { quiet: true })
  if (!r.ok) {
    done()
    return r
  }
  const saved = await rpc('rec_save', { p_entity: 'ticket', p_id: t.id, p_values: { status: 'resolved' } }, z.object({ id: z.string(), version: z.number() }), { quiet: true })
  done()
  return { ok: true, resolved: saved.ok }
}
