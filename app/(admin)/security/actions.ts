'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { createClient } from '@/lib/supabase/server'
import { signForMe } from '@/lib/storage/server'
import { FindResult, Preview, PreviewResult, Rule } from '@/lib/data/security'
import { ALERT_MODES, cidrOk, SECURITY_SETTINGS, timeOk } from '@/lib/data/security-shared'

/**
 * The Security screen's writes. Each parses its input with zod, calls one database function through rpc() and answers
 * { ok: true } or { ok: false, code, detail }: the detail names the field or the reason (fresh_mfa, self_lockout,
 * product_user …) so the screen can say exactly what the database refused. No worker (service-role) function is
 * called from here; the database decides every refusal.
 */
export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode; detail: string | null }

const uuid = z.string().uuid()
const reason = z.string().trim().max(500).nullable().default(null)
const bad = (detail: string | null = null) => ({ ok: false as const, code: 'invalid' as const, detail })
const done = () => revalidatePath('/security', 'page')

async function call<S extends z.ZodTypeAny>(fn: string, args: Record<string, unknown>, schema: S): Promise<Result<{ data: z.infer<S> }>> {
  const r = await rpc(fn, args, schema)
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  done()
  return { ok: true, data: r.data }
}
const strip = <T extends object>(r: Result<T>): Result => (r.ok ? { ok: true } : r)

// ---------------------------------------------------------------------------
// a fresh second factor (§3.12.3): the authenticator code again, so the session's amr carries a TOTP from now
export async function confirmFactor(input: { code: string }): Promise<Result> {
  const p = z.object({ code: z.string().trim().regex(/^\d{6}$/) }).safeParse(input)
  if (!p.success) return bad('code')
  const supabase = await createClient()
  const { data } = await supabase.auth.mfa.listFactors()
  const factor = data?.totp?.find((f) => f.status === 'verified')
  if (!factor) return { ok: false, code: 'not_available', detail: 'factor' }
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code: p.data.code })
  if (error) return bad('code')
  return { ok: true }
}

// ---------------------------------------------------------------------------
// sessions (SEC-04)
export async function revokeSession(input: { session: string; reason?: string | null }): Promise<Result<{ ended: boolean }>> {
  const p = z.object({ session: uuid, reason }).safeParse(input)
  if (!p.success) return bad()
  const r = await call('session_revoke', { p_session: p.data.session, p_reason: p.data.reason }, z.object({ ended: z.boolean() }))
  return r.ok ? { ok: true, ended: r.data.ended } : r
}

export async function revokeAll(input: { staff: string; reason?: string | null }): Promise<Result<{ ended: number }>> {
  const p = z.object({ staff: uuid, reason }).safeParse(input)
  if (!p.success) return bad()
  const r = await call('staff_sessions_revoke_all', { p_staff: p.data.staff, p_reason: p.data.reason }, z.object({ ended: z.coerce.number() }))
  return r.ok ? { ok: true, ended: r.data.ended } : r
}

// ---------------------------------------------------------------------------
// register keys (groups security and security_alerts) through setting_set: its hooks guard self-lockout
const SettingIn = z
  .object({ key: z.string(), value: z.string(), number: z.number().int().min(1).max(3650).nullable().default(null) })
  .refine((s) => SECURITY_SETTINGS[s.key]?.includes(s.value), { path: ['value'] })
  .refine((s) => s.number === null || (s.key === 'password_expiry' && s.value === 'days'), { path: ['number'] })
export async function setSecuritySetting(input: z.input<typeof SettingIn>): Promise<Result> {
  const p = SettingIn.safeParse(input)
  if (!p.success) return bad('value')
  return strip(await call('setting_set', { p_key: p.data.key, p_value: p.data.value, p_scope_id: '', p_number: p.data.number }, z.object({ key: z.string() })))
}

