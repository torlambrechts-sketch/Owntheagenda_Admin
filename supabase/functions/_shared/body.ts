/**
 * A request body read with a byte cap, for public endpoints. A declared Content-Length over the cap is refused before
 * anything is read; a body without one (chunked) is read through its stream with a running count, and the stream is
 * cancelled as soon as the count passes the cap, so a sender cannot make the function buffer more than `limit` bytes.
 * Web Streams only, so the edge functions (Deno) and the tests (Node) run the same code.
 */
export async function readCapped(req: Request, limit: number): Promise<{ ok: true; text: string } | { ok: false; reason: 'too_large' }> {
  const declared = req.headers.get('content-length')
  if (declared !== null && (!/^\d{1,15}$/.test(declared) || Number(declared) > limit)) return { ok: false, reason: 'too_large' }
  if (!req.body) return { ok: true, text: '' }
  const reader = req.body.getReader()
  const chunks: Uint8Array[] = []
  let n = 0
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    n += value.byteLength
    if (n > limit) {
      await reader.cancel().catch(() => undefined)
      return { ok: false, reason: 'too_large' }
    }
    chunks.push(value)
  }
  const all = new Uint8Array(n)
  let at = 0
  for (const c of chunks) {
    all.set(c, at)
    at += c.byteLength
  }
  return { ok: true, text: new TextDecoder().decode(all) }
}
