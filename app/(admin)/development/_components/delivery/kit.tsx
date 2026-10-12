'use client'

import { useCallback, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { reverify } from '@/app/(admin)/applications/actions'
import { d } from './styles'

export type Fail = { ok: false; code: string; detail?: string | null }

/** the words for a refusal: this area's own for a known detail, else the platform's for the code */
export function useErrorText() {
  const t = useTranslations('devDelivery.errors')
  const tc = useTranslations('common.errors')
  return useCallback((f: Fail) => {
    const k = f.detail ?? ''
    if (k && /^[a-z_]{1,40}$/.test(k) && t.has(k)) return t(k)
    return tc.has(f.code) ? tc(f.code) : tc('failed')
  }, [t, tc])
}

/**
 * Runs a write. A stale second factor asks for the authenticator code, then runs it again; any other refusal goes to the
 * toast. The outcome's own words go to the toast only after the database said yes; then the view is read again.
 */
export function useRun() {
  const flash = useToast()
  const router = useRouter()
  const err = useErrorText()
  const [pending, start] = useTransition()
  const [retry, setRetry] = useState<null | (() => void)>(null)
  const run = useCallback(<T extends { ok: boolean }>(fn: () => Promise<T>, okMessage: (r: Extract<T, { ok: true }>) => string | null,
    after?: (r: Extract<T, { ok: true }>) => void) => {
    const go = () => start(async () => {
      const r = await fn()
      if (!r.ok) {
        const f = r as unknown as Fail
        if (f.code === 'forbidden' && f.detail === 'fresh_mfa') { setRetry(() => go); return }
        flash(err(f))
        return
      }
      setRetry(null)
      const done = r as Extract<T, { ok: true }>
      const m = okMessage(done)
      if (m) flash(m)
      after?.(done)
      router.refresh()
    })
    go()
  }, [flash, router, err])
  const mfa = retry ? <FreshMfa onVerified={() => { const g = retry; setRetry(null); g() }} onCancel={() => setRetry(null)} /> : null
  return { run, pending, mfa }
}

/** The fresh second factor (0043 require_fresh_mfa): the authenticator code again, then the same write once more. */
export function FreshMfa({ onVerified, onCancel }: { onVerified: () => void; onCancel: () => void }) {
  const t = useTranslations('devDelivery.mfa')
  const tc = useTranslations('common')
  const [code, setCode] = useState('')
  const [badCode, setBad] = useState(false)
  const [pending, start] = useTransition()
  const submit = () => start(async () => {
    const r = await reverify({ code })
    if (r.ok) onVerified()
    else setBad(true)
  })
  return (
    <div role="group" aria-label={t('title')} className="flex flex-col gap-2 rounded-12 bg-amber-bg px-3 py-[10px] text-12.5 text-amber-ink">
      <b>{t('title')}</b>
      <span>{t('body')}</span>
      <div className="flex flex-wrap gap-2">
        <input
          value={code}
          onChange={(e) => { setCode(e.target.value.replace(/\D/g, '').slice(0, 6)); setBad(false) }}
          onKeyDown={(e) => { if (e.key === 'Enter' && code.length === 6) submit() }}
          inputMode="numeric" autoComplete="one-time-code" aria-label={t('code')} placeholder={t('code')}
          className={`${d.input} w-[140px] ${d.mono}`}
        />
        <button type="button" disabled={code.length !== 6 || pending} onClick={submit} className={d.smallPrimary}>{t('verify')}</button>
        <button type="button" onClick={onCancel} className={d.small}>{tc('cancel')}</button>
      </div>
      {badCode ? <span className="font-semibold text-danger">{t('failed')}</span> : null}
    </div>
  )
}

/** a value to copy (a URL, a request's shape, a file): selected on focus, «Copy» beside it */
export function CopyButton({ text, label }: { text: string; label?: string }) {
  const t = useTranslations('devDelivery')
  const [copied, setCopied] = useState(false)
  return (
    <button
      type="button"
      className={d.small}
      onClick={() => { void navigator.clipboard?.writeText(text).then(() => setCopied(true), () => setCopied(false)) }}
    >
      {copied ? t('copied') : label ?? t('copy')}
    </button>
  )
}
