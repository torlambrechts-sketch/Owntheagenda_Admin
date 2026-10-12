/**
 * csat — the customer's one-click answer to «How satisfied are you with the help you got?» in the email that resolves their
 * ticket (0081).
 *
 * PUBLIC, and why: the customer has no account in Sentral and never will (rules 1–2 are for staff). The authority is the
 * single-use token in the link: 32 random characters whose SHA-256 alone is stored on the ticket, valid for 30 days, spent
 * by the first score. It opens nothing but that ticket's score: no ticket, name or text is read or shown.
 *
 *   GET ?t=<token>&s=<1..5>&l=<no|en>   records the score when a person's click opened the link (Sec-Fetch-User: ?1);
 *                                       a mail scanner's fetch records nothing and leaves the token for the person.
 *
 * Nothing but the score is accepted: no body, no comment, no other parameter is read. The answer is one line of plain text.
 * Logs carry the outcome only, never a token.
 */
import { createClient } from 'npm:@supabase/supabase-js@2'
import { decide, langOf, pageText } from '../_shared/csat.ts'

const text = (body: string, status = 200) => new Response(body, {
  status,
  headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store', 'x-robots-tag': 'noindex', 'referrer-policy': 'no-referrer' },
})
const log = (s: string) => console.log(`[csat] ${s}`)

Deno.serve(async (req) => {
  await req.body?.cancel()
  if (req.method === 'HEAD') return new Response(null, { status: 200 })
  const d = decide(req.method, req.url, req.headers)
  if ('answer' in d) {
    log(d.answer)
    return text(pageText(langOf(req.url), d.answer), d.answer === 'invalid' ? 400 : 200)
  }
  const svc = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', { auth: { persistSession: false } })
  const { data, error } = await svc.rpc('worker_csat_submit', { p_token: d.record.token, p_score: d.record.score })
  const r = (data ?? {}) as { ok?: boolean; code?: string }
  if (error || !r.ok) {
    log(error ? `refused ${error.code ?? ''}`.trim() : r.code ?? 'refused')
    return text(pageText(d.record.lang, 'used'), 410)
  }
  log('recorded')
  return text(pageText(d.record.lang, 'thanks', d.record.score))
})
