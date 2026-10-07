'use client'

import { useTranslations } from 'next-intl'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Jobs } from '@/lib/data/platform'
import { jobRetry } from '../actions'
import { k, useAct, useAgo } from './kit'

type Job = Jobs['jobs'][number]
const PILL = { running: 'bg-teal-soft text-ok-ink', queued: 'bg-highlight text-amber-ink', succeeded: 'bg-ok-bg text-ok-ink', failed: 'bg-salmon text-rust-ink' } as const
const ORDER = { failed: 0, running: 1, queued: 2, succeeded: 3 } as const

/**
 * The job monitor (Appendix 2 System operations): the platform's registered jobs (job_defs) with their last run, and the
 * four counts. Every-minute jobs write a run only when they did work or failed (V-P8P-09); a product's own jobs appear
 * once it reports them (job.run, D-40).
 */
export function JobsView({ jobs, products, canConfigure, nf }: { jobs: Jobs; products: Record<string, string>; canConfigure: boolean; nf: NumberFormat }) {
  const t = useTranslations('platform.jobs')
  const tl = useTranslations('platform.jobLabels')
  const ago = useAgo()
  const { run, pending, flash } = useAct()
  const s = jobs.stats
  const stats: [string, number, string][] = [
    [t('queued'), s.queued, 'text-ink'], [t('running'), s.running, 'text-ink'], [t('failed24'), s.failed_24h, 'text-danger'], [t('succeeded24'), s.succeeded_24h, 'text-link'],
  ]
  const sorted = [...jobs.jobs].sort((a, b) => {
    const sa = a.last_state ? ORDER[a.last_state] : 9
    const sb = b.last_state ? ORDER[b.last_state] : 9
    if (sa !== sb) return sa - sb
    return (b.last_run_at ?? '').localeCompare(a.last_run_at ?? '')
  })
  const label = (j: Job) => {
    const key = j.label_key.replace(/^jobs\./, '')
    return tl.has(key) ? tl(key) : j.key
  }
  const info = (j: Job) => {
    const r = j.last_run
    if (!r) return j.quiet && j.last_state === 'succeeded' ? t('quiet') : '—'
    if (r.state === 'failed' && r.error) return r.error
    const parts = Object.entries(r.info).filter(([, v]) => typeof v === 'number' || typeof v === 'string')
    if (!parts.length) return '—'
    return parts.map(([key, v]) => (typeof v === 'number' ? t.has(`info.${key}`) ? t(`info.${key}`, { count: formatNumber(v, nf) }) : `${key} ${formatNumber(v, nf)}` : `${key} ${String(v)}`)).join(' · ')
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-[10px] [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        {stats.map(([n, v, c]) => (
          <div key={n} className="rounded-16 border border-line bg-surface px-[14px] py-3">
            <div className="text-10.5 font-bold uppercase tracking-label text-muted">{n}</div>
            <div className={`font-serif text-24 font-semibold ${c}`}>{formatNumber(v, nf)}</div>
          </div>
        ))}
      </div>
      <div className={k.card}>
        {!canConfigure ? <div className="border-b border-line px-[18px] py-[9px] text-12 text-muted">{t('readOnly')}</div> : null}
        {sorted.map((j) => {
          const st = j.last_state
          const failed = st === 'failed' && j.last_run?.state === 'failed'
          return (
            <div key={j.key} className={`${k.row} grid items-center gap-[10px] py-[10px] [grid-template-columns:minmax(0,1.4fr)_110px_100px_minmax(0,1.2fr)_80px] max-md:[grid-template-columns:minmax(0,1fr)_auto]`}>
              <span className="flex min-w-0 flex-col">
                <b>{label(j)}</b>
                <span className="text-11.5 text-muted">{[j.product ? products[j.product] ?? j.product : 'Sentral', t(`source.${j.source}`)].join(' · ')}</span>
              </span>
              <span>
                <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${st ? PILL[st] : 'bg-beige text-muted'}`}>{st ? t(`state.${st}`) : t('state.never')}</span>
              </span>
              <span className="text-muted max-md:hidden">{ago(j.last_run_at)}</span>
              <span className="break-words text-muted max-md:hidden">{info(j)}</span>
              {failed && j.last_run ? (
                <button
                  type="button"
                  disabled={!canConfigure || pending}
                  onClick={() => run(() => jobRetry(j.last_run!.id), () => flash(t('retried', { name: label(j) })))}
                  className="h-7 cursor-pointer rounded-9 border border-ink bg-primary text-12 font-bold disabled:cursor-default disabled:opacity-60 max-md:col-span-2"
                >
                  {t('retry')}
                </button>
              ) : <span className="max-md:hidden" />}
            </div>
          )
        })}
      </div>
    </div>
  )
}
