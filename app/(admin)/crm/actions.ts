'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { listAll } from '@/lib/data/contacts'
import { EXPORT_COLUMNS, exportHeader, toCsv } from '@/lib/data/contacts-export'
import { Segment } from '@/lib/data/campaigns-shared'
import { loadCrmDeal, loadOrgOptions, type CrmDeal, type OrgOption } from '@/lib/data/simple-crm'

/**
 * Sentral Simple › CRM: the actions the section adds to the ones it reuses (deals: fetchBoard, moveDeal, setStatus,
 * saveNote; campaigns: countSegment, saveSegment). Each parses its input and answers `{ ok: true, … }` or
 * `{ ok: false, code }`; the database checks the rights again.
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const uuid = z.string().uuid()
const bad: Fail = { ok: false, code: 'invalid' }
const fail = (r: { code: RpcCode; detail: string | null }): Fail => ({ ok: false, code: r.code, detail: r.detail })

/** The drawer's deal and notes. */
export async function fetchCrmDeal(input: unknown): Promise<Res<{ deal: CrmDeal }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const r = await loadCrmDeal(p.data)
  return r.ok ? { ok: true, deal: r.data } : fail(r)
}

/** The new deal's account choices. */
export async function fetchOrgOptions(): Promise<Res<{ orgs: OrgOption[] }>> {
  const r = await loadOrgOptions()
  return r.ok ? { ok: true, orgs: r.data } : fail(r)
}

/**
 * «＋ New deal»: title, account, value and stage, in the board's pipeline (deal_create; deals:add). The stage must be
 * one of the pipeline's — deal_create checks the pipeline, the stage trigger the pair.
 */
export async function createCrmDeal(input: unknown): Promise<Res<{ id: string }>> {
  const p = z.object({
    title: z.string().trim().min(1).max(200),
    pipeline_id: uuid,
    stage_id: uuid,
    organization_id: uuid.nullable(),
    value: z.number().int().min(0).max(1e12).nullable(),
  }).safeParse(input)
  if (!p.success) return bad
  const { organization_id, value, ...rest } = p.data
  const values = { ...rest, ...(organization_id ? { organization_id } : {}), ...(value !== null ? { value } : {}) }
  const r = await rpc('deal_create', { p_values: values }, z.object({ id: uuid }).passthrough())
  return r.ok ? { ok: true, id: r.data.id } : fail(r)
}

/**
 * «Export CSV»: every person the saved list matches, in the columns Contacts › Export writes (formula cells
 * neutralised), recorded with export_log (deals:export — people are a deals-scope record). The list is read again
 * here, so the file is the list's own filter and not one the browser sent.
 */
export async function exportList(input: unknown): Promise<Res<{ csv: string; rows: number; name: string }>> {
  const p = uuid.safeParse(input)
  if (!p.success) return bad
  const segments = await rpc('segments_get', {}, z.array(Segment))
  if (!segments.ok) return fail(segments)
  const seg = segments.data.find((s) => s.id === p.data)
  if (!seg) return { ok: false, code: 'not_found' }
  try {
    const rows = await listAll('person', { filters: seg.query.filters ?? [], sort: { f: 'name', dir: 'asc' } }, z.record(z.string(), z.unknown()))
    const cols = EXPORT_COLUMNS.person!
    const csv = toCsv(cols.map(exportHeader), rows.map((r) => cols.map((c) => r[c] ?? '')))
    const log = await rpc('export_log', { p_entity: 'person', p_rows: rows.length, p_format: 'csv', p_scope: 'segment' }, z.unknown())
    if (!log.ok) return fail(log)
    return { ok: true, csv, rows: rows.length, name: seg.name }
  } catch (err) {
    return { ok: false, code: (err as { code?: RpcCode }).code ?? 'failed' }
  }
}
