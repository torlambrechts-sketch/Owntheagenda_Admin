import { getLocale, getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Rule, SeoAlerts } from '@/lib/growth/seo'
import { cardTable, head } from '../v2kit'
import { AckButton, RuleRow } from './controls'

const TONE: Record<Rule, string> = { rank: '#D4633A', deindex: '#D4633A', traffic: '#E0A21F', cwv: '#D4633A' }

/**
 * SEO › Alerts (SeoSuite.dc.html, v.alerts) on seo_alerts_get (0074). Four of the design's seven rules have a source:
 * a ranking drop (Search Console), a page out of the index (URL Inspection), an organic traffic drop (the tracker) and a
 * failing Core Web Vital (PageSpeed Insights); «Lost featured snippet», «Lost backlink» and «Competitor jump» need data
 * Sentral does not have. Channels are the app and email; Slack has no sender here and a ticket is for customers
 * (V-GR2-31). Changing a rule needs Campaigns › Edit others'; acknowledging needs Campaigns › Add.
 */
export async function SeoAlertsView({ d, nf, product, site = null, canEdit, canAck }: { d: SeoAlerts; nf: NumberFormat; product: string; site?: string | null; canEdit: boolean; canAck: boolean }) {
  const t = await getTranslations('simpleGrowth.seoSuite.alerts')
  const tl = await getTranslations('simpleGrowth.integrations.log')
  const locale = await getLocale()
  const loc = locale === 'no' ? 'nb-NO' : locale
  const dayOf = (d0: Date) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Oslo' }).format(d0)
  const when = (iso: string) => {
    const at = new Date(iso)
    const time = new Intl.DateTimeFormat(loc, { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Oslo' }).format(at)
    const now = new Date()
    if (dayOf(at) === dayOf(now)) return tl('today', { time })
    if (dayOf(at) === dayOf(new Date(now.getTime() - 86_400_000))) return tl('yesterday', { time })
    return new Intl.DateTimeFormat(loc, { day: 'numeric', month: 'short', timeZone: 'Europe/Oslo' }).format(at)
  }
  const n1 = (v: unknown) => (typeof v === 'number' ? formatNumber(v, nf, Number.isInteger(v) ? 0 : 1) : typeof v === 'string' ? v : '—')
  const title = (h: SeoAlerts['history'][number]) => {
    const p = h.params
    switch (h.rule) {
      case 'rank': return t('titles.rank', { query: n1(p.query), from: n1(p.from), to: n1(p.to) })
      case 'deindex': return t('titles.deindex', { path: n1(p.path) })
      case 'traffic': return t('titles.traffic', { hour: n1(p.hour), now: n1(p.now), before: n1(p.before) })
      case 'cwv': return p.metric === 'inp' ? t('titles.cwv_inp', { path: n1(p.path), value: n1(p.value) }) : t('titles.cwv_lcp', { path: n1(p.path), value: n1(p.value) })
    }
  }
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('rules')}</b>
          <span className="text-12 text-muted">{t('rulesNote')}</span>
        </div>
        {d.rules.map((r) => (
          <RuleRow key={r.rule} product={product} site={site} rule={r.rule} name={t(`rule.${r.rule}.n`)} cond={t(`rule.${r.rule}.cond`)} enabled={r.enabled}
            channels={r.channels} mailReady={d.mail_ready} canEdit={canEdit} />
        ))}
      </section>
      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('history')}</b>
          <span className="text-12 text-muted">{t('open', { n: d.open })}</span>
        </div>
        {!d.history.length ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('empty')}</p> : null}
        {d.history.map((h) => (
          <div key={h.id} className={`flex items-center gap-3 border-b border-line px-[18px] py-[11px] ${h.acknowledged_at ? 'opacity-50' : ''}`}>
            <span className="w-[7px] self-stretch rounded-999" style={{ background: TONE[h.rule] }} />
            <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
              <b className="text-13 leading-[1.3] [overflow-wrap:anywhere]">{title(h)}</b>
              <span className="text-11.5 text-muted">{when(h.at)} · {t(`source.${h.rule}`)}</span>
            </span>
            <AckButton id={h.id} acked={!!h.acknowledged_at} canAck={canAck} />
          </div>
        ))}
      </section>
    </div>
  )
}
