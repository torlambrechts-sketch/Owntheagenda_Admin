'use server'

import { cookies } from 'next/headers'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { NOTIFICATION_KINDS } from '@/lib/notification-kinds'
import { rpc } from '@/lib/rpc'

const year = 60 * 60 * 24 * 365
const cookieOpts = { httpOnly: true, sameSite: 'lax' as const, secure: process.env.NODE_ENV === 'production', path: '/', maxAge: year }

/** The product the shell is filtered to (the design kept it in localStorage; a cookie lets the server filter). */
export async function setProduct(key: string): Promise<void> {
  const k = z.string().regex(/^(all|[a-z][a-z0-9_]{1,30})$/).safeParse(key)
  if (!k.success) return
  ;(await cookies()).set('product', k.data, cookieOpts)
  revalidatePath('/', 'layout')
}

export async function setSandbox(on: boolean): Promise<{ ok: boolean }> {
  const r = await rpc('sandbox_set', { p_on: z.boolean().parse(on) }, z.object({ sandbox: z.boolean() }))
  revalidatePath('/', 'layout')
  return { ok: r.ok }
}

export async function clearSamples(): Promise<{ ok: boolean; removed?: number }> {
  const r = await rpc('sandbox_clear', {}, z.object({ removed: z.number() }))
  revalidatePath('/', 'layout')
  return r.ok ? { ok: true, removed: r.data.removed } : { ok: false }
}

export async function setLocale(locale: 'en' | 'no'): Promise<{ ok: boolean }> {
  const l = z.enum(['en', 'no']).parse(locale)
  const r = await rpc('profile_set', { p_values: { locale: l } }, z.object({ ok: z.boolean() }))
  ;(await cookies()).set('lang', l, cookieOpts)
  revalidatePath('/', 'layout')
  return { ok: r.ok }
}

const SearchResult = z.array(
  z.object({ group: z.string(), items: z.array(z.object({ entity: z.string(), id: z.string().uuid(), title: z.string().nullable(), sub: z.string().nullable() })) }),
)
export type SearchResult = z.infer<typeof SearchResult>

export async function search(q: string): Promise<SearchResult | null> {
  const text = z.string().max(100).safeParse(q)
  if (!text.success) return null
  const r = await rpc('search', { p_q: text.data }, SearchResult)
  return r.ok ? r.data : null
}

const Notifications = z.object({
  unread: z.number(),
  items: z.array(
    z.object({
      id: z.string().uuid(),
      kind: z.enum(NOTIFICATION_KINDS),
      key: z.string(),
      params: z.record(z.string(), z.union([z.string(), z.number()])),
      route: z.string().nullable(),
      created_at: z.string(),
      read: z.boolean(),
    }),
  ),
})
export type Notifications = z.infer<typeof Notifications>

export async function notifications(kind: 'mention' | 'reminder' | 'security' | null): Promise<Notifications | null> {
  const k = z.enum(['mention', 'reminder', 'security']).nullable().parse(kind)
  const r = await rpc('notifications_get', { p_kind: k }, Notifications)
  return r.ok ? r.data : null
}

export async function markRead(ids: string[] | null): Promise<void> {
  await rpc('notifications_read', { p_ids: z.array(z.string().uuid()).nullable().parse(ids) }, z.object({ read: z.number() }))
  revalidatePath('/', 'layout')
}
