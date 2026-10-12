import { z } from 'zod'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { loadReleases } from '@/lib/data/dev-delivery'
import { GateBoard } from './delivery/GateBoard'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Development › Release gate (DevClaude.dc.html, view «gate») on the same rows as Releases (dev_releases_get, 0080): a
 * verdict per release from CI's results and Vercel's deployments, and the manual sign-offs (preview checked, rollback
 * plan, …) by a named person. No release button: Sentral does not deploy, migrate or roll out (rule 3, PLAN).
 */
export async function GateView({ searchParams }: DevTabProps) {
  const id = z.string().uuid().safeParse(one(searchParams.release))
  const data = await loadReleases(id.success ? id.data : null)
  return <GateBoard data={data} />
}
