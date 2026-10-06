import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'

/**
 * Deals (Deals.dc.html): the board, the list, the forecast, the archive, the catalog and the drawer read
 * through the 0009/0010 functions. Every shape is parsed; nothing is cast.
 */
const num = z.coerce.number()
const id = z.string().uuid()
const iso = z.string()

export const Stage = z.object({ id, name: z.string(), ord: num.optional(), probability: num, rot_days: num.nullable() })
export const Pipeline = z.object({
  id,
  name: z.string(),
  ord: num,
  card_fields: z.array(z.string()),
  stages: z.array(Stage.extend({ open_deals: num })),
})
export type Pipeline = z.infer<typeof Pipeline>

export const Card = z.object({
  id,
  seq: num,
  title: z.string(),
  value: num,
  currency: z.string(),
  status: z.enum(['open', 'won', 'lost']),
  pipeline_id: id,
  stage_id: id,
  expected_close_date: z.string().nullable(),
  score: num.nullable(),
  source: z.string().nullable(),
  product: z.string().nullable(),
  labels: z.array(id),
  version: num,
  archived_at: iso.nullable(),
  owner_id: id.nullable(),
  owner: z.object({ name: z.string().nullable(), initials: z.string().nullable() }).nullable(),
  organization_id: id.nullable(),
  organization: z.string().nullable(),
  person_id: id.nullable(),
  person: z.string().nullable(),
  idle_days: num,
  rotting: z.boolean(),
  act: z.enum(['overdue', 'planned', 'none']),
  probability: num,
  won_at: iso.nullable(),
  lost_at: iso.nullable(),
  lost_reason: z.string().nullable(),
  created_at: iso,
  updated_at: iso,
  deleted_at: iso.nullable(),
})
export type Card = z.infer<typeof Card>

export const Board = z.object({
  stages: z.array(Stage),
  cards: z.array(Card),
  capacity: z.string().nullable(),
})
export type Board = z.infer<typeof Board>

export const List = z.object({ total: num, rows: z.array(Card) })
export type List = z.infer<typeof List>

export const Forecast = z.object({ from: z.string(), to: z.string(), cards: z.array(Card) })
export type Forecast = z.infer<typeof Forecast>

export const Item = z.object({
  id,
  item_id: id.nullable(),
  name: z.string(),
  quantity: num,
  unit_price: num,
  discount_pct: num,
  tax_rate: num,
  billing: z.enum(['one_off', 'recurring', 'installments']),
  billing_frequency: z.enum(['monthly', 'quarterly', 'semiannual', 'annual']).nullable(),
  cycles: num.nullable(),
  ord: num,
})
export type Item = z.infer<typeof Item>

export const Revenue = z.object({ mrr: num, arr: num, one_off: num, acv: num, tcv: num, lines: num })
export type Revenue = z.infer<typeof Revenue>

export const Detail = Card.extend({
  custom: z.record(z.string(), z.unknown()),
  pipeline: z.string().nullable(),
  person_detail: z.object({ id, name: z.string(), title: z.string().nullable(), email: z.string().nullable(), phone: z.string().nullable() }).nullable(),
  organization_detail: z.object({ id, name: z.string(), org_number: z.string().nullable(), city: z.string().nullable(), employees: num.nullable() }).nullable(),
  stages: z.array(z.object({ id, name: z.string(), probability: num, days: num.nullable() })).nullable(),
  participants: z.array(z.object({ id, name: z.string(), title: z.string().nullable() })),
  followers: z.array(z.object({ id, name: z.string().nullable(), initials: z.string().nullable() })),
  following: z.boolean(),
  items: z.array(Item),
  revenue: Revenue,
  value_source: z.enum(['manual', 'items']),
})
export type Detail = z.infer<typeof Detail>

export const HistoryRow = z.object({ at: iso, field: z.string(), old: z.unknown(), new: z.unknown(), source: z.string(), actor: z.string().nullable() })
export type HistoryRow = z.infer<typeof HistoryRow>

export const Note = z.object({ id, body: z.string(), pinned: z.boolean(), created_at: iso, author: z.string().nullable() })
export type Note = z.infer<typeof Note>

export const Activity = z.object({
  id,
  subject: z.string(),
  starts_at: iso.nullable(),
  done: z.boolean(),
  done_at: iso.nullable(),
  priority: z.enum(['high', 'medium', 'low']),
  type: z.object({ key: z.string(), name: z.string(), glyph: z.string() }).nullable(),
  owner: z.object({ name: z.string().nullable(), initials: z.string().nullable() }).nullable(),
})
export type Activity = z.infer<typeof Activity>
const Activities = z.object({ rows: z.array(Activity) })

export const Label = z.object({ id, name: z.string(), bg: z.string(), ink: z.string() })
export type Label = z.infer<typeof Label>

const FieldOption = z.union([z.string(), z.object({ key: z.string(), label: z.string().optional() })])
export const Field = z.object({
  id,
  key: z.string(),
  label: z.string(),
  type: z.string(),
  options: z.array(FieldOption),
  quality: z.enum(['optional', 'important', 'required']),
  from_stage_id: id.nullable(),
  readonly: z.boolean(),
})
export type Field = z.infer<typeof Field>

