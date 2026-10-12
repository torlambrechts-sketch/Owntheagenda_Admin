'use server'

import { revalidatePath } from 'next/cache'
import { getTranslations } from 'next-intl/server'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { supabaseEnv } from '@/lib/supabase/env'
import { createClient } from '@/lib/supabase/server'
import { isOrgpulsCommand } from '@/supabase/functions/_shared/orgpuls.ts'

/**
 * Platform › the new tabs' writes (0082). Each parses its input, calls one database function and answers `{ ok: true, … }` or
 * `{ ok: false, code, detail }`; the database decides again (the role's mode, the right, the second factor, the open follow-up).
 * An approved product command is run here by the approver, at once, under the approval: approval_take hands over the approved
 * arguments, product-command binds the call to the approval (command_authorize) and approval_done records the outcome.
 */
type Fail = { ok: false; code: RpcCode | string; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.string().uuid()
const productKey = z.string().regex(/^[a-z][a-z0-9_]{1,30}$/)
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const code = (s: unknown) => (typeof s === 'string' && /^[a-z0-9_]{1,40}$/.test(s) ? s : 'failed')
const done = () => revalidatePath('/platform')

// ---------------------------------------------------------------------------
// Roles and approvals
/** One cell of the matrix: applied at once with «allow» for roles.manage, sent for approval with «approve» (a reason). */
export async function setPolicy(input: unknown): Promise<Res<{ applied: boolean; approval: string | null }>> {
  const p = z.object({
    set: uuid,
    action: z.string().regex(/^[a-z_]+\.[a-z_]+$/),
    mode: z.enum(['allow', 'approve', 'deny']),
    reason: z.string().trim().min(3).max(300).optional(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: p.error.issues[0]?.path[0] === 'reason' ? 'reason' : null }
  const r = await rpc('action_policy_set', { p_set: p.data.set, p_action: p.data.action, p_mode: p.data.mode, p_reason: p.data.reason ?? null },
    z.object({ applied: z.boolean(), approval: uuid.nullable() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, applied: r.data.applied, approval: r.data.approval }
}

/** Ask for a trial extension or a deletion you may take only with a second person's approval. */
export async function requestApproval(input: unknown): Promise<Res<{ ref: number }>> {
  const p = z.discriminatedUnion('action', [
    z.object({ action: z.literal('trial.extend'), organization: uuid, days: z.number().int().min(1).max(60), reason: z.string().trim().min(3).max(300) }),
    z.object({ action: z.literal('account.delete'), organization: uuid, confirm: z.string().trim().min(1).max(40), reason: z.string().trim().min(3).max(300) }),
  ]).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: p.error.issues[0]?.path[0] === 'reason' ? 'reason' : null }
  const params = p.data.action === 'trial.extend'
    ? { organization: p.data.organization, days: p.data.days }
    : { organization: p.data.organization, confirm: p.data.confirm.replace(/\s/g, '') }
  const r = await rpc('approval_request', { p_action: p.data.action, p_params: params, p_reason: p.data.reason }, z.object({ id: uuid, ref: z.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, ref: r.data.ref }
}

const Reply = z.object({ ok: z.boolean(), error: z.string().optional(), result: z.unknown().optional() })
const Inner = z.object({ ok: z.boolean(), error: z.string().optional() }).passthrough()

/**
 * What product-command answered: the command ran (true), it did not (false: nothing was sent, a refusal, or the product's own
 * error), or nothing the app could read in time (null: no answer, a timeout, a page that is not product-command's reply). For
 * null the database decides from the command audit (approval_done, approval_sweep), never the app's guess.
 */
type Sent = { ok: true } | { ok: false | null; code: string }

/** product-command's own worst case is a product call of up to 20 s plus its checks and a cold start: wait well beyond it. */
const SEND_TIMEOUT_MS = 40_000

/** product-command with the approver's own session and the approval's id (runCommand without an approval cannot carry it). */
async function sendApproved(command: string, args: Record<string, unknown>, approval: string): Promise<Sent> {
  if (!isOrgpulsCommand(command)) return { ok: false, code: 'invalid' }
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_configured' }
  const supabase = await createClient()
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  if (!token) return { ok: false, code: 'not_signed_in' }
  try {
    const res = await fetch(`${env.url}/functions/v1/product-command`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, apikey: env.key, 'content-type': 'application/json' },
      body: JSON.stringify({ product: 'orgpuls', command, args, approval }),
      cache: 'no-store',
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    })
    const reply = Reply.safeParse(await res.json().catch(() => null))
    if (!reply.success) return { ok: null, code: `http_${res.status}` }
    if (!reply.data.ok) return { ok: false, code: code(reply.data.error) }
    // the product function's own answer inside the envelope
    const inner = Inner.safeParse(reply.data.result)
    if (inner.success && !inner.data.ok) return { ok: false, code: code(inner.data.error) }
    return { ok: true }
  } catch (e) {
    return { ok: null, code: (e as { name?: unknown } | null)?.name === 'TimeoutError' ? 'timeout' : 'unreachable' }
  }
}

const ACTION_LOG: Record<string, string> = { 'trial.extend': 'customer.extend_trial', 'account.delete': 'customer.delete' }
const DecideZ = z.object({ id: uuid, state: z.string(), executor: z.enum(['command', 'database']).nullable(), code: z.string().nullable().optional() })
const TakeZ = z.object({
  id: uuid,
  action: z.string(),
  product: z.literal('orgpuls'),
  command: z.string(),
  args: z.record(z.string(), z.unknown()),
  organization_id: uuid.nullable(),
  reason: z.string(),
})

const DoneZ = z.object({ id: uuid, state: z.enum(['executed', 'failed', 'executing']), code: z.string().nullable().optional() })

/**
 * Approve or reject. A policy change is made by the database on approval; a product command is run here, now, by the approver
 * (a fresh second factor was asked by approval_decide) and its outcome recorded. The answer says what happened, with the
 * product's own code when it refused. When the app could not tell whether the command ran, the database decides from the
 * command audit; until the audit answers the request stays «executing» and the customer's history gets its line from the
 * approval's own audit entry when it is settled.
 */
export async function decideApproval(input: unknown): Promise<Res<{ state: string; code: string | null }>> {
  const p = z.object({ id: uuid, yes: z.boolean(), note: z.string().trim().max(300).optional(), confirm: z.string().max(40).optional() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const d = await rpc('approval_decide', { p_id: p.data.id, p_yes: p.data.yes, p_note: p.data.note || null, p_confirm: p.data.confirm?.replace(/\s/g, '') || null }, DecideZ)
  if (!d.ok) return fail(d)
  if (d.data.state !== 'approved') {
    done()
    return { ok: true, state: d.data.state, code: d.data.code ?? null }
  }
  const take = await rpc('approval_take', { p_id: p.data.id }, TakeZ)
  if (!take.ok) {
    done()
    return { ok: true, state: 'approved', code: take.code }
  }
  const sent = await sendApproved(take.data.command, take.data.args, take.data.id)
  const recorded = await rpc('approval_done', { p_id: take.data.id, p_ok: sent.ok, p_code: sent.ok ? null : sent.code }, DoneZ)
  const state = recorded.ok ? recorded.data.state : null
  const log = ACTION_LOG[take.data.action]
  if (take.data.organization_id && log && (state === 'executed' || state === 'failed')) {
    await rpc('customer_action_log', { p_org: take.data.organization_id, p_action: log, p_reason: take.data.reason, p_ok: state === 'executed' }, z.object({ ok: z.boolean() }), { quiet: true })
  }
  done()
  if (!recorded.ok) {
    if (sent.ok === false) return { ok: true, state: 'failed', code: sent.code }
    const detail = recorded.detail && /^[a-z_]{1,40}$/.test(recorded.detail) ? recorded.detail : 'not_recorded'
    // an unknown outcome the database could not take yet stays open; approval_sweep settles it from the audit
    return { ok: true, state: sent.ok === null ? 'executing' : 'failed', code: detail }
  }
  if (recorded.data.state === 'executed') return { ok: true, state: 'executed', code: null }
  return { ok: true, state: recorded.data.state, code: recorded.data.code ?? (sent.ok ? null : sent.code) }
}

// ---------------------------------------------------------------------------
// Customer success
const RequestOut = z.object({ id: uuid })

/** A feature request recorded on behalf of an organisation (0078: one vote per organisation). */
export async function addRequest(input: unknown): Promise<Res> {
  const p = z.object({ product: productKey, title: z.string().trim().min(3).max(200), organization: uuid.nullable() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'title' }
  const r = await rpc('feature_request_add', { p_product: p.data.product, p_title: p.data.title, p_problem: null, p_organization: p.data.organization }, RequestOut)
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function voteRequest(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, organization: uuid, on: z.boolean() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await rpc('feature_request_vote', { p_id: p.data.id, p_organization: p.data.organization, p_on: p.data.on }, RequestOut)
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function setRequestStatus(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, status: z.enum(['under_review', 'planned', 'in_progress', 'shipped', 'declined']) }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await rpc('feature_request_set', { p_id: p.data.id, p_patch: { status: p.data.status } }, RequestOut)
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

const FollowUp = z.object({ id: uuid, existing: z.boolean() })

/** «Create deal» on an expansion signal; the title is written in the staff member's language. */
export async function createSuccessDeal(input: unknown): Promise<Res<{ existing: boolean }>> {
  const p = z.object({ org: uuid, product: productKey, name: z.string().trim().min(1).max(200) }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const t = await getTranslations('platformPlus.success.renewal')
  const r = await rpc('success_deal_create', { p_org: p.data.org, p_product: p.data.product, p_title: t('dealTitle', { name: p.data.name }).slice(0, 200) }, FollowUp)
  if (!r.ok) return fail(r)
  done()
  return { ok: true, existing: r.data.existing }
}

/** «CSM task» on an at-risk signal: to the account's customer success manager (else its owner). */
export async function createSuccessTask(input: unknown): Promise<Res<{ existing: boolean }>> {
  const p = z.object({ org: uuid, product: productKey, name: z.string().trim().min(1).max(200) }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const t = await getTranslations('platformPlus.success.renewal')
  const r = await rpc('success_task_create', { p_org: p.data.org, p_product: p.data.product, p_subject: t('taskSubject', { name: p.data.name }).slice(0, 200) }, FollowUp)
  if (!r.ok) return fail(r)
  done()
  return { ok: true, existing: r.data.existing }
}

// ---------------------------------------------------------------------------
// Errors per customer
const ErrorRow = z.object({ organization: z.object({ id: uuid, name: z.string() }), replies: z.number(), bounces: z.number(), failed: z.number() })

/**
 * «Create ticket» on an organisation's failed mail: the counts are read again here (never taken from the screen) and written
 * as the ticket's first note — counts only, no address and no message (R-PL-2).
 */
export async function createErrorTicket(input: unknown): Promise<Res<{ ref: string; existing: boolean }>> {
  const p = z.object({ org: uuid, product: productKey }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const list = await rpc('customer_errors', { p_product: p.data.product, p_hours: 24 }, z.object({ rows: z.array(ErrorRow) }))
  if (!list.ok) return fail(list)
  const row = list.data.rows.find((x) => x.organization.id === p.data.org)
  const t = await getTranslations('platformPlus.ops.errors')
  const lines = row ? [
    row.replies ? t('ticketReplies', { count: row.replies }) : null,
    row.bounces ? t('ticketBounces', { count: row.bounces }) : null,
    row.failed ? t('ticketFailed', { count: row.failed }) : null,
  ].filter(Boolean).join('\n') : ''
  const r = await rpc('error_ticket_create', {
    p_org: p.data.org, p_product: p.data.product,
    p_subject: t('ticketSubject', { name: row?.organization.name ?? '' }).slice(0, 200),
    p_body: lines ? `${t('ticketIntro')}\n${lines}` : null,
  }, z.object({ id: uuid, ref: z.string(), existing: z.boolean() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, ref: r.data.ref, existing: r.data.existing }
}
