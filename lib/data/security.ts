import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { ALERT_STATES, AUDIT_KINDS, AUDIT_SOURCES, END_REASONS, EVENT_KINDS, INCIDENT_STATES, METHODS, OUTCOMES, PRINCIPAL_KINDS, SEVERITIES } from './security-shared'

/**
 * Loaders for the Security screen (Security.dc.html; 0043, contract docs/crm-enrichment/deviations/security-schema.md).
 * Every figure comes from a database function and is parsed here, never computed in the client: the dashboard's KPIs are
 * security_dashboard()'s own counts over the login log, the sessions and the security events. An IP address appears only
 * where a function opens the seal for that purpose (login_history, my_sessions). Worker functions (service role) are
 * never called from here.
 */

const num = z.coerce.number()
const uuid = z.string().uuid()
const ts = z.string()
const str = z.string().nullable()

// ---------------------------------------------------------------------------
// dashboard (SEC-01)
const Named = z.object({ id: uuid, name: z.string() })
export const Issue = z.object({
  key: z.string(),
  severity: z.enum(SEVERITIES),
  count: num.optional(),
  action: z.string(),
  due_on: z.string().nullable().optional(),
  staff: z.union([num, z.array(z.object({ id: uuid, name: z.string(), days: num.optional() }))]).optional(),
  mailboxes: z.array(z.object({ id: uuid, address: z.string(), status: z.string(), watch_expires_at: z.string().nullable() })).optional(),
  tokens: z.array(z.object({ id: uuid, staff: uuid.nullable(), name: z.string().nullable() })).optional(),
  webhooks: z.array(z.object({ id: uuid })).optional(),
  runs: z.array(z.object({ id: z.union([uuid, num]), job: z.string().nullable() })).optional(),
})
export type Issue = z.infer<typeof Issue>
export const SecEvent = z.object({
  id: num,
  at: ts,
  kind: z.enum(EVENT_KINDS),
  severity: z.enum(SEVERITIES),
  subject_id: uuid.nullable(),
  subject: str,
  actor_id: uuid.nullable(),
  actor: str,
  detail: z.record(z.string(), z.unknown()),
  alert_state: z.enum(ALERT_STATES),
})
export type SecEvent = z.infer<typeof SecEvent>
export const LiveSession = z.object({
  session_id: uuid,
  staff_id: uuid,
  name: z.string(),
  city: str,
  country: str,
  device: str,
  method: z.enum(METHODS),
  since: ts,
  last_seen_at: ts,
  // a device remembered at the second factor is exempt from the idle rule until then (0071)
  remembered_until: ts.nullable().optional(),
  current: z.boolean().nullable(),
})
export type LiveSession = z.infer<typeof LiveSession>
export const Dashboard = z.object({
  kpis: z.object({
    signed_in_now: num,
    new_devices_7d: z.object({ count: num, staff: z.array(Named) }),
    new_locations_7d: z.object({ count: num, places: z.array(z.object({ city: str, country: str })) }),
    security_events_7d: z.object({ count: num, critical: num }),
    forced_logouts_7d: num,
    // coverage_pct is the database's own rounded percentage (R-SECURITY-02), null with no active staff
    mfa: z.object({ enrolled: num, active: num, coverage_pct: num.nullable() }),
  }),
  settings: z.object({ session_idle: z.string(), session_remember: z.string().optional(), ip_allowlist: z.string(), signin_hours: z.string(), ip_rules: num }),
  live: z.array(LiveSession),
  issues: z.array(Issue),
  issues_open: num,
  events: z.array(SecEvent),
})
export type Dashboard = z.infer<typeof Dashboard>
export const loadDashboard = () => rpc('security_dashboard', {}, Dashboard)

// ---------------------------------------------------------------------------
// alerts and rules (SEC-02, SEC-03)
export const Rule = z.object({
  id: uuid,
  kind: z.enum(['ip_range', 'time_window']),
  cidr: str,
  days: z.array(num).nullable(),
  starts: str,
  ends: str,
  label: z.string(),
  created_at: ts,
  version: num,
})
export type Rule = z.infer<typeof Rule>
export const Rules = z.object({
  ip_allowlist: z.string(),
  signin_hours: z.string(),
  session_idle: z.string(),
  session_remember: z.string().default('days_30'),
  password_expiry: z.string(),
  password_expiry_days: num.nullable(),
  password_reuse: z.string(),
  password_reuse_available: z.boolean(),
  rules: z.array(Rule),
})
export type Rules = z.infer<typeof Rules>
export const Alerts = z.object({
  settings: z.record(z.string(), z.string()),
  failed_logins_count: num,
  large_export_rows: num,
  recipients: z.array(z.object({ id: uuid, name: z.string(), email: z.string() })),
  listed: z.array(uuid),
  // who alert_recipients_set accepts: the active holders of global:security (R-SECURITY-06)
  eligible: z.array(Named),
  email: z.enum(['connected', 'not_connected']),
  slack: z.enum(['connected', 'not_connected']),
  slack_channel: str,
})
export type Alerts = z.infer<typeof Alerts>
export const Preview = z.object({
  staff: z.array(z.object({ staff_id: uuid, name: z.string().nullable(), refused: num, sign_ins: num })),
  self_lockout: z.boolean().nullable(),
})
export type Preview = z.infer<typeof Preview>
export const loadAlertsAndRules = async () => {
  const [alerts, rules] = await Promise.all([rpc('alerts_get', {}, Alerts), rpc('security_rules_get', {}, Rules)])
  return { alerts, rules }
}

