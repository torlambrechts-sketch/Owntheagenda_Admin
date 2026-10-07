'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { AD_CHANNELS, AD_UTM, CONDITIONS, EXITS, SimpleModel, TRIGGERS } from '@/lib/data/simple-growth-shared'
import { setSpend } from '../analytics/actions'
import { setWorkflowState } from '../automation/actions'

/** Server actions of Sentral Simple › Growth: each parses its input and answers `{ ok } | { ok: false, code }`. */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode; detail?: string | null }

const uuid = z.string().uuid()
const product = z.string().regex(/^[a-z][a-z0-9_]{1,40}$/)
const bad = { ok: false as const, code: 'invalid' as const }
const fail = (r: { code: RpcCode; detail: string | null }) => ({ ok: false as const, code: r.code, detail: r.detail })
const done = () => revalidatePath('/growth')

// ---------------------------------------------------------------------------
// SEO
export async function addKeyword(input: { product: string; query: string }): Promise<Result> {
  const p = z.object({ product, query: z.string().trim().min(1).max(200) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('seo_keyword_add', { p_product: p.data.product, p_query: p.data.query }, z.object({ id: uuid, query: z.string() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function removeKeyword(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('seo_keyword_remove', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// Marketing campaigns
const iso = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
const NewCampaign = z.object({
  product,
  name: z.string().trim().min(1).max(120),
  channel: z.enum(AD_CHANNELS),
  landing_path: z.string().trim().max(300).regex(/^\/[A-Za-z0-9/_.~%-]*$/),
  budget: z.number().min(0).max(1e11).nullable(),
  starts_on: iso.nullable(),
  ends_on: iso.nullable(),
})

/** A new campaign (ad_campaign_save): the database makes its utm and tracking link; it starts scheduled. */
export async function createCampaign(input: z.input<typeof NewCampaign>): Promise<Result<{ id: string }>> {
  const p = NewCampaign.safeParse(input)
  if (!p.success) return { ...bad, detail: p.error.issues[0]?.path.join('.') ?? null }
  const r = await rpc('ad_campaign_save', { p_id: null, p_values: p.data, p_version: null }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

/** Live or paused: the record only — no ad platform is reached. */
export async function setCampaignState(input: { id: string; state: 'live' | 'paused'; version: number }): Promise<Result> {
  const p = z.object({ id: uuid, state: z.enum(['live', 'paused']), version: z.number().int().positive() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('ad_campaign_set_state', { p_id: p.data.id, p_state: p.data.state, p_version: p.data.version }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

/** A month's spend for a campaign, under its utm_campaign (analytics_set_spend through the Analytics action). */
export async function setCampaignSpend(input: { campaign: string; channel: string; month: string; amount: number | null }): Promise<Result> {
  const p = z.object({ campaign: z.string().regex(/^[a-z0-9_-]{1,60}$/), channel: z.enum(AD_CHANNELS), month: z.string().regex(/^\d{4}-\d{2}$/), amount: z.number().min(0).max(1e11).nullable() }).safeParse(input)
  if (!p.success) return bad
  const r = await setSpend({ campaign: p.data.campaign, month: p.data.month, amount: p.data.amount, channel: AD_UTM[p.data.channel].spend })
  if (!r.ok) return r
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// Email and automation
const SaveSequence = z.object({
  id: uuid.nullable(),
  version: z.number().int().positive().nullable(),
  name: z.string().trim().min(1).max(120),
  trigger: z.enum(TRIGGERS),
  stage_id: uuid.nullable(),
  list: uuid.nullable(),
  exit: z.enum(EXITS),
  steps: z.array(z.discriminatedUnion('kind', [
    z.object({ kind: z.literal('email'), text: z.string().trim().min(1).max(200), campaign_id: uuid.nullish() }),
    z.object({ kind: z.literal('wait'), days: z.number().int().min(1).max(365) }),
    z.object({ kind: z.literal('cond'), cond: z.enum(CONDITIONS) }),
    z.object({ kind: z.literal('task'), text: z.string().trim().min(1).max(200) }),
  ])).min(1).max(30),
})

/** Save the editor (simple_sequence_save): compiled onto the workflow engine in one transaction, emails as automated drafts. */
export async function saveSequence(input: z.input<typeof SaveSequence>): Promise<Result<{ id: string; version: number; simple: SimpleModel }>> {
  const p = SaveSequence.safeParse(input)
  if (!p.success) return { ...bad, detail: p.error.issues[0]?.path.join('.') ?? null }
  const { id, version, ...values } = p.data
  const r = await rpc('simple_sequence_save', { p_id: id, p_values: values, p_version: version },
    z.object({ id: uuid, version: z.number(), simple: SimpleModel }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id, version: r.data.version, simple: r.data.simple }
}

/** Activate or pause (workflow_set_state through the Automation action); activation is refused while something blocks it. */
export async function setSequenceState(input: { id: string; state: 'draft' | 'active' }): Promise<Result> {
  const r = await setWorkflowState(input)
  if (!r.ok) return r
  done()
  return { ok: true }
}
