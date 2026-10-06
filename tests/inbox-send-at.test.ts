import { describe, expect, it } from 'vitest'
import { mergeTokens, mentionsAttachment, replySubject, sendAtInstant } from '@/lib/data/inbox-shared'

describe('sendAtInstant (Europe/Oslo)', () => {
  const tz = 'Europe/Oslo'
  it('sends now without a time', () => {
    expect(sendAtInstant('now', new Date('2026-10-06T10:00:00Z'), tz)).toBeNull()
  })
  it('tomorrow 08:00 is the next calendar day in the staff member’s zone', () => {
    // Tuesday 6 Oct 23:30 in Oslo (21:30Z) → Wednesday 7 Oct 08:00 CEST = 06:00Z
    expect(sendAtInstant('tomorrow', new Date('2026-10-06T21:30:00Z'), tz)?.toISOString()).toBe('2026-10-07T06:00:00.000Z')
    // just after midnight in Oslo it is already the 7th, so tomorrow is the 8th
    expect(sendAtInstant('tomorrow', new Date('2026-10-06T22:30:00Z'), tz)?.toISOString()).toBe('2026-10-08T06:00:00.000Z')
  })
  it('Monday 09:00 is the next Monday after today, across the change to winter time', () => {
    expect(sendAtInstant('monday', new Date('2026-10-06T10:00:00Z'), tz)?.toISOString()).toBe('2026-10-12T07:00:00.000Z')
    // on a Monday it is the Monday after; 26 Oct is after the clocks go back (CET, UTC+1)
    expect(sendAtInstant('monday', new Date('2026-10-19T10:00:00Z'), tz)?.toISOString()).toBe('2026-10-26T08:00:00.000Z')
  })
})

describe('composer checks', () => {
  it('finds merge tokens once', () => {
    expect(mergeTokens('Hei [Person.fornavn], [Person.fornavn] og [Organisasjon.navn]')).toEqual(['Person.fornavn', 'Organisasjon.navn'])
  })
  it('notices a mentioned attachment', () => {
    expect(mentionsAttachment('Vedlagt er forslaget')).toBe(true)
    expect(mentionsAttachment('Takk for sist')).toBe(false)
  })
  it('prefixes Re: once', () => {
    expect(replySubject('Re: Forslag')).toBe('Re: Forslag')
    expect(replySubject('Pris for tre lokasjoner?')).toBe('Re: Pris for tre lokasjoner?')
  })
})
