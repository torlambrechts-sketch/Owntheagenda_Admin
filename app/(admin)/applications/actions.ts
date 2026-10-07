'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { createClient } from '@/lib/supabase/server'
import { runCommand } from '@/lib/platform/command'
import {
  loadCatalog, loadDeliveries, loadDelivery, type Catalog, type Delivery, type DeliveryRow,
} from '@/lib/data/platform'
import { API_SCOPE_RE, PRODUCT_SCOPES } from '@/lib/data/platform-shared'

/**
 * The Platform screen's server actions (Applications and API and integrations). Every input is parsed; every answer is
 * `{ ok: true, … }` or `{ ok: false, code, detail }`. The database checks rights, the owner and the fresh second factor
 * again. A token's, client secret's or webhook secret's plaintext is returned to the dialog that asked for it and
 * nowhere else: it is never logged and never kept.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.string().uuid()
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const any = z.unknown()
const reason = z.string().trim().max(300).optional()
const productKey = z.string().regex(/^[a-z][a-z0-9_]{1,30}$/)

// ---------------------------------------------------------------------------
// the fresh second factor: the authenticator code again, which renews the session's TOTP time (0043 require_fresh_mfa)
export async function reverify(input: unknown): Promise<Res> {
  const p = z.object({ code: z.string().regex(/^\d{6}$/) }).safeParse(input)
  if (!p.success) return bad
  const supabase = await createClient()
  const { data } = await supabase.auth.mfa.listFactors()
  const factor = (data?.totp ?? []).find((f) => f.status === 'verified')
  if (!factor) return { ok: false, code: 'forbidden', detail: 'fresh_mfa' }
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code: p.data.code })
  return error ? { ok: false, code: 'failed' } : { ok: true }
}

// ---------------------------------------------------------------------------
// applications
/**
 * «Test connection»: a harmless read (orgs.list) through product-command, timed here. Only Orgpuls has a command path
 * (lib/platform/command.ts); another product answers not_available. The product-command function does not yet record
 * the ping (worker_application_ping is the edge function's), so the answer is shown, not stored.
 */
export async function testConnection(input: unknown): Promise<Res<{ ms: number }>> {
  const p = productKey.safeParse(input)
  if (!p.success) return bad
  if (p.data !== 'orgpuls') return { ok: false, code: 'not_available', detail: 'command_path' }
  const started = Date.now()
  const reply = await runCommand('orgs.list', {})
  const ms = Date.now() - started
  if (!reply.ok) return { ok: false, code: 'not_connected', detail: reply.error && /^[a-z0-9_]{1,40}$/.test(reply.error) ? reply.error : 'unreachable' }
  return { ok: true, ms }
}

export async function connectApplication(input: unknown): Promise<Res<{ product: string; intake_code: string; expires_in: number }>> {
  const p = z.object({
    key: productKey,
    name: z.string().trim().min(1).max(80),
    description: z.string().trim().max(80).optional(),
    api_url: z.string().trim().regex(/^https:\/\/[^\s/]+$/),
    public_key: z.string().trim().min(20).max(2000),
    region: z.string().trim().max(60).optional(),
    stage: z.enum(['ga', 'beta']),
    scopes: z.array(z.enum(PRODUCT_SCOPES)).max(PRODUCT_SCOPES.length),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: String(p.error.issues[0]?.path[0] ?? '') }
  const values: Record<string, unknown> = { ...p.data }
  if (!p.data.region) delete values.region
  if (!p.data.description) delete values.description
  const r = await rpc('application_connect', { p_values: values }, z.object({ product: z.string(), intake_code: z.string(), expires_in: z.number() }))
  return r.ok ? { ok: true, ...r.data } : fail(r)
}

// ---------------------------------------------------------------------------
// tokens and OAuth apps
const Once = z.object({ id: z.string(), token: z.string(), masked: z.string() })

export async function tokenCreate(input: unknown): Promise<Res<{ token: string; masked: string }>> {
  const p = z.object({ name: z.string().trim().min(1).max(80), days: z.union([z.literal(30), z.literal(90), z.literal(365)]).nullable() }).safeParse(input)
  if (!p.success) return bad
  const expires = p.data.days ? new Date(Date.now() + p.data.days * 86_400_000).toISOString() : null
  const r = await rpc('api_token_create', { p_name: p.data.name, p_expires_at: expires }, Once)
  return r.ok ? { ok: true, token: r.data.token, masked: r.data.masked } : fail(r)
}

export async function tokenRotate(): Promise<Res<{ token: string; masked: string }>> {
  const r = await rpc('api_token_rotate', {}, Once)
  return r.ok ? { ok: true, token: r.data.token, masked: r.data.masked } : fail(r)
}

export async function tokenRevoke(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, reason }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('api_token_revoke', { p_id: p.data.id, p_reason: p.data.reason || null }, any)
  return r.ok ? { ok: true } : fail(r)
}

