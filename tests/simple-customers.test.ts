import { describe, expect, it } from 'vitest'
import {
  adminContact, ageOf, approvalBlock, initialsOf, pairFor, parseActionNote, priorityOf, requestDays, type TicketRequest,
} from '@/lib/data/simple-customers-shared'
import { IMPACTS, PRIORITIES, URGENCIES } from '@/lib/data/tickets-shared'

// Sentral Simple › Customers: the rules behind the screen (lib/data/simple-customers-shared.ts)
describe('priority onto impact × urgency', () => {
  it('mirrors app.ticket_priority (0012)', () => {
    expect(priorityOf('many_orgs', 'blocking')).toBe('urgent')
    expect(priorityOf('one_user', 'blocking')).toBe('high')
    expect(priorityOf('many_orgs', 'not_blocking')).toBe('high')
    expect(priorityOf('one_org', 'not_blocking')).toBe('normal')
    expect(priorityOf('one_user', 'not_blocking')).toBe('low')
  })

  it('every pair it writes gives the chosen priority', () => {
    for (const impact of IMPACTS) for (const urgency of URGENCIES) for (const p of PRIORITIES) {
      const pair = pairFor(p, { impact, urgency })
      if (priorityOf(impact, urgency) === p) expect(pair).toBeNull()
      else expect(priorityOf(pair!.impact, pair!.urgency)).toBe(p)
    }
  })

  it('keeps the impact when it can, else the canonical pair', () => {
    expect(pairFor('high', { impact: 'one_org', urgency: 'not_blocking' })).toEqual({ impact: 'one_org', urgency: 'blocking' })
    expect(pairFor('urgent', { impact: 'one_user', urgency: 'not_blocking' })).toEqual({ impact: 'many_orgs', urgency: 'blocking' })
    expect(pairFor('low', { impact: 'many_orgs', urgency: 'blocking' })).toEqual({ impact: 'one_user', urgency: 'not_blocking' })
    expect(pairFor('normal', { impact: 'one_user', urgency: 'blocking' })).toEqual({ impact: 'one_org', urgency: 'not_blocking' })
  })
})

describe('«Approve and apply»', () => {
  const trial: TicketRequest = { kind: 'extend_trial', args: { days: 30 } }
  const base = { request: trial, product: 'orgpuls', organizationId: 'o', subscriptionStatus: 'trial' }

  it('runs a trial extension for an Orgpuls account in a trial', () => {
    expect(approvalBlock(base, true)).toBeNull()
    expect(approvalBlock({ ...base, product: null }, true)).toBeNull()
  })

  it('says why it cannot', () => {
    expect(approvalBlock({ ...base, request: null }, true)).toBe('noAction')
    expect(approvalBlock({ ...base, request: { kind: 'other', args: {} } }, true)).toBe('noAction')
    for (const kind of ['change_plan', 'suspend', 'reactivate', 'cancel'] as const) {
      expect(approvalBlock({ ...base, request: { kind, args: {} } }, true)).toBe('noCommand')
    }
    expect(approvalBlock({ ...base, product: 'skiftly' }, true)).toBe('notOrgpuls')
    expect(approvalBlock({ ...base, organizationId: null }, true)).toBe('noOrg')
    expect(approvalBlock({ ...base, subscriptionStatus: 'active' }, true)).toBe('notTrial')
    expect(approvalBlock(base, false)).toBe('noRight')
  })

  it('extends by the days asked for, else 14', () => {
    expect(requestDays(trial)).toBe(30)
    expect(requestDays({ kind: 'extend_trial', args: {} })).toBe(14)
    expect(requestDays({ kind: 'extend_trial', args: { days: 90 } })).toBe(14)
    expect(requestDays(null)).toBe(14)
  })
})

describe('admin contact', () => {
  const u = (o: Partial<Parameters<typeof adminContact>[0][number]>) => ({ product: 'orgpuls', name: 'A', email: 'a@x.no', role: null, active: true, is_billing_contact: false, ...o })

  it('prefers the billing contact, then an admin-like role, then a CRM contact', () => {
    const users = [u({ name: 'Vera', role: 'verneombud' }), u({ name: 'Dag', role: 'daglig_leder' }), u({ name: 'Bea', role: 'avdelingsleder', is_billing_contact: true })]
    expect(adminContact(users, [], 'orgpuls')?.name).toBe('Bea')
    expect(adminContact(users.slice(0, 2), [], 'orgpuls')?.name).toBe('Dag')
    expect(adminContact(users.slice(0, 1), [{ name: 'Kari', email: 'k@x.no' }], 'orgpuls')).toEqual({ name: 'Kari', email: 'k@x.no' })
  })

  it('looks only at the application in scope and at active users', () => {
    expect(adminContact([u({ product: 'skiftly', role: 'admin' }), u({ role: 'daglig_leder', active: false })], [], 'orgpuls')).toBeNull()
  })
})

describe('small formats', () => {
  const now = new Date('2026-10-07T12:00:00Z')
  const before = (ms: number) => new Date(now.getTime() - ms).toISOString()

  it('writes ages the design\'s way', () => {
    expect(ageOf(before(20_000), now)).toEqual({ unit: 'now', n: 0 })
    expect(ageOf(before(12 * 60_000), now)).toEqual({ unit: 'min', n: 12 })
    expect(ageOf(before(39 * 3_600_000), now)).toEqual({ unit: 'd', n: 1 })
    expect(ageOf(before(5 * 3_600_000), now)).toEqual({ unit: 'h', n: 5 })
    expect(ageOf(before(9 * 86_400_000), now)).toEqual({ unit: 'w', n: 1 })
    expect(ageOf(before(95 * 86_400_000), now)).toEqual({ unit: 'mo', n: 3 })
  })

  it('reads an action line and initials', () => {
    expect(parseActionNote('billing.extend_trial:ok')).toEqual({ action: 'billing.extend_trial', ok: true })
    expect(parseActionNote('billing.extend_trial:failed')).toEqual({ action: 'billing.extend_trial', ok: false })
    expect(parseActionNote('Hei!')).toBeNull()
    expect(initialsOf('Kari Nordmann')).toBe('KN')
    expect(initialsOf(null)).toBe('—')
  })
})
