import { describe, expect, it } from 'vitest'
import { Budget, Flows, Outcomes, Trial, ice, observedCac, outcomeRow, pace, scenario, suggestedMove, yearSpan } from '../lib/growth/playbook'
import { growthHref, parseGrowth } from '../lib/growth/scope'

type Row = Budget['rows'][number]
const row = (channel: Row['channel'], budget: number | null, spend90: number | null, paying90: number | null, spent = 0): Row => ({ channel, budget, spent, spend90, paying90 })

describe('Playbook: outcomes (0076)', () => {
  it('costs per signup, account and paying customer, and the months a customer takes to pay it back', () => {
    const o = outcomeRow({ channel: 'paid_search', spend: 30400, signups: 64, accounts: 42, paying: 17, mrr: 10540 }, 620)
    expect(o.cps).toBeCloseTo(475)
    expect(o.cpa).toBeCloseTo(723.8, 1)
    expect(o.cac).toBeCloseTo(1788.2, 1)
    expect(o.payback).toBeCloseTo(2.88, 2)
  })
  it('without spend, paying customers or ARPA the figure is not there', () => {
    expect(outcomeRow({ channel: 'organic_search', spend: null, signups: 151, accounts: 104, paying: 41, mrr: 0 }, 620)).toEqual({ cps: null, cpa: null, cac: null, payback: null })
    expect(outcomeRow({ channel: 'paid_search', spend: 1000, signups: 10, accounts: null, paying: null, mrr: null }, 620).cac).toBeNull()
    expect(outcomeRow({ channel: 'paid_search', spend: 1000, signups: 10, accounts: 5, paying: 2, mrr: 0 }, null).payback).toBeNull()
  })
  it('parses the read, journeys absent without a source', () => {
    const d = Outcomes.parse({ model: 'first', days: 90, attributed: false, arpa: null, tracked_since: null, channels: [], journeys: null })
    expect(d.journeys).toBeNull()
    expect(() => Outcomes.parse({ model: 'position', days: 90, attributed: false, arpa: null, tracked_since: null, channels: [], journeys: null })).toThrow()
  })
})

describe('Playbook: budget pace (0076)', () => {
  it('measures spend against the share of the month gone: within 15 % ahead and 20 % under is on pace', () => {
    // day 11 of 31, 35,5 % gone
    expect(pace(30000, 11800, 11, 31).state).toBe('on')
    expect(pace(8000, 2100, 11, 31).state).toBe('under')
    expect(pace(null, 500, 11, 31)).toEqual({ state: 'none', share: 0, runsOut: null })
  })
  it('ahead of pace says the day the budget runs out at today’s rate, within the month', () => {
    const p = pace(10000, 6000, 10, 30)
    expect(p.state).toBe('ahead')
    expect(p.runsOut).toBe(16)
    expect(pace(1000, 5000, 10, 30).runsOut).toBe(10)
  })
})

