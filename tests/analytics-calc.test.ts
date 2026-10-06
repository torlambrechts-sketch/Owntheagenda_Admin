import { describe, expect, it } from 'vitest'
import {
  addMonths, biggestDrop, duration, firstSnapshotMonth, monthsEnding, movementsInRange, pctChange, revenueChurnByMonth, share,
  trialCohortSpan, verdict, weightShares, SIGNALS,
} from '@/lib/data/analytics-calc'

const now = new Date('2026-10-06T10:00:00Z')
const mv = (month: string, x: Partial<{ new: number; expansion: number; contraction: number; churn: number }>) => {
  const m = { new: 0, expansion: 0, contraction: 0, churn: 0, ...x }
  return { month, ...m, net: m.new + m.expansion + m.contraction + m.churn }
}

describe('analytics arithmetic', () => {
  it('walks months across a year', () => {
    expect(addMonths('2026-01', -1)).toBe('2025-12')
    expect(addMonths('2025-11', 14)).toBe('2027-01')
    expect(monthsEnding(now, 3)).toEqual(['2026-08', '2026-09', '2026-10'])
  })

  it('sums the movements of the months the range covers', () => {
    const rows = [mv('2026-10', { new: 100, churn: -20 }), mv('2026-09', { expansion: 50 }), mv('2026-01', { new: 999 })]
    expect(movementsInRange(rows, now, '30d')).toMatchObject({ net: 80, months: 1 })
    expect(movementsInRange(rows, now, '90d')).toMatchObject({ net: 130, expansion: 50, months: 2 })
    expect(movementsInRange(rows, now, '12m').net).toBe(1129)
    expect(firstSnapshotMonth(rows)).toBe('2026-01')
  })

  it('labels the trial cohorts analytics_business counts', () => {
    expect(trialCohortSpan(now, 30)).toEqual(['2026-07', '2026-08'])
  })

  it('never divides by nothing', () => {
    expect(share(3, 0)).toBeNull()
    expect(share(null, 4)).toBeNull()
    expect(share(1, 4)).toBe(25)
    expect(pctChange(110, 100)).toBeCloseTo(10)
    expect(pctChange(110, null)).toBeNull()
  })

  it('answers the first question from the figures', () => {
    expect(verdict(31, 78)).toBe('yes')
    expect(verdict(10, 78)).toBe('partly')
    expect(verdict(10, 20)).toBe('no')
    expect(verdict(null, 78)).toBeNull()
  })

  it('writes durations the way the design does', () => {
    expect(duration(6)).toEqual({ unit: 'min', n: 6 })
    expect(duration(240)).toEqual({ unit: 'h', n: 4 })
    expect(duration(2880)).toEqual({ unit: 'days', n: 2 })
  })

  it('finds the biggest drop-off', () => {
    const steps = [10, 10, 9, 3, 3].map((count, i) => ({ key: `s${i}`, count, median_min: null }))
    expect(biggestDrop(steps)).toEqual({ index: 3, drop: 1 - 3 / 9 })
    expect(biggestDrop([{ key: 'a', count: 0, median_min: null }, { key: 'b', count: 0, median_min: null }])).toBeNull()
  })

  it('shows weights as shares of their sum', () => {
    const w = weightShares({ admin_login: 50, payment: 50 }, SIGNALS)
    expect(w.map((x) => [x.key, x.pct])).toEqual([['admin_login', 50], ['payment', 50]])
  })

  it('knows nothing about revenue churn before the first snapshot', () => {
    const rows = [mv('2026-09', { churn: -10 })]
    const mrr = new Map([['2026-08', 100], ['2026-09', 90], ['2026-07', 100]])
    const r = revenueChurnByMonth(rows, mrr, ['2026-08', '2026-09', '2026-10'])
    expect(r.get('2026-08')).toBeNull()
    expect(r.get('2026-09')).toBe(10)
    expect(r.get('2026-10')).toBe(0)
  })
})
