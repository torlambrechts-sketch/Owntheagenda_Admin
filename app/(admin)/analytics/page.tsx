import { cookies } from 'next/headers'
import { getNow, getTranslations } from 'next-intl/server'
import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import { RpcError, type RpcResult } from '@/lib/rpc'
import {
  loadActivation, loadAttribution, loadBusiness, loadHealth, loadMetricDefs, loadRetention, loadUsage, loadWeb,
} from '@/lib/data/analytics'
import { RANGED_TABS, RANGES, TABS, addMonths } from '@/lib/data/analytics-calc'
import { Frame } from './_components/Frame'
import { Business } from './_components/Business'
import { Activation } from './_components/Activation'
import { Retention } from './_components/Retention'
import { Usage } from './_components/Usage'
import { Web } from './_components/Web'
import { Attribution } from './_components/Attribution'
import { Health } from './_components/Health'
import { Definitions } from './_components/Definitions'

const Params = z.object({
  tab: z.enum(TABS).catch('business'),
  range: z.enum(RANGES).catch('12m'),
  cohort: z.string().regex(/^\d{4}-\d{2}$/).nullable().catch(null),
  ret: z.enum(['logos', 'revenue']).catch('logos'),
  touch: z.enum(['first', 'last']).catch('first'),
})
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)

class Refused extends Error {}
/** A read the tab cannot render without: a refusal for want of the right shows the no-access state. */
function need<T>(r: RpcResult<T>): T {
  if (r.ok) return r.data
  if (r.code === 'forbidden') throw new Refused()
  throw new RpcError(r.code, r.detail)
}

/**
 * Analytics (Analytics.dc.html). The tab, the range and the tab's own toggles live in the address, so a link
 * opens the same view; the product comes from the shell's switcher. Each tab loads only what it shows, and
 * every read that takes a period gets the range.
 */
export default async function AnalyticsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({ tab: one(sp.tab) ?? 'business', range: one(sp.range) ?? '12m', cohort: one(sp.cohort) ?? null, ret: one(sp.ret) ?? 'logos', touch: one(sp.touch) ?? 'first' })
  const shell = await getShell()
  const t = await getTranslations('analytics')
  const noAccess = (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] md:px-7">
      <div className="rounded-20 border border-line bg-surface p-[26px]">
        <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
        <p className="m-0 mt-2 text-13 text-muted">{t('noAccess.body')}</p>
      </div>
    </div>
  )
  // the analytics reads need Global › See reports of others; the database refuses anyway
  if (!can(shell, 'global', 'reports_others')) return noAccess

  const product = (await cookies()).get('product')?.value ?? 'all'
  const now = await getNow()
  const nf = shell.me.number_format
  const cur = product === 'all' ? null : shell.products.find((x) => x.key === product)
  const scope = cur?.name ?? t('allApplications')
  const inScope = shell.products.filter((x) => x.installed && (product === 'all' || x.key === product))
  const { tab, range } = p

  let body: React.ReactNode
  try {
    if (tab === 'business') {
      const [biz, defs] = await Promise.all([loadBusiness(product, range), loadMetricDefs()])
      body = <Business d={need(biz)} defs={defs.ok ? defs.data : []} range={range} products={inScope} scope={scope} nf={nf} now={now} />
    } else if (tab === 'activation') {
      const first = need(await loadActivation(product, p.cohort))
      // a cohort outside the four offered falls back to the default one
      const d = p.cohort && !(first.cohorts ?? []).includes(p.cohort) ? need(await loadActivation(product, null)) : first
      const earlier = need(await loadActivation(product, addMonths(d.cohort, -3)))
      body = <Activation d={d} earlier={earlier.cohort === addMonths(d.cohort, -3) ? earlier : null} nf={nf} />
    } else if (tab === 'retention') {
      const [ret, biz] = await Promise.all([loadRetention(product, p.ret), loadBusiness(product, '12m')])
      body = <Retention d={need(ret)} biz={biz.ok ? biz.data : null} nf={nf} now={now} />
    } else if (tab === 'usage') {
      body = <Usage d={need(await loadUsage(product, range))} range={range} products={inScope} single={product !== 'all'} nf={nf} now={now} />
    } else if (tab === 'web') {
      const [web, attr] = await Promise.all([loadWeb(range), loadAttribution('first', range)])
      body = <Web d={need(web)} spend={need(attr).spend} canSpend={can(shell, 'campaigns', 'reports_others')} range={range} nf={nf} now={now} />
    } else if (tab === 'attribution') {
      const webHref = `/analytics?tab=web${range === '12m' ? '' : `&range=${range}`}`
      body = <Attribution d={need(await loadAttribution(p.touch, range))} canSpend={can(shell, 'campaigns', 'reports_others')} nf={nf} webHref={webHref} />
    } else if (tab === 'health') {
      const products = Object.fromEntries(shell.products.map((x) => [x.key, x.name]))
      body = <Health d={need(await loadHealth(product))} products={products} canEdit={can(shell, 'global', 'configure')} nf={nf} now={now} />
    } else {
      body = <Definitions defs={need(await loadMetricDefs())} />
    }
  } catch (e) {
    if (e instanceof Refused) return noAccess
    throw e
  }

  return (
    <Frame tab={tab} tabs={TABS} range={range} scope={scope} ranged={RANGED_TABS.includes(tab)}>
      {body}
    </Frame>
  )
}
