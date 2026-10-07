import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'
import { DELIVERY_STATES, HEALTH, JOB_STATES, WEBHOOK_STATES } from './platform-shared'

/**
 * The Platform screen's reads (0044_platform.sql; contract docs/crm-enrichment/deviations/platform-schema.md). Every
 * answer is parsed, never cast. Nothing here reads a secret: the database reports whether one exists, and a token's or
 * webhook secret's plaintext only ever travels in the answer to the action that made it.
 */
const ts = z.string().nullable()
const num = z.number()
const numN = z.number().nullable()

export const HealthZ = z.object({
  status: z.enum(HEALTH),
  calls_15m: num,
  calls_per_min: num,
  p95_ms: numN,
  error_rate: numN,
  last_event_at: ts,
  last_ping_at: ts,
  last_ping_ok: z.boolean().nullable(),
  last_ping_ms: numN,
})
export type HealthT = z.infer<typeof HealthZ>

export const AppCardZ = z.object({
  key: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  color: z.string().nullable(),
  ink: z.string().nullable(),
  stage: z.enum(['ga', 'beta']),
  installed: z.boolean(),
  region: z.string().nullable(),
  health: HealthZ,
  orgs: num,
  spark: z.array(num),
})
export type AppCard = z.infer<typeof AppCardZ>

export const AppDetailZ = z.object({
  key: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  stage: z.enum(['ga', 'beta']),
  installed: z.boolean(),
  health: HealthZ,
  connection: z.object({
    api_url: z.string().nullable(),
    api_version: z.string().nullable(),
    region: z.string().nullable(),
    enabled: z.boolean(),
    scopes: z.array(z.string()),
    token_secret: z.boolean(),
    webhook_secret: z.boolean(),
    event_kinds_30d: num,
    last_sync_at: ts,
    connected_since: ts,
    last_ping_at: ts,
    last_ping_ok: z.boolean().nullable(),
    last_ping_ms: numN,
    last_ping_status: numN,
  }).nullable(),
  synced: z.object({
    organizations: num, organizations_last: ts,
    users: num, users_last: ts,
    subscriptions: num, subscriptions_last: ts,
    usage_events_24h: num, usage_last: ts,
    flags: numN,
  }),
  events: z.array(z.object({ kind: z.string(), count: num, uses: z.array(z.string()), label_key: z.string().nullable() })),
  commands: z.array(z.object({ command: z.string(), scope: z.string(), used_by: z.array(z.string()), destructive: z.boolean(), allowed: z.boolean() })),
})
export type AppDetail = z.infer<typeof AppDetailZ>

export const FlagsZ = z.object({
  modules: z.array(z.object({ key: z.string(), enabled: z.boolean(), updated_at: ts })),
  products: z.array(z.object({ key: z.string(), name: z.string(), flags_command: z.boolean(), pilots_command: z.boolean(), set_command: z.boolean(), active_tenants: num })),
})
export type Flags = z.infer<typeof FlagsZ>

export const NoticeZ = z.object({
  notice_command: z.boolean(),
  maintenance_command: z.boolean(),
  current: z.object({
    id: z.string(), text: z.string().nullable(), maintenance: z.boolean(), problem_ticket_id: z.string().nullable(), problem_number: z.union([z.number(), z.string()]).nullable(),
    set_at: z.string(), pushed_at: ts, push_error: z.string().nullable(),
  }).nullable(),
  history: z.array(z.object({ id: z.string(), text: z.string().nullable(), maintenance: z.boolean(), set_at: z.string(), cleared_at: ts, set_by: z.string().nullable() })),
})
export type Notice = z.infer<typeof NoticeZ>

const cmd = z.object({ command: z.string().nullable() })
export const ContentZ = z.object({
  help: z.object({ articles: num, published: num, last_change: ts, macros: num }),
  cards: z.object({ question_set: cmd, pulse_templates: cmd, tiltak: cmd, legal: cmd, templates: cmd, modules: cmd }),
  draft_command: z.boolean(),
  rollback_command: z.boolean(),
})
export type Content = z.infer<typeof ContentZ>

const RunZ = z.object({ id: num, state: z.enum(JOB_STATES), at: ts, info: z.record(z.string(), z.unknown()), error: z.string().nullable() })
export const JobsZ = z.object({
  stats: z.object({ queued: num, running: num, failed_24h: num, succeeded_24h: num }),
  jobs: z.array(z.object({
    key: z.string(), label_key: z.string(), product: z.string().nullable(), schedule: z.string().nullable(), source: z.enum(['cron', 'queue', 'product']),
    quiet: z.boolean(), last_run_at: ts, last_state: z.enum(JOB_STATES).nullable(), last_run: RunZ.nullable(),
  })),
})
export type Jobs = z.infer<typeof JobsZ>

export const ApiOverviewZ = z.object({
  endpoints: z.array(z.object({ method: z.string(), path: z.string(), op: z.string(), entity: z.string().nullable(), cost: numN })),
  tokens: z.array(z.object({
    id: z.string(), kind: z.literal('personal'), name: z.string(), staff: z.string().nullable(), masked: z.string(), scopes: z.array(z.string()),
    created_at: z.string(), last_used_at: ts, expires_at: ts, mine: z.boolean(),
  })),
  grants: z.array(z.object({
    id: z.string(), kind: z.string(), app: z.string(), client: z.string(), staff: z.string().nullable(), scopes: z.array(z.string()),
    created_at: z.string(), last_used_at: ts, mine: z.boolean(),
  })),
  has_token: z.boolean(),
  rate: z.object({ mode: z.string(), budget_day: numN, used_today: numN, burst_token: numN, burst_oauth: numN, burst_search: numN }),
  usage: z.array(z.object({ hour: z.string(), requests: num })),
  usage_scope: z.enum(['company', 'mine']),
})
export type ApiOverview = z.infer<typeof ApiOverviewZ>

