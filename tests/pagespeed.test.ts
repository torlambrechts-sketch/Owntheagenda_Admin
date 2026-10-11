import { describe, expect, it } from 'vitest'
import { psiUrl, refusalOf, vitalsOf } from '../supabase/functions/_shared/pagespeed'

const lab = { lighthouseResult: { audits: { 'largest-contentful-paint': { numericValue: 2412.6 }, 'cumulative-layout-shift': { numericValue: 0.0431 } }, categories: { performance: { score: 0.87 } } } }

describe('pagespeed (0073)', () => {
  it('asks for the page, mobile, performance only, with the key', () => {
    const u = new URL(psiUrl('https://www.orgpuls.com/pris', 'AIzaTEST', 'mobile'))
    expect(u.searchParams.get('url')).toBe('https://www.orgpuls.com/pris')
    expect(u.searchParams.get('strategy')).toBe('mobile')
    expect(u.searchParams.get('category')).toBe('performance')
    expect(u.searchParams.get('key')).toBe('AIzaTEST')
  })

  it('reads the lab run when Google has no real-user data for the page', () => {
    expect(vitalsOf(lab)).toEqual({ lcp_ms: 2413, inp_ms: null, cls: 0.043, score: 87, field: false })
  })

  it('prefers real users for the page, never the origin\'s', () => {
    const field = { ...lab, loadingExperience: { metrics: { LARGEST_CONTENTFUL_PAINT_MS: { percentile: 2100 }, INTERACTION_TO_NEXT_PAINT: { percentile: 180 }, CUMULATIVE_LAYOUT_SHIFT_SCORE: { percentile: 5 } } } }
    expect(vitalsOf(field)).toEqual({ lcp_ms: 2100, inp_ms: 180, cls: 0.05, score: 87, field: true })
    expect(vitalsOf({ ...field, loadingExperience: { ...field.loadingExperience, origin_fallback: true } })).toEqual({ lcp_ms: 2413, inp_ms: null, cls: 0.043, score: 87, field: false })
  })

  it('says nothing for an empty answer, and names a refused key', () => {
    expect(vitalsOf({})).toBeNull()
    expect(vitalsOf(null)).toBeNull()
    expect(refusalOf(400, { error: { errors: [{ reason: 'keyInvalid' }] } })).toBe('key_refused')
    expect(refusalOf(403, {})).toBe('key_refused')
    expect(refusalOf(429, {})).toBe('quota')
    expect(refusalOf(500, {})).toBe('http_500')
  })
})
