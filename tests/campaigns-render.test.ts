import { describe, expect, it } from 'vitest'
import { UNSUBSCRIBE, escapeHtml, footerProblems, renderEmail, safeHref, withUtm, type RenderInput } from '@/lib/data/campaigns-render'
import { BLANK_DESIGN, addRow, cleanDesign, fromQuery, moveRow, patchRow, removeRow, toQuery, type Cond, type Design } from '@/lib/data/campaigns-shared'

/** app.doc_html_unsafe (0032), the check campaign_schedule runs on the renderer's output. */
const unsafe = (html: string) => /<\s*\/?\s*(script|iframe|frame|object|embed|form|input|meta|link|base|style)\b|\son[a-z]+\s*=|javascript:|vbscript:|data:text\/html/i.test(html)
/** app.html_escape (0032). */
const pgEscape = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')

const design: Design = {
  rows: [
    { kind: 'header', bg: 'card', text: 'Nyhetsbrev · oktober' },
    { kind: 'title', text: 'Hei [Person.fornavn]', fs: 26 },
    { kind: 'paragraph', text: 'Første linje\nAndre linje' },
    { kind: 'image', src: 'https://cdn.example.no/bilde.png', alt: 'Resultater' },
    { kind: 'list', items: ['Kartlegg alle faktorer', 'Tiltak med eier og frist'] },
    { kind: 'button', text: 'Les sjekklisten →', href: 'https://orgpuls.com/sjekkliste' },
    { kind: 'divider' },
    { kind: 'social', items: [{ label: 'LinkedIn', href: 'https://www.linkedin.com/company/orgpuls' }, { label: 'Facebook' }] },
    { kind: 'footer', bg: 'cream' },
  ],
}
const base: RenderInput = {
  design,
  preheader: 'Det viktigste denne måneden',
  sender: { name: 'Orgpuls', postalAddress: 'Orgpuls AS, Postboks 1, 0101 Oslo' },
  brand: 'Orgpuls',
  utm: { source: 'newsletter', medium: 'email', campaign: 'okt-2026' },
}

