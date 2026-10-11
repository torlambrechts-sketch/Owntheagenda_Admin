import { getTranslations } from 'next-intl/server'
import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import { currentProduct } from '@/lib/product'
import type { RpcResult } from '@/lib/rpc'
import { RpcError } from '@/lib/rpc'
import {
  loadAdCampaigns, loadEmailConnected, loadLists, loadOverview, loadProposalStage, loadSeo, loadSequences,
} from '@/lib/data/simple-growth'
import { GROWTH_RANGES, GROWTH_TABS, RANGED, RANGE_DAYS, type GrowthTab } from '@/lib/data/simple-growth-shared'
import { loadWebSite } from '@/lib/data/analytics'
import { WebDetail } from '../analytics/_components/Web'
import { GrowthTabs } from './_components/GrowthTabs'
import { Analytics } from './_components/Analytics'
import { SeoTab } from './_components/Seo'
import { CampaignsTab } from './_components/Campaigns'
import { EmailTab } from './_components/Email'

const Params = z.object({ tab: z.enum(GROWTH_TABS).catch('analytics'), range: z.enum(GROWTH_RANGES).catch('30d') })
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)

class Refused extends Error {}
/** A read the tab cannot render without: a refusal for want of the right shows the tab's no-access state. */
function need<T>(r: RpcResult<T>): T {
  if (r.ok) return r.data
  if (r.code === 'forbidden') throw new Refused()
  throw new RpcError(r.code, r.detail)
}

/**
 * Sentral Simple › Growth (SimpleGrowth.dc.html; its campaigns and email views are GrowthMarketing.dc.html). The tab and
 * the range live in the address; the application is the shell's. Analytics and SEO need a reports right (global or
 * campaigns, require_marketing_reports), Marketing campaigns and Email Campaigns › See; a tab the person may not open is
 * not offered. Each tab loads only what it shows.
 */
export default async function GrowthPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({ tab: one(sp.tab) ?? 'analytics', range: one(sp.range) ?? '30d' })
  const shell = await getShell()
  const t = await getTranslations('simpleGrowth')
  const product = await currentProduct(shell)
  const app = shell.products.find((x) => x.key === product)
  const nf = shell.me.number_format

  const reports = can(shell, 'global', 'reports_others') || can(shell, 'campaigns', 'reports_others')
  const see = can(shell, 'campaigns', 'see')
  const tabs = GROWTH_TABS.filter((k) => (k === 'analytics' || k === 'seo' ? reports : see))
  const tab: GrowthTab | null = tabs.includes(p.tab) ? p.tab : tabs[0] ?? null
  const noAccess = (
    <div className="rounded-20 border border-line bg-surface p-[26px]">
      <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
      <p className="m-0 mt-2 text-13 text-muted">{t('noAccess.body')}</p>
    </div>
  )

  let body: React.ReactNode = noAccess
  try {
    if (tab === 'analytics') {
      // the overview, then the full web detail of the application's own site over the same days (V-WEB-05)
      const overview = need(await loadOverview(product, p.range))
      const web = overview.site ? need(await loadWebSite(overview.site.id, RANGE_DAYS[p.range])) : null
      body = (
        <>
          <Analytics d={overview} nf={nf} app={app?.name ?? product} detail={web !== null} />
          {web ? <WebDetail d={web} nf={nf} /> : null}
        </>
      )
    } else if (tab === 'seo') {
      body = <SeoTab d={need(await loadSeo(product, p.range))} nf={nf} product={product} app={app?.name ?? product} canAdd={can(shell, 'campaigns', 'add')} editOthers={can(shell, 'campaigns', 'edit_others')} />
    } else if (tab === 'campaigns') {
      body = (
        <CampaignsTab
          d={need(await loadAdCampaigns(product))}
          nf={nf}
          product={product}
          app={app?.name ?? product}
          canAdd={can(shell, 'campaigns', 'add')}
          editOthers={can(shell, 'campaigns', 'edit_others')}
          canSpend={can(shell, 'campaigns', 'reports_others')}
        />
      )
    } else if (tab === 'email') {
      const [sequences, stage, lists, emailConnected] = await Promise.all([loadSequences(), loadProposalStage(), loadLists(), loadEmailConnected()])
      body = (
        <EmailTab
          sequences={need(sequences)}
          stage={stage}
          lists={lists}
          emailConnected={emailConnected}
          nf={nf}
          rights={{
            // the engine's rule (workflow_save, campaign_action) and the campaigns' (campaign_save); the database decides
            edit: can(shell, 'deals', 'workflows') && can(shell, 'campaigns', 'workflows') && can(shell, 'campaigns', 'add'),
            configure: can(shell, 'global', 'configure'),
          }}
        />
      )
    }
  } catch (e) {
    if (!(e instanceof Refused)) throw e
    body = noAccess
  }

  return (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
      {tab ? <GrowthTabs tab={tab} range={p.range} tabs={tabs} showRange={RANGED.includes(tab)} /> : null}
      {body}
    </div>
  )
}
