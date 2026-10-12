import 'server-only'
import { z } from 'zod'
import { rpcOrThrow } from '@/lib/rpc'
import { supabaseEnv } from '@/lib/supabase/env'
import { CHECK_KEYS, INTEGRATION_KEYS, SUITE_KINDS } from '@/app/(admin)/development/_components/delivery/logic'

/**
 * Development › the delivery half (0080): Releases, Release gate, Integrations register, Code and environments, Delivery
 * metrics, Vercel and Supabase. Every read goes through its database function and is parsed here, never cast.
 */

const uuid = z.string().uuid()
const num = z.coerce.number()
const iso = z.string()
const Product = z.object({ key: z.string(), name: z.string().nullable(), color: z.string().nullable() })
export type DeliveryProduct = z.infer<typeof Product>

// ---------------------------------------------------------------------------
// deploys and CI runs
export const Deployment = z.object({
  id: z.string(),
  project_id: z.string(),
  environment: z.string(),
  state: z.enum(['building', 'ready', 'error', 'canceled']),
  sha: z.string().nullable(),
  ref: z.string().nullable(),
  pr: num.nullable(),
  commit_title: z.string().nullable(),
  host: z.string().nullable(),
  inspector_url: z.string().nullable(),
  created_at: iso.nullable(),
  seen_at: iso,
  ready_at: iso.nullable(),
  failed_at: iso.nullable(),
  promoted_at: iso.nullable(),
  rolled_back_at: iso.nullable(),
})
export type Deployment = z.infer<typeof Deployment>

export const Suite = z.object({ name: z.string(), kind: z.enum(SUITE_KINDS), passed: num, failed: num, skipped: num })
export const Deps = z.object({ critical: num, high: num, moderate: num, low: num })
export const CiRun = z.object({
  product: z.string(),
  sha: z.string(),
  ref: z.string().nullable(),
  pr: num.nullable(),
  commit_at: iso.nullable(),
  commit_title: z.string().nullable(),
  run_url: z.string().nullable(),
  finished_at: iso,
  suites: z.array(Suite),
  migrations_pending: z.array(z.string()),
  deps: Deps.nullable(),
  coverage: num.nullable(),
})
export type CiRun = z.infer<typeof CiRun>

export const Connection = z.object({
  key_stored: z.boolean(),
  status: z.string().nullable(),
  key_stored_at: iso.nullable(),
  last_delivery_at: iso.nullable(),
  applied_30d: num,
  ignored_30d: num,
})
export type Connection = z.infer<typeof Connection>

export const Deploys = z.object({
  can_configure: z.boolean(),
  can_manage: z.boolean(),
  vercel: Connection,
  ci: Connection,
  products: z.array(Product),
  projects: z.array(z.object({ id: z.string(), name: z.string(), product: z.string().nullable(), last_event_at: iso, deployments: num })),
  latest: z.array(Deployment),
  live: z.array(Deployment),
  previews: z.array(Deployment),
  ci_runs: z.array(CiRun),
})
export type Deploys = z.infer<typeof Deploys>
export const loadDeploys = () => rpcOrThrow('dev_deploys', {}, Deploys)

/** the address Vercel and the CI post to: this project's dev-events function */
export function eventsUrl(): string | null {
  const env = supabaseEnv()
  return 'problem' in env ? null : `${env.url}/functions/v1/dev-events`
}

// ---------------------------------------------------------------------------
// metrics
export const Metrics = z.object({
  days: num,
  sources: z.object({ deploys: z.boolean(), ci: z.boolean() }),
  deploys: z.object({ ready: num, per_day: num, finished: num, failed: num, rolled_back: num, failure_rate: num.nullable() }),
  lead: z.object({ n: num, median_hours: num.nullable() }),
  restore: z.object({ n: num, days: num, median_minutes: num.nullable() }),
  coverage: z.array(z.object({ product: z.string(), coverage: num, at: iso })),
})
export type Metrics = z.infer<typeof Metrics>
export const loadMetrics = (days = 30) => rpcOrThrow('dev_metrics', { p_days: days }, Metrics)

// ---------------------------------------------------------------------------
// releases
export const Note = z.object({
  id: uuid,
  product: z.string(),
  kind: z.enum(['new', 'improved', 'fixed']),
  title: z.string(),
  body: z.string().nullable(),
  state: z.enum(['draft', 'published']),
  source: z.string(),
  feature_request_id: uuid.nullable(),
  published_at: iso.nullable(),
  updated_at: iso,
  ord: num.optional(),
})
export type Note = z.infer<typeof Note>

export const Check = z.object({
  key: z.enum(CHECK_KEYS),
  kind: z.enum(['auto', 'manual']),
  source: z.enum(['ci', 'vercel', 'changelog']).nullable(),
  state: z.enum(['pass', 'fail', 'unknown']),
  detail: z.record(z.string(), z.unknown()).nullable(),
  signed: z.object({ by: z.string().nullable(), at: iso, note: z.string().nullable() }).nullable().optional(),
})
export type Check = z.infer<typeof Check>

export const Release = z.object({
  id: uuid,
  product: z.string(),
  name: z.string(),
  planned_on: z.string().nullable(),
  sha: z.string().nullable(),
  state: z.enum(['open', 'recorded']),
  recorded_at: iso.nullable(),
  recorded_by: z.string().nullable(),
  created_at: iso,
  version: num,
  notes: num,
  rollbacks: num.nullable(),
  watching: z.boolean(),
})
export type Release = z.infer<typeof Release>

export const Releases = z.object({
  can_add: z.boolean(),
  products: z.array(Product),
  releases: z.array(Release),
  current: Release.extend({
    checks: z.array(Check),
    commit: z.object({ sha: z.string().nullable(), source: z.enum(['release', 'deploy', 'ci']) }).nullable(),
    ci: z.object({ finished_at: iso, run_url: z.string().nullable(), ref: z.string().nullable() }).nullable(),
    changelog: z.array(Note),
    drafts: z.array(Note),
  }).nullable(),
})
export type Releases = z.infer<typeof Releases>
export type CurrentRelease = NonNullable<Releases['current']>
export const loadReleases = (release: string | null) => rpcOrThrow('dev_releases_get', { p_release: release }, Releases)

// ---------------------------------------------------------------------------
// the integrations register
export const Register = z.object({
  can_configure: z.boolean(),
  can_add: z.boolean(),
  staff: z.array(z.object({ id: uuid, name: z.string() })),
  rows: z.array(z.object({
    key: z.enum(INTEGRATION_KEYS),
    direction: z.enum(['out', 'in']),
    status: z.string().nullable(),
    owner: z.object({ id: uuid, name: z.string().nullable() }).nullable(),
    runs: z.object({ total: num, failed: num }).nullable(),
    deliveries_30d: num.nullable(),
    token_expires_at: iso.nullable(),
    api_version: z.string().nullable(),
    change: z.object({ text: z.string().nullable(), due_on: z.string().nullable(), url: z.string().nullable(), none: z.boolean(), by: z.string().nullable(), at: iso.nullable() }),
    plan: z.object({ id: uuid, change_text: z.string(), due_on: z.string().nullable(), owner: z.string().nullable(), planned_by: z.string().nullable(), planned_at: iso }).nullable(),
  })),
})
export type Register = z.infer<typeof Register>
export type RegisterRow = Register['rows'][number]
export const loadRegister = () => rpcOrThrow('dev_integrations_get', {}, Register)
