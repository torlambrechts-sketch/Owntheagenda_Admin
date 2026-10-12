import Link from 'next/link'
import type { Route } from 'next'
import { getFormatter, getTranslations } from 'next-intl/server'
import { formatNumber, percent } from '@/lib/format'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { loadDeploys, loadMetrics } from '@/lib/data/dev-delivery'
import { loadBoard, loadBugs } from '@/lib/data/dev-core'
import { doraFrequency, doraLeadTime, doraRestore, durationParts, type DoraLevel } from './delivery/logic'
import { d } from './delivery/styles'

const LEVEL_BG: Record<DoraLevel, string> = { elite: 'bg-ok-bg', high: 'bg-teal-soft', medium: 'bg-highlight', low: 'bg-peach' }
/** the design's cycle segments and their colours (DevHub.dc.html «cycle») */
const CYCLE = [['coding', 'bg-primary'], ['waiting', 'bg-alert'], ['review', 'bg-blue-bg'], ['staging', 'bg-teal-light'], ['rollout', 'bg-ok']] as const

/**
 * Development › Delivery metrics (DevHub.dc.html, tab «metrics») on dev_metrics (0080), from Vercel's deployments and the
 * CI's commit times: deploy frequency, lead time, change failure rate (failed or rolled-back production deploys ÷
 * production deploys) and time to restore. A level badge only where the named DORA report's bands do not overlap
 * (logic.ts, V-V3E-22), and for the frequency only once Vercel has been heard for the whole window: history starts at
 * connection (X-V3-1), so until then the rate is per day heard and says since when (V-V3E-23). The cycle-time segments
 * need pull requests (GitHub) and stay «—». Health: bugs escaped to production (dev_bugs_get, 0079) and the running
 * sprint's capacity (dev_board_get, 0079) as the design has them; unplanned work is left out (V-V3E-24).
 */
