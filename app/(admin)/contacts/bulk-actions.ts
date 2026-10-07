'use server'

import { z } from 'zod'
import type { RpcCode } from '@/lib/rpc'
import { loadBulkChanges, revertBulkChange, type BulkChange } from '@/lib/data/platform-bulk'

/** Contacts › Restore · Bulk changes (R-6), built by the Platform builder (V-PLATFORM-14). Inputs parsed; refusals as codes. */
type Fail = { ok: false; code: RpcCode; detail?: string | null }

export async function fetchBulkChanges(): Promise<{ ok: true; rows: BulkChange[] } | Fail> {
  const r = await loadBulkChanges()
  return r.ok ? { ok: true, rows: r.data } : { ok: false, code: r.code, detail: r.detail }
}

export async function revertBulk(input: unknown): Promise<{ ok: true; reverted: number; stale: number; gone: number; forbidden: number } | Fail> {
  const p = z.object({ id: z.string().uuid(), reason: z.string().trim().max(300).optional() }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await revertBulkChange(p.data.id, p.data.reason || null)
  return r.ok ? { ok: true, reverted: r.data.reverted, stale: r.data.stale, gone: r.data.gone, forbidden: r.data.forbidden } : { ok: false, code: r.code, detail: r.detail }
}
