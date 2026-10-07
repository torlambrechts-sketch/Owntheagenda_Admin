import type { Metadata } from 'next'
import { getTranslations } from 'next-intl/server'
import { AuthCard } from '@/components/auth/AuthCard'
import { WelcomeForm } from './WelcomeForm'

export const metadata: Metadata = { robots: { index: false, follow: false }, referrer: 'no-referrer' }

/**
 * An invitation's link (0060): the new staff member chooses a password, then the second factor (/mfa). The one-time token
 * is checked only when the form is sent, so a mail scanner opening the link does not spend it.
 */
export default async function WelcomePage({ searchParams }: { searchParams: Promise<{ token_hash?: string; type?: string }> }) {
  const t = await getTranslations('welcome')
  const { token_hash, type } = await searchParams
  const ok = typeof token_hash === 'string' && /^[A-Za-z0-9_-]{20,200}$/.test(token_hash) && (type === 'invite' || type === 'recovery')
  return (
    <AuthCard title={t('title')}>
      {ok ? (
        <>
          <p className="m-0 text-13 leading-[1.55] text-muted">{t('lead')}</p>
          <WelcomeForm tokenHash={token_hash} type={type as 'invite' | 'recovery'} />
        </>
      ) : (
        <p className="m-0 text-13 text-muted">{t('badLink')}</p>
      )}
    </AuthCard>
  )
}
