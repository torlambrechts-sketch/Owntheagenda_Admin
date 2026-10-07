import 'server-only'
import { createClient } from '@/lib/supabase/server'
import { sign, signerReady, type SignRequest, type Signed } from './sign'

/**
 * The staff member's own access token, from the session cookie the middleware keeps fresh. The storage-sign function checks
 * it with Auth (signature, session, aal2) before it asks the database, so the cookie's word alone signs nothing.
 */
export async function accessToken(): Promise<string | null> {
  const supabase = await createClient()
  const { data } = await supabase.auth.getSession()
  return data.session?.access_token ?? null
}

/** Sign one upload or download for the signed-in staff member (see lib/storage/sign.ts). */
export async function signForMe(request: SignRequest): Promise<Signed> {
  const token = await accessToken()
  if (!token) return { ok: false, code: 'not_signed_in', detail: null }
  return sign(token, request)
}

/** Whether upload and download work now: the signer answers and its private buckets exist. */
export async function storageReady(): Promise<boolean> {
  return signerReady(await accessToken())
}
