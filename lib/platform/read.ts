import 'server-only'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'

/** What the signed-in person is to the platform (public.admin_whoami). */
export const Whoami = z.object({ account: z.boolean(), aal2: z.boolean(), admin: z.boolean(), email: z.string().nullable() })
export type Whoami = z.infer<typeof Whoami>

export async function whoami(): Promise<Whoami | null> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('admin_whoami')
  if (error) return null
  const parsed = Whoami.safeParse(data)
  return parsed.success ? parsed.data : null
}

const Status = z.object({
  ok: z.literal(true),
  installations: z.array(z.object({ product: z.string(), name: z.string(), enabled: z.boolean().nullable(), host: z.string().nullable() })),
  accounts: z.number(),
  tenants_active: z.number(),
  events: z.number(),
  last_event_at: z.string().nullable(),
  by_kind: z.record(z.string(), z.number()),
  recent: z.array(z.object({ product: z.string(), kind: z.string(), received_at: z.string() })),
  commands: z.array(z.object({ at: z.string(), actor: z.string(), product: z.string(), command: z.string(), ok: z.boolean(), error: z.string().nullable() })),
})
export type Status = z.infer<typeof Status>

export async function platformStatus(): Promise<Status | null> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('platform_status')
  if (error) return null
  const parsed = Status.safeParse(data)
  return parsed.success ? parsed.data : null
}
