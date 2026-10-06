'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { Enrichment, FeedData, ScoreModels } from '@/lib/data/feed'
import { COUNT_OPS, CRIT_FIELDS, ENRICH_FIELDS, GROUPS, PAYMENT_STATES } from '@/lib/data/feed-shared'

/** Server actions of the Feed screen: each parses its input and answers `{ ok } | { ok: false, code }`. */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode; detail?: string | null }

const uuid = z.string().uuid()
const bad = { ok: false as const, code: 'invalid' as const }
const done = () => revalidatePath('/feed')
const fail = (r: { code: RpcCode; detail: string | null }) => ({ ok: false as const, code: r.code, detail: r.detail })

// ---------------------------------------------------------------------------
// feed
export async function resolveCard(input: { id: string; how: 'task' | 'email' | 'done' | 'dismissed' }): Promise<Result> {
  const p = z.object({ id: uuid, how: z.enum(['task', 'email', 'done', 'dismissed']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('feed_resolve', { p_id: p.data.id, p_how: p.data.how }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

const Panel = z.object({
  id: uuid,
  title: z.string(),
  value: z.coerce.number(),
  currency: z.string(),
  organization: z.string().nullable(),
  person: z.string().nullable(),
  person_detail: z.object({ name: z.string(), title: z.string().nullable() }).nullable(),
})
const Acts = z.object({ rows: z.array(z.object({ id: uuid, subject: z.string(), done: z.boolean() })) })
export type PanelData = { id: string; title: string; value: number; currency: string; organization: string | null; person: string | null; role: string | null; acts: { id: string; subject: string; done: boolean }[] }

/** «Open»: the deal (deal_detail, 0009) and its first three activities. */
export async function openDeal(input: { id: string }): Promise<Result<{ panel: PanelData }>> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const [d, a] = await Promise.all([
    rpc('deal_detail', { p_id: p.data.id }, Panel),
    rpc('activities_get', { p_query: { deal_id: p.data.id } }, Acts),
  ])
  if (!d.ok) return fail(d)
  const x = d.data
  return {
    ok: true,
    panel: {
      id: x.id, title: x.title, value: x.value, currency: x.currency, organization: x.organization, person: x.person_detail?.name ?? x.person,
      role: x.person_detail?.title ?? null, acts: a.ok ? a.data.rows.slice(0, 3) : [],
    },
  }
}

/** «Open» on a card without a deal (cross-sell): the organization's first three activities. */
export async function openOrg(input: { id: string }): Promise<Result<{ acts: PanelData['acts'] }>> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const a = await rpc('activities_get', { p_query: { organization_id: p.data.id } }, Acts)
  if (!a.ok) return fail(a)
  return { ok: true, acts: a.data.rows.slice(0, 3) }
}

/** The one-time scope: which pipelines the feed covers (empty = all). The stage scope is kept as it is. */
export async function setScope(input: { pipelineIds: string[] }): Promise<Result> {
  const p = z.object({ pipelineIds: z.array(uuid).max(50) }).safeParse(input)
  if (!p.success) return bad
  const cur = await rpc('feed_get', { p_tab: 'follow_ups', p_filter: {} }, FeedData)
  if (!cur.ok) return fail(cur)
  const r = await rpc('feed_scope_set', { p_pipeline_ids: p.data.pipelineIds, p_stage_ids: cur.data.scope.stage_ids }, z.object({ ok: z.boolean() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// scoring
const days = z.number().int().min(1).max(365)
const Spec = z.discriminatedUnion('key', [
  z.object({ key: z.enum(['email.opened', 'email.replied', 'email.no_reply']), days }),
  z.object({ key: z.literal('participant_label'), label: uuid }),
  z.object({ key: z.literal('org_products'), op: z.enum(COUNT_OPS), n: z.number().int().min(0).max(100) }),
  z.object({ key: z.literal('org_payment'), state: z.enum(PAYMENT_STATES) }),
  z.object({ key: z.literal('source'), values: z.array(z.string().trim().min(1).max(80)).min(1).max(20) }),
  z.object({ key: z.enum(['value', 'org.employees']), min: z.number().min(0).max(1e12).nullable(), max: z.number().min(0).max(1e12).nullable() }),
  z.object({ key: z.enum(['org.city', 'org.fylke', 'org.industry']), text: z.string().trim().min(1).max(80) }),
])
export type CritSpec = z.infer<typeof Spec>

/** One criterion's condition: one AND group, as app.wf_match reads it. */
function conditionOf(s: CritSpec): Record<string, unknown>[] | null {
  switch (s.key) {
    case 'email.opened': case 'email.replied': case 'email.no_reply': return [{ f: s.key, v: s.days }]
    case 'participant_label': return [{ f: 'participant_label', v: s.label }]
    case 'org_products': return [{ f: 'org_products', op: s.op, v: s.n }]
    case 'org_payment': return [{ f: 'org_payment', v: s.state }]
    case 'source': return [{ f: 'source', op: 'in', v: s.values }]
    case 'value': case 'org.employees': {
      if (s.min === null && s.max === null) return null
      const base = s.key === 'value' ? { f: 'value' } : { rel: 'organization_id', f: 'employees' }
      return [...(s.min !== null ? [{ ...base, op: 'gte', v: s.min }] : []), ...(s.max !== null ? [{ ...base, op: 'lte', v: s.max }] : [])]
    }
    case 'org.city': case 'org.fylke': case 'org.industry':
      return [{ rel: 'organization_id', f: s.key.slice(4), op: 'contains', v: s.text }]
  }
}

async function modelById(modelId: string) {
  const r = await rpc('score_models_get', {}, ScoreModels)
  if (!r.ok) return r
  const m = r.data.models.find((x) => x.id === modelId)
  return m ? { ok: true as const, data: m } : { ok: false as const, code: 'not_found' as const, detail: null }
}

async function saveCriteria(modelId: string, criteria: { group: string; label: string | null; condition: unknown }[]): Promise<Result> {
  const r = await rpc('score_model_save', { p_id: modelId, p_values: {}, p_criteria: criteria }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function addCriterion(input: { modelId: string; group: string; label: string; spec: CritSpec }): Promise<Result> {
  const p = z.object({ modelId: uuid, group: z.enum(GROUPS), label: z.string().trim().min(1).max(120), spec: Spec }).safeParse(input)
  if (!p.success) return bad
  const m = await modelById(p.data.modelId)
  if (!m.ok) return fail(m)
  const f = CRIT_FIELDS.find((x) => x.key === p.data.spec.key)
  if (!f || !f.entities.includes(m.data.entity)) return bad
  const cond = conditionOf(p.data.spec)
  if (!cond) return bad
  const keep = m.data.criteria.map((c) => ({ group: c.group, label: c.label, condition: c.condition }))
  return saveCriteria(m.data.id, [...keep, { group: p.data.group, label: p.data.label, condition: [cond] }])
}

export async function removeCriterion(input: { modelId: string; criterionId: string }): Promise<Result> {
  const p = z.object({ modelId: uuid, criterionId: uuid }).safeParse(input)
  if (!p.success) return bad
  const m = await modelById(p.data.modelId)
  if (!m.ok) return fail(m)
  const keep = m.data.criteria.filter((c) => c.id !== p.data.criterionId).map((c) => ({ group: c.group, label: c.label, condition: c.condition }))
  return saveCriteria(m.data.id, keep)
}

export async function createModel(input: { name: string; entity: 'deal' | 'lead'; pipelineId: string | null }): Promise<Result<{ id: string }>> {
  const p = z.object({ name: z.string().trim().min(1).max(120), entity: z.enum(['deal', 'lead']), pipelineId: uuid.nullable() }).safeParse(input)
  if (!p.success) return bad
  const values = { name: p.data.name, entity: p.data.entity, ...(p.data.entity === 'deal' && p.data.pipelineId ? { pipeline_id: p.data.pipelineId } : {}) }
  const r = await rpc('score_model_save', { p_id: null, p_values: values, p_criteria: [] }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

/** A draft model made by mistake is removed (score_model_delete, 0027); an active one is refused. */
export async function deleteModel(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('score_model_delete', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function activateModel(input: { id: string; active: boolean }): Promise<Result> {
  const p = z.object({ id: uuid, active: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('score_model_activate', { p_id: p.data.id, p_active: p.data.active }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// enrichment
/** «Enrich N organizations with gaps»: the first hundred candidates enrichment_get names (candidate_ids, 0027). */
export async function requestBulkEnrich(): Promise<Result<{ requested: number }>> {
  const e = await rpc('enrichment_get', {}, Enrichment)
  if (!e.ok) return fail(e)
  const ids = e.data.candidate_ids.slice(0, 100)
  if (ids.length === 0) return { ok: true, requested: 0 }
  const r = await rpc('enrich_request', { p_ids: ids }, z.object({ requested: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, requested: r.data.requested }
}

export async function applyEnrich(input: { request: string; fields: string[] }): Promise<Result<{ applied: number }>> {
  const p = z.object({ request: uuid, fields: z.array(z.enum(ENRICH_FIELDS)).min(1).max(ENRICH_FIELDS.length) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('enrich_apply', { p_request: p.data.request, p_fields: p.data.fields }, z.object({ applied: z.array(z.string()) }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, applied: r.data.applied.length }
}

export async function dismissEnrich(input: { request: string }): Promise<Result> {
  const p = z.object({ request: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('enrich_dismiss', { p_request: p.data.request }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function decideLookup(input: { id: string; accept: boolean; organizationId: string | null }): Promise<Result> {
  const p = z.object({ id: uuid, accept: z.boolean(), organizationId: uuid.nullable() }).safeParse(input)
  if (!p.success) return bad
  const values = p.data.organizationId ? { organization_id: p.data.organizationId } : {}
  const r = await rpc('lookup_decide', { p_id: p.data.id, p_accept: p.data.accept, p_values: values }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}
