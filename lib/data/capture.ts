import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import {
  ChatDetail, ChatQueue, FormDetail, FormRow, Playbook, PlaybookStats, ProspectUsage, SavedFilter, Site, Submission, Visitor, Visitors, settingValue,
} from '@/lib/data/capture-shared'

/**
 * Loaders of Lead capture and Web visitors (0031). Forms and playbooks are read under campaigns:see, chats,
 * prospects and visitors under deals:see (spec §6, Q21); the page asks only for what the staff member may see.
 */

export const loadForms = () => rpcOrThrow('forms_get', {}, z.array(FormRow))
export const loadForm = (id: string) => rpc('form_get', { p_id: id }, FormDetail)
export const loadSubmissions = (id: string) => rpc('form_submissions', { p_id: id, p_limit: 8 }, z.array(Submission), { quiet: true })

export const loadPlaybooks = () => rpcOrThrow('playbooks_get', {}, z.array(Playbook))
export const loadPlaybookStats = (id: string) => rpc('playbook_stats', { p_id: id, p_days: 30 }, PlaybookStats)

export const loadChatQueue = () => rpcOrThrow('chats_queue', {}, ChatQueue)
export const loadChat = (id: string) => rpc('chat_get', { p_id: id }, ChatDetail)

export const loadSites = () => rpcOrThrow('web_sites_get', {}, z.array(Site))

export const loadProspectUsage = () => rpcOrThrow('prospect_usage', {}, ProspectUsage)
export const loadProspectFilters = async () =>
  (await rpcOrThrow('views_get', { p_screen: 'prospect_search' }, z.object({ views: z.array(SavedFilter) }))).views

export const loadVisitors = (days: number, filters: Record<string, string | boolean>) => rpcOrThrow('visitors_get', { p_days: days, p_filters: filters }, Visitors)
export const loadVisitor = (org: string, days: number) => rpc('visitor_get', { p_org_number: org, p_days: days }, Visitor, { quiet: true })

const SettingRow = z.object({ key: z.string(), default: z.string(), values: z.array(z.object({ scope_id: z.string(), value: z.string() })) })
/** The capture settings as the register holds them (settings_get, any staff member). */
export async function loadCaptureSettings() {
  const rows = await rpcOrThrow('settings_get', {}, z.array(SettingRow.passthrough()))
  const v = (k: string, d: string) => settingValue(rows, k) ?? d
  return {
    double_opt_in: v('double_opt_in', 'on'),
    form_tracking: v('form_tracking', 'on'),
    web_ident: v('web_ident', 'on'),
    widget_consent: v('widget_consent', 'off'),
    contact_rule: v('contact_rule', 'no_rule'),
  }
}
export type CaptureSettings = Awaited<ReturnType<typeof loadCaptureSettings>>

const Pipeline = z.object({ id: z.string().uuid(), name: z.string(), stages: z.array(z.object({ id: z.string().uuid(), name: z.string() })) })
/** Pipelines for «creates a deal» (deals:see; an empty list without it). */
export async function loadPipelines() {
  const r = await rpc('pipelines_get', {}, z.array(Pipeline.passthrough()), { quiet: true })
  return r.ok ? r.data.map((p) => ({ id: p.id, name: p.name, stages: p.stages.map((s) => ({ id: s.id, name: s.name })) })) : []
}

const Wf = z.object({ id: z.string().uuid(), name: z.string(), state: z.string() })
/** Sequences a form can enroll its lead in. */
export async function loadSequences() {
  const r = await rpc('workflows_get', { p_filter: { kind: 'sequence' } }, z.array(Wf.passthrough()), { quiet: true })
  return r.ok ? r.data.map((w) => ({ id: w.id, name: w.name, state: w.state })) : []
}

const CustomField = z.object({ entity: z.string(), key: z.string(), label: z.string(), type: z.string() })
/** Custom fields of people, organizations and leads a form field can save to. */
export async function loadCustomFields() {
  const r = await rpc('fields_get', { p_entity: null }, z.array(CustomField.passthrough()), { quiet: true })
  return r.ok ? r.data.filter((f) => ['person', 'organization', 'lead'].includes(f.entity) && f.type !== 'formula').map((f) => ({ map: `custom.${f.entity}.${f.key}`, label: f.label, entity: f.entity })) : []
}
