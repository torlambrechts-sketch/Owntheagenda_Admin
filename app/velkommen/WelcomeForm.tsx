'use client'

import { useActionState } from 'react'
import { useTranslations } from 'next-intl'
import { authAlert, authButton, authField, authLabel } from '@/components/auth/styles'
import { acceptInvitation, type WelcomeState } from './actions'

export function WelcomeForm({ tokenHash, type }: { tokenHash: string; type: 'invite' | 'recovery' }) {
  const t = useTranslations('welcome')
  const [state, action, pending] = useActionState<WelcomeState, FormData>(acceptInvitation, { problem: null })
  return (
    <form action={action} className="flex flex-col gap-[14px]">
      <input type="hidden" name="token_hash" value={tokenHash} />
      <input type="hidden" name="type" value={type} />
      <label className={authLabel}>
        {t('password')}
        <input name="password" type="password" autoComplete="new-password" minLength={12} required className={authField} />
      </label>
      <label className={authLabel}>
        {t('repeat')}
        <input name="repeat" type="password" autoComplete="new-password" minLength={12} required className={authField} />
      </label>
      <p className="m-0 text-12 text-muted">{t('rule')}</p>
      {state.problem ? <p role="alert" className={authAlert}>{t(`problems.${state.problem}`)}</p> : null}
      <button type="submit" disabled={pending} className={authButton}>{t('submit')}</button>
    </form>
  )
}
