import { describe, expect, it } from 'vitest'
import { Definition, delta as rawDelta, figure as rawFigure, initialBuilder, palette, toDefinition } from '@/lib/data/insights-shared'

// the space_comma format groups with a no-break space; compare with plain spaces
const plain = (s: string) => s.replace(/\u00a0/g, ' ')
const figure = (...a: Parameters<typeof rawFigure>) => plain(rawFigure(...a))
const delta = (...a: Parameters<typeof rawDelta>) => { const d = rawDelta(...a); return d ? { ...d, text: plain(d.text) } : d }

describe('insights figures', () => {
  it('writes amounts the way the design does', () => {
    expect(figure('nok', 312000, 'space_comma')).toBe('312 000 kr')
    expect(figure('nok', 1849000, 'space_comma', true)).toBe('1 849k')
    expect(figure('days', 34, 'space_comma')).toBe('34 d')
    expect(figure('percent', 72, 'space_comma')).toBe('72 %')
    expect(figure('count', null, 'space_comma')).toBe('—')
  })
  it('compares with the previous period only when there is one', () => {
    expect(delta('nok', 118, 100, 'space_comma')).toEqual({ text: '+18 %', good: true })
    expect(delta('nok', 90, 100, 'space_comma')).toEqual({ text: '−10 %', good: false })
    expect(delta('nok', 100, 0, 'space_comma')).toBeNull()
    expect(delta('nok', 100, null, 'space_comma')).toBeNull()
    // a shorter sales cycle is the better one
    expect(delta('days', 30, 34, 'space_comma')).toEqual({ text: '−4 d', good: true })
  })
  it('puts the series colour first in the palette', () => {
    expect(palette('#123456')[0]).toBe('#123456')
    expect(palette('nonsense')[0]).toBe('#F5C64A')
  })
})

describe('the builder definition', () => {
  it('describes the design default: sum of value by owner this quarter', () => {
    const d = toDefinition(initialBuilder('00000000-0000-4000-8000-000000000000'))
    expect(d).toEqual({ entity: 'deal', type: 'performance', measure: { fn: 'sum', field: 'value' }, group_by: 'owner',
      period: { kind: 'quarter', field: 'created_at' }, chart: 'column', filters: [] })
    expect(Definition.safeParse(d).success).toBe(true)
  })
  it('waits for a whole custom range and a pipeline for conversion', () => {
    const s = initialBuilder('')
    expect(toDefinition({ ...s, period: 'custom', from: '2026-01-01', to: '' })).toBeNull()
    expect(toDefinition({ ...s, type: 'conversion' })).toBeNull()
    expect(toDefinition({ ...s, type: 'duration' })?.measure).toEqual({ fn: 'cycle_days' })
    expect(toDefinition({ ...s, type: 'duration' })?.period?.field).toBe('won_at')
  })
  it('refuses a definition outside the shape', () => {
    expect(Definition.safeParse({ entity: 'audit' }).success).toBe(false)
    expect(Definition.safeParse({ entity: 'deal', group_by: 'x; drop table' }).success).toBe(false)
  })
})
