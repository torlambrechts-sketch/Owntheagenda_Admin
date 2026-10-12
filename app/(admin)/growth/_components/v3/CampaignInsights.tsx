'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { formatNumber, money, type NumberFormat } from '@/lib/format'
import { CPS_RED, adRows, barMode, campaignTips, dailyBars, rowCps, type CampaignDetail, type CampaignTip } from '@/lib/growth/v3'
import { TipBox } from './TipBox'

const label = 'text-11 font-bold uppercase tracking-[.1em] text-muted'
const ROW = '[grid-template-columns:minmax(0,1.4fr)_56px_50px_70px]'

/**
 * The campaign card's three new blocks (GrowthMarketing.dc.html, between «Budget used» and «Tracking link»): the 21 days
 * of spend and signups with the day line, the ads and keywords of its platform campaigns, and the tips. Spend per day
 * comes only from an ad platform; typed spend is per month and the treatment says so. Signups are the website tracker's
 * completed signups with the campaign's link. Every tip opens the platform where the change is made (X-V3-3).
 */
export function CampaignInsights({ d, state, nf }: { d: CampaignDetail | null; state: 'ready' | 'loading' | 'failed'; nf: NumberFormat }) {
  const t = useTranslations('simpleGrowth.v3')
  const ta = useTranslations('simpleGrowth.ads')
  const format = useFormatter()
  const [cday, setCday] = useState<string | null>(null)

  if (!d) {
    return (
      <>
        <div className={label}>{t('daily.title')}</div>
        <div className="text-12 text-muted">{state === 'failed' ? t('daily.failed') : t('daily.loading')}</div>
      </>
    )
  }

  const mode = barMode(d)
  const bars = dailyBars(d)
  const cur = d.currency ?? 'NOK'
  const kr = (v: number | null) => (v === null ? '—' : money(v, nf, cur))
  // «Sun 11 Oct», put together from its parts: a whole-date pattern differs between the server's ICU and the browser's
  const dayName = (day: string) => {
    const at = new Date(`${day}T12:00:00Z`)
    return `${t(`dow.${at.getUTCDay() === 0 ? 7 : at.getUTCDay()}`)} ${at.getUTCDate()} ${format.dateTime(at, { month: 'short', timeZone: 'UTC' })}`
  }
  const picked = bars.find((b) => b.day === cday) ?? null
  const rows = adRows(d)
  const tips = campaignTips(d)
  const platform = d.platforms.length > 0
  const names = [...new Set(d.platforms.map((p) => ta(`names.${p.provider}`)))].join(', ')
  const ratioText = (r: number) => formatNumber(Math.round(r * 10) / 10, nf, Number.isInteger(Math.round(r * 10) / 10) ? 0 : 1)

  const tipText = (x: CampaignTip) => {
    if (x.kind === 'best') return t('tips.bestKeyword', { name: x.name, cps: kr(x.cps), rest: kr(x.restCps) })
    const kw = x.level === 'keyword'
    if (x.ratio === null) {
      return t(kw ? 'tips.dearKeywordNone' : 'tips.dearAdNone', { name: x.name, clicks: formatNumber(x.clicks, nf), days: d.days_n, rest: kr(x.restCps) })
    }
    return t(kw ? 'tips.dearKeyword' : 'tips.dearAd', { name: x.name, ratio: ratioText(x.ratio), cps: kr(x.cps), rest: kr(x.restCps) })
  }
  const tipCta = (x: CampaignTip) => {
    const platformName = ta(`names.${x.provider}`)
    return x.kind === 'best' ? t('tips.raise', { platform: platformName }) : x.level === 'keyword' ? t('tips.pause', { platform: platformName }) : t('tips.open', { platform: platformName })
  }

  const barTitle = (b: (typeof bars)[number]) => {
    const date = dayName(b.day)
    if (d.starts_on && b.day < d.starts_on) return t('daily.beforeStart', { date })
    return t('daily.tip', { date, spend: kr(b.spend), n: b.signups })
  }

  return (
    <>
      <div className={label}>{t('daily.title')}</div>
      <div role="group" aria-label={t('daily.group', { from: dayName(d.from), to: dayName(d.to) })} className="flex h-20 items-end gap-[3px] border-b border-line-strong">
        {bars.map((b) => {
          if (b.empty) return <span key={b.day} className="h-full flex-1" title={barTitle(b)} aria-hidden="true" />
          const on = cday === b.day
          const tip = barTitle(b)
          return (
            <button
              key={b.day}
              type="button"
              onClick={() => setCday(on ? null : b.day)}
              title={tip}
              aria-label={tip}
              aria-pressed={on}
              className="flex h-full min-w-0 flex-1 cursor-pointer flex-col justify-end border-0 bg-transparent p-0"
            >
              {b.h === null ? (
                // signups alone: no spend bar is drawn
                <span className="relative block h-full">
                  <span className={`absolute inset-x-1/4 bottom-0 ${on ? 'bg-primary' : 'bg-link'}`} style={{ height: `${b.sh}%` }} />
                </span>
              ) : (
                <span className={`relative block rounded-t-[3px] ${on ? 'bg-primary' : 'bg-sand'}`} style={{ height: `${b.h}%` }}>
                  <span className="absolute inset-x-1/4 bottom-0 bg-link" style={{ height: `${b.sh}%` }} />
                </span>
              )}
            </button>
          )
        })}
      </div>
      {picked ? (
        <div className="rounded-10 border border-line bg-canvas px-[10px] py-2 text-12" aria-live="polite">
          {picked.spend !== null && picked.signups > 0
            ? t('daily.lineCps', { date: dayName(picked.day), spend: kr(picked.spend), n: picked.signups, cps: kr(picked.spend / picked.signups) })
            : t('daily.line', { date: dayName(picked.day), spend: kr(picked.spend), n: picked.signups })}
        </div>
      ) : null}
      <div className="-mt-1 flex flex-col gap-[2px] text-11.5 text-muted">
        {mode === 'signups' ? <span>{d.spend_source === 'platform' ? t('daily.mixed') : t('daily.typed')}</span> : null}
        {mode === 'platform' && d.time_zones.length ? <span>{t('daily.timeZone', { zones: d.time_zones.join(', ') })}</span> : null}
        <span>{d.tracked ? t('daily.signupsSource') : t('daily.noTracker')}</span>
      </div>

      {platform ? (
        <>
          <div className={label}>{t('ads.title')}</div>
          {rows.length ? (
            <div role="table" aria-label={t('ads.title')} className="flex flex-col gap-3">
              <div role="row" className="sr-only">
                <span role="columnheader">{t('ads.cols.name')}</span><span role="columnheader">{t('ads.cols.clicks')}</span>
                <span role="columnheader">{t('ads.cols.signups')}</span><span role="columnheader">{t('ads.cols.cps')}</span>
              </div>
              {rows.map((r) => {
                const cps = rowCps(r)
                const red = cps !== null && r.currency === 'NOK' && cps > CPS_RED
                return (
                  <div key={`${r.kind}:${r.account}:${r.id}`} role="row" className={`grid items-center gap-2 border-b border-tile py-[5px] text-12 tabular-nums ${ROW}`}>
                    <span role="cell" className="overflow-hidden text-ellipsis whitespace-nowrap" title={r.name}><b>{r.kind === 'keyword' ? t('ads.keyword', { text: r.name }) : r.name}</b></span>
                    <span role="cell">{formatNumber(r.clicks, nf)}</span>
                    <span role="cell">{r.signups === null ? '—' : formatNumber(r.signups, nf)}</span>
                    <b role="cell" className={red ? 'text-danger' : 'text-link'}>{cps === null ? '—' : money(cps, nf, r.currency ?? cur)}</b>
                  </div>
                )
              })}
            </div>
          ) : <div className="text-12 text-muted">{t('ads.none', { days: d.days_n })}</div>}
          <div className="-mt-1 flex flex-col gap-[2px] text-11.5 text-muted">
            {rows.length ? <span>{t('ads.note', { days: d.days_n, platforms: names })}</span> : null}
            {rows.some((r) => r.signups === null) ? <span>{t('ads.convention')}</span> : null}
          </div>
        </>
      ) : null}

      {tips.map((x) => (
        <TipBox key={x.key} text={tipText(x)} cta={tipCta(x)} href={x.url} title={t('tips.linkTitle', { platform: ta(`names.${x.provider}`) })} />
      ))}
    </>
  )
}
