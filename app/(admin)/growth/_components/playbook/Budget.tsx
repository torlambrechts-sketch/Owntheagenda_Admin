'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { observedCac, pace, scenario, suggestedMove, type Budget, type BudgetChannel } from '@/lib/growth/playbook'
import { moveBudget, setBudget } from '../../playbook-actions'
import { Tile, card, cardTable, channelColor, head } from '../v2kit'

const ROW = '[grid-template-columns:minmax(0,1.2fr)_110px_minmax(0,1.6fr)_120px_130px]'
const PACE = {
  on: { bar: '#5C9A55', text: 'text-link' },
  ahead: { bar: '#D4633A', text: 'text-danger' },
  under: { bar: '#C4BCA8', text: 'text-warn-ink' },
  none: { bar: '#C4BCA8', text: 'text-muted' },
} as const

/**
 * Marketing campaigns › Budget planner (GrowthPlaybook.dc.html, v.budget) on growth_budget (0076): this month's budget per
 * channel against what was spent, the pace against the share of the month gone, and the cost of a paying customer each
 * channel showed over 90 days. The design's «per paying, next 10k» is a marginal cost Sentral cannot observe; the view
 * shows the 90-day average and says so (V-GR2-34). The move and the scenario follow from those costs (lib/growth/playbook).
 * Setting a budget needs Campaigns › Reports on others' (the right spend is typed in under); the database checks it.
 */
