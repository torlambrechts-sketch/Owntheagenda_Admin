import { describe, expect, it } from 'vitest'
import { GOOGLE_KEYWORDS, GOOGLE_KEYWORD_DAYS, googleImport, googleKeywords } from '../supabase/functions/_shared/ads'
import {
  CampaignDetail, SHOWN_ROWS, SendTimes, SequenceResults, adRows, barMode, campaignTips, dailyBars, emailRows, emailTips, endedBeforeWindow, heatGrid,
  hourText, platformUrl, rowCps, windowDays, windowOff, windowText, type CampaignDetail as Detail, type SequenceResults as Results, type SendTimes as Times,
} from '../lib/growth/v3'

const day = (i: number) => `2026-10-${String(i).padStart(2, '0')}`
function detail(over: Partial<Detail> = {}): Detail {
  return {
    id: '00000000-0000-4000-8000-000000000001', from: day(1), to: day(4), days_n: 4, starts_on: null, ends_on: null, tracked: true,
    spend_source: 'platform', currency: 'NOK', time_zones: [], utm_content: false, utm_term: true,
    platforms: [{ provider: 'google_ads', account: '5550001111', campaign: '901', name: 'Search', status: 'live', bidding: 'manual_cpc' }],
    days: [{ day: day(1), spend: 100, signups: 2 }, { day: day(2), spend: 50, signups: 1 }, { day: day(3), spend: null, signups: 0 }, { day: day(4), spend: 0, signups: 0 }],
    ads: [], keywords: [], ...over,
  }
}
const kw = (id: string, name: string, clicks: number, spend: number, signups: number | null) => ({
  id, ad_group: '77', provider: 'google_ads' as const, account: '5550001111', campaign: '901', name, status: 'live' as const, currency: 'NOK',
  clicks, spend, conversions: null, signups, match_type: 'exact' as const,
})
const ad = (id: string, name: string, clicks: number, spend: number, signups: number | null, provider: 'google_ads' | 'linkedin_ads' | 'meta_ads' = 'linkedin_ads') => ({
  id, provider, account: '508000111', campaign: '42', name, status: 'live' as const, currency: 'NOK', clicks, spend, conversions: null, signups,
})

