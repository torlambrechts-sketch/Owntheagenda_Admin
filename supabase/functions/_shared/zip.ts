/**
 * A small ZIP reader and writer in Web APIs only (DecompressionStream / CompressionStream «deflate-raw», no dependency), so
 * the edge functions (Deno) and the tests (Node) run the same code. It reads what a .docx is (stored or deflated entries,
 * no ZIP64, no encryption) and writes the privacy package (deflated JSON files, UTF-8 names).
 *
 * Every limit is checked before the bytes are trusted: the central directory must lie inside the file, an entry's declared
 * size must be under the caller's limit, and inflating stops as soon as it passes that limit (a «zip bomb» fails, it does
 * not fill the memory). The CRC is checked. A malformed archive throws ZipError with a code, never with its content.
 */
export class ZipError extends Error {
  constructor(public code: 'invalid' | 'unsupported' | 'too_large' | 'missing') {
    super(`zip: ${code}`)
  }
}

const CRC_TABLE = (() => {
  const t = new Uint32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    t[n] = c >>> 0
  }
  return t
})()

export function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]!) & 0xff]! ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

/** Run bytes through a (de)compression stream, stopping once the output passes `max` bytes. */
async function transform(data: Uint8Array, stream: TransformStream<Uint8Array, Uint8Array>, max: number): Promise<Uint8Array> {
  const source = new ReadableStream<Uint8Array>({ start(c) { c.enqueue(data); c.close() } })
  const reader = source.pipeThrough(stream).getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      total += value.length
      if (total > max) {
        await reader.cancel().catch(() => {})
        throw new ZipError('too_large')
      }
      chunks.push(value)
    }
  } catch (e) {
    if (e instanceof ZipError) throw e
    throw new ZipError('invalid')
  }
  const out = new Uint8Array(total)
  let at = 0
  for (const c of chunks) { out.set(c, at); at += c.length }
  return out
}

const inflate = (data: Uint8Array, max: number) =>
  transform(data, new DecompressionStream('deflate-raw') as unknown as TransformStream<Uint8Array, Uint8Array>, max)
const deflate = (data: Uint8Array) =>
  transform(data, new CompressionStream('deflate-raw') as unknown as TransformStream<Uint8Array, Uint8Array>, data.length + 1024 + data.length / 8)

type Entry = { name: string; method: number; flags: number; crc: number; csize: number; usize: number; offset: number }

function entries(zip: Uint8Array): Entry[] {
  const v = new DataView(zip.buffer, zip.byteOffset, zip.byteLength)
  // the end of central directory record: within the last 64 KiB + 22 bytes
  let eocd = -1
  for (let i = zip.length - 22; i >= Math.max(0, zip.length - 22 - 65535); i--) {
    if (v.getUint32(i, true) === 0x06054b50) { eocd = i; break }
  }
  if (eocd < 0) throw new ZipError('invalid')
  const count = v.getUint16(eocd + 10, true)
  const size = v.getUint32(eocd + 12, true)
  const start = v.getUint32(eocd + 16, true)
  if (count === 0xffff || size === 0xffffffff || start === 0xffffffff) throw new ZipError('unsupported')
  if (start + size > eocd) throw new ZipError('invalid')
  const names = new TextDecoder('utf-8')
  const out: Entry[] = []
  let p = start
  for (let n = 0; n < count; n++) {
    if (p + 46 > eocd || v.getUint32(p, true) !== 0x02014b50) throw new ZipError('invalid')
    const nameLen = v.getUint16(p + 28, true)
    const extraLen = v.getUint16(p + 30, true)
    const commentLen = v.getUint16(p + 32, true)
    if (p + 46 + nameLen > eocd) throw new ZipError('invalid')
    const e: Entry = {
      flags: v.getUint16(p + 8, true), method: v.getUint16(p + 10, true), crc: v.getUint32(p + 16, true),
      csize: v.getUint32(p + 20, true), usize: v.getUint32(p + 24, true), offset: v.getUint32(p + 42, true),
      name: names.decode(zip.subarray(p + 46, p + 46 + nameLen)),
    }
    if (e.csize === 0xffffffff || e.usize === 0xffffffff || e.offset === 0xffffffff) throw new ZipError('unsupported')
    out.push(e)
    p += 46 + nameLen + extraLen + commentLen
  }
  return out
}

