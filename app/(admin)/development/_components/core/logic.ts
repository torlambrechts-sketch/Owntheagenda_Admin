/**
 * Development › the core half: the pure rules the views and the server actions share (no I/O, no React). Tested in
 * tests/v3-dev-core.test.ts.
 */

export const LANES = ['now', 'next', 'later'] as const
export type Lane = (typeof LANES)[number]
/** the work board's columns and a roadmap item's delivery status (the starter kit's status flow) */
export const STATUSES = ['backlog', 'spec', 'in_progress', 'review', 'staging', 'rollout', 'done'] as const
export type Status = (typeof STATUSES)[number]
export const KINDS = ['story', 'bug', 'task', 'spike'] as const
export type Kind = (typeof KINDS)[number]
export const SEVERITIES = ['s1', 's2', 's3'] as const
export type Severity = (typeof SEVERITIES)[number]
export const SPEC_ROLES = ['product', 'engineering', 'security_privacy', 'support'] as const
export type SpecRole = (typeof SPEC_ROLES)[number]
export const SPEC_SECTIONS = ['problem', 'options', 'decision', 'privacy', 'rollout'] as const
export type SpecSection = (typeof SPEC_SECTIONS)[number]
export const SPEC_STATUSES = ['draft', 'in_review', 'approved'] as const
export const AI_FEATURES = ['spec_draft', 'task_plan', 'release_note_draft'] as const
export type AiFeature = (typeof AI_FEATURES)[number]
export const NOTE_KINDS = ['new', 'improved', 'fixed'] as const
export type NoteKind = (typeof NOTE_KINDS)[number]

/** the design's colours: lane rules (LN), column rules (CO), file status pills (SBG), severity chips (SV) */
export const LANE_RULE: Record<Lane, string> = { now: 'border-b-ok', next: 'border-b-warn', later: 'border-b-line-strong' }
export const COLUMN_RULE: Record<Status, string> = {
  backlog: 'border-b-line-strong', spec: 'border-b-lilac', in_progress: 'border-b-primary', review: 'border-b-blue-bg',
  staging: 'border-b-teal-light', rollout: 'border-b-sand', done: 'border-b-ok',
}
export const STATUS_PILL: Record<Status, string> = {
  backlog: 'bg-tile', spec: 'bg-lilac', in_progress: 'bg-highlight', review: 'bg-blue-bg', staging: 'bg-teal-light', rollout: 'bg-sand', done: 'bg-ok-bg',
}
export const SEVERITY_CHIP: Record<Severity, string> = { s1: 'bg-salmon text-rust-ink', s2: 'bg-amber-bg text-amber-ink', s3: 'bg-teal-soft text-ok-ink' }
/** the roadmap's product pill: the application's own colour, Sentral's from the design (#F3E2C9) */
export const SENTRAL_COLOR = '#F3E2C9'

/** «in-progress»: the status as the starter kit's front matter writes it */
export const fileStatus = (s: Status) => s.replace('_', '-')

/** two letters for an avatar: the stored initials, else the first letters of the first two names */
export function initials(name: string | null | undefined, stored?: string | null): string {
  if (stored && stored.trim()) return stored.trim().slice(0, 2).toUpperCase()
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean)
  if (!parts.length) return '—'
  return ((parts[0]![0] ?? '') + (parts.length > 1 ? parts[parts.length - 1]![0] ?? '' : parts[0]![1] ?? '')).toUpperCase()
}

/** a file name part: lower case ASCII, words joined by «-», at most 40 characters */
export function slug(title: string): string {
  const s = title.toLowerCase()
    .replace(/æ/g, 'ae').replace(/ø/g, 'o').replace(/å/g, 'a')
    .normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')
  return (s.slice(0, 40).replace(/-+$/g, '') || 'item')
}

// ---------------------------------------------------------------------------
// time

/** the calendar day of an instant in a time zone, as YYYY-MM-DD */
export function dayIn(iso: string | Date, timeZone: string): string {
  const d = typeof iso === 'string' ? new Date(iso) : iso
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)
}
/** «16:00» in a time zone */
export function timeIn(iso: string, timeZone: string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(iso))
}
const dayDiff = (a: string, b: string) => Math.round((Date.parse(`${a}T12:00:00Z`) - Date.parse(`${b}T12:00:00Z`)) / 86_400_000)

export type Due = { kind: 'today'; time: string } | { kind: 'left'; days: number } | { kind: 'overdue'; days: number }
/** the bug's due label (BG[][4]): due today at a time, n days left, or overdue by n days */
export function dueState(dueIso: string, nowIso: string, timeZone = 'Europe/Oslo'): Due {
  const due = dayIn(dueIso, timeZone)
  const today = dayIn(nowIso, timeZone)
  if (Date.parse(dueIso) < Date.parse(nowIso)) return { kind: 'overdue', days: Math.max(dayDiff(today, due), 0) }
  if (due === today) return { kind: 'today', time: timeIn(dueIso, timeZone) }
  return { kind: 'left', days: Math.max(dayDiff(due, today), 1) }
}

