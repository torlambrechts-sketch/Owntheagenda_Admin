/**
 * Security screen (Security.dc.html): what the client components and the server share — the tabs, the enums the
 * database returns (message keys, never labels) and the pure helpers. No server import here.
 */

export const TABS = ['dash', 'alerts', 'logins', 'signin', 'protect', 'privacy', 'audit'] as const
export type Tab = (typeof TABS)[number]

/** The URL each tab lives at; the design's pill buttons become links (V-SECURITY-01). */
export const tabHref = (t: Tab) => (t === 'dash' ? '/security' : `/security?tab=${t}`)

export const SEVERITIES = ['info', 'low', 'high', 'critical'] as const
export const ALERT_STATES = ['none', 'queued', 'sent', 'digest', 'failed'] as const
export const EVENT_KINDS = [
  'new_device', 'new_location', 'failed_logins', 'account_locked', 'user_invited', 'password_reset', 'large_export', 'large_delete',
  'session_revoked', 'mfa_reset', 'ip_blocked', 'time_blocked', 'api_token_old', 'webhook_banned', 'incident_logged', 'admin_login',
] as const
export const OUTCOMES = ['success', 'failed_password', 'failed_mfa', 'blocked_ip', 'blocked_time', 'blocked_inactive', 'blocked_method', 'rate_limited'] as const
export const METHODS = ['password_totp', 'google_totp', 'microsoft_totp', 'recovery_code'] as const
export const END_REASONS = ['signed_out', 'idle_timeout', 'forced', 'ip_rule', 'time_rule', 'deactivated', 'mfa_reset', 'recovery_code', 'expired'] as const
export const ISSUE_KEYS = ['mfa_not_enrolled', 'mailbox_reauth', 'api_tokens_old', 'access_review_due', 'ip_allowlist_empty', 'webhooks_banned', 'jobs_failed'] as const
export const FIREWALL_CHECKS = ['no_grants', 'no_references', 'aggregates_only', 'no_tracking_in_surveys', 'no_contacts_from_respondents', 'tested'] as const
export const INCIDENT_STATES = ['investigating', 'assessed_not_notifiable', 'notified', 'closed'] as const
export const AUDIT_KINDS = ['read', 'write', 'export', 'role', 'security'] as const
export const AUDIT_SOURCES = ['web', 'api', 'mcp', 'workflow', 'ticket', 'support_access', 'mobile', 'import', 'product', 'system'] as const
export const PRINCIPAL_KINDS = ['staff', 'token', 'oauth', 'workflow', 'system', 'product'] as const
export const ALERT_KEYS = ['alert_new_device', 'alert_user_invited', 'alert_failed_logins', 'alert_password_reset', 'alert_large_export', 'login_alerts'] as const
export type AlertKey = (typeof ALERT_KEYS)[number]
export const ALERT_MODES = ['off', 'immediate', 'digest'] as const
export const DIGEST_HOURS = Array.from({ length: 24 }, (_, h) => `${String(h).padStart(2, '0')}:00`)
export const RETENTION_KEYS = ['crm_soft_deleted', 'product_events_raw', 'login_log', 'tickets_closed', 'email_bodies', 'meeting_recordings', 'audit_log', 'erasure_tombstones', 'survey_responses'] as const
/** privacy_preview's counts, in the order «Found in» lists them. */
export const PRIVACY_COUNTS = [
  'people', 'leads', 'emails', 'email_participants', 'activities', 'activity_guests', 'deals', 'deal_participants', 'tickets', 'consent_events',
  'form_submissions', 'chat_conversations', 'campaign_recipients', 'meetings', 'documents', 'signatures', 'bookings', 'product_events',
  'enrichment_requests', 'history',
] as const
export type PrivacyCount = (typeof PRIVACY_COUNTS)[number]

