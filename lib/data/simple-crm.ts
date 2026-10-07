import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { Board, Detail, LostReason, Note, Pipeline } from '@/lib/data/deals'
import { Segment } from '@/lib/data/campaigns-shared'
import { MEMBERS_SHOWN } from '@/lib/data/simple-crm-shared'

/**
 * Loaders of Sentral Simple's CRM (SimpleCRM.dc.html): the board of the first pipeline with its closed deals (for the
 * month's won and lost), the deal drawer, and the saved lists with the people in one. Everything through the existing
 * functions (0009, 0035, 0037, 0006); every shape parsed.
 */

const SettingRow = z.object({ key: z.string(), default: z.string(), values: z.array(z.object({ scope_id: z.string(), value: z.string() })) })

/** Whether «lost» needs a reason (lost_reason_required, PIP-07; deal_status refuses without one when on). */
async function lostReasonRequired(): Promise<boolean> {
  const r = await rpc('settings_get', {}, z.array(SettingRow.passthrough()), { quiet: true })
  if (!r.ok) return false
  const s = r.data.find((x) => x.key === 'lost_reason_required')
  return (s ? (s.values.find((x) => x.scope_id === '')?.value ?? s.default) : 'off') === 'on'
}

/**
 * The Deals tab. Sentral Simple shows one pipeline: the first one the person may see, in the order Settings gives the
 * pipelines (pipelines_get, by ord) — the design's D.pipelines[0]. The board is read with its closed deals so the
 * month's won and lost come from the same cards.
 */
export async function loadCrmDeals() {
  const pipelines = await rpc('pipelines_get', {}, z.array(Pipeline))
  if (!pipelines.ok) return { ok: false as const, code: pipelines.code }
  const pipeline = pipelines.data[0] ?? null
  if (!pipeline) return { ok: true as const, data: { pipeline: null, pipelines: 0, board: null, lostReasons: [], lostRequired: false } }
  const [board, lostReasons, lostRequired] = await Promise.all([
    rpc('deal_board', { p_pipeline: pipeline.id, p_query: { filters: [], closed: true } }, Board),
    rpc('lost_reasons_get', {}, z.array(LostReason), { quiet: true }),
    lostReasonRequired(),
  ])
  if (!board.ok) return { ok: false as const, code: board.code }
  return {
    ok: true as const,
    data: { pipeline, pipelines: pipelines.data.length, board: board.data, lostReasons: lostReasons.ok ? lostReasons.data : [], lostRequired },
  }
}
export type CrmDeals = Extract<Awaited<ReturnType<typeof loadCrmDeals>>, { ok: true }>['data']

/** The drawer: the deal (deal_detail) and its notes (notes_list), newest first. */
export async function loadCrmDeal(id: string) {
  const [detail, notes] = await Promise.all([
    rpc('deal_detail', { p_id: id }, Detail),
    rpc('notes_list', { p_entity: 'deal', p_id: id }, z.array(Note)),
  ])
  if (!detail.ok) return detail
  return { ok: true as const, data: { detail: detail.data, notes: notes.ok ? notes.data : [] } }
}
export type CrmDeal = { detail: Detail; notes: Note[] }

const OrgOption = z.object({ id: z.string().uuid(), name: z.string() })
export type OrgOption = z.infer<typeof OrgOption>
/** The new deal's account choices: organizations by name (rec_list, deals:see). */
export async function loadOrgOptions() {
  const r = await rpc('rec_list', { p_entity: 'organization', p_query: { limit: 500, sort: { f: 'name', dir: 'asc' } } }, z.object({ rows: z.array(OrgOption.passthrough()) }))
  return r.ok ? { ok: true as const, data: r.data.rows.map((o) => ({ id: o.id, name: o.name })) } : r
}

export const Member = z.object({
  id: z.string().uuid(),
  name: z.string(),
  email: z.string().nullable(),
  title: z.string().nullable(),
  organization_id__title: z.string().nullable().optional(),
  marketing_status: z.string(),
})
export type Member = z.infer<typeof Member>

const Groups = z.array(z.object({ key: z.string().nullable(), n: z.coerce.number() }))

/** The people a list's filter matches, by name (rec_list person, the same filter the counts use). */
export const loadMembers = (query: Record<string, unknown>) =>
  rpc('rec_list', { p_entity: 'person', p_query: { filters: query.filters ?? [], sort: { f: 'name', dir: 'asc' }, limit: MEMBERS_SHOWN } },
    z.object({ total: z.coerce.number(), rows: z.array(Member) }))

/**
 * The Lists tab: the saved lists (segments_get, campaigns:see and the campaigns module), the people in the chosen one,
 * and the roles the new-list form offers — the titles people actually have (rec_group on title).
 */
export async function loadCrmLists(listId: string | null) {
  const [segments, roles] = await Promise.all([
    rpc('segments_get', {}, z.array(Segment)),
    rpc('rec_group', { p_entity: 'person', p_by: 'title', p_query: {} }, Groups, { quiet: true }),
  ])
  if (!segments.ok) return { ok: false as const, code: segments.code }
  const selected = segments.data.find((s) => s.id === listId) ?? segments.data[0] ?? null
  const members = selected ? await loadMembers(selected.query) : null
  return {
    ok: true as const,
    data: {
      segments: segments.data,
      selectedId: selected?.id ?? null,
      members: members && members.ok ? members.data : null,
      membersFailed: !!members && !members.ok,
      roles: roles.ok ? roles.data.flatMap((g) => (g.key && g.key.trim() ? [g.key] : [])).sort((a, b) => a.localeCompare(b, 'nb')) : [],
    },
  }
}
export type CrmLists = Extract<Awaited<ReturnType<typeof loadCrmLists>>, { ok: true }>['data']
