import 'server-only'
import { z } from 'zod'
import { supabaseEnv } from '@/lib/supabase/env'
import { tokenOk } from './logic'

/**
 * The public CSAT page's two questions to the csat function (0081): is the token still open (it changes nothing), and the
 * answer itself. The token in the address is the only authority; it travels to the function in a POST body. `null` is «not
 * reachable now» (a 5xx, a timeout, an answer of the wrong shape): the page then says «try again», never «already used».
 */
const Peek = z.object({ open: z.boolean(), from_name: z.string().nullable() })
const Answer = z.object({ recorded: z.boolean() })

async function call(body: object): Promise<unknown> {
  const env = supabaseEnv()
  if ('problem' in env) return null
  try {
    const res = await fetch(`${env.url}/functions/v1/csat`, {
      method: 'POST',
      headers: { apikey: env.key, 'content-type': 'application/json' },
      body: JSON.stringify(body),
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    })
    if (!res.ok) return null
    return await res.json().catch(() => null)
  } catch {
    return null
  }
}

export async function peekCsat(token: string): Promise<z.infer<typeof Peek> | null> {
  if (!tokenOk(token)) return { open: false, from_name: null }
  const r = Peek.safeParse(await call({ action: 'peek', token }))
  return r.success ? r.data : null
}

/** recorded, closed (spent, expired or unknown) or unavailable */
export async function answerCsat(token: string, score: number): Promise<'recorded' | 'closed' | 'unavailable'> {
  if (!tokenOk(token) || !Number.isInteger(score) || score < 1 || score > 5) return 'closed'
  const r = Answer.safeParse(await call({ action: 'answer', token, score }))
  if (!r.success) return 'unavailable'
  return r.data.recorded ? 'recorded' : 'closed'
}
