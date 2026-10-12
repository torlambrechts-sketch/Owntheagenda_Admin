import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { expectedCtr, intentOf, keywordAdvice, keywordRow, kwFilter, relChange, type KwRow } from '@/lib/growth/calc'
import { KW_TABS, growthHref, type KwTab, type Scope } from '@/lib/growth/scope'
import type { Seo } from '@/lib/data/simple-growth-shared'
import type { KeywordHistory } from '@/lib/growth/types'
import { Delta, Tile, cardTable, colHead, label11, mono } from './v2kit'
import { KeywordTrack, StopTracking, TrackThis } from './KeywordTrack'
import { SiteHealth } from './SiteHealth'
import { ContentIdeas } from './ContentIdeas'

const COLS = '[grid-template-columns:minmax(0,1.7fr)_60px_46px_50px_54px_56px_66px]'
const TAG_TONE: Record<KwRow['segment'], string> = { top3: 'text-link', striking: 'text-warn-ink', low: 'text-danger', new: 'text-warn-ink' }

/**
 * Growth › SEO › Keywords (SimpleGrowth.dc.html, seoKeywords) on seo_get and seo_keyword_history: every search Google showed
 * the site for, with the page it showed, and the keywords tracked by hand (0084), by segment, their click rate against what the position usually gets (expectedCtr) and the clicks reaching the top three
 * would add; the picked keyword's position day by day and what to do. Search Console has no search volume: the column
 * shows impressions (V-SGR-08), and «Who ranks above us» needs result-page data the platform does not have (V-GR2-15).
 */
