import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'

/** A product's shared secret from this project's Vault (0002), read once per function instance. */
const cache = new Map<string, string>()

export async function productSecret(svc: SupabaseClient, name: string): Promise<string> {
  const hit = cache.get(name)
  if (hit) return hit
  const { data, error } = await svc.rpc('product_secret', { p_name: name })
  if (error || typeof data !== 'string' || data.length < 32) return ''
  cache.set(name, data)
  return data
}
