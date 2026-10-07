/**
 * The design's navigation (Sentral Admin.dc.html, NAV): route key, address, group and icon. Labels are
 * message keys (shell.nav.<key>, shell.crumb.<group>). The design's buttons become links (control
 * substitution: the prototype has no router).
 */
export const ICON = {
  dashboard: 'M4 4h7v7H4zM13 4h7v4h-7zM13 10h7v10h-7zM4 13h7v7H4z',
  building: 'M5 21V5a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v16M15 10h3a1 1 0 0 1 1 1v10M3 21h18M8 8h3M8 12h3M8 16h3',
  pulse: 'M3 12h4l2-5 4 10 2-5h6',
  users: 'M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20M10 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7M20 20v-1.5a3.5 3.5 0 0 0-2.5-3.35M15.5 4.2a3.5 3.5 0 0 1 0 6.6',
  ticket: 'M4 8a2 2 0 0 0 0 4v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4a2 2 0 0 1 0-4V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1zM14 4v13',
  target: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8M12 12h.01',
  kanban: 'M4 4h4v16H4zM10 4h4v10h-4zM16 4h4v6h-4z',
  inbox: 'M4 13l2.5-8h11L20 13v6H4zM4 13h5l1 2h4l1-2h5',
  mail: 'M4 6h16v12H4zM4 7l8 6 8-6',
  contacts: 'M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6zM12 12a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5M8.5 17a3.5 3.5 0 0 1 7 0M4 7h2M4 12h2M4 17h2',
  list: 'M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01',
  filter: 'M4 5h16l-6 7.5V19l-4 1v-7.5z',
  template: 'M5 4h14v16H5zM8 8h8M8 12h8M8 16h5',
  flag: 'M5 21V4M5 4h11l-2 4 2 4H5',
  chart: 'M4 20V4M4 20h16M8 16v-4M12 16V8M16 16v-6',
  coins: 'M9 11a5 3 0 1 0 0-.01M4 11v4c0 1.66 2.24 3 5 3s5-1.34 5-3v-4M14 7.3c.6-.2 1.3-.3 2-.3 2.76 0 5 1.34 5 3v4c0 1.4-1.6 2.6-3.8 2.9',
  search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14M20 20l-4-4',
  puzzle: 'M9 4h4v2a1.5 1.5 0 0 0 3 0V4h4v4h-2a1.5 1.5 0 0 0 0 3h2v4h-4v-2a1.5 1.5 0 0 0-3 0v2H9v-4H7a1.5 1.5 0 0 1 0-3h2zM9 15v5h11v-5',
  globe: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3',
  activity: 'M4 12h3l3 7 4-14 3 7h3',
  log: 'M8 4h8l3 3v13H5V4zM9 10h6M9 14h6M9 18h3',
  shield: 'M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6zM9 12l2 2 4-4',
  page: 'M7 3h7l5 5v13H7zM14 3v5h5M10 13h6M10 17h6',
  redirect: 'M4 17V9a3 3 0 0 1 3-3h11M15 3l3 3-3 3M20 21H10',
  close: 'M6 6l12 12M18 6L6 18',
  calendar: 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',
  phone: 'M7 3h10v18H7zM11 18h2',
  mic: 'M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3M5 11a7 7 0 0 0 14 0M12 18v3',
  bolt: 'M13 3L5 14h6l-1 7 8-11h-6z',
  sliders: 'M4 7h10M18 7h2M4 17h4M12 17h8M16 5v4M10 15v4',
  bell: 'M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20a2 2 0 0 0 4 0',
  chevron: 'M6 9l6 6 6-6',
  plus: 'M12 5v14M5 12h14',
} as const

export type RouteKey =
  | 'crm' | 'growth' | 'platform'
  | 'home' | 'customers' | 'analytics' | 'tickets' | 'feed' | 'leads' | 'deals' | 'contacts' | 'activities' | 'inbox' | 'meetings'
  | 'projects' | 'documents' | 'campaigns' | 'leadgen' | 'visitors' | 'automation' | 'insights' | 'apps' | 'settings'
  | 'security' | 'mobile' | 'coverage' | 'api'

export type Group = 'all' | 'customers' | 'crm' | 'growth' | 'platform'

export const ROUTES: Record<RouteKey, { path: string; group: Group; icon: keyof typeof ICON }> = {
  // the four sections of Sentral Simple (design-reference/sentral-simple); customers below is the first of them
  crm: { path: '/crm', group: 'crm', icon: 'kanban' },
  growth: { path: '/growth', group: 'growth', icon: 'chart' },
  platform: { path: '/platform', group: 'platform', icon: 'puzzle' },
  home: { path: '/overview', group: 'all', icon: 'dashboard' },
  customers: { path: '/customers', group: 'customers', icon: 'building' },
  analytics: { path: '/analytics', group: 'customers', icon: 'chart' },
  tickets: { path: '/tickets', group: 'customers', icon: 'ticket' },
  feed: { path: '/feed', group: 'crm', icon: 'pulse' },
  leads: { path: '/leads', group: 'crm', icon: 'filter' },
  deals: { path: '/deals', group: 'crm', icon: 'kanban' },
  contacts: { path: '/contacts', group: 'crm', icon: 'contacts' },
  activities: { path: '/activities', group: 'crm', icon: 'calendar' },
  inbox: { path: '/inbox', group: 'crm', icon: 'inbox' },
  meetings: { path: '/meetings', group: 'crm', icon: 'mic' },
  projects: { path: '/projects', group: 'crm', icon: 'flag' },
  documents: { path: '/documents', group: 'crm', icon: 'page' },
  campaigns: { path: '/campaigns', group: 'growth', icon: 'mail' },
  leadgen: { path: '/lead-capture', group: 'growth', icon: 'target' },
  visitors: { path: '/web-visitors', group: 'growth', icon: 'globe' },
  automation: { path: '/automation', group: 'growth', icon: 'bolt' },
  insights: { path: '/insights', group: 'growth', icon: 'activity' },
  apps: { path: '/applications', group: 'platform', icon: 'puzzle' },
  api: { path: '/api', group: 'platform', icon: 'redirect' },
  settings: { path: '/settings', group: 'platform', icon: 'sliders' },
  security: { path: '/security', group: 'platform', icon: 'shield' },
  mobile: { path: '/mobile', group: 'platform', icon: 'phone' },
  coverage: { path: '/coverage', group: 'platform', icon: 'list' },
}

