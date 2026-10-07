import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { runJob } from '@/lib/jobs/run'

const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const id = '7c1f4b5e-0000-4000-8000-000000000001'
const ran = (over: Record<string, unknown>) => ({ ok: true, ran: true, kind: 'transcript', state: 'ready', reason: null, segments: 3, others: 0, ...over })

// The app's side of jobs-run (0054): the caller's own token, every answer parsed, and never a failed action
describe('jobs runner', () => {
  beforeEach(() => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://example.supabase.co')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', 'anon')
  })
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.unstubAllEnvs()
  })

  it('posts the kind and the id with the caller\'s own token, and reads a finished run', async () => {
    const fetchMock = vi.fn(async () => reply(ran({})))
    vi.stubGlobal('fetch', fetchMock)
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'ready', reason: null })
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('https://example.supabase.co/functions/v1/jobs-run')
    expect((init.headers as Record<string, string>).authorization).toBe('Bearer tok')
    expect(JSON.parse(init.body as string)).toEqual({ kind: 'transcript', id })
  })

  it('reads a written package, a failure with its reason, and a job that could not finish as pending', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => reply(ran({ kind: 'privacy', state: 'done', segments: null }))))
    expect(await runJob('tok', { kind: 'privacy', id })).toEqual({ state: 'done', reason: null })
    vi.stubGlobal('fetch', vi.fn(async () => reply(ran({ state: 'failed', reason: 'no_segments', segments: null }))))
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'failed', reason: 'no_segments' })
    vi.stubGlobal('fetch', vi.fn(async () => reply(ran({ state: 'processing', reason: 'storage', segments: null }))))
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'pending', reason: 'storage' })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, ran: false, kind: 'privacy', state: 'running', reason: 'busy', segments: null, others: 0 })))
    expect(await runJob('tok', { kind: 'privacy', id })).toEqual({ state: 'pending', reason: 'busy' })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, ran: false, kind: 'transcript', state: 'ready', reason: 'done', segments: null, others: 0 })))
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'ready', reason: null })
  })

  it('never throws: unreachable, not deployed, refused or a strange answer leave the job pending', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('down') }))
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'pending', reason: 'not_connected' })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ error: 'x' }, 404)))
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'pending', reason: 'not_connected' })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ error: 'unauthorized' }, 401)))
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'pending', reason: 'not_signed_in' })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ error: 'not_allowed' }, 403)))
    expect(await runJob('tok', { kind: 'privacy', id })).toEqual({ state: 'pending', reason: 'forbidden' })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ error: 'not_found' }, 403)))
    expect(await runJob('tok', { kind: 'privacy', id })).toEqual({ state: 'pending', reason: 'not_found' })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, ran: true, kind: 'privacy', state: 'ready', reason: null, segments: 1, others: 0 })))
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'pending', reason: 'failed' }) // another kind answered
    vi.stubGlobal('fetch', vi.fn(async () => reply(ran({ reason: 'Not a code!' }))))
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'pending', reason: 'failed' })
  })

  it('sends nothing without a token, for an id that is not a uuid, or without the Supabase settings', async () => {
    const fetchMock = vi.fn(async () => reply(ran({})))
    vi.stubGlobal('fetch', fetchMock)
    expect(await runJob(null, { kind: 'transcript', id })).toEqual({ state: 'pending', reason: 'not_signed_in' })
    expect(await runJob('tok', { kind: 'transcript', id: '../x' })).toEqual({ state: 'pending', reason: 'failed' })
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', '')
    expect(await runJob('tok', { kind: 'transcript', id })).toEqual({ state: 'pending', reason: 'not_connected' })
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
