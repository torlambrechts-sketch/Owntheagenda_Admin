'use server'

import type { Route } from 'next'
import { redirect } from 'next/navigation'
import { z } from 'zod'
import { answerCsat } from './csat'

const Form = z.object({
  token: z.string().regex(/^[A-Za-z0-9_-]{32}$/),
  score: z.coerce.number().int().min(1).max(5),
  lang: z.enum(['no', 'en']),
})

/** The page's button: record the score, then the page again saying what happened (thanks, used, or try again). */
export async function answer(form: FormData): Promise<void> {
  const p = Form.safeParse({ token: form.get('token'), score: form.get('score'), lang: form.get('lang') })
  // a malformed form gets the page's «link not complete» (a link host serves /u only, so never the sign-in)
  if (!p.success) redirect('/u/csat/-' as Route)
  const { token, score, lang } = p.data
  const r = await answerCsat(token, score)
  const to = `/u/csat/${encodeURIComponent(token)}?s=${score}&l=${lang}${r === 'recorded' ? '&r=thanks' : r === 'unavailable' ? '&r=retry' : ''}`
  redirect(to as Route)
}
