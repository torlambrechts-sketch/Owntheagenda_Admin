'use client'

import { useTranslations } from 'next-intl'

/**
 * Small pieces the support views share, transcribed from SupportHub.dc.html's inline styles: the card, the card header,
 * the uppercase label, the 40×22 switch, and the one honest line a disabled control carries.
 */
export const card = 'rounded-20 border border-line bg-surface'
export const cardInk = 'rounded-20 border border-ink bg-surface'
export const cardHead = 'flex justify-between gap-[10px] border-b border-line px-[18px] py-[13px]'
export const label = 'text-10.5 font-bold uppercase tracking-[.08em] text-muted'
export const sectionLabel = 'text-11 font-bold uppercase tracking-[.1em] text-muted'

/** a refusal code as words: this screen's own message, else the common one */
export function useSupportError() {
  const t = useTranslations('supportHub.errors')
  const c = useTranslations('common.errors')
  return (code: string) => (t.has(code) ? t(code) : c.has(code) ? c(code) : c('failed'))
}

/** a view the staff member may not read: the reason, never an empty frame that looks like data */
export function Refused({ code }: { code: string }) {
  const text = useSupportError()
  return <div className={`${card} px-[18px] py-4 text-12.5 text-muted`}>{text(code)}</div>
}

/** the line under a disabled control that says why */
export function Why({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <span className={`text-11.5 leading-[1.45] text-muted ${className}`}>{children}</span>
}

/** the design's switch: 40×22 track, a 16 px knob at 3 or 21 */
export function Toggle({ on, label: name, disabled, why, onChange }: { on: boolean; label: string; disabled?: boolean; why?: string | null; onChange?: (on: boolean) => void }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={name}
      title={why ?? undefined}
      disabled={disabled}
      onClick={() => onChange?.(!on)}
      className={`relative h-[22px] w-10 flex-none cursor-pointer rounded-999 border-none disabled:cursor-not-allowed disabled:opacity-60 ${on ? 'bg-ink' : 'bg-line-strong'}`}
    >
      <span className="absolute top-[3px] h-4 w-4 rounded-999 bg-surface" style={{ left: on ? 21 : 3 }} />
    </button>
  )
}
