'use client'

import { useActionState, useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { enroll, verify, type Enrolment, type VerifyState } from './actions'

const button =
  'rounded-md bg-neutral-900 px-4 py-2 font-semibold text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-neutral-900 disabled:opacity-60'

function CodeForm({ factorId }: { factorId: string }) {
  const t = useTranslations('mfa')
  const [state, action, pending] = useActionState<VerifyState, FormData>(verify, { problem: null })
  return (
    <form action={action} className="flex flex-col gap-4">
      <input type="hidden" name="factorId" value={factorId} />
      <label className="text-sm font-medium">
        {t('code')}
        <input
          name="code"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="\d{6}"
          maxLength={6}
          required
          className="mt-1 block w-full rounded-md border border-neutral-300 px-3 py-2 tracking-widest focus:outline-none focus-visible:ring-2 focus-visible:ring-neutral-900"
        />
      </label>
      {state.problem ? (
        <p role="alert" className="text-sm text-red-700">
          {t('failed')}
        </p>
      ) : null}
      <button type="submit" disabled={pending} className={button}>
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
        <p className="mb-4 text-neutral-700">{t('verifyLead')}</p>
        <CodeForm factorId={factorId} />
      </>
    )
  }
  if (enrolment?.ok) {
    return (
      <>
        <p className="mb-4 text-neutral-700">{t('enrollLead')}</p>
        {/* eslint-disable-next-line @next/next/no-img-element -- an SVG data URI from Supabase Auth */}
        <img src={enrolment.qr} alt="" width={192} height={192} className="mb-3 h-48 w-48" />
        <p className="mb-6 break-all text-sm text-neutral-600">{t('secret', { secret: enrolment.secret })}</p>
        <CodeForm factorId={enrolment.factorId} />
      </>
    )
  }
  return (
    <button type="button" disabled={pending} className={button} onClick={() => start(async () => setEnrolment(await enroll()))}>
      {t('start')}
    </button>
  )
}
