/**
 * The csat function's decisions (0081), pure so the tests (Node) run the same code. A request carries a single-use token, a
 * score 1–5 and the email's language, and nothing else is read. A score is recorded only when a person's click opened the
 * link (Sec-Fetch-User: ?1, sent by browsers on a user-activated navigation): mail scanners that fetch every link in an
 * email (and would spend the token on the first score they meet) send no such header. Answers are plain text: Supabase
 * serves a GET answer of text/html as text/plain.
 */
import { MAIL_TEXTS } from './mail-texts.gen.ts'

export type CsatLang = 'en' | 'no'
export type CsatRequest = { token: string; score: number; lang: CsatLang }
export type CsatDecision = { record: CsatRequest } | { answer: 'invalid' | 'browser' }

const TOKEN = /^[A-Za-z0-9_-]{32}$/

/** what to do with a request: record it, or say why not (the token is never echoed) */
export function decide(method: string, url: string, headers: Headers): CsatDecision {
  const p = new URL(url).searchParams
  const token = p.get('t') ?? ''
  const score = Number(p.get('s'))
  const lang: CsatLang = p.get('l') === 'en' ? 'en' : 'no'
  if (method !== 'GET' || !TOKEN.test(token) || !Number.isInteger(score) || score < 1 || score > 5) return { answer: 'invalid' }
  if (headers.get('sec-fetch-user') !== '?1') return { answer: 'browser' }
  return { record: { token, score, lang } }
}

export function langOf(url: string): CsatLang {
  return new URL(url).searchParams.get('l') === 'en' ? 'en' : 'no'
}

/** the page's one line, in the email's language */
export function pageText(lang: CsatLang, outcome: 'thanks' | 'used' | 'browser' | 'invalid', score?: number): string {
  const t = MAIL_TEXTS[lang].csat.page
  return outcome === 'thanks' ? t.thanks.replace('{score}', String(score ?? '')) : t[outcome]
}
