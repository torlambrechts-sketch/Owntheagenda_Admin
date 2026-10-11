'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useLocale, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { growthHref, LOG_FILTERS, type LogFilter, type Scope } from '@/lib/growth/scope'
import type { LogRow } from '@/lib/growth/types'
import { colHead, mono } from './v2kit'

const COLS = '[grid-template-columns:110px_80px_minmax(0,1fr)_80px_minmax(0,1.3fr)_minmax(0,1.3fr)]'
const fmtTime = (iso: string, locale = 'en') => {
  const d = new Date(iso)
  const day = new Intl.DateTimeFormat(locale === 'no' ? 'nb-NO' : locale, { day: 'numeric', month: 'short', timeZone: 'Europe/Oslo' }).format(d)
  const time = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'Europe/Oslo' }).format(d)
  return { day, time }
}

/**
 * The signup log (SimpleGrowth.dc.html, log[]): the scope's visits, newest first, how far each got, and its trail of pages
 * and presses. A visit is a daily-salted hash shown by four characters; it never carries a person or an account (D-37).
 * Export CSV writes the rows on screen, which hold no personal data.
 */
export function SignupLog({ rows, total, step, filter, scope, scopeLabel }: {
  rows: LogRow[]; total: number; step: number; filter: LogFilter; scope: Scope; scopeLabel: string
}) {
  const t = useTranslations('simpleGrowth.funnel.log')
  const ts = useTranslations('simpleGrowth.funnel.steps')
  const tc = useTranslations('simpleGrowth.channels')
  const tsc = useTranslations('simpleGrowth.scope.devices')
  const flash = useToast()
  const locale = useLocale()
  const [open, setOpen] = useState<string | null>(null)
  const [limit, setLimit] = useState(25)
  const shown = rows.filter((r) => (filter === 'stopped' ? r.reached === step : filter === 'account' ? r.reached >= 5 : true))
  const reachedText = (r: LogRow) => (r.reached >= 5 ? t('finished') : t('stopped', { step: ts(String(r.reached)) }))
  const dot = (r: LogRow) => (r.reached >= 5 ? '#E0A21F' : r.reached >= 4 ? '#E0A21F' : '#D4633A')
  const dev = (d: string) => (tsc.has(d) ? tsc(d) : '—')
  // the channel's name, as the design writes it; the referrer or utm source is the hover
  const src = (r: LogRow) => (tc.has(r.channel) ? tc(r.channel) : r.channel)

  const exportCsv = () => {
    const head = ['time', 'visitor', 'source', 'channel', 'device', 'landing_page', 'reached_step', 'seconds']
    const esc = (v: string | number | null) => (v === null ? '' : /[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v))
    const lines = [head.join(','), ...shown.map((r) => [r.at, r.visitor, r.source, r.channel, r.device, r.entry, r.reached, r.seconds].map(esc).join(','))]
    const url = URL.createObjectURL(new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a')
    a.href = url
    a.download = 'signup-log.csv'
    a.click()
    URL.revokeObjectURL(url)
    flash(t('exported', { count: shown.length }))
  }

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-3">
        <b className="text-15">{t('title', { scope: scopeLabel })}</b>
        <span className="flex flex-wrap items-center gap-[6px]">
          {LOG_FILTERS.map((f) => {
            const on = f === filter
            return (
              <Link key={f} href={growthHref('funnel', scope, { step, lf: f }) as Route} aria-current={on ? 'true' : undefined}
                className={`cursor-pointer whitespace-nowrap rounded-999 border px-[11px] py-[5px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
                {t(`filters.${f}`)}
              </Link>
            )
          })}
          <button type="button" onClick={exportCsv} disabled={shown.length === 0}
            className="h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold text-ink">
            {t('export')}
          </button>
        </span>
      </div>
      <div className="overflow-x-auto">
        <div className="min-w-[700px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] ${colHead} ${COLS}`}>
            <span>{t('cols.time')}</span><span>{t('cols.visitor')}</span><span>{t('cols.source')}</span><span>{t('cols.device')}</span><span>{t('cols.page')}</span><span>{t('cols.reached')}</span>
          </div>
          {shown.slice(0, limit).map((r) => {
            const id = `${r.at}${r.visitor}`
            const on = open === id
            const { day, time } = fmtTime(r.at, locale)
            const t0 = new Date(r.at).getTime()
            return (
              <div key={id} className="border-b border-line">
                <button type="button" onClick={() => setOpen(on ? null : id)} aria-expanded={on}
                  className={`grid w-full cursor-pointer items-center gap-[10px] border-none px-[18px] py-2 text-left text-12.5 text-ink ${COLS} ${on ? 'bg-highlight' : 'bg-transparent'}`}>
                  <span className="whitespace-nowrap tabular-nums">{day} {time}</span>
                  <span className={`${mono} text-11.5`}>{r.visitor}</span>
                  <span className="overflow-hidden text-ellipsis whitespace-nowrap" title={r.source ?? undefined}>{src(r)}</span>
                  <span>{dev(r.device)}</span>
                  <span className={`overflow-hidden text-ellipsis whitespace-nowrap ${mono} text-11.5`}>{r.entry ?? '—'}</span>
                  <span className="flex min-w-0 items-center gap-[6px]">
                    <span className="h-2 w-2 flex-none rounded-999" style={{ background: dot(r) }} />
                    <span className="overflow-hidden text-ellipsis whitespace-nowrap font-semibold">{reachedText(r)}</span>
                  </span>
                </button>
                {on ? (
                  <div className="flex flex-col gap-1 pb-3 pl-[128px] pr-[18px] pt-1">
                    {r.trail.map((e, i) => {
                      const secs = Math.max(0, Math.round((new Date(e.at).getTime() - t0) / 1000))
                      const at = fmtTime(e.at).time
                      return (
                        <div key={i} className="grid gap-[10px] text-12 [grid-template-columns:60px_minmax(0,1fr)]">
                          <span className={`${mono} text-faint`} title={t('secondsIn', { s: secs })}>{at}</span>
                          <span className="text-ink [overflow-wrap:anywhere]">
                            <b className={`${mono} text-11.5`}>{e.kind === 'view' ? 'page_view' : e.name}</b>{' '}
                            {e.kind === 'view' ? e.path : [e.value, e.path].filter(Boolean).join(' · ')}
                          </span>
                        </div>
                      )
                    })}
                    {r.reached < 5 ? (
                      <div className="grid gap-[10px] text-12 [grid-template-columns:60px_minmax(0,1fr)]">
                        <span className={`${mono} text-faint`}>—</span>
                        <span className="text-danger"><b className={`${mono} text-11.5`}>stopped</b> {r.exit ? t('leftOn', { path: r.exit }) : ''}</span>
                      </div>
                    ) : null}
                  </div>
                ) : null}
              </div>
            )
          })}
          {shown.length === 0 ? <div className="p-6 text-center text-13 text-muted">{t('none')}</div> : null}
          {shown.length > limit ? (
            <button type="button" onClick={() => setLimit((n) => n + 25)} className="w-full cursor-pointer border-none bg-transparent px-[18px] py-[10px] text-left text-12.5 font-semibold text-link">
              {t('showMore', { n: Math.min(25, shown.length - limit) })}
            </button>
          ) : total > rows.length ? <div className="px-[18px] py-[10px] text-12 text-muted">{t('more', { shown: rows.length, total })}</div> : null}
        </div>
      </div>
    </div>
  )
}
