/**
 * The public CSAT page's pure decisions (0081), for the page and the tests. The address is /u/csat/<token>?s=<1..5>&l=<no|en>,
 * from the five links in the email that resolves a ticket.
 */
export type CsatLang = 'en' | 'no'

export const tokenOk = (token: string) => /^[A-Za-z0-9_-]{32}$/.test(token)

/** the score in the address: a whole number 1–5, else none */
export function scoreOf(s: string | string[] | undefined): number | null {
  if (typeof s !== 'string' || !/^[1-5]$/.test(s)) return null
  return Number(s)
}

export const langOf = (l: string | string[] | undefined): CsatLang => (l === 'en' ? 'en' : 'no')

/**
 * A person's click opened the link: browsers send Sec-Fetch-User: ?1 only on a navigation the user started. A mail
 * scanner's fetch, a webview's programmatic load or a redirector does not, and gets the page with its button instead, so a
 * score is never recorded by a machine and never lost for a person.
 */
export const clicked = (h: { get(name: string): string | null }) => h.get('sec-fetch-user') === '?1'
