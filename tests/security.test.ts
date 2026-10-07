import { describe, expect, it } from 'vitest'
import { cidrOk, errorDetailKey, foundIn, intervalUnit, parseInterval, timeOk } from '@/lib/data/security-shared'
import en from '@/messages/en/security.json'
import no from '@/messages/no/security.json'

describe('security: retention intervals', () => {
  it('parses the intervals retention_get returns', () => {
    expect(parseInterval('30 days')).toEqual({ years: 0, months: 0, days: 30 })
    expect(parseInterval('1 year 1 mon')).toEqual({ years: 1, months: 1, days: 0 })
    expect(parseInterval('3 years')).toEqual({ years: 3, months: 0, days: 0 })
    expect(parseInterval(null)).toBeNull()
    expect(parseInterval('01:00:00')).toBeNull()
  })
  it('words a period in one unit', () => {
    expect(intervalUnit('1 year 1 mon')).toEqual({ unit: 'months', n: 13 })
    expect(intervalUnit('5 years')).toEqual({ unit: 'years', n: 5 })
    expect(intervalUnit('60 days')).toEqual({ unit: 'days', n: 60 })
    expect(intervalUnit('1 year 2 days')).toBeNull()
  })
})

describe('security: rule inputs (as the database checks them)', () => {
  it('accepts ranges no wider than /8 or /16', () => {
    expect(cidrOk('193.69.41.0/24')).toBe(true)
    expect(cidrOk('84.208.12.40')).toBe(true)
    expect(cidrOk('10.0.0.0/8')).toBe(true)
    expect(cidrOk('10.0.0.0/7')).toBe(false)
    expect(cidrOk('300.1.1.1/24')).toBe(false)
    expect(cidrOk('2001:db8::/32')).toBe(true)
    expect(cidrOk('2001:db8::/8')).toBe(false)
    expect(cidrOk('office')).toBe(false)
  })
  it('accepts HH:MM only', () => {
    expect(timeOk('07:00')).toBe(true)
    expect(timeOk('24:00')).toBe(false)
    expect(timeOk('7:00')).toBe(false)
  })
})

describe('security: privacy preview and refusals', () => {
  it('lists only the modules where the person was found, in order', () => {
    expect(foundIn({ tickets: 1, people: 1, emails: 3, deals: 0 })).toEqual([
      { key: 'people', n: 1 }, { key: 'emails', n: 3 }, { key: 'tickets', n: 1 },
    ])
  })
  it('every count and every known refusal detail has a message in both languages', () => {
    for (const m of [en, no]) {
      for (const k of ['people', 'leads', 'emails', 'email_participants', 'activities', 'activity_guests', 'deals', 'deal_participants', 'tickets',
        'consent_events', 'form_submissions', 'chat_conversations', 'campaign_recipients', 'meetings', 'documents', 'signatures', 'bookings',
        'product_events', 'enrichment_requests', 'history']) {
        expect(m.security.privacy.counts).toHaveProperty(k)
      }
      for (const d of ['fresh_mfa', 'self_lockout', 'product_user', 'owner_only', 'rate_limited']) {
        expect(errorDetailKey(d)).toBe(d)
        expect(m.security.errors).toHaveProperty(d)
      }
    }
    expect(errorDetailKey('scope:action')).toBeNull()
  })
})
