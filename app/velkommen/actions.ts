'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'

export type WelcomeState = { problem: null | 'invalid' | 'mismatch' | 'weak' | 'expired' | 'failed' }

const Input = z.object({
  token_hash: z.string().regex(/^[A-Za-z0-9_-]{20,200}$/),
  type: z.enum(['invite', 'recovery']),
  password: z.string().min(12).max(200),
  repeat: z.string().max(200),
})

/**
 * The invitation's one-time token signs the person in (Auth verifies it once), the chosen password is set, and the second
 * factor is next: /mfa enrols it, and nothing in Sentral opens before it.
 */
export async function acceptInvitation(_prev: WelcomeState, form: FormData): Promise<WelcomeState> {
  const p = Input.safeParse({ token_hash: form.get('token_hash'), type: form.get('type'), password: form.get('password'), repeat: form.get('repeat') })
  if (!p.success) return { problem: p.error.issues.some((i) => i.path[0] === 'password') ? 'weak' : 'invalid' }
  if (p.data.password !== p.data.repeat) return { problem: 'mismatch' }
  const supabase = await createClient()
  const { error: verifyError } = await supabase.auth.verifyOtp({ token_hash: p.data.token_hash, type: p.data.type })
  if (verifyError) return { problem: 'expired' }
  const { error } = await supabase.auth.updateUser({ password: p.data.password })
  if (error) return { problem: error.code === 'weak_password' ? 'weak' : 'failed' }
  redirect('/mfa')
}
