'use client'

import { createContext, useCallback, useContext, useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { reverify } from '../actions'

/** Recurring classes of Platform.dc.html, transcribed from its inline styles. */
export const k = {
  card: 'overflow-hidden rounded-20 border border-line bg-surface',
  cardPad: 'flex flex-col rounded-20 border border-line bg-surface px-[18px] py-4',
  head: 'flex items-center justify-between gap-[10px] border-b border-line px-[18px] py-3',
  headTitle: 'text-14 font-bold',
  row: 'border-b border-line px-[18px] text-12.5',
  mono: 'font-[ui-monospace,Menlo,monospace]',
  // the 28 px buttons: strong (ink border, surface), primary (yellow), soft (line border)
  btn: 'h-7 cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold disabled:cursor-default disabled:opacity-60',
  btnPrimary: 'h-7 cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-[10px] text-12 font-bold disabled:cursor-default disabled:opacity-60',
  btnSoft: 'h-7 cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-60',
  btnRevoke: 'h-[26px] cursor-pointer rounded-8 border border-coral bg-transparent text-11.5 font-semibold text-rust disabled:cursor-default disabled:opacity-60',
  // the dialog's 38 px controls
  label: 'flex flex-col gap-1 text-11.5 font-semibold text-muted',
  input: 'h-[38px] rounded-10 border border-line bg-canvas px-[11px] text-13 text-ink',
  dlgCancel: 'h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold',
  dlgConfirm: 'h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60',
  dlgDanger: 'h-[38px] cursor-pointer rounded-11 border border-coral bg-transparent px-[15px] text-13 font-semibold text-rust disabled:cursor-default disabled:opacity-60',
  note: 'text-11.5 text-muted',
  empty: 'px-[18px] py-[14px] text-12.5 text-muted',
  chip: (on: boolean) => `cursor-pointer rounded-999 border px-[10px] py-[5px] text-12 font-[ui-monospace,Menlo,monospace] ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`,
}

export type Fail = { ok: false; code: string; detail?: string | null }

/** The design's dialog (Connect an application): 560 px card, 22 px radius, serif title; Escape and the backdrop close. */
export function Dialog({ title, onClose, children, width = 560 }: { title: string; onClose: () => void; children: React.ReactNode; width?: number }) {
  const card = useRef<HTMLDivElement>(null)
  const close = useRef(onClose)
  useEffect(() => { close.current = onClose })
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null
    card.current?.querySelector<HTMLElement>('input, textarea, select, button')?.focus()
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
        className="flex max-h-[calc(100vh-40px)] max-w-full flex-col gap-[11px] overflow-y-auto rounded-22 bg-surface px-6 py-[22px] shadow-modal"
      >
        <b className="font-serif text-21">{title}</b>
        {children}
      </div>
    </div>
  )
}

/** The design's small switch (feature flags, maintenance): 40×22, 16 px knob at 3 or 21. */
export function Toggle({ on, onChange, label, disabled, big }: { on: boolean; onChange: (on: boolean) => void; label: string; disabled?: boolean; big?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!on)}
      className={`relative flex-none cursor-pointer rounded-999 border-none disabled:cursor-default disabled:opacity-60 ${big ? 'h-6 w-11' : 'h-[22px] w-10'} ${on ? 'bg-ink' : 'bg-line-strong'}`}
    >
      <span
        className={`absolute top-[3px] rounded-999 bg-surface ${big ? 'h-[18px] w-[18px]' : 'h-4 w-4'}`}
        style={{ left: big ? (on ? 23 : 5) : on ? 21 : 3 }}
      />
    </button>
  )
}

/** The message for a refusal: common.errors.<code>, or the screen's own words for a known detail. */
export function useErrorText() {
  const tc = useTranslations('common.errors')
  const t = useTranslations('platform.errors')
  return useCallback((f: Fail) => {
    const d = f.detail ?? ''
    if (d && t.has(d)) return t(d)
    return tc.has(f.code) ? tc(f.code) : tc('failed')
  }, [t, tc])
}

/** Runs an action, toasts the refusal, re-reads the page on success. */
export function useAct() {
  const router = useRouter()
  const flash = useToast()
  const errText = useErrorText()
  const [pending, start] = useTransition()
  const run = useCallback(<T extends { ok: boolean }>(fn: () => Promise<T>, onOk?: (r: T) => void, opts: { refresh?: boolean } = {}) => {
    start(async () => {
      const r = await fn()
      if (!r.ok) { flash(errText(r as unknown as Fail)); return }
      onOk?.(r)
      if (opts.refresh !== false) router.refresh()
    })
  }, [router, flash, errText])
  return { run, pending, flash, errText }
}

/** The server's «now» for this render, so a relative time reads the same on the server and in the browser. */
const NowCtx = createContext<string | null>(null)
export function NowProvider({ now, children }: { now: string; children: React.ReactNode }) {
  return <NowCtx.Provider value={now}>{children}</NowCtx.Provider>
}