// ---------------------------------------------------------------------------
// IP ranges and sign-in windows (SEC-03)
const RuleValues = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('ip_range'), label: z.string().trim().min(1).max(80), cidr: z.string().trim().refine(cidrOk) }),
  z.object({
    kind: z.literal('time_window'),
    label: z.string().trim().min(1).max(80),
    days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    starts: z.string().refine(timeOk),
    ends: z.string().refine(timeOk),
  }).refine((w) => w.starts !== w.ends, { path: ['ends'] }),
])
export async function saveRule(input: { id: string | null; values: unknown; version?: number | null }): Promise<Result> {
  const p = z.object({ id: uuid.nullable(), values: RuleValues, version: z.number().int().nullable().default(null) }).safeParse(input)
  if (!p.success) {
    const field = p.error.issues[0]?.path.at(-1)
    return bad(field === 'cidr' ? 'cidr' : field === 'days' ? 'days' : field === 'label' ? 'label' : 'window')
  }
  return strip(await call('security_rule_save', { p_id: p.data.id, p_values: p.data.values, p_version: p.data.version }, Rule))
}

export async function deleteRule(input: { id: string }): Promise<Result> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad()
  return strip(await call('security_rule_delete', { p_id: p.data.id }, z.object({ ok: z.boolean() })))
}

const ChangeIn = z.object({
  ip_allowlist: z.enum(['on', 'off']).optional(),
  signin_hours: z.enum(['on', 'off']).optional(),
  remove: uuid.optional(),
  rule: z.union([
    z.object({ id: uuid.optional(), kind: z.literal('ip_range'), cidr: z.string().trim().refine(cidrOk) }),
    z.object({ id: uuid.optional(), kind: z.literal('time_window'), days: z.array(z.number().int().min(1).max(7)).min(1), starts: z.string().refine(timeOk), ends: z.string().refine(timeOk) }),
  ]).optional(),
})
export async function previewRules(input: z.input<typeof ChangeIn>): Promise<Result<{ data: Preview }>> {
  const p = ChangeIn.safeParse(input)
  if (!p.success) return bad('change')
  const r = await rpc('security_rule_preview', { p_change: p.data }, Preview)
  return r.ok ? { ok: true, data: r.data } : { ok: false, code: r.code, detail: r.detail }
}

// ---------------------------------------------------------------------------
// two-factor, SSO and the access review (SEC-05, SEC-06)
export async function mfaReminder(input: { staff: string[] }): Promise<Result<{ email: string }>> {
  const p = z.object({ staff: z.array(uuid).min(1).max(50) }).safeParse(input)
  if (!p.success) return bad()
  let email = 'not_connected'
  for (const s of p.data.staff) {
    const r = await rpc('staff_mfa_reminder', { p_staff: s }, z.object({ in_app: z.boolean(), email: z.enum(['queued', 'not_connected']) }))
    if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
    email = r.data.email
  }
  done()
  return { ok: true, email }
}

export async function recoveryCodesGenerate(): Promise<Result<{ codes: string[] }>> {
  // the codes are shown once and never logged; the database stores only their hashes
  const r = await call('recovery_codes_generate', {}, z.object({ codes: z.array(z.string().regex(/^[0-9a-f]{5}-[0-9a-f]{5}$/)).length(10) }))
  return r.ok ? { ok: true, codes: r.data.codes } : r
}

export async function mfaReset(input: { staff: string; reason?: string | null }): Promise<Result<{ removed: number }>> {
  const p = z.object({ staff: uuid, reason }).safeParse(input)
  if (!p.success) return bad()
  const r = await call('staff_mfa_reset', { p_staff: p.data.staff, p_reason: p.data.reason }, z.object({ factors_removed: z.coerce.number() }))
  return r.ok ? { ok: true, removed: r.data.factors_removed } : r
}

export async function ssoSet(input: { provider: string; enabled: boolean; domains?: string[] | null }): Promise<Result> {
  const p = z.object({ provider: z.enum(['google', 'microsoft']), enabled: z.boolean(), domains: z.array(z.string().trim().max(120)).max(20).nullable().default(null) }).safeParse(input)
  if (!p.success) return bad('domains')
  return strip(await call('sso_set', { p_provider: p.data.provider, p_enabled: p.data.enabled, p_domains: p.data.domains }, z.object({ provider: z.string() })))
}

export async function reviewStart(): Promise<Result> {
  return strip(await call('access_review_start', {}, z.object({ id: uuid })))
}

