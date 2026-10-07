'use client'

import { useTranslations } from 'next-intl'
import { DIMS, FILTER_COLS, type Cond, type StoredDefinition } from '@/lib/data/insights-shared'
import type { Pickers } from '@/lib/data/insights'

export type { Pickers }

export type Rights = {
  meId: string
  meName: string
  see: boolean // Deals › See records: reports, goals and forecasts read deal-scope records
  others: boolean // Deals › See reports of others; without it a report counts the staff member's own records
  projects: boolean // Projects › See records, with the module on: the report entity «project» (INS-01)
  projectsOthers: boolean // Projects › See reports of others
  campaigns: boolean // Campaigns › See records, with the module on: the report entity «campaign» (INS-01)
  campaignsOthers: boolean // Campaigns › See reports of others
  exportRows: boolean
  configure: boolean // goals for a team or the company
  global: boolean // Global › See records: the product forecast reads subscriptions
}

const DIM_SET = new Set<string>(DIMS)
const COL_SET = new Set<string>(FILTER_COLS)

/** Labels for dimensions and filter columns from the messages; a custom field by its registry label. */
export function useLabels(custom: { key: string; label: string }[] = []) {
  const t = useTranslations('insights')
  const dim = (key: string | null | undefined): string => {
    if (!key) return t('none')
    if (key.startsWith('custom.')) return t('dims.custom', { label: custom.find((c) => c.key === key)?.label ?? key.slice(7) })
    if (DIM_SET.has(key)) return t(`dims.${key}` as 'dims.owner')
    if (COL_SET.has(key)) return t(`cols.${key}` as 'cols.value')
    return key
  }
  const cond = (c: Cond): string => {
    const v = c.op === 'empty' || c.op === 'notempty' ? '' : Array.isArray(c.v) ? c.v.join(', ') : typeof c.v === 'boolean' ? t(c.v ? 'filters.yes' : 'filters.no') : String(c.v ?? '')
    return t('filters.text', { field: dim(c.f), op: t(`ops.${c.op}` as 'ops.eq'), value: v }).trim()
  }
  return { dim, cond }
}

/** A tile's subtitle from its definition: the record type, the period it ran for, its dimension, and whose records it counts. */
export function useTileSub(rights: Rights, pickers: Pickers) {
  const t = useTranslations('insights')
  const { dim } = useLabels()
  return (def: StoredDefinition) => {
    const entity = (['deal', 'activity', 'lead', 'person', 'organization', 'project', 'campaign'] as const).find((e) => e === def.entity)
    const parts: string[] = [entity ? t(`entities.${entity}`) : def.entity]
    if (def.type === 'conversion' || (def.type === 'progress' && def.pipeline_id)) {
      const p = pickers.pipelines.find((x) => x.id === def.pipeline_id)
      if (p) parts.push(p.name)
    }
    const kind = def.period?.kind ?? (def.type === 'conversion' ? 'last_90' : null)
    const open = (def.filters ?? []).some((f) => typeof f === 'object' && f !== null && (f as Cond).f === 'status' && (f as Cond).op === 'eq' && (f as Cond).v === 'open')
    parts.push(kind && kind !== 'all' ? t(`sub.${kind}` as 'sub.month') : open ? t('sub.open') : t('sub.all'))
    if (def.type === 'progress') parts.push(t('sub.byStageReached'))
    else if (def.type === 'products') parts.push(t('sub.byProduct'))
    else if (def.group_by && def.type !== 'conversion') parts.push(t('sub.by', { dim: (def.entity === 'campaign' && def.group_by === 'type' ? t('dims.campaignType') : dim(def.group_by)).toLowerCase() }))
    const others = def.entity === 'project' ? rights.projectsOthers : def.entity === 'campaign' ? rights.campaignsOthers : rights.others
    if (rights.see && !others) parts.push(t('sub.own'))
    return parts.join(' · ')
  }
}

/** A template's name in the staff member's language; anyone else's dashboard by its own name. */
export function useDashboardName() {
  const t = useTranslations('insights')
  return (d: { name: string; template_role: string | null }) =>
    d.template_role && ['default', 'sales_manager', 'sales_rep', 'marketing'].includes(d.template_role) ? t(`templates.${d.template_role}` as 'templates.default') : d.name
}

export const btnTool = 'h-[34px] cursor-pointer rounded-10 border bg-transparent px-3 text-12.5 font-semibold disabled:cursor-default disabled:opacity-55'
export const card = 'rounded-20 border border-line bg-surface px-[18px] py-4'
