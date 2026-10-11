import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { OPP_KINDS, type SeoOpp } from '@/lib/growth/seo'
import { OPP_TYPES, growthHref, type Scope } from '@/lib/growth/scope'
import { card } from '../v2kit'
import { PlanButton } from './controls'
import { KIND_BG, oppTexts } from './text'

const COLS = '[grid-template-columns:minmax(0,2fr)_110px_70px_90px_96px]'

/**
 * SEO › Opportunities (SeoSuite.dc.html, v.opps) on seo_opportunities (0074), typed and priced in lib/growth/seo.ts. The
 * type chips filter through the address. «Difficulty» (KD) needs an SEO tool's index and is left out, as is the
 * «Featured snippet» kind, which needs result-page data (V-GR2-25).
 */
export async function SeoOppsView({ opps, ot, priced, connected, scope, nf, product, canAdd }: {
  opps: SeoOpp[]; ot: (typeof OPP_TYPES)[number]; priced: boolean; connected: boolean; scope: Scope; nf: NumberFormat; product: string; canAdd: boolean
}) {
  const t = await getTranslations('simpleGrowth.seoSuite')
  const shown = opps.filter((o) => ot === 'all' || o.kind === ot)
  const texts = await oppTexts(shown, nf)
  const chips = (['all', ...OPP_KINDS] as const).map((k) => ({ k, count: k === 'all' ? opps.length : opps.filter((o) => o.kind === k).length }))
  return (
    <div className="flex flex-col gap-[10px]">
      <div className="flex flex-wrap items-center gap-[6px]">
        {chips.map(({ k, count }) => {
          const on = ot === k
          return (
            <Link key={k} href={growthHref('seo', scope, { sub: 'opps', ot: k }) as Route} aria-current={on ? 'true' : undefined}
              className={`cursor-pointer whitespace-nowrap rounded-999 border px-[11px] py-[5px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
              {k === 'all' ? t('opps.all') : t(`kinds.${k}`)} <span className="text-muted">{formatNumber(count, nf)}</span>
            </Link>
          )
        })}
        <span className="flex-1" />
        <span className="text-12 text-muted">{priced ? t('opps.formula') : t('opps.formulaMissing')}</span>
      </div>
      <section className={`${card} overflow-x-auto`}>
        <div className="min-w-[560px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] ${COLS} text-10.5 font-bold uppercase tracking-[.08em] text-muted`}>
            <span>{t('opps.cols.opp')}</span><span>{t('opps.cols.type')}</span><span>{t('opps.cols.effort')}</span><span>{t('opps.cols.value')}</span><span />
          </div>
          {!connected ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('notConnected')}</p> : null}
          {connected && !shown.length ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('opps.empty')}</p> : null}
          {shown.map((o, i) => (
            <div key={`${o.kind}:${o.query}:${o.path ?? ''}`} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 ${COLS}`}>
              <span className="flex min-w-0 flex-col">
                <b className="leading-[1.3]">{texts[i]!.line}</b>
                <span className="text-11.5 text-muted [overflow-wrap:anywhere]">{texts[i]!.note}</span>
              </span>
              <span><span className={`whitespace-nowrap rounded-999 px-[9px] py-[2px] text-11 font-bold ${KIND_BG[o.kind]}`}>{texts[i]!.type}</span></span>
              <span>{texts[i]!.effort}</span>
              <b className="whitespace-nowrap text-link">{texts[i]!.worthShort}</b>
              <PlanButton product={product} query={o.query} kind={o.kind} path={o.path} planned={o.planned} label={t('doIt')} disabled={!canAdd} />
            </div>
          ))}
        </div>
      </section>
    </div>
  )
}
