import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { whoami } from '@/lib/platform/read'
import { getShell } from '@/lib/shell'
import { Shell } from '@/components/shell/Shell'

/** Every screen of the platform sits in the shell, behind an admin account with a second factor. */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const me = await whoami()
  if (!me?.account) redirect('/ingen-tilgang')
  if (!me.admin) redirect('/mfa')
  const shell = await getShell()
  const product = (await cookies()).get('product')?.value ?? 'all'
  const known = product === 'all' || shell.products.some((p) => p.key === product)
  return (
    <Shell shell={shell} product={known ? product : 'all'}>
      {children}
    </Shell>
  )
}
