import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import { ActivityType, Label, Pipeline } from '@/lib/data/deals'
import { FEED_TABS, type FeedTab } from '@/lib/data/feed-shared'

/**
 * Feed (Feed.dc.html): the Feed, Scoring models and Enrichment tabs read through the 0022 functions. A card
 * is a kind and its parameters, never prose; the screen words it from messages. Every shape is parsed.
 */
const num = z.coerce.number()
const id = z.string().uuid()

export const FeedCard = z.object({
  id,
  kind: z.string(),
  tone: z.string(),
  params: z.record(z.string(), z.unknown()),
  created_at: z.string(),
  deal: z.object({
    id,
    title: z.string(),
    value: num.nullable(),
    currency: z.string().nullable(),
    stage_id: id.nullable(),
    stage: z.string().nullable(),
    score: num.nullable(),
    person: z.string().nullable(),
    person_id: id.nullable(),
    owner_id: id.nullable().optional(),
    owner: z.string().nullable().optional(),
  }).nullable(),
  organization: z.object({ id, name: z.string(), city: z.string().nullable() }).nullable(),
})
export type FeedCard = z.infer<typeof FeedCard>

export const FeedData = z.object({
  counts: z.record(z.string(), num).nullable().transform((c) => c ?? {}),
  scope: z.object({ pipeline_ids: z.array(id), stage_ids: z.array(id) }),
  ai_scoring: z.boolean(),
  cards: z.array(FeedCard),
})
export type FeedData = z.infer<typeof FeedData>

const DoneOf = z.object({ done: num, total: num })
export const Progress = z.object({
  done_today: num,
  today: z.object({ all: DoneOf, task: DoneOf, call: DoneOf }),
  month: z.object({ new_deals: num, won_count: num, won_value: num, forecast: num }),
})
export type Progress = z.infer<typeof Progress>

const Mailboxes = z.object({ mailboxes: z.array(z.object({ status: z.string(), can_reply: z.boolean() })) })

export const Criterion = z.object({
  id,
  group: z.enum(['high', 'slight', 'negative']),
  ord: num,
  label: z.string().nullable(),
  condition: z.array(z.unknown()),
})
export type Criterion = z.infer<typeof Criterion>

export const ScoreModel = z.object({
  id,
  name: z.string(),
  entity: z.enum(['deal', 'lead']),
  pipeline_id: id.nullable(),
  pipeline: z.string().nullable(),
  state: z.enum(['draft', 'active']),
  base: num,
  points: z.object({ high: num, slight: num, negative: num }),
  scored: num,
  criteria: z.array(Criterion),
})
export type ScoreModel = z.infer<typeof ScoreModel>
export const ScoreModels = z.object({ limit: num.nullable(), models: z.array(ScoreModel) })

export const ScorePreview = z.object({
  score: num,
  hits: z.array(z.object({ criterion: id, group: z.string(), label: z.string().nullable(), points: num })),
})
export type ScorePreview = z.infer<typeof ScorePreview>

export const EnrichRequest = z.object({
  id,
  organization_id: id,
  organization: z.string(),
  state: z.enum(['requested', 'ready', 'failed']),
  error: z.string().nullable(),
  created_at: z.string(),
  fields: z.array(z.object({ field: z.string(), current: z.unknown(), proposed: z.unknown(), writable: z.boolean() })),
})
export type EnrichRequest = z.infer<typeof EnrichRequest>

export const Lookup = z.object({
  id,
  thread_id: id.nullable(),
  from: z.string(),
  name: z.string().nullable(),
  domain: z.string(),
  proposed: z.record(z.string(), z.unknown()),
  organization: z.object({ id, name: z.string() }).nullable(),
  subject: z.string().nullable().optional(),
  at: z.string().optional(),
})
export type Lookup = z.infer<typeof Lookup>

export const Enrichment = z.object({
  candidates: num,
  candidate_ids: z.array(id).default([]),
  contact_data: z.string().nullable(),
  credits: z.object({ used_month: num, limit: num.nullable() }),
  requests: z.array(EnrichRequest),
  lookups: z.array(Lookup),
})
export type Enrichment = z.infer<typeof Enrichment>

export const PreviewRecord = z.object({ id, title: z.string() })
export type PreviewRecord = z.infer<typeof PreviewRecord>

// ---------------------------------------------------------------------------
export async function loadFeed(tab: FeedTab, filter: { stage_ids?: string[]; kinds?: string[]; score_min?: number; score_max?: number }) {
  const [feed, progress, pipelines, types, mail] = await Promise.all([
    rpcOrThrow('feed_get', { p_tab: tab, p_filter: filter }, FeedData),
    rpcOrThrow('feed_progress', {}, Progress),
    rpcOrThrow('pipelines_get', {}, z.array(Pipeline)),
    rpcOrThrow('activity_types_get', {}, z.array(ActivityType)),
    rpc('mailboxes_get', {}, Mailboxes),
  ])
  // a composer opens only where a mailbox can send (0020: syncing or synced, and mine to reply from)
  const canSend = mail.ok && mail.data.mailboxes.some((m) => m.can_reply && (m.status === 'synced' || m.status === 'syncing'))
  return { feed, progress, pipelines, types, canSend }
}
export type FeedBundle = Awaited<ReturnType<typeof loadFeed>>

/** The records a model's preview offers: the first twelve open deals of its pipeline, or open leads. */
export async function loadPreviewRecords(model: ScoreModel): Promise<PreviewRecord[]> {
  if (model.entity === 'deal') {
    const r = await rpc('deal_list', { p_query: { status: 'open', limit: 12, ...(model.pipeline_id ? { pipeline_id: model.pipeline_id } : {}) } },
      z.object({ rows: z.array(PreviewRecord) }))
    return r.ok ? r.data.rows : []
  }
  const r = await rpc('rec_list', { p_entity: 'lead', p_query: { limit: 12, filters: [{ f: 'converted_at', op: 'empty' }, { f: 'archived_at', op: 'empty' }] } },
    z.object({ rows: z.array(PreviewRecord) }))
  return r.ok ? r.data.rows : []
}

export async function loadScoring() {
  const [models, pipelines, labels] = await Promise.all([
    rpcOrThrow('score_models_get', {}, ScoreModels),
    rpcOrThrow('pipelines_get', {}, z.array(Pipeline)),
    rpcOrThrow('labels_get', { p_entity: 'person' }, z.array(Label)),
  ])
  return { ...models, pipelines, labels }
}

export const previewScore = (model: string, record: string) => rpc('score_preview', { p_model: model, p_record: record }, ScorePreview)

export const loadEnrichment = () => rpcOrThrow('enrichment_get', {}, Enrichment)

export { FEED_TABS }