export async function MetricsView({ nf }: DevTabProps) {
  const [m, deploys, bugs, board, t, format] = await Promise.all([loadMetrics(30), loadDeploys(), loadBugs(null), loadBoard(), getTranslations('devDelivery'), getFormatter()])
  const dur = (minutes: number | null) => {
    const p = durationParts(minutes)
    return p ? t(`units.${p.unit}`, { n: formatNumber(p.n, nf, p.unit === 'min' || Number.isInteger(p.n) ? 0 : 1) }) : '—'
  }
  const has = m.sources.deploys
  const leadHours = m.lead.n > 0 ? m.lead.median_hours : null
  const restore = m.restore.n > 0 ? m.restore.median_minutes : null
  const perDay = has ? m.deploys.per_day : null
  const since = m.since ? format.dateTime(new Date(m.since), { day: 'numeric', month: 'short' }) : null
  const tiles: { key: string; value: string; level: DoraLevel | null; sub: string }[] = [
    { key: 'frequency', value: perDay !== null ? t('metrics.perDay', { n: formatNumber(perDay, nf, perDay >= 10 || Number.isInteger(perDay) ? 0 : 1) }) : '—',
      // a level only over a window Vercel was heard for in full: a rate over two days is not a 30-day rate
      level: perDay !== null && m.complete ? doraFrequency(perDay) : null,
      sub: m.complete || !since ? t('metrics.frequencySub', { days: m.days }) : t('metrics.frequencySince', { day: since }) },
    { key: 'lead', value: dur(leadHours === null ? null : leadHours * 60), level: doraLeadTime(leadHours),
      sub: m.lead.n > 0 ? t('metrics.leadSub', { n: m.lead.n }) : t('metrics.leadNone') },
    { key: 'failure', value: m.deploys.failure_rate === null ? '—' : percent(m.deploys.failure_rate, nf), level: null,
      sub: m.deploys.finished > 0 ? t('metrics.failureSub', { bad: m.deploys.failed + m.deploys.rolled_back, n: m.deploys.finished }) : t('metrics.failureNone') },
    { key: 'restore', value: dur(restore), level: doraRestore(restore), sub: t('metrics.restoreSub', { days: m.restore.days, n: m.restore.n }) },
  ]
  const pname = (key: string) => (key === 'sentral' ? t('sentral') : deploys.products.find((p) => p.key === key)?.name ?? key)
  const escaped = bugs.kpi.escaped_30
  const goal = bugs.targets.escaped_goal
  const sprint = board.sprint

  return (
    <div className="flex flex-col gap-[14px]">
      {!has && !m.sources.ci ? (
        <div className={`${d.card} px-[18px] py-3 text-12.5 text-muted`}>
          {t('metrics.noSource')} <Link href={'/development?tab=env' as Route} className="font-semibold">{t('code.connect')}</Link>
        </div>
      ) : null}
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(170px,1fr))]">
        {tiles.map((k) => (
          <div key={k.key} className={d.kpi}>
            <div className={d.kpiLabel}>{t(`metrics.${k.key}`)}</div>
            <div className="mt-[5px] flex items-baseline gap-2">
              <span className={d.kpiValue}>{k.value}</span>
              {k.level ? <span title={t('metrics.levelTitle')} className={`rounded-999 px-2 py-[2px] text-10.5 font-bold ${LEVEL_BG[k.level]}`}>{t(`levels.${k.level}`)}</span> : null}
            </div>
            <div className="text-11.5 text-muted">{k.sub}</div>
          </div>
        ))}
      </div>
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={`${d.card} px-[18px] py-4`}>
          <b className="text-15">{t('metrics.cycle')}</b>
          <div className="mb-2 mt-3 h-6 rounded-7 bg-tile" aria-hidden />
          {CYCLE.map(([k, bg]) => (
            <div key={k} className="grid gap-[10px] py-[3px] text-12.5 [grid-template-columns:minmax(0,1fr)_auto]">
              <span className="flex min-w-0 items-center gap-[7px] whitespace-nowrap"><span className={`h-[10px] w-[10px] rounded-3 ${bg}`} />{t(`metrics.segments.${k}`)}</span>
              <b className="whitespace-nowrap">—</b>
            </div>
          ))}
          <span className="mt-1 block text-11.5 text-faint">{t('metrics.cycleNone')}</span>
        </div>
        <div className={`${d.card} flex flex-col gap-[6px] px-[18px] py-4`}>
          <b className="text-15">{t('metrics.health')}</b>
          <div className="flex justify-between gap-[10px] border-b border-tile py-[5px] text-12.5" title={t('metrics.escapedTitle', { goal })}>
            <span className="text-muted">{t('metrics.escaped')}</span>
            <b className={`whitespace-nowrap ${escaped >= goal ? 'text-warn-ink' : 'text-ink'}`}>{t('metrics.perMonth', { n: formatNumber(escaped, nf) })}</b>
          </div>
          <div className="flex justify-between border-b border-tile py-[5px] text-12.5" title={t('metrics.flagsTitle')}>
            <span className="text-muted">{t('metrics.flags')}</span><b>—</b>
          </div>
          <div className="flex justify-between gap-[10px] border-b border-tile py-[5px] text-12.5"
            title={sprint ? t('metrics.capacityTitle', { name: sprint.name }) : t('metrics.capacityNone')}>
            <span className="text-muted">{t('metrics.capacity')}</span>
            <b className={`whitespace-nowrap ${sprint && sprint.committed > 0 ? 'text-link' : 'text-ink'}`}>
              {sprint && sprint.committed > 0 ? t('metrics.points', { done: formatNumber(sprint.done, nf), committed: formatNumber(sprint.committed, nf) }) : '—'}
            </b>
          </div>
          {m.coverage.length ? m.coverage.map((c) => (
            <div key={c.product} className="flex justify-between border-b border-tile py-[5px] text-12.5">
              <span className="text-muted">{t('metrics.coverage', { app: pname(c.product) })}</span><b>{percent(c.coverage, nf)}</b>
            </div>
          )) : (
            <div className="flex justify-between border-b border-tile py-[5px] text-12.5" title={t('metrics.coverageTitle')}>
              <span className="text-muted">{t('metrics.coverageNone')}</span><b>—</b>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
