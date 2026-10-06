import 'server-only'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'

/**
 * One way to call the platform's database functions: the result is parsed with its zod schema, never cast,
 * and a refusal comes back as a code the UI has a message for. The database raises with a short message
 * (forbidden, not_found, version_conflict, invalid, reason_required, module_off, not_signed_in, approval_required) and a detail
 * naming the field or right.
 */
export const RPC_CODES = ['forbidden', 'not_found', 'version_conflict', 'invalid', 'reason_required', 'module_off', 'not_signed_in', 'fixed_setting', 'approval_required', 'failed'] as const
export type RpcCode = (typeof RPC_CODES)[number]

export class RpcError extends Error {
  constructor(public code: RpcCode, public detail: string | null) {
    super(code)
  }
}

export type RpcResult<T> = { ok: true; data: T } | { ok: false; code: RpcCode; detail: string | null }

const known = new Set<string>(RPC_CODES)

export async function rpc<S extends z.ZodTypeAny>(fn: string, args: Record<string, unknown>, schema: S, opts: { quiet?: boolean } = {}): Promise<RpcResult<z.infer<S>>> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc(fn, args)
  if (error) {
    const code = (known.has(error.message) ? error.message : 'failed') as RpcCode
    if (code === 'failed' && !opts.quiet) console.error(`[rpc] ${fn} failed (${error.code ?? 'no code'})`)
    return { ok: false, code, detail: error.details ?? null }
  }
  const parsed = schema.safeParse(data)
  if (!parsed.success) {
    console.error(`[rpc] ${fn} returned an unexpected shape`, parsed.error.issues.slice(0, 3).map((i) => i.path.join('.')))
    return { ok: false, code: 'failed', detail: null }
  }
  return { ok: true, data: parsed.data }
}

/** The same, for reads a page cannot render without: a refusal throws to the error boundary. */
export async function rpcOrThrow<S extends z.ZodTypeAny>(fn: string, args: Record<string, unknown>, schema: S, opts: { quiet?: boolean } = {}): Promise<z.infer<S>> {
  const r = await rpc(fn, args, schema, opts)
  if (!r.ok) throw new RpcError(r.code, r.detail)
  return r.data
}