export const useNowMs = () => { const iso = useContext(NowCtx); return iso ? new Date(iso).getTime() : Date.now() }

/** «2 min ago», or the design's null «—». */
export function useAgo() {
  const format = useFormatter()
  const iso = useContext(NowCtx)
  const t = useTranslations('common')
  return useCallback((v: string | null | undefined) => (v ? format.relativeTime(new Date(v), iso ? new Date(iso) : new Date()) : t('dash')), [format, iso, t])
}

/**
 * The fresh second factor (0043 require_fresh_mfa): a sensitive action refused with forbidden/fresh_mfa asks for the
 * authenticator code again, then retries. The refusal is said as it is; nothing is skipped.
 */
export function FreshMfa({ onVerified, onCancel }: { onVerified: () => void; onCancel: () => void }) {
  const t = useTranslations('platform.mfa')
  const [code, setCode] = useState('')
  const [bad, setBad] = useState(false)
  const [pending, start] = useTransition()
  const submit = () => start(async () => {
    const r = await reverify({ code })
    if (r.ok) onVerified()
    else setBad(true)
  })
  return (
    <div className="flex flex-col gap-2 rounded-12 bg-amber-bg px-3 py-[10px] text-12.5 text-amber-ink">
      <b>{t('title')}</b>
      <span>{t('body')}</span>
      <div className="flex flex-wrap gap-2">
        <input
          value={code}
          onChange={(e) => { setCode(e.target.value.replace(/\D/g, '').slice(0, 6)); setBad(false) }}
          onKeyDown={(e) => { if (e.key === 'Enter' && code.length === 6) submit() }}
          inputMode="numeric"
          autoComplete="one-time-code"
          aria-label={t('code')}
          placeholder={t('code')}
          className={`${k.input} w-[140px] ${k.mono}`}
        />
        <button type="button" disabled={code.length !== 6 || pending} onClick={submit} className={k.dlgConfirm}>{t('verify')}</button>
        <button type="button" onClick={onCancel} className={k.dlgCancel}>{t('cancel')}</button>
      </div>
      {bad ? <span className="font-semibold text-danger">{t('failed')}</span> : null}
    </div>
  )
}

/**
 * A sensitive action (token, client secret, connecting an application): runs it, and when the database refuses for a stale
 * second factor shows the code step and retries after it. Other refusals are returned as text for the dialog.
 */
export function useSensitive() {
  const errText = useErrorText()
  const [retry, setRetry] = useState<null | (() => void)>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, start] = useTransition()
  const router = useRouter()
  const call = useCallback(<T extends { ok: boolean }>(fn: () => Promise<T>, onOk: (r: T) => void) => {
    setError(null)
    const go = () => start(async () => {
      const r = await fn()
      if (r.ok) { setRetry(null); onOk(r); router.refresh(); return }
      const f = r as unknown as Fail
      if (f.code === 'forbidden' && f.detail === 'fresh_mfa') setRetry(() => go)
      else setError(errText(f))
    })
    go()
  }, [errText, router])
  const mfa = retry ? <FreshMfa onVerified={() => { const g = retry; setRetry(null); g() }} onCancel={() => setRetry(null)} /> : null
  const alert = error ? <div role="alert" className="text-12.5 font-semibold text-danger">{error}</div> : null
  return { call, pending, mfa, alert, blocked: retry !== null }
}

/** A value shown once (a token, a signing secret, an intake code): selectable, copyable, gone when the dialog closes. */
export function OnceValue({ label, value, warning }: { label: string; value: string; warning: string }) {
  const t = useTranslations('platform.once')
  const [copied, setCopied] = useState(false)
  return (
    <div className="flex flex-col gap-[6px]">
      <span className="text-11.5 font-semibold text-muted">{label}</span>
      <div className="flex gap-2">
        <input readOnly value={value} onFocus={(e) => e.currentTarget.select()} aria-label={label} className={`${k.input} min-w-0 flex-1 ${k.mono} text-12`} />
        <button
          type="button"
          className={k.dlgCancel}
          onClick={() => { void navigator.clipboard?.writeText(value).then(() => setCopied(true), () => setCopied(false)) }}
        >
          {copied ? t('copied') : t('copy')}
        </button>
      </div>
      <span className="rounded-12 bg-amber-bg px-3 py-[9px] text-12 font-semibold text-amber-ink">{warning}</span>
    </div>
  )
}

/** «You can read this. Changing it needs the right …» (V-SETTINGS-33). */
export function ReadOnly({ right }: { right: 'configure' | 'security' | 'owner' }) {
  const t = useTranslations('platform')
  return <div className="border-b border-line px-[18px] py-[9px] text-12 text-muted">{t('readOnly', { right: t(`rights.${right}`) })}</div>
}
