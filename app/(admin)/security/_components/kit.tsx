'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useRouter } from 'next/navigation'
import { useToast } from '@/components/ui/Toast'
import { errorDetailKey } from '@/lib/data/security-shared'
import { confirmFactor, type Result } from '../actions'

/** Recurring class strings of Security.dc.html, transcribed from its inline styles. */
export const sx = {
  card: 'overflow-hidden rounded-20 border border-line bg-surface',
  cardPad: 'flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4',
  head: 'flex justify-between gap-[10px] border-0 border-b border-solid border-line px-[18px] py-3',
  headTitle: 'px-[18px] py-3 text-14 font-bold border-0 border-b border-solid border-line',
  row: 'border-0 border-b border-solid border-line px-[18px]',
  colHead: 'text-10.5 font-bold uppercase tracking-label text-muted',
  // the design's small outlined button (Assessment, Export, ＋ Log incident)
  btn: 'h-7 cursor-pointer whitespace-nowrap rounded-9 border border-solid border-ink bg-surface px-[10px] text-12 font-bold text-ink disabled:cursor-default disabled:opacity-60',
  btn30: 'h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-solid border-ink bg-surface px-[11px] text-12 font-bold text-ink disabled:cursor-default disabled:opacity-60',
  btnDanger30: 'h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-solid border-coral bg-peach px-[11px] text-12 font-bold text-rust-ink disabled:cursor-default disabled:opacity-60',
  // the live rows' «Log out» and the history's «Log out of all devices»
  logout: 'h-[26px] cursor-pointer rounded-8 border border-solid border-coral bg-transparent text-11.5 font-semibold text-rust disabled:cursor-default disabled:opacity-60',
  input: 'h-[38px] rounded-10 border border-solid border-line bg-canvas px-[11px] text-13 text-ink',
  inputSm: 'h-[30px] rounded-9 border border-solid border-line bg-canvas px-2 text-12.5 text-ink disabled:opacity-60',
  select: 'h-[30px] rounded-8 border border-solid border-line bg-canvas px-1 text-12 text-ink disabled:opacity-60',
  label: 'flex flex-col gap-1 text-11.5 font-semibold text-muted',
  muted: 'text-11.5 text-muted',
  band: 'rounded-12 bg-cream px-3 py-[9px] text-12 leading-[1.5] text-amber-ink',
  bandDanger: 'rounded-12 bg-peach px-3 py-[9px] text-12 leading-[1.5] text-rust-ink',
}

/** The design's alert switch: a 40 × 22 track, 16 px knob at 3 or 21 (Alerts and rules). */
export function Toggle({ on, onChange, label, disabled }: { on: boolean; onChange: (on: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!on)}
      className={`relative h-[22px] w-10 flex-none cursor-pointer rounded-999 border-none disabled:cursor-default disabled:opacity-60 ${on ? 'bg-ink' : 'bg-line-strong'}`}
    >
      <span className="absolute top-[3px] h-4 w-4 rounded-999 bg-surface" style={{ left: on ? 21 : 3 }} />
    </button>
  )
}

/** A dialog in the shell's modal language: dimmed backdrop, card, eyebrow and serif title; × and Escape close. */
export function Modal({ eyebrow, title, onClose, children, width = 440 }: { eyebrow: string; title: string; onClose: () => void; children: React.ReactNode; width?: number }) {
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
          <button type="button" onClick={onClose} aria-label={t('close')} className="h-[30px] w-[30px] flex-none cursor-pointer rounded-999 border border-solid border-ink bg-transparent">×</button>
        </div>
        {children}
      </div>
    </div>
  )
}

export const dialogBtn = 'h-10 cursor-pointer rounded-11 border border-solid border-ink bg-primary px-[18px] text-13 font-bold disabled:cursor-default disabled:opacity-60'
export const dialogCancel = 'h-10 cursor-pointer rounded-11 border border-solid border-line bg-transparent px-4 text-13 font-semibold'
export const dialogDanger = 'h-10 cursor-pointer rounded-11 border border-solid border-coral bg-peach px-4 text-13 font-bold text-rust-ink disabled:cursor-default disabled:opacity-60'
export const dialogInput = 'h-10 rounded-10 border border-solid border-line bg-canvas px-3 text-13 font-medium text-ink'

/** The message for a refusal: the screen's own wording for a known detail, else common.errors.<code>. */
export function useErrorText() {
  const t = useTranslations('security.errors')
  const c = useTranslations('common.errors')
  return useCallback((r: { code: string; detail: string | null }) => {
    const d = errorDetailKey(r.detail)
    return d ? t(d) : c(r.code as 'failed')
  }, [t, c])
}

type Pending = { kind: 'mfa' | 'reason'; retry: (reason: string | null) => void; cancel: () => void }

/**
 * Runs a write and handles the two refusals that ask the person for something more: a fresh second factor
 * (forbidden / fresh_mfa: the authenticator code again, then the same write once more) and a typed reason
 * (reason_required, when the typed_reason setting is on). Every other refusal is said in the toast.
 */
