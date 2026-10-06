'use client'

import { useEffect, useState, useTransition } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { initials } from './fmt'

export type UserRow = {
  key: string
  name: string
  email: string
  org: string
  role: string
  mfa: string
  mfaTone: string
  last: string
  lastFull: string
  membership: string
  authLabel: string
  mfaFact: string
  pending: string
}

const ACTIONS = [
  ['magicLink', false], ['resetMfa', false], ['changeEmail', false], ['billingContact', false], ['remove', true], ['deactivate', true],
] as const

/** The users list with its search and the selected user's card (Customers.dc.html, v.users). */
export function UsersPanel({ rows, q }: { rows: UserRow[]; q: string }) {
  const t = useTranslations('customers.usersTab')
  const tn = useTranslations('customers')
  const router = useRouter()
  const pathname = usePathname()
  const params = useSearchParams()
  const [, start] = useTransition()
  const [text, setText] = useState(q)
  const [picked, setPicked] = useState<string | null>(rows[0]?.key ?? null)

  useEffect(() => {
    if (text === q) return
    const h = setTimeout(() => {
      const sp = new URLSearchParams(params.toString())
      if (text.trim()) sp.set('uq', text.trim())
      else sp.delete('uq')
      start(() => router.replace(`${pathname}?${sp}` as never, { scroll: false }))
    }, 300)
    return () => clearTimeout(h)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text])

  const user = rows.find((r) => r.key === picked) ?? rows[0]
  const memberships = user ? rows.filter((r) => r.email !== '—' && r.email.toLowerCase() === user.email.toLowerCase()) : []

  return (
    <div className="grid items-start gap-4 [grid-template-columns:minmax(0,1fr)_340px] max-md:[grid-template-columns:minmax(0,1fr)]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="border-b border-line px-4 py-3">
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={t('search')}
            aria-label={t('search')}
            className="h-9 w-full rounded-10 border border-line bg-canvas px-3 text-13"
          />
        </div>
        <div className="overflow-x-auto">
          <div className="max-md:min-w-[560px]">
            {rows.map((u) => (
              <button
                key={u.key}
                type="button"
                aria-pressed={user?.key === u.key}
                onClick={() => setPicked(u.key)}
                className={`grid w-full cursor-pointer items-center gap-[10px] border-b border-line px-4 py-[10px] text-left text-13 [grid-template-columns:minmax(0,1.5fr)_minmax(0,1.2fr)_110px_90px_90px] ${user?.key === u.key ? 'bg-highlight' : 'bg-transparent'}`}
              >
                <span className="flex min-w-0 flex-col"><b>{u.name}</b><span className="overflow-hidden text-ellipsis whitespace-nowrap text-11.5 text-muted">{u.email}</span></span>
                <span className="text-ink-2">{u.org}</span>
                <span>{u.role}</span>
                <span className={u.mfaTone}>{u.mfa}</span>
                <span className="text-muted">{u.last}</span>
              </button>
            ))}
            {rows.length === 0 ? <div className="px-4 py-[26px] text-center text-13 text-muted">{t('empty')}</div> : null}
          </div>
        </div>
      </div>
      <div className="sticky top-20 flex flex-col gap-3 rounded-20 border border-line bg-surface px-[22px] py-5">
        {user ? (
          <>
            <div className="flex items-center gap-3">
              <span className="flex h-11 w-11 items-center justify-center rounded-13 bg-ink font-serif font-bold text-canvas">{initials(user.name)}</span>
              <span className="flex flex-col"><b className="text-15">{user.name}</b><span className="text-12 text-muted">{user.email}</span></span>
            </div>
            <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('memberships')}</div>
            {memberships.map((m) => (
              <div key={m.key} className="flex justify-between border-b border-line py-[6px] text-12.5">
                <span className="flex flex-col"><b>{m.org}</b><span className="text-11.5 text-muted">{m.membership}</span></span>
              </div>
            ))}
            {[
              [t('lastLogin'), user.lastFull], [t('mfa'), user.mfaFact], [t('auth'), user.authLabel], [t('pending'), user.pending],
            ].map(([k, v]) => (
              <div key={k} className="flex justify-between text-12.5"><span className="text-muted">{k}</span><b>{v}</b></div>
            ))}
            <div className="flex flex-wrap gap-[6px] pt-[6px]">
              {ACTIONS.map(([k, danger]) => (
                <button
                  key={k}
                  type="button"
                  disabled
                  title={tn('notYet')}
                  className={`h-[30px] cursor-default rounded-9 border bg-transparent px-[11px] text-12 font-semibold opacity-55 ${danger ? 'border-coral text-rust' : 'border-line text-ink'}`}
                >
                  {t(`actions.${k}`)}
                </button>
              ))}
            </div>
            <div className="text-11.5 text-muted">{tn('users.actionsNotYet')}</div>
          </>
        ) : (
          <div className="text-13 text-muted">{t('none')}</div>
        )}
      </div>
    </div>
  )
}
