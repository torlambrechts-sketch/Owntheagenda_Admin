'use client'

import { createContext, useCallback, useContext, useRef, useState } from 'react'

/** The design's toast: dark pill, bottom centre, gone after 2.6 s (every screen's flash()). */
const Ctx = createContext<(message: string) => void>(() => {})

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [msg, setMsg] = useState<string | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const flash = useCallback((m: string) => {
    setMsg(m)
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => setMsg(null), 2600)
  }, [])
  return (
    <Ctx.Provider value={flash}>
      {children}
      {msg ? (
        <div role="status" className="fixed bottom-[26px] left-1/2 z-[95] -translate-x-1/2 rounded-14 bg-ink px-[18px] py-3 text-13 font-semibold text-canvas">
          {msg}
        </div>
      ) : null}
    </Ctx.Provider>
  )
}

export const useToast = () => useContext(Ctx)
