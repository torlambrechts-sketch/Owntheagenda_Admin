import type { getFormatter, getTranslations } from 'next-intl/server'

/** Small formatting helpers the server parts share; client parts receive the strings already written. */
export type T = Awaited<ReturnType<typeof getTranslations>>
export type Fmt = Awaited<ReturnType<typeof getFormatter>>

const DAY = 86_400_000

/** «987 467 565», the design's grouping with no-break spaces. */
export const orgNr = (s: string | null | undefined) => (s ? s.replace(/^(\d{3})(\d{3})(\d{3})$/, '$1 $2 $3') : '—')

export const daysSince = (iso: string, now: Date) => Math.max(0, Math.floor((now.getTime() - new Date(iso).getTime()) / DAY))
export const daysUntil = (iso: string, now: Date) => Math.ceil((new Date(iso).getTime() - now.getTime()) / DAY)

/** «27 d ago» under a month, «3 mo ago» after (the design's signup column). */
export function ago(iso: string, now: Date, t: T) {
  const d = daysSince(iso, now)
  return d < 30 ? t('fmt.daysAgo', { n: d }) : t('fmt.monthsAgo', { n: Math.round(d / 30) })
}

const sameDay = (a: Date, b: Date, fmt: Fmt) =>
  fmt.dateTime(a, { year: 'numeric', month: '2-digit', day: '2-digit' }) === fmt.dateTime(b, { year: 'numeric', month: '2-digit', day: '2-digit' })

/**
 * The design's times: `plain` «Today», «Yesterday», «2 Oct» (lists); `timeline` «Today 09:12», «Yesterday»,
 * «2 Oct»; `full` «Today 08:40», «2 Oct 14:02» (the audit trail). Another year adds the year.
 */
export function when(iso: string, now: Date, fmt: Fmt, t: T, mode: 'plain' | 'timeline' | 'full' = 'timeline') {
  const d = new Date(iso)
  const time = fmt.dateTime(d, { hour: '2-digit', minute: '2-digit' })
  const withTime = mode === 'full'
  if (sameDay(d, now, fmt)) return mode === 'plain' ? t('fmt.todayPlain') : t('fmt.today', { time })
  if (sameDay(d, new Date(now.getTime() - DAY), fmt)) return withTime ? t('fmt.yesterdayAt', { time }) : t('fmt.yesterday')
  const y = fmt.dateTime(d, { year: 'numeric' }) === fmt.dateTime(now, { year: 'numeric' })
  const date = fmt.dateTime(d, y ? { day: 'numeric', month: 'short' } : { day: 'numeric', month: 'short', year: 'numeric' })
  return withTime ? `${date} ${time}` : date
}

/** «2–16 Sep», or with the year outside this year (the survey dates). */
export function dateRange(from: string | null, to: string | null, now: Date, fmt: Fmt) {
  const a = from ? new Date(from) : null
  const b = to ? new Date(to) : null
  const thisYear = (d: Date) => fmt.dateTime(d, { year: 'numeric' }) === fmt.dateTime(now, { year: 'numeric' })
  const opts = (d: Date) => (thisYear(d) ? { day: 'numeric', month: 'short' } as const : { day: 'numeric', month: 'short', year: '2-digit' } as const)
  if (a && b) return fmt.dateTimeRange(a, b, opts(b))
  const d = a ?? b
  return d ? fmt.dateTime(d, opts(d)) : '—'
}

/** A message for a data value when one exists, the value itself otherwise (an event kind the screen does not know yet). */
export const label = (t: T, ns: string, value: string | null | undefined) => {
  if (!value) return '—'
  const key = `${ns}.${value}`
  return t.has(key) ? t(key) : value
}

export const initials = (name: string) =>
  name.split(/\s+/).filter(Boolean).map((w) => w[0]).slice(0, 2).join('')
