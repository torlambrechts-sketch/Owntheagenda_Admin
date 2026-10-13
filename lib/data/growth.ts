import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { Segment, SenderDomains } from '@/lib/data/campaigns-shared'
import { GrowthFunnel, GrowthIntegrations, GrowthPages, GrowthScope, KeywordHistory } from '@/lib/growth/types'
import { SeoAlerts, SeoChanges, SeoClusters, SeoLinks, SeoOpps, SeoOverview, SeoPlan } from '@/lib/growth/seo'
import { Budget, Calendar, Deliverability, Experiments, Flows, Outcomes, Trial } from '@/lib/growth/playbook'
import { GrowthAds } from '@/lib/growth/ads'
import { RANGE_DAYS, osloToday, scopeDay, type Scope } from '@/lib/growth/scope'

/**
 * Growth v2's reads (0073), each scoped the same way: the application, the period, the drilled day and hour, the channel
 * and the device. Parsed here; a refusal comes back as its code.
 */
function args(product: string, s: Scope, site: string | null) {
  return {
    p_product: product,
    p_days: RANGE_DAYS[s.range],
    p_day: scopeDay(s, osloToday()),
    p_hour: s.hour,
    p_channel: s.src,
    p_device: s.dev,
    ...onSite(site),
  }
}

/** one of the application's sites (0089), sent only when one is chosen: without it a read takes all of them */
const onSite = (site: string | null) => (site ? { p_site: site } : {})

/** the application's sites, for the site picker (0089) */
export const loadSites = (product: string) => rpc('growth_sites_list', { p_product: product }, z.array(z.object({ id: z.string().uuid(), hostname: z.string() })))

export const loadScope = (product: string, s: Scope, site: string | null = null) => rpc('growth_scope', args(product, s, site), GrowthScope)

export const loadFunnel = (product: string, s: Scope, step: number, site: string | null = null) => rpc('growth_funnel', { ...args(product, s, site), p_step: step }, GrowthFunnel)

export const loadPages = (product: string, s: Scope, path: string | null, site: string | null = null) => rpc('growth_pages', { ...args(product, s, site), p_path: path }, GrowthPages)

export const loadKeywordHistory = (product: string, query: string, days: number, site: string | null = null) =>
  rpc('seo_keyword_history', { p_product: product, p_query: query, p_days: days === 1 ? 7 : days, ...onSite(site) }, KeywordHistory)

export const loadIntegrations = (product: string) => rpc('growth_integrations', { p_product: product }, GrowthIntegrations)

// Growth › SEO, the suite (0074): one read per view
export const loadSeoOverview = (product: string, site: string | null = null) => rpc('seo_overview', { p_product: product, ...onSite(site) }, SeoOverview)
export const loadSeoOpps = (product: string, site: string | null = null) => rpc('seo_opportunities', { p_product: product, ...onSite(site) }, SeoOpps)
export const loadSeoClusters = (product: string, site: string | null = null) => rpc('seo_clusters', { p_product: product, ...onSite(site) }, SeoClusters)
export const loadSeoPlan = (product: string, item: string | null, site: string | null = null) => rpc('seo_plan_get', { p_product: product, p_item: item, ...onSite(site) }, SeoPlan)
export const loadSeoLinks = (product: string, site: string | null = null) => rpc('seo_links_get', { p_product: product, ...onSite(site) }, SeoLinks)
export const loadSeoChanges = (product: string, site: string | null = null) => rpc('seo_changes_get', { p_product: product, ...onSite(site) }, SeoChanges)
export const loadSeoAlerts = (product: string, site: string | null = null) => rpc('seo_alerts_get', { p_product: product, ...onSite(site) }, SeoAlerts)

// Growth › the playbook (0076): campaigns' and email's further views
export const loadOutcomes = (product: string, model: 'first' | 'last') => rpc('growth_outcomes', { p_product: product, p_model: model }, Outcomes)
export const loadBudget = (product: string) => rpc('growth_budget', { p_product: product }, Budget)
export const loadExperiments = (product: string) => rpc('growth_experiments_get', { p_product: product }, Experiments)
export const loadCalendar = (product: string) => rpc('growth_calendar', { p_product: product }, Calendar)
export const loadTrial = (product: string) => rpc('growth_trial', { p_product: product }, Trial)
export const loadFlows = () => rpc('growth_flows', {}, Flows)
export const loadDeliverability = (product: string) => rpc('growth_deliverability', { p_product: product }, Deliverability)
export const loadAudiences = () => rpc('segments_get', {}, z.array(Segment))
export const loadSenderDomains = () => rpc('sender_domains_get', {}, SenderDomains)

// Growth › the ad platforms (0077): connections, accounts, campaigns and ads with their figures
export const loadAds = (product: string) => rpc('growth_ads', { p_product: product }, GrowthAds)
