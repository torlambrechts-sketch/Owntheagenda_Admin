/**
 * The csat function's decisions (0081), pure so the tests (Node) run the same code. The five links in a resolution email
 * open the public page /u/csat/<token> (app/u/csat), on the application's link address or Sentral's. Opening the page
 * changes nothing; the page asks here, by POST, whether the token is still open and, when the person sends the score,
 * records it. A request carries a single-use token and, to answer, a score 1–5: nothing else is read.
 */
export type CsatAction = { peek: string } | { answer: { token: string; score: number } } | { invalid: true }

export const CSAT_TOKEN = /^[A-Za-z0-9_-]{32}$/

export function parseCsat(method: string, raw: string): CsatAction {
  if (method !== 'POST' || raw.length > 1_000) return { invalid: true }
  let body: unknown
  try {
    body = JSON.parse(raw)
  } catch {
    return { invalid: true }
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return { invalid: true }
  const { action, token, score } = body as Record<string, unknown>
  if (typeof token !== 'string' || !CSAT_TOKEN.test(token)) return { invalid: true }
  if (action === 'peek') return { peek: token }
  if (action === 'answer' && typeof score === 'number' && Number.isInteger(score) && score >= 1 && score <= 5) return { answer: { token, score } }
  return { invalid: true }
}
