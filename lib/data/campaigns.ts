import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import {
  CampaignDetail, CampaignList, Compare, ConsentLog, Hygiene, Recipients, Recommendation, Segment, SenderDomains, StatusSummary, Suppression, Template,
  type CampaignType, type RecipientState,
} from '@/lib/data/campaigns-shared'

/**
 * Loaders of the Campaigns route (0037; consent and suppressions 0031). Every read is under campaigns:see; the
 * figures of colleagues' campaigns follow the database's reports rule (V-P6C-19), which answers stats null.
 */

export const loadCampaigns = (type: CampaignType | null) =>
  rpcOrThrow('campaigns_get', { p_query: type ? { type, limit: 200 } : { limit: 200 } }, CampaignList)
export const loadCampaign = (id: string) => rpc('campaign_get', { p_id: id }, CampaignDetail, { quiet: true })
export const loadCompare = (ids: string[] | null, type: CampaignType | null) =>
  rpc('campaigns_compare', { p_ids: ids && ids.length ? ids : null, p_type: type }, Compare, { quiet: true })
export const loadRecipients = (id: string, state: RecipientState | null) =>
  rpc('campaign_recipients', { p_id: id, p_state: state, p_limit: 200 }, Recipients, { quiet: true })

export const loadTemplates = () => rpcOrThrow('marketing_templates_get', {}, z.array(Template))
export const loadSegments = () => rpcOrThrow('segments_get', {}, z.array(Segment))
export const loadDomains = () => rpcOrThrow('sender_domains_get', {}, SenderDomains)
export const loadRecommendations = () => rpcOrThrow('deliverability_recommendations', {}, z.array(Recommendation))
export const loadHygiene = () => rpcOrThrow('hygiene_candidates', {}, Hygiene)
export const loadStatusSummary = () => rpcOrThrow('marketing_status_summary', {}, StatusSummary)
export const loadConsentLog = (before: number | null) => rpcOrThrow('consent_log', { p_limit: 8, p_before: before }, ConsentLog)
export const loadSuppressions = (q: string | null) => rpc('suppressions_get', { p_q: q }, z.array(Suppression), { quiet: true })

const Coupon = z.object({ code: z.string(), description: z.string().nullable(), percent: z.coerce.number().nullable(), months: z.coerce.number().nullable() })
/** The active coupons a promotion may carry (campaign_coupons, campaigns:see; R-CAMPAIGNS-02). */
export const loadCoupons = () => rpcOrThrow('campaign_coupons', {}, z.array(Coupon))

const TemplateVersion = z.object({ version: z.coerce.number(), subject: z.string(), created_at: z.string(), by: z.string().nullable() })
export type TemplateVersion = z.infer<typeof TemplateVersion>
/** A marketing template's saved versions, newest first (R-CAMPAIGNS-05). */
export const loadTemplateVersions = (id: string) => rpc('marketing_template_versions', { p_id: id }, z.array(TemplateVersion), { quiet: true })

const PersonOption = z.object({ id: z.string().uuid(), name: z.string(), email: z.string().nullable() })
export type PersonOption = z.infer<typeof PersonOption>
/** People with an address, to merge a preview or a test with (deals:see; an empty list without it). */
export async function loadPeopleOptions() {
  const r = await rpc('rec_list', { p_entity: 'person', p_query: { limit: 200, sort: { f: 'name', dir: 'asc' }, filters: [{ f: 'email', op: 'notempty' }] } },
    z.object({ rows: z.array(PersonOption.passthrough()) }), { quiet: true })
  return r.ok ? r.data.rows.map((p) => ({ id: p.id, name: p.name, email: p.email })) : []
}

const SettingRow = z.object({ key: z.string(), default: z.string(), values: z.array(z.object({ scope_id: z.string(), value: z.string() })) })
/** The setting that decides whether deleting asks for a reason (D-12). */
export async function loadReasonRequired() {
  const r = await rpc('settings_get', {}, z.array(SettingRow.passthrough()), { quiet: true })
  if (!r.ok) return false
  const s = r.data.find((x) => x.key === 'typed_reason')
  const v = s ? (s.values.find((x) => x.scope_id === '')?.value ?? s.default) : 'off'
  return v === 'on'
}
