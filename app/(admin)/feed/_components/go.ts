'use client'

import { useCallback, useTransition } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import type { RpcCode } from '@/lib/rpc'

/** Moves the screen's state in the address (tab, sub-tab, filters, the chosen model) without a scroll jump. */
export function useGo() {
  const router = useRouter()
  const path = usePathname()
  const sp = useSearchParams()
  const [pending, start] = useTransition()
  const go = useCallback((patch: Record<string, string | null>, opts: { reset?: boolean } = {}) => {
    const q = new URLSearchParams(opts.reset ? '' : sp.toString())
    for (const [k, v] of Object.entries(patch)) {
      if (v === null || v === '') q.delete(k)
      else q.set(k, v)
    }
    const s = q.toString()
    start(() => router.push((s ? `${path}?${s}` : path) as never, { scroll: false }))
  }, [router, path, sp])
  return { go, pending }
}

/** The message for a refusal the database gave (common.errors.<code>). */
export function useErr() {
  const t = useTranslations('common.errors')
  return useCallback((code: RpcCode) => t(code), [t])
}