/**
 * Sentral Simple's rail («Sentral Simple.dc.html»): four sections, each a label and a sub-label (shell.section.<key>) and
 * the design's own icon. Every other route stays reachable by address (and from the account menu) but is not in the rail.
 */
export type SectionKey = 'customers' | 'crm' | 'growth' | 'platform'
export const SECTIONS: { key: SectionKey; icon: string }[] = [
  { key: 'customers', icon: 'M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20M10 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7M20 20v-1.5a3.5 3.5 0 0 0-2.5-3.35M15.5 4.2a3.5 3.5 0 0 1 0 6.6' },
  { key: 'crm', icon: 'M4 4h4v16H4zM10 4h4v10h-4zM16 4h4v6h-4z' },
  { key: 'growth', icon: 'M4 20V4M4 20h16M8 16v-4M12 16V8M16 16v-6' },
  { key: 'platform', icon: 'M9 4h4v2a1.5 1.5 0 0 0 3 0V4h4v4h-2a1.5 1.5 0 0 0 0 3h2v4h-4v-2a1.5 1.5 0 0 0-3 0v2H9v-4H7a1.5 1.5 0 0 1 0-3h2z' },
]

/** The full interface's navigation, kept for the routes the rail no longer lists (titles, access). */
export const NAV: { group: Group | null; items: RouteKey[] }[] = [
  { group: null, items: ['home'] },
  { group: 'customers', items: ['customers', 'analytics', 'tickets'] },
  { group: 'crm', items: ['feed', 'leads', 'deals', 'contacts', 'activities', 'inbox', 'meetings', 'projects', 'documents'] },
  { group: 'growth', items: ['campaigns', 'leadgen', 'visitors', 'automation', 'insights'] },
  { group: 'platform', items: ['apps', 'api', 'settings', 'security', 'mobile', 'coverage'] },
]

/** The module switch that hides a route (Settings › Modules). */
export const MODULE_OF: Partial<Record<RouteKey, string>> = {
  deals: 'deals', leads: 'leads', projects: 'projects', campaigns: 'campaigns', documents: 'documents', meetings: 'meetings',
  leadgen: 'leadgen', visitors: 'visitors', mobile: 'mobile',
}

/**
 * The rights that open a route: any one of them is enough; none listed is every staff member. Mirrors the guard of the
 * page's main read (its `app.require`), so the menu offers only what the person can open — the database refuses anyway.
 * Platform, Automation, Insights, API, Settings, Security and Coverage have a view for everyone (team list, one's own workflows, dashboards,
 * tokens, settings and sessions).
 */
export const ACCESS: Partial<Record<RouteKey, readonly `${'deals' | 'projects' | 'campaigns' | 'tickets' | 'global'}:${string}`[]>> = {
  // Simple: Customers holds accounts and tickets; Growth is the marketing view (design: «Sales: CRM»), opened by a reports
  // right — Marketing and Read-only hold one, Sales has campaigns:see for CRM › Lists only (0057)
  customers: ['deals:see', 'tickets:see'],
  crm: ['deals:see'],
  growth: ['global:reports_others', 'campaigns:reports_others'],
  analytics: ['global:reports_others', 'campaigns:reports_others'],
  tickets: ['tickets:see'],
  feed: ['deals:see'], leads: ['deals:see'], deals: ['deals:see'], contacts: ['deals:see'], activities: ['deals:see'],
  inbox: ['deals:see'], meetings: ['deals:see'], documents: ['deals:see'], mobile: ['deals:see'],
  projects: ['projects:see'],
  campaigns: ['campaigns:see'],
  leadgen: ['campaigns:see', 'deals:see'],
  visitors: ['campaigns:see', 'deals:see'],
  apps: ['global:see'],
}

/** Is this route in the menu for this person: their rights, the module switch, and the meeting workspace. */
export function routeVisible(
  key: RouteKey,
  who: { admin: boolean; rights: readonly string[]; modules: Record<string, boolean>; meetingsWorkspace?: boolean },
): boolean {
  const mod = MODULE_OF[key]
  if (mod && who.modules[mod] === false) return false
  if (key === 'meetings' && who.meetingsWorkspace === false) return false
  const need = ACCESS[key]
  return who.admin || !need || need.some((r) => who.rights.includes(r))
}

export function routeOf(pathname: string): RouteKey {
  const hit = (Object.entries(ROUTES) as [RouteKey, (typeof ROUTES)[RouteKey]][])
    .filter(([, r]) => r.path === '/' ? pathname === '/' : pathname === r.path || pathname.startsWith(`${r.path}/`))
  return hit[0]?.[0] ?? 'home'
}

export const pathOf = (key: RouteKey) => ROUTES[key].path
