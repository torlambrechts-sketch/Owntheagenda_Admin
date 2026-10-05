'use server'

import { z } from 'zod'
import { runCommand } from '@/lib/platform/command'
import { whoami } from '@/lib/platform/read'

export type TestResult = { ok: true; count: number } | { ok: false; error: string } | null

/** The connection's proof: Orgpuls' organisations, counted (orgs.list, orgs:read). */
export async function testConnection(): Promise<TestResult> {
  const me = await whoami()
  if (!me?.admin) return { ok: false, error: 'not_allowed' }
  const reply = await runCommand('orgs.list', { p_limit: 200 })
  if (!reply.ok) return { ok: false, error: (reply.error ?? 'failed').slice(0, 60) }
  const list = z.array(z.unknown()).safeParse(reply.result)
  return list.success ? { ok: true, count: list.data.length } : { ok: false, error: 'unexpected_reply' }
}