export async function reviewDecide(input: { review: string; staff: string; decision: string }): Promise<Result> {
  const p = z.object({ review: uuid, staff: uuid, decision: z.enum(['keep', 'change', 'deactivate']) }).safeParse(input)
  if (!p.success) return bad('decision')
  return strip(await call('access_review_decide', { p_review: p.data.review, p_staff: p.data.staff, p_decision: p.data.decision }, z.object({ ok: z.boolean() })))
}

export async function reviewComplete(input: { review: string }): Promise<Result> {
  const p = z.object({ review: uuid }).safeParse(input)
  if (!p.success) return bad()
  return strip(await call('access_review_complete', { p_review: p.data.review }, z.object({ ok: z.boolean() })))
}

// ---------------------------------------------------------------------------
// data protection (SEC-10)
const RestoreIn = z.object({
  at: z.string().datetime({ offset: true }),
  ok: z.boolean(),
  rpo: z.number().int().min(0).max(100_000),
  rto: z.number().int().min(0).max(100_000),
  note: z.string().trim().max(300).nullable().default(null),
})
export async function restoreTestRecord(input: z.input<typeof RestoreIn>): Promise<Result<{ meets: boolean }>> {
  const p = RestoreIn.safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path[0] ?? 'at'))
  const r = await call('restore_test_record', { p_at: p.data.at, p_ok: p.data.ok, p_rpo_min: p.data.rpo, p_rto_min: p.data.rto, p_note: p.data.note },
    z.object({ id: z.coerce.number(), meets_objectives: z.boolean() }))
  return r.ok ? { ok: true, meets: r.data.meets_objectives } : r
}

// ---------------------------------------------------------------------------
// privacy (SEC-11): find, preview, export, erase with its approval step. Subjects travel by id, never by address.
const Subject = z.object({ people: z.array(uuid).max(20).default([]), leads: z.array(uuid).max(20).default([]) })
  .refine((s) => s.people.length + s.leads.length > 0)

export async function privacyFind(input: { q: string }): Promise<Result<{ data: FindResult }>> {
  const p = z.object({ q: z.string().trim().min(3).max(200) }).safeParse(input)
  if (!p.success) return bad('q')
  const r = await rpc('privacy_find', { p_q: p.data.q }, FindResult)
  return r.ok ? { ok: true, data: r.data } : { ok: false, code: r.code, detail: r.detail }
}

export async function privacyPreview(input: { subject: z.input<typeof Subject> }): Promise<Result<{ data: PreviewResult }>> {
  const p = z.object({ subject: Subject }).safeParse(input)
  if (!p.success) return bad('subject')
  const r = await rpc('privacy_preview', { p_subject: p.data.subject }, PreviewResult)
  return r.ok ? { ok: true, data: r.data } : { ok: false, code: r.code, detail: r.detail }
}

/** The personvern request an export or an erasure answers (privacy_requests_get), or none; the job closes it when done. */
const request = uuid.nullable().default(null)

export async function privacyExport(input: { subject: z.input<typeof Subject>; request?: string | null; reason?: string | null }): Promise<Result> {
  const p = z.object({ subject: Subject, request, reason }).safeParse(input)
  if (!p.success) return bad('subject')
  return strip(await call('privacy_export', { p_subject: p.data.subject, p_request: p.data.request, p_reason: p.data.reason }, z.object({ job: uuid, state: z.string() })))
}

const Erased = z.object({ job: uuid, state: z.enum(['done', 'previewed']), approval: z.literal('required').optional(), counts: z.record(z.string(), z.coerce.number()) })
export async function privacyErase(input: { subject: z.input<typeof Subject>; confirm: string; request?: string | null; reason?: string | null }): Promise<Result<{ state: 'done' | 'previewed'; rows: number }>> {
  const p = z.object({ subject: Subject, confirm: z.string().trim().min(1).max(320), request, reason }).safeParse(input)
  if (!p.success) return bad('confirm')
  const r = await call('privacy_erase', { p_subject: p.data.subject, p_request: p.data.request, p_confirm: p.data.confirm, p_reason: p.data.reason }, Erased)
  return r.ok ? { ok: true, state: r.data.state, rows: Object.values(r.data.counts).reduce((a, b) => a + b, 0) } : r
}

