import 'server-only'
import { z } from 'zod'
import { rpcOrThrow } from '@/lib/rpc'

/**
 * Platform › the new tabs (design-reference/sentral-simple/PlatformPlus.dc.html; 0082): Roles and approvals, Customer success,
 * Rollouts and announcements, Billing portal. Every answer is parsed. Each read is made under its own right in the database;
 * a value without a source comes back null and is shown as «—».
 */
const id = z.string().uuid()
const count = z.coerce.number().int()
const money = z.coerce.number()

// ---------------------------------------------------------------------------
// Roles and approvals
export const MODES = ['allow', 'approve', 'deny'] as const
export type Mode = (typeof MODES)[number]
const Cell = z.enum(['allow', 'approve', 'deny', 'none'])
export type CellMode = z.infer<typeof Cell>

const ActionZ = z.object({
  key: z.string().regex(/^[a-z_]+\.[a-z_]+$/),
  enforced: z.enum(['command', 'database', 'right', 'none']),
  basis_right: z.string().nullable(),
  approvable: z.boolean(),
})
export type StaffAction = z.infer<typeof ActionZ>

const MatrixZ = z.object({
  roles: z.array(z.object({ id, key: z.string().nullable(), name: z.string() })),
  actions: z.array(ActionZ),
  cells: z.record(z.string(), z.record(z.string(), Cell)),
  // per role, the actions its rights reach: the only cells the matrix can open (it narrows a role, never widens it)
  reach: z.record(z.string(), z.array(z.string())),
  // the actions a setting holds at «needs approval» (Settings › Second admin: account.delete, D-30)
  forced: z.array(z.string()),
  manage: z.enum(MODES),
})
export type AccessMatrix = z.infer<typeof MatrixZ>

const ApprovalZ = z.object({
  id,
  ref: count,
  action: z.string(),
  product: z.string().nullable(),
  state: z.enum(['pending', 'approved', 'rejected', 'executing', 'executed', 'failed', 'expired']),
  organization: z.object({ id, name: z.string() }).nullable(),
  days: count.nullable(),
  policy: z.object({
    set: z.string(),
    set_key: z.string().nullable(),
    set_name: z.string().nullable(),
    action: z.string(),
    mode: z.enum(MODES),
    from: z.enum(MODES),
  }).nullable(),
  reason: z.string(),
  requested_by: z.string().nullable(),
  requested_at: z.string(),
  expires_at: z.string(),
  decided_by: z.string().nullable(),
  decided_at: z.string().nullable(),
  result_code: z.string().nullable(),
  mine: z.boolean(),
  can_decide: z.boolean(),
  confirm: z.boolean(),
})
export type Approval = z.infer<typeof ApprovalZ>

const ApprovalsZ = z.object({ rows: z.array(ApprovalZ), open: count, requestable: z.array(z.string()) })
export type Approvals = z.infer<typeof ApprovalsZ>

const AccountOptionZ = z.object({ id, name: z.string() })
export type AccountOption = z.infer<typeof AccountOptionZ>

export async function loadAccess(): Promise<{ matrix: AccessMatrix; approvals: Approvals; accounts: AccountOption[] }> {
  const [matrix, approvals] = await Promise.all([
    rpcOrThrow('access_matrix', {}, MatrixZ),
    rpcOrThrow('approvals_list', {}, ApprovalsZ),
  ])
  // the request dialog picks among Orgpuls' accounts (the one product with a command path), only when there is something to ask
  const accounts = approvals.requestable.length
    ? await rpcOrThrow('plus_accounts', { p_product: 'orgpuls' }, z.array(AccountOptionZ))
    : []
  return { matrix, approvals, accounts }
}

// ---------------------------------------------------------------------------
// Customer success
export const ONBOARDING_STEPS = ['account_created', 'employees_uploaded', 'team_invited', 'survey_scheduled', 'survey_sent', 'results_viewed', 'first_tiltak'] as const
const OnboardingZ = z.object({
  days: count,
  cohort: count,
  steps: z.array(z.object({ key: z.enum(ONBOARDING_STEPS), done: count.nullable() })),
})
export type Onboarding = z.infer<typeof OnboardingZ>

export const REQUEST_STATUSES = ['under_review', 'planned', 'in_progress', 'shipped', 'declined'] as const
const RequestZ = z.object({
  id,
  ref: count,
  title: z.string(),
  status: z.enum(REQUEST_STATUSES),
  votes: count,
  organizations: z.array(z.object({ id, name: z.string() })),
  ticket_count: count,
  deal_count: count,
  asking: z.object({ accounts: count, mrr: money.nullable(), unpriced: count }).nullable(),
})
export type FeatureRequest = z.infer<typeof RequestZ>

