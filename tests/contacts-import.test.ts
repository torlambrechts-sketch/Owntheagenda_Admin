import { describe, expect, it } from 'vitest'
import { detectDelimiter, parseCsv, parseNumber, suggestMapping } from '@/lib/data/contacts-import'
import { csvCell, neutralise, toCsv } from '@/lib/data/contacts-export'

describe('parseCsv (RFC 4180)', () => {
  it('reads headers and rows with CRLF and LF', () => {
    expect(parseCsv('Navn,E-post\r\nKari,kari@lumio.no\nOla,ola@x.no\n')).toEqual({
      headers: ['Navn', 'E-post'],
      rows: [['Kari', 'kari@lumio.no'], ['Ola', 'ola@x.no']],
    })
  })
  it('keeps delimiters, line breaks and doubled quotes inside quotes', () => {
    const r = parseCsv('a,b\n"x, y","line\nbreak ""q"""\n')
    expect(r.rows).toEqual([['x, y', 'line\nbreak "q"']])
  })
  it('drops a byte-order mark and blank records, pads short records', () => {
    const r = parseCsv('﻿a,b,c\n\n1,2\n,,\n')
    expect(r.headers).toEqual(['a', 'b', 'c'])
    expect(r.rows).toEqual([['1', '2', '']])
  })
  it('detects the semicolon Excel writes in a Norwegian locale', () => {
    expect(detectDelimiter('Navn;Firma;"a,b"\n')).toBe(';')
    expect(parseCsv('Navn;Firma\nKari;Lumio AS').rows).toEqual([['Kari', 'Lumio AS']])
  })
  it('handles a last record without a line break and empty quoted fields', () => {
    expect(parseCsv('a,b\n"",2').rows).toEqual([['', '2']])
  })
})

describe('suggestMapping', () => {
  it('matches plain column names in bokmål and English, each target once', () => {
    expect(suggestMapping('person', ['Navn', 'E-post', 'Mobil', 'Firma', 'Orgnr', 'Stilling', 'Notat fra stand', 'Email'], [])).toEqual(
      ['name', 'email', 'phone', 'org_name', 'org_nr', 'title', null, null],
    )
  })
  it('maps an organization file and custom fields by label', () => {
    expect(suggestMapping('organization', ['Firma', 'Orgnr', 'Antall ansatte', 'Segment'], [{ key: 'segment', label: 'Segment', type: 'text' }])).toEqual(
      ['name', 'org_number', 'employees', 'custom.segment'],
    )
  })
})

describe('numbers and CSV output', () => {
  it('reads Norwegian and English numbers, leaves anything else as text', () => {
    expect(parseNumber('12 345,50')).toBe(12345.5)
    expect(parseNumber('64000 kr')).toBe(64000)
    expect(parseNumber('about 10')).toBe('about 10')
  })
  it('neutralises cells that a spreadsheet would run as a formula', () => {
    expect(neutralise('=SUM(A1)')).toBe("'=SUM(A1)")
    expect(neutralise('+47 900')).toBe("'+47 900")
    expect(neutralise('−5')).toBe("'−5")
    expect(neutralise('@x')).toBe("'@x")
    expect(neutralise('Kari')).toBe('Kari')
  })
  it('quotes cells with delimiters, quotes and line breaks', () => {
    expect(csvCell('a "b", c')).toBe('"a ""b"", c"')
    expect(toCsv(['h'], [['x'], [null]])).toBe('h\r\nx\r\n\r\n')
  })
})
