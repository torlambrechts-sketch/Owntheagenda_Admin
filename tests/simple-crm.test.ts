import { describe, expect, it } from 'vitest'
import { canEditDeal, describeQuery, listQuery, monthKey, ruleLine, summarise, type CrmRights } from '@/lib/data/simple-crm-shared'
import en from '@/messages/en/simple-crm.json'

// a translator over the English file, as next-intl would format these simple messages
const t = (key: string, values: Record<string, string | number> = {}) => {
  const raw = key.split('.').reduce<unknown>((o, k) => (o as Record<string, unknown>)?.[k], en.simpleCrm)
  if (typeof raw !== 'string') throw new Error(`missing ${key}`)
  return raw.replace(/\{(\w+)\}/g, (_, k: string) => String(values[k] ?? `{${k}}`))
}

describe('the board summary', () => {
  const now = new Date('2026-10-07T12:00:00Z')
  const card = (status: 'open' | 'won' | 'lost', value: number, probability: number, at: string | null = null) =>
    ({ status, value, probability, won_at: status === 'won' ? at : null, lost_at: status === 'lost' ? at : null })

  it('counts open deals, their value and the stage-weighted value', () => {
    const s = summarise([card('open', 100_000, 10), card('open', 50_000, 60)], 'Europe/Oslo', now)
    expect(s).toMatchObject({ count: 2, value: 150_000, weighted: 40_000, wonValue: 0, wonCount: 0, lostCount: 0 })
  })

  it('takes won and lost from the current month only, nothing added', () => {
    const s = summarise([
      card('won', 84_000, 80, '2026-10-04T12:00:00Z'),
      card('won', 10_000, 80, '2026-09-30T12:00:00Z'),
      card('lost', 36_000, 60, '2026-10-02T12:00:00Z'),
      card('lost', 5_000, 60, null),
    ], 'Europe/Oslo', now)
    expect(s).toMatchObject({ count: 0, wonValue: 84_000, wonCount: 1, lostCount: 1 })
  })

  it('reads the month in the staff member’s time zone', () => {
    // 22:30 UTC on 30 September is already October in Oslo
    expect(monthKey(new Date('2026-09-30T22:30:00Z'), 'Europe/Oslo')).toBe('2026-10')
    expect(monthKey(new Date('2026-09-30T22:30:00Z'), 'UTC')).toBe('2026-09')
    expect(monthKey(new Date('2026-09-30T22:30:00Z'), 'Not/AZone')).toBe('2026-09')
  })
})

describe('who may move a deal', () => {
  const r = (x: Partial<CrmRights>): CrmRights => ({ meId: 'me', add: true, editOthers: false, readOnly: false, exportRows: false, lists: false, addList: false, growth: false, ...x })
  it('the owner, or anyone with edit_others; never a read-only person', () => {
    expect(canEditDeal(r({}), { owner_id: 'me' })).toBe(true)
    expect(canEditDeal(r({}), { owner_id: 'someone' })).toBe(false)
    expect(canEditDeal(r({ editOthers: true }), { owner_id: 'someone' })).toBe(true)
    expect(canEditDeal(r({ readOnly: true, add: false }), { owner_id: 'me' })).toBe(false)
  })
})

describe('a saved list in words', () => {
  it('says the design’s phrases for role, account status and email status', () => {
    expect(describeQuery({ filters: [{ f: 'title', op: 'eq', v: 'HR' }, { f: 'organization.status', op: 'eq', v: 'trial' }] }, t))
      .toEqual(['Role is HR', 'Account is Trial'])
    expect(describeQuery({ filters: [{ f: 'marketing_status', op: 'eq', v: 'subscribed' }] }, t)).toEqual(['Email status is Subscribed'])
    expect(ruleLine(['Role is HR', 'Account is Trial'])).toBe('Role is HR · account is Trial')
  })

  it('handles ranges, OR groups, an empty filter and one the words cannot express', () => {
    expect(describeQuery({
      filters: [
        { f: 'organization.employees', op: 'gte', v: 26 }, { f: 'organization.employees', op: 'lte', v: 100 },
        { or: [[{ f: 'engagement.opened_days', op: 'lte', v: 90 }], [{ f: 'fylke', op: 'in', v: ['Vestland', 'Rogaland'] }]] },
      ],
    }, t)).toEqual(['Employees is 26–100', 'Days since last open is at most 90', 'or County is one of Vestland, Rogaland'])
    expect(describeQuery({ filters: [] }, t)).toEqual(['Everyone'])
    expect(describeQuery({ filters: [{ f: 'nonsense', op: 'eq', v: 1 }] }, t)).toEqual(['Conditions set in Campaigns'])
    expect(describeQuery({ filters: [{ f: 'product.last_round_days', op: 'empty' }] }, t)).toEqual(['No survey round yet'])
  })

  it('the new-list form leaves «any» out of the filter', () => {
    expect(listQuery('', '')).toEqual({ filters: [] })
    expect(listQuery('HR', 'trial')).toEqual({ filters: [{ f: 'title', op: 'eq', v: 'HR' }, { f: 'organization.status', op: 'eq', v: 'trial' }] })
  })
})
