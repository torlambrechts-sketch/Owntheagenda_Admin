import 'server-only'
import { z } from 'zod'
import { rpcOrThrow } from '@/lib/rpc'
import { loadApplication, loadApplications, loadFlags, loadNotice, type Notice } from './platform'
import { Staff } from './settings'
import type { Health } from './platform-shared'
import { isCommandProduct } from '@/supabase/functions/_shared/commands.ts'

/**
 * Sentral Simple › Platform (design-reference/sentral-simple/SimplePlatform.dc.html): the reads behind Applications, Plans and
 * prices and Team. They reuse the Platform screen's loaders (0044) and Settings' staff schema; 0057 adds plan_accounts and
 * staff_list's role fields. The four tabs PlatformPlus.dc.html adds read through lib/data/platform-plus.ts (0082).
 * Every answer is parsed. No secret is read: the database says only whether one exists.
 */
/** the design's seven tabs in its order (v3): Applications · Rollouts and announcements · Plans and prices · Billing portal ·
 *  Customer success · Team · Roles and approvals */
export const SIMPLE_PLATFORM_TABS = ['apps', 'ops', 'plans', 'billing', 'success', 'team', 'access'] as const
export type SimplePlatformTab = (typeof SIMPLE_PLATFORM_TABS)[number]

// ---------------------------------------------------------------------------
// Applications
export type SimpleApp = {
  key: string
  name: string
  description: string | null
  color: string | null
  ink: string | null
  installed: boolean
  status: Health
  orgs: number
  p95_ms: number | null
  error_rate: number | null
  /** the installation's host and the product's API version, as the connection reports them */
  host: string | null
  version: string | null
  /** Test connection goes through product-command, which reaches a product with a command registry (_shared/commands.ts) */
  testable: boolean
  /** the product offers settings.set_maintenance (none does yet: D-40) */
  maintenance: boolean
  /** whether Vault holds the product's token and webhook secrets (never their values) */
  token_secret: boolean | null
  webhook_secret: boolean | null
}

const hostOf = (url: string | null) => {
  if (!url) return null
  try { return new URL(url).host } catch { return null }
}

export async function loadAppsTab(product: string): Promise<{
  apps: SimpleApp[]
  notice: Notice | null
  flags: { flags_command: boolean; set_command: boolean } | null
}> {
  const cards = await loadApplications()
  const [details, flags, notice] = await Promise.all([
    Promise.all(cards.map((c) => (c.installed ? loadApplication(c.key) : null))),
    loadFlags(),
    loadNotice(product),
  ])
  const apps = cards.map((c, i): SimpleApp => {
    const d = details[i]
    const detail = d && d.ok ? d.data : null
    const conn = detail?.connection ?? null
    const has = (cmd: string) => !!detail?.commands.some((x) => x.command === cmd)
    return {
      key: c.key, name: c.name, description: c.description, color: c.color, ink: c.ink, installed: c.installed,
      status: c.health.status, orgs: c.orgs, p95_ms: c.health.p95_ms, error_rate: c.health.error_rate,
      host: hostOf(conn?.api_url ?? null), version: conn?.api_version ?? null,
      testable: isCommandProduct(c.key) && has('orgs.list') && !!conn?.enabled,
      maintenance: has('settings.set_maintenance'),
      token_secret: conn ? conn.token_secret : null, webhook_secret: conn ? conn.webhook_secret : null,
    }
  })
  const f = flags.products.find((p) => p.key === product)
  return { apps, notice: notice.ok ? notice.data : null, flags: f ? { flags_command: f.flags_command, set_command: f.set_command } : null }
}

// ---------------------------------------------------------------------------
// Plans and prices: the plan catalogue (billing_overview, 0013) and live accounts per band (plan_accounts, 0057)
const PlanZ = z.object({
  product: z.string(),
  band_label: z.string(),
  min_employees: z.number(),
  max_employees: z.number().nullable(),
  monthly_price: z.coerce.number(),
  annual_price: z.coerce.number().nullable(),
  version: z.number(),
  valid_from: z.string(),
})
export type SimplePlan = z.infer<typeof PlanZ> & { accounts: number | null }

export async function loadPlansTab(product: string): Promise<SimplePlan[]> {
  const [billing, accounts] = await Promise.all([
    rpcOrThrow('billing_overview', { p_product: product }, z.object({ plans: z.array(PlanZ) })),
    rpcOrThrow('plan_accounts', { p_product: product }, z.array(z.object({ band_label: z.string(), accounts: z.number() }))),
  ])
  // one card per band: its newest active version
  const newest = new Map<string, z.infer<typeof PlanZ>>()
  for (const p of billing.plans.filter((x) => x.product === product)) {
    const had = newest.get(p.band_label)
    if (!had || p.version > had.version) newest.set(p.band_label, p)
  }
  return [...newest.values()]
    .sort((a, b) => a.min_employees - b.min_employees)
    .map((p) => ({ ...p, accounts: accounts.find((a) => a.band_label === p.band_label)?.accounts ?? null }))
}

// ---------------------------------------------------------------------------
// Team and roles: staff_list with 0057's role fields, and the sets the role select may offer (access_model)
const TeamMemberZ = Staff.extend({
  permission_set_key: z.string().nullable(),
  owner: z.boolean(),
  /** null without global:security, as the address and the last activity */
  login: z.boolean().nullable(),
  /** the invitation email (0060): queued, sent or failed; null without global:security or when none was asked for */
  invite_state: z.enum(['queued', 'sent', 'failed']).nullable().optional(),
  invite_sent_at: z.string().nullable().optional(),
})
export type TeamMember = z.infer<typeof TeamMemberZ>

const RoleZ = z.object({ id: z.string().uuid(), key: z.string().nullable(), name: z.string(), offered: z.boolean() })
export type Role = z.infer<typeof RoleZ>

export async function loadTeamTab(): Promise<{ team: TeamMember[]; roles: Role[] }> {
  const [team, model] = await Promise.all([
    rpcOrThrow('staff_list', {}, z.array(TeamMemberZ)),
    rpcOrThrow('access_model', {}, z.object({ permission_sets: z.array(RoleZ) })),
  ])
  return { team, roles: model.permission_sets }
}
