/**
 * The transcript upload reader (MTG-06): an uploaded .vtt, .srt, .txt or .docx becomes segments
 * {start_ms, end_ms, speaker, text} for worker_upload_parsed (0042), or a reason code for worker_upload_failed (0054).
 * Web APIs only, so the jobs-run edge function (Deno) and the tests (Node) run the same code.
 *
 *   .vtt   cues (an identifier line, cue settings, NOTE/STYLE/REGION blocks are skipped), <v Speaker> voice tags (one segment
 *          per voice), other tags stripped, entities decoded; a cue without a voice may begin «Name: text».
 *   .srt   numbered cues, «hh:mm:ss,mmm --> …» (with or without the index line or position settings), formatting tags and
 *          {\an8} overrides stripped; «Name: text» or «[Name] text» name the speaker.
 *   .txt   «Name: text» lines, «[00:01:23] Name: text» timed lines, «Name  0:03» header lines (Teams, Otter) whose text follows;
 *          a line without a name continues the line above it; a .txt that is really a subtitle file is read as one.
 *   .docx  the paragraphs of word/document.xml (w:t runs, w:tab, w:br; deleted text ignored), read as a .txt.
 *
 * Tolerated everywhere: a byte-order mark, CRLF or CR line ends, UTF-16 with its BOM, and legacy Windows-1252 text that is
 * not UTF-8. A format without timings stores start 0 and no end (the schema requires a start); `timed` says which.
 * The schema's limits are kept here: at most 20 000 segments, 4 000 characters of text each (longer text is split at a
 * space), a speaker label of 120 characters, times under 1e9 ms. Failure reasons are codes, never the file's words.
 */
import { unzipFile, ZipError } from './zip.ts'

export type Segment = { start_ms: number; end_ms: number | null; speaker: string | null; text: string }
export type TranscriptFormat = 'vtt' | 'srt' | 'txt' | 'docx'
export const PARSE_FAILURES = ['empty', 'too_large', 'not_text', 'docx_invalid', 'no_segments', 'too_many_segments'] as const
export type ParseFailure = (typeof PARSE_FAILURES)[number]
export type ParseResult = { ok: true; segments: Segment[]; timed: boolean } | { ok: false; reason: ParseFailure }

/** The bucket's own limit (meeting-files, 0052) and the schema's (mtg_segments_store, transcript_segments). */
export const MAX_BYTES = 5_242_880
export const MAX_SEGMENTS = 20_000
export const MAX_TEXT = 4_000
export const MAX_SPEAKER = 120
const MAX_MS = 999_999_999
const MAX_DOCUMENT_XML = 40 * 1024 * 1024

const FORMATS: Record<string, TranscriptFormat> = {
  'text/vtt': 'vtt', 'application/x-subrip': 'srt', 'text/plain': 'txt',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
}

/** The reader for an upload's type (the types meeting_transcript_upload_begin accepts), or null. */
export function formatFor(mime: string): TranscriptFormat | null {
  return FORMATS[mime] ?? null
}

// ---------------------------------------------------------------------------
// text

/** Bytes to text: a BOM decides UTF-16; else strict UTF-8; else Windows-1252. Null when it is not text at all. */
export function decodeText(bytes: Uint8Array): string | null {
  let text: string
  if (bytes[0] === 0xff && bytes[1] === 0xfe) text = new TextDecoder('utf-16le').decode(bytes.subarray(2))
  else if (bytes[0] === 0xfe && bytes[1] === 0xff) text = new TextDecoder('utf-16be').decode(bytes.subarray(2))
  else {
    try {
      text = new TextDecoder('utf-8', { fatal: true }).decode(bytes)
    } catch {
      try {
        text = new TextDecoder('windows-1252').decode(bytes)
      } catch {
        text = Array.from(bytes, (b) => String.fromCharCode(b)).join('')
      }
    }
  }
  text = text.replace(/^\uFEFF/, '')
  // a NUL or a run of control characters is a binary file, not a transcript
  if (/[\u0000-\u0008\u000E-\u001F]/.test(text.slice(0, 4096))) return null
  return text
}

