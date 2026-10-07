import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { supabaseEnv } from '@/lib/supabase/env'
import { accessToken } from '@/lib/storage/server'

/**
 * The mail provider (Brevo, 0060) as the app sees it. The app never holds the Brevo key: the owner's key goes from the form
 * straight on to secret-intake (Vault), and every check or test is mail-run's, called with the owner's own token. Replies
 * are parsed, never cast.
 */
const Sender = z.object({ id: z.string(), domain: z.string(), stream: z.enum(['marketing', 'transactional']), sends_here: z.boolean(), address: z.string(),
  name: z.string().nullable(), reply_to: z.string().nullable(), product: z.string().nullable().optional(), authenticated: z.boolean(), verified: z.boolean(), last_checked_at: z.string().nullable(), version: z.number() })
export const EmailProvider = z.object({
  provider: z.literal('brevo'),
  status: z.enum(['not_connected', 'connected', 'error']),
  connected: z.boolean(),
  connected_at: z.string().nullable(),
  key_stored: z.boolean(),
  public_base: z.string().nullable(),
  /** each application's own link address (0063): its campaigns' unsubscribe links open there */
  app_bases: z.record(z.string(), z.string()).default({}),
  inbound_domain: z.string().nullable(),
  inbound_ok: z.boolean(),
  account: z.object({ plan: z.string().nullable().optional() }).passthrough(),
  webhook_ok: z.boolean(),
  last_check_at: z.string().nullable(),
  last_error: z.string().nullable(),
  last_run_at: z.string().nullable(),
  ready: z.boolean(),
  /** the applications whose customers get email now: a verified sending address of their own (0061) */
  ready_products: z.array(z.string()).default([]),
  sender: z.object({ id: z.string(), address: z.string(), name: z.string().nullable(), reply_to: z.string().nullable(), stream: z.string() }).nullable(),
  senders: z.array(Sender),
  waiting: z.object({ tickets: z.number(), invites: z.number(), alerts: z.number(), jobs: z.number() }),
  failed_24h: z.number(),
  can_manage: z.boolean(),
})
export type EmailProvider = z.infer<typeof EmailProvider>
export type EmailSender = z.infer<typeof Sender>

export const loadEmailProvider = () => rpc('email_provider_get', {}, EmailProvider)

const code = z.string().regex(/^[a-z0-9_.:-]{1,60}$/)
const Connect = z.object({ ok: z.boolean(), code: code.optional(), plan: z.string().nullable().optional(), webhook: z.boolean().optional(),
  inbound: z.boolean().nullable().optional(), domains: z.array(z.object({ domain: z.string(), verified: z.boolean() }).passthrough()).optional() })
export type MailRunReply = z.infer<typeof Connect>

/** mail-run with the owner's own token: «connect» proves the key and checks the domains, «test» mails the owner. */
export async function mailRun(kind: 'connect' | 'test'): Promise<MailRunReply> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  const token = await accessToken()
  if (!token) return { ok: false, code: 'not_signed_in' }
  try {
    const res = await fetch(`${env.url}/functions/v1/mail-run`, {
      method: 'POST',
      headers: { apikey: env.key, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ kind }),
      cache: 'no-store',
      signal: AbortSignal.timeout(45_000),
    })
    if (res.status === 404 || res.status === 503) return { ok: false, code: 'not_deployed' }
    if (res.status === 403 || res.status === 401) return { ok: false, code: 'forbidden' }
    const parsed = Connect.safeParse(await res.json().catch(() => null))
    return parsed.success ? parsed.data : { ok: false, code: 'unexpected_reply' }
  } catch {
    return { ok: false, code: 'not_connected' }
  }
}

/**
 * The owner's key, handed straight to secret-intake with the one-time number from email_provider_intake. The value is not
 * logged, stored or returned here; only the intake's verdict comes back.
 */
export async function handOverKey(intakeCode: string, key: string): Promise<{ ok: boolean; code: string | null }> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, code: 'not_connected' }
  try {
    const res = await fetch(`${env.url}/functions/v1/secret-intake`, {
      method: 'POST',
      headers: { apikey: env.key, 'content-type': 'application/json' },
      body: JSON.stringify({ nonce: intakeCode, secrets: { brevo_api_key: key } }),
      cache: 'no-store',
      signal: AbortSignal.timeout(15_000),
    })
    const r = z.object({ ok: z.boolean().optional(), stored: z.number().optional(), error: z.string().optional() }).safeParse(await res.json().catch(() => null))
    if (res.ok && r.success && r.data.ok && r.data.stored === 1) return { ok: true, code: null }
    if (res.status === 404 || res.status === 503) return { ok: false, code: 'not_deployed' }
    return { ok: false, code: res.status === 403 ? 'expired' : 'invalid' }
  } catch {
    return { ok: false, code: 'not_connected' }
  }
}
