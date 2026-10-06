import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import { IMPACTS, LINK_KINDS, PRIORITIES, SORTS, TICKET_STATUSES, TICKET_TYPES, URGENCIES, VIEWS } from './tickets-shared'

export { IMPACTS, LINK_KINDS, PRIORITIES, SORTS, TICKET_STATUSES, TICKET_TYPES, URGENCIES, VIEWS }

/**
 * Tickets (0012_tickets.sql): the inbox, one ticket's detail, the configuration, the help centre, macros
 * and reports. Every row is parsed here; the screen never casts what the database returns.
 */
const num = z.coerce.number()
const id = z.string().uuid()

export const TicketRow = z.object({
  id,
  ref: z.string(),
  number: num,
  type: z.enum(TICKET_TYPES),
  category_key: z.string(),
  queue_key: z.string(),
  status: z.enum(TICKET_STATUSES),
  impact: z.enum(IMPACTS),
  urgency: z.enum(URGENCIES),
  priority: z.enum(PRIORITIES),
  subject: z.string(),
  product: z.string().nullable(),
  channel: z.enum(['in_app', 'email', 'contact_form', 'staff']),
  context: z.record(z.string(), z.unknown()).catch({}),
  version: num,
  owner_id: id.nullable(),
  assignee_id: id.nullable(),
  organization_id: id.nullable(),
  person_id: id.nullable(),
  problem_id: id.nullable(),
  problem_ref: z.string().nullable(),
  problem_status: z.enum(['investigating', 'known_error', 'resolved']).nullable(),
  root_cause: z.string().nullable(),
  workaround: z.string().nullable(),
  status_banner: z.boolean(),
  incidents: num,
  responded: z.boolean(),
  csat_score: num.nullable(),
  created_at: z.string(),
  first_response_at: z.string().nullable(),
  first_response_due_at: z.string().nullable(),
  resolution_due_at: z.string().nullable(),
  first_response_left_min: num.nullable(),
  first_response_used_min: num.nullable(),
  resolution_left_min: num.nullable(),
  sla_risk: z.boolean(),
  organization: z.object({ id, name: z.string(), org_number: z.string().nullable(), employees: num.nullable(), account_id: id.nullable() }).nullable(),
  person: z.object({ id, name: z.string(), title: z.string().nullable(), email: z.string().nullable() }).nullable(),
  assignee: z.object({ id, name: z.string().nullable(), initials: z.string().nullable() }).nullable(),
})
export type TicketRow = z.infer<typeof TicketRow>

const Counts = z.object({
  open: num, mine: num, unassigned: num, sla: num, closed: num,
  queues: z.record(z.string(), num),
})
export const TicketList = z.object({ rows: z.array(TicketRow), counts: Counts })
export type TicketList = z.infer<typeof TicketList>

export const TicketDetail = TicketRow.extend({
  messages: z.array(z.object({
    id,
    kind: z.enum(['customer', 'reply', 'note', 'system', 'admin_action']),
    body: z.string(),
    author: z.string().nullable(),
    created_at: z.string(),
    delivery_status: z.enum(['queued', 'sent', 'failed', 'not_configured']).nullable(),
  })),
  links: z.array(z.object({ kind: z.enum(LINK_KINDS), ref: z.string(), label: z.string().nullable() })),
  privacy: z.object({ id, kind: z.string(), due_at: z.string(), status: z.string() }).nullable(),
  subscription: z.object({ status: z.string().nullable(), trial_ends_at: z.string().nullable(), plan: z.string().nullable() }).nullable(),
})
export type TicketDetail = z.infer<typeof TicketDetail>

export const TicketConfig = z.object({
  queues: z.array(z.object({ key: z.string(), name: z.string(), allowed: z.boolean() })),
  categories: z.array(z.object({ key: z.string(), name: z.string(), queue_key: z.string() })),
  sla: z.array(z.object({ priority: z.enum(PRIORITIES), first_response_min: num, resolution_min: num })),
  hours: z.array(z.object({ dow: num, opens: z.string(), closes: z.string() })),
  assignees: z.array(z.object({ id, name: z.string().nullable(), initials: z.string().nullable() })),
})
export type TicketConfig = z.infer<typeof TicketConfig>