const lines = (text: string) => text.replace(/\r\n?/g, '\n').split('\n')

const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', lrm: '', rlm: '' }
export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]{1,6}|#\d{1,7}|[a-z]{2,6});/gi, (m, e: string) => {
    if (e[0] === '#') {
      const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)
      return n > 0 && n <= 0x10ffff && !(n >= 0xd800 && n <= 0xdfff) ? String.fromCodePoint(n) : ''
    }
    return ENTITIES[e.toLowerCase()] ?? m
  })
}

const squash = (s: string) => s.replace(/\s+/g, ' ').trim()

// ---------------------------------------------------------------------------
// times and speakers

// seconds may be one digit: Teams' Word export writes «0:0:3.520»
const TIME = String.raw`(?:\d{1,3}:)?\d{1,2}:\d{1,2}(?:[.,]\d{1,3})?`
const CUE = new RegExp(String.raw`^\s*(${TIME})\s*-->\s*(${TIME})(?:\s.*)?$`)

/** «01:02:03.450», «02:03,4», «2:03» → milliseconds, or null. */
export function toMs(t: string): number | null {
  const m = /^(?:(\d{1,3}):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?$/.exec(t.trim())
  if (!m) return null
  const h = m[1] ? Number(m[1]) : 0
  const min = Number(m[2])
  const s = Number(m[3])
  if (s > 59 || (m[1] !== undefined && min > 59)) return null
  const ms = h * 3_600_000 + min * 60_000 + s * 1000 + (m[4] ? Number(m[4].padEnd(3, '0')) : 0)
  return ms <= MAX_MS ? ms : null
}

// a name: starts with a letter, at most 60 name-like characters and six words
const NAME = String.raw`\p{L}[\p{L}\p{M}\d .'’\-()&]{0,59}?`
const SPEAKER_LINE = new RegExp(String.raw`^(${NAME})\s*:\s+(\S.*)$`, 'u')
const BRACKET_LINE = new RegExp(String.raw`^\[(${NAME})\]\s*:?\s*(\S.*)$`, 'u')
const TIMED_SPEAKER = new RegExp(String.raw`^\[?(${TIME})\]?\s*[-–]?\s*(${NAME})\s*:\s+(\S.*)$`, 'u')
const TIMED_TEXT = new RegExp(String.raw`^\[(${TIME})\]\s*(\S.*)$`, 'u')
// «Name  0:03» (two spaces or a tab: «We meet at 10:30» is a sentence, not a header) or «[Name] 10:02:15»
const HEADER = new RegExp(String.raw`^(?:(${NAME})\s{2,}|\[(${NAME})\]\s*)\[?(${TIME})\]?$`, 'u')
const NAME_ONLY = new RegExp(String.raw`^(${NAME})$`, 'u')

const nameOk = (n: string) => n.trim().split(/\s+/).length <= 6 && !/^\d/.test(n)

function speakerOf(line: string): { speaker: string; text: string } | null {
  const m = SPEAKER_LINE.exec(line) ?? BRACKET_LINE.exec(line)
  return m && nameOk(m[1]!) ? { speaker: m[1]!.trim(), text: m[2]! } : null
}

// ---------------------------------------------------------------------------
// segments out: the schema's limits

function finish(raw: Segment[], timed: boolean): ParseResult {
  const out: Segment[] = []
  for (const s of raw) {
    let text = squash(s.text)
    if (!text) continue
    const speaker = s.speaker ? squash(s.speaker).slice(0, MAX_SPEAKER) || null : null
    const end = s.end_ms !== null && s.end_ms >= s.start_ms ? s.end_ms : null
    while (text.length > MAX_TEXT) {
      let cut = text.lastIndexOf(' ', MAX_TEXT)
      if (cut < MAX_TEXT / 2) cut = MAX_TEXT
      out.push({ start_ms: s.start_ms, end_ms: end, speaker, text: text.slice(0, cut).trim() })
      text = text.slice(cut).trim()
    }
    if (text) out.push({ start_ms: s.start_ms, end_ms: end, speaker, text })
    if (out.length > MAX_SEGMENTS) return { ok: false, reason: 'too_many_segments' }
  }
  if (out.length === 0) return { ok: false, reason: 'no_segments' }
  return { ok: true, segments: out, timed }
}

// ---------------------------------------------------------------------------
// cues: WebVTT and SubRip (and a .txt or .docx that holds them)

const TAG = /<\/?(?:c|i|b|u|lang|ruby|rt|font|span|v)(?:[.\s][^>]*)?>|<\d{1,3}:\d{2}(?::\d{2})?(?:[.,]\d{1,3})?>/gi
const OVERRIDE = /\{\\[^}]*\}/g
const VOICE = /<v(?:\.[^\s>]*)?(?:\s+([^>]*))?>/gi
const clean = (s: string) => decodeEntities(s.replace(OVERRIDE, '').replace(TAG, ''))

