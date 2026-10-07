import { describe, expect, it } from 'vitest'
import { STATE_KEYS, STATE_TONE, attendeeLine, clock, dayIn, minutes, valueText } from '@/lib/data/meetings-shared'

describe('clock (transcript times)', () => {
  it('writes mm:ss as the design does', () => {
    expect(clock(12000)).toBe('00:12')
    expect(clock(160000)).toBe('02:40')
    expect(clock(422999)).toBe('07:02')
  })
  it('adds hours for a long call', () => {
    expect(clock(3723000)).toBe('1:02:03')
  })
})

describe('minutes', () => {
  it('rounds to whole minutes and never shows 0 for a short transcript', () => {
    expect(minutes(422)).toBe(7)
    expect(minutes(20)).toBe(1)
    expect(minutes(0)).toBe(0)
  })
})

describe('dayIn', () => {
  it('tells the calendar day in the staff member’s zone', () => {
    expect(dayIn('2026-10-06T22:30:00Z', 'Europe/Oslo')).toBe('2026-10-07')
    expect(dayIn('2026-10-06T22:30:00Z', 'UTC')).toBe('2026-10-06')
  })
})

describe('attendeeLine', () => {
  const others = (n: number) => `${n} others`
  it('lists up to three names, then «first, N others»', () => {
    expect(attendeeLine(['Kari Nordmann', 'Mona Hansen', 'Petter Aas'], others)).toBe('Kari Nordmann, Mona Hansen, Petter Aas')
    expect(attendeeLine(['Ole Hansen', 'A', 'B', 'C', 'D'], others)).toBe('Ole Hansen, 4 others')
    expect(attendeeLine([], others)).toBe('')
  })
})

describe('valueText (suggestion values)', () => {
  const fmt = (n: number) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')
  const labels: Record<string, string> = { a: 'Hot', b: 'Multi-product' }
  const name = (id: string) => labels[id] ?? null
  it('formats numbers, resolves label ids and joins lists', () => {
    expect(valueText(120000, fmt, name)).toBe('120 000')
    expect(valueText(['a', 'b'], fmt, name)).toBe('Hot, Multi-product')
    expect(valueText('Driftssjef', fmt, name)).toBe('Driftssjef')
  })
  it('has no text for nothing, so the screen shows its dash', () => {
    expect(valueText(null, fmt, name)).toBeNull()
    expect(valueText([], fmt, name)).toBeNull()
    expect(valueText({ x: 1 }, fmt, name)).toBeNull()
  })
})

describe('state tones', () => {
  it('has a colour for every state the database derives (V-P7M-09) and for none', () => {
    for (const k of [...STATE_KEYS, 'none'] as const) expect(STATE_TONE[k]).toBeDefined()
    expect(STATE_TONE.suggestions).toEqual({ c: '#A33A16', bg: '#FBD5C4' })
    expect(STATE_TONE.bot_joins).toEqual({ c: '#2F5D2A', bg: '#CFE7E4' })
  })
})
