/**
 * The design's colour pairs (Customers.dc.html: statusTone, the lifecycle bar, the access states), keyed by
 * the database's values. A value the design does not draw takes its default pair (tile, muted).
 */
export const STATUS_TONE: Record<string, string> = {
  active: 'bg-ok-bg text-ok-ink',
  trial: 'bg-highlight text-amber-ink',
  past_due: 'bg-salmon text-rust-ink',
  suspended: 'bg-peach text-rust-ink',
  cancelled: 'bg-[rgba(25,21,16,.06)] text-muted',
}
export const statusTone = (s: string | null | undefined) => (s && STATUS_TONE[s]) || 'bg-tile text-muted'

export const LIFECYCLE_COLOR: Record<string, string> = {
  trial: '#FBEBBE',
  active: '#CFE7E4',
  past_due: '#F0B9A0',
  suspended: '#FBD5C4',
  cancelled: '#E8DFC9',
  expired: '#C4BCA8',
  free: '#E4EEEC',
}
export const LIFECYCLE_ORDER = ['trial', 'active', 'past_due', 'suspended', 'cancelled', 'expired', 'free']

export const GRANT_TONE: Record<string, string> = {
  active: 'bg-ok-bg text-ok-ink',
  pending: 'bg-highlight text-amber-ink',
}
export const grantTone = (s: string) => GRANT_TONE[s] ?? 'bg-[rgba(25,21,16,.06)] text-muted'

// the timeline dot per kind (the design's e.c)
export const TIMELINE_DOT: Record<string, string> = {
  logins: '#E4EEEC',
  crm: '#FBEBBE',
  support: '#CFE0F5',
  activation: '#CFE7E4',
  billing: '#F3E2C9',
  admin: '#F5C64A',
}

export const PRIORITY_INK: Record<string, string> = { urgent: 'text-danger', high: 'text-warn-ink' }
