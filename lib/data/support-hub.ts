import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { CHANNELS, COMPONENT_STATES, INCIDENT_STATES, LOCALES } from '@/app/(admin)/customers/_components/support/logic'

/**
 * What Customers › Help centre and support reads (SupportHub.dc.html, 0081). Every result is parsed, never cast. A read the
 * staff member may not make comes back as `{ ok: false, code }` and the tab shows the reason instead of numbers.
 */
const num = z.coerce.number()
const uuid = z.string().uuid()
const ts = z.string()

// ---------------------------------------------------------------------------
// Support results
export const Results = z.object({
  days: num,
  tickets: z.object({ created: num, previous: num, previous_complete: z.boolean() }),
  csat: z.object({ avg: num.nullable(), answered: num, requested: num, previous_avg: num.nullable() }),
  gaps: z.array(z.object({ category_key: z.string(), name: z.string(), tickets: num })),
  measured: z.boolean(),
  articles: z.array(z.object({ id: uuid, title: z.string(), views: num.nullable(), linked_tickets: num })),
  can_write: z.boolean(),
})
export type Results = z.infer<typeof Results>
export const loadResults = (product: string) => rpc('support_results', { p_product: product, p_days: 30 }, Results)

// ---------------------------------------------------------------------------
// Help widget (an admin preview)
const Subscription = z.object({ product: z.string(), status: z.string().nullable(), plan: z.string().nullable() })
export const Widget = z.object({
  pages: z.array(z.string()),
  articles: z.array(z.object({ id: uuid, title: z.string(), app_pages: z.array(z.string()) })),
  ai_enabled: z.boolean(),
  can_configure: z.boolean(),
  can_ask: z.boolean(),
  last_request: z.object({
    ref: z.string(),
    person: z.string().nullable(),
    role: z.string().nullable(),
    page: z.string().nullable(),
    browser: z.string().nullable(),
    app_version: z.string().nullable(),
    organization: z.object({ name: z.string(), org_number: z.string().nullable() }).nullable(),
    subscriptions: z.array(Subscription),
  }).nullable(),
})
export type Widget = z.infer<typeof Widget>
export const loadWidget = (product: string) => rpc('support_widget_get', { p_product: product }, Widget)

// ---------------------------------------------------------------------------
// Help centre
export const HelpCentre = z.object({
  measured: z.boolean(),
  can_edit: z.boolean(),
  can_publish: z.boolean(),
  categories: z.array(z.object({ key: z.string(), name: z.string() })),
  pages: z.array(z.string()),
  articles: z.array(z.object({
    id: uuid,
    group_id: uuid,
    title: z.string(),
    category_key: z.string().nullable(),
    status: z.enum(['draft', 'published']),
    locale: z.enum(LOCALES),
    locales: z.array(z.enum(LOCALES)),
    problem: z.boolean(),
    updated_at: ts,
    views: num.nullable(),
    linked_tickets: num,
  })),
})
export type HelpCentre = z.infer<typeof HelpCentre>
export const loadHelpCentre = (product: string) => rpc('help_centre_get', { p_product: product }, HelpCentre)

export const Article = z.object({
  id: uuid,
  product: z.string(),
  group_id: uuid,
  locale: z.enum(LOCALES),
  slug: z.string(),
  title: z.string(),
  body: z.string(),
  category_key: z.string().nullable(),
  status: z.enum(['draft', 'published']),
  version: num,
  problem_id: uuid.nullable(),
  problem_number: num.nullable(),
  seo_title: z.string().nullable(),
  app_pages: z.array(z.string()),
  source: z.string(),
  published_at: ts.nullable(),
  reviewed_at: ts.nullable(),
  reviewed_by: z.string().nullable(),
  updated_at: ts,
  linked_tickets: num,
  siblings: z.array(z.object({ locale: z.enum(LOCALES), id: uuid, status: z.enum(['draft', 'published']) })),
})
export type Article = z.infer<typeof Article>
export async function loadArticle(id: string): Promise<Article | null> {
  const r = await rpc('help_article_get', { p_id: id }, Article, { quiet: true })
  return r.ok ? r.data : null
}

