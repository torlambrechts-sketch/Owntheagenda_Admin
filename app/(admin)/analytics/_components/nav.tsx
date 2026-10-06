'use client'

import { useCallback, useTransition } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'

/** Moves the screen's state in the address (tab, range, cohort, mode, touch) without a scroll jump. */
export function useGo() {
  const router = useRouter()
  const path = usePathname()
  const params = useSearchParams()
  const [pending, start] = useTransition()
  const go = useCallback((next: Record<string, string | null>, opts: { keep?: string[]; push?: boolean } = {}) => {
    const sp = new URLSearchParams(opts.keep ? '' : params.toString())
    for (const k of opts.keep ?? []) {
      const v = params.get(k)
      if (v) sp.set(k, v)
    }
    for (const [k, v] of Object.entries(next)) {
      if (v === null || v === '') sp.delete(k)
      else sp.set(k, v)
    }
    const qs = sp.toString()
    start(() => {
      const href = (qs ? `${path}?${qs}` : path) as never
      if (opts.push) router.push(href, { scroll: false })
      else router.replace(href, { scroll: false })
    })
  }, [params, path, router])
  return { go, pending }
}

/** A toggle of the design (cohort, mode, touch) that re-reads the screen with another value in the address. */
export function GoButton({ set, on, className, children }: { set: Record<string, string | null>; on: boolean; className: string; children: React.ReactNode }) {
  const { go } = useGo()
  return (
    <button type="button" aria-pressed={on} onClick={() => go(set)} className={className}>
      {children}
    </button>
  )
}
