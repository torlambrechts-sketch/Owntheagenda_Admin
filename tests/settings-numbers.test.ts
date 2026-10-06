import { describe, expect, it } from 'vitest'
import { numberBounds, numberOk } from '@/app/(admin)/settings/_components/numbers'

describe('setting numbers', () => {
  it('keeps list hygiene to 6–24 whole months', () => {
    expect(numberOk('list_hygiene', 12)).toBe(true)
    expect(numberOk('list_hygiene', 5)).toBe(false)
    expect(numberOk('list_hygiene', 25)).toBe(false)
    expect(numberOk('list_hygiene', 12.5)).toBe(false)
  })
  it('needs at least one minute or day for the analytics targets', () => {
    expect(numberOk('activation_target', 0)).toBe(false)
    expect(numberOk('activation_target', 30)).toBe(true)
    expect(numberOk('renewal_window', 90)).toBe(true)
    expect(numberOk('renewal_window', 3651)).toBe(false)
  })
  it('leaves the older numeric settings as they were', () => {
    expect(numberBounds('count_limits')).toEqual({ min: 0, max: 1_000_000_000, int: false })
    expect(numberOk('count_limits', 0)).toBe(true)
    expect(numberOk('deal_capacity', 40)).toBe(true)
    expect(numberOk('count_limits', Number.NaN)).toBe(false)
  })
})
