'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { loadCampaignDetail, loadSequenceResults } from '@/lib/data/growth-v3'
import { SendWindow, type CampaignDetail, type SequenceResults } from '@/lib/growth/v3'

/**
 * Growth v3's actions (0083). Two reads the card and the email editor ask for when another campaign or sequence is chosen
 * (the first one is read with the page), and the one write: «Send all steps at the best time» on or off. Each parses its
 * input and answers `{ ok: true, … }` or `{ ok: false, code }`; the database checks the rights again. Nothing here reaches
 * an ad platform (X-V3-3).
 */
type Fail = { ok: false; code: RpcCode; detail?: string | null }
const uuid = z.string().uuid()
const product = z.string().regex(/^[a-z][a-z0-9_]{1,40}$/)
const bad: Fail = { ok: false, code: 'invalid' }

export async function campaignDetail(input: { id: string }): Promise<{ ok: true; data: CampaignDetail } | Fail> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await loadCampaignDetail(p.data.id)
  return r.ok ? { ok: true, data: r.data } : { ok: false, code: r.code, detail: r.detail }
}

export async function sequenceResults(input: { id: string }): Promise<{ ok: true; data: SequenceResults } | Fail> {
  const p = z.object({ id: uuid }).safeParse(input)
  if (!p.success) return bad
  const r = await loadSequenceResults(p.data.id)
  return r.ok ? { ok: true, data: r.data } : { ok: false, code: r.code, detail: r.detail }
}

/** The sequence's send window: the application's best time now (the database derives it), or none. */
export async function setSendWindow(input: { id: string; product: string; on: boolean }): Promise<{ ok: true; window: z.infer<typeof SendWindow> | null } | Fail> {
  const p = z.object({ id: uuid, product, on: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('simple_sequence_send_window', { p_id: p.data.id, p_product: p.data.product, p_on: p.data.on },
    z.object({ id: uuid, send_window: SendWindow.nullable() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  revalidatePath('/growth')
  return { ok: true, window: r.data.send_window }
}