describe('Playbook: suggested move and scenario (0076)', () => {
  it('moves 30 % of the dearest channel’s budget, in whole hundreds, when it costs half again the cheapest', () => {
    const m = suggestedMove([row('paid_search', 30000, 30000, 17), row('paid_social', 24000, 24000, 6), row('email', 2000, 1200, 4)])
    expect(m).toMatchObject({ from: 'paid_social', to: 'email', amount: 7200 })
    expect(m!.gain).toBeCloseTo(7200 / 300 - 7200 / 4000, 1)
  })
  it('no move when the costs are close, or fewer than two channels have one, or the dearest has no budget', () => {
    expect(suggestedMove([row('paid_search', 10000, 10000, 10), row('paid_social', 10000, 12000, 10)])).toBeNull()
    expect(suggestedMove([row('paid_search', 10000, 10000, 10), row('paid_social', 10000, 10000, null)])).toBeNull()
    expect(suggestedMove([row('paid_search', 10000, 10000, 10), row('paid_social', null, 50000, 2)])).toBeNull()
    expect(suggestedMove([row('paid_search', 10000, 1000, 10), row('paid_social', 200, 5000, 1)])).toBeNull()
  })
  it('observed cost per paying customer needs both spend and paying customers', () => {
    expect(observedCac({ spend90: 9000, paying90: 3 })).toBe(3000)
    expect(observedCac({ spend90: 9000, paying90: 0 })).toBeNull()
    expect(observedCac({ spend90: null, paying90: 3 })).toBeNull()
  })
  it('the scenario buys at the cheapest observed cost and prices it at ARPA', () => {
    const rows = [row('paid_search', 1, 20000, 10), row('paid_social', 1, 40000, 5)]
    expect(scenario(20000, rows, 620)).toEqual({ paying: 10, mrr: 6200 })
    expect(scenario(20000, rows, null)).toEqual({ paying: 10, mrr: null })
    expect(scenario(0, rows, 620)).toBeNull()
    expect(scenario(20000, [row('paid_search', 1, null, null)], 620)).toBeNull()
  })
  it('parses the last move of the month', () => {
    const b = Budget.parse({ month: '2026-10-01', day: 11, days: 31, attributed: true, arpa: 620,
      last_move: { from: 'paid_social', to: 'paid_search', amount: 7200, at: '2026-10-11T10:00:00Z' }, rows: [row('paid_search', 30000, 1, 1)] })
    expect(b.last_move?.amount).toBe(7200)
  })
})

describe('Playbook: experiments, calendar, flows (0076)', () => {
  it('ICE is the mean of impact, confidence and ease, to one decimal', () => {
    expect(ice({ impact: 9, confidence: 8, ease: 8 })).toBe(8.3)
    expect(ice({ impact: 6, confidence: 6, ease: 9 })).toBe(7)
  })
  it('places a period on the year line, clipped to the year, at least a day wide', () => {
    expect(yearSpan('2026-01-01', '2026-12-31', 2026)).toEqual({ x: 0, w: 100 })
    const d = yearSpan('2026-07-01', '2026-07-01', 2026)!
    expect(d.w).toBeCloseTo(100 / 365, 3)
    expect(yearSpan('2025-12-01', '2026-01-31', 2026)!.x).toBe(0)
    expect(yearSpan('2025-01-01', '2025-02-01', 2026)).toBeNull()
  })
  it('a trial flow’s steps name the email they send, never its content', () => {
    const t = Trial.parse({ trials: { ended: 7, converted: 2, ended_prev: 0, converted_prev: 0 }, first_survey: { days: 1.8, days_prev: null, accounts: 13 },
      abandoned: { n: 30, n_prev: 4 }, tracked_since: null,
      flows: [{ id: '00000000-0000-4000-8000-000000000001', name: 'Trial day 7', kind: 'lifecycle', state: 'draft', activated: false, trigger: 'org.created', trigger_data: null,
        steps: [{ kind: 'delay', email: null, amount: 7, unit: 'days' }, { kind: 'email_auto', email: 'Velkommen', amount: null, unit: null }], in_flow: 0, completed_90: 0 }] })
    expect(t.flows[0]!.steps[1]).toEqual({ kind: 'email_auto', email: 'Velkommen', amount: null, unit: null })
    expect(Flows.parse([]).length).toBe(0)
  })
})

describe('Playbook: the address (0076)', () => {
  it('carries the sub-view and the attribution model, first touch by default', () => {
    expect(parseGrowth({ tab: 'campaigns', sub: 'outcomes', am: 'last' })).toMatchObject({ tab: 'campaigns', sub: 'outcomes', am: 'last' })
    expect(parseGrowth({ tab: 'campaigns', am: 'data_driven' }).am).toBe('first')
    expect(growthHref('campaigns', {}, { sub: 'outcomes', am: 'first' })).toBe('/growth?tab=campaigns&sub=outcomes')
    expect(growthHref('campaigns', { range: '7d' }, { sub: 'outcomes', am: 'last' })).toBe('/growth?tab=campaigns&sub=outcomes&am=last')
    expect(growthHref('email', {}, { sub: 'deliver' })).toBe('/growth?tab=email&sub=deliver')
  })
})
