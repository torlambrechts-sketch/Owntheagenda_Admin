import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { pageAdvice, pageOpportunity, pageTag, rate, type PageTag } from '@/lib/growth/calc'
import { PAGE_SORTS, growthHref, type PageSort, type Scope } from '@/lib/growth/scope'
import type { GrowthPages } from '@/lib/growth/types'
import { Bar, cardTable, channelColor, colHead, head12, label11, mono } from './v2kit'

const LAND_COLS = '[grid-template-columns:minmax(0,1.6fr)_64px_56px_56px_60px_54px]'
const REF_COLS = '[grid-template-columns:minmax(0,1.4fr)_60px_56px_64px]'
const CTA_COLS = '[grid-template-columns:minmax(0,1.4fr)_minmax(0,1fr)_56px_50px_56px]'
const TAG_TONE: Record<Exclude<PageTag, null>, string> = { converts: 'text-link', slow: 'text-danger', weak: 'text-warn-ink', bounce: 'text-warn-ink' }

/**
 * Growth › Pages and links (SimpleGrowth.dc.html, v.pages) on growth_pages: the landing pages with their visits, bounce,
 * signups begun and Core Web Vitals (PageSpeed Insights, 0073), the picked page's card (with the page's own figures in
 * Google search, rare searches included, 0091), the sites that send visits and
 * the presses on the site's own links and buttons. A referring site's links and domain rating need a backlink index the
 * platform does not have; those columns are left out (V-GR2-12).
 */
