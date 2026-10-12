'use client'

import { useTranslations } from 'next-intl'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import {
  emailRows, emailTips, heatGrid, hourText, windowDays, windowOff, type EmailTip, type HeatBand, type SendTimes, type SendWindow, type SequenceResults,
} from '@/lib/growth/v3'
import { TipBox } from './TipBox'

const COLS = '[grid-template-columns:minmax(0,1.6fr)_50px_54px_54px_54px_56px]'
const card = 'flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-5 py-4'
/** the design's four fills, and the empty treatment of a cell with too few sends */
const FILL: Record<HeatBand, string> = {
  high: 'bg-link', midhigh: 'bg-teal-mid', mid: 'bg-ok-bg', low: 'bg-tile', none: 'border border-dashed border-line bg-transparent',
}

/**
 * Email and automation's two new cards under the editor (GrowthMarketing.dc.html, v.email): «Results per step» for the
 * chosen sequence over the last 30 days with the three email tips, and «Best time to send»: the application's open rate by
 * send weekday and hour (Oslo, 90 days), «Best:» from the data and «Send all steps at the best time», a per-sequence
 * setting the engine honours (0083). «Create A/B test» stays off: an automated email has no subject B (V-P6C-11).
 */
export function EmailInsights({ name, results, loading, steps, times, nf, editable, pending, onAddCondition, onWindow }: {
  name: string
  results: SequenceResults | null
  loading: boolean
  steps: { kind: string; cond?: string }[]
  times: SendTimes | null
  nf: NumberFormat
  editable: boolean
  pending: boolean
  onAddCondition: (step: number, email: number) => void
  onWindow: (on: boolean) => void
}) {
  const t = useTranslations('simpleGrowth.v3')
  const dash = '—'
  const dow = (d: number) => t(`dow.${d}`)
  const rows = results ? emailRows(results) : []
  const best = times?.best ?? null
  const tips: EmailTip[] = results ? emailTips(results, steps, best) : []
  const win: SendWindow | null = results?.send_window ?? null
  const grid = times ? heatGrid(times) : null
  const rate = (v: number | null) => (v === null ? dash : percent(v, nf))
  const why = windowOff({ editable, hasEmail: steps.some((s) => s.kind === 'email'), on: !!win, times })
  const off = why === 'readOnly' ? t('readOnly') : why === 'noEmail' ? t('best.noEmail') : why === 'unread' ? t('best.unread')
    : why === 'notYet' && times ? t('best.notYet', { min: times.min, days: times.days }) : null

  const tipBox = (x: EmailTip) => {
    if (x.kind === 'ab') {
      return <TipBox key="ab" text={t('emailTips.ab', { n: x.email, rate: percent(Math.round(x.rate), nf) })} cta={t('emailTips.abCta')} disabled reason={t('emailTips.abOff')} />
    }
    if (x.kind === 'cond') {
      return (
        <TipBox key="cond" text={t('emailTips.cond', { n: x.email, share: percent(Math.round(x.share), nf) })} cta={t('emailTips.condCta')}
          onClick={() => onAddCondition(x.step, x.email)} disabled={!editable} reason={editable ? null : t('readOnly')} />
      )
    }
    return (
      <TipBox key="time" text={t('emailTips.time', { days: windowDays(x.days, dow), hour: hourText(x.hour) })} cta={t('emailTips.timeCta')}
        onClick={() => onWindow(true)} disabled={!editable || pending} reason={editable ? null : t('readOnly')} />
    )
  }

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={card}>
        <div className="flex items-baseline justify-between gap-[10px]"><b className="text-15">{t('results.title', { name })}</b><span className="whitespace-nowrap text-12 text-muted">{t('results.window', { days: results?.days ?? 30 })}</span></div>
        <div className="overflow-x-auto">
          <div role="table" aria-label={t('results.title', { name })} className="flex min-w-[400px] flex-col gap-[10px]">
            <div role="row" className={`grid gap-2 border-b border-line pb-[6px] text-10.5 font-bold uppercase tracking-[.08em] text-muted ${COLS}`}>
              <span role="columnheader">{t('results.cols.email')}</span><span role="columnheader">{t('results.cols.sent')}</span>
              <span role="columnheader">{t('results.cols.open')}</span><span role="columnheader">{t('results.cols.click')}</span>
              <span role="columnheader">{t('results.cols.unsub')}</span><span role="columnheader">{t('results.cols.signups')}</span>
            </div>
            {rows.map((r) => (
              <div key={r.step} role="row" className={`grid items-center gap-2 border-b border-tile py-[5px] text-12.5 tabular-nums ${COLS}`}>
                <span role="cell" className="overflow-hidden text-ellipsis whitespace-nowrap" title={r.subject}><b>{r.subject}</b></span>
                <span role="cell" title={r.sent === null ? t('results.noReports') : undefined}>{r.sent === null ? dash : formatNumber(r.sent, nf)}</span>
                <b role="cell" className={r.openLow ? 'text-danger' : 'text-ink'}>{rate(r.open)}</b>
                <span role="cell" className={r.clickLow ? 'text-danger' : 'text-ink'}>{rate(r.click)}</span>
                <span role="cell">{rate(r.unsub)}</span>
                <b role="cell" className="text-link">{r.signups === null ? dash : formatNumber(r.signups, nf)}</b>
              </div>
            ))}
          </div>
        </div>
        {loading ? <div className="text-12 text-muted">{t('results.loading')}</div> : null}
        {!loading && results && rows.length === 0 ? <div className="text-12 text-muted">{t('results.empty')}</div> : null}
        {!loading && !results ? <div className="text-12 text-muted">{t('results.failed')}</div> : null}
        {tips.map(tipBox)}
        {rows.length ? <div className="text-11.5 text-muted">{t('results.note')}</div> : null}
      </div>

      <div className={card}>
        <div className="flex items-baseline justify-between gap-[10px]"><b className="text-15">{t('best.title')}</b><span className="text-right text-12 text-muted">{t('best.subtitle')}</span></div>
        {grid && times ? (
          <>
            <div className="overflow-x-auto">
              <div role="table" aria-label={t('best.subtitle')} className="grid min-w-[300px] gap-[3px] text-10.5 [grid-template-columns:34px_repeat(12,minmax(0,1fr))]">
                <div role="row" className="contents">
                  <span role="columnheader" />
                  {grid.rows[0]!.cells.map((c) => <span key={c.hour} role="columnheader" className="text-center text-faint">{String(c.hour).padStart(2, '0')}</span>)}
                </div>
                {grid.rows.map((r) => (
                  <div key={r.dow} role="row" className="contents">
                    <span role="rowheader" className="self-center font-semibold text-muted">{dow(r.dow)}</span>
                    {r.cells.map((c) => {
                      const tip = c.rate === null
                        ? t('best.cellThin', { day: dow(c.dow), hour: hourText(c.hour), n: c.delivered, min: times.min })
                        : t('best.cell', { day: dow(c.dow), hour: hourText(c.hour), rate: percent(Math.round(c.rate), nf), n: c.delivered })
                      return (
                        <span key={c.hour} role="cell" title={tip} aria-label={tip}
                          className={`box-border h-[22px] rounded-5 ${FILL[c.band]} ${c.best ? 'border-2 border-solid border-primary' : ''}`} />
                      )
                    })}
                  </div>
                ))}
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-3 text-11.5 text-muted">
              <span className="flex items-center gap-1"><span className="h-3 w-3 rounded-3 bg-tile" />{t('best.low')}</span>
              <span className="flex items-center gap-1"><span className="h-3 w-3 rounded-3 bg-teal-mid" />{t('best.medium')}</span>
              <span className="flex items-center gap-1"><span className="h-3 w-3 rounded-3 bg-link" />{t('best.high')}</span>
              <span>{best
                ? t.rich('best.best', { slot: `${dow(best.dow)} ${hourText(best.hour)}`, rate: percent(Math.round((best.opened / best.delivered) * 100), nf), b: (x) => <b className="text-ink">{x}</b> })
                : t.rich('best.none', { b: (x) => <b className="text-ink">{x}</b> })}</span>
            </div>
            <div className="flex flex-col gap-[2px] text-11.5 text-muted">
              <span>{t('best.note', { days: times.days, min: times.min })}</span>
              {grid.outside > 0 ? <span>{t('best.outside', { n: grid.outside })}</span> : null}
            </div>
          </>
        ) : <div className="text-12 text-muted">{t('best.failed')}</div>}
        <button
          type="button"
          onClick={() => onWindow(!win)}
          disabled={!!off || pending}
          aria-pressed={!!win}
          title={win ? t('best.offTitle') : off ?? undefined}
          className="h-8 cursor-pointer self-start whitespace-nowrap rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-not-allowed disabled:opacity-50"
        >
          {win ? t('best.on', { days: windowDays(win.days, dow), hour: hourText(win.hour) }) : t('best.button')}
        </button>
        {off && !win ? <div className="-mt-1 text-12 text-muted">{off}</div> : null}
        {win ? <div className="-mt-1 text-12 text-muted">{t('best.onNote')}</div> : null}
      </div>
    </div>
  )
}
