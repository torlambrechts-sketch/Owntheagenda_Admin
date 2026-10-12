import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { ctr, fatigue, type GrowthAds } from '@/lib/growth/ads'
import { growthHref } from '@/lib/growth/scope'
import { cardTable, head } from '../v2kit'
import { CampaignLink } from '../ads/CampaignLink'

const TONE = { fatigued: 'text-danger', healthy: 'text-link', quiet: 'text-muted' } as const
const STATUS_TONE = { live: 'text-link', paused: 'text-warn-ink', ended: 'text-muted' } as const

/**
 * Marketing campaigns › Creative and landing pages (GrowthPlaybook.dc.html, v.creative). With an ad platform connected
 * (0077): the ads with their click-through over the last seven days against the seven before, fatigued when it fell 30 %
 * or more on enough impressions, and the platform campaigns with the Sentral campaign each counts as. The message matrix
 * needs ads tagged by pain point and persona, and landing page tests an A/B tool; neither exists, and the view says so
 * (V-GR2-37, V-GR2-42). Without a connection it says where to connect one.
 */
export async function CreativeView({ ads, nf, canLink }: { ads: GrowthAds | null; nf: NumberFormat; canLink: boolean }) {
  const t = await getTranslations('simpleGrowth.playbook.creative')
  const ta = await getTranslations('simpleGrowth.ads')
  const connected = !!ads?.providers.some((p) => p.status === 'connected')
  const dash = '—'
  const pc = (v: number | null) => (v === null ? dash : percent(v * 100, nf))
  const cur = (v: number, c: string | null) => money(v, nf, c ?? 'NOK')

  if (!ads || !connected || (!ads.campaigns.length && !ads.ads.length)) {
    return (
      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('title')}</b>
          <span className="text-12 text-muted">{connected ? t('noData') : t('note')}</span>
        </div>
        <div className="flex flex-col gap-2 px-[18px] py-[14px] text-12.5 leading-[1.5] text-muted">
          <p className="m-0">{t.rich(connected ? 'linkAccounts' : 'connectFirst', { link: (x) => <Link href={growthHref('integrations', {}) as Route}>{x}</Link> })}</p>
          <p className="m-0">{t.rich('today', { link: (x) => <Link href={growthHref('pages', {}) as Route}>{x}</Link> })}</p>
        </div>
      </section>
    )
  }

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
        <section className={cardTable}>
          <div className={head}>
            <b className="text-15">{t('variants')}</b>
            <span className="text-12 text-muted">{t('fatigueRule')}</span>
          </div>
          {!ads.ads.length ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('noAds')}</p> : null}
          {ads.ads.slice(0, 30).map((a) => {
            const f = fatigue(a)
            return (
              <div key={a.id} className="flex items-center gap-[10px] border-b border-line px-[18px] py-[10px]">
                <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
                  <b className="text-12.5 leading-[1.3] [overflow-wrap:anywhere]">{a.headline ?? a.name ?? dash}</b>
                  <span className="text-11.5 text-muted">
                    {ta(`names.${a.provider}`)}{a.campaign ? ` · ${a.campaign}` : ''} · {t('ctr', { v: pc(f.ctr) })} · {t('impressions', { n: formatNumber(a.last7.impressions, nf) })}
                    {f.frequency !== null ? ` · ${t('frequency', { v: formatNumber(f.frequency, nf, 1) })}` : ''}
                  </span>
                </span>
                <span className={`whitespace-nowrap text-11.5 font-bold ${TONE[f.state]}`}
                  title={f.change !== null ? t('changeTitle', { now: pc(f.ctr), prev: pc(f.prev) }) : undefined}>
                  {t(`states.${f.state}`)}{f.state === 'fatigued' && f.change !== null ? ` ${percent(f.change * 100, nf)}` : ''}
                </span>
              </div>
            )
          })}
        </section>

        <section className={cardTable}>
          <div className={head}>
            <b className="text-15">{t('campaigns')}</b>
            <span className="text-12 text-muted">{t('campaignsNote')}</span>
          </div>
          {ads.campaigns.map((c) => (
            <div key={c.id} className="flex flex-col gap-[6px] border-b border-line px-[18px] py-[11px]">
              <div className="flex items-start justify-between gap-[10px]">
                <span className="flex min-w-0 flex-col">
                  <b className="text-13 [overflow-wrap:anywhere]">{c.name}</b>
                  <span className="text-11.5 text-muted">{ta(`names.${c.provider}`)} · {c.account}</span>
                </span>
                <span className={`whitespace-nowrap text-11.5 font-bold ${STATUS_TONE[c.status]}`}>{t(`status.${c.status}`)}</span>
              </div>
              <span className="text-12 text-ink-2">
                {t('d30', { impressions: formatNumber(c.d30.impressions, nf), clicks: formatNumber(c.d30.clicks, nf), ctr: pc(ctr(c.d30.clicks, c.d30.impressions)),
                            spend: cur(c.d30.spend, c.currency), conversions: c.d30.conversions === null ? dash : formatNumber(c.d30.conversions, nf, Number.isInteger(c.d30.conversions) ? 0 : 1) })}
              </span>
              <span className="flex flex-wrap items-center gap-2 text-11.5 text-muted">
                {t('countsAs')}
                {canLink ? (
                  <CampaignLink id={c.id} value={c.linked_by_hand ? c.ad_campaign_id : null} options={ads.sentral_campaigns} label={t('countsAsLabel', { name: c.name })}
                    auto={c.ad_campaign && !c.linked_by_hand ? t('auto', { name: c.ad_campaign }) : t('autoNone')} />
                ) : <b className="text-ink">{c.ad_campaign ?? dash}</b>}
                {c.currency && c.currency !== 'NOK' ? <span>{ta('notNok')}</span> : null}
              </span>
            </div>
          ))}
        </section>
      </div>
      <p className="m-0 text-12 text-muted">{t('matrixNone')}</p>
    </div>
  )
}
