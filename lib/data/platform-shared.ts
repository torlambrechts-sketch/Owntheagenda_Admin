/**
 * The Platform screen's shared vocabulary (Platform.dc.html): its eight tabs, where each lives, and the closed lists the
 * database checks. Client-safe: no server code here.
 */
export const PLATFORM_TABS = ['apps', 'api', 'hooks', 'catalog', 'mcp', 'jobs', 'flags', 'content'] as const
export type PlatformTab = (typeof PLATFORM_TABS)[number]

/**
 * Two routes carry the eight tabs (the shell's Applications and API and integrations): the operational tabs under
 * /applications, the developer-facing ones under /api. Each route's own tab is its default.
 */
export const TAB_HREF: Record<PlatformTab, string> = {
  apps: '/applications',
  jobs: '/applications?tab=jobs',
  flags: '/applications?tab=flags',
  content: '/applications?tab=content',
  api: '/api',
  hooks: '/api?tab=hooks',
  catalog: '/api?tab=catalog',
  mcp: '/api?tab=mcp',
}

export const HEALTH = ['operational', 'degraded', 'unreachable', 'no_data', 'disabled', 'not_installed'] as const
export type Health = (typeof HEALTH)[number]

/** The scopes a product's installation may hold: the real command scopes (0044 application_connect), not the design's chips. */
export const PRODUCT_SCOPES = [
  'orgs:read', 'orgs:write', 'billing:read', 'billing:write', 'translations:read', 'translations:write',
  'modules:read', 'modules:write', 'legal:read', 'legal:write', 'settings:read', 'settings:write',
] as const

/**
 * The API scopes an OAuth app may ask for (0044 app.api_scopes). No RPC lists them yet (R-PLATFORM-02); the database
 * refuses any other value (app.scopes_ok), so this list can only be narrower than the truth, never wider.
 */
export const API_SCOPES = ['*', 'deals:read', 'deals:write', 'projects:read', 'projects:write', 'campaigns:read', 'campaigns:write', 'tickets:read', 'tickets:write', 'global:read'] as const

export const CATALOG_COLLECTIONS = ['productivity_mail', 'team_chat', 'close_paid', 'automate'] as const

export const WEBHOOK_STATES = ['active', 'paused', 'banned', 'blocked', 'deleted'] as const
export const DELIVERY_STATES = ['queued', 'sent', 'failed', 'skipped'] as const
export const JOB_STATES = ['queued', 'running', 'succeeded', 'failed'] as const
