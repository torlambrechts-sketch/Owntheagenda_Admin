import { getTranslations } from 'next-intl/server'
import { signOut } from '@/app/login/actions'
import { AuthCard } from '@/components/auth/AuthCard'
import { authButton } from '@/components/auth/styles'

export default async function DeniedPage() {
  const t = await getTranslations()
  return (
    <AuthCard title={t('denied.title')}>
      <p className="m-0 text-13 leading-[1.55] text-muted">{t('denied.body')}</p>
      <form action={signOut}>
        <button type="submit" className={authButton}>
          {t('app.signOut')}
        </button>
      </form>
    </AuthCard>
  )
}
