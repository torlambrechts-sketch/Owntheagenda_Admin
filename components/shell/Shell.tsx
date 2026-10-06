'use client'

import { useCallback, useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { routeOf } from '@/lib/nav'
import { signOut } from '@/app/login/actions'
import { Sidebar } from './Sidebar'
import { Header, type Popover } from './Header'
import { SearchDialog } from './SearchDialog'
import { AssistantPanel } from './AssistantPanel'
import { ToastProvider } from '@/components/ui/Toast'
import type { ShellData } from './types'

const IDLE_MS = 30 * 60 * 1000

/** The frame around every screen: rail, top bar, ⌘K search, assistant, and the idle sign-out (D-29). */
export function Shell({ shell, product, children }: { shell: ShellData; product: string; children: React.ReactNode }) {
  const route = routeOf(usePathname())
  const [popover, setPopover] = useState<Popover>(null)
  const [searchOpen, setSearchOpen] = useState(false)
  const [assist, setAssist] = useState(false)
  const [menu, setMenu] = useState(false)

  const closeAll = useCallback(() => { setPopover(null); setSearchOpen(false); setMenu(false) }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setPopover(null); setSearchOpen(true) }
      if (e.key === 'Escape') closeAll()
    }
    const onOpen = () => { setPopover(null); setSearchOpen(true) }
    window.addEventListener('keydown', onKey)
    window.addEventListener('sentral:search', onOpen)
    return () => { window.removeEventListener('keydown', onKey); window.removeEventListener('sentral:search', onOpen) }
  }, [closeAll])

  useEffect(() => { setPopover(null); setMenu(false) }, [route])

  // the session ends after 30 minutes without input, when the register says so
  useEffect(() => {
    if (shell.settings.session_idle !== 'on_30') return
    let timer = setTimeout(() => void signOut(), IDLE_MS)
    const reset = () => { clearTimeout(timer); timer = setTimeout(() => void signOut(), IDLE_MS) }
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
        <Header
          shell={shell}
          route={route}
          popover={popover}
          setPopover={setPopover}
          assist={assist}
          toggleAssist={() => setAssist(!assist)}
          openSearch={() => { setPopover(null); setSearchOpen(true) }}
          openMenu={() => setMenu(true)}
        />
        <div className="min-w-0 flex-1">{children}</div>
      </main>
      {assist ? <AssistantPanel onClose={() => setAssist(false)} /> : null}
      {searchOpen ? <SearchDialog onClose={() => setSearchOpen(false)} /> : null}
    </div>
    </ToastProvider>
  )
}
