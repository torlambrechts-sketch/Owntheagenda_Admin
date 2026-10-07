/**
 * Sentral Simple › Customers: the fixed value sets and the pure rules the screen shares between server and client
 * (safe to import in client components; proved in tests/simple-customers.test.ts).
 */
import { IMPACTS, URGENCIES, type PRIORITIES } from './tickets-shared'

export const SECTION_TABS = ['accounts', 'tickets'] as const
export type SectionTab = (typeof SECTION_TABS)[number]

/** The design's queues and the tickets_get view behind each (0012, «requests» from 0056). */
export const QUEUES = ['open', 'unassigned', 'requests', 'closed'] as const
export type Queue = (typeof QUEUES)[number]

/** The account list's status filter (the design's five; «all» shows every status). */
export const ACCOUNT_FILTERS = ['all', 'trial', 'active', 'past_due', 'suspended'] as const
export type AccountFilter = (typeof ACCOUNT_FILTERS)[number]

/** The design's priority bar in the ticket list (pc: Urgent #D4633A, High #E0A21F, Normal #9DB8B3, Low #C4BCA8). */
export const PRIORITY_BAR = { urgent: 'bg-alert', high: 'bg-warn', normal: 'bg-teal-mid', low: 'bg-line-strong' } as const

/** The structured service request (0056, app.tickets.request). */
export const REQUEST_KINDS = ['extend_trial', 'change_plan', 'suspend', 'reactivate', 'cancel', 'other'] as const
export type RequestKind = (typeof REQUEST_KINDS)[number]
export type TicketRequest = { kind: RequestKind; args: { days?: number; plan?: string } }

/** The request kinds a product command can apply today: Orgpuls' billing.extend_trial (D-40). */
export const APPLIABLE: readonly RequestKind[] = ['extend_trial']

/** The days a trial extension adds: what the request asks for (1–60), else the design's 14. */
export const requestDays = (r: TicketRequest | null) => (r?.args.days && r.args.days >= 1 && r.args.days <= 60 ? r.args.days : 14)

export type ApprovalBlock = 'noAction' | 'noCommand' | 'notOrgpuls' | 'noOrg' | 'notTrial' | 'noRight'

/**
 * Why «Approve and apply» cannot run for this service request, or null when it can: the request must name a kind a
 * command applies, for an Orgpuls account in a trial, by someone who may run account actions.
 */
export function approvalBlock(t: {
  request: TicketRequest | null
  product: string | null
  organizationId: string | null
  subscriptionStatus: string | null
}, canApprove: boolean): ApprovalBlock | null {
  if (!t.request || t.request.kind === 'other') return 'noAction'
  if (!APPLIABLE.includes(t.request.kind)) return 'noCommand'
  if (t.product && t.product !== 'orgpuls') return 'notOrgpuls'
  if (!t.organizationId) return 'noOrg'
  if (t.subscriptionStatus !== 'trial') return 'notTrial'
  if (!canApprove) return 'noRight'
  return null
}

type Impact = (typeof IMPACTS)[number]
type Urgency = (typeof URGENCIES)[number]
type Priority = (typeof PRIORITIES)[number]

/** app.ticket_priority (0012): the priority impact × urgency gives. */
export const priorityOf = (impact: Impact, urgency: Urgency): Priority =>
  impact === 'many_orgs' && urgency === 'blocking' ? 'urgent' : impact === 'many_orgs' || urgency === 'blocking' ? 'high' : impact === 'one_org' ? 'normal' : 'low'

/** The canonical impact × urgency for each priority (used when nothing of the current pair can be kept). */
const CANONICAL: Record<Priority, { impact: Impact; urgency: Urgency }> = {
  urgent: { impact: 'many_orgs', urgency: 'blocking' },
  high: { impact: 'one_user', urgency: 'blocking' },
  normal: { impact: 'one_org', urgency: 'not_blocking' },
  low: { impact: 'one_user', urgency: 'not_blocking' },
}

/**
 * The design picks a priority; the schema derives it from impact × urgency (a generated column). The pair written is
 * the one that gives the chosen priority while keeping as much of the current pair as possible (impact first), else
 * the canonical pair. Choosing the current priority changes nothing (null).
 */
export function pairFor(target: Priority, current: { impact: Impact; urgency: Urgency }): { impact: Impact; urgency: Urgency } | null {
  if (priorityOf(current.impact, current.urgency) === target) return null
  const options = IMPACTS.flatMap((impact) => URGENCIES.map((urgency) => ({ impact, urgency }))).filter((p) => priorityOf(p.impact, p.urgency) === target)
  const score = (p: { impact: Impact; urgency: Urgency }) => (p.impact === current.impact ? 2 : 0) + (p.urgency === current.urgency ? 1 : 0)
  const best = Math.max(...options.map(score))
  if (best === 0) return CANONICAL[target]
  const kept = options.filter((p) => score(p) === best)
  return kept.find((p) => p.impact === CANONICAL[target].impact && p.urgency === CANONICAL[target].urgency) ?? kept[0]!
}

/** The roles that run an account in a product (Orgpuls' daglig leder; a generic admin or owner elsewhere). */
const ADMIN_ROLES = ['daglig_leder', 'admin', 'owner']

type Member = { product: string; name: string | null; email: string | null; role: string | null; active: boolean; is_billing_contact: boolean }
type Contact = { name: string; email: string | null }

/**
 * The account's admin contact: the application's billing contact, else its first admin-like user, else the first CRM
 * contact; null when the database knows none.
 */
export function adminContact(users: Member[], contacts: Contact[], product: string): { name: string; email: string | null } | null {
  const here = users.filter((u) => u.active && u.product === product && (u.name || u.email))
  const pick = here.find((u) => u.is_billing_contact) ?? here.find((u) => u.role !== null && ADMIN_ROLES.includes(u.role))
  if (pick) return { name: pick.name ?? pick.email ?? '', email: pick.name ? pick.email : null }
  const c = contacts[0]
  return c ? { name: c.name, email: c.email } : null
}

/** «Just now», «12 min», «3 h», «2 d», «1 w», «3 mo», «2 y» — the design's compact ages, as a unit and a count. */
export type Age = { unit: 'now' | 'min' | 'h' | 'd' | 'w' | 'mo' | 'y'; n: number }
export function ageOf(iso: string, now: Date): Age {
  const min = Math.max(0, Math.floor((now.getTime() - new Date(iso).getTime()) / 60_000))
  if (min < 1) return { unit: 'now', n: 0 }
  if (min < 60) return { unit: 'min', n: min }
  const h = Math.floor(min / 60)
  if (h < 24) return { unit: 'h', n: h }
  const d = Math.floor(h / 24)
  if (d < 7) return { unit: 'd', n: d }
  if (d < 30) return { unit: 'w', n: Math.floor(d / 7) }
  if (d < 365) return { unit: 'mo', n: Math.floor(d / 30) }
  return { unit: 'y', n: Math.floor(d / 365) }
}

/** A name's initials for an avatar (two letters). */
export const initialsOf = (name: string | null | undefined) =>
  (name ?? '').split(/[\s@.]+/).filter(Boolean).map((w) => w[0]!.toUpperCase()).slice(0, 2).join('') || '—'

/** The thread line an executed action leaves (ticket_action_note, 0023): «<action>:<ok|failed>». */
export function parseActionNote(body: string): { action: string; ok: boolean } | null {
  const m = /^([a-z_]+\.[a-z_]+):(ok|failed)$/.exec(body.trim())
  return m ? { action: m[1]!, ok: m[2] === 'ok' } : null
}