/** a sprint's dates the design's way: «6–17 Oct» in one month, «28 Sep–9 Oct» across two */
export function sprintDates(start: string, end: string, locale: string): string {
  const s = new Date(`${start}T12:00:00Z`)
  const e = new Date(`${end}T12:00:00Z`)
  const day = (d: Date) => new Intl.DateTimeFormat(locale, { day: 'numeric', timeZone: 'UTC' }).format(d).replace('.', '')
  const dayMonth = (d: Date) => new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(d)
  return s.getUTCMonth() === e.getUTCMonth() && s.getUTCFullYear() === e.getUTCFullYear() ? `${day(s)}–${dayMonth(e)}` : `${dayMonth(s)}–${dayMonth(e)}`
}

/** hours as the design writes a duration: minutes under an hour, «4 h» under a day, else days with one decimal */
export function durationParts(hours: number): { unit: 'min' | 'h' | 'd'; value: number; decimals: number } {
  if (hours < 1) return { unit: 'min', value: Math.max(Math.round(hours * 60), hours > 0 ? 1 : 0), decimals: 0 }
  if (hours < 24) return { unit: 'h', value: Math.round(hours), decimals: 0 }
  const days = Math.round((hours / 24) * 10) / 10
  return { unit: 'd', value: days, decimals: Number.isInteger(days) ? 0 : 1 }
}

/** a share in whole percent, or null when there is nothing to divide by */
export const share = (part: number, whole: number) => (whole > 0 ? Math.round((part / whole) * 100) : null)

// ---------------------------------------------------------------------------
// the board's keyboard alternative

/** Alt+→ / Alt+← on a card: the neighbouring column, or null at the edge */
export function neighbour(status: Status, dir: 1 | -1): Status | null {
  const i = STATUSES.indexOf(status) + dir
  return i >= 0 && i < STATUSES.length ? STATUSES[i]! : null
}

// ---------------------------------------------------------------------------
// Claude's drafts, read into records (the database checks every value again)

const SECTION_NAMES: Record<SpecSection, string[]> = {
  problem: ['problem', 'problemet'],
  options: ['options', 'alternatives', 'alternativer', 'alternativ'],
  decision: ['decision', 'beslutning', 'vedtak'],
  privacy: ['privacy and anonymity', 'privacy', 'personvern og anonymitet', 'personvern'],
  rollout: ['rollout', 'roll-out', 'utrulling', 'lansering'],
}

/** a spec draft's five sections by their headings; a draft without them goes into Problem whole */
export function parseSpecDraft(body: string): Record<SpecSection, string> {
  const out: Record<SpecSection, string> = { problem: '', options: '', decision: '', privacy: '', rollout: '' }
  let current: SpecSection | null = null
  let matched = false
  const lines: Record<SpecSection, string[]> = { problem: [], options: [], decision: [], privacy: [], rollout: [] }
  for (const raw of body.replace(/\r\n/g, '\n').split('\n')) {
    const h = /^\s*#{1,4}\s*(.+?)\s*:?\s*$/.exec(raw)
    if (h) {
      const name = h[1]!.toLowerCase().replace(/[«»*_]/g, '').trim()
      const hit = SPEC_SECTIONS.find((s) => SECTION_NAMES[s].includes(name))
      if (hit) { current = hit; matched = true; continue }
    }
    if (current) lines[current].push(raw)
  }
  if (!matched) return { ...out, problem: body.trim().slice(0, 8000) }
  for (const s of SPEC_SECTIONS) out[s] = lines[s].join('\n').trim().slice(0, 8000)
  return out
}

const KIND_WORDS: Record<string, Kind> = {
  story: 'story', historie: 'story', task: 'task', oppgave: 'task', spike: 'spike', utforsking: 'spike', bug: 'bug', feil: 'bug',
}
/** a task plan: one work item per list line, «- Kind: title»; at most 20 */
export function parseTaskPlan(body: string): { kind: Kind; title: string }[] {
  const out: { kind: Kind; title: string }[] = []
  for (const raw of body.replace(/\r\n/g, '\n').split('\n')) {
    const m = /^\s*(?:[-*•]|\d+[.)])\s+(?:\[[ xX]\]\s*)?(.+?)\s*$/.exec(raw)
    if (!m) continue
    let text = m[1]!.replace(/\*\*/g, '').trim()
    let kind: Kind = 'task'
    const k = /^(story|historie|task|oppgave|spike|utforsking|bug|feil)\s*[:\-–]\s*(.+)$/i.exec(text)
    if (k) { kind = KIND_WORDS[k[1]!.toLowerCase()]!; text = k[2]!.trim() }
    if (text.length < 3) continue
    out.push({ kind, title: text.slice(0, 200) })
    if (out.length === 20) break
  }
  return out
}