export async function SeoKeywordsTab({ d, scope, kt, kw, history, nf, product, brands, canAdd, editOthers }: {
  d: Seo; scope: Scope; kt: KwTab; kw: string | null; history: KeywordHistory | null; nf: NumberFormat; product: string; brands: string[]
  canAdd: boolean; editOthers: boolean
}) {
  const t = await getTranslations('simpleGrowth.keywords')
  const dash = '—'
  const num = (v: number | null) => (v === null ? dash : formatNumber(v, nf))
  const rows = d.keywords.map((k) => ({ ...keywordRow(k), id: k.id, tracked: k.tracked, page: k.page ?? null, mine: k.mine, variants: k.variants ?? null }))
  const shown = rows.filter((r) => kwFilter(kt, r)).sort((a, b) => b.potential - a.potential || (b.impressions ?? 0) - (a.impressions ?? 0))
  const sel = rows.find((r) => r.query === kw) ?? shown[0] ?? rows[0] ?? null
  const s = d.totals
  const top3 = rows.filter((r) => r.segment === 'top3').length
  const top3Prev = rows.filter((r) => r.position_prev !== null && r.position_prev <= 3).length
  const striking = rows.filter((r) => r.segment === 'striking').length
  const potential = rows.reduce((a, r) => a + r.potential, 0)
  const hrefKw = (extra: { kt?: KwTab; kw?: string | null }) => growthHref('seo', scope, { sub: 'keywords', kt: extra.kt ?? kt, kw: extra.kw === undefined ? sel?.query ?? null : extra.kw })

  // the position line: lower is better, so 1 is at the top; a dashed line marks the top three
  const pts = (history?.points ?? []).filter((p) => p.position !== null)
  const kmax = Math.max(12, ...pts.map((p) => p.position ?? 0)) + 1
  const ky = (p: number) => (4 + ((p - 1) / (kmax - 1)) * 62).toFixed(1)
  const line = pts.map((p, i) => `${pts.length > 1 ? ((i * 300) / (pts.length - 1)).toFixed(1) : '150'},${ky(p.position!)}`).join(' ')
  const advice = sel ? keywordAdvice(sel) : null

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        <Tile label={t('kpi.clicks')} value={s ? num(s.clicks) : dash} delta={<Delta change={s ? relChange(s.clicks, s.clicks_prev) : null} nf={nf} />} />
        <Tile label={t('kpi.impressions')} value={s ? num(s.impressions) : dash} delta={<Delta change={s ? relChange(s.impressions, s.impressions_prev) : null} nf={nf} />} />
        <Tile label={t('kpi.top3')} value={d.connected ? String(top3) : dash}
          delta={d.connected && top3 !== top3Prev ? <span className={`whitespace-nowrap text-12 font-bold ${top3 > top3Prev ? 'text-link' : 'text-danger'}`}>{(top3 > top3Prev ? '+' : '−') + Math.abs(top3 - top3Prev)}</span> : null} />
        <Tile label={t('kpi.striking')} value={d.connected ? String(striking) : dash} />
        <Tile label={t('kpi.potential')} value={d.connected ? `+${formatNumber(potential, nf)}` : dash} />
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,560px),1fr))]">
        <div className={cardTable}>
          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-3">
            <span className="flex flex-wrap gap-[5px]">
              {KW_TABS.map((k) => {
                const on = k === kt
                return (
                  <Link key={k} href={hrefKw({ kt: k, kw: null }) as Route} aria-current={on ? 'true' : undefined}
                    className={`cursor-pointer whitespace-nowrap rounded-999 border px-[11px] py-[5px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
                    {t(`tabs.${k}`)} <span className="text-muted">{rows.filter((r) => kwFilter(k, r)).length}</span>
                  </Link>
                )
              })}
            </span>
            {d.site && canAdd ? <KeywordTrack product={product} connected={d.connected} /> : null}
          </div>
          <div className="overflow-x-auto"><div className="min-w-[520px]">
            <div className={`grid gap-2 border-b border-line px-[18px] py-[9px] ${colHead} tracking-[.08em] ${COLS}`}>
              <span>{t('cols.keyword')}</span><span>{t('cols.volume')}</span><span>{t('cols.pos')}</span><span className="whitespace-nowrap">{t('cols.change', { days: d.days })}</span>
              <span>{t('cols.ctr')}</span><span>{t('cols.clicks')}</span><span>{t('cols.potential')}</span>
            </div>
            {shown.map((k) => {
              const on = sel?.query === k.query
              // a tracked head term Google never reports on its own still shows in the longer searches that contain it
              const inLonger = k.segment === 'new' && k.variants && k.variants.queries > 0
              const tag = k.segment === 'top3' ? t('tags.top3') : k.segment === 'striking' ? (k.ctrGap ? t('tags.strikingCtr') : t('tags.striking')) : k.segment === 'low' ? t('tags.low')
                : !d.connected ? t('tags.notConnected') : inLonger ? t('tags.inSearches', { n: k.variants!.queries, impressions: formatNumber(k.variants!.impressions, nf) }) : t('tags.new')
              return (
                <Link key={k.query} href={hrefKw({ kw: k.query }) as Route} aria-current={on ? 'true' : undefined}
                  className={`grid w-full cursor-pointer items-center gap-2 border-b border-line px-[18px] py-[9px] text-left text-12.5 tabular-nums text-ink hover:text-ink hover:no-underline ${COLS} ${on ? 'bg-highlight' : 'bg-transparent'}`}>
                  <span className="flex min-w-0 flex-col">
                    <b className="overflow-hidden text-ellipsis whitespace-nowrap">{k.query}</b>
                    <span className={`overflow-hidden text-ellipsis whitespace-nowrap text-11 font-bold ${inLonger ? 'text-muted' : TAG_TONE[k.segment]}`}>{tag}</span>
                    {k.page || k.tracked ? (
                      <span className="overflow-hidden text-ellipsis whitespace-nowrap text-11 text-muted" title={k.page ?? undefined}>
                        {k.page ? <span className={mono}>{k.page}</span> : null}{k.page && k.tracked ? ' · ' : null}{k.tracked ? t('trackedMark') : null}
                      </span>
                    ) : null}
                  </span>
                  <span>{num(k.impressions)}</span>
                  <b className={k.position === null ? 'text-faint' : k.position <= 3 ? 'text-link' : k.position <= 10 ? 'text-warn-ink' : 'text-danger'}>{k.position === null ? dash : formatNumber(k.position, nf, 1)}</b>
                  <span className={`font-bold ${k.change === null || Math.abs(k.change) < 0.3 ? 'text-faint' : k.change > 0 ? 'text-link' : 'text-danger'}`}>
                    {k.change === null ? dash : Math.abs(k.change) < 0.3 ? '·' : `${k.change > 0 ? '▲' : '▼'} ${formatNumber(Math.abs(k.change), nf, 1)}`}
                  </span>
                  <span className={k.ctrGap ? 'text-danger' : 'text-ink'}>{k.ctr === null ? dash : percent(k.ctr * 100, nf)}</span>
                  <span>{num(k.clicks)}</span>
                  <b className="text-link">{k.potential ? `+${formatNumber(k.potential, nf)}` : dash}</b>
                </Link>
              )
            })}
            {rows.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{d.site ? (d.connected ? t('emptyConnected') : t('empty')) : t('noSite')}</div> : null}
            {d.keywords_total && d.keywords_total > rows.filter((r) => (r.impressions ?? 0) > 0).length ? (
              <div className="px-[18px] py-[10px] text-12 text-muted">{t('capped', { n: rows.filter((r) => (r.impressions ?? 0) > 0).length, total: d.keywords_total })}</div>
            ) : null}
            {rows.length > 0 && shown.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{t('noneInTab')}</div> : null}
          </div></div>
        </div>

        {sel ? (
          <div className="flex flex-col gap-[10px] rounded-20 border border-ink bg-surface px-5 py-4">
            <div className="flex justify-between gap-[10px]">
              <b className="min-w-0 font-serif text-19 leading-[1.2] [overflow-wrap:anywhere]">{sel.query}</b>
              <span className="self-start whitespace-nowrap rounded-999 bg-tile px-[10px] py-[3px] text-11 font-bold">{t(`intent.${intentOf(sel.query, brands)}`)}</span>
            </div>
            <div className="text-11.5 text-muted">{t('detail.position', { days: history?.days ?? 30 })}</div>
            <svg viewBox="0 0 300 70" preserveAspectRatio="none" className="block h-[70px] w-full rounded-10 bg-canvas" role="img" aria-label={t('detail.position', { days: history?.days ?? 30 })}>
              <line x1="0" y1={ky(3)} x2="300" y2={ky(3)} stroke="#5C9A55" strokeDasharray="4 4" strokeWidth="1" vectorEffect="non-scaling-stroke" />
              {pts.length > 1 ? <polyline points={line} fill="none" stroke="#191510" strokeWidth="2" vectorEffect="non-scaling-stroke" /> : null}
            </svg>
            {pts.length <= 1 ? <span className="text-11.5 text-muted">{d.connected ? t('detail.noHistory') : t('detail.notConnected')}</span> : null}
            <div className="grid gap-2 [grid-template-columns:repeat(auto-fit,minmax(90px,1fr))]">
              {[
                { k: t('detail.impressions'), v: num(sel.impressions), c: 'text-ink' },
                { k: t('detail.ctr'), v: sel.position !== null && sel.ctr !== null ? `${percent(sel.ctr * 100, nf)} / ${percent(expectedCtr(sel.position) * 100, nf)}` : dash, c: sel.ctrGap ? 'text-danger' : 'text-ink' },
                { k: t('detail.potential'), v: sel.potential ? `+${formatNumber(sel.potential, nf)}` : dash, c: 'text-link' },
              ].map((f) => (
                <div key={f.k} className="rounded-12 border border-line bg-canvas px-[10px] py-2">
                  <div className="text-10 font-bold uppercase tracking-[.08em] text-muted">{f.k}</div>
                  <b className={`text-13.5 ${f.c}`}>{f.v}</b>
                </div>
              ))}
            </div>
            <div className="text-12 text-muted">{t('detail.page')} <span className={`${mono} text-ink`}>{sel.page ?? dash}</span></div>
            {(history?.pages.length ?? 0) > 1 ? (
              <>
                <div className={label11}>{t('detail.pages')}</div>
                {history!.pages.map((p) => (
                  <div key={p.page} className="flex gap-2 text-12"><span className={`flex-1 ${mono} text-11.5 [overflow-wrap:anywhere]`}>{p.page}</span><b>{num(p.impressions)}</b></div>
                ))}
              </>
            ) : null}
            {advice ? <div className="rounded-13 bg-highlight px-3 py-[10px] text-12.5 leading-[1.5]"><b>{t('detail.doThis')}</b> {t(`advice.${advice}`, { q: sel.query })}</div> : null}
            {sel.tracked && sel.id && canAdd && (sel.mine || editOthers) ? <StopTracking id={sel.id} query={sel.query} /> : null}
            {!sel.tracked && canAdd ? <TrackThis product={product} query={sel.query} /> : null}
          </div>
        ) : null}
      </div>

      {d.site ? (
        <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
          {d.health ? <SiteHealth health={d.health} cannibal={d.cannibal ?? []} slow={d.slow ?? []} site={d.site.id} product={product} nf={nf} canEdit={canAdd} /> : null}
          {d.ideas ? <ContentIdeas ideas={d.ideas} product={product} nf={nf} canEdit={canAdd} /> : <ContentIdeas ideas={[]} product={product} nf={nf} canEdit={false} notConnected />}
        </div>
      ) : null}
    </div>
  )
}
