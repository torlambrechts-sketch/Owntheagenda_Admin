import { z } from 'zod'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { loadReleases } from '@/lib/data/dev-delivery'
import { ReleaseBoard } from './delivery/ReleaseBoard'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Development › Releases (DevHub.dc.html, tab «releases») on dev_releases_get (0080): a release is a named record per
 * product, not a deploy (PLAN: continuous deploys stay). Its checklist is computed from the CI run and the production
 * deployment of its commit; the manual items are signed by a named person; the changelog is release notes (0078), edited
 * here; «Record release» freezes the checklist and publishes the notes. The release shown is ?release=, else the newest open.
 */
export async function ReleasesView({ product, searchParams }: DevTabProps) {
  const id = z.string().uuid().safeParse(one(searchParams.release))
  const data = await loadReleases(id.success ? id.data : null)
  return <ReleaseBoard data={data} railProduct={product} />
}
