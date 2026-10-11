import Link from 'next/link'
import type { Route } from 'next'
import { getLocale, getTranslations } from 'next-intl/server'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { intentOf } from '@/lib/growth/calc'
import { STAGES, stageStep, type SeoOpp, type SeoPlan, type Stage } from '@/lib/growth/seo'
import { growthHref, type Scope } from '@/lib/growth/scope'
import { label11, mono } from '../v2kit'
import { PlanMove } from './controls'
import { pos } from './text'

/** the columns' underline colours (STG[][1]) */
const STAGE_LINE: Record<Stage, string> = { idea: '#F2EAD6', writing: '#F3E2C9', published: '#CFE0F5', measuring: '#CFE7E4' }

/**
 * SEO › Content plan (SeoSuite.dc.html, v.plan) on seo_plan_get (0074). Four columns; ← and → move a card, and reaching
 * «Published» logs the change. A card's value is the current estimate of its search's opportunity (none once the
 * opportunity is gone); 28 days after publishing, Search Console's figures before and after replace the «Measuring»
 * line. The brief's related searches and questions are Search Console's own queries; «Length vs top 3» needs result-page
 * data and is left out, as are signups per article (V-GR2-27).
 */
export async function SeoPlanView({ d, opps, scope, nf, brands, canAdd }: {
  d: SeoPlan; opps: SeoOpp[]; scope: Scope; nf: NumberFormat; brands: string[]; canAdd: boolean
}) {
  const t = await getTranslations('simpleGrowth.seoSuite')
  const ti = await getTranslations('simpleGrowth.keywords.intent')
  const locale = await getLocale()
  const date = (iso: string) => new Intl.DateTimeFormat(locale === 'no' ? 'nb-NO' : locale, { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(`${iso.slice(0, 10)}T12:00:00Z`))
  const best = new Map<string, SeoOpp>()
  for (const o of opps) if (!best.has(o.query)) best.set(o.query, o)
  const stageName = (s: Stage) => t(`plan.stages.${s}`)
  const title = (it: SeoPlan['items'][number]) => t(`plan.title.${it.kind}`, { q: it.query, path: it.path ?? it.query })
  const change = (before: number, after: number) => (before > 0 ? `${after >= before ? '+' : '−'}${percent(Math.abs(Math.round((after / before - 1) * 100)), nf)}` : `${formatNumber(before, nf)} → ${formatNumber(after, nf)}`)
  const result = (it: SeoPlan['items'][number]): { text: string; good: boolean } | null => {
    if (it.measured) {
      const m = it.measured
      if (!m.clicks_before && !m.clicks_after && m.position_before === null && m.position_after === null) return { text: t('plan.noFigures'), good: false }
      const clicks = change(m.clicks_before, m.clicks_after)
      const good = m.clicks_after > m.clicks_before
      return m.position_before !== null && m.position_after !== null
        ? { text: t('plan.result', { clicks, from: pos(m.position_before, nf), to: pos(m.position_after, nf) }), good }
        : { text: t('plan.resultClicks', { clicks }), good }
    }
    return it.measure_on ? { text: t('plan.measuring', { date: date(it.measure_on) }), good: false } : null
  }
  const open = d.items.find((x) => x.id === d.brief?.id) ?? null

  return (
    <div className="flex flex-col gap-3">
      {!d.items.length ? <p className="m-0 text-12.5 text-muted">{t('plan.empty')}</p> : null}
      <div className="flex items-start gap-[10px] overflow-x-auto pb-[6px]">
        {STAGES.map((s) => {
          const cards = d.items.filter((x) => x.stage === s)
          return (
            <div key={s} className="flex min-h-[260px] flex-[1_0_220px] flex-col gap-2 rounded-18 bg-tile p-2">
              <div className="flex justify-between px-[6px] pb-2 pt-[6px]" style={{ borderBottom: `3px solid ${STAGE_LINE[s]}` }}>
                <b className="text-13">{stageName(s)}</b>
                <span className="text-12 text-muted">{cards.length}</span>
              </div>
              {cards.map((it) => {
                const o = best.get(it.query)
                const r = result(it)
                const back = stageStep(it.stage, -1)
                const fwd = stageStep(it.stage, 1)
                return (
                  <div key={it.id} className={`relative flex flex-col gap-[6px] rounded-14 border bg-surface px-[11px] py-[10px] ${open?.id === it.id ? 'border-ink' : 'border-line'}`}>
                    <Link href={growthHref('seo', scope, { sub: 'plan', brief: it.id }) as Route}
                      className="text-12.5 font-bold leading-[1.3] text-ink after:absolute after:inset-0 after:rounded-14 after:content-[''] hover:text-ink hover:no-underline">
                      {title(it)}
                    </Link>
                    <span className="text-11.5 text-muted">{t('plan.meta', { q: it.query, owner: it.owner ?? '—' })}</span>
                    <span className="flex items-center justify-between text-11.5">
                      <b className="text-link">{o ? (o.value !== null ? t('perMonth', { value: money(o.value, nf) }) : t('clicksPerMonth', { n: formatNumber(o.clicks, nf) })) : '—'}</b>
                      {canAdd ? (
                        <span className="relative z-10">
                          <PlanMove id={it.id} back={back} fwd={fwd} backName={back ? stageName(back) : ''} fwdName={fwd ? stageName(fwd) : ''}
                            backLabel={back ? t('plan.back', { stage: stageName(back) }) : ''} fwdLabel={fwd ? t('plan.fwd', { stage: stageName(fwd) }) : ''} />
                        </span>
                      ) : null}
                    </span>
                    {r ? <span className={`text-11.5 font-bold ${r.good ? 'text-link' : 'text-warn-ink'}`}>{r.text}</span> : null}
                  </div>
                )
              })}
            </div>
          )
        })}
      </div>
      {open && d.brief ? (
        <section className="grid gap-4 rounded-20 border border-ink bg-surface px-[22px] py-[18px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
          <div className="col-span-full flex flex-col gap-2">
            <div className="flex items-start justify-between gap-[10px]">
              <div>
                <div className={label11}>{t('plan.brief.label', { stage: stageName(open.stage) })}</div>
                <b className="font-serif text-21 leading-[1.2]">{title(open)}</b>
              </div>
              <Link href={growthHref('seo', scope, { sub: 'plan' }) as Route} aria-label={t('plan.brief.close')} title={t('plan.brief.close')}
                className="flex h-[30px] w-[30px] flex-none items-center justify-center rounded-999 border border-ink bg-transparent text-ink hover:text-ink hover:no-underline">×</Link>
            </div>
          </div>
          <div className="flex flex-col gap-[7px]">
            <span className={label11}>{t('plan.brief.target')}</span>
            <b className="text-13.5">{open.query}</b>
            <span className="text-12 text-muted">{t('plan.brief.urlIntent', { url: open.path ?? t('plan.brief.noUrl'), intent: ti(intentOf(open.query, brands)) })}</span>
            <span className={`${label11} mt-[6px]`}>{t('plan.brief.terms')}</span>
            {d.brief.terms.length ? (
              <div className="flex flex-wrap gap-1">
                {d.brief.terms.map((x) => <span key={x} className="rounded-999 bg-tile px-[9px] py-[3px] text-11.5">{x}</span>)}
              </div>
            ) : <span className="text-12 text-muted">{t('plan.brief.noTerms')}</span>}
          </div>
          <div className="flex flex-col gap-[7px]">
            <span className={label11}>{t('plan.brief.questions')}</span>
            {d.brief.questions.length ? d.brief.questions.map((q) => <span key={q} className="text-12.5">? {q}</span>)
              : <span className="text-12 text-muted">{t('plan.brief.noQuestions')}</span>}
          </div>
          <div className="flex flex-col gap-[7px]">
            <span className={label11}>{t('plan.brief.links')}</span>
            {d.brief.links.length ? d.brief.links.map((l) => <span key={l.from} className={`${mono} text-12`}>↳ {l.from} → «{l.anchor}»</span>)
              : <span className="text-12 text-muted">{t('plan.brief.noLinks')}</span>}
          </div>
          {open.measured ? (
            <div className="col-span-full grid gap-2 [grid-template-columns:repeat(auto-fit,minmax(140px,1fr))]">
              <div className="rounded-13 bg-ok-bg px-[11px] py-[9px]">
                <div className="text-10 font-bold uppercase tracking-[.08em] text-ok-ink">{t('plan.brief.measured', { k: t('plan.brief.clicks') })}</div>
                <b className="text-14">{change(open.measured.clicks_before, open.measured.clicks_after)}</b>
              </div>
              <div className="rounded-13 bg-ok-bg px-[11px] py-[9px]">
                <div className="text-10 font-bold uppercase tracking-[.08em] text-ok-ink">{t('plan.brief.measured', { k: t('plan.brief.position') })}</div>
                <b className="text-14">{pos(open.measured.position_before, nf)} → {pos(open.measured.position_after, nf)}</b>
              </div>
            </div>
          ) : null}
        </section>
      ) : null}
    </div>
  )
}