const NOTE_WORDS: Record<string, NoteKind> = {
  new: 'new', nytt: 'new', ny: 'new', nyhet: 'new', improved: 'improved', forbedret: 'improved', bedre: 'improved', fixed: 'fixed', rettet: 'fixed', fikset: 'fixed',
}
/** release notes: «- New: …», «- Improved: …», «- Fixed: …»; at most 10 */
export function parseReleaseNotes(body: string): { kind: NoteKind; title: string }[] {
  const out: { kind: NoteKind; title: string }[] = []
  for (const raw of body.replace(/\r\n/g, '\n').split('\n')) {
    const m = /^\s*(?:[-*•]|\d+[.)])?\s*\**(new|nytt|ny|nyhet|improved|forbedret|bedre|fixed|rettet|fikset)\**\s*:\s*(.+?)\s*$/i.exec(raw)
    if (!m) continue
    const title = m[2]!.replace(/\*\*/g, '').trim()
    if (title.length < 3) continue
    out.push({ kind: NOTE_WORDS[m[1]!.toLowerCase()]!, title: title.slice(0, 200) })
    if (out.length === 10) break
  }
  return out
}

// ---------------------------------------------------------------------------
// the Markdown roadmap: the starter kit's feature and bug files, generated from the records

export type LogEntry = { at: string; by: string | null; action: string; detail: Record<string, unknown> | null }
export type FileLink = { kind: string; label: string | null; title: string | null }
export type FeatureRecord = {
  key: string; product: string; title: string; goal: string | null; status: Status; owner: string | null; spec: string | null
  problem: string | null; links: FileLink[]; tasks: { key: string; title: string; done: boolean }[]; log: LogEntry[]
}
export type BugRecord = {
  number: number; product: string; title: string; severity: Severity; state: 'open' | 'fixed' | 'duplicate'; owner: string | null
  customers: number | null; ticketNumbers: number[]; problemNumber: number | null; workStatus: Status | null
  tasks: { key: string; title: string; done: boolean }[]; log: LogEntry[]
}

/** a YAML scalar that needs no quoting stays bare; anything else is double-quoted */
export function yaml(v: string | null | undefined): string {
  if (v === null || v === undefined || v === '') return '—'
  return /^[\p{L}\p{N} ._/@+-]+$/u.test(v) && !/^[-?:,[\]{}#&*!|>'"%@`]/.test(v) && v.trim() === v ? v : JSON.stringify(v)
}
/** a link as a file names it: an id where there is one, else its kind and title */
export function linkToken(l: FileLink): string {
  if (l.label) return l.label
  const t = (l.title ?? '').replace(/[[\],]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60)
  return `${l.kind === 'seo_plan' ? 'seo' : l.kind}: ${t}`
}
const list = (xs: string[]) => `[${xs.join(', ')}]`
const taskLines = (ts: { key: string; title: string; done: boolean }[]) => (ts.length ? ts.map((x) => `- [${x.done ? 'x' : ' '}] ${x.key} ${x.title}`) : ['- [ ] '])

export function featurePath(r: { key: string; title: string }) { return `roadmap/features/${r.key}-${slug(r.title)}.md` }
export function bugPath(r: { number: number; title: string }) { return `roadmap/bugs/BUG-${r.number}-${slug(r.title)}.md` }
export const bugStatus = (r: Pick<BugRecord, 'state' | 'workStatus'>): Status => r.workStatus ?? (r.state === 'open' ? 'backlog' : 'done')

/** a feature file: the starter kit's front matter, the spec's problem, the tasks (the item's work items), the log (its audit) */
export function featureMarkdown(r: FeatureRecord, logLine: (e: LogEntry) => string): string {
  return [
    '---',
    `id: ${r.key}`,
    `title: ${yaml(r.title)}`,
    `status: ${fileStatus(r.status)}`,
    `owner: ${yaml(r.owner)}`,
    `product: ${r.product}`,
    'priority: —',
    `metric: ${r.goal ? JSON.stringify(r.goal) : '""'}`,
    'flag: —',
    'rollout: —',
    `spec: ${r.spec ?? '—'}`,
    `links: ${list(r.links.map(linkToken))}`,
    '---',
    '',
    '## Problem',
    ...(r.problem ? [r.problem.trim()] : []),
    '',
    '## Tasks',
    ...taskLines(r.tasks),
    '',
    '## Log',
    ...[...r.log].reverse().map((e) => `- ${e.at.slice(0, 10)} ${logLine(e)}`),
    '',
  ].join('\n')
}

/** a bug file: the starter kit's bug front matter, its tasks and its log */
export function bugMarkdown(r: BugRecord, logLine: (e: LogEntry) => string): string {
  const links = [...r.ticketNumbers.map((n) => `T-${n}`), ...(r.problemNumber ? [`problem T-${r.problemNumber}`] : [])]
  return [
    '---',
    `id: BUG-${r.number}`,
    `title: ${yaml(r.title)}`,
    `status: ${fileStatus(bugStatus(r))}`,
    `owner: ${yaml(r.owner)}`,
    `product: ${r.product}`,
    `priority: ${r.severity.toUpperCase()}`,
    `customers: ${r.customers ?? '—'}`,
    `links: ${list(links)}`,
    '---',
    '',
    '## Tasks',
    ...taskLines(r.tasks),
    '',
    '## Log',
    ...[...r.log].reverse().map((e) => `- ${e.at.slice(0, 10)} ${logLine(e)}`),
    '',
  ].join('\n')
}
