'use server'

import { headers } from 'next/headers'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { handOverKey, mailRun } from '@/lib/mail/provider'

/**
 * Platform › Email (Brevo, 0060). The owner connects: an intake number (fresh second factor), the key handed straight to
 * secret-intake, then mail-run proves it and checks the sending domains. Each action parses its input and answers
 * `{ ok: true, … }` or `{ ok: false, code, detail }`; the database and mail-run decide (owner, fresh second factor) again.
 */
type Fail = { ok: false; code: RpcCode | string; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const Intake = z.object({ intake_code: z.string().regex(/^[0-9a-f]{48}$/), expires_in: z.number() })

/** Connect (or replace the key): number, hand-over, proof. The key never comes back and is never logged. */
export async function connectBrevo(input: unknown): Promise<Res<{ plan: string | null; webhook: boolean; inbound: boolean | null; verified: number; domains: number }>> {
  const p = z.object({ key: z.string().trim().regex(/^[A-Za-z0-9_-]{32,300}$/) }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'key' }
  const intake = await rpc('email_provider_intake', {}, Intake)
  if (!intake.ok) return intake
  // the address links in mail will open: this screen's own host, unless the owner already chose one
  const now = await rpc('email_provider_get', {}, z.object({ public_base: z.string().nullable(), inbound_domain: z.string().nullable() }).passthrough())
  if (now.ok && !now.data.public_base) {
    const host = (await headers()).get('host')
    if (host && /^[a-z0-9.-]+(:\d+)?$/i.test(host) && !/^(localhost|127\.)/.test(host)) {
      await rpc('email_provider_settings', { p_public_base: `https://${host.toLowerCase()}`, p_inbound_domain: now.data.inbound_domain }, z.unknown())
    }
  }
  const handed = await handOverKey(intake.data.intake_code, p.data.key)
  if (!handed.ok) return { ok: false, code: 'failed', detail: handed.code }
  const r = await mailRun('connect')
  if (!r.ok) return { ok: false, code: 'not_connected', detail: r.code ?? 'failed' }
  return { ok: true, plan: r.plan ?? null, webhook: r.webhook ?? false, inbound: r.inbound ?? null,
           verified: (r.domains ?? []).filter((d) => d.verified).length, domains: (r.domains ?? []).length }
}

/** Check again: the key, the webhooks, every sending domain. */
export async function checkBrevo(): Promise<Res<{ verified: number; domains: number; webhook: boolean }>> {
  const r = await mailRun('connect')
  if (!r.ok) return { ok: false, code: 'not_connected', detail: r.code ?? 'failed' }
  return { ok: true, verified: (r.domains ?? []).filter((d) => d.verified).length, domains: (r.domains ?? []).length, webhook: r.webhook ?? false }
}

/** One email to the owner's own address from the transactional sender. */
export async function testBrevo(): Promise<Res> {
  const r = await mailRun('test')
  return r.ok ? { ok: true } : { ok: false, code: 'not_connected', detail: r.code ?? 'failed' }
}

export async function saveMailSettings(input: unknown): Promise<Res> {
  const p = z.object({
    publicBase: z.string().trim().toLowerCase().regex(/^https:\/\/[a-z0-9.-]+(:\d+)?\/?$/),
    inboundDomain: z.string().trim().toLowerCase().max(200).nullable(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: p.error.issues[0]?.path[0] === 'publicBase' ? 'public_base' : 'inbound_domain' }
  const r = await rpc('email_provider_settings', { p_public_base: p.data.publicBase, p_inbound_domain: p.data.inboundDomain || null }, z.unknown())
  return r.ok ? { ok: true } : r
}

export async function disconnectBrevo(): Promise<Res> {
  const r = await rpc('email_provider_disconnect', {}, z.unknown())
  return r.ok ? { ok: true } : r
}

/** A sending address (0037 sender_domain_save): the domain, who it is from, the stream; Brevo is asked right after. */
export async function saveSender(input: unknown): Promise<Res> {
  const p = z.object({
    domain: z.string().trim().toLowerCase().regex(/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$/),
    fromLocal: z.string().trim().toLowerCase().regex(/^[a-z0-9._+-]{1,64}$/),
    fromName: z.string().trim().min(1).max(80),
    replyTo: z.string().trim().toLowerCase().email().max(254).nullable(),
    stream: z.enum(['transactional', 'marketing']),
    postalAddress: z.string().trim().max(300).nullable(),
    /** the application whose mail this address sends; null for staff mail (invitations, alerts) */
    product: z.string().regex(/^[a-z][a-z0-9_]{1,30}$/).nullable(),
  }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: String(p.error.issues[0]?.path[0] ?? 'values') }
  const v = p.data
  const r = await rpc('sender_domain_save', {
    p_id: null,
    p_values: { domain: v.domain, from_local: v.fromLocal, from_name: v.fromName, reply_to: v.replyTo || null, stream: v.stream, sends_here: true,
                ...(v.postalAddress ? { postal_address: v.postalAddress } : {}), ...(v.product ? { product: v.product } : {}) },
  }, z.unknown())
  if (!r.ok) return r
  await mailRun('connect')
  return { ok: true }
}

/** Send (or send again) a staff member's invitation (0060 staff_invite_send). */
export async function sendInvite(input: unknown): Promise<Res> {
  const p = z.string().uuid().safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await rpc('staff_invite_send', { p_staff: p.data }, z.unknown())
  return r.ok ? { ok: true } : r
}
