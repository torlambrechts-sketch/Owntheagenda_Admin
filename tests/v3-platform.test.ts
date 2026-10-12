import { readFileSync } from 'node:fs'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ORGPULS_COMMANDS } from '@/supabase/functions/_shared/orgpuls.ts'

// Platform › the new tabs (0082): the views' small rules, the tab strip, the two production defects (F-P1 plan keys, F-P2 the
// status message's label), product-command asking command_authorize before it signs, and the approval run: an approved
// product command goes to product-command with the approval's id and exactly the approved arguments, and its outcome is
// recorded. The database, the session and the product are stubbed.
const rpc = vi.fn()
vi.mock('server-only', () => ({}))
vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }))
vi.mock('@/lib/rpc', () => ({ rpc: (...a: unknown[]) => rpc(...a) }))
vi.mock('@/lib/supabase/env', () => ({ supabaseEnv: () => ({ url: 'https://db.example', key: 'anon' }) }))
vi.mock('@/lib/supabase/server', () => ({ createClient: async () => ({ auth: { getSession: async () => ({ data: { session: { access_token: 'token' } } }) } }) }))
vi.mock('next-intl/server', () => ({ getTranslations: async () => (k: string, v?: Record<string, unknown>) => (v ? `${k}:${JSON.stringify(v)}` : k) }))

const logic = await import('@/app/(admin)/platform/_components/plus/logic')
const { SIMPLE_PLATFORM_TABS } = await import('@/lib/data/simple-platform')
const { REQUEST_STATUSES } = await import('@/lib/data/platform-plus')
const actions = await import('@/app/(admin)/platform/plus-actions')

const read = (p: string) => readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
const json = (p: string) => JSON.parse(read(p))

beforeEach(() => {
  rpc.mockReset()
  vi.unstubAllGlobals()
})

