import { formatNumber, percent, type NumberFormat } from '@/lib/format'

/** Pieces Analytics.dc.html repeats: the cards, the KPI tile, the bar row and the empty treatment. */
export const card = 'rounded-20 border border-line bg-surface'
export const cardChart = `${card} px-[22px] py-[18px]`
export const cardTable = `${card} overflow-hidden`
export const title = 'text-15 font-bold'
export const sub = 'text-12 text-muted'
export const tableHead = 'border-b border-line px-[18px] py-[14px]'
export const colHead = 'text-10.5 font-bold uppercase tracking-label text-muted'
export const softPill = (on: boolean) =>
  `cursor-pointer rounded-999 border px-[10px] py-1 text-11.5 text-ink ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`
export const darkPill = (on: boolean) =>
  `cursor-pointer rounded-999 border px-[11px] py-[5px] text-12 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`

/** A signed figure the way the design writes deltas: «+4,9 %», «−0,3». */
export const signed = (s: string, n: number) => (n > 0 ? `+${s}` : n < 0 ? s.startsWith('−') ? s : `−${s}` : s)
export const signedPct = (n: number, nf: NumberFormat) => signed(percent(Math.abs(n), nf), n)
export const signedNum = (n: number, nf: NumberFormat, decimals = 0) => signed(formatNumber(Math.abs(n), nf, decimals), n)
export const deltaTone = (n: number, goodWhenUp = true) => (n === 0 ? 'text-muted' : n > 0 === goodWhenUp ? 'text-link' : 'text-danger')

export function Kpi({ label, value, delta, tone, subText, size = 22, tip }: {
  label: string; value: string; delta?: string | null; tone?: string; subText?: string | null; size?: 22 | 24; tip?: string
}) {
  return (
    <div className="rounded-18 border border-line bg-surface px-4 py-[14px]" title={tip}>
      <div className={colHead}>{label}</div>
      <div className="mt-[6px] flex items-baseline gap-2">
        <span className={`whitespace-nowrap font-serif font-semibold tabular-nums ${size === 24 ? 'text-24' : 'text-22'}`}>{value}</span>
        {delta ? <span className={`text-12 font-bold ${tone ?? 'text-link'}`}>{delta}</span> : null}
      </div>
      {subText ? <div className="mt-[2px] text-11.5 text-muted">{subText}</div> : null}
    </div>
  )
}

/** The design's empty treatment inside a card: a short, muted sentence where the figures would be. */
export function Empty({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <div className={`rounded-15 border border-dashed border-line-strong px-4 py-6 text-center text-12.5 text-muted ${className}`}>{children}</div>
}

/** The shared horizontal bar of the design's lists: a track and a fill of `w` percent. */
export function Track({ w, fill, h = 'h-2' }: { w: number; fill: string; h?: string }) {
  return (
    <span className={`block ${h} overflow-hidden rounded-999 bg-tile`}>
      <span className="block h-full" style={{ width: `${Math.max(0, Math.min(100, w))}%`, background: fill }} />
    </span>
  )
}

/** The chart legend swatch. */
export function Swatch({ color, line = false }: { color: string; line?: boolean }) {
  return line
    ? <span className="h-[3px] w-[14px] rounded-2" style={{ background: color }} />
    : <span className="h-[10px] w-[10px] rounded-3 border border-[rgba(25,21,16,.15)]" style={{ background: color }} />
}
