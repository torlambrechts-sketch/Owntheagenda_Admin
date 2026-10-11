'use client'

import { useActionState, useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { authAlert, authButton, authField, authLabel } from '@/components/auth/styles'
import { enroll, verify, type Enrolment, type VerifyState } from './actions'

function CodeForm({ factorId }: { factorId: string }) {
  const t = useTranslations('mfa')
  const [state, action, pending] = useActionState<VerifyState, FormData>(verify, { problem: null })
  return (
    <form action={action} className="flex flex-col gap-[14px]">
      <input type="hidden" name="factorId" value={factorId} />
      <label className={authLabel}>
        {t('code')}
        <input name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" maxLength={6} required className={`${authField} tracking-[.3em]`} />
      </label>
      {/* the session on this device is kept past the idle rule for 30 days (0071); the code is still asked at every sign-in */}
      <label className="flex cursor-pointer items-start gap-[9px] text-12.5">
        <input type="checkbox" name="remember" className="mt-[2px] h-4 w-4 flex-none accent-ink" />
        <span className="flex flex-col">
          <b>{t('remember')}</b>
          <span className="text-muted">{t('rememberHint')}</span>
        </span>
      </label>
      {state.problem ? (
        <p role="alert" className={authAlert}>
          {t(state.problem)}
        </p>
      ) : null}
      <button type="submit" disabled={pending} className={authButton}>
        {t('submit')}
      </button>
    </form>
  )
}

/** The verified factor's code, or a new authenticator's QR code and then its first code. */
export function MfaForms({ factorId }: { factorId: string | null }) {
  const t = useTranslations('mfa')
  const [enrolment, setEnrolment] = useState<Enrolment | null>(null)
  const [pending, start] = useTransition()

  if (factorId) {
    return (
      <>
        <p className="m-0 text-13 leading-[1.55] text-muted">{t('verifyLead')}</p>
        <CodeForm factorId={factorId} />
      </>
    )
  }
  if (enrolment?.ok) {
    return (
      <>
        <p className="m-0 text-13 leading-[1.55] text-muted">{t('enrollLead')}</p>
        {/* eslint-disable-next-line @next/next/no-img-element -- an SVG data URI from Supabase Auth */}
        <img src={enrolment.qr} alt={t('qrAlt')} width={192} height={192} className="block h-48 w-48 rounded-12 border border-line bg-surface" />
        <p className="m-0 break-all text-12 text-muted">{t('secret', { secret: enrolment.secret })}</p>
        <CodeForm factorId={enrolment.factorId} />
      </>
    )
  }
  return (
    <>
      {enrolment && !enrolment.ok ? (
        <p role="alert" className={authAlert}>
          {t('enrollFailed')}
        </p>
      ) : null}
      <button type="button" disabled={pending} className={authButton} onClick={() => start(async () => setEnrolment(await enroll()))}>
        {t('start')}
      </button>
    </>
  )
}
