import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import {
  loadCampaign, loadCampaigns, loadCompare, loadConsentLog, loadCoupons, loadDomains, loadHygiene, loadPeopleOptions, loadReasonRequired, loadRecipients, loadTemplateVersions,
  loadRecommendations, loadSegments, loadStatusSummary, loadSuppressions, loadTemplates,
} from '@/lib/data/campaigns'
import { CAMPAIGN_TABS, CAMPAIGN_TYPES, RECIPIENT_STATES, TAB_PILL, type CampaignTab } from '@/lib/data/campaigns-shared'
import { CaptureTabs, visiblePills } from '../lead-capture/_components/CaptureTabs'
import { CampaignsView } from './_components/CampaignsView'
import { BuilderView } from './_components/BuilderView'
import { AudienceView } from './_components/AudienceView'
import { DeliverabilityView } from './_components/DeliverabilityView'

const uuid = z.string().uuid().nullable().catch(null)
const Params = z.object({
  tab: z.enum(CAMPAIGN_TABS).nullable().catch(null),
  campaign: uuid,
  template: uuid,
  seg: uuid,
  type: z.enum(CAMPAIGN_TYPES).nullable().catch(null),
  cmp: z.string().max(800).nullable().catch(null),
  view: z.enum(['recipients']).nullable().catch(null),
  state: z.enum(RECIPIENT_STATES).nullable().catch(null),
  before: z.coerce.number().int().positive().nullable().catch(null),
  sq: z.string().max(254).nullable().catch(null),
})
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Campaigns (Marketing.dc.html, route campaigns): Campaigns, Email builder, Audience and consent, Deliverability.
 * The tab and the chosen campaign, template or segment live in the address; Lead capture links here with
 * ?tab=builder|audience|deliverability. Each tab loads only what it shows (0037; consent and suppressions 0031).
 */
export default async function CampaignsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse(Object.fromEntries(Object.keys(Params.shape).map((k) => [k, one(sp[k])])))
  const shell = await getShell()
  const t = await getTranslations('campaigns')
  const nf = shell.me.number_format
  const rights = { campaigns: can(shell, 'campaigns', 'see'), deals: can(shell, 'deals', 'see') }
  const pills = visiblePills(shell.modules, rights)

  if (!pills.includes('campaigns')) {
    return (
      <div className="px-4 pb-[60px] pt-5 md:px-7">
        <div className="rounded-20 border border-line bg-surface p-[26px]">
          <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
          <p className="m-0 mt-2 text-13 text-muted">{t(shell.modules.campaigns === false ? 'noAccess.moduleOff' : 'noAccess.body')}</p>
        </div>
      </div>
    )
  }

  const tab: CampaignTab = p.tab ?? (p.template ? 'builder' : 'campaigns')
  const canDo = {
    add: can(shell, 'campaigns', 'add'), editOthers: can(shell, 'campaigns', 'edit_others'), del: can(shell, 'campaigns', 'delete'),
    export: can(shell, 'campaigns', 'export'), bulk: can(shell, 'campaigns', 'bulk'), configure: can(shell, 'campaigns', 'configure'),
  }
  const products = shell.products.map((x) => ({ key: x.key, name: x.name, color: x.color }))

  let body: React.ReactNode
  if (tab === 'campaigns') {
    const list = await loadCampaigns(p.type)
    const id = list.rows.find((r) => r.id === p.campaign)?.id ?? p.campaign ?? list.rows[0]?.id ?? null
    const cmp = p.cmp ? p.cmp.split(',').filter((x) => z.string().uuid().safeParse(x).success).slice(0, 20) : null
    const [detail, compare, templates, reasonRequired] = await Promise.all([
      id ? loadCampaign(id) : null,
      loadCompare(cmp, p.type),
      loadTemplates(),
      loadReasonRequired(),
    ])
    const selected = detail && detail.ok ? detail.data : null
    const recipients = selected && p.view === 'recipients' && selected.reports ? await loadRecipients(selected.id, p.state) : null
    body = (
      <CampaignsView
        rows={list.rows}
        type={p.type}
        selected={selected}
        compare={compare.ok ? compare.data : null}
        cmp={cmp && cmp.length ? cmp : null}
        recipients={recipients && recipients.ok ? { rows: recipients.data.rows, state: p.state } : null}
        templates={templates}
        can={canDo}
        reasonRequired={reasonRequired}
        nf={nf}
      />
    )
  } else if (tab === 'builder') {
    const [detail, templates, list, segments, domains, coupons, people, versions] = await Promise.all([
      p.campaign && !p.template ? loadCampaign(p.campaign) : null,
      loadTemplates(),
      loadCampaigns(null),
      loadSegments(),
      loadDomains(),
      loadCoupons(),
      loadPeopleOptions(),
      p.template ? loadTemplateVersions(p.template) : null,
    ])
    body = (
      <BuilderView
        campaign={detail && detail.ok ? detail.data : null}
        template={p.template ? templates.find((x) => x.id === p.template) ?? null : null}
        templates={templates}
        campaigns={list.rows}
        segments={segments}
        domains={domains.rows}
        providerConnected={domains.provider_connected}
        coupons={coupons}
        versions={versions && versions.ok ? versions.data : null}
        people={people}
        products={products}
        can={canDo}
        nf={nf}
      />
    )
  } else if (tab === 'audience') {
    const [segments, summary, log, suppressions, hygiene] = await Promise.all([
      loadSegments(),
      loadStatusSummary(),
      loadConsentLog(p.before),
      loadSuppressions(p.sq && p.sq.includes('@') ? p.sq : null),
      loadHygiene(),
    ])
    body = (
      <AudienceView
        segments={segments}
        selected={segments.find((s) => s.id === p.seg) ?? null}
        summary={summary}
        hygieneMonths={hygiene.months}
        log={{ rows: log.rows, next: log.next, before: p.before }}
        suppressions={p.sq && !p.sq.includes('@') ? null : suppressions.ok ? suppressions.data : []}
        suppressionQuery={p.sq}
        can={canDo}
        nf={nf}
      />
    )
  } else {
    const [domains, recommendations, hygiene] = await Promise.all([loadDomains(), loadRecommendations(), loadHygiene()])
    body = (
      <DeliverabilityView
        domains={domains.rows}
        providerConnected={domains.provider_connected}
        recommendations={recommendations}
        hygiene={hygiene}
        products={products}
        can={canDo}
        nf={nf}
      />
    )
  }

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <CaptureTabs current={TAB_PILL[tab]} pills={pills} />
      {body}
    </div>
  )
}
