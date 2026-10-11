import Link from 'next/link'
import type { Route } from 'next'
import { percent, type NumberFormat } from '@/lib/format'
import { colHead } from '../../analytics/_components/kit'

/** Pieces SimpleGrowth.dc.html (11 Oct 2026) repeats across its tabs. */
export const card = 'rounded-20 border border-line bg-surface'
export const cardTable = `${card} overflow-hidden`
/** a card head: padding 13×18 (12×18 on Pages, SEO and the log), title 15 bold, a muted 12 px note */
export const head = 'flex items-baseline justify-between gap-3 border-b border-line px-[18px] py-[13px]'
export const head12 = 'flex items-baseline justify-between gap-3 border-b border-line px-[18px] py-3'
export const mono = 'font-[ui-monospace,Menlo,monospace]'
export const label11 = 'text-11 font-bold uppercase tracking-[.1em] text-muted'
export { colHead }
/** the muted line a card shows when there is nothing to list */
export const emptyLine = 'p-6 text-center text-13 text-muted'

/** The design's swatch per channel (SRC[][3]); channel_rules' keys */
export const CHANNEL_COLOR: Record<string, string> = {
  organic_search: '#5C9A55', paid_search: '#E0A21F', direct: '#C4BCA8', social: '#6E8FB8', referral: '#8F74B3', email: '#D4633A',
  paid_social: '#B5DAD4', partner: '#8F74B3',
}
export const channelColor = (c: string) => CHANNEL_COLOR[c] ?? '#C4BCA8'

/** «+12 %» / «−9 %» in the design's colours (green when up, unless lower is better) */
export function Delta({ change, lowerIsBetter = false, nf }: { change: number | null; lowerIsBetter?: boolean; nf: NumberFormat }) {
  if (change === null) return null
  const good = lowerIsBetter ? change <= 0 : change >= 0
  return (
    <span className={`whitespace-nowrap text-12 font-bold ${good ? 'text-link' : 'text-danger'}`}>
      {(change >= 0 ? '+' : '−') + percent(Math.abs(change), nf)}
    </span>
  )
}

/** A KPI tile (kpis[]: radius 18, padding 13×15, the serif value at 24 px); a link when it picks something */
export function Tile({ label, value, delta, href, on = false, size = 24, note, title }: {
  label: string; value: string; delta?: React.ReactNode; href?: string; on?: boolean; size?: 23 | 24; note?: string | null; title?: string
}) {
  const body = (
    <>
      <div className={colHead}>{label}</div>
      <div className="mt-[5px] flex items-baseline gap-2">
        <span className={`whitespace-nowrap font-serif font-semibold text-ink ${size === 23 ? 'text-23' : 'text-24'}`}>{value}</span>
        {delta}
      </div>
      {note ? <div className="text-11.5 text-muted">{note}</div> : null}
    </>
  )
  const cls = `block rounded-18 border px-[15px] py-[13px] text-left ${on ? 'border-ink bg-highlight' : 'border-line bg-surface'}`
  return href
    ? <Link href={href as Route} aria-current={on ? 'true' : undefined} title={title} className={`${cls} cursor-pointer text-ink hover:text-ink hover:no-underline`}>{body}</Link>
    : <div className={cls} title={title}>{body}</div>
}

/** «Fri 9 Oct» (en) / «fre. 9. okt.» (no), for a plain date */
export function dayLabel(iso: string, locale: string): string {
  const d = new Date(`${iso}T12:00:00Z`)
  const loc = locale === 'no' ? 'nb-NO' : locale
  return new Intl.DateTimeFormat(loc, { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' }).format(d).replace(',', '')
}

export const hh = (h: number) => `${String(h).padStart(2, '0')}:00`

/** a bar's fill in a track (the funnel's steps, the step card's reasons and segments, the page's sources) */
export function Bar({ w, color, h = 8, round = 'rounded-999', track = 'bg-tile' }: { w: number; color: string; h?: 8 | 9 | 10 | 20; round?: string; track?: string }) {
  const hc = h === 20 ? 'h-5' : h === 10 ? 'h-[10px]' : h === 9 ? 'h-[9px]' : 'h-2'
  return (
    <span className={`block ${hc} overflow-hidden ${round} ${track}`}>
      <span className="block h-full" style={{ width: `${Math.max(0, Math.min(100, w))}%`, background: color }} />
    </span>
  )
}
