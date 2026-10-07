/**
 * Meetings (Meetings.dc.html): what the server and the client components share — the tabs, the state pill's colours,
 * and the small pure formatters the list, the header and the suggestions use. No server code here.
 */
export const VIEWS = ['workspace', 'capture', 'controls'] as const
export type View = (typeof VIEWS)[number]
export const MTABS = ['brief', 'transcript', 'suggest'] as const
export type MTab = (typeof MTABS)[number]

export const STATE_KEYS = ['cancelled', 'recording_blocked', 'notice_due', 'bot_joins', 'bot_in_call', 'processing', 'transcription_failed', 'suggestions', 'recap_saved', 'recap_ready', 'transcript_ready'] as const
export type StateKey = (typeof STATE_KEYS)[number]

/** The pill colours the design gives each state (M[].sc / sbg); states it does not draw take the nearest. */
export const STATE_TONE: Record<StateKey | 'none', { c: string; bg: string }> = {
  bot_joins: { c: '#2F5D2A', bg: '#CFE7E4' },
  bot_in_call: { c: '#2F5D2A', bg: '#CFE7E4' },
  notice_due: { c: '#8A6A00', bg: '#FBEBBE' },
  processing: { c: '#8A6A00', bg: '#FBEBBE' },
  suggestions: { c: '#A33A16', bg: '#FBD5C4' },
  recording_blocked: { c: '#A33A16', bg: '#FBD5C4' },
  transcription_failed: { c: '#A33A16', bg: '#FBD5C4' },
  recap_ready: { c: '#2F5D2A', bg: '#CFE7E4' },
  transcript_ready: { c: '#5F5849', bg: '#EFE6D2' },
  recap_saved: { c: '#5F5849', bg: '#EFE6D2' },
  cancelled: { c: '#5F5849', bg: '#EFE6D2' },
  none: { c: '#5F5849', bg: '#EFE6D2' },
}

export const BOT_REASONS = ['notice_not_sent', 'opted_out', 'not_connected', 'no_link', 'disabled', 'internal_only'] as const
export const CONFERENCES = ['meet', 'teams', 'zoom', 'phone', 'in_person', 'other'] as const
export const CAPTURES = ['bot', 'desktop', 'upload', 'none'] as const

/** mm:ss of a segment's start (the design's «02:40»); an hour or more reads h:mm:ss. */
export function clock(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const pad = (n: number) => String(n).padStart(2, '0')
  return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${pad(m)}:${pad(s % 60)}`
}

/** Whole minutes of a duration in seconds, at least one when there is any. */
export const minutes = (s: number) => (s > 0 ? Math.max(1, Math.round(s / 60)) : 0)

/** The calendar day of an instant in a time zone, as YYYY-MM-DD (to tell «Today» from other days). */
export function dayIn(iso: string | Date, tz: string): string {
  const d = typeof iso === 'string' ? new Date(iso) : iso
  return new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)
}

/**
 * Who comes, the design's way: every name when there are three or fewer, else «Ole Hansen, 4 others». The owner is
 * left out (the list row's own count does the same).
 */
export function attendeeLine(names: string[], others: (n: number) => string): string {
  if (names.length <= 3) return names.join(', ')
  return `${names[0]}, ${others(names.length - 1)}`
}

/** A suggestion's value as text: numbers in the staff member's format, label ids as names, a list joined. */
export function valueText(v: unknown, fmt: (n: number) => string, labelName: (id: string) => string | null): string | null {
  if (v === null || v === undefined) return null
  if (typeof v === 'number') return fmt(v)
  if (typeof v === 'boolean') return v ? '✓' : '✗'
  if (typeof v === 'string') return labelName(v) ?? v
  if (Array.isArray(v)) {
    const parts = v.map((x) => valueText(x, fmt, labelName)).filter((x): x is string => !!x)
    return parts.length ? parts.join(', ') : null
  }
  return null
}
