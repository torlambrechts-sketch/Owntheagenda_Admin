'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { getShell } from '@/lib/shell'
import { renderEmail } from '@/lib/data/campaigns-render'
import {
  BORDERS, CAMPAIGN_LANGUAGES, CAMPAIGN_TYPES, CampaignDetail, Counts, Design, Preview, ROW_KINDS, SenderDomain, cleanDesign, type CampaignDetail as Detail,
} from '@/lib/data/campaigns-shared'

/** Server actions of the Campaigns route: each parses its input and answers `{ ok } | { ok: false, code, detail }`. */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode; detail?: string | null }

const uuid = z.string().uuid()
const bad = { ok: false as const, code: 'invalid' as const }
const fail = (r: { code: RpcCode; detail: string | null }) => ({ ok: false as const, code: r.code, detail: r.detail })
const done = () => revalidatePath('/campaigns')
const reason = z.string().trim().max(300).optional()

/** The design as the builder sends it; the database checks it again (app.campaign_design_check). */
const DesignIn = Design.extend({
  rows: z.array(z.object({
    kind: z.enum(ROW_KINDS), text: z.string().max(5000).optional(), fs: z.number().min(10).max(48).optional(),
    bg: z.enum(['card', 'soft_yellow', 'mint', 'cream']).optional(), padding: z.number().refine((x): boolean => [14, 22, 32].includes(x)).optional(),
    border: z.enum(BORDERS).optional(), src: z.string().max(2000).optional(), href: z.string().max(2000).optional(), alt: z.string().max(300).optional(),
    html: z.string().max(100000).optional(),
    items: z.array(z.union([z.string().max(500), z.object({ label: z.string().max(200), href: z.string().max(2000).optional() })])).max(50).optional(),
  })).min(1).max(200),
})

// ---------------------------------------------------------------------------
// the renderer's input from a saved campaign: the one renderer for preview, test and schedule (V-P6C-01)
async function render(c: Detail, html?: string | null): Promise<string> {
  const shell = await getShell()
  const product = shell.products.find((p) => p.key === c.product)?.name
  return renderEmail({
    design: c.html ? null : c.design,
    html: html ?? c.html,
    preheader: c.preheader,
    sender: { name: c.from_name ?? product ?? '', postalAddress: c.postal_address },
    brand: product ?? c.from_name ?? '',
    utm: c.utm,
    lang: c.language,
  })
}

// ---------------------------------------------------------------------------
// campaigns (campaigns:add; others' campaigns campaigns:edit_others)
const CreateInput = z.object({
  name: z.string().trim().min(1).max(120),
  type: z.enum(CAMPAIGN_TYPES),
  template_id: uuid.nullable().optional(),
  html: z.string().max(500000).nullable().optional(),
})
export async function createCampaign(input: z.input<typeof CreateInput>): Promise<Result<{ id: string }>> {
  const p = CreateInput.safeParse(input)
  if (!p.success) return bad
  const values: Record<string, unknown> = { name: p.data.name, type: p.data.type }
  if (p.data.template_id) values.template_id = p.data.template_id
  if (p.data.html) values.html = p.data.html
  const r = await rpc('campaign_save', { p_id: null, p_values: values, p_version: null }, z.object({ id: uuid }).passthrough())
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

const Values = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  type: z.enum(CAMPAIGN_TYPES).optional(),
  segment_id: uuid.nullable().optional(),
  template_id: uuid.nullable().optional(),
  design: DesignIn.optional(),
  html: z.string().max(500000).optional(),
  subject_a: z.string().max(200).optional(),
  subject_b: z.string().max(200).nullable().optional(),
  preheader: z.string().max(200).nullable().optional(),
  ab_percent: z.number().int().min(2).max(50).optional(),
  ab_metric: z.enum(['opens', 'clicks']).optional(),
  ab_wait_hours: z.number().int().min(1).max(72).optional(),
  sender_domain_id: uuid.nullable().optional(),
  coupon_code: z.string().max(30).nullable().optional(),
  utm_source: z.string().regex(/^[a-z0-9_-]{1,60}$/).optional(),
  utm_medium: z.string().regex(/^[a-z0-9_-]{1,60}$/).optional(),
  utm_campaign: z.string().regex(/^[a-z0-9_-]{1,60}$/).optional(),
  tracking: z.boolean().optional(),
  notify_owners: z.boolean().optional(),
  language: z.enum(CAMPAIGN_LANGUAGES).optional(),
})
const SaveInput = z.object({ id: uuid, version: z.number().int(), values: Values })
export async function saveCampaign(input: z.input<typeof SaveInput>): Promise<Result<{ version: number }>> {
  const p = SaveInput.safeParse(input)
  if (!p.success) return bad
  const v = { ...p.data.values }
  if (v.design) v.design = cleanDesign(v.design)
  const r = await rpc('campaign_save', { p_id: p.data.id, p_values: v, p_version: p.data.version }, CampaignDetail)
  if (!r.ok) return fail(r)
  done()
  return { ok: true, version: r.data.version }
}

