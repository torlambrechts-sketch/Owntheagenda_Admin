import { getLocale, getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { currentProduct } from '@/lib/product'
import type { RpcResult } from '@/lib/rpc'
import { RpcError } from '@/lib/rpc'
import { loadAdCampaigns, loadEmailConnected, loadLists, loadProposalStage, loadSeo, loadSequences } from '@/lib/data/simple-growth'
import { loadFunnel, loadIntegrations, loadKeywordHistory, loadPages, loadScope } from '@/lib/data/growth'
import { keywordRow, opportunities, rate } from '@/lib/growth/calc'
import { RANGE_DAYS, SCOPED, TABS, osloToday, parseGrowth, type Scope, type Tab } from '@/lib/growth/scope'
import { GrowthTabs } from './_components/GrowthTabs'
import { ScopeBar } from './_components/ScopeBar'
import { OverviewTab } from './_components/Overview'
import { FunnelTab } from './_components/Funnel'
import { PagesTab } from './_components/Pages'
import { SeoKeywordsTab } from './_components/SeoKeywords'
import { IntegrationsTab } from './_components/Integrations'
import { CampaignsTab } from './_components/Campaigns'
import { EmailTab } from './_components/Email'
import { dayLabel, hh } from './_components/v2kit'

/** The channels the Source filter offers: channel_rules' keys (0025, 0073) */
const CHANNELS = ['organic_search', 'paid_search', 'direct', 'social', 'referral', 'email', 'paid_social', 'partner']

class Refused extends Error {}
/** A read the tab cannot render without: a refusal for want of the right shows the tab's no-access state. */
function need<T>(r: RpcResult<T>): T {
  if (r.ok) return r.data
  if (r.code === 'forbidden') throw new Refused()
  throw new RpcError(r.code, r.detail)
}

/**
 * Sentral Simple › Growth (SimpleGrowth.dc.html of 11 Oct 2026; Marketing campaigns and Email are GrowthMarketing.dc.html).
 * Seven tabs; the scope bar (period › day › hour, source, device) on Overview, Signup funnel and log, Pages and links and
 * SEO › Keywords. Everything chosen lives in the address (lib/growth/scope). Overview, funnel, pages, SEO and Integrations
 * need a reports right (global or campaigns, require_marketing_reports); Marketing campaigns and Email Campaigns › See. A
 * tab the person may not open is not offered. Each tab loads only what it shows; docs/crm-enrichment/growth-v2-gap.md
 * maps the design to its sources.
 */
export default async function GrowthPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = parseGrowth(await searchParams)
  const shell = await getShell()
  const t = await getTranslations('simpleGrowth')
  const locale = await getLocale()
  const product = await currentProduct(shell)
  const app = shell.products.find((x) => x.key === product)
  const nf = shell.me.number_format

  const reports = can(shell, 'global', 'reports_others') || can(shell, 'campaigns', 'reports_others')
  const see = can(shell, 'campaigns', 'see')
  const canAdd = can(shell, 'campaigns', 'add')
  const tabs = TABS.filter((k) => (k === 'campaigns' || k === 'email' ? see : reports))
  const tab: Tab | null = tabs.includes(p.tab) ? p.tab : tabs[0] ?? null
  const scope: Scope = { range: p.range, day: p.day, hour: p.hour, src: p.src, dev: p.dev }
  const today = osloToday()
  const day = p.range === 'today' ? today : p.day
  const scopeLabel = day
    ? `${dayLabel(day, locale)}${p.hour !== null ? ` ${hh(p.hour)}–${hh((p.hour + 1) % 24)}` : ''}`
    : t('scope.lastLower', { days: RANGE_DAYS[p.range] })
  const noAccess = (
    <div className="rounded-20 border border-line bg-surface p-[26px]">
      <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
      <p className="m-0 mt-2 text-13 text-muted">{t('noAccess.body')}</p>
    </div>
  )

  let body: React.ReactNode = noAccess
  let bar: React.ReactNode = null
  const scopeBar = (updatedAt: string | null, extra: Record<string, string | number | null> = {}, opts: { hideFilters?: boolean; seo?: boolean } = {}) => (
    <ScopeBar tab={tab!} scope={scope} channels={CHANNELS} dayLabel={day ? dayLabel(day, locale) : null} updatedAt={updatedAt} extra={extra}
      hideFilters={opts.hideFilters} ranges={opts.seo ? ['7d', '30d', '90d'] : undefined} />
  )
  try {
    if (tab === 'overview') {
      const [sc, pages, seo, funnel] = await Promise.all([
        loadScope(product, scope), loadPages(product, scope, null), loadSeo(product, p.range === 'today' ? '7d' : p.range), loadFunnel(product, scope, 4),
      ])
      const d = need(sc)
      const f = funnel.ok ? funnel.data : null
      // the share of visits that finished signup after sending the org.nr (step 4's segments count both)
      const seg4 = f ? f.segments.filter((x) => x.kind === 'channel') : []
      const entered4 = seg4.reduce((a, x) => a + x.entered, 0)
      const stepRate = entered4 ? seg4.reduce((a, x) => a + x.continued, 0) / entered4 : null
      const opps = opportunities({
        days: d.days === 1 ? 1 : d.days, visitors: d.kpis.visitors, started: d.kpis.started, devices: d.devices,
        landing: pages.ok ? pages.data.landing : [],
        keywords: seo.ok ? seo.data.keywords.map((k) => keywordRow(k)) : [],
        errors: f ? f.reasons.filter((r) => r.kind === 'error').map((r) => ({ value: r.value, count: r.count })) : [],
        stepRate: stepRate && stepRate > 0 ? stepRate : null,
      })
      bar = scopeBar(d.updated_at, { metric: p.metric })
      body = <OverviewTab d={d} scope={scope} metric={p.metric} nf={nf} opps={opps} />
    } else if (tab === 'funnel') {
      const [sc, f] = await Promise.all([loadScope(product, scope), loadFunnel(product, scope, p.step)])
      bar = scopeBar(sc.ok ? sc.data.updated_at : null, { step: p.step, lf: p.lf })
      body = <FunnelTab d={need(f)} scope={scope} scopeLabel={scopeLabel} lf={p.lf} nf={nf} />
    } else if (tab === 'pages') {
      const [sc, pg] = await Promise.all([loadScope(product, scope), loadPages(product, scope, p.page)])
      const s = sc.ok ? sc.data : null
      bar = scopeBar(s?.updated_at ?? null, { sort: p.sort, page: p.page })
      body = <PagesTab d={need(pg)} scope={scope} sort={p.sort} nf={nf} siteRate={s ? rate(s.kpis.started, s.kpis.visitors) : null} />
    } else if (tab === 'seo') {
      const range = p.range === 'today' ? '7d' : p.range
      const d = need(await loadSeo(product, range))
      const kwSel = p.kw ?? d.keywords.map((k) => keywordRow(k)).sort((a, b) => b.potential - a.potential)[0]?.query ?? null
      const history = kwSel && d.connected ? await loadKeywordHistory(product, kwSel, RANGE_DAYS[range]) : null
      bar = scopeBar(d.search_console.last_import_at, { sub: 'keywords', kt: p.kt, kw: p.kw }, { hideFilters: true, seo: true })
      const brands = [product, app?.name ?? '', ...(d.site ? [d.site.hostname.replace(/^www\./, '').split('.')[0] ?? ''] : [])]
      body = (
        <SeoKeywordsTab d={d} scope={{ ...scope, range }} kt={p.kt} kw={kwSel} history={history?.ok ? history.data : null} nf={nf} product={product} brands={brands}
          canAdd={canAdd} editOthers={can(shell, 'campaigns', 'edit_others')} />
      )
    } else if (tab === 'integrations') {
      const [d, seo] = await Promise.all([loadIntegrations(product), loadSeo(product, '30d')])
      body = <IntegrationsTab d={need(d)} sc={seo.ok ? seo.data : null} open={p.sub} nf={nf} app={app?.name ?? product} canMeasure={canAdd} />
    } else if (tab === 'campaigns') {
      body = (
        <CampaignsTab
          d={need(await loadAdCampaigns(product))}
          nf={nf}
          product={product}
          app={app?.name ?? product}
          canAdd={canAdd}
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
    bar = null
  }

  return (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
      {tab ? <GrowthTabs tab={tab} tabs={tabs} scope={scope} /> : null}
      {tab && SCOPED.includes(tab) ? bar : null}
      {body}
    </div>
  )
}
