'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { handOverSecrets } from '@/lib/secrets/hand-over'
import { CHECK_KEYS, INTEGRATION_KEYS, MANUAL } from './_components/delivery/logic'

/**
 * Development › the delivery half (0080): releases and their checklist, the changelog (release notes, 0078), the
 * integrations register, the Vercel projects' applications, the repositories bound to a product and the two connections
 * (Vercel's webhook secret and the CI's).
 * Every input is parsed; every answer is `{ ok: true, … }` or `{ ok: false, code, detail }`. The database checks the right,
 * the owner and the fresh second factor again. A signing secret goes from the form to secret-intake under a one-time intake
 * number and nowhere else: it is not logged, kept or returned.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.string().uuid()
const bad = (detail?: string): Fail => ({ ok: false, code: 'invalid', detail: detail ?? null })
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const any = z.record(z.string(), z.unknown())
const product = z.string().regex(/^[a-z][a-z0-9_]{1,30}$/)
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
const sha = z.string().trim().toLowerCase().regex(/^[0-9a-f]{7,40}$/)
const done = () => revalidatePath('/development')

// ---------------------------------------------------------------------------
// releases
export async function addRelease(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({ product, name: z.string().trim().min(1).max(80), plannedOn: day.nullable(), sha: sha.nullable() }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path[0] ?? ''))
  const r = await rpc('dev_release_add', { p_product: p.data.product, p_name: p.data.name, p_planned_on: p.data.plannedOn, p_sha: p.data.sha }, z.object({ id: uuid }))
  done()
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

export async function setRelease(input: unknown): Promise<Res> {
  const p = z.object({
    id: uuid, version: z.number().int(),
    patch: z.object({ name: z.string().trim().min(1).max(80).optional(), planned_on: day.nullable().optional(), sha: sha.nullable().optional() }).strict(),
  }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path.at(-1) ?? ''))
  const r = await rpc('dev_release_set', { p_id: p.data.id, p_patch: p.data.patch, p_version: p.data.version }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

export async function deleteRelease(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('dev_release_delete', { p_id: p.data }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

/** a manual item signed by the person calling, or the signature withdrawn; the rollback plan carries its text */
export async function signItem(input: unknown): Promise<Res> {
  const p = z.object({
    release: uuid, item: z.enum(CHECK_KEYS).refine((k) => MANUAL.includes(k)), on: z.boolean(), note: z.string().trim().max(500).nullable(),
  }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path[0] ?? ''))
  if (p.data.on && p.data.item === 'rollback' && !p.data.note) return bad('note')
  const r = await rpc('dev_release_sign', { p_release: p.data.release, p_item: p.data.item, p_on: p.data.on, p_note: p.data.note }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

/** «Record release»: the database records it only when every item passes, and publishes its changelog */
export async function recordRelease(input: unknown): Promise<Res<{ published: number }>> {
  const p = z.object({ id: uuid, version: z.number().int() }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('dev_release_record', { p_id: p.data.id, p_version: p.data.version }, z.object({ ok: z.boolean(), published: z.coerce.number() }))
  done()
  return r.ok ? { ok: true, published: r.data.published } : fail(r)
}

// ---------------------------------------------------------------------------
// the changelog: release notes (0078) attached to a release
export async function attachNote(input: unknown): Promise<Res> {
  const p = z.object({ release: uuid, note: uuid, on: z.boolean() }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('dev_release_note_attach', { p_release: p.data.release, p_note: p.data.note, p_on: p.data.on }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

/**
 * A changelog line written or edited here: a release note of the release's product, joined to the release when new. An
 * edit changes the kind and the line only: the note's body and its feature request (written elsewhere) are sent back as
 * they were, because release_note_save (0078) writes every field.
 */
export async function saveNote(input: unknown): Promise<Res> {
  const p = z.object({
    release: uuid, id: uuid.nullable(), product, kind: z.enum(['new', 'improved', 'fixed']), title: z.string().trim().min(3).max(200),
    body: z.string().max(4000).nullable(), featureRequest: uuid.nullable(),
  }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path[0] ?? ''))
  const saved = await rpc('release_note_save', {
    p_id: p.data.id, p_product: p.data.product, p_kind: p.data.kind, p_title: p.data.title, p_body: p.data.id ? p.data.body : null,
    p_feature_request: p.data.id ? p.data.featureRequest : null, p_source: p.data.id ? 'manual' : 'release',
  }, z.object({ id: uuid }).passthrough())
  if (!saved.ok) return fail(saved)
  if (!p.data.id) {
    const a = await rpc('dev_release_note_attach', { p_release: p.data.release, p_note: saved.data.id, p_on: true }, any)
    if (!a.ok) return fail(a)
  }
  done()
  return { ok: true }
}

// ---------------------------------------------------------------------------
// the integrations register
export async function setIntegration(input: unknown): Promise<Res> {
  const p = z.object({
    key: z.enum(INTEGRATION_KEYS), owner: uuid.nullable(), changeText: z.string().trim().max(200), dueOn: day.nullable(),
    url: z.string().trim().max(250).refine((u) => u === '' || /^https:\/\/\S{3,}$/.test(u)), none: z.boolean(),
  }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path[0] ?? ''))
  const r = await rpc('dev_integration_set', {
    p_key: p.data.key, p_owner: p.data.owner, p_change_text: p.data.changeText || null, p_change_due_on: p.data.changeText ? p.data.dueOn : null,
    p_change_url: p.data.changeText ? p.data.url || null : null, p_change_none: !p.data.changeText && p.data.none,
  }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

export async function planUpgrade(input: unknown): Promise<Res> {
  const p = z.enum(INTEGRATION_KEYS).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('dev_integration_plan', { p_key: p.data, p_due_on: null }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

export async function planDone(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('dev_integration_plan_done', { p_plan: p.data }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

// ---------------------------------------------------------------------------
// the repositories whose CI may post: the owner binds each to its product (fresh second factor), or unbinds it
const repository = z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9_-]{0,38}\/(?!\.\.?$)[a-z0-9_.-]{1,100}$/)
export async function bindRepo(input: unknown): Promise<Res> {
  const p = z.object({ repository, product: product.nullable() }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path[0] ?? ''))
  const r = await rpc('dev_ci_repo_set', { p_repository: p.data.repository, p_product: p.data.product }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

// ---------------------------------------------------------------------------
// Vercel projects and the two connections
export async function setProject(input: unknown): Promise<Res> {
  const p = z.object({ id: z.string().regex(/^prj_[A-Za-z0-9]{6,64}$/), product: product.nullable() }).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('dev_project_set', { p_id: p.data.id, p_product: p.data.product }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}

const SECRET: Record<'vercel' | 'ci', { name: string; shape: RegExp }> = {
  vercel: { name: 'vercel_signing_secret', shape: /^[A-Za-z0-9_-]{16,256}$/ },
  ci: { name: 'ci_signing_secret', shape: /^[A-Za-z0-9_-]{32,256}$/ },
}

/** the owner stores a signing secret: an intake number (owner, fresh second factor), then secret-intake */
export async function connectSource(input: unknown): Promise<Res> {
  const p = z.object({ purpose: z.enum(['vercel', 'ci']), secret: z.string().trim() }).safeParse(input)
  if (!p.success) return bad()
  const s = SECRET[p.data.purpose]
  if (!s.shape.test(p.data.secret)) return bad('secret_shape')
  const intake = await rpc('v3_intake', { p_purpose: p.data.purpose }, z.object({ intake_code: z.string().regex(/^[0-9a-f]{48}$/), expires_in: z.number() }))
  if (!intake.ok) return fail(intake)
  const handed = await handOverSecrets(intake.data.intake_code, { [s.name]: p.data.secret })
  done()
  return handed.ok ? { ok: true } : { ok: false, code: 'failed', detail: handed.code }
}

export async function disconnectSource(input: unknown): Promise<Res> {
  const p = z.enum(['vercel', 'ci']).safeParse(input)
  if (!p.success) return bad()
  const r = await rpc('v3_disconnect', { p_purpose: p.data }, any)
  done()
  return r.ok ? { ok: true } : fail(r)
}
