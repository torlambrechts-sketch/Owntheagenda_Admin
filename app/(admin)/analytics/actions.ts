'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { CHANNELS, SIGNALS } from '@/lib/data/analytics-calc'

/** Server actions of the Analytics screen: each parses its input and answers `{ ok } | { ok: false, code }`. */
export type Result = { ok: true } | { ok: false; code: RpcCode; detail?: string | null }

const bad = { ok: false as const, code: 'invalid' as const }

const SpendInput = z.object({
  campaign: z.string().trim().min(1).max(120),
  month: z.string().regex(/^\d{4}-\d{2}$/),
  // null removes the month's spend for the campaign
  amount: z.number().min(0).max(1e11).nullable(),
  channel: z.enum(CHANNELS).nullable(),
})

/** Campaign spend for a month (analytics_set_spend; Campaigns › Spend, needs Campaigns › See reports of others). */
export async function setSpend(input: z.input<typeof SpendInput>): Promise<Result> {
  const p = SpendInput.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('analytics_set_spend', {
    p_campaign: p.data.campaign, p_month: `${p.data.month}-01`, p_amount: p.data.amount, p_channel: p.data.channel,
  }, z.object({ ok: z.literal(true) }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  revalidatePath('/analytics')
  return { ok: true }
}

const Weights = z.record(z.enum(SIGNALS), z.number().int().min(0).max(100))
  .refine((w) => Object.values(w).some((x) => x > 0), { message: 'one weight above zero' })

/** A new version of the health model (health_model_save; needs Global › Configure). Scores are recomputed. */
export async function saveHealthModel(input: z.input<typeof Weights>): Promise<Result> {
  const p = Weights.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('health_model_save', { p_weights: p.data }, z.object({ id: z.string().uuid() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  revalidatePath('/analytics')
  return { ok: true }
}
