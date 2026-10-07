import { headers } from 'next/headers'
import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { routeOf, routeVisible, MODULE_OF } from '@/lib/nav'
import { redirect } from 'next/navigation'
import { whoami } from '@/lib/platform/read'
import { getShell } from '@/lib/shell'
import { currentProduct } from '@/lib/product'
import { rpc } from '@/lib/rpc'
import type { AppStatus } from '@/components/shell/Header'
import { HEALTH } from '@/lib/data/platform-shared'
import { Shell } from '@/components/shell/Shell'

const AppsHealth = z.array(z.object({
  key: z.string(),
  health: z.object({ status: z.enum(HEALTH) }),
}))

/** Every screen of the platform sits in the shell, behind an admin account with a second factor. */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const me = await whoami()
  if (!me?.account) redirect('/ingen-tilgang')
  if (!me.admin) redirect('/mfa')
  const shell = await getShell()
  const product = await currentProduct(shell)
  // the header's «API operational»: the application's health as the platform reads it (global:see; hidden otherwise)
  const apps = await rpc('applications_get', {}, AppsHealth, { quiet: true })
  const status: AppStatus = apps.ok ? apps.data.find((a) => a.key === product)?.health.status ?? null : null
  // a route the person may not open shows why instead of its page, so the page's reads are never called (lib/nav.ts)
  const route = routeOf((await headers()).get('x-sentral-path') ?? '/')
  const open = routeVisible(route, { admin: shell.me.permission_kind === 'admin', rights: shell.me.rights, modules: shell.modules, meetingsWorkspace: shell.meetings_workspace })
  const t = await getTranslations('shell.noAccess')
  const moduleOff = !!MODULE_OF[route] && shell.modules[MODULE_OF[route]!] === false
  return (
    <Shell shell={shell} product={product} status={status}>
      {open ? children : (
        <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] md:px-7">
          <div className="rounded-20 border border-line bg-surface p-[26px]">
            <h1 className="m-0 font-serif text-22 font-semibold">{t('title')}</h1>
            <p className="m-0 mt-2 text-13 text-muted">{t(moduleOff ? 'moduleOff' : 'body')}</p>
          </div>
        </div>
      )}
    </Shell>
  )
}
