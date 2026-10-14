import 'server-only'
import { z } from 'zod'
import type { CommandProduct, ProductCommand } from '@/supabase/functions/_shared/commands.ts'
import { supabaseEnv } from '@/lib/supabase/env'
import { createClient } from '@/lib/supabase/server'

/**
 * A command to a product (orgpuls, leaderpact: _shared/commands.ts), as the signed-in admin, through the product-command edge function: it holds
 * the token secret, signs a two-minute token for this one command and writes the audit. The app only
 * forwards the admin's own session, so nothing here can act as anyone else.
 */
const Reply = z.object({ ok: z.boolean(), error: z.string().optional(), result: z.unknown().optional() })
export type CommandReply = z.infer<typeof Reply>

export async function runCommand<P extends CommandProduct>(product: P, command: ProductCommand<P>, args: Record<string, unknown> = {}): Promise<CommandReply> {
  const env = supabaseEnv()
  if ('problem' in env) return { ok: false, error: 'not_configured' }
  const supabase = await createClient()
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  if (!token) return { ok: false, error: 'not_signed_in' }
  try {
    const res = await fetch(`${env.url}/functions/v1/product-command`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, apikey: env.key, 'content-type': 'application/json' },
      body: JSON.stringify({ product, command, args }),
      cache: 'no-store',
      signal: AbortSignal.timeout(25_000),
    })
    const parsed = Reply.safeParse(await res.json().catch(() => null))
    return parsed.success ? parsed.data : { ok: false, error: `http_${res.status}` }
  } catch {
    return { ok: false, error: 'unreachable' }
  }
}