const SignalZ = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('expansion'),
    organization: z.object({ id, name: z.string() }),
    employees: count,
    max: count,
    band: z.string().nullable(),
    next: z.string().nullable(),
    open: id.nullable(),
  }),
  z.object({
    kind: z.literal('at_risk'),
    organization: z.object({ id, name: z.string() }),
    health_from: count.nullable(),
    health_to: count.nullable(),
    days_since_sign_in: count.nullable(),
    open: id.nullable(),
  }),
])
export type Signal = z.infer<typeof SignalZ>

export async function loadSuccess(product: string): Promise<{
  onboarding: Onboarding
  requests: { money: boolean; rows: FeatureRequest[] }
  signals: Signal[]
  accounts: AccountOption[]
}> {
  const [onboarding, requests, signals, accounts] = await Promise.all([
    rpcOrThrow('onboarding_completion', { p_product: product, p_days: 180 }, OnboardingZ),
    rpcOrThrow('success_requests', { p_product: product }, z.object({ money: z.boolean(), rows: z.array(RequestZ) })),
    rpcOrThrow('renewal_signals', { p_product: product }, z.array(SignalZ)),
    rpcOrThrow('plus_accounts', { p_product: product }, z.array(AccountOptionZ)),
  ])
  return { onboarding, requests, signals, accounts }
}

// ---------------------------------------------------------------------------
// Rollouts and announcements
const ReachZ = z.object({ known: z.boolean(), accounts: count, users: count })
export type Reach = z.infer<typeof ReachZ>
/** the composer's two audience chips (D-PL-06): «Admins» = Orgpuls' daglig leder, «Trial» = accounts in trial */
export const AUDIENCES = ['all', 'admins', 'trial', 'admins_trial'] as const
export type Audience = (typeof AUDIENCES)[number]

const LimitZ = z.object({
  organization: z.object({ id, name: z.string() }),
  employees: count,
  max: count,
  band: z.string().nullable(),
  pct: count,
  day: z.string().nullable(),
})
export type NearLimit = z.infer<typeof LimitZ>

const ErrorRowZ = z.object({
  organization: z.object({ id, name: z.string() }),
  replies: count,
  bounces: count,
  failed: count,
  total: count,
  ticket: z.object({ id, ref: z.string() }).nullable(),
})
export type ErrorRow = z.infer<typeof ErrorRowZ>

export async function loadOps(product: string): Promise<{
  reach: Record<Audience, Reach>
  limits: { warn_pct: number; usage: boolean; rows: NearLimit[] }
  errors: { hours: number; rows: ErrorRow[]; clean: number }
}> {
  const reach = (roles: string[], access: string[]) => rpcOrThrow('announcement_reach', { p_product: product, p_roles: roles, p_access: access }, ReachZ)
  const [all, admins, trial, adminsTrial, limits, errors] = await Promise.all([
    reach([], []),
    reach(['daglig_leder'], []),
    reach([], ['trial']),
    reach(['daglig_leder'], ['trial']),
    rpcOrThrow('limits_near', { p_product: product }, z.object({ warn_pct: count, usage: z.boolean(), rows: z.array(LimitZ) })),
    rpcOrThrow('customer_errors', { p_product: product, p_hours: 24 }, z.object({ hours: count, rows: z.array(ErrorRowZ), clean: count })),
  ])
  return { reach: { all, admins, trial, admins_trial: adminsTrial }, limits, errors }
}

// ---------------------------------------------------------------------------
// Billing portal
const BillingPlanZ = z.object({
  band: z.string(),
  key: z.string().nullable(),
  min: count,
  max: count.nullable(),
  monthly: money,
  annual: money.nullable(),
})
export type BillingPlan = z.infer<typeof BillingPlanZ>

const BillingAccountZ = z.object({
  id,
  name: z.string(),
  plan: z.string().nullable(),
  band: z.string().nullable(),
  key: z.string().nullable(),
  max: count.nullable(),
  monthly: money.nullable(),
  interval: z.string().nullable(),
  status: z.string().nullable(),
  trial_ends_at: z.string().nullable(),
  cancel_effective_at: z.string().nullable(),
  open_tickets: count.nullable(),
  tickets_30d: count.nullable(),
})
export type BillingAccount = z.infer<typeof BillingAccountZ>

const BillingZ = z.object({
  plans: z.array(BillingPlanZ),
  tickets: z.boolean(),
  tickets_30d: count.nullable(),
  tickets_prev_30d: count.nullable(),
  accounts: z.array(BillingAccountZ),
})
export type Billing = z.infer<typeof BillingZ>

export async function loadBilling(product: string): Promise<Billing> {
  return rpcOrThrow('billing_portal', { p_product: product }, BillingZ)
}
