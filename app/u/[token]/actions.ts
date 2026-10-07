'use server'

import type { Route } from 'next'
import { redirect } from 'next/navigation'
import { z } from 'zod'
import { doUnsubscribe } from '@/lib/mail/public'

/** The button: unsubscribe, then the page again in its done state (the token decides; the answer is the same either way). */
export async function unsubscribe(form: FormData): Promise<void> {
  const token = z.string().regex(/^[A-Za-z0-9_-]{16,128}$/).safeParse(form.get('token'))
  if (!token.success) redirect('/login')
  await doUnsubscribe(token.data)
  redirect(`/u/${encodeURIComponent(token.data)}?done=1` as Route)
}
