'use client'

import { useCallback, useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { routeOf } from '@/lib/nav'
import { sessionCheck, signOut } from '@/app/login/actions'
import { Sidebar } from './Sidebar'
import { Header, type AppStatus } from './Header'
import { SearchDialog } from './SearchDialog'
import { ToastProvider } from '@/components/ui/Toast'
import type { ShellData } from './types'

const IDLE_MS = 30 * 60 * 1000
// input is use: the register hears of it at most this often, so a long read in one page is not idle on the server
const PING_MS = 5 * 60 * 1000

/** The frame around every screen (Sentral Simple): rail, top bar, ⌘K search, and the idle sign-out (D-29). */
export function Shell({ shell, product, status, children }: { shell: ShellData; product: string; status: AppStatus; children: React.ReactNode }) {
  const route = routeOf(usePathname())
  const [searchOpen, setSearchOpen] = useState(false)
  const [menu, setMenu] = useState(false)

  const closeAll = useCallback(() => { setSearchOpen(false); setMenu(false) }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setSearchOpen(true) }
      if (e.key === 'Escape') closeAll()
    }
    const onOpen = () => setSearchOpen(true)
    window.addEventListener('keydown', onKey)
    window.addEventListener('sentral:search', onOpen)
    return () => { window.removeEventListener('keydown', onKey); window.removeEventListener('sentral:search', onOpen) }
  }, [closeAll])

  useEffect(() => { setMenu(false) }, [route])

  // after 30 minutes without input the register decides (sessionCheck): an idle session ends unless its device is
  // remembered (0071), and a session in use in another tab is not idle; an unanswered check is asked once more a minute later
  useEffect(() => {
    if (shell.settings.session_idle !== 'on_30') return
    let timer: ReturnType<typeof setTimeout>
    let pinged = Date.now()
    const check = async (retry: boolean) => {
      const state = await sessionCheck().catch(() => 'unknown' as const)
      if (state === 'ok') arm(IDLE_MS)
      else if (state === 'unknown' && retry) arm(60_000, false)
      else void signOut()
    }
    const arm = (ms: number, retry = true) => { clearTimeout(timer); timer = setTimeout(() => void check(retry), ms) }
    const reset = () => {
      arm(IDLE_MS)
      if (Date.now() - pinged < PING_MS) return
      pinged = Date.now()
      void sessionCheck().then((state) => { if (state === 'ended') void signOut() }).catch(() => undefined)
    }
    arm(IDLE_MS)
    const events = ['mousemove', 'keydown', 'pointerdown', 'scroll'] as const
    events.forEach((ev) => window.addEventListener(ev, reset, { passive: true }))
    return () => { clearTimeout(timer); events.forEach((ev) => window.removeEventListener(ev, reset)) }
  }, [shell.settings.session_idle])

  return (
    <ToastProvider>
    <div className="flex min-h-screen bg-canvas font-sans text-14 text-ink">
      {menu ? <div className="fixed inset-0 z-[74] bg-[rgba(25,21,16,.42)] md:hidden" onClick={() => setMenu(false)} /> : null}
      <Sidebar shell={shell} route={route} product={product} open={menu} onNavigate={() => setMenu(false)} />
      <main className="flex min-w-0 flex-1 flex-col">
        <Header shell={shell} route={route} product={product} status={status} openMenu={() => setMenu(true)} />
        <div className="min-w-0 flex-1">{children}</div>
      </main>
      {searchOpen ? <SearchDialog onClose={() => setSearchOpen(false)} /> : null}
    </div>
    </ToastProvider>
  )
}
