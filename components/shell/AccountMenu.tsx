'use client'

import { useTransition } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { setLocale, setSandbox } from '@/app/(admin)/shell-actions'
import { signOut } from '@/app/login/actions'
import { formatNumber } from '@/lib/format'
import { routeVisible } from '@/lib/nav'
import { canIn, type ShellData } from './types'

/** The initials button and its card: who I am, language, time zone, number format, settings, sign out. */
export function AccountMenu({ shell, open, toggle, close }: { shell: ShellData; open: boolean; toggle: () => void; close: () => void }) {
  const t = useTranslations('shell.account')
  const me = shell.me

  return (
    <div className="relative">
      <button
        type="button"
        onClick={toggle}
        aria-label={t('label', { name: me.name })}
        aria-expanded={open}
        className="flex h-9 w-9 cursor-pointer items-center justify-center rounded-999 border border-ink bg-highlight text-12 font-bold"
      >
        {initialsOf(me)}
      </button>
      {open ? <AccountCard shell={shell} close={close} className="absolute right-0 top-11 z-[60] w-[290px] rounded-18 border border-line bg-surface p-2 shadow-pop" /> : null}
    </div>
  )
}

/** Who I am, language, time zone, number format, sandbox, settings and security, sign out (the account card). */
export function AccountCard({ shell, close, className }: { shell: ShellData; close: () => void; className: string }) {
  const t = useTranslations('shell.account')
  const ts = useTranslations('shell.sandbox')
  const router = useRouter()
  const [pending, start] = useTransition()
  const me = shell.me
  const pill = (sel: boolean) => `cursor-pointer rounded-999 border-none px-[9px] py-1 text-11.5 ${sel ? 'bg-highlight font-bold' : 'bg-transparent text-muted'}`
  return (
    <div className={className}>
      <div className="border-b border-line px-3 pb-3 pt-2">
            <div className="text-14 font-bold">{me.name}</div>
            <div className="mt-[2px] text-12.5 text-muted">{me.email}</div>
            <div className="mt-2 text-12 font-semibold text-muted">
              {t('summary', { role: me.title ?? me.permission_set, allowlist: shell.settings.ip_allowlist === 'on' ? 'on' : 'off' })}
            </div>
          </div>
          <div className="flex flex-col gap-[2px] pt-[6px] text-13">
            <div className="flex items-center justify-between px-3 py-2">
              <span className="font-semibold">{t('language')}</span>
              <span className="flex gap-[2px]">
                {(['en', 'no'] as const).map((l) => (
                  <button
                    key={l}
                    type="button"
                    disabled={pending}
                    aria-pressed={me.locale === l}
                    onClick={() => start(async () => { await setLocale(l); router.refresh() })}
                    className={pill(me.locale === l)}
                  >
                    {t(`languages.${l}`)}
                  </button>
                ))}
              </span>
            </div>
            <div className="flex justify-between px-3 py-2">
              <span className="font-semibold">{t('timeZone')}</span>
              <span className="text-muted">{me.time_zone}</span>
            </div>
            <div className="flex justify-between px-3 py-2">
              <span className="font-semibold">{t('numberFormat')}</span>
              <span className="text-muted">{formatNumber(12345.67, me.number_format, 2)}</span>
            </div>
            <div className="flex items-center justify-between px-3 py-2">
              <span className="font-semibold">{ts('toggle')}</span>
              <button
                type="button"
                role="switch"
                aria-checked={me.sandbox}
                disabled={pending}
                onClick={() => start(async () => { await setSandbox(!me.sandbox); router.refresh() })}
                className={`relative h-[18px] w-[30px] cursor-pointer rounded-999 border-none p-0 ${me.sandbox ? 'bg-ink' : 'bg-line-strong'}`}
              >
                <span className="absolute top-[2px] h-[14px] w-[14px] rounded-999 border border-[rgba(25,21,16,.15)] bg-surface" style={{ left: me.sandbox ? 14 : 2 }} />
              </button>
            </div>
            {shell.settings.session_idle === 'on_30' ? <div className="px-3 py-2 text-12 text-muted">{t('idle')}</div> : null}
          </div>
          <div className="mt-[6px] flex flex-col gap-[2px] border-t border-line pt-2 text-13">
            <div className="px-3 pb-1 pt-[2px] text-10.5 font-bold uppercase tracking-label text-muted">{t('manage')}</div>
            {manageLinks(shell).map((l) => (
              <Link
                key={l.key}
                href={l.href as never}
                onClick={close}
                className="rounded-10 border-none bg-transparent px-3 py-[7px] text-left text-13 font-semibold text-ink hover:text-ink hover:no-underline"
              >
                {t(`links.${l.key}`)}
              </Link>
            ))}
          </div>
          <div className="mt-[6px] border-t border-line pt-[6px]">
            <form action={signOut}>
              <button type="submit" className="w-full cursor-pointer rounded-10 border-none bg-transparent px-3 py-[9px] text-left text-13 font-semibold">
                {t('signOut')}
              </button>
            </form>
          </div>
    </div>
  )
}

/**
 * Settings and security (S5): the screens Sentral Simple keeps out of the rail, reachable from the account card. Each link
 * is offered only to someone who can open it; the screens and the database check again.
 */
export function manageLinks(shell: ShellData): { key: 'settings' | 'pipelines' | 'macros' | 'security' | 'privacy' | 'audit'; href: string }[] {
  const who = { admin: shell.me.permission_kind === 'admin', rights: shell.me.rights, modules: shell.modules, meetingsWorkspace: shell.meetings_workspace }
  const security = canIn(shell, 'global', 'security')
  return [
    { key: 'settings' as const, href: '/settings', on: true },
    { key: 'pipelines' as const, href: '/settings?sec=pipelines', on: routeVisible('deals', who) },
    { key: 'macros' as const, href: '/tickets?tab=macros', on: routeVisible('tickets', who) },
    { key: 'security' as const, href: '/security', on: true },
    { key: 'privacy' as const, href: '/security?tab=privacy', on: security },
    { key: 'audit' as const, href: '/security?tab=audit', on: security },
  ].filter((l) => l.on).map(({ key, href }) => ({ key, href }))
}

export const initialsOf = (me: ShellData['me']) => me.initials ?? me.name.split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase()