export const OauthAppsZ = z.array(z.object({
  id: z.string(), client_id: z.string(), name: z.string(), kind: z.enum(['integration', 'mcp', 'extension']), redirect_uris: z.array(z.string()),
  allowed_scopes: z.array(z.string()), confidential: z.boolean(), dynamic: z.boolean(), owner: z.string().nullable(), created_at: z.string(),
  disabled_at: ts, grants: num,
}))
export type OauthApp = z.infer<typeof OauthAppsZ>[number]

export const WebhooksZ = z.object({
  webhooks: z.array(z.object({
    id: z.string(), owner_id: z.string(), owner: z.string().nullable(), event_kind: z.string(), url: z.string(), state: z.enum(WEBHOOK_STATES),
    banned_until: ts, retrying: z.boolean(), last_success_at: ts, failing_since: ts, created_at: z.string(), version: num, mine: z.boolean(),
  })),
  deliveries: z.array(z.object({
    id: z.string(), webhook_id: z.string(), at: z.string(), event: z.string(), host: z.string().nullable(), status: numN, state: z.enum(DELIVERY_STATES),
    attempt: num, attempts: num, error: z.string().nullable(),
  })),
  kinds: z.array(z.string()),
  limit: numN,
  count_limits: z.string(),
  policy: z.record(z.string(), z.unknown()),
  can_manage_all: z.boolean(),
})
export type Webhooks = z.infer<typeof WebhooksZ>

export const DeliveryRowsZ = z.array(z.object({
  id: z.string(), event_id: num, event: z.string(), attempt: num, attempts: num, redelivery: num, state: z.enum(DELIVERY_STATES),
  scheduled_at: z.string(), sent_at: ts, status: numN, duration_ms: numN, error: z.string().nullable(),
}))
export type DeliveryRow = z.infer<typeof DeliveryRowsZ>[number]

/** One delivery as logged (V-P8P-01): the envelope with the changed fields' names, the body's hash and size — never a body. */
export const DeliveryZ = z.object({
  id: z.string(), event: z.string(), attempt: num, attempts: num, state: z.enum(DELIVERY_STATES), status: numN, duration_ms: numN, error: z.string().nullable(),
  scheduled_at: z.string(), sent_at: ts, envelope: z.record(z.string(), z.unknown()).nullable(), body_sha256: z.string().nullable(), bytes: numN,
  signature_header: z.string(), signed_at: numN,
})
export type Delivery = z.infer<typeof DeliveryZ>

export const CatalogZ = z.object({
  query: z.string().nullable(),
  items: z.array(z.object({
    key: z.string(), collection: z.string(), provider: z.string().nullable(), connection: z.enum(['company', 'per_user', 'api', 'extension']),
    access: z.array(z.string()), tags: z.array(z.string()), first_party: z.boolean(), installed: z.boolean(), company_connected: z.boolean().nullable(),
    mine: z.boolean(), users: num, score: num, match: z.boolean(),
  })),
})
export type Catalog = z.infer<typeof CatalogZ>

export const McpZ = z.object({
  access: z.string(),
  sync: z.string(),
  connected: num,
  last_index_at: ts,
  assistants: z.array(z.object({ id: z.string(), app: z.string(), staff: z.string().nullable(), last_used_at: ts, created_at: z.string(), mine: z.boolean() })),
  tools: z.array(z.object({ name: z.string(), op: z.string(), entity: z.string().nullable() })),
  can_configure: z.boolean(),
})
export type Mcp = z.infer<typeof McpZ>

export const loadApplications = () => rpcOrThrow('applications_get', {}, z.array(AppCardZ))
export const loadApplication = (key: string) => rpc('application_get', { p_product: key }, AppDetailZ)
export const loadFlags = () => rpcOrThrow('flags_get', {}, FlagsZ)
export const loadNotice = (key: string) => rpc('status_notice_get', { p_product: key }, NoticeZ)
export const loadContent = (key: string) => rpc('content_get', { p_product: key }, ContentZ)
export const loadJobs = () => rpcOrThrow('jobs_get', { p_filter: {} }, JobsZ)
export const loadApiOverview = () => rpcOrThrow('api_overview', {}, ApiOverviewZ)
export const loadOauthApps = () => rpcOrThrow('oauth_apps_get', {}, OauthAppsZ)
export const loadWebhooks = () => rpcOrThrow('webhooks_get', { p_filter: {} }, WebhooksZ)
export const loadDeliveries = (webhook: string) => rpc('webhook_deliveries_get', { p_webhook: webhook, p_cursor: null }, DeliveryRowsZ)
export const loadDelivery = (id: string) => rpc('webhook_delivery_get', { p_id: id }, DeliveryZ)
export const loadCatalog = (q: string | null) => rpc('integration_catalog_get', { p_q: q }, CatalogZ)
export const loadMcp = () => rpcOrThrow('mcp_get', {}, McpZ)
