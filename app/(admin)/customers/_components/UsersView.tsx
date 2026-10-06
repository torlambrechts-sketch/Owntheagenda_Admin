import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import { searchMembers } from '@/lib/data/customers'
import { UsersPanel, type UserRow } from './UsersPanel'
import { label, when } from './fmt'

/** Customers › Users: product users across every company (members_search), never respondents. */
export async function UsersView({ q, product }: { q: string; product: string }) {
  const t = await getTranslations('customers')
  const fmt = await getFormatter()
  const now = await getNow()
  const r = await searchMembers(q)
  if (!r.ok) {
    return <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center text-13 text-muted">{r.code === 'forbidden' ? t('detail.tabForbidden') : t('detail.tabFailed')}</div>
  }
  const rows: UserRow[] = r.data
    .filter((m) => product === 'all' || m.product === product)
    .map((m) => ({
      key: `${m.product}:${m.tenant_id}:${m.user_id}`,
      name: m.name ?? m.email ?? '—',
      email: m.email ?? '—',
      org: m.organization?.name ?? '—',
      role: label(t, 'roles', m.role),
      mfa: m.mfa_enabled === null ? '—' : m.mfa_enabled ? t('users.on') : t('users.off'),
      mfaTone: m.mfa_enabled === null ? 'text-muted' : m.mfa_enabled ? 'text-link' : 'text-danger',
      last: m.invite_state === 'pending' ? t('users.invitePending') : m.last_login_at ? when(m.last_login_at, now, fmt, t, 'plain') : '—',
      lastFull: m.last_login_at ? when(m.last_login_at, now, fmt, t) : '—',
      membership: [label(t, 'roles', m.role), m.invited_by ? t('usersTab.invitedBy', { name: m.invited_by }) : null, m.invited_at ? fmt.dateTime(new Date(m.invited_at), { month: 'short', year: 'numeric' }) : null].filter(Boolean).join(' · '),
      authLabel: label(t, 'auth', m.auth_method),
      mfaFact: m.mfa_enabled === null ? '—' : m.mfa_enabled ? t('usersTab.mfaOn') : t('users.off'),
      pending: m.invite_state === null ? '—' : m.invite_state === 'pending' ? t('usersTab.pendingYes') : t('usersTab.pendingNone'),
    }))
  return <UsersPanel rows={rows} q={q} />
}