export function useGuarded() {
  const flash = useToast()
  const err = useErrorText()
  const router = useRouter()
  const [pending, setPending] = useState<Pending | null>(null)
  const [busy, setBusy] = useState(false)

  const run = useCallback(
    async <T extends object>(fn: (reason: string | null) => Promise<Result<T>>, opts: { reason?: string | null; onError?: (r: { code: string; detail: string | null }) => boolean } = {}): Promise<Result<T>> => {
      setBusy(true)
      let r: Result<T>
      try {
        r = await fn(opts.reason ?? null)
      } finally {
        setBusy(false)
      }
      if (r.ok) { router.refresh(); return r }
      if (r.code === 'forbidden' && r.detail === 'fresh_mfa') {
        return new Promise((resolve) => setPending({ kind: 'mfa', retry: () => { setPending(null); void run(fn, opts).then(resolve) }, cancel: () => { setPending(null); resolve(r) } }))
      }
      if (r.code === 'reason_required') {
        return new Promise((resolve) => setPending({ kind: 'reason', retry: (reason) => { setPending(null); void run(fn, { ...opts, reason }).then(resolve) }, cancel: () => { setPending(null); resolve(r) } }))
      }
      if (!opts.onError?.(r)) flash(err(r))
      return r
    },
    [flash, err, router],
  )

  const dialog = pending ? <GuardDialog pending={pending} /> : null
  return { run, busy, dialog }
}

function GuardDialog({ pending }: { pending: Pending }) {
  const t = useTranslations('security.guard')
  const err = useErrorText()
  const [value, setValue] = useState('')
  const [problem, setProblem] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (pending.kind === 'reason') {
      if (!value.trim()) return setProblem(t('reasonEmpty'))
      return pending.retry(value.trim())
    }
    setBusy(true)
    const r = await confirmFactor({ code: value })
    setBusy(false)
    if (!r.ok) return setProblem(r.detail === 'code' ? t('codeWrong') : err(r))
    pending.retry(null)
  }
  return (
    <Modal eyebrow={t(pending.kind === 'mfa' ? 'mfaEyebrow' : 'reasonEyebrow')} title={t(pending.kind === 'mfa' ? 'mfaTitle' : 'reasonTitle')} onClose={pending.cancel}>
      <form onSubmit={submit} className="flex flex-col gap-3">
        <p className="m-0 text-13 leading-[1.5] text-muted">{t(pending.kind === 'mfa' ? 'mfaBody' : 'reasonBody')}</p>
        {pending.kind === 'mfa' ? (
          <input
            className={dialogInput}
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="\d{6}"
            maxLength={6}
            aria-label={t('codeLabel')}
            placeholder="000000"
            value={value}
            onChange={(e) => { setValue(e.target.value.replace(/\D/g, '')); setProblem(null) }}
          />
        ) : (
          <textarea
            className="min-h-[80px] rounded-10 border border-solid border-line bg-canvas p-3 text-13 text-ink"
            aria-label={t('reasonLabel')}
            maxLength={500}
            value={value}
            onChange={(e) => { setValue(e.target.value); setProblem(null) }}
          />
        )}
        {problem ? <div role="alert" className="text-12 font-semibold text-danger">{problem}</div> : null}
        <div className="flex justify-end gap-2">
          <button type="button" className={dialogCancel} onClick={pending.cancel}>{t('cancel')}</button>
          <button type="submit" className={dialogBtn} disabled={busy || (pending.kind === 'mfa' && value.length !== 6)}>{t(pending.kind === 'mfa' ? 'confirm' : 'continue')}</button>
        </div>
      </form>
    </Modal>
  )
}

/**
 * «Today 09:21», «Yesterday 16:02», «2 Oct 08:11» in the staff member's time zone. `now` comes from the server so the
 * server and the browser render the same words.
 */
export function useWhen(now: string) {
  const f = useFormatter()
  const t = useTranslations('security.when')
  return useCallback((at: string, opts: { time?: boolean } = {}) => {
    const d = new Date(at)
    const n = new Date(now)
    const day = (x: Date) => f.dateTime(x, { year: 'numeric', month: '2-digit', day: '2-digit' })
    const time = f.dateTime(d, { hour: '2-digit', minute: '2-digit' })
    const withTime = opts.time !== false
    if (day(d) === day(n)) return withTime ? t('today', { time }) : t('todayShort')
    if (day(d) === day(new Date(n.getTime() - 86_400_000))) return withTime ? t('yesterday', { time }) : t('yesterdayShort')
    const date = f.dateTime(d, d.getFullYear() === n.getFullYear() ? { day: 'numeric', month: 'short' } : { day: 'numeric', month: 'short', year: 'numeric' })
    return withTime ? t('date', { date, time }) : date
  }, [f, t, now])
}

/** Is this moment on the same calendar day as `now`, in the staff member's time zone? */
export function useIsToday(now: string) {
  const f = useFormatter()
  return useCallback((at: string) => {
    const day = (x: Date) => f.dateTime(x, { year: 'numeric', month: '2-digit', day: '2-digit' })
    return day(new Date(at)) === day(new Date(now))
  }, [f, now])
}

/** «HH:MM» in the staff member's time zone. */
export function useClock() {
  const f = useFormatter()
  return useCallback((at: string) => f.dateTime(new Date(at), { hour: '2-digit', minute: '2-digit' }), [f])
}

/** «City, CC» or what is known of it. */
export const place = (city: string | null, country: string | null) => [city, country].filter(Boolean).join(', ')
