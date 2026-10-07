'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { RpcCode } from '@/lib/rpc'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { dayIn } from '@/lib/data/meetings-shared'
import { searchHits, type Hit } from '../actions'

export type Me = { id: string; timeZone: string; numberFormat: NumberFormat; dealsAdd: boolean }

/** The design's card (the meeting tabs use radius 18, the list and header 20). */
export const card18 = 'rounded-18 border border-line bg-surface'
export const card20 = 'rounded-20 border border-line bg-surface'
/** The recap's 32 px button and the suggestions' 28 px pair (Meetings.dc.html). */
export const btn32 = 'h-8 cursor-pointer self-start rounded-9 border border-ink bg-surface px-[13px] text-12 font-bold disabled:cursor-default disabled:opacity-60'
export const btn28Ghost = 'h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[9px] text-11.5 font-semibold disabled:cursor-default disabled:opacity-60'
export const btn28 = 'h-7 cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-11.5 font-bold disabled:cursor-default disabled:opacity-60'
export const eyebrowAmber = 'text-11 font-bold uppercase tracking-eyebrow text-amber-ink'
/** A line that says what is not connected, in the design's quiet text. */
export const quiet = 'text-12 leading-[1.5] text-muted'
export const field = 'flex flex-col gap-[5px] text-12 font-semibold text-muted'
export const fieldInput = 'h-10 rounded-10 border border-line bg-canvas px-3 text-13 font-medium text-ink disabled:opacity-60'
export const btnCancel = 'h-10 cursor-pointer rounded-11 border border-line bg-transparent px-4 text-13 font-semibold'
export const btnConfirm = 'h-10 cursor-pointer rounded-11 border border-ink bg-primary px-[18px] text-13 font-bold disabled:cursor-default disabled:opacity-60'
export const btnDanger = 'h-10 cursor-pointer rounded-11 border border-coral bg-transparent px-4 text-13 font-semibold text-rust disabled:cursor-default disabled:opacity-60'

/** Errors as the common messages, a few known details as the meetings' own. */
export function useFail() {
  const flash = useToast()
  const te = useTranslations('common.errors')
  const tm = useTranslations('meetings.errors')
  return useCallback((r: { code: RpcCode; detail?: string | null }) => {
    const key = r.code === 'not_connected' && r.detail ? `not_connected_${r.detail}` : r.code === 'forbidden' && r.detail ? `forbidden_${r.detail.replace(/[:]/g, '_')}` : null
    flash(key && tm.has(key) ? tm(key) : te(r.code))
  }, [flash, te, tm])
}

/**
 * «Thu 8 Oct»: weekday and date formatted apart, because Node's and the browser's ICU join them differently
 * («Thu, 8 Oct» on the server) and a server-rendered date must match the client's.
 */
export const weekdayDate = (f: ReturnType<typeof useFormatter>, d: Date) => `${f.dateTime(d, { weekday: 'short' })} ${f.dateTime(d, { day: 'numeric', month: 'short' })}`

/** Dates the design's way, in the staff member's zone: «Thu 8 Oct 10:00», «Today 09:00», «2 Oct». */
export function useWhen(me: Me) {
  const f = useFormatter()
  const t = useTranslations('meetings')
  return useCallback((iso: string | null, opts: { time?: boolean; day?: 'weekday' | 'plain' } = {}) => {
    if (!iso) return t('dash')
    const d = new Date(iso)
    const time = f.dateTime(d, { hour: '2-digit', minute: '2-digit' })
    const today = dayIn(new Date(), me.timeZone) === dayIn(d, me.timeZone)
    const date = today ? t('today') : opts.day === 'plain' ? f.dateTime(d, { day: 'numeric', month: 'short' }) : weekdayDate(f, d)
    return opts.time === false ? date : `${date} ${time}`
  }, [f, t, me.timeZone])
}

export const useNum = (me: Me) => useCallback((n: number) => formatNumber(n, me.numberFormat, Number.isInteger(n) ? 0 : 1), [me.numberFormat])

/** The design's dialog (the shell's modal language): dimmed backdrop, card, eyebrow and serif title, × and Escape close. */
export function Modal({ eyebrow, title, onClose, children, width = 480 }: { eyebrow: string; title: string; onClose: () => void; children: React.ReactNode; width?: number }) {
  const t = useTranslations('common')
  const box = useRef<HTMLDivElement>(null)
  const close = useRef(onClose)
  useEffect(() => { close.current = onClose })
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null
    box.current?.querySelector<HTMLElement>('input, textarea, select, button[data-autofocus]')?.focus()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); close.current() } }
    window.addEventListener('keydown', onKey, true)
    return () => { window.removeEventListener('keydown', onKey, true); prev?.focus?.() }
  }, [])
  return (
    <div onClick={onClose} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div
        ref={box}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
        style={{ width }}
        className="flex max-h-[calc(100vh-40px)] max-w-full flex-col gap-[14px] overflow-y-auto rounded-22 bg-surface px-[26px] py-6 shadow-modal"
      >
        <div className="flex items-start justify-between gap-[10px]">
          <div>
            <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{eyebrow}</div>
            <div className="mt-1 font-serif text-22 font-semibold">{title}</div>
          </div>
          <button type="button" onClick={onClose} aria-label={t('close')} className="h-[30px] w-[30px] flex-none cursor-pointer rounded-999 border border-ink bg-transparent">×</button>
        </div>
        {children}
      </div>
    </div>
  )
}

/** A record search for linking a meeting: deal, lead, person or organization. */
export function Picker({ entity, onPick }: { entity: 'deal' | 'lead' | 'person' | 'organization'; onPick: (h: Hit) => void }) {
  const t = useTranslations('meetings.link')
  const [q, setQ] = useState('')
  const [hits, setHits] = useState<Hit[]>([])
  const seq = useRef(0)
  useEffect(() => {
    const n = ++seq.current
    const h = setTimeout(() => {
      void searchHits({ entity, q }).then((r) => { if (n === seq.current && r.ok) setHits(r.rows) })
    }, 200)
    return () => clearTimeout(h)
  }, [q, entity])
  return (
    <div className="flex flex-col gap-1">
      <input value={q} aria-label={t('search')} placeholder={t('search')} onChange={(e) => setQ(e.target.value)} className={fieldInput} />
      <div className="flex max-h-[240px] flex-col overflow-y-auto">
        {hits.map((h) => (
          <button key={h.id} type="button" onClick={() => onPick(h)} className="cursor-pointer rounded-9 border-none bg-transparent px-2 py-[7px] text-left text-13 hover:bg-highlight">
            {h.label}
          </button>
        ))}
        {hits.length === 0 ? <span className="px-2 py-[7px] text-12 text-faint">{t('noHits')}</span> : null}
      </div>
    </div>
  )
}
