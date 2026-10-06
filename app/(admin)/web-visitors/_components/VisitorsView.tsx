'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { ui } from '@/components/ui/styles'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { recordHref } from '@/lib/records-href'
import { CHANNELS, PERIODS, lastVisit, onPage, type Visitor, type Visitors } from '@/lib/data/capture-shared'
import { useErr, useGo } from '../../lead-capture/_components/hooks'
import { convertVisitor } from '../actions'

export type VisitorFilters = { days: number; crm: 'yes' | 'no' | null; campaign: string | null; page: string | null }
const COLS = '[grid-template-columns:40px_minmax(0,1.4fr)_130px_110px_90px_60px]'
const action = 'h-8 cursor-pointer rounded-9 border px-[11px] text-12 disabled:cursor-default disabled:opacity-50'

/**
 * Web visitors (Marketing.dc.html, v.visitors): companies visiting the tracked sites, most active first (WEB-03),
 * and one company's visits with Create lead / deal / organization (WEB-04). Company level only (D-37). Without the
 * IP-to-company provider no company is named: the not-connected state, never a sample company (D-41).
 */
export function VisitorsView({ data, visitor, filters, canConvert, prospects, nf, now }: {
  data: Visitors; visitor: Visitor | null; filters: VisitorFilters; canConvert: boolean; prospects: boolean; nf: NumberFormat; now: string
}) {
  const t = useTranslations('capture.visitors')
  const tc = useTranslations('capture.channels')
  const fmt = useFormatter()
  const { go } = useGo()
  const sel = visitor?.org_number ?? null
  const channel = (c: string | null) => (c ? ((CHANNELS as readonly string[]).includes(c) ? tc(c) : c) : '—')
  const when = (iso: string) => {
    const w = lastVisit(iso, new Date(now))
    return w.key === 'date' ? fmt.dateTime(new Date(iso), { day: 'numeric', month: 'short' }) : t(`time.${w.key}`, { n: w.n })
  }
  const loc = (city: string | null, country: string | null) => [city, country].filter(Boolean).join(', ') || '—'
  const seen = data.sites

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-[10px] text-12 text-muted">
        <span className={`rounded-999 px-[11px] py-[5px] font-bold ${seen.length ? 'bg-ok-bg text-ok-ink' : 'bg-tile text-ink'}`}>
          {seen.length ? t('trackerOn', { n: seen.length }) : t('trackerNone')}
        </span>
        {seen.length ? <span>{seen.map((s) => s.hostname.replace(/^www\./, '')).join(' · ')}</span> : null}
        {data.connected ? <span>· {t('filtered')}</span> : null}
        <span>· {t(data.identification === 'on' ? 'identOn' : 'identOff')}</span>
      </div>

      <Filters filters={filters} onChange={(patch) => go({ ...patch, org: null })} />

      <div className={`grid grid-cols-1 items-start gap-[14px] ${visitor ? 'lg:[grid-template-columns:minmax(0,1fr)_minmax(280px,340px)]' : ''}`}>
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className="overflow-x-auto">
            <div className="min-w-[620px]">
              <div className={`grid gap-[10px] border-0 border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${COLS}`}>
                <span>{t('col.rank')}</span><span>{t('col.company')}</span><span title={t('col.locationNote')}>{t('col.location')}</span>
                <span>{t('col.source')}</span><span>{t('col.last')}</span><span>{t('col.pages')}</span>
              </div>
              {data.rows.map((w, i) => (
                <button
                  key={w.org_number}
                  type="button"
                  onClick={() => go({ org: w.org_number })}
                  aria-current={w.org_number === sel ? 'true' : undefined}
                  className={`grid w-full cursor-pointer items-center gap-[10px] border-0 border-b border-line px-4 py-[10px] text-left text-12.5 ${COLS} ${w.org_number === sel ? 'bg-highlight' : 'bg-transparent'}`}
                >
                  <span className={`flex h-[26px] w-[26px] items-center justify-center rounded-8 text-12 font-bold ${i < 2 ? 'bg-primary' : 'bg-tile'}`}>{w.rank}</span>
                  <span className="flex min-w-0 flex-col"><b>{w.name ?? w.org_number}</b><span className="text-11.5 text-muted">{w.industry ?? '—'}</span></span>
                  <span>{loc(w.city, w.country)}</span>
                  <span className="text-muted">{channel(w.source)}</span>
                  <span className="text-muted">{when(w.last_visit)}</span>
                  <b>{formatNumber(w.pages, nf)}</b>
                </button>
              ))}
            </div>
          </div>
          {data.rows.length === 0 ? (
            <div className="flex flex-col gap-1 px-4 py-6 text-12.5">
              {data.identification !== 'on' ? (
                <><b>{t('empty.offTitle')}</b><span className="text-muted">{t('empty.off')}</span></>
              ) : !data.connected ? (
                <><b>{t('empty.notConnectedTitle')}</b><span className="text-muted">{t('empty.notConnected')}</span></>
              ) : (
                <><b>{t('empty.noneTitle')}</b><span className="text-muted">{t('empty.none', { days: filters.days })}</span></>
              )}
            </div>
          ) : !data.connected ? (
            <div className="px-4 py-3 text-11.5 text-faint">{t('notConnectedNote')}</div>
          ) : null}
        </div>
        {visitor ? <Detail key={visitor.org_number} v={visitor} canConvert={canConvert} prospects={prospects} channel={channel} /> : null}
      </div>
    </div>
  )
}

