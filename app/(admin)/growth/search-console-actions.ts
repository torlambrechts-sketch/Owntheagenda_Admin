'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { handOverGoogleKey, searchConsoleRun } from '@/lib/search-console/run'

/**
 * Growth › SEO › Search Console (0064). The owner connects: an intake number (fresh second factor), the JSON key handed to
 * secret-intake, then search-console-run proves it, maps the sites and imports. Each action parses its input and answers
 * `{ ok: true, … }` or `{ ok: false, code, detail }`; the database and the function decide (owner, fresh second factor) again.
 */
type Fail = { ok: false; code: RpcCode | string; detail?: string | null }
type Res<T = object> = ({ ok: true } & T) | Fail

const Intake = z.object({ intake_code: z.string().regex(/^[0-9a-f]{48}$/), expires_in: z.number() })
/** a Google service account's JSON key file, as Google hands it out */
const GoogleKey = z.string().max(6000).refine((s) => {
  try {
    const j = JSON.parse(s) as Record<string, unknown>
    return j.type === 'service_account' && typeof j.client_email === 'string' && /@[a-z0-9.-]+\.iam\.gserviceaccount\.com$/.test(j.client_email)
      && typeof j.private_key === 'string' && j.private_key.startsWith('-----BEGIN PRIVATE KEY-----')
  } catch {
    return false
  }
})
const done = () => revalidatePath('/growth')

export async function connectSearchConsole(input: unknown): Promise<Res<{ mapped: number; sites: number; rows: number }>> {
  const p = z.object({ key: GoogleKey }).safeParse(input)
  if (!p.success) return { ok: false, code: 'invalid', detail: 'bad_key' }
  const intake = await rpc('search_console_intake', {}, Intake)
  if (!intake.ok) return intake
  const handed = await handOverGoogleKey(intake.data.intake_code, p.data.key.trim())
  if (!handed.ok) return { ok: false, code: 'failed', detail: handed.code }
  const r = await searchConsoleRun('connect')
  done()
  if (!r.ok) return { ok: false, code: 'not_connected', detail: r.code ?? 'failed' }
  return { ok: true, mapped: (r.sites ?? []).filter((s) => s.property).length, sites: (r.sites ?? []).length, rows: r.rows ?? 0 }
}

/** Check again: the key, the properties the account may read, then import what time allows. */
export async function checkSearchConsole(): Promise<Res<{ mapped: number; rows: number }>> {
  const r = await searchConsoleRun('connect')
  done()
  if (!r.ok) return { ok: false, code: 'not_connected', detail: r.code ?? 'failed' }
  return { ok: true, mapped: (r.sites ?? []).filter((s) => s.property).length, rows: r.rows ?? 0 }
}

/** Import now instead of tonight. */
export async function importSearchConsole(): Promise<Res<{ rows: number }>> {
  const r = await searchConsoleRun('run')
  done()
  if (!r.ok) return { ok: false, code: 'not_connected', detail: r.code ?? 'failed' }
  return { ok: true, rows: r.rows ?? 0 }
}

export async function disconnectSearchConsole(): Promise<Res> {
  const r = await rpc('search_console_disconnect', {}, z.unknown())
  done()
  return r.ok ? { ok: true } : r
}
