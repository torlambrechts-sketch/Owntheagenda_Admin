import type { DevTabProps } from '@/lib/data/dev-tabs'
import { RepoKit } from './delivery/RepoKit'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Development › Repo rules (DevClaude.dc.html, view «repo»): the repo starter kit, served as files to copy into a
 * product's repository, corrected where it contradicts the real rules (k floor 3 and default 5, npm, two repositories,
 * forward-only migrations, no inbound bearer token, no free-text dispatch, no production SQL for Claude) with each
 * correction listed. Sentral does not read the repository (no GitHub, PLAN.md), so it does not claim to know whether one
 * has drifted from these files (V-V3E-30). The file shown is ?file=.
 */
export async function RepoView({ searchParams }: DevTabProps) {
  return <RepoKit selected={one(searchParams.file)} />
}