describe('the matrix and the views', () => {
  it('cycles a cell ✓ → A → – → ✓ where approval can be carried out, else ✓ ↔ –', () => {
    expect(logic.nextMode('allow', true)).toBe('approve')
    expect(logic.nextMode('approve', true)).toBe('deny')
    expect(logic.nextMode('deny', true)).toBe('allow')
    expect(logic.nextMode('allow', false)).toBe('deny')
    expect(logic.nextMode('deny', false)).toBe('allow')
  })

  it('never offers «allowed» while Settings › Second admin holds the action at approval (D-30)', () => {
    expect(logic.nextMode('approve', true, true)).toBe('deny')
    expect(logic.nextMode('deny', true, true)).toBe('approve')
    expect(logic.nextMode('allow', true, true)).toBe('approve')
  })

  it('keeps message keys free of dots', () => {
    expect(logic.actionKey('trial.extend')).toBe('trial_extend')
    const en = json('messages/en/platform-plus.json').platformPlus.access.roles.actions
    for (const k of ['accounts.view', 'tickets.reply', 'trial.extend', 'support_access.request', 'plan.change', 'credit_note.issue',
      'discount.over_threshold', 'account.delete', 'flags.change', 'announcements.publish', 'customers.export', 'roles.manage']) {
      expect(en[logic.actionKey(k)]).toBeTruthy()
    }
  })

  it('reads the audience the chips name', () => {
    expect(logic.audienceOf(false, false)).toBe('all')
    expect(logic.audienceOf(true, false)).toBe('admins')
    expect(logic.audienceOf(false, true)).toBe('trial')
    expect(logic.audienceOf(true, true)).toBe('admins_trial')
  })

  it('never turns a missing source or an empty cohort into 0 %', () => {
    expect(logic.pctOf(null, 20)).toBeNull()
    expect(logic.pctOf(3, 0)).toBeNull()
    expect(logic.pctOf(0, 20)).toBe(0)
    expect(logic.pctOf(17, 22)).toBe(77)
  })

  it('colours as the design does', () => {
    expect(logic.limitTone(96)).toBe('bg-alert')
    expect(logic.limitTone(82)).toBe('bg-warn')
    expect(logic.errorTone(14)).toBe('text-danger')
    expect(logic.errorTone(2)).toBe('text-warn-ink')
    expect(logic.errorTone(0)).toBe('text-link')
  })

  it('colours a rise in billing tickets as bad and a fall as good, never the count itself', () => {
    expect(logic.trendTone(3, 0)).toBe('text-danger')
    expect(logic.trendTone(1, 4)).toBe('text-link')
    expect(logic.trendTone(2, 2)).toBe('text-muted')
    const billing = read('app/(admin)/platform/_components/plus/BillingTab.tsx')
    expect(billing).not.toMatch(/text-30 font-semibold text-link/)
    // an absent NPS is a muted dash, not a green figure
    expect(read('app/(admin)/platform/_components/plus/SuccessTab.tsx')).toMatch(/text-40 font-semibold text-muted">—/)
  })

  it('says how near a plan\'s limit an account is, not that it will cross it', () => {
    for (const l of ['en', 'no']) {
      const next = json(`messages/${l}/platform-plus.json`).platformPlus.success.renewal.next as string
      expect(next).toContain('{max}')
      expect(next).not.toMatch(/will cross|går over til/)
    }
  })

  it('offers the same request statuses on the screen as the reader accepts', () => {
    expect([...logic.REQUEST_STATUSES]).toEqual([...REQUEST_STATUSES])
  })

  it('knows an open request by its state and its time', () => {
    const now = Date.parse('2026-10-12T12:00:00Z')
    expect(logic.isOpen({ state: 'pending', expires_at: '2026-10-19T12:00:00Z' }, now)).toBe(true)
    expect(logic.isOpen({ state: 'pending', expires_at: '2026-10-12T11:59:00Z' }, now)).toBe(false)
    expect(logic.isOpen({ state: 'executed', expires_at: '2026-10-19T12:00:00Z' }, now)).toBe(false)
  })
})

describe('the tab strip', () => {
  it('has the design\'s seven tabs in its order, «Team» renamed', () => {
    expect([...SIMPLE_PLATFORM_TABS]).toEqual(['apps', 'ops', 'plans', 'billing', 'success', 'team', 'access'])
    for (const l of ['en', 'no']) {
      const tabs = json(`messages/${l}/simple-platform.json`).simplePlatform.tabs
      for (const k of SIMPLE_PLATFORM_TABS) expect(tabs[k]).toBeTruthy()
    }
    expect(json('messages/en/simple-platform.json').simplePlatform.tabs.team).toBe('Team')
    expect(json('messages/en/simple-platform.json').simplePlatform.tabs.access).toBe('Roles and approvals')
  })
})

describe('production defects', () => {
  it('F-P2: the status message is said to reach the public website, not the app', () => {
    for (const l of ['en', 'no']) {
      const n = json(`messages/${l}/simple-platform.json`).simplePlatform.notice
      expect(n.placeholder).not.toMatch(/top of the app|øverst i appen/i)
      expect(n.placeholder).toMatch(/website|nettsted/i)
      expect(n.live).toMatch(/website|nettsted/i)
    }
  })

  it('F-P1: plan_accounts counts a subscription by the plan key Orgpuls sends', () => {
    const sql = read('supabase/migrations/0082_platform_plus.sql')
    const body = sql.slice(sql.indexOf('create or replace function public.plan_accounts'))
    expect(body.slice(0, body.indexOf('end $fn$'))).toContain('s.plan = b.plan_key or s.plan = b.band_label')
    expect(sql).toMatch(/when 25 then 'small' when 100 then 'usual'/)
  })
})

describe('product-command asks command_authorize before it signs (R-PL-1)', () => {
  const src = read('supabase/functions/product-command/index.ts')
  it('asks with the caller\'s own token, before the token is signed', () => {
    const ask = src.indexOf("asUser.rpc('command_authorize'")
    expect(ask).toBeGreaterThan(0)
    expect(ask).toBeLessThan(src.indexOf('signJwt('))
    expect(src).toMatch(/p_approval: approval, p_args: approval \? args : null/)
  })

  it('maps only commands product-command knows to actions', () => {
    const sql = read('supabase/migrations/0082_platform_plus.sql')
    const block = sql.slice(sql.indexOf('insert into app.command_actions'), sql.indexOf('create table app.action_policies'))
    const mapped = [...block.matchAll(/\('orgpuls', '([a-z]+\.[a-z_]+)', '([a-z_]+\.[a-z_]+)'\)/g)].map((m) => m[1]!)
    expect(mapped.length).toBe(8)
    for (const c of mapped) expect(Object.keys(ORGPULS_COMMANDS)).toContain(c)
    expect(mapped).toEqual(expect.arrayContaining(['billing.extend_trial', 'orgs.delete_now', 'settings.set_notice', 'modules.set_status']))
  })
})

describe('the approval run', () => {
  const id = '6f1c1a8e-5a43-4f3e-9d6c-1d2b3c4d5e6f'
  const org = '0b6d7a3e-2c1f-4e5d-8a9b-0c1d2e3f4a5b'
  const args = { p_org: 'orgpuls-o1', p_days: 14, p_reason: 'Asked on the phone' }
  const ok = (data: unknown) => ({ ok: true, data })

  it('runs an approved command once, bound to the approval, and records it', async () => {
    rpc.mockImplementation(async (fn: string) => {
      if (fn === 'approval_decide') return ok({ id, state: 'approved', executor: 'command' })
      if (fn === 'approval_take') return ok({ id, action: 'trial.extend', product: 'orgpuls', command: 'billing.extend_trial', args, organization_id: org, reason: 'Asked on the phone' })
      if (fn === 'approval_done') return ok({ id, state: 'executed' })
      return ok({ ok: true })
    })
    const fetch = vi.fn(async () => new Response(JSON.stringify({ ok: true, result: { ok: true } }), { status: 200 }))
    vi.stubGlobal('fetch', fetch)
    expect(await actions.decideApproval({ id, yes: true })).toEqual({ ok: true, state: 'executed', code: null })
    expect(fetch).toHaveBeenCalledTimes(1)
    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('https://db.example/functions/v1/product-command')
    expect(JSON.parse(String(init.body))).toEqual({ product: 'orgpuls', command: 'billing.extend_trial', args, approval: id })
    expect(rpc).toHaveBeenCalledWith('approval_done', { p_id: id, p_ok: true, p_code: null }, expect.anything())
    expect(rpc).toHaveBeenCalledWith('customer_action_log', { p_org: org, p_action: 'customer.extend_trial', p_reason: 'Asked on the phone', p_ok: true }, expect.anything(), { quiet: true })
  })

  it('records the product\'s own refusal as the outcome', async () => {
    rpc.mockImplementation(async (fn: string) => {
      if (fn === 'approval_decide') return ok({ id, state: 'approved', executor: 'command' })
      if (fn === 'approval_take') return ok({ id, action: 'trial.extend', product: 'orgpuls', command: 'billing.extend_trial', args, organization_id: org, reason: 'r' })
      if (fn === 'approval_done') return ok({ id, state: 'failed' })
      return ok({ ok: true })
    })
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ ok: true, result: { ok: false, error: 'trial_extended_once' } }), { status: 200 })))
    expect(await actions.decideApproval({ id, yes: true })).toEqual({ ok: true, state: 'failed', code: 'trial_extended_once' })
    expect(rpc).toHaveBeenCalledWith('approval_done', { p_id: id, p_ok: false, p_code: 'trial_extended_once' }, expect.anything())
  })

  it('passes product-command\'s refusal on as a code, never its text', async () => {
    rpc.mockImplementation(async (fn: string) => {
      if (fn === 'approval_decide') return ok({ id, state: 'approved', executor: 'command' })
      if (fn === 'approval_take') return ok({ id, action: 'account.delete', product: 'orgpuls', command: 'orgs.delete_now', args: { p_org: 't', p_confirm: '123456789', p_reason: 'r' }, organization_id: null, reason: 'r' })
      return ok({ id, state: 'failed' })
    })
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ ok: false, error: 'Some <html> page' }), { status: 502 })))
    expect(await actions.decideApproval({ id, yes: true, confirm: '123 456 789' })).toEqual({ ok: true, state: 'failed', code: 'failed' })
    expect(rpc).toHaveBeenCalledWith('approval_decide', { p_id: id, p_yes: true, p_note: null, p_confirm: '123456789' }, expect.anything())
  })

  const approvedTrial = (done: unknown) => async (fn: string) => {
    if (fn === 'approval_decide') return ok({ id, state: 'approved', executor: 'command' })
    if (fn === 'approval_take') return ok({ id, action: 'trial.extend', product: 'orgpuls', command: 'billing.extend_trial', args, organization_id: org, reason: 'r' })
    if (fn === 'approval_done') return ok(done)
    return ok({ ok: true })
  }

  it('leaves an outcome it could not see to the database: no answer in time is not «failed»', async () => {
    rpc.mockImplementation(approvedTrial({ id, state: 'executed', code: null }))
    vi.stubGlobal('fetch', vi.fn(async () => { throw new DOMException('The operation timed out.', 'TimeoutError') }))
    expect(await actions.decideApproval({ id, yes: true })).toEqual({ ok: true, state: 'executed', code: null })
    expect(rpc).toHaveBeenCalledWith('approval_done', { p_id: id, p_ok: null, p_code: 'timeout' }, expect.anything())
    expect(rpc).toHaveBeenCalledWith('customer_action_log', expect.objectContaining({ p_ok: true }), expect.anything(), { quiet: true })
  })

  it('keeps a request open while the audit has not answered, and writes no outcome to the customer yet', async () => {
    rpc.mockImplementation(approvedTrial({ id, state: 'executing', code: 'unreachable' }))
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('fetch failed') }))
    expect(await actions.decideApproval({ id, yes: true })).toEqual({ ok: true, state: 'executing', code: 'unreachable' })
    expect(rpc).toHaveBeenCalledWith('approval_done', { p_id: id, p_ok: null, p_code: 'unreachable' }, expect.anything())
    expect(rpc).not.toHaveBeenCalledWith('customer_action_log', expect.anything(), expect.anything(), expect.anything())
  })

  it('treats a reply that is not product-command\'s own as unknown, not as a refusal', async () => {
    rpc.mockImplementation(approvedTrial({ id, state: 'failed', code: 'http_504' }))
    vi.stubGlobal('fetch', vi.fn(async () => new Response('<html>Gateway Timeout</html>', { status: 504 })))
    expect(await actions.decideApproval({ id, yes: true })).toEqual({ ok: true, state: 'failed', code: 'http_504' })
    expect(rpc).toHaveBeenCalledWith('approval_done', { p_id: id, p_ok: null, p_code: 'http_504' }, expect.anything())
  })

  it('waits longer than product-command\'s own call to the product', () => {
    const app = Number(/SEND_TIMEOUT_MS = ([\d_]+)/.exec(read('app/(admin)/platform/plus-actions.ts'))![1]!.replace(/_/g, ''))
    const fn = Number(/AbortSignal\.timeout\(([\d_]+)\)/.exec(read('supabase/functions/product-command/index.ts'))![1]!.replace(/_/g, ''))
    expect(app).toBeGreaterThanOrEqual(fn + 15_000)
  })

  it('a rejection or a policy change runs nothing', async () => {
    const fetch = vi.fn()
    vi.stubGlobal('fetch', fetch)
    rpc.mockResolvedValueOnce(ok({ id, state: 'rejected', executor: null }))
    expect(await actions.decideApproval({ id, yes: false })).toEqual({ ok: true, state: 'rejected', code: null })
    rpc.mockResolvedValueOnce(ok({ id, state: 'executed', executor: 'database', code: null }))
    expect(await actions.decideApproval({ id, yes: true })).toEqual({ ok: true, state: 'executed', code: null })
    expect(fetch).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalledWith('approval_take', expect.anything(), expect.anything())
  })

  it('passes the database\'s refusal on, with its detail', async () => {
    rpc.mockResolvedValueOnce({ ok: false, code: 'forbidden', detail: 'fresh_mfa' })
    expect(await actions.decideApproval({ id, yes: true })).toEqual({ ok: false, code: 'forbidden', detail: 'fresh_mfa' })
  })
})