describe('Growth v3: the campaign card (0083)', () => {
  it('parses what ad_campaign_detail returns', () => {
    expect(CampaignDetail.safeParse(detail({ keywords: [kw('1', 'vaktplan', 10, 5, null)], ads: [ad('9', 'Video', 3, 1, 0)] })).success).toBe(true)
    expect(CampaignDetail.safeParse({ ...detail(), spend_source: 'guessed' }).success).toBe(false)
  })
  it('draws spend as the design does: max × 96 % + 2 %, signups inside as a share of the busiest day', () => {
    const b = dailyBars(detail())
    expect(b[0]).toMatchObject({ empty: false, h: 98, sh: 100, spend: 100 })
    expect(b[1]).toMatchObject({ h: 50, sh: 50 })
    expect(b[2]).toMatchObject({ empty: true, spend: null })       // no platform row and no signups: an empty slot
    expect(b[3]).toMatchObject({ empty: false, h: 2, spend: 0 })   // a zero day is a stub
  })
  it('draws nothing before the campaign started', () => {
    const b = dailyBars(detail({ starts_on: day(2) }))
    expect(b[0]!.empty).toBe(true)
    expect(b[1]).toMatchObject({ h: 98, sh: 100 })
  })
  it('draws nothing after the campaign ended, unless something was recorded that day', () => {
    // typed spend and no signups: the days after the end are empty slots, not 2 % stubs (Årsplan, ended before the window)
    const typed = (ends: string) => detail({ spend_source: 'typed', starts_on: '2026-01-03', ends_on: ends,
      days: [1, 2, 3, 4].map((i) => ({ day: day(i), spend: null, signups: 0 })) })
    const gone = dailyBars(typed('2026-02-20'))
    expect(gone.every((b) => b.empty)).toBe(true)
    expect(endedBeforeWindow(typed('2026-02-20'), gone)).toBe(true)
    // ended inside the window: the days it ran are stubs, the days after are empty
    const half = dailyBars(typed(day(2)))
    expect(half.map((b) => b.empty)).toEqual([false, false, true, true])
    expect(half[0]).toMatchObject({ h: 2, sh: 0 })
    expect(endedBeforeWindow(typed(day(2)), half)).toBe(false)
    // a platform day with spend after the end date still shows (the platform campaign ran on), and so do signups
    const ran = dailyBars(detail({ ends_on: day(1) }))
    expect(ran.map((b) => b.empty)).toEqual([false, false, true, false])
    const late = detail({ spend_source: 'typed', ends_on: day(1), days: [{ day: day(1), spend: null, signups: 0 }, { day: day(2), spend: null, signups: 3 }] })
    expect(dailyBars(late).map((b) => [b.empty, b.sh])).toEqual([[false, 0], [false, 100]])
    expect(endedBeforeWindow(detail({ ends_on: '2026-09-30' }), dailyBars(detail({ ends_on: '2026-09-30' })))).toBe(false)
  })
  it('never spreads typed spend over days: the signups stand alone, and with none every day is the design\'s stub', () => {
    const typed = detail({ spend_source: 'typed', days: [{ day: day(1), spend: null, signups: 1 }, { day: day(2), spend: null, signups: 2 }] })
    expect(barMode(typed)).toBe('signups')
    expect(dailyBars(typed).map((x) => [x.h, x.sh, x.spend])).toEqual([[null, 50, null], [null, 100, null]])
    const none = detail({ spend_source: null, days: [{ day: day(1), spend: null, signups: 0 }] })
    expect(dailyBars(none)[0]).toMatchObject({ h: 2, sh: 0, empty: false })
    expect(barMode(detail({ currency: null }))).toBe('signups')     // several currencies are never added up
  })
  it('a row\'s cost per signup is its own spend over its own signups, or nothing', () => {
    expect(rowCps({ spend: 300, signups: 3 })).toBe(100)
    expect(rowCps({ spend: 300, signups: 0 })).toBeNull()
    expect(rowCps({ spend: 300, signups: null })).toBeNull()
    expect(rowCps({ spend: 0, signups: 2 })).toBeNull()
  })
  it('lists keywords before ads, at most six of each', () => {
    const rows = adRows(detail({ keywords: Array.from({ length: 8 }, (_, i) => kw(String(i), `k${i}`, 10, 1, 0)), ads: [ad('9', 'A', 1, 1, null)] }))
    expect(rows.map((r) => r.kind)).toEqual([...Array(6).fill('keyword'), 'ad'])
  })
  it('links each tip to where the change is made in the platform', () => {
    expect(platformUrl('google_ads', '5550001111', '901', 'keyword')).toBe('https://ads.google.com/aw/keywords?campaignId=901&__e=5550001111')
    expect(platformUrl('google_ads', '5550001111', '901', 'ad')).toBe('https://ads.google.com/aw/ads?campaignId=901&__e=5550001111')
    expect(platformUrl('linkedin_ads', '508000111', '42', 'ad')).toBe('https://www.linkedin.com/campaignmanager/accounts/508000111/campaigns/42/creatives')
    expect(platformUrl('meta_ads', '987', '211', 'ad')).toBe('https://adsmanager.facebook.com/adsmanager/manage/ads?act=987&selected_campaign_ids=211')
  })
  it('a keyword three times dearer per signup than the rest is a tip with its own ratio; one that converts best is another (manual bidding)', () => {
    const d = detail({ keywords: [kw('1', 'lovkrav', 820, 2100, 21), kw('2', 'medarbeider', 1140, 2700, 18), kw('3', 'hms system', 610, 1600, 4), kw('4', 'gratis', 370, 600, 19)] })
    const tips = campaignTips(d)
    expect(tips).toHaveLength(2)
    expect(tips[0]).toMatchObject({ kind: 'dear', level: 'keyword', name: 'hms system', cps: 400 })
    const first = tips[0]!
    expect(first.kind === 'dear' && first.ratio !== null && first.ratio > 3).toBe(true)
    expect(tips[0]!.url).toContain('ads.google.com/aw/keywords')
    expect(tips[1]).toMatchObject({ kind: 'best', name: 'gratis' })
  })
  it('no bid tip where Google sets the bids, and none below the click minimum', () => {
    const smart = detail({ platforms: [{ ...detail().platforms[0]!, bidding: 'maximize_conversions' }],
      keywords: [kw('1', 'a', 500, 1000, 10), kw('2', 'b', 500, 3000, 3), kw('4', 'c', 200, 100, 5)] })
    expect(campaignTips(smart).some((t) => t.kind === 'best')).toBe(false)
    const few = detail({ keywords: [kw('1', 'a', 40, 1000, 0), kw('2', 'b', 500, 100, 5)] })
    expect(campaignTips(few)).toEqual([])
  })
  it('a row with clicks and no signups after spending more than a signup costs elsewhere is a tip without a ratio', () => {
    const tips = campaignTips(detail({ keywords: [], ads: [ad('1', 'Daglig leder, construction', 520, 1300, 0), ad('2', 'Video', 310, 400, 4)] }))
    expect(tips).toEqual([expect.objectContaining({ kind: 'dear', level: 'ad', name: 'Daglig leder, construction', ratio: null, restCps: 100 })])
    expect(tips[0]!.url).toContain('linkedin.com/campaignmanager')
  })
  it('a tip rests on the rows the card shows: never a seventh keyword, and «the rest» is the rest of the list', () => {
    const shown = Array.from({ length: SHOWN_ROWS }, (_, i) => kw(String(i), `k${i}`, 300, 1000, 10))  // 100 kr per signup each
    const hidden = kw('7', 'skjult', 200, 5000, 1)                                                      // 5 000 kr per signup, not shown
    const d = detail({ keywords: [...shown, hidden] })
    expect(adRows(d).some((r) => r.name === 'skjult')).toBe(false)
    expect(campaignTips(d).some((t) => t.name === 'skjult')).toBe(false)
    // a shown dear keyword is compared with the other five shown, not with the hidden one
    const dear = kw('0', 'dyr', 300, 3000, 5)
    const tips = campaignTips(detail({ keywords: [dear, ...shown.slice(1), hidden] }))
    expect(tips[0]).toMatchObject({ kind: 'dear', name: 'dyr', restCps: 100, ratio: 6 })
  })
  it('without signups per row (no utm_term / utm_content), or in another currency, there is no tip', () => {
    expect(campaignTips(detail({ keywords: [kw('1', 'a', 900, 9000, null), kw('2', 'b', 900, 100, null)] }))).toEqual([])
    expect(campaignTips(detail({ currency: null, keywords: [kw('1', 'a', 900, 9000, 1), kw('2', 'b', 900, 100, 5)] }))).toEqual([])
    const sek = { ...kw('1', 'a', 900, 9000, 1), currency: 'SEK' }
    expect(campaignTips(detail({ keywords: [sek, kw('2', 'b', 900, 100, 5)] }))).toEqual([])
  })
})