/** One cue's payload lines → segments: one per voice; untagged lines named «Name: text» start a segment of their own. */
function cueSegments(start: number, end: number | null, payload: string[], nameLines: boolean): Segment[] {
  const joined = payload.join('\n')
  const out: Segment[] = []
  if (/<v[\s.>]/i.test(joined)) {
    const parts = joined.split(VOICE)
    // split with a capture group: [before, name1, text1, name2, text2, …]
    const before = clean(parts[0] ?? '')
    if (squash(before)) out.push({ start_ms: start, end_ms: end, speaker: null, text: before })
    for (let i = 1; i < parts.length; i += 2) {
      const name = parts[i] ? decodeEntities(parts[i]!).trim() : null
      out.push({ start_ms: start, end_ms: end, speaker: name || null, text: clean(parts[i + 1] ?? '') })
    }
    return out
  }
  const rows = payload.map((l) => clean(l).replace(/^\s*[-–]\s+/, '').trim()).filter(Boolean)
  // Teams' Word export: «timing / Name / text»: a lone name line above the text
  if (nameLines && rows.length >= 2 && NAME_ONLY.test(rows[0]!) && nameOk(rows[0]!) && !speakerOf(rows[0]!)) {
    return [{ start_ms: start, end_ms: end, speaker: rows[0]!, text: rows.slice(1).join(' ') }]
  }
  let cur: Segment | null = null
  for (const row of rows) {
    const sp = speakerOf(row)
    if (sp || !cur) {
      cur = { start_ms: start, end_ms: end, speaker: sp?.speaker ?? null, text: sp?.text ?? row }
      out.push(cur)
    } else {
      cur.text += ` ${row}`
    }
  }
  return out
}

/** Cues from lines, by their timing lines. A blank line ends a cue's text; what follows until the next timing line (a header,
 *  an identifier, a NOTE, STYLE or REGION block) is not text. A bare number right above a timing line is an SRT index. */
export function parseCues(all: string[], nameLines = false): Segment[] {
  const out: Segment[] = []
  let cue: { start: number; end: number | null; lines: string[] } | null = null
  let open = false
  const flush = () => { if (cue) out.push(...cueSegments(cue.start, cue.end, cue.lines, nameLines)) }
  for (let i = 0; i < all.length; i++) {
    const line = all[i]!
    if (!line.trim()) { open = false; continue }
    const m = CUE.exec(line)
    if (m) {
      const start = toMs(m[1]!)
      const end = toMs(m[2]!)
      flush()
      cue = start === null ? null : { start, end, lines: [] }
      open = cue !== null
      continue
    }
    if (!open || !cue) continue
    if (/^\d{1,6}$/.test(line.trim()) && i + 1 < all.length && CUE.test(all[i + 1]!)) continue
    cue.lines.push(line)
  }
  flush()
  return out
}

const hasCues = (all: string[]) => all.some((l) => CUE.test(l))

// ---------------------------------------------------------------------------
// plain lines: .txt and the paragraphs of a .docx

