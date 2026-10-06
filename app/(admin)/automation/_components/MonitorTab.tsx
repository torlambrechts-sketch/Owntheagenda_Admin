'use client'

import { useState } from 'react'
import { useFormatter, useNow, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import type { Monitor, Run } from '@/lib/data/automation'
import { retryRun } from '../actions'
import { TONE, useErrorText } from './shared'

const STEP_TONE: Record<string, string> = { succeeded: TONE.ok, failed: TONE.fail, not_met: TONE.draft, skipped: TONE.draft }

/** Monitoring (Automation.dc.html, v.monitor): health, overview and run history from workflow_monitor and
 *  workflow_runs_get. With no runs every figure is zero and every list shows its empty line. */
export function MonitorTab({ monitor: m, runs, canRetry, nf }: {
  monitor: Monitor
  runs: Run[]
  canRetry: boolean
  nf: NumberFormat
}) {
  const t = useTranslations('automation.monitor')
  const flash = useToast()
  const err = useErrorText()
  const format = useFormatter()
  const now = useNow()
  const [busy, setBusy] = useState<string | null>(null)
  const n = (x: number) => formatNumber(x, nf)

  const trend = m.d14.runs === 0 ? t('trend.none') : m.d14.last7 > m.d14.prev7 * 1.1 ? t('trend.up') : m.d14.last7 < m.d14.prev7 * 0.9 ? t('trend.down') : t('trend.stable')
  const loop = m.loop_protection === 'off' ? 'off' : m.loop_protection === 'custom' ? 'custom' : 'source'
  const health = [
    { k: 'today', v: n(m.today.runs), c: 'text-ink', s: m.today.runs ? t('succeeded', { pct: percent((m.today.completed / m.today.runs) * 100, nf) }) : t('noRunsToday') },
    { k: 'd7', v: n(m.d7.runs), c: 'text-ink', s: t('failedRetried', { failed: n(m.d7.failed), retried: n(m.d7.retried) }) },
    { k: 'd14', v: n(m.d14.runs), c: 'text-ink', s: trend },
    {
      k: 'loop',
      v: t(loop === 'off' ? 'off' : 'on'),
      c: loop === 'off' ? 'text-danger' : 'text-link',
      s: t(`loop.${loop}`, { n: m.loop_protection_runs == null ? '—' : n(m.loop_protection_runs) }) + (m.loop_blocked_7d ? ` · ${t('loopBlocked', { n: n(m.loop_blocked_7d) })}` : ''),
    },
  ]
  const overview = [
    { k: 'mostFailed', items: m.most_failed.map((x) => ({ id: x.id, n: x.name, v: n(x.count), c: 'text-danger' })) },
    { k: 'mostActive', items: m.most_active.map((x) => ({ id: x.id, n: x.name, v: n(x.count), c: 'text-ink' })) },
    { k: 'neverRun', items: m.never_run.map((x) => ({ id: x.id, n: x.name, v: t(`state.${x.state}`), c: 'text-faint' })) },
  ]

  const day = (d: Date) => format.dateTime(d, { year: 'numeric', month: '2-digit', day: '2-digit' })
  const when = (iso: string) => {
    const d = new Date(iso)
    const yest = new Date(now.getTime() - 86_400_000)
    if (day(d) === day(now)) return t('today', { time: format.dateTime(d, { hour: '2-digit', minute: '2-digit' }) })
    if (day(d) === day(yest)) return t('yesterday')
    return format.dateTime(d, { day: 'numeric', month: 'short' })
  }
  // the engine's codes (wf_step) as words; anything else is the worker's own short text (a status, a timeout)
  const runError = (e: string) => (/^[a-z_]+$/.test(e) && t.has(`runErrors.${e}`) ? t(`runErrors.${e}`) : e)
  const stepTitle = (s: Run['steps'][number]) => (s.error ? runError(s.error) : t(`stepState.${s.state}`))

  const retry = async (r: Run) => {
    setBusy(r.id)
    const res = await retryRun({ id: r.id })
    setBusy(null)
    if (!res.ok) flash(err(res.code, res.detail))
    else flash(t('retried', { state: t(`runState.${res.state}`) }))
  }

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr))]">
        {health.map((h) => (
          <div key={h.k} className="rounded-18 border border-line bg-surface px-4 py-[14px]">
            <div className="text-10.5 font-bold uppercase tracking-label text-muted">{t(`health.${h.k}`)}</div>
            <div className={`mt-[6px] font-serif text-26 font-semibold ${h.c}`}>{h.v}</div>
            <div className="text-11.5 text-muted">{h.s}</div>
          </div>
        ))}
      </div>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
        {overview.map((o) => (
          <div key={o.k} className="flex flex-col gap-[6px] rounded-18 border border-line bg-surface px-4 py-[14px]">
            <b className="text-13.5">{t(`overview.${o.k}`)}</b>
            {o.items.length === 0 ? <div className="py-1 text-12.5 text-muted">{t(`overview.empty.${o.k}`)}</div> : null}
            {o.items.map((i) => (
              <div key={i.id} className="flex justify-between gap-2 border-b border-line py-1 text-12.5">
                <span>{i.n}</span><b className={i.c}>{i.v}</b>
              </div>
            ))}
          </div>
        ))}
      </div>
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-3">
          <b className="text-14">{t('history')}</b>
          <span className="text-12 text-muted">{t('historyNote')}</span>
        </div>
        {runs.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('noRuns')}</div> : null}
        <div className="overflow-x-auto">
          {runs.map((r) => (
            <div key={r.id} className="grid min-w-[720px] items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 last:border-b-0 [grid-template-columns:110px_minmax(0,1.3fr)_minmax(0,1.2fr)_minmax(0,2fr)_90px]">
              <span className="text-muted">{when(r.started_at)}</span>
              <b>{r.workflow}</b>
              <span className="text-muted">{r.subject_title ?? '—'}</span>
              <span className="flex flex-wrap gap-1">
                <span title={t('stepState.succeeded')} className={`rounded-7 px-2 py-[2px] text-11 font-bold ${TONE.ok}`}>{t('chips.trigger')}</span>
                {r.steps.map((s, i) => (
                  <span key={`${s.key}-${i}`} title={stepTitle(s)} className={`rounded-7 px-2 py-[2px] text-11 font-bold ${STEP_TONE[s.state] ?? TONE.wait}`}>
                    {t.has(`chips.${s.kind}`) ? t(`chips.${s.kind}`) : s.kind}
                  </span>
                ))}
              </span>
              {r.state === 'failed' && !r.retried && canRetry ? (
                <button type="button" disabled={busy === r.id} onClick={() => retry(r)} className="h-7 cursor-pointer rounded-9 border border-ink bg-primary text-12 font-bold disabled:opacity-60">{t('retry')}</button>
              ) : (
                <span className={`text-12 font-bold ${r.state === 'completed' ? 'text-link' : r.state === 'failed' || r.state === 'loop_blocked' ? 'text-danger' : 'text-muted'}`}>
                  {r.state === 'failed' && r.retried ? t('runState.retried') : t(`runState.${r.state}`)}
                </span>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
