'use client'

import { useCallback, useTransition } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import type { NumberFormat } from '@/lib/format'

export type Rights = { add: boolean; del: boolean; bulk: boolean; editOthers: boolean; exp: boolean; configure: boolean }
export type Me = { id: string; nf: NumberFormat; tz: string }

/** The design's marketing-status pill colours (Contacts.dc.html, ctone). */
export const MARKETING_TONE: Record<string, string> = {
  subscribed: 'bg-ok-bg text-ok-ink',
  no_consent: 'bg-[rgba(25,21,16,.06)] text-muted',
  pending: 'bg-highlight text-amber-ink',
  unsubscribed: 'bg-peach text-rust-ink',
  bounced: 'bg-salmon text-rust-ink',
}

/** The design's activity colours on the timeline (actC). */
export const ACT_BG: Record<string, string> = { call: '#DCEBD3', meeting: '#CFE0F5', task: '#F3E2C9', deadline: '#F6D9C6', email: '#E7DAF2', lunch: '#F2EAD6', demo: '#CFE0F5' }

export const firstName = (n: string | null | undefined) => (n ? n.split(' ')[0]! : '')
export const initialsOf = (n: string) => n.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join('')
export const orgNr = (s: string | null | undefined) => (s && /^\d{9}$/.test(s) ? `${s.slice(0, 3)} ${s.slice(3, 6)} ${s.slice(6)}` : (s ?? ''))

/** URL state: the tab, the open record and the filters live in the address, so a link reopens them. */
export function useNav() {
  const router = useRouter()
  const path = usePathname()
  const sp = useSearchParams()
  const [pending, start] = useTransition()
  const go = useCallback((patch: Record<string, string | null>, push = false) => {
    const next = new URLSearchParams(sp.toString())
    for (const [k, v] of Object.entries(patch)) { if (v === null || v === '') next.delete(k); else next.set(k, v) }
    const qs = next.toString()
    const href = (qs ? `${path}?${qs}` : path) as never
    start(() => (push ? router.push(href, { scroll: false }) : router.replace(href, { scroll: false })))
  }, [path, router, sp])
  const refresh = useCallback(() => start(() => router.refresh()), [router])
  return { go, refresh, pending, sp }
}

/** The message for a refused action: the shared codes and this screen's own (file limits). */
export function useError() {
  const tc = useTranslations('common.errors')
  const t = useTranslations('contacts.errors')
  return (code: string) => (['too_large', 'empty_file', 'too_many_rows', 'xlsx'].includes(code) ? t(code as 'too_large') : tc(code as 'failed'))
}

/** A file download made in the browser from text the server built. */
export function download(name: string, text: string, type = 'text/csv;charset=utf-8') {
  const url = URL.createObjectURL(new Blob(['﻿', text], { type }))
  const a = document.createElement('a')
  a.href = url
  a.download = name
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

/** The calendar day (YYYY-MM-DD) of an instant in the staff member's time zone. */
export const localDay = (d: Date, tz: string) => new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)

/** The dialog frame the design draws for the convert modal: dimmed page, centred card, Escape closes. */
export const overlay = 'fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5'
export const dialog = 'flex w-[440px] max-w-full flex-col gap-3 rounded-22 bg-surface px-6 py-[22px] shadow-modal'
export const fieldLabel = 'flex flex-col gap-[5px] text-12 font-semibold text-muted'
export const fieldInput = 'h-[38px] rounded-10 border border-line bg-canvas px-2 text-13 font-normal text-ink'
