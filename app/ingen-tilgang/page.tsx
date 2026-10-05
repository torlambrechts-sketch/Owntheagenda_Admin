import { getTranslations } from 'next-intl/server'
import { signOut } from '@/app/login/actions'

export default async function DeniedPage() {
  const t = await getTranslations()
  return (
    <main className="mx-auto mt-24 w-full max-w-sm px-4">
      <h1 className="mb-4 text-2xl font-semibold">{t('denied.title')}</h1>
      <p className="mb-6 text-neutral-700">{t('denied.body')}</p>
      <form action={signOut}>
        <button type="submit" className="underline focus:outline-none focus-visible:ring-2 focus-visible:ring-neutral-900">
          {t('app.signOut')}
        </button>
      </form>
    </main>
  )
}