// ---------------------------------------------------------------------------
// device and login history (SEC-04)
export const Login = z.object({
  at: ts,
  outcome: z.enum(OUTCOMES),
  method: z.enum(METHODS).nullable(),
  device: str,
  new_device: z.boolean(),
  city: str,
  country: str,
  new_location: z.boolean(),
  ip: str, // opened by login_history for global:security or oneself: the function returns it for this purpose
  session_id: uuid.nullable(),
  ended_at: str,
  end_reason: z.enum(END_REASONS).nullable(),
  active: z.boolean(),
})
export type Login = z.infer<typeof Login>
export const loadLoginHistory = (staff: string) => rpc('login_history', { p_staff: staff, p_days: 60 }, z.array(Login))

export const StaffOpt = z.object({ id: uuid, name: z.string(), email: z.string().nullable(), active: z.boolean(), is_sample: z.boolean() })
export type StaffOpt = z.infer<typeof StaffOpt>
export const loadStaffOpts = () => rpc('staff_list', {}, z.array(StaffOpt.passthrough()))

export const MySession = z.object({
  session_id: uuid,
  created_at: ts,
  last_seen_at: ts,
  device: str,
  city: str,
  country: str,
  method: z.enum(METHODS),
  ip: str, // the caller's own sessions: my_sessions opens the seal for the person themselves
  current: z.boolean().nullable(),
})
export type MySession = z.infer<typeof MySession>
export const loadMySessions = () => rpc('my_sessions', {}, z.array(MySession))

// ---------------------------------------------------------------------------
// SSO and two-factor (SEC-05, SEC-06) and the access review
export const Sso = z.object({
  providers: z.array(z.object({
    provider: z.enum(['google', 'microsoft']),
    enabled: z.boolean(),
    configured: z.boolean(),
    state: z.enum(['not_connected', 'on', 'off']),
    allowed_domains: z.array(z.string()),
    updated_at: str,
    users: num,
  })),
  access_review_due: str,
  access_review_open: z.boolean(),
})
export type Sso = z.infer<typeof Sso>
export const Mfa = z.object({ enforced: z.boolean().nullable(), active: num, authenticator: num, not_enrolled: z.array(Named), recovery_codes: num })
export type Mfa = z.infer<typeof Mfa>
export const Review = z.object({
  review: z.object({ id: uuid, due_on: z.string(), started_at: ts, completed_at: str }).passthrough().nullable(),
  next_due: str,
  interval: z.string(),
  items: z.array(z.object({
    staff_id: uuid,
    name: z.string(),
    permission_set_id: uuid.nullable(),
    permission_set: str,
    group_id: uuid.nullable(),
    group: str,
    decision: z.enum(['keep', 'change', 'deactivate']).nullable(),
    decided_at: str,
  })).optional(),
})
export type Review = z.infer<typeof Review>
export const loadSignin = async () => {
  const [sso, mfa, review, staff] = await Promise.all([
    rpc('sso_get', {}, Sso), rpc('mfa_overview', {}, Mfa), rpc('access_review_get', { p_review: null }, Review), loadStaffOpts(),
  ])
  return { sso, mfa, review, staff }
}

// ---------------------------------------------------------------------------
// data protection (SEC-10)
export const Firewall = z.object({ ok: z.boolean(), checks: z.array(z.object({ key: z.string(), ok: z.boolean() })), ci: z.unknown() })
export type Firewall = z.infer<typeof Firewall>
export const Protection = z.object({
  facts: z.record(z.string(), z.object({ value: z.string(), source: z.string() })),
  last_backup: z.object({ at: ts, ok: z.boolean() }).nullable(),
  pitr: z.object({ at: ts, ok: z.boolean() }).nullable(),
  pitr_warning: z.boolean(),
  last_restore_test: z.object({ at: ts, ok: z.boolean(), rpo_minutes: num.nullable(), rto_minutes: num.nullable(), meets_objectives: z.boolean().nullable() }).nullable(),
  objectives: z.object({ rpo_minutes: num, rto_minutes: num }),
})
export type Protection = z.infer<typeof Protection>
export const loadProtection = async () => {
  const [firewall, protection] = await Promise.all([rpc('firewall_status', {}, Firewall), rpc('protection_get', {}, Protection)])
  return { firewall, protection }
}

