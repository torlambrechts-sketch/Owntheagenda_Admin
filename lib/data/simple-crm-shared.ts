import type { Card } from '@/lib/data/deals'
import { fromQuery, fieldDef, MARKETING_STATUSES, MEMBER_ROLES, ORG_STATUSES, type Cond } from '@/lib/data/campaigns-shared'

/**
 * What the CRM section of Sentral Simple (SimpleCRM.dc.html) shares between server and client: the tabs, the board's
 * summary from the board's own cards, and the words for a saved list's conditions. Pure; the database decides.
 */
export const CRM_TABS = ['deals', 'lists'] as const
export type CrmTab = (typeof CRM_TABS)[number]

// the design's stage palette (SimpleCRM.dc.html: viz), one colour per column in order
export const STAGE_VIZ = ['#F6D9C6', '#DCEBD3', '#CFE0F5', '#F3E2C9', '#E7DAF2'] as const

/** What the signed-in staff member may do in the section (mirrors app.can; the database refuses anyway). */
export type CrmRights = {
  meId: string
  /** deals:add — a new deal */
  add: boolean
  /** deals:edit_others — move or close a colleague's deal */
  editOthers: boolean
  /** neither add nor edit_others: the board is for reading */
  readOnly: boolean
  /** deals:export — the list's CSV (people are a deals-scope record) */
  exportRows: boolean
  /** the campaigns module is on and the person has campaigns:see — saved lists are campaign segments (0037) */
  lists: boolean
  /** campaigns:add — a new list */
  addList: boolean
  /** Growth is in the person's rail (lib/nav ACCESS): «Use in email campaign» leads there, so it is offered only then */
  growth: boolean
}

export const canEditDeal = (r: CrmRights, d: { owner_id: string | null }) => !r.readOnly && (r.editOthers || d.owner_id === r.meId)

// ---------------------------------------------------------------------------
// the summary line and the Won / Lost zones: the board's cards, nothing added

/** «2026-10»: the calendar month of an instant in a time zone (the staff member's; UTC when the zone is unknown). */
export function monthKey(d: Date, tz: string): string {
  const fmt = (zone: string) => new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit' }).formatToParts(d)
  let parts: Intl.DateTimeFormatPart[]
  try { parts = fmt(tz) } catch { parts = fmt('UTC') }
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? ''
  return `${get('year')}-${get('month')}`
}

export type Summary = { count: number; value: number; weighted: number; wonValue: number; wonCount: number; lostCount: number }

/**
 * Open deals, their value and their value weighted by the stage's probability; won and lost deals closed in the current
 * calendar month (won_at / lost_at in the staff member's time zone). The cards are the board's, open and closed.
 */
export function summarise(cards: Pick<Card, 'status' | 'value' | 'probability' | 'won_at' | 'lost_at'>[], tz: string, now = new Date()): Summary {
  const m = monthKey(now, tz)
  const inMonth = (iso: string | null) => !!iso && monthKey(new Date(iso), tz) === m
  const open = cards.filter((c) => c.status === 'open')
  const won = cards.filter((c) => c.status === 'won' && inMonth(c.won_at))
  const lost = cards.filter((c) => c.status === 'lost' && inMonth(c.lost_at))
  return {
    count: open.length,
    value: open.reduce((a, c) => a + c.value, 0),
    weighted: open.reduce((a, c) => a + (c.value * c.probability) / 100, 0),
    wonValue: won.reduce((a, c) => a + c.value, 0),
    wonCount: won.length,
    lostCount: lost.length,
  }
}

/** The card's next step (Card.act, from the deal's open activities): the design's words and colours. */
export const NEXT_STEP = {
  overdue: { key: 'overdue', ink: 'text-danger', border: 'border-coral' },
  none: { key: 'none', ink: 'text-warn-ink', border: 'border-line' },
  planned: { key: 'planned', ink: 'text-link', border: 'border-line' },
} as const

