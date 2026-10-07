'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { ROUTES, SECTIONS, type RouteKey } from '@/lib/nav'
import { clearSamples } from '@/app/(admin)/shell-actions'
import { canIn, type ShellData } from './types'

/** The application's API health, as `applications_get` reports it; null when the staff member may not read it. */
export type AppStatus = 'operational' | 'degraded' | 'unreachable' | 'no_data' | 'not_installed' | 'disabled' | null

/**
 * Sentral Simple's sticky top bar («Sentral Simple.dc.html», <header>): the application's name and description over the
 * page title, and its API status. The sandbox band below it stays while sample data is shown (the switch is in the
 * account card).
 */
export function Header({ shell, route, product, status, openMenu }: {
  shell: ShellData
  route: RouteKey
  product: string
  status: AppStatus
  openMenu: () => void
}) {
  const t = useTranslations('shell')
  const router = useRouter()
  const [pending, start] = useTransition()
  const app = shell.products.find((p) => p.key === product)
  const section = SECTIONS.some((s) => s.key === route)
  const over = section ? [app?.name, app?.description].filter(Boolean).join(' · ') : t(`crumb.${ROUTES[route].group}`)
  const title = section ? t(`section.${route}.label`) : t(`title.${route}`)

  return (
    <header className="sticky top-0 z-40 border-b border-line bg-surface">
      <div className="flex min-h-[60px] items-center gap-[14px] px-4 py-[10px] md:px-7">
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
        <div className="flex min-w-0 flex-1 flex-col">
          <span className="overflow-hidden text-ellipsis whitespace-nowrap text-11 font-semibold text-muted">{over}</span>
          <span className="font-serif text-20 font-semibold leading-[1.15]">{title}</span>
        </div>
        {status ? (
          <span className="flex items-center gap-[7px] text-12 text-muted">
            <span className={`h-[7px] w-[7px] rounded-999 ${status === 'operational' ? 'bg-ok' : status === 'degraded' || status === 'no_data' ? 'bg-warn' : 'bg-line-strong'}`} />
            {t(`apiStatus.${status}`)}
          </span>
        ) : null}
      </div>
      {shell.me.sandbox ? (
        <div className="flex flex-wrap items-center gap-3 border-t border-line bg-highlight px-4 py-[9px] text-12.5 md:px-7">
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
