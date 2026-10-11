import Link from 'next/link'
import type { Route } from 'next'
import { getLocale, getTranslations } from 'next-intl/server'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import type { Trial } from '@/lib/growth/playbook'
import { growthHref } from '@/lib/growth/scope'
import { Tile, card } from '../v2kit'

const EMAIL_STEPS = new Set(['send_email', 'email_auto', 'email_manual', 'campaign_action'])
const UNITS = new Set(['minutes', 'hours', 'days', 'weeks'])

/** a change in the design's KPI colours: green when it went the right way, red when not */
function Change({ v, text, lowerIsBetter = false }: { v: number | null; text: string; lowerIsBetter?: boolean }) {
  if (v === null || v === 0) return null
  const good = lowerIsBetter ? v < 0 : v > 0
  return <span className={`whitespace-nowrap text-12 font-bold ${good ? 'text-link' : 'text-danger'}`}>{text}</span>
}

/**
 * Email and automation › Trial and abandoned signup (GrowthPlaybook.dc.html, v.trial) on growth_trial (0076): trial to
 * paid over 90 days against the 90 before, the median days to the first survey, the visits that began the signup and did
 * not finish it, and the flows that start from what an account does in the product. A control group needs a holdout the
 * engine does not have, and an abandoned visit leaves no address to write to, so «Recovered» is «—» (V-GR2-39).
 */
export async function TrialView({ d, nf, app }: { d: Trial; nf: NumberFormat; app: string }) {
  const t = await getTranslations('simpleGrowth.playbook.trial')
  const tm = await getTranslations('customers.milestones')
  const tk = await getTranslations('automation.monitor.chips')
  const locale = await getLocale()
  const dash = '—'
  const sign = (v: number, dec = 0) => `${v > 0 ? '+' : '−'}${formatNumber(Math.abs(v), nf, dec)}`
  const date = (iso: string) => new Intl.DateTimeFormat(locale === 'no' ? 'nb-NO' : locale, { day: 'numeric', month: 'short', timeZone: 'Europe/Oslo' }).format(new Date(iso))

  const rate = d.trials.ended ? d.trials.converted / d.trials.ended : null
  const ratePrev = d.trials.ended_prev ? d.trials.converted_prev / d.trials.ended_prev : null
  const pts = rate !== null && ratePrev !== null ? Math.round((rate - ratePrev) * 1000) / 10 : null
  const fs = d.first_survey
  const fsDelta = fs.days !== null && fs.days_prev !== null ? Math.round((fs.days - fs.days_prev) * 10) / 10 : null
  const lateTracker = d.tracked_since && Date.parse(d.tracked_since) > Date.now() - 30 * 86_400_000

  const when = (f: Trial['flows'][number]) => {
    const data = f.trigger_data ?? {}
    if (f.trigger === 'org.created') return t('trigger.org_created')
    if (f.trigger === 'milestone.reached') {
      const key = typeof data.key === 'string' ? data.key : null
      return key ? t('trigger.milestone', { name: tm.has(key) ? tm(key) : key }) : t('trigger.milestone_any')
    }
    const state = typeof data.payment_state === 'string' ? data.payment_state : null
    return state ? t('trigger.billing_state', { state: t.has(`payment.${state}`) ? t(`payment.${state}`) : state }) : t('trigger.billing')
  }
  const step = (s: Trial['flows'][number]['steps'][number]) => {
    if (s.kind === 'delay') return s.amount !== null && s.unit && UNITS.has(s.unit) ? `◷ ${t(`delay.${s.unit}`, { n: s.amount })}` : `◷ ${tk('delay')}`
    const kind = tk.has(s.kind) ? tk(s.kind) : s.kind
    if (EMAIL_STEPS.has(s.kind)) return s.email ? `✉ «${s.email}»` : `✉ ${kind}`
    return `✓ ${kind}`
  }

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        <Tile size={23} label={t('kpi.trial')} value={rate !== null ? percent(rate * 100, nf) : dash}
          delta={pts !== null ? <Change v={pts} text={t('pts', { n: sign(pts, Number.isInteger(pts) ? 0 : 1) })} /> : null}
          note={d.trials.ended ? t('kpi.trialNote', { n: d.trials.ended }) : t('kpi.trialNone')} />
        <Tile size={23} label={t('kpi.firstSurvey')} value={fs.days !== null ? t('days', { n: formatNumber(fs.days, nf, 1) }) : dash}
          delta={fsDelta !== null ? <Change v={fsDelta} lowerIsBetter text={sign(fsDelta, 1)} /> : null}
          note={fs.accounts ? t('kpi.firstSurveyNote', { n: fs.accounts }) : t('kpi.firstSurveyNone')} />
        <Tile size={23} label={t('kpi.abandoned')} value={d.tracked_since ? formatNumber(d.abandoned.n, nf) : dash}
          note={!d.tracked_since ? t('kpi.noTracker') : lateTracker ? t('kpi.abandonedSince', { date: date(d.tracked_since) }) : t('kpi.abandonedNote')} />
        <Tile size={23} label={t('kpi.recovered')} value={dash} note={t('kpi.recoveredNone')} />
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
        <section className={`${card} flex flex-col gap-2 px-[18px] py-4`}>
          <div className="flex flex-wrap items-baseline justify-between gap-x-3">
            <b className="text-15">{t('flows')}</b>
            <span className="text-12 text-muted">{t('flowsNote', { app })}</span>
          </div>
          {!d.flows.length ? <p className="m-0 text-12.5 leading-[1.5] text-muted">{t('flowsEmpty')}</p> : null}
          {d.flows.map((f) => (
            <div key={f.id} className="flex flex-col gap-[6px] rounded-15 border border-line bg-canvas px-[13px] py-[11px]">
              <div className="flex justify-between gap-[10px]">
                <b className="text-12.5">{t('if', { when: when(f) })}</b>
                <span className="whitespace-nowrap text-11.5 text-muted">{t('inFlow', { n: f.in_flow })}</span>
              </div>
              {f.steps.map((s, i) => <span key={i} className="text-12 [overflow-wrap:anywhere]">{step(s)}</span>)}
              {!f.steps.length ? <span className="text-12 text-muted">{t('noSteps')}</span> : null}
              <span className={`text-11.5 font-bold ${f.state === 'active' ? 'text-link' : 'text-muted'}`}>
                {f.state === 'active' ? t('live', { name: f.name, n: f.completed_90 }) : t('notLive', { name: f.name })}
              </span>
            </div>
          ))}
        </section>

        <section className={`${card} flex flex-col gap-[10px] px-[18px] py-4`}>
          <b className="text-15">{t('recovery.title')}</b>
          <span className="text-12 leading-[1.5] text-muted">{t('recovery.why')}</span>
          <span className="text-12 leading-[1.5] text-muted">
            {t.rich('recovery.funnel', { link: (x) => <Link href={growthHref('funnel', {}) as Route}>{x}</Link> })}
          </span>
          <div className="flex justify-between border-t border-tile pt-[10px] text-13">
            <span>{t('recovery.total')}</span>
            <b>{d.tracked_since ? formatNumber(d.abandoned.n, nf) : dash}</b>
          </div>
        </section>
      </div>
    </div>
  )
}
