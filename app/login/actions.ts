'use server'

import { cookies, headers } from 'next/headers'
import { redirect } from 'next/navigation'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'
import { DEVICE_COOKIE, SEEN_COOKIE, originOf, report } from '@/lib/supabase/report'

export type LoginState = { problem: 'invalid' | 'failed' | null }

const Input = z.object({ email: z.string().trim().toLowerCase().email().max(254), password: z.string().min(1).max(200) })

/** This browser's own id for the device history (a random value, nothing about the person). */
async function deviceId(): Promise<string> {
  const store = await cookies()
  const known = store.get(DEVICE_COOKIE)?.value
  if (known && /^[0-9a-f-]{36}$/.test(known)) return known
  const fresh = crypto.randomUUID()
  store.set(DEVICE_COOKIE, fresh, { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 60 * 60 * 24 * 400 })
  return fresh
}

/** A password first; the second factor is the next page, and nothing is reachable before it. */
export async function signIn(_prev: LoginState, form: FormData): Promise<LoginState> {
  const parsed = Input.safeParse({ email: form.get('email'), password: form.get('password') })
  if (!parsed.success) return { problem: 'invalid' }
  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword(parsed.data)
  const device = await deviceId()
  if (error) {
    // the register counts failures in a row; only the keyed server can report one (lib/supabase/report.ts)
    await report({ kind: 'login', outcome: 'failed_password', email: parsed.data.email, origin: originOf(await headers()), device })
    return { problem: 'failed' }
  }
  redirect('/mfa')
}

export async function signOut(): Promise<void> {
  const supabase = await createClient()
  // the register first, while the session still exists: the row ends as «signed out» (0048)
  await supabase.rpc('session_sign_out')
  await supabase.auth.signOut({ scope: 'local' })
  ;(await cookies()).delete(SEEN_COOKIE)
  redirect('/login')
}
