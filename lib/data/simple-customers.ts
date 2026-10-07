import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import { loadCustomer, loadCustomers, loadTimeline } from './customers'
import { TicketDetail, TicketRow, loadConfig, loadMacros } from './tickets'
import { REQUEST_KINDS, type Queue } from './simple-customers-shared'

export { loadConfig, loadMacros }

/**
 * What Sentral Simple › Customers reads (SimpleCustomers.dc.html). The accounts, the account's detail and the ticket
 * configuration come from the existing loaders; this adds the KPI row (simple_customers_summary, 0056), the
 * «requests» queue and the structured request on a ticket (0056). Every result is parsed.
 */
const num = z.coerce.number()

const Summary = z.object({
  mrr: num.nullable(),
  arr: num.nullable(),
  paying: num,
  trials: num,
  trial_conversion: num.nullable(),
  open_tickets: num.nullable(),
  median_first_response_min: num.nullable(),
})
export type Summary = z.infer<typeof Summary>

/** The KPI row for one application; null when the staff member may not read it. */
export async function loadSummary(product: string): Promise<Summary | null> {
  const r = await rpc('simple_customers_summary', { p_product: product }, Summary, { quiet: true })
  return r.ok ? r.data : null
}

/** The accounts using one application, with that application's status, plan and MRR (customers_get, 0056 scope). */
export const loadAccounts = (product: string) => loadCustomers({ product })

/** One account: its detail and its timeline (customer_detail, customer_timeline). */
export async function loadAccount(id: string) {
  const [detail, timeline] = await Promise.all([loadCustomer(id), loadTimeline(id)])
  if (!detail.ok) return detail
  return { ok: true as const, data: { detail: detail.data, timeline: timeline.ok ? timeline.data : [] } }
}

// the request as the database stores it (0056); anything malformed reads as no request
export const Request = z.object({
  kind: z.enum(REQUEST_KINDS),
  args: z.object({ days: z.number().int().optional(), plan: z.string().optional() }).catch({}),
}).nullable().catch(null)

export const SimpleTicketRow = TicketRow.extend({ request: Request.optional().transform((v) => v ?? null) })
export type SimpleTicketRow = z.infer<typeof SimpleTicketRow>
export const SimpleTicketDetail = TicketDetail.extend({ request: Request.optional().transform((v) => v ?? null) })
export type SimpleTicketDetail = z.infer<typeof SimpleTicketDetail>

const Counts = z.object({ open: num, unassigned: num, requests: num, closed: num })
const QueueList = z.object({ rows: z.array(SimpleTicketRow), counts: Counts })
export type QueueList = z.infer<typeof QueueList>

/** One queue of the application's tickets, the most urgent SLA first, with every queue's count (tickets_get). */
export const loadQueue = (product: string, queue: Queue) =>
  rpcOrThrow('tickets_get', { p_query: { view: queue, product, sort: 'sla' } }, QueueList)

/** One ticket with its thread and request; a ticket the staff member may not see reads as absent. */
export async function loadTicket(id: string): Promise<SimpleTicketDetail | null> {
  const r = await rpc('ticket_detail', { p_id: id }, SimpleTicketDetail, { quiet: true })
  return r.ok ? r.data : null
}
