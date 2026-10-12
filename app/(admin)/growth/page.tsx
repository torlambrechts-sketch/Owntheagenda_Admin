import { getLocale, getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { currentProduct } from '@/lib/product'
import type { RpcResult } from '@/lib/rpc'
import { RpcError } from '@/lib/rpc'
import { loadAdCampaigns, loadEmailConnected, loadLists, loadProposalStage, loadSeo, loadSequences } from '@/lib/data/simple-growth'
import { loadCampaignDetail, loadSendTimes, loadSequenceResults } from '@/lib/data/growth-v3'
import { loadAds, loadAudiences, loadBudget, loadCalendar, loadDeliverability, loadExperiments, loadFlows, loadFunnel, loadIntegrations, loadKeywordHistory, loadOutcomes,
  loadPages, loadScope, loadSenderDomains, loadSeoAlerts, loadSeoChanges, loadSeoClusters, loadSeoLinks, loadSeoOpps, loadSeoOverview, loadSeoPlan,
  loadTrial } from '@/lib/data/growth'
import { SEO_VIEWS, seoOpportunities, valuePerClick, type SeoView } from '@/lib/growth/seo'
import { CAMP_VIEWS, EMAIL_VIEWS, type CampView, type EmailView } from '@/lib/growth/playbook'
import { keywordRow, opportunities, rate } from '@/lib/growth/calc'
import { RANGE_DAYS, SCOPED, TABS, growthHref, osloToday, parseGrowth, type Scope, type Tab } from '@/lib/growth/scope'
import { GrowthTabs, SubTabs } from './_components/GrowthTabs'
import { ScopeBar } from './_components/ScopeBar'
import { OverviewTab } from './_components/Overview'
import { FunnelTab } from './_components/Funnel'
import { PagesTab } from './_components/Pages'
import { SeoKeywordsTab } from './_components/SeoKeywords'
import { IntegrationsTab } from './_components/Integrations'
import { SeoOverviewView } from './_components/seo/Overview'
import { SeoClustersView } from './_components/seo/Clusters'
import { SeoOppsView } from './_components/seo/Opportunities'
import { SeoPlanView } from './_components/seo/Plan'
import { SeoLinksView } from './_components/seo/Links'
import { SeoSerpView } from './_components/seo/Serp'
import { SeoChangesView } from './_components/seo/Changes'
import { SeoAlertsView } from './_components/seo/Alerts'
import { CampaignsTab } from './_components/Campaigns'
import { EmailTab } from './_components/Email'
import { OutcomesView } from './_components/playbook/Outcomes'
import { BudgetView } from './_components/playbook/Budget'
import { ExperimentsView } from './_components/playbook/Experiments'
import { AudiencesView } from './_components/playbook/Audiences'
import { CreativeView } from './_components/playbook/Creative'
import { CalendarView } from './_components/playbook/Calendar'
import { TrialView } from './_components/playbook/Trial'
import { LibraryView } from './_components/playbook/Library'
import { DeliverabilityView } from './_components/playbook/Deliverability'
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
 * SEO › Keywords. SEO has nine views (SeoSuite.dc.html, 0074) under its own sub-tabs; Marketing campaigns seven and Email four
 * (GrowthPlaybook.dc.html, 0076). Everything chosen lives in the address (lib/growth/scope). Overview, funnel, pages, SEO and Integrations
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

  // a view refused for want of a right shows the no-access card under its sub-tabs, so the others stay in reach
  const guarded = async (f: () => Promise<React.ReactNode>): Promise<React.ReactNode> => {
    try {
      return await f()
    } catch (e) {
      if (e instanceof Refused) return noAccess
      throw e
    }
  }

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
      // SEO's nine views (SeoSuite.dc.html); the scope bar only on Keywords (the design's showScope)
      const view: SeoView = (SEO_VIEWS as readonly string[]).includes(p.sub ?? '') ? (p.sub as SeoView) : 'overview'
      const subTabs = (
        <SubTabs current={view} label={t('seoSuite.subTabs.label')}
          items={SEO_VIEWS.map((k) => ({ key: k, label: t(`seoSuite.subTabs.${k}`), href: growthHref('seo', scope, { sub: k === 'overview' ? null : k }) }))} />
      )
      const brands = (host: string | null) => [product, app?.name ?? '', ...(host ? [host.replace(/^www\./, '').split('.')[0] ?? ''] : [])]
      let inner: React.ReactNode = null
      if (view === 'keywords') {
        const range = p.range === 'today' ? '7d' : p.range
        const d = need(await loadSeo(product, range))
        const kwSel = p.kw ?? d.keywords.map((k) => keywordRow(k)).sort((a, b) => b.potential - a.potential)[0]?.query ?? null
        const history = kwSel && d.connected ? await loadKeywordHistory(product, kwSel, RANGE_DAYS[range]) : null
        bar = scopeBar(d.search_console.last_import_at, { sub: 'keywords', kt: p.kt, kw: p.kw }, { hideFilters: true, seo: true })
        inner = (
          <SeoKeywordsTab d={d} scope={{ ...scope, range }} kt={p.kt} kw={kwSel} history={history?.ok ? history.data : null} nf={nf} product={product}
            brands={brands(d.site?.hostname ?? null)} canAdd={canAdd} editOthers={can(shell, 'campaigns', 'edit_others')} />
        )
      } else if (view === 'overview') {
        const [ov, op] = await Promise.all([loadSeoOverview(product), loadSeoOpps(product)])
        const o = need(op)
        inner = <SeoOverviewView d={need(ov)} opps={seoOpportunities(o)} priced={valuePerClick(o.econ).perClick !== null} nf={nf} product={product} app={app?.name ?? product} canAdd={canAdd} />
      } else if (view === 'clusters') {
        inner = <SeoClustersView d={need(await loadSeoClusters(product))} sel={p.cl} scope={scope} nf={nf} product={product} canAdd={canAdd} />
      } else if (view === 'opps') {
        const o = need(await loadSeoOpps(product))
        inner = <SeoOppsView opps={seoOpportunities(o)} ot={p.ot} priced={valuePerClick(o.econ).perClick !== null} connected={o.connected} scope={scope} nf={nf} product={product} canAdd={canAdd} />
      } else if (view === 'plan') {
        const [pl, op] = await Promise.all([loadSeoPlan(product, p.brief), loadSeoOpps(product)])
        inner = <SeoPlanView d={need(pl)} opps={op.ok ? seoOpportunities(op.data) : []} scope={scope} nf={nf} brands={brands(null)} canAdd={canAdd} />
      } else if (view === 'links') {
        inner = <SeoLinksView d={need(await loadSeoLinks(product))} nf={nf} product={product} canAdd={canAdd} />
      } else if (view === 'serp') {
        inner = <SeoSerpView />
      } else if (view === 'changes') {
        inner = <SeoChangesView d={need(await loadSeoChanges(product))} nf={nf} product={product} canAdd={canAdd} />
      } else if (view === 'alerts') {
        inner = <SeoAlertsView d={need(await loadSeoAlerts(product))} nf={nf} product={product} canEdit={can(shell, 'campaigns', 'edit_others')} canAck={canAdd} />
      }
      body = <div className="flex flex-col gap-[14px]">{subTabs}{inner}</div>
    } else if (tab === 'integrations') {
      const [d, seo, ads] = await Promise.all([loadIntegrations(product), loadSeo(product, '30d'), loadAds(product)])
      body = <IntegrationsTab d={need(d)} sc={seo.ok ? seo.data : null} ads={ads.ok ? ads.data : null} products={shell.products.map((x) => ({ key: x.key, name: x.name }))}
        open={p.sub} nf={nf} app={app?.name ?? product} canMeasure={canAdd} />
    } else if (tab === 'campaigns') {
      // Marketing campaigns and the playbook's views (GrowthPlaybook.dc.html, 0076) under their own sub-tabs
      const view: CampView = (CAMP_VIEWS as readonly string[]).includes(p.sub ?? '') ? (p.sub as CampView) : 'base'
      const appName = app?.name ?? product
      const inner = await guarded(async () => {
        switch (view) {
          case 'outcomes': return <OutcomesView d={need(await loadOutcomes(product, p.am))} nf={nf} app={appName} />
          case 'budget': return <BudgetView d={need(await loadBudget(product))} nf={nf} product={product} app={appName} canEdit={can(shell, 'campaigns', 'reports_others')} />
          case 'experiments': return <ExperimentsView d={need(await loadExperiments(product))} nf={nf} product={product} canAdd={canAdd} />
          case 'audiences': {
            const [lists, ads] = await Promise.all([loadAudiences(), loadAds(product)])
            return <AudiencesView lists={need(lists)} nf={nf} app={appName} connected={ads.ok ? ads.data.providers.filter((x) => x.status === 'connected').map((x) => x.provider) : []} />
          }
          case 'creative': {
            const ads = await loadAds(product)
            return <CreativeView ads={ads.ok ? ads.data : null} nf={nf} canLink={can(shell, 'campaigns', 'edit_others')} />
          }
          case 'calendar': return <CalendarView d={need(await loadCalendar(product))} product={product} canAdd={canAdd} />
          default: {
            const camps = need(await loadAdCampaigns(product))
            // the first campaign's days, ads and keywords (0083); the others are read when chosen
            const first = camps.rows[0]?.figures ? await loadCampaignDetail(camps.rows[0].id) : null
            return (
            <CampaignsTab
              d={camps}
              initialDetail={first?.ok ? first.data : null}
              nf={nf}
              product={product}
              app={appName}
              canAdd={canAdd}
              editOthers={can(shell, 'campaigns', 'edit_others')}
              canSpend={can(shell, 'campaigns', 'reports_others')}
            />
            )
          }
        }
      })
      body = (
        <div className="flex flex-col gap-[14px]">
          <SubTabs current={view} label={t('playbook.campSubs.label')}
            items={CAMP_VIEWS.map((k) => ({ key: k, label: t(`playbook.campSubs.${k}`), href: growthHref('campaigns', scope, { sub: k === 'base' ? null : k }) }))} />
          {inner}
        </div>
      )
    } else if (tab === 'email') {
      const view: EmailView = (EMAIL_VIEWS as readonly string[]).includes(p.sub ?? '') ? (p.sub as EmailView) : 'base'
      // the engine's rule (workflow_save, campaign_action) and the campaigns' (campaign_save); the database decides
      const edit = can(shell, 'deals', 'workflows') && can(shell, 'campaigns', 'workflows') && can(shell, 'campaigns', 'add')
      const inner = await guarded(async () => {
        switch (view) {
          case 'trial': return <TrialView d={need(await loadTrial(product))} nf={nf} app={app?.name ?? product} />
          case 'library': return <LibraryView d={need(await loadFlows())} nf={nf} canEdit={edit} />
          case 'deliver': {
            const [dl, dom] = await Promise.all([loadDeliverability(product), loadSenderDomains()])
            return <DeliverabilityView d={need(dl)} domains={dom.ok ? dom.data.rows : null} nf={nf} />
          }
          default: {
            const [sequences, stage, lists, emailConnected, times] = await Promise.all([loadSequences(), loadProposalStage(), loadLists(), loadEmailConnected(), loadSendTimes(product)])
            const seqs = need(sequences)
            // the first sequence's last 30 days per step (0083); the others are read when chosen
            const results = seqs[0] ? await loadSequenceResults(seqs[0].id) : null
            return (
              <EmailTab
                sequences={seqs}
                product={product}
                initialResults={results?.ok ? results.data : null}
                sendTimes={times.ok ? times.data : null}
                stage={stage}
                lists={lists}
                emailConnected={emailConnected}
                nf={nf}
                rights={{ edit, configure: can(shell, 'global', 'configure') }}
              />
            )
          }
        }
      })
      body = (
        <div className="flex flex-col gap-[14px]">
          <SubTabs current={view} label={t('playbook.emailSubs.label')}
            items={EMAIL_VIEWS.map((k) => ({ key: k, label: t(`playbook.emailSubs.${k}`), href: growthHref('email', scope, { sub: k === 'base' ? null : k }) }))} />
          {inner}
        </div>
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