export async function PagesTab({ d, scope, sort, nf, siteRate }: { d: GrowthPages; scope: Scope; sort: PageSort; nf: NumberFormat; siteRate: number | null }) {
  const t = await getTranslations('simpleGrowth.pages')
  const tc = await getTranslations('simpleGrowth.channels')
  const dash = '—'
  const num = (v: number | null | undefined) => (v === null || v === undefined ? dash : formatNumber(v, nf))
  const total = d.landing.reduce((a, p) => a + p.visits, 0)
  const sr = siteRate ?? 0
  const rows = d.landing.map((p) => ({ ...p, tag: pageTag(p, total), cv: p.visits ? p.started / p.visits : 0, opp: pageOpportunity(p, sr) }))
  const sorted = [...rows].sort((a, b) =>
    sort === 'visits' ? b.visits - a.visits : sort === 'conversion' ? b.cv - a.cv : sort === 'slowest' ? (b.lcp_ms ?? -1) - (a.lcp_ms ?? -1) : b.opp - a.opp)
  const pg = d.page
  const pgRow = pg ? rows.find((r) => r.path === pg.path) ?? null : null
  // the page in Google search, rare searches included, and what of it the keywords below cannot show (0091)
  const gg = pg?.google ?? null
  const ggRest = gg && (gg.impressions > gg.named_impressions || gg.clicks > gg.named_clicks)
    ? { impressions: num(Math.max(0, gg.impressions - gg.named_impressions)), clicks: num(Math.max(0, gg.clicks - gg.named_clicks)) } : null
  const channelName = (c: string | null) => (c && tc.has(c) ? tc(c) : c ?? '')
  const sec = (ms: number | null) => (ms === null ? dash : `${formatNumber(ms / 1000, nf, 1)} s`)

  // the page's visits per day, as the design's sparkline
  const pts = pg?.daily ?? []
  const pmax = Math.max(1, ...pts.map((p) => p.visits))
  const line = pts.map((p, i) => `${pts.length > 1 ? ((i * 300) / (pts.length - 1)).toFixed(1) : '150'},${(58 - (p.visits / pmax) * 54).toFixed(1)}`).join(' ')
  const vit = pg?.vitals ?? null
  const vitals = [
    { k: 'LCP', v: vit?.lcp_ms ?? null, good: (x: number) => x <= 2500, f: (x: number) => `${formatNumber(x / 1000, nf, 1)} s` },
    { k: 'INP', v: vit?.inp_ms ?? null, good: (x: number) => x <= 200, f: (x: number) => `${formatNumber(x, nf)} ms` },
    { k: 'CLS', v: vit?.cls ?? null, good: (x: number) => x <= 0.1, f: (x: number) => formatNumber(x, nf, 2) },
  ]
  const srcTotal = Math.max(1, (pg?.sources ?? []).reduce((a, s) => a + s.visits, 0))
  const advice = pgRow ? pageAdvice(pgRow.tag, rate(pgRow.started, pgRow.visits)) : null
  const status = (r: GrowthPages['referrers'][number]) => {
    if (r.visits === 0 && r.prev > 0) return { k: 'lost', c: 'text-danger' }
    if (r.is_new) return { k: 'new', c: 'text-link' }
    return { k: 'active', c: 'text-ink' }
  }
  const human = (v: string) => v.replace(/[-_]+/g, ' ').replace(/^./, (c) => c.toUpperCase())

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,560px),1fr))]">
        <div className={cardTable}>
          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-3">
            <b className="text-15">{t('landing.title')}</b>
            <span className="flex flex-wrap gap-[5px]">
              {PAGE_SORTS.map((s) => {
                const on = s === sort
                return (
                  <Link key={s} href={growthHref('pages', scope, { sort: s, page: pg?.path ?? null }) as Route} aria-current={on ? 'true' : undefined}
                    className={`cursor-pointer whitespace-nowrap rounded-999 border px-[11px] py-[5px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
                    {t(`sorts.${s}`)}
                  </Link>
                )
              })}
            </span>
          </div>
          <div className="overflow-x-auto"><div className="min-w-[440px]">
            <div className={`grid gap-2 border-b border-line px-[18px] py-[9px] ${colHead} tracking-[.08em] ${LAND_COLS}`}>
              <span>{t('landing.page')}</span><span>{t('landing.visits')}</span><span>{t('landing.bounce')}</span><span>{t('landing.signups')}</span><span>{t('landing.conv')}</span><span>LCP</span>
            </div>
            {sorted.map((p) => {
              const on = pg?.path === p.path
              return (
                <Link key={p.path} href={growthHref('pages', scope, { sort, page: p.path }) as Route} aria-current={on ? 'true' : undefined}
                  className={`grid w-full cursor-pointer items-center gap-2 border-b border-line px-[18px] py-[9px] text-left text-12.5 tabular-nums text-ink hover:text-ink hover:no-underline ${LAND_COLS} ${on ? 'bg-highlight' : 'bg-transparent'}`}>
                  <span className="flex min-w-0 flex-col">
                    <span className={`overflow-hidden text-ellipsis whitespace-nowrap ${mono} text-11.5`}>{p.path}</span>
                    {p.tag ? <span className={`text-11 font-bold ${TAG_TONE[p.tag]}`}>{t(`tags.${p.tag}`)}</span> : null}
                  </span>
                  <span>{num(p.visits)}</span>
                  <span className={p.bounce > 60 ? 'text-danger' : 'text-ink'}>{percent(Math.round(p.bounce), nf)}</span>
                  <span>{num(p.started)}</span>
                  <b className={p.cv * 100 >= 3 ? 'text-link' : p.cv * 100 < 1 ? 'text-danger' : 'text-ink'}>{percent(p.cv * 100, nf)}</b>
                  <span className={p.lcp_ms === null ? 'text-faint' : p.lcp_ms > 2500 ? 'text-danger' : 'text-link'}>{sec(p.lcp_ms)}</span>
                </Link>
              )
            })}
            {rows.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{d.tracked ? t('landing.none') : t('landing.waiting')}</div> : null}
          </div></div>
        </div>

        {pg ? (
          <div className="flex flex-col gap-[11px] rounded-20 border border-ink bg-surface px-5 py-4">
            <div className={`${mono} text-13 font-bold [overflow-wrap:anywhere]`}>{pg.path}</div>
            <div className="text-12 text-muted">
              {t('card.line', { title: pg.title ?? t('card.noTitle'), visits: num(pg.visits), conv: percent((rate(pg.started, pg.visits) ?? 0) * 100, nf) })}
            </div>
            {pts.length > 1 ? (
              <svg viewBox="0 0 300 60" preserveAspectRatio="none" className="block h-[60px] w-full" role="img" aria-label={t('card.trend')}>
                <polygon points={`0,58 ${line} 300,58`} fill="#E4EEEC" />
                <polyline points={line} fill="none" stroke="#6E8FB8" strokeWidth="2" vectorEffect="non-scaling-stroke" />
              </svg>
            ) : null}
            <div className="grid grid-cols-3 gap-2">
              {vitals.map((f) => {
                const good = f.v === null ? null : f.good(f.v)
                return (
                  <div key={f.k} className={`rounded-12 px-[10px] py-2 ${good === null ? 'bg-tile' : good ? 'bg-ok-bg' : 'bg-peach'}`}>
                    <div className="text-10 font-bold uppercase tracking-[.08em] text-muted">{f.k}</div>
                    <b className={`text-13.5 ${good === null ? 'text-muted' : good ? 'text-ok-ink' : 'text-rust-ink'}`}>{f.v === null ? dash : f.f(f.v)}</b>
                  </div>
                )
              })}
            </div>
            {vit === null ? <span className="text-11.5 text-muted">{t('card.noVitals')}</span> : null}
            <div className={label11}>{t('card.sources')}</div>
            {pg.sources.map((s) => (
              <div key={s.channel} className="grid items-center gap-2 text-12 [grid-template-columns:110px_minmax(0,1fr)_46px]">
                <span className="overflow-hidden text-ellipsis whitespace-nowrap">{channelName(s.channel)}</span>
                <Bar w={(s.visits / srcTotal) * 100} color={channelColor(s.channel)} />
                <b className="text-right">{percent((s.visits / srcTotal) * 100, nf)}</b>
              </div>
            ))}
            {pg.sources.length === 0 ? <span className="text-12 text-muted">{t('card.noSources')}</span> : null}
            {gg ? (
              <>
                <div className={label11}>{t('card.google', { days: gg.days })}</div>
                <span className="text-12">
                  {gg.impressions || gg.clicks
                    ? t('card.googleLine', { impressions: num(gg.impressions), clicks: num(gg.clicks), position: gg.position === null ? dash : formatNumber(gg.position, nf, 1) })
                    : t('card.googleNone')}
                </span>
                {ggRest ? <span className="text-11.5 text-muted">{t('card.googleUnnamed', ggRest)}</span> : null}
              </>
            ) : null}
            <div className={label11}>{t('card.keywords')}</div>
            <div className="flex flex-wrap gap-[5px]">
              {pg.keywords.map((k) => (
                <span key={k.query} className="rounded-999 bg-tile px-[9px] py-[3px] text-11.5">{k.query} · <b>#{k.position === null ? dash : formatNumber(k.position, nf, 1)}</b></span>
              ))}
              {pg.keywords.length === 0 ? <span className="text-12 text-muted">{t('card.noKeywords')}</span> : null}
            </div>
            {advice ? (
              <div className="rounded-13 bg-highlight px-3 py-[10px] text-12.5 leading-[1.5]">
                <b>{t('card.rec')}</b>{' '}
                {t(`advice.${advice}`, { conv: percent((rate(pgRow?.started, pgRow?.visits) ?? 0) * 100, nf), lcp: sec(pgRow?.lcp_ms ?? null) })}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
        <div className={cardTable}>
          <div className={head12}><b className="text-15">{t('refs.title')}</b><span className="text-12 text-muted">{t('refs.sub')}</span></div>
          <div className={`grid gap-2 border-b border-line px-[18px] py-[9px] ${colHead} tracking-[.08em] ${REF_COLS}`}>
            <span>{t('refs.domain')}</span><span>{t('refs.visits')}</span><span>{t('refs.signups')}</span><span>{t('refs.status')}</span>
          </div>
          {d.referrers.map((r) => {
            const st = status(r)
            return (
              <div key={r.host} className={`grid items-center gap-2 border-b border-line px-[18px] py-[9px] text-12.5 tabular-nums ${REF_COLS}`}>
                <span className="flex min-w-0 flex-col">
                  <b className="overflow-hidden text-ellipsis whitespace-nowrap">{r.host}</b>
                  <span className="text-11 text-muted">{channelName(r.channel)}</span>
                </span>
                <span>{num(r.visits)}</span>
                <b>{num(r.started)}</b>
                <span className={`text-11.5 font-bold ${st.c}`}>{t(`refs.states.${st.k}`)}</span>
              </div>
            )
          })}
          {d.referrers.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{t('refs.none')}</div> : null}
        </div>

        <div className={cardTable}>
          <div className={head12}><b className="text-15">{t('ctas.title')}</b><span className="text-12 text-muted">{t('ctas.sub')}</span></div>
          <div className="overflow-x-auto"><div className="min-w-[420px]">
          <div className={`grid gap-2 border-b border-line px-[18px] py-[9px] ${colHead} tracking-[.08em] ${CTA_COLS}`}>
            <span>{t('ctas.link')}</span><span>{t('ctas.page')}</span><span>{t('ctas.clicks')}</span><span>{t('ctas.ctr')}</span><span>{t('ctas.signups')}</span>
          </div>
          {d.ctas.map((c) => (
            <div key={`${c.value}${c.path}`} className={`grid items-center gap-2 border-b border-line px-[18px] py-[9px] text-12.5 tabular-nums ${CTA_COLS}`}>
              <b className="overflow-hidden text-ellipsis whitespace-nowrap">«{human(c.value)}»</b>
              <span className={`overflow-hidden text-ellipsis whitespace-nowrap ${mono} text-11 text-muted`}>{c.path ?? dash}</span>
              <span>{num(c.clicks)}</span>
              <span>{c.page_sessions ? percent((c.sessions / c.page_sessions) * 100, nf) : dash}</span>
              <b className="text-link">{num(c.started)}</b>
            </div>
          ))}
          {d.ctas.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{d.tracked ? t('ctas.none') : t('landing.waiting')}</div> : null}
          </div></div>
        </div>
      </div>
    </div>
  )
}