const results = (over: Partial<Results> = {}): Results => ({
  id: '00000000-0000-4000-8000-000000000002', days: 30, send_window: null,
  emails: [
    { step: 0, campaign_id: '00000000-0000-4000-8000-000000000003', subject: 'Velkommen',
      figures: { tracking: true, sent: 252, delivered: 250, opens: 150, clicks: 45, unsubscribed: 1, with_org: 200, past_employees: 10, signups: 14 } },
    { step: 3, campaign_id: '00000000-0000-4000-8000-000000000004', subject: 'Last opp',
      figures: { tracking: true, sent: 222, delivered: 200, opens: 80, clicks: 18, unsubscribed: 2, with_org: 160, past_employees: 64, signups: 6 } },
  ],
  ...over,
})
const steps = [{ kind: 'email' }, { kind: 'wait' }, { kind: 'cond', cond: 'not_paying' }, { kind: 'email' }]
const times = (over: Partial<Times> = {}): Times => ({
  days: 90, min: 20,
  cells: [{ dow: 2, hour: 8, delivered: 100, opened: 54 }, { dow: 3, hour: 8, delivered: 40, opened: 16 }, { dow: 1, hour: 13, delivered: 10, opened: 9 },
    { dow: 4, hour: 12, delivered: 30, opened: 6 }, { dow: 5, hour: 18, delivered: 25, opened: 5 }],
  best: { dow: 2, hour: 8, delivered: 100, opened: 54, days: [2, 3] },
  ...over,
})