function Filters({ filters, onChange }: { filters: VisitorFilters; onChange: (patch: Record<string, string | null>) => void }) {
  const t = useTranslations('capture.visitors.filters')
  const [campaign, setCampaign] = useState(filters.campaign ?? '')
  const [page, setPage] = useState(filters.page ?? '')
  const field = 'h-[30px] rounded-9 border border-line bg-canvas px-[9px] text-12 text-ink'
  return (
    <div className="flex flex-wrap items-center gap-[6px] text-12 text-muted" role="group" aria-label={t('label')}>
      {PERIODS.map((d) => (
        <button key={d} type="button" aria-pressed={filters.days === d} onClick={() => onChange({ days: d === 30 ? null : String(d) })} className={ui.pillSoft(filters.days === d)}>
          {t(`days.${d}`)}
        </button>
      ))}
      <span className="ml-2">{t('inCrm')}</span>
      {([null, 'yes', 'no'] as const).map((c) => (
        <button key={c ?? 'all'} type="button" aria-pressed={filters.crm === c} onClick={() => onChange({ crm: c })} className={ui.pillSoft(filters.crm === c)}>
          {t(`crm.${c ?? 'all'}`)}
        </button>
      ))}
      <form className="flex flex-wrap gap-[6px]" onSubmit={(e) => { e.preventDefault(); onChange({ campaign: campaign.trim() || null, page: page.trim() || null }) }}>
        <input value={campaign} onChange={(e) => setCampaign(e.target.value)} placeholder={t('campaign')} aria-label={t('campaign')} maxLength={120} className={`${field} w-[150px]`} />
        <input value={page} onChange={(e) => setPage(e.target.value)} placeholder={t('page')} aria-label={t('page')} maxLength={200} className={`${field} w-[150px]`} />
        <button type="submit" className={ui.btnSmall}>{t('apply')}</button>
      </form>
    </div>
  )
}

function Detail({ v, canConvert, prospects, channel }: { v: Visitor; canConvert: boolean; prospects: boolean; channel: (c: string | null) => string }) {
  const t = useTranslations('capture.visitors')
  const err = useErr()
  const flash = useToast()
  const [busy, start] = useTransition()
  const [made, setMade] = useState<{ entity: 'lead' | 'deal' | 'organization'; id: string } | null>(null)
  const convert = (kind: 'lead' | 'deal' | 'organization') => start(async () => {
    const r = await convertVisitor({ org: v.org_number, kind })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t(`converted.${kind}`))
    if (r.id) setMade({ entity: r.entity, id: r.id })
  })
  const shown = v.pageviews.slice(0, 12)
  const loc = [v.city, v.country].filter(Boolean).join(', ')
  return (
    <div className="flex flex-col gap-[10px] rounded-20 border border-ink bg-surface px-[18px] py-4">
      <b className="font-serif text-19">{v.name ?? v.org_number}</b>
      <span className="text-12 text-muted">
        {[v.industry, loc ? t('registered', { loc }) : null, t(v.in_crm ? 'inCrm' : 'notInCrm'), t('visits30', { n: v.visits_30d })].filter(Boolean).join(' · ')}
      </span>
      <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('history')}</div>
      {shown.map((h, i) => {
        const o = onPage(h.seconds)
        return (
          <div key={`${h.at}-${i}`} className="flex justify-between gap-2 border-0 border-b border-line py-1 text-12" title={channel(h.channel)}>
            <span className="min-w-0 break-all font-mono">{h.path}</span>
            <span className="shrink-0 text-muted">{o.key === 'none' ? '—' : t(`onPage.${o.key}`, { n: o.n })}</span>
          </div>
        )
      })}
      {v.pageviews.length > shown.length ? <span className="text-11.5 text-muted">{t('morePages', { n: v.pageviews.length - shown.length })}</span> : null}
      <div className="flex flex-wrap gap-[6px]">
        {canConvert ? (
          <>
            <button type="button" disabled={busy} onClick={() => convert('lead')} className={`${action} border-ink bg-primary font-bold`}>{t('createLead')}</button>
            <button type="button" disabled={busy} onClick={() => convert('deal')} className={`${action} border-line bg-transparent font-semibold`}>{t('createDeal')}</button>
            {v.in_crm && v.organization_id ? null : (
              <button type="button" disabled={busy} onClick={() => convert('organization')} className={`${action} border-line bg-transparent font-semibold`}>{t('createOrg')}</button>
            )}
          </>
        ) : null}
        {v.in_crm && v.organization_id ? (
          <Link href={recordHref('organization', v.organization_id) as Route} className={`${action} inline-flex items-center border-line bg-transparent font-semibold text-ink hover:text-ink hover:no-underline`}>{t('openOrg')}</Link>
        ) : null}
        {prospects ? (
          <Link
            href={`/lead-capture?tab=prospect&kw=${encodeURIComponent(v.website ?? v.name ?? v.org_number)}` as Route}
            className={`${action} inline-flex items-center border-line bg-transparent font-semibold text-ink hover:text-ink hover:no-underline`}
          >
            {t('findPeople')}
          </Link>
        ) : null}
      </div>
      {made ? (
        <Link href={recordHref(made.entity, made.id) as Route} className="text-12 font-semibold">{t(`open.${made.entity}`)}</Link>
      ) : null}
      <span className="text-11.5 text-faint">{t('linkNote')}</span>
    </div>
  )
}
