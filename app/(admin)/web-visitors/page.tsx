import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { loadVisitor, loadVisitors } from '@/lib/data/capture'
import { CaptureTabs, visiblePills } from '../lead-capture/_components/CaptureTabs'
import { VisitorsView } from './_components/VisitorsView'

const Params = z.object({
  days: z.coerce.number().pipe(z.union([z.literal(30), z.literal(90), z.literal(365)])).catch(30),
  crm: z.enum(['yes', 'no']).nullable().catch(null),
  campaign: z.string().trim().min(1).max(120).nullable().catch(null),
  page: z.string().trim().regex(/^\/[^\s]{0,199}$/).nullable().catch(null),
  org: z.string().regex(/^\d{9}$/).nullable().catch(null),
})
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Web visitors (Marketing.dc.html, route visitors). Company-level visits of the tracked sites (deals:see), the
 * period and the WEB-03 filters in the address, and the chosen company's visit history.
 */
export default async function WebVisitorsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({ days: one(sp.days) ?? 30, crm: one(sp.crm), campaign: one(sp.campaign), page: one(sp.page), org: one(sp.org) })
  const shell = await getShell()
  const t = await getTranslations('capture')
  const rights = { campaigns: can(shell, 'campaigns', 'see'), deals: can(shell, 'deals', 'see') }
  const pills = visiblePills(shell.modules, rights)

  if (!pills.includes('visitors')) {
    return (
      <div className="px-4 pb-[60px] pt-5 md:px-7">
        <div className="rounded-20 border border-line bg-surface p-[26px]">
          <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
          <p className="m-0 mt-2 text-13 text-muted">{t(shell.modules.visitors === false ? 'noAccess.moduleOff' : 'noAccess.visitors')}</p>
        </div>
      </div>
    )
  }

  const filters: Record<string, string | boolean> = {
    ...(p.crm ? { in_crm: p.crm === 'yes' } : {}),
    ...(p.campaign ? { campaign: p.campaign } : {}),
    ...(p.page ? { page: p.page } : {}),
  }
  const data = await loadVisitors(p.days, filters)
  const org = data.rows.find((r) => r.org_number === p.org)?.org_number ?? data.rows[0]?.org_number ?? null
  const v = org ? await loadVisitor(org, p.days) : null

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <CaptureTabs current="visitors" pills={pills} />
      <VisitorsView
        data={data}
        visitor={v && v.ok ? v.data : null}
        filters={{ days: p.days, crm: p.crm, campaign: p.campaign, page: p.page }}
        canConvert={can(shell, 'deals', 'add')}
        prospects={pills.includes('prospect')}
        nf={shell.me.number_format}
        now={new Date().toISOString()}
      />
    </div>
  )
}
