import { describe, expect, it } from 'vitest'
import { addDays, fromZoned, isoWeek, monthGrid, mondayOf, parseYmd, weekday, zoned } from '@/lib/data/activities-time'

describe('activities calendar arithmetic', () => {
  it('starts the week on Monday', () => {
    expect(weekday({ y: 2026, m: 10, d: 5 })).toBe(1)
    expect(mondayOf({ y: 2026, m: 10, d: 11 })).toEqual({ y: 2026, m: 10, d: 5 })
    expect(isoWeek({ y: 2026, m: 10, d: 5 })).toBe(41)
  })

  it('puts 1 October 2026 on a Thursday in the month grid', () => {
    const cells = monthGrid(2026, 10)
    expect(weekday({ y: 2026, m: 10, d: 1 })).toBe(4)
    expect(cells.slice(0, 4)).toEqual([null, null, null, { y: 2026, m: 10, d: 1 }])
    expect(cells.length).toBe(35)
  })

  it('converts wall-clock time in a zone, across the DST change', () => {
    const at = fromZoned({ y: 2026, m: 10, d: 6 }, 9, 30, 'Europe/Oslo')
    expect(at.toISOString()).toBe('2026-10-06T07:30:00.000Z')
    const winter = fromZoned({ y: 2026, m: 11, d: 2 }, 9, 30, 'Europe/Oslo')
    expect(winter.toISOString()).toBe('2026-11-02T08:30:00.000Z')
    expect(zoned(winter, 'Europe/Oslo')).toMatchObject({ y: 2026, m: 11, d: 2, h: 9, min: 30 })
  })

  it('parses only real days', () => {
    expect(parseYmd('2026-02-30')).toBeNull()
    expect(parseYmd('2026-10-31')).toEqual({ y: 2026, m: 10, d: 31 })
    expect(addDays({ y: 2026, m: 10, d: 31 }, 1)).toEqual({ y: 2026, m: 11, d: 1 })
  })
})
