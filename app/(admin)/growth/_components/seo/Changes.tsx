import { getLocale, getTranslations } from 'next-intl/server'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { changeResult, type SeoChanges } from '@/lib/growth/seo'
import { card, mono } from '../v2kit'
import { ChangeForm } from './controls'

const COLS = '[grid-template-columns:80px_minmax(0,1.3fr)_minmax(0,1.5fr)_80px_80px_70px_90px]'
const PILL: Record<'win' | 'small' | 'none' | 'loss' | 'measuring', string> = {
  win: 'bg-ok-bg text-ok-ink', small: 'bg-teal-soft text-ok-ink', none: 'bg-tile text-muted', loss: 'bg-peach text-danger', measuring: 'bg-highlight text-amber-ink',
}

/**
 * SEO › Change log (SeoSuite.dc.html, v.changes) on seo_changes_get (0074). A change is logged by hand, by the content plan
 * («Published») or by «Add link». Its result compares Search Console's 28 days after with the 28 before, for the page (or,
 * for a new page not yet known by its address, the search); until 28 days are reported it is «Measuring». A drop of 10 %
 * or more is a «Loss», which the design does not have (V-GR2-30).
 */
export async function SeoChangesView({ d, nf, product, site = null, canAdd }: { d: SeoChanges; nf: NumberFormat; product: string; site?: string | null; canAdd: boolean }) {
  const t = await getTranslations('simpleGrowth.seoSuite.changes')
  const locale = await getLocale()
  const loc = locale === 'no' ? 'nb-NO' : locale
  const short = (iso: string) => new Intl.DateTimeFormat(loc, { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(`${iso}T12:00:00Z`))

  // the chart: the last 60 days, a point per reported day, a mark per change in the window
  const today = new Date(`${new Date().toISOString().slice(0, 10)}T00:00:00Z`).getTime()
  const idx = (iso: string) => 59 - Math.round((today - new Date(`${iso}T00:00:00Z`).getTime()) / 86_400_000)
  const pts = d.daily.map((x) => ({ i: idx(x.day), v: x.clicks })).filter((p) => p.i >= 0 && p.i <= 59)
  const mx = Math.max(1, ...pts.map((p) => p.v))
  const line = pts.map((p) => `${((p.i * 600) / 59).toFixed(1)},${(136 - (p.v / mx) * 128).toFixed(1)}`).join(' ')
  const area = pts.length ? `${((pts[0]!.i * 600) / 59).toFixed(1)},136 ${line} ${((pts[pts.length - 1]!.i * 600) / 59).toFixed(1)},136` : ''
  const marks = d.changes.map((c) => ({ c, i: idx(c.day) })).filter((m) => m.i >= 0 && m.i <= 59)
  const where = (c: SeoChanges['changes'][number]) => c.path ?? `«${c.query}»`
  const signed = (v: number, unit: string) => `${v >= 0 ? '+' : '−'}${formatNumber(Math.abs(v), nf, Number.isInteger(v) ? 0 : 1)}${unit}`

  return (
    <div className="flex flex-col gap-[14px]">
      {canAdd ? (
        <section className={`${card} flex flex-wrap items-center gap-2 px-[18px] py-[14px]`}>
          <b className="mr-[6px] text-14">{t('log')}</b>
          <ChangeForm product={product} site={site} pages={d.pages} />
          {!d.pages.length ? <span className="text-12 text-muted">{t('noPages')}</span> : null}
        </section>
      ) : null}
      <section className={`${card} px-5 py-4`}>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          <b className="text-15">{t('chart')}</b>
          <span className="text-12 text-muted">{t('chartNote')}</span>
        </div>
        {pts.length > 1 ? (
          <div className="relative">
            <svg viewBox="0 0 600 140" preserveAspectRatio="none" className="block h-[140px] w-full" aria-hidden>
              <polygon points={area} fill="#E4EEEC" />
              <polyline points={line} fill="none" stroke="#5C9A55" strokeWidth={2} vectorEffect="non-scaling-stroke" />
            </svg>
            {marks.map(({ c, i }) => (
              <span key={c.id} title={`${short(c.day)} · ${t(`kinds.${c.kind}`)} · ${where(c)}`} className="absolute bottom-0 top-0 w-[2px] bg-primary" style={{ left: `${(i / 59) * 100}%` }}>
                <span className="absolute left-[-5px] top-[-4px] h-3 w-3 rounded-999 border-[1.5px] border-ink bg-primary" />
              </span>
            ))}
          </div>
        ) : <p className="m-0 text-12.5 text-muted">{t('noDaily')}</p>}
      </section>
      <section className={`${card} overflow-x-auto`}>
        <div className="min-w-[680px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-[.08em] text-muted ${COLS}`}>
            <span>{t('cols.date')}</span><span>{t('cols.page')}</span><span>{t('cols.change')}</span><span>{t('cols.clicks')}</span>
            <span>{t('cols.position')}</span><span>{t('cols.ctr')}</span><span>{t('cols.result')}</span>
          </div>
          {!d.changes.length ? <p className="m-0 px-[18px] py-[14px] text-12.5 text-muted">{t('empty')}</p> : null}
          {d.changes.map((c) => {
            const r = changeResult(c)
            const tone = (v: number | null) => (v === null || v === 0 ? 'text-faint' : v > 0 ? 'text-link' : 'text-danger')
            return (
              <div key={c.id} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 tabular-nums ${COLS}`}>
                <span className="text-muted">{short(c.day)}</span>
                <span className={`${mono} text-11.5 [overflow-wrap:anywhere]`}>{where(c)}</span>
                <span className="flex flex-col">
                  <b>{t(`kinds.${c.kind}`)}</b>
                  {c.note ? <span className="text-11.5 text-muted">{c.note}</span> : null}
                </span>
                <span className={`font-bold ${tone(r.clicks)}`}>{r.clicks === null ? '—' : `${r.clicks >= 0 ? '+' : '−'}${percent(Math.abs(r.clicks), nf)}`}</span>
                <span className={`font-bold ${tone(r.position)}`}>{r.position === null ? '—' : r.position === 0 ? '0' : `${r.position > 0 ? '▲' : '▼'} ${formatNumber(Math.abs(r.position), nf, Number.isInteger(r.position) ? 0 : 1)}`}</span>
                <span>{r.ctr === null ? '—' : t('pts', { v: signed(r.ctr, '') })}</span>
                <span>{r.verdict ? <span className={`whitespace-nowrap rounded-999 px-[9px] py-[2px] text-11 font-bold ${PILL[r.verdict]}`}>{t(`result.${r.verdict}`)}</span> : '—'}</span>
              </div>
            )
          })}
        </div>
      </section>
    </div>
  )
}

