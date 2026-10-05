/**
 * The platform's public Supabase settings. Both are public by design (the browser holds them); the
 * service role never reaches this app: the edge functions hold every secret.
 */
export function supabaseEnv(): { url: string; key: string } | { problem: string } {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim()
  if (!url || !/^https:\/\/[^\s/]+$/.test(url)) return { problem: 'NEXT_PUBLIC_SUPABASE_URL is missing or not an https origin' }
  if (!key) return { problem: 'NEXT_PUBLIC_SUPABASE_ANON_KEY is missing' }
  return { url, key }
}

/**
 * Supabase answers in well under a second. A call that does not (a wrong or paused project) must not hold
 * a request until Vercel turns it into a 504: after five seconds it fails, and the caller treats that as
 * a failed check (the middleware sends the visitor to the sign-in page).
 */
const TIMEOUT_MS = 5_000
export const boundedFetch: typeof fetch = (input, init) => {
  const limit = AbortSignal.timeout(TIMEOUT_MS)
  return fetch(input, { ...init, signal: init?.signal ? AbortSignal.any([init.signal, limit]) : limit })
}
