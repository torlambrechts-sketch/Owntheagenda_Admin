'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Role, TeamMember } from '@/lib/data/simple-platform'
import { saveStaff } from '../../settings/actions'
import { useAct, useAgo } from '../../applications/_components/kit'
import { inviteStaff } from '../actions'

/** The design's five roles in its order; a custom set made in Settings follows by name. */
const ROLE_ORDER = ['admin', 'sales', 'support', 'marketing', 'analyst']
const COLS = '[grid-template-columns:minmax(0,1.5fr)_160px_110px_90px] max-sm:[grid-template-columns:minmax(0,1fr)_118px_76px]'

/**
 * Team and roles (SimplePlatform.dc.html, v.team): the staff list with each person's role, last activity and Remove /
 * Restore; Invite by address. Roles are permission sets (0057: Admin, Sales, Support, Marketing, Read-only); only offered sets
 * are offered, the owner is «Admin (owner)», and nobody changes their own role. Changing anything needs global:security, and
 * the address and last activity are shown only with it (staff_list). An invitation creates the staff row only (V-SPL-12).
 */
export function TeamTab({ team, roles, me, canSecurity }: { team: TeamMember[]; roles: Role[]; me: string; canSecurity: boolean }) {
  const t = useTranslations('simplePlatform.team')
  const ago = useAgo()
  const { run, pending, flash } = useAct()
  const [invite, setInvite] = useState('')
  const rank = (r: Role) => (r.key && ROLE_ORDER.includes(r.key) ? ROLE_ORDER.indexOf(r.key) : ROLE_ORDER.length)
  const offered = roles.filter((r) => r.offered).sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name))
  const label = (r: { key: string | null; name: string }) => (r.key && ROLE_ORDER.includes(r.key) ? t(`roles.${r.key}`) : r.name)

  const sendInvite = (e: React.FormEvent) => {
    e.preventDefault()
    const email = invite.trim().toLowerCase()
    if (!email.includes('@')) { flash(t('needEmail')); return }
    if (team.some((m) => m.email?.toLowerCase() === email)) { flash(t('already', { email })); return }
    run(() => inviteStaff(email), () => { setInvite(''); flash(t('invited', { email })) })
  }

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-3">
        <b className="text-15">{t('title')}</b>
        {canSecurity ? (
          <form onSubmit={sendInvite} className="flex gap-[6px]">
            <input
              type="email"
              value={invite}
              onChange={(e) => setInvite(e.target.value)}
              aria-label={t('inviteLabel')}
              placeholder="name@orgpuls.no"
              className="h-[34px] w-[220px] max-w-full rounded-9 border border-line bg-canvas px-[10px] text-12.5"
            />
            <button type="submit" disabled={pending} className="h-[34px] flex-none cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-[13px] text-12 font-bold disabled:cursor-default disabled:opacity-60">
              {t('invite')}
            </button>
          </form>
        ) : null}
      </div>
      {!canSecurity ? <div className="border-b border-line px-[18px] py-[9px] text-12 text-muted">{t('readOnly')}</div> : null}
      <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${COLS}`}>
        <span>{t('col.person')}</span><span>{t('col.role')}</span><span className="max-sm:hidden">{t('col.last')}</span><span />
      </div>
      {team.map((u) => {
        const self = u.id === me
        const locked = !canSecurity || self || u.owner || pending
        const current = roles.find((r) => r.id === u.permission_set_id)
        const last = !u.active ? t('removed') : u.login === false ? t('noLogin') : u.last_seen_at ? ago(u.last_seen_at) : '—'
        return (
          <div key={u.id} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-13 ${COLS}`} style={{ opacity: u.active ? 1 : 0.45 }}>
            <span className="flex min-w-0 flex-col">
              <b className="truncate">{u.name}</b>
              {u.email && u.email !== u.name ? <span className="truncate text-11.5 text-muted">{u.email}</span> : null}
            </span>
            <select
              value={u.permission_set_id}
              disabled={locked}
              aria-label={t('roleOf', { name: u.name })}
              onChange={(e) => {
                const next = roles.find((r) => r.id === e.target.value)
                if (!next) return
                run(() => saveStaff({ id: u.id, values: { permission_set_id: next.id } }), () => flash(t('nowRole', { name: u.name, role: label(next) })))
              }}
              className="h-8 min-w-0 rounded-9 border border-line bg-canvas text-12.5 text-ink"
            >
              {u.owner ? <option value={u.permission_set_id}>{t('owner')}</option> : (
                <>
                  {offered.map((r) => <option key={r.id} value={r.id}>{label(r)}</option>)}
                  {current && !current.offered ? <option value={current.id} disabled>{current.name}</option> : null}
                </>
              )}
            </select>
            <span className="text-muted max-sm:hidden">{last}</span>
            <button
              type="button"
              disabled={locked}
              title={self ? t('selfNote') : u.owner ? t('ownerNote') : undefined}
              onClick={() => run(() => saveStaff({ id: u.id, values: { active: !u.active } }))}
              className="h-7 cursor-pointer rounded-9 border border-coral bg-transparent text-12 font-semibold text-rust disabled:cursor-default disabled:opacity-60"
            >
              {u.active ? t('remove') : t('restore')}
            </button>
          </div>
        )
      })}
      <div className="px-[18px] py-3 text-12 text-muted">{t('legend')}</div>
    </div>
  )
}
