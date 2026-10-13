'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { CHANGE_KINDS, CHANNELS, OPP_KINDS, RULES, STAGES } from '@/lib/growth/seo'
import type { Result } from './actions'

/** Growth › SEO, the suite's writes (0074). Each parses its input; the database checks the right and every value again. */

const uuid = z.string().uuid()
const product = z.string().regex(/^[a-z][a-z0-9_]{1,40}$/)
const path = z.string().regex(/^\//).max(300)
const bad = { ok: false as const, code: 'invalid' as const }
const done = () => revalidatePath('/growth')
/** one of the application's sites (0089); absent or null is its first, as before */
const site = uuid.nullable().optional()
const onSite = (v: string | null | undefined) => (v ? { p_site: v } : {})

/** «Do it» and «Plan»: a search into the content plan */
export async function planAdd(input: { product: string; site?: string | null; query: string; kind: string; path: string | null }): Promise<Result<{ id: string }>> {
  const p = z.object({ product, site, query: z.string().trim().min(1).max(200), kind: z.enum(OPP_KINDS), path: path.nullable() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('seo_plan_add', { p_product: p.data.product, p_query: p.data.query, p_kind: p.data.kind, p_path: p.data.path, ...onSite(p.data.site) },
                      z.object({ planned: z.boolean(), id: uuid }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true, id: r.data.id }
}

/** ← and → on a plan card */
export async function planMove(input: { id: string; stage: string }): Promise<Result<{ logged: boolean }>> {
  const p = z.object({ id: uuid, stage: z.enum(STAGES) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('seo_plan_move', { p_id: p.data.id, p_stage: p.data.stage }, z.object({ stage: z.enum(STAGES), logged: z.boolean() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true, logged: r.data.logged }
}

/** «Log change» */
export async function changeAdd(input: { product: string; site?: string | null; path: string; kind: string; note: string }): Promise<Result> {
  const p = z.object({ product, site, path, kind: z.enum(CHANGE_KINDS), note: z.string().trim().max(200) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('seo_change_add', { p_product: p.data.product, p_path: p.data.path, p_kind: p.data.kind, p_note: p.data.note || null, ...onSite(p.data.site) },
                      z.object({ id: uuid }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}

/** «Add link» or «Skip» on a suggested internal link */
export async function linkDecide(input: { product: string; site?: string | null; from: string; to: string; anchor: string; decision: 'added' | 'skipped' }): Promise<Result> {
  const p = z.object({ product, site, from: path, to: path, anchor: z.string().max(120), decision: z.enum(['added', 'skipped']) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('seo_link_decide', { p_product: p.data.product, p_from: p.data.from, p_to: p.data.to, p_anchor: p.data.anchor, p_decision: p.data.decision, ...onSite(p.data.site) },
                      z.object({ decision: z.string() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}

/** an alert rule on or off, or a channel added or removed */
export async function alertRuleSet(input: { product: string; site?: string | null; rule: string; enabled: boolean; channels: string[] }): Promise<Result> {
  const p = z.object({ product, site, rule: z.enum(RULES), enabled: z.boolean(), channels: z.array(z.enum(CHANNELS)).max(2) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('seo_alert_rule_set', { p_product: p.data.product, p_rule: p.data.rule, p_enabled: p.data.enabled, p_channels: p.data.channels, ...onSite(p.data.site) },
                      z.object({ rule: z.string(), enabled: z.boolean() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}

/** «Acknowledge» and «Reopen» */
export async function alertAck(input: { id: string; ack: boolean }): Promise<Result> {
  const p = z.object({ id: uuid, ack: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('seo_alert_ack', { p_id: p.data.id, p_ack: p.data.ack }, z.object({ acknowledged: z.boolean() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true }
}
