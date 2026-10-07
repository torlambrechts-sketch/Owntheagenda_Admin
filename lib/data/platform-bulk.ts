import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'

/**
 * Revertable bulk changes (Contacts R-6; 0044 bulk_changes_get / bulk_change_revert), shown on Contacts › Restore where the
 * design draws them. Every rec_bulk call logs the before-values; a revert goes row by row through rec_save, so rights and the
 * version apply per record.
 */
export const BulkChangesZ = z.array(z.object({
  id: z.string(),
  entity: z.string(),
  staff: z.string().nullable(),
  at: z.string(),
  fields: z.array(z.string()),
  count: z.number(),
  reverted_at: z.string().nullable(),
  revert_result: z.object({ reverted: z.number(), stale: z.number(), gone: z.number(), forbidden: z.number() }).nullable(),
  can_revert: z.boolean(),
}))
export type BulkChange = z.infer<typeof BulkChangesZ>[number]

export const RevertZ = z.object({ id: z.string(), reverted: z.number(), stale: z.number(), gone: z.number(), forbidden: z.number() })

export const loadBulkChanges = () => rpc('bulk_changes_get', { p_entity: null, p_limit: 20 }, BulkChangesZ)
export const revertBulkChange = (id: string, reason: string | null) => rpc('bulk_change_revert', { p_id: id, p_reason: reason }, RevertZ)
