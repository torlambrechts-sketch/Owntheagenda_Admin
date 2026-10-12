import Link from 'next/link'
import type { Route } from 'next'
import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { currentProduct } from '@/lib/product'
import { SIMPLE_PLATFORM_TABS, loadAppsTab, loadPlansTab, loadTeamTab, type SimplePlatformTab } from '@/lib/data/simple-platform'
import { loadAccess, loadBilling, loadOps, loadSuccess } from '@/lib/data/platform-plus'
import { NowProvider } from '../applications/_components/kit'
import { AppsTab } from './_components/AppsTab'
import { loadEmailProvider } from '@/lib/mail/provider'
import { PlansTab } from './_components/PlansTab'
import { TeamTab } from './_components/TeamTab'
import { AccessTab } from './_components/plus/AccessTab'
import { BillingTab } from './_components/plus/BillingTab'
import { OpsTab } from './_components/plus/OpsTab'
import { SuccessTab } from './_components/plus/SuccessTab'

const HREF: Record<SimplePlatformTab, string> = {
  apps: '/platform',
  ops: '/platform?tab=ops',
  plans: '/platform?tab=plans',
  billing: '/platform?tab=billing',
  success: '/platform?tab=success',
  team: '/platform?tab=team',
  access: '/platform?tab=access',
}
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Platform (SimplePlatform.dc.html, PlatformPlus.dc.html): Applications (default), Rollouts and announcements (?tab=ops), Plans
 * and prices (?tab=plans), Billing portal (?tab=billing), Customer success (?tab=success), Team (?tab=team) and Roles and
 * approvals (?tab=access). The design's pill buttons become links, so a tab has an address (control substitution, V-SPL-01).
 * Everything is scoped to the application chosen in the rail. Every tab but Team reads with Global › See (D-PL-16); the team
 * list is every staff member's. What a person may change is decided again by the database.
 */
export default async function PlatformPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const tab = z.enum(SIMPLE_PLATFORM_TABS).catch('apps').parse(one(sp.tab) ?? 'apps')
  const shell = await getShell()
  const product = await currentProduct(shell)
  const t = await getTranslations('simplePlatform')
  const app = shell.products.find((p) => p.key === product)
  const name = app?.name ?? product
  const nf = shell.me.number_format
  const seeGlobal = can(shell, 'global', 'see')

  let body: React.ReactNode
  if (tab === 'team') {
    const { team, roles } = await loadTeamTab()
    body = <TeamTab team={team} roles={roles} me={shell.me.id} canSecurity={can(shell, 'global', 'security')} />
  } else if (!seeGlobal) {
    body = (
      <div className="rounded-20 border border-line bg-surface p-[26px]">
        <b className="font-serif text-20 font-semibold">{t('noAccess.title')}</b>
        <p className="m-0 mt-2 text-13 text-muted">{t('noAccess.body')}</p>
      </div>
    )
  } else if (tab === 'plans') {
    body = <PlansTab plans={await loadPlansTab(product)} name={name} nf={nf} />
  } else if (tab === 'access') {
    const { matrix, approvals, accounts } = await loadAccess()
    body = <AccessTab matrix={matrix} approvals={approvals} accounts={accounts} productName={name} />
  } else if (tab === 'success') {
    const s = await loadSuccess(product)
    body = (
      <SuccessTab
        product={product}
        name={name}
        onboarding={s.onboarding}
        requests={s.requests}
        signals={s.signals}
        accounts={s.accounts}
        canAddRequest={can(shell, 'global', 'add') || can(shell, 'dev', 'add')}
        canDeal={can(shell, 'deals', 'add')}
        nf={nf}
      />
    )
  } else if (tab === 'ops') {
    const o = await loadOps(product)
    body = <OpsTab product={product} name={name} reach={o.reach} limits={o.limits} errors={o.errors} canTicket={can(shell, 'tickets', 'add')} nf={nf} />
  } else if (tab === 'billing') {
    body = <BillingTab billing={await loadBilling(product)} product={name} nf={nf} />
  } else {
    const [{ apps, notice, flags }, email] = await Promise.all([loadAppsTab(product), loadEmailProvider()])
    body = (
      <AppsTab
        apps={apps}
        current={product}
        name={name}
        notice={notice}
        flags={flags}
        canConfigure={can(shell, 'global', 'configure')}
        owner={shell.me.owner}
        nf={nf}
        email={email.ok ? email.data : null}
      />
    )
  }

  return (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
      <nav aria-label={t('tabs.label')} className="flex flex-wrap gap-[6px]">
        {SIMPLE_PLATFORM_TABS.map((k) => {
          const on = k === tab
          return (
            <Link
              key={k}
              href={HREF[k] as Route}
              aria-current={on ? 'page' : undefined}
              className={`flex-none cursor-pointer whitespace-nowrap rounded-999 border px-4 py-2 text-13 hover:no-underline ${
                on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'
              }`}
            >
              {t(`tabs.${k}`)}
            </Link>
          )
        })}
      </nav>
      <NowProvider now={new Date().toISOString()}>{body}</NowProvider>
    </div>
  )
}
