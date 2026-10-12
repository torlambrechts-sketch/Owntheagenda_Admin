import { getNow } from 'next-intl/server'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { loadRegister } from '@/lib/data/dev-delivery'
import { RegisterTable } from './delivery/RegisterTable'

/**
 * Development › Integrations register (DevHub.dc.html, tab «integrations») on dev_integrations_get (0080): Sentral's own
 * integrations, their failure rates from the logs they write (growth_sync_log, job_runs, integration_calls, ai_calls), token
 * expiry where a connection records one, the API version pinned in code (logic.ts API_VERSIONS, tested against the edge
 * functions), and the owner and upcoming change typed by a person. «Plan upgrade» records a plan with the owner and a due
 * date; «Renew token» opens the real reconnection. Product-side dependencies wait for a product event (V-V3E-14).
 */
export async function IntegrationsView({ nf }: DevTabProps) {
  const [data, now] = await Promise.all([loadRegister(), getNow()])
  return <RegisterTable data={data} nf={nf} now={now.getTime()} />
}
