'use client'

import { useCallback, useState } from 'react'
import { useTranslations } from 'next-intl'
import type { NumberFormat } from '@/lib/format'
import type { Dashboard, DashboardRef, DealForecast, Goal, ProductForecast } from '@/lib/data/insights'
import { TABS, initialBuilder, type BuilderState, type Fields, type Tab } from '@/lib/data/insights-shared'
import { AskAi } from './AskAi'
import { Builder } from './Builder'
import { Dashboards } from './Dashboards'
import { DrillModal, type DrillTarget } from './DrillModal'
import { Forecast } from './Forecast'
import { Goals } from './Goals'
import type { Pickers, Rights } from './shared'

type Res<T> = { ok: true; data: T } | { ok: false; code: string }

/** Insights (Insights.dc.html): five tabs, the drill-down over them, and the header's promise. */
export function InsightsScreen(p: {
  initialTab: Tab
  list: DashboardRef[]
  current: Dashboard | null
  currentKey: string
  goals: Res<Goal[]>
  dealForecast: Res<DealForecast>
  productForecast: Res<ProductForecast>
  dealFields: Fields | null
  reportLimit: number | null
  rights: Rights
  pickers: Pickers
  nf: NumberFormat
}) {
  const t = useTranslations('insights')
  const [tab, setTab] = useState<Tab>(p.initialTab)
  const [builder, setBuilder] = useState<BuilderState>(() => initialBuilder(p.pickers.pipelines[0]?.id ?? ''))
  const [drill, setDrill] = useState<DrillTarget | null>(null)
  const closeDrill = useCallback(() => setDrill(null), [])

  // Save to dashboard goes to the open dashboard when it may be changed, else to the staff member's own
  const editable = p.current && (p.current.role === 'owner' || p.current.role === 'editor') ? p.current.id : null
  const own = p.list.find((d) => d.role === 'owner')?.id ?? null

  const pick = (k: Tab) => {
    setTab(k)
    try { const u = new URL(window.location.href); u.searchParams.set('tab', k); window.history.replaceState(null, '', u) } catch { /* the address is a convenience */ }
  }

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-[6px]">
          {TABS.map((k) => (
            <button key={k} type="button" aria-pressed={tab === k} onClick={() => pick(k)}
              className={`cursor-pointer rounded-999 border px-[14px] py-2 text-12.5 ${tab === k ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}>
              {t(`tabs.${k}`)}
            </button>
          ))}
        </div>
        <span className="flex-1" />
        <span className="text-12 text-muted">{t('header', { limit: p.reportLimit === null ? t('unlimited') : String(p.reportLimit) })}</span>
      </div>

      {tab === 'dash' ? (
        <Dashboards list={p.list} current={p.current} currentKey={p.currentKey} rights={p.rights} pickers={p.pickers} nf={p.nf}
          onAddReport={() => pick('builder')} onDrill={setDrill} />
      ) : null}
      {tab === 'builder' ? (
        <Builder state={builder} setState={setBuilder} initialFields={p.dealFields} rights={p.rights} pickers={p.pickers} nf={p.nf}
          target={{ dashboard: editable ?? own, newName: t('dash.mine') }} onSaved={() => pick('dash')} onDrill={setDrill} />
      ) : null}
      {tab === 'goals' ? <Goals goals={p.goals.ok ? p.goals.data : []} error={p.goals.ok ? null : p.goals.code} rights={p.rights} pickers={p.pickers} nf={p.nf} /> : null}
      {tab === 'forecast' ? <Forecast deals={p.dealForecast} products={p.productForecast} rights={p.rights} nf={p.nf} /> : null}
      {tab === 'ai' ? <AskAi /> : null}

      {drill ? <DrillModal target={drill} onClose={closeDrill} nf={p.nf} canExport={p.rights.exportRows} /> : null}
    </div>
  )
}
