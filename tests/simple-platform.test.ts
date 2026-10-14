import { beforeEach, describe, expect, it, vi } from 'vitest'

// Sentral Simple › Platform's actions (app/(admin)/platform/actions.ts): the product's two-level reply (product-command's
// envelope around the product function's own {ok, error}), the commands' argument names (Orgpuls 0205 calls by name), and
// the status message's delivery record. The product, the database and the session are stubbed.
const runCommand = vi.fn()
const rpc = vi.fn()
const noticeSet = vi.fn()
const loadNotice = vi.fn()
let rights: string[] = []

vi.mock('server-only', () => ({}))
vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }))
vi.mock('@/lib/platform/command', () => ({ runCommand: (...a: unknown[]) => runCommand(...a) }))
vi.mock('@/lib/rpc', () => ({ rpc: (...a: unknown[]) => rpc(...a) }))
vi.mock('@/lib/data/platform', () => ({ loadNotice: (...a: unknown[]) => loadNotice(...a) }))
vi.mock('@/app/(admin)/applications/actions', () => ({ noticeSet: (...a: unknown[]) => noticeSet(...a) }))
vi.mock('@/lib/shell', () => ({
  getShell: async () => ({ me: { permission_kind: 'regular', rights } }),
  can: (s: { me: { rights: string[] } }, scope: string, action: string) => s.me.rights.includes(`${scope}:${action}`),
}))

const { fetchProductFlags, setProductFlag, publishNotice, inviteStaff } = await import('@/app/(admin)/platform/actions')

beforeEach(() => {
  runCommand.mockReset(); rpc.mockReset(); noticeSet.mockReset(); loadNotice.mockReset()
  rights = []
})

describe('feature flags through modules.list / modules.set_status', () => {
  it('maps the product modules and counts pilots', async () => {
    runCommand.mockResolvedValue({ ok: true, result: { ok: true, modules: [
      { key: 'pulse', version: '1.0.0', name: 'Pulse', status: 'published', items: 12, pilots: [{ org_id: 'a', name: 'A' }], variants: [] },
      { key: 'nynorsk', version: '0.1.0', name: 'Nynorsk', status: 'draft', items: 0, pilots: [] },
    ], adoption: [] } })
    const r = await fetchProductFlags('orgpuls')
    expect(runCommand).toHaveBeenCalledWith('orgpuls', 'modules.list', {})
    expect(r).toEqual({ ok: true, flags: [
      { key: 'pulse', version: '1.0.0', name: 'Pulse', status: 'published', items: 12, pilots: 1 },
      { key: 'nynorsk', version: '0.1.0', name: 'Nynorsk', status: 'draft', items: 0, pilots: 0 },
    ] })
  })

  it('says why when the product refuses or does not answer, and never reaches another product', async () => {
    runCommand.mockResolvedValueOnce({ ok: true, result: { ok: false, error: 'not_allowed' } })
    expect(await fetchProductFlags('orgpuls')).toEqual({ ok: false, code: 'not_connected', detail: 'not_allowed' })
    runCommand.mockResolvedValueOnce({ ok: false, error: 'http_503' })
    expect(await fetchProductFlags('orgpuls')).toEqual({ ok: false, code: 'not_connected', detail: 'http_503' })
    runCommand.mockResolvedValueOnce({ ok: false, error: 'Some <html> page' })
    expect(await fetchProductFlags('orgpuls')).toEqual({ ok: false, code: 'not_connected', detail: 'failed' })
    expect(await fetchProductFlags('skiftly')).toEqual({ ok: false, code: 'not_available', detail: 'command_path' })
    expect(runCommand).toHaveBeenCalledTimes(3)
  })

  it('switches only with the right to configure and a reason, by argument name', async () => {
    const input = { product: 'orgpuls', key: 'pulse', version: '1.0.0', status: 'retired', reason: 'Replaced by 1.1' }
    expect(await setProductFlag(input)).toEqual({ ok: false, code: 'forbidden' })
    rights = ['global:configure']
    expect(await setProductFlag({ ...input, reason: 'no' })).toEqual({ ok: false, code: 'invalid', detail: 'reason' })
    runCommand.mockResolvedValue({ ok: true, result: { ok: true, result: 'retired' } })
    expect(await setProductFlag(input)).toEqual({ ok: true })
    expect(runCommand).toHaveBeenCalledWith('orgpuls', 'modules.set_status', { p_key: 'pulse', p_version: '1.0.0', p_status: 'retired', p_reason: 'Replaced by 1.1' })
    runCommand.mockResolvedValue({ ok: true, result: { ok: false, error: 'invalid_transition' } })
    expect(await setProductFlag(input)).toEqual({ ok: false, code: 'not_connected', detail: 'invalid_transition' })
  })
})

