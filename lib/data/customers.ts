import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'

/**
 * What the Customers screen reads (0013_customers.sql and the generic record functions). Every result is
 * parsed; a value the database does not hold stays null and the screen renders the design's «—».
 */
const ts = z.string()
const nullableText = z.string().nullable()
const n = z.number()

export const Product = z.object({ key: z.string(), status: z.string() })

export const CustomerRow = z.object({
  id: z.string(),
  name: z.string(),
  org_number: nullableText,
  account_id: nullableText,
  industry: nullableText,
  fylke: nullableText,
  city: nullableText,
  source: nullableText,
  ehf: z.boolean(),
  labels: z.array(z.string()),
  owner_id: nullableText,
  csm_id: nullableText,
  version: n,
  owner: nullableText,
  employees: n.nullable(),
  products: z.array(Product),
  status: nullableText,
  plan: nullableText,
  mrr: n,
  priced: z.boolean(),
  trial_ends_at: ts.nullable(),
  signup_at: ts.nullable(),
  last_survey_at: ts.nullable(),
  response: n.nullable(),
  // the scoring model arrives in phase 4; until then the database returns null and nothing is drawn
  health: n.nullable(),
})
export type CustomerRow = z.infer<typeof CustomerRow>

export const VIEW_KEYS = ['all', 'trials_week_no_survey', 'at_risk', 'past_due', 'multi_product', 'ehf'] as const
export type ViewKey = (typeof VIEW_KEYS)[number]

const CustomersList = z.object({
  rows: z.array(CustomerRow),
  views: z.object({ all: n, trials_week_no_survey: n, at_risk: n, past_due: n, multi_product: n, ehf: n }),
  facets: z.object({ plans: z.array(z.string()), industries: z.array(z.string()), fylker: z.array(z.string()), sources: z.array(z.string()) }),
})
export type CustomersList = z.infer<typeof CustomersList>

export const FILTER_KEYS = ['status', 'plan', 'industry', 'fylke', 'source', 'product'] as const
export type FilterKey = (typeof FILTER_KEYS)[number]
export type ListQuery = { q?: string; view?: ViewKey; f?: Partial<Record<FilterKey, string>>; product?: string }

export const loadCustomers = (query: ListQuery) => rpcOrThrow('customers_get', { p_query: query }, CustomersList)

export const Grant = z.object({
  id: z.string(),
  organization_id: z.string(),
  product: z.string(),
  staff_id: z.string(),
  reason: z.string(),
  hours: n,
  state: z.enum(['pending', 'active', 'expired', 'revoked', 'denied']),
  requested_at: ts,
  approved_by: nullableText,
  approved_at: ts.nullable(),
  expires_at: ts.nullable(),
  page_views: n,
  organization: z.string().optional(),
  staff: z.string().nullable().optional(),
})
export type Grant = z.infer<typeof Grant>

const Subscription = z.object({
  product: z.string(),
  tenant_id: z.string(),
  plan: nullableText,
  billing_interval: nullableText,
  status: z.string(),
  mrr: n,
  price: n.nullable(),
  currency: z.string(),
  seats: n.nullable(),
  trial_ends_at: ts.nullable(),
  confirmed_at: ts.nullable(),
  cancelled_at: ts.nullable(),
  payment_state: z.string(),
  since: ts,
})
export type Subscription = z.infer<typeof Subscription>

const Member = z.object({
  product: z.string(),
  user_id: z.string(),
  name: nullableText,
  email: nullableText,
  role: nullableText,
  active: z.boolean(),
  last_login_at: ts.nullable(),
  mfa_enabled: z.boolean().nullable(),
  auth_method: nullableText,
  invite_state: nullableText,
  invited_by: nullableText,
  is_billing_contact: z.boolean(),
})
export type Member = z.infer<typeof Member>

const Round = z.object({
  product: z.string(),
  round_ref: z.string(),
  name: nullableText,
  kind: nullableText,
  planned_at: ts.nullable(),
  opens_at: ts.nullable(),
  closes_at: ts.nullable(),
  invited: n.nullable(),
  delivered: n.nullable(),
  bounced: n.nullable(),
  answered: n.nullable(),
  reminders_sent: n.nullable(),
  gained_after_reminders: n.nullable(),
})
export type Round = z.infer<typeof Round>

const CustomerDetail = CustomerRow.extend({
  address: nullableText,
  postal_code: nullableText,
  nace: nullableText,
  website: nullableText,
  phone: nullableText,
  email: nullableText,
  brreg_synced_at: ts.nullable(),
  registered_employees: n.nullable(),
  csm: nullableText,
  subscriptions: z.array(Subscription),
  users: z.array(Member),
  rounds: z.array(Round),
  counts: z.record(z.string(), n),
  milestones: z.record(z.string(), ts),
  deals: z.array(z.object({ id: z.string(), title: z.string(), value: n.nullable(), status: z.string(), stage: z.string() })),
  contacts: z.array(z.object({ id: z.string(), name: z.string(), title: nullableText, email: nullableText, marketing_status: nullableText })),
  access_grants: z.array(Grant),
})
export type CustomerDetail = z.infer<typeof CustomerDetail>

export const loadCustomer = (id: string) => rpc('customer_detail', { p_org: id }, CustomerDetail)