describe('campaign email renderer (V-P6C-01)', () => {
  it('renders a table-based email with inline styles only, which the database accepts', () => {
    const html = renderEmail(base)
    expect(html.startsWith('<!DOCTYPE html>')).toBe(true)
    expect(html).toContain('<table role="presentation"')
    expect(html).toContain('max-width:600px')
    expect(unsafe(html)).toBe(false)
    expect(html).not.toMatch(/<style|class=/i)
  })

  it('always carries [Unsubscribe] and the sender\'s postal address (campaign_schedule\'s footer check)', () => {
    const html = renderEmail(base)
    expect(html).toContain(`href="${UNSUBSCRIBE}"`)
    expect(html).toContain(pgEscape(base.sender.postalAddress!))
    expect(footerProblems(html, base.sender.postalAddress)).toEqual([])
  })

  it('finds an address with characters app.html_escape changes', () => {
    const address = 'Bråten & Sønn AS, «Gata» 1, 0101 Oslo'
    const html = renderEmail({ ...base, sender: { name: 'B&S', postalAddress: address } })
    expect(html).toContain(pgEscape(address))
    expect(footerProblems(html, address)).toEqual([])
  })

  it('adds the footer when a design lacks one, and names what is missing when there is no address', () => {
    const html = renderEmail({ ...base, design: { rows: [{ kind: 'title', text: 'Hei' }] }, sender: { name: 'X', postalAddress: null } })
    expect(html).toContain(UNSUBSCRIBE)
    expect(footerProblems(html, null)).toEqual(['address'])
    expect(footerProblems('<p>Hei</p>', 'Gate 1')).toEqual(['unsubscribe', 'address'])
  })

  it('escapes every text, so a row cannot inject markup or an event attribute', () => {
    const html = renderEmail({
      ...base,
      design: {
        rows: [
          { kind: 'title', text: '<script>alert(1)</script>' },
          { kind: 'paragraph', text: '"><img src=x onerror=alert(1)>' },
          { kind: 'paragraph', text: 'Logg inn online = enkelt, javascript: nei' },
          { kind: 'button', text: '<b>Klikk</b>', href: 'javascript:alert(1)' },
          { kind: 'header', text: '<i>x</i>' },
          { kind: 'footer' },
        ],
      },
      sender: { name: '<Orgpuls>', postalAddress: 'Gate 1' },
      brand: '<Brand>',
      preheader: '<hidden>',
    })
    expect(html).not.toContain('<script')
    expect(html).not.toContain('<img src=x')
    expect(html).not.toContain('<b>Klikk')
    expect(html).not.toContain('<i>x')
    expect(html).not.toContain('<Orgpuls>')
    expect(html).toContain('&lt;script&gt;')
    expect(html).not.toContain('href="javascript:')
    // a text with «on… =» and «javascript:» is escaped too: the database's check must still pass
    expect(unsafe(html)).toBe(false)
  })

  it('keeps merge tokens for app.merge_render and turns line breaks into <br>', () => {
    const html = renderEmail(base)
    expect(html).toContain('Hei [Person.fornavn]')
    expect(html).toContain('Første linje<br>Andre linje')
  })

  it('appends the UTM to http(s) links only, keeping existing parameters and fragments', () => {
    const html = renderEmail(base)
    expect(html).toContain('href="https://orgpuls.com/sjekkliste?utm_source=newsletter&utm_medium=email&utm_campaign=okt-2026"')
    expect(withUtm('https://x.no/a?b=1#top', base.utm)).toBe('https://x.no/a?b=1&utm_source=newsletter&utm_medium=email&utm_campaign=okt-2026#top')
    expect(withUtm('https://x.no/?utm_source=own', base.utm)).toBe('https://x.no/?utm_source=own&utm_medium=email&utm_campaign=okt-2026')
    expect(withUtm('mailto:hei@x.no', base.utm)).toBe('mailto:hei@x.no')
    expect(html).not.toContain('[Unsubscribe]?utm')
  })

  it('accepts only http(s), mailto and merge-token links', () => {
    expect(safeHref('https://a.no')).toBe('https://a.no')
    expect(safeHref('mailto:a@b.no')).toBe('mailto:a@b.no')
    expect(safeHref('[Person.nettside]')).toBe('[Person.nettside]')
    expect(safeHref('javascript:alert(1)')).toBeNull()
    expect(safeHref('https://a.no/" onclick="x')).toBeNull()
    expect(safeHref('')).toBeNull()
  })

  it('leaves out empty rows and images without an https source', () => {
    const html = renderEmail({ ...base, design: { rows: [{ kind: 'title', text: '' }, { kind: 'image' }, { kind: 'image', src: 'http://x.no/a.png' }, { kind: 'button', text: '' }, { kind: 'footer' }] } })
    expect(html).not.toContain('<h1')
    expect(html).not.toContain('<img')
  })

  it('uses the background, padding and border of each row', () => {
    const html = renderEmail({ ...base, design: { rows: [{ kind: 'paragraph', text: 'x', bg: 'mint', padding: 32, border: 'hairline' }, { kind: 'footer', bg: 'soft_yellow' }] } })
    expect(html).toContain('padding:26px 32px;background:#CFE7E4;border-top:1px solid #E8DFC9')
    expect(html).toContain('background:#FBEBBE;font-family')
  })

  it('wraps hand-written HTML as written, inside the same shell', () => {
    const own = '<table><tr><td>Hei</td></tr><tr><td>Gate 1 · <a href="[Unsubscribe]">Av</a></td></tr></table>'
    const html = renderEmail({ ...base, design: null, html: own })
    expect(html).toContain(own)
    expect(footerProblems(html, 'Gate 1')).toEqual([])
  })

  it('hides the preheader and prints the footer in the chosen language', () => {
    expect(renderEmail(base)).toContain('display:none;max-height:0')
    expect(renderEmail(base)).toContain('Meld deg av med ett klikk')
    expect(renderEmail({ ...base, lang: 'en' })).toContain('Unsubscribe with one click')
    expect(renderEmail({ ...base, lang: 'nn' })).toContain('Meld deg av med eitt klikk')
    expect(renderEmail({ ...base, lang: 'sv' })).toContain('Avsluta prenumerationen med ett klick')
    expect(renderEmail({ ...base, lang: 'sv' })).toContain('<html lang="sv">')
    expect(unsafe(renderEmail({ ...base, lang: 'nn' }))).toBe(false)
  })

  it('escapes like app.html_escape', () => {
    expect(escapeHtml(`<a href="x">'&'</a>`)).toBe(pgEscape(`<a href="x">'&'</a>`))
  })
})

