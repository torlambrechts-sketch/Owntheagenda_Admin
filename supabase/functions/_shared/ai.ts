/**
 * ai-run's own rules (0078, X-V3-2), pure so they are tested (tests/v3-ai-gateway.test.ts).
 *
 * ai_prepare's answer decides the whole Claude request, so it is parsed field by field before any of it is sent
 * (CLAUDE.md: an RPC result is parsed, never cast; the functions carry no zod). The time budget keeps ai-run's own total
 * under the app's 150 s abort and under the edge runtime's wall clock: one try of at most 60 s and one retry, all of it
 * cut at 130 s.
 */
export type Effort = 'low' | 'medium' | 'high'
export type Prepared = {
  /** the ai_calls row ai_prepare reserved: counted against the hourly cap, completed by worker_ai_record */
  call: number
  feature: string
  subject: string
  staff: string
  model: string
  effort: Effort
  max_tokens: number
  system: string
  prompt: string
}

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
export const FEATURE = /^[a-z][a-z_]{2,39}$/
const MODEL = /^claude-[a-z0-9-]{3,40}$/

export const CLAUDE_TIMEOUT_MS = 60_000
export const CLAUDE_RETRIES = 1
export const CLAUDE_BUDGET_MS = 130_000

const isText = (x: unknown): x is string => typeof x === 'string' && x.trim().length > 0

/** the reserved call's id alone: a request that did not parse still completes its reservation */
export function preparedCall(v: unknown): number | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null
  const c = (v as Record<string, unknown>).call
  return typeof c === 'number' && Number.isSafeInteger(c) && c > 0 ? c : null
}

/** ai_prepare's request, or null when any field is not what 0078 returns (bounds as ai_settings and ai_features hold them) */
export function parsePrepared(v: unknown): Prepared | null {
  const call = preparedCall(v)
  if (call === null) return null
  const o = v as Record<string, unknown>
  if (typeof o.feature !== 'string' || !FEATURE.test(o.feature)) return null
  if (typeof o.subject !== 'string' || !UUID.test(o.subject) || typeof o.staff !== 'string' || !UUID.test(o.staff)) return null
  if (typeof o.model !== 'string' || !MODEL.test(o.model)) return null
  if (o.effort !== 'low' && o.effort !== 'medium' && o.effort !== 'high') return null
  if (typeof o.max_tokens !== 'number' || !Number.isInteger(o.max_tokens) || o.max_tokens < 256 || o.max_tokens > 16000) return null
  if (!isText(o.system) || !isText(o.prompt)) return null
  return { call, feature: o.feature, subject: o.subject, staff: o.staff, model: o.model, effort: o.effort, max_tokens: o.max_tokens, system: o.system, prompt: o.prompt }
}
