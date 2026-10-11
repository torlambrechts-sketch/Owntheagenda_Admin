'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { AREAS, BUDGET_CHANNELS, OUTCOMES } from '@/lib/growth/playbook'
import type { Result } from './actions'

/** Growth › the playbook's writes (0076). Each parses its input; the database checks the right and every value again. */

const uuid = z.string().uuid()
const product = z.string().regex(/^[a-z][a-z0-9_]{1,40}$/)
const bad = { ok: false as const, code: 'invalid' as const }
const done = () => revalidatePath('/growth')
const ok = z.record(z.string(), z.unknown())

async function call(fn: string, args: Record<string, unknown>): Promise<Result> {
  const r = await rpc(fn, args, ok)
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}

/** a channel's budget this month */
export async function setBudget(input: { product: string; channel: string; amount: number }): Promise<Result> {
  const p = z.object({ product, channel: z.enum(BUDGET_CHANNELS), amount: z.number().min(0).max(100_000_000) }).safeParse(input)
  if (!p.success) return bad
  return call('marketing_budget_set', { p_product: p.data.product, p_channel: p.data.channel, p_amount: p.data.amount })
}

/** «Apply move» */
export async function moveBudget(input: { product: string; from: string; to: string; amount: number }): Promise<Result> {
  const p = z.object({ product, from: z.enum(BUDGET_CHANNELS), to: z.enum(BUDGET_CHANNELS), amount: z.number().positive().max(100_000_000) }).safeParse(input)
  if (!p.success || p.data.from === p.data.to) return bad
  return call('marketing_budget_move', { p_product: p.data.product, p_from: p.data.from, p_to: p.data.to, p_amount: p.data.amount })
}

/** «＋ Add experiment» */
export async function addExperiment(input: { product: string; hypothesis: string; area: string; impact: number; confidence: number; ease: number }): Promise<Result> {
  const score = z.number().int().min(1).max(10)
  const p = z.object({ product, hypothesis: z.string().trim().min(3).max(300), area: z.enum(AREAS), impact: score, confidence: score, ease: score }).safeParse(input)
  if (!p.success) return bad
  return call('growth_experiment_add', { p_product: p.data.product, p_hypothesis: p.data.hypothesis, p_area: p.data.area,
                                         p_impact: p.data.impact, p_confidence: p.data.confidence, p_ease: p.data.ease })
}

/** ← and → on an experiment */
export async function moveExperiment(input: { id: string; stage: string }): Promise<Result> {
  const p = z.object({ id: uuid, stage: z.enum(['backlog', 'ready', 'running']) }).safeParse(input)
  if (!p.success) return bad
  return call('growth_experiment_move', { p_id: p.data.id, p_stage: p.data.stage })
}

/** «Call result» */
export async function callExperiment(input: { id: string; outcome: string; note: string }): Promise<Result> {
  const p = z.object({ id: uuid, outcome: z.enum(OUTCOMES), note: z.string().trim().max(200) }).safeParse(input)
  if (!p.success) return bad
  return call('growth_experiment_call', { p_id: p.data.id, p_outcome: p.data.outcome, p_note: p.data.note || null })
}

/** «Archive» */
export async function archiveExperiment(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  return call('growth_experiment_archive', { p_id: p.data.id })
}

/** a blackout period on the calendar */
export async function addBlackout(input: { product: string; name: string; from: string; to: string }): Promise<Result> {
  const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
  const p = z.object({ product, name: z.string().trim().min(1).max(60), from: day, to: day }).safeParse(input)
  if (!p.success || p.data.to < p.data.from) return bad
  return call('growth_blackout_add', { p_product: p.data.product, p_name: p.data.name, p_from: p.data.from, p_to: p.data.to })
}

export async function removeBlackout(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  return call('growth_blackout_remove', { p_id: p.data.id })
}