export function BudgetView({ d, nf, product, app, canEdit }: { d: Budget; nf: NumberFormat; product: string; app: string; canEdit: boolean }) {
  const t = useTranslations('simpleGrowth.playbook.budget')
  const tc = useTranslations('simpleGrowth.channels')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [extra, setExtra] = useState('20000')
  const dash = '—'
  const kr = (v: number | null) => (v === null ? dash : money(v, nf))
  const ch = (c: string) => (tc.has(c) ? tc(c) : c)
  const month = format.dateTime(new Date(`${d.month}T12:00:00Z`), { month: 'long', timeZone: 'UTC' })
  const dayOf = (n: number) => format.dateTime(new Date(`${d.month.slice(0, 8)}${String(n).padStart(2, '0')}T12:00:00Z`), { day: 'numeric', month: 'short', timeZone: 'UTC' })

  const budgets = d.rows.filter((r) => r.budget !== null)
  const total = budgets.length ? budgets.reduce((a, r) => a + r.budget!, 0) : null
  const spent = d.rows.reduce((a, r) => a + r.spent, 0)
  const gone = d.day / d.days
  const spend90 = d.rows.reduce((a, r) => a + (r.spend90 ?? 0), 0)
  const paying90 = d.rows.reduce((a, r) => a + (r.paying90 ?? 0), 0)
  const blended = d.attributed && spend90 && paying90 ? spend90 / paying90 : null
  const payback = blended !== null && d.arpa ? blended / d.arpa : null

  const mv = suggestedMove(d.rows)
  const lm = d.last_move
  const applied = !!(lm && (!mv || (lm.from === mv.from && lm.to === mv.to)))
  const sc = scenario(Number(extra.replace(/\D/g, '')) || 0, d.rows, d.arpa)

  const apply = () => mv && start(async () => {
    const r = await moveBudget({ product, from: mv.from, to: mv.to, amount: mv.amount })
    if (!r.ok) { flash(te(r.code)); return }
    flash(t('movedToast', { from: ch(mv.from), to: ch(mv.to) }))
    router.refresh()
  })

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        <Tile size={23} label={t('kpi.budget', { month })} value={kr(total)} note={total !== null ? t('kpi.budgetNote', { n: budgets.length }) : t('kpi.budgetNone')} />
        <Tile size={23} label={t('kpi.spent')} value={money(spent, nf)} note={t('kpi.spentNote', { share: percent(gone * 100, nf) })} />
        <Tile size={23} label={t('kpi.cac')} value={kr(blended)} note={d.attributed ? t('kpi.cacNote') : t('kpi.noSource', { app })} />
        <Tile size={23} label={t('kpi.payback')} value={payback !== null ? t('months', { n: formatNumber(payback, nf, 1) }) : dash}
          tone={payback !== null && payback < 12 ? 'text-link' : 'text-ink'} note={t('kpi.paybackNote')} />
      </div>

      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('title', { month })}</b>
          <span className="text-12 text-muted">{t('dayOf', { day: d.day, days: d.days })}</span>
        </div>
        <div className="overflow-x-auto">
          <div className="min-w-[640px]">
            {d.rows.map((r) => {
              const p = pace(r.budget, r.spent, d.day, d.days)
              const cac = observedCac(r)
              const label = p.state === 'none'
                ? (r.spent ? t('pace.noBudgetSpent', { spent: money(r.spent, nf) }) : t('pace.none'))
                : p.state === 'ahead' ? t('pace.ahead', { date: dayOf(p.runsOut ?? d.days) }) : t(`pace.${p.state}`)
              return (
                <div key={r.channel} className={`grid ${ROW} items-center gap-3 border-b border-line px-[18px] py-[11px] text-12.5 last:border-b-0`}>
                  <span className="flex min-w-0 items-center gap-2">
                    <span className="h-[9px] w-[9px] flex-none rounded-3" style={{ background: channelColor(r.channel) }} />
                    <b className="truncate">{ch(r.channel)}</b>
                  </span>
                  <BudgetInput key={`${r.channel}:${r.budget}`} product={product} channel={r.channel} value={r.budget} label={t('inputLabel', { channel: ch(r.channel) })} canEdit={canEdit} />
                  <span className="flex flex-col gap-[3px]">
                    <span className="relative block h-[10px] overflow-hidden rounded-999 bg-tile">
                      <span className="block h-full" style={{ width: `${Math.min(100, p.share * 100)}%`, background: PACE[p.state].bar }} />
                      <span className="absolute bottom-0 top-0 w-[2px] bg-ink" style={{ left: `${gone * 100}%` }} />
                    </span>
                    <span className={`text-11 font-bold ${PACE[p.state].text}`}>{label}</span>
                  </span>
                  <span className="flex flex-col">
                    <b>{kr(cac)}</b>
                    <span className="text-11 text-muted">{t('perPaying', { days: 90 })}</span>
                  </span>
                  <span className="text-12 text-muted">{r.budget && cac ? t('projection', { n: Math.round(r.budget / cac) }) : dash}</span>
                </div>
              )
            })}
          </div>
        </div>
        {!d.attributed ? <p className="m-0 border-t border-line px-[18px] py-[10px] text-11.5 text-muted">{t('noSource', { app })}</p> : null}
      </section>

      {mv && !applied ? (
        <div className="flex flex-wrap items-center gap-3 rounded-18 border border-ink bg-highlight px-[18px] py-[14px]">
          <span className="flex-[1_1_360px] text-13 leading-normal">
            {t.rich('move', {
              amount: money(mv.amount, nf), from: ch(mv.from), to: ch(mv.to), fromCac: money(mv.fromCac, nf), toCac: money(mv.toCac, nf),
              b: (x) => <b>{x}</b>,
            })}
          </span>
          <b className="whitespace-nowrap text-link">{t('gain', { n: formatNumber(mv.gain, nf, Number.isInteger(mv.gain) ? 0 : 1) })}</b>
          <button type="button" onClick={apply} disabled={pending || !canEdit}
            className="h-[34px] cursor-pointer whitespace-nowrap rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold text-ink disabled:cursor-default">
            {t('apply')}
          </button>
        </div>
      ) : null}
      {applied && lm ? (
        <div className="flex flex-wrap items-center gap-3 rounded-18 border border-ink bg-highlight px-[18px] py-[14px]">
          <span className="flex-[1_1_360px] text-13 leading-normal">
            {t.rich('moved', {
              amount: money(lm.amount, nf), from: ch(lm.from), to: ch(lm.to),
              date: format.dateTime(new Date(lm.at), { day: 'numeric', month: 'short', timeZone: 'Europe/Oslo' }), b: (x) => <b>{x}</b>,
            })}
          </span>
          <button type="button" disabled className="h-[34px] cursor-default whitespace-nowrap rounded-10 border border-ink bg-ok-bg px-[14px] text-12.5 font-bold text-ink">
            {t('applied')}
          </button>
        </div>
      ) : null}

      <div className={`${card} flex flex-wrap items-center gap-[14px] px-5 py-4`}>
        <b className="text-14">{t('scenario.title')}</b>
        <span className="text-13">{t('scenario.ifAdd')}</span>
        <input value={extra} onChange={(e) => setExtra(e.target.value.replace(/\D/g, '').slice(0, 9))} inputMode="numeric" aria-label={t('scenario.amount')}
          className="h-[34px] w-[100px] rounded-9 border border-line bg-canvas px-[9px] text-13 font-bold text-ink" />
        <span className="text-13">{t('scenario.toBest')}</span>
        <b className="font-serif text-20 text-link">
          {sc ? (sc.mrr !== null ? t('scenario.result', { n: formatNumber(sc.paying, nf, Number.isInteger(sc.paying) ? 0 : 1), mrr: money(sc.mrr, nf) })
            : t('scenario.resultPaying', { n: formatNumber(sc.paying, nf, Number.isInteger(sc.paying) ? 0 : 1) })) : dash}
        </b>
      </div>
    </div>
  )
}

/** a channel's budget for the month (height 32, radius 9, on the canvas colour); saved when it loses focus or on Enter. Keyed by
 *  the stored amount, so a move or another person's change shows once the view refreshes; nothing removes a budget, so an
 *  emptied field goes back to it. */
function BudgetInput({ product, channel, value, label, canEdit }: { product: string; channel: BudgetChannel; value: number | null; label: string; canEdit: boolean }) {
  const t = useTranslations('simpleGrowth.playbook.budget')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const stored = value === null ? '' : String(Math.round(value))
  const [v, setV] = useState(stored)
  const [pending, start] = useTransition()
  const save = () => {
    if (v === '' || v === stored) { setV(stored); return }
    const amount = Number(v)
    start(async () => {
      const r = await setBudget({ product, channel, amount })
      if (!r.ok) { flash(te(r.code)); return }
      flash(t('saved'))
      router.refresh()
    })
  }
  return (
    <input value={v} onChange={(e) => setV(e.target.value.replace(/\D/g, '').slice(0, 9))} onBlur={save}
      onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }}
      inputMode="numeric" aria-label={label} disabled={!canEdit || pending} placeholder="—"
      className="h-8 w-full min-w-0 rounded-9 border border-line bg-canvas px-[9px] text-12.5 font-semibold text-ink disabled:cursor-default" />
  )
}
