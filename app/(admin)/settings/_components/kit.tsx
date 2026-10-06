'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { RpcCode } from '@/lib/rpc'

type Outcome = { ok: true } | { ok: false; code: RpcCode }

/**
 * Runs a server action: on success the screen re-reads the database (router.refresh, so the shell's nav
 * follows a module switch) and the toast says what happened; a refusal shows its common.errors message.
 */
export function useRun() {
  const router = useRouter()
  const flash = useToast()
  const te = useTranslations('common.errors')
  const [pending, start] = useTransition()
  const run = <R extends Outcome>(action: () => Promise<R>, onOk?: (r: Extract<R, { ok: true }>) => string | void) =>
    start(async () => {
      const r = await action()
      if (!r.ok) {
        flash(te(r.code))
        return
      }
      const msg = onOk?.(r as Extract<R, { ok: true }>)
      if (msg) flash(msg)
      router.refresh()
    })
  return { run, pending }
}

/** Class strings transcribed from Settings.dc.html, used by more than one section. */
export const k = {
  card: 'overflow-hidden rounded-20 border border-line bg-surface',
  cardHead: 'flex justify-between gap-3 border-b border-line px-[18px] py-3',
  colHead: 'text-10.5 font-bold uppercase tracking-label text-muted',
  // a chip that picks (entities, pipelines, permission sets): highlight when chosen
  chip: (on: boolean) => `cursor-pointer rounded-999 border px-3 py-[6px] text-12 text-ink ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`,
  dashed: 'h-[30px] cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[11px] text-12 font-semibold text-ink disabled:cursor-default disabled:opacity-60',
  dashedChip: 'cursor-pointer rounded-999 border border-dashed border-line-strong bg-transparent px-3 py-[6px] text-12 text-ink disabled:cursor-default disabled:opacity-60',
  input: 'h-8 rounded-9 border border-line bg-canvas px-[9px] text-12.5 text-ink',
  select: 'h-[30px] max-w-[60%] rounded-8 border border-line bg-canvas text-12 text-ink',
  small: 'h-[26px] cursor-pointer rounded-8 border border-line bg-transparent px-2 text-11.5 text-ink disabled:cursor-default disabled:opacity-50',
  smallDanger: 'h-[26px] cursor-pointer rounded-8 border border-coral bg-transparent px-2 text-11.5 text-rust disabled:cursor-default disabled:opacity-50',
  primary: 'h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-3 text-12 font-bold text-ink disabled:cursor-default disabled:opacity-60',
  ghost: 'h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-3 text-12 font-semibold text-ink disabled:cursor-default disabled:opacity-60',
  label: 'flex flex-col gap-1 text-11.5 font-semibold text-muted',
  note: 'text-11.5 text-muted',
}

/** The design's switches: Modules 42×24 with an 18 px knob, Activity types 40×22 with a 16 px knob (left 3 or 21). */
export function DesignSwitch({ on, onChange, label, disabled, size = 'lg' }: { on: boolean; onChange: (on: boolean) => void; label: string; disabled?: boolean; size?: 'lg' | 'sm' }) {
  const lg = size === 'lg'
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!on)}
      className={`relative shrink-0 cursor-pointer rounded-999 border-none p-0 disabled:cursor-default disabled:opacity-60 ${lg ? 'h-6 w-[42px]' : 'h-[22px] w-10'} ${on ? 'bg-ink' : 'bg-line-strong'}`}
    >
      <span className={`absolute top-[3px] rounded-999 bg-surface ${lg ? 'h-[18px] w-[18px]' : 'h-4 w-4'}`} style={{ left: on ? 21 : 3 }} />
    </button>
  )
}

/** A notice in the design's muted note style, for a control the staff member may not use or that has no backend yet. */
export function Note({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <div className={`text-11.5 text-muted ${className}`}>{children}</div>
}
