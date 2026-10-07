import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { rebase, resetSignerCache, sign, signerReady } from '@/lib/storage/sign'
import { acceptFor, RECORD_TYPES, TRANSCRIPT_TYPES, typeFor } from '@/lib/storage/mime'

const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const path = 'project/7c1f4b5e-0000-4000-8000-000000000001/7c1f4b5e-0000-4000-8000-000000000002/Plan.pdf'

// The app's side of storage-sign (0052): every answer parsed, refusals mapped to message codes, URLs on the app's origin
describe('storage signer', () => {
  beforeEach(() => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://example.supabase.co')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', 'anon')
    resetSignerCache()
  })
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.unstubAllEnvs()
  })

  it('posts the caller\'s own token and the path, and re-bases the signed upload URL onto the app\'s Supabase origin', async () => {
    const fetch = vi.fn(async () => reply({ ok: true, mode: 'upload', bucket: 'record-files', path, token: 'tok', url: `http://kong:8000/storage/v1/object/upload/sign/record-files/${path}?token=tok` }))
    vi.stubGlobal('fetch', fetch)
    expect(await sign('user-jwt', { mode: 'upload', bucket: 'record-files', path })).toEqual({
      ok: true, url: `https://example.supabase.co/storage/v1/object/upload/sign/record-files/${path}?token=tok`,
    })
    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('https://example.supabase.co/functions/v1/storage-sign')
    expect((init.headers as Record<string, string>).authorization).toBe('Bearer user-jwt')
    expect(JSON.parse(init.body as string)).toEqual({ mode: 'upload', bucket: 'record-files', path })
  })

  it('returns a download URL and refuses an answer of the wrong shape or for another path', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, mode: 'download', url: 'https://example.supabase.co/storage/v1/object/sign/record-files/x?token=t&download=Plan.pdf', expires_in: 60 })))
    expect(await sign('t', { mode: 'download', bucket: 'record-files', path })).toEqual({ ok: true, url: 'https://example.supabase.co/storage/v1/object/sign/record-files/x?token=t&download=Plan.pdf' })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, mode: 'download', url: 'not a url' })))
    expect(await sign('t', { mode: 'download', bucket: 'record-files', path })).toEqual({ ok: false, code: 'failed', detail: null })
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, mode: 'upload', bucket: 'record-files', path: 'other/path/x.pdf', token: 't', url: 'https://example.supabase.co/storage/v1/object/upload/sign/record-files/other?token=t' })))
    expect(await sign('t', { mode: 'upload', bucket: 'record-files', path })).toEqual({ ok: false, code: 'failed', detail: null })
  })

  it('never sends a climbing path, an unknown bucket or an empty token', async () => {
    const fetch = vi.fn()
    vi.stubGlobal('fetch', fetch)
    expect(await sign('t', { mode: 'upload', bucket: 'record-files', path: 'project/../../etc/x' })).toEqual({ ok: false, code: 'invalid', detail: 'path' })
    expect(await sign('t', { mode: 'upload', bucket: 'avatars' as never, path })).toEqual({ ok: false, code: 'invalid', detail: 'path' })
    expect(await sign('', { mode: 'download', bucket: 'record-files', path })).toEqual({ ok: false, code: 'invalid', detail: 'path' })
    expect(fetch).not.toHaveBeenCalled()
  })

  it('maps the signer\'s refusals to the codes the screens have messages for', async () => {
    const cases: [number, unknown, unknown][] = [
      [403, { error: 'not_allowed' }, { ok: false, code: 'forbidden', detail: null }],
      [403, { error: 'not_found' }, { ok: false, code: 'not_found', detail: null }],
      [403, { error: 'expired' }, { ok: false, code: 'not_available', detail: 'expired' }],
      [403, { error: 'missing' }, { ok: false, code: 'not_available', detail: 'missing' }],
      [403, { error: 'exists' }, { ok: false, code: 'invalid', detail: 'exists' }],
      [401, { error: 'unauthorized' }, { ok: false, code: 'not_signed_in', detail: null }],
      [404, { error: 'NOT_FOUND' }, { ok: false, code: 'not_connected', detail: 'storage' }],
      [503, null, { ok: false, code: 'not_connected', detail: 'storage' }],
      [502, { error: 'failed' }, { ok: false, code: 'failed', detail: null }],
    ]
    for (const [status, body, want] of cases) {
      vi.stubGlobal('fetch', vi.fn(async () => reply(body, status)))
      expect(await sign('t', { mode: 'download', bucket: 'record-files', path })).toEqual(want)
    }
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('fetch failed') }))
    expect(await sign('t', { mode: 'download', bucket: 'record-files', path })).toEqual({ ok: false, code: 'not_connected', detail: 'storage' })
  })

  it('only re-bases Storage object URLs', () => {
    expect(rebase('http://127.0.0.1:54421/storage/v1/object/sign/b/p?token=1', 'http://127.0.0.1:54499/')).toBe('http://127.0.0.1:54499/storage/v1/object/sign/b/p?token=1')
    expect(rebase('https://evil.example/elsewhere?x=1', 'https://example.supabase.co')).toBeNull()
    expect(rebase('nonsense', 'https://example.supabase.co')).toBeNull()
  })

  it('says whether the signer runs, remembers it for a minute and a failure for fifteen seconds', async () => {
    const fetch = vi.fn(async () => reply({ ok: true, buckets: true }))
    vi.stubGlobal('fetch', fetch)
    expect(await signerReady('t', 1_000)).toBe(true)
    expect(await signerReady('t', 50_000)).toBe(true)
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(await signerReady(null, 62_000)).toBe(false)              // expired, and nobody to ask with
    vi.stubGlobal('fetch', vi.fn(async () => reply({ message: 'Function not found' }, 404)))
    expect(await signerReady('t', 63_000)).toBe(false)
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, buckets: true })))
    expect(await signerReady('t', 70_000)).toBe(false)                 // the failure is remembered …
    expect(await signerReady('t', 79_000)).toBe(true)                  // … for fifteen seconds
    resetSignerCache()
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, buckets: false })))
    expect(await signerReady('t', 100_000)).toBe(false)
    resetSignerCache()
    vi.stubGlobal('fetch', vi.fn(async () => reply({ error: 'unauthorized' }, 401)))
    expect(await signerReady('t', 200_000)).toBe(false)
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ok: true, buckets: true })))
    expect(await signerReady('t', 200_001)).toBe(true)                 // an unauthorised probe is not remembered
  })
})

describe('upload types', () => {
  it('takes the type from the extension, as the RPCs require', () => {
    expect(typeFor('Samtale.SRT', TRANSCRIPT_TYPES)).toBe('application/x-subrip')
    expect(typeFor('møte.vtt', TRANSCRIPT_TYPES)).toBe('text/vtt')
    expect(typeFor('opptak.m4a', RECORD_TYPES)).toBe('audio/mp4')
    expect(typeFor('IMG_0001.HEIC', RECORD_TYPES)).toBe('image/heic')
    expect(typeFor('plan.exe', RECORD_TYPES)).toBeNull()
    expect(typeFor('no-extension', RECORD_TYPES)).toBeNull()
    expect(typeFor('rapport.pdf', TRANSCRIPT_TYPES)).toBeNull()
  })

  it('offers the extensions and types a picker filters by', () => {
    expect(acceptFor(TRANSCRIPT_TYPES)).toBe('.vtt,.srt,.txt,.docx,text/vtt,application/x-subrip,text/plain,application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    expect(acceptFor(RECORD_TYPES, (m) => m.startsWith('audio/'))).toBe('.webm,.m4a,.mp3,audio/webm,audio/mp4,audio/mpeg')
  })
})
