/**
 * PageSpeed Insights (0073), reduced to Core Web Vitals: what pagespeed-run asks Google and what it keeps of the answer.
 * Pure, so the edge function (Deno) and the tests (Node) run the same code. Real users' readings (the Chrome UX Report
 * Google attaches for a page with enough traffic) win over the lab run; a reading for the whole origin is not the page's
 * and is not used for it. Nothing of the page's content is kept.
 */

export type Vitals = { lcp_ms: number | null; inp_ms: number | null; cls: number | null; score: number | null; field: boolean }

export const PSI = 'https://www.googleapis.com/pagespeedonline/v5/runPagespeed'

export function psiUrl(pageUrl: string, key: string, strategy: 'mobile' | 'desktop' = 'mobile'): string {
  const u = new URL(PSI)
  u.searchParams.set('url', pageUrl)
  u.searchParams.set('strategy', strategy)
  u.searchParams.set('category', 'performance')
  u.searchParams.set('key', key)
  return u.toString()
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const ms = (v: unknown): number | null => { const n = num(v); return n === null ? null : Math.max(0, Math.round(n)) }

/** what a PageSpeed answer says about the page: field data when Google has it for this page, else the lab run */
export function vitalsOf(body: unknown): Vitals | null {
  if (!body || typeof body !== 'object') return null
  const b = body as {
    loadingExperience?: { origin_fallback?: boolean; metrics?: Record<string, { percentile?: unknown }> }
    lighthouseResult?: { audits?: Record<string, { numericValue?: unknown }>; categories?: { performance?: { score?: unknown } } }
  }
  const audits = b.lighthouseResult?.audits ?? {}
  const scoreRaw = num(b.lighthouseResult?.categories?.performance?.score)
  const lab = {
    lcp_ms: ms(audits['largest-contentful-paint']?.numericValue),
    cls: num(audits['cumulative-layout-shift']?.numericValue),
  }
  const fieldOk = !!b.loadingExperience?.metrics && !b.loadingExperience.origin_fallback
  const m = fieldOk ? b.loadingExperience!.metrics! : {}
  const fLcp = ms(m.LARGEST_CONTENTFUL_PAINT_MS?.percentile)
  const fInp = ms(m.INTERACTION_TO_NEXT_PAINT?.percentile)
  // CrUX reports CLS × 100 as an integer
  const fClsRaw = num(m.CUMULATIVE_LAYOUT_SHIFT_SCORE?.percentile)
  const fCls = fClsRaw === null ? null : Math.round(fClsRaw) / 100
  const field = fieldOk && (fLcp !== null || fInp !== null || fCls !== null)
  const out: Vitals = {
    lcp_ms: field && fLcp !== null ? fLcp : lab.lcp_ms,
    inp_ms: field ? fInp : null,
    cls: field && fCls !== null ? fCls : lab.cls === null ? null : Math.round(lab.cls * 1000) / 1000,
    score: scoreRaw === null ? null : Math.round(scoreRaw * 100),
    field,
  }
  return out.lcp_ms === null && out.cls === null && out.score === null ? null : out
}

/** a refusal as a short code: a bad key is not the page's fault */
export function refusalOf(status: number, body: unknown): string {
  const reason = (body as { error?: { errors?: Array<{ reason?: unknown }>; status?: unknown } } | null)?.error
  const r = typeof reason?.errors?.[0]?.reason === 'string' ? (reason.errors[0].reason as string) : typeof reason?.status === 'string' ? (reason.status as string) : ''
  if (/keyInvalid|API_KEY_INVALID|PERMISSION_DENIED|accessNotConfigured/i.test(r) || status === 403) return 'key_refused'
  if (status === 429) return 'quota'
  return `http_${status}`
}