describe('requests and follow-ups', () => {
  it('asks only with a reason and a trial of 1 to 60 days; the org.nr is sent without spaces', async () => {
    const org = '0b6d7a3e-2c1f-4e5d-8a9b-0c1d2e3f4a5b'
    expect(await actions.requestApproval({ action: 'trial.extend', organization: org, days: 90, reason: 'Asked' })).toEqual({ ok: false, code: 'invalid', detail: null })
    expect(await actions.requestApproval({ action: 'trial.extend', organization: org, days: 14, reason: 'x' })).toEqual({ ok: false, code: 'invalid', detail: 'reason' })
    rpc.mockResolvedValue({ ok: true, data: { id: org, ref: 7 } })
    expect(await actions.requestApproval({ action: 'account.delete', organization: org, confirm: '912 345 678', reason: 'Retention ended' })).toEqual({ ok: true, ref: 7 })
    expect(rpc).toHaveBeenCalledWith('approval_request', { p_action: 'account.delete', p_params: { organization: org, confirm: '912345678' }, p_reason: 'Retention ended' }, expect.anything())
  })

  it('writes an error ticket from the counts read again, never from the screen', async () => {
    const org = '0b6d7a3e-2c1f-4e5d-8a9b-0c1d2e3f4a5b'
    rpc.mockImplementation(async (fn: string) => fn === 'customer_errors'
      ? { ok: true, data: { rows: [{ organization: { id: org, name: 'Lumio AS' }, replies: 2, bounces: 0, failed: 1 }] } }
      : { ok: true, data: { id: org, ref: 'T-12', existing: false } })
    expect(await actions.createErrorTicket({ org, product: 'orgpuls', replies: 999 })).toEqual({ ok: true, ref: 'T-12', existing: false })
    const call = rpc.mock.calls.find((c) => c[0] === 'error_ticket_create')!
    const body = String((call[1] as { p_body: string }).p_body)
    expect(body).toContain('ticketReplies:{"count":2}')
    expect(body).toContain('ticketFailed:{"count":1}')
    expect(body).not.toContain('999')
    expect(body).not.toContain('ticketBounces')
  })
})
