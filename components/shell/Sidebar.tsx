'use client'

import Link from 'next/link'
import { useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { ROUTES, SECTIONS, routeVisible, type RouteKey } from '@/lib/nav'
import { setProduct } from '@/app/(admin)/shell-actions'
import { AccountCard, initialsOf } from './AccountMenu'
import type { ShellData } from './types'

/**
 * Sentral Simple's rail («Sentral Simple.dc.html», <aside>): brand, the application select, the four sections and the
 * signed-in person. The design's section buttons are links (control substitution, D-06: the prototype has no router), and
 * the person at the foot opens the account card (the prototype has no sign-out).
 */
export function Sidebar({ shell, route, product, open, onNavigate }: { shell: ShellData; route: RouteKey; product: string; open: boolean; onNavigate: () => void }) {
  const t = useTranslations('shell')
  const router = useRouter()
  const [, start] = useTransition()
  const [account, setAccount] = useState(false)
  const foot = useRef<HTMLDivElement>(null)
  const who = { admin: shell.me.permission_kind === 'admin', rights: shell.me.rights, modules: shell.modules, meetingsWorkspace: shell.meetings_workspace }

  useEffect(() => {
    if (!account) return
    const onDoc = (e: MouseEvent) => { if (foot.current && !foot.current.contains(e.target as Node)) setAccount(false) }
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setAccount(false) }
    document.addEventListener('mousedown', onDoc)
    window.addEventListener('keydown', onKey)
    return () => { document.removeEventListener('mousedown', onDoc); window.removeEventListener('keydown', onKey) }
  }, [account])

  return (
    <aside
      className={`${open ? 'flex' : 'hidden'} md:flex fixed md:sticky left-0 top-0 z-[75] md:z-auto h-screen w-[244px] flex-none flex-col gap-[14px] border-r border-line bg-surface px-3 py-4`}
    >
      <div className="flex items-center gap-[10px] px-1">
        {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's own mark, served as a static file */}
        <img src="/brand/orgpuls-mark.svg" alt="" width={30} height={30} className="block" />
        <div className="flex flex-col">
          <span className="font-serif text-19 font-semibold leading-none">{t('brand')}</span>
          <span className="text-11 font-semibold text-muted">{t('brandSub')}</span>
        </div>
      </div>
      <label className="flex flex-col gap-1 px-1 text-10.5 font-bold uppercase tracking-label text-muted">
        {t('application')}
        <select
          value={product}
          onChange={(e) => { const key = e.target.value; start(async () => { await setProduct(key); router.refresh() }) }}
          className="h-[38px] rounded-10 border border-line bg-canvas px-2 text-13 font-bold normal-case tracking-normal text-ink"
        >
          {shell.products.map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}
        </select>
      </label>
      <nav aria-label={t('mainMenu')} className="flex flex-col gap-1">
        {SECTIONS.filter((s) => routeVisible(s.key, who)).map((s) => {
          const cur = s.key === route
          return (
            <Link
              key={s.key}
              href={ROUTES[s.key].path as never}
              onClick={onNavigate}
              aria-current={cur ? 'page' : undefined}
              className={`flex w-full items-center gap-[11px] rounded-13 px-[10px] py-[9px] text-left text-ink hover:text-ink hover:no-underline ${cur ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <span className={`flex h-8 w-8 flex-none items-center justify-center rounded-10 ${cur ? 'bg-primary' : 'bg-tile'}`}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d={s.icon} />
                </svg>
              </span>
              <span className="flex min-w-0 flex-col">
                <span className={`text-14 ${cur ? 'font-bold' : 'font-semibold'}`}>{t(`section.${s.key}.label`)}</span>
                <span className="overflow-hidden text-ellipsis whitespace-nowrap text-11.5 text-muted">{t(`section.${s.key}.sub`)}</span>
              </span>
            </Link>
          )
        })}
      </nav>
      <span className="flex-1" />
      <div ref={foot} className="relative">
        {account ? (
          <AccountCard shell={shell} close={() => setAccount(false)} className="absolute bottom-full left-0 z-[60] mb-2 w-[290px] rounded-18 border border-line bg-surface p-2 shadow-pop" />
        ) : null}
        <button
          type="button"
          onClick={() => setAccount(!account)}
          aria-expanded={account}
          aria-label={t('account.label', { name: shell.me.name })}
          className="flex w-full cursor-pointer items-center gap-[10px] border-x-0 border-b-0 border-t border-solid border-line bg-transparent p-[10px] text-left"
        >
          <span className="flex h-8 w-8 flex-none items-center justify-center rounded-999 border border-solid border-ink bg-highlight text-11.5 font-bold">{initialsOf(shell.me)}</span>
          <span className="flex min-w-0 flex-col">
            <b className="text-13">{shell.me.name}</b>
            <span className="text-11.5 text-muted">{shell.me.permission_set}</span>
          </span>
        </button>
      </div>
    </aside>
  )
}
