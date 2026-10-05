import 'server-only'
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { supabaseEnv } from './env'

export async function createClient() {
  const env = supabaseEnv()
  if ('problem' in env) throw new Error(env.problem)
  const store = await cookies()
  return createServerClient(env.url, env.key, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (toSet) => {
        try {
          toSet.forEach(({ name, value, options }) => store.set(name, value, options))
        } catch {
          // a Server Component cannot set cookies; the middleware refreshes the session instead
        }
      },
    },
  })
}
