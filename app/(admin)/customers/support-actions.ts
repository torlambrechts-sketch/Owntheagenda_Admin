'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { aiRun, loadAiOutputs } from '@/lib/ai/run'
import { Article, SearchHits, type Article as ArticleT, type SearchHits as SearchHitsT } from '@/lib/data/support-hub'
import { COMPONENT_STATES, LOCALES, parseAnswer, helpPathOk, type ParsedAnswer } from './_components/support/logic'

/**
 * The writes of Customers › Help centre and support (0081). Each parses its input, calls one database function and returns
 * `{ ok: true, … }` or `{ ok: false, code }`; the view shows the code's message. The database checks every right again.
 */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: string }

const id = z.string().uuid()
const product = z.string().regex(/^[a-z]{2,20}$/)
const locale = z.enum(LOCALES)
const fail = (code: string) => ({ ok: false as const, code })
const done = () => revalidatePath('/customers')
const Ok = z.object({ ok: z.boolean() }).passthrough()

// ---------------------------------------------------------------------------
// help centre
export async function searchHelp(input: { product: string; locale: string; q: string }): Promise<Result<{ hits: SearchHitsT }>> {
  const p = z.object({ product, locale, q: z.string().max(200) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('help_search', { p_product: p.data.product, p_locale: p.data.locale, p_q: p.data.q }, SearchHits)
  return r.ok ? { ok: true, hits: r.data } : fail(r.code)
}

const NewArticle = z.object({
  product,
  title: z.string().trim().min(1).max(200),
  locale: locale.optional(),
  category_key: z.string().regex(/^[a-z_]{2,40}$/).nullable().optional(),
  group_id: id.optional(),
  source: z.enum(['staff', 'gap']).optional(),
})
export async function createArticle(input: z.input<typeof NewArticle>): Promise<Result<{ id: string }>> {
  const p = NewArticle.safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('help_article_write', { p_id: null, p_values: p.data, p_version: null }, Article)
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true, id: r.data.id }
}

const ArticleValues = z.object({
  title: z.string().trim().min(1).max(200),
  body: z.string().max(20000),
  category_key: z.string().regex(/^[a-z_]{2,40}$/).nullable(),
  seo_title: z.string().trim().max(200),
  app_pages: z.array(z.string().refine(helpPathOk)).max(10),
}).partial()
export async function saveArticle(input: { id: string; version: number; values: z.input<typeof ArticleValues> }): Promise<Result<{ article: ArticleT }>> {
  const p = z.object({ id, version: z.number().int().positive(), values: ArticleValues }).safeParse(input)
  if (!p.success || Object.keys(p.data.values).length === 0) return fail('invalid')
  const r = await rpc('help_article_write', { p_id: p.data.id, p_values: p.data.values, p_version: p.data.version }, Article)
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true, article: r.data }
}

export async function publishArticle(input: { id: string; on: boolean }): Promise<Result<{ article: ArticleT }>> {
  const p = z.object({ id, on: z.boolean() }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('help_article_publish', { p_id: p.data.id, p_on: p.data.on }, Article)
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true, article: r.data }
}

export async function reviewArticle(input: { id: string }): Promise<Result<{ article: ArticleT }>> {
  const p = z.object({ id }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('help_article_review', { p_id: p.data.id }, Article)
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true, article: r.data }
}

// ---------------------------------------------------------------------------
// the widget settings and the «answer from published articles» preview (X-V3-2: the staff member's own question and the
// product's published articles are all Claude reads)
export async function saveSupportSettings(input: { product: string; aiEnabled: boolean }): Promise<Result> {
  const p = z.object({ product, aiEnabled: z.boolean() }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('support_settings_save', { p_product: p.data.product, p_ai_enabled: p.data.aiEnabled }, z.object({ ai_enabled: z.boolean() }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

export async function askArticles(input: { product: string; locale: string; question: string; titles: string[] }): Promise<Result<{ answer: ParsedAnswer; truncated: boolean }>> {
  const p = z.object({ product, locale, question: z.string().trim().min(3).max(500), titles: z.array(z.string().max(200)).max(100) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const q = await rpc('help_question_ask', { p_product: p.data.product, p_locale: p.data.locale, p_question: p.data.question }, z.object({ id }))
  if (!q.ok) return fail(q.code)
  const run = await aiRun('help_answer_preview', q.data.id)
  if (!run.ok) return fail(run.code ?? 'failed')
  const outputs = await loadAiOutputs('help_answer_preview', q.data.id)
  const body = outputs.find((o) => o.id === run.output)?.body ?? outputs[0]?.body
  if (!body) return fail('empty')
  return { ok: true, answer: parseAnswer(body, p.data.titles), truncated: run.truncated === true }
}

// ---------------------------------------------------------------------------
// status: components, incidents
export async function addComponent(input: { product: string; name: string }): Promise<Result> {
  const p = z.object({ product, name: z.string().trim().min(2).max(80) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('status_component_save', { p_id: null, p_product: p.data.product, p_name: p.data.name }, z.object({ id }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

export async function setComponent(input: { id: string; state: string }): Promise<Result> {
  const p = z.object({ id, state: z.enum(COMPONENT_STATES) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('status_component_set', { p_id: p.data.id, p_state: p.data.state }, Ok)
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

export async function removeComponent(input: { id: string }): Promise<Result> {
  const p = z.object({ id }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('status_component_remove', { p_id: p.data.id }, Ok)
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

export async function openIncident(input: { product: string; title: string; body: string; problem: string | null; components: string[] }): Promise<Result> {
  const p = z.object({
    product, title: z.string().trim().min(3).max(200), body: z.string().trim().min(1).max(4000), problem: id.nullable(), components: z.array(id).max(50),
  }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('status_incident_open', { p_product: p.data.product, p_title: p.data.title, p_body: p.data.body, p_problem: p.data.problem,
                                                p_components: p.data.components }, z.object({ id }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

export async function postIncidentUpdate(input: { id: string; state: string; body: string }): Promise<Result> {
  const p = z.object({ id, state: z.enum(['investigating', 'identified', 'monitoring']), body: z.string().trim().min(1).max(4000) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('status_incident_update', { p_id: p.data.id, p_state: p.data.state, p_body: p.data.body }, Ok)
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true }
}

// «notified» is the number of tickets resolved with the reply; mail_ready says whether those replies can be emailed at all
export async function resolveIncident(input: { id: string; message: string }): Promise<Result<{ notified: number; mailReady: boolean }>> {
  const p = z.object({ id, message: z.string().trim().min(1).max(4000) }).safeParse(input)
  if (!p.success) return fail('invalid')
  const r = await rpc('status_incident_resolve', { p_id: p.data.id, p_message: p.data.message },
                      z.object({ notified: z.number(), notices_cleared: z.number(), mail_ready: z.boolean() }))
  if (!r.ok) return fail(r.code)
  done()
  return { ok: true, notified: r.data.notified, mailReady: r.data.mail_ready }
}
