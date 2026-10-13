import { z } from 'zod'

/**
 * Growth v2 (SimpleGrowth.dc.html of 11 Oct 2026): the tab, the scope bar and each view's choices live in the address,
 * so a drill-down (period › day › hour), a filter or a picked row can be linked to and survives a reload. Pure: the server
 * page parses it, client parts build links with it. The database checks every value again (0073).
 */

export const TABS = ['overview', 'funnel', 'pages', 'seo', 'campaigns', 'email', 'integrations'] as const
export type Tab = (typeof TABS)[number]
/** The tabs that carry the scope bar (the design's showScope); SEO only on its Keywords view. */
export const SCOPED: readonly Tab[] = ['overview', 'funnel', 'pages', 'seo']

export const RANGES = ['today', '7d', '30d', '90d'] as const
export type Range = (typeof RANGES)[number]
export const RANGE_DAYS: Record<Range, 1 | 7 | 30 | 90> = { today: 1, '7d': 7, '30d': 30, '90d': 90 }
export const DEVICES = ['desktop', 'mobile', 'tablet'] as const
export type Device = (typeof DEVICES)[number]
export const METRICS = ['visitors', 'signups', 'accounts', 'paying'] as const
export type Metric = (typeof METRICS)[number]
export const LOG_FILTERS = ['all', 'stopped', 'account'] as const
export type LogFilter = (typeof LOG_FILTERS)[number]
export const PAGE_SORTS = ['opportunity', 'visits', 'conversion', 'slowest'] as const
export type PageSort = (typeof PAGE_SORTS)[number]
export const KW_TABS = ['all', 'top3', 'striking', 'low', 'losing', 'lowctr'] as const
export type KwTab = (typeof KW_TABS)[number]

/** `site`: one of the application's sites by its hostname (0089: a site per market); null is all of them */
export type Scope = { range: Range; day: string | null; hour: number | null; src: string | null; dev: Device | null; site?: string | null }

/** Everything a Growth address may carry. Unknown or malformed values fall back to the defaults. */
export type GrowthParams = Scope & {
  tab: Tab
  metric: Metric
  step: number
  lf: LogFilter
  page: string | null
  sort: PageSort
  sub: string | null
  kt: KwTab
  kw: string | null
  /** SEO › Topic clusters: the topic's main page */
  cl: string | null
  /** SEO › Opportunities: the kind shown, or all */
  ot: (typeof OPP_TYPES)[number]
  /** SEO › Content plan: the item whose brief is open */
  brief: string | null
  /** Marketing campaigns › Outcomes: the attribution model */
  am: (typeof MODELS)[number]
}

export const MODELS = ['first', 'last'] as const

export const OPP_TYPES = ['all', 'striking', 'low_ctr', 'gap', 'cannibal', 'decay'] as const
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)
const DAY = /^\d{4}-\d{2}-\d{2}$/

export function parseGrowth(sp: Record<string, string | string[] | undefined>): GrowthParams {
  const g = (k: string) => one(sp[k])
  // the old address (Growth › Analytics) opens the Overview
  const rawTab = g('tab') === 'analytics' ? 'overview' : g('tab')
  const tab = z.enum(TABS).catch('overview').parse(rawTab ?? 'overview')
  const range = z.enum(RANGES).catch('30d').parse(g('range') ?? '30d')
  const dayRaw = g('day')
  // «Today» is always the one day, hour by hour
  const day = range === 'today' ? null : dayRaw && DAY.test(dayRaw) ? dayRaw : null
  const hourN = Number(g('hour'))
  const hour = (day || range === 'today') && g('hour') !== undefined && Number.isInteger(hourN) && hourN >= 0 && hourN <= 23 ? hourN : null
  const src = g('src') && /^[a-z_]{2,30}$/.test(g('src')!) ? g('src')! : null
  const dev = z.enum(DEVICES).nullable().catch(null).parse(g('dev') ?? null)
  const site = g('site') && /^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(g('site')!) && g('site')!.length <= 253 ? g('site')! : null
  const stepN = Number(g('step'))
  const path = g('page')
  return {
    tab, range, day, hour, src, dev, site,
    metric: z.enum(METRICS).catch('visitors').parse(g('metric') ?? 'visitors'),
    step: Number.isInteger(stepN) && stepN >= 1 && stepN <= 7 ? stepN : 4,
    lf: z.enum(LOG_FILTERS).catch('all').parse(g('lf') ?? 'all'),
    page: path && path.startsWith('/') && path.length <= 500 ? path : null,
    sort: z.enum(PAGE_SORTS).catch('opportunity').parse(g('sort') ?? 'opportunity'),
    sub: g('sub') && /^[a-z][a-z_]{1,19}$/.test(g('sub')!) ? g('sub')! : null,
    kt: z.enum(KW_TABS).catch('all').parse(g('kt') ?? 'all'),
    kw: g('kw') && g('kw')!.length <= 200 ? g('kw')! : null,
    cl: g('cl') && g('cl')!.startsWith('/') && g('cl')!.length <= 300 ? g('cl')! : null,
    ot: z.enum(OPP_TYPES).catch('all').parse(g('ot') ?? 'all'),
    brief: g('brief') && UUID.test(g('brief')!) ? g('brief')! : null,
    am: z.enum(MODELS).catch('first').parse(g('am') ?? 'first'),
  }
}

/** The day the RPCs take: «Today» is today's date in Oslo; otherwise the drilled day, if any. */
export function scopeDay(s: Scope, todayOslo: string): string | null {
  return s.range === 'today' ? todayOslo : s.day
}

/** Today's date in Oslo, as the database counts days (0073 growth_window). */
export function osloToday(now = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Oslo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now)
}

type Extra = Partial<Omit<GrowthParams, keyof Scope | 'tab'>>
const DEFAULTS: Required<{ [K in keyof Extra]: string | number | null }> = {
  metric: 'visitors', step: 4, lf: 'all', page: null, sort: 'opportunity', sub: null, kt: 'all', kw: null, cl: null, ot: 'all', brief: null, am: 'first',
}

/**
 * A Growth address. The scope travels to the scoped tabs; defaults are left out, so the plain address is the Overview
 * of the last 30 days.
 */
export function growthHref(tab: Tab, scope: Partial<Scope>, extra: Extra = {}): string {
  const q = new URLSearchParams()
  if (tab !== 'overview') q.set('tab', tab)
  if (SCOPED.includes(tab)) {
    if (scope.range && scope.range !== '30d') q.set('range', scope.range)
    if (scope.day && scope.range !== 'today') q.set('day', scope.day)
    if (scope.hour !== null && scope.hour !== undefined && (scope.day || scope.range === 'today')) q.set('hour', String(scope.hour))
    if (scope.src) q.set('src', scope.src)
    if (scope.dev) q.set('dev', scope.dev)
    if (scope.site) q.set('site', scope.site)
  }
  for (const [k, v] of Object.entries(extra) as [keyof Extra, string | number | null | undefined][]) {
    if (v === null || v === undefined || v === DEFAULTS[k]) continue
    q.set(k, String(v))
  }
  const s = q.toString()
  return s ? `/growth?${s}` : '/growth'
}