export const SearchHits = z.array(z.object({ id: uuid, title: z.string(), snippet: z.string() }))
export type SearchHits = z.infer<typeof SearchHits>

// ---------------------------------------------------------------------------
// Contact form and email
export const Channels = z.object({
  days: num,
  total: num,
  channels: z.array(z.object({ channel: z.enum(CHANNELS), tickets: num, queues: z.array(z.string()) })),
  topics: z.array(z.object({ topic: z.string(), category_key: z.string(), category: z.string(), queue: z.string(), privacy: z.boolean(), tickets: num })),
  mail: z.object({ ready: z.boolean(), inbound_ok: z.boolean(), inbound_domain: z.string().nullable(), webhook_ok: z.boolean() }).nullable(),
})
export type Channels = z.infer<typeof Channels>
export const loadChannels = (product: string) => rpc('support_channels', { p_product: product, p_days: 30 }, Channels)

// ---------------------------------------------------------------------------
// Customer portal (an admin preview)
export const Portal = z.object({
  organizations: z.array(z.object({ id: uuid, name: z.string(), tickets: num })),
  organization: z.object({ id: uuid, name: z.string() }).nullable(),
  tickets: z.array(z.object({
    id: uuid, ref: z.string(), subject: z.string(), requester: z.string().nullable(), status: z.string(), state: z.enum(['us', 'you', 'done']),
  })),
  privacy_open: num.nullable(),
})
export type Portal = z.infer<typeof Portal>
export const loadPortal = (product: string, org: string | null) => rpc('portal_preview', { p_product: product, p_organization: org }, Portal)

// ---------------------------------------------------------------------------
// AI assist
export const Assist = z.object({
  ticket: z.object({ id: uuid, ref: z.string(), subject: z.string(), organization: z.string().nullable(), problem: z.string().nullable() }).nullable(),
  tickets: z.array(z.object({ id: uuid, ref: z.string(), subject: z.string() })),
  usage: z.object({ previews: num, used: num, calls: num, failed: num }),
  titles: z.array(z.string()),
  ai_enabled: z.boolean(),
  can_ask: z.boolean(),
})
export type Assist = z.infer<typeof Assist>
export const loadAssist = (product: string, ticket: string | null) => rpc('support_assist_get', { p_product: product, p_ticket: ticket }, Assist)

// ---------------------------------------------------------------------------
// Status and changelog
export const Status = z.object({
  can_edit: z.boolean(),
  components: z.array(z.object({ id: uuid, name: z.string(), state: z.enum(COMPONENT_STATES), updated_at: ts })),
  incidents: z.array(z.object({
    id: uuid,
    title: z.string(),
    body: z.string().nullable(),
    state: z.enum(INCIDENT_STATES),
    started_at: ts,
    resolved_at: ts.nullable(),
    notified: num.nullable(),
    problem: z.object({ id: uuid, ref: z.string(), resolved: z.boolean() }).nullable(),
    linked: num,
    customers: num,
    notice_open: z.boolean(),
    notice_cleared: z.boolean(),
    emailed: num.nullable(),
    components: z.array(uuid),
    updates: z.array(z.object({ state: z.enum(INCIDENT_STATES), body: z.string(), at: ts, by: z.string().nullable() })),
  })),
  problems: z.array(z.object({ id: uuid, ref: z.string(), subject: z.string() })),
  changelog: z.array(z.object({ id: uuid, kind: z.enum(['new', 'improved', 'fixed']), title: z.string(), published_at: ts })),
})
export type Status = z.infer<typeof Status>
export const loadStatus = (product: string) => rpc('status_get', { p_product: product }, Status)
