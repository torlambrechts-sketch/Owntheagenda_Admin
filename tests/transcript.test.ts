import { describe, expect, it } from 'vitest'
import {
  decodeText, docxXmlLines, formatFor, MAX_BYTES, MAX_TEXT, parseCues, parseLines, parseTranscript, toMs, type Segment,
} from '@/supabase/functions/_shared/transcript.ts'
import { crc32, unzipFile, zip, ZipError, zipNames } from '@/supabase/functions/_shared/zip.ts'
import { buildPackage, PACKAGE_FILE, PackageError, packagePath } from '@/supabase/functions/_shared/privacy-package.ts'

const enc = new TextEncoder()
const bytes = (s: string) => enc.encode(s)
const ok = async (b: Uint8Array, f: Parameters<typeof parseTranscript>[1]) => {
  const r = await parseTranscript(b, f)
  if (!r.ok) throw new Error(`expected segments, got ${r.reason}`)
  return r
}
const seg = (start_ms: number, end_ms: number | null, speaker: string | null, text: string): Segment => ({ start_ms, end_ms, speaker, text })

/** A minimal .docx: [Content_Types].xml and word/document.xml with these paragraphs (each an array of runs). */
async function docx(paragraphs: string[], extra = '') {
  const body = paragraphs.map((p) => `<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr>${p}</w:p>`).join('')
  const xml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body}${extra}<w:sectPr/></w:body></w:document>`
  return zip([
    { name: '[Content_Types].xml', data: bytes('<?xml version="1.0"?><Types/>') },
    { name: 'word/document.xml', data: bytes(xml) },
  ])
}
const run = (t: string) => `<w:r><w:t xml:space="preserve">${t}</w:t></w:r>`

describe('formats and limits', () => {
  it('maps the four upload types and nothing else', () => {
    expect(formatFor('text/vtt')).toBe('vtt')
    expect(formatFor('application/x-subrip')).toBe('srt')
    expect(formatFor('text/plain')).toBe('txt')
    expect(formatFor('application/vnd.openxmlformats-officedocument.wordprocessingml.document')).toBe('docx')
    expect(formatFor('application/pdf')).toBeNull()
  })

  it('reads times with and without hours, dots or commas, and refuses nonsense', () => {
    expect(toMs('01:02:03.450')).toBe(3_723_450)
    expect(toMs('02:03,4')).toBe(123_400)
    expect(toMs('2:03')).toBe(123_000)
    expect(toMs('00:61.000')).toBeNull()
    expect(toMs('1:61:00')).toBeNull()
    expect(toMs('abc')).toBeNull()
  })

  it('refuses an empty file, one over 5 MB and a binary file', async () => {
    expect(await parseTranscript(new Uint8Array(0), 'vtt')).toEqual({ ok: false, reason: 'empty' })
    expect(await parseTranscript(new Uint8Array(MAX_BYTES + 1), 'txt')).toEqual({ ok: false, reason: 'too_large' })
    expect(await parseTranscript(new Uint8Array([0x25, 0x50, 0x44, 0x46, 0, 1, 2, 3, 0, 0]), 'txt')).toEqual({ ok: false, reason: 'not_text' })
    expect(await parseTranscript(bytes('   \n\n'), 'txt')).toEqual({ ok: false, reason: 'empty' })
  })

  it('decodes a BOM, UTF-16 and Windows-1252', () => {
    expect(decodeText(new Uint8Array([0xef, 0xbb, 0xbf, ...bytes('Hei')]))).toBe('Hei')
    const u16 = new Uint8Array([0xff, 0xfe, 0x48, 0, 0xe6, 0]) // «Hæ» in UTF-16LE
    expect(decodeText(u16)).toBe('Hæ')
    expect(decodeText(new Uint8Array([0x42, 0xf8, 0x72]))).toBe('Bør') // Windows-1252, not UTF-8
  })
})

describe('WebVTT', () => {
  it('reads cues with identifiers, settings, voices, tags and entities, and skips NOTE and STYLE', async () => {
    const vtt = '﻿WEBVTT - a title\r\nKind: captions\r\n\r\nNOTE this is a comment\r\nwith --> nothing\r\n\r\nSTYLE\r\n::cue { color: red }\r\n\r\n'
      + 'intro-1\r\n00:00:01.000 --> 00:00:03.500 align:start position:10%\r\n<v Tor Lambrechts>Hei &amp; velkommen, <i>alle</i>.</v>\r\n\r\n'
      + '00:04.000 --> 00:06.000\r\n<v.loud Ingrid>Takk!\r\nGlad for å være her.\r\n\r\n'
      + '00:00:06.500 --> 00:00:08.000\r\n<v Tor>Først</v> <v Ingrid>Ja</v>\r\n\r\n'
      + '00:00:09.000 --> 00:00:10.000\r\n<c.yellow>Uten stemme</c> <00:00:09.500>her\r\n'
    const r = await ok(bytes(vtt), 'vtt')
    expect(r.timed).toBe(true)
    expect(r.segments).toEqual([
      seg(1000, 3500, 'Tor Lambrechts', 'Hei & velkommen, alle.'),
      seg(4000, 6000, 'Ingrid', 'Takk! Glad for å være her.'),
      seg(6500, 8000, 'Tor', 'Først'),
      seg(6500, 8000, 'Ingrid', 'Ja'),
      seg(9000, 10000, null, 'Uten stemme her'),
    ])
  })

  it('takes «Name: text» in a cue without a voice (Zoom), and keeps an end before its start out', async () => {
    const r = await ok(bytes('WEBVTT\n\n1\n00:00:00.000 --> 00:00:02.000\nTor Lambrechts: Hello there\n\n2\n00:00:05.000 --> 00:00:04.000\nKari: Backwards\n'), 'vtt')
    expect(r.segments).toEqual([seg(0, 2000, 'Tor Lambrechts', 'Hello there'), seg(5000, null, 'Kari', 'Backwards')])
  })

  it('skips a cue with a broken timing and fails a file with no cue at all', async () => {
    const r = await ok(bytes('WEBVTT\n\n00:00:99.000 --> 00:01:00.000\nbroken\n\n00:00:01.000 --> 00:00:02.000\nfine\n'), 'vtt')
    expect(r.segments).toEqual([seg(1000, 2000, null, 'fine')])
    expect(await parseTranscript(bytes('WEBVTT\n\nNOTE nothing here\n'), 'vtt')).toEqual({ ok: false, reason: 'no_segments' })
    expect(await parseTranscript(bytes('just some words'), 'vtt')).toEqual({ ok: false, reason: 'no_segments' })
  })
})

describe('SubRip', () => {
  it('reads numbered cues with CRLF, formatting tags, overrides, position settings and speakers', async () => {
    const srt = '1\r\n00:00:01,000 --> 00:00:02,500 X1:40 X2:600 Y1:20 Y2:50\r\n<i>Tor:</i> Hei,\r\n<b>alle sammen</b>\r\n\r\n'
      + '2\r\n00:00:03,000 --> 00:00:04,000\r\n{\\an8}[Ingrid] Takk\r\n\r\n'
      + '3\r\n00:00:05,000 --> 00:00:07,000\r\n- Tor: Ja?\r\n- Ingrid: Nei.\r\n'
    const r = await ok(bytes(srt), 'srt')
    expect(r.segments).toEqual([
      seg(1000, 2500, 'Tor', 'Hei, alle sammen'),
      seg(3000, 4000, 'Ingrid', 'Takk'),
      seg(5000, 7000, 'Tor', 'Ja?'),
      seg(5000, 7000, 'Ingrid', 'Nei.'),
    ])
  })

  it('reads cues without index lines or blank lines between them', () => {
    expect(parseCues(['00:00:01,000 --> 00:00:02,000', 'one', '2', '00:00:03,000 --> 00:00:04,000', 'two'])).toEqual([
      seg(1000, 2000, null, 'one'), seg(3000, 4000, null, 'two'),
    ])
  })
})

describe('plain text', () => {
  it('reads «Name: text» lines and joins a continuation to the line above', async () => {
    const r = await ok(bytes('Tor: Hei, alle.\r\nDette fortsetter.\r\n\r\nIngrid: Takk.\r\nNote without a speaker here\r\n\r\nEn linje uten navn.\r\n'), 'txt')
    expect(r.timed).toBe(false)
    expect(r.segments).toEqual([
      seg(0, null, 'Tor', 'Hei, alle. Dette fortsetter.'),
      seg(0, null, 'Ingrid', 'Takk. Note without a speaker here'),
      seg(0, null, null, 'En linje uten navn.'),
    ])
  })

  it('reads timed lines and «Name  0:03» headers (Teams, Otter); a sentence ending in a time is not a header', () => {
    const r = parseLines(['[00:00:05] Tor: Hei.', '00:01:10 - Ingrid Berg: Ja.', '', 'Kari Nordmann  1:15', 'Først dette.', 'Og så dette.', '',
      'Meet at 10:30', '[Ola] 1:40', 'Svar.'])
    expect(r.timed).toBe(true)
    expect(r.segments).toEqual([
      seg(5000, null, 'Tor', 'Hei.'),
      seg(70000, null, 'Ingrid Berg', 'Ja.'),
      seg(75000, null, 'Kari Nordmann', 'Først dette. Og så dette.'),
      seg(75000, null, 'Kari Nordmann', 'Meet at 10:30'),
      seg(100000, null, 'Ola', 'Svar.'),
    ])
  })

  it('does not take a URL or a long sentence for a speaker', () => {
    const r = parseLines(['See https://example.com for more', 'This is a much longer sentence than any name would be: and it goes on'])
    expect(r.segments).toEqual([seg(0, null, null, 'See https://example.com for more This is a much longer sentence than any name would be: and it goes on')])
  })

  it('reads a .txt that is really a subtitle file as one', async () => {
    const r = await ok(bytes('WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n<v Tor>Hei\n'), 'txt')
    expect(r.segments).toEqual([seg(1000, 2000, 'Tor', 'Hei')])
  })

  it('splits text over 4 000 characters at a space, keeping speaker and time', async () => {
    const long = Array.from({ length: 1200 }, (_, i) => `ord${i}`).join(' ')
    const r = await ok(bytes(`Tor: ${long}`), 'txt')
    expect(r.segments.length).toBeGreaterThanOrEqual(2)
    expect(r.segments.every((s) => s.text.length <= MAX_TEXT && s.speaker === 'Tor')).toBe(true)
    expect(r.segments.map((s) => s.text).join(' ')).toBe(long)
  })

  it('truncates a voice name to 120 characters and fails over 20 000 segments', async () => {
    const r = await ok(bytes(`WEBVTT\n\n00:01.000 --> 00:02.000\n<v ${'A'.repeat(200)}>hei\n`), 'vtt')
    expect(r.segments[0]!.speaker).toHaveLength(120)
    const many = Array.from({ length: 20_001 }, (_, i) => `S${i % 3}: linje ${i}\n`).join('\n')
    expect(await parseTranscript(bytes(many), 'txt')).toEqual({ ok: false, reason: 'too_many_segments' })
  })
})

describe('Word', () => {
  it('reads paragraphs: runs, tabs, line breaks and entities; deleted text and tab stops are ignored', async () => {
    expect(docxXmlLines(`<w:body><w:p>${run('Tor')}<w:r><w:tab/></w:r>${run('0:03')}</w:p><w:p>${run('Hei &amp; ')}<w:r><w:delText>borte</w:delText></w:r>${run('velkommen')}<w:r><w:br/></w:r>${run('Ny linje')}</w:p><w:p/></w:body>`))
      .toEqual(['Tor\t0:03', 'Hei & velkommen', 'Ny linje', ''])
    const file = await docx([`${run('Tor Lambrechts')}<w:r><w:tab/></w:r>${run('0:03')}`, run('Hei, alle.'), '', run('Ingrid: Takk for sist.'), run('Æ ø å — «sitat»')])
    const r = await ok(file, 'docx')
    expect(r.segments).toEqual([seg(3000, null, 'Tor Lambrechts', 'Hei, alle.'), seg(3000, null, 'Ingrid', 'Takk for sist. Æ ø å — «sitat»')])
  })

  it('reads a Teams Word export with timings, name lines and no blank paragraphs', async () => {
    const file = await docx([run('0:0:0.0 --> 0:0:3.520'), run('Tor Lambrechts'), run('Hei, alle sammen.'), run('0:0:4.0 --> 0:0:6.0'), run('Ingrid Berg'), run('Takk.')])
    const r = await ok(file, 'docx')
    expect(r.segments).toEqual([seg(0, 3520, 'Tor Lambrechts', 'Hei, alle sammen.'), seg(4000, 6000, 'Ingrid Berg', 'Takk.')])
  })

  it('fails what is not a Word document: not a ZIP, a ZIP without document.xml, a truncated ZIP, an empty document', async () => {
    expect(await parseTranscript(bytes('PK not really a zip'), 'docx')).toEqual({ ok: false, reason: 'docx_invalid' })
    expect(await parseTranscript(await zip([{ name: 'other.xml', data: bytes('<x/>') }]), 'docx')).toEqual({ ok: false, reason: 'docx_invalid' })
    const good = await docx([run('Tor: hei')])
    expect(await parseTranscript(good.slice(0, good.length - 30), 'docx')).toEqual({ ok: false, reason: 'docx_invalid' })
    expect(await parseTranscript(await docx(['']), 'docx')).toEqual({ ok: false, reason: 'empty' })
  })
})

describe('zip', () => {
  it('round-trips deflated and stored entries with UTF-8 names and checks the CRC', async () => {
    const big = bytes('{"a": 1}\n'.repeat(500))
    const tiny = bytes('x')
    const z = await zip([{ name: 'store/å.json', data: big }, { name: 'tiny.txt', data: tiny }], new Date('2026-10-07T12:00:00Z'))
    expect(zipNames(z)).toEqual(['store/å.json', 'tiny.txt'])
    expect(await unzipFile(z, 'store/å.json', 1e6)).toEqual(big)
    expect(await unzipFile(z, 'tiny.txt', 10)).toEqual(tiny)
    expect(z.length).toBeLessThan(big.length) // deflated
    await expect(unzipFile(z, 'nope', 10)).rejects.toEqual(new ZipError('missing'))
    await expect(unzipFile(z, 'store/å.json', 100)).rejects.toEqual(new ZipError('too_large'))
    // a flipped byte in the compressed data fails inflate or the CRC
    const bad = z.slice()
    bad[60] = bad[60]! ^ 0xff
    await expect(unzipFile(bad, 'store/å.json', 1e6)).rejects.toBeInstanceOf(ZipError)
    expect(crc32(bytes('123456789'))).toBe(0xcbf43926)
  })

  it('stops inflating past the limit even when the header lies about the size', async () => {
    const bomb = await zip([{ name: 'word/document.xml', data: new Uint8Array(3_000_000) }])
    // rewrite the declared uncompressed size (central directory) to something small
    const v = new DataView(bomb.buffer)
    const eocd = bomb.length - 22
    const cd = v.getUint32(eocd + 16, true)
    v.setUint32(cd + 24, 100, true)
    await expect(unzipFile(bomb, 'word/document.xml', 1000)).rejects.toEqual(new ZipError('too_large'))
  })
})

describe('privacy package', () => {
  const job = '7c1f4b5e-0000-4000-8000-000000000001'
  it('writes one JSON file per section and about.json under privacy/<job>/', async () => {
    expect(packagePath(job)).toBe(`privacy/${job}/${PACKAGE_FILE}`)
    expect(packagePath(job)).toMatch(/^privacy\/[0-9a-f-]{36}\/[A-Za-z0-9._-]{1,80}$/)
    const data = { people: [{ id: 'p1', name: 'Erik', email: 'erik@example.com' }], tickets: [], leads: [{ id: 'l1' }, { id: 'l2' }] }
    const z = await buildPackage(job, data, new Date('2026-10-07T12:00:00Z'))
    expect(zipNames(z)).toEqual(['about.json', 'leads.json', 'people.json', 'tickets.json'])
    const about = JSON.parse(new TextDecoder().decode(await unzipFile(z, 'about.json', 1e6)))
    expect(about).toEqual({ job, generated_at: '2026-10-07T12:00:00.000Z', format: 'json', sections: { leads: 2, people: 1, tickets: 0 } })
    expect(JSON.parse(new TextDecoder().decode(await unzipFile(z, 'people.json', 1e6)))).toEqual(data.people)
  })

  it('refuses a job id that is not a uuid, data that is not an object and an odd section name', async () => {
    expect(() => packagePath('../x')).toThrow(PackageError)
    await expect(buildPackage('nope', {})).rejects.toBeInstanceOf(PackageError)
    await expect(buildPackage(job, [])).rejects.toBeInstanceOf(PackageError)
    await expect(buildPackage(job, { '../evil': [] })).rejects.toBeInstanceOf(PackageError)
  })
})
