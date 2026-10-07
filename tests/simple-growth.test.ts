import { describe, expect, it } from 'vitest'
import {
  AD_UTM, Overview, SimpleModel, daysFrom, firstBlocker, growthHref, moveStep, openRate, parseAmount, seqState, slug, trackingUrl,
} from '@/lib/data/simple-growth-shared'

describe('Growth › Marketing campaigns', () => {
  it('slugs a name the way app.slug does', () => {
    expect(slug('Lovkrav — Q4')).toBe('lovkrav-q4')
    expect(slug('Verneombud på kurs i Ålesund')).toBe('verneombud-pa-kurs-i-alesund')
    expect(slug('Ærlig talt: ØKT  salg!')).toBe('aerlig-talt-okt-salg')
    expect(slug('—')).toBe('')
  })

  it('builds the tracking link from the site, the landing path and the utm', () => {
    expect(trackingUrl('orgpuls.com', '/lovkrav', { source: 'google-ads', medium: 'cpc', campaign: 'lovkrav-q4' }))
      .toBe('https://orgpuls.com/lovkrav?utm_source=google-ads&utm_medium=cpc&utm_campaign=lovkrav-q4')
    expect(trackingUrl('orgpuls.com', 'pris', { source: 'a', medium: 'b', campaign: 'c' })).toBe('https://orgpuls.com/pris?utm_source=a&utm_medium=b&utm_campaign=c')
    expect(trackingUrl(null, '/', { source: 'a', medium: 'b', campaign: 'c' })).toBeNull()
  })

  it('gives each channel the medium channel_rules maps to its source (app.ad_utm)', () => {
    expect(AD_UTM.google_ads).toEqual({ source: 'google-ads', medium: 'cpc', spend: 'paid_search' })
    expect(AD_UTM.linkedin.medium).toBe('paid_social')
    expect(AD_UTM.newsletter.spend).toBe('email')
    expect(AD_UTM.webinar.spend).toBeNull()
  })

  it('reads an amount in the staff member’s number format', () => {
    expect(parseAmount('10 000', 'space_comma')).toBe(10000)
    expect(parseAmount('12 400,50', 'space_comma')).toBe(12400.5)
    expect(parseAmount('12,400.5', 'comma_dot')).toBe(12400.5)
    expect(parseAmount('12.400', 'dot_comma')).toBe(12400)
    expect(parseAmount('', 'space_comma')).toBeNull()
    expect(parseAmount('ti tusen', 'space_comma')).toBeNaN()
  })
})

describe('Growth › Email and automation', () => {
  it('reads a wait back as days', () => {
    expect(daysFrom('Wait 2 days')).toBe(2)
    expect(daysFrom('Vent 14 dager')).toBe(14)
    expect(daysFrom('Wait a while')).toBeNull()
    expect(daysFrom('Wait 0 days')).toBeNull()
    expect(daysFrom('Wait 400 days')).toBeNull()
  })

  it('moves a step and leaves the ends alone', () => {
    expect(moveStep(['a', 'b', 'c'], 2, -1)).toEqual(['a', 'c', 'b'])
    expect(moveStep(['a', 'b', 'c'], 0, -1)).toEqual(['a', 'b', 'c'])
    expect(moveStep(['a', 'b', 'c'], 2, 1)).toEqual(['a', 'b', 'c'])
  })

  it('names a draft that once ran «paused»', () => {
    expect(seqState({ state: 'active', activated: true })).toBe('active')
    expect(seqState({ state: 'draft', activated: true })).toBe('paused')
    expect(seqState({ state: 'draft', activated: false })).toBe('draft')
  })

  it('explains the provider first among the blockers', () => {
    expect(firstBlocker(['campaign_inactive', 'not_connected:email', 'sender_domain_unverified'])).toBe('not_connected:email')
    expect(firstBlocker(['campaign_inactive', 'mailbox_not_connected'])).toBe('campaign_inactive')
    expect(firstBlocker([])).toBeNull()
  })

  it('has no open rate until something tracked was delivered', () => {
    const stats = (delivered: number, opens: number | null) => ({ sent: delivered, delivered, unique_opens: opens, unique_clicks: null, open_rate: null })
    expect(openRate([])).toBeNull()
    expect(openRate([{ campaign_id: crypto.randomUUID(), status: 'draft', stats: null }])).toBeNull()
    expect(openRate([{ campaign_id: crypto.randomUUID(), status: 'active', stats: stats(10, null) }])).toBeNull()
    expect(openRate([{ campaign_id: crypto.randomUUID(), status: 'active', stats: stats(10, 6) }, { campaign_id: crypto.randomUUID(), status: 'active', stats: stats(30, 6) }])).toBe(30)
  })

  it('parses the editor’s model and refuses an unknown step', () => {
    expect(SimpleModel.safeParse({ trigger: 'form_submitted', list: null, exit: 'never', steps: [{ kind: 'wait', days: 2 }] }).success).toBe(true)
    expect(SimpleModel.safeParse({ trigger: 'form_submitted', exit: 'never', steps: [{ kind: 'sms', text: 'Hei' }] }).success).toBe(false)
  })
})

describe('Growth › the address', () => {
  it('leaves the defaults out and keeps the range on the tabs that have it', () => {
    expect(growthHref('analytics', '30d')).toBe('/growth')
    expect(growthHref('analytics', '7d')).toBe('/growth?range=7d')
    expect(growthHref('seo', '90d')).toBe('/growth?tab=seo&range=90d')
    expect(growthHref('campaigns', '90d')).toBe('/growth?tab=campaigns')
  })

  it('parses an overview with the tracker silent: nulls, not zeros', () => {
    const r = Overview.safeParse({
      days: 7, site: null, tracked: false,
      kpis: { visitors: null, visitors_prev: null, signups: 2, signups_prev: 1, trial_conversion: null, spend: null, spend_excluded_currency: 0, spend_from: '2026-09-01', paying_new: 0 },
      daily: [{ day: '2026-10-07', signups: 2, visitors: null }],
      funnel: [{ key: 'visited', count: null }, { key: 'account_created', count: 2 }],
      sources: [{ channel: 'direct', visits: null, signups: 2 }],
      pages: [],
    })
    expect(r.success).toBe(true)
  })
})
