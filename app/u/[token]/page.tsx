import type { Metadata } from 'next'
import { getTranslations } from 'next-intl/server'
import { AuthCard } from '@/components/auth/AuthCard'
import { authButton } from '@/components/auth/styles'
import { peekUnsubscribe } from '@/lib/mail/public'
import { unsubscribe } from './actions'

export const metadata: Metadata = { robots: { index: false, follow: false }, referrer: 'no-referrer' }

/**
 * The unsubscribe link in every campaign email (0060, D-27): who sent it, and one button. Opening the page changes nothing
 * (mail scanners open links); only the button unsubscribes. Public, no session, no index.
 */
export default async function UnsubscribePage({ params, searchParams }: { params: Promise<{ token: string }>; searchParams: Promise<{ done?: string }> }) {
  const t = await getTranslations('unsubscribe')
  const { token } = await params
  const { done } = await searchParams
  const peek = await peekUnsubscribe(token)
  if (!peek) return <AuthCard title={t('title')}><p className="m-0 text-13 text-muted">{t('unavailable')}</p></AuthCard>
  if (!peek.found) return <AuthCard title={t('title')}><p className="m-0 text-13 text-muted">{t('notFound')}</p></AuthCard>
  if (peek.done || done === '1') {
    return <AuthCard title={t('doneTitle')}><p className="m-0 text-13 leading-[1.55]">{t('done', { from: peek.from_name ?? '' })}</p></AuthCard>
  }
  return (
    <AuthCard title={t('title')}>
      <p className="m-0 text-13 leading-[1.55]">{t('lead', { from: peek.from_name ?? '' })}</p>
      <form action={unsubscribe}>
        <input type="hidden" name="token" value={token} />
        <button type="submit" className={authButton}>{t('button')}</button>
      </form>
    </AuthCard>
  )
}
