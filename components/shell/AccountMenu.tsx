'use client'

import { useTransition } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { setLocale } from '@/app/(admin)/shell-actions'
import { signOut } from '@/app/login/actions'
import { formatNumber } from '@/lib/format'
import type { ShellData } from './types'

/** The initials button and its card: who I am, language, time zone, number format, settings, sign out. */
export function AccountMenu({ shell, open, toggle, close }: { shell: ShellData; open: boolean; toggle: () => void; close: () => void }) {
  const t = useTranslations('shell.account')
  const router = useRouter()
  const [pending, start] = useTransition()
  const me = shell.me
  const initials = me.initials ?? me.name.split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase()
  const pill = (sel: boolean) => `cursor-pointer rounded-999 border-none px-[9px] py-1 text-11.5 ${sel ? 'bg-highlight font-bold' : 'bg-transparent text-muted'}`

  return (
    <div className="relative">
      <button
        type="button"
        onClick={toggle}
        aria-label={t('label', { name: me.name })}
        aria-expanded={open}
        className="flex h-9 w-9 cursor-pointer items-center justify-center rounded-999 border border-ink bg-highlight text-12 font-bold"
      >
        {initials}
      </button>
      {open ? (
        <div className="absolute right-0 top-11 z-[60] w-[290px] rounded-18 border border-line bg-surface p-2 shadow-pop">
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
            {shell.settings.session_idle === 'on_30' ? <div className="px-3 py-2 text-12 text-muted">{t('idle')}</div> : null}
            <Link
              href="/settings"
              onClick={close}
              className="rounded-10 border-none bg-transparent px-3 py-[9px] text-left text-13 font-semibold text-ink hover:text-ink hover:no-underline"
            >
              {t('settings')}
            </Link>
            <form action={signOut}>
              <button type="submit" className="w-full cursor-pointer rounded-10 border-none bg-transparent px-3 py-[9px] text-left text-13 font-semibold">
                {t('signOut')}
              </button>
            </form>
          </div>
        </div>
      ) : null}
    </div>
  )
}
