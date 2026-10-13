import { getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { SeoLinks } from '@/lib/growth/seo'
import { card, cardTable, head, mono } from '../v2kit'
import { LinkDecide } from './controls'

const SUG = '[grid-template-columns:minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1.1fr)_160px]'
const HUB = '[grid-template-columns:minmax(0,1.3fr)_50px_minmax(0,1fr)]'

/**
 * SEO › Internal links (SeoSuite.dc.html, v.links) on seo_links_get (0074), from the crawler's last whole crawl: a page
 * that mentions a search (tracked, or among the 40 seen most) but does not link to the page Google shows most for it is a
 * suggestion. «Add link» records the decision and logs the change; Sentral does not edit the website, and the next crawl
 * that finds the link retires the suggestion (V-GR2-28).
 */
export async function SeoLinksView({ d, nf, product, site = null, canAdd }: { d: SeoLinks; nf: NumberFormat; product: string; site?: string | null; canAdd: boolean }) {
  const t = await getTranslations('simpleGrowth.seoSuite.links')
  const mapped = d.links > 0
  const empty = (s: string) => <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{s}</p>
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <section className={`${card} col-span-full overflow-x-auto`}>
        <div className={head}>
          <b className="text-15">{t('sug')}</b>
          <span className="text-12 text-muted">{t('sugNote')}</span>
        </div>
        {!mapped ? empty(t('notCrawled')) : !d.suggestions.length ? empty(t('noSug')) : null}
        {d.suggestions.map((l) => (
          <div key={`${l.from}>${l.to}`} className={`grid min-w-[560px] items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 ${SUG}`}>
            <span className={`${mono} text-11.5 [overflow-wrap:anywhere]`}>{l.from}</span>
            <span>«{l.anchor}»</span>
            <span className={`${mono} text-11.5 [overflow-wrap:anywhere]`}>→ {l.to}</span>
            <span className="flex justify-end gap-[6px]">
              {l.decision === null
                ? (canAdd ? <LinkDecide product={product} site={site} from={l.from} to={l.to} anchor={l.anchor} /> : null)
                : <b className={`text-12 ${l.decision === 'added' ? 'text-link' : 'text-faint'}`}>{l.decision === 'added' ? t('added') : t('skipped')}</b>}
            </span>
          </div>
        ))}
      </section>
      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('orphans')}</b>
          <span className="text-12 text-muted">{t('orphansNote')}</span>
        </div>
        {!mapped ? empty(t('notCrawled')) : !d.orphans.length ? empty(t('noOrphans')) : null}
        {d.orphans.map((o) => (
          <div key={o.path} className="flex justify-between gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5">
            <span className={`${mono} text-11.5 [overflow-wrap:anywhere]`}>{o.path}</span>
            <span className="whitespace-nowrap text-muted">{t('orphanLine', { n: o.visits })}</span>
          </div>
        ))}
      </section>
      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('hubs')}</b>
          <span className="text-12 text-muted">{t('hubsNote')}</span>
        </div>
        {!mapped ? empty(t('notCrawled')) : null}
        {d.hubs.map((h) => (
          <div key={h.path} className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 ${HUB}`}>
            <span className={`${mono} text-11.5 [overflow-wrap:anywhere]`}>{h.path}</span>
            <b>{formatNumber(h.inlinks, nf)}</b>
            <span className="text-muted">{h.anchor ? `«${h.anchor}»` : '—'}</span>
          </div>
        ))}
      </section>
    </div>
  )
}