// ---------------------------------------------------------------------------
// lists: a saved list is a campaign segment (saved_views kind=segment) — a people filter (app.filter_sql, 0040)

export type MarketingStatus = (typeof MARKETING_STATUSES)[number]
/** The email-status chip's colours, per the real marketing_status values (the design's ct table; archived as no consent). */
export const CONSENT_TONE: Record<MarketingStatus, string> = {
  subscribed: 'bg-ok-bg text-ok-ink',
  no_consent: 'bg-[rgba(25,21,16,.06)] text-muted',
  pending: 'bg-highlight text-amber-ink',
  unsubscribed: 'bg-peach text-rust-ink',
  bounced: 'bg-salmon text-rust-ink',
  archived: 'bg-[rgba(25,21,16,.06)] text-muted',
}
/** The people a list shows at once (rec_list's own limit); Export CSV carries them all. */
export const MEMBERS_SHOWN = 500

export const isMarketingStatus = (s: string): s is MarketingStatus => (MARKETING_STATUSES as readonly string[]).includes(s)

/**
 * «Role» in this section is the person's title (people.title): the design's roles (Daglig leder, HR, Leder, Verneombud)
 * are job titles, and the seeded lists filter on it. The product user's role (member.role) is another field and keeps
 * its own name when a list uses it.
 */
export const ROLE_FIELD = 'title'
export const STATUS_FIELD = 'organization.status'
export { ORG_STATUSES }

/** The new-list form as a people filter: role and account status, «any» leaves the condition out. */
export function listQuery(role: string, status: string): { filters: { f: string; op: 'eq'; v: string }[] } {
  return {
    filters: [
      ...(role ? [{ f: ROLE_FIELD, op: 'eq' as const, v: role }] : []),
      ...(status ? [{ f: STATUS_FIELD, op: 'eq' as const, v: status }] : []),
    ],
  }
}

type T = (key: string, values?: Record<string, string | number>) => string

/** A condition's value in words: enumerations through their message, numbers and text as stored. */
function valueText(c: Cond, t: T): string {
  const word = (v: string) => {
    const x = v.trim()
    if (c.f === 'marketing_status' && isMarketingStatus(x)) return t(`consent.${x}`)
    if (c.f === STATUS_FIELD && (ORG_STATUSES as readonly string[]).includes(x)) return t(`orgStatus.${x}`)
    if (c.f === 'member.role' && (MEMBER_ROLES as readonly string[]).includes(x)) return t(`memberRole.${x}`)
    return x
  }
  return c.v.split(',').map(word).filter(Boolean).join(', ')
}

/**
 * «Who is in it»: one phrase per condition («Role is HR», «Account is Trial»); a condition joined by OR to the one
 * before it says so. A stored filter the words cannot express gives one honest phrase instead of a guess.
 */
export function describeQuery(query: unknown, t: T): string[] {
  const conds = fromQuery(query)
  if (conds === null) return [t('cond.custom')]
  if (conds.length === 0) return [t('cond.everyone')]
  return conds.map((c) => {
    const field = fieldDef(c.f) ? t(`field.${c.f.replace('.', '_')}`) : c.f
    const phrase = c.op === 'between'
      ? t('cond.between', { field, from: c.v, to: c.v2 ?? '' })
      : c.op === 'empty' ? (c.f === 'product.last_round_days' ? t('cond.noRound') : t('cond.empty', { field }))
        : t(`cond.${c.op}`, { field, value: valueText(c, t) })
    return c.join === 'or' ? t('cond.or', { phrase }) : phrase
  })
}

/** The saved list's rule under its name: the phrases in a row, later ones starting in lower case as the design writes them. */
export const ruleLine = (phrases: string[]) =>
  phrases.map((p, i) => (i > 0 && p.length > 1 && p[1] === p[1]!.toLowerCase() ? p[0]!.toLowerCase() + p.slice(1) : p)).join(' · ')
