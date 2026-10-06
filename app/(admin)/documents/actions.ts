'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { loadDealOptions, loadDocument, loadSignRequest, loadTemplate, loadViews } from '@/lib/data/documents'
import {
  CATEGORIES, FIELD_KINDS, INVITE_LANGUAGES, SHARES, TABLE_COLUMNS, TEMPLATE_LANGUAGES,
  type DealOption, type DocDetail, type DocView, type SignRequest, type TemplateDetail,
} from '@/lib/data/documents-shared'

/**
 * The Documents screen's server actions. Every input is parsed; every answer is `{ ok: true, … }` or
 * `{ ok: false, code, detail }`, and the screen words the code. The database checks rights and state again.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.string().uuid()
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const Id = z.object({ id: uuid })
const anyObj = z.record(z.string(), z.unknown())

// ---------------------------------------------------------------------------
// documents
export async function documentAction(input: unknown): Promise<Res<{ doc: DocDetail; views: DocView[] }>> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const [d, v] = await Promise.all([loadDocument(p.data.id), loadViews(p.data.id)])
  if (!d.ok) return fail(d)
  return { ok: true, doc: d.data, views: v.ok ? v.data : [] }
}

export async function dealOptionsAction(): Promise<Res<{ deals: DealOption[] }>> {
  return { ok: true, deals: await loadDealOptions() }
}

export async function createDocumentAction(input: unknown): Promise<Res<{ id: string; missing: string[]; unknown: string[] }>> {
  const p = z.object({ template: uuid, deal: uuid, name: z.string().trim().max(200).optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('document_create', { p_template: p.data.template, p_deal: p.data.deal, p_name: p.data.name || null },
    z.object({ id: uuid, missing: z.array(z.string()), unknown: z.array(z.string()) }))
  return r.ok ? { ok: true, ...r.data } : fail(r)
}

export async function updateDocumentAction(input: unknown): Promise<Res<{ missing: string[] }>> {
  const p = z.object({
    id: uuid,
    version: z.number().int(),
    values: z.object({ name: z.string().trim().min(1).max(200), body_html: z.string().max(1_000_000).optional(), valid_until: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional() }).strict(),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('document_update', { p_id: p.data.id, p_values: p.data.values, p_version: p.data.version }, z.object({ missing: z.array(z.string()) }))
  return r.ok ? { ok: true, missing: r.data.missing } : fail(r)
}

export async function deleteDocumentAction(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, reason: z.string().trim().max(300).optional() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('document_delete', { p_ids: [p.data.id], p_reason: p.data.reason || null }, z.object({ deleted: z.number() }))
  return r.ok ? { ok: true } : fail(r)
}

/** A trackable link: the token comes back once (Q1) and is never stored here or anywhere but in the answer. */
export async function createLinkAction(input: unknown): Promise<Res<{ path: string }>> {
  const p = z.object({ id: uuid, recipient: uuid.nullable() }).safeParse(input)
  if (!p.success) return bad
  // the link is made for the person the document is addressed to, so their opens are named in the views
  const r = await rpc('document_link_create', { p_id: p.data.id, p_recipient: p.data.recipient }, z.object({ id: uuid, path: z.string().regex(/^\/d\/[A-Za-z0-9_-]+$/) }))
  return r.ok ? { ok: true, path: r.data.path } : fail(r)
}

export async function revokeLinkAction(input: unknown): Promise<Res> {
  const p = z.object({ link: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('document_link_revoke', { p_link: p.data.link }, z.object({ revoked: z.boolean() }))
  return r.ok ? { ok: true } : fail(r)
}

/** The file behind a document. Without a PDF (no PDF worker yet) the answer is not_connected (pdf). */
export async function fileAction(input: unknown): Promise<Res> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('document_file_url', { p_id: p.data.id }, z.object({ bucket: z.string(), path: z.string() }))
  // the edge function that signs the object does not exist yet (V-P5-06)
  return r.ok ? { ok: false, code: 'not_connected', detail: 'signer' } : fail(r)
}

// ---------------------------------------------------------------------------
// templates
export async function templateAction(input: unknown): Promise<Res<{ template: TemplateDetail }>> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const r = await loadTemplate(p.data.id)
  return r.ok ? { ok: true, template: r.data } : fail(r)
}

const TemplateValues = z.object({
  name: z.string().trim().min(1).max(120),
  category: z.enum(CATEGORIES),
  share: z.enum(SHARES),
  team_id: uuid.nullable(),
  product: z.string().max(40).nullable(),
  language: z.enum(TEMPLATE_LANGUAGES),
  body_html: z.string().max(500_000).optional(),
  product_table: z.object({ columns: z.array(z.enum(TABLE_COLUMNS)).min(1) }).nullable().optional(),
  validity_days: z.number().int().min(1).max(365).nullable(),
  number_prefix: z.string().regex(/^[A-Z]{1,4}-$/).nullable(),
}).strict()

