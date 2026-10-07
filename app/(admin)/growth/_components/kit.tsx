import { percent, type NumberFormat } from '@/lib/format'
import { colHead, deltaTone, signed } from '../../analytics/_components/kit'

/** Pieces SimpleGrowth.dc.html and GrowthMarketing.dc.html repeat (the Analytics kit's column head and deltas reused). */
export { colHead }
export const card = 'rounded-20 border border-line bg-surface'
export const cardTable = `${card} overflow-hidden`
export const cardHead = 'flex justify-between border-b border-line px-[18px] py-[14px]'
export const rowLine = 'border-b border-line px-[18px] py-[9px]'
export const mono = 'font-[ui-monospace,Menlo,monospace]'
/** The muted one-line empty treatment inside a table card. */
export const emptyRow = 'border-b border-line px-[18px] py-4 text-12.5 text-muted'

/** A whole-percent change the way the design writes it: «+12 %», «−9 %» (null without a base). */
export function pctDelta(now: number | null, prev: number | null, nf: NumberFormat): { text: string; tone: string } | null {
  if (now === null || prev === null || prev === 0) return null
  const d = Math.round((now / prev - 1) * 100)
  return { text: signed(percent(Math.abs(d), nf), d), tone: deltaTone(d) }
}

/** The KPI tile (kpis[], seoKpis[]): radius 18, the label, the serif value at 25 px and its delta. */
export function Tile({ label, value, delta, title }: { label: string; value: string; delta?: { text: string; tone: string } | null; title?: string }) {
  return (
    <div className="rounded-18 border border-line bg-surface px-4 py-[14px]" title={title}>
      <div className={colHead}>{label}</div>
      <div className="mt-[6px] flex items-baseline gap-2">
        <span className="whitespace-nowrap font-serif text-[25px] font-semibold">{value}</span>
        {delta ? <span className={`text-12 font-bold ${delta.tone}`}>{delta.text}</span> : null}
      </div>
    </div>
  )
}
