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