/** The register keys this screen may set (groups security and security_alerts), with the options each accepts. */
export const SECURITY_SETTINGS: Record<string, readonly string[]> = {
  session_idle: ['on_30', 'off'],
  session_remember: ['days_30', 'off'],
  ip_allowlist: ['off', 'on'],
  signin_hours: ['off', 'on'],
  password_expiry: ['never', 'days'],
  access_review_interval: ['quarterly', 'half_yearly'],
  login_alerts: ALERT_MODES,
  alert_new_device: ALERT_MODES,
  alert_user_invited: ALERT_MODES,
  alert_failed_logins: ALERT_MODES,
  alert_password_reset: ALERT_MODES,
  alert_large_export: ALERT_MODES,
  alert_digest_time: DIGEST_HOURS,
  security_alert_recipients: ['role', 'list'],
}

/** The error details the database raises on this screen that have their own message (security.errors.<detail>). */
export const ERROR_DETAILS = [
  'fresh_mfa', 'self_lockout', 'owner_only', 'self', 'product_user', 'erased', 'rate_limited', 'open_review', 'undecided', 'enrolled', 'confirm',
  'subject', 'cidr', 'window', 'days', 'domains', 'region', 'password_history', 'expired', 'google', 'microsoft', 'label', 'title', 'summary',
  'detected_at', 'name', 'purpose', 'q', 'at', 'rpo', 'rto', 'note', 'decision', 'staff',
] as const
export const errorDetailKey = (detail: string | null | undefined) =>
  detail && (ERROR_DETAILS as readonly string[]).includes(detail) ? detail : null

/**
 * A Postgres interval as the retention register returns it («30 days», «1 year 1 mon», «3 years») split into whole
 * years, months and days, for a message to word. Anything else gives null and the screen shows «—».
 */
export function parseInterval(s: string | null | undefined): { years: number; months: number; days: number } | null {
  if (!s) return null
  const re = /(\d+)\s+(years?|mons?|days?)/g
  const out = { years: 0, months: 0, days: 0 }
  let m: RegExpExecArray | null
  let seen = false
  while ((m = re.exec(s))) {
    seen = true
    const n = Number(m[1])
    if (m[2]!.startsWith('year')) out.years += n
    else if (m[2]!.startsWith('mon')) out.months += n
    else out.days += n
  }
  if (!seen || s.replace(re, '').trim() !== '') return null
  return out
}

/** «1 year 1 mon» → 13 months: a period worded in one unit where it divides evenly. */
export function intervalUnit(s: string | null | undefined): { unit: 'years' | 'months' | 'days'; n: number } | null {
  const p = parseInterval(s)
  if (!p) return null
  if (p.days) return p.years || p.months ? null : { unit: 'days', n: p.days }
  if (p.months) return { unit: 'months', n: p.years * 12 + p.months }
  return { unit: 'years', n: p.years }
}

/** The counts privacy_preview found, in display order, without the zeros. */
export const foundIn = (counts: Partial<Record<string, number>>) =>
  PRIVACY_COUNTS.filter((k) => (counts[k] ?? 0) > 0).map((k) => ({ key: k, n: counts[k] as number }))

/** An IPv4 or IPv6 range the rules accept: no wider than /8 (IPv4) or /16 (IPv6), as the database checks. */
export function cidrOk(s: string): boolean {
  const v = s.trim()
  const m4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:\/(\d{1,2}))?$/.exec(v)
  if (m4) {
    const octets = m4.slice(1, 5).map(Number)
    const len = m4[5] === undefined ? 32 : Number(m4[5])
    return octets.every((o) => o <= 255) && len >= 8 && len <= 32
  }
  const m6 = /^([0-9a-fA-F:]+)(?:\/(\d{1,3}))?$/.exec(v)
  if (m6 && m6[1]!.includes(':')) {
    const len = m6[2] === undefined ? 128 : Number(m6[2])
    const groups = m6[1]!.split('::')
    if (groups.length > 2) return false
    const parts = groups.flatMap((g) => (g ? g.split(':') : []))
    return len >= 16 && len <= 128 && parts.every((p) => /^[0-9a-fA-F]{1,4}$/.test(p)) && (groups.length === 2 ? parts.length < 8 : parts.length === 8)
  }
  return false
}

/** HH:MM, 24-hour. */
export const timeOk = (s: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(s)

/** «Mon–Fri»-style day lists come from ISO weekdays 1..7. */
export const ISO_DAYS = [1, 2, 3, 4, 5, 6, 7] as const