export async function duplicateCampaign(input: { id: string }): Promise<Result<{ id: string }>> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('campaign_duplicate', { p_id: p.data.id }, z.object({ id: uuid }).passthrough())
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

export async function deleteCampaign(input: { id: string; reason?: string }): Promise<Result> {
  const p = z.object({ id: uuid, reason }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('campaign_delete', { p_ids: [p.data.id], p_reason: p.data.reason || null }, z.object({ deleted: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function cancelCampaign(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('campaign_cancel', { p_id: p.data.id }, z.object({ id: uuid }).passthrough())
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function pauseCampaign(input: { id: string; paused: boolean }): Promise<Result> {
  const p = z.object({ id: uuid, paused: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('campaign_pause', { p_id: p.data.id, p_paused: p.data.paused }, z.object({ id: uuid }).passthrough())
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

/**
 * The preview: the builder's current state rendered by the one renderer (a draft's unsaved rows included), merged
 * by the database with a chosen person, or, with none, the audience's missing values counted (COM-05).
 */
const PreviewInput = z.object({
  id: uuid,
  person: uuid.nullable().optional(),
  draft: z.object({
    design: DesignIn.nullable(), html: z.string().max(500000).nullable(), preheader: z.string().max(200).nullable(), sender_domain_id: uuid.nullable(),
    language: z.enum(CAMPAIGN_LANGUAGES).optional(),
  }).nullable(),
})
export async function previewCampaign(input: z.input<typeof PreviewInput>): Promise<Result<{ preview: Preview }>> {
  const p = PreviewInput.safeParse(input)
  if (!p.success) return bad
  const c = await rpc('campaign_get', { p_id: p.data.id }, CampaignDetail)
  if (!c.ok) return fail(c)
  let html: string | null = null
  if (c.data.status === 'draft' && p.data.draft) {
    const d = p.data.draft
    let sender = { from_name: c.data.from_name, postal_address: c.data.postal_address }
    if (d.sender_domain_id && d.sender_domain_id !== c.data.sender_domain_id) {
      const ds = await rpc('sender_domains_get', {}, z.object({ rows: z.array(SenderDomain) }).passthrough(), { quiet: true })
      const dom = ds.ok ? ds.data.rows.find((x) => x.id === d.sender_domain_id) : null
      if (dom) sender = { from_name: dom.from_name, postal_address: dom.postal_address }
    }
    html = await render({ ...c.data, design: d.design ? cleanDesign(d.design) : c.data.design, html: d.html, preheader: d.preheader, language: d.language ?? c.data.language, ...sender })
  }
  const r = await rpc('campaign_preview', { p_id: p.data.id, p_person: p.data.person ?? null, p_html: html }, Preview)
  if (!r.ok) return fail(r)
  return { ok: true, preview: r.data }
}

/** A test to the staff member's own address, rendered from the saved campaign; not_connected without the provider. */
export async function testSendCampaign(input: { id: string; person?: string | null }): Promise<Result<{ to: string }>> {
  const p = z.object({ id: uuid, person: uuid.nullable().optional() }).safeParse(input)
  if (!p.success) return bad
  const c = await rpc('campaign_get', { p_id: p.data.id }, CampaignDetail)
  if (!c.ok) return fail(c)
  const html = c.data.status === 'draft' ? await render(c.data) : null
  const r = await rpc('campaign_test_send', { p_id: p.data.id, p_html: html, p_person: p.data.person ?? null }, z.object({ queued: z.boolean(), to: z.string() }))
  if (!r.ok) return fail(r)
  return { ok: true, to: r.data.to }
}

/** Schedule (or switch on an automated campaign): the saved design rendered once, checked and frozen by the database. */
export async function scheduleCampaign(input: { id: string; version: number; at: string | null }): Promise<Result<{ status: string }>> {
  const p = z.object({ id: uuid, version: z.number().int(), at: z.string().datetime({ offset: true }).nullable() }).safeParse(input)
  if (!p.success) return bad
  const c = await rpc('campaign_get', { p_id: p.data.id }, CampaignDetail)
  if (!c.ok) return fail(c)
  const html = await render(c.data)
  const r = await rpc('campaign_schedule', { p_id: p.data.id, p_at: p.data.at, p_version: p.data.version, p_html: html }, CampaignDetail)
  if (!r.ok) return fail(r)
  done()
  return { ok: true, status: r.data.status }
}

export async function exportRecipients(input: { id: string }): Promise<Result<{ filename: string; mime: string; content: string; rows: number }>> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('campaign_export', { p_id: p.data.id, p_format: 'csv' },
    z.object({ filename: z.string(), mime: z.string(), rows: z.coerce.number(), content: z.string() }))
  if (!r.ok) return fail(r)
  return { ok: true, ...r.data }
}

// ---------------------------------------------------------------------------
// marketing templates (CMP-02): every save is a new version; layouts need campaigns:configure
const TemplateValues = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  scope: z.enum(['private', 'shared']).optional(),
  category: z.string().trim().max(40).nullable().optional(),
  subject: z.string().max(500).optional(),
  design: DesignIn.optional(),
  html: z.string().max(500000).optional(),
})
export async function saveTemplate(input: { id: string | null; version: number | null; values: z.input<typeof TemplateValues> }): Promise<Result<{ id: string; version: number; current: number }>> {
  const p = z.object({ id: uuid.nullable(), version: z.number().int().nullable(), values: TemplateValues }).safeParse(input)
  if (!p.success) return bad
  const v = { ...p.data.values }
  if (v.design) v.design = cleanDesign(v.design)
  if (v.category === '') v.category = null
  const r = await rpc('marketing_template_save', { p_id: p.data.id, p_values: v, p_version: p.data.version },
    z.object({ id: uuid, version: z.coerce.number(), current_version: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id, version: r.data.version, current: r.data.current_version }
}

/** Restores a template version: saved as the next version, under the same rights as saving (R-CAMPAIGNS-05). */
export async function restoreTemplate(input: { id: string; version: number }): Promise<Result<{ current: number }>> {
  const p = z.object({ id: uuid, version: z.number().int().min(1) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('marketing_template_restore', { p_id: p.data.id, p_version: p.data.version },
    z.object({ id: uuid, version: z.coerce.number(), current_version: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, current: r.data.current_version }
}

export async function deleteTemplate(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('marketing_template_delete', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// segments (CMP-03): the live count is the database's; saving checks that the filter runs
const Query = z.object({ filters: z.array(z.unknown()).max(50) })
export async function countSegment(input: { query: unknown }): Promise<Result<{ counts: z.infer<typeof Counts> }>> {
  const p = z.object({ query: Query }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('segment_count', { p_query: p.data.query }, Counts)
  if (!r.ok) return fail(r)
  return { ok: true, counts: r.data }
}

export async function saveSegment(input: { id: string | null; name: string; query: unknown; description?: string | null; shared: boolean }): Promise<Result<{ id: string }>> {
  const p = z.object({ id: uuid.nullable(), name: z.string().trim().min(1).max(80), query: Query, description: z.string().trim().max(300).nullable().optional(), shared: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('segment_save', { p_id: p.data.id, p_name: p.data.name, p_query: p.data.query, p_description: p.data.description || null, p_shared: p.data.shared },
    z.object({ id: uuid }).passthrough())
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

export async function deleteSegment(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('segment_delete', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// consent: suppressions (0031, campaigns:bulk) and list hygiene (campaigns:bulk)
const Email = z.string().trim().max(254).regex(/^[^@\s]+@[^@\s]+\.[^@\s]+$/)
export async function addSuppression(input: { email: string; scope: 'marketing' | 'all'; reason?: string }): Promise<Result<{ added: boolean }>> {
  const p = z.object({ email: Email, scope: z.enum(['marketing', 'all']), reason }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('suppression_add', { p_email: p.data.email, p_reason: p.data.reason || null, p_scope: p.data.scope }, z.object({ added: z.boolean() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, added: r.data.added }
}

export async function removeSuppression(input: { email: string; scope: string; reason?: string }): Promise<Result> {
  const p = z.object({ email: Email, scope: z.enum(['marketing', 'all']), reason }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('suppression_remove', { p_email: p.data.email, p_scope: p.data.scope, p_reason: p.data.reason || null }, z.object({ removed: z.boolean() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function archiveHygiene(input: { expected: number }): Promise<Result<{ archived: number }>> {
  const p = z.object({ expected: z.number().int().min(0) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('hygiene_archive', { p_expected: p.data.expected }, z.object({ archived: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, archived: r.data.archived }
}

// ---------------------------------------------------------------------------
// sender domains (campaigns:configure): identity only; the checks come from the workers
const DomainValues = z.object({
  domain: z.string().trim().toLowerCase().max(253).optional(),
  stream: z.enum(['marketing', 'transactional']).optional(),
  sends_here: z.boolean().optional(),
  product: z.string().max(40).nullable().optional(),
  from_name: z.string().trim().min(1).max(120).optional(),
  from_local: z.string().regex(/^[a-z0-9._-]{1,40}$/).optional(),
  reply_to: z.string().trim().max(254).nullable().optional(),
  postal_address: z.string().trim().max(300).nullable().optional(),
  warmup_started_at: z.string().regex(/^\d{4}-\d\d-\d\d$/).nullable().optional(),
  warmup_days: z.number().int().min(0).max(120).optional(),
})
export async function saveDomain(input: { id: string | null; version: number | null; values: z.input<typeof DomainValues> }): Promise<Result<{ id: string }>> {
  const p = z.object({ id: uuid.nullable(), version: z.number().int().nullable(), values: DomainValues }).safeParse(input)
  if (!p.success) return bad
  const v = { ...p.data.values }
  if (v.reply_to === '') v.reply_to = null
  if (v.postal_address === '') v.postal_address = null
  const r = await rpc('sender_domain_save', { p_id: p.data.id, p_values: v, p_version: p.data.version }, z.object({ id: uuid }).passthrough())
  if (!r.ok) return fail(r)
  done()
  return { ok: true, id: r.data.id }
}

export async function deleteDomain(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sender_domain_delete', { p_id: p.data.id }, z.object({ id: uuid }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true }
}

export async function recheckDns(input: { id?: string | null }): Promise<Result<{ queued: number }>> {
  const p = z.object({ id: uuid.nullable().optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('sender_domain_recheck', { p_id: p.data.id ?? null }, z.object({ queued: z.coerce.number() }))
  if (!r.ok) return fail(r)
  done()
  return { ok: true, queued: r.data.queued }
}
