'use client'

import { useActionState } from 'react'
import { useTranslations } from 'next-intl'
import { signIn, type LoginState } from './actions'

export function LoginForm() {
  const t = useTranslations('login')
  const [state, action, pending] = useActionState<LoginState, FormData>(signIn, { problem: null })
  const field = 'mt-1 block w-full rounded-md border border-neutral-300 px-3 py-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-neutral-900'
  return (
    <form action={action} className="flex flex-col gap-4">
      <label className="text-sm font-medium">
        {t('email')}
        <input name="email" type="email" autoComplete="username" required className={field} />
      </label>
      <label className="text-sm font-medium">
        {t('password')}
        <input name="password" type="password" autoComplete="current-password" required className={field} />
      </label>
      {state.problem ? (
        <p role="alert" className="text-sm text-red-700">
          {t(state.problem)}
        </p>
      ) : null}
      <button type="submit" disabled={pending} className="rounded-md bg-neutral-900 px-4 py-2 font-semibold text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-neutral-900 disabled:opacity-60">
        {t('submit')}
      </button>
    </form>
  )
}
