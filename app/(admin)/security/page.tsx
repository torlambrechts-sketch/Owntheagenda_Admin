import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { loadAlertsAndRules, loadAudit, loadDashboard, loadLoginHistory, loadMySessions, loadPrivacy, loadProtection, loadSignin, loadStaffOpts } from '@/lib/data/security'
import { AUDIT_KINDS, TABS, type Tab } from '@/lib/data/security-shared'
import { SecurityTabs } from './_components/SecurityTabs'
import { DashboardView } from './_components/DashboardView'
import { AlertsView } from './_components/AlertsView'
import { LoginsView } from './_components/LoginsView'
import { SigninView } from './_components/SigninView'
import { ProtectView } from './_components/ProtectView'
import { PrivacyView } from './_components/PrivacyView'
import { storageReady } from '@/lib/storage/server'
import { AuditView } from './_components/AuditView'
import { SelfView } from './_components/SelfView'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Security (Security.dc.html; spec §2, SEC-01..11): seven tabs at ?tab=<key>. The whole screen needs global:security;
 * without it a staff member sees the no-permission state with their own sessions and recovery codes (D-41). Only the
 * open tab's data is read, because several reads here are themselves audited (login history, audit search).
 */
export default async function SecurityPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const shell = await getShell()
  const sp = await searchParams
  const now = new Date().toISOString()
  const wrap = (children: React.ReactNode) => <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">{children}</div>

  if (!can(shell, 'global', 'security')) {
    const sessions = await loadMySessions()
    return wrap(<SelfView sessions={sessions.ok ? sessions.data : null} meId={shell.me.id} now={now} />)
  }

  const asked = one(sp.tab)
  const tab: Tab = (TABS as readonly string[]).includes(asked ?? '') ? (asked as Tab) : 'dash'
  const t = await getTranslations('security')
  const failed = <div className="rounded-20 border border-solid border-line bg-surface p-[26px] text-13 text-muted">{t('loadFailed')}</div>

  let body: React.ReactNode = null
  switch (tab) {
    case 'dash': {
      const d = await loadDashboard()
      body = d.ok ? <DashboardView data={d.data} now={now} mayRemind /> : failed
      break
    }
    case 'alerts': {
      const { alerts, rules } = await loadAlertsAndRules()
      body = <AlertsView alerts={alerts.ok ? alerts.data : null} rules={rules.ok ? rules.data : null} nf={shell.me.number_format} />
      break
    }
    case 'logins': {
      const staff = await loadStaffOpts()
      const list = staff.ok ? staff.data.filter((s) => !s.is_sample) : []
      const wanted = z.string().uuid().safeParse(one(sp.staff))
      const selected = wanted.success && list.some((s) => s.id === wanted.data) ? wanted.data : shell.me.id
      const logins = await loadLoginHistory(selected)
      body = <LoginsView staff={list} selected={selected} logins={logins.ok ? logins.data : null} now={now} meId={shell.me.id} />
      break
    }
    case 'signin': {
      const { sso, mfa, review, staff } = await loadSignin()
      body = (
        <SigninView sso={sso.ok ? sso.data : null} mfa={mfa.ok ? mfa.data : null} review={review.ok ? review.data : null}
          staff={staff.ok ? staff.data : []} now={now} isOwner={shell.me.owner} meId={shell.me.id} />
      )
      break
    }
    case 'protect': {
      const { firewall, protection } = await loadProtection()
      body = <ProtectView firewall={firewall.ok ? firewall.data : null} protection={protection.ok ? protection.data : null} now={now} />
      break
    }
    case 'privacy': {
      const [p, storage] = await Promise.all([loadPrivacy(), storageReady()])
      body = (
        <PrivacyView retention={p.retention.ok ? p.retention.data : null} subprocessors={p.subprocessors.ok ? p.subprocessors.data : null}
          incidents={p.incidents.ok ? p.incidents.data : null} jobs={p.jobs.ok ? p.jobs.data : null} now={now} meName={shell.me.name} storage={storage} />
      )
      break
    }
    case 'audit': {
      const q = (one(sp.q) ?? '').trim().slice(0, 100)
      const k = one(sp.kind)
      const kind = (AUDIT_KINDS as readonly string[]).includes(k ?? '') ? (k as string) : ''
      const c = z.coerce.number().int().positive().safeParse(one(sp.cursor))
      const cursor = c.success ? c.data : null
      const page = await loadAudit({ ...(q ? { q } : {}), ...(kind ? { kind } : {}) }, cursor)
      body = <AuditView page={page.ok ? page.data : null} q={q} kind={kind || 'all'} cursor={cursor} now={now} />
      break
    }
  }

  return wrap(
    <>
      <SecurityTabs current={tab} />
      {body}
    </>,
  )
}