// ---------------------------------------------------------------------------
// privacy compliance (SEC-11)
export const RetentionRule = z.object({
  key: z.string(),
  keep: str, // for a rule tied to a setting, the setting's period («12 mons»), or null when it keeps until deleted (R-SECURITY-07)
  default_keep: str,
  basis: z.enum(['platform', 'product']),
  job: str,
  setting: z.object({ key: z.string(), value: z.string() }).nullable(),
  in_force: z.boolean(),
  last_run_at: str,
  last_purged: num.nullable(),
})
export type RetentionRule = z.infer<typeof RetentionRule>
export const Subprocessor = z.object({
  id: uuid,
  name: z.string(),
  purpose: z.string(),
  region: str,
  in_use_since: z.string(),
  removed_at: str,
  public: z.boolean(),
  ord: num,
  version: num,
})
export type Subprocessor = z.infer<typeof Subprocessor>
export const Incident = z.object({
  id: uuid,
  title: z.string(),
  summary: z.string(),
  detected_at: ts,
  logged_at: ts,
  personal_data: z.boolean(),
  state: z.enum(INCIDENT_STATES),
  notify_deadline: ts,
  notified_at: str,
  closed_at: str,
  version: num,
  hours_left: num.nullable(),
  elapsed_pct: num,
  logged_by_name: str,
})
export type Incident = z.infer<typeof Incident>
export const PrivacyJob = z.object({
  id: uuid,
  kind: z.enum(['export', 'erasure']),
  state: z.enum(['previewed', 'approved', 'running', 'done', 'failed']),
  preview: z.record(z.string(), num),
  request_id: uuid.nullable(),
  created_at: ts,
  created_by: str,
  approved_by: str,
  finished_at: str,
  url_expires_at: str,
  error: str,
})
export type PrivacyJob = z.infer<typeof PrivacyJob>
export const loadPrivacy = async () => {
  const [retention, subprocessors, incidents, jobs, requests] = await Promise.all([
    rpc('retention_get', {}, z.array(RetentionRule)), rpc('subprocessors_get', {}, z.array(Subprocessor)),
    rpc('incidents_get', {}, z.array(Incident)), rpc('privacy_jobs_get', {}, z.array(PrivacyJob)),
    rpc('privacy_requests_get', {}, z.array(PrivacyRequest)),
  ])
  return { retention, subprocessors, incidents, jobs, requests }
}

/** An open personvern request (R-SECURITY-05): what an export or an erasure may answer (p_request). No requester text. */
export const PrivacyRequest = z.object({
  id: uuid,
  kind: z.enum(['access', 'correction', 'deletion']),
  status: z.enum(['received', 'in_progress']),
  received_at: ts,
  due_at: ts,
  overdue: z.boolean(),
  ticket_number: num.nullable(),
  organization: str,
})
export type PrivacyRequest = z.infer<typeof PrivacyRequest>

export const FindResult = z.object({
  people: z.array(z.object({ id: uuid, name: z.string(), email: str, organization: str, deleted: z.boolean(), leads: z.array(uuid) })),
  members: z.array(z.object({ product: z.string(), tenant_id: z.unknown(), active: z.boolean() })),
  email_participants: num,
  tickets: num,
  consent_events: num,
  erased: z.boolean(),
})
export type FindResult = z.infer<typeof FindResult>
export const PreviewResult = z.object({
  counts: z.record(z.string(), num),
  product_user: z.boolean(),
  emails: num,
  confirm: z.enum(['email', 'name']),
  second_admin: z.boolean(),
})
export type PreviewResult = z.infer<typeof PreviewResult>

// ---------------------------------------------------------------------------
// audit log (SEC-11; D-12)
export const AuditRow = z.object({
  id: num,
  at: ts,
  kind: z.enum(AUDIT_KINDS),
  action: str,
  command: z.boolean(),
  ok: z.boolean().nullable(),
  staff_id: uuid.nullable(),
  who: str,
  principal_kind: z.enum(PRINCIPAL_KINDS).nullable(),
  principal_id: uuid.nullable(),
  workflow: str,
  source: z.enum(AUDIT_SOURCES).nullable(),
  target_type: str,
  target_id: str,
  target: z.object({ state: z.enum(['ok', 'hidden', 'removed', 'other']), title: z.string().optional() }).nullable(),
  organization: str,
  account_id: z.unknown(),
  reason: z.boolean(),
})
export type AuditRow = z.infer<typeof AuditRow>
export const AuditPage = z.object({ rows: z.array(AuditRow), next: num.nullable(), typed_reason: z.string() })
export type AuditPage = z.infer<typeof AuditPage>
export const loadAudit = (filter: { q?: string; kind?: string }, cursor: number | null) =>
  rpc('audit_search', { p_filter: filter, p_cursor: cursor, p_limit: 50 }, AuditPage)
