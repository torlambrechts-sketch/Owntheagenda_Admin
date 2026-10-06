import { redirect } from 'next/navigation'
import { getTranslations } from 'next-intl/server'
import { createClient } from '@/lib/supabase/server'
import { whoami } from '@/lib/platform/read'
import { AuthCard } from '@/components/auth/AuthCard'
import { MfaForms } from './MfaForms'

export default async function MfaPage() {
  const t = await getTranslations('mfa')
  // an account that is not on the staff list may not set up a factor here either (F-5)
  const me = await whoami()
  if (!me?.account) redirect('/ingen-tilgang')
  const supabase = await createClient()
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
  if (aal?.currentLevel === 'aal2') redirect('/')
  const { data } = await supabase.auth.mfa.listFactors()
  const verified = (data?.totp ?? []).find((f) => f.status === 'verified')
  return (
    <AuthCard title={t('title')}>
      <MfaForms factorId={verified?.id ?? null} />
    </AuthCard>
  )
}
