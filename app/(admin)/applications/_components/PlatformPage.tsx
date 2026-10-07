import Link from 'next/link'
import type { Route } from 'next'
import { cookies } from 'next/headers'
import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import {
  loadApiOverview, loadApplication, loadApplications, loadCatalog, loadContent, loadDeliveries, loadFlags, loadJobs, loadMcp, loadNotice, loadOauthApps, loadWebhooks,
} from '@/lib/data/platform'
import { PLATFORM_TABS, TAB_HREF, type PlatformTab } from '@/lib/data/platform-shared'
import { AppsView } from './AppsView'
import { ApiView } from './ApiView'
import { HooksView } from './HooksView'
import { CatalogView } from './CatalogView'
import { McpView } from './McpView'
import { JobsView } from './JobsView'
import { FlagsView } from './FlagsView'
import { ContentView } from './ContentView'
import { NowProvider } from './kit'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null
const Params = z.object({
  tab: z.enum(PLATFORM_TABS).nullable().catch(null),
  app: z.string().regex(/^[a-z][a-z0-9_]{1,30}$/).nullable().catch(null),
  webhook: z.string().uuid().nullable().catch(null),
})

/** The tabs that need «See records» on Global: the applications, their jobs, flags and content (0044 global:see). */
const GLOBAL_TABS: PlatformTab[] = ['apps', 'jobs', 'flags', 'content']

/**
 * Platform (Platform.dc.html): one component behind two routes, as in the design's shell (tab «apps» at /applications,
 * «api» at /api). The tab, the chosen application and the chosen webhook live in the address; each tab loads only what
 * it shows. The design never reads the shell's product: here the shell's product is preselected, else the first
 * installed application (spec §1).
 */
export async function PlatformPage({ route, searchParams }: { route: 'applications' | 'api'; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({ tab: one(sp.tab), app: one(sp.app), webhook: one(sp.webhook) })
  const shell = await getShell()
  const t = await getTranslations('platform')
  const seeGlobal = can(shell, 'global', 'see')
  const configure = can(shell, 'global', 'configure')
  const security = can(shell, 'global', 'security')
  const tabs = PLATFORM_TABS.filter((x) => seeGlobal || !GLOBAL_TABS.includes(x))
  // a notification's link to a webhook (/api?webhook=<id>) opens the Webhooks tab
  const wanted: PlatformTab = p.tab ?? (p.webhook ? 'hooks' : route === 'applications' ? 'apps' : 'api')
  const tab: PlatformTab | null = tabs.includes(wanted) ? wanted : (tabs[0] ?? null)

  let body: React.ReactNode = null
  if (!tab) {
    body = (
      <div className="rounded-20 border border-line bg-surface p-[26px]">
        <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
        <p className="m-0 mt-2 text-13 text-muted">{t('noAccess.body')}</p>
      </div>
    )
  } else if (tab === 'apps' || tab === 'flags' || tab === 'content') {
    const apps = await loadApplications()
    const cookieProduct = (await cookies()).get('product')?.value ?? null
    const installed = apps.filter((a) => a.installed)
    const pick = (k: string | null) => (k ? installed.find((a) => a.key === k)?.key ?? null : null)
    const appKey = pick(p.app) ?? pick(cookieProduct) ?? installed[0]?.key ?? null
    if (tab === 'apps') {
      const detail = appKey ? await loadApplication(appKey) : null
      body = <AppsView apps={apps} current={appKey} detail={detail && detail.ok ? detail.data : null} owner={shell.me.owner} nf={shell.me.number_format} />
    } else if (tab === 'flags') {
      const [flags, notice] = await Promise.all([loadFlags(), appKey ? loadNotice(appKey) : null])
      body = (
        <FlagsView
          flags={flags}
          apps={installed.map((a) => ({ key: a.key, name: a.name }))}
          current={appKey}
          notice={notice && notice.ok ? notice.data : null}
          canConfigure={configure}
          owner={shell.me.owner}
        />
      )
    } else {
      const content = appKey ? await loadContent(appKey) : null
      body = <ContentView apps={installed.map((a) => ({ key: a.key, name: a.name }))} current={appKey} content={content && content.ok ? content.data : null} />
    }
  } else if (tab === 'jobs') {
    const [jobs, apps] = await Promise.all([loadJobs(), loadApplications()])
    body = <JobsView jobs={jobs} products={Object.fromEntries(apps.map((a) => [a.key, a.name]))} canConfigure={configure} nf={shell.me.number_format} />
  } else if (tab === 'api') {
    const [api, oauth] = await Promise.all([loadApiOverview(), loadOauthApps()])
    body = <ApiView api={api} oauth={oauth} canConfigure={configure} canSecurity={security} nf={shell.me.number_format} />
  } else if (tab === 'hooks') {
    const hooks = await loadWebhooks()
    const selected = p.webhook && hooks.webhooks.some((w) => w.id === p.webhook) ? p.webhook : null
    const rows = selected ? await loadDeliveries(selected) : null
    body = <HooksView key={selected ?? 'all'} hooks={hooks} selected={selected} rows={rows && rows.ok ? rows.data : null} />
  } else if (tab === 'catalog') {
    const catalog = await loadCatalog(null)
    body = <CatalogView initial={catalog.ok ? catalog.data : { query: null, items: [] }} canConfigure={configure} />
  } else {
    const mcp = await loadMcp()
    body = <McpView mcp={mcp} />
  }

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      {tabs.length ? (
        <nav className="flex flex-wrap gap-[6px]" aria-label={t('tabs.label')}>
          {tabs.map((x) => {
            const on = x === tab
            return (
              <Link
                key={x}
                href={TAB_HREF[x] as Route}
                aria-current={on ? 'page' : undefined}
                className={`cursor-pointer rounded-999 border px-[13px] py-[7px] text-12.5 hover:no-underline ${on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'}`}
              >
                {t(`tabs.${x}`)}
              </Link>
            )
          })}
        </nav>
      ) : null}
      <NowProvider now={new Date().toISOString()}>{body}</NowProvider>
    </div>
  )
}
