/**
 * The access package (SF-15; R-SECURITY-03): what worker_privacy_package (0043) returns — every row about the person, one
 * section per module — written as a ZIP of JSON files, one per section, plus about.json (the job, when it was made, and how
 * many rows each section holds). The object's name is the path worker_privacy_done stores verbatim, privacy/<job>/<file>
 * (0043's check; the privacy-exports bucket takes application/zip up to 50 MB, 0052). Web APIs only, as the tests run it too.
 */
import { zip } from './zip.ts'

export const PACKAGE_FILE = 'access-package.zip'
export const PACKAGE_MAX_BYTES = 52_428_800

export class PackageError extends Error {
  constructor(public code: 'package_too_large' | 'package_invalid') {
    super(`package: ${code}`)
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** The package's path in the privacy-exports bucket. */
export function packagePath(job: string): string {
  if (!UUID.test(job)) throw new PackageError('package_invalid')
  return `privacy/${job}/${PACKAGE_FILE}`
}

/** The ZIP for one export job. `data` is worker_privacy_package's answer: {section: rows[]}. */
export async function buildPackage(job: string, data: unknown, now = new Date()): Promise<Uint8Array> {
  if (!UUID.test(job) || !data || typeof data !== 'object' || Array.isArray(data)) throw new PackageError('package_invalid')
  const enc = new TextEncoder()
  const sections: Record<string, number> = {}
  const files: { name: string; data: Uint8Array }[] = []
  let total = 0
  for (const [key, rows] of Object.entries(data as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b))) {
    if (!/^[a-z_]{1,40}$/.test(key)) throw new PackageError('package_invalid')
    const list = Array.isArray(rows) ? rows : rows === null ? [] : [rows]
    sections[key] = list.length
    const body = enc.encode(`${JSON.stringify(list, null, 2)}\n`)
    total += body.length
    if (total > PACKAGE_MAX_BYTES * 4) throw new PackageError('package_too_large')
    files.push({ name: `${key}.json`, data: body })
  }
  const about = { job, generated_at: now.toISOString(), format: 'json', sections }
  files.unshift({ name: 'about.json', data: enc.encode(`${JSON.stringify(about, null, 2)}\n`) })
  const out = await zip(files, now)
  if (out.length > PACKAGE_MAX_BYTES) throw new PackageError('package_too_large')
  return out
}
