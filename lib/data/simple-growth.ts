import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { Pipeline } from './deals'
import { loadSegments } from './campaigns'
import { AdCampaigns, Overview, PROPOSAL_STAGE, RANGE_DAYS, Seo, Sequence, type GrowthRange } from './simple-growth-shared'

/**
 * What Sentral Simple › Growth reads (0058, 0059). Every read is scoped to the application the shell names and parsed
 * here; a refusal comes back as its code so a tab can show its no-access state.
 */
export const loadOverview = (product: string, range: GrowthRange) =>
  rpc('growth_overview', { p_product: product, p_days: RANGE_DAYS[range] }, Overview)

export const loadSeo = (product: string, range: GrowthRange) =>
  rpc('seo_get', { p_product: product, p_days: RANGE_DAYS[range] }, Seo)

export const loadAdCampaigns = (product: string) => rpc('ad_campaigns_get', { p_product: product }, AdCampaigns)

export const loadSequences = () => rpc('simple_sequences_get', {}, z.array(Sequence))

/** The stage «Deal moves to Proposal sent» names (the first by pipeline order), or null when there is none or Deals is closed. */
export async function loadProposalStage(): Promise<{ id: string; name: string } | null> {
  const r = await rpc('pipelines_get', {}, z.array(Pipeline), { quiet: true })
  if (!r.ok) return null
  for (const p of r.data) {
    const s = p.stages.find((x) => x.name.trim().toLowerCase() === PROPOSAL_STAGE)
    if (s) return { id: s.id, name: s.name }
  }
  return null
}

/** The lists «Send to list» offers: the segments the staff member may use (empty without Campaigns › See). */
export async function loadLists(): Promise<{ id: string; name: string }[]> {
  try {
    return (await loadSegments()).map((s) => ({ id: s.id, name: s.name }))
  } catch {
    return []
  }
}

/** Is the email provider connected (integrations_get; the Activate button says so while it is not)? */
export async function loadEmailConnected(): Promise<boolean> {
  const r = await rpc('integrations_get', {}, z.array(z.object({ provider: z.string(), status: z.string() })), { quiet: true })
  return r.ok && r.data.some((i) => i.provider === 'email' && i.status === 'connected')
}
