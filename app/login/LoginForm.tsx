'use client'

import { useActionState } from 'react'
import { useTranslations } from 'next-intl'
import { authAlert, authButton, authField, authLabel } from '@/components/auth/styles'
import { signIn, type LoginState } from './actions'

export function LoginForm() {
  const t = useTranslations('login')
  const [state, action, pending] = useActionState<LoginState, FormData>(signIn, { problem: null })
  return (
    <form action={action} className="flex flex-col gap-[14px]">
      <label className={authLabel}>
        {t('email')}
        <input name="email" type="email" autoComplete="username" required className={authField} />
      </label>
      <label className={authLabel}>
        {t('password')}
        <input name="password" type="password" autoComplete="current-password" required className={authField} />
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
