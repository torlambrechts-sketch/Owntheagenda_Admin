import Link from 'next/link'
import type { Route } from 'next'
import { getLocale, getTranslations } from 'next-intl/server'
import { formatNumber, money, type NumberFormat } from '@/lib/format'
import { outcomeRow, type Outcomes } from '@/lib/growth/playbook'
import { MODELS, growthHref } from '@/lib/growth/scope'
import { cardTable, channelColor, emptyLine, head } from '../v2kit'

const COLS = '[grid-template-columns:minmax(0,1.4fr)_90px_80px_80px_70px_90px_90px_80px]'
const th = 'text-10.5 font-bold uppercase tracking-[.08em] text-muted'

/** payback against the design's target: over 12 months is red, over 6 amber, else green */
const paybackTone = (m: number | null) => (m === null ? 'text-ink' : m > 12 ? 'text-danger' : m > 6 ? 'text-warn-ink' : 'text-link')

/**
 * Marketing campaigns › Outcomes and attribution (GrowthPlaybook.dc.html, v.outcomes) on growth_outcomes (0076): 90 days
 * of spend, signups, accounts, paying customers and MRR per channel, under the first or the last touch. Position-based and
 * data-driven models need every touch of a journey, and the product reports only the first and the last; nothing is sent
 * back to an ad platform (V-GR2-33). Without a source in the product's attribution, the account columns are «—».
 */
export async function OutcomesView({ d, nf, app }: { d: Outcomes; nf: NumberFormat; app: string }) {
  const t = await getTranslations('simpleGrowth.playbook.outcomes')
  const tc = await getTranslations('simpleGrowth.channels')
  const locale = await getLocale()
  const dash = '—'
  const kr = (v: number | null) => (v === null ? dash : money(v, nf))
  const num = (v: number | null) => (v === null ? dash : formatNumber(v, nf))
  const ch = (c: string) => (tc.has(c) ? tc(c) : c)
  const date = (iso: string) => new Intl.DateTimeFormat(locale === 'no' ? 'nb-NO' : locale, { day: 'numeric', month: 'short', timeZone: 'Europe/Oslo' }).format(new Date(iso))
  // the tracker counts signups from the day it started; a window that begins earlier says so
  const lateTracker = d.tracked_since && Date.parse(d.tracked_since) > Date.now() - d.days * 86_400_000
  const notes = [
    t('footnote', { arpa: d.arpa !== null ? money(d.arpa, nf) : dash }),
    ...(d.attributed ? [] : [t('noSource', { app })]),
    ...(d.tracked_since ? (lateTracker ? [t('trackedSince', { date: date(d.tracked_since) })] : []) : [t('noTracker')]),
  ]

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-12.5 text-muted">{t('model')}</span>
        <nav className="flex rounded-10 bg-tile p-[3px]" aria-label={t('model')}>
          {MODELS.map((m) => {
            const on = m === d.model
            return (
              <Link key={m} href={growthHref('campaigns', {}, { sub: 'outcomes', am: m }) as Route} aria-current={on ? 'true' : undefined}
                className={`cursor-pointer whitespace-nowrap rounded-7 px-[11px] py-[6px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
                {t(`models.${m}`)}
              </Link>
            )
          })}
        </nav>
        <span className="flex-1" />
        <span className="text-12 text-muted">{t('note', { days: d.days })}</span>
      </div>

      <section className={cardTable}>
        <div className="overflow-x-auto">
          <div className="min-w-[820px]">
            <div className={`grid ${COLS} gap-2 border-b border-line px-[18px] py-[9px] ${th}`}>
              <span>{t('cols.channel')}</span><span>{t('cols.spend')}</span><span>{t('cols.cps')}</span><span>{t('cols.cpa')}</span>
              <span>{t('cols.paying')}</span><span>{t('cols.cac')}</span><span>{t('cols.payback')}</span><span>{t('cols.mrr')}</span>
            </div>
            {!d.channels.length ? <p className={`m-0 border-b border-line ${emptyLine}`}>{t('empty', { days: d.days })}</p> : null}
            {d.channels.map((r) => {
              const o = outcomeRow(r, d.arpa)
              return (
                <div key={r.channel} className={`grid ${COLS} items-center gap-2 border-b border-line px-[18px] py-[10px] text-12.5 tabular-nums`}>
                  <span className="flex min-w-0 items-center gap-2">
                    <span className="h-[9px] w-[9px] flex-none rounded-3" style={{ background: channelColor(r.channel) }} />
                    <b className="truncate">{ch(r.channel)}</b>
                  </span>
                  <span>{r.spend ? kr(r.spend) : dash}</span>
                  <span>{kr(o.cps)}</span>
                  <span>{kr(o.cpa)}</span>
                  <b>{num(r.paying)}</b>
                  <b className={o.payback !== null && o.payback > 12 ? 'text-danger' : ''}>{kr(o.cac)}</b>
                  <span className={`font-bold ${paybackTone(o.payback)}`}>{o.payback !== null ? t('months', { n: formatNumber(o.payback, nf, 1) }) : dash}</span>
                  <span>{r.mrr !== null ? kr(r.mrr) : dash}</span>
                </div>
              )
            })}
          </div>
        </div>
        {notes.map((n, i) => <div key={i} className={`px-[18px] text-11.5 text-muted ${i === 0 ? 'py-[10px]' : 'pb-[10px]'}`}>{n}</div>)}
      </section>

      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('journeys')}</b>
          <span className="text-12 text-muted">{t('journeysNote', { days: d.days })}</span>
        </div>
        {d.journeys === null ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('journeysNoSource', { app })}</p> : null}
        {d.journeys && !d.journeys.length ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('journeysEmpty', { days: d.days })}</p> : null}
        {(d.journeys ?? []).map((j) => {
          const steps = [ch(j.first), ...(j.last !== j.first ? [ch(j.last)] : []), t('signup')]
          return (
            <div key={`${j.first}>${j.last}`} className="flex flex-wrap items-center gap-[10px] border-b border-line px-[18px] py-[11px] last:border-b-0">
              <span className="flex flex-[1_1_380px] flex-wrap items-center gap-1">
                {steps.map((s, i) => (
                  <span key={i} className="flex items-center gap-1">
                    <span className={`whitespace-nowrap rounded-999 px-[10px] py-1 text-12 font-semibold ${i === steps.length - 1 ? 'bg-primary' : 'bg-tile'}`}>{s}</span>
                    {i < steps.length - 1 ? <span className="text-faint">→</span> : null}
                  </span>
                ))}
              </span>
              <span className="whitespace-nowrap text-12.5">
                {t.rich('journeyRow', { n: j.paying, days: j.days ?? dash, b: (x) => <b>{x}</b> })}
              </span>
            </div>
          )
        })}
      </section>
    </div>
  )
}