describe('design helpers', () => {
  it('inserts new rows above the fixed footer, which never moves or goes away', () => {
    const a = addRow(BLANK_DESIGN, 'title')
    expect(a.design.rows.map((r) => r.kind)).toEqual(['header', 'title', 'footer'])
    expect(a.index).toBe(1)
    expect(moveRow(a.design, 1, 1).design).toBe(a.design)
    expect(moveRow(a.design, 2, -1).design).toBe(a.design)
    expect(moveRow(a.design, 1, -1).design.rows.map((r) => r.kind)).toEqual(['title', 'header', 'footer'])
    expect(removeRow(a.design, 2).design).toBe(a.design)
    expect(removeRow(a.design, 1).design.rows.map((r) => r.kind)).toEqual(['header', 'footer'])
  })
  it('lets only the footer\'s background change', () => {
    const d = patchRow(BLANK_DESIGN, 1, { bg: 'mint', text: 'Annet' } as never)
    expect(d.rows[1]).toEqual({ kind: 'footer', bg: 'mint' })
  })
  it('stores a design without empty optional values', () => {
    expect(cleanDesign({ rows: [{ kind: 'button', text: 'Ja', href: '' }, { kind: 'footer', bg: 'cream', text: 'x' }] })).toEqual({
      rows: [{ kind: 'button', text: 'Ja' }, { kind: 'footer', bg: 'cream' }],
    })
  })
})

describe('segment conditions', () => {
  const conds: Cond[] = [
    { join: 'and', f: 'title', op: 'eq', v: 'HR' },
    { join: 'and', f: 'organization.employees', op: 'between', v: '26', v2: '100' },
    { join: 'and', f: 'organization.status', op: 'eq', v: 'trial' },
    { join: 'and', f: 'engagement.opened_days', op: 'lte', v: '90' },
    { join: 'or', f: 'fylke', op: 'in', v: 'Vestland, Rogaland' },
  ]
  const query = {
    filters: [
      { f: 'title', op: 'eq', v: 'HR' },
      { f: 'organization.employees', op: 'gte', v: 26 },
      { f: 'organization.employees', op: 'lte', v: 100 },
      { f: 'organization.status', op: 'eq', v: 'trial' },
      { or: [[{ f: 'engagement.opened_days', op: 'lte', v: 90 }], [{ f: 'fylke', op: 'in', v: ['Vestland', 'Rogaland'] }]] },
    ],
  }
  it('turns the Where / AND / OR list into the people filter, OR joining a condition to the one above', () => {
    expect(toQuery(conds)).toEqual(query)
  })
  it('reads the filter back into the same list', () => {
    expect(fromQuery(query)).toEqual(conds.map((c) => (c.op === 'in' ? { ...c, v: 'Vestland, Rogaland' } : c)))
  })
  it('leaves half-typed conditions out of the query', () => {
    expect(toQuery([{ join: 'and', f: 'organization.employees', op: 'between', v: '26', v2: '' }, { join: 'and', f: 'title', op: 'eq', v: ' ' }])).toEqual({ filters: [] })
  })
  it('keeps product activity (days since the last survey round), «never» included, as the seed stores it', () => {
    const pulse = { filters: [{ f: 'organization.status', op: 'eq', v: 'active' },
      { or: [[{ f: 'product.last_round_days', op: 'gte', v: 90 }], [{ f: 'product.last_round_days', op: 'empty' }]] }] }
    const back = fromQuery(pulse)
    expect(back).toEqual([
      { join: 'and', f: 'organization.status', op: 'eq', v: 'active' },
      { join: 'and', f: 'product.last_round_days', op: 'gte', v: '90' },
      { join: 'or', f: 'product.last_round_days', op: 'empty', v: '' },
    ])
    expect(toQuery(back!)).toEqual(pulse)
  })
  it('refuses a filter the editor cannot show', () => {
    expect(fromQuery({ filters: [{ f: 'owner_id', op: 'eq', v: 'x' }] })).toBeNull()
    expect(fromQuery({})).toEqual([])
  })
})