const TimelineItem = z.object({
  at: ts,
  kind: z.string(),
  event: nullableText,
  product: z.string().nullable().optional(),
  actor: z.string().nullable().optional(),
  reason: z.string().nullable().optional(),
  ref: z.string().nullable().optional(),
  status: z.string().nullable().optional(),
  // an admin row's outcome (0056); absent on product events and tickets
  ok: z.boolean().nullable().optional(),
})
export type TimelineItem = z.infer<typeof TimelineItem>
export const loadTimeline = (id: string) => rpc('customer_timeline', { p_org: id }, z.array(TimelineItem))

const AuditItem = z.object({ at: ts, who: nullableText, action: nullableText, reason: nullableText, ok: z.boolean() })
export type AuditItem = z.infer<typeof AuditItem>
export const loadAudit = (id: string) => rpc('customer_audit', { p_org: id }, z.array(AuditItem))

const Ticket = z.object({
  id: z.string(),
  ref: z.string(),
  type: z.string(),
  subject: z.string(),
  status: z.string(),
  priority: z.string(),
  channel: z.string(),
  queue_key: z.string(),
  category_key: z.string(),
})
export type Ticket = z.infer<typeof Ticket>
const Tickets = z.object({ rows: z.array(Ticket) })

/** The company's tickets, open first, then closed. Null when the staff member may not read tickets. */
export async function loadTickets(id: string) {
  const [open, closed] = await Promise.all([
    rpc('tickets_get', { p_query: { organization_id: id, view: 'open', sort: 'newest' } }, Tickets),
    rpc('tickets_get', { p_query: { organization_id: id, view: 'closed', sort: 'newest' } }, Tickets),
  ])
  if (!open.ok) return open
  return { ok: true as const, data: [...open.data.rows, ...(closed.ok ? closed.data.rows : [])] }
}

const Note = z.object({ id: z.string(), body: z.string(), pinned: z.boolean(), created_at: ts, author: nullableText, author_id: nullableText, parent_id: nullableText })
export type Note = z.infer<typeof Note>
export const loadNotes = (id: string) => rpc('notes_list', { p_entity: 'organization', p_id: id }, z.array(Note))

const Label = z.object({ id: z.string(), name: z.string(), bg: z.string(), ink: z.string() })
export type Label = z.infer<typeof Label>
export const loadLabels = () => rpcOrThrow('labels_get', { p_entity: 'organization' }, z.array(Label))

const Staff = z.object({ id: z.string(), name: z.string(), initials: nullableText, active: z.boolean() })
export type Staff = z.infer<typeof Staff>
export const loadStaff = () => rpcOrThrow('staff_list', {}, z.array(Staff))

const SearchMember = Member.extend({
  tenant_id: z.string(),
  invited_at: ts.nullable(),
  organization: z.object({ id: z.string(), name: z.string() }).nullable(),
})
export type SearchMember = z.infer<typeof SearchMember>
export const searchMembers = (q: string) => rpc('members_search', { p_q: q, p_limit: 50 }, z.array(SearchMember))

const Billing = z.object({
  mrr: n,
  priced: n,
  past_due_mrr: n,
  ehf: n,
  lifecycle: z.record(z.string(), n),
  failed: z.array(z.object({ organization: z.string(), organization_id: z.string(), product: z.string(), amount: n.nullable(), state: z.string() })),
  plans: z.array(
    z.object({
      id: z.string(), product: z.string(), band_label: z.string(), min_employees: n, max_employees: n.nullable(),
      monthly_price: n, annual_price: n.nullable(), version: n, active: z.boolean(),
    }),
  ),
  coupons: z.array(z.object({ code: z.string(), description: nullableText, percent: n.nullable(), months: n.nullable() })),
})
export type Billing = z.infer<typeof Billing>
export const loadBilling = (product: string) => rpc('billing_overview', { p_product: product }, Billing)

export const loadGrants = () => rpc('access_grants_get', {}, z.array(Grant))

const PrivacyRequest = z.object({
  id: z.string(),
  kind: z.string(),
  requester_category: nullableText,
  received_at: ts,
  due_at: ts,
  status: z.string(),
  owner: nullableText,
  ticket_ref: nullableText,
  organization: nullableText,
  organization_id: nullableText,
})
export type PrivacyRequest = z.infer<typeof PrivacyRequest>
/** Only staff who work the personvern queue read these; for anyone else the result is `forbidden`. */
export const loadPrivacy = () => rpc('privacy_get', {}, z.array(PrivacyRequest), { quiet: true })

const SavedViews = z.object({
  views: z.array(z.object({ id: z.string(), name: z.string(), query: z.record(z.string(), z.unknown()), shared: z.boolean(), mine: z.boolean() })),
})
export type SavedView = z.infer<typeof SavedViews>['views'][number]
export const loadSavedViews = () => rpc('views_get', { p_screen: 'customers' }, SavedViews)

const Settings = z.array(z.object({ key: z.string(), default: z.string(), values: z.array(z.object({ scope_id: z.string(), value: z.string() })) }))

/** The effective platform value of one setting from the register (settings_get). */
export async function settingValue(key: string): Promise<string | null> {
  const r = await rpc('settings_get', {}, Settings)
  if (!r.ok) return null
  const s = r.data.find((x) => x.key === key)
  if (!s) return null
  return s.values.find((v) => v.scope_id === '')?.value ?? s.default
}
