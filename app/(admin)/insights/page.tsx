import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import {
  loadDashboard, loadDashboards, loadDealForecast, loadFields, loadGoals, loadPickers, loadProductForecast, loadReportLimit,
} from '@/lib/data/insights'
import { TABS, type Tab } from '@/lib/data/insights-shared'
import { InsightsScreen } from './_components/InsightsScreen'

const plain = <T,>(r: { ok: true; data: T } | { ok: false; code: string }) => (r.ok ? { ok: true as const, data: r.data } : { ok: false as const, code: r.code })

/**
 * Insights (Insights.dc.html): dashboards, the report builder, goals, forecasts and «Ask for a report».
 * ?dashboard=<id> opens a dashboard (or «mine» for the staff member's own, not yet made); ?tab=<tab> a tab.
 */
export default async function InsightsPage({ searchParams }: { searchParams: Promise<{ dashboard?: string; tab?: string }> }) {
  const shell = await getShell()
  const sp = await searchParams
  const see = can(shell, 'deals', 'see')

  const [list, goals, dealForecast, productForecast, fields, pickers, reportLimit] = await Promise.all([
    loadDashboards(),
    loadGoals(),
    loadDealForecast(4),
    loadProductForecast(12),
    see ? loadFields('deal') : Promise.resolve(null),
    loadPickers(),
    loadReportLimit(),
  ])
  const dashboards = list.ok ? list.data : []

  // the dashboard asked for, else the staff member's own, else the Default template
  const asked = z.string().uuid().safeParse(sp.dashboard)
  const chosen = (asked.success ? dashboards.find((d) => d.id === asked.data) : undefined)
    ?? (sp.dashboard === 'mine' ? undefined : (dashboards.find((d) => d.role === 'owner') ?? dashboards.find((d) => d.template_role === 'default') ?? dashboards[0]))
  const current = chosen ? await loadDashboard(chosen.id) : null
  const tab = (TABS as readonly string[]).includes(sp.tab ?? '') ? (sp.tab as Tab) : 'dash'

  return (
    <InsightsScreen
      initialTab={tab}
      list={dashboards}
      current={current && current.ok ? current.data : null}
      currentKey={chosen?.id ?? 'mine'}
      goals={plain(goals)}
      dealForecast={plain(dealForecast)}
      productForecast={plain(productForecast)}
      dealFields={fields && fields.ok ? fields.data : null}
      reportLimit={reportLimit}
      rights={{
        meId: shell.me.id,
        meName: shell.me.name,
        see,
        others: can(shell, 'deals', 'reports_others'),
        exportRows: can(shell, 'deals', 'export'),
        configure: can(shell, 'deals', 'configure'),
        global: can(shell, 'global', 'see'),
      }}
      pickers={pickers}
      nf={shell.me.number_format}
    />
  )
}
