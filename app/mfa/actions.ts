'use server'

import { cookies, headers } from 'next/headers'
import { redirect } from 'next/navigation'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'
import { whoami } from '@/lib/platform/read'
import { DEVICE_COOKIE, SEEN_COOKIE, originOf, report, sessionOf } from '@/lib/supabase/report'

export type Enrolment = { ok: true; factorId: string; qr: string; secret: string } | { ok: false }
const BLOCKED = ['blocked_ip', 'blocked_time', 'blocked_inactive', 'blocked_method'] as const
export type VerifyState = { problem: 'failed' | (typeof BLOCKED)[number] | null }

/**
 * A new authenticator; a half-made one from an earlier try is removed first. The issuer is the name the
 * authenticator app shows; without it Supabase uses the Site URL's host.
 */
export async function enroll(): Promise<Enrolment> {
  // only an account on the staff list may set up a factor (F-5)
  const me = await whoami()
  if (!me?.account) return { ok: false }
  const supabase = await createClient()
  const { data: list } = await supabase.auth.mfa.listFactors()
  for (const f of list?.all ?? []) {
    if (f.factor_type === 'totp' && f.status !== 'verified') await supabase.auth.mfa.unenroll({ factorId: f.id })
  }
  const { data, error } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Authenticator', issuer: 'OwnTheAgenda Admin' })
  if (error || !data) return { ok: false }
  return { ok: true, factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret }
}

const Input = z.object({ factorId: z.string().uuid(), code: z.string().trim().regex(/^\d{6}$/) })

export async function verify(_prev: VerifyState, form: FormData): Promise<VerifyState> {
  const parsed = Input.safeParse({ factorId: form.get('factorId'), code: form.get('code') })
  if (!parsed.success) return { problem: 'failed' }
  const supabase = await createClient()
  const before = (await supabase.auth.getSession()).data.session?.access_token
  const { error } = await supabase.auth.mfa.challengeAndVerify(parsed.data)
  const origin = originOf(await headers())
  const store = await cookies()
  const device = store.get(DEVICE_COOKIE)?.value ?? null
  if (error) {
    if (before) await report({ kind: 'login', outcome: 'failed_mfa', token: before, origin, device })
    return { problem: 'failed' }
  }
  // the sign-in is complete: the register decides whether it may stand (IP, hours, an inactive account)
  const token = (await supabase.auth.getSession()).data.session?.access_token
  const reply = token ? await report({ kind: 'login', outcome: 'success', token, origin, device }) : null
  const blocked = BLOCKED.find((b) => b === reply?.reason)
  if (reply && !reply.ok) {
    await supabase.auth.signOut({ scope: 'local' })
    return { problem: blocked ?? 'failed' }
  }
  const session = token ? sessionOf(token) : null
  if (reply && session) store.set(SEEN_COOKIE, `${session}.${Math.floor(Date.now() / 1000)}`, { httpOnly: true, secure: true, sameSite: 'lax', path: '/' })
  redirect('/')
}
