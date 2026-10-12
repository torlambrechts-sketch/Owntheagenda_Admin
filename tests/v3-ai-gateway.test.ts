import { afterEach, describe, expect, it, vi } from 'vitest'
import { CLAUDE_BUDGET_MS, CLAUDE_RETRIES, CLAUDE_TIMEOUT_MS, parsePrepared, preparedCall } from '../supabase/functions/_shared/ai'

vi.mock('server-only', () => ({}))
vi.mock('@/lib/rpc', () => ({ rpc: vi.fn() }))
vi.mock('@/lib/supabase/env', () => ({ supabaseEnv: () => ({ url: 'https://db.example', key: 'anon' }) }))
vi.mock('@/lib/storage/server', () => ({ accessToken: async () => 'token' }))

const { AI_RUN_WAIT_MS, aiRun, aiRunFailure } = await import('../lib/ai/run')

/** what ai_prepare returns (0078) */
const prepared = (over: Record<string, unknown> = {}) => ({
  call: 4211, feature: 'spec_draft', subject_type: 'dev_roadmap_item', subject: '00000000-0000-4000-8000-000000000001',
  staff: '00000000-0000-4000-8000-000000000002', model: 'claude-opus-5-5', effort: 'medium', max_tokens: 4000,
  system: 'Write a spec.', prompt: 'Pulse surveys', ...over,
})

describe('ai-run: ai_prepare\'s answer is parsed before anything reaches Claude (0078)', () => {
  it('takes the request as 0078 returns it, with the reserved call', () => {
    expect(parsePrepared(prepared())).toEqual({
      call: 4211, feature: 'spec_draft', subject: '00000000-0000-4000-8000-000000000001', staff: '00000000-0000-4000-8000-000000000002',
      model: 'claude-opus-5-5', effort: 'medium', max_tokens: 4000, system: 'Write a spec.', prompt: 'Pulse surveys',
    })
  })
  it('refuses a drifted shape: a renamed key, a number as a string, an empty system, a model or effort it does not know', () => {
    const bad: Record<string, unknown>[] = [
      { max_tokens: '4000' }, { max_tokens: 100 }, { max_tokens: 20000 }, { max_tokens: 4000.5 }, { system: null }, { system: '  ' }, { prompt: '' },
      { model: 'gpt-4o' }, { model: 'claude-' }, { effort: 'max' }, { staff: 'tor' }, { subject: null }, { feature: 'Spec' }, { call: '4211' },
      { call: 0 }, { call: null },
    ]
    for (const over of bad) expect(parsePrepared(prepared(over)), JSON.stringify(over)).toBeNull()
    expect(parsePrepared(null)).toBeNull()
    expect(parsePrepared([prepared()])).toBeNull()
    const { max_tokens: _gone, ...renamed } = prepared()
    expect(parsePrepared({ ...renamed, maxTokens: 4000 })).toBeNull()
  })
  it('still finds the reserved call in an answer that did not parse, so the reservation is completed rather than left to the sweep', () => {
    expect(preparedCall(prepared({ max_tokens: '4000' }))).toBe(4211)
    expect(preparedCall({ call: -1 })).toBeNull()
    expect(preparedCall('4211')).toBeNull()
  })
})

describe('ai-run: the time budget stays under the app\'s own wait', () => {
  it('one try and one retry fit in the budget, and the budget ends before the app gives up', () => {
    expect(CLAUDE_TIMEOUT_MS * (1 + CLAUDE_RETRIES)).toBeLessThanOrEqual(CLAUDE_BUDGET_MS)
    expect(CLAUDE_BUDGET_MS).toBeLessThan(AI_RUN_WAIT_MS)
    expect(AI_RUN_WAIT_MS).toBeLessThanOrEqual(150_000)
  })
})

describe('lib/ai/run: a request that ran out of time is a timeout, not «not connected»', () => {
  afterEach(() => { vi.unstubAllGlobals() })
  it('names the error by what happened', () => {
    expect(aiRunFailure(new DOMException('The operation timed out.', 'TimeoutError'))).toBe('timeout')
    expect(aiRunFailure(new DOMException('aborted', 'AbortError'))).toBe('timeout')
    expect(aiRunFailure(new TypeError('fetch failed'))).toBe('not_connected')
    expect(aiRunFailure('boom')).toBe('not_connected')
  })
  it('aiRun answers «timeout» when its own wait ends, and «not_connected» when the gateway is not reached', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new DOMException('The operation timed out.', 'TimeoutError') }))
    expect(await aiRun('spec_draft', '00000000-0000-4000-8000-000000000001')).toEqual({ ok: false, code: 'timeout' })
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('fetch failed') }))
    expect(await aiRun('spec_draft', '00000000-0000-4000-8000-000000000001')).toEqual({ ok: false, code: 'not_connected' })
  })
  it('passes ai-run\'s own codes through, the timeout among them', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ ok: false, code: 'timeout' }), { status: 504, headers: { 'content-type': 'application/json' } })))
    expect(await aiRun('spec_draft', '00000000-0000-4000-8000-000000000001')).toEqual({ ok: false, code: 'timeout' })
  })
})
