import { describe, expect, it } from 'vitest'
import { csatDelta, helpPathOk, parseAnswer, shares, snippetRuns, suggestedFor, ticketsDelta, componentTone, kindTone } from '../app/(admin)/customers/_components/support/logic'
import { parseCsat } from '../supabase/functions/_shared/csat'
import { csatLinks, ticketReply } from '../supabase/functions/_shared/mail-render'
import { inboundItems, inboundMail, inboundTally, threadHeaders } from '../supabase/functions/_shared/brevo-events'
import { clicked, langOf, scoreOf, tokenOk } from '../app/u/csat/[token]/logic'

const TOKEN = 'Abcdefghijklmnopqrstuvwxyz012-_9'

describe('support results', () => {
  it('a ticket delta needs a whole previous period with tickets; fewer is good', () => {
    expect(ticketsDelta(12, 0, true)).toBeNull()
    expect(ticketsDelta(12, 20, false)).toBeNull()
    expect(ticketsDelta(9, 10, true)).toEqual({ pct: -10, direction: 'fewer', good: true })
    expect(ticketsDelta(15, 10, true)).toEqual({ pct: 50, direction: 'more', good: false })
    expect(ticketsDelta(10, 10, true)).toEqual({ pct: 0, direction: 'same', good: true })
  })
  it('CSAT compares two averages, one decimal; none without both', () => {
    expect(csatDelta(4.7, null)).toBeNull()
    expect(csatDelta(null, 4.6)).toBeNull()
    expect(csatDelta(4.7, 4.6)).toEqual({ diff: 0.1, good: true })
    expect(csatDelta(4.2, 4.6)).toEqual({ diff: -0.4, good: false })
  })
  it('shares are whole percent of the total, none of nothing', () => {
    expect(shares([7, 2, 3, 0])).toEqual([58, 17, 25, 0])
    expect(shares([0, 0])).toEqual([null, null])
  })
})

describe('answer from published articles', () => {
  const titles = ['Invitasjoner kommer ikke frem', 'Slik legger du til verneombud']
  it('reads the answer and a source that names a published article', () => {
    const a = parseAnswer('Be IT godkjenne avsenderen.\nSend på nytt.\nSOURCE: Invitasjoner kommer ikke frem', titles)
    expect(a).toEqual({ kind: 'answer', text: 'Be IT godkjenne avsenderen.\nSend på nytt.', source: 'Invitasjoner kommer ikke frem' })
  })
  it('a source that is not a published article is not shown as one', () => {
    expect(parseAnswer('Svar.\nSOURCE: Noe Claude fant på', titles)).toEqual({ kind: 'answer', text: 'Svar.', source: null })
    expect(parseAnswer('Svar.\nKilde: «slik legger du til verneombud»', titles)).toEqual({ kind: 'answer', text: 'Svar.', source: 'Slik legger du til verneombud' })
  })
  it('NO_ARTICLE, or nothing, is no answer', () => {
    expect(parseAnswer('NO_ARTICLE', titles)).toEqual({ kind: 'none' })
    expect(parseAnswer('  ', titles)).toEqual({ kind: 'none' })
    expect(parseAnswer('NO_ARTICLE\nSOURCE: x', titles)).toEqual({ kind: 'none' })
  })
  it('search hits are marked by the database and split into runs', () => {
    expect(snippetRuns('Be IT godkjenne ⟦invitasjonen⟧ og ⟦send⟧ igjen')).toEqual([
      { text: 'Be IT godkjenne ', hit: false }, { text: 'invitasjonen', hit: true }, { text: ' og ', hit: false }, { text: 'send', hit: true }, { text: ' igjen', hit: false },
    ])
    expect(snippetRuns('ingen treff')).toEqual([{ text: 'ingen treff', hit: false }])
  })
})

describe('the widget preview', () => {
  it('an app page is a path, never a respondent page', () => {
    expect(helpPathOk('/malinger')).toBe(true)
    expect(helpPathOk('/oppsett/ansatte')).toBe(true)
    expect(helpPathOk('/s/abc123')).toBe(false)
    expect(helpPathOk('/s')).toBe(false)
    expect(helpPathOk('/sider')).toBe(true)
    expect(helpPathOk('https://x/malinger')).toBe(false)
    expect(helpPathOk('/malinger?token=1')).toBe(false)
  })
  it('suggests the newest three articles shown on the page', () => {
    const arts = [1, 2, 3, 4].map((n) => ({ id: `a${n}`, title: `T${n}`, app_pages: n === 2 ? ['/tiltak'] : ['/malinger'] }))
    expect(suggestedFor('/malinger', arts).map((a) => a.id)).toEqual(['a1', 'a3', 'a4'])
    expect(suggestedFor('/resultater', arts)).toEqual([])
  })
  it('tones follow the design', () => {
    expect([componentTone('operational'), componentTone('maintenance'), componentTone('degraded')]).toEqual(['bg-ok-bg', 'bg-teal-soft', 'bg-amber-bg'])
    expect([kindTone('new'), kindTone('improved'), kindTone('fixed')]).toEqual(['bg-ok-bg', 'bg-teal-soft', 'bg-highlight'])
  })
})