export async function grantRevoke(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('oauth_grant_revoke', { p_id: p.data }, any)
  return r.ok ? { ok: true } : fail(r)
}

export async function oauthAppCreate(input: unknown): Promise<Res<{ client_id: string; client_secret: string | null }>> {
  const p = z.object({
    name: z.string().trim().min(1).max(80),
    kind: z.enum(['integration', 'extension']),
    redirect_uris: z.array(z.string().trim().url().startsWith('https://')).min(1).max(10),
    allowed_scopes: z.array(z.string().regex(API_SCOPE_RE)).min(1).max(20),
    confidential: z.boolean(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: String(p.error.issues[0]?.path[0] ?? '') }
  const r = await rpc('oauth_app_save', { p_id: null, p_values: p.data }, z.object({ id: z.string(), client_id: z.string(), client_secret: z.string().nullable() }))
  return r.ok ? { ok: true, client_id: r.data.client_id, client_secret: r.data.client_secret } : fail(r)
}

export async function oauthAppDisable(input: unknown): Promise<Res<{ grants: number }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('oauth_app_disable', { p_id: p.data }, z.object({ grants_revoked: z.number() }))
  return r.ok ? { ok: true, grants: r.data.grants_revoked } : fail(r)
}

// ---------------------------------------------------------------------------
// webhooks
export async function webhookSave(input: unknown): Promise<Res<{ id: string; secret: string | null }>> {
  const p = z.object({
    id: uuid.nullable(),
    event_kind: z.string().regex(/^[a-z_]+\.[a-z_]+$/),
    url: z.string().trim().max(2000).startsWith('https://'),
    version: z.number().int().nullable(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: p.error.issues[0]?.path[0] === 'url' ? 'url' : 'event_kind' }
  const r = await rpc('webhook_save', { p_id: p.data.id, p_values: { event_kind: p.data.event_kind, url: p.data.url }, p_version: p.data.version },
    z.object({ id: z.string(), version: z.number(), secret: z.string().optional() }))
  return r.ok ? { ok: true, id: r.data.id, secret: r.data.secret ?? null } : fail(r)
}

/**
 * A new signing secret for a webhook (R-PLATFORM-06): the owner or global:configure, with the export right of its event's
 * area (0049). The secret travels only in this answer, shown once in its dialog; the old one stops signing at once.
 */
export async function webhookRotate(input: unknown): Promise<Res<{ secret: string }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('webhook_rotate_secret', { p_id: p.data }, z.object({ id: z.string(), version: z.number(), secret: z.string().regex(/^whsec_/) }))
  return r.ok ? { ok: true, secret: r.data.secret } : fail(r)
}

export async function webhookDelete(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('webhook_delete', { p_id: p.data }, any)
  return r.ok ? { ok: true } : fail(r)
}

export async function webhookSetState(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, state: z.enum(['active', 'paused']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('webhook_set_state', { p_id: p.data.id, p_state: p.data.state }, any)
  return r.ok ? { ok: true } : fail(r)
}

/** «Send test»: queues a ping as attempt 1. No delivery worker runs yet, so it stays queued (V-PLATFORM-11). */
export async function webhookTest(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('webhook_test', { p_id: p.data }, any)
  return r.ok ? { ok: true } : fail(r)
}

export async function webhookRedeliver(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('webhook_redeliver', { p_delivery: p.data }, any)
  return r.ok ? { ok: true } : fail(r)
}

export async function fetchDeliveries(input: unknown): Promise<Res<{ rows: DeliveryRow[] }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await loadDeliveries(p.data)
  return r.ok ? { ok: true, rows: r.data } : fail(r)
}

/** One delivery's envelope and hash: an audited read (webhook_delivery_get), made only when the staff member picks it. */
export async function fetchDelivery(input: unknown): Promise<Res<{ delivery: Delivery }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await loadDelivery(p.data)
  return r.ok ? { ok: true, delivery: r.data } : fail(r)
}

// ---------------------------------------------------------------------------
// integration catalog
export async function catalogSearch(input: unknown): Promise<Res<{ catalog: Catalog }>> {
  const p = z.string().max(200).safeParse(input)
  if (!p.success) return bad
  const r = await loadCatalog(p.data.trim() || null)
  return r.ok ? { ok: true, catalog: r.data } : fail(r)
}

export async function integrationInstall(input: unknown): Promise<Res<{ connect_required: string | null }>> {
  const p = z.string().regex(/^[a-z_]{2,40}$/).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('integration_install', { p_key: p.data }, z.object({ key: z.string(), connect_required: z.string().nullable() }))
  return r.ok ? { ok: true, connect_required: r.data.connect_required } : fail(r)
}

const Preview = z.object({ users: z.number(), mailboxes: z.number(), calendars: z.number(), company_connection: z.boolean(), workflows: z.number(), grants: z.number() })
export type RemovePreview = z.infer<typeof Preview>

export async function integrationRemovePreview(input: unknown): Promise<Res<{ preview: RemovePreview }>> {
  const p = z.string().regex(/^[a-z_]{2,40}$/).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('integration_remove', { p_key: p.data, p_confirm: null }, z.object({ key: z.string(), preview: Preview }))
  return r.ok ? { ok: true, preview: r.data.preview } : fail(r)
}

export async function integrationRemove(input: unknown): Promise<Res> {
  const p = z.object({ key: z.string().regex(/^[a-z_]{2,40}$/), confirm: z.string().max(40) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('integration_remove', { p_key: p.data.key, p_confirm: p.data.confirm }, z.object({ removed: z.literal(true) }))
  return r.ok ? { ok: true } : fail(r)
}

const Users = z.array(z.object({ staff_id: z.string(), name: z.string().nullable(), via: z.enum(['mailbox', 'calendar', 'token', 'company']) }))
export type IntegrationUser = z.infer<typeof Users>[number]

export async function integrationUsers(input: unknown): Promise<Res<{ users: IntegrationUser[] }>> {
  const p = z.string().regex(/^[a-z_]{2,40}$/).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('integration_users', { p_key: p.data }, Users)
  return r.ok ? { ok: true, users: r.data } : fail(r)
}

export async function integrationUserRevoke(input: unknown): Promise<Res> {
  const p = z.object({ key: z.string().regex(/^[a-z_]{2,40}$/), staff: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('integration_user_revoke', { p_key: p.data.key, p_staff: p.data.staff }, any)
  return r.ok ? { ok: true } : fail(r)
}

// ---------------------------------------------------------------------------
// AI connector, jobs, flags, banner
export async function mcpSet(input: unknown): Promise<Res> {
  const p = z.boolean().safeParse(input)
  if (!p.success) return bad
  const r = await rpc('mcp_set', { p_enabled: p.data }, any)
  return r.ok ? { ok: true } : fail(r)
}

export async function jobRetry(input: unknown): Promise<Res<{ state: string | null }>> {
  const p = z.number().int().positive().safeParse(input)
  if (!p.success) return bad
  const r = await rpc('job_retry', { p_run: p.data }, z.object({ run: z.number(), state: z.string().nullable() }))
  return r.ok ? { ok: true, state: r.data.state } : fail(r)
}

export async function moduleSet(input: unknown): Promise<Res> {
  const p = z.object({ key: z.string().regex(/^[a-z_]{2,40}$/), enabled: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('module_set', { p_key: p.data.key, p_enabled: p.data.enabled }, any)
  return r.ok ? { ok: true } : fail(r)
}

/** Set (text) or clear (null) a product's banner; maintenance is refused not_available until the product has the command. */
export async function noticeSet(input: unknown): Promise<Res> {
  const p = z.object({
    product: productKey,
    text: z.string().trim().min(1).max(500).nullable(),
    problem: uuid.nullable(),
    maintenance: z.boolean(),
    confirm: z.string().max(40).nullable(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'text' }
  const r = await rpc('status_notice_set', {
    p_product: p.data.product, p_text: p.data.text, p_problem: p.data.problem, p_maintenance: p.data.maintenance, p_confirm: p.data.confirm,
  }, any)
  return r.ok ? { ok: true } : fail(r)
}
