'use client'

import { useCallback, useTransition } from 'react'
import type { Route } from 'next'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import type { RpcCode } from '@/lib/rpc'

/** Moves the screen's state in the address (tab, chosen campaign, filters) without a scroll jump. */
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
    start(() => router.push((s ? `${path}?${s}` : path) as Route, { scroll: false }))
  }, [router, path, sp])
  return { go, pending }
}

/**
 * The message for a refusal: a campaign-specific one when the database named the field (campaigns.errors.<detail>,
 * merge tokens as merge), otherwise common.errors.<code>.
 */
export function useErr() {
  const t = useTranslations('common.errors')
  const c = useTranslations('campaigns.errors')
  return useCallback((code: RpcCode, detail?: string | null) => {
    if (code === 'invalid' && detail?.startsWith('merge:')) return c('merge', { token: detail.slice(6) })
    if (code === 'version_conflict') return t(code)
    const row = code === 'invalid' && detail ? /^design\.(\d+)\.(\w+)$/.exec(detail) : null
    if (row) return c('invalid_design_row', { row: Number(row[1]) + 1, field: row[2]! })
    if (code === 'invalid' && detail?.startsWith('filter.')) return c('invalid_filter', { field: detail.slice(7) })
    const k = detail ? `${code}_${detail}`.replace(/[^a-z0-9_]/gi, '_') : null
    if (k && c.has(k)) return c(k)
    return t(code)
  }, [t, c])
}

/** Downloads a text file the server built (the recipients CSV). */
export function download(filename: string, mime: string, content: string) {
  const url = URL.createObjectURL(new Blob([content], { type: `${mime};charset=utf-8` }))
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
