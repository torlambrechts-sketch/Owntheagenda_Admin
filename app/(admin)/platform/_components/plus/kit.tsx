'use client'

import { useCallback, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { FreshMfa } from '../../../applications/_components/kit'

export type Fail = { ok: false; code: string; detail?: string | null }

/** Recurring classes of PlatformPlus.dc.html, transcribed from its inline styles. */
export const p = {
  card: 'overflow-hidden rounded-20 border border-line bg-surface',
  cardPad: 'flex flex-col rounded-20 border border-line bg-surface px-[18px] py-4',
  head: 'flex justify-between gap-[10px] border-b border-line px-[18px] py-[13px]',
  title: 'text-15 font-bold',
  sub: 'text-12 text-muted',
  row: 'border-b border-line px-[18px]',
  // a four-column list row (name · detail · figure · button) with the design's columns from md; below it stacks so the name
  // keeps its width: name and figure, then detail and button (the cells carry order-1/2/3 md:order-none)
  stackRow: 'grid items-center gap-[10px] py-[10px] text-12.5 [grid-template-columns:minmax(0,1fr)_110px]',
  empty: 'border-b border-line px-[18px] py-[14px] text-12.5 text-muted',
  foot: 'px-[18px] py-[10px] text-11.5 text-muted',
  // the 28 px row buttons: strong (ink border) and soft (line border)
  btnRow: 'h-7 cursor-pointer whitespace-nowrap rounded-8 border border-ink text-11.5 font-bold disabled:cursor-default disabled:opacity-60',
  btnRowSoft: 'h-7 cursor-pointer whitespace-nowrap rounded-8 border border-line bg-transparent text-11.5 font-semibold disabled:cursor-default disabled:opacity-60',
  // the 30 px Reject / Approve pair
  btnReject: 'h-[30px] cursor-pointer rounded-9 border border-coral bg-transparent px-[11px] text-12 font-semibold text-rust disabled:cursor-default disabled:opacity-60',
  btnApprove: 'h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-60',
  bar: 'h-2 overflow-hidden rounded-999 bg-tile',
  grid2: 'grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]',
  label: 'flex flex-col gap-1 text-11.5 font-semibold text-muted',
  input: 'h-[38px] rounded-10 border border-line bg-canvas px-[11px] text-13 text-ink',
}

/** A refusal in words: this screen's own detail first, then the shared codes. */
export function usePlusError() {
  const t = useTranslations('platformPlus.errors')
  const tc = useTranslations('common.errors')
  return useCallback((f: Fail) => {
    const d = f.detail ?? ''
    if (d && t.has(d)) return t(d)
    if (t.has(f.code)) return t(f.code)
    return tc.has(f.code) ? tc(f.code) : tc('failed')
  }, [t, tc])
}

/**
 * Runs an action and re-reads the page. A refusal for a stale second factor shows the code step and runs it again after;
 * any other refusal is said in the toast as it is.
 */
export function usePlusAct() {
  const router = useRouter()
  const flash = useToast()
  const err = usePlusError()
  const [pending, start] = useTransition()
  const [retry, setRetry] = useState<null | (() => void)>(null)
  const run = useCallback(<T extends { ok: boolean }>(fn: () => Promise<T>, onOk?: (r: Extract<T, { ok: true }>) => void) => {
    const go = () => start(async () => {
      const r = await fn()
      if (!r.ok) {
        const f = r as unknown as Fail
        if (f.code === 'forbidden' && f.detail === 'fresh_mfa') { setRetry(() => go); return }
        flash(err(f))
        return
      }
      setRetry(null)
      onOk?.(r as Extract<T, { ok: true }>)
      router.refresh()
    })
    go()
  }, [router, flash, err])
  const mfa = retry ? <FreshMfa onVerified={() => { const g = retry; setRetry(null); g() }} onCancel={() => setRetry(null)} /> : null
  return { run, pending, flash, err, mfa }
}

/** A card header: the design's bold title and the muted line on the right. */
export function Head({ title, sub, children }: { title: string; sub?: string | null; children?: React.ReactNode }) {
  return (
    <div className={`${p.head} flex-wrap`}>
      <b className={p.title}>{title}</b>
      {children ? (
        <span className="flex flex-wrap items-center gap-[10px]">
          {sub ? <span className={p.sub}>{sub}</span> : null}
          {children}
        </span>
      ) : sub ? <span className={p.sub}>{sub}</span> : null}
    </div>
  )
}
