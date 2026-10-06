'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'
import { whoami } from '@/lib/platform/read'

export type Enrolment = { ok: true; factorId: string; qr: string; secret: string } | { ok: false }
export type VerifyState = { problem: 'failed' | null }

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
  const { error } = await supabase.auth.mfa.challengeAndVerify(parsed.data)
  if (error) return { problem: 'failed' }
  redirect('/')
}
