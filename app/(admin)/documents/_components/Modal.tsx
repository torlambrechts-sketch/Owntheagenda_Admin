'use client'

import { useEffect, useRef } from 'react'
import { useTranslations } from 'next-intl'

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
    window.addEventListener('keydown', onKey)
    return () => { window.removeEventListener('keydown', onKey); prev?.focus?.() }
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
