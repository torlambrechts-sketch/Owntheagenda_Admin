import { getTranslations } from 'next-intl/server'
import { AuthCard } from '@/components/auth/AuthCard'
import { LoginForm } from './LoginForm'

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ idle?: string; ended?: string }> }) {
  const t = await getTranslations('login')
  const { idle, ended } = await searchParams
  return (
    <AuthCard title={t('title')}>
      {idle || ended ? <p role="status" className="m-0 text-12.5 text-muted">{t(idle || ended === 'idle_timeout' ? 'idle' : 'ended')}</p> : null}
      <LoginForm />
    </AuthCard>
  )
}
