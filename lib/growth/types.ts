import { z } from 'zod'

/**
 * The shapes Growth v2's reads return (0073), parsed at the boundary and shared by the server page and its client parts.
 * A figure the database could not know is null and is rendered as «—», never as 0.
 */
const n = z.number()
const nn = z.number().nullable()
const uuid = z.string().uuid()

export const GrowthScope = z.object({
  days: n,
  day: z.string().nullable(),
  hour: nn,
  from: z.string(),
  to: z.string(),
  tracked_since: z.string().nullable(),
  site: z.object({ id: uuid, hostname: z.string() }).nullable(),
  updated_at: z.string().nullable(),
  kpis: z.object({
    visitors: nn, visitors_prev: nn, started: nn, started_prev: nn, accounts: nn, accounts_prev: nn,
    paying: nn, paying_prev: nn, spend: nn, spend_prev: nn,
  }),
  // the period's days ('YYYY-MM-DD') or the day's hours ('0'…'23')
  series: z.array(z.object({ at: z.string(), visitors: nn, started: nn, accounts: nn, paying: nn })),
  peak_hour: nn,
  devices: z.array(z.object({ device: z.string(), visits: n, started: n })),
  channels: z.array(z.object({ channel: z.string(), visits: nn, started: nn, accounts: nn, paying: nn })),
})
export type GrowthScope = z.infer<typeof GrowthScope>

export const TrailStep = z.object({
  kind: z.enum(['view', 'event']), at: z.string(), path: z.string().nullable().optional(), name: z.string().optional(), value: z.string().nullable().optional(),
})
export const LogRow = z.object({
  at: z.string(), visitor: z.string(), channel: z.string(), source: z.string().nullable(), device: z.string(), entry: z.string().nullable(),
  reached: n, seconds: nn, exit: z.string().nullable(), trail: z.array(TrailStep),
})
export type LogRow = z.infer<typeof LogRow>

export const GrowthFunnel = z.object({
  days: n,
  step: n,
  tracked_since: z.string().nullable(),
  steps: z.array(z.object({ key: n, count: nn, prev: nn })),
  median_seconds: nn,
  reasons: z.array(z.object({ kind: z.enum(['exit', 'error']), value: z.string(), count: n })),
  stopped: nn,
  segments: z.array(z.object({ kind: z.enum(['channel', 'device']), key: z.string(), entered: n, continued: n })),
  log_total: n,
  log: z.array(LogRow),
})
export type GrowthFunnel = z.infer<typeof GrowthFunnel>

export const Landing = z.object({
  path: z.string(), visits: n, bounce: n, started: n, title: z.string().nullable(), lcp_ms: nn, inp_ms: nn, cls: nn,
})
export type Landing = z.infer<typeof Landing>
export const Vitals = z.object({ lcp_ms: nn, inp_ms: nn, cls: nn, score: nn, field: z.boolean(), fetched_at: z.string() })
export const GrowthPages = z.object({
  days: n,
  path: z.string().nullable(),
  tracked: z.boolean(),
  landing: z.array(Landing),
  page: z.object({
    path: z.string(), title: z.string().nullable(), visits: n, started: n,
    daily: z.array(z.object({ day: z.string(), visits: n })),
    vitals: Vitals.nullable(),
    sources: z.array(z.object({ channel: z.string(), visits: n })),
    // the page in Google search over the keywords' period, its unnamed searches included, and what its named searches
    // account for (0090); null before the pages' own figures are imported
    google: z.object({ days: n, impressions: n, clicks: n, position: nn, named_impressions: n, named_clicks: n }).nullable().optional(),
    keywords: z.array(z.object({ query: z.string(), impressions: n, position: nn })),
  }).nullable(),
  referrers: z.array(z.object({ host: z.string(), channel: z.string().nullable(), visits: n, started: n, prev: n, first_seen: z.string().nullable(), is_new: z.boolean() })),
  ctas: z.array(z.object({ value: z.string(), path: z.string().nullable(), clicks: n, sessions: n, page_sessions: n, started: n })),
})
export type GrowthPages = z.infer<typeof GrowthPages>

export const KeywordHistory = z.object({
  query: z.string(),
  days: n,
  points: z.array(z.object({ day: z.string(), position: nn, impressions: n, clicks: n })),
  pages: z.array(z.object({ page: z.string(), impressions: n, clicks: n })),
})
export type KeywordHistory = z.infer<typeof KeywordHistory>

export const GrowthIntegrations = z.object({
  can_manage: z.boolean(),
  tracker: z.object({
    sites: z.array(z.object({ hostname: z.string(), aliases: z.array(z.string()), last_seen_at: z.string().nullable() })),
    last_seen_at: z.string().nullable(),
    sessions_24h: n,
  }),
  search_console: z.object({
    status: z.string(), property: z.string().nullable(), last_import_at: z.string().nullable(), last_error: z.string().nullable(),
    /** each site's property (0089: a site per market) */
    sites: z.array(z.object({ hostname: z.string(), property: z.string().nullable(), last_import_at: z.string().nullable(), last_error: z.string().nullable() })).catch([]),
  }).nullable(),
  pagespeed: z.object({ status: z.string().nullable(), last_error: z.string().nullable(), key_stored: z.boolean(), last_at: z.string().nullable(), pages: n }),
  crawler: z.object({ last_at: z.string(), pages: n, error: z.string().nullable() }).nullable(),
  products: z.array(z.object({ product: z.string(), name: z.string(), last_event_at: z.string().nullable(), events_24h: n })),
  email: z.object({ status: z.string() }).nullable(),
  log: z.array(z.object({
    at: z.string(), source: z.string(), rows: nn, state: z.enum(['ok', 'warning', 'failed']),
    info: z.record(z.string(), z.unknown()),
  })),
})
export type GrowthIntegrations = z.infer<typeof GrowthIntegrations>
