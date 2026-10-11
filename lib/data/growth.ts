import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { Segment, SenderDomains } from '@/lib/data/campaigns-shared'
import { GrowthFunnel, GrowthIntegrations, GrowthPages, GrowthScope, KeywordHistory } from '@/lib/growth/types'
import { SeoAlerts, SeoChanges, SeoClusters, SeoLinks, SeoOpps, SeoOverview, SeoPlan } from '@/lib/growth/seo'
import { Budget, Calendar, Deliverability, Experiments, Flows, Outcomes, Trial } from '@/lib/growth/playbook'
import { RANGE_DAYS, osloToday, scopeDay, type Scope } from '@/lib/growth/scope'

/**
 * Growth v2's reads (0073), each scoped the same way: the application, the period, the drilled day and hour, the channel
 * and the device. Parsed here; a refusal comes back as its code.
 */
function args(product: string, s: Scope) {
  return {
    p_product: product,
    p_days: RANGE_DAYS[s.range],
    p_day: scopeDay(s, osloToday()),
    p_hour: s.hour,
    p_channel: s.src,
    p_device: s.dev,
  }
}

export const loadScope = (product: string, s: Scope) => rpc('growth_scope', args(product, s), GrowthScope)

export const loadFunnel = (product: string, s: Scope, step: number) => rpc('growth_funnel', { ...args(product, s), p_step: step }, GrowthFunnel)

export const loadPages = (product: string, s: Scope, path: string | null) => rpc('growth_pages', { ...args(product, s), p_path: path }, GrowthPages)

export const loadKeywordHistory = (product: string, query: string, days: number) =>
  rpc('seo_keyword_history', { p_product: product, p_query: query, p_days: days === 1 ? 7 : days }, KeywordHistory)

export const loadIntegrations = (product: string) => rpc('growth_integrations', { p_product: product }, GrowthIntegrations)

// Growth › SEO, the suite (0074): one read per view
export const loadSeoOverview = (product: string) => rpc('seo_overview', { p_product: product }, SeoOverview)
export const loadSeoOpps = (product: string) => rpc('seo_opportunities', { p_product: product }, SeoOpps)
export const loadSeoClusters = (product: string) => rpc('seo_clusters', { p_product: product }, SeoClusters)
export const loadSeoPlan = (product: string, item: string | null) => rpc('seo_plan_get', { p_product: product, p_item: item }, SeoPlan)
export const loadSeoLinks = (product: string) => rpc('seo_links_get', { p_product: product }, SeoLinks)
export const loadSeoChanges = (product: string) => rpc('seo_changes_get', { p_product: product }, SeoChanges)
export const loadSeoAlerts = (product: string) => rpc('seo_alerts_get', { p_product: product }, SeoAlerts)

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
