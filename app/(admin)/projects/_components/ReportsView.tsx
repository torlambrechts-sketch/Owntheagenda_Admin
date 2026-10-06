'use client'

import { useEffect, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { BoardRow, Reports } from '@/lib/data/projects'
import { dateOnly, HEALTH_TONE, type Rights } from '@/lib/data/projects-shared'
import { fetchReports } from '../actions'

type Props = { boards: BoardRow[]; boardId: string | null; rights: Rights; rev: number }

const cardCls = 'rounded-20 border border-line bg-surface px-[18px] py-4'

/**
 * Reports (Projects.dc.html v.reports): open projects per health and the median days of finished stays per phase
 * (project_reports), on one board or all, in a period; own projects only without «See reports of others». The
 * automation hooks are the engine's registry, not prose.
 */
export function ReportsView({ boards, boardId, rights, rev }: Props) {
  const t = useTranslations('projects.reports')
  const th = useTranslations('projects.health')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const [board, setBoard] = useState<string>(boardId ?? '')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [data, setData] = useState<Reports | null>(null)

  useEffect(() => {
    void fetchReports({ board: board || null, from: from || null, to: to || null }).then((r) => {
      if (r.ok) setData(r.reports)
      else flash(te(r.code))
    })
  }, [board, from, to, rev, flash, te])

  const perf = data?.performance ?? []
  const anyOpen = perf.some((p) => p.n > 0)
  const durMax = Math.max(0, ...(data?.duration ?? []).map((d) => d.median_days ?? 0))
  const byBoard = new Map<string, Reports['duration']>()
  for (const d of data?.duration ?? []) byBoard.set(d.board, [...(byBoard.get(d.board) ?? []), d])
  const day = (d: string) => format.dateTime(dateOnly(d), { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' })

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2 text-12 text-muted">
        <label className="flex items-center gap-[6px]">
          {t('board')}
          <select value={board} onChange={(e) => setBoard(e.target.value)} className="h-[30px] rounded-9 border border-line bg-surface px-2 text-12.5 font-semibold text-ink">
            <option value="">{t('allBoards')}</option>
            {boards.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </label>
        <label className="flex items-center gap-[6px]">{t('from')}<input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="h-[30px] rounded-9 border border-line bg-surface px-2 text-12.5 text-ink" /></label>
        <label className="flex items-center gap-[6px]">{t('to')}<input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="h-[30px] rounded-9 border border-line bg-surface px-2 text-12.5 text-ink" /></label>
        {data ? <span>{t('period', { from: day(data.from), to: day(data.to) })}</span> : null}
        {data?.own_only || !rights.reportsOthers ? <span className="rounded-999 bg-cream px-[10px] py-[3px] font-semibold text-amber-ink">{t('ownOnly')}</span> : null}
      </div>

      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
        <div className={cardCls}>
          <b className="text-14">{t('performance')}</b>
          {perf.map((p) => (
            <div key={p.health ?? 'none'} className="grid items-center gap-2 py-[6px] text-12.5 [grid-template-columns:110px_minmax(0,1fr)_30px]">
              <span>{p.health ? th(p.health) : th('none')}</span>
              <span className="h-[10px] overflow-hidden rounded-999 bg-tile">
                <span className={`block h-full ${p.health ? HEALTH_TONE[p.health].bar : 'bg-line-strong'}`} style={{ width: `${p.w}%` }} />
              </span>
              <b>{p.n}</b>
            </div>
          ))}
          {data && !anyOpen ? <div className="pt-1 text-12 text-muted">{t('noProjects')}</div> : null}
        </div>

        <div className={cardCls}>
          <b className="text-14">{t('duration')}</b>
          {[...byBoard.entries()].map(([bname, rows]) => (
            <div key={bname}>
              {byBoard.size > 1 ? <div className="pt-2 text-10.5 font-bold uppercase tracking-label text-muted">{bname}</div> : null}
              {rows.map((d) => (
                <div key={d.phase_id} className="grid items-center gap-2 py-[6px] text-12.5 [grid-template-columns:110px_minmax(0,1fr)_40px]">
                  <span className="truncate" title={t('stays', { count: d.n })}>{d.phase} <span className="text-faint">{d.n}</span></span>
                  <span className="h-[10px] overflow-hidden rounded-999 bg-tile">
                    <span className="block h-full bg-teal-mid" style={{ width: `${d.median_days !== null && durMax > 0 ? (d.median_days / durMax) * 100 : 0}%` }} />
                  </span>
                  <b>{d.median_days !== null ? t('days', { n: Math.round(d.median_days) }) : '—'}</b>
                </div>
              ))}
            </div>
          ))}
          {data && data.duration.length === 0 ? <div className="pt-1 text-12 text-muted">{t('noPhases')}</div> : null}
          {data ? <div className="pt-1 text-11.5 text-faint">{t('durationNote')}</div> : null}
        </div>

        <div className={`${cardCls} flex flex-col gap-[6px]`}>
          <b className="text-14">{t('hooks')}</b>
          {data ? (
            <span className="text-12.5 leading-[1.55]">
              {t('hooksLine', {
                triggers: data.hooks.triggers.map((k) => (t.has(`trigger.${k}`) ? t(`trigger.${k}`) : k)).join(', '),
                actions: data.hooks.actions.map((k) => (t.has(`action.${k}`) ? t(`action.${k}`) : k)).join(', '),
              })}
            </span>
          ) : null}
          {data && !data.hooks.actions_available ? <span className="text-12 text-muted">{t('actionsOff')}</span> : null}
        </div>
      </div>
    </div>
  )
}