describe('Growth v3: Email and automation (0083)', () => {
  it('parses what the reads return', () => {
    expect(SequenceResults.safeParse(results()).success).toBe(true)
    expect(SendTimes.safeParse(times()).success).toBe(true)
    expect(SendTimes.safeParse({ ...times(), cells: [{ dow: 8, hour: 8, delivered: 1, opened: 0 }] }).success).toBe(false)
  })
  it('a row\'s rates are over delivered, red under 45 % open and 10 % click', () => {
    const [a, b] = emailRows(results())
    expect(a).toMatchObject({ sent: 252, open: 60, click: 18, unsub: 0.4, signups: 14, openLow: false, clickLow: false })
    expect(b).toMatchObject({ open: 40, click: 9, openLow: true, clickLow: true })
  })
  it('an email that sent nothing shows 0 and «—», never a rate; another person\'s email shows nothing', () => {
    const r = emailRows(results({ emails: [
      { step: 0, campaign_id: null, subject: 'Draft', figures: { tracking: true, sent: 0, delivered: 0, opens: 0, clicks: 0, unsubscribed: 0, with_org: 0, past_employees: 0, signups: 0 } },
      { step: 2, campaign_id: null, subject: 'Theirs', figures: null },
    ] }))
    expect(r[0]).toMatchObject({ sent: 0, open: null, click: null, unsub: null, signups: null })
    expect(r[1]).toMatchObject({ sent: null, open: null, signups: null })
  })
  it('opens are not a rate when the email does not track them', () => {
    const r = emailRows(results({ emails: [{ ...results().emails[0]!, figures: { ...results().emails[0]!.figures!, tracking: false, opens: null, clicks: null } }] }))
    expect(r[0]).toMatchObject({ open: null, click: null })
  })
  it('the three tips follow their rules on the sequence\'s own figures', () => {
    const tips = emailTips(results(), steps, times().best)
    expect(tips).toEqual([
      { kind: 'ab', email: 2, rate: 9 },
      { kind: 'cond', email: 2, step: 3, share: 40 },
      { kind: 'time', days: [2, 3], hour: 8 },
    ])
  })
  it('no condition tip when the employee condition is already there; no time tip with a window or without a best time', () => {
    const guarded = [{ kind: 'email' }, { kind: 'cond', cond: 'employees_missing' }, { kind: 'wait' }, { kind: 'email' }]
    expect(emailTips(results(), guarded, times().best).some((t) => t.kind === 'cond')).toBe(false)
    expect(emailTips(results({ send_window: { days: [2], hour: 8, set_at: '2026-10-12T08:00:00Z' } }), steps, times().best).some((t) => t.kind === 'time')).toBe(false)
    expect(emailTips(results(), steps, null).some((t) => t.kind === 'time')).toBe(false)
  })
  it('an email tip needs 20 delivered', () => {
    const thin = results({ emails: [{ ...results().emails[1]!, step: 0, figures: { ...results().emails[1]!.figures!, delivered: 19, with_org: 19 } }] })
    expect(emailTips(thin, steps, null)).toEqual([])
  })
  it('the heatmap bands each cell against the best; a thin cell has no rate and no fill', () => {
    const g = heatGrid(times())
    const cell = (dow: number, hour: number) => g.rows.find((r) => r.dow === dow)!.cells.find((c) => c.hour === hour)!
    expect(cell(2, 8)).toMatchObject({ band: 'high', best: true, rate: 54 })
    expect(cell(3, 8)).toMatchObject({ band: 'midhigh', best: false, rate: 40 })
    expect(cell(4, 12)).toMatchObject({ band: 'low', rate: 20 })
    expect(cell(1, 13)).toMatchObject({ band: 'none', rate: null, delivered: 10 })
    expect(cell(6, 8)).toMatchObject({ band: 'none', delivered: 0 })
    expect(g.rows).toHaveLength(7)
    expect(g.rows[0]!.cells.map((c) => c.hour)).toEqual([6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20])
    expect(g.outside).toBe(25)
  })
  it('without a best time no cell is marked best', () => {
    expect(heatGrid(times({ best: null })).rows.flatMap((r) => r.cells).some((c) => c.best)).toBe(false)
  })
  it('the best-time button says why it is off, and only what is known: unread send times are not «no time has 20»', () => {
    const base = { editable: true, hasEmail: true, on: false, times: times() }
    expect(windowOff(base)).toBeNull()
    expect(windowOff({ ...base, times: null })).toBe('unread')
    expect(windowOff({ ...base, times: times({ best: null }) })).toBe('notYet')
    expect(windowOff({ ...base, editable: false, times: null })).toBe('readOnly')
    expect(windowOff({ ...base, hasEmail: false })).toBe('noEmail')
    expect(windowOff({ ...base, on: true, times: null })).toBeNull()   // a window that is on can always be switched off
  })
  it('writes the window as the design does', () => {
    const name = (d: number) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]!
    expect(windowText([2, 3, 4], 8, name)).toBe('Tue–Thu 08:00')
    expect(windowText([1, 3], 8, name)).toBe('Mon, Wed 08:00')
    expect(windowDays([5, 1, 2, 3], name)).toBe('Mon–Wed, Fri')
    expect(windowDays([2, 3], name)).toBe('Tue, Wed')
    expect(hourText(20)).toBe('20:00')
  })
})

