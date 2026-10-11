'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { handOverPagespeedKey, pagespeedRun } from '@/lib/pagespeed/run'

/**
 * Growth › Integrations › PageSpeed Insights (0073). The owner connects: an intake number (fresh second factor), the API key
 * handed to secret-intake, then a first measurement. «Measure now» asks pagespeed-run with the person's own token. Each
 * action parses its input; the database and the function decide (owner, fresh second factor, Campaigns › Add) again.
 */
type Fail = { ok: false; code: RpcCode | string; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const Intake = z.object({ intake_code: z.string().regex(/^[0-9a-f]{48}$/), expires_in: z.number() })
/** a Google API key: letters, digits, - and _, 30–80 characters (they start «AIza» today) */
const ApiKey = z.string().trim().regex(/^[A-Za-z0-9_-]{30,80}$/)
const done = () => revalidatePath('/growth')

export async function connectPagespeed(input: unknown): Promise<Res<{ pages: number }>> {
  const p = z.object({ key: ApiKey }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'bad_key' }
  const intake = await rpc('pagespeed_intake', {}, Intake)
  if (!intake.ok) return intake
  const handed = await handOverPagespeedKey(intake.data.intake_code, p.data.key)
  if (!handed.ok) return { ok: false, code: 'failed', detail: handed.code }
  const r = await pagespeedRun(null)
  done()
  if (!r.ok) return { ok: false, code: 'not_connected', detail: r.code }
  if (r.error === 'key_refused') return { ok: false, code: 'not_connected', detail: 'key_refused' }
  return { ok: true, pages: r.pages }
}

export async function measurePagespeed(input: { site: string | null }): Promise<Res<{ pages: number; error: string | null }>> {
  const p = z.object({ site: z.string().uuid().nullable() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await pagespeedRun(p.data.site)
  done()
  return r.ok ? { ok: true, pages: r.pages, error: r.error } : { ok: false, code: 'not_connected', detail: r.code }
}

export async function disconnectPagespeed(): Promise<Res> {
  const r = await rpc('pagespeed_disconnect', {}, z.unknown())
  done()
  return r.ok ? { ok: true } : r
}
