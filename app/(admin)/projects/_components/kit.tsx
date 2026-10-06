'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { searchHits, type Hit } from '../actions'

/** The design's dialog (the shell's modal language): dimmed backdrop, card, eyebrow and serif title, × and Escape close. */
export function Modal({ eyebrow, title, onClose, children, width = 520 }: { eyebrow: string; title: string; onClose: () => void; children: React.ReactNode; width?: number }) {
  const t = useTranslations('common')
  const card = useRef<HTMLDivElement>(null)
  const close = useRef(onClose)
  useEffect(() => { close.current = onClose })
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null
    card.current?.querySelector<HTMLElement>('input, textarea, select')?.focus()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); close.current() } }
    window.addEventListener('keydown', onKey, true)
    return () => { window.removeEventListener('keydown', onKey, true); prev?.focus?.() }
  }, [])
  return (
    <div onClick={onClose} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div
        ref={card}
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

export const field = 'flex flex-col gap-[5px] text-12 font-semibold text-muted'
export const fieldInput = 'h-10 rounded-10 border border-line bg-canvas px-3 text-13 font-medium text-ink disabled:opacity-60'
export const btnCancel = 'h-10 cursor-pointer rounded-11 border border-line bg-transparent px-4 text-13 font-semibold'
export const btnConfirm = 'h-10 cursor-pointer rounded-11 border border-ink bg-primary px-[18px] text-13 font-bold disabled:cursor-default disabled:opacity-60'
export const btnDanger = 'h-10 cursor-pointer rounded-11 border border-coral bg-transparent px-4 text-13 font-semibold text-rust disabled:cursor-default disabled:opacity-60'
export const note = 'rounded-12 bg-cream px-3 py-[9px] text-12 leading-[1.5] text-amber-ink'
/** The drawer's small controls (the design's 30 px buttons in the work items header). */
export const btnSmallGhost = 'h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-60'
export const btnSmallStrong = 'h-[30px] cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold disabled:cursor-default disabled:opacity-60'
export const inputSmall = 'h-[30px] rounded-9 border border-line bg-canvas px-2 text-12.5 text-ink disabled:opacity-60'
export const card = 'rounded-18 border border-line bg-surface'

/** A record search (person, organization, deal) for the drawer and the new-project dialog. */
export function Picker({ entity, onPick, onCancel }: { entity: 'person' | 'organization' | 'deal'; onPick: (h: Hit) => void; onCancel: () => void }) {
  const t = useTranslations('projects.picker')
  const [q, setQ] = useState('')
  const [hits, setHits] = useState<Hit[]>([])
  const ref = useRef<HTMLInputElement>(null)
  const seq = useRef(0)
  useEffect(() => { ref.current?.focus() }, [])
  useEffect(() => {
    const n = ++seq.current
    const h = setTimeout(() => {
      void searchHits({ entity, q }).then((r) => { if (n === seq.current && r.ok) setHits(r.rows) })
    }, 200)
    return () => clearTimeout(h)
  }, [q, entity])
  return (
    <div className="flex flex-col gap-1">
      <div className="flex gap-[6px]">
        <input
          ref={ref}
          value={q}
          aria-label={t(entity)}
          placeholder={t(entity)}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Escape') { e.stopPropagation(); onCancel() } }}
          className="h-8 min-w-0 flex-1 rounded-9 border border-line bg-canvas px-2 text-12.5"
        />
        <button type="button" onClick={onCancel} aria-label={t('cancel')} className="h-8 w-8 cursor-pointer rounded-999 border border-line bg-transparent">×</button>
      </div>
      {hits.map((h) => (
        <button key={h.id} type="button" onClick={() => onPick(h)} className="flex cursor-pointer flex-col items-start rounded-9 border-none bg-transparent px-2 py-[5px] text-left text-12.5 hover:bg-canvas">
          <b>{h.label}</b>
          {h.sub ? <span className="text-11.5 text-muted">{h.sub}</span> : null}
        </button>
      ))}
      {q && hits.length === 0 ? <span className="px-2 text-11.5 text-faint">{t('none')}</span> : null}
    </div>
  )
}
