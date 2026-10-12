import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'

/**
 * The count on the «Bug triage» pill: the application's open bugs (0079 dev_open_bugs; fixed and merged ones do not
 * count), or null when there are none or the count cannot be read — then the pill carries no badge rather than a guess.
 */
export async function openBugCount(product: string): Promise<number | null> {
  const r = await rpc('dev_open_bugs', { p_product: product }, z.coerce.number().int().min(0), { quiet: true })
  return r.ok && r.data > 0 ? r.data : null
}