export async function saveTemplateAction(input: unknown): Promise<Res<{ id: string; unknown: string[] }>> {
  const p = z.object({ id: uuid.nullable(), version: z.number().int().nullable(), values: TemplateValues }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('doc_template_save', { p_id: p.data.id, p_values: p.data.values, p_version: p.data.version }, z.object({ id: uuid, unknown: z.array(z.string()) }))
  return r.ok ? { ok: true, ...r.data } : fail(r)
}

export async function deleteTemplateAction(input: unknown): Promise<Res> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('doc_template_delete', { p_id: p.data.id }, anyObj)
  return r.ok ? { ok: true } : fail(r)
}

export async function importTemplateAction(input: unknown): Promise<Res> {
  const p = z.object({ provider: z.enum(['google', 'microsoft']), file: z.string().trim().min(1).max(300) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('doc_template_import', { p_provider: p.data.provider, p_file_ref: p.data.file }, anyObj)
  return r.ok ? { ok: true } : fail(r)
}

// ---------------------------------------------------------------------------
// e-signature
export async function signRequestAction(input: unknown): Promise<Res<{ request: SignRequest }>> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const r = await loadSignRequest(p.data.id)
  return r.ok ? { ok: true, request: r.data } : fail(r)
}

const pct = z.number().min(0).max(100)
const SignDraft = z.object({
  id: uuid.nullable(),
  document: uuid,
  version: z.number().int().nullable(),
  signers: z.array(z.object({ name: z.string().trim().min(1).max(200), email: z.string().trim().max(254).regex(/^[^@\s]+@[^@\s]+$/), color: z.string().regex(/^#[0-9A-F]{6}$/), person_id: uuid.nullable() }).strict()).max(500),
  fields: z.array(z.object({ signer: z.number().int().min(1), kind: z.enum(FIELD_KINDS), page: z.number().int().min(1), x: pct, y: pct, w: pct, h: pct }).strict()).max(2000),
  message: z.string().max(2000),
  language: z.enum(INVITE_LANGUAGES),
  otp: z.boolean(),
})

/** Save the draft request, then send it. A refusal to send leaves the draft saved, and says so. */
export async function sendSignatureAction(input: unknown): Promise<{ ok: true; id: string } | (Fail & { id?: string })> {
  const p = z.object({ draft: SignDraft, send: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const d = p.data.draft
  const saved = await rpc('signature_request_save', {
    p_id: d.id, p_document: d.document, p_signers: d.signers, p_fields: d.fields, p_message: d.message.trim() || null,
    p_language: d.language, p_otp: d.otp, p_version: d.version,
  }, z.object({ id: uuid }))
  if (!saved.ok) return fail(saved)
  if (!p.data.send) return { ok: true, id: saved.data.id }
  const sent = await rpc('signature_request_send', { p_id: saved.data.id }, anyObj)
  return sent.ok ? { ok: true, id: saved.data.id } : { ...fail(sent), id: saved.data.id }
}

export async function remindSignerAction(input: unknown): Promise<Res> {
  const p = z.object({ id: uuid, signer: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('signature_request_remind', { p_id: p.data.id, p_signer: p.data.signer }, anyObj)
  return r.ok ? { ok: true } : fail(r)
}

export async function cancelSignatureAction(input: unknown): Promise<Res> {
  const p = Id.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('signature_request_cancel', { p_id: p.data.id }, anyObj)
  return r.ok ? { ok: true } : fail(r)
}

// ---------------------------------------------------------------------------
// storage and branding
export async function connectDriveAction(input: unknown): Promise<Res> {
  const p = z.enum(['google', 'microsoft']).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('doc_storage_connect', { p_provider: p.data }, anyObj)
  // an OAuth URL would come back here once the drive adapter exists; today the answer is not_connected
  return r.ok ? { ok: false, code: 'not_connected', detail: p.data } : fail(r)
}

export async function storageDefaultAction(input: unknown): Promise<Res> {
  const p = z.object({ provider: z.enum(['platform', 'google', 'onedrive', 'sharepoint']), location: z.object({ kind: z.enum(['shared', 'personal']), label: z.string().max(120) }).nullable() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('doc_storage_set_default', { p_provider: p.data.provider, p_location: p.data.location ?? {} }, anyObj)
  return r.ok ? { ok: true } : fail(r)
}

/** Branding and the e-signature service are settings (0030), set with setting_set (Global › configure). */
export async function documentSettingAction(input: unknown): Promise<Res> {
  const p = z.union([
    z.object({ key: z.literal('doc_branding'), value: z.enum(['hidden', 'shown']) }),
    z.object({ key: z.literal('esign_service'), value: z.enum(['builtin', 'external']) }),
  ]).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('setting_set', { p_key: p.data.key, p_value: p.data.value }, z.unknown())
  return r.ok ? { ok: true } : fail(r)
}
