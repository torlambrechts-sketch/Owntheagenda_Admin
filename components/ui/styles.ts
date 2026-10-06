/**
 * Class strings for the design's recurring controls, transcribed from the bundle's inline styles. A screen
 * uses these rather than restating the values, so one control looks the same everywhere.
 */
export const ui = {
  // cards
  card: 'rounded-20 border border-line bg-surface',
  cardPad: 'rounded-20 border border-line bg-surface px-[22px] py-5',
  // the uppercase label over a value or a column
  eyebrow: 'text-11 font-bold uppercase tracking-eyebrow text-muted',
  colHead: 'text-10.5 font-bold uppercase tracking-label text-muted',
  // buttons
  btnPrimary: 'h-9 cursor-pointer rounded-10 border border-ink bg-primary px-4 text-12.5 font-bold',
  btnGhost: 'h-9 cursor-pointer rounded-10 border border-line bg-transparent px-4 text-12.5 font-semibold',
  btnSmall: 'h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-3 text-12 font-semibold',
  btnDark: 'h-9 cursor-pointer rounded-10 border border-ink bg-ink px-4 text-12.5 font-bold text-canvas',
  // a link that looks like plain text (navigation rows, cards)
  plainLink: 'text-ink hover:text-ink hover:no-underline',
  // pill tabs (notifications, filters)
  pill: (on: boolean) => `cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium'}`,
  pillSoft: (on: boolean) => `cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`,
  // inputs
  input: 'h-[38px] rounded-10 border border-line bg-canvas px-3 text-13',
  select: 'h-[30px] rounded-8 border border-line bg-canvas text-12',
  serifValue: 'font-serif font-semibold tabular-nums leading-none',
}
