import { redirect } from 'next/navigation'
import { getTranslations } from 'next-intl/server'
import { createClient } from '@/lib/supabase/server'
import { MfaForms } from './MfaForms'

export default async function MfaPage() {
  const t = await getTranslations('mfa')
  const supabase = await createClient()
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
  if (aal?.currentLevel === 'aal2') redirect('/')
  const { data } = await supabase.auth.mfa.listFactors()
  const verified = (data?.totp ?? []).find((f) => f.status === 'verified')
  return (
    <main className="mx-auto mt-24 w-full max-w-sm px-4">
      <h1 className="mb-6 text-2xl font-semibold">{t('title')}</h1>
      <MfaForms factorId={verified?.id ?? null} />
    </main>
  )
}
