import { describe, expect, it } from 'vitest'
import { csatDelta, helpPathOk, parseAnswer, shares, snippetRuns, suggestedFor, ticketsDelta, componentTone, kindTone } from '../app/(admin)/customers/_components/support/logic'
import { decide, pageText } from '../supabase/functions/_shared/csat'
import { csatLinks, ticketReply } from '../supabase/functions/_shared/mail-render'
import { inboundItems, inboundMail, threadHeaders } from '../supabase/functions/_shared/brevo-events'

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
  const h = (o: Record<string, string> = {}) => new Headers(o)
  it('a person\'s click records a score 1–5 with a well-formed token', () => {
    expect(decide('GET', `https://x/functions/v1/csat?t=${TOKEN}&s=4&l=en`, h({ 'sec-fetch-user': '?1' }))).toEqual({ record: { token: TOKEN, score: 4, lang: 'en' } })
    expect(decide('GET', `https://x/functions/v1/csat?t=${TOKEN}&s=5`, h({ 'sec-fetch-user': '?1' }))).toEqual({ record: { token: TOKEN, score: 5, lang: 'no' } })
  })
  it('a mail scanner\'s fetch records nothing and leaves the token', () => {
    expect(decide('GET', `https://x/functions/v1/csat?t=${TOKEN}&s=1`, h())).toEqual({ answer: 'browser' })
    expect(decide('GET', `https://x/functions/v1/csat?t=${TOKEN}&s=1`, h({ 'sec-fetch-mode': 'navigate' }))).toEqual({ answer: 'browser' })
  })
  it('nothing but a score and a token is accepted', () => {
    for (const q of [`t=${TOKEN}&s=0`, `t=${TOKEN}&s=6`, `t=${TOKEN}&s=3.5`, `t=${TOKEN}`, `t=short&s=3`, `t=${TOKEN}x&s=3`, 's=3']) {
      expect(decide('GET', `https://x/functions/v1/csat?${q}`, h({ 'sec-fetch-user': '?1' }))).toEqual({ answer: 'invalid' })
    }
    expect(decide('POST', `https://x/functions/v1/csat?t=${TOKEN}&s=3`, h({ 'sec-fetch-user': '?1' }))).toEqual({ answer: 'invalid' })
  })
  it('the answer is one line in the email\'s language', () => {
    expect(pageText('no', 'thanks', 4)).toBe('Takk. Svaret ditt, 4 av 5, er registrert.')
    expect(pageText('en', 'used')).toBe('This link has already been used or is no longer valid.')
  })
  it('the resolving reply carries five links to the csat function, one per score', () => {
    const links = csatLinks('https://zuvqbaejoktpekfsiyyr.supabase.co', TOKEN, 'no')!
    expect(links).toHaveLength(5)
    expect(links[0]).toBe(`https://zuvqbaejoktpekfsiyyr.supabase.co/functions/v1/csat?t=${TOKEN}&s=1&l=no`)
    expect(csatLinks('https://x.example', 'not-a-token', 'no')).toBeNull()
    expect(csatLinks('javascript:alert(1)', TOKEN, 'no')).toBeNull()
    const m = ticketReply({ lang: 'no', ref: 'T-9', subject: 's', body: 'Løst.', agent: 'Hanna', fromName: 'Orgpuls', csat: links })
    expect(m.text).toContain('Hvor fornøyd er du med hjelpen du fikk?')
    expect(m.text).toContain(`5: https://zuvqbaejoktpekfsiyyr.supabase.co/functions/v1/csat?t=${TOKEN}&s=5&l=no`)
    expect(m.html).toContain(`href="https://zuvqbaejoktpekfsiyyr.supabase.co/functions/v1/csat?t=${TOKEN}&amp;s=3&amp;l=no"`)
    expect(`${m.html}${m.text}`).not.toContain('Sentral')
    const plain = ticketReply({ lang: 'no', ref: 'T-9', subject: 's', body: 'Løst.', agent: 'Hanna', fromName: 'Orgpuls' })
    expect(plain.text).not.toContain('fornøyd')
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
