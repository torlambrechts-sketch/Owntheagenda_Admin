// Signs a seeded staff member in against the local stack (password, then TOTP) and prints an aal2 client.
// Usage in scripts: const sb = await signedIn('tor@orgpuls.no')
import { createClient } from '@supabase/supabase-js'
import { totp } from './totp.mjs'
import { DEV_PASSWORD, DEV_TOTP } from '../seed/dev-credentials.mjs'

export const LOCAL_URL = process.env.LOCAL_SUPABASE_URL ?? 'http://127.0.0.1:54421'
// the local stack's public anon key (the same for every local Supabase)
export const LOCAL_ANON = process.env.LOCAL_SUPABASE_ANON_KEY ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'

export async function signedIn(email) {
  const sb = createClient(LOCAL_URL, LOCAL_ANON, { auth: { persistSession: false, autoRefreshToken: false } })
  const { error } = await sb.auth.signInWithPassword({ email, password: DEV_PASSWORD })
  if (error) throw error
  const { data: f } = await sb.auth.mfa.listFactors()
  const factor = f.totp[0]
  const { error: e2 } = await sb.auth.mfa.challengeAndVerify({ factorId: factor.id, code: totp(DEV_TOTP) })
  if (e2) throw e2
  return sb
}
