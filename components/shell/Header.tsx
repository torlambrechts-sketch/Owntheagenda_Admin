'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { ROUTES, type RouteKey } from '@/lib/nav'
import { clearSamples, setSandbox } from '@/app/(admin)/shell-actions'
import { NotificationsMenu } from './NotificationsMenu'
import { AccountMenu } from './AccountMenu'
import { canIn, type ShellData } from './types'

export type Popover = 'notif' | 'acct' | null

/** The sticky top bar (Sentral Admin.dc.html, <header>) and the sandbox band under it. */
export function Header({ shell, route, popover, setPopover, assist, toggleAssist, openSearch, openMenu }: {
  shell: ShellData
  route: RouteKey
  popover: Popover
  setPopover: (p: Popover) => void
  assist: boolean
  toggleAssist: () => void
  openSearch: () => void
  openMenu: () => void
}) {
  const t = useTranslations('shell')
  const router = useRouter()
  const [pending, start] = useTransition()
  const sandbox = shell.me.sandbox
  const group = ROUTES[route].group

  return (
    <header className="sticky top-0 z-40 border-b border-line bg-surface">
      <div className="flex min-h-[56px] items-center gap-[14px] px-4 py-2 md:px-[26px]">
        <button
          type="button"
          onClick={openMenu}
          aria-label={t('openMenu')}
          className="flex h-9 w-9 flex-none cursor-pointer items-center justify-center rounded-10 border border-line bg-transparent md:hidden"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true">
            <path d="M4 7h16M4 12h16M4 17h16" />
          </svg>
        </button>
        <div className="flex min-w-[120px] flex-1 flex-col overflow-hidden whitespace-nowrap">
          <span className="overflow-hidden text-ellipsis text-11 font-semibold text-muted">{t(`crumb.${group}`)}</span>
          <span className="overflow-hidden text-ellipsis font-serif text-18 font-semibold leading-[1.15]">{t(`title.${route}`)}</span>
        </div>
        <button
          type="button"
          onClick={openSearch}
          className="flex h-[38px] min-w-[40px] flex-[0_1_300px] cursor-pointer items-center gap-[9px] overflow-hidden rounded-10 border border-line bg-canvas px-3 text-13 text-faint"
        >
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" className="flex-none" aria-hidden="true">
            <path d="M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14M20 20l-4-4" />
          </svg>
          <span className="min-w-0 flex-1 overflow-hidden text-ellipsis whitespace-nowrap text-left max-md:sr-only">{t('search.placeholder')}</span>
          <span className="rounded-6 border border-line bg-surface px-[6px] py-[2px] text-11 font-bold text-muted max-md:hidden">⌘K</span>
        </button>
        <button
          type="button"
          aria-pressed={sandbox}
          disabled={pending}
          onClick={() => start(async () => { await setSandbox(!sandbox); router.refresh() })}
          className={`flex h-[34px] cursor-pointer items-center gap-2 rounded-10 border px-[11px] text-12.5 font-semibold max-md:hidden ${sandbox ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`}
        >
          <span className={`relative h-[18px] w-[30px] rounded-999 ${sandbox ? 'bg-ink' : 'bg-line-strong'}`}>
            <span className="absolute top-[2px] h-[14px] w-[14px] rounded-999 border border-[rgba(25,21,16,.15)] bg-surface" style={{ left: sandbox ? 14 : 2 }} />
          </span>
          {t('sandbox.toggle')}
        </button>
        <NotificationsMenu shell={shell} open={popover === 'notif'} toggle={() => setPopover(popover === 'notif' ? null : 'notif')} close={() => setPopover(null)} />
        <button
          type="button"
          aria-pressed={assist}
          onClick={toggleAssist}
          className={`flex h-9 cursor-pointer items-center gap-2 rounded-10 border pl-1 pr-3 text-12.5 font-semibold max-md:pr-1 ${assist ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`}
        >
          {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's assistant portrait */}
          <img src="/brand/assistant.png" alt="" width={28} height={28} className="block rounded-9 bg-canvas" />
          <span className="max-md:sr-only">{t('assistant.button')}</span>
        </button>
        <AccountMenu shell={shell} open={popover === 'acct'} toggle={() => setPopover(popover === 'acct' ? null : 'acct')} close={() => setPopover(null)} />
      </div>
      {sandbox ? (
        <div className="flex flex-wrap items-center gap-3 border-t border-line bg-highlight px-4 py-[9px] text-12.5 md:px-[26px]">
          <span className="font-bold">{t('sandbox.title')}</span>
          <span className="text-amber-ink">{t('sandbox.body')}</span>
          <span className="flex-1" />
          {canIn(shell, 'global', 'configure') ? (
            <button
              type="button"
              disabled={pending}
              onClick={() => start(async () => { await clearSamples(); router.refresh() })}
              className="h-7 cursor-pointer rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold"
            >
              {t('sandbox.remove')}
            </button>
          ) : null}
        </div>
      ) : null}
    </header>
  )
}
