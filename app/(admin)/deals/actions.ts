'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import {
  loadBoard, loadCatalog, loadDeal, loadDeleted, loadForecast, loadList, searchRecords,
  type Board, type CatalogItem, type DealBundle, type Deleted, type Forecast, type List, type PersonHit,
} from '@/lib/data/deals'

/**
 * The Deals screen's server actions. Every input is parsed; every answer is `{ ok: true, … }` or
 * `{ ok: false, code }`, and the screen shows `common.errors.<code>`. The database checks rights again.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.string().uuid()
const cond = z.object({ f: z.string().regex(/^(custom\.)?[a-z_][a-z0-9_]{0,40}$/), op: z.enum(['eq', 'neq', 'in', 'contains', 'gt', 'gte', 'lt', 'lte', 'empty', 'notempty', 'has', 'within_days']), v: z.unknown().optional() })
// a filter is a condition or an OR of AND groups (app.filter_sql, 0023)
const filters = z.array(z.union([cond, z.object({ or: z.array(z.array(cond).max(20)).min(1).max(10) })])).max(20)
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const okish = z.unknown()

// ---------------------------------------------------------------------------
// reads
export async function fetchBoard(input: unknown): Promise<Res<{ board: Board }>> {
  const p = z.object({ pipeline: uuid, filters, closed: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await loadBoard(p.data.pipeline, p.data.filters, p.data.closed)
  return r.ok ? { ok: true, board: r.data } : fail(r)
}

export async function fetchList(input: unknown): Promise<Res<{ list: List }>> {
  const p = z.object({
    status: z.enum(['open', 'won', 'lost', 'all']).optional(),
    filters,
    sort: z.array(z.object({ f: z.enum(['seq', 'title', 'organization', 'value', 'stage', 'owner', 'expected_close_date', 'score', 'source', 'labels']), dir: z.enum(['asc', 'desc']) })).max(10),
    archived: z.boolean().optional(),
    trash: z.boolean().optional(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await loadList(p.data)
  return r.ok ? { ok: true, list: r.data } : fail(r)
}

export async function fetchForecast(input: unknown): Promise<Res<{ forecast: Forecast }>> {
  const p = z.object({ pipeline: uuid, from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), months: z.number().int().min(1).max(12), filters }).safeParse(input)
  if (!p.success) return bad
  const r = await loadForecast(p.data.pipeline, p.data.from, p.data.months, p.data.filters)
  return r.ok ? { ok: true, forecast: r.data } : fail(r)
}

export async function fetchArchive(): Promise<Res<{ archived: List['rows']; deleted: List['rows']; by: Deleted[] }>> {
  const [a, d, by] = await Promise.all([
    loadList({ filters: [], sort: [{ f: 'value', dir: 'desc' }], archived: true }),
    loadList({ filters: [], sort: [{ f: 'value', dir: 'desc' }], trash: true }),
    loadDeleted(),
  ])
  if (!a.ok) return fail(a)
  // the trash needs the delete right; without it the section is empty rather than an error
  return { ok: true, archived: a.data.rows, deleted: d.ok ? d.data.rows.filter((x) => Date.now() - new Date(x.deleted_at ?? 0).getTime() < 30 * 86_400_000) : [], by: by.ok ? by.data.filter((x) => x.entity === 'deal') : [] }
}

export async function fetchCatalog(): Promise<Res<{ catalog: CatalogItem[] }>> {
  const r = await loadCatalog()
  return r.ok ? { ok: true, catalog: r.data } : fail(r)
}

export async function fetchDeal(input: unknown): Promise<Res<{ deal: DealBundle }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await loadDeal(p.data)
  return r.ok ? { ok: true, deal: r.data } : fail(r)
}

export async function searchPeople(input: unknown): Promise<Res<{ rows: PersonHit[] }>> {
  const p = z.object({ entity: z.enum(['person', 'organization']), q: z.string().max(100) }).safeParse(input)
  if (!p.success) return bad
  const r = await searchRecords(p.data.entity, p.data.q)
  return r.ok ? { ok: true, rows: r.data.rows } : fail(r)
}

// ---------------------------------------------------------------------------
// writes
export async function createDeal(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({ title: z.string().trim().min(1).max(200), pipeline_id: uuid, stage_id: uuid.optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_create', { p_values: p.data }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

const Missing = z.array(z.object({ key: z.string(), label: z.string(), type: z.string(), options: z.array(z.unknown()) }))
export type MissingField = z.infer<typeof Missing>[number]

/** Moves a deal; when fields are required from the target stage the answer lists them instead. */
export async function moveDeal(input: unknown): Promise<Res<{ missing: MissingField[] | null }>> {
  const p = z.object({ id: uuid, stage: uuid, version: z.number().int().optional(), fields: z.record(z.string(), z.unknown()).optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_move', { p_id: p.data.id, p_stage: p.data.stage, p_version: p.data.version ?? null, p_fields: p.data.fields ?? null }, z.object({ id: uuid, missing: Missing.optional() }))
  return r.ok ? { ok: true, missing: r.data.missing ?? null } : fail(r)
}

/** Many deals to one stage (the list's selection bar): each through deal_move; held back ones are counted. */
export async function moveDeals(input: unknown): Promise<Res<{ moved: number; held: number }>> {
  const p = z.object({ ids: z.array(uuid).min(1).max(200), stage: uuid }).safeParse(input)
  if (!p.success) return bad
  let moved = 0, held = 0
  for (const id of p.data.ids) {
    const r = await rpc('deal_move', { p_id: id, p_stage: p.data.stage }, z.object({ id: uuid, missing: Missing.optional() }))
    if (!r.ok) return fail(r)
    if (r.data.missing) held++
    else moved++
  }
  return { ok: true, moved, held }
}

export async function setStatus(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, status: z.enum(['open', 'won', 'lost']), reason: z.string().max(200).optional(), comment: z.string().max(10000).optional(), version: z.number().int().optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_status', { p_id: p.data.id, p_status: p.data.status, p_reason: p.data.reason ?? null, p_comment: p.data.comment ?? null, p_version: p.data.version ?? null }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function archiveDeals(input: unknown): Promise<Res<{ changed: number }>> {
  const p = z.object({ ids: z.array(uuid).min(1).max(500), archived: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_archive', { p_ids: p.data.ids, p_archived: p.data.archived }, z.object({ changed: z.coerce.number() }))
  return r.ok ? { ok: true, changed: r.data.changed } : fail(r)
}

export async function deleteDeals(input: unknown): Promise<Res<{ deleted: number }>> {
  const p = z.object({ ids: z.array(uuid).min(1).max(500) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_delete', { p_entity: 'deal', p_ids: p.data.ids }, z.object({ deleted: z.coerce.number() }))
  return r.ok ? { ok: true, deleted: r.data.deleted } : fail(r)
}

export async function restoreDeals(input: unknown): Promise<Res> {
  const p = z.object({ ids: z.array(uuid).min(1).max(500) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_restore', { p_entity: 'deal', p_ids: p.data.ids }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function duplicateDeal(input: unknown): Promise<Res<{ id: string }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_duplicate', { p_id: p.data }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

const dealValues = z.object({
  value: z.number().min(0).max(1e12).optional(),
  owner_id: uuid.optional(),
  labels: z.array(uuid).max(50).optional(),
  expected_close_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  person_id: uuid.nullable().optional(),
  organization_id: uuid.nullable().optional(),
  custom: z.record(z.string().regex(/^[a-z][a-z0-9_]{1,40}$/), z.unknown()).optional(),
  value_source: z.enum(['manual', 'items']).optional(),
}).strict()

export async function saveDeal(input: unknown): Promise<Res<{ version: number }>> {
  const p = z.object({ id: uuid, values: dealValues, version: z.number().int().optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_save', { p_entity: 'deal', p_id: p.data.id, p_values: p.data.values, p_version: p.data.version ?? null }, z.object({ version: z.coerce.number() }))
  return r.ok ? { ok: true, version: r.data.version } : fail(r)
}

export async function bulkOwner(input: unknown): Promise<Res<{ updated: number }>> {
  const p = z.object({ ids: z.array(uuid).min(1).max(500), owner_id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_bulk', { p_entity: 'deal', p_ids: p.data.ids, p_values: { owner_id: p.data.owner_id } }, z.object({ updated: z.coerce.number() }))
  return r.ok ? { ok: true, updated: r.data.updated } : fail(r)
}

export async function saveItem(input: unknown): Promise<Res> {
  const p = z.object({
    deal: uuid,
    id: uuid.nullable(),
    values: z.object({ item_id: uuid.optional(), quantity: z.number().gt(0).max(1e7).optional(), discount_pct: z.number().min(0).max(100).optional() }).strict(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_item_save', { p_deal: p.data.deal, p_id: p.data.id, p_values: p.data.values }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function deleteItem(input: unknown): Promise<Res> {
  const p = z.object({ deal: uuid, id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_item_delete', { p_deal: p.data.deal, p_id: p.data.id }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function setParticipant(input: unknown): Promise<Res> {
  const p = z.object({ deal: uuid, person: uuid, on: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('participant_set', { p_deal: p.data.deal, p_person: p.data.person, p_on: p.data.on }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function setFollow(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, on: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('follow_set', { p_entity: 'deal', p_id: p.data.id, p_on: p.data.on }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function saveNote(input: unknown): Promise<Res> {
  const p = z.object({ deal: uuid, body: z.string().trim().min(1).max(10000) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('note_save', { p_entity: 'deal', p_id: p.data.deal, p_note: null, p_body: p.data.body }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function saveActivity(input: unknown): Promise<Res> {
  const p = z.object({ deal: uuid, type_id: uuid, subject: z.string().trim().min(1).max(200), starts_at: z.string().datetime({ offset: true }).nullable() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_save', { p_entity: 'activity', p_id: null, p_values: { deal_id: p.data.deal, type_id: p.data.type_id, subject: p.data.subject, starts_at: p.data.starts_at } }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function completeActivity(input: unknown): Promise<Res<{ prompt: boolean }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('activity_done', { p_id: p.data, p_done: true }, z.object({ prompt: z.boolean() }))
  return r.ok ? { ok: true, prompt: r.data.prompt } : fail(r)
}

export async function saveView(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({ name: z.string().trim().min(1).max(80), query: z.object({ conds: z.array(z.object({ field: z.string(), op: z.string(), val: z.string(), join: z.enum(['and', 'or']).optional() })).max(20) }) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('view_save', { p_id: null, p_screen: 'deals', p_name: p.data.name, p_query: p.data.query, p_shared: false }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function setPref(input: unknown): Promise<Res> {
  const p = z.object({ key: z.enum(['show_closed', 'list_cols', 'list_sort', 'card_fields', 'pipeline']), value: z.unknown() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('pref_set', { p_screen: 'deals', p_key: p.data.key, p_value: p.data.value ?? null }, okish)
  return r.ok ? { ok: true } : fail(r)
}

export async function logExport(input: unknown): Promise<Res> {
  const p = z.object({ rows: z.number().int().min(0).max(100000), format: z.enum(['csv', 'xlsx']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('export_log', { p_entity: 'deal', p_rows: p.data.rows, p_format: p.data.format, p_scope: 'list' }, okish)
  return r.ok ? { ok: true } : fail(r)
}

/** «Convert back to lead» (deal_to_lead): a lead from the deal; its notes and activities follow, the deal is archived. */
export async function convertToLead(input: unknown): Promise<Res<{ leadId: string }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('deal_to_lead', { p_id: p.data }, z.object({ lead_id: uuid }))
  return r.ok ? { ok: true, leadId: r.data.lead_id } : fail(r)
}

/** A catalog item with its NOK price (Products › ＋ Product). */
export async function createProduct(input: unknown): Promise<Res> {
  const p = z.object({ name: z.string().trim().min(1).max(120), price: z.number().min(0).max(1e9).nullable() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_save', { p_entity: 'catalog_item', p_id: null, p_values: { name: p.data.name } }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  if (p.data.price !== null) {
    const pr = await rpc('catalog_price_set', { p_item: r.data.id, p_currency: 'NOK', p_price: p.data.price }, okish)
    if (!pr.ok) return fail(pr)
  }
  return { ok: true }
}
