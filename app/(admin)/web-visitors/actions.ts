'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'

export type Result<T = object> = ({ ok: true } & T) | { ok: false; code: RpcCode; detail?: string | null }

/**
 * Convert a visiting company (WEB-04, deals:add): the organization found or made from the register, then a lead
 * or a deal with source «Web visitors». The visit history links through the organization's org number.
 */
export async function convertVisitor(input: { org: string; kind: 'lead' | 'deal' | 'organization' }): Promise<Result<{ id: string | null; entity: 'lead' | 'deal' | 'organization' }>> {
  const p = z.object({ org: z.string().regex(/^\d{9}$/), kind: z.enum(['lead', 'deal', 'organization']) }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid' }
  const r = await rpc('visitor_convert', { p_org_number: p.data.org, p_kind: p.data.kind, p_pipeline: null, p_stage: null },
    z.object({ organization_id: z.string().uuid().optional(), lead_id: z.string().uuid().optional(), deal_id: z.string().uuid().optional() }))
  if (!r.ok) return { ok: false, code: r.code, detail: r.detail }
  revalidatePath('/web-visitors')
  const id = p.data.kind === 'lead' ? r.data.lead_id : p.data.kind === 'deal' ? r.data.deal_id : r.data.organization_id
  return { ok: true, id: id ?? null, entity: p.data.kind }
}
