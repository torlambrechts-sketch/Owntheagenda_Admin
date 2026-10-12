'use client'

import { useCallback, useEffect, useId, useRef, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'

export { c } from './styles'
import { c } from './styles'

export type Fail = { ok: false; code: string; detail?: string | null }

/** the words for a refusal: this area's own for a known detail, else the platform's for the code */
export function useErrorText() {
  const t = useTranslations('devCore.errors')
  const tc = useTranslations('common.errors')
  return useCallback((f: Fail) => {
    const d = f.detail ?? ''
    if (d && /^[a-z0-9_]{1,40}$/.test(d) && t.has(d)) return t(d)
    return tc.has(f.code) ? tc(f.code) : t('generic', { code: d || f.code })
  }, [t, tc])
}

/** runs a write: the refusal in the toast, the outcome in the toast, then the view again from the database */
export function useRun() {
  const flash = useToast()
  const router = useRouter()
  const err = useErrorText()
  const [pending, start] = useTransition()
  const run = useCallback(<T extends { ok: boolean }>(fn: () => Promise<T>, okMessage: (r: T) => string | null, after?: (r: T) => void) => {
    start(async () => {
      const r = await fn()
      if (!r.ok) { flash(err(r as unknown as Fail)); return }
      const m = okMessage(r)
      if (m) flash(m)
      after?.(r)
      router.refresh()
    })
  }, [flash, router, err])
  return { run, pending }
}

/**
 * The design's dialog (SimpleCRM.dc.html modal): dark veil, a card with a serif title, the body, Cancel and the action.
 * Escape and the veil close it; focus starts on the first field and returns where it was.
 */
export function Modal({ title, cta, busy, onClose, onSubmit, children, width = 520, extra }: {
  title: string; cta: string | null; busy: boolean; onClose: () => void; onSubmit?: () => void; children: React.ReactNode; width?: number
  /** a control at the foot's left (Archive) */
  extra?: React.ReactNode
}) {
  const tc = useTranslations('common')
  const id = useId()
  const box = useRef<HTMLDivElement>(null)
  const closeRef = useRef(onClose)
  useEffect(() => { closeRef.current = onClose })
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null
    box.current?.querySelector<HTMLElement>('input, select, textarea, [data-autofocus]')?.focus()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); closeRef.current() } }
    window.addEventListener('keydown', onKey, true)
    return () => { window.removeEventListener('keydown', onKey, true); before?.focus?.() }
  }, [])
  return (
    <div onClick={onClose} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div ref={box} role="dialog" aria-modal="true" aria-labelledby={id} onClick={(e) => e.stopPropagation()} style={{ width }}
        className="flex max-h-[calc(100vh-40px)] max-w-full flex-col gap-3 overflow-y-auto rounded-22 bg-surface px-6 py-[22px] shadow-modal">
        <b id={id} className="font-serif text-21">{title}</b>
        {children}
        <div className="flex flex-wrap items-center justify-end gap-2">
          {extra ? <span className="mr-auto">{extra}</span> : null}
          <button type="button" onClick={onClose} className="h-10 cursor-pointer rounded-11 border border-line bg-transparent px-4 text-13 font-semibold text-ink">
            {cta ? tc('cancel') : tc('close')}
          </button>
          {cta ? (
            <button type="button" data-autofocus disabled={busy} onClick={onSubmit}
              className="h-10 cursor-pointer rounded-11 border border-ink bg-primary px-[18px] text-13 font-bold text-ink disabled:cursor-default disabled:opacity-60">
              {cta}
            </button>
          ) : null}
        </div>
      </div>
    </div>
  )
}

/** a KPI tile (bugKpis / usage: radius 18, 13×15, the serif value at 23 px) */
export function Kpi({ label, value, sub, tone = 'text-ink', title }: { label: string; value: string; sub: string; tone?: string; title?: string }) {
  return (
    <div className="rounded-18 border border-line bg-surface px-[15px] py-[13px]" title={title}>
      <div className={c.kpiLabel}>{label}</div>
      <div className={`mt-[5px] font-serif text-23 font-semibold ${tone}`}>{value}</div>
      <div className="text-11.5 text-muted">{sub}</div>
    </div>
  )
}

export type { ProductInfo } from './styles'
