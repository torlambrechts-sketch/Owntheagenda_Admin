/**
 * Projects (Projects.dc.html): what the screen's client components and the server share — tabs, the health
 * palette, the «Paste a list» parser and small date helpers. No server imports: the components and the tests
 * load this file.
 */

export const TABS = ['board', 'timeline', 'templates', 'reports', 'setup'] as const
export type Tab = (typeof TABS)[number]

export const HEALTHS = ['on_track', 'at_risk', 'off_track', 'on_hold'] as const
export type Health = (typeof HEALTHS)[number]

/**
 * The design's health map (Projects.dc.html, H): the pill's background and ink, and the bar colour the Reports
 * tab derives from it. «Not set» (null) has no pill on a card; in Reports it is the neutral bar.
 */
export const HEALTH_TONE: Record<Health, { pill: string; bar: string }> = {
  on_track: { pill: 'bg-ok-bg text-ok-ink', bar: 'bg-ok' },
  at_risk: { pill: 'bg-amber-bg text-amber-ink', bar: 'bg-warn' },
  off_track: { pill: 'bg-salmon text-rust-ink', bar: 'bg-alert' },
  on_hold: { pill: 'bg-beige text-muted', bar: 'bg-line-strong' },
}
/** The drawer's health select takes the pill's background (proj.hbg). */
export const HEALTH_BG: Record<Health, string> = { on_track: 'bg-ok-bg', at_risk: 'bg-amber-bg', off_track: 'bg-salmon', on_hold: 'bg-beige' }

/** What the staff member may do here (mirrors app.can; the database decides). */
export type Rights = {
  meId: string
  add: boolean
  editOthers: boolean
  del: boolean
  bulk: boolean
  exportRows: boolean
  configure: boolean
  ai: boolean
  reportsOthers: boolean
  dealsSee: boolean
}

export const canEditProject = (r: Rights, p: { owner_id: string | null }) => r.editOthers || (p.owner_id !== null && p.owner_id === r.meId)

/** A date-only value (YYYY-MM-DD) as a Date at noon UTC, so every time zone shows the same day. */
export const dateOnly = (d: string) => new Date(`${d}T12:00:00Z`)
/** YYYY-MM-DD of a Date's UTC day. */
export const isoDay = (d: Date) => d.toISOString().slice(0, 10)
/** Whole days from a to b (both YYYY-MM-DD). */
export const daysBetween = (a: string, b: string) => Math.round((dateOnly(b).getTime() - dateOnly(a).getTime()) / 86_400_000)
export const addDays = (d: string, n: number) => isoDay(new Date(dateOnly(d).getTime() + n * 86_400_000))

export const firstName = (name: string | null | undefined) => (name ?? '').split(/\s+/)[0] ?? ''

// ---------------------------------------------------------------------------
// «Paste a list» (PRJ-08 RU): each non-empty line becomes a task. A leading or trailing date (16.10, 16.10.2026,
// 16 Oct, 16. okt, 2026-10-16) becomes the due date and is taken out of the name. A date without a year falls in
// the current year, or the next one when it would lie more than half a year back (a December list naming January).
// Bullets and checkboxes at the start of a line are list markup, not part of the task.

const MONTHS: Record<string, number> = {
  jan: 1, januar: 1, january: 1, feb: 2, februar: 2, february: 2, mar: 3, mars: 3, march: 3, apr: 4, april: 4, mai: 5, may: 5,
  jun: 6, juni: 6, june: 6, jul: 7, juli: 7, july: 7, aug: 8, august: 8, sep: 9, sept: 9, september: 9, okt: 10, oct: 10, oktober: 10, october: 10,
  nov: 11, november: 11, des: 12, dec: 12, desember: 12, december: 12,
}
const MONTH_RE = Object.keys(MONTHS).sort((a, b) => b.length - a.length).join('|')
const DATE_FORMS = [
  '(\\d{4})-(\\d{1,2})-(\\d{1,2})', // ISO
  '(\\d{1,2})\\.(\\d{1,2})(?:\\.(\\d{2}|\\d{4}))?\\.?', // 16.10 / 16.10.2026
  `(\\d{1,2})\\.?\\s+(${MONTH_RE})\\.?(?:\\s+(\\d{4}))?`, // 16 Oct / 16. okt / 16 okt 2026
]
const LEAD = new RegExp(`^(?:${DATE_FORMS.join('|')})(?:\\s*[:\\-–—·,]\\s*|\\s+)`, 'i')
const TRAIL = new RegExp(`(?:\\s*[:\\-–—·,(]\\s*|\\s+)(?:${DATE_FORMS.join('|')})\\)?$`, 'i')
const BULLET = /^\s*(?:[-*•·–]|\d{1,3}[.)]|\[[ xX]?\])\s+/

export type PastedItem = { name: string; due_on: string | null }

function toDate(m: RegExpMatchArray, today: string): string | null {
  const g = m.slice(1)
  let y: number | null, mo: number, d: number
  if (g[0]) { y = +g[0]; mo = +g[1]!; d = +g[2]! }
  else if (g[3]) { d = +g[3]; mo = +g[4]!; y = g[5] ? (g[5].length === 2 ? 2000 + +g[5] : +g[5]) : null }
  else { d = +g[6]!; mo = MONTHS[g[7]!.toLowerCase()] ?? 0; y = g[8] ? +g[8] : null }
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null
  const year0 = +today.slice(0, 4)
  const build = (yy: number) => {
    const dt = new Date(Date.UTC(yy, mo - 1, d, 12))
    return dt.getUTCMonth() === mo - 1 ? isoDay(dt) : null
  }
  if (y !== null) return build(y)
  const iso = build(year0)
  if (iso && daysBetween(iso, today) > 183) return build(year0 + 1)
  return iso
}

export function parsePasteList(text: string, today: string, max = 200): PastedItem[] {
  const out: PastedItem[] = []
  for (const raw of text.split(/\r?\n/)) {
    let line = raw.replace(BULLET, '').trim()
    if (!line) continue
    let due: string | null = null
    const lead = line.match(LEAD)
    if (lead) {
      const d = toDate(lead, today)
      if (d && line.length > lead[0].length) { due = d; line = line.slice(lead[0].length).trim() }
    }
    if (!due) {
      const trail = line.match(TRAIL)
      if (trail && trail.index !== undefined && trail.index > 0) {
        const d = toDate(trail, today)
        if (d) { due = d; line = line.slice(0, trail.index).trim() }
      }
    }
    if (!line) continue
    out.push({ name: line.slice(0, 300), due_on: due })
    if (out.length >= max) break
  }
  return out
}

// ---------------------------------------------------------------------------
// export: the database's column keys and rows (cells already neutralised there) as a sheet with translated headers
export type ExportCell = string | number | boolean | null
export function exportSheet(columns: string[], rows: ExportCell[][], header: (key: string) => string, cell: (key: string, v: ExportCell) => string | number): (string | number)[][] {
  return [columns.map(header), ...rows.map((r) => r.map((v, i) => cell(columns[i]!, v)))]
}

// ---------------------------------------------------------------------------
// the timeline: a group bar dragged by some pixels becomes a whole number of days on the range
export function dragDays(dx: number, trackWidth: number, rangeDays: number): number {
  if (trackWidth <= 0 || rangeDays <= 0) return 0
  return Math.round((dx / trackWidth) * rangeDays)
}
