import { loadJobs } from '@/lib/data/dev-core'
import { loadAiStatus } from '@/lib/ai/run'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { JobsView as View } from './core/JobsView'

/**
 * Development › Claude jobs (DevClaude.dc.html, v.jobs): every call of the three Development features through ai-run
 * in 30 days with the draft it made, what became of each draft, the usage they add up to (tokens: no price is recorded),
 * and the Claude connection the owner manages. Nothing here runs in a repository: GitHub is not connected.
 */
export async function JobsView({ nf }: DevTabProps) {
  const [data, ai] = await Promise.all([loadJobs(), loadAiStatus()])
  return <View data={data} ai={ai} nf={nf} now={new Date().toISOString()} />
}
