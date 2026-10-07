import 'server-only'
import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'

/**
 * The public unsubscribe page's two questions to mail-events (0060): who sent the mail (it changes nothing), and the
 * unsubscribe itself. The token in the address is the only authority; the answer never says more than the sender's name.
 */
const TOKEN = /^[A-Za-z0-9_-]{16,128}$/
const Peek = z.object({ found: z.boolean(), from_name: z.string().nullable().optional(), done: z.boolean().optional() })
const Done = z.object({ unsubscribed: z.boolean(), from_name: z.string().nullable().optional() })

async function call(body: object): Promise<unknown> {
  const env = supabaseEnv()
  if ('problem' in env) return null
  try {
    const res = await fetch(`${env.url}/functions/v1/mail-events`, {
      method: 'POST',
      headers: { apikey: env.key, 'content-type': 'application/json' },
      body: JSON.stringify(body),
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    })
    return await res.json().catch(() => null)
  } catch {
    return null
  }
}

export async function peekUnsubscribe(token: string): Promise<z.infer<typeof Peek> | null> {
  if (!TOKEN.test(token)) return { found: false }
  const r = Peek.safeParse(await call({ action: 'peek', token }))
  return r.success ? r.data : null
}

export async function doUnsubscribe(token: string): Promise<z.infer<typeof Done> | null> {
  if (!TOKEN.test(token)) return { unsubscribed: false }
  const r = Done.safeParse(await call({ action: 'unsubscribe', token }))
  return r.success ? r.data : null
}
