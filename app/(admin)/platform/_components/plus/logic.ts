/**
 * Platform › the new tabs: the small rules the views share, kept apart so they are tested (tests/v3-platform.test.ts) and the
 * components only render. Nothing here invents a value: a missing source stays null and is shown as «—».
 */
export type Mode = 'allow' | 'approve' | 'deny'

/** A matrix cell's next mode when clicked: ✓ → A → – → ✓ where the queue can execute the action, else ✓ ↔ –. */
export function nextMode(cur: Mode, approvable: boolean): Mode {
  if (cur === 'allow') return approvable ? 'approve' : 'deny'
  if (cur === 'approve') return 'deny'
  return 'allow'
}

/** The design's three cell looks (PlatformPlus.dc.html, sym): ✓ teal, A yellow, – plain. */
export const CELL_CLASS: Record<Mode | 'none', string> = {
  allow: 'border-link bg-ok-bg text-ok-ink',
  approve: 'border-ink bg-highlight text-amber-ink',
  deny: 'border-line bg-transparent text-faint',
  none: 'border-line bg-transparent text-faint',
}
export const SYMBOL: Record<Mode | 'none', string> = { allow: '✓', approve: 'A', deny: '–', none: '–' }

/** next-intl keys cannot hold a dot: «trial.extend» → «trial_extend». */
export const actionKey = (action: string) => action.replace(/\./g, '_')

/** The audience a pair of chips names (the reach is read for all four in advance). */
export function audienceOf(admins: boolean, trial: boolean): 'all' | 'admins' | 'trial' | 'admins_trial' {
  return admins ? (trial ? 'admins_trial' : 'admins') : trial ? 'trial' : 'all'
}

/** A share in whole percent; null when the step has no source or the cohort is empty (0 of 0 is not 0 %). */
export function pctOf(done: number | null, cohort: number): number | null {
  if (done === null || cohort <= 0) return null
  return Math.round((done / cohort) * 100)
}

/** The design's limit bar: red at 95 % and over, amber below (p >= 95). */
export const limitTone = (pct: number) => (pct >= 95 ? 'bg-alert' : 'bg-warn')

/** The design's error count colour: over 10 rust, over 0 amber, 0 green. */
export const errorTone = (n: number) => (n > 10 ? 'text-danger' : n > 0 ? 'text-warn-ink' : 'text-link')

/** A feature request's statuses (0078), in the design's order: Under review · Planned · In progress · Shipped · Not planned. */
export const REQUEST_STATUSES = ['under_review', 'planned', 'in_progress', 'shipped', 'declined'] as const

/** A feature request's status select background (the design's SC). */
export const STATUS_BG: Record<string, string> = {
  under_review: 'bg-tile',
  planned: 'bg-highlight',
  in_progress: 'bg-blue-bg',
  shipped: 'bg-ok-bg',
  declined: 'bg-peach',
}

/** Which approval rows are still open (pending and not past their time). */
export const isOpen = (a: { state: string; expires_at: string }, nowMs: number) => a.state === 'pending' && new Date(a.expires_at).getTime() > nowMs
