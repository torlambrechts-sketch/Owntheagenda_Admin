'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { signForMe } from './server'

/**
 * Files on a record (CRM-05, SF-33), for every screen that shows them: begin (file_upload_begin checks the record's
 * visibility, the edit right, the type, the extension and the size, and writes a pending row) → sign the upload for that
 * row's path → the browser PUTs the file → done (file_upload_done lists it). A download asks file_download_url (visibility,
 * audited) and signs that path for a minute. The path never comes from the browser. If the signer refuses after a begin,
 * the pending row is removed again so it is not left for the nightly purge.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.guid()
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })
const Begin = z.object({ id: uuid, bucket: z.literal('record-files'), path: z.string().min(3).max(500), expires_in: z.number() })
const Where = z.object({ bucket: z.literal('record-files'), path: z.string().min(3).max(500), expires_in: z.number(), filename: z.string(), mime: z.string() })

export async function recordUploadBegin(input: unknown): Promise<Res<{ id: string; url: string }>> {
  const p = z.object({
    entity: z.string().regex(/^[a-z_]{2,40}$/), id: uuid,
    filename: z.string().trim().min(1).max(255), mime: z.string().min(3).max(120), size: z.number().int().min(1).max(26_214_400),
  }).safeParse(input)
  if (!p.success) return bad
  const begun = await rpc('file_upload_begin', { p_entity: p.data.entity, p_id: p.data.id, p_filename: p.data.filename, p_mime: p.data.mime, p_size: p.data.size }, Begin)
  if (!begun.ok) return fail(begun)
  const signed = await signForMe({ mode: 'upload', bucket: 'record-files', path: begun.data.path })
  if (!signed.ok) {
    await rpc('file_delete', { p_id: begun.data.id }, z.unknown(), { quiet: true })
    return { ok: false, code: signed.code, detail: signed.detail }
  }
  return { ok: true, id: begun.data.id, url: signed.url }
}

export async function recordUploadDone(input: unknown): Promise<Res<{ id: string }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('file_upload_done', { p_id: p.data }, z.object({ id: uuid }))
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

/** The PUT did not land: the pending row goes (the uploader may remove their own file). */
export async function recordUploadAbandon(input: unknown): Promise<Res> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await rpc('file_delete', { p_id: p.data }, z.unknown())
  return r.ok ? { ok: true } : fail(r)
}

export async function recordDownload(input: unknown): Promise<Res<{ url: string }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const where = await rpc('file_download_url', { p_id: p.data }, Where)
  if (!where.ok) return fail(where)
  const signed = await signForMe({ mode: 'download', bucket: 'record-files', path: where.data.path })
  return signed.ok ? { ok: true, url: signed.url } : { ok: false, code: signed.code, detail: signed.detail }
}
