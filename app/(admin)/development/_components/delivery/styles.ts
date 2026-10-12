/** DevHub.dc.html's and DevClaude.dc.html's recurring controls for the delivery views, transcribed from their inline styles. */
export const d = {
  card: 'rounded-20 border border-line bg-surface',
  /** the release card, the gate card, the selected file: an ink border */
  cardInk: 'rounded-20 border border-ink bg-surface',
  head: 'flex justify-between gap-2 border-b border-line px-[18px] py-3',
  headTitle: 'text-15 font-bold',
  headNote: 'text-12 text-muted',
  /** «RELEASE CHECKLIST · 5 OF 8», «SIGN-OFF» */
  label: 'text-11 font-bold uppercase tracking-[.1em] text-muted',
  /** the table heads (Integrations register, Deploys per environment) */
  colHead: 'text-10.5 font-bold uppercase tracking-[.08em] text-muted',
  kpi: 'rounded-18 border border-line bg-surface px-[15px] py-[13px]',
  kpiLabel: 'text-10.5 font-bold uppercase tracking-label text-muted',
  kpiValue: 'font-serif text-23 font-semibold',
  mono: 'font-[ui-monospace,Menlo,monospace]',
  serif20: 'font-serif text-20 font-bold',
  /** the 26–28 px row buttons (Sign off, Plan upgrade, Approve for prod) */
  rowBtn: 'h-[26px] cursor-pointer whitespace-nowrap rounded-8 border border-ink bg-surface px-[9px] text-11.5 font-bold text-ink disabled:cursor-default disabled:opacity-50',
  rowBtnPrimary: 'h-[26px] cursor-pointer whitespace-nowrap rounded-8 border border-ink bg-primary px-[9px] text-11.5 font-bold text-ink disabled:cursor-default disabled:opacity-50',
  /** the big 40 px action under a card (Complete the checklist, Release) */
  bigBtn: 'h-10 rounded-11 border border-ink text-13 font-bold text-ink',
  /** form fields in the design's language (SimpleCRM.dc.html's modal: label over a 40 px field) */
  field: 'flex flex-col gap-[5px] text-12 font-semibold text-muted',
  input: 'h-10 min-w-0 rounded-10 border border-line bg-canvas px-3 text-13 text-ink',
  select: 'h-10 min-w-0 rounded-10 border border-line bg-canvas px-2 text-13 text-ink',
  small: 'h-[34px] cursor-pointer whitespace-nowrap rounded-10 border border-line bg-transparent px-3 text-12.5 font-semibold text-ink disabled:cursor-default disabled:opacity-50',
  smallPrimary: 'h-[34px] cursor-pointer whitespace-nowrap rounded-10 border border-ink bg-primary px-3 text-12.5 font-bold text-ink disabled:cursor-default disabled:opacity-50',
  /** a dark code block (DevClaude's <pre>) */
  pre: 'm-0 whitespace-pre-wrap rounded-12 bg-ink px-[14px] py-3 font-[ui-monospace,Menlo,monospace] text-11.5 leading-[1.6] text-tile [overflow-wrap:anywhere]',
  /** the kind chips of a changelog line */
  kind: { new: 'bg-ok-bg', improved: 'bg-teal-soft', fixed: 'bg-highlight' } as Record<'new' | 'improved' | 'fixed', string>,
  /** the status dot's colour */
  dot: { ok: 'text-ok', warn: 'text-warn', alert: 'text-alert', muted: 'text-faint' } as Record<'ok' | 'warn' | 'alert' | 'muted', string>,
  /** the side rule of a security row */
  rule: { ok: 'bg-ok', warn: 'bg-warn', alert: 'bg-alert' } as Record<'ok' | 'warn' | 'alert', string>,
}
