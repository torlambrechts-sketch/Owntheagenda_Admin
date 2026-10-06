import { getFormatter, getTranslations } from 'next-intl/server'
import type { Activation as ActivationData } from '@/lib/data/analytics'
import { addMonths, biggestDrop, duration, share } from '@/lib/data/analytics-calc'
import { percent, type NumberFormat } from '@/lib/format'
import { GoButton } from './nav'
import { Empty, darkPill, signedNum } from './kit'

const ACTIVATED = 'result_unlocked'

/**
 * Activation funnel (Analytics.dc.html, v.activation) on analytics_activation: one signup cohort (the month
 * an account was created), eight milestones, the share lost per step and the median time between steps.
 */
export async function Activation({ d, earlier, nf }: { d: ActivationData; earlier: ActivationData | null; nf: NumberFormat }) {
  const t = await getTranslations('analytics.activation')
  const format = await getFormatter()
  const mon = (m: string) => format.dateTime(new Date(`${m}-15T12:00:00Z`), { month: 'short' })
  const dur = (min: number | null) => {
    if (min === null) return '—'
    const x = duration(min)
    return t(`dur.${x.unit}`, { n: x.n })
  }
  const step = (key: string) => (t.has(`steps.${key}`) ? t(`steps.${key}`) : key)

  const steps = d.steps
  const size = steps[0]?.count ?? 0
  const at = (data: ActivationData | null, key: string) => data?.steps.find((s) => s.key === key)?.count ?? null
  const activated = share(at(d, ACTIVATED), size)
  const before = earlier ? share(at(earlier, ACTIVATED), earlier.steps[0]?.count ?? 0) : null
  const drop = biggestDrop(steps)
  const cohorts = [...(d.cohorts ?? [])].reverse()

  const cards = [
    {
      n: t('cards.drop'),
      v: drop ? t('cards.dropValue', { from: drop.index, to: drop.index + 1 }) : '—',
      s: drop ? t('cards.dropSub', { pct: percent(Math.round(drop.drop * 100), nf), prev: step(steps[drop.index - 1]!.key), next: step(steps[drop.index]!.key) }) : t('cards.dropNone'),
    },
    {
      n: t('cards.activated'),
      v: activated !== null ? percent(Math.round(activated), nf) : '—',
      s: activated !== null && before !== null && earlier
        ? t('cards.activatedSub', { cohort: mon(d.cohort), delta: signedNum(Math.round(activated - before), nf), earlier: mon(earlier.cohort) })
        : t('cards.activatedSubNoDelta', { cohort: mon(d.cohort) }),
    },
    { n: t('cards.paid'), v: dur(d.paid_median_min ?? null), s: t('cards.paidSub') },
  ]

  return (
    <div className="flex flex-col gap-4">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr))]">
        <div className="rounded-20 bg-ink px-[22px] py-5 text-canvas">
          <div className="text-11 font-bold uppercase tracking-eyebrow text-amber-bg">{t('promise.title')}</div>
          <div className="mt-[10px] font-serif text-40 font-semibold leading-none">{dur(d.first_send_median_min ?? null)}</div>
          <div className="mt-[6px] text-13">{d.target_min !== null ? t('promise.sub', { target: d.target_min }) : t('promise.subNoTarget')}</div>
        </div>
        {cards.map((k) => (
          <div key={k.n} className="rounded-20 border border-line bg-surface px-[22px] py-5">
            <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{k.n}</div>
            <div className="mt-2 font-serif text-30 font-semibold">{k.v}</div>
            <div className="mt-1 text-12.5 text-muted">{k.s}</div>
          </div>
        ))}
      </div>

      <div className="overflow-x-auto rounded-20 border border-line bg-surface px-6 py-5">
        <div className="mb-4 flex flex-wrap items-baseline justify-between gap-[10px]">
          <span className="text-15 font-bold">{t('funnel.title')}</span>
          <div className="flex flex-wrap gap-1">
            {cohorts.map((c) => (
              <GoButton key={c} set={{ cohort: c }} on={c === d.cohort} className={darkPill(c === d.cohort)}>{t('funnel.cohort', { month: mon(c) })}</GoButton>
            ))}
          </div>
        </div>
        {size > 0 ? (
          <div className="flex min-w-[640px] flex-col gap-[6px]">
            {steps.map((s, i) => {
              const prev = i ? steps[i - 1]!.count : s.count
              const lostShare = i && prev ? 1 - s.count / prev : 0
              return (
                <div key={s.key} className="grid items-center gap-3 text-13 [grid-template-columns:24px_minmax(180px,1.2fr)_minmax(0,2fr)_60px_76px_96px]">
                  <span className="flex h-[22px] w-[22px] items-center justify-center rounded-999 bg-ink text-11 font-bold text-highlight">{i + 1}</span>
                  <span className="font-semibold">{step(s.key)}</span>
                  <span className="block h-[26px] overflow-hidden rounded-8 bg-tile">
                    <span className="block h-full border-r border-[rgba(25,21,16,.15)]" style={{ width: `${(s.count / size) * 100}%`, background: i === steps.length - 1 ? '#F5C64A' : '#CFE7E4' }} />
                  </span>
                  <b className="text-right tabular-nums">{s.count}</b>
                  <span className={`text-right text-12 font-bold ${lostShare > 0.2 ? 'text-danger' : 'text-warn-ink'}`}>{i && prev ? `−${percent(Math.round(lostShare * 100), nf)}` : ''}</span>
                  <span className="text-right text-12 text-muted">{i ? dur(s.median_min) : '—'}</span>
                </div>
              )
            })}
          </div>
        ) : <Empty>{t('funnel.empty', { month: mon(d.cohort) })}</Empty>}
        <div className="mt-[14px] flex flex-wrap gap-x-[18px] gap-y-1 text-11.5 text-faint">
          <span>{t('funnel.legend.bar')}</span><span>{t('funnel.legend.red')}</span><span>{t('funnel.legend.right')}</span>
        </div>
      </div>
    </div>
  )
}

/** The cohort three months before the chosen one, for the «Activated» comparison. */
export const earlierCohort = (cohort: string) => addMonths(cohort, -3)
