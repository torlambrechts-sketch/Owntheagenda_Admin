'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Dashboard, Issue, SecEvent } from '@/lib/data/security'
import { tabHref } from '@/lib/data/security-shared'
import { mfaReminder, reviewStart, revokeSession } from '../actions'
import { place, sx, useClock, useGuarded, useIsToday, useWhen } from './kit'

const SEV_BAR: Record<string, string> = { critical: 'bg-alert', high: 'bg-alert', low: 'bg-warn', info: 'bg-line-strong' }
const SEV_INK: Record<string, string> = { critical: 'text-danger', high: 'text-danger', low: 'text-warn-ink', info: 'text-ink' }

/**
 * Security dashboard (SEC-01): six KPIs, who is signed in now, the assessment and the last seven days. Every figure is
 * security_dashboard()'s own count over the login log, the sessions and the security events; nothing is computed here.
 */
export function DashboardView({ data, now, mayRemind }: { data: Dashboard; now: string; mayRemind: boolean }) {
  const t = useTranslations('security.dash')
  const when = useWhen(now)
  const clock = useClock()
  const isToday = useIsToday(now)
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const k = data.kpis

  const kpis: { key: string; v: string; s: string; tone: string }[] = [
    { key: 'signedIn', v: String(k.signed_in_now), s: t('kpi.signedInSub'), tone: 'text-ink' },
    { key: 'newDevices', v: String(k.new_devices_7d.count), s: k.new_devices_7d.staff.map((x) => x.name).join(', ') || t('kpi.none'), tone: k.new_devices_7d.count > 0 ? 'text-warn-ink' : 'text-ink' },
    { key: 'newLocations', v: String(k.new_locations_7d.count), s: k.new_locations_7d.places.map((p) => place(p.city, p.country)).join(' · ') || t('kpi.none'), tone: k.new_locations_7d.count > 0 ? 'text-warn-ink' : 'text-ink' },
    { key: 'events', v: String(k.security_events_7d.count), s: t('kpi.critical', { n: k.security_events_7d.critical }), tone: k.security_events_7d.critical > 0 ? 'text-danger' : 'text-ink' },
    { key: 'forced', v: String(k.forced_logouts_7d), s: t('kpi.forcedSub'), tone: 'text-ink' },
    // coverage is the database's own rounded percentage (security_dashboard, R-SECURITY-02); «—» with no active staff
    { key: 'mfa', v: k.mfa.coverage_pct === null ? '—' : t('kpi.mfaPct', { n: k.mfa.coverage_pct }), s: t('kpi.mfaOf', { enrolled: k.mfa.enrolled, active: k.mfa.active }), tone: k.mfa.enrolled < k.mfa.active ? 'text-danger' : 'text-ink' },
  ]

  const settingsLine = [
    data.settings.session_idle === 'on_30' ? t('timeout30') : t('timeoutOff'),
    data.settings.ip_allowlist === 'on' ? t('allowlistOn', { n: data.settings.ip_rules }) : t('allowlistOff'),
    ...(data.settings.signin_hours === 'on' ? [t('hoursOn')] : []),
  ].join(' · ')

  const logout = async (sessionId: string, name: string) => {
    const r = await run((reason) => revokeSession({ session: sessionId, reason }))
    if (r.ok) flash(r.ended ? t('loggedOut', { name }) : t('alreadyEnded'))
  }

  return (
    <div className="flex flex-col gap-[14px]">
      {dialog}
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(160px,1fr))]">
        {kpis.map((x) => (
          <div key={x.key} className="rounded-18 border border-solid border-line bg-surface px-4 py-[14px]">
            <div className="text-10.5 font-bold uppercase tracking-label text-muted">{t(`kpi.${x.key}`)}</div>
            <div className={`mt-[6px] font-serif text-26 font-semibold ${x.tone}`}>{x.v}</div>
            <div className="text-11.5 text-muted">{x.s}</div>
          </div>
        ))}
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <section className={sx.card} aria-label={t('liveTitle')}>
          <div className={`${sx.head} flex-wrap`}>
            <b className="text-14">{t('liveTitle')}</b>
            <span className="text-12 text-muted">{settingsLine}</span>
          </div>
          {data.live.length === 0 ? (
            <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('liveEmpty')}</div>
          ) : (
            <div className="overflow-x-auto">{data.live.map((l) => (
              <div key={l.session_id} className={`${sx.row} grid min-w-[460px] items-center gap-[10px] py-[9px] text-12.5 [grid-template-columns:minmax(0,1.2fr)_minmax(0,1.3fr)_100px_90px]`}>
                <span className="flex min-w-0 items-center gap-2">
                  <span className="h-[7px] w-[7px] flex-none rounded-999 bg-ok" />
                  <b className="truncate">{l.name}</b>
                </span>
                <span className="min-w-0 text-muted">{[place(l.city, l.country), l.device].filter(Boolean).join(' · ') || '—'}</span>
                <span className="text-muted">{t('since', { time: isToday(l.since) ? clock(l.since) : when(l.since, { time: false }) })}</span>
                {l.current ? (
                  <span className="text-center text-11.5 font-semibold text-muted">{t('thisSession')}</span>
                ) : (
                  <button type="button" className={sx.logout} disabled={busy} onClick={() => logout(l.session_id, l.name)}>{t('logout')}</button>
                )}
              </div>
            ))}</div>
          )}
        </section>

        <section className={sx.card} aria-label={t('assessTitle')}>
          <div className={sx.head}>
            <b className="text-14">{t('assessTitle')}</b>
            <span className="text-12 text-muted">{t('open', { n: data.issues_open })}</span>
          </div>
          {data.issues.length === 0 ? (
            <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('issuesEmpty')}</div>
          ) : (
            data.issues.map((i) => <IssueRow key={i.key} issue={i} run={run} busy={busy} mayRemind={mayRemind} now={now} />)
          )}
        </section>
      </div>

      <section className={sx.card} aria-label={t('weekTitle')}>
        <div className={sx.headTitle}>{t('weekTitle')}</div>
        {data.events.length === 0 ? (
          <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('weekEmpty')}</div>
        ) : (
          <div className="overflow-x-auto">
            {data.events.map((e) => (
              <div key={e.id} className={`${sx.row} grid min-w-[620px] gap-[10px] py-[9px] text-12.5 [grid-template-columns:110px_160px_minmax(0,1fr)_140px]`}>
                <span className="text-muted">{when(e.at, { time: isToday(e.at) })}</span>
                <b className={SEV_INK[e.severity]}>{t(`kinds.${e.kind}`)}</b>
                <EventText e={e} />
                <span className="text-muted">{t(`alert.${e.alert_state}`)}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}

function EventText({ e }: { e: SecEvent }) {
  const t = useTranslations('security.dash.text')
  const d = e.detail as Record<string, unknown>
  const s = (v: unknown) => (typeof v === 'string' ? v : '')
  const n = (v: unknown) => (typeof v === 'number' ? v : Number(v) || 0)
  const subject = e.subject ?? t('someone')
  const actor = e.actor ?? t('someone')
  const where = place(s(d.city) || null, s(d.country) || null)
  switch (e.kind) {
    case 'new_device':
      return <span>{t('new_device', { subject, device: s(d.device) || t('unknownDevice'), where: where || t('unknownPlace') })}</span>
    case 'new_location':
      return <span>{t('new_location', { subject, where: where || t('unknownPlace') })}</span>
    case 'failed_logins':
      return <span>{e.subject ? t('failed_logins', { n: n(d.count), subject }) : t('failed_logins_unknown', { n: n(d.count) })}</span>
    case 'large_export':
    case 'large_delete':
      return <span>{t(e.kind, { actor, rows: n(d.rows), entity: s(d.entity) || 'other' })}</span>
    case 'session_revoked':
      return <span>{e.actor_id && e.actor_id === e.subject_id ? t('session_revoked_self', { actor, n: n(d.count) || 1 }) : t('session_revoked', { actor, subject, n: n(d.count) || 1 })}</span>
    case 'mfa_reset':
      return <span>{s(d.via) === 'recovery_code' ? t('mfa_reset_code', { subject }) : t('mfa_reset_owner', { subject, actor })}</span>
    case 'admin_login':
      return <span>{t('admin_login', { subject, where: where || t('unknownPlace') })}</span>
    default:
      return <span>{t(e.kind, { subject, actor })}</span>
  }
}

type Run = ReturnType<typeof useGuarded>['run']

function IssueRow({ issue: i, run, busy, mayRemind, now }: { issue: Issue; run: Run; busy: boolean; mayRemind: boolean; now: string }) {
  const t = useTranslations('security.dash.issues')
  const flash = useToast()
  const router = useRouter()
  const f = useWhen(now)
  const staffList = Array.isArray(i.staff) ? i.staff : []
  const names = (xs: { name: string | null }[]) => xs.map((x) => x.name ?? '—').join(', ')
  const sev = t(`sev.${i.severity}`)
  const count = i.count ?? 0

  let title = ''
  let fix = ''
  switch (i.key) {
    case 'mfa_not_enrolled':
      title = t('mfa_not_enrolled.title', { sev, n: count })
      fix = t('mfa_not_enrolled.fix', { names: names(staffList), days: Math.max(...staffList.map((x) => x.days ?? 0), 0), n: count })
      break
    case 'mailbox_reauth':
      title = t('mailbox_reauth.title', { sev, n: count })
      fix = t('mailbox_reauth.fix', { addresses: (i.mailboxes ?? []).map((m) => m.address).join(', ') })
      break
    case 'api_tokens_old':
      title = t('api_tokens_old.title', { sev, n: count })
      fix = t('api_tokens_old.fix', { names: names(i.tokens ?? []) })
      break
    case 'access_review_due':
      title = i.due_on ? t('access_review_due.title', { sev, date: f(i.due_on, { time: false }) }) : t('access_review_due.titleNever', { sev })
      fix = t('access_review_due.fix', { n: typeof i.staff === 'number' ? i.staff : 0 })
      break
    case 'ip_allowlist_empty':
      title = t('ip_allowlist_empty.title', { sev })
      fix = t('ip_allowlist_empty.fix')
      break
    case 'webhooks_banned':
      title = t('webhooks_banned.title', { sev, n: count })
      fix = t('webhooks_banned.fix')
      break
    case 'jobs_failed':
      title = t('jobs_failed.title', { sev, n: count })
      fix = t('jobs_failed.fix')
      break
    default:
      title = `${sev} · ${i.key}`
  }

  // the issue's action: a write here, or the place where it is fixed. Navigating controls are links (V-SECURITY-01).
  const HREF: Record<string, string> = {
    reauthenticate: '/inbox',
    rotate: '/api',
    add_rule: tabHref('alerts'),
    open_webhooks: '/api?tab=webhooks',
    open_jobs: '/api?tab=jobs',
  }
  const label = t(`actions.${i.action}`)
  let action: React.ReactNode = null
  if (i.action === 'send_reminder') {
    action = mayRemind ? (
      <button type="button" className={sx.btn} disabled={busy} onClick={async () => {
        const r = await run(() => mfaReminder({ staff: staffList.map((x) => x.id) }))
        if (r.ok) flash(t(r.email === 'queued' ? 'reminderQueued' : 'reminderInApp'))
      }}>{label}</button>
    ) : null
  } else if (i.action === 'start_review') {
    action = (
      <button type="button" className={sx.btn} disabled={busy} onClick={async () => {
        const r = await run(() => reviewStart())
        if (r.ok) { flash(t('reviewStarted')); router.push(`${tabHref('signin')}#review` as Route) }
      }}>{label}</button>
    )
  } else if (HREF[i.action]) {
    action = <Link href={HREF[i.action] as Route} className={`${sx.btn} inline-flex items-center hover:text-ink hover:no-underline`}>{label}</Link>
  }

  return (
    <div className={`${sx.row} flex items-start gap-3 py-[11px]`}>
      <span className={`w-[7px] self-stretch rounded-999 ${SEV_BAR[i.severity]}`} />
      <span className="flex flex-1 flex-col gap-[2px]">
        <b className="text-13">{title}</b>
        <span className="text-12 text-muted">{fix}</span>
      </span>
      {action}
    </div>
  )
}