describe('Growth v3: Google Ads keywords, read only (ads-run)', () => {
  it('asks for keywords and their days, never the search terms', () => {
    expect(GOOGLE_KEYWORDS).toContain('FROM ad_group_criterion')
    expect(GOOGLE_KEYWORDS).toContain("ad_group_criterion.type = 'KEYWORD'")
    expect(GOOGLE_KEYWORDS).toContain('ad_group_criterion.negative = FALSE')
    expect(GOOGLE_KEYWORD_DAYS).toContain('FROM keyword_view')
    expect(`${GOOGLE_KEYWORDS} ${GOOGLE_KEYWORD_DAYS}`).not.toMatch(/search_term/)
  })
  it('reduces Google\'s rows to keywords and days; cost in micros becomes kroner', () => {
    const r = googleKeywords(
      [{ campaign: { id: '111' }, adGroup: { id: '77' }, adGroupCriterion: { criterionId: '501', keyword: { text: ' lovkrav arbeidsmiljø ', matchType: 'PHRASE' }, status: 'ENABLED' } },
        { campaign: { id: '111' }, adGroup: { id: '77' }, adGroupCriterion: { criterionId: '502', keyword: { text: 'x', matchType: 'UNKNOWN' }, status: 'PAUSED' } },
        { campaign: { id: '111' }, adGroup: { id: '77' }, adGroupCriterion: { criterionId: 'bad', keyword: { text: 'y' } } }],
      [{ adGroup: { id: '77' }, adGroupCriterion: { criterionId: '501' }, segments: { date: '2026-10-01' }, metrics: { impressions: '300', clicks: '27', costMicros: '229500000', conversions: 1.5 } },
        { adGroup: { id: '77' }, adGroupCriterion: { criterionId: '501' }, segments: { date: 'yesterday' }, metrics: {} }])
    expect(r.keywords).toEqual([
      { id: '501', ad_group: '77', campaign: '111', text: 'lovkrav arbeidsmiljø', match_type: 'phrase', status: 'live' },
      { id: '502', ad_group: '77', campaign: '111', text: 'x', match_type: null, status: 'paused' },
    ])
    expect(r.daily).toEqual([{ id: '501', ad_group: '77', day: '2026-10-01', impressions: 300, clicks: 27, spend: 229.5, conversions: 1.5 }])
  })
  it('an import carries keywords and the bidding strategy, and a refused keyword query leaves the rest imported', async () => {
    const f = (async (_url: RequestInfo | URL, init?: RequestInit) => {
      const q = JSON.parse(String(init?.body)).query as string
      if (q.startsWith('SELECT campaign.id, campaign.name')) return new Response(JSON.stringify({ results: [{ campaign: { id: '111', name: 'Lovkrav', status: 'ENABLED', biddingStrategyType: 'MANUAL_CPC' } }] }))
      if (q.includes('FROM keyword_view')) return new Response('{}', { status: 403 })
      if (q.includes('FROM ad_group_criterion')) return new Response(JSON.stringify({ results: [{ campaign: { id: '111' }, adGroup: { id: '77' }, adGroupCriterion: { criterionId: '501', keyword: { text: 'a', matchType: 'EXACT' }, status: 'ENABLED' } }] }))
      return new Response(JSON.stringify({ results: [] }))
    }) as typeof fetch
    const r = await googleImport({ token: 't', developerToken: 'dev-token-1234567890', loginCustomerId: null }, '1234567890', '2026-10-01', '2026-10-01', f)
    if (!r.ok) throw new Error(r.code)
    expect(r.campaigns).toHaveLength(1)
    expect(r.bidding).toEqual([{ id: '111', bidding: 'manual_cpc' }])
    expect(r.keywords).toBeNull()
    expect(r.keywordDaily).toBeNull()
  })
})
