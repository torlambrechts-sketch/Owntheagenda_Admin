import { describe, expect, it } from 'vitest'
import {
  allSteps, delayDays, errorTarget, findStep, insertStep, makeStep, newKey, removeStep, sameSlot, setConfig, slotAfter, type Graph,
} from '@/lib/data/automation-graph'

const g: Graph = {
  steps: [
    { key: 'c', kind: 'condition', config: { groups: [[{ f: 'value', op: 'gt', v: 1 }]] } },
    { key: 'b', kind: 'if_else', config: { groups: [] }, then: [{ key: 't1', kind: 'add_note', config: { body: 'x' } }], else: [] },
    { key: 'n', kind: 'notify', config: { message: 'm' } },
  ],
}

describe('automation graph', () => {
  it('walks every step depth first, branches included', () => {
    expect(allSteps(g.steps).map((s) => s.key)).toEqual(['c', 'b', 't1', 'n'])
    expect(findStep(g, 't1')?.kind).toBe('add_note')
  })

  it('makes keys the engine accepts and never reuses one', () => {
    const k = newKey(g)
    expect(k).toMatch(/^[a-z0-9_]{1,24}$/)
    expect(allSteps(g.steps).some((s) => s.key === k)).toBe(false)
  })

  it('inserts into the top level and into a branch path', () => {
    const top = insertStep(g, { list: [], index: 1 }, makeStep(g, 'delay'))
    expect(top.steps.map((s) => s.kind)).toEqual(['condition', 'delay', 'if_else', 'notify'])
    const inElse = insertStep(g, { list: [1, 'else'], index: 0 }, { key: 'e1', kind: 'webhook', config: {} })
    expect(inElse.steps[1]!.else!.map((s) => s.key)).toEqual(['e1'])
    expect(g.steps[1]!.else).toEqual([]) // the original is untouched
  })

  it('a new if/else starts with two empty paths', () => {
    const s = makeStep(g, 'if_else')
    expect(s.then).toEqual([])
    expect(s.else).toEqual([])
    expect(s.config).toHaveProperty('groups')
  })

  it('removes a step wherever it is and edits a config in place', () => {
    expect(allSteps(removeStep(g, 't1').steps).map((s) => s.key)).toEqual(['c', 'b', 'n'])
    expect(findStep(setConfig(g, 't1', { body: 'y' }), 't1')?.config).toEqual({ body: 'y' })
  })

  it('finds the slot after a step, inside a branch too', () => {
    expect(slotAfter(g, 'c')).toEqual({ list: [], index: 1 })
    expect(sameSlot(slotAfter(g, 't1'), { list: [1, 'then'], index: 1 })).toBe(true)
    expect(slotAfter(g, 'missing')).toBeNull()
  })

  it('sums delays the way the engine does', () => {
    expect(delayDays({ amount: 3, unit: 'days' })).toBe(3)
    expect(delayDays({ amount: 12, unit: 'hours' })).toBe(0.5)
    expect(delayDays({ amount: 1440, unit: 'minutes' })).toBe(1)
  })

  it('reads the step and field from a validation detail', () => {
    expect(errorTarget('graph.s3.template_id')).toEqual({ key: 's3', field: 'template_id' })
    expect(errorTarget('graph.u.values.foo')).toEqual({ key: 'u', field: 'values.foo' })
    expect(errorTarget('graph.steps')).toEqual({ key: null, field: null })
    expect(errorTarget('trigger_config.entity')).toEqual({ key: null, field: null })
  })
})
