import 'server-only'
import { rpc } from '@/lib/rpc'
import { GrowthFunnel, GrowthIntegrations, GrowthPages, GrowthScope, KeywordHistory } from '@/lib/growth/types'
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
