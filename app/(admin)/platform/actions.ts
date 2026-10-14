'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { can, getShell } from '@/lib/shell'
import { runCommand, type CommandReply } from '@/lib/platform/command'
import { loadNotice } from '@/lib/data/platform'
import { noticeSet } from '../applications/actions'

/**
 * Sentral Simple › Platform's writes. Each parses its input, answers `{ ok: true, … }` or `{ ok: false, code, detail }`, and
 * leaves the decision to the database or the product (rights, the owner, the second factor are checked there again). Role
 * changes and removal reuse Settings' saveStaff; Test connection and Connect reuse the Platform screen's actions.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const productKey = z.string().regex(/^[a-z][a-z0-9_]{1,30}$/)
const code = (s: unknown) => (typeof s === 'string' && /^[a-z0-9_]{1,40}$/.test(s) ? s : 'failed')

/**
 * A product command's own answer: product-command's reply carries the product function's result, which says ok or names its
 * error (Orgpuls 0205: platform_command runs e.g. admin_site_notice_set and returns its jsonb).
 */
const Inner = z.object({ ok: z.boolean(), error: z.string().optional() }).passthrough()
function outcome(reply: CommandReply): { ok: true; result: z.infer<typeof Inner> } | { ok: false; code: string } {
  if (!reply.ok) return { ok: false, code: code(reply.error) }
  const inner = Inner.safeParse(reply.result)
  if (!inner.success) return { ok: false, code: 'unexpected_reply' }
  return inner.data.ok ? { ok: true, result: inner.data } : { ok: false, code: code(inner.data.error) }
}

// ---------------------------------------------------------------------------
// the status message: stored in Sentral (status_notice_set), then delivered through Orgpuls' settings.set_notice
/**
 * Publish (text) or clear (null) the status message of a product. The notice is stored and queued as before (noticeSet); no
 * worker drains that queue yet, so the delivery is made here, at once, by settings.set_notice — Orgpuls only: LeaderPact
 * has no notice command (_shared/leaderpact.ts) — and its outcome is recorded against the notice (status_notice_push_result,
 * 0057; «delivered» only when the command audit holds the call). Orgpuls keeps one notice in two languages, at most 300
 * characters: the same text goes to both.
 */
export async function publishNotice(input: unknown): Promise<Res<{ delivered: boolean; code: string | null }>> {
  const p = z.object({ product: productKey, text: z.string().trim().min(1).max(300).nullable() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'text' }
  // keep the current notice's problem link (a banner tied to a problem clears itself when the problem is resolved)
  const now = await loadNotice(p.data.product)
  const problem = p.data.text && now.ok ? now.data.current?.problem_ticket_id ?? null : null
  const set = await noticeSet({ product: p.data.product, text: p.data.text, problem, maintenance: false, confirm: null })
  if (!set.ok) return set
  if (p.data.product !== 'orgpuls') return { ok: true, delivered: false, code: 'command_path' }
  const sent = outcome(await runCommand('orgpuls', 'settings.set_notice', { p_on: p.data.text !== null, p_no: p.data.text, p_en: p.data.text }))
  const recorded = await rpc('status_notice_push_result', { p_id: set.id, p_ok: sent.ok, p_error: sent.ok ? null : sent.code }, z.object({ id: z.string(), ok: z.boolean() }))
  if (!recorded.ok && sent.ok) return { ok: true, delivered: false, code: 'not_recorded' }
  return sent.ok ? { ok: true, delivered: true, code: null } : { ok: true, delivered: false, code: sent.code }
}

// ---------------------------------------------------------------------------
// feature flags: Orgpuls' question modules (modules.list / modules.set_status), read and switched through product-command
const ModuleZ = z.object({
  key: z.string(),
  version: z.string(),
  name: z.string(),
  status: z.enum(['draft', 'published', 'retired']),
  items: z.coerce.number().nullable().optional(),
  pilots: z.array(z.unknown()).optional(),
})
export type ProductFlag = { key: string; version: string; name: string; status: 'draft' | 'published' | 'retired'; items: number | null; pilots: number }

/**
 * The product's modules as its own modules.list returns them (Orgpuls 0122 admin_modules), newest version first per key.
 * Orgpuls only for now: LeaderPact's modules.set_status takes an integer version and no reason, so its switch needs its own
 * arguments before the Flags tab offers it.
 */
export async function fetchProductFlags(input: unknown): Promise<Res<{ flags: ProductFlag[] }>> {
  const p = productKey.safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  if (p.data !== 'orgpuls') return { ok: false, code: 'not_available', detail: 'command_path' }
  const r = outcome(await runCommand('orgpuls', 'modules.list', {}))
  if (!r.ok) return { ok: false, code: 'not_connected', detail: r.code }
  const mods = z.array(ModuleZ).safeParse(r.result.modules)
  if (!mods.success) return { ok: false, code: 'failed', detail: 'unexpected_reply' }
  return {
    ok: true,
    flags: mods.data.map((m) => ({ key: m.key, version: m.version, name: m.name, status: m.status, items: m.items ?? null, pilots: m.pilots?.length ?? 0 })),
  }
}

/**
 * Publish a draft or retire a published version (modules.set_status): one way only, as Orgpuls moves a module draft →
 * published → retired; a reason of at least five characters goes into Orgpuls' own audit. Sentral asks for the right to
 * configure first; Orgpuls checks the actor again.
 */
export async function setProductFlag(input: unknown): Promise<Res> {
  const p = z.object({
    product: productKey,
    key: z.string().regex(/^[a-z0-9]+(-[a-z0-9]+)*$/),
    version: z.string().regex(/^\d+\.\d+\.\d+$/),
    status: z.enum(['published', 'retired']),
    reason: z.string().trim().min(5).max(300),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: p.error.issues[0]?.path[0] === 'reason' ? 'reason' : null }
  if (!can(await getShell(), 'global', 'configure')) return { ok: false, code: 'forbidden' }
  if (p.data.product !== 'orgpuls') return { ok: false, code: 'not_available', detail: 'command_path' }
  const r = outcome(await runCommand('orgpuls', 'modules.set_status', { p_key: p.data.key, p_version: p.data.version, p_status: p.data.status, p_reason: p.data.reason }))
  return r.ok ? { ok: true } : { ok: false, code: 'not_connected', detail: r.code }
}

// ---------------------------------------------------------------------------
// team
/**
 * Invite: a staff row on Read-only with the address only (staff_save; no name is made up from the address). With Brevo
 * connected and a verified sender (0060) the invitation email goes out with a one-time link: the person chooses a password
 * and the second factor. Without it the row exists and the screen says no email went (V-SPL-12).
 */
export async function inviteStaff(input: unknown): Promise<Res<{ invite: string | null }>> {
  const p = z.string().trim().toLowerCase().email().max(200).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'email' }
  const r = await rpc('staff_save', { p_id: null, p_values: { email: p.data } }, z.object({ id: z.string().uuid(), invite: z.string().optional() }))
  return r.ok ? { ok: true, invite: r.data.invite ?? null } : { ok: false, code: r.code, detail: r.detail }
}