export const Staff = z.object({ id, name: z.string(), initials: z.string().nullable(), active: z.boolean() })
export type Staff = z.infer<typeof Staff>

export const LostReason = z.object({ id, label: z.string() })
export type LostReason = z.infer<typeof LostReason>

export const SavedView = z.object({ id, name: z.string(), query: z.record(z.string(), z.unknown()), shared: z.boolean(), mine: z.boolean() })
export type SavedView = z.infer<typeof SavedView>
export const Views = z.object({ views: z.array(SavedView), prefs: z.record(z.string(), z.unknown()) })
export type Views = z.infer<typeof Views>

export const CatalogItem = z.object({
  id,
  name: z.string(),
  code: z.string().nullable(),
  unit: z.string().nullable(),
  tax_rate: num,
  billing: z.enum(['one_off', 'recurring', 'installments']),
  billing_frequency: z.enum(['monthly', 'quarterly', 'semiannual', 'annual']).nullable(),
  color: z.string().nullable(),
  description: z.string().nullable(),
  prices: z.record(z.string(), num),
})
export type CatalogItem = z.infer<typeof CatalogItem>

export const ActivityType = z.object({ id, key: z.string(), name: z.string(), glyph: z.string(), active: z.boolean() })
export type ActivityType = z.infer<typeof ActivityType>

export const Deleted = z.object({ entity: z.string(), id, title: z.string(), deleted_at: iso, by: z.string().nullable(), purge_at: iso })
export type Deleted = z.infer<typeof Deleted>

export const PersonHit = z.object({ id, name: z.string(), title: z.string().nullable().optional(), city: z.string().nullable().optional(), org_number: z.string().nullable().optional() })
export type PersonHit = z.infer<typeof PersonHit>

// ---------------------------------------------------------------------------
// what the screen needs before anything is chosen
export async function loadDealsBase() {
  const [pipelines, labels, fields, staff, lostReasons, views, activityTypes] = await Promise.all([
    rpcOrThrow('pipelines_get', {}, z.array(Pipeline)),
    rpcOrThrow('labels_get', { p_entity: 'deal' }, z.array(Label)),
    rpcOrThrow('fields_get', { p_entity: 'deal' }, z.array(Field)),
    rpcOrThrow('staff_list', {}, z.array(Staff)),
    rpcOrThrow('lost_reasons_get', {}, z.array(LostReason)),
    rpcOrThrow('views_get', { p_screen: 'deals' }, Views),
    rpcOrThrow('activity_types_get', {}, z.array(ActivityType)),
  ])
  return { pipelines, labels, fields, staff: staff.filter((s) => s.active), lostReasons, views, activityTypes: activityTypes.filter((a) => a.active) }
}
export type DealsBase = Awaited<ReturnType<typeof loadDealsBase>>

export type Filter = { f: string; op: string; v?: unknown }

export const loadBoard = (pipeline: string, filters: Filter[], closed: boolean) =>
  rpc('deal_board', { p_pipeline: pipeline, p_query: { filters, closed } }, Board)

export const loadList = (query: { status?: string; q?: string; filters: Filter[]; sort: { f: string; dir: 'asc' | 'desc' }[]; archived?: boolean; trash?: boolean; pipeline_id?: string; limit?: number }) =>
  rpc('deal_list', { p_query: { limit: 500, ...query } }, List)

export const loadForecast = (pipeline: string, from: string, months: number, filters: Filter[]) =>
  rpc('deal_forecast', { p_pipeline: pipeline, p_from: from, p_months: months, p_query: { filters } }, Forecast)

export const loadCatalog = () => rpc('catalog_get', {}, z.array(CatalogItem))

export const loadDeleted = () => rpc('deleted_get', {}, z.array(Deleted))

/** The drawer: the deal, its changelog, notes and activities. */
export async function loadDeal(dealId: string) {
  const detail = await rpc('deal_detail', { p_id: dealId }, Detail)
  if (!detail.ok) return detail
  const [history, notes, activities] = await Promise.all([
    rpc('rec_history', { p_entity: 'deal', p_id: dealId, p_limit: 100 }, z.array(HistoryRow)),
    rpc('notes_list', { p_entity: 'deal', p_id: dealId }, z.array(Note)),
    rpc('activities_get', { p_query: { deal_id: dealId } }, Activities),
  ])
  return {
    ok: true as const,
    data: {
      detail: detail.data,
      history: history.ok ? history.data : [],
      notes: notes.ok ? notes.data : [],
      activities: activities.ok ? activities.data.rows : [],
    },
  }
}
export type DealBundle = { detail: Detail; history: HistoryRow[]; notes: Note[]; activities: Activity[] }

export const searchRecords = (entity: 'person' | 'organization', q: string) =>
  rpc('rec_list', { p_entity: entity, p_query: { q, limit: 6, sort: { f: 'name', dir: 'asc' } } }, z.object({ rows: z.array(PersonHit) }))
