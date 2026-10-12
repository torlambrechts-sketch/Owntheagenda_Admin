/** DevHub.dc.html's recurring controls, transcribed from its inline styles. */
export const c = {
  card: 'rounded-20 border border-line bg-surface',
  head: 'flex justify-between gap-2 border-b border-line px-[18px] py-3',
  headTitle: 'text-15 font-bold',
  headNote: 'text-12 text-muted',
  label: 'text-11 font-bold uppercase tracking-[.1em] text-muted',
  kpiLabel: 'text-10.5 font-bold uppercase tracking-label text-muted',
  mono: 'font-[ui-monospace,Menlo,monospace]',
  /** the filter chips (chip(on): highlight and ink when chosen) */
  chip: (on: boolean) => `cursor-pointer whitespace-nowrap rounded-999 border px-[11px] py-[5px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`,
  /** «＋ New feature file»: 32 px, dashed ink */
  dashed: 'h-8 cursor-pointer whitespace-nowrap rounded-9 border border-dashed border-ink bg-transparent px-3 text-12 font-semibold text-ink disabled:cursor-default disabled:opacity-50',
  /** the 28 px row buttons (Merge duplicate, Mark fixed) */
  rowBtn: 'h-7 cursor-pointer whitespace-nowrap rounded-8 border border-line bg-transparent px-[10px] text-11.5 font-bold text-ink disabled:cursor-default disabled:opacity-50',
  rowBtnPrimary: 'h-7 cursor-pointer whitespace-nowrap rounded-8 border border-ink bg-primary px-[10px] text-11.5 font-bold text-ink disabled:cursor-default disabled:opacity-50',
  // the dialog's fields (SimpleCRM.dc.html's modal: label over a 40 px field)
  field: 'flex flex-col gap-[5px] text-12 font-semibold text-muted',
  input: 'h-10 min-w-0 rounded-10 border border-line bg-canvas px-3 text-13 text-ink',
  select: 'h-10 min-w-0 rounded-10 border border-line bg-canvas px-2 text-13 text-ink',
  textarea: 'min-h-[90px] rounded-12 border border-line bg-canvas px-3 py-[10px] text-13 leading-[1.55] text-ink',
  small: 'h-[34px] cursor-pointer whitespace-nowrap rounded-10 border border-line bg-transparent px-3 text-12.5 font-semibold text-ink disabled:cursor-default disabled:opacity-50',
  smallPrimary: 'h-[34px] cursor-pointer whitespace-nowrap rounded-10 border border-ink bg-primary px-3 text-12.5 font-bold text-ink disabled:cursor-default disabled:opacity-50',
}

/** an application as Development shows it: its key, name and colour (Sentral's own from the design) */
export type ProductInfo = { key: string; name: string; color: string }
