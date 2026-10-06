import Link from 'next/link'
import { getTranslations } from 'next-intl/server'
import type { Attribution as AttributionData } from '@/lib/data/analytics'
import { money, formatNumber, type NumberFormat } from '@/lib/format'
import { GoButton } from './nav'
import { Empty, cardTable, colHead } from './kit'

// the design's channel colours (Analytics.dc.html, attr), by the channel keys of channel_rules
const COLOR: Record<string, string> = {
  organic_search: '#5C9A55', paid_search: '#E0A21F', social: '#6E8FB8', partner: '#8F74B3', paid_social: '#D4633A', email: '#9DB8B3', direct: '#C4BCA8',
}
const COLS = '[grid-template-columns:minmax(0,1.3fr)_repeat(6,minmax(70px,1fr))]'

/**
 * Attribution (Analytics.dc.html, v.attribution) on analytics_attribution: per channel, signups, activated,
 * paid, MRR won, the spend people entered and CAC = spend ÷ paid. Without spend there is no CAC. Last touch
 * needs Orgpuls to send it; until it does, the tab says so instead of showing first touch twice.
 */
export async function Attribution({ d, canSpend, nf, webHref }: { d: AttributionData; canSpend: boolean; nf: NumberFormat; webHref: string }) {
  const t = await getTranslations('analytics')
  const channel = (c: string) => (t.has(`channels.${c}`) ? t(`channels.${c}`) : c)
  const noLast = d.touch === 'last' && !d.has_last_touch
  const anySpend = d.channels.some((c) => c.spend !== null)

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-[10px]">
        <div className="flex rounded-11 bg-tile p-[3px]">
          {(['first', 'last'] as const).map((k) => (
            <GoButton key={k} set={{ touch: k === 'first' ? null : k }} on={d.touch === k} className={`cursor-pointer rounded-8 border-0 px-[13px] py-[7px] text-12.5 text-ink ${d.touch === k ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
              {t(`attribution.touch.${k}`)}
            </GoButton>
          ))}
        </div>
        <span className="text-12 text-muted">{t('attribution.note')}</span>
      </div>

      {noLast ? (
        <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center">
          <div className="text-15 font-bold">{t('attribution.noLastTouch.title')}</div>
          <div className="mt-2 text-13 text-muted">{t('attribution.noLastTouch.body')}</div>
        </div>
      ) : (
        <div className={`${cardTable} overflow-x-auto`}>
          <div className={`grid min-w-[640px] gap-[10px] border-b border-line px-[18px] py-[10px] ${colHead} ${COLS}`}>
            <span>{t('attribution.cols.channel')}</span><span>{t('attribution.cols.signups')}</span><span>{t('attribution.cols.activated')}</span>
            <span>{t('attribution.cols.paid')}</span><span>{t('attribution.cols.mrr')}</span><span>{t('attribution.cols.spend')}</span><span>{t('attribution.cols.cac')}</span>
          </div>
          {d.channels.map((a) => {
            const cac = a.spend !== null && a.paid > 0 ? a.spend / a.paid : null
            return (
              <div key={a.channel} className={`grid min-w-[640px] items-center gap-[10px] border-b border-line px-[18px] py-[11px] text-13 tabular-nums ${COLS}`}>
                <span className="flex items-center gap-2"><span className="h-[9px] w-[9px] rounded-3" style={{ background: COLOR[a.channel] ?? '#C4BCA8' }} /><b>{channel(a.channel)}</b></span>
                <span>{formatNumber(a.signups, nf)}</span>
                <span>{formatNumber(a.activated, nf)}</span>
                <span>{formatNumber(a.paid, nf)}</span>
                <b>{money(a.mrr, nf)}</b>
                <span className="text-muted">{a.spend !== null ? money(a.spend, nf) : '—'}</span>
                <b className={cac !== null && cac > 2500 ? 'text-danger' : 'text-ink'}>{cac !== null ? money(cac, nf) : '—'}</b>
              </div>
            )
          })}
          {d.channels.length === 0 ? <div className="px-[18px] py-6"><Empty>{t('attribution.empty')}</Empty></div> : null}
          {d.channels.length && !anySpend ? (
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1 px-[18px] py-3 text-12.5 text-muted">
              <span>{t('attribution.noSpend')}</span>
              {canSpend ? <Link href={webHref as never} className="font-semibold">{t('attribution.enterSpend')}</Link> : null}
            </div>
          ) : null}
        </div>
      )}
    </div>
  )
}
