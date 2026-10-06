'use client'

import { useTranslations } from 'next-intl'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { DAY_MIN, useDur, useLabel } from './lib'
import type { Reports as ReportData, TicketConfig } from '@/lib/data/tickets'

/** Reports (Tickets.dc.html, v.reports): ticket_reports over the last 30 days; a value without a source is «—». */
export function Reports({ rep, days, config, nf }: { rep: ReportData; days: number; config: TicketConfig; nf: NumberFormat }) {
  const t = useTranslations('tickets.reports')
  const dur = useDur()
  const cat = useLabel('categories')
  const tp = useTranslations('tickets.priorities')

  const signed = (n: number) => `${n >= 0 ? '+' : '−'}${percent(Math.abs(n), nf)}`
  const breaches = rep.due - rep.met
  const kpis = [
    {
      n: t('kpi.created', { days }), v: formatNumber(rep.created, nf),
      s: rep.previous > 0 ? t('vsPrev', { delta: signed(((rep.created - rep.previous) / rep.previous) * 100) }) : t('noPrev'), c: 'text-muted',
    },
    { n: t('kpi.frt'), v: rep.median_first_response_min !== null ? dur(rep.median_first_response_min) : '—', s: t('business'), c: 'text-muted' },
    {
      n: t('kpi.resolve'),
      v: rep.median_resolution_min === null ? '—' : rep.median_resolution_min >= DAY_MIN ? t('daysValue', { v: formatNumber(rep.median_resolution_min / DAY_MIN, nf, 1) }) : dur(rep.median_resolution_min),
      s: t('business'), c: 'text-muted',
    },
    rep.due > 0
      ? { n: t('kpi.sla'), v: percent((rep.met / rep.due) * 100, nf), s: t('breaches', { n: breaches }), c: breaches ? 'text-warn-ink' : 'text-link' }
      : { n: t('kpi.sla'), v: '—', s: t('noneDue'), c: 'text-muted' },
    rep.resolved > 0
      ? { n: t('kpi.reopen'), v: percent((rep.reopened / rep.resolved) * 100, nf), s: t('ofResolved', { n: rep.resolved }), c: 'text-muted' }
      : { n: t('kpi.reopen'), v: '—', s: t('ofResolved', { n: 0 }), c: 'text-muted' },
    {
      n: t('kpi.csat'), v: rep.csat_avg !== null ? t('csatValue', { v: formatNumber(rep.csat_avg, nf, 1) }) : '—',
      s: rep.csat_requested > 0 ? t('response', { pct: percent((rep.csat_answered / rep.csat_requested) * 100, nf) }) : t('noResponse'), c: 'text-muted',
    },
  ]
  const max = Math.max(1, ...rep.by_category.map((c) => c.trial + c.customer))

  return (
    <div className="flex flex-col gap-4">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        {kpis.map((k) => (
          <div key={k.n} className="rounded-18 border border-line bg-surface px-4 py-[14px]">
            <div className="text-10.5 font-bold uppercase tracking-label text-muted">{k.n}</div>
            <div className="mt-[6px] font-serif text-24 font-semibold">{k.v}</div>
            <div className={`text-11.5 ${k.c}`}>{k.s}</div>
          </div>
        ))}
      </div>
      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className="rounded-20 border border-line bg-surface px-[22px] py-[18px]">
          <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
            <span className="text-15 font-bold">{t('volume')}</span>
            <span className="flex gap-[10px] text-11.5 text-muted">
              <span className="flex items-center gap-[5px]"><span className="h-[10px] w-[10px] rounded-3 border border-[rgba(25,21,16,.15)] bg-highlight" />{t('trial')}</span>
              <span className="flex items-center gap-[5px]"><span className="h-[10px] w-[10px] rounded-3 border border-[rgba(25,21,16,.15)] bg-ok-bg" />{t('customer')}</span>
            </span>
          </div>
          {rep.by_category.map((c) => (
            <div key={c.key} className="grid items-center gap-2 py-1 text-12.5 [grid-template-columns:150px_minmax(0,1fr)_34px]">
              <span>{cat(c.key)}</span>
              <span className="flex h-[14px] overflow-hidden rounded-5 bg-tile">
                <span className="bg-highlight" style={{ width: `${(c.trial / max) * 100}%` }} />
                <span className="bg-ok-bg" style={{ width: `${(c.customer / max) * 100}%` }} />
              </span>
              <b className="text-right">{formatNumber(c.trial + c.customer, nf)}</b>
            </div>
          ))}
          {!rep.by_category.length ? <div className="py-4 text-center text-12.5 text-muted">{t('noVolume')}</div> : null}
        </div>
        <div className="rounded-20 border border-line bg-surface px-[22px] py-[18px]">
          <div className="mb-3 text-15 font-bold">{t('frtTitle')}</div>
          {config.sla.map((s) => {
            const v = rep.frt_by_priority[s.priority] ?? null
            const tg = s.first_response_min
            const mx = Math.max(tg * 2, v ?? 0, 1)
            return (
              <div key={s.priority} className="grid items-center gap-[10px] py-[7px] text-12.5 [grid-template-columns:70px_minmax(0,1fr)_90px]">
                <b>{tp(s.priority)}</b>
                <span className="relative h-[14px] rounded-5 bg-tile">
                  {v !== null ? <span className={`absolute bottom-0 left-0 top-0 rounded-5 ${v <= tg ? 'bg-ok' : 'bg-alert'}`} style={{ width: `${(v / mx) * 100}%` }} /> : null}
                  <span className="absolute -bottom-[3px] -top-[3px] w-[2px] bg-ink" style={{ left: `${(tg / mx) * 100}%` }} />
                </span>
                <span className="text-right">{t('frtValue', { v: v !== null ? dur(v) : '—', t: dur(tg) })}</span>
              </div>
            )
          })}
          <div className="mt-2 text-11.5 text-faint">{t('frtNote')}</div>
        </div>
      </div>
    </div>
  )
}