export const Macro = z.object({
  id,
  name: z.string(),
  category_key: z.string().nullable(),
  used: num,
  versions: z.array(z.object({ locale: z.enum(['nb', 'nn', 'en']), version: num, body: z.string(), published_at: z.string() })),
})
export type Macro = z.infer<typeof Macro>
export const Macros = z.array(Macro)

export const Help = z.object({
  articles: z.array(z.object({
    id, slug: z.string(), title: z.string(), category_key: z.string().nullable(), locale: z.string(), status: z.enum(['draft', 'published']),
    version: num, problem_id: id.nullable(), updated_at: z.string(), published_at: z.string().nullable(), views: num, deflected: num,
  })),
  gaps: z.array(z.object({ topic: z.string(), count: num })),
  /** share of the last 30 days' tickets with an article link, in percent; null without tickets */
  article_rate: num.nullable(),
})
export type Help = z.infer<typeof Help>

export const Reports = z.object({
  created: num, previous: num, median_first_response_min: num.nullable(), median_resolution_min: num.nullable(),
  due: num, met: num, resolved: num, reopened: num, csat_avg: num.nullable(), csat_requested: num, csat_answered: num,
  by_category: z.array(z.object({ key: z.string(), trial: num, customer: num })),
  frt_by_priority: z.record(z.string(), num.nullable()),
})
export type Reports = z.infer<typeof Reports>

const PickRows = <S extends z.ZodTypeAny>(row: S) => z.object({ total: num, rows: z.array(row) })
export const OrgOption = z.object({ id, name: z.string() })
export const PersonOption = z.object({ id, name: z.string(), organization_id: id.nullable() })
export type OrgOption = z.infer<typeof OrgOption>
export type PersonOption = z.infer<typeof PersonOption>

/** A super-admin to escalate to: active staff on a permission set of kind «admin» (access_model + staff_list). */
const AccessModel = z.object({ permission_sets: z.array(z.object({ id, kind: z.string() })) })
const StaffList = z.array(z.object({ id, name: z.string(), active: z.boolean(), permission_set_id: id }))

export type TicketQuery = { view: (typeof VIEWS)[number]; q: string; sort: (typeof SORTS)[number]; product: string }

export const loadTickets = (q: TicketQuery) =>
  rpcOrThrow('tickets_get', { p_query: { view: q.view, q: q.q, sort: q.sort, product: q.product } }, TicketList)

/** One ticket; a ticket the staff member may not see (another queue) reads as absent. */
export async function loadTicketDetail(ticketId: string): Promise<TicketDetail | null> {
  const r = await rpc('ticket_detail', { p_id: ticketId }, TicketDetail, { quiet: true })
  return r.ok ? r.data : null
}

export const loadConfig = () => rpcOrThrow('ticket_config', {}, TicketConfig)
export const loadMacros = () => rpcOrThrow('macros_get', {}, Macros)
export const loadHelp = () => rpcOrThrow('help_get', {}, Help)
export const loadReports = (days: number, product: string) => rpcOrThrow('ticket_reports', { p_days: days, p_product: product }, Reports)

export async function loadPickers(): Promise<{ orgs: OrgOption[]; people: PersonOption[] } | null> {
  const [o, p] = await Promise.all([
    rpc('rec_list', { p_entity: 'organization', p_query: { limit: 500, sort: { f: 'name', dir: 'asc' } } }, PickRows(OrgOption)),
    rpc('rec_list', { p_entity: 'person', p_query: { limit: 500, sort: { f: 'name', dir: 'asc' } } }, PickRows(PersonOption)),
  ])
  if (!o.ok) return null
  return { orgs: o.data.rows, people: p.ok ? p.data.rows : [] }
}

export async function loadSuperAdmins(): Promise<{ id: string; name: string }[]> {
  const [m, s] = await Promise.all([rpc('access_model', {}, AccessModel), rpc('staff_list', {}, StaffList)])
  if (!m.ok || !s.ok) return []
  const admin = new Set(m.data.permission_sets.filter((p) => p.kind === 'admin').map((p) => p.id))
  return s.data.filter((x) => x.active && admin.has(x.permission_set_id)).map((x) => ({ id: x.id, name: x.name }))
}

