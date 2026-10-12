'use client'

import { useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Results } from '@/lib/data/support-hub'
import { createArticle } from '../../support-actions'
import { card, cardHead, useSupportError, Why } from './bits'
import { csatDelta, ticketsDelta } from './logic'

// the design's session-end colours: solved by article, solved by AI answer, ticket created, left without answer
const ENDS = [['solvedArticle', 'bg-ok'], ['solvedAi', 'bg-teal-mid'], ['ticket', 'bg-warn'], ['left', 'bg-alert']] as const
const cols = '[grid-template-columns:minmax(0,1fr)_56px_76px] md:[grid-template-columns:minmax(0,1.6fr)_70px_80px_70px_90px]'

/**
 * Support results (SupportHub.dc.html, v.metrics). Tickets created and CSAT come from tickets; help sessions, self-service,
 * AI acceptance, customer effort, views, «solved» and «helpful» have no source until the widget is embedded (or a
 * decision is made) and show the design's «—» (V-V3S-04, V-V3S-05).
 */
export function ResultsView({ data, product, nf }: { data: Results; product: string; nf: NumberFormat }) {
  const t = useTranslations('supportHub.results')
  const dash = useTranslations('common')('dash')
  const td = ticketsDelta(data.tickets.created, data.tickets.previous, data.tickets.previous_complete)
  const cd = csatDelta(data.csat.avg, data.csat.previous_avg)
  const signed = (n: number, decimals = 0) => `${n > 0 ? '+' : n < 0 ? '−' : '±'}${formatNumber(Math.abs(n), nf, decimals)}`
  const kpis: { key: string; value: string; delta: string | null; good: boolean; sub: string }[] = [
    { key: 'sessions', value: dash, delta: null, good: true, sub: t('kpi.sessionsSub') },
    { key: 'selfService', value: dash, delta: null, good: true, sub: t('kpi.selfServiceSub') },
    {
      key: 'tickets', value: formatNumber(data.tickets.created, nf), delta: td ? `${signed(td.pct)} %` : null, good: td?.good ?? true,
      sub: td ? t(`kpi.tickets_${td.direction}`, { days: data.days }) : t('kpi.ticketsNoDelta'),
    },
    { key: 'aiAccepted', value: dash, delta: null, good: true, sub: t('kpi.aiAcceptedSub') },
    {
      key: 'csat', value: data.csat.avg === null ? dash : t('kpi.csatValue', { avg: formatNumber(data.csat.avg, nf, 1) }),
      delta: cd ? signed(cd.diff, 1) : null, good: cd?.good ?? true,
      sub: data.csat.answered > 0 ? t('kpi.csatSub', { n: data.csat.answered }) : t('kpi.csatNone'),
    },
    { key: 'effort', value: dash, delta: null, good: true, sub: t('kpi.effortSub') },
  ]
  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        {kpis.map((k) => (
          <div key={k.key} className="rounded-18 border border-line bg-surface px-[15px] py-[13px]">
            <div className="text-10.5 font-bold uppercase tracking-[.09em] text-muted">{t(`kpi.${k.key}`)}</div>
            <div className="mt-[5px] flex items-baseline gap-2">
              <span className="whitespace-nowrap font-serif text-23 font-semibold">{k.value}</span>
              {k.delta ? <span className={`whitespace-nowrap text-12 font-bold ${k.good ? 'text-link' : 'text-danger'}`}>{k.delta}</span> : null}
            </div>
            <div className="text-11.5 text-muted">{k.sub}</div>
          </div>
        ))}
      </div>
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
        <div className={`${card} px-5 py-4`}>
          <b className="text-15">{t('ends.title')}</b>
          <div className="mb-2 mt-3 flex h-[22px] overflow-hidden rounded-7 bg-tile" role="img" aria-label={t('ends.empty')} />
          {ENDS.map(([k, c]) => (
            <div key={k} className="flex justify-between py-[3px] text-12.5">
              <span className="flex items-center gap-[7px]"><span className={`h-[10px] w-[10px] rounded-3 ${c}`} />{t(`ends.${k}`)}</span>
              <b>{dash}</b>
            </div>
          ))}
          <Why className="mt-[6px] block">{t('ends.empty')}</Why>
        </div>
        <Gaps data={data} product={product} />
      </div>
      <div className={`${card} overflow-hidden`}>
        <div className={cardHead}><b className="text-15">{t('articles.title')}</b><span className="text-12 text-muted">{t('articles.definition')}</span></div>
        {!data.measured ? <div className="border-b border-line px-[18px] py-[9px]"><Why>{t('articles.notMeasured')}</Why></div> : null}
        {data.articles.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('articles.empty')}</div> : null}
        {data.articles.map((a) => (
          <div key={a.id} className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 tabular-nums ${cols}`}>
            <b className="[overflow-wrap:anywhere]">{a.title}</b>
            <span>{a.views === null ? dash : formatNumber(a.views, nf)}</span>
            <b className="text-muted" title={t('articles.solvedWhy')}>{dash}</b>
            <span className="hidden md:inline" title={t('articles.helpfulWhy')}>{dash}</span>
            <span className="hidden text-11.5 font-bold md:inline" />
          </div>
        ))}
      </div>
    </div>
  )
}

function Gaps({ data, product }: { data: Results; product: string }) {
  const t = useTranslations('supportHub.results')
  const flash = useToast()
  const errorText = useSupportError()
  const [done, setDone] = useState<string[]>([])
  const [pending, start] = useTransition()
  const write = (g: Results['gaps'][number]) => start(async () => {
    const r = await createArticle({ product, title: g.name, category_key: g.category_key, source: 'gap' })
    if (!r.ok) { flash(errorText(r.code)); return }
    setDone((d) => [...d, g.category_key])
    flash(t('gaps.toast'))
  })
  return (
    <div className={`${card} overflow-hidden`}>
      <div className={cardHead}><b className="text-15">{t('gaps.title')}</b><span className="text-12 text-muted">{t('gaps.period', { days: data.days })}</span></div>
      {data.gaps.length === 0 ? <div className="border-b border-line px-[18px] py-[10px] text-12.5 text-muted">{t('gaps.empty')}</div> : null}
      {data.gaps.map((g) => {
        const on = done.includes(g.category_key)
        return (
          <div key={g.category_key} className="flex items-center gap-[10px] border-b border-line px-[18px] py-[10px]">
            <span className="flex flex-1 flex-col gap-[2px]"><b className="text-13">{g.name}</b><span className="text-11.5 text-muted">{t('gaps.sub', { n: g.tickets })}</span></span>
            <button
              type="button"
              onClick={() => write(g)}
              disabled={on || pending || !data.can_write}
              title={!data.can_write ? t('gaps.why') : undefined}
              className={`h-7 cursor-pointer whitespace-nowrap rounded-8 border border-ink px-[10px] text-11.5 font-bold text-ink disabled:cursor-default ${on ? 'bg-ok-bg' : 'bg-primary'} ${!data.can_write ? 'opacity-60' : ''}`}
            >
              {on ? t('gaps.done') : t('gaps.write')}
            </button>
          </div>
        )
      })}
      <div className="px-[18px] py-[9px]"><Why>{data.can_write ? t('gaps.note') : t('gaps.why')}</Why></div>
    </div>
  )
}
