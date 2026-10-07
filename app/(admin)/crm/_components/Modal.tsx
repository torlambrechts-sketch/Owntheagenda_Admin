'use client'

import { useEffect, useRef } from 'react'
import { useTranslations } from 'next-intl'

/** The design's form controls inside the dialog (SimpleCRM.dc.html modal): label over a 40 px field. */
export const field = {
  label: 'flex flex-col gap-[5px] text-12 font-semibold text-muted',
  input: 'h-10 rounded-10 border border-line bg-canvas px-3 text-13 text-ink',
  select: 'h-10 rounded-10 border border-line bg-canvas text-13 text-ink',
}

/**
 * The design's dialog: dark veil, a 480 px card with a serif title, the body, and Cancel / the call to action at the
 * foot. Escape and the veil close it; focus starts on the first field (or the action) and comes back where it was.
 */
export function Modal({ title, cta, busy, error, onClose, onSubmit, children }: {
  title: string
  cta: string
  busy: boolean
  error: string | null
  onClose: () => void
  onSubmit: () => void
  children: React.ReactNode
}) {
  const tc = useTranslations('common')
  const box = useRef<HTMLDivElement>(null)
  const closeRef = useRef(onClose)
  closeRef.current = onClose
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null
    const first = box.current?.querySelector<HTMLElement>('input, select, textarea, [data-autofocus]')
    first?.focus()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); closeRef.current() } }
    window.addEventListener('keydown', onKey, true)
    return () => { window.removeEventListener('keydown', onKey, true); before?.focus?.() }
  }, [])

  return (
    <div onClick={onClose} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div
        ref={box}
        role="dialog"
        aria-modal="true"
        aria-labelledby="crm-modal-title"
        onClick={(e) => e.stopPropagation()}
        className="flex w-[480px] max-w-full flex-col gap-3 rounded-22 bg-surface px-6 py-[22px] shadow-modal"
      >
        <b id="crm-modal-title" className="font-serif text-21">{title}</b>
        {children}
        {error ? <div role="alert" className="text-12.5 font-semibold text-danger">{error}</div> : null}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className="h-10 cursor-pointer rounded-11 border border-line bg-transparent px-4 text-13 font-semibold">{tc('cancel')}</button>
          <button
            type="button"
            data-autofocus
            disabled={busy}
            onClick={onSubmit}
            className="h-10 cursor-pointer rounded-11 border border-ink bg-primary px-[18px] text-13 font-bold disabled:cursor-default disabled:opacity-60"
          >
            {cta}
          </button>
        </div>
      </div>
    </div>
  )
}
