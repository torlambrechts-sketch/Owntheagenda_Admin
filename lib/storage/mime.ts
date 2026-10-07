/**
 * What each upload accepts, as the database decides it (file_upload_begin 0044, meeting_transcript_upload_begin 0042) and
 * the buckets enforce it (0052). The type sent is the one the file name's extension names: a browser leaves File.type empty
 * for .srt or .vtt, and the RPCs require the extension and the type to agree. Shared by the screens and the server actions.
 */
export const RECORD_TYPES: Record<string, string> = {
  pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', csv: 'text/csv', txt: 'text/plain',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  webp: 'image/webp', heic: 'image/heic', webm: 'audio/webm', m4a: 'audio/mp4', mp3: 'audio/mpeg',
}
export const TRANSCRIPT_TYPES: Record<string, string> = {
  vtt: 'text/vtt', srt: 'application/x-subrip', txt: 'text/plain',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
}
export const RECORD_MAX_BYTES = 26_214_400
export const TRANSCRIPT_MAX_BYTES = 5_242_880

/** The type for a file name, or null when the upload does not take it. */
export function typeFor(filename: string, table: Record<string, string>): string | null {
  const ext = /\.([A-Za-z0-9]{1,5})$/.exec(filename.trim())?.[1]?.toLowerCase()
  return ext ? table[ext] ?? null : null
}

/** The `accept` attribute for a file input: the extensions, and the types for pickers that filter by type. */
export function acceptFor(table: Record<string, string>, only?: (mime: string) => boolean): string {
  const rows = Object.entries(table).filter(([, m]) => !only || only(m))
  return [...rows.map(([e]) => `.${e}`), ...new Set(rows.map(([, m]) => m))].join(',')
}

/** Send a file to a signed upload URL (Storage's PUT; the bucket checks the type and the size again). */
export async function putSigned(url: string, file: Blob, mime: string): Promise<boolean> {
  try {
    const res = await fetch(url, { method: 'PUT', headers: { 'content-type': mime, 'x-upsert': 'false' }, body: file })
    return res.ok
  } catch {
    return false
  }
}
