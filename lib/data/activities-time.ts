/**
 * Calendar arithmetic in the staff member's time zone, without a date library. A plain day is {y, m, d}
 * (m 1–12); an instant is a Date. The week starts on Monday (ISO weekday 1).
 */
export type Day = { y: number; m: number; d: number }

const fmtCache = new Map<string, Intl.DateTimeFormat>()
const fmt = (tz: string) => {
  let f = fmtCache.get(tz)
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
    })
    fmtCache.set(tz, f)
  }
  return f
}

/** The wall-clock parts of an instant in a time zone. */
export function zoned(at: Date, tz: string): Day & { h: number; min: number } {
  const p: Record<string, number> = {}
  for (const x of fmt(tz).formatToParts(at)) if (x.type !== 'literal') p[x.type] = Number(x.value)
  return { y: p.year!, m: p.month!, d: p.day!, h: p.hour! % 24, min: p.minute! }
}

/** The instant a wall-clock time in a time zone names (the earlier one in a DST overlap). */
export function fromZoned(day: Day, h: number, min: number, tz: string): Date {
  const want = Date.UTC(day.y, day.m - 1, day.d, h, min)
  let guess = want
  for (let i = 0; i < 3; i++) {
    const z = zoned(new Date(guess), tz)
    const diff = want - Date.UTC(z.y, z.m - 1, z.d, z.h, z.min)
    if (diff === 0) break
    guess += diff
  }
  return new Date(guess)
}

const utc = (x: Day) => Date.UTC(x.y, x.m - 1, x.d)
const fromUtc = (ms: number): Day => {
  const t = new Date(ms)
  return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate() }
}

export const addDays = (x: Day, n: number): Day => fromUtc(utc(x) + n * 86_400_000)
export const sameDay = (a: Day, b: Day) => a.y === b.y && a.m === b.m && a.d === b.d
export const dayDiff = (a: Day, b: Day) => Math.round((utc(a) - utc(b)) / 86_400_000)
/** ISO weekday: Monday 1 … Sunday 7. */
export const weekday = (x: Day) => ((new Date(utc(x)).getUTCDay() + 6) % 7) + 1
export const mondayOf = (x: Day) => addDays(x, 1 - weekday(x))
export const daysInMonth = (y: number, m: number) => new Date(Date.UTC(y, m, 0)).getUTCDate()
export const ymd = (x: Day) => `${x.y}-${String(x.m).padStart(2, '0')}-${String(x.d).padStart(2, '0')}`
export const parseYmd = (s: string | undefined): Day | null => {
  const r = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s ?? '')
  if (!r) return null
  const x = { y: Number(r[1]), m: Number(r[2]), d: Number(r[3]) }
  return x.m >= 1 && x.m <= 12 && x.d >= 1 && x.d <= daysInMonth(x.y, x.m) ? x : null
}
/** A plain day as a Date at noon UTC, for formatting the day itself (weekday, month name) in any zone. */
export const asNoon = (x: Day) => new Date(utc(x) + 12 * 3_600_000)

/** ISO 8601 week number. */
export function isoWeek(x: Day): number {
  const thursday = addDays(x, 4 - weekday(x))
  const jan1 = { y: thursday.y, m: 1, d: 1 }
  return Math.floor(dayDiff(thursday, jan1) / 7) + 1
}

/** The month grid: leading blanks for the weekday of the 1st, whole weeks. */
export function monthGrid(y: number, m: number): (Day | null)[] {
  const lead = weekday({ y, m, d: 1 }) - 1
  const n = daysInMonth(y, m)
  const cells = Math.ceil((lead + n) / 7) * 7
  return Array.from({ length: cells }, (_, i) => {
    const d = i - lead + 1
    return d >= 1 && d <= n ? { y, m, d } : null
  })
}
