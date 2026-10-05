'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'

export type LoginState = { problem: 'invalid' | 'failed' | null }

const Input = z.object({ email: z.string().trim().toLowerCase().email().max(254), password: z.string().min(1).max(200) })

/** A password first; the second factor is the next page, and nothing is reachable before it. */
export async function signIn(_prev: LoginState, form: FormData): Promise<LoginState> {
  const parsed = Input.safeParse({ email: form.get('email'), password: form.get('password') })
  if (!parsed.success) return { problem: 'invalid' }
  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword(parsed.data)
  if (error) return { problem: 'failed' }
  redirect('/mfa')
}

export async function signOut(): Promise<void> {
  const supabase = await createClient()
  await supabase.auth.signOut({ scope: 'local' })
  redirect('/login')
}