describe('the status message', () => {
  const id = '6f1c2f0e-6d43-4b8e-9a4c-2f9c1d3e5a10'
  beforeEach(() => {
    loadNotice.mockResolvedValue({ ok: true, data: { current: { problem_ticket_id: 'bc9345fe-eeb7-4358-ac24-4f4094f41dbf' } } })
    noticeSet.mockResolvedValue({ ok: true, id })
    rpc.mockResolvedValue({ ok: true, data: { id, ok: true } })
  })

  it('is stored keeping its problem link, delivered with settings.set_notice and recorded', async () => {
    runCommand.mockResolvedValue({ ok: true, result: { ok: true } })
    expect(await publishNotice({ product: 'orgpuls', text: '  Vedlikehold i kveld ' })).toEqual({ ok: true, delivered: true, code: null })
    expect(noticeSet).toHaveBeenCalledWith({ product: 'orgpuls', text: 'Vedlikehold i kveld', problem: 'bc9345fe-eeb7-4358-ac24-4f4094f41dbf', maintenance: false, confirm: null })
    expect(runCommand).toHaveBeenCalledWith('orgpuls', 'settings.set_notice', { p_on: true, p_no: 'Vedlikehold i kveld', p_en: 'Vedlikehold i kveld' })
    expect(rpc.mock.calls[0]?.slice(0, 2)).toEqual(['status_notice_push_result', { p_id: id, p_ok: true, p_error: null }])
  })

  it('records a failed delivery with its code, and clears with p_on false', async () => {
    runCommand.mockResolvedValue({ ok: false, error: 'timeout' })
    expect(await publishNotice({ product: 'orgpuls', text: null })).toEqual({ ok: true, delivered: false, code: 'timeout' })
    expect(noticeSet).toHaveBeenCalledWith(expect.objectContaining({ text: null, problem: null }))
    expect(runCommand).toHaveBeenCalledWith('orgpuls', 'settings.set_notice', { p_on: false, p_no: null, p_en: null })
    expect(rpc.mock.calls[0]?.[1]).toEqual({ p_id: id, p_ok: false, p_error: 'timeout' })
  })

  it('does not call a product without a command path, and refuses what Orgpuls cannot hold', async () => {
    expect(await publishNotice({ product: 'skiftly', text: 'Hei' })).toEqual({ ok: true, delivered: false, code: 'command_path' })
    expect(runCommand).not.toHaveBeenCalled()
    expect(await publishNotice({ product: 'orgpuls', text: 'x'.repeat(301) })).toEqual({ ok: false, code: 'invalid', detail: 'text' })
    noticeSet.mockResolvedValueOnce({ ok: false, code: 'forbidden', detail: 'global:configure' })
    expect(await publishNotice({ product: 'orgpuls', text: 'Hei' })).toEqual({ ok: false, code: 'forbidden', detail: 'global:configure' })
  })
})

describe('invite', () => {
  it('creates the staff row with the address only, lower-cased', async () => {
    rpc.mockResolvedValue({ ok: true, data: { id: '6f1c2f0e-6d43-4b8e-9a4c-2f9c1d3e5a10' } })
    expect(await inviteStaff(' Kari.Nordmann@Orgpuls.no ')).toEqual({ ok: true, invite: null })
    expect(rpc.mock.calls[0]?.slice(0, 2)).toEqual(['staff_save', { p_id: null, p_values: { email: 'kari.nordmann@orgpuls.no' } }])
    expect(await inviteStaff('not an address')).toEqual({ ok: false, code: 'invalid', detail: 'email' })
  })
  it('says whether the invitation email was queued (0060)', async () => {
    rpc.mockResolvedValue({ ok: true, data: { id: '6f1c2f0e-6d43-4b8e-9a4c-2f9c1d3e5a10', invite: 'queued' } })
    expect(await inviteStaff('kari@orgpuls.no')).toEqual({ ok: true, invite: 'queued' })
  })
})
