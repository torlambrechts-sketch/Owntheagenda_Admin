import 'server-only'
import { z } from 'zod'
import { rpcOrThrow } from '@/lib/rpc'

const num = z.coerce.number()
export const Overview = z.object({
  mrr: z.object({ now: num, priced: num, prev: num.nullable() }),
  paying: z.object({ now: num, subs_now: num, prev: num.nullable() }),
  trials: z.object({ now: num, ending7: num, ended_month: num, converted_month: num }),
  apps: z.array(
    z.object({
      key: z.string(), name: z.string(), color: z.string(), ink: z.string(), host: z.string().nullable(), enabled: z.boolean(), installed: z.boolean(),
      orgs: num, mrr: num.nullable(), last_event_at: z.string().nullable(),
    }),
  ),
  mrr_series: z.array(z.object({ month: z.string(), by_product: z.record(z.string(), num) })),
  trials_list: z.array(
    z.object({
      account_id: z.string().uuid(), organization_id: z.string().uuid().nullable(), name: z.string(), org_number: z.string().nullable(),
      employees: num.nullable(), ends: z.string(), source: z.string().nullable(), owner: z.string().nullable(),
    }),
  ),
  tickets: z.object({ open: num, at_risk: num, median_first_response_min: num.nullable() }).nullable(),
  pipeline: z.object({
    weighted: num, open: num, rotting: num,
    stages: z.array(z.object({ name: z.string(), n: num, value: num })),
  }).nullable(),
  at_risk: z.array(z.object({ name: z.string() })).nullable(),
  todo: z.array(z.object({ tone: z.enum(['alert', 'warn', 'ok']), key: z.string(), params: z.record(z.string(), z.union([z.string(), z.number()])), href: z.string() })),
})
export type Overview = z.infer<typeof Overview>

export const loadOverview = (product: string) => rpcOrThrow('overview', { p_product: product }, Overview)