describe('CSAT (0081)', () => {
  const body = (o: unknown) => JSON.stringify(o)
  it('the function takes a peek or an answer by POST, a well-formed token and a score 1–5', () => {
    expect(parseCsat('POST', body({ action: 'peek', token: TOKEN }))).toEqual({ peek: TOKEN })
    expect(parseCsat('POST', body({ action: 'answer', token: TOKEN, score: 4 }))).toEqual({ answer: { token: TOKEN, score: 4 } })
  })
  it('nothing but a score and a token is accepted', () => {
    for (const b of [{ action: 'answer', token: TOKEN, score: 0 }, { action: 'answer', token: TOKEN, score: 6 }, { action: 'answer', token: TOKEN, score: 3.5 },
                     { action: 'answer', token: TOKEN, score: '3' }, { action: 'answer', token: TOKEN }, { action: 'peek', token: 'short' },
                     { action: 'peek', token: `${TOKEN}x` }, { action: 'delete', token: TOKEN }, { token: TOKEN }, [TOKEN]]) {
      expect(parseCsat('POST', body(b))).toEqual({ invalid: true })
    }
    expect(parseCsat('GET', body({ action: 'peek', token: TOKEN }))).toEqual({ invalid: true })
    expect(parseCsat('POST', 'not json')).toEqual({ invalid: true })
    expect(parseCsat('POST', body({ action: 'peek', token: TOKEN, pad: 'x'.repeat(1000) }))).toEqual({ invalid: true })
  })
  it('the page reads its address: a token, a score 1–5, the email\'s language', () => {
    expect(tokenOk(TOKEN)).toBe(true)
    expect(tokenOk('short')).toBe(false)
    expect([scoreOf('1'), scoreOf('5'), scoreOf('0'), scoreOf('6'), scoreOf('3.5'), scoreOf(undefined), scoreOf(['3'])]).toEqual([1, 5, null, null, null, null, null])
    expect([langOf('en'), langOf('no'), langOf('sv'), langOf(undefined)]).toEqual(['en', 'no', 'no', 'no'])
  })
  it('only a person\'s click records at once; a scanner, a webview or a redirector gets the button', () => {
    expect(clicked(new Headers({ 'sec-fetch-user': '?1' }))).toBe(true)
    expect(clicked(new Headers())).toBe(false)
    expect(clicked(new Headers({ 'sec-fetch-mode': 'navigate' }))).toBe(false)
  })
  it('the resolving reply carries five links to the public page, one per score, on the address the claim chose', () => {
    const links = csatLinks('https://post.orgpuls.no', TOKEN, 'no')!
    expect(links).toHaveLength(5)
    expect(links[0]).toBe(`https://post.orgpuls.no/u/csat/${TOKEN}?s=1&l=no`)
    expect(csatLinks('https://post.orgpuls.no', 'not-a-token', 'no')).toBeNull()
    expect(csatLinks(null, TOKEN, 'no')).toBeNull()
    expect(csatLinks('javascript:alert(1)', TOKEN, 'no')).toBeNull()
    expect(csatLinks('http://post.orgpuls.no', TOKEN, 'no')).toBeNull()
    const m = ticketReply({ lang: 'no', ref: 'T-9', subject: 's', body: 'Løst.', agent: 'Hanna', fromName: 'Orgpuls', csat: links })
    expect(m.text).toContain('Hvor fornøyd er du med hjelpen du fikk?')
    expect(m.text).toContain(`5: https://post.orgpuls.no/u/csat/${TOKEN}?s=5&l=no`)
    expect(m.html).toContain(`href="https://post.orgpuls.no/u/csat/${TOKEN}?s=3&amp;l=no"`)
    expect(`${m.html}${m.text}`).not.toContain('Sentral')
    const plain = ticketReply({ lang: 'no', ref: 'T-9', subject: 's', body: 'Løst.', agent: 'Hanna', fromName: 'Orgpuls' })
    expect(plain.text).not.toContain('fornøyd')
  })
})

describe('inbound mail outcome (0081)', () => {
  it('a database refusal is not dropped: the delivery is retried, with codes only', () => {
    const t = inboundTally([
      { data: { matched: true }, error: null }, { data: { matched: true, auto_reply: true }, error: null }, { data: { matched: false }, error: null },
      { data: null, error: { code: 'PGRST202' } }, { data: null, error: { code: '57014' } }, { data: null, error: { code: 'PGRST202' } },
    ])
    expect(t).toEqual({ matched: 1, auto_reply: 1, dropped: 1, failed: 3, codes: ['PGRST202', '57014'], retry: true })
  })
  it('an unmatched answer alone is acknowledged', () => {
    expect(inboundTally([{ data: { matched: false }, error: null }, { data: { matched: true, duplicate: true }, error: null }]))
      .toEqual({ matched: 1, auto_reply: 0, dropped: 1, failed: 0, codes: [], retry: false })
    expect(inboundTally([{ data: null, error: { code: null } }]).codes).toEqual(['unknown'])
  })
})

describe('inbound threading headers (0081, F-S2)', () => {
  const item = {
    Uuid: ['u-1'], InReplyTo: '<ref@smtp-relay.mailin.fr>', From: { Address: 'kunde@firma.no' }, Subject: 'Automatisk svar: [T-1] x', RawTextBody: 'Borte',
    Headers: { 'Auto-Submitted': 'auto-replied', 'X-Auto-Response-Suppress': ['All'], References: '<a@x> <ref@smtp-relay.mailin.fr>', 'Received': 'from somewhere', 'X-Spam': 'no' },
  }
  it('reads only the headers that decide threading, lower-cased', () => {
    expect(threadHeaders(item)).toEqual({
      'auto-submitted': 'auto-replied', 'x-auto-response-suppress': 'All', references: '<a@x> <ref@smtp-relay.mailin.fr>', 'in-reply-to': '<ref@smtp-relay.mailin.fr>',
    })
  })
  it('carries them with the item; the old reader keeps its shape', () => {
    expect(inboundMail({ items: [item] })[0]!.headers['auto-submitted']).toBe('auto-replied')
    expect(inboundItems({ items: [item] })).toEqual([{ id: 'u-1', from: 'kunde@firma.no', subject: 'Automatisk svar: [T-1] x', body: 'Borte' }])
  })
  it('no headers is an empty set', () => {
    expect(threadHeaders({})).toEqual({})
  })
})