/** «Name: text», «[00:01:23] Name: text», «Name  0:03» headers; a line without a name continues the line above it. */
export function parseLines(all: string[]): { segments: Segment[]; timed: boolean } {
  const out: Segment[] = []
  let cur: Segment | null = null
  let header: { speaker: string; start: number } | null = null
  let last = 0
  let timed = false
  for (const rawLine of all) {
    const line = rawLine.replace(/\t/g, '  ').trim()
    if (!line) { cur = null; continue }
    let m = TIMED_SPEAKER.exec(line)
    if (m && nameOk(m[2]!) && toMs(m[1]!) !== null) {
      last = toMs(m[1]!)!; timed = true; header = null
      cur = { start_ms: last, end_ms: null, speaker: m[2]!.trim(), text: m[3]! }
      out.push(cur)
      continue
    }
    m = HEADER.exec(line)
    const who = m ? (m[1] ?? m[2])! : ''
    if (m && nameOk(who) && toMs(m[3]!) !== null) {
      last = toMs(m[3]!)!; timed = true
      header = { speaker: who.trim(), start: last }
      cur = null
      continue
    }
    const sp = speakerOf(line)
    if (sp) {
      header = null
      cur = { start_ms: last, end_ms: null, speaker: sp.speaker, text: sp.text }
      out.push(cur)
      continue
    }
    m = TIMED_TEXT.exec(line)
    if (m && toMs(m[1]!) !== null) {
      last = toMs(m[1]!)!; timed = true
      cur = { start_ms: last, end_ms: null, speaker: header?.speaker ?? null, text: m[2]! }
      out.push(cur)
      continue
    }
    if (cur) { cur.text += ` ${line}`; continue }
    cur = { start_ms: header?.start ?? last, end_ms: null, speaker: header?.speaker ?? null, text: line }
    out.push(cur)
  }
  return { segments: out, timed }
}

// ---------------------------------------------------------------------------
// .docx

/** The paragraphs of a Word document's body, as lines (a line break inside a paragraph starts a new line). */
export function docxXmlLines(xml: string): string[] {
  const out: string[] = []
  const paragraphs = xml.match(/<w:p(?:\s[^>]*)?>[\s\S]*?<\/w:p>|<w:p(?:\s[^>]*)?\/>/g) ?? []
  for (const p of paragraphs) {
    let text = ''
    const tokens = p.matchAll(/<w:t(?:\s[^>]*)?>([\s\S]*?)<\/w:t>|<w:tab\/>|<w:br(?:\s[^>]*)?\/>|<w:cr\/>/g)
    for (const t of tokens) {
      if (t[1] !== undefined) text += decodeEntities(t[1])
      else if (t[0].startsWith('<w:tab')) text += '\t'
      else text += '\n'
    }
    out.push(...text.split('\n'))
  }
  return out
}

export async function docxLines(bytes: Uint8Array): Promise<string[] | ParseFailure> {
  try {
    const xml = await unzipFile(bytes, 'word/document.xml', MAX_DOCUMENT_XML)
    return docxXmlLines(new TextDecoder('utf-8').decode(xml))
  } catch (e) {
    return e instanceof ZipError && e.code === 'too_large' ? 'too_large' : 'docx_invalid'
  }
}

// ---------------------------------------------------------------------------

/** Read one uploaded transcript. */
export async function parseTranscript(bytes: Uint8Array, format: TranscriptFormat): Promise<ParseResult> {
  if (bytes.length === 0) return { ok: false, reason: 'empty' }
  if (bytes.length > MAX_BYTES) return { ok: false, reason: 'too_large' }
  if (format === 'docx') {
    const got = await docxLines(bytes)
    if (typeof got === 'string') return { ok: false, reason: got }
    if (!got.some((l) => l.trim())) return { ok: false, reason: 'empty' }
    if (hasCues(got)) return finish(parseCues(got, true), true)
    const r = parseLines(got)
    return finish(r.segments, r.timed)
  }
  const text = decodeText(bytes)
  if (text === null) return { ok: false, reason: 'not_text' }
  if (!text.trim()) return { ok: false, reason: 'empty' }
  const all = lines(text)
  if (format === 'vtt' || format === 'srt') return finish(parseCues(all, false), true)
  if (hasCues(all)) return finish(parseCues(all, true), true)
  const r = parseLines(all)
  return finish(r.segments, r.timed)
}