export async function privacyApprove(input: { job: string }): Promise<Result<{ rows: number }>> {
  const p = z.object({ job: uuid }).safeParse(input)
  if (!p.success) return bad()
  const r = await call('privacy_approve', { p_job: p.data.job }, Erased)
  return r.ok ? { ok: true, rows: Object.values(r.data.counts).reduce((a, b) => a + b, 0) } : r
}

/**
 * The access package's download (SF-15): privacy_export_url checks global:security and the package's 24 hours and audits
 * the read; storage-sign (0052) then signs that path, in the private «privacy-exports» bucket, for one minute.
 */
export async function privacyDownload(input: { job: string }): Promise<Result<{ url: string }>> {
  const p = z.object({ job: uuid }).safeParse(input)
  if (!p.success) return bad()
  const where = await rpc('privacy_export_url', { p_job: p.data.job }, z.object({ path: z.string().regex(/^privacy\/[0-9a-f-]{36}\/[A-Za-z0-9._-]{1,80}$/), expires_at: z.string() }))
  if (!where.ok) return { ok: false, code: where.code, detail: where.detail }
  const signed = await signForMe({ mode: 'download', bucket: 'privacy-exports', path: where.data.path })
  return signed.ok ? { ok: true, url: signed.url } : { ok: false, code: signed.code, detail: signed.detail }
}

// ---------------------------------------------------------------------------
// the sub-processor register and the incident register
const SubIn = z.object({
  name: z.string().trim().min(1).max(80),
  purpose: z.string().trim().min(1).max(200),
  region: z.string().trim().max(60).nullable(),
  public: z.boolean(),
  in_use_since: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
})
export async function subprocessorSave(input: { id: string | null; values: unknown; version?: number | null }): Promise<Result> {
  const p = z.object({ id: uuid.nullable(), values: SubIn, version: z.number().int().nullable().default(null) }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path.at(-1) ?? 'name'))
  const v = { ...p.data.values, region: p.data.values.region || null }
  return strip(await call('subprocessor_save', { p_id: p.data.id, p_values: v, p_version: p.data.version }, z.object({ id: uuid })))
}

const IncidentIn = z.object({
  title: z.string().trim().min(1).max(200).optional(),
  summary: z.string().max(2000).optional(),
  detected_at: z.string().datetime({ offset: true }).optional(),
  personal_data: z.boolean().optional(),
  state: z.enum(['investigating', 'assessed_not_notifiable', 'notified', 'closed']).optional(),
})
export async function incidentSave(input: { id: string | null; values: unknown; version?: number | null }): Promise<Result> {
  const p = z.object({ id: uuid.nullable(), values: IncidentIn, version: z.number().int().nullable().default(null) }).safeParse(input)
  if (!p.success) return bad(String(p.error.issues[0]?.path.at(-1) ?? 'title'))
  if (p.data.id === null && !p.data.values.title) return bad('title')
  return strip(await call('incident_save', { p_id: p.data.id, p_values: p.data.values, p_version: p.data.version }, z.object({ id: uuid })))
}

/**
 * Who receives security alerts (SEC-02): everyone with the security right, or the people named. The names are written
 * first (alert_recipients_set accepts only active holders of global:security), then the mode.
 */
export async function setAlertRecipients(input: { mode: 'role' | 'list'; staff: string[] }): Promise<Result> {
  const p = z.object({ mode: z.enum(['role', 'list']), staff: z.array(uuid).max(100) }).refine((v) => v.mode === 'role' || v.staff.length > 0, { path: ['staff'] }).safeParse(input)
  if (!p.success) return bad('staff')
  if (p.data.mode === 'list') {
    const r = await call('alert_recipients_set', { p_staff: p.data.staff }, z.object({ count: z.coerce.number() }))
    if (!r.ok) return r
  }
  return setSecuritySetting({ key: 'security_alert_recipients', value: p.data.mode })
}

/** The alert modes a toggle may write (kept here so the client cannot send another register key through it). */
export async function setAlert(input: { key: string; mode: string }): Promise<Result> {
  const p = z.object({ key: z.enum(['alert_new_device', 'alert_user_invited', 'alert_failed_logins', 'alert_password_reset', 'alert_large_export', 'login_alerts']), mode: z.enum(ALERT_MODES) }).safeParse(input)
  if (!p.success) return bad('value')
  return setSecuritySetting({ key: p.data.key, value: p.data.mode })
}