/** The names in an archive (for tests and checks). */
export function zipNames(zip: Uint8Array): string[] {
  return entries(zip).map((e) => e.name)
}

/** One file out of an archive, at most `max` bytes uncompressed. Throws ZipError('missing') when it is not there. */
export async function unzipFile(zip: Uint8Array, name: string, max: number): Promise<Uint8Array> {
  const e = entries(zip).find((x) => x.name === name)
  if (!e) throw new ZipError('missing')
  if (e.flags & 0x1) throw new ZipError('unsupported')
  if (e.usize > max) throw new ZipError('too_large')
  const v = new DataView(zip.buffer, zip.byteOffset, zip.byteLength)
  if (e.offset + 30 > zip.length || v.getUint32(e.offset, true) !== 0x04034b50) throw new ZipError('invalid')
  const at = e.offset + 30 + v.getUint16(e.offset + 26, true) + v.getUint16(e.offset + 28, true)
  if (at + e.csize > zip.length) throw new ZipError('invalid')
  const raw = zip.subarray(at, at + e.csize)
  let data: Uint8Array
  if (e.method === 0) data = raw.slice()
  else if (e.method === 8) data = await inflate(raw, max)
  else throw new ZipError('unsupported')
  if (data.length !== e.usize || crc32(data) !== e.crc) throw new ZipError('invalid')
  return data
}

/** DOS date and time, as a ZIP stores them (local time is what readers show; UTC is the honest choice here). */
function dosTime(d: Date): { time: number; date: number } {
  const year = Math.max(1980, d.getUTCFullYear())
  return {
    time: (d.getUTCHours() << 11) | (d.getUTCMinutes() << 5) | Math.floor(d.getUTCSeconds() / 2),
    date: ((year - 1980) << 9) | ((d.getUTCMonth() + 1) << 5) | d.getUTCDate(),
  }
}

/** An archive of these files, each deflated when that makes it smaller. Names are UTF-8 (flag bit 11). */
export async function zip(files: { name: string; data: Uint8Array }[], when = new Date()): Promise<Uint8Array> {
  const enc = new TextEncoder()
  const { time, date } = dosTime(when)
  const locals: Uint8Array[] = []
  const centrals: Uint8Array[] = []
  let offset = 0
  for (const f of files) {
    const name = enc.encode(f.name)
    const packed = await deflate(f.data)
    const method = packed.length < f.data.length ? 8 : 0
    const body = method === 8 ? packed : f.data
    const crc = crc32(f.data)
    const local = new Uint8Array(30 + name.length)
    const l = new DataView(local.buffer)
    l.setUint32(0, 0x04034b50, true); l.setUint16(4, 20, true); l.setUint16(6, 0x0800, true); l.setUint16(8, method, true)
    l.setUint16(10, time, true); l.setUint16(12, date, true); l.setUint32(14, crc, true)
    l.setUint32(18, body.length, true); l.setUint32(22, f.data.length, true); l.setUint16(26, name.length, true); l.setUint16(28, 0, true)
    local.set(name, 30)
    const central = new Uint8Array(46 + name.length)
    const c = new DataView(central.buffer)
    c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true); c.setUint16(10, method, true)
    c.setUint16(12, time, true); c.setUint16(14, date, true); c.setUint32(16, crc, true)
    c.setUint32(20, body.length, true); c.setUint32(24, f.data.length, true); c.setUint16(28, name.length, true)
    c.setUint32(42, offset, true)
    central.set(name, 46)
    locals.push(local, body)
    centrals.push(central)
    offset += local.length + body.length
  }
  const cdSize = centrals.reduce((a, b) => a + b.length, 0)
  const end = new Uint8Array(22)
  const e = new DataView(end.buffer)
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true)
  e.setUint32(12, cdSize, true); e.setUint32(16, offset, true)
  const parts = [...locals, ...centrals, end]
  const out = new Uint8Array(parts.reduce((a, b) => a + b.length, 0))
  let at = 0
  for (const p of parts) { out.set(p, at); at += p.length }
  return out
}
